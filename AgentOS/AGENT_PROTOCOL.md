# AgentOS — Agent Protocol v1.0 (MVP)

**Status:** Active — Minimum infrastructure for autonomous multi-agent collaboration through GitHub.
**Applies to:** All workers on `QuantResearchOS` from 2026-09-15.
**Out of scope:** Telegram, trading logic (`01_Source/EA/MQL5` MIPS v1.0), AI advisory modules (`EAContext*Advisory`, `AICouncil`, `ContinuousLearning`) — read-only via AgentOS.
**Authority:** This protocol is Git-native; Git history is the single source of truth.

---

## 1. Principles

1. **Git is the bus.** No direct agent-to-agent messages, no shared memory, no assumed presence. Every interaction is a committed file + `git push` to `origin`.
2. **One module, one owner.** Every worker owns **exactly one** module (see `OWNERSHIP_MAP.md`). Cross-module writes require a `LOCK` + `TASK` + `DECISION`.
3. **No assumptions.** Workers do not assume another worker exists, is alive, or will reply. They poll `TASK_QUEUE`, `REPORT_QUEUE`, `EVENT_BUS` after `git pull`.
4. **Pull before act.** Before any read or write: `git fetch origin && git pull --ff-only`. Before any push: `git pull --rebase`.
5. **Branch per task.** Format `worker/<worker-id>/<task-id>` (e.g., `worker/worker-research/TASK-0007`). Never commit directly to `main` or `arena/*` without a task.
6. **Commit is communication.** Message format: `[AgentOS][<TASK_ID>][<worker-id>] <verb>: <what> — <why>` e.g., `[AgentOS][TASK-0003][worker-dal] claim: 02_Databases/README — walk-forward sync`.
7. **Advisory only chain preserved.** No worker may modify trading entry/exit/risk/momentum or AI advisory multipliers unless an ADR explicitly authorizes and Strategy Tester gates pass — same freeze as before.

---

## 2. Roles

| Role | Owns | Can do |
|---|---|---|
| **Orchestrator** (`worker-agentos`) | `AgentOS/` | Creates tasks, assigns, resolves conflicts, merges reports, appends to `DECISION_LOG`, `EVENT_BUS`. Only role that may merge to `main`/`arena/*` via PR. |
| **Module Worker** (`worker-*`) | One module from `OWNERSHIP_MAP.md` | Claims tasks for owned module, locks paths, works on branch, pushes, creates report, emits event, releases lock. |

No worker may write outside its owned paths unless holding a lock (see `LOCK_MANAGER.md`).

---

## 3. Communication Channels (all Git files)

| Channel | File | Writer | Reader | Ordering |
|---|---|---|---|---|
| Tasks | `AgentOS/TASK_QUEUE.md` | Orchestrator (create), Worker (claim/update) | All | TaskID monotonic |
| Reports | `AgentOS/REPORT_QUEUE.md` | Worker (create) | Orchestrator | ReportID monotonic |
| Locks | `AgentOS/LOCK_MANAGER.md` | Worker (acquire/release) via PR | All | File path unique |
| Events | `AgentOS/EVENT_BUS.md` | Any worker after state change | All | EventID monotonic, append-only |
| Decisions | `AgentOS/DECISION_LOG.md` | Orchestrator (append) | All | DecisionID monotonic, append-only |
| Registry | `AgentOS/WORKER_REGISTRY.md` | Orchestrator (register/heartbeat) | All | WorkerID unique |
| Ownership | `AgentOS/OWNERSHIP_MAP.md` | Orchestrator (ADR-gated) | All | Module unique |

Direct file edits without going through the queue are forbidden — treat queue files as the API.

---

## 4. Task Lifecycle

```
OPEN → CLAIMED → IN_PROGRESS → REVIEW → DONE
  │        │          │          │
  └→ BLOCKED → OPEN   └→ CANCELLED
```

1. **OPEN:** Orchestrator appends row to `TASK_QUEUE.md` (TaskID, Title, Module, Priority, Files). Emits `task.created` to `EVENT_BUS`.
2. **CLAIM:** Worker `git pull`, checks ownership (its module) + no active lock on files, writes `Owner=<worker-id>`, `Status=CLAIMED`, sets lock via `LOCK_MANAGER.md`, pushes branch, emits `task.claimed`.
3. **IN_PROGRESS:** Worker moves to `IN_PROGRESS`, works on `worker/<id>/<task>` branch, commits to owned paths only.
4. **REVIEW:** Worker pushes branch, appends to `REPORT_QUEUE.md` (ReportID, TaskID, Verdict, Artifacts, Status=PENDING), sets `TASK_QUEUE.Status=REVIEW`, emits `report.created`.
5. **DONE:** Orchestrator reviews, merges PR, sets `TASK_QUEUE.Status=DONE`, `REPORT_QUEUE.Status=APPROVED`, releases lock, emits `task.completed`.

Timeouts: `CLAIMED` → 24h without `IN_PROGRESS` reverts to `OPEN`. `IN_PROGRESS` → 72h without report emits `task.stalled`.

---

## 5. Locking

* One file path → at most one active lock. Lock row: `Path | Worker | TaskID | Acquired (UTC) | Expires (UTC) | Status=ACTIVE`.
* Acquire: Worker adds row to `LOCK_MANAGER.md`, pushes. If path already ACTIVE → reject, emit `lock.denied`.
* Release: Worker sets `Status=RELEASED` after `DONE` or `CANCELLED`.
* Expiry: Orchestrator sweeps hourly (UTC) — `Expires < now()` → `Status=EXPIRED`, emits `lock.expired`, task reopens.

No worker may write to a path it does not own **and** does not lock.

---

## 6. Reporting & Events

* Report must link `TaskID`, include `Verdict=PASS/FAIL/BLOCKED`, `Artifacts` (paths), `Evidence` (log snippet), `Timestamp UTC`.
* Event is append-only: `EventID | Timestamp UTC | Emitter | Type | CorrelationID | Payload JSON`. Types: `task.created|claimed|completed`, `report.created|approved`, `lock.acquired|released|denied|expired`, `decision.recorded`, `worker.heartbeat`.

---

## 7. Branch & Merge

* Worker branch from `origin/arena/*` or `main` as orchestrator instructs.
* PR title: `[AgentOS][TASK-xxxx] <title> — <worker-id>`
* PR description must link `TASK_QUEUE TaskID` + `REPORT_QUEUE ReportID`.
* Only `worker-agentos` merges after `REPORT_QUEUE.Status=APPROVED` + no lock conflict.

---

## 8. Safety Invariants (enforced by `AgentOS/tools/validate.py`)

* `OWNERSHIP_MAP.Module` unique, Worker owns exactly one Module.
* `WORKER_REGISTRY.WorkerID` unique, `ModuleOwned` matches ownership.
* `LOCK_MANAGER` has no duplicate ACTIVE path.
* `TASK_QUEUE.TaskID` monotonic, Status ∈ valid set.
* `REPORT_QUEUE` every report links to existing TaskID.
* `EVENT_BUS` EventID monotonic, `DECISION_LOG` append-only.
* No commits touch `01_Source/EA/MQL5` trading core or `EAContext*Advisory` without ADR.

Violations → CI fails, merge blocked.

---

## 9. Heartbeat & Liveness

Worker appends `worker.heartbeat` to `EVENT_BUS` + updates `WORKER_REGISTRY.LastHeartbeat` every 24h. Missing 72h → `Status=INACTIVE`, orchestrator may reassign `CLAIMED` tasks.

---

## 10. Out of Scope for v1.0

* Telegram, direct RPC, chat, Slack — not implemented.
* Auto-merge without human/GH review — writes go via PR, orchestrator merges.
* Trading/AI logic changes — blocked; AgentOS is collaboration layer only.

---

## 11. Quickstart for a Worker

```bash
git fetch origin && git pull --ff-only
# 1. Find OPEN task for my module in AgentOS/TASK_QUEUE.md
# 2. Claim: edit TASK_QUEUE (Status=CLAIMED, Owner=me), LOCK_MANAGER (add row), EVENT_BUS (task.claimed) → commit → push branch
# 3. Work on owned files → commit → push
# 4. Report: append REPORT_QUEUE, set TASK_QUEUE=REVIEW → push
# 5. Wait for orchestrator merge → pull → lock released
```

See `EXAMPLE_WORKFLOW.md` for a complete traced example.
