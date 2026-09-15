# QuantResearchOS

**Algorithmic trading research operating system for MetaTrader 5.**

The current recovery baseline is verified through Stage 15 (final reconciliation PASS) with the active
Windows MetaEditor and active MetaTrader runtime. AI remains shadow-only and is
not promoted to live trading authority.

QuantResearchOS is the production workspace of the **CandleBreakoutEA** project: a
compile-ready MQL5 Expert Advisor (M1 breakout on H1-candle-close exit, **no SL / no
TP**) surrounded by a full research operating system — market observation, ground-truth
labelling, reproducible datasets, quality gates, deterministic replay, experiments,
benchmarks, walk-forward validation and a historical data platform (ticks + M1–D1 bars).

```
QuantResearchOS/
├── 01_Source/       MQL5 source tree (compilable unit) + category index
├── 02_Databases/    database contracts & runtime locations (Ticks/Market/Research/Models)
├── 03_Documents/    ADRs, reports, specifications, architecture, sprint reports, manuals
├── 04_Output/       build output (EX5), logs, exports, reports, statistics
├── 05_Training/     generated feature vectors, baseline models, ONNX, metrics
├── 06_Tools/        build & documentation toolchain (Python)
├── 07_Backups/      manual backups
├── 08_Archives/     frozen packages, legacy folders, manual previews
└── *.md             governance documents (status, changelog, roadmap, guide…)
```

## Facts

| | |
|---|---|
| Architecture | v1.0 — **FROZEN** (changes only via ADR) |
| Database schema | v11 (additive migration chain 1→11) |
| Sources | MQL5 EA source + validation scripts under `01_Source/EA/MQL5` |
| Last compile | **0 errors, 0 warnings** — `CandleBreakoutEA.ex5`, 207,814 bytes |
| Trading core | final & frozen (MIPS v1.0) |
| Research subsystems | validated; dormant at init, explicit-API only |
| AI status | ONNX + replay inference validated; shadow-only, no trading authority |

## Start here

1. `PROJECT_STATUS.md` — dashboard
2. `ARCHITECTURE_MAP.md` — data → decision → research pipeline
3. `AGENT_GUIDE.md` — rules for every future agent
4. `RESTORE_GUIDE.md` — copying this project to another machine
5. `BUILD_AUDIT.md` and `FINAL_VALIDATION.md` — verified build/runtime boundary and current acceptance evidence
