# 01_Source/EA — the compilable MQL5 tree

```text
EA/MQL5/
├── Experts/CandleBreakoutEA/CandleBreakoutEA.mq5   ← entry point
└── Include/CandleBreakoutEA/                       ← 52 class modules
    ├── EAContext/  EAFeatureBuilder/  EAData/  EAReplay/  EAResearch/  EAHistory/
    └── root trading modules (FROZEN, MIPS v1.0)
```

Keep this layout exactly — include paths depend on it. Build with `06_Tools/build.py`.
