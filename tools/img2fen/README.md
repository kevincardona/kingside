# img2fen — experimental board-image → FEN (+ quick analysis)

A small standalone tool (not part of the app) to turn a **screenshot of a digital
chessboard** into a FEN, then review it: who's winning, the best move, or play on
from there against Stockfish.

> Scope: built for clean **digital** boards (this app, lichess, chess.com, a video
> frame). It is **not** for photos of real boards (angle/lighting/3-D pieces) —
> that needs heavier ML. Dependencies: Pillow only (`pip install pillow`).

## Use it

```sh
# Prove it works (renders known positions and re-reads them):
python3 img2fen.py selftest

# Make a test board from a FEN:
python3 img2fen.py render "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w" board.png

# Extract a FEN from a board screenshot:
python3 img2fen.py fen position.png

# Full review: prints the board, material, and a lichess analysis link:
python3 img2fen.py analyze position.png
# → https://lichess.org/analysis/<fen>   (real Stockfish eval, best move, "play from here")

# Offline eval/best-move instead of the link (needs a stockfish binary):
python3 img2fen.py analyze position.png --stockfish /opt/homebrew/bin/stockfish
```

Useful flags: `--flip` (black at the bottom), `--side b` (black to move),
`--no-trim` (don't auto-strip solid borders).

## Recognising other piece sets (calibration)

Out of the box it knows its own rendered style. For a **real source** (lichess,
chess.com, this app), calibrate once with a screenshot of that source's **starting
position**, then reuse it:

```sh
python3 img2fen.py calibrate lichess_start.png lichess.json
python3 img2fen.py fen any_lichess_position.png --templates lichess.json
```

## How it works

Each square is cropped, reduced to a small grayscale, background-subtracted (so
the piece — not the square colour — dominates), and matched to per-class
templates by cosine similarity; empty squares are gated by how little "ink" they
hold. Templates are learned from a known start position.

## Known limits (it's experimental)

- Needs the board roughly cropped/axis-aligned; heavy UI chrome around it can
  confuse the auto-trim — crop to the board for best results.
- Castling rights / en-passant / move counters can't be known from one image, so
  the FEN uses `- - 0 1` (fine for analysis links and engine play).
- Different piece art needs a one-time `calibrate`. Tiny pieces at low resolution
  can occasionally confuse look-alikes; raise `CELL` in the script if needed.

## Plugging into the app

The extracted FEN drops straight into any analysis board. If you later want a
"set up position" entry point inside {{APP_NAME}} itself, the FEN is already in the
exact format `ChessLogic.parse_fen()` accepts.
