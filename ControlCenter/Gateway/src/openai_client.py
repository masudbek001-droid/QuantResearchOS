"""
QROS Gateway — OpenAI client (Stage 2: wired).

- Real OpenAI client if OPENAI_API_KEY present (openai SDK v1)
- Rule-based fallback when key is placeholder/missing (for offline health)
- Function tools allowlisted: github_read_file, github_list_tasks, agentos_validate
- GitHub API helper (via httpx + GITHUB_TOKEN) with local fallback for sandbox
- Rate limiting per telegram_user_id (in-memory token bucket)
- Structured logging helper via caller
"""
from __future__ import annotations

import json
import time
import pathlib
import logging
from dataclasses import dataclass
from typing import Any

log = logging.getLogger("qros.gateway.openai")

SYSTEM_PROMPT_STAGE2 = """You are QROS Control Center Gateway — remote project management for QuantResearchOS.

PURPOSE: Help the owner manage the project via Telegram. You route natural language to GitHub/AgentOS actions.
NOT trading. NOT AI trading advice. NOT autonomous trading.

ALLOWED:
- Read: PROJECT_STATUS, ROADMAP, TASK_QUEUE, REPORT_QUEUE, EVENT_BUS, GitHub branches/PRs/checks
- Write (Stage 2, allowlisted, confirm): create task, claim task (via GitHub commit to AgentOS queue), emit event

FORBIDDEN:
- Any modification to 01_Source/EA/** trading modules, 02_Databases schema, or AgentOS invariants except via the published AgentOS CLI protocol
- No Telegram bus for AgentOS — Git is the bus. You go through GitHub.

When unsure, return a clarifying question. Always log the telegram_user_id for audit.
Alias: SYSTEM_PROMPT_STAGE1 kept for backwards compat.
"""
SYSTEM_PROMPT_STAGE1 = SYSTEM_PROMPT_STAGE2

# OpenAI function tools in OpenAI v1 format (Stage 2 wired)
TOOLS_DESIGN = [
    {
        "type": "function",
        "function": {
            "name": "github_read_file",
            "description": "Read a file from GitHub repo at branch (e.g., PROJECT_STATUS.md, AgentOS/TASK_QUEUE.md).",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Repo-relative path"},
                    "branch": {"type": "string", "description": "Branch, default arena branch"},
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "github_list_tasks",
            "description": "List AgentOS TASK_QUEUE tasks (Open/Claimed/Done) via GitHub or local mirror.",
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {"type": "string", "enum": ["OPEN", "CLAIMED", "IN_PROGRESS", "REVIEW", "DONE", "BLOCKED", ""]},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "agentos_validate",
            "description": "Run AgentOS/tools/validate.py semantics (read-only).",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "github_create_task",
            "description": "Create AgentOS task (requires confirmation, Stage 2 allowlisted).",
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "module": {"type": "string", "description": "MOD-*"},
                    "priority": {"type": "string", "enum": ["P0", "P1", "P2", "P3"]},
                },
                "required": ["title", "module"],
            },
        },
    },
]

# Keep legacy flat list for Stage1 test compatibility (some tests check .name)
TOOLS_DESIGN_LEGACY = [
    {"name": "github_read_file", "description": TOOLS_DESIGN[0]["function"]["description"], "parameters": {"path": "string", "branch": "string"}},
    {"name": "github_list_tasks", "description": TOOLS_DESIGN[1]["function"]["description"], "parameters": {"status": "string?"}},
    {"name": "github_create_task", "description": TOOLS_DESIGN[3]["function"]["description"], "parameters": {"title": "string", "module": "string", "priority": "string"}},
    {"name": "agentos_validate", "description": TOOLS_DESIGN[2]["function"]["description"], "parameters": {}},
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
    """Stage 1 stub kept for backwards compat / tests."""
    return GatewayResponse(
        reply_text=f"[Stage 1 stub] Received from {request.telegram_user_id}: {request.text[:120]} — Gateway not yet wired to OpenAI (see docs/OPENAI_GATEWAY_DESIGN.md).",
        tool_calls=[],
        audit_user_id=request.telegram_user_id,
    )

# ── Rate limiting (in-memory, per user) ───────────────────────────────────
_rate_buckets: dict[int, list[float]] = {}

def check_rate_limit(user_id: int, rpm: int = 20) -> bool:
    """Return True if allowed, False if rate-limited."""
    now = time.time()
    window = 60.0
    bucket = _rate_buckets.get(user_id, [])
    bucket = [t for t in bucket if now - t < window]
    if len(bucket) >= rpm:
        _rate_buckets[user_id] = bucket
        return False
    bucket.append(now)
    _rate_buckets[user_id] = bucket
    return True

# ── GitHub helper (API + local fallback) ───────────────────────────────────
def _repo_root() -> pathlib.Path:
    # Try common locations: container /app is Gateway, repo is 3 levels up or sandbox
    candidates = [
        pathlib.Path(__file__).resolve().parents[3],  # .../ControlCenter/Gateway/src -> ControlCenter -> QuantResearchOS
        pathlib.Path(__file__).resolve().parents[4],
        pathlib.Path("/app").parents[1] if pathlib.Path("/app").exists() else None,
        pathlib.Path("/home/user/QuantResearchOS"),
        pathlib.Path.cwd(),
    ]
    for c in candidates:
        if c and (c / "AgentOS" / "TASK_QUEUE.md").exists():
            return c
    return pathlib.Path.cwd()

async def github_read_file(path: str, branch: str | None, github_token: str, github_repo: str, github_api_url: str) -> str:
    path = path.lstrip("/")
    branch = branch or "arena/01a0a3b5-quantresearchos"
    # Try GitHub API if token looks real
    if github_token and not github_token.startswith("ghp_placeholder") and not github_token.startswith("ghp_...") and len(github_token) > 20:
        try:
            import httpx
            url = f"{github_api_url.rstrip('/')}/repos/{github_repo}/contents/{path}?ref={branch}"
            headers = {"Authorization": f"Bearer {github_token}", "Accept": "application/vnd.github.v3.raw"}
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.get(url, headers=headers)
                if r.status_code == 200:
                    # raw returns directly if Accept raw, else base64 json
                    if r.headers.get("content-type", "").startswith("application/json"):
                        j = r.json()
                        import base64
                        if j.get("content"):
                            return base64.b64decode(j["content"]).decode("utf-8", errors="ignore")
                    return r.text
                log.warning(f"GitHub API read failed {r.status_code} for {path}")
        except Exception as e:
            log.warning(f"GitHub API exception: {e}")
    # Fallback: local repo mirror (offline, sandbox, or when token placeholder)
    root = _repo_root()
    local = root / path
    if local.is_file():
        try:
            return local.read_text(encoding="utf-8", errors="ignore")[:8000]
        except Exception as e:
            return f"Error reading local {path}: {e}"
    return f"File not found: {path} (repo={github_repo} branch={branch}) — local fallback at {local} missing"

async def github_list_tasks(status: str | None, github_token: str, github_repo: str, github_api_url: str) -> str:
    content = await github_read_file("AgentOS/TASK_QUEUE.md", None, github_token, github_repo, github_api_url)
    if not content or content.startswith("File not found"):
        return content
    # Simple parse: extract table rows
    lines = content.splitlines()
    # Find header | TaskID |
    out = []
    for l in lines:
        if l.strip().startswith("| TASK-") and "|" in l:
            if status and status.upper() not in l:
                continue
            out.append(l.strip())
    if not out:
        return f"No tasks found for status={status or 'all'}"
    return "\n".join(out[:20])

async def agentos_validate_local() -> str:
    """Run validate semantics locally if available."""
    try:
        import subprocess, sys
        root = _repo_root()
        proc = subprocess.run([sys.executable, str(root / "AgentOS" / "tools" / "validate.py")], capture_output=True, text=True, timeout=10)
        combined = (proc.stdout + "\n" + proc.stderr).strip()[:4000]
        return combined or "validate: no output"
    except Exception as e:
        return f"validate error: {e}"

# ── Rule-based fallback (when OpenAI key missing or call fails) ────────────
async def rule_based_handle(text: str, user_id: int, github_token: str, github_repo: str, github_api_url: str) -> str:
    t = text.strip().lower()
    if t in ("/start", "start"):
        return "👋 QROS Control Center online — use /help, /status, /tasks, /reports, /events, /validate"
    if t.startswith("/help"):
        return "/status — PROJECT_STATUS\n/tasks [status] — TASK_QUEUE\n/reports — REPORT_QUEUE\n/events — EVENT_BUS\n/validate — AgentOS validate\nAny text → OpenAI Gateway (if key configured) → GitHub → AgentOS"
    if t.startswith("/status"):
        c = await github_read_file("PROJECT_STATUS.md", None, github_token, github_repo, github_api_url)
        return c[:3500] + ("\n…(truncated)" if len(c) > 3500 else "")
    if t.startswith("/tasks"):
        parts = text.split()
        st = parts[1].upper() if len(parts) > 1 else ""
        return await github_list_tasks(st if st in {"OPEN","DONE","CLAIMED","REVIEW","IN_PROGRESS"} else None, github_token, github_repo, github_api_url)
    if t.startswith("/reports"):
        return await github_read_file("AgentOS/REPORT_QUEUE.md", None, github_token, github_repo, github_api_url)
    if t.startswith("/events"):
        c = await github_read_file("AgentOS/EVENT_BUS.md", None, github_token, github_repo, github_api_url)
        # tail 30 lines
        lines = c.splitlines()
        return "\n".join(lines[-30:])
    if t.startswith("/validate"):
        return await agentos_validate_local()
    # default: echo + hint
    return f"Received: {text[:500]}\nTry /help for commands. (OpenAI not configured — rule-based fallback active)"

# ── OpenAI call (real) ─────────────────────────────────────────────────────
async def openai_handle(request: GatewayRequest, github_token: str, github_repo: str, github_api_url: str, openai_api_key: str, openai_model: str, openai_base_url: str, openai_max_tokens: int, openai_temperature: float) -> GatewayResponse:
    # Try OpenAI SDK
    try:
        import openai
        client = openai.AsyncOpenAI(api_key=openai_api_key, base_url=openai_base_url)
        # First call with tools
        resp = await client.chat.completions.create(
            model=openai_model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT_STAGE2},
                {"role": "user", "content": request.text},
            ],
            tools=TOOLS_DESIGN,
            tool_choice="auto",
            max_tokens=openai_max_tokens,
            temperature=openai_temperature,
        )
        msg = resp.choices[0].message
        tool_calls = msg.tool_calls or []
        executed = []
        if tool_calls:
            for tc in tool_calls:
                fname = tc.function.name
                try:
                    args = json.loads(tc.function.arguments or "{}")
                except Exception:
                    args = {}
                result = ""
                if fname == "github_read_file":
                    result = await github_read_file(args.get("path",""), args.get("branch"), github_token, github_repo, github_api_url)
                elif fname == "github_list_tasks":
                    result = await github_list_tasks(args.get("status"), github_token, github_repo, github_api_url)
                elif fname == "agentos_validate":
                    result = await agentos_validate_local()
                elif fname == "github_create_task":
                    result = "[Stage 2] github_create_task requires confirmation — not yet auto-executed. Reply 'confirm' to proceed."
                else:
                    result = f"Unknown tool {fname}"
                executed.append({"tool": fname, "args": args, "result_preview": result[:800]})
                # Append tool result as follow-up for LLM to summarize
                # For simplicity, we will directly compose reply from tool result in Stage 2 without second LLM call
            # Summarize: concatenate tool results
            reply_parts = []
            for e in executed:
                reply_parts.append(f"🔧 {e['tool']} →\n{e['result_preview']}")
            reply = "\n\n".join(reply_parts) if reply_parts else (msg.content or "")
            return GatewayResponse(reply_text=reply[:3800], tool_calls=executed, audit_user_id=request.telegram_user_id)
        else:
            # No tool, direct answer
            return GatewayResponse(reply_text=msg.content or "[empty reply]", tool_calls=[], audit_user_id=request.telegram_user_id)
    except Exception as e:
        log.warning(f"OpenAI call failed, fallback to rule-based: {e}")
        fallback = await rule_based_handle(request.text, request.telegram_user_id, github_token, github_repo, github_api_url)
        return GatewayResponse(reply_text=fallback, tool_calls=[{"tool": "fallback", "reason": str(e)}], audit_user_id=request.telegram_user_id)
