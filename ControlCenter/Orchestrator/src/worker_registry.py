"""
QROS Worker Registry — Arena + Kilo (Stage 3).
"""
from __future__ import annotations

import json
import pathlib
from dataclasses import dataclass, field, asdict
from typing import Dict, List

try:
    from .mission import utcnow
except ImportError:
    from mission import utcnow

ROOT = pathlib.Path(__file__).resolve().parents[3]
DATA_PATH = ROOT / "ControlCenter" / "data" / "workers.json"
OUTPUT_PATH = ROOT / "04_Output" / "ControlCenter" / "workers.json"

@dataclass
class Worker:
    worker_id: str
    role: str
    status: str = "ACTIVE"
    last_heartbeat: str = ""
    capabilities: List[str] = field(default_factory=list)
    endpoint: str = ""

    def to_dict(self):
        return asdict(self)

class WorkerRegistry:
    def __init__(self, path: pathlib.Path | None = None):
        self.path = path or DATA_PATH
        self.workers: Dict[str, Worker] = {}
        self.load()

    def load(self):
        if self.path.is_file():
            try:
                data = json.loads(self.path.read_text(encoding="utf-8"))
                for w in data.get("workers", []):
                    self.workers[w["worker_id"]] = Worker(**w)
            except Exception:
                self.workers = {}

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"workers": [w.to_dict() for w in self.workers.values()], "updated_at": utcnow()}
        self.path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        try:
            if self.path.resolve() == DATA_PATH.resolve():
                OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
                OUTPUT_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        except Exception:
            pass

    def register(self, worker_id: str, role: str, capabilities: List[str] | None = None, endpoint: str = "") -> Worker:
        w = self.workers.get(worker_id)
        if w:
            w.status = "ACTIVE"
            w.last_heartbeat = utcnow()
            if capabilities:
                w.capabilities = capabilities
            if endpoint:
                w.endpoint = endpoint
        else:
            w = Worker(worker_id=worker_id, role=role, status="ACTIVE", last_heartbeat=utcnow(), capabilities=capabilities or [], endpoint=endpoint)
            self.workers[worker_id] = w
        self.save()
        return w

    def heartbeat(self, worker_id: str) -> bool:
        w = self.workers.get(worker_id)
        if not w:
            return False
        w.last_heartbeat = utcnow()
        w.status = "ACTIVE"
        self.save()
        return True

    def list_active(self) -> List[Worker]:
        return [w for w in self.workers.values() if w.status == "ACTIVE"]

    def get(self, worker_id: str) -> Worker | None:
        return self.workers.get(worker_id)

    def ensure_defaults(self):
        self.register("worker-arena", "arena", ["arena", "git", "queue", "docker"], endpoint="http://arena:8000")
        self.register("worker-kilo", "kilo", ["kilo", "local", "mt5", "build"], endpoint="http://kilo:8000")

    def is_registered(self, worker_id: str) -> bool:
        return worker_id in self.workers and self.workers[worker_id].status == "ACTIVE"
