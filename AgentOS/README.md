# AgentOS v1.0 — Collaboration Layer for QuantResearchOS

**Version:** 1.0 MVP (2026-09-15)
**Purpose:** Minimum Git-native infrastructure for autonomous multi-agent collaboration.
**Branch:** `arena/01a0a3b5-quantresearchos` — AgentOS is `58 .mqh + AgentOS` (no trading/AI logic touched).
**Protocol:** `AGENT_PROTOCOL.md` is law. All 8 queue/registry files are the API.

---

## What AgentOS Is

A **Git-based operating system** for agents. No Telegram, no direct RPC, no shared state. Workers:

* Own exactly one module (`OWNERSHIP_MAP.md` 1:1 invariant)
* Communicate only through `AgentOS/` files
* Work on `worker/<id>/<task>` branches
* Coordinate via `TASK_QUEUE → LOCK_MANAGER → REPORT_QUEUE → EVENT_BUS → DECISION_LOG`

Git history is the bus. `git pull` is poll, `git commit + push` is send.

---

## File Map (MVP)

```
AgentOS/
├── AGENT_PROTOCOL.md      — Rules, lifecycle, branch/commit conventions, invariants
├── TASK_QUEUE.md          — Ordered task queue (OPEN→CLAIMED→IN_PROGRESS→REVIEW→DONE)
├── REPORT_QUEUE.md        — Reports linked to tasks (PENDING→APPROVED)
├── LOCK_MANAGER.md        — File-level locks (one ACTIVE per Path)
├── OWNERSHIP_MAP.md       — Module → Worker 1:1 (10 modules, 10 workers)
├── DECISION_LOG.md        — Append-only decisions (ADR-gated)
├── EVENT_BUS.md           — Append-only ordered events (task/lock/report/worker)
├── WORKER_REGISTRY.md     — Roster + heartbeat + liveness
├── README.md              — This file
├── EXAMPLE_WORKFLOW.md    — Traced end-to-end example (TASK-0003)
├── tools/
│   ├── agentos_cli.py     — CLI for task/claim/report/lock/event/ownership/validate
│   └── validate.py        — Invariant checker (CI gate)
├── tests/
│   └── test_agentos.py    — Tests for protocol invariants + example workflow
└── schema/
    └── *.json             — JSON schemas for machine queues (future)
```

---

## Quick Roles

| Worker | Module | Paths |
|---|---|---|
| `worker-agentos` | MOD-AGENTOS | `AgentOS/**` (orchestrator) |
| `worker-core` | MOD-CORE | Trading core (FROZEN) |
| `worker-context` | MOD-CONTEXT | `EAContext/**` |
| `worker-feature` | MOD-FEATURE | `EAFeatureBuilder/**` |
| `worker-dal` | MOD-DAL | `EAData/**`, `02_Databases/**` |
| `worker-history` | MOD-HISTORY | `EAHistory/**` |
| `worker-replay` | MOD-REPLAY | `EAReplay/**` |
| `worker-research` | MOD-RESEARCH | `EAResearch/**`, `05_Training/**` |
| `worker-tools` | MOD-TOOLS | `06_Tools/**`, `04_Output/**`, `01_Source/Tests/**` |
| `worker-docs` | MOD-DOCS | `03_Documents/**`, `*.md` |

---

## 3-Command Demo

```bash
# Orchestrator creates
python AgentOS/tools/agentos_cli.py task create --title "Validate replay determinism" --module MOD-REPLAY --priority P1 --files "01_Source/EA/MQL5/Include/CandleBreakoutEA/EAReplay/**"

# Worker claims
python AgentOS/tools/agentos_cli.py task claim --id TASK-0005 --worker worker-replay

# Worker reports
python AgentOS/tools/agentos_cli.py report create --task TASK-0005 --worker worker-replay --verdict PASS --artifacts "01_Source/EA/MQL5/Include/CandleBreakoutEA/EAReplay/ReplayValidator.mqh"
```

See `EXAMPLE_WORKFLOW.md` for full trace with Git commands and file diffs.

---

## Invariants (enforced by `tools/validate.py`)

* 1 worker ↔ 1 module (both directions unique)
* No duplicate ACTIVE lock per Path
* TaskID monotonic, valid transitions
* Every report links to existing TaskID, worker owns Module
* EventID monotonic, DecisionLog append-only
* No trading/AI logic touched without ADR

Run: `python AgentOS/tools/validate.py` → `AGENTOS PASS` or `FAIL` with reasons.
Run tests: `python -m pytest AgentOS/tests/test_agentos.py -v` or `python AgentOS/tests/test_agentos.py`

---

## Out of Scope

* Telegram — explicitly not implemented (Git-only bus).
* Trading logic / AI advisory mutations — read-only; AgentOS is collaboration layer only.

---

## Governance

* Changes to `AgentOS/` require `AGENT_PROTOCOL.md` + `DECISION_LOG.md` entry (DEC-xxxx) + ADR if ownership changes.
* This MVP is additive — 0 files outside `AgentOS/` + `03_Documents` reports were modified.

For full spec, read `AGENT_PROTOCOL.md` first, then `EXAMPLE_WORKFLOW.md`.
