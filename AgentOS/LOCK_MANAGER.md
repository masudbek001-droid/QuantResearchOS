# AgentOS — Lock Manager v1.0

**File:** `AgentOS/LOCK_MANAGER.md` — Git-native file-level locks.
**Protocol:** `AGENT_PROTOCOL.md` §5.
**Rule:** One `Path` → at most one `ACTIVE` lock. All writes outside owned module require ACTIVE lock held by writer.

---

## Schema

| Column | Type | Description |
|---|---|---|
| LockID | `LOCK-####` | Monotonic |
| Path | string (glob or exact) | File/dir being locked (e.g., `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAData/**`) |
| Worker | `worker-*` | Holder |
| TaskID | `TASK-####` | Task holding lock |
| Acquired | `YYYY-MM-DD HH:MM UTC` | UTC |
| Expires | `YYYY-MM-DD HH:MM UTC` | UTC — default +72h from Acquired |
| Status | `ACTIVE, RELEASED, EXPIRED, DENIED` | ACTIVE only one per Path |

---

## Active Locks

| LockID | Path | Worker | TaskID | Acquired | Expires | Status |
|---|---|---|---|---|---|---|
| - | - | - | - | - | - | - |

*No active locks at init. Example active row:*
*`LOCK-0001 | 01_Source/EA/MQL5/Include/CandleBreakoutEA/EAData/** | worker-dal | TASK-0010 | 2026-09-15 08:00 UTC | 2026-09-18 08:00 UTC | ACTIVE`*

---

## Denied / History (append, never delete)

| LockID | Path | Worker | TaskID | Acquired | Expires | Status | Reason |
|---|---|---|---|---|---|---|---|
| - | - | - | - | - | - | - | - |

---

## How to Acquire (Worker)

```bash
python AgentOS/tools/agentos_cli.py lock acquire --path "01_Source/EA/MQL5/Include/CandleBreakoutEA/EAData/**" --worker worker-dal --task TASK-0010 --ttl 72
# → checks no ACTIVE lock on Path, appends ACTIVE row, emits lock.acquired
# → if conflict: appends DENIED row, emits lock.denied, worker must back off and poll
```

## How to Release (Worker/Orchestrator)

```bash
python AgentOS/tools/agentos_cli.py lock release --id LOCK-0001 --worker worker-dal
# → sets Status=RELEASED, emits lock.released
```

## Sweep (Orchestrator, hourly UTC)

```bash
python AgentOS/tools/agentos_cli.py lock sweep
# → any ACTIVE where Expires < now() → Status=EXPIRED, emits lock.expired, reopens Task to OPEN
```

## Invariants (enforced by validate.py)

* No duplicate `ACTIVE` for same `Path` (exact string match).
* `Worker` must be registered in `WORKER_REGISTRY.md` and own the module covering `Path` or hold `Task.Module` ownership.
* `Expires > Acquired`.
* Lock `TaskID` must be in `CLAIMED` or `IN_PROGRESS`.

---

*Last sweep: 2026-09-15 07:35 UTC — 0 ACTIVE, 0 EXPIRED.*
