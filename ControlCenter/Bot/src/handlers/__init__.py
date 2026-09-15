"""QROS Bot — handlers package (Stage 2: wired — allowlist + Gateway forwarding)."""

# Stage 1: skeleton
# Stage 2: wired inline in src/main.py (handlers/start, status, tasks, reports, events, text)
# All handlers: check allowlist, forward to Gateway POST /v1/chat, never write AgentOS directly.
# See src/main.py::handle_start, handle_help, handle_status, handle_tasks, handle_reports, handle_events, handle_text, handle_validate

HANDLERS_DESIGN = [
    "/start — greeting + allowlist check → Gateway",
    "/help — command list → Gateway",
    "/status — PROJECT_STATUS.md via Gateway+GitHub",
    "/tasks — TASK_QUEUE.md list/filter via Gateway",
    "/reports — REPORT_QUEUE.md via Gateway",
    "/events — EVENT_BUS tail via Gateway",
    "/validate — AgentOS validate via Gateway",
    "/health — internal (exposed via FastAPI)",
    "text — any message → Gateway OpenAI → GitHub → AgentOS",
]

# Stage 2 wiring: handlers are registered in Application (long polling) with allowlist guard and httpx forward to GATEWAY_INTERNAL_URL
WIRED = True

