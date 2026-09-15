# QROS GithubWatcher — GitHub Webhook Receiver (Stage 1)

**Stage 1: structure only — verifies HMAC, does not forward.**

## Purpose
`GitHub → GithubWatcher → Gateway → Bot → Telegram`. Watcher is the inbound edge from GitHub: it receives webhooks, verifies `X-Hub-Signature-256`, deduplicates by `X-GitHub-Delivery`, and (Stage 2) forwards minimal events to Gateway/Bot.

## Layout
```
GithubWatcher/
├── Dockerfile
├── requirements.txt        # fastapi, uvicorn, httpx
├── src/
│   ├── config.py           # WatcherSettings
│   ├── webhook.py          # verify_signature, SUBSCRIBED_EVENTS_DESIGN, ROUTING_DESIGN
│   └── main.py             # FastAPI stub (/health, /ready, POST /github/webhook)
└── README.md
```

## Configuration
From `ControlCenter/.env.example`:
- `GITHUB_WEBHOOK_SECRET` — random 32+ hex, must match GitHub webhook config
- `GITHUB_TOKEN`, `GITHUB_REPO`, `GITHUB_API_URL`
- `WATCHER_PUBLIC_URL` — `https://<public>/github/webhook` (use ngrok/tunnel for dev)
- `GATEWAY_INTERNAL_URL`, `BOT_INTERNAL_URL`

Ready (offline):
```bash
curl http://localhost:8082/health
curl http://localhost:8082/ready
```

Test HMAC (offline):
```bash
python - <<'PY'
from ControlCenter.GithubWatcher.src.webhook import verify_signature
import hmac, hashlib
secret="test"; body=b'{}'; sig="sha256="+hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
print(verify_signature(secret, body, sig))  # True
PY
```

## GitHub Webhook Design (Stage 1 spec)
Full spec: `ControlCenter/docs/GITHUB_WEBHOOK_DESIGN.md`

- **Endpoint**: `POST /github/webhook` (FastAPI), headers `X-Hub-Signature-256`, `X-GitHub-Event`, `X-GitHub-Delivery`.
- **Subscribed events design**: `push`, `pull_request`, `pull_request_review`, `check_suite`, `check_run`, `workflow_run` (Stage 1 lists; Stage 2 subscribes).
- **Security**: HMAC SHA-256 with `GITHUB_WEBHOOK_SECRET` via `hmac.compare_digest`; reject on missing/invalid signature (401).
- **Idempotency**: `X-GitHub-Delivery` is dedup key; Stage 1 logs it, Stage 2 stores in Redis for 24h.
- **Routing design** (Stage 2): `push` → invalidate AgentOS cache, `pull_request/check_suite` → Gateway summary → Telegram notify.

## Docker
```bash
docker build -t qros/github-watcher:stage1 ./ControlCenter/GithubWatcher
docker run --env-file .env -p 8082:8082 qros/github-watcher:stage1
curl -X POST http://localhost:8082/github/webhook -H 'X-Hub-Signature-256: sha256=...' -d '{}'
```

## Stage 1 Non-Goals
- No forwarding to Gateway/Bot
- No Redis/dedup store
- No GitHub API calls

Stage 2 adds forward + dedup + metrics.
