# Build Audit

Command: `python C:\QuantResearchOS\06_Tools\build.py`

Result on 2026-09-15: **PASS — 0 errors, 0 warnings, EX5 produced**.

The build stages source into `.build`, imports the standard library from the active MetaTrader installation, invokes the real Windows MetaEditor, parses the compiler result, and copies the verified binary to `04_Output/EX5/CandleBreakoutEA.ex5`.

Current EA binary:

- Project output: `C:\QuantResearchOS\04_Output\EX5\CandleBreakoutEA.ex5`
- Active MT5 output: `C:\Program Files\MetaTrader\MQL5\Experts\CandleBreakoutEA\CandleBreakoutEA.ex5`
- Size: 207,814 bytes

Validation scripts compiled cleanly with 0 errors / 0 warnings (2026-09-15):

- `QuantResearchOS_HistoricalExport` — historical tick/bar export harness
- `QuantResearchOS_ReplayValidation` — replay foundation validation (magic 905001)
- `QuantResearchOS_Stage6Validation` — feature/observation/label/dataset/quality pipeline (906001)
- `QuantResearchOS_Stage7Validation` — research platform validation (907001) — 59,392 bytes
- `QuantResearchOS_Stage7Validation_EA` — research EA harness — 59,104 bytes (expert)
- `QuantResearchOS_OnnxValidation` — MT5 ONNX runtime — 11,090 bytes
- `QuantResearchOS_ReplayOnnxValidation` — replay+ONNX inference — 59,680 bytes
- `QuantResearchOS_AIShadowValidation` — shadow AI context — 14,134 bytes

EA binary: `04_Output/EX5/CandleBreakoutEA.ex5` — 207,814 bytes, 53 .mqh + 1 .mq5, 0 errors / 0 warnings; active MT5 EX5 synchronized.
