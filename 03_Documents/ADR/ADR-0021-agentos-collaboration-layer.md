# ADR-0021: AgentOS — Git-Native Multi-Agent Collaboration Layer (v1.0 MVP)

## Status

Accepted. (Implementing AgentOS v1.0 MVP — collaboration layer only)

## Context

- QuantResearchOS is stable through Stage 15 + 5 advisory layers (58 .mqh, 5 tests PASS, advisory only). No autonomous multi-agent workflow existed — coordination was manual via human-orchestrated `AGENT_GUIDE` + `NEXT_TASK` + `DECISION_LOG` updates.
- Requirement: minimum infrastructure for **autonomous multi-agent collaboration through GitHub** — no Telegram, no trading/AI logic change.
- Existing governance is Git-based but not machine-enforceable: no task queue, no lock manager, no event bus, no ownership enforcement.
- Priority is to enable future workers (Kilo local, Arena remote, other) to collaborate without direct messaging, without stepping on each other's modules.

## Decision

Implement **AgentOS v1.0 MVP** as additive Git-native layer:

1. **Directory `AgentOS/`** — 8 required files (Markdown, human + machine):
   - `AGENT_PROTOCOL.md` — Single-owner invariant, Git is the bus, no direct assumptions, branch/commit conventions, lifecycle `OPEN→CLAIMED→IN_PROGRESS→REVIEW→DONE`, lock-per-path, heartbeat.
   - `TASK_QUEUE.md` — Monotonic `TASK-####`, Module, Owner, Status, Priority, Files, Branch, UTC timestamps. Orchestrator creates, worker claims.
   - `REPORT_QUEUE.md` — Monotonic `REPORT-####` linked to TaskID, worker, verdict, artifacts, PENDING→APPROVED.
   - `LOCK_MANAGER.md` — One ACTIVE per Path, TTL 72h, sweep expiry, DENIED on conflict.
   - `OWNERSHIP_MAP.md` — 10 modules (MOD-AGENTOS/CORE/CONTEXT/FEATURE/DAL/HISTORY/REPLAY/RESEARCH/TOOLS/DOCS) → 10 workers 1:1, FROZEN for MOD-CORE.
   - `DECISION_LOG.md` — Append-only `DEC-####`, ADR-gated.
   - `EVENT_BUS.md` — Append-only `EVT-####`, Types `task.*|report.*|lock.*|decision.*|worker.*`, JSON payload.
   - `WORKER_REGISTRY.md` — 10 workers, heartbeat, BranchPrefix `worker/<id>/`, Capabilities.

2. **Tooling `AgentOS/tools/`**:
   - `agentos_cli.py` — CLI for `task create/claim/update`, `lock acquire`, `report create`, `event emit` (keeps MD + bus synced).
   - `validate.py` — Invariant checker (CI gate): 1:1 ownership, no duplicate ACTIVE lock, monotonic IDs, valid transitions, module exists, worker owns module, JSON payload valid, advisory clause present.

3. **Tests `AgentOS/tests/test_agentos.py`** — 11 checks: protocol, 8 files, ownership 1:1, registry 1:1, no direct assumptions, Git-based, validate PASS, lock, no trading/AI touch, example workflow, CLI help.

4. **Documentation**:
   - `AgentOS/README.md` — File map, roles, 3-command demo, invariants.
   - `AgentOS/EXAMPLE_WORKFLOW.md` — Full traced example TASK-0003 (`created → claimed → in_progress → report → review → completed → lock released`) with Git diffs.
   - `03_Documents/Reports/AGENTOS_IMPLEMENTATION_REPORT.md` — Implementation report.

5. **Scheduling / improvements**: After MVP, continue with AgentOS improvements (schema JSON, auto-sweep, PR templates) until real external blocker (GitHub permission, Telegram explicitly excluded).

## Consequences

- Workers communicate only through `AgentOS/` files — `git pull` is poll, `git push` is send. No direct Telegram/RPC.
- Every worker owns exactly one module — enforced by `validate.py`; cross-module writes require lock + task + decision.
- All communication is Git-based — history is auditable, merges via PR by `worker-agentos` only.
- Trading core (MIPS v1.0) and advisory stack (ADR-0016..0020) remain read-only — not touched by AgentOS.
- Future Kilo (local VS Code) can participate by pulling `AgentOS/` and using CLI — human bridges via Git, no direct Arena↔Kilo bus needed.

## Alternatives Considered

- Direct Telegram bot — rejected per task (Git-only bus required).
- Central DB queue (e.g., SQLite) — rejected; breaks Git auditability and offline work.
- Per-file CODEOWNERS only — insufficient; need task/report/event/lock lifecycle, not just ownership.

## References

- `AGENT_PROTOCOL.md` §1-11
- `OWNERSHIP_MAP.md` 1:1 invariant
- `ROADMAP.md` Sprint 14 AgentOS (this ADR)
