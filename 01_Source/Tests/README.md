# 01_Source/Tests — Verification harness

This folder is an **index**, not a copy: the compilable MQL5 tree lives intact at
`01_Source/EA/MQL5/` (moving headers would break `#include <CandleBreakoutEA\...>` paths).

## Contents of this category

Verification = the real MetaQuotes compiler: `06_Tools/build.py` must report 0 errors / 0 warnings and produce the .ex5. No unit-test framework is used (MQL5).
