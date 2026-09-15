"""QROS Bot — configuration (Stage 1: structure only, no secrets in code)."""
from __future__ import annotations

import os
from typing import List

from pydantic import Field
from pydantic_settings import BaseSettings


class BotSettings(BaseSettings):
    """Typed settings loaded from env / .env. All secrets via env, never hardcoded."""

    # Core
    environment: str = Field(default="development", alias="ENVIRONMENT")
    log_level: str = Field(default="info", alias="LOG_LEVEL")
    port: int = Field(default=8081, alias="BOT_PORT")

    # Telegram
    telegram_bot_token: str = Field(default="", alias="TELEGRAM_BOT_TOKEN")
    telegram_allowed_user_ids: str = Field(default="", alias="TELEGRAM_ALLOWED_USER_IDS")
    telegram_webhook_url: str = Field(default="", alias="TELEGRAM_WEBHOOK_URL")
    telegram_api_url: str = Field(default="https://api.telegram.org", alias="TELEGRAM_API_URL")

    # Downstream
    gateway_internal_url: str = Field(default="http://gateway:8080", alias="GATEWAY_INTERNAL_URL")
    github_repo: str = Field(default="masudbek001-droid/QuantResearchOS", alias="GITHUB_REPO")

    class Config:
        env_file = ".env"
        extra = "ignore"

    @property
    def allowed_user_ids_list(self) -> List[int]:
        if not self.telegram_allowed_user_ids.strip():
            return []
        return [int(x.strip()) for x in self.telegram_allowed_user_ids.split(",") if x.strip().isdigit()]

    def validate_stage1(self) -> list[str]:
        """Return list of missing required vars (Stage 1: config validation only, no Telegram call)."""
        missing = []
        if not self.telegram_bot_token:
            missing.append("TELEGRAM_BOT_TOKEN")
        if not self.allowed_user_ids_list:
            missing.append("TELEGRAM_ALLOWED_USER_IDS (at least one)")
        if not self.gateway_internal_url:
            missing.append("GATEWAY_INTERNAL_URL")
        return missing
