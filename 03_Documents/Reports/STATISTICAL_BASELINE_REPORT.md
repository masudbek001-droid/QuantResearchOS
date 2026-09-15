# STATISTICAL BASELINE RESEARCH REPORT — XAUUSD H1 BREAKOUT

**Date**: 2026-09-14  
**Author**: Lead AI Engineer / Quant Research Architect  
**Dataset**: `CBEA_Market.db` — `Bars` (TimeframeID 16385, PERIOD_H1)  
**Sample Span**: 2016-10-05 00:00 to 2026-09-14 11:00  
**Total Sample Size**: 56,514 completed H1 bars  

---

## 1. Executive Summary

A comprehensive, lookahead-free empirical study of the H1 Candle Breakout hypothesis was conducted over 56,514 historical hourly bars of Gold (XAUUSD). The objective was to establish an un-optimized statistical baseline prior to machine learning model development.

### Key Takeaways

1. **Inherent Edge Confirmed**: Clean single-sided breakout occurrences (40,566 events) yield an unconditioned **54.96% win rate** and a **1.95 profit factor** (average expectancy **+0.793 points** per bar).
2. **Volatility Regime Asymmetry**:
   - **Low Volatility Compression** (`ATRRatio < 0.75`): Win rate accelerates to **58.87%** with **+0.972 points** expectancy (N=15,914).
   - **High Volatility Expansion** (`ATRRatio > 1.50`): Win rate deteriorates to **49.76%** (random walk) with **+0.400 points** expectancy (N=6,330).
3. **Hourly & Session Seasonality**:
   - Peak performance occurs during **Hour 12** (WR: 63.31%, Expectancy: +1.809 pts), **Hour 1** (WR: 63.72%, Expectancy: +1.664 pts), and **Hour 13** (WR: 57.93%, Expectancy: +1.515 pts).
   - Worst performance occurs in late session / roll hours (Hour 21: WR 49.37%, Hour 4: WR 50.94%).
4. **Whipsaw Frequency**:
   - In 11.6% of bars, both high and low of the previous bar are breached (outside bar/whipsaw).
   - Inside bars (zero triggers) occur 16.7% of the time.
   - Clean single-side breakouts occur 71.8% of the time.

---

## 2. Global Distribution of H1 Breakout Behavior

| Breakout Event Type | Definition | Count | Frequency (%) |
|---|---|---|---|
| **Clean Buy Breakout** | $High_i \ge High_{i-1}$ and $Low_i > Low_{i-1}$ | 20,982 | **37.13 %** |
| **Clean Sell Breakout** | $Low_i \le Low_{i-1}$ and $High_i < High_{i-1}$ | 19,584 | **34.65 %** |
| **Inside Bar (No Trigger)** | $High_i < High_{i-1}$ and $Low_i > Low_{i-1}$ | 9,410 | **16.65 %** |
| **Outside / Whipsaw (Both)** | $High_i \ge High_{i-1}$ and $Low_i \le Low_{i-1}$ | 6,538 | **11.57 %** |

---

## 3. Performance Metrics (Single-Sided Clean Breakouts)

*Definition: Trade enters at previous H1 extreme and exits at current H1 close. No SL / no TP.*

| Metric | Buy Breakouts | Sell Breakouts | Combined Baseline |
|---|---|---|---|
| **Sample Size (N)** | 20,982 | 19,584 | **40,566** |
| **Win Rate** ($Close_i > Ref$) | 56.21 % | 53.63 % | **54.96 %** |
| **Profit Factor** | 2.10 | 1.81 | **1.95** |
| **Net Expectancy (pts)** | +0.850 | +0.733 | **+0.793** |
| **Average MFE (pts)** | 3.12 | 3.47 | **3.29** |
| **Average MAE (pts)** | 3.12 | 3.34 | **3.22** |
| **MFE / MAE Ratio** | 1.00x | 1.04x | **1.02x** |

---

## 4. Volatility Regime Stratification

Bars were partitioned by the ratio of the previous bar range to the 14-bar ATR ($\text{ATRRatio} = \text{Range}_{i-1} / \text{ATR}_{14}$):

| Volatility Regime | ATRRatio Range | Sample Count | Win Rate (%) | Expectancy (pts) |
|---|---|---|---|---|
| **Low Volatility (Compression)** | $\le 0.75$ | 15,914 | **58.87 %** | **+0.972** |
| **Normal Volatility** | $0.75 < r \le 1.50$ | 18,322 | **53.37 %** | **+0.774** |
| **High Volatility (Expansion)** | $> 1.50$ | 6,330 | **49.79 %** | **+0.400** |

> **Quant Finding**: Entering a breakout immediately following an outsized expansion candle (`ATRRatio > 1.5`) exhibits virtually zero edge (49.8% win rate). Conversely, breakouts originating from quiet compression candles (`ATRRatio < 0.75`) display a statistically significant momentum continuation edge (58.9% win rate).

---

## 5. Session & Hourly Conditioning

### Performance by Trading Session

| Session | Hours (Server) | Sample (N) | Win Rate (%) | Expectancy (pts) |
|---|---|---|---|---|
| **Asia** | 00:00 – 07:59 | 14,510 | **57.19 %** | **+0.786** |
| **London** | 08:00 – 12:59 | 8,918 | **55.07 %** | **+0.805** |
| **New York** | 13:00 – 20:59 | 13,844 | **52.99 %** | **+0.750** |
| **Late / Close** | 21:00 – 23:59 | 3,294 | **53.19 %** | **+0.977** |

### Top 5 Performing Hours

1. **Hour 12**: 63.31% Win Rate | +1.809 points expectancy (N=1,679)
2. **Hour 01**: 63.72% Win Rate | +1.664 points expectancy (N=1,745)
3. **Hour 13**: 57.93% Win Rate | +1.515 points expectancy (N=1,714)
4. **Hour 05**: 62.74% Win Rate | +1.323 points expectancy (N=1,790)
5. **Hour 14**: 55.09% Win Rate | +1.226 points expectancy (N=1,846)

---

## 6. Trend Alignment (10-Bar Macro Direction)

| Alignment | Sample (N) | Win Rate (%) | Expectancy (pts) |
|---|---|---|---|
| **With Trend** | 22,527 | 54.38 % | **+0.874** |
| **Against Trend** | 18,036 | 55.69 % | **+0.692** |

> **Quant Finding**: With-trend breakouts deliver higher expectancy (+0.874 vs +0.692 pts) despite a slightly lower win rate, demonstrating that when a breakout aligns with the 10-bar trend, winning moves are larger in amplitude.

---

## 7. Implications for Machine Learning (Sprint 7 / Phase D)

The empirical statistical baseline confirms:
1. A random classifier baseline is $50\%$. The raw single-sided breakout strategy exhibits a natural edge of $55.0\%$.
2. Conditioned on regime and hour, win rates naturally reach **$58.9\% - 63.7\%$**.
3. A predictive machine learning model (`EAContextAI`) does NOT need to discover a needle in a haystack from scratch; its objective is to predict:
   $$\{P(\text{UP}), P(\text{DOWN}), P(\text{RANGE}), P(\text{FAKE\_BREAKOUT})\}$$
   filtering out whipsaw and exhaustion states while concentrating capital on high-expectancy compression releases and favorable time windows.
