# ADR-0002 — Introduce the centralized Feature Builder (EAFeatureBuilder/)

*Status: Accepted (approved by engineering Task 0004).*

## Context
Market statistics were computed ad-hoc in several modules (CMomentumAnalyzer,

CMarketContext, legacy helpers) — technical debt DUP-03..05. MIPS requires

a single source for market-derived features before feature-builder / persistence work begins.

## Decision
1. Add module `MQL5/Include/CandleBreakoutEA/EAFeatureBuilder/` and place

`FeatureTypes.mqh`, `FeatureSnapshot.mqh`, `FeatureValidation.mqh`,

`EAFeatureBuilder.mqh`.
2. `CFeatureBuilder` is the sole producer of market features; snapshots are

immutable and passed by copy.
3. Backward compatibility: existing computations are **not** replaced in

this task (Step 5). Migration will happen incrementally in later tasks.
4. `CTradeManager` calls `Initialize/Update` on the existing dashboard

path; all other consumers are read-only.

## Consequences
* Centralization of validation (NaN/Inf/negative/invalid/missing rejection).
* Per completed bar, one additional cached series path per tick (no per-tick cost).
* Accepted temporary duplication with `CMarketContext` until migration ADR.
