# Project Inventory

Inventory date: 2026-09-15.

Recursive scan found 834 files:

| Extension | Count |
|---|---:|
| `.mqh` | 567 |
| `.mq5` | 23 |
| `.md` | 130 |
| `.py` | 15 |
| `.ex5` | 13 |
| `.log` | 11 |
| `.json` | 6 |
| `.db` | 5 |
| `.tmp` | 5 |
| `.bmp` | 23 |
| `.png` | 21 |
| `.hlsl` | 2 |
| `.joblib` | 2 |
| `.onnx` | 2 |
| `.csv` | 1 |
| `.pdf` | 1 |
| `.zip` | 1 |
| `.exe` | 1 |
| `.ini` | 1 |
| `.txt` | 1 |
| `.gitignore` | 1 |

Primary source: `C:\QuantResearchOS\01_Source\EA\MQL5` (EA build unit: 53 `.mqh` + 9 `.mq5` with validation scripts; 52+1 for the core EA).

> **Note 2026-09-15 audit:** 834 counted the staged `.build/` copy of the MT5 standard library (≈500 `.mqh`) plus 13 `.ex5`/`.log`/`.db` artifacts. Repo-only without `.build/` is ≈300 files (53 `.mqh`, 9 `.mq5`, 128 `.md`, 15 `.py`). The authoritative EA build unit remains 53 `.mqh` + 1 `.mq5` + 7 isolated validation scripts (all 0/0).

Active MetaTrader runtime:

- `C:\Program Files\MetaTrader`
- `C:\Program Files\MetaTrader\MQL5`

Important generated research artifacts:

- `05_Training\FeatureVectors\feature_vectors_v907100.csv`
- `05_Training\Models\QROS_LogisticRegression_Baseline_v1.joblib`
- `05_Training\Models\QROS_RandomForest_Baseline_v1.joblib`
- `05_Training\ONNX\QROS_LogisticRegression_Baseline_v1.onnx`
- `05_Training\ONNX\QROS_RandomForest_Baseline_v1.onnx`
- `05_Training\Metrics\phase_d_supervised_baseline_v907100.json`
- `05_Training\Metrics\phase_d_walk_forward_v907100.json`
