# ADR-0006 — Observation Engine (market recorder, schema v4)

*Status: Accepted (approved by engineering Task 0008).*

## Context
Quantitative research needs a continuous, trade-independent record of the market:
what kind of bar completed, with which feature vector, in which session context.
MarketSnapshots stores the raw features; an event layer on top was missing.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 4 and add the `Observations` table
   (ObservationID, SymbolID, TimeframeID, ObservationTime, BarTime, ObservationType,
   FeatureSnapshotID → MarketSnapshots, TradeID nullable → Trades, Session, Hour,
   Weekday, Month, CreatedAt) with five indexes and
   `UNIQUE(SymbolID,TimeframeID,BarTime,ObservationType)`.
   Migration `3 → 4` runs through `ApplyMigration("observation engine", ddl[6])`.
2. Define `ENUM_OBSERVATION_TYPE` (10 labels) — descriptive vocabulary only.
3. Add `CObservationWriter` (in `EAData/`): `InsertObservation()` /
   `ValidateObservation()` plus the per-tick `Update()` that stores exactly one
   observation per completed candle, `TradeID = NULL`.
4. Bar classification (breakout/outside/inside/volatility/session labels) lives in the
   recorder and is strictly descriptive — it shares no code path with the entry engine.

## Consequences
* A trade-independent market timeline joins observations to full feature vectors and
  (later) to trade outcomes via `TradeID`.
* Recording reuses the Feature Builder, Context Layer and DAL without modification;
  trading behaviour and runtime are unchanged.
* One extra INSERT per completed candle; no per-tick database work.
