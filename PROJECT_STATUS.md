# PROJECT STATUS — Dashboard

| Field | Value |
|---|---|
| **Project Version** | QuantResearchOS 1.0 (CandleBreakoutEA v1.00) |
| **Architecture Version** | v1.0 — FROZEN (changes only via ADR) |
| **Database Schema Version** | v11 (Research.db; additive chain 1→11) |
| **Current Milestone** | Sprint 10 — Chief Research AI Synthesis **PASS** (2026-09-15, ADR-0017) — Stage 15 + Risk stable |
| **Current Sprint** | Sprint 10 — Chief Research AI — **PASS** (advisory synthesis) |
| **Completed Sprints** | Tasks 0003–0012 (Context Layer, Feature Builder, DAL, schema v2–v8) · Sprint 4 (Replay Foundation, v9, ADR-0011) · Sprint 5 (Research Platform, v10, ADR-0012) · Sprint 6A (Historical Data Platform, v11, ADR-0013) · Sprint 6B (Model Architecture Platform & Statistical Baseline, Models v2, ADR-0014) · Sprint 7 (Training Pipeline, Stages 8–9, ADR-0014) · Sprint 8 (ONNX Runtime & Shadow AI, Stages 10–14, ADR-0015) · Stage 15 (Reconciliation) · Sprint 9 (Chief Risk AI Advisory, ADR-0016) · Sprint 10 (Chief Research AI Synthesis, ADR-0017) |
| **Completed Validation Stages** | Stage 0 (Recovery) · Stage 1 (Compile) · Stage 3 (DB Integrity) · Stage 4 (History Continuity PASS) · Stage 5 (Replay PASS) · Stage 6 (Pipeline PASS) · Stage 7 (Research Platform PASS) · Stage 8 (Supervised Baseline Training PASS) · Stage 9 (Walk-Forward Validation PASS) · Stage 10 (MT5 ONNX Runtime PASS) · Stage 11 (Replay + ONNX PASS) · Stage 12 (AI Safety Gates PASS) · Stage 13 (Shadow AI Context PASS) · Stage 14 (Shadow AI Safety Audit PASS) · **Stage 15 (Final Reconciliation PASS)** · **Chief Risk AI Advisory PASS (ADR-0016)** · **Chief Research AI Synthesis PASS (ADR-0017)** |
| **Current Task** | Chief Research AI synthesis **PASS** — CAIResearchAdvisory (55 .mqh), research_synthesis_report.json + RESEARCH_SYNTHESIS_REPORT.md, test_chief_research_ai PASS (OBSERVE_ONLY) |
| **Next Task** | **Next priority: Decision Bus (Sprint 11)** — requires new ADR; **BLOCKED externally**: MT5/MetaEditor compile still required to verify 55 .mqh 0/0 (Linux sandbox has no MetaEditor) |
| **Overall Progress** | ≈ 96 % (trading core 100 %, data platform 100 %, research 100 %, replay 100 %, baseline ML/training 85 %, AI integration 50 % (shadow→risk advisory), documentation reconciliation 100 %, consistency audit 100 %) |
| **Module Status** | 55 `.mqh` + 1 `.mq5` (EA build unit: +CAIRiskAdvisory + CAIResearchAdvisory) + 7 isolated validation scripts + 2 advisory tests, compile pending MT5 verification (Linux sandbox no MetaEditor); trading modules frozen; trading modules frozen; research/replay/history dormant at init |
| **Database Status** | Research.db, Ticks.db (251M rows), Market.db (2.46M bars; H1=56,529), Models.db schema v2 with 2 registered baseline models and 16 evaluation rows, and test DBs (905001, 906001, 907001) all integrity-checked OK |
| **Last Successful Compile** | 2026-09-15 — MetaEditor, **0 errors / 0 warnings**; `04_Output/EX5/CandleBreakoutEA.ex5` = 207 814 bytes; active MT5 EA EX5 synchronized; Stage 7 script EX5 = 59 392 bytes; Stage 10 script EX5 = 11 090 bytes; Stage 11 script EX5 = 59 680 bytes; Stage 13 script EX5 = 14 134 bytes |

## Module groups

| Group | Location (01_Source/EA/MQL5/Include/CandleBreakoutEA/) | State |
|---|---|---|
| Trading core (frozen) | root modules: Settings, Logger, Risk, Order, Position, BreakEven, Momentum, ExitEngine, ExitStats, TradeManager… | FROZEN — MIPS v1.0 |
| Context Layer | `EAContext/` (5) | operational |
| Feature Builder | `EAFeatureBuilder/` (4) | operational |
| Data Access Layer | `EAData/` (14, schema v11) | operational |
| Advisory Risk AI | `EAContext/` (7) — CAIRiskAdvisory | **PASS** — shadow-only, dormant OFF, no trading authority (ADR-0016) |
| Advisory Research AI | `EAContext/` (7) + Research synthesis | **PASS** — shadow-only, dormant OFF, synthesis hints only (ADR-0017) |
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
