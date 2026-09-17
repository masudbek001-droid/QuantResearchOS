# OpenAI Gateway Design — QROS Control Center (Stage 1)

## 1. Goal
Single OpenAI entry for the Control Center. Bot never calls OpenAI; only Gateway does. Gateway translates Telegram natural language (forwarded by Bot as `POST /v1/chat`) into allowlisted GitHub/AgentOS tool calls. Not trading. Not AI advice.

## 2. Responsibilities

- Holds `OPENAI_API_KEY` exclusively (Bot/Watcher never see it).
- Enforces `SYSTEM_PROMPT_STAGE1` on every call.
- Exposes `POST /v1/chat` (Bot → Gateway) and `GET /v1/tools` (ops).
- Maps user text → function tools → GitHub API (and never local file writes).
- Rate-limits per `telegram_user_id`, caps tokens/temperature, audits.

## 3. System Prompt (Stage 1)

```text
You are QROS Control Center Gateway — remote project management for QuantResearchOS.

PURPOSE: Help the owner manage the project via Telegram. You route natural language to GitHub/AgentOS actions.
NOT trading. NOT AI trading advice. NOT autonomous trading.

ALLOWED:
- Read: PROJECT_STATUS, ROADMAP, TASK_QUEUE, REPORT_QUEUE, EVENT_BUS, GitHub branches/PRs/checks
- Write (Stage 2, allowlisted): create task, claim task (via GitHub commit to AgentOS queue), emit event

FORBIDDEN:
- Any modification to 01_Source/EA/** trading modules, 02_Databases schema, or AgentOS invariants except via the published AgentOS CLI protocol
- No Telegram bus for AgentOS — Git is the bus. You go through GitHub.

When unsure, return a clarifying question. Always log the telegram_user_id for audit.
```

See `ControlCenter/Gateway/src/openai_client.py::SYSTEM_PROMPT_STAGE1`.

## 4. Function Tools (Stage 1 design, Stage 2 wires)

| Tool | Description | Parameters | Safety |
|---|---|---|---|
| `github_read_file` | Read file at branch (e.g., `PROJECT_STATUS.md`, `AgentOS/TASK_QUEUE.md`) | `path: string`, `branch?: string` | Read-only, path allowlist (`*.md`, `AgentOS/**`, `01_Source/**` read) |
| `github_list_tasks` | List `TASK_QUEUE` with optional `status` filter | `status?: OPEN|DONE|...` | Read-only |
| `github_create_task` | Create AgentOS task (Stage 2 write) | `title`, `module` (MOD-*), `priority` | Write — requires Telegram allowlist + inline confirmation |
| `agentos_validate` | Semantics of `AgentOS/tools/validate.py` via GitHub checks / local mirror | — | Read-only |

Stage 1: `TOOLS_DESIGN` lists these; `GET /v1/tools` returns them; `POST /v1/chat` stub does not call OpenAI.

## 5. API — Stage 1 Stub

- `GET /health` → `{"service":"qros-gateway","status":"ok"}`
- `GET /ready` → `{"ready": bool, "missing_env": [...], "model": "...", "github_repo": "..."}`
- `GET /v1/tools` → `{"tools": [...], "system_prompt_preview": "..."}`
- `POST /v1/chat` → stub echo:
  ```
  Request:  {"telegram_user_id":123, "text":"status"}
  Response: {"reply":"[Stage 1 stub] Received from 123: status — ...","tool_calls":[],"audit_user_id":123}
  ```

Stage 2 `POST /v1/chat` will:
1. Rate-limit by `telegram_user_id` (`GATEWAY_RATE_LIMIT_RPM` token bucket → 429).
2. Call `openai.OpenAI(api_key, base_url).chat.completions.create(model, messages=[SYSTEM_PROMPT, user_text], tools=TOOLS_DESIGN, max_tokens, temperature)`.
3. If tool_calls, execute each via GitHub API (`GITHUB_TOKEN`, `GITHUB_REPO`, `GITHUB_API_URL`) with `telegram_user_id` audit, then second OpenAI call to summarize, then reply.

## 6. Safety Rails

- **Allowlist:** OpenAI may only emit tools in `TOOLS_DESIGN`; any other → Gateway rejects.
- **Write confirmation:** `github_create_task` (Stage 2) does not commit until Telegram user confirms via inline keyboard callback (second `POST /v1/chat` with `confirmed: true`).
- **Rate limit:** `GATEWAY_RATE_LIMIT_RPM` (default 20) per user; Gateway returns `429 {error:"rate_limited"}` → Bot replies `⏳ Too many requests, wait 60s.`
- **Token caps:** `OPENAI_MAX_TOKENS` + `OPENAI_TEMPERATURE` fixed; Gateway never forwards unbounded prompts.
- **Secrets:** Gateway logs `telegram_user_id` + `tool_calls[].name`, never `OPENAI_API_KEY` or message secrets.
- **Scope:** GitHub token is fine-grained PAT limited to `masudbek001-droid/QuantResearchOS`; no `admin` scope.

## 7. Configuration

From `.env` → `GatewaySettings`:
- `OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_BASE_URL`, `OPENAI_MAX_TOKENS`, `OPENAI_TEMPERATURE`
- `GITHUB_TOKEN`, `GITHUB_REPO`, `GITHUB_API_URL`
- `GATEWAY_PORT`, `GATEWAY_TIMEOUT_SECONDS`, `GATEWAY_RATE_LIMIT_RPM`

See `ControlCenter/Gateway/src/config.py` and `ControlCenter/docs/ENV_VARS.md`.

## 8. Reliability

- Gateway is stateless; scale via compose `replicas` (Stage 2: add `--scale gateway=2` behind a load balancer).
- Healthcheck: `GET /health` for compose `depends_on: service_healthy`.
- Timeout: `GATEWAY_TIMEOUT_SECONDS` for OpenAI + GitHub calls; on timeout Bot gets `502` and tells Telegram to retry.

## 9. Stage 1 vs Stage 2

| Stage 1 | Stage 2 |
|---|---|
| No `openai.OpenAI()`; `stub_handle` echo | Instantiates client, calls chat.completions, executes tools via GitHub API |
| `POST /v1/chat` → stub reply | Rate limit + OpenAI + tool loop + confirm + audit |
| `GET /v1/tools` design | Same, plus execution |

## 10. Local Test (offline)

```bash
curl -s http://localhost:8080/v1/tools | jq .tools
curl -s -X POST http://localhost:8080/v1/chat -H 'Content-Type: application/json' \
  -d '{"telegram_user_id":123,"text":"status"}' | jq .reply
# → "[Stage 1 stub] Received from 123: status — Gateway not yet wired ..."
```

See `ControlCenter/Gateway/src/openai_client.py` and `src/main.py`.
