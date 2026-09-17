# 01_Source/ML — ML layer — ACTIVE (research/shadow-only, Stages 8–14)

This folder is an **index**, not a copy: the compilable MQL5 tree lives intact at
`01_Source/EA/MQL5/` (moving headers would break `#include <CandleBreakoutEA\...>` paths).

## Contents of this category

Training artifacts live in `05_Training/` (feature vectors, .joblib, ONNX, metrics) and model metadata in `CBEA_Models.db` Models v2 (see `02_Databases/Models/`). Stages 8–11 trained 2 baselines, exported ONNX, validated MT5 load + replay inference. Models remain research/shadow-only per ADR-0015; no live trading authority.
