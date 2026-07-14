#!/usr/bin/env python3
"""Bake the puzzle bundle (assets/puzzles/bundled.json) from the Lichess open
puzzle database (CC0).

Produces two things in one deduped pass over a decompressed CSV slice:
  * levels — the hand-specced Journey campaign: themed, rating-ramped levels
             (LEVELS below). Each level's puzzles are sorted easy->hard.
  * pool   — a large rating-bucketed offline fallback for Endless/Daily.

The full DB is ~300 MB / ~5M puzzles; we only range-request a prefix (see
bake_puzzles.sh). The CSV is ordered by PuzzleId (random vs. rating/theme),
so a slice still spans the whole space.

Bundle row format (raw Lichess columns, matches PuzzleManager._normalize_csv_row):
  {id, fen, moves, rating, themes}.  moves[0] is the opponent setup move
  applied at load; the rest is the solution. Pool rows are normalized lazily.

Usage: python3 tools/bake_puzzles.py <decompressed_csv> [--out PATH]
"""
import argparse
import csv
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE = os.path.join(ROOT, "assets", "puzzles", "bundled.json")

# Lichess CSV columns:
# PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags
COL_ID, COL_FEN, COL_MOVES, COL_RATING, COL_RD, COL_POP, COL_PLAYS, COL_THEMES = range(8)

# ── Journey campaign (themed, rating-ramped, star-gated) ────────────────────
# (name, subtitle, theme_tag, rating_lo, rating_hi, count, unlock_stars)
# theme_tag must appear in the puzzle's Themes column. Levels unlock by the
# player's CUMULATIVE star total (not by finishing the previous level), so
# progression is non-linear — early levels open fast and you choose your path.
# Each level holds many puzzles; you only need a fraction of stars to advance.
PER_LEVEL = 100
LEVELS = [
    ("Checkmate Basics",     "Deliver mate in one",       "mateIn1",          550, 1000, PER_LEVEL,   0),
    ("Hanging Pieces",       "Win the free material",     "hangingPiece",     600, 1050, PER_LEVEL,   6),
    ("The Fork",             "Hit two targets at once",   "fork",             750, 1150, PER_LEVEL,  15),
    ("Pins",                 "Freeze a defender",         "pin",              850, 1250, PER_LEVEL,  28),
    ("Mate in Two",          "Force mate in two",         "mateIn2",          950, 1350, PER_LEVEL,  45),
    ("Skewers",              "Win the piece behind",      "skewer",           950, 1350, PER_LEVEL,  66),
    ("Discovered Attacks",   "Unveil a hidden threat",    "discoveredAttack",1050, 1450, PER_LEVEL,  92),
    ("Back-Rank Mates",      "Exploit the trapped king",  "backRankMate",    1050, 1450, PER_LEVEL, 122),
    ("Capture the Defender", "Remove what holds it up",   "capturingDefender",1150,1550, PER_LEVEL, 157),
    ("Deflection",           "Drag a defender away",      "deflection",      1250, 1650, PER_LEVEL, 197),
    ("Sacrifices",           "Give now, win later",       "sacrifice",       1250, 1700, PER_LEVEL, 242),
    ("Advanced Pawns",       "Push it home",              "advancedPawn",    1200, 1650, PER_LEVEL, 292),
    ("Mate in Three",        "Calculate the forced mate", "mateIn3",         1350, 1800, PER_LEVEL, 347),
    ("Trapped Pieces",       "Hunt the stranded piece",   "trappedPiece",    1300, 1750, PER_LEVEL, 407),
    ("Mating Attacks",       "Storm the enemy king",      "kingsideAttack",  1400, 1850, PER_LEVEL, 472),
    ("Quiet Moves",          "The subtle winning move",   "quietMove",       1400, 1900, PER_LEVEL, 542),
    ("Endgame Technique",    "Convert the small edge",    "endgame",         1300, 1800, PER_LEVEL, 617),
    ("Attraction",           "Lure the king out",         "attraction",      1400, 1900, PER_LEVEL, 697),
    ("Zwischenzug",          "The in-between move",       "intermezzo",      1450, 1950, PER_LEVEL, 782),
    ("Master Tactics",       "Find the crushing blow",    "crushing",        1700, 2200, PER_LEVEL, 872),
]
# Levels tolerate looser quality than the pool so the themed/banded slots fill.
LVL_MIN_POP, LVL_MIN_PLAYS, LVL_MAX_RD = 70, 20, 120

# ── Offline pool (rating-bucketed fallback) ─────────────────────────────────
# (rating_lo, rating_hi, count). Weighted to where this app's players live.
BANDS = [
    (600, 800, 900), (800, 1000, 1000), (1000, 1200, 1150),
    (1200, 1400, 1250), (1400, 1600, 1250), (1600, 1800, 1150),
    (1800, 2000, 1000), (2000, 2200, 800), (2200, 2400, 550),
    (2400, 2800, 350),
]
POOL_MIN_POP, POOL_MIN_PLAYS, POOL_MAX_RD = 85, 40, 90


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--out", default=BUNDLE)
    args = ap.parse_args()

    level_rows = [[] for _ in LEVELS]
    band_rows = [[] for _ in BANDS]
    band_target = [b[2] for b in BANDS]
    used = set()
    scanned = 0

    def levels_done():
        return all(len(level_rows[i]) >= LEVELS[i][5] for i in range(len(LEVELS)))

    def bands_done():
        return all(len(band_rows[i]) >= band_target[i] for i in range(len(BANDS)))

    with open(args.csv, newline="") as f:
        for row in csv.reader(f):
            if len(row) < 8 or row[COL_ID] == "PuzzleId":
                continue
            scanned += 1
            pid = row[COL_ID]
            if pid in used:
                continue
            try:
                rating = int(row[COL_RATING]); rd = int(row[COL_RD])
                pop = int(row[COL_POP]); plays = int(row[COL_PLAYS])
            except ValueError:
                continue
            moves = row[COL_MOVES].strip()
            if len(moves.split(" ")) < 2:
                continue
            themes = row[COL_THEMES]
            entry = {"id": pid, "fen": row[COL_FEN], "moves": moves,
                     "rating": rating, "themes": themes.strip()}

            # Journey levels take priority over the pool.
            placed = False
            if pop >= LVL_MIN_POP and plays >= LVL_MIN_PLAYS and rd <= LVL_MAX_RD:
                theme_set = themes.split(" ")
                for i, (_, _, tag, lo, hi, cnt, _u) in enumerate(LEVELS):
                    if len(level_rows[i]) < cnt and lo <= rating < hi and tag in theme_set:
                        level_rows[i].append(entry)
                        used.add(pid)
                        placed = True
                        break
            if placed:
                continue

            if pop >= POOL_MIN_POP and plays >= POOL_MIN_PLAYS and rd <= POOL_MAX_RD:
                for i, (lo, hi, cnt) in enumerate(BANDS):
                    if len(band_rows[i]) < cnt and lo <= rating < hi:
                        band_rows[i].append(entry)
                        used.add(pid)
                        break

            if levels_done() and bands_done():
                break

    levels = []
    for i, (name, sub, _tag, _lo, _hi, _cnt, unlock) in enumerate(LEVELS):
        puzzles = sorted(level_rows[i], key=lambda r: r["rating"])
        levels.append({"name": name, "subtitle": sub,
                       "unlock_stars": unlock, "puzzles": puzzles})
    pool = [r for band in band_rows for r in band]

    bundle = {"version": 2, "source": "lichess_db_puzzle (CC0)",
              "levels": levels, "pool": pool}
    json.dump(bundle, open(args.out, "w"), separators=(",", ":"))

    print(f"scanned {scanned} rows")
    print("Journey levels:")
    for (name, _, _, lo, hi, cnt, unlock), got in zip(LEVELS, level_rows):
        flag = "" if len(got) >= cnt else "  << SHORT"
        print(f"  {name:<22} {lo}-{hi} (unlock {unlock}*): {len(got)}/{cnt}{flag}")
    print("Pool bands:")
    for (lo, hi, cnt), got in zip(BANDS, band_rows):
        print(f"  {lo:>4}-{hi:<4}: {len(got)}/{cnt}")
    total_lvl = sum(len(x) for x in level_rows)
    print(f"journey: {total_lvl} puzzles across {len(LEVELS)} levels")
    print(f"pool: {len(pool)} puzzles")
    print(f"total bundled: {total_lvl + len(pool)}")
    print(f"{args.out}  {os.path.getsize(args.out)/1024:.1f} KB")


if __name__ == "__main__":
    sys.exit(main())
