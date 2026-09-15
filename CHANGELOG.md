# CHANGELOG — QuantResearchOS / CandleBreakoutEA

Chronological history of every sprint. Trading core (MIPS v1.0) frozen throughout:
entry = M1 candle breakout; **no SL / no TP**; exit = H1 candle close; BreakEven
optional (default OFF); exit priority BE > ProfitLock > Momentum > Carry > H1.

## Foundation (pre-sprint)

* CandleBreakoutEA v1.00: entry engine, risk sizing (fixed / risk-% / soft
  martingale), pending-order lifecycle, H1-close exit, optional M5-swing
  BreakEven, momentum / carry / profit-lock exit intelligence, dashboard,
  logger (`[CBEA <magic> <symbol>]`), 16-column CSV journal, `CBEA_<magic>_`
  object prefix. Manual in Uzbek (futuristic PDF).

## Tasks 0003–0012 — Intelligence & Data Layers (schema v2–v8)

* **Task 0003 — Context Layer** (ADR-0001): `EAContext/` — trade/market/strategy/AI
  contexts assembled per candle into one `STradeContext` snapshot.
* **Task 0004 — Feature Builder** (ADR-0002): `EAFeatureBuilder/` — single source of
  market features, validation included; exposed but not yet replacing live
  calculations (backward compatibility).
* **Tasks 0005–0006 — Data Access Layer** (ADR-0003): `EAData/` — SQLite behind
  `IDataProvider`/`CSQLiteProvider`; versioned schema + migration chain;
  `CDatabaseManager` bound to Research.db (`candlebreakout_<magic>.db`).
* **Schema v2** (ADR-0004): MarketSnapshotWriter — market observations.
* **Schema v3** (ADR-0005): TradeWriter — trade metadata.
* **Schema v4** (ADR-0006): ObservationWriter — market recorder.
* **Schema v5** (ADR-0007): LabelGenerator — ground-truth labels (3-bar future window).
* **Schema v6** (ADR-0008): DatasetBuilder — reproducible ML-ready datasets.
* **Schema v7** (ADR-0009): DataQualityAnalyzer — mandatory quality gate
  (CSV export blocked unless QUALITY_PASS, no override).
* **Schema v8** (ADR-0010): FeatureRegistry — versioned feature catalogue +
  per-dataset manifests.
* Intermediate reports: context, feature, database, label, dataset, quality,
  registry, trade intelligence, stabilization.

## Sprint 4 — Replay Foundation (schema v9, ADR-0011)

* `EAReplay/`: deterministic, database-only replay of recorded history; integrity
  gating; session lifecycle; dormant until explicitly started.
* Docs: REPLAY_ENGINE / REPLAY_TIMELINE / REPLAY_VALIDATION, SPRINT4_REPORT.

## Sprint 5 — Research Platform (schema v10, ADR-0012)

* `EAResearch/`: immutable experiments with pinned input versions; deterministic
  one-shot benchmarks (9 metrics); walk-forward runs (rolling / expanding / fixed)
  with overlap + leakage rejection.
* Docs: EXPERIMENT_ENGINE / BENCHMARK_ENGINE / WALK_FORWARD_ENGINE, SPRINT5_REPORT.

## Sprint 6A — Historical Data Platform (schema v11, ADR-0013)

* Four-database architecture: **Ticks.db** (raw ticks), **Market.db** (M1–D1 bars),
  **Models.db** (schema-only), **Research.db** extended (v11: `DataSources` +
  `ImportHistory`; multi-broker ready).
* `EAHistory/`: CTickExporter (resume + incremental), CBarExporter (7 TFs, resume +
  incremental), CMetadataExporter (sessions, UTC offset, DST, contract metadata),
  CDataIntegrityValidator (read-only scans), CHistoryPlatform facade.
* Docs: DATA_ACQUISITION_REPORT / DATA_INTEGRITY_REPORT / IMPORT_REPORT.

## Reorganization — QuantResearchOS (2026-09-11)

* Entire sandbox consolidated into one clean `QuantResearchOS/` tree
  (01_Source … 08_Archives + governance docs). No source, algorithm or trading
  behaviour changed. Compile re-verified after the move: **0 errors / 0 warnings**,
  `CandleBreakoutEA.ex5` 205 146 bytes. Build tools repointed
  (`06_Tools/build.py` → `01_Source/EA/MQL5`).
# 2026-09-12 — Architecture recovery baseline

- Repaired the Windows MetaEditor build boundary and added project EX5 publication.
- Verified the staged CandleBreakoutEA with 0 compiler errors and 0 warnings.
- Added architecture, dependency, initialization, database, build, memory, health and validation audit records.

# 2026-09-14 — Stage 4 continuity recovery

- Verified that a repeated `QuantResearchOS_HistoricalExport` run resumed tick export instead of reloading the full archive.
- Confirmed latest tick run imported 58,607 new rows with duplicates 0, invalid 0 and out_of_order 0.
- Fixed a false H1/M15 consistency failure by comparing only the common H1/M15 coverage window.
- Removed legacy minute-based bar rows (`TimeframeID` 60/240/1440) from `CBEA_Market.db` after creating a database backup.
- Added source-level cleanup so legacy timeframe rows do not persist after future runs.
- Rebuilt the EA with 0 errors / 0 warnings and rebuilt the historical export script with 0 errors / 0 warnings.
- Synchronized the corrected history validator and script EX5 to `C:\Program Files\MetaTrader\MQL5`.
- Re-ran the corrected historical export and closed Stage 4 with `STATUS=PASS`, `EXPORT=PASS`, `INTEGRITY=PASS`, and `STATISTICS=PASS`.

# 2026-09-14 — Stage 5 replay validation start

- Started Replay Validation.
- Fixed `CReplayController::InitializeReplay()` so `ReplaySessions.TotalBars` is inserted correctly.
- Added isolated `QuantResearchOS_ReplayValidation` script using validation magic `905001`.
- Rebuilt the EA with 0 errors / 0 warnings and compiled the replay validation script with 0 errors / 0 warnings.
- Ran `QuantResearchOS_ReplayValidation` in MT5 and closed Stage 5 with `[QROS_STAGE5] STATUS=PASS`.

# 2026-09-14 — Stage 6 data pipeline validation start

- Started Feature / Observation / Label / Dataset / Quality validation.
- Added isolated `QuantResearchOS_Stage6Validation` script using validation magic `906001`.
- Compiled the EA with 0 errors / 0 warnings and compiled the Stage 6 validation script with 0 errors / 0 warnings.
- Synchronized the Stage 6 script and project include tree to the active MetaTrader installation.
- Ran `QuantResearchOS_Stage6Validation` in MT5 and closed Stage 6 with `[QROS_STAGE6] STATUS=PASS`.

# 2026-09-14 — Stage 7 research platform validation

- Started Research Platform (ExperimentEngine, BenchmarkEngine, WalkForwardEngine) validation.
- Fixed a boundary overlap defect in `WalkForwardEngine::ValidateRun()` (`testing_start < training_end`, DEC-0015) allowing contiguous half-open intervals from `PlanWindows()`.
- Added isolated `QuantResearchOS_Stage7Validation.mq5` script and `QuantResearchOS_Stage7Validation_EA.mq5` harness with validation magic `907001`.
- Built the EA with 0 errors / 0 warnings (`04_Output/EX5/CandleBreakoutEA.ex5`, 207,196 bytes).
- Compiled Stage 7 harnesses with 0 errors / 0 warnings and synchronized binaries to `C:\Program Files\MetaTrader\MQL5`.
- Added automated test suite `01_Source/Tests/test_stage7_research.py` against isolated `candlebreakout_907001.db`.
- Validated experiment lifecycle, benchmark metrics calculation (7 core + 2 placeholders), walk-forward planning and run creation, and experiment sealing immutability.
- Closed Stage 7 with `[QROS_STAGE7] STATUS=PASS`.
- Reconciled Stage 7 source/document drift by restoring `QuantResearchOS_Stage7Validation.mq5`, recompiling it with 0 errors / 0 warnings, resynchronizing the active MT5 EX5, and re-running the Python DB validation suite with `STATUS=PASS`.

# 2026-09-14 — Sprint 6B model platform and statistical baseline hardening

- Verified `CBEA_Models.db` integrity and confirmed `ModelsSchemaVersion=2` with 4 seeded model architectures.
- Verified `CBEA_Market.db` integrity and current H1 bar coverage: 56,529 stored H1 bars, 56,514 analyzed bars after warmup.
- Hardened `06_Tools/statistical_baseline_research.py` against division-by-zero and empty-sample metric failures.
- Re-ran Phase C statistical baseline on XAUUSD H1 and regenerated `04_Output/Statistics/statistical_baseline_report.json`.
- Synchronized `03_Documents/Reports/STATISTICAL_BASELINE_REPORT.md` with the regenerated JSON results.

# 2026-09-14 — Stage 8 supervised baseline training

- Added `06_Tools/train_phase_d_models.py` for point-in-time XAUUSD H1 feature-vector generation and local scikit-learn supervised baseline training.
- Generated `05_Training/FeatureVectors/feature_vectors_v907100.csv` with 56,499 rows and the official 22-feature contract.
- Trained `QROS_LogisticRegression_Baseline_v1` and `QROS_RandomForest_Baseline_v1` as local `.joblib` research artifacts.
- Installed the required local Python ONNX conversion packages (`onnx`, `skl2onnx`) for the project training runtime.
- Exported both baseline models to ONNX and verified them with `onnx.checker.check_model`.
- Registered both models in `CBEA_Models.db`, including ONNX paths/checksums, 44 feature-vector contract rows and 6 evaluation rows.
- Verified `CBEA_Models.db` integrity and closed Stage 8 with `[QROS_STAGE8] STATUS=PASS | onnx=PASS`.

# 2026-09-14 — Stage 9 walk-forward model validation

- Added `06_Tools/walk_forward_phase_d.py` for chronological multi-window model validation.
- Evaluated both Stage 8 baseline models over 5 walk-forward test windows each.
- Wrote 10 `WF_TEST_*` rows to `CBEA_Models.db.ModelEvaluations`.
- Verified `CBEA_Models.db` integrity and closed Stage 9 with `[QROS_STAGE9] STATUS=PASS`.

# 2026-09-14 — Stage 10 MT5 ONNX contract preparation

- Added isolated MT5 script `QuantResearchOS_OnnxValidation.mq5`.
- Synchronized ONNX model files to `C:\Program Files\MetaTrader\MQL5\Files\CBEA\Models`.
- Compiled `QuantResearchOS_OnnxValidation.ex5` with MetaEditor: 0 errors / 0 warnings.
- Ran `QuantResearchOS_OnnxValidation` in active MetaTrader and closed Stage 10 with `[QROS_STAGE10] STATUS=PASS | onnx_models=2 | input_dim=22 | output_dim=4`.

# 2026-09-14 — Stage 11 replay + ONNX validation preparation

- Added isolated `QuantResearchOS_ReplayOnnxValidation.mq5`.
- The script seeds a deterministic replay database, loads both Stage 8 ONNX baseline models, runs inference at every replay bar, and verifies probability outputs.
- Compiled `QuantResearchOS_ReplayOnnxValidation.ex5` with MetaEditor: 0 errors / 0 warnings.
- Synchronized the script EX5 to the active MetaTrader installation.
- Ran `QuantResearchOS_ReplayOnnxValidation` in active MetaTrader and closed Stage 11 with `[QROS_STAGE11] STATUS=PASS | replay_id=1 | bars=5 | inferences=10 | state=REPLAY_FINISHED`.

# 2026-09-15 — Stage 12 AI promotion safety gates

- Added ADR-0015 defining AI promotion, rollback, and safety gates.
- Verified that `EAContextAI` remains shadow/placeholder-only and does not affect trading.
- Closed Stage 12 with trading invariants preserved: AI cannot place, block, modify, or close trades without a future ADR and validation gate.
- Recompiled the EA after Stage 12 documentation changes with MetaEditor: 0 errors / 0 warnings; synchronized `CandleBreakoutEA.ex5` to the active MetaTrader installation.

# 2026-09-15 — Stage 13 shadow-only AI context preparation

- Extended `CAIContext` with explicit prediction label and probability fields.
- Added `CAIShadowInference`, a shadow-only ONNX adapter that can write predictions to `CAIContext` but cannot affect trading.
- Added isolated `QuantResearchOS_AIShadowValidation.mq5`.
- Recompiled the EA and Stage 13 script with MetaEditor: 0 errors / 0 warnings.
- Synchronized the EA EX5, include tree, and Stage 13 script EX5 to the active MetaTrader installation.
- Ran `QuantResearchOS_AIShadowValidation` in active MetaTrader and closed Stage 13 with `[QROS_STAGE13] STATUS=PASS | shadow_models=2 | context=PASS | trading_effect=NONE`.

# 2026-09-15 — Stage 14 AI shadow safety audit

- Added `01_Source/Tests/test_stage14_ai_shadow_safety.py`.
- Verified the shadow adapter contains no order, position, risk, trade manager, or exit-engine authority.
- Verified `CTradeManager` still has zero AI prediction calls.
- Recompiled the EA with MetaEditor: 0 errors / 0 warnings, and synchronized active MT5 EA EX5.
- Closed Stage 14 with `[QROS_STAGE14] STATUS=PASS | shadow_adapter=OBSERVE_ONLY | trade_manager_ai_calls=0 | forbidden_tokens=0`.

# 2026-09-15 — Stage 15 final architecture/documentation reconciliation

- Updated root audit deliverables, project manifest, inventory, health report, final validation, handoff, architecture map, restore guide, README, and user-action status.
- Removed stale Stage 2 pending, training-not-implemented, and old binary-size references from current-state documents.
- Preserved historical ADR/changelog context while adding supersession notes where necessary.
- Closed Stage 15 with project status synchronized to Stage 14 verified runtime reality.

# 2026-09-15 — Consistency audit: ROADMAP synchronization

- Updated `ROADMAP.md` Completed table to include Sprint 6B (Models.db v2 + statistical baseline), Sprint 7 (training pipeline + ONNX export, Stages 8–9), Sprint 8 (ONNX runtime + replay inference, Stages 10–11), and Stages 12–15 (AI safety + reconciliation) with correct schemas and ADRs 0014/0015.
- Replaced stale Current section (\"Sprint 6B awaits command\") with stable Stage 15 PASS state and 0/0 compile reference (207,814 bytes).
- Rewrote Planned table: Sprint 6B/7/8 moved from future to completed; next planned is Sprint 9 Advisory AI (ADR-controlled) and future farm/calendar/tester campaigns.
- Synchronized `PROJECT_STATUS.md` Current Milestone / Current Sprint / Completed Sprints to reflect Stage 15 stability and 53 .mqh + 1 .mq5 EA build unit.

# 2026-09-15 — Consistency audit: AGENT_GUIDE synchronization

- Updated `AGENT_GUIDE.md` step 5: replaced stale 'Do not start Sprint 6B' with 'Do not start a new sprint' and noted Sprints 6B–8 / Stages 8–15 are complete; next work needs a new ADR.
- Updated 'Which files must be read first' #5: changed latest ADR from ADR-0013 to ADR-0015 (AI promotion and safety gates) with prior chain 0001–0014 still binding.

# 2026-09-15 — Consistency audit: DECISIONS register synchronization

- Added missing ADR-0015 row to `DECISIONS.md` (AI Promotion and Safety Gates, staged promotion, mandatory gates, shadow-only, date 2026-09-15 Stages 12–14).
- Preserved ADR-0014 and DEC-0014/0015 ordering; register now covers ADR-0001..0015 fully.

# 2026-09-15 — Consistency audit: AGENT_HANDOFF synchronization

- Updated `AGENT_HANDOFF.md` §4 Current State: Stage 15 now PASS/stable, Active Task none, Immediate Next Tasks reflect ADR-0015 shadow-only and optional README/PDF refresh.
- Updated §7 Version Pins: Dataset Version now lists 906001/907001 + v907100 training vectors; Current Model(s) now lists 2 baseline models (LogisticRegression/RandomForest) shadow-only, not 'None yet'; added Stage 15 PASS pin.

# 2026-09-15 — Consistency audit: USER_ACTION & BUILD_AUDIT synchronization

- Updated `USER_ACTION_REQUIRED.md`: Reason now Stages 2–15 complete, Expected Result Stage 15 COMPLETE/PASS (was 'in progress').
- Updated `BUILD_AUDIT.md`: expanded validation script list from 4 to 8 entries with sizes/magic numbers and EA binary 53 .mqh detail; added 2026-09-15 date.

# 2026-09-15 — Consistency audit: Manual README synchronization

- Updated `03_Documents/Manuals/CandleBreakoutEA_README.md`: binary size 205,146 → 207,814 bytes (two locations), staged path /home/user/.build → QuantResearchOS/.build, tools/build.py → 06_Tools/build.py, schema v1 → v1–v11 chain, EAContextAI placeholder → prediction fields (shadow-only ADR-0015), added CAIShadowInference.mqh entry, expanded verification output with project output path.

# 2026-09-15 — Consistency audit: Inventory & historical snapshots

- Updated `SPRINT6B_MODEL_BASELINE_VALIDATION.md`: Registry/contract/evaluation rows now show post-Stage 8/9 values (2/44/16) in notes and added supersession note that Stages 8–11 have executed; document retained as historical 6B baseline.
- Updated `PROJECT_INVENTORY.md`: clarified 834 includes `.build/` stdlib copy; repo-only ≈300 files; EA build unit 53 .mqh + 1 .mq5 + 7 scripts.
- Updated `PROJECT_HEALTH_REPORT.md`: Inventory row now notes both counts and EA 53+1 scope.

# 2026-09-15 — Consistency audit: Category indexes synchronization

- Updated `01_Source/EA/README.md`: 52 → 53 class modules (added CAIShadowInference note).
- Updated `01_Source/Database/README.md`: 13 → 14 modules (EAData count correction).
- Updated `01_Source/ML/README.md`: PLANNED → ACTIVE (Stages 8–14), documented 05_Training/ONNX/Metrics and 2 baselines shadow-only.
- Updated `02_Databases/Models/README.md`: walk-forward/ONNX now PASS, blocked until future advisory ADR (ADR-0015).

# 2026-09-15 — Consistency audit: 05_Training READMEs synchronization

- Updated `05_Training/Metrics/README.md`: listed both phase_d supervised (6 evals) and walk_forward (10 evals) =16 rows, matching Models.db.
- Updated `05_Training/Models/README.md`: walk-forward/ONNX/replay now PASS but still shadow-only per ADR-0015 (was 'still required').
- Updated `05_Training/ONNX/README.md`: same PASS note + checksum + shadow-only via CAIShadowInference, blocked until advisory ADR.
- Updated `05_Training/Datasets/README.md`: 56,499 vectors materialized (Stage 8 PASS) and DatasetBuilder canonical path note.

# 2026-09-15 — Consistency audit: Build manual & architecture path sync + PDF regeneration

- Updated `06_Tools/build_manual.py`: binary 205,146 → 207,814 bytes, modules 52 → 53, path tools/build.py → 06_Tools/build.py, file count 10 → 53+9, regenerated Uzbek PDF manual (17 pages, 1,604,976 bytes).
- Updated `03_Documents/Architecture/QRS_v1.0.md` and `QOS_v1.0.md`: tools/build.py → 06_Tools/build.py with historical note per DEC-0014 reorganization.
- Updated `03_Documents/Architecture/RUNTIME_INVENTORY.md`: same path corrections.
- Synchronized shipped PDF `03_Documents/Manuals/CandleBreakoutEA_Qollanma.pdf` to rebuilt artifact.

# 2026-09-15 — Consistency audit: Root audit deliverables Stage 15 sync

- Updated `README.md`: verified baseline Stage 14 → Stage 15 (final reconciliation PASS).
- Updated `ARCHITECTURE_AUDIT.md`: validated through Stage 14 → Stage 15.
- Updated `FINAL_VALIDATION.md`: PASS through Stage 14 → Stage 15, added Stage 12 and Stage 15 to runtime evidence, extended coherent pipeline list.
- Updated `INITIALIZATION_SEQUENCE.md`: evidence through Stage 14 → Stage 15.
- Updated `DATABASE_AUDIT.md`: Stages 3–14 → Stages 3–15.
- Updated `MEMORY_AUDIT.md`: validation runs through Stage 14 → Stage 15.
- Updated `REFACTOR_SUMMARY.md`: Stage 14 reality → Stage 15 final reconciliation.

# 2026-09-15 — Consistency audit: Final report & status summit

- Created `CONSISTENCY_AUDIT_2026-09-15.md` (full 11-commit audit matrix, verification greps, external blockers).
- Updated `PROJECT_STATUS.md`: Data Access Layer 13→14, Current Task → audit PASS, Next Task → BLOCKED (MT5 runtime missing + Sprint 9 needs explicit ADR), Overall Progress adds consistency audit 100%.
- Updated `NEXT_TASK.md`: audit PASS, BLOCKED externally, next authorized work requires MT5 host + ADR-0016.
- Audit complete: all systematic documentation/path/count/schema/stage inconsistencies resolved; 11 prior commits + this summit commit total 12 audit commits on `arena/01a0a3b5-quantresearchos`. AI remains shadow-only; trading core frozen MIPS v1.0.
- External blockers documented: MetaEditor missing in Linux sandbox, runtime DBs not in git clone, next sprint needs user ADR.

# 2026-09-15 — ADR-0016: Chief Risk AI Advisory (Sprint 9)

- Added `03_Documents/ADR/ADR-0016-chief-risk-ai-advisory.md` — Chief Risk AI advisory-only layer (shadow-only, dormant, explicit Update, default OFF). Defines volatility/hourly/confidence/daily/carry advisory tables, risk_multiplier 0.50..1.50, flags NORMAL/REDUCED/CAUTION/ELEVATED, safety invariants (no OrderSend/PositionClose/CRiskManager bypass/exit reorder), mandatory gates (Models.db v2 + ONNX + walk-forward PASS + advisory validation + safety audit), rollback = Reset().

# 2026-09-15 — Chief Risk AI MQL: EAContextRiskAdvisory (ADR-0016)

- Added `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextRiskAdvisory.mqh` — class `CAIRiskAdvisory` with `SRiskAdvisory`/`ENUM_RISK_ADVISORY_FLAG`, dormant disabled default, explicit `Update()`/`UpdateDetailed()` (ATR ratio, hour, CAIContext, daily P/L, trend), volatility (low 1.00/normal 0.85/high 0.50), hourly (top 1.00/worst 0.70), confidence (low<0.35 0.80/fake>0.50 0.50), daily 80% ELEVATED, carry advisory, clamp 0.50..1.50, Validate/Reset/ToString, zero trading tokens, never consumes Order/Position/Risk/Exit.

# 2026-09-15 — Chief Risk AI research: advisory tool & reports

- Added `06_Tools/chief_risk_advisory.py` — loads statistical_baseline_report.json (56,514 H1, WR 54.96% PF 1.95) + walk-forward (logistic 0.3901 RF 0.4183) + supervised, builds volatility/hourly/confidence/daily/carry advisory tables (deterministic 0.50..1.50), writes `04_Output/Risk/risk_advisory_report.json` (6.0K) and `03_Documents/Reports/RISK_ADVISORY_REPORT.md` (3.4K), no lookahead, advisory-only, 0.50..1.50 verified.

# 2026-09-15 — Chief Risk AI validation: safety & advisory tests

- Added `01_Source/Tests/test_chief_risk_ai.py` — validates advisory mqh exists, 0 forbidden tokens (OrderSend/PositionClose/CTrade/CRiskManager/CExitEngine etc), TradeManager 0 calls, multiplier bounds 0.50..1.50 for all regimes, vol 1.00/0.85/0.50, hourly 1.00/0.70, confidence 0.80/0.50, daily 80% ELEVATED, carry CAUTION blocks, risk json schema, no lookahead, tool loads baseline/wf. Evidence: [QROS_CHIEF_RISK] STATUS=PASS.

# 2026-09-15 — Chief Risk AI docs: status/roadmap/handoff

- Updated `PROJECT_STATUS.md`: Milestone Sprint 9 Chief Risk AI PASS (ADR-0016), Sprint 9 PASS, Completed Sprints +Chief Risk AI, Validation Stages +Chief Risk AI PASS, Current Task → Chief Risk AI PASS (54 .mqh), Next Task → Chief Research AI next + BLOCKED MT5 compile, Overall 96% AI 50% advisory, Module Status 54 .mqh + EAContext 6 advisory PASS, DAL 14 + Advisory Risk AI row.
- Updated `ROADMAP.md`: Completed +Sprint 9 Chief Risk AI (ADR-0016), Current → Stage 15 + Chief Risk AI stable (54 .mqh), Planned 9 DONE, added 10 Chief Research AI next.
- Updated `NEXT_TASK.md`: Stage 15+Chief Risk AI COMPLETE PASS, Current Active Task → Chief Risk AI DONE next Chief Research AI, BLOCKED MT5 compile, next authorized work Chief Research AI ADR-0017.
- Updated `DECISIONS.md`: added ADR-0016 register row (Chief Risk AI advisory).
- Updated `AGENT_HANDOFF.md`: added Sprint 9 row, Current Milestone Sprint 9 PASS, Active Task Chief Risk AI DONE, Next blocked MT5, Version Pins +Chief Risk AI PASS.

# 2026-09-15 — ADR-0017: Chief Research AI Synthesis (Sprint 10)

- Added `03_Documents/ADR/ADR-0017-chief-research-ai-synthesis.md` — Chief Research AI synthesis advisory (Sprint 10). Python synthesis of statistical baseline + walk-forward + risk advisory into next-experiment hints (ABLATE_ATR/HOUR, TRY_GRADIENT_BOOST, EXPAND_WINDOW), plus MQL advisory stub CAIResearchAdvisory (dormant OFF, explicit Update, 0 trading tokens), gates (risk PASS + synthesis PASS + 0 tokens), rollback Reset().

# 2026-09-15 — Chief Research AI MQL: CAIResearchAdvisory (ADR-0017)

- Added `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextResearchAdvisory.mqh` — class `CAIResearchAdvisory` with `SResearchAdvisory`/`ENUM_RESEARCH_HINT`, dormant OFF, explicit `Update(SRiskAdvisory,CAIContext,atr_ratio,hour)` heuristic (high vol→ABLATE_ATR, worst hour→ABLATE_HOUR, low conf→EXPAND_WINDOW, CAUTION→TRY_GRADIENT_BOOST), confidence 0..1, Validate/Reset/ToString, 0 trading tokens.

# 2026-09-15 — Chief Research AI research: synthesis tool & reports

- Added `06_Tools/chief_research_advisory.py` — loads baseline (54.96% WR PF1.95) + walk-forward (logistic 0.3901 std0.04 RF 0.4183) + risk advisory, synthesizes feature/window/next/quality hints, writes `04_Output/Research/research_synthesis_report.json` (1.3K) and `03_Documents/Reports/RESEARCH_SYNTHESIS_REPORT.md` (1.9K), no lookahead, advisory only.

# 2026-09-15 — Chief Research AI validation: synthesis & safety tests

- Added `01_Source/Tests/test_chief_research_ai.py` — validates mqh exists, 0 forbidden tokens, TradeManager 0 calls, synthesis JSON schema (feature/window/next hints, confidence 0..1), advisory_only true, hints PASS. Evidence: [QROS_CHIEF_RESEARCH] STATUS=PASS.

# 2026-09-15 — Chief Research AI docs: status/roadmap/handoff

- Updated `PROJECT_STATUS.md`: Milestone Sprint 10 Chief Research AI PASS (ADR-0017), Sprint 10 PASS, Completed Sprints +Chief Research AI, Validation Stages +Chief Research AI PASS, Current Task → Chief Research AI PASS (55 .mqh), Next Task → Decision Bus next + BLOCKED MT5 compile (55 .mqh), Overall AI 60% (shadow+risk+research advisory), Module Status 55 .mqh + Research advisory row.
- Updated `ROADMAP.md`: Completed +Sprint 10 Chief Research AI (ADR-0017), Current → Stage 15 + Risk + Research stable (55 .mqh), Planned 10 DONE, added 11 Decision Bus next.
- Updated `NEXT_TASK.md`: Stage 15+Risk+Research COMPLETE PASS, Current Active Task → Chief Research AI DONE next Decision Bus, BLOCKED MT5 compile, next authorized work Decision Bus ADR-0018.
- Updated `DECISIONS.md`: added ADR-0017 register row.
- Updated `AGENT_HANDOFF.md`: added Sprint 10 row, Current Milestone Sprint 10 PASS, Active Task Chief Research AI DONE, Next blocked MT5, Version Pins +Chief Research AI PASS.

# 2026-09-15 — ADR-0018: Decision Bus advisory consensus (Sprint 11)

- Added `03_Documents/ADR/ADR-0018-decision-bus-advisory.md` — Decision Bus advisory consensus routing (Sprint 11). Fuses Risk (0.50..1.50) + Research (confidence) + Shadow (low conf) into bus_multiplier 0.50..1.50, flags NORMAL/REDUCED/CAUTION/ELEVATED, hints RISK/RESEARCH/SHADOW, Python synthesis + MQL CAIDecisionBus dormant OFF, 0 tokens, rollback Reset().

# 2026-09-15 — Decision Bus MQL: CAIDecisionBus (ADR-0018)

- Added `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextDecisionBus.mqh` — class `CAIDecisionBus` with `SBusAdvisory`/`ENUM_BUS_FLAG`/`ENUM_BUS_HINT`, dormant OFF, explicit `Route(SRiskAdvisory,SResearchAdvisory,CAIContext)` → bus_multiplier = risk*research_shave*shadow_shave clamped 0.50..1.50, flag priority ELEVATED>CAUTION>REDUCED>NORMAL, validates, ToString, 0 tokens.

# 2026-09-15 — Decision Bus research: consensus tool & reports

- Added `06_Tools/decision_bus_advisory.py` — loads risk_advisory_report.json + research_synthesis_report.json + baseline + walk_forward, computes bus_multiplier per regime (low 0.90 NORMAL, normal/worst 0.54 REDUCED, high 0.50 CAUTION), flag/hint enums, writes `04_Output/DecisionBus/decision_bus_report.json` (1.2K) and `03_Documents/Reports/DECISION_BUS_REPORT.md` (1.6K), advisory only.

# 2026-09-15 — Decision Bus validation: consensus & safety tests

- Added `01_Source/Tests/test_decision_bus_advisory.py` — validates mqh exists, 0 forbidden tokens, TradeManager 0 calls, bus JSON schema (multiplier 0.50..1.50, flags NORMAL/REDUCED/CAUTION), advisory_only true. Evidence: [QROS_DECISION_BUS] STATUS=PASS.
