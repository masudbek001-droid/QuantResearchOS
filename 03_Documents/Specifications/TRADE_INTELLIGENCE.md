# TRADE INTELLIGENCE LAYER — schema v3

Implemented by Task 0007 under ADR-0005, on top of the Market Intelligence Database
(schema v2). Purpose: complete trade metadata for **future quantitative research** —
explicitly not reporting, not the CSV journal (which stays untouched).

## 1. Schema

### `Trades` (facts — one row per closed/open trade)

| Group | Columns |
|---|---|
| identity | `TradeID` (PK autoinc), `Ticket` (UNIQUE), `Magic` |
| instrument | `SymbolID` → `Symbols`, `TimeframeID` → `Timeframes` |
| entry | `Direction` (0 buy / 1 sell), `Lots`, `EntryTime`, `EntryPrice`, `EntrySnapshotID` → `MarketSnapshots` |
| exit | `ExitTime`, `ExitPrice`, `ExitSnapshotID` → `MarketSnapshots`, `ExitReason` (ENUM_EXIT_REASON int) |
| result | `Profit` (gross), `Swap`, `Commission`, `NetProfit` (= profit+swap+commission) |
| duration | `TradeDurationSeconds`, `TradeDurationBars` |
| flags | `BreakEvenUsed`, `CarryUsed`, `MomentumUsed`, `ProfitLockUsed` |
| audit | `CreatedAt` |

Exit columns are NULL between `InsertTrade()` and `UpdateTradeExit()`.

### Indexes (STEP 5)

`idx_trade_ticket(Ticket)`, `idx_trade_entry(EntryTime)`, `idx_trade_exit(ExitTime)`,
`idx_trade_dir(Direction)`, `idx_trade_reason(ExitReason)`, `idx_trade_symbol(SymbolID)`.

## 2. Relationships

```
Symbols 1 ── * Trades * ── 1 Timeframes
MarketSnapshots 1 ── * Trades.EntrySnapshotID / Trades.ExitSnapshotID
```

A trade row is a **join point** between trade outcomes and the market state: every trade
knows exactly what the market looked like (all 24 feature columns) at entry and exit.

## 3. Snapshot linkage (STEP 2)

* `EntrySnapshotID` — the newest `MarketSnapshots` row **strictly before the entry bar**:
  the observation the strategy could have known when it entered (no look-ahead).
* `ExitSnapshotID` — the newest snapshot recorded by exit time.
* A missing snapshot rejects the write (validation), so stored rows always have both
  links — the research table never contains un-linkable trades.

## 4. Writer (`CTradeWriter`)

`InsertTrade()` on fill/adoption, `UpdateTradeExit()` through the existing single exit
funnel (`RecordExitOnce`), `ValidateTrade()` shared rule set. No business logic: it
validates and stores what the engine already decided. All SQL goes through
`CDatabaseManager` (DAL reused); reference ids come from the snapshot writer (no
duplicated symbol/timeframe resolution).

## 5. Validation (STEP 4)

Rejected: duplicate `Ticket`, invalid entry time (≤0), invalid exit time (exit<entry),
negative lot, missing snapshot reference, invalid symbol/timeframe reference.
Rejections log a warning; the CSV journal and trading are never affected.

## 6. Future compatibility

* **Replay**: `EntryTime`/`ExitTime` indexed + snapshot links let a replay engine rebuild
  both the market timeline and the exact decision context of every trade.
* **AI**: one row = label (NetProfit, ExitReason, flags) + feature keys (entry/exit
  snapshot ids) — a training set is a two-join SELECT away.
* **Versioning**: further columns arrive as schema v4+ through `ApplyMigration`;
  consumers never rewrite.
