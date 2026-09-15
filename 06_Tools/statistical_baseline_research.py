"""
QuantResearchOS — Phase C: Statistical Baseline Analysis Engine
Analyzes the available XAUUSD H1 bar history from CBEA_Market.db.
Quantifies breakout probabilities, win rates, MAE, MFE, expected values,
and conditioning by hour, session, volatility regime, and candle geometry.
"""
import sqlite3
import pandas as pd
import numpy as np
import json
import os
import datetime

MARKET_DB_PATH = r"C:\Program Files\MetaTrader\MQL5\Files\CBEA_Market.db"
OUTPUT_DIR = r"C:\QuantResearchOS\04_Output\Statistics"

def safe_ratio(numerator, denominator):
    return float(numerator / denominator) if denominator and denominator > 0 else 0.0

def safe_mean(series):
    return float(series.mean()) if len(series) > 0 else 0.0

def load_h1_data():
    conn = sqlite3.connect(MARKET_DB_PATH)
    # TimeframeID 16385 is PERIOD_H1
    query = """
    SELECT OpenTime, Open, High, Low, Close, TickVolume, Spread
    FROM Bars
    WHERE TimeframeID = 16385
    ORDER BY OpenTime ASC
    """
    df = pd.read_sql_query(query, conn)
    conn.close()
    
    df['Datetime'] = pd.to_datetime(df['OpenTime'], unit='s')
    df['Hour'] = df['Datetime'].dt.hour
    df['Weekday'] = df['Datetime'].dt.weekday # 0=Mon, 4=Fri
    df['Month'] = df['Datetime'].dt.month
    return df

def calculate_features_and_outcomes(df):
    # 1. Previous bar metrics (Bar i-1)
    df['Prev_Open'] = df['Open'].shift(1)
    df['Prev_High'] = df['High'].shift(1)
    df['Prev_Low'] = df['Low'].shift(1)
    df['Prev_Close'] = df['Close'].shift(1)
    df['Prev_Range'] = df['Prev_High'] - df['Prev_Low']
    df['Prev_Body'] = (df['Prev_Close'] - df['Prev_Open']).abs()
    df['Prev_BodyPct'] = np.where(df['Prev_Range'] > 0, (df['Prev_Body'] / df['Prev_Range']) * 100.0, 0.0)
    df['Prev_UpperShadow'] = df['Prev_High'] - np.maximum(df['Prev_Open'], df['Prev_Close'])
    df['Prev_LowerShadow'] = np.minimum(df['Prev_Open'], df['Prev_Close']) - df['Prev_Low']
    df['Prev_Bullish'] = df['Prev_Close'] > df['Prev_Open']
    
    # ATR 14 of completed bars
    tr = np.maximum(df['High'] - df['Low'],
                    np.maximum((df['High'] - df['Close'].shift(1)).abs(),
                               (df['Low'] - df['Close'].shift(1)).abs()))
    df['ATR14'] = tr.rolling(14).mean().shift(1)
    df['Prev_ATRRatio'] = np.where(df['ATR14'] > 0, df['Prev_Range'] / df['ATR14'], 1.0)
    
    # Trend 10 bars
    df['Trend10'] = np.sign(df['Close'].shift(1) - df['Close'].shift(11))
    
    # Volatility Regimes
    df['Vol_Regime'] = pd.cut(df['Prev_ATRRatio'], bins=[-np.inf, 0.75, 1.5, np.inf], labels=['Low', 'Normal', 'High'])
    
    # Sessions (approximate server hours)
    # Asia: 0..7, London: 8..15, New York: 13..21
    def get_session(h):
        if 0 <= h < 8:
            return 'Asia'
        elif 8 <= h < 13:
            return 'London'
        elif 13 <= h < 21:
            return 'NewYork'
        else:
            return 'Close/Late'
    df['Session'] = df['Hour'].apply(get_session)
    
    # 2. Breakout Trigger Classification on Bar i
    # Trigger conditions
    df['Trigger_Buy'] = df['High'] >= df['Prev_High']
    df['Trigger_Sell'] = df['Low'] <= df['Prev_Low']
    
    conditions = [
        (~df['Trigger_Buy'] & ~df['Trigger_Sell']),
        (df['Trigger_Buy'] & ~df['Trigger_Sell']),
        (~df['Trigger_Buy'] & df['Trigger_Sell']),
        (df['Trigger_Buy'] & df['Trigger_Sell'])
    ]
    choices = ['INSIDE', 'BUY_ONLY', 'SELL_ONLY', 'OUTSIDE_WHIPSAW']
    df['Breakout_Type'] = np.select(conditions, choices, default='UNKNOWN')
    
    # 3. Outcomes for Buy Breakouts
    # If Buy triggered first or only:
    # Win condition: Close > Prev_High
    df['Buy_Win'] = df['Close'] > df['Prev_High']
    df['Buy_Profit'] = df['Close'] - df['Prev_High']
    df['Buy_MFE'] = df['High'] - df['Prev_High']
    df['Buy_MAE'] = df['Prev_High'] - df['Low']
    
    # 4. Outcomes for Sell Breakouts
    # If Sell triggered:
    # Win condition: Close < Prev_Low
    df['Sell_Win'] = df['Close'] < df['Prev_Low']
    df['Sell_Profit'] = df['Prev_Low'] - df['Close']
    df['Sell_MFE'] = df['Prev_Low'] - df['Low']
    df['Sell_MAE'] = df['High'] - df['Prev_Low']
    
    # Clean initial NaN rows (warmup period 15 bars)
    df_clean = df.iloc[15:].copy()
    return df_clean

def run_analysis(df):
    total_bars = len(df)
    print(f"Total analyzed H1 bars: {total_bars:,}")
    
    # --- 1. Global Breakout Distribution ---
    type_counts = df['Breakout_Type'].value_counts()
    type_pcts = (type_counts / total_bars) * 100.0
    
    dist_report = {
        'TotalBars': int(total_bars),
        'InsideBar_Pct': float(type_pcts.get('INSIDE', 0)),
        'BuyOnly_Pct': float(type_pcts.get('BUY_ONLY', 0)),
        'SellOnly_Pct': float(type_pcts.get('SELL_ONLY', 0)),
        'OutsideWhipsaw_Pct': float(type_pcts.get('OUTSIDE_WHIPSAW', 0))
    }
    
    # --- 2. Buy Breakouts (Single Side Triggered) ---
    buy_only = df[df['Breakout_Type'] == 'BUY_ONLY']
    buy_count = len(buy_only)
    buy_win_rate = (buy_only['Buy_Win'].sum() / buy_count) * 100.0 if buy_count > 0 else 0
    buy_ev = safe_mean(buy_only['Buy_Profit'])
    buy_mfe = safe_mean(buy_only['Buy_MFE'])
    buy_mae = safe_mean(buy_only['Buy_MAE'])
    buy_gross_win = buy_only[buy_only['Buy_Profit'] > 0]['Buy_Profit'].sum()
    buy_gross_loss = -buy_only[buy_only['Buy_Profit'] < 0]['Buy_Profit'].sum()
    buy_pf = safe_ratio(buy_gross_win, buy_gross_loss)
    
    # --- 3. Sell Breakouts (Single Side Triggered) ---
    sell_only = df[df['Breakout_Type'] == 'SELL_ONLY']
    sell_count = len(sell_only)
    sell_win_rate = (sell_only['Sell_Win'].sum() / sell_count) * 100.0 if sell_count > 0 else 0
    sell_ev = safe_mean(sell_only['Sell_Profit'])
    sell_mfe = safe_mean(sell_only['Sell_MFE'])
    sell_mae = safe_mean(sell_only['Sell_MAE'])
    sell_gross_win = sell_only[sell_only['Sell_Profit'] > 0]['Sell_Profit'].sum()
    sell_gross_loss = -sell_only[sell_only['Sell_Profit'] < 0]['Sell_Profit'].sum()
    sell_pf = safe_ratio(sell_gross_win, sell_gross_loss)
    
    # Combined Clean Single-Side Breakouts
    clean_trades = pd.concat([
        pd.DataFrame({'Win': buy_only['Buy_Win'], 'Profit': buy_only['Buy_Profit'], 'MFE': buy_only['Buy_MFE'], 'MAE': buy_only['Buy_MAE'], 'Side': 'BUY'}),
        pd.DataFrame({'Win': sell_only['Sell_Win'], 'Profit': sell_only['Sell_Profit'], 'MFE': sell_only['Sell_MFE'], 'MAE': sell_only['Sell_MAE'], 'Side': 'SELL'})
    ])
    total_clean = len(clean_trades)
    clean_win_rate = safe_ratio(clean_trades['Win'].sum(), total_clean) * 100.0
    clean_ev = safe_mean(clean_trades['Profit'])
    gross_win = clean_trades[clean_trades['Profit'] > 0]['Profit'].sum()
    gross_loss = -clean_trades[clean_trades['Profit'] < 0]['Profit'].sum()
    clean_pf = safe_ratio(gross_win, gross_loss)
    clean_mfe = safe_mean(clean_trades['MFE'])
    clean_mae = safe_mean(clean_trades['MAE'])
    
    # --- 4. Conditioning by Hour of Day ---
    hour_stats = []
    for h in range(24):
        hdf = df[(df['Hour'] == h) & (df['Breakout_Type'].isin(['BUY_ONLY', 'SELL_ONLY']))]
        if len(hdf) == 0:
            continue
        h_buys = hdf[hdf['Breakout_Type'] == 'BUY_ONLY']
        h_sells = hdf[hdf['Breakout_Type'] == 'SELL_ONLY']
        h_wins = h_buys['Buy_Win'].sum() + h_sells['Sell_Win'].sum()
        h_net = h_buys['Buy_Profit'].sum() + h_sells['Sell_Profit'].sum()
        h_wr = (h_wins / len(hdf)) * 100.0
        h_ev = h_net / len(hdf)
        hour_stats.append({
            'Hour': h,
            'Count': len(hdf),
            'WinRate': round(h_wr, 2),
            'Expectancy': round(h_ev, 3)
        })
    df_hour = pd.DataFrame(hour_stats)
    
    # --- 5. Conditioning by Session ---
    session_stats = []
    for sess in ['Asia', 'London', 'NewYork', 'Close/Late']:
        sdf = df[(df['Session'] == sess) & (df['Breakout_Type'].isin(['BUY_ONLY', 'SELL_ONLY']))]
        if len(sdf) == 0:
            continue
        s_buys = sdf[sdf['Breakout_Type'] == 'BUY_ONLY']
        s_sells = sdf[sdf['Breakout_Type'] == 'SELL_ONLY']
        s_wins = s_buys['Buy_Win'].sum() + s_sells['Sell_Win'].sum()
        s_net = s_buys['Buy_Profit'].sum() + s_sells['Sell_Profit'].sum()
        session_stats.append({
            'Session': sess,
            'Count': len(sdf),
            'WinRate': round((s_wins / len(sdf)) * 100.0, 2),
            'Expectancy': round(s_net / len(sdf), 3)
        })
    df_session = pd.DataFrame(session_stats)
    
    # --- 6. Conditioning by Volatility Regime ---
    vol_stats = []
    for reg in ['Low', 'Normal', 'High']:
        vdf = df[(df['Vol_Regime'] == reg) & (df['Breakout_Type'].isin(['BUY_ONLY', 'SELL_ONLY']))]
        if len(vdf) == 0:
            continue
        v_buys = vdf[vdf['Breakout_Type'] == 'BUY_ONLY']
        v_sells = vdf[vdf['Breakout_Type'] == 'SELL_ONLY']
        v_wins = v_buys['Buy_Win'].sum() + v_sells['Sell_Win'].sum()
        v_net = v_buys['Buy_Profit'].sum() + v_sells['Sell_Profit'].sum()
        vol_stats.append({
            'Regime': reg,
            'Count': len(vdf),
            'WinRate': round((v_wins / len(vdf)) * 100.0, 2),
            'Expectancy': round(v_net / len(vdf), 3)
        })
    df_vol = pd.DataFrame(vol_stats)
    
    # --- 7. Conditioning by Trend Alignment ---
    trend_stats = []
    # Buy with trend (Trend10 > 0) vs against trend
    b_with = df[(df['Breakout_Type'] == 'BUY_ONLY') & (df['Trend10'] > 0)]
    b_against = df[(df['Breakout_Type'] == 'BUY_ONLY') & (df['Trend10'] < 0)]
    s_with = df[(df['Breakout_Type'] == 'SELL_ONLY') & (df['Trend10'] < 0)]
    s_against = df[(df['Breakout_Type'] == 'SELL_ONLY') & (df['Trend10'] > 0)]
    
    with_trend_count = len(b_with) + len(s_with)
    with_trend_wins = b_with['Buy_Win'].sum() + s_with['Sell_Win'].sum()
    with_trend_net = b_with['Buy_Profit'].sum() + s_with['Sell_Profit'].sum()
    
    against_trend_count = len(b_against) + len(s_against)
    against_trend_wins = b_against['Buy_Win'].sum() + s_against['Sell_Win'].sum()
    against_trend_net = b_against['Buy_Profit'].sum() + s_against['Sell_Profit'].sum()
    
    trend_stats.append({
        'Alignment': 'WITH_TREND',
        'Count': with_trend_count,
        'WinRate': round((with_trend_wins / with_trend_count) * 100.0, 2),
        'Expectancy': round(with_trend_net / with_trend_count, 3)
    })
    trend_stats.append({
        'Alignment': 'AGAINST_TREND',
        'Count': against_trend_count,
        'WinRate': round((against_trend_wins / against_trend_count) * 100.0, 2),
        'Expectancy': round(against_trend_net / against_trend_count, 3)
    })
    df_trend = pd.DataFrame(trend_stats)
    
    # Assemble comprehensive result dictionary
    summary = {
        'TotalBars': total_bars,
        'DateRange': f"{df['Datetime'].min()} to {df['Datetime'].max()}",
        'BreakoutDistribution': dist_report,
        'SingleSideBreakoutOverall': {
            'Count': int(total_clean),
            'ShareOfAllBars': round(float(total_clean / total_bars * 100.0), 2),
            'WinRate': round(float(clean_win_rate), 2),
            'ExpectancyPoints': round(float(clean_ev), 3),
            'ProfitFactor': round(float(clean_pf), 3),
            'AverageMFE': round(float(clean_trades['MFE'].mean()), 3),
            'AverageMAE': round(float(clean_trades['MAE'].mean()), 3),
        'MFE_to_MAE_Ratio': round(safe_ratio(clean_mfe, clean_mae), 3)
        },
        'BuyBreakouts': {
            'Count': int(buy_count),
            'WinRate': round(float(buy_win_rate), 2),
            'ExpectancyPoints': round(float(buy_ev), 3),
            'ProfitFactor': round(float(buy_pf), 3),
            'AvgMFE': round(float(buy_mfe), 3),
            'AvgMAE': round(float(buy_mae), 3)
        },
        'SellBreakouts': {
            'Count': int(sell_count),
            'WinRate': round(float(sell_win_rate), 2),
            'ExpectancyPoints': round(float(sell_ev), 3),
            'ProfitFactor': round(float(sell_pf), 3),
            'AvgMFE': round(float(sell_mfe), 3),
            'AvgMAE': round(float(sell_mae), 3)
        },
        'SessionStats': session_stats,
        'VolRegimeStats': vol_stats,
        'TrendAlignmentStats': trend_stats,
        'HourlyTopHours': df_hour.sort_values('Expectancy', ascending=False).to_dict(orient='records')
    }
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    json_path = os.path.join(OUTPUT_DIR, "statistical_baseline_report.json")
    with open(json_path, "w") as f:
        json.dump(summary, f, indent=2)
        
    print("\n" + "="*70)
    print("STATISTICAL BASELINE SUMMARY (XAUUSD H1)")
    print("="*70)
    print(f"Analyzed Bars: {total_bars:,} ({summary['DateRange']})")
    print(f"\n1. Bar Breakout Behavior:")
    print(f"   - Inside Bars (No trigger)  : {dist_report['InsideBar_Pct']:.1f}%")
    print(f"   - Clean Buy Breakouts       : {dist_report['BuyOnly_Pct']:.1f}%")
    print(f"   - Clean Sell Breakouts      : {dist_report['SellOnly_Pct']:.1f}%")
    print(f"   - Outside/Whipsaw (Both)    : {dist_report['OutsideWhipsaw_Pct']:.1f}%")
    print(f"\n2. Clean Single-Side Breakouts (Sample: {total_clean:,} trades):")
    print(f"   - Win Rate (Close beyond ref): {clean_win_rate:.2f}%")
    print(f"   - Expectancy (Raw Points)    : {clean_ev:.3f}")
    print(f"   - Profit Factor              : {clean_pf:.2f}")
    print(f"   - Avg MFE                    : {clean_mfe:.2f}")
    print(f"   - Avg MAE                    : {clean_mae:.2f}")
    print(f"   - MFE / MAE Ratio            : {safe_ratio(clean_mfe, clean_mae):.2f}x")
    print(f"\n3. Trend Alignment Impact:")
    for t in trend_stats:
        print(f"   - {t['Alignment']:<14}: WR = {t['WinRate']:.1f}%, Expectancy = {t['Expectancy']:+.3f} pts (N={t['Count']:,})")
    print(f"\n4. Session Conditioning:")
    for s in session_stats:
        print(f"   - {s['Session']:<10}: WR = {s['WinRate']:.1f}%, Expectancy = {s['Expectancy']:+.3f} pts (N={s['Count']:,})")
    print(f"\n5. Volatility Regime Conditioning:")
    for v in vol_stats:
        print(f"   - {v['Regime']:<10}: WR = {v['WinRate']:.1f}%, Expectancy = {v['Expectancy']:+.3f} pts (N={v['Count']:,})")
    print("="*70)
    print(f"Saved full JSON to: {json_path}")
    return summary

if __name__ == "__main__":
    df = load_h1_data()
    df_features = calculate_features_and_outcomes(df)
    run_analysis(df_features)
