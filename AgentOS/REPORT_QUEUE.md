# AgentOS — Report Queue v1.0

**File:** `AgentOS/REPORT_QUEUE.md` — Git-native report queue.
**Protocol:** `AGENT_PROTOCOL.md` §6.
**Ordering:** `ReportID` monotonic `REPORT-0001, ...`. Append-only; status updates edit row.
**States:** `PENDING, APPROVED, REJECTED, SUPERSEDED`

> Workers create reports; orchestrator approves. Every report links to a `TaskID`.

---

## Schema

| Column | Type | Description |
|---|---|---|
| ReportID | `REPORT-####` | Monotonic |
| TaskID | `TASK-####` | Must exist in `TASK_QUEUE.md` |
| Worker | `worker-*` | Author, must own Task's Module |
| Status | enum | PENDING→APPROVED/REJECTED |
| Verdict | `PASS, FAIL, BLOCKED, PARTIAL` | Outcome of work |
| Artifacts | path list | Files changed + evidence logs |
| Timestamp | `YYYY-MM-DD HH:MM UTC` | UTC when report created |

---

## Queue

| ReportID | TaskID | Worker | Status | Verdict | Artifacts | Timestamp |
|---|---|---|---|---|---|---|
| REPORT-0001 | TASK-0001 | worker-agentos | PENDING | PASS | `AgentOS/AGENT_PROTOCOL.md: validated invariant 1-11` | 2026-09-15 07:35 UTC |
| REPORT-0002 | TASK-0005 | worker-twin | PENDING | PASS | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAMarketDigitalTwin/**, 06_Tools/market_digital_twin_validate.py, 04_Output/Twin/twin_validation_report.json` | 2026-09-15 11:45 UTC |

> Example: after completing TASK-0003, worker appends `REPORT-0002 | TASK-0003 | worker-agentos | PENDING | PASS | AgentOS/TASK_QUEUE.md updated, EVENT_BUS task.claimed emitted | 2026-09-15 07:40 UTC` then sets `TASK_QUEUE.TASK-0003=REVIEW`.

---

## How to Report (Worker)

```bash
python AgentOS/tools/agentos_cli.py report create --task TASK-0003 --worker worker-agentos --verdict PASS --artifacts "AgentOS/TASK_QUEUE.md,AgentOS/EVENT_BUS.md"
# → appends row, sets TASK_QUEUE.Status=REVIEW, emits report.created
```

## How to Review (Orchestrator)

```bash
python AgentOS/tools/agentos_cli.py report approve --id REPORT-0002
# → sets REPORT_QUEUE.Status=APPROVED, TASK_QUEUE.Status=DONE, releases lock, emits task.completed + report.approved
```

## Invariants

* `ReportID` monotonic, unique.
* `TaskID` must exist.
* `Worker` must own `Task.Module`.
* `Verdict` ∈ {PASS,FAIL,BLOCKED,PARTIAL}.
* `Artifacts` paths must be within worker's owned module or locked paths.

---

*Last synced: 2026-09-15 11:45 UTC — 2 PENDING (REPORT-0002), 0 APPROVED.*