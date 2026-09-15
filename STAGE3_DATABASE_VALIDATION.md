# Stage 3 Database Validation

## Current evidence — 2026-09-14

Validated directly against the active MetaTrader data folder:

| Database | SQLite integrity | Foreign keys | Schema |
|---|---:|---:|---:|
| `candlebreakout_20260909.db` | PASS (`ok`) | PASS (`0`) | v11 |
| `CBEA_Market.db` | PASS (`ok`) | PASS (`0`) | v11 |
| `CBEA_Models.db` | PASS (`ok`) | PASS (`0`) | v11 |

The 40 GB `CBEA_Ticks.db` full integrity scan completed successfully:

| Check | Result |
|---|---:|
| SQLite integrity | PASS (`ok`) |
| Foreign keys | PASS (`0`) |
| Tick rows | 251,334,035 |
| Transaction probe | PASS |
| Stage 2 duplicate/invalid/out-of-order checks | PASS (`0/0/0`) |

The export was re-opened after terminal restart and produced the official Stage 2
`STATUS=PASS` report. Stage 3 database validation is therefore CLOSED.

## Final status

`STAGE3=PASS`  
`DATABASE_VALIDATION=PASS`  
`STATUS=CLOSED`
