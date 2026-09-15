# STAGE 5 - Replay Validation

Date: 2026-09-14

## Status

PASS - CLOSED.

## Findings

- Runtime `candlebreakout_20260909.db` has schema v11 tables, but replay input
  tables are currently empty:
  - `Symbols=0`
  - `Timeframes=0`
  - `MarketSnapshots=0`
  - `Observations=0`
  - `ResearchDatasets=0`
  - `DatasetQuality=0`
  - `ReplaySessions=0`
- Production Research.db therefore cannot yet prove replay behavior from real
  research data.
- `CReplayController::InitializeReplay()` had a runtime SQL defect: the
  `ReplaySessions` insert listed `TotalBars` but did not provide the matching
  value placeholder.

## Fix

- Fixed `CReplayController::InitializeReplay()` so `TotalBars` is inserted.
- Added isolated validation harness:
  `01_Source/EA/MQL5/Scripts/QuantResearchOS_ReplayValidation.mq5`

The harness uses magic `905001` and writes to isolated test database
`candlebreakout_905001.db`, leaving the production Research.db untouched.

## Build Validation

- EA build: `0 errors, 0 warnings`
- EA binary: `04_Output/EX5/CandleBreakoutEA.ex5` (`208574` bytes)
- Replay validation script build: `0 errors, 0 warnings`
- Active MT5 script binary:
  `C:\Program Files\MetaTrader\MQL5\Scripts\QuantResearchOS_ReplayValidation.ex5`
  (`56362` bytes)

## Final Runtime Evidence

`QuantResearchOS_ReplayValidation` was run in MT5 and reported:

- `[QROS_STAGE5] STATUS=PASS`
- `replay_id=1`
- `bars=4`
- `state=REPLAY_FINISHED`

Runtime validation database:

- file: `C:\Program Files\MetaTrader\MQL5\Files\candlebreakout_905001.db`
- `PRAGMA integrity_check=ok`
- `MarketSnapshots=4`
- `Observations=4`
- `ObservationLabels=4`
- `ResearchDatasets=4`
- `DatasetQuality=1`
- `ReplaySessions=1`
- final replay row: `ReplayID=1`, `DatasetVersion=905001`,
  `ReplayState=4`, `CurrentBar=3`, `TotalBars=4`
