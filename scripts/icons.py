# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow"]
# ///
"""Draws the app icon concepts and installs the chosen one into the asset catalog."""
import argparse
import json
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "design" / "icons"
APPICON = ROOT / "ios" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024


def vertical_gradient(top, bottom):
    image = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(image)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        draw.line([(0, y), (SIZE, y)], fill=color)
    return image


def play_triangle(draw, cx, cy, size, fill):
    half = size / 2
    points = [(cx - half * 0.8, cy - half), (cx - half * 0.8, cy + half), (cx + half, cy)]
    draw.polygon(points, fill=fill)


def concept_threads():
    image = vertical_gradient((20, 16, 48), (52, 20, 84))
    glow = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(glow)
    colors = [(251, 114, 153), (236, 120, 190), (190, 130, 240), (120, 170, 250), (90, 210, 240)]
    for i, color in enumerate(colors):
        y = 330 + i * 90
        draw.line([(140, y), (560, y + (512 - y) * 0.55)], fill=color, width=34)
    glow = glow.filter(ImageFilter.GaussianBlur(10))
    image = Image.blend(image, glow, 0.55)
    draw = ImageDraw.Draw(image)
    for i, color in enumerate(colors):
        y = 330 + i * 90
        draw.line([(140, y), (560, y + (512 - y) * 0.55)], fill=color, width=22)
    play_triangle(draw, 680, 512, 330, (255, 255, 255))
    return image


def concept_bolt():
    image = vertical_gradient((255, 128, 168), (214, 60, 120))
    draw = ImageDraw.Draw(image)
    play_triangle(draw, 540, 512, 520, (255, 255, 255))
    cut = [(470, 250), (600, 250), (520, 470), (640, 470), (420, 800), (480, 560), (380, 560)]
    draw.polygon(cut, fill=(214, 60, 120))
    return image


def concept_orbit():
    image = vertical_gradient((10, 12, 30), (24, 18, 56))
    glow = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(glow)
    for radius, color in [(390, (251, 114, 153)), (310, (160, 120, 250)), (230, (90, 200, 240))]:
        box = [512 - radius, 512 - radius, 512 + radius, 512 + radius]
        draw.arc(box, start=200, end=520, fill=color, width=26)
        angle = math.radians(520 % 360)
        dot = (512 + radius * math.cos(angle), 512 + radius * math.sin(angle))
        draw.ellipse([dot[0] - 30, dot[1] - 30, dot[0] + 30, dot[1] + 30], fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(6))
    image = Image.blend(image, glow, 0.85)
    play_triangle(ImageDraw.Draw(image), 530, 512, 230, (255, 255, 255))
    return image


def concept_glass():
    image = vertical_gradient((60, 30, 110), (12, 10, 30))
    orb = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    ImageDraw.Draw(orb).ellipse([212, 212, 812, 812], fill=(255, 255, 255))
    orb = orb.filter(ImageFilter.GaussianBlur(4))
    mask = orb.convert("L").point(lambda v: int(v * 0.32))
    image.paste((235, 225, 255), mask=mask)
    draw = ImageDraw.Draw(image)
    draw.arc([212, 212, 812, 812], start=200, end=330, fill=(255, 255, 255), width=10)
    play_triangle(draw, 530, 512, 300, (251, 114, 153))
    return image


CONCEPTS = {1: concept_threads, 2: concept_bolt, 3: concept_orbit, 4: concept_glass}


def render_all():
    OUT.mkdir(parents=True, exist_ok=True)
    for number, make in CONCEPTS.items():
        path = OUT / f"concept-{number}.png"
        make().convert("RGB").save(path)
        print(path)


def apply(number):
    APPICON.mkdir(parents=True, exist_ok=True)
    CONCEPTS[number]().convert("RGB").save(APPICON / "icon-1024.png")
    contents = {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }
    (APPICON / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    catalog = APPICON.parent / "Contents.json"
    if not catalog.exists():
        catalog.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    print(APPICON / "icon-1024.png")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", type=int, choices=sorted(CONCEPTS))
    args = parser.parse_args()
    if args.apply:
        apply(args.apply)
    else:
        render_all()
