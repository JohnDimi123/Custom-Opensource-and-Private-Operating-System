#!/usr/bin/env python3
"""Generate the small bitmap assets the Plymouth script theme needs."""
import sys, os
from pathlib import Path
try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    os.system(f"{sys.executable} -m pip install -q --break-system-packages Pillow")
    from PIL import Image, ImageDraw, ImageFilter

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)

# --- logo.png: 192x192, four rounded panes (matches Aurora logo) ---
def make_logo(size=192):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # outer glow
    glow = Image.new("RGBA", (size, size), (0,0,0,0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((10, 10, size-10, size-10), fill=(76, 194, 255, 110))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=18))
    img.alpha_composite(glow)
    # 4 panes
    palette = [(76,194,255), (124,92,220), (60,200,180), (76,194,255)]
    pad = int(size * 0.18)
    cell = (size - pad*3) // 2
    coords = [(pad, pad), (pad*2 + cell, pad),
              (pad, pad*2 + cell), (pad*2 + cell, pad*2 + cell)]
    radius = int(cell * 0.18)
    for (x, y), color in zip(coords, palette):
        # rounded rect
        cell_img = Image.new("RGBA", (cell, cell), (0,0,0,0))
        cd = ImageDraw.Draw(cell_img)
        cd.rounded_rectangle((0, 0, cell-1, cell-1), radius=radius, fill=color + (255,))
        img.alpha_composite(cell_img, (x, y))
    img.save(OUT / "logo.png", "PNG")

def make_dot(size=10):
    img = Image.new("RGBA", (size+4, size+4), (0,0,0,0))
    d = ImageDraw.Draw(img)
    d.ellipse((2, 2, size+2, size+2), fill=(236,236,236,255))
    img = img.filter(ImageFilter.GaussianBlur(radius=0.6))
    img.save(OUT / "dot.png", "PNG")

if __name__ == "__main__":
    make_logo()
    make_dot()
    print(f"plymouth assets -> {OUT}")
