# ADR-0007 — Label Engine foundation (schema v5, ground truth only)

*Status: Accepted (approved by engineering Task 0009).*

## Context
Machine-learning datasets need outcome labels for the recorded observations. Labels
must be ground truth about the past, generated only after sufficient future bars
exist, and must never leak into runtime decisions.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 5 and add `ObservationLabels` (ObservationID FK,
   LabelVersion, LookaheadBars, FutureHigh/Low/Close, MFE/MAE, DirectionLabel,
   BreakoutSuccess, LabelQuality, GeneratedAt) with four indexes and
   `UNIQUE(ObservationID,LabelVersion)`. Migration `4 → 5` runs through
   `ApplyMigration("label engine foundation", ddl[5])`.
2. Define `ENUM_DIRECTION_LABEL` (UNKNOWN/UP/DOWN/RANGE/FAKE_BREAKOUT) with fixed,
   documented thresholds (0.5·range move, 0.25·range reversal) measured on raw
   historical prices.
3. Add `CLabelGenerator` (in `EAData/`): `GenerateLabels()` / `ValidateLabels()` /
   `UpdatePendingLabels()`; one batch (25) per completed bar; a label is written only
   when the full 3-bar future window exists.
4. `LabelVersion` makes rule changes additive: new logic = new version, old rows never
   rewritten (reproducible datasets).

## Consequences
* Ready-made labelled dataset: labels join to full feature vectors through
  `Observations.FeatureSnapshotID`.
* Zero look-ahead risk for the runtime: the EA never reads the label table; generation
  is history-only, write-only observation-side work.
* One batched pass per completed bar; no per-tick database work.
