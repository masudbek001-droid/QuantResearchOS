# QROS Control Center — Environment Variables (Stage 1)

Single source: `.env.example` (also `ENV.example`, `ControlCenter/.env.example`, `ControlCenter/config/env.example` — all synchronized). Copy to `.env` (gitignored) and fill.

## How it works
- Docker Compose `env_file: .env` injects into all services.
- Each service validates via `pydantic-settings` (`BotSettings.validate_stage1()`, etc.) and exposes `GET /ready` with `missing_env` (no crash in Stage 1).
- No secrets in code, compose, or logs.

## Table

| Variable | Service | Required (Stage 1) | Default | Description |
|---|---|---|---|---|
| `ENVIRONMENT` | all | no | `development` | `development`/`production`. Toggles log verbosity / TLS expectations. |
| `LOG_LEVEL` | all | no | `info` | `debug`/`info`/`warn`/`error`. |
| `TZ` | all | no | `Asia/Tashkent` | Container timezone (matches repo). |
| `TELEGRAM_BOT_TOKEN` | bot | yes | — | From `@BotFather` `/newbot`. Format `123:ABC...`. |
| `TELEGRAM_ALLOWED_USER_IDS` | bot | yes | — | Comma-separated integers. Empty = deny all. |
| `TELEGRAM_WEBHOOK_URL` | bot | no | — | `https://<host>/telegram/webhook` for webhook mode; empty = long-polling (Stage 2). |
| `TELEGRAM_API_URL` | bot | no | `https://api.telegram.org` | Override for testing. |
| `OPENAI_API_KEY` | gateway | yes | — | `sk-proj-...`. Only gateway holds it. |
| `OPENAI_MODEL` | gateway | no | `gpt-4o-mini` | LLM. |
| `OPENAI_BASE_URL` | gateway | no | `https://api.openai.com/v1` | For proxies. |
| `OPENAI_MAX_TOKENS` | gateway | no | `2048` | Cap. |
| `OPENAI_TEMPERATURE` | gateway | no | `0.2` | Deterministic. |
| `GATEWAY_PORT` | gateway | no | `8080` | Host+container. |
| `GATEWAY_TIMEOUT_SECONDS` | gateway | no | `30` | Upstream. |
| `GATEWAY_RATE_LIMIT_RPM` | gateway | no | `20` | Per `telegram_user_id`, Stage 2. |
| `GATEWAY_INTERNAL_URL` | bot, watcher | no | `http://gateway:8080` | Compose DNS. |
| `BOT_PORT` | bot | no | `8081` | |
| `BOT_INTERNAL_URL` | watcher | no | `http://bot:8081` | |
| `GITHUB_TOKEN` | gateway, watcher | yes | — | Fine-grained PAT, `repo`-limited. |
| `GITHUB_REPO` | all | no | `masudbek001-droid/QuantResearchOS` | |
| `GITHUB_API_URL` | all | no | `https://api.github.com` | |
| `GITHUB_WEBHOOK_SECRET` | watcher | yes | — | `openssl rand -hex 32`. Must match GitHub webhook. |
| `GITHUB_WEBHOOK_PORT` | watcher | no | `8082` | Also `WATCHER_PORT`. |
| `WATCHER_PUBLIC_URL` | watcher | prod yes | — | `https://<host>/github/webhook`. For registration. |
| `WATCHER_INTERNAL_URL` | — | no | `http://github-watcher:8082` | |
| `GITHUB_ARENA_BRANCH` | all | no | `arena/01a0a3b5-quantresearchos` | Managed branch. |
| `CONTROL_CENTER_PORT` | control-center | no | `8083` | Stage 2 dashboard. |
| `AGENTOS_PATH` | gateway | no | `/app/AgentOS` | Inside container, read-only mirror. |
| `AGENTOS_POLL_INTERVAL_SECONDS` | gateway | no | `30` | Cache invalidate, Stage 2. |
| `ARENA_URL` | — | no | `https://arena.example.com` | Stage 2. |
| `KILO_URL` | — | no | `http://kilo:8000` | Stage 2. |
| `KILO_TOKEN` | — | no | — | Stage 2. |
| `COMPOSE_PROJECT_NAME` | compose | no | `qros-control-center` | |
| `NETWORK_NAME` | compose | no | `qros-control-net` | Bridge. |

## Minimal `.env` for local Stage 1 health check
```env
TELEGRAM_BOT_TOKEN=123:placeholder
TELEGRAM_ALLOWED_USER_IDS=123456789
OPENAI_API_KEY=sk-proj-placeholder
GITHUB_TOKEN=ghp_placeholder
GITHUB_WEBHOOK_SECRET=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

`/ready` will still report missing until real values, but `/health` stays `ok` — correct for structure-only.

## Rotation
- `GITHUB_WEBHOOK_SECRET` + GitHub webhook secret → change together → `docker compose up -d --force-recreate watcher`
- `OPENAI_API_KEY` / `GITHUB_TOKEN` → update `.env` → `docker compose up -d --force-recreate gateway`
