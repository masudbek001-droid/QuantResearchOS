#!/usr/bin/env python3
"""Compile an MQL5 source with the real MetaEditor 64 running under Wine."""
import os, re, subprocess, sys, pathlib

ROOT = pathlib.Path("/home/user")
METAEDITOR = ROOT / ".wine/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe"
ENV = dict(os.environ,
           WINEPREFIX=str(ROOT / ".wine"),
           WINEDEBUG="-all",
           XDG_RUNTIME_DIR="/tmp/runtime-user",
           DISPLAY=os.environ.get("DISPLAY", ":99"))


def win_path(p: pathlib.Path) -> str:
    return "Z:" + str(p).replace("/", "\\")


def compile_file(src: pathlib.Path) -> int:
    log = src.with_suffix(".log")
    ex5 = src.with_suffix(".ex5")
    for stale in (log, ex5):
        if stale.exists():
            stale.unlink()

    subprocess.run(["wine", str(METAEDITOR),
                    f"/inc:{win_path(ROOT / 'MQL5')}",
                    f"/compile:{win_path(src)}", f"/log:{win_path(log)}"],
                   env=ENV, timeout=600, cwd=str(METAEDITOR.parent),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    text = ""
    if log.exists():
        raw = log.read_bytes()
        try:
            text = raw.decode("utf-16-le")
        except UnicodeDecodeError:
            text = raw.decode("latin-1", "replace")
    else:
        print("!! no compiler log produced")
        return 2

    diag = [ln.strip() for ln in text.splitlines()
            if re.search(r"\s:\s(error|warning)", ln)]
    for line in diag:
        print("   " + line.replace("Z:\\home\\user\\MQL5\\", ""))

    m = re.search(r"Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?", text)
    if not m:
        print("!! could not parse the compiler result line")
        print(text[-800:])
        return 2
    errors, warnings = int(m.group(1)), int(m.group(2))
    print(f"==> {src.name}: {errors} error(s), {warnings} warning(s), "
          f".ex5 {'produced' if ex5.exists() else 'MISSING'}")
    return 0 if errors == 0 and warnings == 0 and ex5.exists() else 1


if __name__ == "__main__":
    targets = [pathlib.Path(a) for a in sys.argv[1:]]
    rc = 0
    for t in targets:
        print(f"\n=== compiling {t.name} ===")
        rc |= compile_file(t.resolve())
    print("\nOVERALL:", "CLEAN (0 errors, 0 warnings, binary produced)" if rc == 0 else "FAILED")
    sys.exit(rc)
