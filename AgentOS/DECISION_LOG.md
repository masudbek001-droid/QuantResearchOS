# AgentOS — Decision Log v1.0

**File:** `AgentOS/DECISION_LOG.md` — Append-only architectural/operational decisions.
**Protocol:** `AGENT_PROTOCOL.md` §6 (append-only, never rewrite history).
**Authority:** Every row must cite an ADR or `AGENT_PROTOCOL.md` rule for `AgentOS/` changes; trading/AI changes cite `DECISIONS.md` ADR.

---

## Schema

| Column | Type | Description |
|---|---|---|
| DecisionID | `DEC-####` | Monotonic, never reuse |
| Date | `YYYY-MM-DD HH:MM UTC` | UTC |
| Author | `worker-*` | Who decided (orchestrator for AgentOS) |
| Context | string | What triggered decision |
| Decision | string | What was decided |
| Consequence | string | What changes / what is blocked |
| ADR / Ref | `ADR-*` or `AgentOS/AGENT_PROTOCOL.md#§` | Authority |

---

## Log

| DecisionID | Date | Author | Context | Decision | Consequence | ADR / Ref |
|---|---|---|---|---|---|---|
| DEC-0001 | 2026-09-15 07:35 UTC | worker-agentos | AgentOS v1.0 MVP creation requested; no Telegram, no trading/AI logic change | Create `AgentOS/` with 8-file collaboration layer (Protocol, Task/Report Queues, Lock Manager, Ownership Map, Decision Log, Event Bus, Worker Registry) + single-owner invariant. Git is sole bus. | New `AgentOS/` files are source of truth; all workers must use them; trading/AI remain read-only | ADR-0021 |
| DEC-0002 | 2026-09-15 07:35 UTC | worker-agentos | Need deterministic task flow for multi-agent work | Adopt lifecycle `OPEN→CLAIMED→IN_PROGRESS→REVIEW→DONE` with branch `worker/<id>/<task>` and lock-per-path. | Task/Report/Lock/Event files enforce ordering; validate.py enforces invariants | AgentOS/AGENT_PROTOCOL.md §4-5 |
| DEC-0003 | 2026-09-15 11:00 UTC | worker-agentos | Market must have single source of truth; Replay/Training/Risk/Research/AI diverged reading raw history | Create Market Digital Twin `EAMarketDigitalTwin/` as single simulator (MOD-TWIN → worker-twin), exact reproduction via hash, identical events to 5 consumers via TwinEventBus. | Twin becomes sole market source; direct HistoryStore reads outside Twin are violations; Replay etc. become Twin consumers | ADR-0022 |

> All future decisions append below. Never edit rows above — corrections append a new `DEC-####` with `Supersedes: DEC-xxxx`.

---

## How to Record (Orchestrator)

```bash
python AgentOS/tools/agentos_cli.py decision record --author worker-agentos --context "Split MOD-RESEARCH" --decision "Transfer MOD-RESEARCH to worker-research-v2" --consequence "Old owner deprecated, new owner active" --adr ADR-0022
# → appends row, emits decision.recorded to EVENT_BUS
```

## Invariants

* `DecisionID` monotonic, append-only.
* `Author` must be registered worker.
* `ADR / Ref` must exist (ADR file or protocol section).

---

*Last decision: DEC-0003 — next is DEC-0004.*