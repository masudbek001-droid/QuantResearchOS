# RESTORE GUIDE — copying QuantResearchOS to another PC

## 1. Copy the project

Copy the whole `QuantResearchOS/` folder (it is fully self-contained: sources,
docs, tools, shipped binary). Any archive/USB/git clone of this folder is a
complete restore point. Nothing outside the folder is required.

```
QuantResearchOS/          ← copy this entire folder
```

## 2. Mandatory folders (must exist after the copy)

| Folder | Why |
|---|---|
| `01_Source/` | the only copy of the MQL5 sources — the project itself |
| `03_Documents/` | ADRs, specs, reports, manuals — the engineering memory |
| `04_Output/EX5/` | last verified binary (207,814 bytes, 0/0 compile) |
| `06_Tools/` | build + manual toolchain (Python 3, incl. `mt5setup.exe`) |
| root `*.md` | governance (status, roadmap, principles, agent guide…) |

`02_Databases/`, `07_Backups/` and `08_Archives/` are recommended but not
required to continue development.

## 3. Generated automatically (safe to lose / recreate)

| Path | Recreated by |
|---|---|
| `QuantResearchOS/.build/` | `python3 06_Tools/build.py` (compile staging) |
| `02_Databases/*` runtime `.db` files | the EA/validation tools at runtime, under the MT5 data folder `MQL5\Files\` (`candlebreakout_<magic>.db`, `CBEA_Ticks.db`, `CBEA_Market.db`, `CBEA_Models.db`) — they live with the MT5 installation, not in this repo |
| `04_Output/Logs|Export|Reports|Statistics/` | runtime outputs (logs, CSV journals, reports) |
| `05_Training/*` | generated feature vectors, baseline `.joblib` models, ONNX exports, and metrics; can be regenerated from tools and databases |
| Uzbek manual PDF | `python3 06_Tools/build_manual.py` (needs `pip install pymupdf`) |

## 4. Build environment on the new machine (Linux/Wine recipe)

The compiler is MetaQuotes' MetaEditor64 under Wine; it is **environment**, not
part of the project (deliberately kept outside at `~/.wine`):

```bash
sudo apt-get install -y wine64 xvfb
Xvfb :99 -screen 0 1280x1024x24 &
DISPLAY=:99 wine QuantResearchOS/06_Tools/mt5setup.exe /auto   # silent MT5 install
DISPLAY=:99 wine "C:\\Program Files\\MetaTrader 5\\terminal64.exe" &   # once, seeds data dirs
sleep 15
DISPLAY=:99 python3 QuantResearchOS/06_Tools/build.py          # expect PASS 0/0
```

On Windows the same sources compile directly in MetaEditor 5: copy
`01_Source/EA/MQL5/Experts/...` and `01_Source/EA/MQL5/Include/...` into the
terminal's `MQL5` folder and press F7 — no code changes needed.

## 5. After restore — validation checklist

1. `python3 06_Tools/build.py` → **PASS, 0 errors, 0 warnings**.
2. Binary size ≈ `04_Output/EX5/CandleBreakoutEA.ex5` (207,814 bytes; ±few bytes
   from build timestamps is normal).
3. `PROJECT_STATUS.md` "Last Successful Compile" matches your run — update it.
4. Only then continue with `NEXT_TASK.md`.
