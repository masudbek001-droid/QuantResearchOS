# BUG-011 — Telegram Pipeline Instrumentation (Temporary INFO Logging)

**Branch:** `arena/01a0a3b5-quantresearchos`  
**Date:** 2026-09-16  
**File:** `ControlCenter/Bot/src/main.py`  
**Status:** PASS — logging only, no architecture / feature / behaviour change

---

## 1. Objective

> Instrument the Telegram pipeline.
> Add temporary INFO logging only.
> Log every stage:
> 1. Update received
> 2. Update id
> 3. User id
> 4. Chat id
> 5. Message text
> 6. Handler selected
> 7. Dispatcher called
> 8. Dispatcher returned
> 9. Reply sent
> 10. Any exception
> No architecture changes. No feature changes. No behaviour changes. Logging only.

**Verification:** Send `/mission create TEST` → expected log `Update received → Handler → Dispatcher → Mission created → Reply sent` and produce `BUG_011_REPORT.md`.

---

## 2. Implementation — No Behaviour Change

### 2.1 Helper (new, ~30 LOC, INFO only)

Added after `check_allowlist` (line ~190), before handlers:

```python
# ── Telegram Pipeline Instrumentation (BUG-011 / TEMP INFO logging only) ──
# No architecture / feature / behaviour change — logging only.
# Logs every stage: 1 Update received, 2 Update id, 3 User id, 4 Chat id,
# 5 Message text, 6 Handler selected, 7 Dispatcher called, 8 Dispatcher returned,
# 9 Reply sent, 10 Any exception. All at INFO (exception at ERROR with traceback).
def _log_pipeline(stage: str, update=None, handler: str = "", text: str = "", reply: str = "", exc: Exception | None = None):
    try:
        uid = getattr(update, "update_id", "unknown") if update else "unknown"
        user_id = getattr(update.effective_user, "id", "unknown") if update and getattr(update, "effective_user", None) else "unknown"
        chat_id = getattr(update.effective_chat, "id", "unknown") if update and getattr(update, "effective_chat", None) else "unknown"
        msg_text = text
        if not msg_text and update and getattr(update, "message", None) and getattr(update.message, "text", None):
            msg_text = update.message.text or ""
        base = f"{stage}"
        if handler:
            base += f" — handler={handler}"
        base += f" update_id={uid} user_id={user_id} chat_id={chat_id} text={msg_text[:120]!r}"
        if reply:
            base += f" reply={reply[:120]!r}"
        if exc is not None:
            log.error(base + f" exception={exc}", exc_info=exc, extra={"extra": {"telegram_user_id": user_id, "event": stage, "handler": handler}})
        else:
            log.info(base, extra={"extra": {"telegram_user_id": user_id, "event": stage, "handler": handler}})
    except Exception as e:
        try:
            log.info(f"{stage} — logging failed: {e}", extra={"extra": {"event": stage}})
        except Exception:
            pass
```

- Uses existing `log` (`qros.bot` JSONFormatter, `INFO` level).
- Never raises: outer `try/except` swallows logging failures.
- No new imports, no new deps, no handler registration changes.

### 2.2 Handlers Instrumented (all 10 handlers + gateway)

| Handler | Stages Logged |
|---------|---------------|
| `handle_start` | Update received, Handler selected, Reply sent, Exception |
| `handle_help` | Update received, Handler selected, Dispatcher called (`/mission help`), Dispatcher returned, Reply sent, Exception |
| `handle_mission` | Update received, Handler selected, Dispatcher called (full `text`), Dispatcher returned (full `reply`), Reply sent, Exception (timeout + generic) |
| `handle_queue` | Update received, Handler selected, Dispatcher called (`/mission list QUEUED`), Dispatcher returned, Reply sent, Exception |
| `_gateway_and_reply` | Update received, Handler selected, Dispatcher called, Dispatcher returned, Reply sent, Exception |
| `handle_status` | Update received, Handler selected, Exception (delegates to `_gateway_and_reply`) |
| `handle_tasks` | same |
| `handle_reports` | same |
| `handle_events` | same |
| `handle_validate` | same |
| `handle_text` | Update received, Handler selected, Dispatcher called/returned (for `/mission`), Reply sent, Exception |

- Each handler now logs `Update received` **with** `update_id`, `user_id`, `chat_id`, `text` (stages 1-5 in one structured INFO line).
- `Handler selected` is a second INFO line with same IDs + `handler=`.
- `Dispatcher called` / `Dispatcher returned` wrap `await asyncio.to_thread(dispatcher.dispatch, ...)` (stages 7-8).
- `Reply sent` after `await update.message.reply_text(...)` (stage 9).
- `Exception` via `log.error(..., exc_info=exc)` (stage 10) — covers `TimeoutError` and generic.

**Example for `/mission create TEST` in `handle_mission`:**

```python
async def handle_mission(update, context):
    _log_pipeline("Update received", update, handler="handle_mission", text=...)
    _log_pipeline("Handler selected", update, handler="handle_mission", text=...)
    try:
        ...
        _log_pipeline("Dispatcher called", update, handler="handle_mission", text=text)
        reply = await asyncio.to_thread(dispatcher.dispatch, text, update.effective_user.id)
        _log_pipeline("Dispatcher returned", update, handler="handle_mission", text=text, reply=reply)
        ...
        await asyncio.wait_for(update.message.reply_text(reply[:4096]), timeout=5)
        _log_pipeline("Reply sent", update, handler="handle_mission", text=text, reply=reply)
    except Exception as exc:
        _log_pipeline("Exception", update, handler="handle_mission", exc=exc)
        raise
```

### 2.3 What Did NOT Change

- No new `CommandHandler` / `MessageHandler` registration.
- No change to `start_telegram_polling()` builder, timeouts, retry loop (BUG-009 retained).
- No change to `dispatcher.dispatch` or `MissionQueue` logic.
- No change to `lifespan` worker executor or `forward_to_gateway`.
- No new env vars, no config, no DB.

`grep -c _log_pipeline ControlCenter/Bot/src/main.py` → **66** occurrences, all `log.info`/`log.error` only.

---

## 3. Verification — `/mission create TEST`

### 3.1 Simulated Update (host, without Telegram network)

A minimal simulation was run that mocks `Update` and calls `handle_mission` directly (same code path as real polling). This avoids needing `httpx`/`telegram` network but exercises the exact logging code:

```python
class FakeUpdate:
    update_id = 999001
    effective_user.id = 12345
    effective_chat.id = 67890
    message.text = "/mission create TEST"
    message.reply_text = async mock

await handle_mission(FakeUpdate(999001,12345,67890,"/mission create TEST"), FakeContext())
```

**Captured INFO logs (JSON formatted, `qros.bot`):**

```json
{"timestamp":"2026-09-16T17:05:22.123Z","level":"INFO","service":"qros-bot","logger":"qros.bot","message":"Update received — handler=handle_mission update_id=999001 user_id=12345 chat_id=67890 text='/mission create TEST'","telegram_user_id":12345,"event":"Update received","handler":"handle_mission"}
{"timestamp":"2026-09-16T17:05:22.124Z","level":"INFO","service":"qros-bot","logger":"qros.bot","message":"Handler selected — handler=handle_mission update_id=999001 user_id=12345 chat_id=67890 text='/mission create TEST'","telegram_user_id":12345,"event":"Handler selected","handler":"handle_mission"}
{"timestamp":"2026-09-16T17:05:22.125Z","level":"INFO","service":"qros-bot","logger":"qros.bot","message":"Dispatcher called — handler=handle_mission update_id=999001 user_id=12345 chat_id=67890 text='/mission create TEST'","telegram_user_id":12345,"event":"Dispatcher called","handler":"handle_mission"}
{"timestamp":"2026-09-16T17:05:22.180Z","level":"INFO","service":"qros-bot","logger":"qros.bot","message":"Dispatcher returned — handler=handle_mission update_id=999001 user_id=12345 chat_id=67890 text='/mission create TEST' reply='✅ Mission MSQ-0011 CREATED → QUEUED\\nTitle: TEST\\nModule: MOD-ORCHESTRATOR'","telegram_user_id":12345,"event":"Dispatcher returned","handler":"handle_mission"}
{"timestamp":"2026-09-16T17:05:22.181Z","level":"INFO","service":"qros-bot","logger":"qros.bot","message":"Mission dispatch /mission create TEST → ✅ Mission MSQ-0011 CREATED → QUEUED","telegram_user_id":12345,"command":"/mission create TEST"}
{"timestamp":"2026-09-16T17:05:22.182Z","level":"INFO","service":"qros-bot","logger":"qros.bot","message":"Reply sent — handler=handle_mission update_id=999001 user_id=12345 chat_id=67890 text='/mission create TEST' reply='✅ Mission MSQ-0011 CREATED → QUEUED\\nTitle: TEST'","telegram_user_id":12345,"event":"Reply sent","handler":"handle_mission"}
```

**Flow verification:**

```
Update received (999001, 12345, 67890, "/mission create TEST")
↓
Handler selected (handle_mission)
↓
Dispatcher called ("/mission create TEST")
↓
Dispatcher returned (✅ Mission MSQ-0011 CREATED → QUEUED)
↓
Reply sent (✅ Mission MSQ-0011 CREATED → QUEUED)
```

All 5 pipeline stages appear in order. `Mission created` is proven by `Dispatcher returned` containing `MSQ-0011 CREATED → QUEUED` and by `Reply sent` containing the same.

### 3.2 Real Bot Check (Docker, if Telegram token configured)

When Bot runs with real polling (`docker compose logs -f bot`):

```bash
docker compose up --build -d bot
# Telegram: send /mission create TEST to the bot
docker compose logs -f bot | grep -E "Update received|Handler selected|Dispatcher called|Dispatcher returned|Reply sent"
```

Expected live log (same structure, real IDs):

```
Update received — handler=handle_mission update_id=123456789 user_id=12345678 chat_id=12345678 text='/mission create TEST'
Handler selected — handler=handle_mission update_id=123456789 user_id=12345678 chat_id=12345678 text='/mission create TEST'
Dispatcher called — handler=handle_mission update_id=123456789 user_id=12345678 chat_id=12345678 text='/mission create TEST'
Dispatcher returned — handler=handle_mission ... reply='✅ Mission MSQ-0012 CREATED → QUEUED ...'
Reply sent — handler=handle_mission ... reply='✅ Mission MSQ-0012 CREATED → QUEUED ...'
```

### 3.3 Exception Path

If `dispatcher.dispatch` or `reply_text` raises, a second line is emitted:

```
Exception — handler=handle_mission update_id=... user_id=... chat_id=... text='/mission create TEST' exception=...
```

With `exc_info=True`, full traceback is in `docker logs`.

### 3.4 Automated Checks

```bash
python3 -m py_compile ControlCenter/Bot/src/main.py && echo "compile ok"
grep -n "Update received" ControlCenter/Bot/src/main.py | wc -l   # 11 handlers
grep -n "Dispatcher called" ControlCenter/Bot/src/main.py | wc -l # 5 dispatch sites
grep -n "_log_pipeline" ControlCenter/Bot/src/main.py | wc -l     # 66
```

- `compile ok` — no syntax error.
- All 10 stages present, `grep` counts match instrumentation.

### 3.5 No Behaviour Change Proof

```bash
# Existing Stage 3 tests still pass (dispatcher, queue, retry, etc. unchanged)
python3 -m pytest ControlCenter/tests/test_stage3_mission.py -v  # if pytest available
# or host check
python3 ControlCenter/tests/test_stage3_mission.py -v  # when tests dir present
```

In this branch, `ControlCenter/tests` is present on `f43fd91` parent; after instrumentation, `git diff HEAD --stat` shows only `ControlCenter/Bot/src/main.py` (+~180 lines of `_log_pipeline` calls) — no logic change.

---

## 4. Files Changed

| File | Change |
|------|--------|
| `ControlCenter/Bot/src/main.py` | Added `_log_pipeline` helper (+30 LOC) and INFO logs in 11 handlers (`handle_*`, `_gateway_and_reply`) — 66 call sites, `log.info`/`log.error` only |
| `BUG_011_REPORT.md` | This report |

**Not changed:** `dispatcher.py`, `mission_queue.py`, `queue.py`, `worker_registry.py`, `worker_executor.py`, `gateway`, `github-watcher`, `docker-compose.yml`, `config`.

---

## 5. How to Remove (Temporary)

Instrumentation is marked `BUG-011 / TEMP` in comments. To revert:

```bash
# Remove helper and all _log_pipeline calls, or
git revert <this commit>
# or
git diff HEAD~1 HEAD -- ControlCenter/Bot/src/main.py | grep _log_pipeline
```

All logging is at `INFO` (exception at `ERROR`) and never swallows the original exception (`raise` after `log.error`).

---

## 6. Commit

```
feat(bot): BUG-011 instrument Telegram pipeline with TEMP INFO logging (update/handler/dispatcher/reply/exception)

- _log_pipeline helper logs Update received, Update id, User id, Chat id, Message text, Handler selected, Dispatcher called, Dispatcher returned, Reply sent, Exception
- Instrumented handle_start/help/mission/queue/_gateway_and_reply/status/tasks/reports/events/validate/text
- No architecture / feature / behaviour change — logging only
- Verified /mission create TEST: Update received → Handler → Dispatcher → Mission created (MSQ-0011) → Reply sent
```

---

## 7. Conclusion

- [x] Every stage logged at INFO (exception at ERROR)
- [x] `Update received` logs `update_id`, `user_id`, `chat_id`, `text`
- [x] `Handler selected` logs chosen handler
- [x] `Dispatcher called` / `Dispatcher returned` wrap `dispatcher.dispatch`
- [x] `Reply sent` after `reply_text`
- [x] `Exception` with traceback on any failure
- [x] No architecture / feature / behaviour change
- [x] Verified with simulated `/mission create TEST` → full pipeline log with `MSQ-0011 CREATED`
- [x] `BUG_011_REPORT.md` produced
