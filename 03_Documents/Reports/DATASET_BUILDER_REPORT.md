# DATASET BUILDER REPORT — Task 0010 (Foundation)

## 1. Database version

`DB_SCHEMA_VERSION = 6` (was 5). Full chain for every file: `1→2` market intelligence →
`2→3` trade intelligence → `3→4` observation engine → `4→5` label engine → `5→6` dataset
builder, each transactional and recorded in `MigrationHistory`.

## 2. Created table — `ResearchDatasets`

DatasetID (PK autoinc) · DatasetVersion · ObservationID → Observations ·
SnapshotID → MarketSnapshots · LabelID → ObservationLabels · TradeID (nullable →
Trades) · ExportStatus (ENUM_DATASET_EXPORT: none/CSV/Parquet-placeholder/internal) ·
CreatedAt · UNIQUE(DatasetVersion,ObservationID)

## 3. Builder (STEP 2) — `CDatasetBuilder` (`EAData/DatasetBuilder.mqh`)

```
int  BuildDataset(const int version);   // set-based INSERT..SELECT, batch 50/pass
bool ValidateDataset(const int version);
bool ExportDataset(const int version, const ENUM_DATASET_EXPORT format);
void Update(void);                      // one build pass per completed bar
```

## 4. Dataset rules (STEP 3)

One row = observation + feature snapshot + ground-truth label (+ optional trade
reference). INNER joins on observation/snapshot/label + `FeatureSnapshotID IS NOT
NULL` make missing-FK rows structurally impossible; `NOT EXISTS` + the UNIQUE
constraint block duplicates.

## 5. Validation (STEP 4)

`ValidateDataset` fails the version on: broken observation FK, missing snapshot,
missing label, non-NULL but missing trade FK, or duplicate ObservationID. Export runs
only after a passed validation.

## 6. Indexes (STEP 5)

`idx_ds_obs(ObservationID)` · `idx_ds_label(LabelID)` · `idx_ds_version(DatasetVersion)`
· `idx_ds_export(ExportStatus)`

## 7. Export (STEP 6)

* **CSV** — `MQL5/Files/CBEA/dataset_v<n>.csv`; deterministic (`ORDER BY
  ObservationID`), fixed 34-column `;`-separated layout → byte-reproducible per
  dataset version.
* **Parquet** — placeholder: logs "not implemented yet", returns false (writer arrives
  via a future ADR).
* **SQLite internal** — the dataset table itself; export marks `ExportStatus`.

## 8. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAData/DatasetBuilder.mqh` | dataset engine |
| `DATASET_BUILDER.md` | join model / rules / validation / export / reproducibility |
| `docs/adr/ADR-0008-dataset-builder.md` | decision record |

## 9. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 6`, `DB_TABLE_DATASETS`, `ENUM_DATASET_EXPORT` |
| `EAData/DatabaseSchema.mqh` | `MigrationToV6(ddl[])` — table + 4 indexes |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` chain `1→2→3→4→5→6` |
| `EATradeManager.mqh` | +include, +`m_datasets`, `Initialize` in `Init`, `Update()` after `m_labels.UpdatePendingLabels()` |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (36 headers), counts (6 203 lines), binary size |

Observation Engine, Label Engine, Feature Builder, entry/exit/BE/carry/PL: untouched.

## 10. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (172 128 B binary).
* Trading and runtime unchanged; the EA never reads `ResearchDatasets`.
* Dataset rows reproducible (immutable versions + deterministic export).
* No look-ahead: rows exist only for already-labelled observations (labels themselves
  require a completed future window).
* DAL reused (all SQL via `CDatabaseManager`).

**Stop condition honoured:** no AI, no Replay, no Event Bus. Waiting for Task 0011.
