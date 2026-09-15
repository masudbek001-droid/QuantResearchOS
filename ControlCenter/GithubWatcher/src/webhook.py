"""
QROS GithubWatcher — webhook logic (Stage 1: design + offline verification, no network forward).

Implements:
- HMAC SHA-256 verification of X-Hub-Signature-256 (GitHub → Watcher)
- Idempotency via X-GitHub-Delivery header
- Event routing table (design) — which GitHub events matter for Control Center

No forwarding to Gateway/Bot in Stage 1 — just validates and logs.
Stage 2 will: verify → deduplicate → forward minimal payload to Gateway → optional Telegram notify via Bot.
"""
from __future__ import annotations

import hashlib
import hmac


def verify_signature(secret: str, payload: bytes, signature_header: str | None) -> bool:
    """
    Verify GitHub webhook signature.

    GitHub sends:  X-Hub-Signature-256: sha256=<hex hmac-sha256(secret, raw_body)>
    Return True if matches, False otherwise. Empty secret or missing header → False (secure default).
    """
    if not secret or not signature_header:
        return False
    if not signature_header.startswith("sha256="):
        return False
    expected = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
    provided = signature_header.removeprefix("sha256=")
    # constant-time compare
    return hmac.compare_digest(expected, provided)


# Which GitHub events the Control Center cares about (Stage 1 design)
SUBSCRIBED_EVENTS_DESIGN = [
    "push",              # branch updates (arena/**/main) → AgentOS EVENT_BUS poll
    "pull_request",      # opened/synchronize/closed → PR status via Gateway
    "pull_request_review",
    "check_suite",       # CI status (AgentOS CI)
    "check_run",
    "workflow_run",      # workflow conclusions
    "issues",            # optional: task mirroring
    "issue_comment",
]

# Routing design (Stage 2)
ROUTING_DESIGN = {
    "push": "Gateway → notify Telegram (optional) + invalidate AgentOS cache",
    "pull_request": "Gateway → summarize PR for Telegram /status",
    "check_suite/check_run/workflow_run": "Gateway → report CI pass/fail to Telegram",
    "issues": "Gateway → map to TASK_QUEUE (future, read-only Stage 1)",
}

# Idempotency: store X-GitHub-Delivery IDs for 24h; Stage 2 will use Redis/file.
IDEMPOTENCY_DESIGN = "Header X-GitHub-Delivery is the dedup key; Stage 1 logs it, Stage 2 stores in Redis."
