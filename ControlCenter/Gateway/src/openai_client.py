"""
QROS Gateway — OpenAI client stub (Stage 1: structure only).

Stage 1: no network calls. Defines the interface Stage 2 will implement:
- System prompt (remote project management, not trading, not AI advice)
- Function tools (GitHub read/write, AgentOS queue read) — allowlisted
- Safety rails (no trading/core mutation, no AgentOS bypass)

Stage 2 implementation will:
- Instantiate openai.OpenAI(api_key, base_url)
- Enforce rate limit per telegram_user_id
- Map natural language → tool calls → GitHub API (and never local file writes)
"""
from __future__ import annotations

from dataclasses import dataclass


SYSTEM_PROMPT_STAGE1 = """You are QROS Control Center Gateway — remote project management for QuantResearchOS.

PURPOSE: Help the owner manage the project via Telegram. You route natural language to GitHub/AgentOS actions.
NOT trading. NOT AI trading advice. NOT autonomous trading.

ALLOWED:
- Read: PROJECT_STATUS, ROADMAP, TASK_QUEUE, REPORT_QUEUE, EVENT_BUS, GitHub branches/PRs/checks
- Write (Stage 2, allowlisted): create task, claim task (via GitHub commit to AgentOS queue), emit event

FORBIDDEN:
- Any modification to 01_Source/EA/** trading modules, 02_Databases schema, or AgentOS invariants except via the published AgentOS CLI protocol
- No Telegram bus for AgentOS — Git is the bus. You go through GitHub.

When unsure, return a clarifying question. Always log the telegram_user_id for audit.
"""

# Stage 2 function tool stubs (design only, not wired yet)
TOOLS_DESIGN = [
    {
        "name": "github_read_file",
        "description": "Read a file from GitHub repo at branch (e.g., PROJECT_STATUS.md, AgentOS/TASK_QUEUE.md).",
        "parameters": {"path": "string", "branch": "string"},
    },
    {
        "name": "github_list_tasks",
        "description": "List AgentOS TASK_QUEUE tasks (Open/Claimed/Done) via GitHub.",
        "parameters": {"status": "string?"},
    },
    {
        "name": "github_create_task",
        "description": "Create AgentOS task (Stage 2, requires allowlist + confirmation).",
        "parameters": {"title": "string", "module": "string", "priority": "string"},
    },
    {
        "name": "agentos_validate",
        "description": "Run AgentOS/tools/validate.py semantics via GitHub check (read-only).",
        "parameters": {},
    },
]


@dataclass
class GatewayRequest:
    telegram_user_id: int
    text: str
    context: dict | None = None


@dataclass
class GatewayResponse:
    reply_text: str
    tool_calls: list[dict] | None = None
    audit_user_id: int | None = None


def stub_handle(request: GatewayRequest) -> GatewayResponse:
    """Stage 1 stub — no OpenAI call, returns design echo for offline tests."""
    return GatewayResponse(
        reply_text=f"[Stage 1 stub] Received from {request.telegram_user_id}: {request.text[:120]} — Gateway not yet wired to OpenAI (see docs/OPENAI_GATEWAY_DESIGN.md).",
        tool_calls=[],
        audit_user_id=request.telegram_user_id,
    )
