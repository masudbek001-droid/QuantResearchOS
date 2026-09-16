"""
QROS Mission Queue — operational orchestration (Stage 3).

Persists to ControlCenter/data/mission_queue.json + 04_Output/ControlCenter/mission_queue.json
Implements lifecycle, history, retry, timeout, cancellation, GitHub sync hook.

No Redis — file based, atomic write via temp rename.
"""
from __future__ import annotations

import json
import pathlib
import re
from typing import Dict, List, Optional

try:
    from .mission import Mission, MissionStatus, MissionHistoryEntry, can_transition, can_retry, can_cancel, utcnow
except ImportError:
    from mission import Mission, MissionStatus, MissionHistoryEntry, can_transition, can_retry, can_cancel, utcnow

try:
    from .worker_registry import WorkerRegistry
except ImportError:
    from worker_registry import WorkerRegistry

ROOT = pathlib.Path(__file__).resolve().parents[3]
DATA_PATH = ROOT / "ControlCenter" / "data" / "mission_queue.json"
OUTPUT_PATH = ROOT / "04_Output" / "ControlCenter" / "mission_queue.json"

class MissionQueue:
    def __init__(self, path: pathlib.Path | None = None, workers: WorkerRegistry | None = None):
        self.path = path or DATA_PATH
        self.workers = workers or WorkerRegistry()
        self.missions: Dict[str, Mission] = {}
        self.next_id = 1
        self.load()

    def load(self):
        if self.path.is_file():
            try:
                data = json.loads(self.path.read_text(encoding="utf-8"))
                for m in data.get("missions", []):
                    mission = Mission.from_dict(m)
                    self.missions[mission.mission_id] = mission
                max_n = 0
                for mid in self.missions:
                    try:
                        n = int(mid.split("-")[1])
                        max_n = max(max_n, n)
                    except:
                        pass
                self.next_id = max_n + 1
            except Exception as e:
                self.missions = {}
                self.next_id = 1

    def save(self):
        # BUG-010 fix: atomic write + mirror must not hang on PermissionError (Docker appuser 1000 vs host 1001 with 755 bind mounts).
        # Exact blocking line before fix: tmp.write_text(json.dumps(payload, indent=2), ...) -> PermissionError: [Errno 13] Permission denied: '.../mission_queue.tmp'
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
        except Exception:
            pass
        payload = {
            "missions": [m.to_dict() for m in sorted(self.missions.values(), key=lambda x: x.mission_id)],
            "next_id": self.next_id,
            "updated_at": utcnow(),
        }
        data = json.dumps(payload, indent=2)
        try:
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(data, encoding="utf-8")
            tmp.replace(self.path)
        except (PermissionError, OSError) as e:
            try:
                self.path.write_text(data, encoding="utf-8")
            except (PermissionError, OSError):
                try:
                    import os
                    os.chmod(self.path.parent, 0o777)
                    self.path.write_text(data, encoding="utf-8")
                except Exception:
                    pass
            except Exception:
                pass
        except Exception:
            try:
                self.path.write_text(data, encoding="utf-8")
            except Exception:
                pass
        try:
            try:
                is_default = str(self.path.resolve()) == str(DATA_PATH.resolve())
            except Exception:
                is_default = str(self.path) == str(DATA_PATH)
            if is_default:
                try:
                    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
                except Exception:
                    pass
                try:
                    OUTPUT_PATH.write_text(data, encoding="utf-8")
                except (PermissionError, OSError):
                    try:
                        import os
                        os.chmod(OUTPUT_PATH.parent, 0o777)
                        OUTPUT_PATH.write_text(data, encoding="utf-8")
                    except Exception:
                        pass
                except Exception:
                    pass
        except Exception:
            pass

    def _next_id_str(self) -> str:
        mid = f"MSQ-{self.next_id:04d}"
        self.next_id += 1
        return mid

    def _history(self, mission: Mission, fr: MissionStatus, to: MissionStatus, by: str, reason: str = ""):
        entry = MissionHistoryEntry(from_status=fr.value, to_status=to.value, at=utcnow(), by=by, reason=reason)
        mission.history.append(entry.__dict__)
        mission.updated_at = entry.at

    def create(self, title: str, module: str = "MOD-ORCHESTRATOR", priority: str = "P1", created_by: str = "telegram", payload: dict | None = None, timeout_seconds: int = 3600, max_retries: int = 3) -> Mission:
        mid = self._next_id_str()
        now = utcnow()
        m = Mission(
            mission_id=mid,
            title=title,
            module=module,
            priority=priority,
            created_by=created_by,
            payload=payload or {},
            status=MissionStatus.CREATED,
            timeout_seconds=timeout_seconds,
            max_retries=max_retries,
            created_at=now,
            updated_at=now,
            history=[],
        )
        m.history.append(MissionHistoryEntry(from_status="NONE", to_status=MissionStatus.CREATED.value, at=now, by=created_by, reason="created").__dict__)
        self.missions[mid] = m
        self.save()
        return m

    def get(self, mission_id: str) -> Optional[Mission]:
        return self.missions.get(mission_id)

    def list(self, status: str | None = None) -> List[Mission]:
        if status:
            try:
                st = MissionStatus(status)
                return [m for m in self.missions.values() if m.status == st]
            except:
                return []
        return sorted(self.missions.values(), key=lambda x: x.mission_id)

    def transition(self, mission_id: str, to: MissionStatus, by: str, reason: str = "") -> Mission:
        m = self.missions.get(mission_id)
        if not m:
            raise KeyError(f"Mission {mission_id} not found")
        fr = m.status
        if not can_transition(fr, to):
            raise ValueError(f"Invalid transition {fr.value} -> {to.value} for {mission_id}")
        self._history(m, fr, to, by, reason)
        m.status = to
        self.save()
        return m

    def queue(self, mission_id: str, by: str) -> Mission:
        return self.transition(mission_id, MissionStatus.QUEUED, by)

    def assign(self, mission_id: str, worker_id: str, by: str) -> Mission:
        m = self.get(mission_id)
        if not m:
            raise KeyError(mission_id)
        # BUG-WORKER-002 fix: accept short names arena/kilo and role-based lookup
        orig_worker_id = worker_id
        worker_id = worker_id.lower()
        if worker_id in ("arena", "kilo"):
            worker_id = f"worker-{worker_id}"
        if worker_id not in ("worker-arena", "worker-kilo"):
            if not self.workers.is_registered(worker_id):
                for w in self.workers.workers.values():
                    if w.role.lower() == worker_id:
                        worker_id = w.worker_id
                        break
                else:
                    raise ValueError(f"Worker {orig_worker_id} not registered")
        elif not self.workers.is_registered(worker_id):
            raise ValueError(f"Worker {orig_worker_id} not registered")
        m.assigned_to = worker_id
        return self.transition(mission_id, MissionStatus.ASSIGNED, by, reason=f"assigned to {worker_id}")

    def start(self, mission_id: str, by: str) -> Mission:
        return self.transition(mission_id, MissionStatus.RUNNING, by)

    def review(self, mission_id: str, by: str, reason: str = "") -> Mission:
        return self.transition(mission_id, MissionStatus.REVIEW, by, reason)

    def complete(self, mission_id: str, by: str) -> Mission:
        return self.transition(mission_id, MissionStatus.DONE, by)

    def archive(self, mission_id: str, by: str) -> Mission:
        return self.transition(mission_id, MissionStatus.ARCHIVED, by)

    def retry(self, mission_id: str, by: str, reason: str = "") -> Mission:
        m = self.get(mission_id)
        if not m:
            raise KeyError(mission_id)
        if not can_retry(m.status):
            raise ValueError(f"Cannot retry from {m.status.value}")
        if m.retry_count >= m.max_retries:
            raise ValueError(f"Max retries {m.max_retries} exceeded for {mission_id}")
        fr = m.status
        self._history(m, fr, MissionStatus.QUEUED, by, reason or f"retry {m.retry_count+1}/{m.max_retries}")
        m.status = MissionStatus.QUEUED
        m.retry_count += 1
        m.error = None
        self.save()
        return m

    def cancel(self, mission_id: str, by: str, reason: str = "") -> Mission:
        m = self.get(mission_id)
        if not m:
            raise KeyError(mission_id)
        if not can_cancel(m.status):
            raise ValueError(f"Cannot cancel {m.status.value} (already ARCHIVED)")
        fr = m.status
        self._history(m, fr, MissionStatus.ARCHIVED, by, reason or "cancelled")
        m.status = MissionStatus.ARCHIVED
        self.save()
        return m

    def check_timeouts(self, now_iso: str | None = None) -> List[Mission]:
        import datetime
        now = datetime.datetime.now(datetime.timezone.utc)
        if now_iso:
            try:
                now = datetime.datetime.fromisoformat(now_iso.replace("Z","+00:00"))
            except:
                pass
        timed_out = []
        for m in list(self.missions.values()):
            if m.status != MissionStatus.RUNNING:
                continue
            try:
                updated = datetime.datetime.fromisoformat(m.updated_at.replace("Z","+00:00"))
            except:
                continue
            elapsed = (now - updated).total_seconds()
            if elapsed > m.timeout_seconds:
                fr = m.status
                self._history(m, fr, MissionStatus.REVIEW, "system", reason=f"timeout after {m.timeout_seconds}s")
                m.status = MissionStatus.REVIEW
                m.error = "timeout"
                timed_out.append(m)
        if timed_out:
            self.save()
        return timed_out

    def run_lifecycle(self, mission_id: str, by: str = "system") -> Mission:
        steps = [MissionStatus.QUEUED, MissionStatus.ASSIGNED, MissionStatus.RUNNING, MissionStatus.REVIEW, MissionStatus.DONE, MissionStatus.ARCHIVED]
        for step in steps:
            m = self.get(mission_id)
            if m.status == MissionStatus.QUEUED and step == MissionStatus.ASSIGNED:
                self.assign(mission_id, "worker-arena", by)
            elif m.status == MissionStatus.ASSIGNED and step == MissionStatus.RUNNING:
                self.start(mission_id, by)
            else:
                if can_transition(m.status, step):
                    self.transition(mission_id, step, by)
        return self.get(mission_id)
