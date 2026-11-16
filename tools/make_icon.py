#!/usr/bin/env python3
"""Draw the 35x35 launcher icon shown in the watch's face picker.

Usage:  python3 tools/make_icon.py        (needs Pillow)
"""
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "resources", "drawables", "launcher_icon.png")

SIZE = 35
BLACK, WHITE, AMBER = (0, 0, 0, 255), (255, 255, 255, 255), (255, 255, 0, 255)

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.ellipse([0, 0, SIZE - 1, SIZE - 1], fill=BLACK)

# tick ring: three quarters lit
c = (SIZE - 1) / 2.0
for i in range(24):
    a = math.radians(i * 15 - 90)
    x, y = c + 15 * math.cos(a), c + 15 * math.sin(a)
    colour = AMBER if i < 18 else WHITE
    d.point((round(x), round(y)), fill=colour)
    if i < 18:
        x2, y2 = c + 14 * math.cos(a), c + 14 * math.sin(a)
        d.point((round(x2), round(y2)), fill=colour)

# a squared "A" built the same way as the numerals
x0, y0, w, h, t = 11, 9, 13, 17, 3
d.rectangle([x0, y0 + 2, x0 + t - 1, y0 + h - 1], fill=WHITE)  # left stem
d.rectangle([x0 + w - t, y0 + 2, x0 + w - 1, y0 + h - 1], fill=WHITE)  # right stem
d.rectangle([x0 + 2, y0, x0 + w - 3, y0 + t - 1], fill=WHITE)  # top bar
d.rectangle([x0 + 1, y0 + 1, x0 + w - 2, y0 + t - 1], fill=WHITE)
d.rectangle([x0, y0 + 8, x0 + w - 1, y0 + 8 + t - 1], fill=AMBER)  # cross bar

img.save(OUT)
print("wrote", os.path.normpath(OUT))
