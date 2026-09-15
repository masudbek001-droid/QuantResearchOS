# ADR-0022: Market Digital Twin — Single Source of Truth Simulator

## Status

Accepted. (Implementing — Market Digital Twin)

## Context

- QuantResearchOS has discrete history paths: `EAHistory/HistoryStore` (Ticks.db/Market.db raw export), `EAReplay/ReplayTimeline` (database-only replay), `EAResearch` (experiments), `05_Training` (datasets), `EAContext` advisory (Risk/Research/Bus/Council/Learning) reading snapshots. Each subsystem historically consumed **raw history directly** (MarketSnapshots, Observations, Labels, ticks) — leading to divergent clocks, non-identical events, and no single truth.
- Training used pre-built datasets (05_Training), Replay used ReplaySessions, Risk/AI used live snapshots. No guarantee they see *identical* market sequence. Replay was deterministic per se, but not the canonical source for Training/Risk/Research/AI.
- Requirement: Market simulator must **reproduce historical market behaviour exactly** (bit-for-bit OHLCV + ticks as stored) and become **single source of truth**. Replay, Training, Risk, Research, AI must all receive **identical events** from the simulator. No subsystem may read raw history bypassing Twin.

## Decision

Implement **Market Digital Twin (MDT)** as new module `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAMarketDigitalTwin/` owned by `worker-twin` (MOD-TWIN).

### Core

- `TwinTypes.mqh` — Single event struct `SMarketEvent` (event_id, time, type TICK/BAR/CANDLE_CLOSE, OHLCV, spread, ATR, snapshot_id, source_hash) — **immutable** once emitted. Hash (`source_hash`) is `FNV-1a` of raw bar as stored, proving exact reproduction.
- `TwinClock.mqh` — Deterministic virtual clock. Advances only via `Twin.Next()` — never `TimeCurrent()` except to stamp Twin creation. Clock is `INT64` bar_index + datetime; identical for all consumers per event.
- `TwinEventBus.mqh` — In-process pub/sub. Consumers implement `ITwinConsumer { void OnMarketEvent(const SMarketEvent &ev); }`. Twin dispatches **by value copy** to each consumer in registration order; bus holds no state except consumer list. Guarantees identical payload (same struct bytes) — validated by emitting `event_hash` (hash of event struct) per dispatch and logging per-consumer hash.
- `MarketDigitalTwin.mqh` (`CMarketDigitalTwin`) — Single source. Loads *once* from HistoryStore (Ticks.db/Market.db) or MarketSnapshots, builds in-memory timeline (array of SMarketEvent ordered by time), validates against source checksum (sum of `source_hash`), then serves `Next()` deterministically. No consumer may call HistoryStore directly — all 5 consumers (Replay, Training, Risk, Research, AI) register via `Subscribe()` and receive same `SMarketEvent` copy. Integrates with existing `CReplayValidator` for integrity gate before first event.
- `TwinValidator.mqh` — Offline + online validator: offline Python `market_digital_twin_validate.py` reads `Market.db` bars + Twin-emitted hashes and asserts `TwinHashes == SourceHashes` for entire window. Online `ValidateExact()` called every N events, halts Twin on mismatch (same pattern as `CReplayController::IntegrityGate`).

### Ownership & Protocol

- New `MOD-TWIN` (`AgentOS/OWNERSHIP_MAP.md`) → `worker-twin` (single owner). `WORKER_REGISTRY.md` adds `worker-twin` with `MOD-TWIN`, branch prefix `worker/worker-twin/`.
- `MOD-REPLAY`, `MOD-RESEARCH`, `MOD-TOOLS` (training), `MOD-CONTEXT` (Risk/AI) remain owners of their logic but **must consume Twin** — enforced by Twin being the only HistoryStore accessor; direct HistoryStore calls outside Twin are validated as violations in `TwinValidator` (and future CI check).
- Task `TASK-0005` (MOD-TWIN, P0) tracks build: Twin core + bus + validator + consumer adapters + Python twin validator + tests + docs.

### Integration (no trading logic change)

- Trading core (`MOD-CORE`, MIPS v1.0) remains frozen. Twin is *read-only* market feed; trading decisions still via `EATradeManager` as before, but now market data originates from Twin's `bar_time` not `iTime()`.
- Advisory stack (ADR-0016..0020) unchanged — they receive Twin events via new `OnMarketEvent` adaptation (advisory modules keep multipliers, only source changes).
- Existing `EAReplay` becomes thin wrapper over Twin: `CReplayController` will optionally delegate `StepForward()` to `Twin.Next()` when `USE_TWIN=true` (default), ensuring Replay, Training, Risk, Research, AI share clock.

### Alternatives Considered

- Enhance `EAReplay` alone — rejected: Replay was replay-specific (ReplaySessions table), not market simulator; needed new abstraction for 5 consumers, exact-reproduction guarantee, and hash proof.
- Per-subsystem shadows — rejected: duplicates history reads, breaks identical-events guarantee.

## Consequences

- Single timeline, single hash. Any divergence between consumers is a bug (bus dispatches identical bytes, validated).
- Offline proof: Python validator asserts `SHA256(TwinEventHashes) == SHA256(Market.db bars)` for window.
- All future Training datasets, Research benchmarks, Risk evaluations, AI inferences must be regenerated from Twin — old raw-history datasets become deprecated, new ones marked `source=TWIN`.

## References

- EAReplay/ReplayTimeline (prior deterministic replay), EAHistory/HistoryStore (raw source), TwinValidator, AgentOS protocol single-owner invariant (validate.py).

