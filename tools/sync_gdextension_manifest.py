#!/usr/bin/env python3
"""Enable/disable entries in gdextension/chess_engine.gdextension based on
which native libraries actually exist in gdextension/bin/.

Godot aborts an export when the manifest references a missing library, but
the game runs fine without one (AIEngine falls back to the GDScript engine).
Run this before exporting — locally and in CI — so every platform always
exports, with native Stockfish wherever a lib has been built:

    python3 tools/sync_gdextension_manifest.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "gdextension" / "chess_engine.gdextension"

# Lines like:  android.release.arm64 = "res://gdextension/bin/lib...so"
ENTRY = re.compile(r'^(#?)\s*([a-z0-9_.]+)\s*=\s*"res://([^"]+)"\s*$')

def main() -> int:
    lines = MANIFEST.read_text().splitlines()
    out, changed = [], []
    in_libraries = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            in_libraries = stripped == "[libraries]"
            out.append(line)
            continue
        m = ENTRY.match(stripped) if in_libraries else None
        if not m:
            out.append(line)
            continue
        commented, key, res_path = m.group(1) == "#", m.group(2), m.group(3)
        exists = (ROOT / res_path).exists()
        if exists and commented:
            out.append('%s = "res://%s"' % (key, res_path))
            changed.append("enabled  " + key)
        elif not exists and not commented:
            out.append('#%s = "res://%s"' % (key, res_path))
            changed.append("disabled " + key)
        else:
            out.append(line)
    MANIFEST.write_text("\n".join(out) + "\n")
    for c in changed:
        print(c)
    print("manifest in sync (%d change%s)" % (len(changed), "" if len(changed) == 1 else "s"))
    return 0

if __name__ == "__main__":
    sys.exit(main())
