"""
QROS Mission — lifecycle model (Stage 3).

Lifecycle:
CREATED → QUEUED → ASSIGNED → RUNNING → REVIEW → DONE → ARCHIVED

Plus:
- RETRY: RUNNING/REVIEW → QUEUED (increment retry_count)
- CANCEL: any non-ARCHIVED → ARCHIVED
- TIMEOUT: RUNNING past timeout_seconds → REVIEW (reason timeout)
- History: every transition appended
"""
from __future__ import annotations

import datetime
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import List, Dict, Any


class MissionStatus(str, Enum):
    CREATED = "CREATED"
    QUEUED = "QUEUED"
    ASSIGNED = "ASSIGNED"
    RUNNING = "RUNNING"
    REVIEW = "REVIEW"
    DONE = "DONE"
    ARCHIVED = "ARCHIVED"

# Allowed forward transitions (strict)
ALLOWED = {
    MissionStatus.CREATED: [MissionStatus.QUEUED],
    MissionStatus.QUEUED: [MissionStatus.ASSIGNED],
    MissionStatus.ASSIGNED: [MissionStatus.RUNNING],
    MissionStatus.RUNNING: [MissionStatus.REVIEW],
    MissionStatus.REVIEW: [MissionStatus.DONE],
    MissionStatus.DONE: [MissionStatus.ARCHIVED],
    MissionStatus.ARCHIVED: [],
}

# Retry: from RUNNING or REVIEW back to QUEUED
RETRY_FROM = {MissionStatus.RUNNING, MissionStatus.REVIEW}

def can_transition(fr: MissionStatus, to: MissionStatus) -> bool:
    return to in ALLOWED.get(fr, [])

def can_retry(fr: MissionStatus) -> bool:
    return fr in RETRY_FROM

def can_cancel(fr: MissionStatus) -> bool:
    return fr != MissionStatus.ARCHIVED

@dataclass
class MissionHistoryEntry:
    from_status: str
    to_status: str
    at: str  # ISO8601 UTC
    by: str  # actor worker or telegram_user_id
    reason: str = ""

@dataclass
class Mission:
    mission_id: str  # MSQ-0001
    title: str
    module: str = "MOD-ORCHESTRATOR"
    priority: str = "P1"
    created_by: str = "telegram"  # telegram_user_id or worker
    payload: Dict[str, Any] = field(default_factory=dict)
    status: MissionStatus = MissionStatus.CREATED
    assigned_to: str | None = None  # worker-arena / worker-kilo
    retry_count: int = 0
    max_retries: int = 3
    timeout_seconds: int = 3600
    created_at: str = ""
    updated_at: str = ""
    history: List[Dict[str, Any]] = field(default_factory=list)
    github_task_id: str | None = None  # mapped TaskID like TASK-0006
    error: str | None = None

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["status"] = self.status.value if isinstance(self.status, Enum) else self.status
        return d

    @staticmethod
    def from_dict(d: Dict[str, Any]) -> "Mission":
        # handle status as string
        st = d.get("status", MissionStatus.CREATED)
        if isinstance(st, str):
            try:
                st = MissionStatus(st)
            except:
                st = MissionStatus.CREATED
        d["status"] = st
        return Mission(**d)

def utcnow() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
