# Project Manifest

Root: `C:\QuantResearchOS`

Active MetaTrader installation: `C:\Program Files\MetaTrader`

Active MQL5 tree: `C:\Program Files\MetaTrader\MQL5`

Primary source: `C:\QuantResearchOS\01_Source\EA\MQL5`

Build tool: `C:\QuantResearchOS\06_Tools\build.py`

Compiler: `C:\Program Files\MetaTrader\MetaEditor64.exe`

Primary EA output:

- Project: `C:\QuantResearchOS\04_Output\EX5\CandleBreakoutEA.ex5`
- Active MT5: `C:\Program Files\MetaTrader\MQL5\Experts\CandleBreakoutEA\CandleBreakoutEA.ex5`

Runtime databases:

- `C:\Program Files\MetaTrader\MQL5\Files\candlebreakout_20260909.db`
- `C:\Program Files\MetaTrader\MQL5\Files\CBEA_Ticks.db`
- `C:\Program Files\MetaTrader\MQL5\Files\CBEA_Market.db`
- `C:\Program Files\MetaTrader\MQL5\Files\CBEA_Models.db`

Validation databases:

- `candlebreakout_905001.db`
- `candlebreakout_906001.db`
- `candlebreakout_907001.db`
- `candlebreakout_911001.db`

Current rule:

Never treat a temporary Codex workspace as project source. All durable changes
must be made under `C:\QuantResearchOS` and synchronized to the active MetaTrader
installation when required.
