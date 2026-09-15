# ARCHITECTURE MAP — QuantResearchOS v1.0 (FROZEN)

## The pipeline

```
        MARKET (MT5 ticks & bars)
           │
           ▼
        CONTEXT ─────────────── EAContext/  (trade/market/strategy/AI snapshot)
           │                     └─ STradeContext, assembled once per candle
           ▼
        FEATURE BUILDER ─────── EAFeatureBuilder/  (single source of features,
           │                     validated; CFeatureSnapshot)
           ▼
        SNAPSHOT ────────────── EAData/MarketSnapshotWriter  (schema v2:
           │                     the market exactly as seen at decision time)
           ▼
        OBSERVATION ─────────── EAData/ObservationWriter  (schema v4:
           │                     full observation stream)
           ▼
        LABELS ──────────────── EAData/LabelGenerator  (schema v5: ground truth,
           │                     written only after the 3-bar future window)
           ▼
        DATASET ─────────────── EAData/DatasetBuilder + FeatureRegistry
           │                     (schema v6/v8: reproducible joins + pinned
           │                      feature/label/quality manifests)
           │                     └─ DataQualityAnalyzer (v7): mandatory gate
           ▼
        REPLAY ──────────────── EAReplay/  (schema v9: deterministic,
           │                     database-only playback, integrity-gated)
           ▼
        EXPERIMENT ──────────── EAResearch/ExperimentEngine  (schema v10:
           │                     immutable, version-pinned, sealed on finish)
           ▼
        BENCHMARK ───────────── EAResearch/BenchmarkEngine  (one-shot,
           │                     deterministic metrics from the pinned dataset)
           ▼
        WALK FORWARD ────────── EAResearch/WalkForwardEngine  (rolling /
           │                     expanding / fixed windows, overlap + leakage
           │                     rejection)
           ▼
        TRAINING ────────────── 05_Training/  (Stage 8: feature vectors,
           │                     supervised baselines, metrics)
           ▼
        ONNX ────────────────── Stage 10/11 validated runtime and replay
           │                     inference through shadow-only contracts)
           ▼
        SHADOW AI ───────────── EAContextAI + CAIShadowInference:
           │                     observation only, no trading authority
           ▼
        EA ──────────────────── trading core (FROZEN, MIPS v1.0):
                                 entry → H1-close exit, optional BreakEven;
                                 AI cannot place, block, modify, or close
                                 trades without a future ADR.
```

## Historical data plane (Sprint 6A, ADR-0013)

```
   MT5 history ──► EAHistory/ ──► Ticks.db   (raw ticks, UNIQUE-dedup, resume)
                     │        ──► Market.db  (M1–D1 bars, 7 TFs, resume)
                     │        ──► Models.db  (schema v2: registry, contracts,
                     │                       evaluations, ONNX metadata)
                     │
                     ├── CDataIntegrityValidator (read-only scans)
                     ├── CMetadataExporter (sessions, UTC offset, DST, contract)
                     └── CHistoryPlatform ──► Research.db v11
                          (DataSources registry + ImportHistory audit trail)
```

## Layering rules

1. **Direction:** data flows down the pipeline only; nothing downstream writes
   back into trading decisions automatically.
2. **Trading core** (EATradeManager, entry/exit/BE/carry/momentum/risk) talks to
   research subsystems only through dormant, explicit APIs.
3. **DAL boundary:** SQLite only behind `IDataProvider`; `CDatabaseManager` owns
   Research.db; dedicated stores (Ticks/Market/Models) use `CSQLiteProvider`
   directly with local Symbols/Timeframes masters.
4. **Managers never reach into each other's internals** — they share `CEASettings`
   (pointer to the single instance owned by CTradeManager) and `CLogger`.
5. **Freeze:** any arrow added/changed here requires an ADR.
