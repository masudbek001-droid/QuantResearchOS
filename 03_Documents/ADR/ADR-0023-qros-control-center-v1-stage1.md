# ADR-0023: QROS Control Center v1 — Stage 1 Project Structure

## Status

Accepted. (Stage 1: structure only — 2026-09-15)

## Context

- QuantResearchOS has a Git-native collaboration layer (`AgentOS` v1.0, ADR-0021) and a Market Digital Twin `MOD-TWIN` (ADR-0022), both validated and frozen except via ADR. Trading core (`MIPS v1.0`) remains frozen.
- Requirement **MISSION-001** asks for a remote project management plane: `Telegram → QROS Bot → OpenAI Gateway → GitHub → AgentOS → Arena + Kilo`. Purpose is not trading, not AI advice — only project governance from anywhere.
- Existing AgentOS is Git-only (no Telegram bus) and enforces single-owner per `OWNERSHIP_MAP.md`. Control Center must be a client of AgentOS via GitHub, never a bypass.
- Stage 1 is explicitly **structure only**: Docker Compose, directory layout, env vars, READMEs, architecture diagrams, deployment guide, security model, webhook/bot/gateway designs — no business logic, no trading/AgentOS mutation.

## Decision

Implement **QROS Control Center v1 Stage 1** as a new top-level subsystem isolated from trading and AgentOS:

### Directory Layout
```
QuantResearchOS/
├── docker-compose.yml              # 3-service compose (gateway 8080, bot 8081, watcher 8082) + qros-control-net
├── .env.example / ENV.example      # single source for all env (also ControlCenter/.env.example, config/env.example)
├── ARCHITECTURE.md / SECURITY.md / INSTALL.md  # also ControlCenter/docs/*
├── ControlCenter/
│   ├── README.md, docker-compose.yml, .env.example
│   ├── docs/{ARCHITECTURE,SECURITY,INSTALL,ENV_VARS,GITHUB_WEBHOOK_DESIGN,TELEGRAM_BOT_DESIGN,OPENAI_GATEWAY_DESIGN}.md
│   ├── Bot/       Dockerfile, requirements.txt, src/{config.py,main.py,handlers/}, README.md
│   ├── Gateway/   Dockerfile, requirements.txt, src/{config.py,openai_client.py,main.py}, README.md
│   └── GithubWatcher/ Dockerfile, requirements.txt, src/{config.py,webhook.py,main.py}, README.md
│   └── tests/test_stage1_structure.py
├── Bot/ Gateway/ GithubWatcher/    # thin root wrappers pointing to ControlCenter/* (deliverable compliance)
```

### Services (Stage 1 stubs)
- **Bot** (`ControlCenter/Bot`): FastAPI stub `/health`, `/ready`, `/`; `BotSettings` validates `TELEGRAM_BOT_TOKEN` + allowlist `TELEGRAM_ALLOWED_USER_IDS` at entry; no polling, no Telegram call. Stage 2 will add `python-telegram-bot` Application, allowlist, `POST /v1/chat` forward.
- **Gateway** (`ControlCenter/Gateway`): FastAPI stub `/health`, `/ready`, `/v1/tools`, `POST /v1/chat` → `stub_handle` echo; `SYSTEM_PROMPT_STAGE1` + `TOOLS_DESIGN` (read file, list tasks, create task, validate) are design only; no `openai.OpenAI()` in Stage 1. Stage 2 adds client, rate limit, GitHub tool execution, confirm.
- **GithubWatcher** (`ControlCenter/GithubWatcher`): FastAPI stub `POST /github/webhook` verifies `X-Hub-Signature-256` via `hmac.compare_digest`, logs `X-GitHub-Delivery`; subscribed events design (`push`, `pull_request`, `check_suite`, `workflow_run`, etc.); no forward, no Redis in Stage 1. Stage 2 adds dedup + forward to Gateway/Bot.

### Configuration & Security
- Single `env_file: .env` via compose; `.env` gitignored (`.gitignore` adds `.env`, `*.pem`, `*.key`). All secrets via env, never code/logs.
- Telegram allowlist deny-by-default; GitHub webhook HMAC + idempotency (`X-GitHub-Delivery`); GitHub fine-grained PAT minimal scopes; OpenAI key only in Gateway; non-root `appuser`, bridge network, healthchecks, `unless-stopped`.
- AgentOS invariant preserved: Bot/Gateway never write `AgentOS/**` directly; GitHub is sole writer (Stage 2 via API), Watcher read-only.

### Non-Goals (Stage 1)
- No Telegram polling/webhook registration, no OpenAI calls, no GitHub writes, no AgentOS mutation, no trading logic, no Arena/Kilo execution.

## Consequences

- Stage 1 can be brought up: `cp .env.example .env && docker compose up -d && curl /health` → 3× `{"status":"ok","stage":"1-structure"}`; `python ControlCenter/tests/test_stage1_structure.py` PASS (17 checks). Compose file validates with `docker compose config`.
- All future business logic (Stage 2) will be additive behind these contracts — no file renames, no trading core touch, no AgentOS schema change.
- Control Center is documented (mermaid pipelines, deployment topology, env table, per-service READMEs, three design specs) and test-covered before any code execution.

## References

- MISSION-001 (Stage 1 deliverables: docker-compose.yml, ControlCenter/, Bot/, Gateway/, GithubWatcher/, README, INSTALL.md, ARCHITECTURE.md, SECURITY.md, ENV.example)
- AgentOS `AGENT_PROTOCOL.md` § Git-only bus, `OWNERSHIP_MAP.md` single-owner, `AgentOS/tools/validate.py` invariants
- ADR-0021 (AgentOS) + ADR-0022 (Twin) — frozen boundaries Control Center respects

