# DATA QUALITY ENGINE REPORT — Task 0011

## 1. Database version

`DB_SCHEMA_VERSION = 7` (was 6). Full chain: `1→2` market intelligence → `2→3` trade
intelligence → `3→4` observation engine → `4→5` label engine → `5→6` dataset builder →
`6→7` data quality engine, each transactional and recorded in `MigrationHistory`.

## 2. Created table — `DatasetQuality`

QualityID (PK autoinc) · DatasetVersion · RowCount · ValidRows · InvalidRows ·
DuplicateRows · MissingSnapshots · MissingLabels · BrokenReferences ·
LookAheadViolations · ConsistencyScore · CompletenessScore · IntegrityScore ·
OverallScore · QualityStatus · GeneratedAt + `idx_quality_version(DatasetVersion)`.
Append-only: every analysis stores a new report row (auditable, reproducible).

## 3. Quality status (STEP 2)

`QUALITY_UNKNOWN(0)` never analyzed (not exportable) · `QUALITY_PASS(1)` clean ·
`QUALITY_WARNING(2)` score<100, export blocked · `QUALITY_FAIL(3)` hard violation,
export blocked.

## 4. Analyzer (STEP 3) — `CDataQualityAnalyzer` (`EAData/DataQualityAnalyzer.mqh`)

```
ENUM_QUALITY_STATUS AnalyzeDataset(const int version);
bool GenerateQualityReport(const int version, string &report);
bool ValidateDataset(const int version);   // latest report == QUALITY_PASS
void Update(void);                         // one analysis per completed bar
```

## 5. Validation rules (STEP 4)

Duplicates (`COUNT(*)-COUNT(DISTINCT ObservationID)`), missing labels/snapshots (LEFT
JOIN → NULL), broken FKs (observation + non-NULL trade), invalid timestamps
(`BarTime<=0`, `ObservationTime<=0`, `ObservationTime<BarTime`), invalid feature values
(NULL in NOT NULL REALs — SQLite cannot store NaN there — `ATR<0`, `Spread<0`,
`High<Low`, close outside range), look-ahead leakage (per-row scan of the latest 500:
`GeneratedAt ≥ BarTime + LookaheadBars×TF` + structural lookahead contract), dataset
version mismatch (label `LabelVersion ≠ 1`).

## 6. Scores (STEP 5) — 0..100 integers

Completeness = valid/row ratio · Integrity = reference classes · Consistency =
semantic classes · Overall = mean of the three. Any hard violation ⇒ FAIL; else
overall==100 ⇒ PASS; else WARNING.

## 7. Export protection (STEP 6)

`CDatasetBuilder.ExportDataset(...CSV)` now consults the attached analyzer and refuses
the export (with a warning log) unless the latest report is `QUALITY_PASS`. The gate
lives inside the only export path; **override is not implemented and not possible**;
`QUALITY_UNKNOWN` blocks as well.

## 8. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAData/DataQualityAnalyzer.mqh` | the quality engine |
| `DATA_QUALITY_ENGINE.md` | schema / rules / scores / export protection |
| `docs/adr/ADR-0009-data-quality-engine.md` | decision record |

## 9. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 7`, `DB_TABLE_QUALITY`, `ENUM_QUALITY_STATUS` |
| `EAData/DatabaseSchema.mqh` | `MigrationToV7(ddl[])` |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` chain `1→…→7` |
| `EAData/DatasetBuilder.mqh` | +optional `AttachQuality()` gate checked in `ExportDataset` (STEP 6 requirement; builder logic itself unchanged) |
| `EATradeManager.mqh` | +include, +`m_quality`, `Initialize` + `AttachQuality` in `Init`, `Update()` after `m_datasets.Update()` |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (37 headers), counts (6 519 lines), binary size |

Dataset Builder core, Label Engine, Observation Engine, Feature Builder, trading:
untouched.

## 10. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (177 668 B binary).
* Trading/runtime unchanged; quality data is write/report-only.
* Export blocked for failed (and unanalyzed) datasets — enforced in code, no override.
* Quality reports reproducible (deterministic counts/scores over stored data).
* DAL reused (all SQL via `CDatabaseManager`).

**Stop condition honoured:** no AI, no Replay, no Event Bus. Waiting for Task 0012.
