#!/usr/bin/env bash
# Download a slice of the Lichess open puzzle DB (CC0) and bake it into the
# offline bundle. The full file is ~300 MB; we only range-request a prefix
# because the CSV is ordered by PuzzleId (random vs. rating), so a slice still
# spans the whole rating range. zstd decodes the valid prefix and errors on
# the truncated tail (ignored).
#
# Usage: tools/bake_puzzles.sh [slice_megabytes]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="https://database.lichess.org/lichess_db_puzzle.csv.zst"
SLICE_MB="${1:-60}"
BYTES=$((SLICE_MB * 1024 * 1024))
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading first ${SLICE_MB} MB of the Lichess puzzle DB..."
curl -sSL --max-time 300 -r "0-$BYTES" "$URL" -o "$TMP/slice.zst"
echo "Decompressing (truncated tail expected)..."
zstd -dc "$TMP/slice.zst" 2>/dev/null > "$TMP/puzzles.csv" || true
LINES="$(wc -l < "$TMP/puzzles.csv" | tr -d ' ')"
echo "Decompressed ~${LINES} rows."

python3 "$ROOT/tools/bake_puzzles.py" "$TMP/puzzles.csv"
