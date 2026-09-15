# 05_Training/Models

Trained model files.

Current Stage 8 research artifacts:

- `QROS_LogisticRegression_Baseline_v1.joblib`
- `QROS_RandomForest_Baseline_v1.joblib`

These are local scikit-learn baseline models. Matching ONNX exports are stored
under `05_Training/ONNX/`.

They remain research/shadow-only per ADR-0015 (Stage 13–14 PASS). Walk-forward validation (Stage 9), MT5-side ONNX loading (Stage 10), and replay+ONNX inference (Stage 11) have all PASSED (shadow-only inference validated, no trading authority).
