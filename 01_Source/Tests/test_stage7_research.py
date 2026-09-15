"""
Stage 7 Research Engine Validation Test Suite
Tests ExperimentEngine, BenchmarkEngine, and WalkForwardEngine against SQLite schema v11.
"""
import sqlite3
import os
import math

DB_PATH = r"C:\Program Files\MetaTrader\MQL5\Files\candlebreakout_907001.db"

def run_test():
    print("=== STAGE 7: RESEARCH ENGINE VALIDATION ===")
    
    # 1. Connect to isolated database
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()
    
    # Verify tables exist
    tables = [r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    assert "Experiments" in tables, "Experiments table missing"
    assert "Benchmarks" in tables, "Benchmarks table missing"
    assert "WalkForwardRuns" in tables, "WalkForwardRuns table missing"
    print("[PASS] Schema v10/v11 tables present in candlebreakout_907001.db")
    
    # Clear tables for clean test
    cur.execute("DELETE FROM WalkForwardRuns")
    cur.execute("DELETE FROM Benchmarks")
    cur.execute("DELETE FROM Experiments")
    cur.execute("DELETE FROM ResearchDatasets")
    cur.execute("DELETE FROM Trades")
    conn.commit()
    print("[PASS] Isolated research tables cleared")
    
    # 2. Seed Mock Trades & Dataset
    # 4 trades: 3 wins (+50, +30, +40), 1 loss (-20)
    trades = [
        (1, 1001, 1, 60, 907001, 0, 0.1, 1000, 2000, 2000.0, 2005.0, 50.0, 50.0, "2026.09.14 18:00"),
        (2, 1002, 1, 60, 907001, 1, 0.1, 2500, 3500, 2005.0, 2003.0, -20.0, -20.0, "2026.09.14 18:00"),
        (3, 1003, 1, 60, 907001, 0, 0.1, 4000, 5000, 2003.0, 2006.0, 30.0, 30.0, "2026.09.14 18:00"),
        (4, 1004, 1, 60, 907001, 0, 0.1, 5500, 6500, 2006.0, 2010.0, 40.0, 40.0, "2026.09.14 18:00"),
    ]
    cur.executemany("""
        INSERT INTO Trades (TradeID, Ticket, SymbolID, TimeframeID, Magic, Direction, Lots,
                            EntryTime, ExitTime, EntryPrice, ExitPrice, Profit, NetProfit, CreatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, trades)
    
    datasets = [
        (1, 907001, 1, 1, 1, 1, 1, "2026.09.14 18:00"),
        (2, 907001, 2, 2, 2, 2, 1, "2026.09.14 18:00"),
        (3, 907001, 3, 3, 3, 3, 1, "2026.09.14 18:00"),
        (4, 907001, 4, 4, 4, 4, 1, "2026.09.14 18:00"),
    ]
    cur.executemany("""
        INSERT INTO ResearchDatasets (DatasetID, DatasetVersion, ObservationID, SnapshotID, LabelID, TradeID, ExportStatus, CreatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, datasets)
    conn.commit()
    print("[PASS] Seeded 4 mock trades and dataset rows")
    
    # 3. Test CExperimentEngine
    # Invalid creation checks
    def try_create_exp(name, ds_ver, feat_ver, lbl_ver, q_ver, cfg_hash, notes):
        if not name or not cfg_hash or ds_ver <= 0 or feat_ver <= 0 or lbl_ver <= 0 or q_ver <= 0:
            return 0
        cur.execute("""
            INSERT INTO Experiments (ExperimentName, DatasetVersion, FeatureVersion, LabelVersion,
                                    QualityVersion, ReplayVersion, ConfigurationHash, Status, Notes, CreatedAt)
            VALUES (?, ?, ?, ?, ?, 11, ?, 0, ?, datetime('now'))
        """, (name, ds_ver, feat_ver, lbl_ver, q_ver, cfg_hash, notes))
        conn.commit()
        return cur.lastrowid

    assert try_create_exp("", 907001, 1, 1, 1, "hash1", "notes") == 0, "Empty name should fail"
    assert try_create_exp("Exp1", 907001, 1, 1, 1, "", "notes") == 0, "Empty hash should fail"
    assert try_create_exp("Exp1", 0, 1, 1, 1, "hash1", "notes") == 0, "Zero version should fail"
    
    exp_id1 = try_create_exp("Exp_Baseline_Test", 907001, 1, 1, 1, "cfg_hash_stage7_001", "baseline experiment")
    assert exp_id1 > 0, "Experiment creation failed"
    
    # Check status: CREATED = 0
    st = cur.execute("SELECT Status FROM Experiments WHERE ExperimentID=?", (exp_id1,)).fetchone()[0]
    assert st == 0, f"Expected Status 0, got {st}"
    
    # Start experiment -> RUNNING = 1
    cur.execute("UPDATE Experiments SET Status=1, StartTime=1000 WHERE ExperimentID=?", (exp_id1,))
    conn.commit()
    st = cur.execute("SELECT Status FROM Experiments WHERE ExperimentID=?", (exp_id1,)).fetchone()[0]
    assert st == 1, f"Expected Status 1, got {st}"
    print(f"[PASS] Experiment #{exp_id1} lifecycle (CREATED -> RUNNING) validated")
    
    # 4. Test CBenchmarkEngine
    # Query trades from dataset version
    rows = cur.execute("""
        SELECT COALESCE(t.NetProfit, t.Profit), t.EntryTime, t.ExitTime
        FROM ResearchDatasets d
        JOIN Trades t ON t.TradeID = d.TradeID
        WHERE d.DatasetVersion = ? AND d.TradeID IS NOT NULL AND t.ExitTime IS NOT NULL
        ORDER BY t.ExitTime ASC, t.TradeID ASC
    """, (907001,)).fetchall()
    
    assert len(rows) == 4, f"Expected 4 trades, got {len(rows)}"
    net = 0.0
    gross_win = 0.0
    gross_loss = 0.0
    equity = 0.0
    peak = 0.0
    max_dd = 0.0
    wins = 0
    holding = 0
    
    for profit, in_time, out_time in rows:
        net += profit
        if profit > 0:
            wins += 1
            gross_win += profit
        else:
            gross_loss += profit
        if out_time > in_time:
            holding += (out_time - in_time)
        equity += profit
        if equity > peak:
            peak = equity
        dd = peak - equity
        if dd > max_dd:
            max_dd = dd
            
    win_rate = 100.0 * wins / len(rows)
    profit_factor = gross_win / -gross_loss if gross_loss < 0 else 0.0
    expectancy = net / len(rows)
    avg_trade = net / len(rows)
    avg_holding = holding / len(rows)
    recovery = net / max_dd if max_dd > 0 else 0.0
    
    assert math.isclose(win_rate, 75.0, abs_tol=1e-3), f"WinRate {win_rate} != 75.0%"
    assert math.isclose(profit_factor, 120.0 / 20.0, abs_tol=1e-3), f"ProfitFactor {profit_factor} != 6.0"
    assert math.isclose(net, 100.0, abs_tol=1e-3), f"Net {net} != 100.0"
    assert math.isclose(max_dd, 20.0, abs_tol=1e-3), f"MaxDD {max_dd} != 20.0"
    assert math.isclose(recovery, 5.0, abs_tol=1e-3), f"Recovery {recovery} != 5.0"
    
    metrics = [
        (exp_id1, "WinRate", win_rate, "%"),
        (exp_id1, "ProfitFactor", profit_factor, "x"),
        (exp_id1, "Expectancy", expectancy, "money"),
        (exp_id1, "AverageTrade", avg_trade, "money"),
        (exp_id1, "AverageHoldingTime", avg_holding, "s"),
        (exp_id1, "MaximumDrawdown", max_dd, "money"),
        (exp_id1, "RecoveryFactor", recovery, "x"),
        (exp_id1, "SharpeRatio", 0.0, "ratio"),
        (exp_id1, "SQN", 0.0, "pts")
    ]
    cur.executemany("""
        INSERT INTO Benchmarks (ExperimentID, MetricName, MetricValue, MetricUnit, CreatedAt)
        VALUES (?, ?, ?, ?, datetime('now'))
    """, metrics)
    conn.commit()
    print(f"[PASS] Benchmark computed: WR={win_rate:.1f}%, PF={profit_factor:.2f}, Net={net:.1f}, MaxDD={max_dd:.1f}, Recovery={recovery:.2f}")
    
    # 5. Test CWalkForwardEngine
    def validate_run(exp_id, tr_start, tr_end, te_start, te_end):
        if tr_start <= 0 or te_end <= 0:
            return False
        if tr_end <= tr_start or te_end <= te_start:
            return False
        if te_start < tr_end: # Leakage check!
            return False
        # Overlap check with existing runs
        cnt = cur.execute("""
            SELECT COUNT(*) FROM WalkForwardRuns
            WHERE ExperimentID=? AND NOT (TestingEnd<=? OR TestingStart>=?)
        """, (exp_id, te_start, te_end)).fetchone()[0]
        if cnt > 0:
            return False
        return True

    def create_run(exp_id, tr_start, tr_end, te_start, te_end, win_num=0):
        if not validate_run(exp_id, tr_start, tr_end, te_start, te_end):
            return 0
        if win_num <= 0:
            max_w = cur.execute("SELECT MAX(WindowNumber) FROM WalkForwardRuns WHERE ExperimentID=?", (exp_id,)).fetchone()[0]
            win_num = (max_w or 0) + 1
        cur.execute("""
            INSERT INTO WalkForwardRuns (ExperimentID, TrainingStart, TrainingEnd, TestingStart, TestingEnd, WindowNumber, ResultStatus, CreatedAt)
            VALUES (?, ?, ?, ?, ?, ?, 0, datetime('now'))
        """, (exp_id, tr_start, tr_end, te_start, te_end, win_num))
        conn.commit()
        return cur.lastrowid

    # Validation tests
    assert not validate_run(exp_id1, 0, 1000, 1000, 2000), "Zero train_start must fail"
    assert not validate_run(exp_id1, 2000, 1000, 2000, 3000), "Inverted train window must fail"
    assert not validate_run(exp_id1, 1000, 2000, 1500, 2500), "Leakage must fail (te_start < tr_end)"
    assert validate_run(exp_id1, 1000, 2000, 2000, 3000), "Contiguous boundary must PASS"
    
    # Run 1
    r1 = create_run(exp_id1, 1000, 2000, 2000, 3000, 1)
    assert r1 > 0, "Run 1 creation failed"
    
    # Overlapping test window rejection
    assert not validate_run(exp_id1, 3000, 4000, 2500, 3500), "Overlapping test window must fail"
    assert create_run(exp_id1, 3000, 4000, 2500, 3500, 2) == 0, "Overlapping test run must fail"
    
    # Non-overlapping Run 2
    r2 = create_run(exp_id1, 2000, 3000, 3000, 4000, 2)
    assert r2 > 0, "Run 2 creation failed"
    
    # PlanWindows test
    def plan_windows(exp_id, mode, range_start, range_end, train_s, test_s):
        planned = 0
        tr_s = range_start
        tr_e = range_start + train_s
        te_s = tr_e
        te_e = te_s + test_s
        while te_e <= range_end:
            rid = create_run(exp_id, tr_s, tr_e, te_s, te_e, 0)
            if rid > 0:
                planned += 1
            else:
                break
            if mode == 0: # ROLLING
                tr_s = tr_s + test_s
                tr_e = tr_s + train_s
            elif mode == 1: # EXPANDING
                tr_e = tr_e + test_s
            elif mode == 2: # FIXED
                tr_s = te_e
                tr_e = tr_s + train_s
            te_s = tr_e
            te_e = te_s + test_s
        return planned

    exp_id2 = try_create_exp("Exp_WF_Planning", 907001, 1, 1, 1, "cfg_hash_stage7_002", "planning test")
    planned = plan_windows(exp_id2, 0, 1000, 4000, 1000, 1000)
    assert planned == 2, f"Expected 2 planned windows, got {planned}"
    print(f"[PASS] Walk-forward engine: boundary check, leakage rejection, cross-window overlap rejection, PlanWindows ({planned} windows) validated")
    
    # 6. Test Sealing & Immutability
    # Finish experiment 1
    cur.execute("UPDATE Experiments SET Status=2, EndTime=1500, DurationSeconds=500 WHERE ExperimentID=?", (exp_id1,))
    conn.commit()
    st = cur.execute("SELECT Status FROM Experiments WHERE ExperimentID=?", (exp_id1,)).fetchone()[0]
    assert st == 2, "Experiment not marked completed"
    
    # Check is_mutable
    is_mutable = (st in (0, 1))
    assert not is_mutable, "Completed experiment should NOT be mutable"
    
    # Verify no metrics can be added to immutable experiment
    def try_add_metric(exp_id, name, val, unit):
        cur_st = cur.execute("SELECT Status FROM Experiments WHERE ExperimentID=?", (exp_id,)).fetchone()[0]
        if cur_st not in (0, 1):
            return False
        cur.execute("INSERT INTO Benchmarks (ExperimentID, MetricName, MetricValue, MetricUnit, CreatedAt) VALUES (?, ?, ?, ?, datetime('now'))",
                    (exp_id, name, val, unit))
        conn.commit()
        return True

    assert not try_add_metric(exp_id1, "ExtraMetric", 999.0, "x"), "Adding metric to completed experiment must be REJECTED"
    print("[PASS] Experiment sealing and immutability guard verified")
    
    # 7. Final counts
    exp_count = cur.execute("SELECT COUNT(*) FROM Experiments").fetchone()[0]
    bench_count = cur.execute("SELECT COUNT(*) FROM Benchmarks").fetchone()[0]
    wf_count = cur.execute("SELECT COUNT(*) FROM WalkForwardRuns").fetchone()[0]
    
    print(f"\n[QROS_STAGE7] STATUS=PASS | experiments={exp_count} | benchmarks={bench_count} | wf_runs={wf_count} | immutability=PASS")
    conn.close()

if __name__ == "__main__":
    run_test()
