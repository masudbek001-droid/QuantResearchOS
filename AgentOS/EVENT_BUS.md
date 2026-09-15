# AgentOS — Event Bus v1.0

**File:** `AgentOS/EVENT_BUS.md` — Append-only ordered event log. Git history is the bus.
**Protocol:** `AGENT_PROTOCOL.md` §6 (append-only, EventID monotonic).
**Delivery:** Workers `git pull` to receive events; no push notifications. Poll interval recommended: before every queue action + every 5 min when idle.

---

## Schema

| Column | Type | Description |
|---|---|---|
| EventID | `EVT-####` | Monotonic, never reuse |
| Timestamp | `YYYY-MM-DD HH:MM:SS UTC` | UTC, second precision |
| Emitter | `worker-*` | Who emitted |
| Type | enum | `task.created, task.claimed, task.completed, task.blocked, report.created, report.approved, report.rejected, lock.acquired, lock.released, lock.denied, lock.expired, decision.recorded, worker.registered, worker.heartbeat, worker.inactive` |
| CorrelationID | `TASK-####` / `REPORT-####` / `LOCK-####` / `-` | Linked ID |
| Payload | JSON (single line) | `{ "detail": "..." }` — must be valid JSON |

---

## Bus (append-only)

| EventID | Timestamp | Emitter | Type | CorrelationID | Payload |
|---|---|---|---|---|---|
| EVT-0001 | 2026-09-15 07:35:00 UTC | worker-agentos | worker.registered | - | `{"worker":"worker-agentos","module":"MOD-AGENTOS"}` |
| EVT-0002 | 2026-09-15 07:35:00 UTC | worker-agentos | task.created | TASK-0001 | `{"title":"Verify AgentOS protocol installation","module":"MOD-AGENTOS"}` |
| EVT-0003 | 2026-09-15 07:35:00 UTC | worker-agentos | task.created | TASK-0002 | `{"title":"Validate ownership map single-owner invariant","module":"MOD-AGENTOS"}` |
| EVT-0004 | 2026-09-15 07:35:00 UTC | worker-agentos | task.created | TASK-0003 | `{"title":"Seed TASK_QUEUE with example workflow","module":"MOD-AGENTOS"}` |
| EVT-0005 | 2026-09-15 07:35:00 UTC | worker-agentos | task.created | TASK-0004 | `{"title":"Research platform benchmark deterministic replay","module":"MOD-RESEARCH"}` |

> Emitted by `AgentOS/tools/agentos_cli.py` on each state transition. Workers append by editing this file, committing `[AgentOS][TASK-xxxx][worker] event: <type>`, pushing.

---

## How to Emit (Worker/Orchestrator)

```bash
python AgentOS/tools/agentos_cli.py event emit --emitter worker-research --type task.claimed --correlation TASK-0004 --payload '{"branch":"worker/worker-research/TASK-0004"}'
# → appends row with next EventID, UTC timestamp, commits
```

## How to Poll

```bash
git fetch origin && git pull --ff-only
tail -n 20 AgentOS/EVENT_BUS.md  # new events since last seen EventID
```

## Invariants

* `EventID` monotonic, append-only, no gaps in validation (warn if gap, but allow — merges may interleave; validator checks monotonic not contiguous).
* `Timestamp` must be UTC, `Type` ∈ enum, `Payload` must be valid JSON, `Emitter` registered.
* Never delete or reorder rows; corrections emit new `compensating` event.

---

*Last event: EVT-0005 — next is EVT-0006. Poll after every `git pull`.*
