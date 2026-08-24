"""Renders one AppIcon.appiconset per palette preset (build spec §17) from
the geometry in Design/AppIcon-Master.svg — same closed-book silhouette,
one shading tone, no gradients, no text, for every accent color.

These are functional placeholders, not final production art: a real
hand-finished icon per preset (the spec's own stated reason the palette is
a closed set rather than a free color picker) still belongs on a designer's
desk before shipping. Requires Pillow: pip install pillow

Usage: python3 scripts/generate_app_icons.py
"""
from PIL import Image, ImageDraw
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

THEMES = {
    "ink": (31, 33, 41),
    "forest": (33, 89, 61),
    "rust": (158, 74, 46),
    "slate": (74, 92, 107),
    "plum": (97, 51, 107),
    "ochre": (168, 125, 38),
    "moss": (84, 102, 61),
    "midnight": (26, 36, 77),
}

BACKGROUND = (244, 241, 236)  # warm paper white, neutral across every preset
SIZE = 1024

def darken(color, factor=0.72):
    return tuple(max(0, int(c * factor)) for c in color)

def make_icon(accent, out_path):
    final = Image.new("RGB", (SIZE, SIZE), BACKGROUND)

    book_w, book_h = 580, 740
    x0 = (SIZE - book_w) // 2
    y0 = (SIZE - book_h) // 2
    x1 = x0 + book_w
    y1 = y0 + book_h
    radius = 30
    spine_x = x0 + int(book_w * 0.26)

    # Front cover, full book shape, flat accent fill (rounded corners)
    mask = Image.new("L", (SIZE, SIZE), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=255)
    cover = Image.new("RGB", (SIZE, SIZE), accent)
    final.paste(cover, (0, 0), mask)

    # One shading tone: the spine-side strip, darker, same rounded corners
    # on its left edge only.
    spine_mask = Image.new("L", (SIZE, SIZE), 0)
    sdraw = ImageDraw.Draw(spine_mask)
    sdraw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=255)
    sdraw.rectangle([spine_x, y0, x1, y1], fill=0)
    spine_layer = Image.new("RGB", (SIZE, SIZE), darken(accent))
    final.paste(spine_layer, (0, 0), spine_mask)

    # Visible spine crease line
    draw = ImageDraw.Draw(final)
    draw.line([(spine_x, y0 + 10), (spine_x, y1 - 10)], fill=darken(accent, 0.55), width=7)

    final.save(out_path, "PNG")

out_dir = os.path.join(REPO_ROOT, "Sources/MyStoryDailyJournal/Support/Assets.xcassets")
os.makedirs(out_dir, exist_ok=True)

for name, rgb in THEMES.items():
    set_name = "AppIcon" if name == "ink" else f"AppIcon-{name}"
    set_dir = os.path.join(out_dir, f"{set_name}.appiconset")
    os.makedirs(set_dir, exist_ok=True)
    make_icon(rgb, os.path.join(set_dir, "icon-1024.png"))
    print("wrote", set_dir)
