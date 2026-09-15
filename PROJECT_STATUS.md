# PROJECT STATUS — Dashboard

| Field | Value |
|---|---|
| **Project Version** | QuantResearchOS 1.0 (CandleBreakoutEA v1.00) |
| **Architecture Version** | v1.0 — FROZEN (changes only via ADR) |
| **Database Schema Version** | v11 (Research.db; additive chain 1→11) |
| **Current Milestone** | Sprint 6B — Model Architecture Platform & Phase C Statistical Baseline |
| **Current Sprint** | Sprint 6B / Statistical Baseline — **ACTIVE** |
| **Completed Sprints** | Tasks 0003–0012 (Context Layer, Feature Builder, DAL, schema v2–v8) · Sprint 4 (Replay Foundation, v9, ADR-0011) · Sprint 5 (Research Platform, v10, ADR-0012) · Sprint 6A (Historical Data Platform, v11, ADR-0013) |
| **Completed Validation Stages** | Stage 0 (Recovery) · Stage 1 (Compile) · Stage 3 (DB Integrity) · Stage 4 (History Continuity PASS) · Stage 5 (Replay PASS) · Stage 6 (Pipeline PASS) · Stage 7 (Research Platform PASS) · Stage 8 (Supervised Baseline Training PASS) · Stage 9 (Walk-Forward Validation PASS) · Stage 10 (MT5 ONNX Runtime PASS) · Stage 11 (Replay + ONNX PASS) · Stage 12 (AI Safety Gates PASS) · Stage 13 (Shadow AI Context PASS) · Stage 14 (Shadow AI Safety Audit PASS) · **Stage 15 (Final Reconciliation PASS)** |
| **Current Task** | Project stabilized through Stage 15 |
| **Next Task** | Optional: refresh README/PDF/manual package, or create a new ADR for the next shadow/tester validation stage |
| **Overall Progress** | ≈ 95 % (trading core 100 %, data platform 100 %, research 100 %, replay 100 %, baseline ML/training 85 %, AI integration 40 %, documentation reconciliation 100 %) |
| **Module Status** | 52 `.mqh` + 1 `.mq5`, all compile clean; trading modules frozen; research/replay/history dormant at init |
| **Database Status** | Research.db, Ticks.db (251M rows), Market.db (2.46M bars; H1=56,529), Models.db schema v2 with 2 registered baseline models and 16 evaluation rows, and test DBs (905001, 906001, 907001) all integrity-checked OK |
| **Last Successful Compile** | 2026-09-15 — MetaEditor, **0 errors / 0 warnings**; `04_Output/EX5/CandleBreakoutEA.ex5` = 207 814 bytes; active MT5 EA EX5 synchronized; Stage 7 script EX5 = 59 392 bytes; Stage 10 script EX5 = 11 090 bytes; Stage 11 script EX5 = 59 680 bytes; Stage 13 script EX5 = 14 134 bytes |

## Module groups

| Group | Location (01_Source/EA/MQL5/Include/CandleBreakoutEA/) | State |
|---|---|---|
| Trading core (frozen) | root modules: Settings, Logger, Risk, Order, Position, BreakEven, Momentum, ExitEngine, ExitStats, TradeManager… | FROZEN — MIPS v1.0 |
| Context Layer | `EAContext/` (5) | operational |
| Feature Builder | `EAFeatureBuilder/` (4) | operational |
| Data Access Layer | `EAData/` (13, schema v11) | operational |
| Replay Foundation | `EAReplay/` (4) | dormant, explicit start; Stage 5 validated |
| Research Platform | `EAResearch/` (3) | dormant, explicit API; Stage 7 validated |
| Historical Data Platform | `EAHistory/` (7) | dormant, explicit API; Stage 4 validated |
| Dashboard / visual | `EADashboard.mqh`, `EAVisualManager.mqh` | operational |

## Known limits

* Broker live behaviour (fills, expiration, stops level) untested — demo/Strategy Tester before live.
* `05_Training/` is active for feature extraction, statistical baseline, and model training.
* ONNX export is available and both Stage 8 ONNX artifacts pass `onnx.checker`; MT5-side ONNX loading passed in Stage 10.
* Baseline models are research artifacts only; they are not loaded into live trading.
* Stage 11 proves replay-time ONNX inference, not production trading readiness.
