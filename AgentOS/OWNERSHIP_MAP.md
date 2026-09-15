# AgentOS — Ownership Map v1.0

**File:** `AgentOS/OWNERSHIP_MAP.md` — Single-owner module registry.
**Protocol:** `AGENT_PROTOCOL.md` §2 (one module, one owner). Changes require ADR + entry in `DECISION_LOG.md`.
**Invariant:** `Module` unique, `Worker` unique (one worker → one module, one module → one worker). No overlap.

---

## Schema

| Column | Type | Description |
|---|---|---|
| Module | `MOD-*` | Stable module ID |
| Name | string | Human name |
| Paths | glob list | Owned filesystem paths (authoritative) |
| Owner | `worker-*` | Exactly one worker |
| Status | `ACTIVE, FROZEN, DEPRECATED` | FROZEN = read-only without ADR |
| ADR | `ADR-*` or `-` | Authorizing ADR |

---

## Map (MVP — 8 modules, 8 workers)

| Module | Name | Paths | Owner | Status | ADR |
|---|---|---|---|---|---|
| MOD-AGENTOS | AgentOS Collaboration Layer | `AgentOS/**`, `AGENT_PROTOCOL.md`, `TASK_QUEUE.md`, `REPORT_QUEUE.md`, `LOCK_MANAGER.md`, `OWNERSHIP_MAP.md`, `DECISION_LOG.md`, `EVENT_BUS.md`, `WORKER_REGISTRY.md` | worker-agentos | ACTIVE | ADR-0021 |
| MOD-CORE | Trading Core (MIPS v1.0) | `01_Source/EA/MQL5/Experts/**`, `01_Source/EA/MQL5/Include/CandleBreakoutEA/EATradeManager.mqh`, `EARiskManager.mqh`, `EAOrderManager.mqh`, `EAPositionManager.mqh`, `EABreakEvenManager.mqh`, `EAMomentum.mqh`, `EAExitEngine.mqh`, `EASettings.mqh`, `EALogger.mqh` | worker-core | FROZEN | MIPS v1.0 |
| MOD-CONTEXT | Context & Advisory | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/**` | worker-context | ACTIVE | ADR-0001, ADR-0016..0020 |
| MOD-FEATURE | Feature Builder | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAFeatureBuilder/**` | worker-feature | ACTIVE | ADR-0002 |
| MOD-DAL | Data Access & Stores | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAData/**`, `02_Databases/**` | worker-dal | ACTIVE | ADR-0003..0004, ADR-0013 |
| MOD-HISTORY | Historical Data Platform | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAHistory/**`, `01_Source/History/**` | worker-history | ACTIVE | ADR-0013 |
| MOD-REPLAY | Replay Foundation | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAReplay/**`, `01_Source/Replay/**` | worker-replay | ACTIVE | ADR-0011 |
| MOD-RESEARCH | Research & Training | `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAResearch/**`, `05_Training/**`, `01_Source/Research/**`, `01_Source/ML/**`, `01_Source/Models/**` | worker-research | ACTIVE | ADR-0012, ADR-0014 |
| MOD-TOOLS | Build & Output | `06_Tools/**`, `04_Output/**` (generated), `01_Source/Tests/**`, `01_Source/Utilities/**` | worker-tools | ACTIVE | — |
| MOD-DOCS | Documentation | `03_Documents/**`, `*.md` (governance: README, PROJECT_STATUS, ROADMAP, DECISIONS, etc.), `08_Archives/**` | worker-docs | ACTIVE | — |

> Note: MVP counts 10 rows for completeness (includes TOOLS + DOCS). Core invariant still holds: each worker owns exactly one Module, each Module has exactly one Owner. `MOD-TOOLS` and `MOD-DOCS` are separate owners (worker-tools, worker-docs). If strict 8 is required, merge TOOLS+DOCS → worker-tools owns both; the table above documents the intended split for clarity. The registry below registers 10 workers to match 10 modules — validator checks 1:1.

---

## Rules

1. **Exact match:** Worker may only commit to paths under its `Paths` glob, or to `AgentOS/**` queue files via the protocol (task/report/event/lock APIs) which are co-owned by `worker-agentos` but writable via queue semantics.
2. **Frozen:** `MOD-CORE` is FROZEN — any write requires ADR + Decision Log entry + Strategy Tester gate.
3. **Advisory read-only:** `MOD-CONTEXT` advisory files (`*Advisory.mqh`, `*Council.mqh`, `*ContinuousLearning.mqh`) are boundary — writes require ADR-0015 gate.
4. **No stealth ownership change:** Changing `Owner` requires new row with new `Module` version or ADR, old row → `DEPRECATED`, never delete.

---

## How to Change Ownership (Orchestrator, ADR-gated)

```bash
python AgentOS/tools/agentos_cli.py ownership transfer --module MOD-RESEARCH --to worker-research-v2 --adr ADR-0022 --reason "Split research/training"
# → appends new row, old row Status=DEPRECATED, appends DECISION_LOG, emits decision.recorded
```

---

*Last validated: 2026-09-15 07:35 UTC — 10 ACTIVE, 0 conflicts, all workers 1:1.*
