"""
QROS GithubWatcher — webhook logic (Stage 2: wired).

- HMAC verification (unchanged)
- Event parser (push, pull_request, check_suite, workflow_run, etc.)
- AgentOS forwarding helpers (structured event format)
"""
from __future__ import annotations

import hashlib
import hmac
import json
from typing import Any

def verify_signature(secret: str, payload: bytes, signature_header: str | None) -> bool:
    if not secret or not signature_header:
        return False
    if not signature_header.startswith("sha256="):
        return False
    expected = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
    provided = signature_header.removeprefix("sha256=")
    return hmac.compare_digest(expected, provided)

SUBSCRIBED_EVENTS_DESIGN = [
    "push",
    "pull_request",
    "pull_request_review",
    "check_suite",
    "check_run",
    "workflow_run",
    "issues",
    "issue_comment",
]

ROUTING_DESIGN = {
    "push": "Gateway → notify Telegram (optional) + invalidate AgentOS cache",
    "pull_request": "Gateway → summarize PR for Telegram /status",
    "check_suite/check_run/workflow_run": "Gateway → report CI pass/fail to Telegram",
    "issues": "Gateway → map to TASK_QUEUE (future, read-only Stage 1)",
}

IDEMPOTENCY_DESIGN = "Header X-GitHub-Delivery is the dedup key; Stage 1 logs it, Stage 2 stores in memory (no Redis per NO Redis rule)."

# ── In-memory dedup (Stage 2: NO Redis per mission) ────────────────────────
_seen_deliveries: set[str] = set()

def is_duplicate(delivery: str | None) -> bool:
    if not delivery:
        return False
    if delivery in _seen_deliveries:
        return True
    _seen_deliveries.add(delivery)
    # keep set bounded
    if len(_seen_deliveries) > 1000:
        _seen_deliveries.clear()
    return False

# ── Event parser (Stage 2) ─────────────────────────────────────────────────
def parse_github_event(event: str | None, payload_bytes: bytes) -> dict[str, Any]:
    """
    Parse raw GitHub webhook payload into normalized dict for forwarding to Gateway/AgentOS.

    Returns: {"event": str, "repo": str, "ref": str, "action": str, "payload": dict}
    Never raises — returns raw payload on parse error.
    """
    try:
        data = json.loads(payload_bytes.decode("utf-8") if payload_bytes else "{}")
    except Exception:
        data = {}
    repo = ""
    try:
        repo = (data.get("repository") or {}).get("full_name", "") or data.get("repo", {}).get("full_name", "")
    except Exception:
        repo = ""
    result: dict[str, Any] = {"event": event or "unknown", "repo": repo, "payload": data}
    if event == "push":
        result["ref"] = data.get("ref", "")
        result["pusher"] = (data.get("pusher") or {}).get("name", "")
        result["commits"] = data.get("commits", [])
        result["head_commit"] = data.get("head_commit", {})
    elif event == "pull_request":
        result["action"] = data.get("action", "")
        pr = data.get("pull_request") or {}
        result["pr_number"] = pr.get("number")
        result["pr_title"] = pr.get("title")
        result["pr_state"] = pr.get("state")
    elif event in ("check_suite", "check_run", "workflow_run"):
        result["action"] = data.get("action", "")
        result["conclusion"] = data.get("conclusion") or (data.get("check_suite") or {}).get("conclusion") or (data.get("workflow_run") or {}).get("conclusion")
    return result

def format_agentos_forward(event: str | None, parsed: dict[str, Any], delivery: str | None) -> dict[str, Any]:
    """
    Format GitHub event as AgentOS-style forwarding payload (for Gateway → Bot → Telegram, and for evidence logs).
    Stage 2 minimal AgentOS event forwarding: map GitHub push → EVENT_BUS style log (not mutating AgentOS files).
    """
    return {
        "event": event,
        "delivery": delivery,
        "repo": parsed.get("repo", ""),
        "parsed": {k: v for k, v in parsed.items() if k not in ("payload",)},
        # Include truncated payload for audit
        "payload_preview": json.dumps(parsed.get("payload", {}) )[:2000],
    }
