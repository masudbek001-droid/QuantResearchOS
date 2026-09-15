# 01_Source/Models — Model architecture index

This folder is an index, not a copy: the compilable MQL5 tree lives intact at
`01_Source/EA/MQL5/` because moving headers would break
`#include <CandleBreakoutEA\...>` paths.

`Models.db` is currently at `ModelsSchemaVersion = 2` and is managed by
`01_Source/Database/migrate_models_v2.py`.

Current model artifacts are produced by `06_Tools/train_phase_d_models.py` and
stored under `05_Training/`. The EAContextAI slot in `EAContext/` remains the
reserved integration point; no trained model is loaded into live trading yet.
