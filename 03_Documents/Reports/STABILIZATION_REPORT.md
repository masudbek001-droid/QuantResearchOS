# STABILIZATION REPORT — CandleBreakoutEA

Sprint scope: code quality, architecture stability, consistency, reliability.
**No trading idea, entry logic, exit logic, parameter behaviour or architecture was changed.**
Final validation: `tools/build.py` → `VERDICT: PASS - 0 errors, 0 warnings` (109 590-byte binary).

---

## 1. Files Modified (reason per file)

| File | Reason |
|---|---|
| `EASettings.mqh` | Task 3: strongly typed exit enum now exactly `EXIT_H1 / EXIT_BREAK_EVEN / EXIT_PROFIT_LOCK / EXIT_MOMENTUM / EXIT_CARRY / EXIT_MANUAL / EXIT_ERROR`; `ExitReasonToString` defaults to `"Error"` instead of a free-text `"Unknown"`. |
| `EALogger.mqh` | Task 4: standardized line `<timestamp> [CBEA <magic> <symbol>] [TAG] message`; only the seven tags `INFO WARNING ERROR TRADE EXIT BREAK EVEN MOMENTUM`; `Event`/`SetLevel` removed; `Debug` kept but emitted with the `INFO` tag at top verbosity so behaviour (gating) is unchanged. |
| `EATradeContext.mqh` **(new)** | Task 2: `STradeContext` — the single read-only snapshot (ticket, direction, entry time/candle/price, lots, current profit & points, MFE/MAE, break-even/profit-lock/carry flags + lock level, momentum score, planned exit reason). `Reset()` zeroes everything so consumers never read garbage. |
| `EAMomentum.mqh` | Task 8: the 0–100 score depends only on **completed** bars, so it is computed once per break-even bar and served from a `(bar_time, side)` cache on every tick instead of re-reading 12 series values per tick. |
| `EAExitEngine.mqh` | Task 1/3/8: enum rename; symbol point cached at `Init` (no per-tick `SymbolInfoDouble`); live floating value stored (`LastFloating`) so the manager no longer recomputes it; unused `IsActive` removed; single-decision structure verified — priority #2 (Profit Lock) returns before #3 (Momentum) is evaluated, so at most one exit request per tick; #1 (BreakEven) always runs first in the caller; #4/#5 (carry / H1) are evaluated only at candle close, a separate phase. |
| `EABreakEvenManager.mqh` | Task 4/9: `BreakEven Updated` now logged with `[BREAK EVEN]`; dead `BarsSinceOpen` removed; new `HadStop()` exposes "a stop was actually placed" for the CSV `BreakEvenUsed` column (Task 7). |
| `EAExitStats.mqh` | Task 3/7: counters sized for 7 reasons; CSV extended (append-only) with `EntryPrice;ExitPrice;BreakEvenUsed;MomentumExit`; MFE/MAE columns documented; missing values are written as `0`, never as gaps; summary line gains `ER:`. |
| `EADashboard.mqh` | Task 5: panel now reads **only** `STradeContext` + stats; shows Strategy State, BreakEven status, Profit-Lock status + level, Carry, Momentum, Floating, Planned Exit, one-line trade summary (`#ticket side lots @ entry | MFE | MAE`) and the counters. Duplicated floating/lock computations removed; redraw still only on text change. |
| `EATradeManager.mqh` | Tasks 1/2/8: new `BuildContext()` is the single producer of `STradeContext`; `UpdateDashboard()` consumes it (strategy state `IDLE/ARMED/IN TRADE/CARRY`); removed the duplicated `CurrentFloatingPoints()`; one position scan per tick in `OnTick` and `PollPendingOrders` (was 2–3); entry candle remembered for the context; all log calls re-tagged (`Trade/Exit/Info`); logger init signature updated. |
| `EAOrderManager.mqh` | Task 4: pending create/delete logged with `[TRADE]`; dead `HasOrder` removed (Task 9). |
| `EAPositionManager.mqh` | Task 4: `Trade Closed` logged with `[EXIT]`. |
| `EARiskManager.mqh` | Task 4: filter/daily-limit blocks logged with `[WARNING]` (previously an always-on event). |
| `EATradeHistory.mqh` | Task 9: dead `LossesSince` removed; `DealProfitOfPosition` kept (safe `0.0` on missing history). |
| `EAUtils.mqh` | Task 9: dead `BarTime` helper (declaration + definition) removed. |
| `CandleBreakoutEA.mq5` | Tasks 4/6: logger init carries magic+symbol; inputs regrouped to **Trading / Risk / Break Even / Exit Engine / Dashboard / Logging / Advanced / Future AI** (same inputs, same defaults, same behaviour; daily limits moved to Risk, hours to Advanced, visuals+panel to Dashboard); inert `Reserved for future AI modules` placeholder added so the required group exists without behaviour. |
| `README.md`, `tools/build_manual.py` (+PDF) | Documentation synced with every visible change: new log format/tag table, CSV columns, dashboard description, TradeContext paragraph, module tree (15 headers), input groups, binary size, module/line counts. |

## 2. Architecture improvements

* **One read model for trade state.** `STradeContext` is produced once per tick by the trade
  manager and consumed by dashboard and journal; no module reaches into another manager's
  internals, and duplicated floating-profit math was deleted.
* **Single exit-decision funnel.** Priority 1→5 is enforced by phase separation (BreakEven on
  tick, then engine's lock→momentum with early return, then candle-close carry/H1) — two exit
  requests can never be issued in the same evaluation; a self-close guard plus
  `m_last_recorded_ticket` make double closes and double CSV rows impossible.
* **Typed exit reasons everywhere**, including a safe `EXIT_ERROR` fallback; free-text reasons
  no longer exist.
* **Logger contract**: seven tags, every line carries timestamp + symbol + magic, ticket inside
  the message when one exists.

## 3. Performance improvements

* Momentum score: 1 computation per M5 bar instead of per tick (≈12 series reads saved/tick).
* Symbol point cached in the exit engine; no per-tick `SymbolInfoDouble`.
* Position list scanned once per tick (was up to three times).
* Floating profit computed once (engine) and reused by the context/dashboard.
* Dashboard still redraws only when its composed text changes.

## 4. Remaining issues

* Runtime broker behaviour (fills, expirations, stops level, hedging/netting) remains untested —
  compile validation only; Strategy Tester / demo run still required before live use.
* `Debug` diagnostics share the `INFO` tag (the tag vocabulary is fixed by design); verbosity
  still separates them.
* The `Future AI` group contains only the inert reserved switch, as required by the sprint.

## 5. Future recommendations

1. Exercise the EA in the Strategy Tester and assert the CSV journal (every row has all 16
   columns, exactly one exit reason per ticket).
2. Add a per-reason win-rate/expectancy summary computed from the CSV journal (statistics only,
   no logic change).
3. When a future AI module arrives, replace the reserved input with a real feature flag and feed
   it through `STradeContext` — the read model is already in place.
4. Consider persisting `STradeContext` on deinit so an EA restart resumes the dashboard without a
   warm-up tick.

---
*Validated: 0 compile errors, 0 warnings; no duplicated logic/variables; no dead code; no missing
TradeContext fields; dashboard values sourced exclusively from the context; log vocabulary limited
to the seven standardized tags.*
