# DECISIONS — Architectural Decision Register

Every architectural change in this project is recorded as a numbered ADR
(`03_Documents/ADR/`). This register is the index; the ADR files carry the full
context, alternatives and consequences.

| ID | Decision | Reason | Date |
|---|---|---|---|
| ADR-0001 | Context Layer (`EAContext/`) — one `STradeContext` snapshot per candle | Give every decision a single, assembled view of trade/market/strategy state instead of scattered lookups | Task 0003 (pre-2026-09-11) |
| ADR-0002 | Feature Builder (`EAFeatureBuilder/`) as the single source of market features | Kill duplicated indicator math; validation lives with the feature | Task 0004 (pre-2026-09-11) |
| ADR-0003 | Data Access Layer — SQLite strictly behind `IDataProvider`/`CSQLiteProvider` | Swappable storage, testable code, no SQL leaking into managers | Tasks 0005–0006 (pre-2026-09-11) |
| ADR-0004 | Schema v2 — MarketSnapshotWriter | Record the market exactly as the EA saw it at decision time | pre-2026-09-11 |
| ADR-0005 | Schema v3 — TradeWriter | Trade metadata becomes research data | pre-2026-09-11 |
| ADR-0006 | Schema v4 — ObservationWriter (market recorder) | Full observation stream for future labels; STOP: no trade tables/positions/Replay/Event Bus/AI yet | pre-2026-09-11 |
| ADR-0007 | Schema v5 — LabelGenerator (ground truth, 3-bar future window) | Supervised learning needs labels written only after the future completes; STOP: no Replay/Event Bus/AI, no change to trading engines | pre-2026-09-11 |
| ADR-0008 | Schema v6 — DatasetBuilder (reproducible ML-ready joins) | One reproducible join of observations + snapshots + labels (+trades) | pre-2026-09-11 |
| ADR-0009 | Schema v7 — DataQualityAnalyzer + mandatory export gate | Garbage in, garbage out: CSV export blocked unless QUALITY_PASS, no override | Task 0011 (pre-2026-09-11) |
| ADR-0010 | Schema v8 — FeatureRegistry + per-dataset manifests | Pin feature/label/quality versions per dataset → experiments become reproducible | Task 0012 (pre-2026-09-11) |
| ADR-0011 | Schema v9 — Replay Foundation (`EAReplay/`), database-only, dormant | Validate strategies against recorded history deterministically, without touching runtime | Sprint 4 (pre-2026-09-11) |
| ADR-0012 | Schema v10 — Research Platform: immutable experiments, one-shot deterministic benchmarks, walk-forward windows | Research results must be sealed, comparable and leak-free | Sprint 5 (pre-2026-09-11) |
| ADR-0013 | Four-database architecture (Ticks.db / Market.db / Models.db + Research.db v11: DataSources, ImportHistory); dedup by UNIQUE + INSERT OR IGNORE; resume by watermark; read-only integrity validator; dormant facade | Raw tick/bar volume must not bloat the versioned research schema; re-exports and crash-resumes must be safe; multi-broker ready | 2026-09-11 (Sprint 6A) |
| DEC-0014 | Project reorganization into `QuantResearchOS/` — source tree moved intact under `01_Source/EA/MQL5`, category folders are indexes, no file duplicated, build tools repointed, compile re-verified | One clean, portable production workspace; zero risk to include paths and trading behaviour | 2026-09-11 |
| DEC-0015 | Walk-Forward boundary definition: contiguous window acceptance | `testing_start < training_end` strictly enforces leakage rejection while permitting contiguous half-open intervals `test_start == train_end` planned by `PlanWindows()` | 2026-09-14 |
| ADR-0014 | Model Architecture Platform (`Models.db` Schema v2, Feature Contracts) | Structured model cataloguing, tensor input contracts, and metric tracking across model lifecycles | 2026-09-14 (Sprint 6B) |
| ADR-0020 | Continuous Learning — drift & retrain advisory (CAIContinuousLearning, drift 0..1 urgent≥0.70, Python+MQL dormant) | Drift monitoring without live retrain; next production promotion | 2026-09-15 (Sprint 13) |
| ADR-0019 | AI Council — multi-agent weighted consensus (CAIAICouncil, Risk0.35/Research0.25/Shadow0.25/Bus0.15, 0.50..1.50, dormant) | Weighted observability without MIPS change; next Continuous Learning | 2026-09-15 (Sprint 12) |
| ADR-0018 | Decision Bus — advisory consensus routing (CAIDecisionBus, Risk×Research×Shadow 0.50..1.50, flags/hints, JSON+MQL dormant) | Consensus observable without MIPS change; next AI Council | 2026-09-15 (Sprint 11) |
| ADR-0017 | Chief Research AI — research synthesis advisory (CAIResearchAdvisory, feature/window/next hints, synthesis JSON, dormant OFF, 0 tokens) | Research triage automated without MIPS change; next Decision Bus | 2026-09-15 (Sprint 10) |
| ADR-0016 | Chief Risk AI — advisory risk layer (CAIRiskAdvisory, SRiskAdvisory, volatility/hourly/confidence/daily/carry, 0.50..1.50, dormant OFF, 0 trading tokens) | Advisory risk insight without corrupting MIPS v1.0; research JSON reproducible; next step Chief Research AI | 2026-09-15 (Sprint 9) |
| ADR-0015 | AI Promotion and Safety Gates — staged AI promotion (research-only → shadow inference → advisory sizing → production candidate) with mandatory gates, checksum/rollback, and no live trading authority without ADR | AI/ONNX validated (Stages 8–11) but must not silently change frozen MIPS v1.0 trading core; shadow-only is first authorized mode | 2026-09-15 (Stages 12–14) |

*Dates:* ADR files record status and authorizing task/sprint; exact calendar dates
were not stamped before 2026-09-11, hence "pre-2026-09-11".
