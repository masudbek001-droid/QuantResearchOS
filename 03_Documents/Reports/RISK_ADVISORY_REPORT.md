# Chief Risk AI — Advisory Report (ADR-0016)

**Generated:** 2026-09-15 06:44 UTC  
**Source:** `04_Output/Statistics/statistical_baseline_report.json` + `phase_d_*` metrics  
**Mode:** advisory only — no order/position/exit authority (ADR-0015/0016)

## 1. Dataset Baseline (no lookahead)

- **H1 bars:** 56514 (2016-10-05→2026-09-14)
- **Clean breakouts:** 40566 (WR 54.96%, PF 1.945)
- **Volatility regimes (ATRRatio):**
  - Low ≤0.75: N≈15,914 WR 58.87% Exp +0.972 → **mult 1.00 NORMAL** (compression edge)
  - Normal 0.75–1.50: WR 53.36% → **mult 0.85 REDUCED**
  - High >1.50: N=6,330 WR 49.79% Exp +0.40 → **mult 0.50 CAUTION** (random)

## 2. Hourly Seasonality (server hour)

| Hour | Expectancy | Mult | Flag | Why |
|---|---|---|---|---|
| 00:00 | +1.072 | 0.90 | REDUCED | session blend |
| 01:00 | +1.664 | 1.00 | NORMAL | top hour |
| 02:00 | +0.324 | 0.90 | REDUCED | session blend |
| 03:00 | +0.198 | 0.90 | REDUCED | session blend |
| 04:00 | +0.183 | 0.70 | CAUTION | worst hour |
| 05:00 | +1.323 | 1.00 | NORMAL | top hour |
| 06:00 | +0.803 | 0.90 | REDUCED | session blend |
| 07:00 | +0.698 | 0.90 | REDUCED | session blend |
| 08:00 | +0.740 | 0.85 | REDUCED | session blend |
| 09:00 | +0.454 | 0.85 | REDUCED | session blend |
| 10:00 | +0.366 | 0.85 | REDUCED | session blend |
| 11:00 | +0.725 | 0.85 | REDUCED | session blend |
| 12:00 | +1.809 | 1.00 | NORMAL | top hour |
| 13:00 | +1.515 | 1.00 | NORMAL | top hour |
| 14:00 | +1.226 | 1.00 | NORMAL | top hour |
| 15:00 | +0.865 | 0.85 | REDUCED | session blend |
| 16:00 | +0.508 | 0.85 | REDUCED | session blend |
| 17:00 | +0.322 | 0.85 | REDUCED | session blend |
| 18:00 | +0.515 | 0.85 | REDUCED | session blend |
| 19:00 | +0.617 | 0.85 | REDUCED | session blend |
| 20:00 | +0.395 | 0.85 | REDUCED | session blend |
| 21:00 | +0.118 | 0.70 | CAUTION | worst hour |
| 22:00 | +1.090 | 0.90 | REDUCED | session blend |
| 23:00 | +1.143 | 0.90 | REDUCED | session blend |

## 3. Model Confidence Calibration (walk-forward)

- LogisticRegression walk-forward avg_accuracy **0.3901**, test 0.4542
- RandomForest walk-forward avg_accuracy **0.4183**, test 0.4557
- **Low confidence <0.35** → mult 0.80 (below wf avg)
- **Fake breakout p>0.50 (label 3)** → mult 0.50 CAUTION whipsaw

## 4. Daily Tightening & Carry (advisory)

- Daily P/L ≥80% of profit/loss limit → flag **ELEVATED** (advisory, no block)
- Carry discouraged when flag CAUTION/ELEVATED or trend <70

## 5. Normalization

- Formula: `vol_mult * hour_mult * conf_mult` clamped **0.50 .. 1.50**
- Flag priority: ELEVATED > CAUTION > REDUCED > NORMAL
- Default state: **OFF / disabled** → `Reset()` neutral

## 6. Files

- Machine JSON: `04_Output/Risk/risk_advisory_report.json`
- MQL advisory: `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextRiskAdvisory.mqh` (dormant, no trading tokens)
- Validation: `01_Source/Tests/test_chief_risk_ai.py` (bounds + flags + no lookahead)

## 7. Required Gates (ADR-0015/0016)

1. Models.db integrity OK (v2, 2 models, 44 contracts, 16 evals)
2. ONNX checker + MT5 load + replay+ONNX PASS (Stages 10–11)
3. Walk-forward PASS (Stage 9)
4. Chief Risk advisory validation PASS (this report)
5. Safety audit 0 forbidden tokens
6. Default OFF, rollback = Reset()
7. Strategy Tester still required for production (future ADR)

No live risk behavior changes — advisory strings only.
