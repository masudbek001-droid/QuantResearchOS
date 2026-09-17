# Refactor Summary

- Repaired the build boundary in `06_Tools/build.py` from hard-coded Linux/Wine paths to the declared Windows MetaTrader installation.
- Added an optional `QUANTRESEARCHOS_MT5` override.
- Added verified EX5 publication to `04_Output/EX5`.
- Created a pre-recovery backup of the installed CandleBreakoutEA before synchronization.
- Repaired historical export database path/schema handling.
- Repaired replay session insertion for `ReplaySessions.TotalBars`.
- Repaired walk-forward boundary validation to allow contiguous non-overlapping
  train/test intervals.
- Added supervised training, ONNX export, walk-forward validation, replay+ONNX
  validation, and shadow-only AI context validation tools.
- Updated stale reserved/model/training documentation to match current Stage 15
  reality (final reconciliation).

No trading feature behavior was changed. AI remains shadow-only and has no
trading authority.
