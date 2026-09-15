# CandleBreakoutEA — MetaTrader 5 Expert Advisor

Previous-candle breakout on a selectable main timeframe (default **H1**), with an **M5 swing
break-even** trail, four lot-sizing modes, daily P/L limits, a per-hour trading filter, chart
visuals and a structured Experts log.

Object oriented, modular, compiles with **0 errors and 0 warnings** on the current MetaQuotes
compiler.

---

## 1. Files

```
MQL5/
├── Experts/
│   └── CandleBreakoutEA/
│       └── CandleBreakoutEA.mq5      entry point: inputs, OnInit / OnTick / OnDeinit / OnTradeTransaction
└── Include/
    └── CandleBreakoutEA/
        ├── EASettings.mqh            shared enums + the CEASettings configuration payload
        ├── EAUtils.mqh               CEAUtils: normalization, broker limits, time & price helpers
        ├── EALogger.mqh              CLogger: single funnel into the Experts log
        ├── EATradeHistory.mqh        CTradeHistory: daily P/L, losing streak
        ├── EARiskManager.mqh         CRiskManager: daily limits + trading hours filter
        ├── EAOrderManager.mqh        COrderManager: pending order create / find / delete
        ├── EAPositionManager.mqh     CPositionManager: position inspection + close
        ├── EABreakEvenManager.mqh    CBreakEvenManager: M5 swing trailing stop
        ├── EAMomentum.mqh            CMomentumAnalyzer: momentum strength measurement
        ├── EATradeContext.mqh        STradeContext: unified read-only snapshot of the live trade
        ├── EAContext/                  Context Layer (Task 0003):
            ├── EAContextTrade.mqh      CTradeContext: runtime trade state
            ├── EAContextMarket.mqh     CMarketContext: market snapshot (cached per bar)
            ├── EAContextStrategy.mqh   CStrategyContext: cycle state + enabled stack
            ├── EAContextAI.mqh         CAIContext: placeholder only
            └── EAContextLayer.mqh      CContextLayer: facade, single update funnel
        ├── EAFeatureBuilder/           Feature Builder (Task 0004):
            ├── FeatureTypes.mqh        status/session/trend enums + analysis constants
            ├── FeatureSnapshot.mqh     SFeatureSnapshot: immutable market features
            ├── FeatureValidation.mqh   CFeatureValidation: NaN/neg/invalid/missing rules
            └── EAFeatureBuilder.mqh    CFeatureBuilder: the only market-feature source
        ├── EAData/                     Data Access Layer (Task 0005):
            ├── DatabaseTypes.mqh       status enum + schema/table constants
            ├── IDataProvider.mqh       pure persistence interface
            ├── SQLiteProvider.mqh      CSQLiteProvider: isolated SQLite binding
            ├── DatabaseSchema.mqh      schema v1 DDL (metadata tables only)
            ├── DatabaseVersion.mqh     versioning + migration funnel
            ├── DatabaseValidation.mqh  stateless validation rules
            ├── DatabaseManager.mqh     CDatabaseManager: the ONLY public class
            ├── MarketSnapshotWriter.mqh market observations -> schema v2
            ├── TradeWriter.mqh         trade metadata -> schema v3
            ├── ObservationWriter.mqh   market recorder -> schema v4
            ├── LabelGenerator.mqh      ground-truth labels -> schema v5
            ├── DatasetBuilder.mqh      research datasets -> schema v6
            ├── DataQualityAnalyzer.mqh quality gate -> schema v7
            └── FeatureRegistry.mqh     feature catalogue -> schema v8
        └── EAReplay/                   Replay Foundation (Sprint 4):
            ├── ReplayTypes.mqh         states, speeds, replay structs
            ├── ReplayValidator.mqh     integrity & consistency engine
            ├── ReplayTimeline.mqh      deterministic database-only playback
            └── ReplayController.mqh    session lifecycle -> schema v9
        ├── EAResearch/                 Research Platform (Sprint 5):
        │   ├── ExperimentEngine.mqh    experiments -> schema v10
        │   ├── BenchmarkEngine.mqh     deterministic benchmarks
        │   └── WalkForwardEngine.mqh   walk-forward windows
        └── EAHistory/                  Historical Data Platform (Sprint 6A):
            ├── HistoryTypes.mqh        Ticks.db / Market.db / Models.db contracts
            ├── HistoryStore.mqh        dedicated store + Symbols/Timeframes masters
            ├── TickExporter.mqh        raw tick export (resume + incremental)
            ├── BarExporter.mqh         M1–D1 bar export (resume + incremental)
            ├── MetadataExporter.mqh    sessions, offset, DST, contract metadata
            ├── DataIntegrityValidator.mqh  read-only integrity scans
            └── HistoryPlatform.mqh     facade: sources + ImportHistory -> schema v11
        ├── EAExitEngine.mqh          CExitEngine: exit intelligence engine (lock / momentum / carry)
        ├── EAExitStats.mqh           CExitStats: per-reason counters + CSV journal
        ├── EADashboard.mqh           CDashboard: on-chart EXIT ENGINE panel
        ├── EAVisualManager.mqh       CVisualManager: chart objects
        └── EATradeManager.mqh        CTradeManager: the candle-cycle state machine
```

No module reaches into another's internals — managers talk through `CEASettings` (a pointer to the
one instance owned by `CTradeManager`) and `CLogger`.

## 2. Installation

1. Copy `MQL5/Experts/CandleBreakoutEA/` into `<MT5 Data Folder>/MQL5/Experts/`.
2. Copy `MQL5/Include/CandleBreakoutEA/` into `<MT5 Data Folder>/MQL5/Include/`.
3. Press **F7** in MetaEditor on `CandleBreakoutEA.mq5`.

`<MT5 Data Folder>` is *File → Open Data Folder* in the terminal. The EA depends on
`<Trade\Trade.mqh>`, which ships with every MetaTrader 5 installation — nothing to download.

The include folder is namespaced (`Include/CandleBreakoutEA/`) so it cannot collide with the
standard library or with other experts.

## 3. Strategy lifecycle

On every new main-timeframe candle:

| Step | Behaviour |
|---|---|
| 1 | The finished candle is flattened: any open position is closed, any leftover pending order is deleted. |
| 2 | Filters are evaluated (trading hours, daily profit, daily loss). If a filter blocks, the candle is skipped and the reason is logged. |
| 3 | The **previous** candle high and low are read. |
| 4 | **Buy Stop** at the previous high and **Sell Stop** at the previous low. No offset, **no stop loss, no take profit**. |
| 5 | The first fill deletes the opposite pending order → exactly one trade per candle. |
| 6 | While the position is open the EA switches to the break-even timeframe; the **Exit Intelligence Engine** watches the position (break even → profit lock → momentum exit, see §5). |
| 7 | At the candle close everything is closed — unless Carry Mode (default off) keeps a strong profitable position for exactly one extra candle. |

Two independent mechanisms guarantee the flatten at candle close:

* the EA deletes / closes on the first tick of the new bar;
* where the broker allows it, pending orders are also placed with an **expiration** equal to the
  candle close, so they die even if the terminal is offline.

**One trade per candle** is enforced by `m_traded_this_candle`. After a position closes inside the
same candle the EA does nothing until the next bar, unless `Allow Re-Entry After Close In Same
Candle` is turned on.

**On attach:** the currently running candle is only used as a baseline — the first cycle starts at
the next candle open, so the EA never trades a half-finished candle it did not arm itself. A
position that was already open (same magic + symbol) is adopted and managed.

## 4. Break even

Enabled by `Enable BreakEven`. After the entry the EA counts **completed** M5 bars. Every
`Update Every N Completed Bars` bars (default 2) it looks for the newest **confirmed** swing
(`Swing Bars` bars on each side of the pivot, formed after the entry) and moves the stop behind it:

* long → stop to the latest confirmed swing low
* short → stop to the latest confirmed swing high

Trades are opened **without any stop loss**. When Break Even is enabled the EA *creates* the first
stop at the first qualifying swing and then only moves it forward, only when it already locks profit
beyond entry + spread, and never closer to the market than the broker's stops level. If no
qualifying swing exists yet the EA simply waits. With `Enable BreakEven = false` (the default) a
trade carries no stop at all — the only exit is the candle close.

## 5. Exit Intelligence Engine

While a position is open, exits are evaluated in a strict priority order. Entries, pending orders,
the risk manager and the lot logic are **untouched** — the engine can only close earlier or carry
longer, never open anything.

| # | Exit | Trigger | Exit reason |
|---|---|---|---|
| 1 | **BreakEven** | the optional M5 swing stop is hit (existing behaviour, runs first) | `BreakEven` |
| 2 | **Profit Lock** | floating profit reached `Profit Lock Trigger` (points) and then fell back to `Keep %` of the peak | `Profit Lock` |
| 3 | **Momentum Exit** | after ≥ 3 completed break-even bars the momentum score drops below `Momentum Sensitivity` | `Momentum Exit` |
| 4 | **Candle close** | the mandatory flatten at the main-timeframe candle close (always) | `H1 Close` |

**Momentum score (0–100)** — `CMomentumAnalyzer` reads the last three **completed** break-even
timeframe bars in the direction of the trade: full body in direction scores high, opposite wicks
and opposite candles score low, and three shrinking bodies or a doji-like last bar subtract extra
points. The score is measurement only — it never places orders.

**Carry Mode** (default **off**) — at the candle close a position may survive **exactly one extra
candle** when it is in profit *and* the momentum score is at least `Minimum Trend Strength For
Carry`. `Maximum Carry Candles` is hard-capped at `1` (any other value is rejected at `OnInit`).
While a position is carried no new pending orders are placed, and at the next candle close it is
flattened with the reason `Carry Expired`.

**Trade Context** — while a position is open the trade manager fills one shared `STradeContext`
(ticket, direction, entry time/candle/price, live profit, MFE/MAE, break-even / profit-lock /
carry flags, momentum score, planned exit reason). The dashboard and the exit journal only
*read* this snapshot; no module reaches into another manager's state.

**Exit journal** — every closed trade (including broker- and terminal-initiated closes, classified
as `BreakEven` or `Manual` from the last known stop, `Error` when it cannot be classified) is:

* logged to the Experts tab (`Exit recorded | #ticket | reason | profit | peak | momentum`),
* appended to `MQL5/Files/CBEA_<magic>_<symbol>_exits.csv`:

```
Ticket;OpenTime;CloseTime;Side;Lots;Profit;ExitReason;MaximumFloatingProfit;MaximumFloatingLoss;ProfitLocked;CarryUsed;MomentumScore;EntryPrice;ExitPrice;BreakEvenUsed;MomentumExit
```

`MaximumFloatingProfit` / `MaximumFloatingLoss` are the trade's MFE / MAE in points; missing
values are written as `0` so the journal never contains gaps.

* counted per reason in the dashboard's **EXIT STATISTICS** block.

**Dashboard** — a compact panel in the chart's top-right corner, drawn only from the
TradeContext: strategy state (`IDLE / ARMED / IN TRADE / CARRY`), break-even status, profit-lock
status and level, carry status, momentum score, floating profit, the planned exit reason, a
one-line trade summary (`#ticket side lots @ entry | MFE | MAE`) and the per-reason counters
(`H1 BE PL MO CR MN ER`). It redraws only when the composed text changes. Panel objects share
the `CBEA_<magic>_` prefix and are removed with everything else in `OnDeinit`.

**Context Layer** — `EAContext/` (ADR-0001) centralizes runtime observation state in four
contexts (`CTradeContext`, `CMarketContext`, `CStrategyContext`, placeholder `CAIContext`)
behind the `CContextLayer` facade. The trade manager is the only writer (one `Update()` per
tick on the existing dashboard path); every other module reads. Contexts hold no business
logic, market statistics are cached per completed bar, and `Serialize()` is a stub until the
persistence ADR. Trading behaviour is unchanged.

**Feature Builder** — `EAFeatureBuilder/` (ADR-0002) centralizes every market-derived
statistic (ranges, shadows, ATR, volatility, trend, session) behind one validated,
immutable snapshot per completed bar. The trade manager is the only updater; all other
modules read copies. Existing calculations stay in place until the migration tasks.

**Data Access Layer** — `EAData/` (ADR-0003) is the only persistence interface:
`CDatabaseManager` (facade) → `IDataProvider` (contract) → `CSQLiteProvider` (isolated
SQLite). Schema v1 holds metadata tables only (`DatabaseInfo`, `SchemaVersion`,
`MigrationHistory`). Schema **v2** adds the Market Intelligence tables (`Symbols`,
`Timeframes`, `MarketSnapshots` + 6 indexes): `CMarketSnapshotWriter` persists one
validated market observation per completed bar. Schema **v3** adds the Trade
Intelligence table `Trades` (+6 indexes): `CTradeWriter` stores complete trade metadata
with `EntrySnapshotID`/`ExitSnapshotID` links into `MarketSnapshots` for future research.
Schema **v4** adds the Observation Engine: `Observations` (+5 indexes) — exactly one
classified market observation per completed candle, trade-independent. Schema **v5**
adds the Label Engine: `ObservationLabels` (+4 indexes) — ground-truth outcome labels
written only after the 3-bar future window completes. Schema **v6** adds the Research
Dataset Builder: `ResearchDatasets` (+4 indexes) — reproducible ML-ready joins of
observations + snapshots + labels (+ optional trades). Schema **v7** adds the Data
Quality Engine: `DatasetQuality` reports + a mandatory gate — CSV export is blocked
unless the dataset is `QUALITY_PASS` (no override). Schema **v8** adds the Feature
Registry: versioned catalogue of every feature (name, category, owner, validation
rule) + per-dataset manifests pinning Feature/Label/Quality versions. Schema **v9**
adds the Replay Foundation (`EAReplay/`, ADR-0011): deterministic, database-only
replay of recorded history with integrity gating — dormant until explicitly started.
Schema **v10** adds the Research Platform (`EAResearch/`, ADR-0012): immutable
experiments with pinned versions, deterministic benchmarks, and walk-forward windows
(rolling/expanding/fixed) with overlap rejection. Schema **v11** adds the
Historical Data Platform (`EAHistory/`, ADR-0013): dedicated Ticks.db / Market.db /
Models.db stores, broker data-source registry and import history in Research.db —
dormant exports with resume + incremental sync + integrity validation. The trade manager opens
the DAL at init and closes it at deinit; failures never affect trading.

## 6. Lot sizing

| Mode | Behaviour |
|---|---|
| **Fixed Lot** | `Fixed Lot` verbatim (normalized to the symbol lot step / min / max). |
| **Risk % of Balance** | `balance × Risk% ÷ loss-per-lot`, where loss-per-lot is derived from `Risk Stop Distance` (the input is sizing-only; `0` disables Risk % sizing with a warning and no orders are placed). |
| **Soft Martingale** | base lot × `Multiplier^min(consecutiveLosses, MaxSteps)` — progression **caps** at the maximum step. |
| **Hard Martingale** | base lot × `Multiplier^(consecutiveLosses mod MaxSteps)` — progression **resets** to step 0 after the maximum step. |

The consecutive-loss count is read from the account history (deals filtered by magic + symbol), so
it survives an EA restart.

## 7. Filters

* **Daily Profit Limit / Daily Loss Limit** — closed-trade P/L of the current server day
  (profit + swap + commission). `0` disables the limit. A blocked candle logs
  `Daily Limit Reached | ...`.
* **Trading Hours Filter** — `Trading Hours Bitmask` is a 24-bit mask, **bit 0 = 00:00**,
  **bit 23 = 23:00**. Every hour is enabled or disabled independently.
  Default `16777215` = `0xFFFFFF` = all hours on.

  | Hours wanted | Mask |
  |---|---|
  | all | `16777215` |
  | 08:00–16:59 only | `130816` |
  | 00:00–06:59 only | `127` |
  | London + New York 07:00–20:59 | `2097024` |

  Build any value with `Σ 2^hour`. The mask is evaluated against the **server** clock.

## 8. Chart objects

| Object | Meaning |
|---|---|
| blue dashed line `Prev High` | previous candle high (buy trigger) |
| red dashed line `Prev Low` | previous candle low (sell trigger) |
| green / red segment | the pending order lifetime, up to its expiration |
| green ▲ / red ▼ | entry |
| yellow ✕ | exit |
| gold dotted line `BE` | the live break-even / trailing stop |
| top-right panel `== EXIT ENGINE ==` | live exit state + per-reason statistics (see §5) |

Everything is prefixed with `CBEA_<magic>_` and removed in `OnDeinit`.

## 9. Log

Every line is standardized: `<timestamp> [CBEA <magic> <symbol>] [TAG] message`, the ticket is
embedded in the message whenever one exists. Only seven tags exist:

| Tag | Used for |
|---|---|
| `[INFO]` | cycle events, initialization, diagnostics |
| `[WARNING]` | skipped orders, filters blocking, invalid data |
| `[ERROR]` | failed order / close / modify requests |
| `[TRADE]` | pending orders created / deleted / triggered |
| `[EXIT]` | every close, profit lock, carry decisions, exit journal |
| `[BREAK EVEN]` | swing stop updates |
| `[MOMENTUM]` | momentum based exit decisions |

```
2026.09.09 14:00:00 [CBEA 20260909 EURUSD] [INFO]    New Candle | #12 | PERIOD_H1 | 14:00 | close 15:00
2026.09.09 14:00:00 [CBEA 20260909 EURUSD] [TRADE]   Pending Orders Created | BuyStop 1.09420 | SellStop 1.09180 | no SL | no TP | lots 0.10
2026.09.09 14:12:11 [CBEA 20260909 EURUSD] [TRADE]   Buy Triggered | #184467448 | entry 1.09420 | lots 0.10 | no SL | no TP
2026.09.09 14:35:02 [CBEA 20260909 EURUSD] [BREAK EVEN] BreakEven Updated | #184467448 | SL none -> 1.09455 | swing 1.09455 | M5 bars 4
2026.09.09 14:41:20 [CBEA 20260909 EURUSD] [EXIT]    Profit Lock armed | peak 412 pts | locked level 206 pts
2026.09.09 14:52:47 [CBEA 20260909 EURUSD] [EXIT]    Trade Closed | #184467448 BUY 0.10 lots | profit 20.10 | reason: Profit Lock
2026.09.09 14:52:47 [CBEA 20260909 EURUSD] [EXIT]    Exit recorded | #184467448 | Profit Lock | profit 20.10 | peak 412 pts | momentum 33
2026.09.09 15:00:01 [CBEA 20260909 EURUSD] [MOMENTUM] Momentum Exit | score 33 < sensitivity 40
2026.09.09 15:00:01 [CBEA 20260909 EURUSD] [WARNING] Daily Limit Reached | profit 512.00 >= 500.00
```

`Log Level` selects the verbosity: *Errors only → Errors + Warnings → + Info → Everything*.
`Enable Logging = false` silences the EA completely.

## 10. Inputs

The inputs are organized in MetaEditor groups: **Trading, Risk, Break Even, Exit Engine,
Dashboard, Logging, Advanced, Future AI** (the last one only holds an inactive reserved switch).
Behaviour of every parameter is unchanged.

| Input | Default | Purpose |
|---|---|---|
| Main Timeframe | `PERIOD_H1` | candle that drives the whole cycle |
| Magic Number | `20260909` | isolates the EA's orders, positions and history |
| Order Comment | `CandleBreakout` | order comment |
| Allow Re-Entry After Close In Same Candle | `false` | off = strictly one trade per candle |
| Lot Mode | `Fixed Lot` | Fixed / Risk % / Soft Martingale / Hard Martingale |
| Fixed Lot | `0.10` | used by Fixed Lot and as the martingale base |
| Risk % Of Balance | `1.0` | risk modes |
| Martingale Multiplier | `1.5` | martingale modes |
| Maximum Martingale Steps | `5` | cap (soft) / reset point (hard) |
| Risk Stop Distance (points) | `500` | distance assumed ONLY by the Risk % lot calculation; it never creates an order stop; `0` = warning and no orders are placed |
| Enable BreakEven | `false` | optional M5 swing trailing; off by default so trades carry no stop |
| BreakEven Timeframe | `PERIOD_M5` | |
| Swing Bars | `2` | bars on each side of the pivot |
| Update Every N Completed Bars | `2` | trailing frequency |
| BreakEven Buffer (points) | `0` | extra distance behind the swing |
| Enable Profit Lock | `true` | exit #2: give back only part of a big floating profit |
| Profit Lock Trigger (points) | `300` | floating profit that arms the lock |
| Profit Lock Keep (%) | `50` | share of the peak that must be kept |
| Enable Momentum Exit | `true` | exit #3: leave when the trend weakens |
| Momentum Sensitivity | `40` | close when the score (0–100) drops below this |
| Enable Carry Mode | `false` | allow exactly one extra candle for a strong winner |
| Maximum Carry Candles | `1` | hard cap — `OnInit` rejects any other value |
| Minimum Trend Strength For Carry | `70` | momentum score required to carry |
| Show Exit Dashboard Panel | `true` | top-right EXIT ENGINE / STATISTICS panel |
| Draw Chart Objects | `true` | breakout levels, entries, exits, BE line |
| Reserved for future AI modules | `false` | inactive placeholder, no effect |
| Enable Logging / Log Level | `true` / `Info` | standardized seven-tag log |
| Enable Daily Limits | `true` | |
| Daily Profit Limit | `0` | `0` = off |
| Daily Loss Limit | `0` | `0` = off |
| Enable Trading Hours Filter | `false` | |
| Trading Hours Bitmask | `16777215` | 24-bit hour mask |

`OnInit` rejects invalid combinations with `INIT_PARAMETERS_INCORRECT` and prints the reason.

## 11. Extending

* **New lot mode** — add a value to `ENUM_LOT_MODE`, extend `CTradeManager::CalculateLotSize`.
* **New filter** — add a case to `CRiskManager::Check`; it returns an `ENUM_TRADE_BLOCK` and logs
  its own reason, so `CTradeManager` needs no change.
* **New visual** — add a method to `CVisualManager`; cleanup is automatic through the prefix.
* **Different exit rule** — add a check inside `CExitEngine::OnTick` (before the return) and a
  value to `ENUM_EXIT_REASON`; the mandatory flatten stays in `CTradeManager::CloseCandle`.
* **New exit statistic** — extend `SExitRecord` / `CExitStats::Record` and the CSV header together.

## 12. Verification

`tools/build.py` stages the sources into a real MetaTrader 5 data folder and compiles them with
`MetaEditor64.exe`:

```
staged into     : /home/user/.build
standard library: True
compiler result : 0 error(s), 0 warning(s)
binary          : CandleBreakoutEA.ex5 (205146 bytes)

VERDICT: PASS - 0 errors, 0 warnings, binary produced
```

Runtime behaviour on a broker account (fills, expirations, stops level) has not been exercised —
run the EA in the Strategy Tester and on a demo account before going live.

## 13. Notes

* All prices and volumes are normalized to the symbol's tick size, digits, lot step and min/max.
* The broker **stops level** and **freeze level** are respected for pending prices and the optional
  trailing; an order that cannot satisfy them is skipped with a warning instead of being rejected.
* The filling policy is chosen from `SYMBOL_FILLING_MODE` (FOK → IOC → RETURN).
* Removing the EA from the chart deletes its objects but leaves open positions and orders in place.
