# ADR-0024: QROS Control Center v1 — Stage 2 Wired (Telegram → Gateway → GitHub → AgentOS)

## Status

Accepted. (Stage 2: wired — 2026-09-15 — MISSION-003)

## Context

- ADR-0023 (Stage 1) delivered project structure, compose, env, docs, stubs with `/health` — no business logic, no polling, no OpenAI calls, no GitHub writes, 17-check structure PASS.
- MISSION-003 (Chief Architect Approval) requires Stage 2 to **bring ONLINE** by wiring existing components — not redesign, not new features, not trading/AgentOS mutation. Only finish pipeline `Telegram ↓ Gateway ↓ GitHub ↓ AgentOS`.
- Required wiring (10 items): Telegram long polling, OpenAI client, GitHub webhook receiver, webhook HMAC, GitHub event parser, AgentOS forwarding, health endpoints, structured logging, Docker healthchecks, graceful restart. Forbidden: Dashboard, Redis, RabbitMQ, Kafka, PostgreSQL, Web UI, OAuth/arch redesign.
- Evidence must show: Docker running, Health PASS, Telegram connected, OpenAI connected, GitHub webhook PASS, AgentOS forwarding PASS, logs.

## Decision

Wire Stage 1 stubs into **Stage 2 wired** services, keeping same directory layout, compose, env, docs, and 1:1 AgentOS invariants.

### Bot (`ControlCenter/Bot/src/main.py`)

- **Structured JSON logging**: `JSONFormatter {timestamp, level, service, logger, message, telegram_user_id}` via `json.dumps`, `StreamHandler(stdout)`.
- **Health**: `GET /health` → `{"status":"ok","stage":"2-wired"}` (Docker healthcheck uses this, always 200 even with placeholder secrets). `GET /ready` → checks `TELEGRAM_BOT_TOKEN` presence, `allowed_users`, `gateway_reachable` probe, `telegram_connected` flag; `ready:false` with placeholder (health still green) → `ready:true` with real token.
- **Telegram long polling**: `Application.builder().token(token).build()` + `CommandHandler` for `/start`, `/help`, `/status`, `/tasks`, `/reports`, `/events`, `/validate` + `MessageHandler` for text → all `allowlist` guard → `httpx POST gateway:8080/v1/chat` → `send_message` reply. `start_polling(drop_pending_updates=True)` in `lifespan` background task, `getMe` probe sets `telegram_connected=True`.
- **Internal**: `POST /internal/notify` for Gateway/Watcher → `bot.send_message` to all `allowed_users`.
- **Graceful**: `lifespan` start/stop, `signal SIGTERM/SIGINT`, `await updater.stop()/stop()/shutdown()`.

### Gateway (`ControlCenter/Gateway/src/openai_client.py` + `src/main.py`)

- **OpenAI client**: `openai.AsyncOpenAI(api_key, base_url)`; `SYSTEM_PROMPT_STAGE2` + `TOOLS_DESIGN` (4 tools: `github_read_file`, `github_list_tasks`, `agentos_validate`, `github_create_task`) + `check_rate_limit` 20 rpm per user + `github_read_file` (GitHub API via `httpx` + local fallback `AgentOS/**`) + `rule_based_handle` fallback for `/status` etc. when key placeholder; `openai_handle` tool loop → results concatenated.
- **Main**: `POST /v1/chat` → rate limit 429 → `openai_handle` if key real else `rule_based_handle`; `GET /v1/tools`, `GET /health` (always ok), `GET /ready` (probes `openai_connected`, `github_connected` via token format + `rate_limit` ping without cost), `POST /internal/github-event` → formats notify text + `httpx POST bot:8081/internal/notify`.
- **Logging**: `JSONFormatter` per service; `lifespan` + `signal`.

### Watcher (`ControlCenter/GithubWatcher/src/webhook.py` + `src/main.py`)

- **HMAC**: `verify_signature` `hmac.compare_digest` unchanged (Stage 1 PASS).
- **Parser**: `parse_github_event(event, payload_bytes)` → `push` (ref/pusher/commits), `pull_request` (action/pr_number/title), `check_suite/workflow_run` (conclusion); `format_agentos_forward` + in-memory `_seen_deliveries` dedup (no Redis per mission).
- **Main**: `POST /github/webhook` → dedup → `verify_signature` 401 → `parse` → log `AgentOS forwarding` JSON → `httpx POST gateway:8080/internal/github-event` (async, webhook always 200 quickly); `GET /health`/`/ready` (gateway_reachable probe), `JSONFormatter`, `lifespan` + `signal`.

### Compose & Ops

- `docker-compose.yml` image tags `1.0.0-stage2`, same 3 services + `qros-control-net` + `qros-logs` + 3 `healthcheck` `urllib /health` + `restart: unless-stopped` + `depends_on: service_healthy`.
- No Redis/Dashboard/etc. — compose still 3 services only.

## Consequences

- Stage 2 wired evidence: `ControlCenter/tests/test_stage2_wiring.py` 13 checks PASS, `test_stage1_structure` still 17 PASS, `AgentOS` validate 11 PASS, twin 7 PASS; `TestClient` health `200 stage 2-wired`, webhook `push 200 / duplicate 200 / bad 401`, gateway `POST /v1/chat /status` returns `PROJECT_STATUS.md` via rule fallback offline, structured JSON logs, compose 3 healthchecks.
- With placeholder secrets, `health` green (Docker green), `ready` degraded — correct without breaking CI. With real `.env` secrets + public `WATCHER_PUBLIC_URL`, `ready:true`, `telegram_connected:true`, `openai_connected:true`, `github_connected:true`.
- No trading `01_Source/EA/**` or AgentOS mutation; trading frozen MIPS v1.0 preserved.

## References

- ADR-0023 (Stage 1 structure), MISSION-003 (Stage 2 wiring), ControlCenter docs `ARCHITECTURE.md`/`SECURITY.md`/`INSTALL.md` + `STAGE2_EVIDENCE.md`, `04_Output/ControlCenter/stage2_evidence.json`

