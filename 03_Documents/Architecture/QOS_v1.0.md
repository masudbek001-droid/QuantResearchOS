# QOS — Quality of Service & Operational Specification
**CandleBreakoutEA · Version 1.0 · Status: FROZEN**

Source of truth for runtime service objectives, operations and change management.
Changes require an ADR.

## O-1 Runtime service objectives
* **Audit completeness** — every order placed/deleted, every fill, every close (own, broker or
  terminal initiated) produces exactly one standardized log line and, for closes, exactly one
  CSV row.
* **Journal integrity** — the CSV file is opened once at init, appended with flush per record,
  header written only when the file is created; the file is never truncated or restructured by
  the EA.
* **UI non-interference** — chart objects and the dashboard are non-selectable, hidden from the
  object list and removed on deinit; the EA never removes foreign objects.
* **Tick budget** — per-tick work is bounded: one position scan, cached momentum, cached point,
  text-only dashboard diff; no history scan on the tick path (history reads occur at candle
  boundaries and on close classification only).

## O-2 Operational constraints
* Time-based logic (hours mask, daily limits, candle boundaries) uses the **server clock**.
* Multiple instances require distinct magic numbers; one instance manages one symbol.
* Removing the EA deletes its objects but intentionally leaves open positions/orders in place.

## O-3 Deployment & packaging
* Deliverable layout is frozen: `MQL5/Experts/CandleBreakoutEA/*.mq5`,
  `MQL5/Include/CandleBreakoutEA/*.mqh`; the consistent package
  (`CandleBreakoutEA_package.zip`) contains all sources plus the compiled `.ex5` and `README.md`
  and must be refreshed after every change.
* Installation: copy the two folders into the MT5 data folder; the only external dependency is
  the stock `<Trade\Trade.mqh>`.
* A compiled `.ex5` copy and the Uzbek PDF manual ship alongside the sources; both must match
  the frozen architecture version.

## O-4 Verification before release
1. `tools/build.py` → `VERDICT: PASS - 0 errors, 0 warnings, binary produced`.
2. Grep-level consistency checks (no stale tags, no duplicated helpers) where applicable.
3. Strategy Tester / demo run before any live deployment (compile validation does not cover
   broker behaviour: fills, expirations, stops level, hedging/netting).

## O-5 Versioning & change management
* Architecture version is tracked in `ARCHITECTURE_VERSION.md` (currently **1.0 / FROZEN**).
* Any change to MIPS/QRS/QOS or to the module map, contracts, invariants or folder roles must
  be introduced by an ADR in `docs/adr/` and referenced from `docs/backlog/` tasks.
* Implementation tasks are decomposed into `docs/backlog/`; each task cites the architecture
  requirement(s) it implements (QRS identifiers where available).
* Reserved folders (`src/`, `tests/`, `database/`, `research/`, `models/`, `replay/`, `logs/`,
  `scripts/`) hold future non-MQL engineering assets only; MQL5 sources remain in `MQL5/` until
  an ADR states otherwise.
