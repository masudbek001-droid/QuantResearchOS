# ADR-0016: Chief Risk AI — Advisory Risk Layer (Shadow-Only)

## Status

Accepted. (Implementing Sprint 9 / Chief Risk AI)

## Context

- Stages 8–15 are PASS: Models.db v2 holds 2 baselines (22-feature contracts, 16 evaluations), ONNX checker PASS, MT5 ONNX load PASS, replay+ONNX PASS, statistical baseline regenerated (56,514 H1 bars, 40,566 clean breakouts, volatility/hourly stratification).
- ADR-0015 gated AI promotion: research-only → shadow inference (current) → advisory sizing/management (requires new ADR + tester evidence) → production. Shadow inference via `CAIShadowInference` → `CAIContext` is validated but has **no trading authority** (Stage 14 safety audit PASS).
- Risk management today is `CRiskManager` (hours mask + daily profit/loss limits) and fixed sizing logic in `CTradeManager`. No risk advisory from statistical regimes or model confidence exists.
- Next roadmap priority after Shadow AI is **Chief Risk AI** (strict priority list: Runtime→…→Shadow AI→Chief Risk AI). It must be **advisory only** until a later ADR authorizes execution.

## Decision

Implement **Chief Risk AI** as a **shadow-only advisory risk layer**:

1. **New MQL module** `EAContext/EAContextRiskAdvisory.mqh` (`CAIRiskAdvisory`):
   - Pure advisory: reads `CMarketContext` (ATR/ATRRatio/hour/session/trend), `CAIContext` (prediction/confidence), account state (daily P/L, consecutive losses), and statistical regime tables.
   - Outputs `SRiskAdvisory { risk_multiplier 0.5..1.5, risk_flag, carry_advisory, daily_tightening_advisory, confidence_calibrated }` — observable only via `CLogger`/`CDashboard` string, never consumed by `CRiskManager`, `COrderManager`, `CExitEngine`, or `CTradeManager` entry gates.
   - **Dormant at init** (enabled flag default OFF, tied to reserved input). Explicit `Update()` only. Zero OrderSend/PositionClose/SL writes. No `BLOCK` return.
   - Validates inputs: `risk_multiplier∈[0.5,1.5]`, `Validate()` checks confidence 0..1, ATR≥0, hour 0..23. `Reset()` restores neutral (1.0, NORMAL).

2. **Risk tables (research artifact, not hard-coded magic):**
   - Volatility regime multipliers derived from statistical baseline `volRegimeStats`: Low (ATRRatio ≤0.75, WR 58.87%, PF 1.95 → 1.00), Normal (0.75–1.50 → 0.85), High (>1.50, WR 49.79% → 0.50 caution).
   - Hourly multipliers from `hourlyTopHours`/worst hours: top hours 12/01/13 → 1.00, worst hour 21 (49.37%) + high-vol → 0.60, otherwise 0.85–0.95.
   - Model confidence calibration: walk-forward `avg_accuracy` Logistic 0.390 / RF 0.418 vs confidence; if `PredictionConfidence <0.35` → multiplier ×0.80; if `FAKE_BREAKOUT` p>0.50 → 0.50 caution.
   - Daily proximity: if `abs(DailyProfit) ≥0.80*limit` (limit>0) → flag ELEVATED.
   - All tables materialized by Python tool `06_Tools/chief_risk_advisory.py` into `04_Output/Risk/risk_advisory_report.json` + markdown; MQL uses distilled constants with JSON as source of truth.

3. **Python research tool** `06_Tools/chief_risk_advisory.py`:
   - Loads `statistical_baseline_report.json` + `phase_d_*` metrics, computes advisory tables, writes `04_Output/Risk/` artifacts, validates no lookahead (uses only past regime stats + walk-forward averages).
   - No live trading, no DB writes to `CBEA_Models.db`.

4. **Safety invariants (ADR-0015 preserved):**
   - May NOT call `OrderSend`, `OrderDelete`, `PositionClose`, `SetDeviationInPoints`, `CRiskManager::Check` bypass, or `CExitEngine` reordering.
   - May NOT block `CTradeManager` arming when `CRiskManager` says `BLOCK_NONE`.
   - May NOT bypass `CRiskManager` BLOCK when it says `BLOCK_HOURS`/`BLOCK_DAILY_PNL`.
   - Default OFF; rollback = `Reset()` + disable flag, trading core identical to MIPS v1.0.
   - Tested by `01_Source/Tests/test_chief_risk_ai.py` → safety token scan 0 hits, advisory multiplier bounds, regime mapping, immutability.

## Mandatory Gates Before Any Live Effect

Same as ADR-0015 gates 1–7 PLUS:
- Chief Risk advisory validation `STATUS=PASS` (multiplier bounds, flag correctness, 0 forbidden tokens).
- Safety audit `trade_manager_ai_calls=0` still holds (new advisory not consumed).
- Strategy Tester regression gate still required for production (future ADR).

## Rollback Rule

Identical to ADR-0015: unload advisory, `Reset()`, keep MIPS v1.0 behavior; log gate failure in CHANGELOG.

## Consequences

- Advisory risk insight becomes observable without corrupting frozen trading core.
- Research artifacts (`risk_advisory_report.json`) remain reproducible from baseline JSON.
- Live risk behavior cannot change accidentally — advisory outputs are strings only until a future ADR explicitly wires them behind a flag with tester evidence.

## References
- `03_Documents/Reports/STATISTICAL_BASELINE_REPORT.md` (volatility/hourly stratification)
- `05_Training/Metrics/phase_d_*` (walk-forward avg_accuracy 0.390/0.418)
- `STAGE8_SUPERVISED_MODEL_TRAINING.md` (22-feature contract)
- `STAGE14_AI_SHADOW_SAFETY_AUDIT.md` (forbidden token pattern)
