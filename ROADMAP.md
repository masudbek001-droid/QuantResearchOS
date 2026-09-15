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

## ▶ Current

* **Nothing running.** Sprint 6B awaits an explicit user command. The platform is
  in a stable, fully compiled, fully documented state.

## 📋 Planned

| Sprint | Scope (subject to the user's specification) |
|---|---|
| **6B** | Model Architecture Platform — model metadata in Models.db, feature-vector contracts, readiness for training |
| **7** | Training pipeline — dataset export to `05_Training/`, feature vectors, model training, metrics |
| **8** | ONNX runtime — model inference inside the EA, AI-gated decisions (context AI slot already reserved) |

## 🔭 Future

* Multi-broker backtesting farm (DataSources registry is multi-broker ready).
* Live walk-forward re-validation calendar.
* Strategy Tester / demo validation campaign before any live deployment.

## Rules of the road

* Every sprint ends with: compile 0/0 · documentation · ADR (if architecture or
  schema touched) · refreshed package · STOP at its stop condition.
* Research and data subsystems stay dormant at init — runtime trading never
  depends on them.
