# 05_Training/Models

Trained model files.

Current Stage 8 research artifacts:

- `QROS_LogisticRegression_Baseline_v1.joblib`
- `QROS_RandomForest_Baseline_v1.joblib`

These are local scikit-learn baseline models. Matching ONNX exports are stored
under `05_Training/ONNX/`.

They are not live-trading models. Walk-forward validation and MT5-side ONNX
contract validation are still required before EAContextAI integration.
