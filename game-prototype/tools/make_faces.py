"""Draws the face atlases for the modeled characters (own artwork, no external assets).
The faces are drawn on a transparent background: the character shader paints the skin colour underneath, so one atlas
serves every skin tone. Two styles (f: lashes and thinner brows, m: thicker brows), nine expressions in a 3x3 grid.
Cell order (row by row): neutral, smile, happy, surprised, think, sad, annoyed, blink, talk.
The cell is the front of the head, projected flat: x in [-1, 1] across the head width, y in [-1, 1] top to bottom.
Usage: python3 -I make_faces.py <out_dir>"""
import os, sys, math
from PIL import Image, ImageDraw, ImageFilter

EXPRS = ['neutral', 'smile', 'happy', 'surprised', 'think', 'sad', 'annoyed', 'blink', 'talk']
CELL = 512
S = 3                       # supersampling
INK = (46, 26, 18, 255)
BROW = (74, 44, 28, 255)
IRIS = (112, 70, 38)
IRIS_DARK = (58, 34, 18)
MOUTH = (118, 36, 44, 255)
TONGUE = (226, 112, 122, 255)
TEETH = (252, 250, 246, 255)
LIP = (196, 96, 92, 200)
BLUSH = (240, 120, 120)

def P(x, y):
    """cell coordinates (-1..1) -> pixels in the supersampled cell"""
    return ((x + 1.0) * 0.5 * CELL * S, (y + 1.0) * 0.5 * CELL * S)

def cell(style, expr):
    im = Image.new('RGBA', (CELL * S, CELL * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def ell(x, y, rx, ry, fill, outline=None, width=0):
        a = P(x - rx, y - ry); b = P(x + rx, y + ry)
        d.ellipse([a, b], fill=fill, outline=outline, width=int(width * S))
    def arc(x, y, rx, ry, a0, a1, color, width):
        a = P(x - rx, y - ry); b = P(x + rx, y + ry)
        d.arc([a, b], a0, a1, fill=color, width=int(width * S))
    def poly(pts, fill):
        d.polygon([P(*p) for p in pts], fill=fill)
    # soft blush on a separate layer, blurred
    blush = Image.new('RGBA', im.size, (0, 0, 0, 0)); bd = ImageDraw.Draw(blush)
    for sx in (-1, 1):
        a = P(sx * 0.42 - 0.14, 0.24 - 0.07); b = P(sx * 0.42 + 0.14, 0.24 + 0.07)
        bd.ellipse([a, b], fill=BLUSH + (110 if expr in ('happy', 'smile', 'blink') else 70,))
    blush = blush.filter(ImageFilter.GaussianBlur(10 * S))
    im.alpha_composite(blush)
    ey = 0.02; ex = 0.33
    open_eyes = expr not in ('happy', 'blink')
    for sx in (-1, 1):
        cx = sx * ex
        if open_eyes:
            rx, ry = 0.19, 0.22
            if expr == 'surprised': rx, ry = 0.2, 0.25
            if expr in ('sad',): ry = 0.2
            if expr == 'annoyed': ry = 0.13
            ell(cx, ey, rx, ry, (255, 255, 255, 255))
            # pupil direction
            lx, ly = -sx * 0.02, 0.02
            if expr == 'think': lx, ly = 0.06, -0.07
            if expr == 'sad': ly = 0.05
            ir = 0.135 if expr != 'surprised' else 0.115
            if expr == 'annoyed': ir = 0.1
            # iris with a darker rim and a lighter lower half
            ell(cx + lx, ey + ly, ir, ir * 1.08, IRIS_DARK + (255,))
            ell(cx + lx, ey + ly + 0.01, ir * 0.86, ir * 0.92, IRIS + (255,))
            ell(cx + lx, ey + ly + 0.05, ir * 0.62, ir * 0.5, tuple(min(255, c + 40) for c in IRIS) + (255,))
            ell(cx + lx, ey + ly, ir * 0.48, ir * 0.52, (20, 12, 8, 255))
            ell(cx + lx - 0.05, ey + ly - 0.06, 0.045, 0.05, (255, 255, 255, 255))       # highlights
            ell(cx + lx + 0.05, ey + ly + 0.05, 0.02, 0.02, (255, 255, 255, 230))
            # lids: shape the eye with a skin-coloured cut-out is not possible here (skin is painted by the shader),
            # so the mood is shown with a lid line plus the brows
            lid_w = 7 if style == 'f' else 5
            arc(cx, ey + 0.005, rx + 0.01, ry + 0.01, 198, 342, INK, lid_w)
            if expr == 'annoyed':        # squinting: a flat lid line across the top of the eye
                d.line([P(cx - rx - 0.02, ey - ry + 0.02), P(cx + rx + 0.02, ey - ry + 0.02)], fill=INK, width=lid_w * S)
            if style == 'f':
                for k in range(3):       # lashes at the outer corner
                    a = math.radians(-20 - k * 22) if sx > 0 else math.radians(200 + k * 22)
                    x0 = cx + math.cos(a) * rx * 0.95; y0 = ey + math.sin(a) * ry * 0.95
                    x1 = cx + math.cos(a) * (rx + 0.07); y1 = ey + math.sin(a) * (ry + 0.06)
                    d.line([P(x0, y0), P(x1, y1)], fill=INK, width=4 * S)
            arc(cx, ey + 0.02, rx * 0.8, ry * 0.9, 30, 150, (0, 0, 0, 40), 3)              # soft lower lid
        elif expr == 'happy':
            arc(cx, ey + 0.08, 0.17, 0.15, 200, 340, INK, 9)
        else:
            arc(cx, ey - 0.04, 0.17, 0.12, 20, 160, INK, 8)
            if style == 'f':
                for k in range(2):
                    x = cx + sx * (0.12 + k * 0.05); d.line([P(x, ey + 0.05), P(x + sx * 0.03, ey + 0.1)], fill=INK, width=4 * S)
    # brows
    bw = 7 if style == 'f' else 11
    for sx in (-1, 1):
        cx = sx * ex; by = -0.3
        if expr == 'surprised': by = -0.38
        if expr == 'think' and sx > 0: by = -0.38
        if expr == 'sad':
            d.line([P(cx - sx * 0.14, by + 0.02), P(cx + sx * 0.14, by + 0.09)], fill=BROW, width=bw * S)
            continue
        if expr == 'annoyed':
            d.line([P(cx - sx * 0.15, by + 0.07), P(cx + sx * 0.15, by - 0.01)], fill=BROW, width=bw * S)
            continue
        arc(cx, by + 0.08, 0.17, 0.09, 205, 335, BROW, bw)
    # mouth
    my = 0.5
    if expr in ('smile', 'blink'):
        arc(0, my - 0.1, 0.2, 0.12, 25, 155, INK, 7)
        for sx in (-1, 1): ell(sx * 0.2, my - 0.06, 0.012, 0.012, (0, 0, 0, 80))
    elif expr == 'happy':
        d.chord([P(-0.22, my - 0.17), P(0.22, my + 0.17)], 0, 180, fill=MOUTH)
        d.chord([P(-0.2, my - 0.16), P(0.2, my - 0.06)], 0, 180, fill=TEETH)
        d.chord([P(-0.12, my + 0.02), P(0.12, my + 0.16)], 180, 360, fill=TONGUE)
        arc(0, my, 0.22, 0.17, 0, 180, INK, 5)
    elif expr == 'surprised':
        ell(0, my + 0.03, 0.08, 0.1, MOUTH); ell(0, my + 0.07, 0.05, 0.04, TONGUE)
    elif expr == 'think':
        d.line([P(-0.06, my + 0.01), P(0.13, my - 0.03)], fill=INK, width=6 * S)
    elif expr == 'sad':
        arc(0, my + 0.1, 0.13, 0.08, 205, 335, INK, 6)
    elif expr == 'annoyed':
        d.line([P(-0.11, my + 0.02), P(0.11, my + 0.02)], fill=INK, width=6 * S)
    elif expr == 'talk':
        d.chord([P(-0.12, my - 0.08), P(0.12, my + 0.1)], 0, 360, fill=MOUTH)
        d.chord([P(-0.07, my + 0.0), P(0.07, my + 0.1)], 180, 360, fill=TONGUE)
        d.chord([P(-0.11, my - 0.08), P(0.11, my - 0.02)], 0, 180, fill=TEETH)
    else:   # neutral
        arc(0, my - 0.05, 0.12, 0.06, 35, 145, INK, 6)
    if style == 'f' and expr in ('neutral', 'smile', 'blink', 'think', 'sad', 'annoyed'):
        arc(0, my - 0.05 if expr != 'sad' else my + 0.1, 0.1, 0.05, 40 if expr != 'sad' else 220, 140 if expr != 'sad' else 320, LIP, 4)
    return im.resize((CELL, CELL), Image.LANCZOS)

out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for style in ('f', 'm'):
    atlas = Image.new('RGBA', (CELL * 3, CELL * 3), (0, 0, 0, 0))
    for i, e in enumerate(EXPRS):
        atlas.paste(cell(style, e), ((i % 3) * CELL, (i // 3) * CELL))
    atlas.save(os.path.join(out, f'face_{style}.png')); print('saved', style, atlas.size)
