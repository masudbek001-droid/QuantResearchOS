# RESEARCH DATASET BUILDER — `ResearchDatasets` (schema v6)

Implemented by Task 0010 under ADR-0008. The Dataset Builder assembles the ML-ready
research set by joining the platform's ground-truth pipeline. It performs **no
prediction** and takes no trading decisions.

## 1. The join

```
Observations (what happened)
  + MarketSnapshots   (24-column feature vector of the same bar, via FeatureSnapshotID)
  + ObservationLabels (ground-truth outcome, LabelVersion = 1)
  + Trades            (optional reference, NULL for trade-independent observations)
  = ResearchDatasets  (one row = one training sample)
```

## 2. Schema

### `ResearchDatasets`

`DatasetID` (PK autoinc) · `DatasetVersion` · `ObservationID` → `Observations` ·
`SnapshotID` → `MarketSnapshots` · `LabelID` → `ObservationLabels` ·
`TradeID` (nullable → `Trades`) · `ExportStatus` (`ENUM_DATASET_EXPORT`: 0 none /
1 CSV / 2 Parquet-placeholder / 3 internal) · `CreatedAt` ·
`UNIQUE(DatasetVersion, ObservationID)`

Indexes: `idx_ds_obs(ObservationID)`, `idx_ds_label(LabelID)`,
`idx_ds_version(DatasetVersion)`, `idx_ds_export(ExportStatus)`.

## 3. Dataset rules (STEP 3)

Every row contains observation + feature snapshot + ground-truth label, with an
optional trade reference. The builder uses **INNER joins + `FeatureSnapshotID IS NOT
NULL`**, so rows with a missing snapshot or label can never enter the set; duplicates
are blocked by the UNIQUE constraint and a `NOT EXISTS` guard.

## 4. Builder API (STEP 2)

```
int  BuildDataset(const int version);            // batched (50/pass), BarTime order
bool ValidateDataset(const int version);         // FK + duplicate integrity
bool ExportDataset(const int version, const ENUM_DATASET_EXPORT format);
void Update(void);                               // one build pass per completed bar
```

`DATASET_VERSION = 1`; a contract change ships as a new version via ADR — v1 rows are
never modified, so any published dataset stays reproducible.

## 5. Validation (STEP 4)

`BuildDataset` structurally rejects: missing snapshot (join condition), missing label
(join condition). `ValidateDataset` rejects the version when any row has: broken
observation FK, broken snapshot FK, broken label FK, non-NULL but missing trade FK, or
a duplicate `ObservationID`. Export refuses to run on a failed validation.

## 6. Export (STEP 6)

| Format | Status |
|---|---|
| CSV | implemented — `MQL5/Files/CBEA/dataset_v<n>.csv`, `;` separated, fixed 34-column header |
| Parquet | placeholder — `ExportDataset(..., DATASET_EXPORT_PARQUET)` logs and returns false |
| SQLite internal | the dataset table itself; export marks `ExportStatus` |

**Reproducibility:** the export SELECT is deterministic (`ORDER BY ObservationID`),
columns and separator are fixed, numeric text comes straight from SQLite storage
format — the same dataset version always produces byte-identical CSV.

## 7. Safety

* No look-ahead: rows exist only for observations whose labels were generated after
  their future window completed (Label Engine contract); the builder adds no data.
* Runtime independence: the EA never reads `ResearchDatasets`; the builder is
  write/export-only, one batched pass per completed bar, all SQL through the DAL.

## 8. Future compatibility

* **AI**: `ExportDataset` CSV is the training input; `TradeID` enables outcome-joined
  subsets; new feature columns arrive via new dataset versions.
* **Replay**: dataset rows reference exact observations/snapshots, letting a replay
  engine validate models against recorded history.
