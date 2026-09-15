# STAGE 4 - History and Export Continuity Validation

Date: 2026-09-14

## Status

PASS - CLOSED.

## Evidence

- Historical export was run again through `QuantResearchOS_HistoricalExport`.
- Tick export resumed from the stored maximum timestamp instead of reloading the full archive.
- The second run imported `58,607` new ticks and reported:
  - `ticks: total=251392641 duplicates=0 invalid=0 out_of_order=0`
- Bar export imported new bars without duplicate keys, but the validation gate reported:
  - `PERIOD_H1: total=56527`
  - `PERIOD_M15: total=122881`
  - `timeframe consistency: H1=56527 M15=122881 ratio=2.17 -> MISMATCH`

## Root Cause

The H1/M15 validator compared full-table counts. After the re-run, H1 history covered
2016-09-18 through 2026-09-14, while M15 history covered 2021-07-01 through
2026-09-14. Comparing full counts across different coverage windows produced a false
failure.

## Fix

`CDataIntegrityValidator::ValidateTimeframes()` now computes the common H1/M15
coverage window first, then compares only the counts inside that shared range.

Changed file:

- `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAHistory/DataIntegrityValidator.mqh`

Additional cleanup:

- `CHistoryStore::EnsureMasters()` removes pre-v11 minute-based timeframe IDs
  from the `Timeframes` master.
- `CBarExporter::EnsureTable()` removes legacy bar rows with `TimeframeID IN
  (60,240,1440)`.
- Runtime `CBEA_Market.db` was backed up before cleanup:
  `07_Backups/stage4-marketdb-20260914/CBEA_Market.db`
- Runtime cleanup removed `40,669` legacy bar rows.

Post-cleanup validation:

- `market_rows=2,465,748`
- `legacy_rows=0`
- `duplicate_groups=0`
- `invalid=0`
- common H1/M15 range: `2021-07-01 13:30:00` to `2026-09-14 09:00:00`
- common H1 bars: `30,755`
- common M15 bars: `122,881`
- ratio: `3.9954804096894816`
- `timeframe_ok=true`

## Build Validation

- `06_Tools/build.py`
- Result: `0 errors, 0 warnings`
- EA binary produced: `CandleBreakoutEA.ex5` (`208670` bytes)

The historical export script was also compiled separately:

- Result: `0 errors, 0 warnings`
- Script binary copied to active MT5:
  `C:\Program Files\MetaTrader\MQL5\Scripts\QuantResearchOS_HistoricalExport.ex5`
- Script binary size: `80100` bytes

## Remaining Gate

The corrected `QuantResearchOS_HistoricalExport` EX5 was run again on 2026-09-14.
Stage 4 is closed with:

- `STATUS=PASS`
- `EXPORT=PASS`
- `INTEGRITY=PASS`
- `STATISTICS=PASS`

Final runtime evidence:

- `export: ticks=37414 bars=219`
- `ticks: total=251430049 duplicates=0 invalid=0 out_of_order=0`
- `PERIOD_M1: total=1838117 duplicates=0 invalid=0`
- `PERIOD_M5: total=368390 duplicates=0 invalid=0`
- `PERIOD_M15: total=122891 duplicates=0 invalid=0`
- `PERIOD_M30: total=61462 duplicates=0 invalid=0`
- `PERIOD_H1: total=56529 duplicates=0 invalid=0`
- `PERIOD_H4: total=15507 duplicates=0 invalid=0`
- `PERIOD_D1: total=3064 duplicates=0 invalid=0`
- `timeframe consistency: common=2021.07.01..2026.09.14 H1=30757 M15=122889 ratio=4.00 -> OK`
- final bars total: `2465960`
