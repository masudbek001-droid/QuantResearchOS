# TRADE INTELLIGENCE REPORT — Task 0007 (Phase 1)

## 1. Database version

`DB_SCHEMA_VERSION = 3` (was 2). Chain: fresh files v1 → migrate `1→2` (market
intelligence) → migrate `2→3` (trade intelligence); existing files migrate from whatever
supported version they hold. Every step is transactional and recorded in
`MigrationHistory`.

## 2. Created table — `Trades`

TradeID (PK autoinc) · Ticket (UNIQUE) · SymbolID → Symbols · TimeframeID → Timeframes ·
Magic · Direction (0 buy / 1 sell) · Lots · EntryTime · ExitTime · EntryPrice · ExitPrice ·
Profit (gross) · Swap · Commission · NetProfit (=profit+swap+commission) ·
TradeDurationSeconds · TradeDurationBars · ExitReason (ENUM_EXIT_REASON) ·
BreakEvenUsed · CarryUsed · MomentumUsed · ProfitLockUsed ·
**EntrySnapshotID → MarketSnapshots** · **ExitSnapshotID → MarketSnapshots** · CreatedAt

## 3. Indexes (STEP 5)

`idx_trade_ticket(Ticket)` · `idx_trade_entry(EntryTime)` · `idx_trade_exit(ExitTime)` ·
`idx_trade_dir(Direction)` · `idx_trade_reason(ExitReason)` · `idx_trade_symbol(SymbolID)`

## 4. Snapshot linkage (STEP 2)

* `EntrySnapshotID` = newest snapshot **strictly before the entry bar** (decision-time
  view, no look-ahead). Written by `InsertTrade()`.
* `ExitSnapshotID` = newest snapshot recorded by exit time. Written by
  `UpdateTradeExit()`.
* Missing snapshot ⇒ the write is rejected and logged; stored rows always carry both
  links.

## 5. Trade writer (STEP 3) — `CTradeWriter` (`EAData/TradeWriter.mqh`)

```
bool InsertTrade(ticket,is_buy,lots,entry_time,entry_price,entry_bar);
bool UpdateTradeExit(ticket,entry_time,entry_bar,exit_time,exit_price,
                     profit,swap,commission,exit_reason,
                     be_used,carry_used,momentum_used,pl_used);
bool ValidateTrade(ticket,lots,entry_time,exit_time,entry_snapshot_id);
```

Runtime hooks (all additive): `HandlePositionOpened` and `SyncWithChart` call
`InsertTrade`; the existing single exit funnel `RecordExitOnce` calls `UpdateTradeExit`
with realized components from the new additive reader
`CTradeHistory::DealCostsOfPosition()` (gross/swap/commission; price-difference fallback
kept when history is not booked yet). Flags: `BreakEvenUsed` = BE had a stop,
`CarryUsed` = snapshot carry counter > 0, `MomentumUsed` = reason EXIT_MOMENTUM,
`ProfitLockUsed` = reason EXIT_PROFIT_LOCK.

## 6. Validation rules (STEP 4)

Rejected: duplicate Ticket, invalid entry time (≤0), invalid exit time (exit < entry),
negative lot, missing snapshot reference, invalid symbol/timeframe reference. All
rejections log a warning; trading and the frozen CSV journal never depend on the writer.

## 7. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAData/TradeWriter.mqh` | the trade metadata writer |
| `TRADE_INTELLIGENCE.md` | schema / relationships / linkage / replay & AI compatibility |
| `docs/adr/ADR-0005-trade-intelligence-layer.md` | decision record |

## 8. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 3`, `DB_TABLE_TRADES` |
| `EAData/DatabaseSchema.mqh` | `MigrationToV3(ddl[])` — table + 6 indexes |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` chain `1→2→3` |
| `EAData/MarketSnapshotWriter.mqh` | public `SymbolId()/TimeframeId()` accessors (no duplicated reference resolution) |
| `EATradeHistory.mqh` | +`DealCostsOfPosition()` reader |
| `EATradeManager.mqh` | +include, +`m_trade_writer`, `Initialize` in `Init`, insert hooks in `HandlePositionOpened`/`SyncWithChart`, exit hook in `RecordExitOnce` |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (33 headers), counts (5 428 lines), binary size |

Entry/Exit/BreakEven/Carry/Profit-Lock logic, Feature Builder, MarketSnapshots schema:
untouched.

## 9. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (156 300 B binary).
* Trading/runtime behaviour unchanged — writer sits after existing bookkeeping and only
  adds SQL.
* DAL reused (all SQL via `CDatabaseManager`); Context Layer reused (unchanged, feeds
  the cross-checked snapshots); Feature Builder reused (snapshot source for linkage).
* Trade metadata stored with entry/exit snapshot linkage operational.

**Stop condition honoured:** no Replay, no Event Bus, no AI. Waiting for Task 0008.
