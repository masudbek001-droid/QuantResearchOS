# QROS Gateway — OpenAI Router (Stage 1)

**Stage 1: structure only — no OpenAI calls, no GitHub writes.**

## Purpose
`Telegram → QROS Bot → OpenAI Gateway → GitHub → AgentOS → Arena+Kilo`. The Gateway is the only component that talks to OpenAI. The Bot forwards Telegram messages here; the Gateway translates natural language into allowlisted GitHub/AgentOS tool calls.

## Layout
```
Gateway/
├── Dockerfile
├── requirements.txt        # fastapi, uvicorn, openai, httpx
├── src/
│   ├── config.py           # GatewaySettings (env, validate_stage1)
│   ├── openai_client.py    # SYSTEM_PROMPT_STAGE1 + TOOLS_DESIGN + stub_handle
│   └── main.py             # FastAPI stub (/health, /ready, /v1/chat, /v1/tools)
└── README.md
```

## Configuration
From `ControlCenter/.env.example`:
- `OPENAI_API_KEY`, `OPENAI_MODEL` (default `gpt-4o-mini`), `OPENAI_BASE_URL`
- `GITHUB_TOKEN`, `GITHUB_REPO`, `GITHUB_API_URL`
- `GATEWAY_PORT`, `GATEWAY_RATE_LIMIT_RPM`

Ready check (offline, no network):
```bash
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/v1/tools
curl -X POST http://localhost:8080/v1/chat -H 'Content-Type: application/json' \
  -d '{"telegram_user_id":123,"text":"status"}'
```

## OpenAI Gateway Design (Stage 1 spec)
Full spec: `ControlCenter/docs/OPENAI_GATEWAY_DESIGN.md`

- **System prompt**: remote project management only; explicitly forbids trading/AI advice and direct AgentOS file writes; all state via GitHub.
- **Function tools design** (not wired yet): `github_read_file`, `github_list_tasks`, `github_create_task`, `agentos_validate` — Stage 2 will execute them via GitHub API with the user's allowlist and an audit trail.
- **Safety**: rate limit per `telegram_user_id`, max tokens/temperature capped, token never logged, all tool calls require allowlist + confirmation for writes.
- **Observability**: every request logs `telegram_user_id` + tool name, never the OpenAI key or Telegram token.

## Docker
```bash
docker build -t qros/gateway:stage1 ./ControlCenter/Gateway
docker run --env-file .env -p 8080:8080 qros/gateway:stage1
```

## Stage 1 Non-Goals
- No `openai.OpenAI()` instantiation
- No GitHub API calls
- No AgentOS mutation

Stage 2 wires the client, adds rate limiting, and maps `POST /v1/chat` → OpenAI → tool execution → reply.
