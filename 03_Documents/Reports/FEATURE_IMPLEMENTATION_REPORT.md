# FEATURE IMPLEMENTATION REPORT — Task 0004 (Feature Builder Foundation)

## 1. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAFeatureBuilder/FeatureTypes.mqh` | analysis constants (`FB_ATR_PERIOD=14`, `FB_TREND_PERIOD=10`, `FB_MIN_BARS`, session borders), `ENUM_FB_SESSION`, `ENUM_FB_TREND`, `ENUM_FB_STATUS` + `FbStatusToString` |
| `EAFeatureBuilder/FeatureSnapshot.mqh` | `SFeatureSnapshot` — immutable snapshot with all mandated fields plus `Reserved1–4`, `Reset()` |
| `EAFeatureBuilder/FeatureValidation.mqh` | `CFeatureValidation` — stateless rules: `IsFinite` (`MathIsValidNumber`), `IsValidCandle`, `Validate()` returning `ENUM_FB_STATUS` |
| `EAFeatureBuilder/EAFeatureBuilder.mqh` | `CFeatureBuilder` — `Initialize/Update/Reset/Validate/GetSnapshot/ToString` + `LastStatus/IsReady`; per-bar cache; publishes only validated snapshots |
| `FEATURE_BUILDER.md` | purpose / responsibilities / lifecycle / ownership / read-write policy / features / extensions |
| `docs/adr/ADR-0002-feature-builder.md` | architecture decision record |

## 2. Files modified (additive only)

| File | Change |
|---|---|
| `EATradeManager.mqh` | +include, +`CFeatureBuilder m_features` member, `Initialize()` in `Init`, one `m_features.Update()` call on the existing `UpdateDashboard()` path |
| `CandleBreakoutEA.mq5` | header comment lists `EAFeatureBuilder/*.mqh` |
| `README.md`, `tools/build_manual.py` (+PDF) | module tree (24 headers), counts (4 165 lines), binary size, Feature Builder paragraph |

## 3. Public API

```
void                Initialize(const CEASettings&, CLogger&);
void                Update(void);                    // cached per completed main-TF bar
void                Reset(void);
bool                Validate(void) const;            // re-checks the published snapshot
SFeatureSnapshot    GetSnapshot(void) const;         // copy; consumers read-only
ENUM_FB_STATUS      LastStatus(void) const;
bool                IsReady(void) const;
string              ToString(void) const;
```

## 4. Implemented features

Candle: CurrentRange, PreviousRange, BodySize, BodyPercent, Upper/LowerShadow(+ratios),
Bullish/Bearish, invalid-candle rejection. Momentum/volatility: ATR(14), ATRRatio,
Volatility (points), TrendDirection, TrendStrength. Clock/session: Hour, Weekday, Month,
Quarter, Session, BrokerOffset. Market microstructure: Spread. Reserved slots for the future.

## 5. Validation rules

`FB_OK`, `FB_ERR_MISSING_RATES` (Bars < 2·14+2 or no series), `FB_ERR_INVALID_CANDLE`
(high<low, OHLC outside range, zero range, bad percents), `FB_ERR_NEGATIVE_ATR`,
`FB_ERR_NEGATIVE_SPREAD`, `FB_ERR_NON_FINITE` (NaN/Inf via `MathIsValidNumber`).
Invalid passes never overwrite the last valid snapshot; only status transitions are logged.

## 6. Backward compatibility

* **Existing calculations left intact** (`CMomentumAnalyzer`, `CMarketContext`) per Step 5 —
  the accepted temporary duplication is recorded in ADR-0002.
* No entry/exit/pending/BreakEven/carry path touched; inputs, CSV, logs vocabulary, dashboard
  and Context Layer unchanged.
* `VERDICT: PASS - 0 errors, 0 warnings` (123 866 B binary).

## 7. Pending migration work (future tasks)

1. Point `CMarketContext` at `CFeatureBuilder` and delete its private series math.
2. Let `CMomentumAnalyzer` consume builder features where equivalent.
3. Retire duplicated digits/side-price helpers onto context/builder reads (DUP-04/05).
4. Serialization + persistence (SQLite ADR) and replay consumption.

**Stop condition honoured:** no module migrated, no SQLite / Event Bus / Replay started.
Waiting for Task 0005.
