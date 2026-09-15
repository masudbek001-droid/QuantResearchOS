# CONTEXT LAYER — `MQL5/Include/CandleBreakoutEA/EAContext/`

Implemented by Task 0003 under ADR-0001. The Context Layer is the **single source of runtime
state** for observation-oriented modules. It contains **no business logic**: it never places,
modifies or closes anything and never gates the strategy.

## 1. Modules

| File | Class | Contents |
|---|---|---|
| `EAContextTrade.mqh` | `CTradeContext` | Ticket, Direction, Symbol, Magic, Lots, EntryPrice, EntryTime, EntryBarTime, CurrentProfit, FloatingProfitMax/Min (MFE/MAE), TradeAgeBars, TradeAgeMinutes, BreakEvenActive, CarryActive, MomentumActive, ProfitLockActive, ExitReason, TradeState (`CTX_TRADE_FLAT/ARMED/IN_TRADE/CARRY`) |
| `EAContextMarket.mqh` | `CMarketContext` | CurrentSpread, CurrentATR(14), PreviousRange, CurrentRange, UpperShadow, LowerShadow, BodySize, BodyPercent, Volatility, TrendDirection, TrendStrength, CurrentSession (Asia/London/NewYork by server hour), CurrentHour, Weekday, Month, Quarter, BrokerOffset, DSTFlag*, HolidayFlag*, NewsFlag* (*placeholders) |
| `EAContextStrategy.mqh` | `CStrategyContext` | TradeOpened, PendingOrdersPlaced, BreakEvenEnabled, CarryEnabled, MomentumEnabled, ProfitLockEnabled, MandatoryHourClose, CurrentStrategyState (`IDLE/ARMED/IN TRADE/CARRY`), RiskMultiplier, ConfidenceScore* |
| `EAContextAI.mqh` | `CAIContext` | ModelVersion, PredictionAvailable, PredictionConfidence, InferenceTime, Enabled, Reserved1–3 — **placeholder only**, no inference |
| `EAContextLayer.mqh` | `CContextLayer` | facade owning the four contexts; single `Update()` funnel; `Validate/Reset/ToString/Serialize` |

Every context implements the mandated interface: `Init`, `Reset`, `Validate`, `Update`,
`ToString`, and a `Serialize(string&)` **stub** (returns `false` until the persistence ADR).

## 2. Responsibilities

* **Observe, never act.** Contexts copy/derive state (ages, ATR, shadows, trend share, session)
  from completed bars and from the existing `STradeContext` snapshot; trading decisions remain
  exclusively in `CExitEngine` / `CTradeManager` (frozen).
* **De-duplicate runtime reads.** Market bar statistics are computed once per completed main-TF
  bar and cached (`m_cache_bar`); repeated `Update()` calls inside a bar are free.
* **Safe defaults.** `Reset()` zeroes every field; `Validate()` checks consistency only
  (ranges, positivity), no strategy rules.

## 3. Ownership & write rules

| Actor | Permission |
|---|---|
| `CTradeManager` | the **only writer**: owns `CContextLayer m_contexts`, calls `Init()` once and `Update()` once per tick from the existing `UpdateDashboard()` path (single `BuildContext` scan, no new market scans; `RiskMultiplier` is captured once per candle via the log-free `CurrentRiskMultiplier()`) |
| All other modules (future feature builder, replay, persistence, dashboard extensions) | **read-only** access to the public fields |
| Contexts themselves | may only modify their own fields inside `Reset/Update` |

## 4. Lifecycle

1. `OnInit` → `CTradeManager::Init` → `CContextLayer::Init(settings, logger)` → each context
   `Init` + facade `Validate()` (a failure logs one `[WARNING]`, never blocks trading).
2. Every tick → `UpdateDashboard()` → `BuildContext()` → `m_contexts.Update(ctx, armed,
   multiplier, state)`:
   * `trade` copies the snapshot, derives ages, marks `CTX_TRADE_ARMED` when flat + pendings;
   * `market` refreshes clock fields each tick, bar fields once per completed bar;
   * `strategy` records flags/state/multiplier;
   * `ai` stays inert.
3. `OnDeinit` → contexts are discarded with the manager (no external resources held).

## 5. Backward compatibility

* The pre-existing `STradeContext` (`EATradeContext.mqh`) and the dashboard are **unchanged in
  behaviour**; the Context Layer consumes the same snapshot, so both views always agree.
* `CEASettings` gained one additive field `ai_reserved` wired to the existing inert
  `Reserved for future AI modules` input; defaults unchanged.
* No entry/exit/pending/BreakEven/carry code path was altered (verified: compile-only diff,
  `VERDICT: PASS - 0 errors, 0 warnings`).
