# AgentOS — Task Queue v1.0

**File:** `AgentOS/TASK_QUEUE.md` — Git-native task queue.
**Protocol:** `AGENT_PROTOCOL.md` §4.
**Ordering:** `TaskID` monotonic `TASK-0001, TASK-0002, ...`. Append-only; status updates edit row in place (Git history preserves transitions).
**States:** `OPEN, CLAIMED, IN_PROGRESS, REVIEW, DONE, BLOCKED, CANCELLED`

> Workers: `git pull` before reading. Claim only tasks for your owned module (see `OWNERSHIP_MAP.md`). Acquire lock first (see `LOCK_MANAGER.md`).

---

## Schema (per row)

| Column | Type | Description |
|---|---|---|
| TaskID | `TASK-####` | Monotonic, zero-padded 4 |
| Title | string | Short verb + object |
| Module | `MOD-*` | Must exist in `OWNERSHIP_MAP.md` |
| Owner | `worker-*` or `-` | `-` when OPEN/BLOCKED |
| Status | enum | See above |
| Priority | `P0..P3` | P0 critical, P3 low |
| Files | path glob | Paths task intends to touch (for lock) |
| Branch | `worker/<id>/<task>` or `-` | Created on CLAIM |
| Created | `YYYY-MM-DD HH:MM UTC` | UTC |
| Updated | `YYYY-MM-DD HH:MM UTC` | UTC |

Machine-readable JSON mirror (append after table edits, keep synced):
```json
// AgentOS/queue_tasks.json is canonical for tooling; this MD is human view.
// Tool: AgentOS/tools/agentos_cli.py syncs MD ↔ JSON.
```

---

## Queue

| TaskID | Title | Module | Owner | Status | Priority | Files | Branch | Created | Updated |
|---|---|---|---|---|---|---|---|---|---|
| TASK-0001 | Verify AgentOS protocol installation | MOD-AGENTOS | - | OPEN | P0 | `AgentOS/AGENT_PROTOCOL.md` | - | 2026-09-15 07:35 UTC | 2026-09-15 07:35 UTC |
| TASK-0002 | Validate ownership map single-owner invariant | MOD-AGENTOS | - | OPEN | P0 | `AgentOS/OWNERSHIP_MAP.md` | - | 2026-09-15 07:35 UTC | 2026-09-15 07:35 UTC |
| TASK-0003 | Seed TASK_QUEUE with example workflow | MOD-AGENTOS | - | OPEN | P1 | `AgentOS/TASK_QUEUE.md` | - | 2026-09-15 07:35 UTC | 2026-09-15 07:35 UTC |
| TASK-0004 | Research platform benchmark deterministic replay | MOD-RESEARCH | - | OPEN | P1 | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAResearch/**` | - | 2026-09-15 07:35 UTC | 2026-09-15 07:35 UTC |
| TASK-0005 | Build Market Digital Twin — single source of truth simulator | MOD-TWIN | worker-twin | DONE | P0 | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAMarketDigitalTwin/**` | worker/worker-twin/TASK-0005 | 2026-09-15 11:00 UTC | 2026-09-15 12:00 UTC |

> Example workflow uses TASK-0003: worker-agentos claims → branch `worker/worker-agentos/TASK-0003` → updates `TASK_QUEUE.md` + `EVENT_BUS.md` → report in `REPORT_QUEUE.md`.
> TASK-0005 is active: worker-twin owns MOD-TWIN, Twin is single source for Replay/Training/Risk/Research/AI.

---

## How to Create a Task (Orchestrator)

```bash
python AgentOS/tools/agentos_cli.py task create --title "Fix replay determinism" --module MOD-REPLAY --priority P1 --files "01_Source/EA/MQL5/Include/CandleBreakoutEA/EAReplay/**"
# → appends row, increments TaskID, writes EVENT_BUS task.created, commits "[AgentOS][TASK-0005][worker-agentos] create: Fix replay determinism"
```

## How to Claim (Worker)

```bash
python AgentOS/tools/agentos_cli.py task claim --id TASK-0002 --worker worker-agentos
# checks ownership, lock availability, sets Owner/Status=CLAIMED/Branch, acquires lock, emits event, commits
```

## Invariants

* `TaskID` never reused.
* `Module` must exist in `OWNERSHIP_MAP.md`.
* `Owner` must own `Module` per `OWNERSHIP_MAP.md`.
* `Status` transition must follow lifecycle (validate.py enforces).

---

*Last synced: 2026-09-15 12:00 UTC — 4 OPEN, 0 CLAIMED, 0 REVIEW, 1 DONE (TASK-0005)*