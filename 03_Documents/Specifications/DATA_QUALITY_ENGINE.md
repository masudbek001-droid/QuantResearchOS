# RESEARCH DATA QUALITY ENGINE — `DatasetQuality` (schema v7)

Implemented by Task 0011 under ADR-0009. The Quality Engine validates every research
dataset **before** it may be used for machine learning. A dataset that is not
`QUALITY_PASS` **cannot be exported** — there is no override.

## 1. Schema

### `DatasetQuality` (one report row per analysis)

`QualityID` (PK autoinc) · `DatasetVersion` · `RowCount` · `ValidRows` · `InvalidRows` ·
`DuplicateRows` · `MissingSnapshots` · `MissingLabels` · `BrokenReferences` ·
`LookAheadViolations` · `ConsistencyScore` · `CompletenessScore` · `IntegrityScore` ·
`OverallScore` · `QualityStatus` (`ENUM_QUALITY_STATUS`) · `GeneratedAt`
+ `idx_quality_version(DatasetVersion)`

Reports are append-only: every analysis stores a new row, so the quality history of a
dataset version is fully auditable and each report is reproducible from the dataset
state at the time.

## 2. Quality status (STEP 2)

| Value | Status | Meaning |
|---|---|---|
| 0 | `QUALITY_UNKNOWN` | never analyzed — not exportable |
| 1 | `QUALITY_PASS` | clean — CSV export allowed |
| 2 | `QUALITY_WARNING` | score below 100 but no hard violation — export blocked |
| 3 | `QUALITY_FAIL` | hard violation — export blocked |

## 3. Analyzer (STEP 3) — `CDataQualityAnalyzer`

```
ENUM_QUALITY_STATUS AnalyzeDataset(const int version);  // runs all checks, stores a report
bool GenerateQualityReport(const int version, string &report);
bool ValidateDataset(const int version);                // latest report == QUALITY_PASS?
void Update(void);                                      // one analysis per completed bar
```

No business logic: the analyzer only counts, scores and reports.

## 4. Validation rules (STEP 4)

| Check | Implementation |
|---|---|
| duplicate rows | `COUNT(*) - COUNT(DISTINCT ObservationID)` per version |
| missing labels | `LEFT JOIN ObservationLabels` → NULL |
| missing snapshots | `LEFT JOIN MarketSnapshots` → NULL |
| broken foreign keys | observation FK, non-NULL trade FK |
| invalid timestamps | `BarTime<=0`, `ObservationTime<=0`, `ObservationTime<BarTime` |
| invalid feature values / NaN / Infinity | NULL in NOT NULL REAL columns (SQLite cannot hold NaN there), `ATR<0`, `Spread<0`, `High<Low`, close outside range |
| look-ahead leakage | per-row scan (latest 500): label `GeneratedAt` must be ≥ `BarTime + LookaheadBars × timeframe`; plus structural `LookaheadBars` contract |
| dataset version mismatch | rows whose label `LabelVersion` ≠ 1 |

## 5. Scores (STEP 5) — integers 0..100

* `CompletenessScore = 100 × ValidRows / RowCount` (all problem classes subtracted)
* `IntegrityScore` — reference integrity: broken refs, missing snapshots/labels, duplicates
* `ConsistencyScore` — semantic integrity: look-ahead, version mismatch, invalid
  timestamps/features
* `OverallScore = (completeness + integrity + consistency) / 3`
* Status: any hard violation ⇒ `FAIL`; else `overall == 100` ⇒ `PASS`; else `WARNING`.

## 6. Export protection (STEP 6)

`CDatasetBuilder::ExportDataset(..., DATASET_EXPORT_CSV)` consults the attached
analyzer: if the latest report of the version is not `QUALITY_PASS`, the export is
refused and logged. **Override is not possible** — the gate sits inside the only export
path, and an unanalyzed dataset (`QUALITY_UNKNOWN`) is blocked as well.

## 7. Determinism & safety

* Reports depend only on stored data — the same dataset state always produces the same
  scores (reproducible).
* Read-only + one INSERT per pass; the EA trading path never reads quality data; all
  SQL goes through the DAL.
