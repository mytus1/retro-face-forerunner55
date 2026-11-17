#!/usr/bin/env python3
"""Generate the bitmap fonts used by the Apogee watch face.

The Forerunner 55 has a 1-bit-per-channel display with no anti-aliasing, so
instead of rasterising an outline font (which goes ragged at these sizes) the
glyphs are *designed on the pixel grid*.

There are two numeral styles, switchable in the face's settings:

  * VHS      Drawn by hand on a coarse 8 x 14 grid, like the character
             generator of a video recorder.  Used as-is for the small data
             values and blown up 4x, blocks and all, for the time.
  * Squared  Built from seven straight strokes, then every outer corner is
             rounded and every inner corner left crisp: condensed, monoline,
             space-age display type.

Labels use a hand-drawn 5x7 pixel alphabet.

Outputs (in resources/fonts):
    apogee_time_vhs / apogee_data_vhs          VHS numerals, large and small
    apogee_time_square / apogee_data_square    squared numerals, large and small
    apogee_label                               small caps, digits, punctuation, icons
    apogee_label_bold                          same alphabet, one pixel heavier (date)

Usage:  python3 tools/make_fonts.py            (needs Pillow: pip install pillow)
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "resources", "fonts")
SS = 8  # supersampling factor used while rounding corners

# --------------------------------------------------------------------------
# Tunables.  Change these, re-run the script, rebuild the watch face.
# --------------------------------------------------------------------------
# Both styles must share the same footprint, because the layout in
# source/ApogeeView.mc is the same for both:
#   time numerals 32 x 56 with a 6 px gap, colon 8 px wide
#   data numerals  8 x 14 with a 2 px gap
#
# Squared style: w/h = glyph size in px, t = stroke thickness, r = outer
# corner radius, gap = space between glyphs.  (h - t) must be even so the
# middle bar centres.
TIME_SQUARE = dict(w=32, h=56, t=8, r=7, gap=6)
DATA_SQUARE = dict(w=8, h=14, t=2, r=2, gap=2)

# VHS style: the art below is 8 x 14 cells; the time shows each cell as a
# VHS_SCALE x VHS_SCALE block of pixels.
VHS_SCALE = 4
TIME_GAP = 6
DATA_GAP = 2


# --------------------------------------------------------------------------
# Tiny raster helpers (glyphs are lists of rows of 0/1)
# --------------------------------------------------------------------------
def blank(w, h):
    return [[0] * w for _ in range(h)]


def rect(g, x0, y0, x1, y1):
    for y in range(max(0, y0), min(len(g), y1)):
        for x in range(max(0, x0), min(len(g[0]), x1)):
            g[y][x] = 1


def from_art(rows):
    return [[1 if c == "#" else 0 for c in row] for row in rows]


def embolden(g):
    """Thicken a glyph by one pixel to the right (classic bitmap bold)."""
    return [[1 if (row[x] if x < len(row) else 0) or (x > 0 and row[x - 1]) else 0 for x in range(len(row) + 1)] for row in g]


def run(g, x, y, dx, dy):
    """Number of consecutive filled pixels starting at (x, y) heading (dx, dy)."""
    n = 0
    while 0 <= y < len(g) and 0 <= x < len(g[0]) and g[y][x]:
        n += 1
        x += dx
        y += dy
    return n


def round_corners(g, t, r_bend, r_end=0.0, r_inner=0.0):
    """Round the corners of a blocky glyph.

    Convex corners where a stroke *turns* get radius r_bend, convex corners at
    the free end of a stroke get r_end, concave corners get r_inner.
    """
    h, w = len(g), len(g[0])
    big = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    for y in range(h):
        for x in range(w):
            if g[y][x]:
                d.rectangle([x * SS, y * SS, x * SS + SS - 1, y * SS + SS - 1], fill=255)

    def px(x, y):
        return 1 if (0 <= x < w and 0 <= y < h and g[y][x]) else 0

    def patch(vx, vy, sx, sy, rad, convex):
        if rad <= 0:
            return
        n = int(round(rad * SS))
        x0 = vx * SS if sx > 0 else vx * SS - n
        y0 = vy * SS if sy > 0 else vy * SS - n
        tile = Image.new("L", (n, n), 0 if convex else 255)
        td = ImageDraw.Draw(tile)
        # circle centre is the tile corner furthest from the vertex
        cx = n if sx > 0 else 0
        cy = n if sy > 0 else 0
        td.ellipse([cx - n, cy - n, cx + n - 1, cy + n - 1], fill=255 if convex else 0)
        big.paste(tile, (x0, y0))

    for vy in range(h + 1):
        for vx in range(w + 1):
            quad = {
                (-1, -1): px(vx - 1, vy - 1),
                (1, -1): px(vx, vy - 1),
                (-1, 1): px(vx - 1, vy),
                (1, 1): px(vx, vy),
            }
            filled = sum(quad.values())
            if filled == 1:  # convex corner
                sx, sy = [k for k, v in quad.items() if v][0]
                cx = vx if sx > 0 else vx - 1
                cy = vy if sy > 0 else vy - 1
                rx = run(g, cx, cy, sx, 0)
                ry = run(g, cx, cy, 0, sy)
                is_bend = min(rx, ry) > t
                rad = r_bend if is_bend else r_end
                rad = min(rad, rx / 2.0, ry / 2.0) if not is_bend else rad
                patch(vx, vy, sx, sy, rad, True)
            elif filled == 3:  # concave corner
                sx, sy = [k for k, v in quad.items() if not v][0]
                patch(vx, vy, sx, sy, r_inner, False)

    small = big.resize((w, h), Image.BOX)
    return [[1 if small.getpixel((x, y)) >= 128 else 0 for x in range(w)] for y in range(h)]


# --------------------------------------------------------------------------
# Numerals
# --------------------------------------------------------------------------
SEGMENTS = {
    "0": "ABCDEF",
    "2": "ABGED",
    "3": "ABCDg",
    "4": "FGBC",
    "5": "AFGCD",
    "6": "AFEDCG",
    "7": "ABC",
    "8": "ABCDEFG",
    "9": "ABCDFG",
}


def numeral(ch, w, h, t, r, **_):
    g = blank(w, h)
    m0 = (h - t) // 2
    m1 = m0 + t
    if ch == "1":
        stem = (w - t) // 2 + max(1, t // 4)
        flag = max(2, int(round(t * 0.9)))
        rect(g, stem, 0, stem + t, h)
        rect(g, stem - flag, 0, stem, t)
    else:
        seg = {
            "A": (0, 0, w, t),
            "B": (w - t, 0, w, m1),
            "C": (w - t, m0, w, h),
            "D": (0, h - t, w, h),
            "E": (0, m0, t, h),
            "F": (0, 0, t, m1),
            "G": (0, m0, w, m1),
            "g": (int(round(w * 0.30)), m0, w, m1),  # short middle bar for "3"
        }
        for s in SEGMENTS[ch]:
            rect(g, *seg[s])
    return round_corners(g, t, r_bend=r, r_end=max(0.0, t / 9.0), r_inner=max(0.0, (t - 3) / 4.0))


def colon(w, h, t, **_):
    """Two square dots, vertically centred on the upper and lower counters."""
    g = blank(t, h)
    m0 = (h - t) // 2
    top = (t + m0 - t) // 2 + t // 2  # centre of upper counter, minus half a dot
    top = t + (m0 - t - t) // 2
    bot = h - t - (m0 - t - t) // 2 - t
    rect(g, 0, top, t, top + t)
    rect(g, 0, bot, t, bot + t)
    return round_corners(g, t + 1, r_bend=0, r_end=max(0.0, t / 4.5))


# --------------------------------------------------------------------------
# VHS numerals: 8 x 14 cells, strokes two cells thick, corners cut by one cell
# --------------------------------------------------------------------------
VHS = {
    "0": [
        "..####..",
        ".######.",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        ".######.",
        "..####..",
    ],
    "1": [
        "...##...",
        "..###...",
        ".####...",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
        ".######.",
        ".######.",
    ],
    "2": [
        "..####..",
        ".######.",
        "##....##",
        "##....##",
        "......##",
        ".....###",
        "....###.",
        "...###..",
        "..###...",
        ".###....",
        "###.....",
        "##......",
        "########",
        "########",
    ],
    "3": [
        "..####..",
        ".######.",
        "##....##",
        "......##",
        "......##",
        "......##",
        "...####.",
        "...####.",
        "......##",
        "......##",
        "......##",
        "##....##",
        ".######.",
        "..####..",
    ],
    "4": [
        ".....##.",
        "....###.",
        "...####.",
        "..##.##.",
        ".##..##.",
        "##...##.",
        "##...##.",
        "##...##.",
        "########",
        "########",
        ".....##.",
        ".....##.",
        ".....##.",
        ".....##.",
    ],
    "5": [
        "########",
        "########",
        "##......",
        "##......",
        "##......",
        "######..",
        "#######.",
        "......##",
        "......##",
        "......##",
        "......##",
        "##....##",
        ".######.",
        "..####..",
    ],
    "6": [
        "..####..",
        ".######.",
        "##....##",
        "##......",
        "##......",
        "######..",
        "#######.",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        ".######.",
        "..####..",
    ],
    "7": [
        "########",
        "########",
        "......##",
        "......##",
        ".....##.",
        ".....##.",
        "....##..",
        "....##..",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
        "...##...",
    ],
    "8": [
        "..####..",
        ".######.",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        ".######.",
        ".######.",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        ".######.",
        "..####..",
    ],
    "9": [
        "..####..",
        ".######.",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        "##....##",
        ".#######",
        "..######",
        "......##",
        "......##",
        "##....##",
        ".######.",
        "..####..",
    ],
    ":": ["..", "..", "..", "##", "##", "..", "..", "..", "..", "##", "##", "..", "..", ".."],
}


def scale(g, n):
    """Blow a glyph up n times, keeping every cell a hard-edged block."""
    out = []
    for row in g:
        wide = [v for v in row for _ in range(n)]
        out.extend([list(wide) for _ in range(n)])
    return out


# Punctuation for the small data numerals (14 rows tall, shared by both styles)
DATA_EXTRA = {
    ":": ["..", "..", "..", "##", "##", "..", "..", "..", "..", "##", "##", "..", "..", ".."],
    ".": [".."] * 12 + ["##"] * 2,
    "-": ["....."] * 6 + ["#####"] * 2 + ["....."] * 6,
    "%": [
        "###...##",
        "#.#...##",
        "###..##.",
        ".....##.",
        "....##..",
        "....##..",
        "...##...",
        "...##...",
        "..##....",
        "..##....",
        ".##..###",
        ".##..#.#",
        "##...###",
        "##......",
    ],
    "°": [".##.", "#..#", "#..#", ".##."] + ["...."] * 10,
    # "K" for thousands, e.g. 12.4K steps
    "K": [
        "##..##",
        "##..##",
        "##.##.",
        "##.##.",
        "####..",
        "####..",
        "###...",
        "###...",
        "####..",
        "####..",
        "##.##.",
        "##.##.",
        "##..##",
        "##..##",
    ],
    " ": ["...."] * 14,
}

# --------------------------------------------------------------------------
# 5x7 label alphabet
# --------------------------------------------------------------------------
LABEL = {
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    # digits echo the squared construction of the big numerals
    "0": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "1": [".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###"],
    "2": ["####.", "....#", "....#", ".###.", "#....", "#....", "#####"],
    "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
    "4": ["#...#", "#...#", "#...#", ".####", "....#", "....#", "....#"],
    "5": ["#####", "#....", "#....", "####.", "....#", "....#", "####."],
    "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["####.", "....#", "....#", "....#", "....#", "....#", "....#"],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
    " ": ["...", "...", "...", "...", "...", "...", "..."],
    ".": [".", ".", ".", ".", ".", ".", "#"],
    ":": [".", ".", "#", ".", "#", ".", "."],
    "-": ["...", "...", "...", "###", "...", "...", "..."],
    "+": ["...", "...", ".#.", "###", ".#.", "...", "..."],
    "/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
    "%": ["##..#", "##.#.", "...#.", "..#..", ".#...", ".#.##", "#..##"],
    "°": [".#.", "#.#", ".#.", "...", "...", "...", "..."],
    # ---- icons (mapped onto otherwise unused ASCII) ----
    # "<"  phone link lost: bluetooth rune with a cross
    "<": [
        "..#......",
        "..##.....",
        "#.#.#....",
        ".###.....",
        "#.#.#.#.#",
        "..##...#.",
        "..#...#.#",
    ],
    # ">"  unread notifications: envelope
    ">": [
        ".........",
        "#########",
        "##.....##",
        "#.##.##.#",
        "#...#...#",
        "#########",
        ".........",
    ],
    # "*"  heart
    "*": [
        ".##.##.",
        "#######",
        "#######",
        "#######",
        ".#####.",
        "..###..",
        "...#...",
    ],
    # "^"  alarm set: bell
    "^": [
        "...#...",
        "..###..",
        ".#####.",
        ".#####.",
        ".#####.",
        "#######",
        "...#...",
    ],
    # "~"  do not disturb: crescent moon
    "~": [
        "..###..",
        ".##....",
        "##.....",
        "##.....",
        "##.....",
        ".##...#",
        "..####.",
    ],
}


# --------------------------------------------------------------------------
# Atlas + .fnt writer
# --------------------------------------------------------------------------
def write_font(name, glyphs, gap, line_height):
    """glyphs: list of (char, rows).  Writes <name>.png and <name>.fnt."""
    pad = 1
    width = sum(len(rows[0]) + pad for _, rows in glyphs) + pad
    height = max(len(rows) for _, rows in glyphs) + 2 * pad
    # round the atlas up to a multiple of 4 - keeps every importer happy
    width += (-width) % 4
    height += (-height) % 4
    atlas = Image.new("L", (width, height), 0)
    lines = []
    x = pad
    for ch, rows in glyphs:
        w, h = len(rows[0]), len(rows)
        for yy in range(h):
            for xx in range(w):
                if rows[yy][xx]:
                    atlas.putpixel((x + xx, pad + yy), 255)
        lines.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15"
            % (ord(ch), x, pad, w, h, w + gap)
        )
        x += w + pad
    os.makedirs(OUT, exist_ok=True)
    atlas.save(os.path.join(OUT, name + ".png"))
    with open(os.path.join(OUT, name + ".fnt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(
            'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
            "padding=0,0,0,0 spacing=1,1 outline=0\n" % (name, line_height)
        )
        f.write(
            "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=4 "
            "greenChnl=4 blueChnl=4\n" % (line_height, line_height, width, height)
        )
        f.write('page id=0 file="%s.png"\n' % name)
        f.write("chars count=%d\n" % len(glyphs))
        f.write("\n".join(lines) + "\n")
    return atlas


def build():
    fonts = {}

    def data_extras():
        out = []
        for c, art in DATA_EXTRA.items():
            assert len(art) == 14 and len(set(len(r) for r in art)) == 1, c
            out.append((c, from_art(art)))
        return out

    # VHS: one drawing, two sizes
    for c, art in VHS.items():
        assert len(art) == 14 and len(set(len(r) for r in art)) == 1, c
    big = [(c, scale(from_art(VHS[c]), VHS_SCALE)) for c in "0123456789:"]
    fonts["apogee_time_vhs"] = write_font("apogee_time_vhs", big, TIME_GAP, 14 * VHS_SCALE)
    small = [(c, from_art(VHS[c])) for c in "0123456789"]
    fonts["apogee_data_vhs"] = write_font("apogee_data_vhs", small + data_extras(), DATA_GAP, 14)

    # Squared: generated from strokes at each size
    big = [(c, numeral(c, **TIME_SQUARE)) for c in "0123456789"]
    big.append((":", colon(**TIME_SQUARE)))
    fonts["apogee_time_square"] = write_font("apogee_time_square", big, TIME_SQUARE["gap"], TIME_SQUARE["h"])
    small = [(c, numeral(c, **DATA_SQUARE)) for c in "0123456789"]
    fonts["apogee_data_square"] = write_font("apogee_data_square", small + data_extras(), DATA_SQUARE["gap"], DATA_SQUARE["h"])

    label_glyphs = []
    for c, art in LABEL.items():
        assert len(art) == 7 and len(set(len(r) for r in art)) == 1, c
        label_glyphs.append((c, from_art(art)))
    fonts["apogee_label"] = write_font("apogee_label", label_glyphs, 1, 7)

    # A heavier cut of the same alphabet, used for the date line.
    bold_glyphs = [(c, embolden(g)) for c, g in label_glyphs if c not in "<>*^~"]
    fonts["apogee_label_bold"] = write_font("apogee_label_bold", bold_glyphs, 1, 7)
    return fonts


def preview(fonts, path, scale=4):
    w = max(a.width for a in fonts.values()) * scale
    h = sum(a.height * scale + 8 for a in fonts.values())
    sheet = Image.new("L", (w, h), 40)
    y = 0
    for a in fonts.values():
        sheet.paste(a.resize((a.width * scale, a.height * scale), Image.NEAREST), (0, y))
        y += a.height * scale + 8
    sheet.save(path)


if __name__ == "__main__":
    built = build()
    for n, a in built.items():
        print("%-13s atlas %dx%d" % (n, a.width, a.height))
    if len(sys.argv) > 1:
        preview(built, sys.argv[1])
        print("preview ->", sys.argv[1])
