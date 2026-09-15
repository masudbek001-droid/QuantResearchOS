# 02_Databases/Market — Market.db — M1–D1 bar store (Sprint 6A)

Runtime file: MT5 `MQL5\Files\CBEA\Market.db`. Table `Bars` UNIQUE(SymbolID,TimeframeID,OpenTime) + 16 columns (OHLC, spread, UTC/week/month/quarter, Session, DST). Owner: `EAHistory/BarExporter.mqh`.

No database file is stored in the repository: all four are created at runtime by the EA.
Contracts are defined in source (`EAData/`, `EAHistory/`) and in `03_Documents/`.
