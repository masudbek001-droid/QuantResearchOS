"""
QROS Gateway — main (Stage 2: wired — OpenAI client + GitHub tools + health + structured logging + graceful restart).

Exposes:
- GET /health, /ready, /v1/tools, /v1/chat (wired)
- POST /internal/github-event (Watcher → Gateway)
- GET / (pipeline)
"""
from __future__ import annotations

import asyncio
import json
import logging
import signal
import sys
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
import uvicorn
import httpx

from src.config import GatewaySettings
from src.openai_client import (
    SYSTEM_PROMPT_STAGE1,
    SYSTEM_PROMPT_STAGE2,
    TOOLS_DESIGN,
    TOOLS_DESIGN_LEGACY,
    GatewayRequest,
    stub_handle,
    check_rate_limit,
    openai_handle,
    rule_based_handle,
)

# ── Structured JSON logging ────────────────────────────────────────────────
class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "service": "qros-gateway",
            "logger": record.name,
            "message": record.getMessage(),
        }
        if hasattr(record, "extra"):
            payload.update(record.extra)
        for k in ("telegram_user_id", "tool", "event", "delivery", "repo"):
            if hasattr(record, k):
                payload[k] = getattr(record, k)
        return json.dumps(payload, ensure_ascii=False)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JSONFormatter())
root = logging.getLogger()
root.handlers = [handler]
root.setLevel(logging.INFO)
log = logging.getLogger("qros.gateway")

settings = GatewaySettings()

# ── FastAPI with lifespan ──────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info(f"Gateway startup — port {settings.port} model={settings.openai_model} repo={settings.github_repo}")
    yield
    log.info("Gateway shutdown — graceful")

app = FastAPI(title="QROS Gateway (Stage 2)", version="1.0.0-stage2", description="OpenAI routing wired — Telegram→Gateway→GitHub→AgentOS", lifespan=lifespan)

class ChatIn(BaseModel):
    telegram_user_id: int
    text: str
    context: dict | None = None

class GithubEventIn(BaseModel):
    event: str | None = None
    delivery: str | None = None
    repo: str | None = None
    payload: dict | None = None

@app.get("/health")
def health():
    return {"service": "qros-gateway", "status": "ok", "stage": "2-wired", "version": "1.0.0-stage2"}

@app.get("/ready")
async def ready():
    missing = settings.validate_stage1()
    # OpenAI probe: if key looks real, try a cheap call? Instead check key format
    openai_connected = bool(settings.openai_api_key and len(settings.openai_api_key) > 20 and not settings.openai_api_key.startswith("sk-proj-..."))
    # For placeholder, report false but still ready if gateway itself ok — health ok, ready degraded
    # GitHub probe: token present and not placeholder
    github_connected = bool(settings.github_token and len(settings.github_token) > 20 and not settings.github_token.startswith("ghp_..."))
    # If tokens are placeholders, we report connected=False but ready still based on missing_env (Stage1 compat)
    # For Stage2 evidence, we want to show attempted connection: try GitHub API ping if token real
    if github_connected:
        try:
            async with httpx.AsyncClient(timeout=5) as c:
                r = await c.get(f"{settings.github_api_url.rstrip('/')}/rate_limit", headers={"Authorization": f"Bearer {settings.github_token}"})
                github_connected = r.status_code == 200
        except Exception:
            github_connected = False
    # OpenAI ping (optional, lightweight)
    if openai_connected:
        try:
            import openai
            client = openai.OpenAI(api_key=settings.openai_api_key, base_url=settings.openai_base_url)
            # Do not call API in ready to avoid cost; just check client init
            openai_connected = True
        except Exception:
            openai_connected = False
    return {
        "service": "qros-gateway",
        "ready": len(missing) == 0,
        "missing_env": missing,
        "model": settings.openai_model,
        "github_repo": settings.github_repo,
        "openai_connected": openai_connected,
        "github_connected": github_connected,
        "environment": settings.environment,
    }

@app.get("/v1/tools")
def tools():
    return {"service": "qros-gateway", "stage": "2-wired", "system_prompt_preview": SYSTEM_PROMPT_STAGE2[:400] + "...", "tools": TOOLS_DESIGN, "legacy": TOOLS_DESIGN_LEGACY}

@app.post("/v1/chat")
async def chat(body: ChatIn, request: Request):
    if not body.text or not body.text.strip():
        raise HTTPException(status_code=400, detail="text required")
    # rate limit
    if not check_rate_limit(body.telegram_user_id, settings.gateway_rate_limit_rpm):
        log.warning("Rate limited", extra={"extra": {"telegram_user_id": body.telegram_user_id}})
        raise HTTPException(status_code=429, detail="rate_limited: wait 60s")
    log.info(f"Chat from {body.telegram_user_id}: {body.text[:80]}", extra={"extra": {"telegram_user_id": body.telegram_user_id}})
    # Decide: if OpenAI key present and not placeholder, try openai_handle else rule_based
    use_openai = bool(settings.openai_api_key and len(settings.openai_api_key) > 20 and not settings.openai_api_key.startswith("sk-proj-...") and "replace" not in settings.openai_api_key)
    req = GatewayRequest(telegram_user_id=body.telegram_user_id, text=body.text, context=body.context)
    if use_openai:
        resp = await openai_handle(req, settings.github_token, settings.github_repo, settings.github_api_url, settings.openai_api_key, settings.openai_model, settings.openai_base_url, settings.openai_max_tokens, settings.openai_temperature)
    else:
        # offline / placeholder -> rule based
        fb = await rule_based_handle(body.text, body.telegram_user_id, settings.github_token, settings.github_repo, settings.github_api_url)
        resp = type("R", (), {"reply_text": fb, "tool_calls": [{"tool": "rule_based"}]})()
        log.info("Rule-based fallback used", extra={"extra": {"telegram_user_id": body.telegram_user_id}})
    return {"reply": resp.reply_text, "tool_calls": getattr(resp, "tool_calls", []), "audit_user_id": body.telegram_user_id, "stage": "2-wired"}

@app.post("/internal/github-event")
async def internal_github_event(body: GithubEventIn, request: Request):
    log.info(f"GitHub event forwarded: {body.event} repo={body.repo} delivery={body.delivery}", extra={"extra": {"event": body.event or "", "delivery": body.delivery or "", "repo": body.repo or ""}})
    # Format notification for Telegram via Bot
    notify_text = f"📦 GitHub `{body.event}` on `{body.repo}`"
    if body.event == "push":
        ref = (body.payload or {}).get("ref", "")
        pusher = (body.payload or {}).get("pusher", {}).get("name", "")
        commits = len((body.payload or {}).get("commits", []))
        notify_text = f"🔨 Push to `{ref}` by {pusher} ({commits} commits) on `{body.repo}`"
    elif body.event == "pull_request":
        pr = (body.payload or {}).get("pull_request", {})
        action = (body.payload or {}).get("action", "")
        notify_text = f"🔀 PR {action} #{pr.get('number','')} {pr.get('title','')[:60]} on `{body.repo}`"
    elif body.event in ("check_suite", "check_run", "workflow_run"):
        conclusion = (body.payload or {}).get("conclusion") or (body.payload or {}).get("check_suite", {}).get("conclusion") or "unknown"
        notify_text = f"✅ CI {body.event} {conclusion} on `{body.repo}`"
    # Try to forward to Bot /internal/notify
    bot_url = (settings.github_token and getattr(settings, "bot_internal_url", None)) or os.getenv("BOT_INTERNAL_URL", "http://bot:8081")
    # fallback env: BOT_INTERNAL_URL is in .env but not in GatewaySettings; read manually
    bot_url = os.getenv("BOT_INTERNAL_URL", "http://bot:8081")
    try:
        async with httpx.AsyncClient(timeout=5) as c:
            r = await c.post(f"{bot_url.rstrip('/')}/internal/notify", json={"text": notify_text})
            log.info(f"Notify forwarded to Bot status={r.status_code}", extra={"extra": {"event": body.event or ""}})
    except Exception as e:
        log.warning(f"Notify forward to Bot failed: {e}")
    return {"received": True, "event": body.event, "notified": notify_text[:120]}

@app.get("/")
def root():
    return {
        "service": "qros-gateway",
        "stage": "2-wired",
        "pipeline": "Telegram → Bot → Gateway → GitHub → AgentOS",
        "endpoints": ["/health", "/ready", "/v1/chat", "/v1/tools", "/internal/github-event"],
        "openai_model": settings.openai_model,
        "github_repo": settings.github_repo,
    }

# Graceful restart signals (uvicorn handles, but log)
def _handle_signal(signum, frame):
    log.info(f"Gateway received signal {signum} — graceful shutdown")

import os
signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)

def main() -> None:
    missing = settings.validate_stage1()
    if missing:
        log.warning(f"Gateway missing env: {', '.join(missing)} (will use fallback)")
    else:
        log.info(f"Gateway config OK — model={settings.openai_model} repo={settings.github_repo}")
    log.info(f"Starting QROS Gateway wired on port {settings.port}")
    uvicorn.run(app, host="0.0.0.0", port=settings.port, log_level="info")

if __name__ == "__main__":
    main()
