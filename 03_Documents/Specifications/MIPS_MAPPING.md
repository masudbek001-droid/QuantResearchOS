# MIPS MAPPING — Task 0002
Maps every discovered module to the frozen MIPS v1.0 architecture and reports context/event
readiness. **Audit only — no modifications.**

## 1. Module → architecture layer

| Discovered module | MIPS layer (MIPS §2/§3) | Conforms? |
|---|---|---|
| `CandleBreakoutEA.mq5` | Entry Point / Configuration | ✔ inputs copied once via `BuildSettings`, validation before run |
| `CEASettings` | Core (shared enums + payload) | ✔ `Reset()` defaults, class-for-pointer rule |
| `CEAUtils` | Utilities | ✔ stateless statics; 3 dead helpers noted in TECHNICAL_DEBT |
| `CLogger` | Infrastructure / Logging | ✔ seven-tag contract, line format per MIPS §3 |
| `CTradeHistory` | Persistence (read side) | ✔ history aggregation only, no writes |
| `CRiskManager` | Risk gate | ✔ logs its own block reasons |
| `COrderManager` | Entry Layer | ✔ no SL/TP anywhere (QR-2.3) |
| `CPositionManager` | Runtime plumbing | ✔ |
| `CBreakEvenManager` | Exit Layer — priority #1 | ✔ only SL writer |
| `CMomentumAnalyzer` | Exit Layer (measurement) | ✔ cached per completed bar (Q-4) |
| `CExitEngine` | Exit Layer — priorities #2/#3/#4 | ✔ single decision per evaluation (QR-2.4) |
| `CExitStats` | Statistics / Persistence (write side) | ✔ append-only CSV, `0` for missing (QR-3.4) |
| `CDashboard` | Visualization | ✔ reads only `STradeContext` + stats |
| `CVisualManager` | Visualization | ✔ prefix contract |
| `CTradeManager` | Runtime Layer (state machine, orchestrator) | ✔ mandatory close #5, carry phase separation |
| `STradeContext` | Context Layer | ✔ single producer, read-only consumers |

**Deviations from MIPS: none.** Every public interface listed in MIPS §3 exists with the
documented signature; the include DAG matches the dependency rules (MIPS §4).

## 2. Context readiness (Step 7)

| Context | Status | Evidence |
|---|---|---|
| **TradeContext** | **Implemented** | `STradeContext` (61 lines) with all MIPS §3 fields; produced once per tick by `CTradeManager::BuildContext`; consumed by dashboard and journal; `Reset()` guarantees safe zeros |
| **MarketContext** | **Missing** | market data is pulled ad-hoc (`CEAUtils::Bid/Ask/PointValue`, `i*` series) at each call site; no snapshot struct, no cache owner besides the momentum bar-cache |
| **StrategyContext** | **Missing** | strategy *configuration* lives in `CEASettings`; strategy *state* (candle time/close, armed, traded flag, position bookkeeping) is private members of `CTradeManager`; no dedicated struct |
| **AIContext** | **Missing** | only the inert `InpAiReserved` input exists (Q-7); no feature store, no model surface |

## 3. Event readiness (Step 8)

| Capability | Status | Current state |
|---|---|---|
| **Event Bus** | **Missing** | communication is direct method calls; the only broadcast channel is the standardized log (seven tags). No event queue, no subscribers, no replayable event stream |
| **Replay** | **Partial** | the append-only CSV journal (`EAExitStats`) already records per-ticket entry/exit, MFE/MAE, lock/carry/momentum — a viable replay *data source*; no replay engine, no reader tooling, logs are human text only |
| **SQLite** | **Missing** | persistence = CSV in `MQL5/Files`; `database/` folder reserved and empty; no SQL engine, no schema |
| **Feature Builder** | **Partial** | `CMomentumAnalyzer` computes one normalized 0–100 feature from completed bars (cached); no generic feature extraction, no feature persistence, no builder API |

## 4. Readiness implications for future tasks

1. An **Event Bus** would slot between `CTradeManager` (producer) and logger/stats/dashboard
   (consumers) without touching strategy logic — but requires an ADR (architecture change).
2. **Replay** can be prototyped out-of-tree (`replay/`, `scripts/`) against the existing CSV
   columns before any MQL change.
3. **SQLite** belongs in the reserved `database/` layer; the CSV writer is the migration source.
4. A **MarketContext** is the cheapest first context (wraps `CEAUtils` reads + series cache) and
   would remove DUP-04/DUP-05 duplication as a side effect — ADR required.

**Validation of this task:** zero source modifications (verified by mtime marker), zero compile
impact (`VERDICT: PASS - 0 errors, 0 warnings`), zero behaviour changes.
