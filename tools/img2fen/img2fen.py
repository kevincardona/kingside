#!/usr/bin/env python3
"""
img2fen — experimental chessboard-image → FEN extractor (+ quick analysis).

Aimed at CLEAN DIGITAL BOARDS: a screenshot from this app, lichess, chess.com,
or a video frame. It is NOT built for photos of real boards (perspective /
lighting / 3-D pieces) — that needs heavier ML and is out of scope here.

How it recognises pieces
------------------------
Each of the 64 squares is cropped, reduced to a small grayscale, background-
subtracted (so the piece shape dominates, not the square colour) and matched
against per-class templates by cosine similarity. Empty squares are gated by how
little "ink" they contain.

Templates come from a START POSITION you already know the layout of:
  • By default the tool renders its own synthetic start board and uses that —
    good enough for Unicode/letter style boards and the self-test.
  • For a real source (lichess, chess.com, this app), calibrate ONCE with a
    screenshot of that source's STARTING position; then every position from the
    same source is recognised. Different piece art → re-calibrate.

Quick start
-----------
    python3 img2fen.py selftest                 # prove the pipeline round-trips
    python3 img2fen.py render "<fen>" board.png  # make a test board
    python3 img2fen.py calibrate start.png mysite.json
    python3 img2fen.py fen position.png --templates mysite.json
    python3 img2fen.py analyze position.png      # FEN + who's winning + lichess URL

Dependencies: Pillow (pip install pillow). numpy/python-chess/Stockfish NOT
required. Pass --stockfish /path/to/stockfish for an offline eval/best-move.
"""
from __future__ import annotations
import argparse, json, math, os, subprocess, sys, urllib.parse

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("This tool needs Pillow:  pip install pillow")

# FEN piece chars. Uppercase = white, lowercase = black, '.' = empty.
PIECE_CHARS = ["P", "N", "B", "R", "Q", "K", "p", "n", "b", "r", "q", "k"]
GLYPH = {"p": "♟", "n": "♞", "b": "♝", "r": "♜", "q": "♛", "k": "♚"}
START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
MATERIAL = {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9, "k": 0}

CELL = 36            # square is reduced to CELL x CELL grayscale for matching
FONT_CANDIDATES = [
    "/System/Library/Fonts/Apple Symbols.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


# ── FEN helpers ─────────────────────────────────────────────────────────────
def rows_to_placement(rows: list[str]) -> str:
    """rows[0] = rank 8 ... rows[7] = rank 1, each 8 chars ('.' = empty)."""
    out = []
    for r in rows:
        s, run = "", 0
        for c in r:
            if c == ".":
                run += 1
            else:
                if run:
                    s += str(run); run = 0
                s += c
        if run:
            s += str(run)
        out.append(s)
    return "/".join(out)


def placement_to_rows(placement: str) -> list[str]:
    rows = []
    for part in placement.split("/"):
        r = ""
        for c in part:
            r += "." * int(c) if c.isdigit() else c
        rows.append(r.ljust(8, ".")[:8])
    while len(rows) < 8:
        rows.append("." * 8)
    return rows[:8]


def material_eval(placement: str) -> tuple[int, str]:
    w = b = 0
    for c in placement:
        if c in MATERIAL:
            w += MATERIAL[c]
        elif c.lower() in MATERIAL:
            b += MATERIAL[c.lower()]
    diff = w - b
    if diff == 0:
        return 0, "Material is even"
    side = "White" if diff > 0 else "Black"
    return diff, f"{side} is up {abs(diff)} point(s) of material"


def lichess_url(fen: str) -> str:
    return "https://lichess.org/analysis/" + fen.replace(" ", "_")


# ── Image → squares ─────────────────────────────────────────────────────────
def _find_font(size: int):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return ImageFont.load_default()


def render_fen(fen: str, size: int = 512) -> Image.Image:
    """Render a FEN to a clean digital board (for tests / default templates)."""
    placement = fen.split()[0]
    rows = placement_to_rows(placement)
    cell = size // 8
    light, dark = (240, 217, 181), (181, 136, 99)
    img = Image.new("RGB", (cell * 8, cell * 8), light)
    d = ImageDraw.Draw(img)
    font = _find_font(int(cell * 0.78))
    for r in range(8):
        for f in range(8):
            x0, y0 = f * cell, r * cell
            if (r + f) % 2 == 1:
                d.rectangle([x0, y0, x0 + cell, y0 + cell], fill=dark)
            ch = rows[r][f]
            if ch == ".":
                continue
            glyph = GLYPH[ch.lower()]
            cx, cy = x0 + cell // 2, y0 + cell // 2
            if ch.isupper():   # white piece: light fill, dark outline
                d.text((cx, cy), glyph, font=font, fill=(248, 248, 248),
                       anchor="mm", stroke_width=max(1, cell // 22), stroke_fill=(45, 45, 45))
            else:              # black piece: dark fill
                d.text((cx, cy), glyph, font=font, fill=(25, 25, 25), anchor="mm")
    return img


def _auto_trim(img: Image.Image) -> Image.Image:
    """Strip near-uniform solid borders (padding around a board screenshot)."""
    g = img.convert("L")
    w, h = g.size
    px = g.load()

    def row_var(y):
        vals = [px[x, y] for x in range(0, w, max(1, w // 64))]
        m = sum(vals) / len(vals)
        return sum((v - m) ** 2 for v in vals) / len(vals)

    def col_var(x):
        vals = [px[x, y] for y in range(0, h, max(1, h // 64))]
        m = sum(vals) / len(vals)
        return sum((v - m) ** 2 for v in vals) / len(vals)

    thr = 120.0
    top = next((y for y in range(h) if row_var(y) > thr), 0)
    bot = next((y for y in range(h - 1, -1, -1) if row_var(y) > thr), h - 1)
    left = next((x for x in range(w) if col_var(x) > thr), 0)
    right = next((x for x in range(w - 1, -1, -1) if col_var(x) > thr), w - 1)
    if right - left > 16 and bot - top > 16:
        return img.crop((left, top, right + 1, bot + 1))
    return img


def load_board(path: str, flip: bool, auto_trim: bool) -> Image.Image:
    img = Image.open(path).convert("RGB")
    if auto_trim:
        img = _auto_trim(img)
    # Force a square board (digital boards are square; this corrects tiny crops).
    s = min(img.size)
    img = img.crop((0, 0, s, s)).resize((512, 512))
    if flip:
        img = img.transpose(Image.ROTATE_180)
    return img


def square_features(board: Image.Image) -> list[tuple[list[float], float]]:
    """Return 64 (normalized_feature, ink_energy) in FEN order: a8..h8, a7.., h1."""
    g = board.convert("L")
    bw = g.size[0] // 8
    feats = []
    for r in range(8):
        for f in range(8):
            sq = g.crop((f * bw, r * bw, (f + 1) * bw, (r + 1) * bw)).resize((CELL, CELL))
            px = list(sq.tobytes())   # mode "L" → one byte per pixel
            # Background estimate from the border ring (pieces are centred).
            border = []
            for i, v in enumerate(px):
                yy, xx = divmod(i, CELL)
                if xx < 3 or xx >= CELL - 3 or yy < 3 or yy >= CELL - 3:
                    border.append(v)
            bg = sum(border) / len(border)
            dev = [v - bg for v in px]
            energy = sum(abs(d) for d in dev) / len(dev)
            norm = math.sqrt(sum(d * d for d in dev)) or 1.0
            feats.append(([d / norm for d in dev], energy))
    return feats


def _cos(a: list[float], b: list[float]) -> float:
    return sum(x * y for x, y in zip(a, b))


# ── Templates ───────────────────────────────────────────────────────────────
def build_templates(board: Image.Image, start_placement: str = START_FEN.split()[0]) -> dict:
    """Learn per-class templates from a board whose layout we know (a start pos)."""
    feats = square_features(board)
    rows = placement_to_rows(start_placement)
    buckets: dict[str, list[list[float]]] = {}
    empties: list[float] = []
    pieces_energy: list[float] = []
    for idx, (vec, energy) in enumerate(feats):
        ch = rows[idx // 8][idx % 8]
        if ch == ".":
            empties.append(energy)
            buckets.setdefault(".", []).append(vec)
        else:
            pieces_energy.append(energy)
            buckets.setdefault(ch, []).append(vec)
    templates = {}
    for ch, vecs in buckets.items():
        n = len(vecs)
        avg = [sum(v[i] for v in vecs) / n for i in range(CELL * CELL)]
        norm = math.sqrt(sum(x * x for x in avg)) or 1.0
        templates[ch] = [x / norm for x in avg]
    # Ink gate: midpoint between the busiest empty and the quietest piece.
    gate = (max(empties) + min(pieces_energy)) / 2 if empties and pieces_energy else 6.0
    return {"cell": CELL, "gate": gate, "templates": templates}


def classify(vec: list[float], energy: float, model: dict) -> str:
    if energy < model["gate"]:
        return "."
    best, best_s = ".", -2.0
    for ch, t in model["templates"].items():
        if ch == ".":
            continue
        s = _cos(vec, t)
        if s > best_s:
            best, best_s = ch, s
    return best


def extract_rows(board: Image.Image, model: dict) -> list[str]:
    feats = square_features(board)
    rows = []
    for r in range(8):
        rows.append("".join(classify(*feats[r * 8 + f], model=model) for f in range(8)))
    return rows


def extract_fen(board: Image.Image, model: dict, side: str = "w") -> str:
    placement = rows_to_placement(extract_rows(board, model))
    return f"{placement} {side} - - 0 1"


def default_model() -> dict:
    return build_templates(render_fen(START_FEN))


# ── Optional offline Stockfish (minimal UCI over subprocess) ────────────────
def stockfish_analyze(fen: str, engine_path: str, movetime_ms: int = 1500) -> str:
    try:
        p = subprocess.Popen([engine_path], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             text=True, bufsize=1)
    except OSError as e:
        return f"(stockfish unavailable: {e})"

    def send(cmd):
        p.stdin.write(cmd + "\n"); p.stdin.flush()

    send("uci")
    send("isready")
    send(f"position fen {fen}")
    send(f"go movetime {movetime_ms}")
    best, score = "", ""
    try:
        for line in p.stdout:
            line = line.strip()
            if line.startswith("info") and " score " in line:
                toks = line.split()
                if "cp" in toks:
                    cp = int(toks[toks.index("cp") + 1])
                    score = f"{cp/100:+.2f}"
                elif "mate" in toks:
                    score = f"mate in {toks[toks.index('mate') + 1]}"
            if line.startswith("bestmove"):
                best = line.split()[1]
                break
    finally:
        send("quit")
        p.wait(timeout=5)
    return f"eval {score} (white POV) · best move {best}"


# ── Pretty board print ──────────────────────────────────────────────────────
def print_board(rows: list[str]) -> None:
    print("   a b c d e f g h")
    for i, r in enumerate(rows):
        print(f" {8 - i} " + " ".join(c if c != '.' else '.' for c in r))


# ── CLI commands ────────────────────────────────────────────────────────────
def cmd_render(a):
    render_fen(a.fen, a.size).save(a.out)
    print(f"wrote {a.out}")


def cmd_calibrate(a):
    board = load_board(a.start_image, a.flip, not a.no_trim)
    model = build_templates(board)
    with open(a.out, "w") as f:
        json.dump(model, f)
    print(f"calibrated {len(model['templates'])} classes (gate={model['gate']:.2f}) -> {a.out}")


def _load_model(a) -> dict:
    if a.templates:
        with open(a.templates) as f:
            return json.load(f)
    return default_model()


def cmd_fen(a):
    board = load_board(a.image, a.flip, not a.no_trim)
    model = _load_model(a)
    rows = extract_rows(board, model)
    print_board(rows)
    fen = f"{rows_to_placement(rows)} {a.side} - - 0 1"
    print("\nFEN:", fen)


def cmd_analyze(a):
    if a.input.lower().endswith((".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp")):
        board = load_board(a.input, a.flip, not a.no_trim)
        model = _load_model(a)
        rows = extract_rows(board, model)
        print_board(rows)
        fen = f"{rows_to_placement(rows)} {a.side} - - 0 1"
    else:
        fen = a.input if " " in a.input else f"{a.input} {a.side} - - 0 1"
        rows = placement_to_rows(fen.split()[0])
        print_board(rows)
    print("\nFEN:", fen)
    _, txt = material_eval(fen.split()[0])
    print("Material:", txt)
    print("Review / best move / play from here:")
    print("  ", lichess_url(fen))
    if a.stockfish:
        print("Stockfish:", stockfish_analyze(fen, a.stockfish))


def cmd_selftest(a):
    fens = [
        START_FEN.split()[0],
        "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R",   # 2 knights out
        "rnbq1rk1/ppp1bppp/4pn2/3p4/2PP4/2N1PN2/PP3PPP/R1BQKB1R",  # Q-pawn middlegame
        "8/8/8/4k3/8/3K4/4Q3/8",                                   # sparse endgame
    ]
    model = build_templates(render_fen(START_FEN))
    ok = 0
    for placement in fens:
        board = render_fen(placement + " w - - 0 1")
        got = rows_to_placement(extract_rows(board, model))
        match = got == placement
        ok += match
        print(("PASS" if match else "FAIL"), placement)
        if not match:
            print("   got:", got)
    print(f"\nRESULT: {ok}/{len(fens)} positions round-tripped")
    sys.exit(0 if ok == len(fens) else 1)


def main():
    ap = argparse.ArgumentParser(description="Experimental chessboard image -> FEN.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add_img_opts(p):
        p.add_argument("--flip", action="store_true", help="board has black at the bottom")
        p.add_argument("--side", default="w", choices=["w", "b"], help="side to move (default w)")
        p.add_argument("--templates", help="calibration JSON (default: built-in synthetic)")
        p.add_argument("--no-trim", action="store_true", help="don't auto-trim solid borders")

    r = sub.add_parser("render", help="render a FEN to a test board image")
    r.add_argument("fen"); r.add_argument("out", nargs="?", default="board.png")
    r.add_argument("--size", type=int, default=512); r.set_defaults(fn=cmd_render)

    c = sub.add_parser("calibrate", help="learn templates from a start-position screenshot")
    c.add_argument("start_image"); c.add_argument("out", nargs="?", default="templates.json")
    c.add_argument("--flip", action="store_true"); c.add_argument("--no-trim", action="store_true")
    c.set_defaults(fn=cmd_calibrate)

    f = sub.add_parser("fen", help="extract a FEN from a board image")
    f.add_argument("image"); add_img_opts(f); f.set_defaults(fn=cmd_fen)

    an = sub.add_parser("analyze", help="image-or-FEN -> material + lichess URL (+ stockfish)")
    an.add_argument("input"); add_img_opts(an)
    an.add_argument("--stockfish", help="path to a stockfish binary for offline eval/best-move")
    an.set_defaults(fn=cmd_analyze)

    st = sub.add_parser("selftest", help="render known positions and verify extraction")
    st.set_defaults(fn=cmd_selftest)

    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
