# 02_Databases/Ticks — Ticks.db — raw tick store (Sprint 6A)

Runtime file: MT5 `MQL5\Files\CBEA\Ticks.db`. Table `Ticks` UNIQUE(SymbolID,BrokerTime,Milliseconds,Bid,Ask), INSERT OR IGNORE; local Symbols/Timeframes masters; `MarketMetadata` (sessions, offset, DST, contract). Owner: `EAHistory/HistoryStore.mqh` + `TickExporter.mqh`.

No database file is stored in the repository: all four are created at runtime by the EA.
Contracts are defined in source (`EAData/`, `EAHistory/`) and in `03_Documents/`.
