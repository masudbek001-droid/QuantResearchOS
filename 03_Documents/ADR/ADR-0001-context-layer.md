# ADR-0001 — Introduce the Context Layer (EAContext/)

*Status: Accepted (authorized by engineering Task 0003).*

## Context
MIPS v1.0 froze the architecture with a single read-only trade snapshot (`STradeContext`).
Tasks 0003+ require market/strategy/AI state for future feature building, replay and
persistence without touching the frozen trading logic.

## Decision
1. Add module `MQL5/Include/CandleBreakoutEA/EAContext/` with `CTradeContext`,
   `CMarketContext`, `CStrategyContext`, `CAIContext` and the `CContextLayer` facade.
2. `CTradeManager` is the only writer (one `Update()` per tick on the existing dashboard
   path); every other consumer is read-only.
3. Contexts carry no business logic; `Serialize()` remains a stub until a persistence ADR.
4. `STradeContext` stays as the frozen producer contract; the Context Layer wraps it. A future
   ADR may migrate consumers and retire the duplication.
5. `CEASettings.ai_reserved` is added (additive) to wire the reserved Future-AI input.

## Consequences
* Observation state is centralized; market bar statistics cached per completed bar.
* No behaviour change: entry/exit/pending/BreakEven/carry paths untouched.
* Known accepted duplication: `STradeContext` vs `CTradeContext` until the migration ADR.
