"""
QROS Telegram Command Dispatcher — Stage 3.
"""
from __future__ import annotations

from typing import Optional

try:
    from .mission_queue import MissionQueue
    from .worker_registry import WorkerRegistry
    from .mission import MissionStatus
    from .github_sync import GitHubSync
except ImportError:
    try:
        from mission_queue import MissionQueue
        from worker_registry import WorkerRegistry
        from mission import MissionStatus
        from github_sync import GitHubSync
    except ImportError:
        from queue import MissionQueue
        from worker_registry import WorkerRegistry
        from mission import MissionStatus
        from github_sync import GitHubSync

class TelegramCommandDispatcher:
    def __init__(self, queue: MissionQueue | None = None, workers: WorkerRegistry | None = None, github_sync: GitHubSync | None = None):
        self.workers = workers or WorkerRegistry()
        self.workers.ensure_defaults()
        self.queue = queue or MissionQueue(workers=self.workers)
        self.github_sync = github_sync or GitHubSync()

    def dispatch(self, text: str, telegram_user_id: int) -> str:
        t = text.strip()
        if not t:
            return "Empty command. Try /mission help"
        lower = t.lower()
        if lower in ("/mission", "/mission help", "/mission_help", "/queue help"):
            return self._help()
        if lower.startswith("/mission create"):
            title = t[len("/mission create"):].strip()
            if not title:
                return "Usage: /mission create <title> [| module=MOD-X priority=P1]"
            module = "MOD-ORCHESTRATOR"
            priority = "P1"
            payload = {}
            if "|" in title:
                parts = [p.strip() for p in title.split("|")]
                title = parts[0]
                for p in parts[1:]:
                    for token in p.split():
                        if "=" in token:
                            k,v = [x.strip() for x in token.split("=",1)]
                            if k == "module": module = v
                            elif k == "priority": priority = v
            mission = self.queue.create(title=title, module=module, priority=priority, created_by=str(telegram_user_id), payload=payload)
            try:
                task_id = self.github_sync.sync_create(mission)
                mission.github_task_id = task_id
            except Exception:
                pass
            try:
                self.queue.queue(mission.mission_id, by=str(telegram_user_id))
            except Exception:
                pass
            return f"✅ Mission {mission.mission_id} CREATED → QUEUED\nTitle: {title}\nModule: {module} Priority: {priority}\nUse /mission show {mission.mission_id}"
        if lower.startswith("/mission list"):
            parts = t.split()
            status = parts[2].upper() if len(parts) > 2 else None
            missions = self.queue.list(status=status if status in [s.value for s in MissionStatus] else None)
            if not missions:
                return f"No missions{' for '+status if status else ''}."
            lines = [f"{m.mission_id} [{m.status.value}] {m.title[:40]} → {m.assigned_to or '-'} retry:{m.retry_count}" for m in missions[-20:]]
            return "📋 Missions:\n" + "\n".join(lines)
        if lower.startswith("/queue") or lower == "/mission queue":
            missions = self.queue.list(status=MissionStatus.QUEUED.value)
            if not missions:
                return "Queue empty (QUEUED)."
            return "\n".join([f"{m.mission_id} {m.title}" for m in missions])
        if lower.startswith("/mission show"):
            parts = t.split()
            if len(parts) < 3:
                return "Usage: /mission show <MSQ-0001>"
            mid = parts[2].upper()
            m = self.queue.get(mid)
            if not m:
                return f"Mission {mid} not found"
            hist = " → ".join([f"{h['from_status']}→{h['to_status']}" for h in m.history[-4:]])
            return f"🔍 {m.mission_id} [{m.status.value}] {m.title}\nModule:{m.module} Pri:{m.priority} Assigned:{m.assigned_to or '-'}\nRetry:{m.retry_count}/{m.max_retries} Timeout:{m.timeout_seconds}s\nHistory: {hist}\nCreated: {m.created_at}"
        if lower.startswith("/mission assign"):
            parts = t.split()
            if len(parts) < 4:
                return "Usage: /mission assign <MSQ-0001> <worker-arena|worker-kilo>"
            mid, worker = parts[2].upper(), parts[3].lower()
            # BUG-WORKER-002 fix: accept short names arena/kilo as aliases for worker-arena/worker-kilo
            if worker in ("arena", "kilo"):
                worker = f"worker-{worker}"
            elif worker not in ("worker-arena", "worker-kilo"):
                for w in self.workers.workers.values():
                    if w.role.lower() == worker:
                        worker = w.worker_id
                        break
            try:
                self.queue.assign(mid, worker, by=str(telegram_user_id))
                return f"✅ {mid} ASSIGNED → {worker}"
            except Exception as e:
                return f"❌ Assign failed: {e}"
        if lower.startswith("/mission start"):
            parts = t.split()
            if len(parts) < 3:
                return "Usage: /mission start <MSQ-0001>"
            mid = parts[2].upper()
            try:
                self.queue.start(mid, by=str(telegram_user_id))
                return f"▶️ {mid} RUNNING"
            except Exception as e:
                return f"❌ Start failed: {e}"
        if lower.startswith("/mission review"):
            parts = t.split()
            if len(parts) < 3:
                return "Usage: /mission review <MSQ-0001>"
            mid = parts[2].upper()
            try:
                self.queue.review(mid, by=str(telegram_user_id))
                return f"👀 {mid} REVIEW"
            except Exception as e:
                return f"❌ Review failed: {e}"
        if lower.startswith("/mission done"):
            parts = t.split()
            if len(parts) < 3:
                return "Usage: /mission done <MSQ-0001>"
            mid = parts[2].upper()
            try:
                self.queue.complete(mid, by=str(telegram_user_id))
                return f"✅ {mid} DONE"
            except Exception as e:
                return f"❌ Done failed: {e}"
        if lower.startswith("/mission archive"):
            parts = t.split()
            if len(parts) < 3:
                return "Usage: /mission archive <MSQ-0001>"
            mid = parts[2].upper()
            try:
                self.queue.archive(mid, by=str(telegram_user_id))
                return f"🗄️ {mid} ARCHIVED"
            except Exception as e:
                return f"❌ Archive failed: {e}"
        if lower.startswith("/mission retry"):
            parts = t.split()
            if len(parts) < 3:
                return "Usage: /mission retry <MSQ-0001>"
            mid = parts[2].upper()
            try:
                self.queue.retry(mid, by=str(telegram_user_id))
                return f"🔄 {mid} RETRY → QUEUED (retry:{self.queue.get(mid).retry_count})"
            except Exception as e:
                return f"❌ Retry failed: {e}"
        if lower.startswith("/mission cancel"):
            parts = t.split()
            if len(parts) < 3:
                return "Usage: /mission cancel <MSQ-0001>"
            mid = parts[2].upper()
            try:
                self.queue.cancel(mid, by=str(telegram_user_id), reason="cancelled via Telegram")
                return f"🚫 {mid} CANCELLED → ARCHIVED"
            except Exception as e:
                return f"❌ Cancel failed: {e}"
        if lower.startswith("/mission workers"):
            active = self.workers.list_active()
            if not active:
                return "No workers registered"
            return "👷 Workers:\n" + "\n".join([f"{w.worker_id} [{w.role}] {w.status} hb:{w.last_heartbeat}" for w in active])
        if lower.startswith("/mission timeout"):
            timed = self.queue.check_timeouts()
            if not timed:
                return "No timeouts"
            return "⏰ Timeouts:\n" + "\n".join([f"{m.mission_id} → REVIEW (timeout)" for m in timed])
        return ""

    def _help(self) -> str:
        return (
            "🎯 Mission Dispatcher — commands:\n"
            "/mission create <title> | module=MOD-X priority=P1 — create & queue\n"
            "/mission list [STATUS] — list missions\n"
            "/queue — QUEUED only\n"
            "/mission show <MSQ-0001>\n"
            "/mission assign <id> <worker-arena|worker-kilo>\n"
            "/mission start <id> — QUEUED→ASSIGNED→RUNNING\n"
            "/mission review <id> — RUNNING→REVIEW\n"
            "/mission done <id> — REVIEW→DONE\n"
            "/mission archive <id> — DONE→ARCHIVED\n"
            "/mission retry <id> — RUNNING/REVIEW→QUEUED\n"
            "/mission cancel <id> — →ARCHIVED\n"
            "/mission workers — Arena/Kilo\n"
            "/mission timeout — check timeouts\n"
            "Lifecycle: CREATED→QUEUED→ASSIGNED→RUNNING→REVIEW→DONE→ARCHIVED"
        )
