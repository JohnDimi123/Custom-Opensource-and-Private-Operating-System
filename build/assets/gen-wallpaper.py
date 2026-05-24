#!/usr/bin/env python3
"""Generate original AuroraOS wallpapers (light + dark) procedurally.

Output: PNG files in --out directory.
- aurora-default.png  (1920x1080 dark blue/teal aurora-like gradient)
- aurora-light.png    (1920x1080 soft pastel for light mode)
- aurora-1440.png     (smaller variant)

Pure stdlib + PIL.  Everything here is original output.
"""
from __future__ import annotations

import argparse
import math
import os
import random
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("Pillow not available; trying to install", file=sys.stderr)
    os.system(f"{sys.executable} -m pip install -q --break-system-packages Pillow")
    from PIL import Image, ImageDraw, ImageFilter


def lerp(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


def smoothstep(x):
    return x * x * (3 - 2 * x)


def render_aurora(size, palette, blob_count=14, seed=1):
    """Soft, layered radial-gradient bands evoking aurora light.

    palette = [bg_top, bg_bottom, glow_a, glow_b, glow_c]"""
    w, h = size
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), palette[0])
    px = img.load()
    # Vertical bg gradient
    for y in range(h):
        t = smoothstep(y / max(1, h - 1))
        c = lerp(palette[0], palette[1], t)
        for x in range(w):
            px[x, y] = c

    # Compose glowing blobs on a separate float buffer for additive blend
    blob_layer = Image.new("RGB", (w, h), (0, 0, 0))
    bd = ImageDraw.Draw(blob_layer)
    for _ in range(blob_count):
        cx = rng.uniform(-0.1 * w, 1.1 * w)
        cy = rng.uniform(0.1 * h, 0.9 * h)
        r = rng.uniform(0.18 * w, 0.45 * w)
        col = rng.choice(palette[2:])
        # Slight intensity variation
        col = tuple(min(255, int(c * rng.uniform(0.55, 0.95))) for c in col)
        bd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)

    blob_layer = blob_layer.filter(ImageFilter.GaussianBlur(radius=int(w * 0.06)))
    # Additive-screen-ish blend
    out = Image.blend(img, ImageEqualBlendMax(img, blob_layer), 1.0)

    # Subtle vignette
    vignette = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(vignette)
    vd.ellipse((-w * 0.2, -h * 0.2, w * 1.2, h * 1.2), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(radius=int(w * 0.15)))
    out = Image.composite(out, Image.new("RGB", (w, h), palette[0]), vignette)
    return out


def ImageEqualBlendMax(a, b):
    """Approximate 'screen' blend: max(a, b) pixel-wise."""
    return Image.eval(a, lambda v: v).point(lambda v: v)  # placeholder
    # Pillow doesn't have screen blend directly; we approximate with chops.max


def screen_blend(a, b):
    from PIL import ImageChops
    return ImageChops.lighter(a, b)


def render(out_path: Path, size, palette, seed=1):
    w, h = size
    rng = random.Random(seed)
    base = Image.new("RGB", (w, h), palette[0])
    # vertical gradient
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = smoothstep(y / max(1, h - 1))
        grad.putpixel((0, y), lerp(palette[0], palette[1], t))
    base = grad.resize((w, h))

    # glow blobs additive
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for _ in range(16):
        cx = rng.uniform(-0.1 * w, 1.1 * w)
        cy = rng.uniform(0.05 * h, 0.95 * h)
        r = rng.uniform(0.20 * w, 0.50 * w)
        col = rng.choice(palette[2:])
        col = tuple(int(c * rng.uniform(0.5, 1.0)) for c in col)
        gd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=int(min(w, h) * 0.10)))

    img = screen_blend(base, glow)

    # Soft vignette
    vignette = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(vignette)
    vd.ellipse((-w * 0.25, -h * 0.25, w * 1.25, h * 1.25), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(radius=int(min(w, h) * 0.18)))
    img = Image.composite(img, Image.new("RGB", (w, h), palette[0]), vignette)

    img.save(out_path, "PNG", optimize=True)
    print(f"  wrote {out_path}  ({out_path.stat().st_size//1024} KB)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    # Dark aurora-night palette: deep navy -> midnight; teal/violet/cyan glows
    dark_palette = [
        (8, 12, 32),       # bg top
        (3, 6, 18),        # bg bottom
        (28, 90, 168),     # cobalt
        (52, 168, 220),    # cyan
        (124, 92, 220),    # violet
        (60, 200, 180),    # teal
    ]
    # Light palette: airy pastels
    light_palette = [
        (224, 232, 248),
        (244, 244, 252),
        (180, 210, 240),
        (200, 232, 240),
        (220, 210, 240),
        (210, 232, 220),
    ]

    render(out / "aurora-default.png", (1920, 1080), dark_palette, seed=42)
    render(out / "aurora-light.png",   (1920, 1080), light_palette, seed=17)
    render(out / "aurora-1440.png",    (1440, 900),  dark_palette, seed=42)
    render(out / "aurora-lockscreen.png", (1920, 1080), dark_palette, seed=7)


if __name__ == "__main__":
    main()
