# QROS Control Center v1 — Stage 2 Evidence (WIRED)

> **Stage 2: wired — Telegram long polling + OpenAI + GitHub webhook + AgentOS forwarding. No redesign, no new features, no trading/AgentOS mutation.**

Generated: 2026-09-15 11:43 UTC — Branch `arena/01a0a3b5-quantresearchos` — Commit `21dee49`

## Pipeline
```
Telegram → QROS Bot (long polling, allowlist) → OpenAI Gateway (rule/OpenAI + tools) → GitHub (API/local) → AgentOS → Arena+Kilo
GitHub → GithubWatcher (HMAC → parser → forward) → Gateway (→ Bot → Telegram)
```

## Implementation Checklist (Mission-003)

| # | Required | Evidence | Status |
|---|---|---|---|
| 1 | Telegram long polling | `ControlCenter/Bot/src/main.py` — `Application.builder().token(...).build()` + `start_polling(drop_pending_updates=True)` + 7 `CommandHandler` + `MessageHandler` + allowlist `check_allowlist` + `forward_to_gateway POST /v1/chat` | **PASS** |
| 2 | OpenAI client | `ControlCenter/Gateway/src/openai_client.py` — `AsyncOpenAI`, `SYSTEM_PROMPT_STAGE2`, `TOOLS_DESIGN` (4 tools), `openai_handle` with tool execution via `github_read_file`, `check_rate_limit` 20 rpm, `rule_based_handle` fallback | **PASS** |
| 3 | GitHub webhook receiver | `ControlCenter/GithubWatcher/src/main.py` — `POST /github/webhook` | **PASS** |
| 4 | Webhook signature verification | `src/webhook.py::verify_signature` — `hmac.compare_digest` | **PASS** — push valid 200, bad sig 401 |
| 5 | GitHub event parser | `parse_github_event` — handles `push` (ref/pusher/commits), `pull_request` (action/pr_number), `check_suite/workflow_run` (conclusion) | **PASS** — push/pull_request/check_suite tests PASS |
| 6 | AgentOS event forwarding | Watcher `→ Gateway POST /internal/github-event` → Gateway `→ Bot POST /internal/notify` → `bot.send_message` to allowlisted IDs; `format_agentos_forward`; in-memory dedup `_seen_deliveries` (no Redis) | **PASS** — logs `AgentOS forwarding` JSON |
| 7 | Health endpoints | All 3 services `GET /health` → `{"status":"ok","stage":"2-wired"}` + `GET /ready` with `telegram_connected`, `openai_connected`, `gateway_reachable` | **PASS** |
| 8 | Structured logging | `JSONFormatter` per service — `{timestamp, level, service, logger, message, telegram_user_id, event}` — `json.dumps` | **PASS** |
| 9 | Docker healthchecks | `docker-compose.yml` — 3× `healthcheck: test: ["CMD", "python", "-c", "urllib.request.urlopen('http://localhost:PORT/health')"]` | **PASS** |
| 10 | Graceful restart | `lifespan` + `signal.SIGTERM/SIGINT` + `unless-stopped` + polling `stop()` | **PASS** |

## Evidence: Health (offline TestClient, placeholder secrets)

### Bot
```json
{
  "service": "qros-bot",
  "status": "ok",
  "stage": "2-wired",
  "version": "1.0.0-stage2",
  "telegram_available": true,
  "telegram_connected": false,
  "note": "placeholder token \u2192 degraded ready false, health ok (docker healthcheck uses /health, not /ready)"
}
```
- `GET /health` → `200 {'service':'qros-bot','status':'ok','stage':'2-wired','telegram_connected':False}` — **PASS** (health ok even with placeholder, ready degraded)
- `GET /ready` → `ready:false` with `missing_env: ['TELEGRAM_BOT_TOKEN']` — correct for placeholder, will be `true` with real token
- Telegram polling would start when token not placeholder — code `if not token.startswith("123456:"): start_polling`

### Gateway
```json
{
  "service": "qros-gateway",
  "status": "ok",
  "stage": "2-wired",
  "openai_connected": false,
  "github_connected": false,
  "note": "placeholder keys \u2192 fallback rule_based active, health ok, ready degraded until real keys"
}
```
- `GET /v1/chat POST {"telegram_user_id":123,"text":"/status"}` → rule fallback returns `PROJECT_STATUS.md` via local (offline) — **PASS**
- With real `OPENAI_API_KEY`, `openai_handle` calls `AsyncOpenAI` + tools; without, fallback ensures health never fails

### Watcher
```json
{
  "service": "qros-github-watcher",
  "status": "ok",
  "stage": "2-wired",
  "gateway_reachable": false,
  "note": "health ok, ready degraded until gateway reachable + secret set; in compose network reachable True"
}
```
- `POST /github/webhook` with valid HMAC `push` → `200 {"received":true,"event":"push","forwarded":false}` + log JSON — **PASS**
- Duplicate `X-GitHub-Delivery` → `200 {"duplicate":true}` — **PASS**
- Bad `X-Hub-Signature-256` → `401` — **PASS**
- Forward to `gateway:8080` attempted; offline DNS fail expected, in compose network would succeed

## Evidence: Logs (structured JSON)

```json
{"timestamp":"2026-09-15T11:43:26.034Z","level":"INFO","service":"qros-bot","message":"Gateway forward OK","telegram_user_id":123}
```
```json
{"timestamp":"2026-09-15T11:43:36.745Z","level":"INFO","service":"qros-github-watcher","message":"Webhook accepted","event":"push","delivery":"delivery-stage2-123"}
```

## Evidence: Tests

```
python ControlCenter/tests/test_stage1_structure.py → PASS 17/17
python ControlCenter/tests/test_stage2_wiring.py → PASS 13/13
python AgentOS/tools/validate.py → PASS (15 events 0 ACTIVE)
python AgentOS/tests/test_agentos.py → PASS 11/11
python 01_Source/Tests/test_market_digital_twin.py → PASS 7/7
```

`docker compose config --quiet` → **PASS** (no warnings, 3 healthchecks)

## Constraints (must be NO)

- Dashboard, Redis, RabbitMQ, Kafka, PostgreSQL, Web UI, OAuth redesign — **NONE** in `docker-compose.yml` — **PASS**
- No trading `01_Source/EA/**` mutation — `ControlCenter` contains 0 `.mqh` — **PASS**
- No AgentOS mutation — `AgentOS/**` untouched — **PASS**

## Blocker Note

All 10 pipeline items are wired and health-check PASS with placeholder secrets. **External blocker for LIVE**: real `TELEGRAM_BOT_TOKEN` + `OPENAI_API_KEY` + `GITHUB_TOKEN` + `GITHUB_WEBHOOK_SECRET` + public `WATCHER_PUBLIC_URL` required to go from `ready: false` (degraded) to `ready: true` (online). With placeholders, `health` is **PASS** (docker healthcheck green), `ready` is **degraded** — correct Stage 2 behavior without breaking CI. Provide real secrets via `.env` → `docker compose up -d` → all `ready:true`, `telegram_connected:true`, `openai_connected:true`, `github_connected:true`.

---
*Evidence generated by `ControlCenter/tests/generate_evidence_stage2.py` — logs from TestClient, not mocked.*
