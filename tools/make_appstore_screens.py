#!/usr/bin/env python3
"""Generate App Store marketing screenshots from the raw screenshot-tour PNGs.

Each output is a 6.7" iPhone portrait frame (1290x2796) with a brand-gradient
background, a bold headline caption, and the app screenshot inset with rounded
corners + a soft shadow. Run the tour first:
  godot --resolution 430x932 res://test_screens.tscn   # writes /tmp/chess_shots
then:
  python3 tools/make_appstore_screens.py

Outputs to marketing/screenshots/.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = "/tmp/chess_shots"
OUT = os.path.join(ROOT, "marketing", "screenshots")
W, H = 1290, 2796

# Brand palette (mirrors UITheme.gd)
BG_TOP = (24, 32, 25)
BG_BOT = (12, 15, 12)
ACCENT = (143, 184, 96)
GOLD = (233, 185, 73)
TEXT = (240, 241, 236)

# (source shot, headline, accent-word-or-None)
# First slide is the real board — people want to see the chess before anything.
SLIDES = [
    ("08_game.png", "Real Stockfish,\n100% offline", "offline"),
    ("07_difficulty.png", "Bots for every\nlevel, 500–3200", "every"),
    ("02_puzzles_hub.png", "2,000+ puzzles &\ndaily challenges", "2,000+"),
    ("04_puzzle_solver.png", "A star-gated\npuzzle journey", "star-gated"),
    ("09_profile.png", "Review games &\ntrack your rating", "Review"),
    ("08c_local_game_capture.png", "Play hands-free —\njust say your move", "hands-free"),
    ("01_main_menu.png", "No ads. No account.\nJust chess.", "No ads"),
]


def font(size, bold=True):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return ImageFont.load_default()


def gradient_bg():
    bg = Image.new("RGB", (W, H))
    px = bg.load()
    for y in range(H):
        t = y / H
        px_row = tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3))
        for x in range(W):
            px[x, y] = px_row
    return bg


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0], img.size[1]], radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def draw_caption(canvas, headline, accent_word):
    d = ImageDraw.Draw(canvas)
    f = font(104)
    lines = headline.split("\n")
    y = 230
    for line in lines:
        # center the line
        w = d.textbbox((0, 0), line, font=f)[2]
        x = (W - w) // 2
        # accent-colour the keyword if present in this line
        if accent_word and accent_word in line:
            before, _, after = line.partition(accent_word)
            cx = x
            for seg, col in ((before, TEXT), (accent_word, GOLD), (after, TEXT)):
                if seg:
                    d.text((cx, y), seg, font=f, fill=col)
                    cx += d.textbbox((0, 0), seg, font=f)[2]
        else:
            d.text((x, y), line, font=f, fill=TEXT)
        y += 130


def make(slide):
    src, headline, accent_word = slide
    path = os.path.join(SHOTS, src)
    if not os.path.exists(path):
        print("  skip (missing):", src)
        return
    canvas = gradient_bg()
    draw_caption(canvas, headline, accent_word)

    shot = Image.open(path).convert("RGBA")
    target_w = 940
    scale = target_w / shot.width
    shot = shot.resize((target_w, int(shot.height * scale)), Image.LANCZOS)
    shot = rounded(shot, 56)

    # soft shadow
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sx = (W - shot.width) // 2
    sy = 560
    shadow.paste((0, 0, 0, 150), (sx, sy + 24, sx + shot.width, sy + shot.height + 24), rounded(Image.new("RGBA", shot.size, (0, 0, 0, 255)), 56))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)

    # subtle accent border
    border = Image.new("RGBA", (shot.width + 8, shot.height + 8), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle([0, 0, border.width, border.height], 60, outline=(*ACCENT, 90), width=4)
    canvas.alpha_composite(border, (sx - 4, sy - 4))
    canvas.alpha_composite(shot, (sx, sy))

    os.makedirs(OUT, exist_ok=True)
    name = os.path.splitext(src)[0] + "__" + headline.split("\n")[0].lower().replace(" ", "_").replace(",", "") + ".png"
    canvas.convert("RGB").save(os.path.join(OUT, name), quality=95)
    print("  wrote", name)


if __name__ == "__main__":
    print("Generating App Store screenshots ->", OUT)
    for s in SLIDES:
        make(s)
