# Build Audit

Command: `python C:\QuantResearchOS\06_Tools\build.py`

Result on 2026-09-15: **PASS — 0 errors, 0 warnings, EX5 produced**.

The build stages source into `.build`, imports the standard library from the active MetaTrader installation, invokes the real Windows MetaEditor, parses the compiler result, and copies the verified binary to `04_Output/EX5/CandleBreakoutEA.ex5`.

Current EA binary:

- Project output: `C:\QuantResearchOS\04_Output\EX5\CandleBreakoutEA.ex5`
- Active MT5 output: `C:\Program Files\MetaTrader\MQL5\Experts\CandleBreakoutEA\CandleBreakoutEA.ex5`
- Size: 207,814 bytes

Validation scripts compiled cleanly with 0 errors / 0 warnings:

- `QuantResearchOS_Stage7Validation`
- `QuantResearchOS_OnnxValidation`
- `QuantResearchOS_ReplayOnnxValidation`
- `QuantResearchOS_AIShadowValidation`
