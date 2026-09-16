"""
QROS Bot — main (Stage 3: wired + orchestration — Telegram dispatcher + Mission Queue + health + structured logging + graceful restart).

Pipeline: Telegram → QROS Bot → OpenAI Gateway → GitHub → AgentOS
           Telegram → Bot Dispatcher → Mission Queue → Arena/Kilo → GitHub Task sync → AgentOS
Reverse: GitHub → Watcher → Gateway → Bot → Telegram

Stage 3 adds:
- Telegram command dispatcher (MissionQueue)
- Mission lifecycle CREATED→QUEUED→ASSIGNED→RUNNING→REVIEW→DONE→ARCHIVED + retry/timeout/cancel
- Arena/Kilo worker registration + history
- GitHub task sync (offline fallback)

Stage 2 wiring retained (long polling, gateway forwarding, health, JSON logs, graceful).

No trading/AgentOS redesign, no Twin changes.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
import uvicorn

from src.config import BotSettings

# ── Structured JSON logging ────────────────────────────────────────────────
# BUG-006 fix: logger must exist BEFORE any orchestrator exception handling.
# Bot must gracefully continue when Orchestrator is absent (FileNotFoundError for
# /Orchestrator/src/mission.py when running as /app/src/main.py inside container).
# Never call log.warning() before logger initialization.
class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "service": "qros-bot",
            "logger": record.name,
            "message": record.getMessage(),
        }
        if hasattr(record, "extra"):
            payload.update(record.extra)
        for k in ("telegram_user_id", "command", "gateway_status", "event", "delivery", "mission_id", "worker_id"):
            if hasattr(record, k):
                payload[k] = getattr(record, k)
        return json.dumps(payload, ensure_ascii=False)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JSONFormatter())
root = logging.getLogger()
root.handlers = [handler]
root.setLevel(logging.INFO)
log = logging.getLogger("qros.bot")

# ── Orchestrator imports (Stage 3) — avoid stdlib queue shadowing ──
# BUG-006: wrapped to gracefully disable orchestrator if mission.py cannot be loaded.
# Uses importlib to avoid sys.modules['queue'] shadowing stdlib queue (MANTIS-BUG-002).
# If any import fails (FileNotFoundError, ImportError for MissionStatus), set ORCH_AVAILABLE=False
# and continue startup without crash — health endpoint remains available.
_orch_path = None
WorkerExecutor = None  # type: ignore
try:
    import pathlib as _pl
    import importlib.util as _ilu
    _orch_path = _pl.Path(__file__).resolve().parents[2] / "Orchestrator" / "src"
    # Also try alternative container path /app/src/main.py -> parents[1]=/app, so check fallback
    if not _orch_path.is_dir():
        # Inside Docker, /app/src/main.py parents[2] is /, so try parents[1]/Orchestrator and repo root fallback
        _alt = _pl.Path(__file__).resolve().parents[1] / "Orchestrator" / "src"
        if _alt.is_dir():
            _orch_path = _alt
        else:
            # Try repo root: parents[3] when running from host ControlCenter/Bot/src/main.py -> project root
            _repo_try = _pl.Path(__file__).resolve().parents[3] / "ControlCenter" / "Orchestrator" / "src"
            if _repo_try.is_dir():
                _orch_path = _repo_try
    def _load_orch_module(name: str):
        spec = _ilu.spec_from_file_location(name, _orch_path / f"{name}.py")
        if spec is None or spec.loader is None:
            raise FileNotFoundError(f"{_orch_path / f'{name}.py'} not found (spec is None)")
        mod = _ilu.module_from_spec(spec)
        sys.modules[name] = mod  # register to allow intra-orch imports (mission <- worker_registry <- mission_queue <- dispatcher)
        spec.loader.exec_module(mod)
        return mod
    _mission_mod = _load_orch_module("mission")
    MissionStatus = _mission_mod.MissionStatus
    _wr_mod = _load_orch_module("worker_registry")
    WorkerRegistry = _wr_mod.WorkerRegistry
    _mq_mod = _load_orch_module("mission_queue")
    MissionQueue = _mq_mod.MissionQueue
    _gs_mod = _load_orch_module("github_sync")
    GitHubSync = _gs_mod.GitHubSync
    _disp_mod = _load_orch_module("dispatcher")
    TelegramCommandDispatcher = _disp_mod.TelegramCommandDispatcher
    # Worker Execution Engine (Stage 4) — optional, graceful if missing
    try:
        _wexec_mod = _load_orch_module("worker_executor")
        WorkerExecutor = _wexec_mod.WorkerExecutor  # type: ignore
        log.info("WorkerExecutor loaded")
    except Exception as we:
        WorkerExecutor = None  # type: ignore
        log.warning(f"WorkerExecutor not available: {we}")
    ORCH_AVAILABLE = True
except Exception as e:
    # Fallback: try legacy sys.path + mission_queue (non-shadowing) then queue
    try:
        if _orch_path is not None and str(_orch_path) not in sys.path:
            sys.path.insert(0, str(_orch_path))
        from mission import MissionStatus as _MS  # type: ignore
        MissionStatus = _MS
        try:
            from mission_queue import MissionQueue as _MQ  # type: ignore
        except ImportError:
            from queue import MissionQueue as _MQ  # type: ignore
        MissionQueue = _MQ
        from worker_registry import WorkerRegistry as _WR  # type: ignore
        WorkerRegistry = _WR
        from dispatcher import TelegramCommandDispatcher as _TD  # type: ignore
        TelegramCommandDispatcher = _TD
        from github_sync import GitHubSync as _GS  # type: ignore
        GitHubSync = _GS
        try:
            from worker_executor import WorkerExecutor as _WE  # type: ignore
            WorkerExecutor = _WE
        except Exception:
            WorkerExecutor = None  # type: ignore
        ORCH_AVAILABLE = True
    except Exception as e2:
        ORCH_AVAILABLE = False
        MissionStatus = None  # type: ignore
        WorkerExecutor = None  # type: ignore
        # log is now defined (BUG-006), so warning is safe
        log.warning(f"Orchestrator not available (graceful disable): {e} / {e2}")

settings = BotSettings()

# ── Orchestrator instances (Stage 3) ───────────────────────────────────────
if ORCH_AVAILABLE:
    _workers = WorkerRegistry()
    _workers.ensure_defaults()
    _queue = MissionQueue(workers=_workers)
    _github_sync = GitHubSync()
    dispatcher = TelegramCommandDispatcher(queue=_queue, workers=_workers, github_sync=_github_sync)
    log.info(f"Orchestrator wired — workers: {[w.worker_id for w in _workers.list_active()]} missions: {len(_queue.missions)}")
else:
    dispatcher = None
    _workers = None
    _queue = None
    _github_sync = None
    log.warning("Orchestrator not available — dispatcher disabled (health-only)")

# ── Worker Execution Engine (Stage 4) globals ───────────────────────────
_worker_executors: list = []
_worker_tasks: list[asyncio.Task] = []

# ── Gateway forwarding (Stage 2) ───────────────────────────────────────────
async def forward_to_gateway(telegram_user_id: int, text: str, context: dict | None = None) -> dict:
    url = f"{settings.gateway_internal_url.rstrip('/')}/v1/chat"
    payload = {"telegram_user_id": telegram_user_id, "text": text, "context": context or {}}
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.post(url, json=payload)
            r.raise_for_status()
            data = r.json()
            log.info("Gateway forward OK", extra={"extra": {"telegram_user_id": telegram_user_id, "command": text[:40], "gateway_status": r.status_code}})
            return data
    except Exception as e:
        log.error(f"Gateway forward failed: {e}", extra={"extra": {"telegram_user_id": telegram_user_id}})
        return {"reply": f"⚠️ Gateway unavailable ({e}). Try /status again in 30s.", "stage": "error"}

# ── Telegram polling ───────────────────────────────────────────────────────
telegram_app = None
telegram_task: asyncio.Task | None = None
telegram_connected = False

try:
    from telegram import Update
    from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters
    TELEGRAM_AVAILABLE = True
except Exception as e:
    TELEGRAM_AVAILABLE = False
    log.warning(f"python-telegram-bot not available: {e} — health-only mode")

async def check_allowlist(user_id: int) -> bool:
    return user_id in settings.allowed_user_ids_list

# ── Handlers ───────────────────────────────────────────────────────────────
async def handle_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_allowlist(update.effective_user.id):
        log.warning("unauthorized /start", extra={"extra": {"telegram_user_id": update.effective_user.id}})
        await update.message.reply_text("⛔ Not authorized.")
        return
    await update.message.reply_text(
        "👋 QROS Control Center online.\n"
        "Pipeline: Telegram → Bot → Gateway → GitHub → AgentOS\n"
        "Mission: /mission help | /mission create <title> | /mission list | /queue\n"
        "Legacy: /help /status /tasks /reports /events /validate"
    )

async def handle_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_allowlist(update.effective_user.id):
        await update.message.reply_text("⛔ Not authorized.")
        return
    # Stage 3 help includes mission help — offload blocking dispatcher to threadpool (BUG-002 fix)
    if ORCH_AVAILABLE and dispatcher:
        help_text = await asyncio.to_thread(dispatcher.dispatch, "/mission help", update.effective_user.id)
        await update.message.reply_text(
            "QROS Control Center — remote project management (not trading, not AI)\n"
            "/start — greeting\n"
            "/help — this list\n"
            "/status — PROJECT_STATUS.md via Gateway+GitHub\n"
            "/tasks — TASK_QUEUE.md via Gateway\n"
            "/reports — REPORT_QUEUE.md\n"
            "/events — EVENT_BUS tail\n"
            "/validate — AgentOS validate\n"
            "--- Mission Queue (Stage 3) ---\n" + help_text
        )
    else:
        await update.message.reply_text(
            "QROS Control Center — remote project management (not trading, not AI)\n"
            "/start — greeting\n"
            "/help — this list\n"
            "/status — PROJECT_STATUS.md via Gateway+GitHub\n"
            "/tasks — TASK_QUEUE.md via Gateway\n"
            "/reports — REPORT_QUEUE.md\n"
            "/events — EVENT_BUS tail\n"
            "/validate — AgentOS validate\n"
            "Any text → Gateway → OpenAI → GitHub → AgentOS"
        )

async def handle_mission(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_allowlist(update.effective_user.id):
        await update.message.reply_text("⛔ Not authorized.")
        return
    if not ORCH_AVAILABLE or not dispatcher:
        await update.message.reply_text("⚠️ Mission Queue unavailable (orchestrator not loaded).")
        return
    text = update.message.text or ""
    # Full text includes command and args, e.g., "/mission create Foo"
    # BUG-002 fix: offload blocking file I/O (queue.py:65 write_text) to threadpool
    reply = await asyncio.to_thread(dispatcher.dispatch, text, update.effective_user.id)
    if not reply:
        reply = "Unknown mission command. Try /mission help"
    log.info(f"Mission dispatch {text[:60]} → {reply[:60]}", extra={"extra": {"telegram_user_id": update.effective_user.id, "command": text[:40]}})
    try:
        await asyncio.wait_for(update.message.reply_text(reply[:4096]), timeout=5)
    except asyncio.TimeoutError:
        log.error("Telegram reply_text timeout (mission)", extra={"extra": {"telegram_user_id": update.effective_user.id}})

async def handle_queue(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_allowlist(update.effective_user.id):
        await update.message.reply_text("⛔ Not authorized.")
        return
    if not ORCH_AVAILABLE or not dispatcher:
        await update.message.reply_text("⚠️ Queue unavailable")
        return
    reply = await asyncio.to_thread(dispatcher.dispatch, "/mission list QUEUED", update.effective_user.id)
    try:
        await asyncio.wait_for(update.message.reply_text(reply[:4096]), timeout=5)
    except asyncio.TimeoutError:
        log.error("Telegram reply_text timeout (queue)", extra={"extra": {"telegram_user_id": update.effective_user.id}})

async def _gateway_and_reply(update: Update, text: str):
    if not await check_allowlist(update.effective_user.id):
        await update.message.reply_text("⛔ Not authorized.")
        return
    # Intercept mission commands before Gateway — offload blocking dispatcher (BUG-002)
    if text.strip().lower().startswith("/mission") or text.strip().lower().startswith("/queue"):
        if ORCH_AVAILABLE and dispatcher:
            reply = await asyncio.to_thread(dispatcher.dispatch, text, update.effective_user.id)
            if reply:
                try:
                    await asyncio.wait_for(update.message.reply_text(reply[:4096]), timeout=5)
                except asyncio.TimeoutError:
                    log.error("Telegram reply_text timeout (_gateway_and_reply)", extra={"extra": {"telegram_user_id": update.effective_user.id}})
                return
    ctx = {"chat_id": update.effective_chat.id, "username": update.effective_user.username}
    data = await forward_to_gateway(update.effective_user.id, text, ctx)
    reply = data.get("reply") or data.get("message") or "[no reply]"
    for i in range(0, len(reply), 4096):
        await update.message.reply_text(reply[i:i+4096])

async def handle_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await _gateway_and_reply(update, "/status" if not context.args else "/status " + " ".join(context.args))

async def handle_tasks(update: Update, context: ContextTypes.DEFAULT_TYPE):
    txt = "/tasks" + (" " + " ".join(context.args) if context.args else "")
    await _gateway_and_reply(update, txt)

async def handle_reports(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await _gateway_and_reply(update, "/reports")

async def handle_events(update: Update, context: ContextTypes.DEFAULT_TYPE):
    txt = "/events" + (" " + " ".join(context.args) if context.args else "")
    await _gateway_and_reply(update, txt)

async def handle_validate(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await _gateway_and_reply(update, "/validate")

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not update.message or not update.message.text:
        return
    if update.message.text.startswith("/"):
        # Check if it's a mission command that wasn't caught by specific handler
        if update.message.text.lower().startswith("/mission") or update.message.text.lower().startswith("/queue"):
            await handle_mission(update, context)
            return
        return
    await _gateway_and_reply(update, update.message.text)

async def start_telegram_polling():
    global telegram_app, telegram_connected
    if not TELEGRAM_AVAILABLE:
        log.info("Telegram polling disabled — library unavailable")
        return
    if not settings.telegram_bot_token or settings.telegram_bot_token.startswith("123456:"):
        log.warning("Telegram polling disabled — TELEGRAM_BOT_TOKEN placeholder or missing")
        return
    if not settings.allowed_user_ids_list:
        log.warning("Telegram polling disabled — TELEGRAM_ALLOWED_USER_IDS empty")
        return

    # BUG-009 fix: Telegram polling never becomes active — root cause was
    #   Bot.initialize() → Bot.get_me() raising TimedOut/NetworkError (transient)
    #   which is NOT retried (unlike Updater._bootstrap which retries indefinitely).
    #   Default HTTPXRequest read_timeout=5 < Updater timeout=10 causes premature
    #   httpx.ReadTimeout → TimedOut before Telegram long-poll expires. Also
    #   Application.initialize() only catches InvalidToken, so any TimedOut aborts
    #   the entire start_telegram_polling() and sets telegram_connected=False with
    #   no retry — the background task ends and never recovers.
    # Fixes:
    #   1) Make Bot.initialize resilient to transient get_me failures (retry + allow continue)
    #   2) Build Application with correct get_updates timeouts (read_timeout 30 = timeout 10 + margin)
    #   3) Wrap initialize/start/start_polling in retry loop with backoff, never give up on TimedOut/NetworkError
    #   4) Increase start_polling read/write/connect/pool timeouts to 30s and keep bootstrap_retries=-1

    # Patch Bot.initialize to be resilient to transient network errors (BUG-009)
    try:
        from telegram._bot import Bot as _PatchedBot
        from telegram.error import InvalidToken as _InvToken, TimedOut as _Tmo, NetworkError as _Nerr

        if not getattr(_PatchedBot.initialize, "_qros_patched", False):
            _orig_init = _PatchedBot.initialize

            async def _resilient_bot_initialize(self):  # type: ignore
                if getattr(self, "_initialized", False):
                    self._LOGGER.debug("This Bot is already initialized.")
                    return
                await asyncio.gather(self._request[0].initialize(), self._request[1].initialize())
                # Retry get_me a few times; on persistent transient failure continue anyway
                # so that polling can still start (bot cache not required for get_updates).
                last_exc = None
                for attempt in range(5):
                    try:
                        await self.get_me()
                        last_exc = None
                        break
                    except _InvToken as exc:
                        raise InvalidToken(f"The token `{self._token}` was rejected by the server.") from exc
                    except (_Tmo, _Nerr) as exc:
                        last_exc = exc
                        # TimedOut/NetworkError are transient — log and retry quickly
                        self._LOGGER.warning(f"Bot.initialize get_me transient failure attempt {attempt+1}/5: {exc}")
                        if attempt < 4:
                            await asyncio.sleep(0.5 * (2**attempt))
                            continue
                    except Exception as exc:
                        # ConnectError etc. -> mapped to NetworkError already, but be safe
                        last_exc = exc
                        self._LOGGER.warning(f"Bot.initialize get_me failed attempt {attempt+1}/5: {exc}")
                        if attempt < 4:
                            await asyncio.sleep(0.5 * (2**attempt))
                            continue
                if last_exc is not None:
                    # Don't fail initialization — polling can run without cached bot username.
                    # Updater.start_polling will still call get_updates.
                    self._LOGGER.warning(f"Bot.initialize continuing without cached bot after get_me failures: {last_exc}")
                self._initialized = True  # type: ignore

            _resilient_bot_initialize._qros_patched = True  # type: ignore
            _PatchedBot.initialize = _resilient_bot_initialize  # type: ignore
            log.info("Patched Bot.initialize for BUG-009 resilience (transient get_me)")
    except Exception as pe:
        log.warning(f"Bot.initialize patch not applied: {pe}")

    delay = 2.0
    max_delay = 60.0
    attempt = 0
    while True:
        try:
            # Build with extended timeouts to avoid read_timeout 5 < timeout 10 mismatch
            builder = Application.builder().token(settings.telegram_bot_token)
            # PTB 20.7+ separates get_updates timeouts — set both pools
            try:
                builder = builder.get_updates_read_timeout(30).get_updates_write_timeout(30).get_updates_connect_timeout(30).get_updates_pool_timeout(30)
                builder = builder.connect_timeout(30).read_timeout(30).write_timeout(30).pool_timeout(30)
            except Exception as be:
                log.warning(f"Builder timeout config not applied: {be}")
            telegram_app = builder.build()
            telegram_app.add_handler(CommandHandler("start", handle_start))
            telegram_app.add_handler(CommandHandler("help", handle_help))
            telegram_app.add_handler(CommandHandler("mission", handle_mission))
            telegram_app.add_handler(CommandHandler("queue", handle_queue))
            telegram_app.add_handler(CommandHandler("status", handle_status))
            telegram_app.add_handler(CommandHandler("tasks", handle_tasks))
            telegram_app.add_handler(CommandHandler("reports", handle_reports))
            telegram_app.add_handler(CommandHandler("events", handle_events))
            telegram_app.add_handler(CommandHandler("validate", handle_validate))
            telegram_app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
            log.info(f"Telegram polling starting — allowed_users={settings.allowed_user_ids_list} orch={ORCH_AVAILABLE} attempt={attempt+1}")
            await telegram_app.initialize()
            await telegram_app.start()
            try:
                # get_me with explicit timeout longer than HTTPXRequest default
                me = await asyncio.wait_for(telegram_app.bot.get_me(), timeout=15)
                telegram_connected = True
                log.info(f"Telegram connected as @{me.username} id={me.id}", extra={"extra": {"telegram_user_id": me.id}})
            except asyncio.TimeoutError as e:
                log.warning(f"Telegram getMe timeout (will still poll): {e}")
                telegram_connected = True
            except Exception as e:
                # Second get_me is non-critical — keep polling even if it fails
                try:
                    from telegram.error import InvalidToken as _IT2
                    if isinstance(e, _IT2):
                        raise
                except Exception:
                    pass
                log.warning(f"Telegram getMe failed (will still poll): {e}")
                telegram_connected = True
            # start_polling is non-blocking; it creates Updater.__polling_task and returns when ready
            # bootstrap_retries=-1 retries delete_webhook indefinitely; timeout=10 matches PG, read_timeout=30 avoids premature client timeout
            await telegram_app.updater.start_polling(
                drop_pending_updates=True,
                allowed_updates=Update.ALL_TYPES,
                bootstrap_retries=-1,
                timeout=10,
                read_timeout=30,
                write_timeout=30,
                connect_timeout=30,
                pool_timeout=30,
            )
            log.info("Telegram long polling ONLINE (Stage 3: dispatcher + mission queue)")
            telegram_connected = True
            break  # success — exit retry loop; polling continues in Updater.__polling_task
        except asyncio.CancelledError:
            log.info("Telegram polling startup cancelled")
            telegram_connected = False
            raise
        except Exception as e:
            # InvalidToken must not be retried — fail fast
            try:
                from telegram.error import InvalidToken as _IT
                if isinstance(e, _IT):
                    log.error(f"Telegram polling failed — invalid token: {e}")
                    telegram_connected = False
                    break
            except Exception:
                if "InvalidToken" in type(e).__name__ or "unauthorized" in str(e).lower() or "invalid token" in str(e).lower():
                    log.error(f"Telegram polling failed — invalid token: {e}")
                    telegram_connected = False
                    break
            attempt += 1
            log.warning(f"Telegram polling start attempt {attempt} failed: {e} — retry in {delay:.1f}s")
            telegram_connected = False
            # Cleanup partially initialized app to avoid leaking httpx clients
            if telegram_app is not None:
                try:
                    # Only shutdown if it was at least partially initialized
                    bot_inited = getattr(getattr(telegram_app, "bot", None), "_initialized", False)
                    app_inited = getattr(telegram_app, "_initialized", False)
                    if bot_inited or app_inited:
                        try:
                            # Stop what we started (safe even if not fully started)
                            with open(os.devnull, "w"):
                                pass
                            # Try graceful shutdown; ignore errors
                            try:
                                await asyncio.wait_for(telegram_app.shutdown(), timeout=5)
                            except asyncio.TimeoutError:
                                pass
                            except Exception:
                                pass
                        except Exception:
                            pass
                except Exception:
                    pass
                telegram_app = None
            try:
                await asyncio.sleep(delay)
            except asyncio.CancelledError:
                log.info("Telegram retry sleep cancelled")
                raise
            delay = min(max_delay, delay * 1.5 + 0.5)
            # continue loop — never give up on transient errors (TimedOut/NetworkError)
            continue

async def stop_telegram_polling():
    global telegram_app, telegram_connected
    if telegram_app:
        try:
            log.info("Stopping Telegram polling (graceful)")
            await telegram_app.updater.stop()
            await telegram_app.stop()
            await telegram_app.shutdown()
            log.info("Telegram polling stopped")
        except Exception as e:
            log.warning(f"Telegram stop error: {e}")
        telegram_connected = False

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info(f"Bot startup — port {settings.port} gateway={settings.gateway_internal_url} orch={ORCH_AVAILABLE} worker_executor={WorkerExecutor is not None}")
    if TELEGRAM_AVAILABLE and settings.telegram_bot_token and not settings.telegram_bot_token.startswith("123456:"):
        task = asyncio.create_task(start_telegram_polling())
        app.state.telegram_task = task
    # Stage 4: Worker Execution Engine — start arena/kilo executors if available
    if ORCH_AVAILABLE and WorkerExecutor and _queue and _workers:
        try:
            # Pass shared queue/workers to avoid duplicate in-memory state
            arena_ex = WorkerExecutor("worker-arena", queue=_queue, workers=_workers)
            kilo_ex = WorkerExecutor("worker-kilo", queue=_queue, workers=_workers)
            _worker_executors.extend([arena_ex, kilo_ex])
            for ex in _worker_executors:
                t = asyncio.create_task(ex.run_forever())
                _worker_tasks.append(t)
            app.state.worker_tasks = _worker_tasks  # type: ignore
            log.info(f"Worker Execution Engine started — workers={[e.worker_id for e in _worker_executors]} poll={arena_ex.poll_interval}s")
        except Exception as e:
            log.warning(f"Worker Execution Engine failed to start: {e}")
    yield
    log.info("Bot shutdown — graceful")
    # Stop workers first
    if _worker_tasks:
        for t in _worker_tasks:
            t.cancel()
        try:
            await asyncio.gather(*_worker_tasks, return_exceptions=True)
        except Exception:
            pass
        log.info("Worker Execution Engine stopped")
    if hasattr(app.state, "telegram_task"):
        try:
            await stop_telegram_polling()
        except Exception:
            pass
        app.state.telegram_task.cancel()
        try:
            await app.state.telegram_task
        except asyncio.CancelledError:
            pass
    log.info("Bot shutdown complete")

app = FastAPI(
    title="QROS Bot (Stage 3)",
    version="1.0.0-stage3",
    description="Telegram dispatcher → Mission Queue → Gateway → GitHub → AgentOS",
    lifespan=lifespan,
)

@app.get("/health")
def health():
    return {"service": "qros-bot", "status": "ok", "stage": "2-wired", "version": "1.0.0-stage3", "telegram_connected": telegram_connected, "telegram_available": TELEGRAM_AVAILABLE, "orchestrator": ORCH_AVAILABLE}

@app.get("/ready")
async def ready():
    missing = settings.validate_stage1()
    gateway_ok = False
    try:
        async with httpx.AsyncClient(timeout=3) as c:
            r = await c.get(f"{settings.gateway_internal_url.rstrip('/')}/health")
            gateway_ok = r.status_code == 200
    except Exception:
        gateway_ok = False
    tg_ok = telegram_connected if not settings.telegram_bot_token.startswith("123456:") and settings.telegram_bot_token else False
    workers_ok = False
    queue_len = 0
    if ORCH_AVAILABLE and _workers and _queue:
        workers_ok = len(_workers.list_active()) >= 2
        queue_len = len(_queue.missions)
    return {
        "service": "qros-bot",
        "ready": len(missing) == 0 and gateway_ok,
        "missing_env": missing,
        "allowed_users_configured": len(settings.allowed_user_ids_list),
        "gateway": settings.gateway_internal_url,
        "gateway_reachable": gateway_ok,
        "telegram_connected": tg_ok,
        "telegram_available": TELEGRAM_AVAILABLE,
        "orchestrator": ORCH_AVAILABLE,
        "workers_registered": len(_workers.list_active()) if _workers else 0,
        "missions": queue_len,
        "environment": settings.environment,
    }

@app.get("/")
def root():
    return {
        "service": "qros-bot",
        "stage": "2-wired",
        "version": "1.0.0-stage3",
        "pipeline": "Telegram → QROS Bot → OpenAI Gateway → GitHub → AgentOS → Arena+Kilo",
        "health": "/health",
        "ready": "/ready",
        "internal": "POST /internal/notify",
        "mission": "POST /mission/create, GET /mission/list, /mission/lifecycle",
        "commands": ["/start", "/help", "/status", "/tasks", "/reports", "/events", "/validate", "/mission", "/queue"],
        "telegram_polling": "long polling + dispatcher" if TELEGRAM_AVAILABLE else "stub",
        "orchestrator": ORCH_AVAILABLE,
    }

class NotifyIn(BaseModel):
    text: str
    parse_mode: str | None = None

@app.post("/internal/notify")
async def internal_notify(body: NotifyIn, request: Request):
    if not telegram_app or not telegram_connected:
        log.warning("Notify dropped — Telegram not connected", extra={"extra": {"event": "notify_dropped"}})
        return {"delivered": False, "reason": "telegram not connected", "text_preview": body.text[:80]}
    delivered = 0
    for uid in settings.allowed_user_ids_list:
        try:
            await telegram_app.bot.send_message(chat_id=uid, text=body.text, parse_mode=body.parse_mode)
            delivered += 1
            log.info(f"Notify delivered to {uid}", extra={"extra": {"telegram_user_id": uid}})
        except Exception as e:
            log.error(f"Notify failed to {uid}: {e}", extra={"extra": {"telegram_user_id": uid}})
    return {"delivered": True, "recipients": delivered, "text_preview": body.text[:80]}

# ── Mission REST (Stage 3, for Gateway/Orchestrator health + evidence) ──────
@app.get("/mission/list")
def mission_list(status: str | None = None):
    if not ORCH_AVAILABLE or not _queue:
        raise HTTPException(status_code=503, detail="orchestrator not available")
    missions = _queue.list(status=status)
    return {"missions": [m.to_dict() for m in missions], "count": len(missions)}

@app.get("/mission/{mission_id}")
def mission_get(mission_id: str):
    if not ORCH_AVAILABLE or not _queue:
        raise HTTPException(status_code=503, detail="orchestrator not available")
    m = _queue.get(mission_id.upper())
    if not m:
        raise HTTPException(status_code=404, detail="mission not found")
    return m.to_dict()

class MissionCreateIn(BaseModel):
    title: str
    module: str = "MOD-ORCHESTRATOR"
    priority: str = "P1"
    telegram_user_id: int = 0
    payload: dict | None = None

@app.post("/mission/create")
def mission_create(body: MissionCreateIn):
    if not ORCH_AVAILABLE or not _queue:
        raise HTTPException(status_code=503, detail="orchestrator not available")
    m = _queue.create(title=body.title, module=body.module, priority=body.priority, created_by=str(body.telegram_user_id), payload=body.payload)
    _queue.queue(m.mission_id, by=str(body.telegram_user_id))
    # sync to GitHub
    try:
        tid = _github_sync.sync_create(m)
        m.github_task_id = tid
        _queue.save()
    except Exception:
        pass
    return m.to_dict()

@app.post("/mission/{mission_id}/transition")
def mission_transition(mission_id: str, to: str, by: str = "api"):
    if not ORCH_AVAILABLE or not _queue:
        raise HTTPException(status_code=503, detail="orchestrator not available")
    try:
        st = MissionStatus(to)
    except:
        raise HTTPException(status_code=400, detail=f"invalid status {to}")
    m = _queue.transition(mission_id.upper(), st, by=by)
    return m.to_dict()

def _handle_signal(signum, frame):
    log.info(f"Received signal {signum} — graceful shutdown")

signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)

def main() -> None:
    missing = settings.validate_stage1()
    if missing:
        log.warning(f"Bot config incomplete — missing: {', '.join(missing)} (health will show degraded)")
    else:
        log.info(f"Bot config OK — allowed_users={settings.allowed_user_ids_list} gateway={settings.gateway_internal_url}")
    log.info(f"Starting QROS Bot wired+orchestrated on port {settings.port} (Stage 3)")
    uvicorn.run(app, host="0.0.0.0", port=settings.port, log_level="info")

if __name__ == "__main__":
    main()
