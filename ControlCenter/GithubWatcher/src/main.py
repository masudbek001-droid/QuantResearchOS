"""
QROS GithubWatcher — main (Stage 1: structure only).

FastAPI app:
- GET /health, /ready, /
- POST /github/webhook  — verifies HMAC, logs event, returns 200 (no forwarding yet)

Stage 2: add idempotency store, forward to Gateway/Bot, emit metrics.
"""
from __future__ import annotations

import logging

from fastapi import FastAPI, Header, HTTPException, Request
import uvicorn

from src.config import WatcherSettings
from src.webhook import SUBSCRIBED_EVENTS_DESIGN, verify_signature

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [watcher] %(message)s")
log = logging.getLogger("qros.watcher")

settings = WatcherSettings()
app = FastAPI(title="QROS GithubWatcher (Stage 1)", version="1.0.0-stage1", description="GitHub webhook — Stage 1 verifies HMAC only.")


@app.get("/health")
def health():
    return {"service": "qros-github-watcher", "status": "ok", "stage": "1-structure", "version": "1.0.0-stage1"}


@app.get("/ready")
def ready():
    missing = settings.validate_stage1()
    return {
        "service": "qros-github-watcher",
        "ready": len(missing) == 0,
        "missing_env": missing,
        "github_repo": settings.github_repo,
        "subscribed_events": SUBSCRIBED_EVENTS_DESIGN,
        "public_url": settings.watcher_public_url or "(set WATCHER_PUBLIC_URL)",
        "environment": settings.environment,
    }


@app.get("/")
def root():
    return {
        "service": "qros-github-watcher",
        "stage": "1-structure",
        "pipeline": "GitHub → GithubWatcher → Gateway → Bot → Telegram",
        "webhook": "POST /github/webhook  (Header: X-Hub-Signature-256, X-GitHub-Event, X-GitHub-Delivery)",
        "subscribed_events": SUBSCRIBED_EVENTS_DESIGN,
        "docs": "ControlCenter/docs/GITHUB_WEBHOOK_DESIGN.md",
        "note": "Stage 1: verifies HMAC and logs, does not forward.",
    }


@app.post("/github/webhook")
async def github_webhook(
    request: Request,
    x_hub_signature_256: str | None = Header(default=None),
    x_github_event: str | None = Header(default=None),
    x_github_delivery: str | None = Header(default=None),
):
    raw = await request.body()
    # Verify HMAC (secure default: reject if secret not configured or signature missing)
    if not verify_signature(settings.github_webhook_secret, raw, x_hub_signature_256):
        log.warning("Webhook rejected — bad signature (event=%s delivery=%s)", x_github_event, x_github_delivery)
        raise HTTPException(status_code=401, detail="invalid signature")
    # Stage 1: log and acknowledge; no forwarding
    log.info("Webhook accepted — event=%s delivery=%s bytes=%d", x_github_event, x_github_delivery, len(raw))
    # Minimal parse for health (do not trust body without signature)
    return {
        "received": True,
        "event": x_github_event,
        "delivery": x_github_delivery,
        "stage": "1-structure",
        "forwarded": False,
        "note": "Stage 1: no forward to Gateway/Bot yet.",
    }


def main() -> None:
    missing = settings.validate_stage1()
    if missing:
        log.warning("Watcher Stage 1 missing env: %s", ", ".join(missing))
    else:
        log.info("Watcher config OK — repo=%s public_url=%s", settings.github_repo, settings.watcher_public_url or "(unset)")
    log.info("Starting QROS GithubWatcher stub on port %s", settings.port)
    uvicorn.run(app, host="0.0.0.0", port=settings.port, log_level="info")


if __name__ == "__main__":
    main()
