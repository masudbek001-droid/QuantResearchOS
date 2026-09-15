# LABEL ENGINE — `ObservationLabels` (schema v5)

Implemented by Task 0009 under ADR-0007. The Label Engine generates **ground-truth
outcome labels** for recorded market observations — the dataset foundation for future
machine learning. It predicts nothing, decides nothing, and never touches trading.

## 1. Schema

### `ObservationLabels` (facts — one row per labelled observation, per label version)

`LabelID` (PK autoinc) · `ObservationID` → `Observations` · `LabelVersion` ·
`LookaheadBars` · `FutureHigh` · `FutureLow` · `FutureClose` ·
`MaxFavorableExcursion` (best future excursion above the bar close) ·
`MaxAdverseExcursion` (worst excursion below it) · `DirectionLabel` · `BreakoutSuccess`
· `LabelQuality` (100 = complete window; only complete windows are stored) ·
`GeneratedAt` · `UNIQUE(ObservationID, LabelVersion)`

## 2. Direction labels (STEP 2)

| Value | Label | Ground truth rule (rng = observed bar range, net = FutureClose − bar close) |
|---|---|---|
| 0 | `LABEL_UNKNOWN` | never stored (reserved) |
| 1 | `LABEL_UP` | net ≥ 0.5·rng |
| 2 | `LABEL_DOWN` | net ≤ −0.5·rng |
| 3 | `LABEL_RANGE` | \|net\| inside the threshold band |
| 4 | `LABEL_FAKE_BREAKOUT` | breakout observation (OBS_BREAKOUT_UP/DOWN) that reversed by ≥ 0.25·rng |

`BreakoutSuccess = 1` only for breakout observations whose future confirmed the direction.

## 3. Indexes (STEP 5)

`idx_label_obs(ObservationID)`, `idx_label_dir(DirectionLabel)`,
`idx_label_look(LookaheadBars)`, `idx_label_gen(GeneratedAt)`.

## 4. Generation contract (STEP 3)

* `LABEL_LOOKAHEAD_BARS = 3` completed bars behind the observed bar; a label is written
  **only when the full window exists** (`iBarShift(bar) ≥ lookahead`). No partial
  windows, no extrapolation — labels are strictly about the past.
* `LABEL_VERSION = 1`; a rule change is a new version via ADR — old labels are never
  rewritten, so datasets stay reproducible.
* `CLabelGenerator`: `GenerateLabels(limit)` batch core (25 rows/pass, ordered by
  BarTime, stops at the first not-yet-ready row), `ValidateLabels()` integrity re-check,
  `UpdatePendingLabels()` one batch per completed bar on the existing funnel.
* Inputs are raw historical prices only; features for training arrive via the
  observation's `FeatureSnapshotID` link (Feature Builder data), never recomputed here.

## 5. Validation (STEP 4)

Rejected: missing observation (dangling FK), duplicate label
(`UNIQUE(ObservationID,LabelVersion)` + pre-insert rules), negative lookahead, invalid
future prices (NaN/Infinity via `CFeatureValidation::IsFinite`, `FutureHigh <
FutureLow`, close outside the range), incomplete future window (row stays pending).

## 6. Look-ahead safety

Labels read **history behind** the observed bar and are written after the fact; nothing
in the generator feeds the Feature Builder, Context Layer or any trading path. The
runtime EA never reads `ObservationLabels`.

## 7. Future compatibility

* **AI**: one row = label (DirectionLabel, BreakoutSuccess) + excursion statistics,
  joinable to full feature vectors through `Observations.FeatureSnapshotID` — training
  sets are pure SELECTs.
* **Replay**: labels let a replayed timeline be scored against ground truth.
* **Versioning**: new label logic ships as `LabelVersion = n` without touching v1 rows.
