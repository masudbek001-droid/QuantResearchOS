# AgentOS — Worker Registry v1.0

**File:** `AgentOS/WORKER_REGISTRY.md` — Authoritative worker roster.
**Protocol:** `AGENT_PROTOCOL.md` §9 (heartbeat, liveness). Only `worker-agentos` may register/deregister.
**Invariant:** `WorkerID` unique, each worker owns exactly one `Module` per `OWNERSHIP_MAP.md`, `ModuleOwned` matches ownership.

---

## Schema

| Column | Type | Description |
|---|---|---|
| WorkerID | `worker-*` | Stable, DNS-like, lowercase with hyphen |
| ModuleOwned | `MOD-*` | Exactly one, must exist in `OWNERSHIP_MAP.md` |
| Role | `orchestrator, module-worker` | `orchestrator` only for `worker-agentos` |
| Status | `ACTIVE, INACTIVE, DEPRECATED` | ACTIVE = may claim tasks |
| LastHeartbeat | `YYYY-MM-DD HH:MM UTC` or `-` | UTC, updated via `worker.heartbeat` event |
| BranchPrefix | `worker/<id>/` | Enforced by protocol |
| Capabilities | string list | e.g., `mql, python, docs, build` |

---

## Registry

| WorkerID | ModuleOwned | Role | Status | LastHeartbeat | BranchPrefix | Capabilities |
|---|---|---|---|---|---|---|
| worker-agentos | MOD-AGENTOS | orchestrator | ACTIVE | 2026-09-15 07:35 UTC | `worker/worker-agentos/` | `orchestration, git, docs, python` |
| worker-core | MOD-CORE | module-worker | ACTIVE | - | `worker/worker-core/` | `mql, mt5` |
| worker-context | MOD-CONTEXT | module-worker | ACTIVE | - | `worker/worker-context/` | `mql, context` |
| worker-feature | MOD-FEATURE | module-worker | ACTIVE | - | `worker/worker-feature/` | `mql, features` |
| worker-dal | MOD-DAL | module-worker | ACTIVE | - | `worker/worker-dal/` | `mql, db, python` |
| worker-history | MOD-HISTORY | module-worker | ACTIVE | - | `worker/worker-history/` | `mql, history, ticks` |
| worker-replay | MOD-REPLAY | module-worker | ACTIVE | - | `worker/worker-replay/` | `mql, replay` |
| worker-research | MOD-RESEARCH | module-worker | ACTIVE | - | `worker/worker-research/` | `mql, research, python` |
| worker-tools | MOD-TOOLS | module-worker | ACTIVE | - | `worker/worker-tools/` | `python, build, tests` |
| worker-docs | MOD-DOCS | module-worker | ACTIVE | - | `worker/worker-docs/` | `docs, manual, pdf` |

> 10 workers for 10 modules — satisfies 1:1 invariant. `worker-core` is FROZEN (owns MIPS v1.0, read-only without ADR). All workers communicate only through `AgentOS/` files.

---

## How to Register (Orchestrator)

```bash
python AgentOS/tools/agentos_cli.py worker register --id worker-new --module MOD-NEW --role module-worker --capabilities "python,ml"
# → checks 1:1 invariant, appends row, emits worker.registered, commits
```

## How to Heartbeat (Worker)

```bash
python AgentOS/tools/agentos_cli.py worker heartbeat --id worker-research
# → updates LastHeartbeat to now UTC, emits worker.heartbeat, commits
```

## Liveness

* `ACTIVE` + `LastHeartbeat` older than 72h → orchestrator sets `INACTIVE`, emits `worker.inactive`, reassigns `CLAIMED` tasks.
* `DEPRECATED` = worker retired, never reuse ID.

## Invariants (validate.py)

* `WorkerID` unique.
* `ModuleOwned` unique across registry (one owner per module).
* `ModuleOwned` exists in `OWNERSHIP_MAP.md` and its `Owner` equals `WorkerID`.
* `BranchPrefix` == `worker/<WorkerID>/`.

---

*Last heartbeat sweep: 2026-09-15 07:35 UTC — 10 ACTIVE, 0 INACTIVE.*
