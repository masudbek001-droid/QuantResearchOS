<!--- AgentOS PR Template — Git-native collaboration layer -->

## AgentOS Task

- **TaskID:** `TASK-####` (from `AgentOS/TASK_QUEUE.md`)
- **ReportID:** `REPORT-####` (from `AgentOS/REPORT_QUEUE.md`)
- **Worker:** `worker-*` (must own Module per `AgentOS/OWNERSHIP_MAP.md`)
- **Module:** `MOD-*`

## Checklist (must be PASS before merge)

- [ ] `python AgentOS/tools/validate.py` → `[AGENTOS] STATUS=PASS`
- [ ] `python AgentOS/tests/test_agentos.py` → `[AGENTOS_TESTS] STATUS=PASS`
- [ ] Branch is `worker/<worker-id>/<task-id>` (e.g., `worker/worker-research/TASK-0007`)
- [ ] `AgentOS/LOCK_MANAGER.md` shows ACTIVE lock for touched paths (or owned module)
- [ ] `AgentOS/EVENT_BUS.md` has `task.claimed` + `report.created` events for this TaskID
- [ ] No `01_Source/EA/MQL5` trading core changes unless ADR + Strategy Tester gate (MIPS v1.0 frozen)
- [ ] No `EAContext*Advisory` AI advisory multiplier changes unless ADR-0015 gate
- [ ] No Telegram / direct RPC — Git-only bus

## Artifacts

- Paths changed:
- Verdict: `PASS / FAIL / BLOCKED`
- Evidence log snippet:

```
(paste validate + test output)
```

## Orchestrator Notes

- Merge only after `REPORT_QUEUE.md` Status → `APPROVED`
- After merge: `TASK_QUEUE.md` → `DONE`, `LOCK_MANAGER.md` → `RELEASED`, `EVENT_BUS.md` → `task.completed`

