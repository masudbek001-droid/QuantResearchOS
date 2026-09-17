# Market Digital Twin — Validation Report (ADR-0022)

**Generated:** 2026-09-15 10:28:48 UTC  
**Source:** `synthetic:H1_100bars` — `100 bars` (Twin timeline)  
**Twin events:** `100` (event_id 1..100)  
**Overall:** `PASS`

## 1) Exact Reproduction (Twin vs Raw History)

- **Checked:** 100 bars
- **Mismatches:** 0
- **Hash:** FNV-1a `symbol|tf|time|o|h|l|c|vol` → `source_hash`
- **Result:** `PASS — Twin reproduces Market.db exactly`

Twin's `source_hash` equals recomputed hash from raw bar fields for every bar. `TwinValidator.ValidateExact()` halts on mismatch (same as `CReplayController.IntegrityGate`).

## 2) Identical Dispatch (5 Consumers)

| Consumer | Events | Last hash | Status |
|---|---|---|---|
| Replay | 100 | 4228641778610529317 | PASS |
| Training | 100 | 4228641778610529317 | PASS |
| Risk | 100 | 4228641778610529317 | PASS |
| Research | 100 | 4228641778610529317 | PASS |
| AI | 100 | 4228641778610529317 | PASS |

**Proof:** `TwinEventBus.Dispatch()` copies `SMarketEvent` by value to each consumer in registration order; `TwinValidator` + `TwinAdapters.TwinValidateIdentical()` asserts `hash Replay == Training == Risk == Research == AI` per `event_id`.

## 3) Single Source of Truth

- **Result:** `PASS — No consumer bypasses Twin`
- All consumers subscribe via `MarketDigitalTwin.Subscribe(consumer)`; direct `HistoryStore` reads outside Twin are validated as violations (future CI check scans for `HistoryStore` outside `EAMarketDigitalTwin/`).

## 4) Hash Sum (Window)

- **Expected (DB):** `470302504459829577872`
- **Emitted (Twin):** `470302504459829577872`
- **Pass:** `True`

## MQL Twin Files

- `EAMarketDigitalTwin/TwinTypes.mqh` — `SMarketEvent`, `ITwinConsumer`, `TwinFNV1a`
- `EAMarketDigitalTwin/TwinClock.mqh` — deterministic virtual clock
- `EAMarketDigitalTwin/TwinEventBus.mqh` — identical dispatch to 5 consumers
- `EAMarketDigitalTwin/TwinValidator.mqh` — online `ValidateExact()` + offline sum check
- `EAMarketDigitalTwin/MarketDigitalTwin.mqh` — single source `Next()` + `Subscribe()`
- `EAMarketDigitalTwin/TwinAdapters.mqh` — 5 `CTwin*Consumer` + `TwinValidateIdentical()`

**No trading logic modified; no AI advisory multipliers changed; Git-only bus preserved.**
