#!/bin/sh
# Static analysis for the whole project: builds a Rojo sourcemap, then type-checks every script
# against the Roblox API with luau-lsp. Usage: scripts/analyze.sh
# Requires: rojo, luau-lsp and the Roblox globalTypes.d.luau (see README "Tooling").
set -u
cd "$(dirname "$0")/.." || exit 2

ROJO="${ROJO:-rojo}"
LUAU_LSP="${LUAU_LSP:-luau-lsp}"
LUAU_DEFS="${LUAU_DEFS:-globalTypes.d.luau}"

"$ROJO" sourcemap default.project.json --include-non-scripts -o sourcemap.json >/dev/null || exit 3
"$LUAU_LSP" analyze --sourcemap=sourcemap.json --definitions="$LUAU_DEFS" --base-luaurc=.luaurc src 2>&1 \
	| grep -v '^[[:space:]]\|^\[INFO\]\|^\[WARN\]'
exit 0
