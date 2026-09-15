# FEATURE BUILDER — `MQL5/Include/CandleBreakoutEA/EAFeatureBuilder/`

Implemented by Task 0004 under ADR-0002. The Feature Builder is the **centralized and only**
source of market-derived statistics; after this task no other module may calculate market
statistics independently (migration of pre-existing calculations happens in later tasks).

## 1. Purpose

* One place for every market feature: candles, ranges, shadows, ATR, volatility, trend,
  session/clock data.
* Kill duplicated ad-hoc series math (technical debt DUP-03..05 from Task 0002).
* Feed future consumers: context layer migration, feature pipelines, replay, persistence, AI.

## 2. Responsibilities

* Compute all features from **completed** main-TF bars only; cache per completed bar so
  per-tick `Update()` calls are free.
* Validate every output; publish only fully valid snapshots.
* Strictly observation-only: no trading, order, position, file or chart-object side effects.

## 3. Lifecycle

1. `OnInit` → `CTradeManager::Init` → `m_features.Initialize(settings, logger)`;
   status starts at `FB_ERR_MISSING_RATES`, one `[INFO]` line.
2. Every tick (on the existing `UpdateDashboard()` path) → `m_features.Update()`:
   no-op inside a bar; on each new completed bar one series pass, validation, and on
   `FB_OK` publication (invalid passes keep the last valid snapshot and log only status
   transitions).
3. `OnDeinit` → discarded with the manager; holds no external resources.

## 4. Ownership / read-write policy

| Actor | Permission |
|---|---|
| `CFeatureBuilder` | the only writer of its snapshot |
| `CTradeManager`   | the only caller of `Initialize()/Update()` |
| every other module | read-only via `GetSnapshot()` (receives a copy) and `LastStatus()` |

The snapshot type is value-semantics immutable by convention: consumers never write back.

## 5. Supported features (`SFeatureSnapshot`)

Timestamp, Symbol, Timeframe, Spread (pts), ATR(14), ATR Ratio (last range / ATR),
PreviousRange, CurrentRange, BodySize, BodyPercent, UpperShadow, LowerShadow,
UpperShadowRatio, LowerShadowRatio, Bullish, Bearish, Volatility (ATR in points),
TrendDirection, TrendStrength (0..100), CurrentHour, Weekday, Month, Quarter,
Session (Asia/London/NewYork by server hour), BrokerOffset, Reserved1–4.

## 6. Validation rules (`CFeatureValidation`)

Rejects: NaN/Infinity (`MathIsValidNumber`), negative ATR, negative spread, invalid candle
(high<low, OHLC outside [low,high], zero range), missing rates (`Bars < 2*ATR_PERIOD+2`),
out-of-range percentages/strengths. `Validate()` returns `ENUM_FB_STATUS`; the builder stores
the last status and exposes `IsReady()`.

## 7. Future extensions

* Migrate `CMarketContext` / `CMomentumAnalyzer` series reads onto the builder (see pending
  migration list in FEATURE_IMPLEMENTATION_REPORT).
* Fill `Reserved1–4` through ADRs.
* Wire serialization when the persistence (SQLite) ADR lands; feed the replay engine later.
