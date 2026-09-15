# DATA INTEGRITY REPORT — Sprint 6A (CDataIntegrityValidator)

## Scope

`CDataIntegrityValidator` is read-only: aggregate SQL scans over Ticks.db /
Market.db, writes nothing, returns `clean` + a text report. Wired through
`CHistoryPlatform::ValidateIntegrity(report)`.

## 1. Ticks.db — `ValidateTicks`

| Check | Method |
|---|---|
| Duplicates | self-join `Ticks t1 JOIN Ticks t2 ON …` with `t1.ROWID < t2.ROWID` on (SymbolID, BrokerTime, Milliseconds, Bid, Ask) |
| Invalid ticks | `Bid<=0 OR Ask<=0 OR Ask<Bid` |
| Out-of-order | per symbol, broker time regressions (`MIN(BrokerTime)` vs ordered scan of ROWID-adjacent rows) |

## 2. Market.db — `ValidateBars` (per timeframe, 7 loops)

| Check | Method |
|---|---|
| Duplicate candles | `COUNT(*)` vs `COUNT(DISTINCT SymbolID, OpenTime)` |
| Invalid OHLC | `High<Low OR Open<Low OR Open>High OR Close<Low OR Close>High OR Open<=0` |
| Negative spread | `Spread<0` |
| Missing bars | expected = span/TF seconds − weekend slots (`span_days/7 × 2 × 86400/tf_sec`) vs actual count |
| Sequence / weekend awareness | expected-count model is weekend-aware, so Sat/Sun gaps are not false positives; exchange-holiday gaps surface as `missing` and are reported, never silently repaired |

## 3. Cross-timeframe consistency — `ValidateTimeframes`

* H1 vs M15 count ratio must sit in (3.9, 4.1) → one of four M15 bars per H1 bar.
* MIN/MAX coverage of every TF compared against the D1 envelope.

## 4. Result contract

Each `Validate*` returns `true` only when the scan found zero anomalies; the combined
report (tick + bar + TF sections) is what the caller logs / persists. Repair is out
of scope by design — the validator diagnoses, `ResumeExport` / `SynchronizeBars`
(UNIQUE + INSERT OR IGNORE) heal by re-running.

## 5. Verification

Compiles as part of the full build (**0 errors, 0 warnings**, ex5 205 506 bytes).
No trading/decision code path references the validator — it is reachable only from
`CHistoryPlatform` API.
