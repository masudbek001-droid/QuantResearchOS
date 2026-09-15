# RUNTIME INVENTORY — Task 0002
Audit-only document. **No source file was modified, renamed or moved.** Line counts and call
sites were collected by repository scan on 2026-09-10.

## 1. Complete file inventory

### 1.1 MQL5 sources (frozen, `MQL5/`)

| File | Lines | Type | Purpose |
|---|---|---|---|
| `Experts/CandleBreakoutEA/CandleBreakoutEA.mq5` | 288 | expert | Entry point: 30 inputs in 8 groups, validation, `OnInit/OnDeinit/OnTick/OnTradeTransaction` |
| `Include/CandleBreakoutEA/EASettings.mqh` | 190 | header | 4 enums + `CEASettings` + 3 global stringifiers |
| `Include/CandleBreakoutEA/EAUtils.mqh` | 234 | header | `CEAUtils` static helper class (17 functions) |
| `Include/CandleBreakoutEA/EALogger.mqh` | 75 | header | `CLogger` |
| `Include/CandleBreakoutEA/EATradeHistory.mqh` | 191 | header | `CTradeHistory` + `SHistoryDealRow` |
| `Include/CandleBreakoutEA/EARiskManager.mqh` | 110 | header | `CRiskManager` |
| `Include/CandleBreakoutEA/EAOrderManager.mqh` | 180 | header | `COrderManager` |
| `Include/CandleBreakoutEA/EAPositionManager.mqh` | 141 | header | `CPositionManager` |
| `Include/CandleBreakoutEA/EABreakEvenManager.mqh` | 254 | header | `CBreakEvenManager` |
| `Include/CandleBreakoutEA/EAMomentum.mqh` | 125 | header | `CMomentumAnalyzer` + 7 scoring constants |
| `Include/CandleBreakoutEA/EATradeContext.mqh` | 61 | header | `STradeContext` |
| `Include/CandleBreakoutEA/EAExitEngine.mqh` | 218 | header | `CExitEngine` + `SExitSnapshot` + `EXIT_MIN_EVIDENCE_BARS` |
| `Include/CandleBreakoutEA/EAExitStats.mqh` | 136 | header | `CExitStats` + `SExitRecord` + `EXIT_REASON_COUNT` |
| `Include/CandleBreakoutEA/EADashboard.mqh` | 147 | header | `CDashboard` + 5 geometry constants + `DASH_LINES` |
| `Include/CandleBreakoutEA/EAVisualManager.mqh` | 169 | header | `CVisualManager` |
| `Include/CandleBreakoutEA/EATradeManager.mqh` | 642 | header | `CTradeManager` + `EXIT_SL_TOLERANCE_POINTS` |
| **total** | **3161** | | |

### 1.2 Configuration / resources / scripts / other

| Path | Kind | Notes |
|---|---|---|
| `.gitignore` | config | ignores `.build/` |
| `ARCHITECTURE_VERSION.md`, `README.md`, `STABILIZATION_REPORT.md`, `IMPLEMENTATION_READY_REPORT.md` | docs | root documentation |
| `docs/architecture/{MIPS,QRS,QOS}_v1.0.md`, `docs/adr/README.md`, `docs/backlog/README.md` | docs | frozen architecture + process |
| `CandleBreakoutEA.ex5` | resource | compiled binary (109 536 B) |
| `CandleBreakoutEA_package.zip` | resource | delivery package (18 entries) |
| `CandleBreakoutEA_Qollanma.pdf` | resource | Uzbek manual (16 pages) |
| `tools/build.py` | script | compile harness (MetaEditor64 under Wine) |
| `tools/build_manual.py`, `tools/manual_style.py`, `tools/manual_diagrams.py` | scripts | PDF manual generator |
| `tools/compile_mq5.py` | script | legacy single-file compile helper |
| `tools/mt5setup.exe` | resource | MT5 installer used by the harness |
| `preview/` | resource | PDF page renders for visual QA |
| `src/ tests/ database/ research/ models/ replay/ logs/ scripts/` | reserved | empty by Architecture Freeze (README placeholders only) |

No custom indicators, no external MQL5 libraries; the only third-party dependency is the stock
`<Trade\Trade.mqh>`.

## 2. Module classification

| File | Group | Rationale |
|---|---|---|
| `CandleBreakoutEA.mq5` | **Entry** | application entry point; owns inputs and validation; contains no strategy logic of its own |
| `EASettings.mqh` | **Core** | shared enums, configuration payload, stringifiers used by every layer |
| `EAUtils.mqh` | **Utilities** | stateless normalization / broker-limit / time helpers |
| `EALogger.mqh` | **Logging** | single log funnel, seven-tag vocabulary |
| `EATradeHistory.mqh` | **Database** | read-side persistence access (account history aggregation) |
| `EARiskManager.mqh` | **Risk** | candle gate: hours mask + daily limits |
| `EAOrderManager.mqh` | **Entry** | creates/deletes the breakout pending orders (no SL/TP) |
| `EAPositionManager.mqh` | **Runtime** | position inspection/closing plumbing used by both sides |
| `EABreakEvenManager.mqh` | **Exit** | exit priority #1, the only SL writer |
| `EAMomentum.mqh` | **Exit** | measurement feeding exit #3 and carry; no decisions |
| `EATradeContext.mqh` | **Context** | unified read-only trade snapshot |
| `EAExitEngine.mqh` | **Exit** | exit priorities #2/#3 per tick, carry (#4) at candle close, MFE/MAE tracking |
| `EAExitStats.mqh` | **Statistics** | per-reason counters + CSV journal writer |
| `EADashboard.mqh` | **Dashboard** | on-chart HUD, reads only `STradeContext` + stats |
| `EAVisualManager.mqh` | **Visual** | chart objects + prefix cleanup |
| `EATradeManager.mqh` | **Runtime** | candle-cycle state machine; orchestrates all managers; mandatory close (#5) |
| **Research** | — | no file classifies here; the folder is reserved and empty |
| **Unknown** | — | none; every file maps cleanly to exactly one group |

## 3. Runtime object inventory

* Two process-lifetime globals: `g_logger`, `g_trade_manager` (main .mq5 only).
* Sixteen class instances live inside `CTradeManager` (12 managers/engine + settings + logger copy).
* File-scope named constants: 7 momentum weights, 5 dashboard geometry values,
  `EXIT_MIN_EVIDENCE_BARS`, `EXIT_REASON_COUNT`, `EXIT_SL_TOLERANCE_POINTS`, `DASH_LINES`.
* No mutable file-scope state in any header.
