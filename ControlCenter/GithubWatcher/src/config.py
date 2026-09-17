"""QROS GithubWatcher — configuration (Stage 1: structure only)."""
from __future__ import annotations

from pydantic import Field
from pydantic_settings import BaseSettings


class WatcherSettings(BaseSettings):
    environment: str = Field(default="development", alias="ENVIRONMENT")
    log_level: str = Field(default="info", alias="LOG_LEVEL")
    port: int = Field(default=8082, alias="GITHUB_WEBHOOK_PORT")

    github_webhook_secret: str = Field(default="", alias="GITHUB_WEBHOOK_SECRET")
    github_token: str = Field(default="", alias="GITHUB_TOKEN")
    github_repo: str = Field(default="masudbek001-droid/QuantResearchOS", alias="GITHUB_REPO")
    github_api_url: str = Field(default="https://api.github.com", alias="GITHUB_API_URL")

    watcher_public_url: str = Field(default="", alias="WATCHER_PUBLIC_URL")
    gateway_internal_url: str = Field(default="http://gateway:8080", alias="GATEWAY_INTERNAL_URL")
    bot_internal_url: str = Field(default="http://bot:8081", alias="BOT_INTERNAL_URL")

    class Config:
        env_file = ".env"
        extra = "ignore"

    def validate_stage1(self) -> list[str]:
        missing = []
        if not self.github_webhook_secret:
            missing.append("GITHUB_WEBHOOK_SECRET")
        return missing
