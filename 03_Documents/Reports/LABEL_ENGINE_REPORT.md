# LABEL ENGINE REPORT — Task 0009 (Foundation)

## 1. Database version

`DB_SCHEMA_VERSION = 5` (was 4). Full chain for every file: `1→2` market intelligence →
`2→3` trade intelligence → `3→4` observation engine → `4→5` label engine, each
transactional and recorded in `MigrationHistory`.

## 2. Created table — `ObservationLabels`

LabelID (PK autoinc) · ObservationID → Observations · LabelVersion · LookaheadBars ·
FutureHigh · FutureLow · FutureClose · MaxFavorableExcursion · MaxAdverseExcursion ·
DirectionLabel · BreakoutSuccess · LabelQuality · GeneratedAt ·
UNIQUE(ObservationID,LabelVersion)

## 3. Direction labels (STEP 2)

`LABEL_UNKNOWN(0)` (reserved), `LABEL_UP(1)`, `LABEL_DOWN(2)`, `LABEL_RANGE(3)`,
`LABEL_FAKE_BREAKOUT(4)`. Ground-truth rules (rng = observed bar range, net =
FutureClose − observed bar close): UP/DOWN at ±0.5·rng; breakout observations that
reverse by ≥0.25·rng become FAKE_BREAKOUT; `BreakoutSuccess=1` only for confirmed
breakouts.

## 4. Generator (STEP 3) — `CLabelGenerator` (`EAData/LabelGenerator.mqh`)

```
int  GenerateLabels(const int limit);   // batch core (25/pass, BarTime-ordered)
bool ValidateLabels(void);              // integrity re-check of stored rows
void UpdatePendingLabels(void);         // one batch per completed bar
```

Labels are generated **only after sufficient future bars exist**
(`iBarShift(bar) ≥ LABEL_LOOKAHEAD_BARS=3`); incomplete windows leave the row pending.
`LabelVersion=1` — rule changes ship as new versions via ADR, stored rows are never
rewritten.

## 5. Validation rules (STEP 4)

Rejected: missing observation (dangling FK), duplicate label
(UNIQUE + pre-insert rules), negative lookahead, invalid future prices
(NaN/Infinity via `CFeatureValidation::IsFinite`, FutureHigh<FutureLow, close outside
range), incomplete future window (pending, never stored).

## 6. Indexes (STEP 5)

`idx_label_obs(ObservationID)` · `idx_label_dir(DirectionLabel)` ·
`idx_label_look(LookaheadBars)` · `idx_label_gen(GeneratedAt)`

## 7. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAData/LabelGenerator.mqh` | enum + label engine |
| `LABEL_ENGINE.md` | schema / labels / contract / validation / AI compatibility |
| `docs/adr/ADR-0007-label-engine.md` | decision record |

## 8. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 5`, `DB_TABLE_LABELS` |
| `EAData/DatabaseSchema.mqh` | `MigrationToV5(ddl[])` — table + 4 indexes |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` chain `1→2→3→4→5` |
| `EATradeManager.mqh` | +include, +`m_labels`, `Initialize` in `Init`, `UpdatePendingLabels()` after `m_observations.Update()` |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (35 headers), counts (5 946 lines), binary size |

Observation Engine logic, entry/exit/BE/carry/profit-lock, Feature Builder: untouched.

## 9. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (170 054 B binary).
* Trading behaviour and runtime unchanged; the EA never reads the label table.
* DAL reused (all SQL via `CDatabaseManager`); Feature Builder reused (feature vectors
  arrive via `Observations.FeatureSnapshotID`; validation reuses
  `CFeatureValidation::IsFinite`).
* Labels generated only after future data exists; no look-ahead bias in runtime.

**Stop condition honoured:** no AI, no Replay, no Event Bus. Waiting for Task 0010.
