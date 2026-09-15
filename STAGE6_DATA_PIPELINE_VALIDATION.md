# STAGE 6 - Feature / Observation / Label / Dataset / Quality Validation

Date: 2026-09-14

## Status

PASS - CLOSED.

## Scope

Stage 6 validates the research data production chain:

1. Feature Builder
2. Market Snapshot contract
3. Observation Engine
4. Label Engine
5. Dataset Builder
6. Data Quality Engine
7. Quality-gated dataset export

## Findings

- Production `candlebreakout_20260909.db` currently has schema v11 but no real
  research rows in `MarketSnapshots`, `Observations`, `ObservationLabels`,
  `ResearchDatasets`, or `DatasetQuality`.
- Production Research.db therefore must not be used as the Stage 6 proving
  ground yet.
- The validation path uses isolated magic `906001` and database
  `candlebreakout_906001.db`.

## Harness

Added:

- `01_Source/EA/MQL5/Scripts/QuantResearchOS_Stage6Validation.mq5`

The harness:

- checks live `CFeatureBuilder` readiness on the chart symbol and H1 timeframe;
- seeds deterministic H1 snapshots into isolated Research.db;
- writes observations through `CObservationWriter`;
- generates labels through `CLabelGenerator`;
- builds a dataset through `CDatasetBuilder`;
- runs `CDataQualityAnalyzer`;
- verifies that unsupported Parquet export stays blocked;
- verifies that CSV export is allowed only after quality PASS.

## Build Validation

- EA build: `0 errors, 0 warnings`
- EA binary: `04_Output/EX5/CandleBreakoutEA.ex5` (`207326` bytes)
- Stage 6 script build: `0 errors, 0 warnings`
- Active MT5 script binary:
  `C:\Program Files\MetaTrader\MQL5\Scripts\QuantResearchOS_Stage6Validation.ex5`
  (`78046` bytes)

## Final Runtime Evidence

`QuantResearchOS_Stage6Validation` was run in MT5 on XAUUSD/H1 and reported:

- `[QROS_STAGE6] STATUS=PASS`
- `features=PASS`
- `export=PASS`
- `snapshots=4`
- `observations=4`
- `labels=4`
- `datasets=4`
- `quality=1`

Isolated validation database:

- file: `C:\Program Files\MetaTrader\MQL5\Files\candlebreakout_906001.db`
- `PRAGMA integrity_check=ok`
- `Symbols=1`
- `Timeframes=1`
- `MarketSnapshots=4`
- `Observations=4`
- `ObservationLabels=4`
- `ResearchDatasets=4`
- `DatasetQuality=1`
- latest quality row: `DatasetVersion=906001`, `RowCount=4`,
  `ValidRows=4`, `InvalidRows=0`, `QualityStatus=1`, `OverallScore=100`

CSV export:

- file: `C:\Program Files\MetaTrader\MQL5\Files\CBEA\dataset_v906001.csv`
- size: `1007` bytes
- lines: `5` (header + 4 data rows)
