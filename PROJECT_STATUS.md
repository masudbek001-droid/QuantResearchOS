# PROJECT STATUS — Dashboard

| Field | Value |
|---|---|
| **Project Version** | QuantResearchOS 1.0 (CandleBreakoutEA v1.00) |
| **Architecture Version** | v1.0 — FROZEN (changes only via ADR) |
| **Database Schema Version** | v11 (Research.db; additive chain 1→11) |
| **Current Milestone** | Market Digital Twin — Single Source of Truth **PASS** (2026-09-15, ADR-0022) — Stage 15 + 5 advisory + AgentOS + Twin |
| **Current Sprint** | Market Digital Twin — **PASS** (TASK-0005 via AgentOS) |
| **Completed Sprints** | Tasks 0003–0012 (Context Layer, Feature Builder, DAL, schema v2–v8) · Sprint 4 (Replay Foundation, v9, ADR-0011) · Sprint 5 (Research Platform, v10, ADR-0012) · Sprint 6A (Historical Data Platform, v11, ADR-0013) · Sprint 6B (Model Architecture Platform & Statistical Baseline, Models v2, ADR-0014) · Sprint 7 (Training Pipeline, Stages 8–9, ADR-0014) · Sprint 8 (ONNX Runtime & Shadow AI, Stages 10–14, ADR-0015) · Stage 15 (Reconciliation) · Sprint 9 (Chief Risk AI Advisory, ADR-0016) · Sprint 10 (Chief Research AI Synthesis, ADR-0017) · Sprint 11 (Decision Bus Advisory, ADR-0018) · Sprint 12 (AI Council Advisory, ADR-0019) · Sprint 13 (Continuous Learning Advisory, ADR-0020) · AgentOS v1.0 (ADR-0021) · Market Digital Twin (ADR-0022, TASK-0005 via AgentOS) |
| **Completed Validation Stages** | Stage 0 (Recovery) · Stage 1 (Compile) · Stage 3 (DB Integrity) · Stage 4 (History Continuity PASS) · Stage 5 (Replay PASS) · Stage 6 (Pipeline PASS) · Stage 7 (Research Platform PASS) · Stage 8 (Supervised Baseline Training PASS) · Stage 9 (Walk-Forward Validation PASS) · Stage 10 (MT5 ONNX Runtime PASS) · Stage 11 (Replay + ONNX PASS) · Stage 12 (AI Safety Gates PASS) · Stage 13 (Shadow AI Context PASS) · Stage 14 (Shadow AI Safety Audit PASS) · **Stage 15 (Final Reconciliation PASS)** · **Chief Risk AI Advisory PASS (ADR-0016)** · **Chief Research AI Synthesis PASS (ADR-0017)** · **Decision Bus Advisory PASS (ADR-0018)** · **AI Council Advisory PASS (ADR-0019)** · **Continuous Learning Advisory PASS (ADR-0020)** · **AgentOS v1.0 PASS (ADR-0021)** · **Market Digital Twin PASS (ADR-0022, 100 bars exact, 5 consumers identical)** |
| **Current Task** | Market Digital Twin **PASS** — EAMarketDigitalTwin (5 MQL: TwinTypes/Clock/Bus/Validator/Core + Adapters), 100 bars FNV-1a 0 mismatches, 5 consumers identical (Replay/Training/Risk/Research/AI), single source via TwinEventBus |
| **Next Task** | Twin integration follow-ups (Replay/Training/Risk/Research/AI adapters consume Twin by default) until MT5 compile blocker; **BLOCKED externally**: MT5 compile (64 .mqh 0/0) + GitHub branch protection (403) |
| **Overall Progress** | ≈ 96 % (trading core 100 %, data platform 100 %, research 100 %, replay 100 %, baseline ML/training 85 %, AI integration 50 % (shadow→risk advisory), documentation reconciliation 100 %, consistency audit 100 %) |
| **Module Status** | 64 `.mqh` (58 + 6 Twin) + 1 `.mq5` + 7 scripts + 5 advisory tests + AgentOS v1.0 (11 workers) + Twin (TASK-0005 DONE, 100 bars exact, 5 consumers), compile pending MT5 (Linux sandbox); trading/Advisory frozen; Twin is single market source |
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
| Advisory Decision Bus | `EAContext/` (8) — CAIDecisionBus consensus | **PASS** — shadow-only, dormant OFF, consensus routing only (ADR-0018) |
| Advisory AI Council | `EAContext/` (9) — CAIAICouncil weighted | **PASS** — shadow-only, dormant OFF, multi-agent consensus (ADR-0019) |
| Advisory Continuous Learning | `EAContext/` (10) — CAIContinuousLearning drift | **PASS** — shadow-only, dormant OFF, retrain advisory only (ADR-0020) |
| AgentOS Collaboration | `AgentOS/` (8 files + CLI/validate) | **PASS** — Git-native, single-owner, Git-only bus, no Telegram (ADR-0021) |
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
