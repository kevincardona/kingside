#!/usr/bin/env bash
# build_pck.sh — rebuild Chess.pck from current Godot scripts so the iOS
# simulator build picks up recent edits. Run this after changing any .gd / .tscn
# file, then build & run the Xcode project as usual.
#
# The produced Chess.pck is checked into the repo so Xcode Cloud (which has no
# Godot install) can build the iOS target. Re-run this script and commit the
# result whenever project content changes.
#
# Usage:  ./build_pck.sh
#
# Override the Godot binary by exporting GODOT_BIN first.

set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
PCK_PATH="${PROJECT_DIR}/Chess.pck"
TMP_PCK="$(mktemp -t chess_pckXXXXXX).pck"

run_godot() {
	local args=("$@")
	# Godot writes harmless "Attempt to register extension class" messages
	# to stderr on every fresh invocation when a GDExtension is present;
	# discard them so the script output stays clean.
	"$GODOT_BIN" "${args[@]}" 2>/dev/null
}

if [[ ! -x "$GODOT_BIN" ]]; then
	echo "error: Godot binary not found or not executable: $GODOT_BIN" >&2
	echo "       set GODOT_BIN to your editor binary, e.g.:" >&2
	echo "       GODOT_BIN=/path/to/Godot ./build_pck.sh" >&2
	exit 1
fi

cd "$PROJECT_DIR"

echo "→ Importing project (regenerates .godot/ cache)…"
run_godot --headless --import

echo "→ Exporting pack to $TMP_PCK…"
run_godot --headless --export-pack "iOS" "$TMP_PCK"

if [[ ! -f "$TMP_PCK" ]]; then
	echo "error: pack export did not produce $TMP_PCK" >&2
	exit 1
fi

mv "$TMP_PCK" "$PCK_PATH"
echo "✓ Wrote $(basename "$PCK_PATH") ($(du -h "$PCK_PATH" | awk '{print $1}'))"
echo "  Rebuild & run the Xcode project to pick up changes."
