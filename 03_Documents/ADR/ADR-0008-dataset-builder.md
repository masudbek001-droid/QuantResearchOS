# ADR-0008 — Research Dataset Builder (schema v6, reproducible exports)

*Status: Accepted (approved by engineering Task 0010).*

## Context
The platform now records observations (v4), labels them with ground truth (v5) and
stores market feature vectors (v2). Machine-learning work needs one reproducible join
of these artifacts, built without any prediction and without touching trading.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 6 and add `ResearchDatasets` (DatasetVersion,
   ObservationID, SnapshotID, LabelID, nullable TradeID, ExportStatus, CreatedAt) with
   four indexes and `UNIQUE(DatasetVersion,ObservationID)`. Migration `5 → 6` runs
   through `ApplyMigration("research dataset builder", ddl[5])`.
2. Add `CDatasetBuilder` (in `EAData/`): `BuildDataset()` (batched set-based
   INSERT..SELECT with INNER joins and a NOT EXISTS guard — structurally impossible to
   insert rows with missing snapshot/label), `ValidateDataset()` (FK + duplicate
   integrity), `ExportDataset()` (deterministic CSV; Parquet placeholder; SQLite
   internal status).
3. `DATASET_VERSION` versioning: contract changes are additive; published versions are
   immutable, guaranteeing reproducible exports.
4. One build pass per completed bar on the existing funnel; the EA never reads the
   dataset table.

## Consequences
* ML-ready training files are one API call away, byte-reproducible per version.
* The whole ground-truth pipeline (observations → labels → datasets) now lives behind
  the DAL with zero runtime trading impact.
* Parquet export is an explicit placeholder until a writer ADR lands.
