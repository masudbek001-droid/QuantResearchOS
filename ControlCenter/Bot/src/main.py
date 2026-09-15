"""
QROS Bot — main entry (Stage 1: structure only).

Purpose: remote project management — Telegram → Gateway → GitHub → AgentOS.
Stage 1 does NOT implement business logic, does NOT poll Telegram, does NOT mutate AgentOS.

What this stub does:
- Loads config via src.config.BotSettings
- Exposes FastAPI /health and /ready for Docker healthcheck / compose depends_on
- Validates required env without contacting Telegram/OpenAI/GitHub (offline-safe)
- Logs allowed commands design (see docs/TELEGRAM_BOT_DESIGN.md) but does not register handlers

Stage 2 will add: python-telegram-bot Application, allowlist auth, command handlers, Gateway forwarding.
"""
from __future__ import annotations

import logging
import os

from fastapi import FastAPI
import uvicorn

from src.config import BotSettings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [bot] %(message)s")
log = logging.getLogger("qros.bot")

settings = BotSettings()
app = FastAPI(title="QROS Bot (Stage 1)", version="1.0.0-stage1", description="Structure only — no Telegram polling yet.")


@app.get("/health")
def health():
    return {"service": "qros-bot", "status": "ok", "stage": "1-structure", "version": "1.0.0-stage1"}


@app.get("/ready")
def ready():
    missing = settings.validate_stage1()
    return {
        "service": "qros-bot",
        "ready": len(missing) == 0,
        "missing_env": missing,
        "allowed_users_configured": len(settings.allowed_user_ids_list),
        "gateway": settings.gateway_internal_url,
        "environment": settings.environment,
    }


@app.get("/")
def root():
    return {
        "service": "qros-bot",
        "stage": "1-structure",
        "pipeline": "Telegram → QROS Bot → OpenAI Gateway → GitHub → AgentOS → Arena+Kilo",
        "docs": ["ControlCenter/docs/TELEGRAM_BOT_DESIGN.md", "ControlCenter/docs/ARCHITECTURE.md"],
        "commands_design": ["/start", "/help", "/status", "/tasks", "/reports", "/events"],
        "note": "Stage 1: structure only — no business logic. See src/handlers/ for Stage 2 skeleton.",
    }


def main() -> None:
    missing = settings.validate_stage1()
    if missing:
        log.warning("Stage 1 config incomplete — missing: %s (expected for structure-only run)", ", ".join(missing))
    else:
        log.info("Bot config OK — allowed_users=%s gateway=%s", settings.allowed_user_ids_list, settings.gateway_internal_url)
    log.info("Starting QROS Bot stub on port %s (Stage 1: no Telegram polling)", settings.port)
    uvicorn.run(app, host="0.0.0.0", port=settings.port, log_level="info")


if __name__ == "__main__":
    main()
