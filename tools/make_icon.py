#!/usr/bin/env python3
"""Render the app icon (full-bleed, opaque) and regenerate the iOS AppIcon set.

Same knight + green-checker design as the in-game logo (scripts/ui/MainMenuScreen
_HomeLogo), but the dark board colour fills the WHOLE square — no inset card /
frame — so iOS's rounded-square (squircle) mask wraps it cleanly. Drawn with
PIL because headless Godot can't render a SubViewport.

  python3 tools/make_icon.py
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG_CARD2 = (41, 49, 40)     # #293128 — full-bleed background
ACCENT = (94, 127, 62)      # #5E7F3E — green checker squares
TEXT = (240, 241, 236)      # #F0F1EC — knight / pedestal
BG_CARD = (30, 36, 31)      # #1E241F — eye

S = 1024


def draw_icon(w=S):
    img = Image.new("RGB", (w, w), BG_CARD2)
    d = ImageDraw.Draw(img)
    rx = 0.06  # in-game card inset, kept so the checker matches the logo
    # Two green squares (same placement as the logo, relative to the inset card)
    s1 = (rx + 0.08)
    d.rectangle([s1 * w, s1 * w, (s1 + 0.36) * w, (s1 + 0.36) * w], fill=ACCENT)
    s2 = (rx + 0.44)
    d.rectangle([s2 * w, s2 * w, (s2 + 0.36) * w, (s2 + 0.36) * w], fill=ACCENT)
    # Knight silhouette — identical points to the in-game logo
    pts = [(0.35, 0.80), (0.65, 0.80), (0.62, 0.70), (0.55, 0.65), (0.65, 0.50),
           (0.60, 0.30), (0.45, 0.35), (0.30, 0.45), (0.35, 0.55), (0.45, 0.50),
           (0.38, 0.70)]
    d.polygon([(x * w, y * w) for x, y in pts], fill=TEXT)
    # Eye
    ex, ey, er = 0.52 * w, 0.42 * w, 0.025 * w
    d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=BG_CARD)
    # Pedestal
    d.rectangle([0.30 * w, 0.82 * w, 0.70 * w, 0.88 * w], fill=TEXT)
    return img


def main():
    icon = draw_icon()
    brand = os.path.join(ROOT, "assets", "brand")
    icon.save(os.path.join(brand, "app_icon_1024.png"))
    icon.save(os.path.join(brand, "splash.png"))
    print("wrote assets/brand/app_icon_1024.png + splash.png (1024, RGB/no-alpha)")

    # Regenerate every PNG already present in the iOS AppIcon set at its size.
    iconset = os.path.join(ROOT, "Chess", "Images.xcassets", "AppIcon.appiconset")
    if os.path.isdir(iconset):
        for fn in sorted(os.listdir(iconset)):
            if not fn.endswith(".png"):
                continue
            p = os.path.join(iconset, fn)
            w = Image.open(p).size[0]
            icon.resize((w, w), Image.LANCZOS).convert("RGB").save(p)
            print(f"  {fn}  ({w}px)")


if __name__ == "__main__":
    main()
