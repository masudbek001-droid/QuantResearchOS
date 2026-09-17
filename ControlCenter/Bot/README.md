# QROS Bot — Telegram Front (Stage 1)

**Stage 1: structure only — no business logic, no polling, no AgentOS mutation.**

## Purpose
Remote project management entry: `Telegram → QROS Bot → OpenAI Gateway → GitHub → AgentOS → Arena+Kilo`. The Bot is the only Telegram surface; it never writes `AgentOS/**` directly — all state changes go through Gateway → GitHub.

## Layout
```
Bot/
├── Dockerfile              # python:3.11-slim, non-root, healthcheck
├── requirements.txt        # python-telegram-bot, fastapi, uvicorn, httpx
├── src/
│   ├── config.py           # BotSettings (env, allowlist, validate_stage1)
│   ├── main.py             # FastAPI stub (/health, /ready) — no polling yet
│   └── handlers/__init__.py # skeleton for Stage 2 commands
└── README.md
```

## Configuration
See `ControlCenter/.env.example` / `ENV.example`. Required for readiness:
- `TELEGRAM_BOT_TOKEN` — from @BotFather
- `TELEGRAM_ALLOWED_USER_IDS` — comma-separated IDs (deny-by-default)
- `GATEWAY_INTERNAL_URL` — default `http://gateway:8080`

Validate without network:
```bash
python -m src.config  # or GET /ready
curl http://localhost:8081/ready
```

## Telegram Bot Design (Stage 1 spec)
Full spec: `ControlCenter/docs/TELEGRAM_BOT_DESIGN.md`

- **Auth**: allowlist enforced at handler entry; all other users get silent drop + audit log.
- **Commands design** (not implemented yet): `/start`, `/help`, `/status`, `/tasks`, `/reports`, `/events`. All read-only in Stage 1; writes (task claim, report approve) are Stage 2 via Gateway.
- **Transport**: Stage 1 stub exposes FastAPI only. Stage 2 adds `python-telegram-bot` Application with long-polling (default) or webhook (`TELEGRAM_WEBHOOK_URL`).
- **Forwarding**: every command → HTTP POST to `Gateway /v1/chat` with `telegram_user_id`, `command`, `args`; Bot never calls GitHub/AgentOS directly.
- **Security**: token never logged, allowlist never bypassed, all Gateway calls carry `X-Telegram-User-Id` for audit.

## Docker
```bash
docker build -t qros/bot:stage1 ./ControlCenter/Bot
docker run --env-file .env -p 8081:8081 qros/bot:stage1
curl http://localhost:8081/health
```

## Stage 1 Non-Goals
- No Telegram polling / webhook registration
- No OpenAI calls
- No GitHub writes
- No trading or AI logic

Stage 2 will implement handlers + Gateway forwarding under the same security model.
