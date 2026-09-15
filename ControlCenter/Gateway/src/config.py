"""QROS Gateway — configuration (Stage 1: structure only)."""
from __future__ import annotations

from pydantic import Field
from pydantic_settings import BaseSettings


class GatewaySettings(BaseSettings):
    environment: str = Field(default="development", alias="ENVIRONMENT")
    log_level: str = Field(default="info", alias="LOG_LEVEL")
    port: int = Field(default=8080, alias="GATEWAY_PORT")

    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY")
    openai_model: str = Field(default="gpt-4o-mini", alias="OPENAI_MODEL")
    openai_base_url: str = Field(default="https://api.openai.com/v1", alias="OPENAI_BASE_URL")
    openai_max_tokens: int = Field(default=2048, alias="OPENAI_MAX_TOKENS")
    openai_temperature: float = Field(default=0.2, alias="OPENAI_TEMPERATURE")
    gateway_timeout_seconds: int = Field(default=30, alias="GATEWAY_TIMEOUT_SECONDS")
    gateway_rate_limit_rpm: int = Field(default=20, alias="GATEWAY_RATE_LIMIT_RPM")

    github_token: str = Field(default="", alias="GITHUB_TOKEN")
    github_repo: str = Field(default="masudbek001-droid/QuantResearchOS", alias="GITHUB_REPO")
    github_api_url: str = Field(default="https://api.github.com", alias="GITHUB_API_URL")

    class Config:
        env_file = ".env"
        extra = "ignore"

    def validate_stage1(self) -> list[str]:
        missing = []
        if not self.openai_api_key:
            missing.append("OPENAI_API_KEY")
        if not self.github_token:
            missing.append("GITHUB_TOKEN (for future GitHub→AgentOS bridge)")
        return missing
