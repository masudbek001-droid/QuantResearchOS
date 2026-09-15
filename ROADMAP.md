# ROADMAP — QuantResearchOS

## ✅ Completed

| Sprint | Scope | Schema | ADR |
|---|---|---|---|
| Foundation | CandleBreakoutEA v1.00 — frozen trading core (MIPS v1.0) | — | — |
| Tasks 0003–0012 | Context Layer, Feature Builder, DAL, observation → labels → datasets → quality → feature registry | v2–v8 | 0001–0010 |
| Sprint 4 | Replay Foundation — deterministic database-only replay | v9 | 0011 |
| Sprint 5 | Research Platform — experiments, benchmarks, walk-forward | v10 | 0012 |
| Sprint 6A | Historical Data Platform — Ticks/Market/Models stores, exporters, integrity, incremental sync, import history | v11 | 0013 |
| Reorganization | QuantResearchOS clean workspace (this state) | — | — |
| Sprint 6B | Model Architecture Platform — Models.db schema v2, 4 architectures seeded, statistical baseline (Phase C) regenerated | Models v2 | 0014 |
| Sprint 7 | Training pipeline — 56,499 feature vectors, 2 supervised baselines (LogisticRegression, RandomForest), ONNX export with checker PASS, Models.db registry/contracts/evaluations | Models v2 | 0014 |
| Sprint 8 | ONNX runtime — MT5 ONNX load PASS (22→4), replay+ONNX inference PASS (10 inferences), shadow AI context PASS | — | 0014 / 0015 |
| Stages 12–15 | AI promotion safety gates, shadow-only inference, shadow safety audit, final architecture/documentation reconciliation — PASS | — | 0015 |
| Sprint 9 | **Chief Risk AI** — advisory risk layer (CAIRiskAdvisory), volatility/hourly/confidence/daily/carry tables, risk_advisory_report.json, safety test PASS | — | 0016 |

## ▶ Current

* **Stable through Stage 15 + Chief Risk AI (2026-09-15) — PASS.** Historical data, replay, research, training, ONNX runtime, shadow-AI and **advisory Risk AI (ADR-0016)** are validated. EA now 54 .mqh (was 53) + 7 scripts + 1 risk test; advisory only, default OFF. Next work is Chief Research AI (requires new ADR).

## 📋 Planned

| Sprint | Scope (subject to the user's specification) |
|---|---|
| **9** | **Chief Risk AI** — **DONE** (this sprint, ADR-0016) — advisory risk layer PASS |
| **10 (next)** | Chief Research AI — research advisory, experiment/benchmark synthesis, WalkForward meta-analysis (requires ADR) |
| Future | Multi-broker backtesting farm (DataSources registry is multi-broker ready); live walk-forward re-validation calendar; Strategy Tester / demo campaign before any live deployment |

## 🔭 Future

* Multi-broker backtesting farm (DataSources registry is multi-broker ready).
* Live walk-forward re-validation calendar.
* Strategy Tester / demo validation campaign before any live deployment.

## Rules of the road

* Every sprint ends with: compile 0/0 · documentation · ADR (if architecture or
  schema touched) · refreshed package · STOP at its stop condition.
* Research and data subsystems stay dormant at init — runtime trading never
  depends on them.
