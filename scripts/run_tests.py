#!/usr/bin/env python3
"""Bundles the shared/server logic modules into the Luau test harness and runs it with the Luau CLI.

Usage: python3 scripts/run_tests.py            (uses `luau` from PATH, or the LUAU env var)
"""
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULE_DIRS = ["src/shared", "src/server/Modules"]

def main() -> int:
    sources = {}
    for rel in MODULE_DIRS:
        for path in sorted((ROOT / rel).glob("*.luau")):
            key = f"{rel}/{path.stem}"
            text = path.read_text(encoding="utf-8")
            if "]=====]" in text:
                raise SystemExit(f"{path} contains the long-string terminator")
            sources[key] = text

    lines = ["__SOURCES = {"]
    for key, text in sources.items():
        lines.append(f'  ["{key}"] = [=====[{text}]=====],')
    lines.append("}")
    harness = (ROOT / "scripts" / "test_logic.luau").read_text(encoding="utf-8")
    bundle = "\n".join(lines) + "\n" + harness

    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
        handle.write(bundle)
        bundle_path = handle.name
    try:
        luau = os.environ.get("LUAU", "luau")
        result = subprocess.run([luau, bundle_path], cwd=ROOT)
        return result.returncode
    finally:
        os.unlink(bundle_path)

if __name__ == "__main__":
    sys.exit(main())
