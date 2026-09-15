#!/usr/bin/env python3
"""
Verify CandleBreakoutEA against the real MetaQuotes compiler.

The sources in ./MQL5 are copied into a genuine MetaTrader 5 data folder and
compiled with MetaEditor64.exe. The script fails unless the compiler reports
0 errors AND 0 warnings AND produces the .ex5 binary.
"""
import os, re, shutil, subprocess, sys, pathlib

ROOT      = pathlib.Path(__file__).resolve().parent.parent   # QuantResearchOS/
SRC_MQL5  = ROOT / "01_Source" / "EA" / "MQL5"
DEFAULT_MT5 = pathlib.Path(r"C:\Program Files\MetaTrader")
MT5_DIR   = pathlib.Path(os.environ.get("QUANTRESEARCHOS_MT5", str(DEFAULT_MT5)))
METAEDITOR= MT5_DIR / "MetaEditor64.exe"
BUILD_DIR = ROOT / ".build"
OUTPUT_EX5 = ROOT / "04_Output" / "EX5" / "CandleBreakoutEA.ex5"

EA_REL    = "Experts/CandleBreakoutEA/CandleBreakoutEA.mq5"
INC_REL   = "Include/CandleBreakoutEA"

ENV = dict(os.environ)


def compiler_path(p: pathlib.Path) -> str:
    return str(p)


def stage() -> pathlib.Path:
    """Mirror the deliverable into a real MT5 data folder (standard library intact)."""
    BUILD_DIR.mkdir(exist_ok=True)

    ea_dst_dir = BUILD_DIR / "Experts/CandleBreakoutEA"
    if ea_dst_dir.exists():
        shutil.rmtree(ea_dst_dir)
    ea_dst_dir.mkdir(parents=True)
    shutil.copy2(SRC_MQL5 / EA_REL, ea_dst_dir / "CandleBreakoutEA.mq5")

    inc_dst = BUILD_DIR / INC_REL
    if inc_dst.exists():
        shutil.rmtree(inc_dst)
    shutil.copytree(SRC_MQL5 / INC_REL, inc_dst)

    # the EA uses <Trade\Trade.mqh>, so the stock library must be present
    std_inc = MT5_DIR / "MQL5" / "Include"
    dst_inc = BUILD_DIR / "Include"
    for item in std_inc.iterdir():
        target = dst_inc / item.name
        if item.name == "CandleBreakoutEA" or target.exists():
            continue
        if item.is_dir():
            shutil.copytree(item, target)
        else:
            shutil.copy2(item, target)
    return BUILD_DIR


def build(data_folder: pathlib.Path) -> int:
    log = data_folder / "compile.log"
    ex5 = data_folder / EA_REL
    for stale in (log, ex5.with_suffix(".ex5")):
        if stale.exists():
            stale.unlink()

    subprocess.run([str(METAEDITOR),
                    f"/inc:{compiler_path(data_folder)}",
                    f"/compile:{compiler_path(data_folder / EA_REL)}",
                    f"/log:{compiler_path(log)}"],
                    env=ENV, cwd=str(METAEDITOR.parent), timeout=600,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=False)

    if not log.exists():
        print("no compiler log produced - MetaEditor did not run")
        return 2

    text = log.read_bytes().decode("utf-16-le", "replace")
    for line in text.splitlines():
        if re.search(r"\s:\s(error|warning)", line):
            print("   " + line.strip())

    m = re.search(r"Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?", text)
    if not m:
        print("could not parse the compiler result:\n" + text[-500:])
        return 2

    errors, warnings = int(m.group(1)), int(m.group(2))
    produced = ex5.with_suffix(".ex5").exists()
    size = ex5.with_suffix(".ex5").stat().st_size if produced else 0
    if produced:
        OUTPUT_EX5.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ex5.with_suffix(".ex5"), OUTPUT_EX5)
    print(f"compiler result : {errors} error(s), {warnings} warning(s)")
    print(f"binary          : {'CandleBreakoutEA.ex5 (' + str(size) + ' bytes)' if produced else 'NOT PRODUCED'}")
    print(f"project output  : {OUTPUT_EX5 if produced else 'NOT PRODUCED'}")
    return 0 if (errors == 0 and warnings == 0 and produced) else 1


if __name__ == "__main__":
    if not METAEDITOR.exists():
        print(f"MetaEditor64.exe not found at {METAEDITOR}")
        sys.exit(2)
    folder = stage()
    print(f"staged into     : {folder}")
    print(f"standard library: {(folder / 'Include/Trade/Trade.mqh').exists()}")
    rc = build(folder)
    print("\nVERDICT:", "PASS - 0 errors, 0 warnings, binary produced" if rc == 0 else "FAIL")
    sys.exit(rc)
