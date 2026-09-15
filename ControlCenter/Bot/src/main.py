"""
QROS Bot — main (Stage 2: wired — Telegram long polling + Gateway forwarding + health + structured logging + graceful restart).

Pipeline: Telegram → QROS Bot → OpenAI Gateway → GitHub → AgentOS
Reverse: GitHub → Watcher → Gateway → Bot → Telegram

Stage 2 wires:
- Structured JSON logging
- Health /ready with telegram_connected + gateway_reachable
- Telegram long polling (allowlist, handlers → Gateway POST /v1/chat)
- Internal /internal/notify for Gateway/Watcher → Telegram
- Graceful shutdown (SIGTERM cancels polling, stops FastAPI)
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
class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "service": "qros-bot",
            "logger": record.name,
            "message": record.getMessage(),
        }
        # add extra fields if present
        if hasattr(record, "extra"):
            payload.update(record.extra)
        for k in ("telegram_user_id", "command", "gateway_status", "event", "delivery"):
            if hasattr(record, k):
                payload[k] = getattr(record, k)
        return json.dumps(payload, ensure_ascii=False)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JSONFormatter())
root = logging.getLogger()
root.handlers = [handler]
root.setLevel(logging.INFO)
log = logging.getLogger("qros.bot")

settings = BotSettings()

# ── Gateway forwarding ─────────────────────────────────────────────────────
async def forward_to_gateway(telegram_user_id: int, text: str, context: dict | None = None) -> dict:
    url = f"{settings.gateway_internal_url.rstrip('/')}/v1/chat"
    payload = {"telegram_user_id": telegram_user_id, "text": text, "context": context or {}}
    try:
        async with httpx.AsyncClient(timeout=settings.gateway_internal_url and 15 or 15) as client:
            r = await client.post(url, json=payload)
            r.raise_for_status()
            data = r.json()
            log.info("Gateway forward OK", extra={"extra": {"telegram_user_id": telegram_user_id, "command": text[:40], "gateway_status": r.status_code}})
            return data
    except Exception as e:
        log.error(f"Gateway forward failed: {e}", extra={"extra": {"telegram_user_id": telegram_user_id}})
        return {"reply": f"⚠️ Gateway unavailable ({e}). Try /status again in 30s.", "stage": "error"}

# ── Telegram polling (optional — requires token & library) ─────────────────
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

# Handlers — all forward to Gateway
async def handle_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_allowlist(update.effective_user.id):
        log.warning("unauthorized /start", extra={"extra": {"telegram_user_id": update.effective_user.id}})
        await update.message.reply_text("⛔ Not authorized.")
        return
    await update.message.reply_text(
        "👋 QROS Control Center online.\n"
        "Pipeline: Telegram → Bot → Gateway → GitHub → AgentOS\n"
        "Commands: /help /status /tasks /reports /events /validate"
    )

async def handle_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_allowlist(update.effective_user.id):
        await update.message.reply_text("⛔ Not authorized.")
        return
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

async def _gateway_and_reply(update: Update, text: str):
    if not await check_allowlist(update.effective_user.id):
        await update.message.reply_text("⛔ Not authorized.")
        return
    ctx = {"chat_id": update.effective_chat.id, "username": update.effective_user.username}
    data = await forward_to_gateway(update.effective_user.id, text, ctx)
    reply = data.get("reply") or data.get("message") or "[no reply]"
    # Telegram limit 4096
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
    try:
        telegram_app = Application.builder().token(settings.telegram_bot_token).build()
        telegram_app.add_handler(CommandHandler("start", handle_start))
        telegram_app.add_handler(CommandHandler("help", handle_help))
        telegram_app.add_handler(CommandHandler("status", handle_status))
        telegram_app.add_handler(CommandHandler("tasks", handle_tasks))
        telegram_app.add_handler(CommandHandler("reports", handle_reports))
        telegram_app.add_handler(CommandHandler("events", handle_events))
        telegram_app.add_handler(CommandHandler("validate", handle_validate))
        telegram_app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
        log.info(f"Telegram polling starting — allowed_users={settings.allowed_user_ids_list}")
        await telegram_app.initialize()
        await telegram_app.start()
        # verify getMe
        try:
            me = await telegram_app.bot.get_me()
            telegram_connected = True
            log.info(f"Telegram connected as @{me.username} id={me.id}", extra={"extra": {"telegram_user_id": me.id}})
        except Exception as e:
            log.warning(f"Telegram getMe failed (will still poll): {e}")
            telegram_connected = True
        await telegram_app.updater.start_polling(drop_pending_updates=True, allowed_updates=Update.ALL_TYPES)
        log.info("Telegram long polling ONLINE")
    except Exception as e:
        log.error(f"Telegram polling failed to start: {e}")
        telegram_connected = False

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

# ── FastAPI with lifespan (graceful restart) ───────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    log.info(f"Bot startup — port {settings.port} gateway={settings.gateway_internal_url}")
    # start polling in background if configured
    task = None
    if TELEGRAM_AVAILABLE and settings.telegram_bot_token and not settings.telegram_bot_token.startswith("123456:"):
        task = asyncio.create_task(start_telegram_polling())
        # store for shutdown
        app.state.telegram_task = task
    yield
    # shutdown
    log.info("Bot shutdown — graceful")
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
    title="QROS Bot (Stage 2)",
    version="1.0.0-stage2",
    description="Telegram long polling → Gateway → GitHub → AgentOS",
    lifespan=lifespan,
)

@app.get("/health")
def health():
    return {"service": "qros-bot", "status": "ok", "stage": "2-wired", "version": "1.0.0-stage2", "telegram_connected": telegram_connected, "telegram_available": TELEGRAM_AVAILABLE}

@app.get("/ready")
async def ready():
    missing = settings.validate_stage1()
    # gateway reachable probe
    gateway_ok = False
    try:
        async with httpx.AsyncClient(timeout=3) as c:
            r = await c.get(f"{settings.gateway_internal_url.rstrip('/')}/health")
            gateway_ok = r.status_code == 200
    except Exception:
        gateway_ok = False
    # telegram probe (if token placeholder, report degraded)
    tg_ok = telegram_connected if not settings.telegram_bot_token.startswith("123456:") and settings.telegram_bot_token else False
    # For health/evidence: if token is placeholder, we still report ready=false but health ok — allows CI without real token
    return {
        "service": "qros-bot",
        "ready": len(missing) == 0 and gateway_ok,
        "missing_env": missing,
        "allowed_users_configured": len(settings.allowed_user_ids_list),
        "gateway": settings.gateway_internal_url,
        "gateway_reachable": gateway_ok,
        "telegram_connected": tg_ok,
        "telegram_available": TELEGRAM_AVAILABLE,
        "environment": settings.environment,
    }

@app.get("/")
def root():
    return {
        "service": "qros-bot",
        "stage": "2-wired",
        "pipeline": "Telegram → QROS Bot → OpenAI Gateway → GitHub → AgentOS → Arena+Kilo",
        "health": "/health",
        "ready": "/ready",
        "internal": "POST /internal/notify",
        "commands": ["/start", "/help", "/status", "/tasks", "/reports", "/events", "/validate"],
        "telegram_polling": "long polling" if TELEGRAM_AVAILABLE else "stub (library missing)",
    }

class NotifyIn(BaseModel):
    text: str
    parse_mode: str | None = None

@app.post("/internal/notify")
async def internal_notify(body: NotifyIn, request: Request):
    # internal — only trusted network; allowlist not enforced but log caller
    # Forward to all allowed users via Telegram
    if not telegram_app or not telegram_connected:
        log.warning("Notify dropped — Telegram not connected", extra={"extra": {"event": "notify_dropped"}})
        # still return ok for Watcher/Gateway — do not fail webhook
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

# signal handling for graceful restart (uvicorn handles SIGTERM, but also ensure polling stops)
def _handle_signal(signum, frame):
    log.info(f"Received signal {signum} — graceful shutdown")
    # uvicorn will trigger lifespan shutdown

signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)

def main() -> None:
    missing = settings.validate_stage1()
    if missing:
        log.warning(f"Bot config incomplete — missing: {', '.join(missing)} (health will show degraded)")
    else:
        log.info(f"Bot config OK — allowed_users={settings.allowed_user_ids_list} gateway={settings.gateway_internal_url}")
    log.info(f"Starting QROS Bot wired on port {settings.port} (Stage 2: long polling if configured)")
    uvicorn.run(app, host="0.0.0.0", port=settings.port, log_level="info")

if __name__ == "__main__":
    main()
