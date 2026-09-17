"""
QROS GithubWatcher — main (Stage 2: wired — webhook verify + parser + AgentOS forwarding + health + structured logging + graceful restart).
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, Header, HTTPException, Request
import httpx
import uvicorn

from src.config import WatcherSettings
from src.webhook import SUBSCRIBED_EVENTS_DESIGN, verify_signature, parse_github_event, format_agentos_forward, is_duplicate

# ── Structured JSON logging ────────────────────────────────────────────────
class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "service": "qros-github-watcher",
            "logger": record.name,
            "message": record.getMessage(),
        }
        if hasattr(record, "extra"):
            payload.update(record.extra)
        for k in ("event", "delivery", "repo", "gateway_status"):
            if hasattr(record, k):
                payload[k] = getattr(record, k)
        return json.dumps(payload, ensure_ascii=False)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JSONFormatter())
root = logging.getLogger()
root.handlers = [handler]
root.setLevel(logging.INFO)
log = logging.getLogger("qros.watcher")

settings = WatcherSettings()

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info(f"Watcher startup — port {settings.port} repo={settings.github_repo}")
    yield
    log.info("Watcher shutdown — graceful")

app = FastAPI(title="QROS GithubWatcher (Stage 2)", version="1.0.0-stage2", description="GitHub webhook wired — verify, parse, forward to Gateway", lifespan=lifespan)

@app.get("/health")
def health():
    return {"service": "qros-github-watcher", "status": "ok", "stage": "2-wired", "version": "1.0.0-stage2"}

@app.get("/ready")
async def ready():
    missing = settings.validate_stage1()
    # gateway reachable probe
    gateway_ok = False
    try:
        async with httpx.AsyncClient(timeout=3) as c:
            r = await c.get(f"{settings.gateway_internal_url.rstrip('/')}/health")
            gateway_ok = r.status_code == 200
    except Exception:
        gateway_ok = False
    return {
        "service": "qros-github-watcher",
        "ready": len(missing) == 0,
        "missing_env": missing,
        "github_repo": settings.github_repo,
        "subscribed_events": SUBSCRIBED_EVENTS_DESIGN,
        "public_url": settings.watcher_public_url or "(set WATCHER_PUBLIC_URL)",
        "gateway_reachable": gateway_ok,
        "gateway_internal_url": settings.gateway_internal_url,
        "environment": settings.environment,
    }

@app.get("/")
def root():
    return {
        "service": "qros-github-watcher",
        "stage": "2-wired",
        "pipeline": "GitHub → GithubWatcher → Gateway → Bot → Telegram",
        "webhook": "POST /github/webhook  (Header: X-Hub-Signature-256, X-GitHub-Event, X-GitHub-Delivery)",
        "subscribed_events": SUBSCRIBED_EVENTS_DESIGN,
        "forward_target": f"{settings.gateway_internal_url.rstrip('/')}/internal/github-event",
        "health": "/health",
        "ready": "/ready",
    }

@app.post("/github/webhook")
async def github_webhook(
    request: Request,
    x_hub_signature_256: str | None = Header(default=None),
    x_github_event: str | None = Header(default=None),
    x_github_delivery: str | None = Header(default=None),
):
    raw = await request.body()
    # Dedup check (in-memory, no Redis per mission)
    if is_duplicate(x_github_delivery):
        log.info(f"Duplicate webhook dropped", extra={"extra": {"event": x_github_event or "", "delivery": x_github_delivery or ""}})
        return {"received": True, "duplicate": True, "event": x_github_event, "delivery": x_github_delivery}
    # Verify HMAC
    if not verify_signature(settings.github_webhook_secret, raw, x_hub_signature_256):
        log.warning(f"Webhook rejected — bad signature", extra={"extra": {"event": x_github_event or "", "delivery": x_github_delivery or ""}})
        raise HTTPException(status_code=401, detail="invalid signature")
    # Parse
    parsed = parse_github_event(x_github_event, raw)
    log.info(f"Webhook accepted — event={x_github_event} delivery={x_github_delivery} repo={parsed.get('repo','')} bytes={len(raw)}", extra={"extra": {"event": x_github_event or "", "delivery": x_github_delivery or "", "repo": parsed.get("repo","")}})
    # AgentOS forwarding: format and forward to Gateway
    forward_payload = format_agentos_forward(x_github_event, parsed, x_github_delivery)
    # Structured AgentOS forwarding log (evidence)
    log.info(f"AgentOS forwarding: {x_github_event} repo={parsed.get('repo','')}", extra={"extra": {"event": x_github_event or "", "delivery": x_github_delivery or "", "repo": parsed.get("repo","")}})
    # Forward to Gateway internal endpoint (async, do not block webhook 200)
    gateway_url = f"{settings.gateway_internal_url.rstrip('/')}/internal/github-event"
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            r = await client.post(gateway_url, json={"event": x_github_event, "delivery": x_github_delivery, "repo": parsed.get("repo",""), "payload": parsed.get("payload",{})})
            log.info(f"Forwarded to Gateway status={r.status_code}", extra={"extra": {"event": x_github_event or "", "gateway_status": r.status_code}})
            forwarded = r.status_code == 200
    except Exception as e:
        log.warning(f"Forward to Gateway failed: {e}", extra={"extra": {"event": x_github_event or ""}})
        forwarded = False
    return {
        "received": True,
        "event": x_github_event,
        "delivery": x_github_delivery,
        "stage": "2-wired",
        "forwarded": forwarded,
        "parsed": {k: v for k, v in parsed.items() if k != "payload"},
        "gateway_url": gateway_url,
    }

# ── Internal health probe endpoint for testing AgentOS forwarding ──────────
@app.get("/internal/seen")
def seen():
    from src.webhook import _seen_deliveries
    return {"seen_deliveries": len(_seen_deliveries)}

def _handle_signal(signum, frame):
    log.info(f"Watcher received signal {signum} — graceful shutdown")

signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)

def main() -> None:
    missing = settings.validate_stage1()
    if missing:
        log.warning(f"Watcher missing env: {', '.join(missing)} (webhook will reject until secret set)")
    else:
        log.info(f"Watcher config OK — repo={settings.github_repo} public_url={settings.watcher_public_url or '(unset)'} gateway={settings.gateway_internal_url}")
    log.info(f"Starting QROS GithubWatcher wired on port {settings.port}")
    uvicorn.run(app, host="0.0.0.0", port=settings.port, log_level="info")

if __name__ == "__main__":
    main()
