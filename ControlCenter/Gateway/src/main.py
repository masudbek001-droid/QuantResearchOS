"""
QROS Gateway — main (Stage 1: structure only).

Exposes FastAPI:
- GET /health, /ready
- POST /v1/chat  (stub — echoes, no OpenAI call)
- GET /v1/tools  (lists designed function tools)

Stage 2 will add: OpenAI client with SYSTEM_PROMPT_STAGE1, rate limiting, GitHub tool execution.
"""
from __future__ import annotations

import logging

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

from src.config import GatewaySettings
from src.openai_client import SYSTEM_PROMPT_STAGE1, TOOLS_DESIGN, GatewayRequest, stub_handle

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [gateway] %(message)s")
log = logging.getLogger("qros.gateway")

settings = GatewaySettings()
app = FastAPI(title="QROS Gateway (Stage 1)", version="1.0.0-stage1", description="OpenAI routing — Stage 1 structure only.")


class ChatIn(BaseModel):
    telegram_user_id: int
    text: str
    context: dict | None = None


@app.get("/health")
def health():
    return {"service": "qros-gateway", "status": "ok", "stage": "1-structure", "version": "1.0.0-stage1"}


@app.get("/ready")
def ready():
    missing = settings.validate_stage1()
    return {
        "service": "qros-gateway",
        "ready": len(missing) == 0,
        "missing_env": missing,
        "model": settings.openai_model,
        "github_repo": settings.github_repo,
        "environment": settings.environment,
    }


@app.get("/v1/tools")
def tools():
    return {"service": "qros-gateway", "stage": "1-structure", "system_prompt_preview": SYSTEM_PROMPT_STAGE1[:300] + "...", "tools": TOOLS_DESIGN}


@app.post("/v1/chat")
def chat(body: ChatIn):
    if not body.text or not body.text.strip():
        raise HTTPException(status_code=400, detail="text required")
    # Stage 1: no OpenAI call, no GitHub call
    req = GatewayRequest(telegram_user_id=body.telegram_user_id, text=body.text, context=body.context)
    resp = stub_handle(req)
    return {"reply": resp.reply_text, "tool_calls": resp.tool_calls, "audit_user_id": resp.audit_user_id, "stage": "1-stub"}


@app.get("/")
def root():
    return {
        "service": "qros-gateway",
        "stage": "1-structure",
        "pipeline": "Telegram → Bot → Gateway → GitHub → AgentOS",
        "endpoints": ["/health", "/ready", "/v1/chat", "/v1/tools"],
        "docs": "ControlCenter/docs/OPENAI_GATEWAY_DESIGN.md",
        "note": "No OpenAI network calls in Stage 1. Set OPENAI_API_KEY for Stage 2 readiness.",
    }


def main() -> None:
    missing = settings.validate_stage1()
    if missing:
        log.warning("Gateway Stage 1 missing env: %s", ", ".join(missing))
    else:
        log.info("Gateway config OK — model=%s repo=%s", settings.openai_model, settings.github_repo)
    log.info("Starting QROS Gateway stub on port %s", settings.port)
    uvicorn.run(app, host="0.0.0.0", port=settings.port, log_level="info")


if __name__ == "__main__":
    main()
