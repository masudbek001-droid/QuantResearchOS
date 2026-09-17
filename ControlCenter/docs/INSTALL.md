# QROS Control Center v1 — Install & Deployment (Stage 1)

> **Stage 1: structure only.** Follow this guide to bring up the compose stack with health-only stubs (no Telegram polling, no OpenAI calls, no GitHub writes). All services respond on `/health` — real logic is Stage 2.

---

## 1. Prerequisites

| Requirement | Version | Check |
|---|---|---|
| Docker | ≥ 24 + Compose v2 (`docker compose`) | `docker --version && docker compose version` |
| Git | any | `git --version` |
| Telegram Bot token | from @BotFather | `TELEGRAM_BOT_TOKEN` |
| OpenAI API key | sk-proj-... | `OPENAI_API_KEY` |
| GitHub PAT | fine-grained or classic | `GITHUB_TOKEN` with `repo` (Stage 1 read, Stage 2 write) |
| Public URL for webhook (prod) | https | ngrok / Cloudflare Tunnel / reverse proxy for `POST /github/webhook` |
| Ports free | 8080, 8081, 8082 | `lsof -i :8080` etc. |

No MT5/MetaEditor, no Windows.

---

## 2. Clone & Branch

```bash
git clone https://github.com/masudbek001-droid/QuantResearchOS.git
cd QuantResearchOS
git fetch origin
git checkout arena/01a0a3b5-quantresearchos
git status  # 0 Active lock expected after Stage 1
```

---

## 3. Environment

```bash
cp .env.example .env        # also available as ENV.example, ControlCenter/.env.example
# edit .env — fill the 5 secrets:
# TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_IDS, OPENAI_API_KEY, GITHUB_TOKEN, GITHUB_WEBHOOK_SECRET

# Minimal .env for local health checks (stubs work without real secrets, but /ready will report missing):
cat .env | grep -E "TELEGRAM|OPENAI|GITHUB"

# Verify .env is ignored (must not be committed):
git check-ignore -v .env
# → .gitignore:.env  (OK)
```

Secret generation helper:
```bash
openssl rand -hex 32   # → paste into GITHUB_WEBHOOK_SECRET
```

---

## 4. Validate Compose (offline, no build)

```bash
docker compose config --quiet && echo "compose OK"
docker compose config | grep -E "service|image|ports" | head -n 30
```

---

## 5. Build & Up (Stage 1 stubs)

```bash
docker compose build
docker compose up -d

# Wait for healthchecks (15–20s):
docker compose ps
docker compose logs -f  # Ctrl-C to detach

# Health probes (all should return {"status":"ok"}):
curl -s http://localhost:8080/health | jq  # gateway
curl -s http://localhost:8081/health | jq  # bot
curl -s http://localhost:8082/health | jq  # watcher

# Readiness (reports missing env without crashing):
curl -s http://localhost:8080/ready | jq
curl -s http://localhost:8081/ready | jq
curl -s http://localhost:8082/ready | jq
```

Expected Stage 1 readiness (with placeholders): `ready: false`, `missing_env: ["TELEGRAM_BOT_TOKEN", ...]` — the stubs still return `200` and log a warning, which is correct for structure-only.

---

## 6. Verify Stage 1 Structure (tests)

```bash
python ControlCenter/tests/test_stage1_structure.py
# or full suite
python AgentOS/tools/validate.py
python AgentOS/tests/test_agentos.py    # 1:1 workers, no Telegram bus, etc.
python 01_Source/Tests/test_market_digital_twin.py  # twin still PASS
```

---

## 7. GitHub Webhook (optional for Stage 1)

Stage 1 Watcher verifies HMAC but does not forward — you can test it without a public URL.

### Local test (no public URL needed)
```bash
python - <<'PY'
import hmac, hashlib, urllib.request, json
secret = open(".env").read().split("GITHUB_WEBHOOK_SECRET=")[1].splitlines()[0].strip()
body = json.dumps({"zen":"test"}).encode()
sig = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
req = urllib.request.Request("http://localhost:8082/github/webhook", data=body, headers={
  "X-Hub-Signature-256": sig,
  "X-GitHub-Event": "ping",
  "X-GitHub-Delivery": "test-123",
  "Content-Type": "application/json"
})
print(urllib.request.urlopen(req, timeout=5).read().decode())
PY
# → {"received":true,"event":"ping", ...}
```

### Prod webhook registration
1. `GITHUB_WEBHOOK_SECRET` → `.env` (already set).
2. Expose Watcher publicly: `https://<your-host>/github/webhook` (via Cloudflare Tunnel, Traefik, or ngrok `ngrok http 8082`).
3. GitHub → repo → Settings → Webhooks → Add webhook:
   - Payload URL: `https://<your-host>/github/webhook`
   - Content type: `application/json`
   - Secret: same as `GITHUB_WEBHOOK_SECRET`
   - Events: *Let me select individual* → `Pushes`, `Pull requests`, `Check suites`, `Check runs`, `Workflow runs`
   - Active: ✓, SSL verification: Enable
4. Click *Recent Deliveries* → Redeliver a `ping` → Watcher logs `Webhook accepted`.

No ngrok/TLS in dev — local `curl` above suffices for Stage 1.

---

## 8. Telegram & OpenAI (Stage 1: not wired)

- **Telegram:** Stage 1 Bot does not poll. Stage 2 will: `@BotFather` → `/newbot` → token → `.env` `TELEGRAM_BOT_TOKEN` → `TELEGRAM_ALLOWED_USER_IDS=your_id` (get via `@userinfobot`). The Bot's `/ready` will confirm allowlist.
- **OpenAI:** Stage 1 Gateway does not call OpenAI. Stage 2: `OPENAI_API_KEY` + `OPENAI_MODEL=gpt-4o-mini`. Test Stage 1 stub: `curl -X POST http://localhost:8080/v1/chat -H 'Content-Type: application/json' -d '{"telegram_user_id":123,"text":"status"}'`.

---

## 9. Stop & Clean

```bash
docker compose down
docker compose down -v  # also remove qros-control-logs volume
docker compose logs bot gateway github-watcher  # last logs if needed
```

---

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `docker compose config` → `variable is not set` | `cp .env.example .env` and fill values; compose uses defaults but `TELEGRAM_*` etc. need real values for Stage 2 |
| `8080 already in use` | `lsof -i :8080` then `PORT` override: `GATEWAY_PORT=18080 docker compose up -d` |
| `/ready` shows `missing_env` | Expected for placeholders. Fill `.env`; no crash is correct for Stage 1 |
| Watcher `401 invalid signature` | `GITHUB_WEBHOOK_SECRET` mismatch between `.env` and GitHub webhook settings, or body was modified by proxy |
| `git check-ignore` silent | Add `.env` to `.gitignore` (already added by Stage 1) |
| Tests fail: missing `ControlCenter/**` | Ensure you are on `arena/01a0a3b5-quantresearchos` and have pulled; run `python ControlCenter/tests/test_stage1_structure.py -v` |

---

## 11. Stage 1 → Stage 2 Hand-off

Stage 1 is complete when:
- `docker compose build && docker compose up -d` → 3× `health ok`
- `python ControlCenter/tests/test_stage1_structure.py` → PASS
- No `01_Source/EA/**` or `AgentOS/**` mutation (check `git diff --stat HEAD`)

Stage 2 (not in this PR) will: wire `python-telegram-bot` polling, `openai.OpenAI()` with `SYSTEM_PROMPT_STAGE1`, GitHub API writes, Redis dedup, and Telegram command handlers.

---

*Questions: see `ControlCenter/docs/ARCHITECTURE.md` and `ControlCenter/docs/SECURITY.md`.*
