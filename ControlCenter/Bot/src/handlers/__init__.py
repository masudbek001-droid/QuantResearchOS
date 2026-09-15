"""QROS Bot — handlers package (Stage 1: skeleton, no business logic)."""

# Stage 2 will add:
# - handlers/start.py      (/start, /help — auth-gated)
# - handlers/status.py     (/status — GitHub/AgentOS via Gateway)
# - handlers/tasks.py      (/tasks list/claim — read via Gateway)
# - handlers/reports.py    (/reports — REPORT_QUEUE via Gateway)
# - handlers/events.py     (/events — EVENT_BUS via Gateway)
# All handlers must: check allowlist, forward to Gateway, never write AgentOS directly.

HANDLERS_DESIGN = [
    "/start — greeting + allowlist check",
    "/help — command list",
    "/status — PROJECT_STATUS.md via Gateway+GitHub",
    "/tasks — TASK_QUEUE.md list/filter via Gateway",
    "/reports — REPORT_QUEUE.md via Gateway",
    "/events — EVENT_BUS tail via Gateway",
    "/health — internal (exposed via FastAPI)",
]
