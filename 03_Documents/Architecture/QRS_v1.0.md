# QRS — Quality Requirements Specification
**CandleBreakoutEA · Version 1.0 · Status: FROZEN**

Source of truth for the quality bar every implementation task must satisfy. Changes require
an ADR.

## Q-1 Compilation
* The MetaQuotes compiler (MetaEditor64) reports **0 errors and 0 warnings** on every build.
* Validation is performed by `tools/build.py`, which stages the sources into a genuine MT5 data
  folder (stock library intact) and fails unless the `.ex5` binary is produced.

## Q-2 Trading correctness invariants
* **QR-2.1** One trade per candle; no duplicate positions and no duplicate pending orders in any
  phase (arming, carry, re-entry, restart/adoption).
* **QR-2.2** Entry logic is final: breakout levels, order types, lot sizing and filters may not
  be altered to reduce or increase entry frequency; the exit engine never opens or blocks trades.
* **QR-2.3** No initial SL/TP on any order or position; the only SL writer is the optional
  BreakEven manager; the mandatory exit is the candle close.
* **QR-2.4** Exit priority is strictly `BreakEven → Profit Lock → Momentum → Carry → H1 close`;
  at most one exit decision per evaluation; every closed ticket is booked under exactly one
  `ENUM_EXIT_REASON` (fallback `EXIT_ERROR` when classification is impossible).
* **QR-2.5** Carry Mode allows at most one extra candle; any other `Maximum Carry Candles`
  value is rejected at `OnInit`.

## Q-3 Reliability
* **QR-3.1** Attach safety: the running candle is a baseline only; a pre-existing same-magic
  position is adopted and managed; consecutive-loss streaks and daily P/L survive restarts via
  account history.
* **QR-3.2** Broker-initiated closes (break-even stop, terminal) are classified and journaled;
  close failures are logged `[ERROR]` and retried only by the next legitimate cycle event.
* **QR-3.3** All prices/volumes are normalized to tick size, digits, lot step and min/max;
  stops-level and freeze-level violations skip the order with a `[WARNING]` instead of failing.
* **QR-3.4** Missing/unknown values in the CSV journal are written as `0`, never as gaps.

## Q-4 Performance
* Momentum score is computed once per completed break-even bar and cached per `(bar, side)`.
* The position list is scanned at most once per tick; the symbol point is cached per position.
* Floating profit is computed once per evaluation and reused through `STradeContext`.
* The dashboard recomposes every tick but redraws chart objects only when the text changed.

## Q-5 Maintainability
* Single-responsibility classes; small functions; descriptive English names; comments only on
  important logic; no duplicated logic, variables or helpers; no dead code; no magic numbers
  (named constants or inputs).
* Modifications follow the patch discipline: read the whole file, change the minimum number of
  lines, never rename public classes/methods, never rewrite whole files without necessity.
* Documentation describing changed behaviour (root `README.md`, Uzbek PDF manual) must be
  synchronized in the same change.

## Q-6 Observability
* Log vocabulary is exactly seven tags; every line carries timestamp, symbol, magic and the
  ticket when one exists (MIPS §3 Logger).
* The CSV journal contains every closed ticket with MFE/MAE, lock, carry and momentum data.
* The dashboard shows strategy state, exit-engine state, trade summary and per-reason counters,
  sourced exclusively from `STradeContext`.

## Q-7 Safety
* Risk gate (hours mask + daily limits) is evaluated before arming every candle and logs its own
  block reason.
* The `Future AI` input group contains only an inert reserved switch; no autonomous behaviour
  exists.
