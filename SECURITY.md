# QROS Control Center v1 — Security Model (Stage 1)

> **Stage 1: structure only — security model is design + env/verification stubs. No secrets in repo, no business logic yet.**

## 1. Threat Model

| Actor | Asset | Threat | Mitigation (Stage 1 design → Stage 2 enforcement) |
|---|---|---|---|
| Untrusted Telegram user | Bot control | Impersonation, command injection | Allowlist `TELEGRAM_ALLOWED_USER_IDS` at Bot entry; deny-by-default; log + drop; Telegram token never exposed |
| Internet | GitHub webhook | Forged webhook, replay | HMAC `sha256` with `GITHUB_WEBHOOK_SECRET` + `compare_digest`; 401 on fail; `X-GitHub-Delivery` idempotency (Stage 2: Redis) |
| Leaked env | `TELEGRAM_BOT_TOKEN`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, `GITHUB_WEBHOOK_SECRET` | Secret exfiltration | Secrets only via env/secret manager; `.env` gitignored; compose `env_file`; never logged; redacted in logs |
| Compromised Gateway | GitHub repo | Unauthorized writes | Token minimal scopes (fine-grained PAT, repo-limited, `repo` + `workflow` only if needed); Bot never holds GitHub token except Watcher/Gateway; all writes via GitHub API audit trail |
| Prompt injection | Gateway → tools | Malicious tool calls | System prompt forbids trading/core mutation, allowlists tools (`github_read_file`, etc.); Stage 2 confirms writes; rate limit per user |
| Container escape | Host | Privilege escalation | Non-root `appuser` (uid 1000), no privileged, bridge network `qros-control-net`, healthchecks, `unless-stopped` not `always` |

Out of scope: trading execution (frozen), MT5 runtime.

---

## 2. Secrets Management

### 2.1 Single Source
- `ControlCenter/.env.example` (and root `.env.example`, `ENV.example`, `ControlCenter/config/env.example` — copies) documents every var with placeholder values.
- Real values live in `.env` (gitignored) or a secret manager (e.g., Docker secrets, Vault, 1Password — operator chooses). Never commit `.env`.

### 2.2 Handling Rules
1. **Never** hardcode tokens/keys in code, Dockerfiles, compose, or logs.
2. Compose loads via `env_file: .env`; services read via `pydantic-settings` (`BotSettings`, `GatewaySettings`, `WatcherSettings`); missing required vars → `validate_stage1()` reports but does not crash (Stage 1 offline-safe).
3. Logs redact secrets: `TELEGRAM_BOT_TOKEN` never logged; `OPENAI_API_KEY` never forwarded to Bot/Watcher/Telegram; `GITHUB_TOKEN` never in webhook payload.
4. Rotation: rotate `GITHUB_WEBHOOK_SECRET` + webhook config + `GITHUB_TOKEN` together; restart `docker compose up -d --force-recreate`.

### 2.3 `.gitignore` Complement
Root `.gitignore` already ignores `*.log`, `__pycache__`, `.venv`. ControlCenter Stage 1 adds `.env` handling — ensure:
```gitignore
# QROS Control Center — secrets
.env
*.pem
*.key
```

Verify: `git check-ignore -v .env` should match (Stage 1 test checks).

---

## 3. Telegram Security

- **Allowlist:** `TELEGRAM_ALLOWED_USER_IDS` — comma-separated integers. Bot checks at handler entry before any forwarding:
  ```python
  if update.effective_user.id not in settings.allowed_user_ids_list: log.warning("deny", user_id=...); return
  ```
  Empty list = deny all (Stage 1 `validate_stage1` flags it).

- **Token:** `TELEGRAM_BOT_TOKEN` via `@BotFather`. Store only in `.env`. Never in code or Telegram messages. Stage 2 webhook verification (if using webhook mode) checks `X-Telegram-Bot-Api-Secret-Token` if configured.

- **Transport:** Stage 1: no polling, no webhook. Stage 2: long-polling (default, no public URL needed) or webhook (`TELEGRAM_WEBHOOK_URL` must be `https`, Telegram sets webhook with secret token). Both go through Bot → Gateway, never Bot → GitHub.

- **Logging:** only `telegram_user_id` + command name, never message content containing secrets.

---

## 4. GitHub Webhook Security

- **Verification:** `POST /github/webhook` requires `X-Hub-Signature-256: sha256=<hex>`. Handler:
  ```python
  expected = hmac.new(secret.encode(), raw_body, sha256).hexdigest()
  hmac.compare_digest(expected, provided)
  ```
  Constant-time, 401 on mismatch or missing header/secret.

- **Secret:** `GITHUB_WEBHOOK_SECRET` — 32+ random hex (`openssl rand -hex 32`). Must match GitHub repo → Settings → Webhooks → Secret. Rotate together.

- **Subscribed events (Stage 1 design):** `push`, `pull_request`, `pull_request_review`, `check_suite`, `check_run`, `workflow_run`. Minimal; no `*`.

- **Idempotency:** `X-GitHub-Delivery` (UUID per delivery). Stage 1 logs it; Stage 2 stores in Redis for 24h, dedups before forwarding to Gateway/Bot.

- **Token scopes:** `GITHUB_TOKEN` minimal. Prefer fine-grained PAT: repo `masudbek001-droid/QuantResearchOS` → Contents: Read+Write, Metadata: Read, Pull requests: Read+Write, Workflows: Read (Write only if triggering). No `admin`, no `delete_repo`. Gateway is the only holder that writes; Bot does not hold it (except Watcher for optional status).

- **Audit:** every webhook logs `event`, `delivery`, `bytes`, never payload secrets. GitHub provides delivery history in webhook settings for replay (with same signature).

Reference implementation: `ControlCenter/GithubWatcher/src/webhook.py::verify_signature`.

---

## 5. OpenAI Gateway Security

- **Key isolation:** `OPENAI_API_KEY` only in Gateway env. Never in Bot/Watcher, never in Telegram reply, never in GitHub commit. Gateway `validate_stage1` reports missing but never prints the key.

- **System prompt guard:** `SYSTEM_PROMPT_STAGE1` forbids trading/core mutation, mandates `GitHub-as-bus`, allowlists tools. Stage 2 will prepend it to every call and enforce function-call allowlist (`github_read_file`, `github_list_tasks`, `github_create_task`, `agentos_validate`). Any other tool → refused.

- **Rate limiting:** `GATEWAY_RATE_LIMIT_RPM` per `telegram_user_id` (Stage 2: token bucket, 429 on exceed). Prevents abuse / cost blowup.

- **Prompt injection defense:** Gateway treats Telegram text as untrusted data, not instruction. Tools are called only via OpenAI function calling, not by parsing user text directly. Stage 2 confirms writes (e.g., create task) with Telegram inline keyboard before executing.

- **Logging:** logs `telegram_user_id` + `tool_calls[]`, never prompts containing secrets.

---

## 6. Container & Network

- **Base:** `python:3.11-slim`, `appuser` non-root (uid 1000), copied code `ro`, `PIP_NO_CACHE_DIR=1`.
- **Network:** bridge `qros-control-net` (compose `name:`). No host networking. Services reach each other via DNS: `gateway`, `bot`, `github-watcher`.
- **Exposed ports:** `GATEWAY_PORT` (8080), `BOT_PORT` (8081), `GITHUB_WEBHOOK_PORT` (8082) — only webhook needs public reachability (via reverse proxy / tunnel). In prod, put Watcher behind TLS terminator (Traefik/Nginx/Cloudflare Tunnel), enforce HTTPS.
- **Healthchecks:** `GET /health` per service; compose `depends_on: service_healthy` for ordering.
- **Restart:** `unless-stopped` (not `always`).

---

## 7. AgentOS Invariant (Unmodified)

Control Center does **not** bypass AgentOS. Stage 1 verifies by test: no commit touches `AgentOS/**` except via GitHub API in Stage 2 (audited). The bot/gateway never write local `AgentOS/**` files; they create commits through GitHub, which is the single writer — preserving `AGENT_PROTOCOL.md` single-owner and Git-only bus.

---

## 8. Operations Checklist

- [ ] `cp .env.example .env` and fill `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USER_IDS`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, `GITHUB_WEBHOOK_SECRET` (never commit `.env`)
- [ ] `GITHUB_WEBHOOK_SECRET` → GitHub repo Settings → Webhooks → Add webhook → Payload URL `https://<public>/github/webhook` → Secret = same value → Events: let me select individual → check `push`, `pull requests`, `checks`, `workflow runs` → Active + SSL verification
- [ ] `GITHUB_TOKEN` → fine-grained PAT limited to `masudbek001-droid/QuantResearchOS`
- [ ] `docker compose config --quiet` → no warnings
- [ ] `curl http://localhost:8081/health && curl http://localhost:8080/health && curl http://localhost:8082/health` → all `{"status":"ok"}`
- [ ] Verify `.env` ignored: `git check-ignore -v .env`
- [ ] In prod: TLS for webhook, allowlist non-empty, logs contain no secrets

---

*Stage 1: model only. Stage 2 will add enforcement (Redis dedup, rate limiter, confirm dialogs, audit trail).*
