# MIPS — Module & Interface Specification
**CandleBreakoutEA · Version 1.0 · Status: FROZEN**

This document is the single source of truth for the module decomposition and the public
interfaces of CandleBreakoutEA. Implementation work must follow it; any modification requires
an ADR (see `docs/adr/README.md`).

---

## 1. Frozen strategy (invariant, not modifiable)

| Rule | Value |
|---|---|
| Entry trigger | Previous-candle breakout: Buy Stop at previous high, Sell Stop at previous low |
| Offset / SL / TP | None. No offset, no initial stop loss, no take profit on any order or position |
| Trades per candle | Exactly one (`m_traded_this_candle`), optional same-candle re-entry input (default off) |
| Mandatory exit | Flatten at the main-timeframe (default H1) candle close |
| BreakEven | Optional (default off); when on, may create/trail a stop behind confirmed M5 swings after entry |
| Exit priority | 1 BreakEven → 2 Profit Lock → 3 Momentum Exit → 4 Carry Mode (max 1 extra candle) → 5 mandatory candle close |
| Entry frequency | Final. Nothing in the exit engine, filters or dashboards may open, block or delay entries |

## 2. Module map

Sources live in `MQL5/` (frozen location; `src/` is reserved for future non-MQL tooling).

| Module | Class | Responsibility |
|---|---|---|
| `CandleBreakoutEA.mq5` | — | Entry point: inputs, `OnInit/OnTick/OnDeinit/OnTradeTransaction`, input validation |
| `EASettings.mqh` | `CEASettings` + enums | Shared configuration payload, `ENUM_LOT_MODE`, `ENUM_EXIT_REASON`, `ENUM_TRADE_BLOCK`, `ENUM_LOG_LEVEL`, stringifiers |
| `EAUtils.mqh` | `CEAUtils` | Normalization, broker limits (stops/freeze level, filling mode), time & price helpers |
| `EALogger.mqh` | `CLogger` | Single funnel into the Experts log; standardized line and seven tags |
| `EATradeHistory.mqh` | `CTradeHistory` | Account-history aggregation: daily P/L, consecutive losses, per-position realized profit |
| `EARiskManager.mqh` | `CRiskManager` | Candle gate: trading-hours mask + daily profit/loss limits |
| `EAOrderManager.mqh` | `COrderManager` | Pending order create / find / delete (no SL/TP ever) |
| `EAPositionManager.mqh` | `CPositionManager` | Position inspection and closing for this EA's magic+symbol |
| `EABreakEvenManager.mqh` | `CBreakEvenManager` | Priority #1: M5 confirmed-swing trailing stop (only SL writer) |
| `EAMomentum.mqh` | `CMomentumAnalyzer` | Pure measurement: 0–100 momentum score from last 3 completed break-even bars (cached per bar) |
| `EATradeContext.mqh` | `STradeContext` | Unified read-only snapshot of the live trade (single producer: `CTradeManager::BuildContext`) |
| `EAExitEngine.mqh` | `CExitEngine` | Priorities #2/#3 per tick, carry decision (#4) at candle close, MFE/MAE tracking |
| `EAExitStats.mqh` | `CExitStats` | Per-reason counters + append-only CSV journal |
| `EADashboard.mqh` | `CDashboard` | On-chart HUD; reads only `STradeContext` + stats; redraws only on text change |
| `EAVisualManager.mqh` | `CVisualManager` | Chart objects (levels, entries, exits, BE line); prefix-based cleanup |
| `EATradeManager.mqh` | `CTradeManager` | Candle-cycle state machine; owns all managers and the single `CEASettings` instance |

## 3. Interface contracts

* **Construction** — every manager exposes `Init(const CEASettings&, CLogger&)` (dashboard:
  `Init(const CEASettings&)`) and stores pointers to the single settings instance owned by
  `CTradeManager`. No manager allocates shared state.
* **Settings** — `CEASettings` is a class (MQL5 forbids struct pointers); `Reset()` fills all
  defaults; inputs are copied once in `BuildSettings()`.
* **Trade context** — `STradeContext` fields: ticket, direction, entry time, entry candle,
  entry price, lots, current profit (money), current points, MFE/MAE (points), break-even
  enabled/active, profit-lock active + level, carry active, momentum score, planned exit
  reason. Consumers read only; `Reset()` guarantees safe zeros when flat.
* **Exit reasons** — `ENUM_EXIT_REASON`: `EXIT_H1, EXIT_BREAK_EVEN, EXIT_PROFIT_LOCK,
  EXIT_MOMENTUM, EXIT_CARRY, EXIT_MANUAL, EXIT_ERROR`; exactly one per closed ticket.
* **Logger** — line format `<timestamp> [CBEA <magic> <symbol>] [TAG] message`; tags limited to
  `INFO WARNING ERROR TRADE EXIT BREAK EVEN MOMENTUM`; ticket embedded in the message when
  available; `TRADE/EXIT/BREAK EVEN/MOMENTUM` always printed, severities level-gated.
* **CSV journal** — `MQL5/Files/CBEA_<magic>_<symbol>_exits.csv`, `;`-separated, append-only,
  columns (order frozen, extension only via ADR):
  `Ticket;OpenTime;CloseTime;Side;Lots;Profit;ExitReason;MaximumFloatingProfit;
  MaximumFloatingLoss;ProfitLocked;CarryUsed;MomentumScore;EntryPrice;ExitPrice;
  BreakEvenUsed;MomentumExit`. Missing values are written as `0`.
* **Chart objects** — all names start with `CBEA_<magic>_` (dashboard adds `DASH_`); cleanup in
  `OnDeinit` via the shared prefix.
* **Single exit decision** — `CExitEngine::OnTick` returns at most one close request per
  evaluation (early returns enforce priority); carry and mandatory close live exclusively in the
  candle-close phase of `CTradeManager`; a self-close guard and `m_last_recorded_ticket`
  prevent double closes and double journal rows.

## 4. Dependency rules

* Includes are namespaced: `<CandleBreakoutEA\*.mqh>`; the only external dependency is the
  stock `<Trade\Trade.mqh>`.
* No module reaches into another's internals; cross-module data flows through `CEASettings`,
  `CLogger`, `STradeContext` and explicit return values.
* New behaviour is added by extending one class (single responsibility), never by forking logic.
