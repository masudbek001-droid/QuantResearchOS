# Telegram Bot Design — QROS Control Center (Stage 1)

## 1. Goal
Telegram is the remote UI for project management. Bot is the only Telegram surface; it authenticates, then forwards every user message to Gateway (`POST /v1/chat`) and relays the reply. No direct GitHub/AgentOS calls from Bot. Not trading. Not autonomous.

## 2. Commands (Stage 1 design, Stage 2 implements)

| Command | Description | Gateway tool (Stage 2) | Scope |
|---|---|---|---|
| `/start` | Greeting + auth check + help hint | — (static) | All allowlisted |
| `/help` | List commands, pipeline, links | — | All |
| `/status` | `PROJECT_STATUS.md` + `ROADMAP.md` summary | `github_read_file` (PROJECT_STATUS) | Read |
| `/tasks [OPEN|DONE]` | `TASK_QUEUE.md` list/filter | `github_list_tasks` | Read |
| `/reports` | `REPORT_QUEUE.md` | `github_read_file` | Read |
| `/events [n]` | `EVENT_BUS` tail | `github_read_file` | Read |
| `/validate` | run `agentos_validate` (CI view) | `agentos_validate` | Read |
| `/task create <title>` | Stage 2 write, requires confirm | `github_create_task` | Write (confirm) |

Stage 1 stub: `src/main.py` exposes `GET /` with this list; `src/handlers/__init__.py` holds skeletons. No handlers run yet.

## 3. Authentication

- Env `TELEGRAM_ALLOWED_USER_IDS` — comma-separated integers (not usernames). Example: `123456789,987654321`.
- At handler entry:
  ```python
  if update.effective_user.id not in settings.allowed_user_ids_list:
      log.warning("unauthorized", extra={"user_id": update.effective_user.id})
      await update.message.reply_text("⛔ Not authorized.")
      return
  ```
- Empty list = deny all (`validate_stage1` reports missing). Never empty in prod.
- Token `TELEGRAM_BOT_TOKEN` is secret; never logged, never echoed, never committed.

## 4. Transport

- **Stage 1:** Bot is a FastAPI stub only (`GET /health`, `/ready`, `/`). No Telegram network.
- **Stage 2 options:**
  - **Long-polling (default):** `Application.builder().token(token).build()`, `run_polling(allowed_updates=...)`. No public URL, simplest for prod behind NAT.
  - **Webhook:** set `TELEGRAM_WEBHOOK_URL=https://<host>/telegram/webhook`, then `bot.set_webhook(url, secret_token=webhook_secret)`. Requires TLS + `X-Telegram-Bot-Api-Secret-Token` verification.

Both modes share the same handler allowlist; webhook adds header check.

## 5. Forwarding to Gateway

Every authorized message:
```
Telegram User → Bot handler → httpx POST http://gateway:8080/v1/chat
  { "telegram_user_id": 123, "text": "/status", "context": { "chat_id": ... } }
→ Gateway → OpenAI / GitHub → { "reply": "...", "tool_calls": [...] }
→ Bot → Telegram sendMessage(reply)
```

- Bot passes `telegram_user_id` for Gateway audit/rate-limit.
- Timeout: `GATEWAY_TIMEOUT_SECONDS` (default 30s). On Gateway 429/timeout, Bot replies `⏳ Gateway busy, retry.`
- Bot never calls GitHub (`GITHUB_TOKEN` is not in Bot in Stage 2 tight config; it lives in Gateway).

## 6. Handler Skeleton (Stage 2 preview)

```python
# src/handlers/status.py (Stage 2)
from telegram import Update
from telegram.ext import ContextTypes
import httpx

async def status(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id not in settings.allowed_user_ids_list: return
    async with httpx.AsyncClient() as c:
        r = await c.post(f"{settings.gateway_internal_url}/v1/chat",
                         json={"telegram_user_id": update.effective_user.id, "text": "/status"})
        await update.message.reply_text(r.json()["reply"])
```

All handlers follow this pattern; no direct `AgentOS/**` mutation.

## 7. UX

- All replies are Markdown-safe (escape for Telegram MarkdownV2 or use plain).
- Long outputs (TASK_QUEUE) truncated + paginated; offer inline buttons (Stage 2: `InlineKeyboardButton` for `/tasks` → `View REPORT-...`).
- Errors: Gateway down → `⚠️ Control Center busy, retry in 30s`; unauthorized → generic.

## 8. Security & Logging

- Logs: `user_id` + command, never token or full message if it contains secrets.
- Rate limit: Bot also does per-user leaky bucket (optional; Gateway is authoritative).
- Webhook secret (if using webhook): `TELEGRAM_WEBHOOK_SECRET` header `X-Telegram-Bot-Api-Secret-Token` verified with `compare_digest`.

## 9. Stage 1 vs Stage 2

| Stage 1 | Stage 2 |
|---|---|
| FastAPI stub, no `Application`, no polling | `python-telegram-bot` Application, allowlist, handlers, Gateway forward |
| `src/handlers/__init__.py` lists design | `src/handlers/*.py` implement above |
| `GET /ready` reports allowlist length | Handlers enforce it |

See `ControlCenter/Bot/src/config.py` and `ControlCenter/Bot/README.md`.
