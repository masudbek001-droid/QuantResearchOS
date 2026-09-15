# Database Audit

The source uses MQL5 `DatabaseOpen`/`DatabaseClose` through `SQLiteProvider.mqh`.
The provider closes an owned handle during deinitialization and the manager owns
the provider. Schema, validation and version modules are included in the provider
dependency chain.

Validated runtime stores:

- `candlebreakout_20260909.db` — Research DB, schema v11
- `CBEA_Ticks.db` — raw ticks, 251M+ rows, duplicate-safe resume
- `CBEA_Market.db` — multi-timeframe bars, H1=56,529
- `CBEA_Models.db` — schema v2, 2 registered baseline models, 44 feature-vector
  contracts, 16 evaluation rows

Validation DBs:

- `candlebreakout_905001.db`
- `candlebreakout_906001.db`
- `candlebreakout_907001.db`
- `candlebreakout_911001.db`

Integrity checks passed for the active stores used in Stages 3–14.
