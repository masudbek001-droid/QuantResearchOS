# AGENT HANDOFF — QuantResearchOS

> **Notice for Future AI Agents**: This document is the primary persistent memory layer of QuantResearchOS. Read this file, `README.md`, `PROJECT_STATUS.md`, and `PROJECT_PRINCIPLES.md` before making any modifications.

---

## 1. Project Purpose

**QuantResearchOS** is a reproducible quantitative research operating system and algorithmic trading platform centered on the **CandleBreakoutEA** architecture.

Its mission is to build an institutional-grade, end-to-end research-to-execution pipeline:
```
Market Data (Ticks/Bars)
  └──> Context Layer (STradeContext)
        └──> Feature Builder (22 v1 features)
              └──> Snapshots (MarketSnapshots, schema v2)
                    └──> Observations (Observations, schema v4)
                          └──> Outcome Labels (ObservationLabels, schema v5)
                                └──> Datasets (ResearchDatasets, schema v6)
                                      └──> Quality Validation Gate (DatasetQuality, schema v7)
                                            └──> Feature Registry & Manifests (FeatureRegistry, schema v8)
                                                  └──> Deterministic Replay (EAReplay, schema v9)
                                                        └──> Research Platform (EAResearch, schema v10)
                                                              └──> Historical Data Platform (EAHistory, schema v11)
                                                                    └──> Model Architecture & ML (Stages 8–9)
                                                                          └──> ONNX Runtime (Stages 10–11)
                                                                                └──> Shadow AI Context (Stages 12–14)
```

---

## 2. Core Architecture & Database Topology

### Four-Database Architecture (Sprint 6A / ADR-0013)

| Database | Location (MT5 Files) | Purpose | Primary Table(s) | Status |
|---|---|---|---|---|
| **Research.db** | `candlebreakout_<magic>.db` | Versioned research artifacts, DAL, lifecycle | `MarketSnapshots`, `Trades`, `Observations`, `ObservationLabels`, `ResearchDatasets`, `DatasetQuality`, `FeatureRegistry`, `ReplaySessions`, `Experiments`, `Benchmarks`, `WalkForwardRuns`, `DataSources`, `ImportHistory` | Active (Schema v11) |
| **Market.db** | `CBEA_Market.db` | High-performance historical multi-timeframe OHLCV | `Bars` (2,465,960 rows across M1..D1), `MarketMetadata` | Active (Validated Stage 4) |
| **Ticks.db** | `CBEA_Ticks.db` | Raw tick storage with deduplication & resume | `Ticks` (251,430,049 rows, 37.99 GB) | Active (Validated Stage 4) |
| **Models.db** | `CBEA_Models.db` | ML model registry, feature contracts, evaluations, ONNX metadata | `ModelsSchemaVersion` v2, `ModelArchitectures`, `ModelRegistry`, `FeatureVectorContracts`, `ModelEvaluations` | Active research/shadow-only (Stages 8–14 validated) |

---

## 3. Milestones & Task Status Summary

| Milestone / Task | Description | Schema / ADR | Status | Evidence |
|---|---|---|---|---|
| **Foundation** | CandleBreakoutEA v1.00 (MIPS v1.0 frozen trading core) | — | **VERIFIED DONE** | `04_Output/EX5/CandleBreakoutEA.ex5` (0 err / 0 warn) |
| **Task 0003** | Context Layer (`EAContext/`, `STradeContext`) | ADR-0001 | **VERIFIED DONE** | In production include tree |
| **Task 0004** | Feature Builder (`EAFeatureBuilder/`, `CFeatureSnapshot`) | ADR-0002 | **VERIFIED DONE** | 22 validated features |
| **Tasks 0005–0006** | Data Access Layer & DB v2 (`MarketSnapshots`, `Symbols`, `Timeframes`) | v2 / ADR-0003, 0004 | **VERIFIED DONE** | Schema v2, 24-field snapshot |
| **Task 0007** | Trade Intelligence v3 (`Trades`, Entry/Exit SnapshotID, `CTradeWriter`) | v3 / ADR-0005 | **VERIFIED DONE** | Schema v3 |
| **Task 0008** | Observation Engine v4 (`Observations`, 10 event types) | v4 / ADR-0006 | **VERIFIED DONE** | `UNIQUE(SymbolID, TF, BarTime, Type)` |
| **Task 0009** | Label Engine v5 (`ObservationLabels`, 3-bar future horizon) | v5 / ADR-0007 | **VERIFIED DONE** | Direction, MFE, MAE, BreakoutSuccess |
| **Task 0010** | Dataset Builder v6 (`ResearchDatasets`, joins, manifests, CSV export) | v6 / ADR-0008 | **VERIFIED DONE** | Batch size 50, CSV export |
| **Task 0011** | Data Quality Engine v7 (`DatasetQuality`, score 0..100, export gate) | v7 / ADR-0009 | **VERIFIED DONE** | PASS/WARN/FAIL, zero lookahead |
| **Task 0012** | Feature Registry v8 (`FeatureRegistry`, 22 v1 features, manifests) | v8 / ADR-0010 | **VERIFIED DONE** | 7 categories, manifests sidecars |
| **Sprint 4** | Replay Foundation v9 (`EAReplay/`, `ReplaySessions`) | v9 / ADR-0011 | **VERIFIED DONE** | `STAGE5_REPLAY_VALIDATION.md` PASS |
| **Sprint 5** | Research Platform v10 (`EAResearch/`, Experiments, Benchmarks, WF) | v10 / ADR-0012 | **VERIFIED DONE** | `STAGE7_RESEARCH_VALIDATION.md` PASS |
| **Sprint 6A** | Historical Data Platform v11 (`EAHistory/`, 4-DB topology, resume) | v11 / ADR-0013 | **VERIFIED DONE** | `STAGE4_HISTORY_EXPORT_CONTINUITY.md` PASS |
| **Stage 6** | Feature / Observation / Label / Dataset / Quality Validation | — | **VERIFIED DONE** | `STAGE6_DATA_PIPELINE_VALIDATION.md` PASS |
| **Stage 7** | Research / Experiment / Benchmark / WalkForward Validation | — | **VERIFIED DONE** | `STAGE7_RESEARCH_VALIDATION.md` PASS |
| **Stage 8** | Supervised baseline training + ONNX export | ADR-0014 | **VERIFIED DONE** | `STAGE8_SUPERVISED_MODEL_TRAINING.md` PASS |
| **Stage 9** | Walk-forward model validation | ADR-0014 | **VERIFIED DONE** | `STAGE9_WALK_FORWARD_VALIDATION.md` PASS |
| **Stage 10** | MT5 ONNX runtime validation | ADR-0014 | **VERIFIED DONE** | `STAGE10_MT5_ONNX_CONTRACT.md` PASS |
| **Stage 11** | Replay + ONNX inference validation | ADR-0014 | **VERIFIED DONE** | `STAGE11_REPLAY_ONNX_VALIDATION.md` PASS |
| **Stage 12** | AI promotion safety gates | ADR-0015 | **VERIFIED DONE** | `STAGE12_AI_PROMOTION_SAFETY_GATES.md` PASS |
| **Stage 13** | Shadow AI context runtime validation | ADR-0015 | **VERIFIED DONE** | `STAGE13_AI_SHADOW_CONTEXT_VALIDATION.md` PASS |
| **Stage 14** | Shadow AI source safety audit | ADR-0015 | **VERIFIED DONE** | `STAGE14_AI_SHADOW_SAFETY_AUDIT.md` PASS |

---

## 4. Current State

- **Current Milestone**: Stage 15 — Final Architecture/Documentation Reconciliation **PASS** (2026-09-15). Stable.
- **Active Task**: None — project is stable through Stage 14 validated runtime + Stage 15 reconciliation. Next work is optional README/PDF/manual refresh or a new ADR-controlled validation stage.
- **Immediate Next Tasks**:
  1. Keep AI shadow-only; no trading decision may consume predictions yet (ADR-0015 gated).
  2. If future advisory AI behavior is desired, create a new ADR and Strategy Tester / replay gate first.
  3. Optional: refresh `README.md` / `CandleBreakoutEA_Qollanma.pdf` package or run `06_Tools/build.py` to re-verify 0/0 before any live deployment.

---

## 5. Build and Test Toolchain

### Build Commands
- **Compile CandleBreakoutEA**:
  ```powershell
  python C:\QuantResearchOS\06_Tools\build.py
  ```
  *Requirement: 0 errors, 0 warnings, binary placed in `04_Output/EX5/CandleBreakoutEA.ex5`.*

- **Compile MQL5 Scripts Directly with MetaEditor**:
  ```powershell
  & "C:\Program Files\MetaTrader\MetaEditor64.exe" /inc:"C:\QuantResearchOS\.build" /compile:"C:\QuantResearchOS\.build\Scripts\<Script>.mq5" /log:"C:\QuantResearchOS\.build\<Script>-compile.log"
  ```

### Test & Validation Commands
- **Python MT5 Bridge Connection Test**:
  ```powershell
  python -c "import MetaTrader5 as mt5; print('MT5 init:', mt5.initialize()); print('Account:', mt5.account_info().login if mt5.account_info() else 'None'); mt5.shutdown()"
  ```
- **SQLite Database Integrity Checks**:
  ```powershell
  python -c "import sqlite3; conn = sqlite3.connect(r'C:\Program Files\MetaTrader\MQL5\Files\<db_name>'); print(conn.execute('PRAGMA integrity_check').fetchall())"
  ```

---

## 6. Important Project Paths

- **Root Workspace**: `C:\QuantResearchOS`
- **MQL5 Source Tree**: `C:\QuantResearchOS\01_Source\EA\MQL5`
  - EA Entrypoint: `01_Source/EA/MQL5/Experts/CandleBreakoutEA/CandleBreakoutEA.mq5`
  - EA Include Modules: `01_Source/EA/MQL5/Include/CandleBreakoutEA/`
    - `EAContext/` (Context Layer)
    - `EAData/` (Data Access Layer & Schemas)
    - `EAFeatureBuilder/` (Feature Calculation & Validation)
    - `EAHistory/` (Historical Data Exporters & Validators)
    - `EAReplay/` (Deterministic Replay Engine)
    - `EAResearch/` (Experiment, Benchmark & Walk-Forward Engines)
  - Validation Scripts: `01_Source/EA/MQL5/Scripts/`
- **MetaTrader 5 Installation**: `C:\Program Files\MetaTrader`
- **MT5 Runtime Data & DBs**: `C:\Program Files\MetaTrader\MQL5\Files\`
  - Production Research DB: `candlebreakout_20260909.db`
  - Market OHLCV DB: `CBEA_Market.db`
  - Tick DB: `CBEA_Ticks.db`
  - Models DB: `CBEA_Models.db`
  - Export CSVs: `C:\Program Files\MetaTrader\MQL5\Files\CBEA\`
- **Staging & Build Directory**: `C:\QuantResearchOS\.build`
- **Output Binaries**: `C:\QuantResearchOS\04_Output\EX5\`
- **Training & ML Workspaces**: `C:\QuantResearchOS\05_Training\`
  - `Datasets/`, `FeatureVectors/`, `Metrics/`, `Models/`, `ONNX/`
- **Tools & Automation Scripts**: `C:\QuantResearchOS\06_Tools\`

---

## 7. Version Pins

- **Database Schema Version**: `11` (chain: 1→2→3→4→5→6→7→8→9→10→11)
- **Feature Version**: `1` (22 standard features catalogued in `CFeatureRegistry`)
- **Label Version**: `1` (lookahead: 3 bars, threshold: 0.5 range)
- **Dataset Version**: Pipeline validation `906001`/`907001`; training feature vectors `v907100` (56,499 rows, 22-feature contract)
- **Current Models**: 2 baseline models registered in `CBEA_Models.db` (Models v2) — `QROS_LogisticRegression_Baseline_v1` and `QROS_RandomForest_Baseline_v1` — research/shadow-only, ONNX PASS, not loaded into live trading (ADR-0015)
- **Stage 15 Status**: **PASS** — architecture, DB, build, and docs reconciled to Stage 14 reality

---

## 8. Prohibited Regressions & Rules of the Road (Strictly Enforced)

1. **NO LOOK-AHEAD BIAS**:
   - Training features MUST NEVER contain information from the future.
   - Observation time vs label horizon vs feature calculation time must be strictly verified.
2. **FROZEN TRADING CORE (MIPS v1.0)**:
   - Entry: M1 candle breakout.
   - **NO SL / NO TP anywhere, ever.**
   - Exit: H1 candle close.
   - BreakEven: Optional (default OFF).
   - Exit priority: BreakEven > ProfitLock > Momentum > Carry > H1 close.
   - Trading behaviour must not be altered without an approved Architectural Decision Record (ADR).
3. **DAL BOUNDARY**:
   - All SQLite operations must go through `IDataProvider` / `CSQLiteProvider` / `CDatabaseManager`.
   - Never write raw SQL directly in trading or feature managers.
4. **MIGRATION IMMUTABILITY**:
   - Never modify migrations 1→11 in `DatabaseSchema.mqh` or `DatabaseVersion.mqh`.
   - Schema updates must be strictly additive and appended as v12+.
5. **ZERO WARNINGS / ZERO ERRORS**:
   - Every compile must result in `0 errors, 0 warnings`.
   - Never hide or suppress compiler warnings.
6. **QUALITY GATING**:
   - No dataset export or ML consumption without passing `CDataQualityAnalyzer` (`QUALITY_PASS`).
