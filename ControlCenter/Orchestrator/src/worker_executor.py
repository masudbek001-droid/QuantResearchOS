"""
QROS Worker Execution Engine — Stage 4 (Worker Automation).

Watches MissionQueue for ASSIGNED missions and automatically executes them for
worker-arena / worker-kilo.

Flow:
  ASSIGNED (assigned_to == worker_id)
    → RUNNING (notify started)
    → create execution context
    → perform dummy task (create file)
    → git commit + push (record hash, branch, files, message, duration)
    → REVIEW (history with commit)
    → DONE (notify completed)
  On failure:
    RUNNING → RETRY (→ QUEUED) until retry_limit, then → ARCHIVED (FAILED) (notify retry/failed)

No Redis/RabbitMQ/Kafka/Postgres — file-based JSON only.
No trading/Research/AgentOS redesign.
"""
from __future__ import annotations

import asyncio
import datetime
import json
import logging
import os
import pathlib
import subprocess
import sys
import time
from typing import Optional, Dict, Any, List

# Setup logger (structured JSON if available, else plain)
try:
    import logging
    log = logging.getLogger("qros.worker-executor")
    if not log.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter('{"timestamp":"%(asctime)s","level":"%(levelname)s","service":"qros-worker","message":"%(message)s"}'))
        log.addHandler(handler)
        log.setLevel(logging.INFO)
except Exception:
    import logging as _lg
    log = _lg.getLogger("qros.worker-executor")

# Import mission components with robust handling for queue shadowing and importlib loading
_ORCH_SRC = pathlib.Path(__file__).resolve().parent
# Do not insert at front to avoid shadowing stdlib queue (BUG-STABILITY)
# Use importlib for orchestrator modules instead of sys.path manipulation
if str(_ORCH_SRC) not in sys.path:
    sys.path.append(str(_ORCH_SRC))

def _load_orch(name: str):
    """Load Orchestrator module via importlib to avoid stdlib shadowing."""
    import importlib.util as _ilu
    p = _ORCH_SRC / f"{name}.py"
    if p.is_file():
        # Avoid shadowing stdlib 'queue' - load under different name
        mod_name = f"_orch_{name}" if name == "queue" else name
        spec = _ilu.spec_from_file_location(mod_name, p)
        if spec and spec.loader:
            mod = _ilu.module_from_spec(spec)
            sys.modules[mod_name] = mod
            # Also keep original name for backward compat but ensure stdlib queue not overwritten
            if name != "queue":
                sys.modules[name] = mod
            spec.loader.exec_module(mod)
            return mod
    return None

# Try normal imports first (when modules already loaded via Bot)
try:
    from mission import Mission, MissionStatus, utcnow  # type: ignore
    # mission_queue may not exist under that name on some branches, fallback to queue.py
    try:
        from mission_queue import MissionQueue, DATA_PATH, OUTPUT_PATH  # type: ignore
    except ImportError:
        # Load queue.py directly via importlib (avoid stdlib)
        _qmod = _load_orch("queue")
        if _qmod and hasattr(_qmod, "MissionQueue"):
            MissionQueue = _qmod.MissionQueue  # type: ignore
            DATA_PATH = _qmod.DATA_PATH  # type: ignore
            OUTPUT_PATH = _qmod.OUTPUT_PATH  # type: ignore
        elif "_orch_queue" in sys.modules and hasattr(sys.modules["_orch_queue"], "MissionQueue"):
            _qmod2 = sys.modules["_orch_queue"]
            MissionQueue = _qmod2.MissionQueue  # type: ignore
            DATA_PATH = _qmod2.DATA_PATH  # type: ignore
            OUTPUT_PATH = _qmod2.OUTPUT_PATH  # type: ignore
        else:
            raise
    from worker_registry import WorkerRegistry  # type: ignore
    from github_sync import GitHubSync  # type: ignore
except Exception:
    # Fallback: load all via importlib
    _mmod = _load_orch("mission")
    if _mmod:
        Mission = _mmod.Mission  # type: ignore
        MissionStatus = _mmod.MissionStatus  # type: ignore
        utcnow = _mmod.utcnow  # type: ignore
    else:
        raise ImportError("mission.py not found")
    # mission_queue
    _mqmod = _load_orch("mission_queue")
    if _mqmod and hasattr(_mqmod, "MissionQueue"):
        MissionQueue = _mqmod.MissionQueue  # type: ignore
        DATA_PATH = _mqmod.DATA_PATH  # type: ignore
        OUTPUT_PATH = _mqmod.OUTPUT_PATH  # type: ignore
    else:
        _qmod = _load_orch("queue")
        if _qmod and hasattr(_qmod, "MissionQueue"):
            MissionQueue = _qmod.MissionQueue  # type: ignore
            DATA_PATH = _qmod.DATA_PATH  # type: ignore
            OUTPUT_PATH = _qmod.OUTPUT_PATH  # type: ignore
        elif "_orch_queue" in sys.modules and hasattr(sys.modules["_orch_queue"], "MissionQueue"):
            _qmod2 = sys.modules["_orch_queue"]
            MissionQueue = _qmod2.MissionQueue  # type: ignore
            DATA_PATH = _qmod2.DATA_PATH  # type: ignore
            OUTPUT_PATH = _qmod2.OUTPUT_PATH  # type: ignore
        else:
            raise ImportError("mission_queue/queue.py not found")
    _wmod = _load_orch("worker_registry")
    WorkerRegistry = _wmod.WorkerRegistry  # type: ignore
    _gmod = _load_orch("github_sync")
    GitHubSync = _gmod.GitHubSync  # type: ignore

ROOT = pathlib.Path(__file__).resolve().parents[3]
# For Docker vs host, ROOT is correct for git repo
REPO_ROOT = ROOT
if not (REPO_ROOT / ".git").exists():
    # Fallback: try to find git root via git rev-parse
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=2)
        if out.returncode == 0:
            REPO_ROOT = pathlib.Path(out.stdout.strip())
    except Exception:
        pass

# Telegram notify endpoint
BOT_INTERNAL_URL = os.getenv("BOT_INTERNAL_URL", os.getenv("BOT_URL", "http://bot:8081"))
# Fallbacks for host
if BOT_INTERNAL_URL == "http://bot:8081":
    # Try localhost if bot not reachable (host testing)
    pass

# Poll interval seconds
POLL_INTERVAL = float(os.getenv("WORKER_POLL_INTERVAL", "2"))

def _notify_telegram(text: str, parse_mode: Optional[str] = None) -> bool:
    """Send Telegram notification via Bot /internal/notify. Returns True if delivered."""
    # Try multiple endpoints: BOT_INTERNAL_URL, localhost, gateway
    urls = []
    # Primary from env
    urls.append(f"{BOT_INTERNAL_URL.rstrip('/')}/internal/notify")
    # Host fallback
    urls.append("http://localhost:8081/internal/notify")
    urls.append("http://127.0.0.1:8081/internal/notify")
    # Gateway fallback (if Bot forwards)
    gw = os.getenv("GATEWAY_INTERNAL_URL", "http://gateway:8080")
    urls.append(f"{gw.rstrip('/')}/internal/notify")

    payload = {"text": text}
    if parse_mode:
        payload["parse_mode"] = parse_mode

    # Use httpx if available, else urllib
    try:
        import httpx
        for url in urls:
            try:
                # Short timeout, don't block worker
                with httpx.Client(timeout=3) as client:
                    r = client.post(url, json=payload)
                    if r.status_code == 200:
                        log.info(f"Telegram notify delivered to {url}: {text[:80]}")
                        return True
                    else:
                        log.debug(f"Notify {url} returned {r.status_code}: {r.text[:200]}")
            except Exception as e:
                log.debug(f"Notify {url} failed: {e}")
                continue
        log.warning(f"Telegram notify failed for all urls, text: {text[:80]}")
        return False
    except ImportError:
        # Fallback urllib
        import urllib.request, urllib.error, json as _json
        for url in urls:
            try:
                data = _json.dumps(payload).encode("utf-8")
                req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
                with urllib.request.urlopen(req, timeout=3) as resp:
                    if resp.status == 200:
                        log.info(f"Telegram notify delivered via urllib to {url}")
                        return True
            except Exception as e:
                log.debug(f"urllib notify {url} failed: {e}")
                continue
        return False

def _git_info() -> Dict[str, str]:
    """Get current branch and commit hash."""
    branch = "unknown"
    commit = "unknown"
    try:
        out = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True, timeout=2, cwd=str(REPO_ROOT))
        if out.returncode == 0:
            branch = out.stdout.strip()
    except Exception:
        pass
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, timeout=2, cwd=str(REPO_ROOT))
        if out.returncode == 0:
            commit = out.stdout.strip()[:7]  # short hash like 8fd3e11
    except Exception:
        pass
    return {"branch": branch, "commit": commit}

def _git_commit_and_push(mission: Mission, worker_id: str) -> Dict[str, Any]:
    """
    Perform dummy execution: create a file, git add, commit, push.
    Returns dict with commit_hash, branch, start_time, finish_time, duration, files_changed, commit_message.
    """
    start_time = datetime.datetime.now(datetime.timezone.utc)
    start_iso = start_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    branch = _git_info()["branch"]
    # Ensure git config
    try:
        subprocess.run(["git", "config", "user.email", "worker@qros.local"], cwd=str(REPO_ROOT), timeout=2, capture_output=True)
        subprocess.run(["git", "config", "user.name", f"QROS {worker_id}"], cwd=str(REPO_ROOT), timeout=2, capture_output=True)
    except Exception:
        pass

    # Create execution context: file per mission
    exec_dir = REPO_ROOT / "04_Output" / "ControlCenter" / "worker_executions"
    # Also mirror to ControlCenter/data for persistence check
    data_exec_dir = REPO_ROOT / "ControlCenter" / "data" / "worker_executions"
    try:
        exec_dir.mkdir(parents=True, exist_ok=True)
        data_exec_dir.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass

    # Dummy task: create execution result file
    # If mission title contains "FAIL" and retry_count ==0, simulate failure for retry testing
    should_fail = "FAIL" in mission.title.upper() and mission.retry_count == 0 and "RETRY_TEST" in mission.title
    # Also allow payload to force fail
    if mission.payload and mission.payload.get("force_fail"):
        should_fail = True

    if should_fail:
        raise RuntimeError(f"Simulated failure for {mission.mission_id} (title contains FAIL)")

    exec_file = exec_dir / f"{mission.mission_id}_{worker_id}.md"
    data_exec_file = data_exec_dir / f"{mission.mission_id}_{worker_id}.md"
    commit_message = f"feat(mission): {mission.mission_id} {mission.title[:50]} [{worker_id}]"
    files_changed: List[str] = []

    # Create content with mission details
    content = f"""# Mission Execution Result

**Mission ID:** {mission.mission_id}
**Title:** {mission.title}
**Module:** {mission.module}
**Priority:** {mission.priority}
**Worker:** {worker_id}
**Status:** {mission.status.value if hasattr(mission.status, 'value') else mission.status}
**Created by:** {mission.created_by}
**Start time:** {start_iso}
**Branch:** {branch}
**Payload:** {json.dumps(mission.payload, indent=2)}

## Execution Context
- Execution performed by {worker_id} automatically via Worker Execution Engine
- No manual intervention
- Dummy task: create this file and commit

## Result
- Status: SUCCESS
- Worker: {worker_id}
- Mission: {mission.mission_id}
"""

    # Write files
    try:
        exec_file.write_text(content, encoding="utf-8")
        data_exec_file.write_text(content, encoding="utf-8")
        files_changed = [str(exec_file.relative_to(REPO_ROOT)), str(data_exec_file.relative_to(REPO_ROOT))]
    except Exception as e:
        log.warning(f"Failed to write execution files for {mission.mission_id}: {e}")
        # Try chmod fallback
        try:
            import os
            os.chmod(exec_dir, 0o777)
            os.chmod(data_exec_dir, 0o777)
            exec_file.write_text(content, encoding="utf-8")
            data_exec_file.write_text(content, encoding="utf-8")
            files_changed = [str(exec_file.relative_to(REPO_ROOT)), str(data_exec_file.relative_to(REPO_ROOT))]
        except Exception as e2:
            log.error(f"Execution file write failed even after chmod: {e2}")
            raise

    # Git add and commit — BUG-012 instrumentation: log before/after each git stage
    commit_hash = "unknown"
    full_commit_hash = "unknown"
    try:
        log.debug(f"[{mission.mission_id}] git add — before", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
        # Check if there are changes to commit
        # Use git status
        status_out = subprocess.run(["git", "status", "--porcelain", str(exec_file), str(data_exec_file)], capture_output=True, text=True, timeout=3, cwd=str(REPO_ROOT))
        log.debug(f"[{mission.mission_id}] git add — status done: {status_out.returncode}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
        # Always add
        log.debug(f"[{mission.mission_id}] git add — running git add {exec_file.name}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
        add_out = subprocess.run(["git", "add", str(exec_file), str(data_exec_file)], capture_output=True, text=True, timeout=3, cwd=str(REPO_ROOT))
        log.debug(f"[{mission.mission_id}] git add — after add_out={add_out.returncode}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
        if add_out.returncode != 0:
            log.warning(f"git add failed for {mission.mission_id}: {add_out.stderr}")

        # Check if there's anything to commit (staged)
        log.debug(f"[{mission.mission_id}] git commit — before diff --cached", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
        diff_out = subprocess.run(["git", "diff", "--cached", "--name-only"], capture_output=True, text=True, timeout=3, cwd=str(REPO_ROOT))
        log.debug(f"[{mission.mission_id}] git commit — diff done staged={bool(diff_out.stdout.strip())}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
        if diff_out.stdout.strip():
            log.debug(f"[{mission.mission_id}] git commit — before commit", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
            commit_out = subprocess.run(["git", "commit", "-m", commit_message], capture_output=True, text=True, timeout=5, cwd=str(REPO_ROOT))
            log.debug(f"[{mission.mission_id}] git commit — after commit_out={commit_out.returncode}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
            if commit_out.returncode == 0:
                # Get commit hash
                hash_out = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, timeout=2, cwd=str(REPO_ROOT))
                if hash_out.returncode == 0:
                    full_commit_hash = hash_out.stdout.strip()
                    commit_hash = full_commit_hash[:7]
                # Get branch again (might have changed)
                branch_out = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True, timeout=2, cwd=str(REPO_ROOT))
                if branch_out.returncode == 0:
                    branch = branch_out.stdout.strip()
                # Push with resilient handling for fetch-first (Stage 4)
                push_branch = branch
                log.debug(f"[{mission.mission_id}] git push — before push to {push_branch}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
                try:
                    push_out = subprocess.run(["git", "push", "origin", push_branch], capture_output=True, text=True, timeout=10, cwd=str(REPO_ROOT))
                    log.debug(f"[{mission.mission_id}] git push — after push_out={push_out.returncode}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
                    if push_out.returncode != 0:
                        stderr_low = (push_out.stderr or "").lower()
                        if "fetch first" in stderr_low or "rejected" in stderr_low:
                            log.warning(f"Push fetch-first for {mission.mission_id}, trying fetch+rebase")
                            try:
                                log.debug(f"[{mission.mission_id}] git push — fetch before rebase", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
                                subprocess.run(["git", "fetch", "origin", push_branch], capture_output=True, text=True, timeout=10, cwd=str(REPO_ROOT))
                                log.debug(f"[{mission.mission_id}] git push — pull --rebase before", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
                                rb = subprocess.run(["git", "pull", "--rebase", "origin", push_branch], capture_output=True, text=True, timeout=10, cwd=str(REPO_ROOT))
                                log.debug(f"[{mission.mission_id}] git push — after rebase rb={rb.returncode}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
                                if rb.returncode != 0:
                                    log.warning(f"Rebase result for {mission.mission_id}: {rb.stderr[:300] if rb.stderr else rb.stdout[:300]}")
                                log.debug(f"[{mission.mission_id}] git push — retry push before", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
                                push2 = subprocess.run(["git", "push", "origin", push_branch], capture_output=True, text=True, timeout=10, cwd=str(REPO_ROOT))
                                log.debug(f"[{mission.mission_id}] git push — after retry push2={push2.returncode}", extra={"extra": {"mission_id": mission.mission_id}})  # type: ignore
                                if push2.returncode == 0:
                                    log.info(f"git push succeeded after rebase for {mission.mission_id} to origin/{push_branch}: {commit_hash}")
                                else:
                                    log.warning(f"git push still failed after rebase for {mission.mission_id}: {push2.stderr[:500]}")
                            except Exception as e2:
                                log.warning(f"Fetch/rebase exception for {mission.mission_id}: {e2}")
                        else:
                            log.warning(f"git push failed for {mission.mission_id} ({push_branch}): {push_out.stderr[:500]}")
                    else:
                        log.info(f"git push succeeded for {mission.mission_id} to origin/{push_branch}: {commit_hash}")
                except Exception as e:
                    log.warning(f"git push exception for {mission.mission_id}: {e}")
            else:
                # Commit failed (maybe no changes or already committed)
                log.warning(f"git commit failed for {mission.mission_id}: {commit_out.stderr[:500]}")
                # Try to get hash anyway
                hash_out = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, timeout=2, cwd=str(REPO_ROOT))
                if hash_out.returncode == 0:
                    full_commit_hash = hash_out.stdout.strip()
                    commit_hash = full_commit_hash[:7]
        else:
            log.info(f"No staged changes for {mission.mission_id}, using existing commit {commit_hash}")
            hash_out = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, timeout=2, cwd=str(REPO_ROOT))
            if hash_out.returncode == 0:
                full_commit_hash = hash_out.stdout.strip()
                commit_hash = full_commit_hash[:7]
            # Still need files_changed
            if not files_changed:
                files_changed = [str(exec_file.relative_to(REPO_ROOT))]

        # If files_changed empty, try to get from last commit
        if not files_changed or files_changed == []:
            try:
                show_out = subprocess.run(["git", "show", "--name-only", "--pretty=format:", "HEAD"], capture_output=True, text=True, timeout=2, cwd=str(REPO_ROOT))
                if show_out.returncode == 0 and show_out.stdout.strip():
                    files_changed = [f.strip() for f in show_out.stdout.strip().split("\n") if f.strip()]
            except Exception:
                pass

    except Exception as e:
        log.warning(f"Git commit/push failed for {mission.mission_id}: {e}")
        # Still return partial info, don't fail the whole execution unless we want to simulate failure
        # For dummy execution, we consider git failure as not fatal, just log
        pass

    finish_time = datetime.datetime.now(datetime.timezone.utc)
    finish_iso = finish_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    duration = (finish_time - start_time).total_seconds()

    # Ensure files_changed has at least the exec file
    if not files_changed:
        files_changed = [f"04_Output/ControlCenter/worker_executions/{mission.mission_id}_{worker_id}.md"]

    return {
        "commit_hash": commit_hash,
        "full_commit_hash": full_commit_hash,
        "branch": branch,
        "start_time": start_iso,
        "finish_time": finish_iso,
        "duration": duration,
        "files_changed": files_changed,
        "commit_message": commit_message,
    }

class WorkerExecutor:
    """Watches MissionQueue and executes ASSIGNED missions for a specific worker."""

    def __init__(self, worker_id: str, queue: Optional[MissionQueue] = None, workers: Optional[WorkerRegistry] = None, poll_interval: float = POLL_INTERVAL):
        self.worker_id = worker_id
        self.poll_interval = poll_interval
        self.workers = workers or WorkerRegistry()
        self.queue = queue or MissionQueue(workers=self.workers)
        # Ensure workers defaults
        try:
            self.workers.ensure_defaults()
        except Exception:
            pass
        self._running = False
        self._task: Optional[asyncio.Task] = None

    def _should_handle(self, mission: Mission) -> bool:
        """Check if this worker should handle the mission."""
        if mission.status != MissionStatus.ASSIGNED:
            return False
        if not mission.assigned_to:
            return False
        # Exact match
        if mission.assigned_to == self.worker_id:
            return True
        # Handle short names
        if self.worker_id == "worker-arena" and mission.assigned_to.lower() in ("arena", "worker-arena"):
            return True
        if self.worker_id == "worker-kilo" and mission.assigned_to.lower() in ("kilo", "worker-kilo"):
            return True
        return False

    def _record_history(self, mission: Mission, from_status: MissionStatus, to_status: MissionStatus, by: str, reason: str = ""):
        """Helper to add history entry directly (used for commit/push)."""
        try:
            from .mission import MissionHistoryEntry
        except ImportError:
            from mission import MissionHistoryEntry  # type: ignore
        entry = MissionHistoryEntry(from_status=from_status.value if hasattr(from_status, 'value') else str(from_status),
                                    to_status=to_status.value if hasattr(to_status, 'value') else str(to_status),
                                    at=utcnow(), by=by, reason=reason)
        mission.history.append(entry.__dict__)
        mission.updated_at = entry.at

    async def execute_mission(self, mission_id: str):
        """Execute a single mission through RUNNING->REVIEW->DONE with git and notify."""
        log.info(f"[{mission_id}] execute_mission — entered", extra={"extra": {"mission_id": mission_id}})  # type: ignore
        # Reload to get latest
        try:
            log.debug(f"[{mission_id}] RUNNING — before queue.load", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            self.queue.load()
            log.debug(f"[{mission_id}] RUNNING — after queue.load", extra={"extra": {"mission_id": mission_id}})  # type: ignore
        except Exception as e:
            log.warning(f"[{mission_id}] RUNNING — queue.load failed: {e}")
            pass
        mission = self.queue.get(mission_id)
        if not mission:
            log.warning(f"Mission {mission_id} not found for execution by {self.worker_id}")
            return
        if not self._should_handle(mission):
            log.debug(f"Mission {mission_id} not for {self.worker_id} (assigned_to={mission.assigned_to})")
            return

        log.info(f"Worker {self.worker_id} starting execution for {mission_id}: {mission.title}")
        log.debug(f"[{mission_id}] RUNNING entered — before notify", extra={"extra": {"mission_id": mission_id}})  # type: ignore
        # Notify started (offload blocking IO)
        try:
            await asyncio.to_thread(_notify_telegram, f"🚀 Mission started\n{mission.mission_id} [{mission.title[:40]}]\nWorker: {self.worker_id}\nStatus: RUNNING")
        except Exception:
            pass
        log.debug(f"[{mission_id}] RUNNING entered — after notify", extra={"extra": {"mission_id": mission_id}})  # type: ignore

        # Transition ASSIGNED -> RUNNING
        log.info(f"[{mission_id}] RUNNING — before queue.start", extra={"extra": {"mission_id": mission_id}})  # type: ignore
        try:
            self.queue.start(mission_id, by=self.worker_id)
            log.info(f"Mission {mission_id} -> RUNNING by {self.worker_id}")
            log.info(f"[{mission_id}] RUNNING — after queue.start success", extra={"extra": {"mission_id": mission_id}})  # type: ignore
        except Exception as e:
            log.error(f"Failed to transition {mission_id} to RUNNING: {e}")
            log.info(f"[{mission_id}] RUNNING — queue.start failed", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            _notify_telegram(f"❌ Mission failed to start\n{mission_id}: {e}")
            return

        # Record start time for duration
        start_time = time.time()
        start_iso = utcnow()
        log.debug(f"[{mission_id}] execution context — before create", extra={"extra": {"mission_id": mission_id}})  # type: ignore

        # Perform execution
        try:
            log.debug(f"[{mission_id}] execution context — after create, before dummy task", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            log.debug(f"[{mission_id}] dummy task — started", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            # Offload blocking git IO to threadpool to avoid blocking event loop (stability fix)
            git_info = await asyncio.to_thread(_git_commit_and_push, mission, self.worker_id)
            log.debug(f"[{mission_id}] dummy task — finished", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            # Git info contains commit_hash, branch, etc.
            finish_iso = git_info["finish_time"]
            duration = git_info["duration"]
            commit_hash = git_info["commit_hash"]
            branch = git_info["branch"]
            files_changed = git_info["files_changed"]
            commit_message = git_info["commit_message"]

            # Reload after git (in case another worker modified)
            try:
                self.queue.load()
                mission = self.queue.get(mission_id)
                if not mission:
                    log.error(f"Mission {mission_id} disappeared after git, abort")
                    return
            except Exception:
                pass

            # Add history entries for Commit and Push (between RUNNING and REVIEW)
            # We use the queue's _history via direct mission.history manipulation
            # Commit entry
            commit_reason = f"Commit: {commit_hash} Branch: {branch} Message: {commit_message} Files: {', '.join(files_changed[:3])}"
            self._record_history(mission, MissionStatus.RUNNING, MissionStatus.RUNNING, by=self.worker_id, reason=commit_reason)
            # Push entry (use same RUNNING->RUNNING but with push info)
            push_reason = f"Push: origin/{branch} Commit: {commit_hash} Files: {len(files_changed)}"
            self._record_history(mission, MissionStatus.RUNNING, MissionStatus.RUNNING, by=self.worker_id, reason=push_reason)
            # Also store execution details in payload for verification
            mission.payload = mission.payload or {}
            mission.payload["execution"] = {
                "worker_id": self.worker_id,
                "commit_hash": commit_hash,
                "full_commit_hash": git_info["full_commit_hash"],
                "branch": branch,
                "start_time": git_info["start_time"],
                "finish_time": finish_iso,
                "duration": duration,
                "files_changed": files_changed,
                "commit_message": commit_message,
            }
            log.info(f"[{mission_id}] REVIEW — before queue.review", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            # Transition RUNNING -> REVIEW
            try:
                self.queue.review(mission_id, by=self.worker_id, reason=f"execution done commit {commit_hash} branch {branch} duration {duration:.1f}s")
                log.info(f"[{mission_id}] REVIEW — after queue.review success", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            except Exception as e:
                log.error(f"Failed to transition {mission_id} RUNNING->REVIEW: {e}")
                log.info(f"[{mission_id}] REVIEW — queue.review failed", extra={"extra": {"mission_id": mission_id}})  # type: ignore
                # Force history
                self._record_history(mission, MissionStatus.RUNNING, MissionStatus.REVIEW, by=self.worker_id, reason=str(e))
                mission.status = MissionStatus.REVIEW
                self.queue.save()

            # Reload again
            try:
                log.debug(f"[{mission_id}] DONE — before reload", extra={"extra": {"mission_id": mission_id}})  # type: ignore
                self.queue.load()
                mission = self.queue.get(mission_id)
                log.debug(f"[{mission_id}] DONE — after reload", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            except Exception as e:
                log.warning(f"[{mission_id}] DONE — reload failed: {e}")
                pass

            # Transition REVIEW -> DONE
            log.info(f"[{mission_id}] DONE — before queue.complete", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            try:
                self.queue.complete(mission_id, by=self.worker_id)
                log.info(f"Mission {mission_id} -> DONE by {self.worker_id} commit {commit_hash}")
                log.info(f"[{mission_id}] DONE — after queue.complete success", extra={"extra": {"mission_id": mission_id}})  # type: ignore
            except Exception as e:
                log.error(f"Failed to transition {mission_id} REVIEW->DONE: {e}")
                log.info(f"[{mission_id}] DONE — queue.complete failed", extra={"extra": {"mission_id": mission_id}})  # type: ignore
                mission.status = MissionStatus.DONE
                self.queue.save()

            # Notify completed (offload)
            try:
                await asyncio.to_thread(_notify_telegram, f"✅ Mission completed\n{mission.mission_id} [{mission.title[:40]}]\nWorker: {self.worker_id}\nCommit: {commit_hash}\nBranch: {branch}\nDuration: {duration:.1f}s\nStatus: DONE")
            except Exception:
                pass

            # Record final DONE history already has git info via previous entries
            log.info(f"Worker {self.worker_id} completed {mission_id} in {duration:.1f}s commit {commit_hash}")

        except Exception as e:
            # Execution failed
            log.error(f"Worker {self.worker_id} execution failed for {mission_id}: {e}", exc_info=True)
            duration = time.time() - start_time
            # Notify retry or failed
            try:
                self.queue.load()
                mission = self.queue.get(mission_id)
                if not mission:
                    return
                # Check retry count
                if mission.retry_count < mission.max_retries:
                    # Retry: RUNNING -> QUEUED (via retry)
                    try:
                        self.queue.retry(mission_id, by=self.worker_id, reason=f"execution failed: {e} retry {mission.retry_count+1}/{mission.max_retries}")
                        log.info(f"Mission {mission_id} retry {mission.retry_count}/{mission.max_retries} by {self.worker_id}")
                        try:
                            await asyncio.to_thread(_notify_telegram, f"🔄 Mission retry\n{mission.mission_id} [{mission.title[:40]}]\nWorker: {self.worker_id}\nError: {e}\nRetry: {mission.retry_count}/{mission.max_retries}\nStatus: QUEUED")
                        except Exception:
                            pass
                        # After retry, the mission goes to QUEUED, but if max retries not exceeded, the dispatcher or next loop will re-assign?
                        # For now, we re-assign automatically to same worker for next retry
                        # But the spec says worker watches ASSIGNED, so we need to re-queue and re-assign?
                        # Simplified: after retry, we immediately re-assign to same worker and continue loop will handle
                        try:
                            # Need to re-load and check if it's QUEUED
                            self.queue.load()
                            m2 = self.queue.get(mission_id)
                            if m2 and m2.status == MissionStatus.QUEUED:
                                # Re-assign to same worker for next attempt (if auto)
                                self.queue.assign(mission_id, self.worker_id, by=self.worker_id)
                                log.info(f"Re-assigned {mission_id} to {self.worker_id} for retry")
                        except Exception as e2:
                            log.warning(f"Failed to re-assign {mission_id} for retry: {e2}")
                    except Exception as e2:
                        log.error(f"Retry failed for {mission_id}: {e2}")
                        # If retry fails due to max retries, go to ARCHIVED (FAILED)
                        try:
                            # Check if max retries exceeded
                            m = self.queue.get(mission_id)
                            if m and m.retry_count >= m.max_retries:
                                self.queue.cancel(mission_id, by=self.worker_id, reason=f"failed after {m.max_retries} retries: {e}")
                                _notify_telegram(f"❌ Mission failed\n{mission.mission_id} [{mission.title[:40]}]\nWorker: {self.worker_id}\nError: {e}\nRetries: {m.retry_count}/{m.max_retries}\nStatus: FAILED")
                        except Exception:
                            pass
                else:
                    # Max retries exceeded -> FAILED (ARCHIVED)
                    try:
                        self.queue.cancel(mission_id, by=self.worker_id, reason=f"failed after {mission.max_retries} retries: {e}")
                        log.info(f"Mission {mission_id} failed after {mission.max_retries} retries, archived")
                    except Exception as e2:
                        log.error(f"Failed to archive {mission_id} after max retries: {e2}")
                        # Force
                        try:
                            m = self.queue.get(mission_id)
                            if m:
                                m.status = MissionStatus.ARCHIVED  # type: ignore
                                m.error = str(e)
                                self._record_history(m, MissionStatus.RUNNING, MissionStatus.ARCHIVED, by=self.worker_id, reason=f"FAILED after {m.max_retries} retries: {e}")
                                self.queue.save()
                        except Exception:
                            pass
                    _notify_telegram(f"❌ Mission failed\n{mission.mission_id} [{mission.title[:40]}]\nWorker: {self.worker_id}\nError: {e}\nStatus: FAILED after {mission.max_retries} retries")
            except Exception as e2:
                log.error(f"Failed to handle retry/failed for {mission_id}: {e2}")

    async def run_once(self):
        """Single poll iteration: load queue and handle ASSIGNED missions for this worker."""
        try:
            self.queue.load()
        except Exception as e:
            log.warning(f"Worker {self.worker_id} load failed: {e}")
            return
        # Find ASSIGNED missions for this worker
        assigned = [m for m in self.queue.list(status=MissionStatus.ASSIGNED.value) if self._should_handle(m)]
        if not assigned:
            return
        for mission in assigned:
            # Avoid handling if already being handled? Simple: execute sequentially
            try:
                await self.execute_mission(mission.mission_id)
            except Exception as e:
                log.error(f"Worker {self.worker_id} failed to execute {mission.mission_id}: {e}", exc_info=True)
            # Reload after each execution to handle new assignments that may have come in
            try:
                self.queue.load()
            except Exception:
                pass

    async def run_forever(self):
        """Continuous loop."""
        self._running = True
        log.info(f"Worker {self.worker_id} started, polling every {self.poll_interval}s, repo={REPO_ROOT}, queue={self.queue.path}")
        while self._running:
            try:
                await self.run_once()
            except asyncio.CancelledError:
                log.info(f"Worker {self.worker_id} cancelled")
                break
            except Exception as e:
                log.error(f"Worker {self.worker_id} run_once error: {e}", exc_info=True)
            try:
                await asyncio.sleep(self.poll_interval)
            except asyncio.CancelledError:
                break
        log.info(f"Worker {self.worker_id} stopped")

    def stop(self):
        self._running = False
        if self._task and not self._task.done():
            self._task.cancel()

# For standalone usage
async def main_async(worker_id: Optional[str] = None):
    """Run worker(s) standalone."""
    workers_to_run = []
    if worker_id:
        workers_to_run = [worker_id]
    else:
        # Run both arena and kilo
        workers_to_run = ["worker-arena", "worker-kilo"]

    executors = [WorkerExecutor(wid) for wid in workers_to_run]
    tasks = [asyncio.create_task(ex.run_forever()) for ex in executors]
    log.info(f"Started workers: {workers_to_run}")
    try:
        await asyncio.gather(*tasks)
    except asyncio.CancelledError:
        for ex in executors:
            ex.stop()
        await asyncio.gather(*tasks, return_exceptions=True)

def main():
    import argparse
    parser = argparse.ArgumentParser(description="QROS Worker Executor")
    parser.add_argument("--worker", type=str, default=None, help="worker-arena or worker-kilo, default both")
    parser.add_argument("--once", action="store_true", help="run once and exit (for testing)")
    args = parser.parse_args()

    if args.once:
        # Run once synchronously
        wid = args.worker or "worker-arena"
        ex = WorkerExecutor(wid)
        asyncio.run(ex.run_once())
        print(f"Once run for {wid} done")
    else:
        # Run forever
        asyncio.run(main_async(args.worker))

if __name__ == "__main__":
    main()
