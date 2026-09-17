# QROS Control Center v1 — Stage 1

**Remote project management for QuantResearchOS. Not trading. Not AI.**

---

## Pipeline
```
Telegram
  ↓  Bot API (allowlist)
QROS Bot  — ControlCenter/Bot             (Telegram → Gateway)
  ↓  POST /v1/chat
OpenAI Gateway — ControlCenter/Gateway    (LLM → GitHub tools)
  ↓  GitHub API
GitHub — masudbek001-droid/QuantResearchOS (source of truth, arena branch)
  ↓  git is the bus
AgentOS — AgentOS/**  (TASK_QUEUE, REPORT_QUEUE, EVENT_BUS, LOCK_MANAGER)
  ↓
Arena + Kilo
  ↑  notifications
GitHub webhook → GithubWatcher → Gateway → Bot → Telegram
```

## Stage 1 Scope (this PR)
**Structure, Docker, config, docs — no business logic.**

| Deliverable | Path |
|---|---|
| `docker-compose.yml` | `/docker-compose.yml`, `ControlCenter/docker-compose.yml` |
| `ControlCenter/` | root |
| `Bot/` | `ControlCenter/Bot/` (Dockerfile, src, README) |
| `Gateway/` | `ControlCenter/Gateway/` (Dockerfile, src, README) |
| `GithubWatcher/` | `ControlCenter/GithubWatcher/` (Dockerfile, src, README) |
| `README` | `ControlCenter/README.md` (this) + root `README.md` (project) |
| `INSTALL.md` | `/INSTALL.md`, `ControlCenter/docs/INSTALL.md` |
| `ARCHITECTURE.md` | `/ARCHITECTURE.md`, `ControlCenter/docs/ARCHITECTURE.md` |
| `SECURITY.md` | `/SECURITY.md`, `ControlCenter/docs/SECURITY.md` |
| `ENV.example` | `/.env.example`, `/ENV.example`, `ControlCenter/.env.example`, `ControlCenter/config/env.example` |

Every milestone: `test` → `commit` → `push` → `continue` (until external blocker).

## Quick Start (Stage 1 stubs)

```bash
cp .env.example .env   # fill TELEGRAM_BOT_TOKEN, OPENAI_API_KEY, GITHUB_TOKEN, GITHUB_WEBHOOK_SECRET
docker compose build
docker compose up -d
curl http://localhost:8080/health  # gateway
curl http://localhost:8081/health  # bot
curl http://localhost:8082/health  # watcher
python ControlCenter/tests/test_stage1_structure.py
```

All three should return `{"status":"ok","stage":"1-structure"}`. Business logic (Telegram polling, OpenAI calls, GitHub writes) is Stage 2.

## Directory Layout

```
ControlCenter/
├── README.md                    # this file
├── docker-compose.yml
├── .env.example
├── config/env.example
├── docs/
│   ├── ARCHITECTURE.md          # pipeline + diagrams + layout
│   ├── SECURITY.md              # secrets, allowlist, HMAC, scopes
│   ├── INSTALL.md               # prerequisites + up + webhook test
│   ├── ENV_VARS.md              # full env table
│   ├── GITHUB_WEBHOOK_DESIGN.md # endpoint, HMAC, subscribed events, dedup
│   ├── TELEGRAM_BOT_DESIGN.md   # commands, auth, transport, forwarding
│   └── OPENAI_GATEWAY_DESIGN.md # system prompt, tools, safety, rate limit
├── Bot/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── src/config.py         # BotSettings + allowlist validation
│   ├── src/main.py           # FastAPI stub /health /ready
│   ├── src/handlers/__init__.py  # command skeletons
│   └── README.md
├── Gateway/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── src/config.py
│   ├── src/openai_client.py  # SYSTEM_PROMPT_STAGE1 + TOOLS_DESIGN + stub
│   ├── src/main.py           # FastAPI stub /v1/chat /v1/tools
│   └── README.md
├── GithubWatcher/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── src/config.py
│   ├── src/webhook.py        # verify_signature + subscribed events
│   ├── src/main.py           # FastAPI stub /github/webhook
│   └── README.md
└── tests/
    └── test_stage1_structure.py  # validates all Stage 1 deliverables
```

## Services

| Service | Port | Health | Purpose |
|---|---|---|---|
| `gateway` | `GATEWAY_PORT` 8080 | `GET /health` | OpenAI routing (Stage 1 stub `POST /v1/chat`) |
| `bot` | `BOT_PORT` 8081 | `GET /health` | Telegram front (Stage 1 FastAPI stub, no polling) |
| `github-watcher` | `GITHUB_WEBHOOK_PORT` 8082 | `GET /health` | GitHub webhook HMAC verify (Stage 1 no forward) |

Compose: `docker-compose.yml` (`qros-control-net` bridge, `qros-logs` volume, `unless-stopped`, health-based `depends_on`).

## Configuration
Single source: `.env.example`. See `ControlCenter/docs/ENV_VARS.md`.

Required secrets (placeholders pass `docker compose config`, but `/ready` reports missing until real):
- `TELEGRAM_BOT_TOKEN` + `TELEGRAM_ALLOWED_USER_IDS`
- `OPENAI_API_KEY`
- `GITHUB_TOKEN` + `GITHUB_WEBHOOK_SECRET`

No secrets in repo — `.env` is gitignored.

## Security
Summary: `SECURITY.md` → secrets via env, allowlist deny-by-default, HMAC `sha256` + `compare_digest`, fine-grained PAT, OpenAI key only in Gateway, non-root containers, bridge network, no AgentOS bypass.

## Docs
- Architecture: `ControlCenter/docs/ARCHITECTURE.md` (also `/ARCHITECTURE.md`) — diagrams, deployment topology, directory layout.
- Install: `ControlCenter/docs/INSTALL.md` (also `/INSTALL.md`) — build, up, health, webhook test, troubleshooting.
- Security: `ControlCenter/docs/SECURITY.md` (also `/SECURITY.md`).
- Designs: `GITHUB_WEBHOOK_DESIGN.md`, `TELEGRAM_BOT_DESIGN.md`, `OPENAI_GATEWAY_DESIGN.md`.

## Tests

```bash
python ControlCenter/tests/test_stage1_structure.py -v
python AgentOS/tools/validate.py        # AgentOS invariants (0 ACTIVE lock)
python AgentOS/tests/test_agentos.py    # 11 checks still PASS (no trading touch)
```

## Non-Goals (Stage 1)
- No Telegram polling / webhook registration
- No `openai.OpenAI()` calls (Gateway `stub_handle` only)
- No GitHub API writes
- No mutation of `01_Source/EA/**` (frozen) or `AgentOS/**`
- No Arena/Kilo execution

## Stage 2 Preview
- Bot: `python-telegram-bot` Application + handlers + Gateway forward
- Gateway: OpenAI client + `SYSTEM_PROMPT_STAGE1` + tool execution + rate limit + confirmation
- Watcher: forward + Redis dedup + metrics + Telegram notify

---

*Stage 1 structure — 2026-09-15.*
