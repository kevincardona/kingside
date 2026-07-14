"""Generate the iMessage App Icon set for the Messages extension from the
main app's 1024px icon. iMessage icons are wide (e.g. 60x45pt); the square
logo is scaled to fit the height and centered on a canvas filled with the
icon's corner color, so the bands blend with the artwork background.

Run from the repo root:  python3 tools/gen_imessage_icons.py
"""
import json
import os

from PIL import Image

SRC = "Chess/Images.xcassets/AppIcon.appiconset/Icon-1024.png"
DEST = "MessagesExtension/Assets.xcassets/iMessage App Icon.stickersiconset"

# (idiom, size_pt, scale, platform)
SPECS = [
    ("iphone", (29, 29), 2, None),
    ("iphone", (29, 29), 3, None),
    ("iphone", (60, 45), 2, None),
    ("iphone", (60, 45), 3, None),
    ("ipad", (29, 29), 2, None),
    ("ipad", (67, 50), 2, None),
    ("ipad", (74, 55), 2, None),
    ("universal", (27, 20), 2, "ios"),
    ("universal", (27, 20), 3, "ios"),
    ("universal", (32, 24), 2, "ios"),
    ("universal", (32, 24), 3, "ios"),
    ("ios-marketing", (1024, 768), 1, "ios"),
]


def render(src: Image.Image, w: int, h: int) -> Image.Image:
    bg = src.getpixel((2, 2))
    canvas = Image.new("RGB", (w, h), bg)
    side = min(w, h)
    logo = src.resize((side, side), Image.LANCZOS)
    canvas.paste(logo, ((w - side) // 2, (h - side) // 2))
    return canvas


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    os.makedirs(DEST, exist_ok=True)
    images = []
    for idiom, (w_pt, h_pt), scale, platform in SPECS:
        w, h = w_pt * scale, h_pt * scale
        name = f"icon-{w_pt}x{h_pt}@{scale}x-{idiom}.png"
        render(src, w, h).save(os.path.join(DEST, name))
        entry = {
            "filename": name,
            "idiom": idiom,
            "scale": f"{scale}x",
            "size": f"{w_pt}x{h_pt}",
        }
        if platform:
            entry["platform"] = platform
        images.append(entry)
        print(f"  {name}  ({w}x{h})")
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(DEST, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    root = "MessagesExtension/Assets.xcassets/Contents.json"
    with open(root, "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("Done.")


if __name__ == "__main__":
    main()
