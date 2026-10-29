"""Draws the face atlases for the stylized characters (own artwork, no external assets).
One PNG per skin tone, six expressions stacked vertically (equirectangular: the face is at the centre of each row).
Rows: 0 smile, 1 happy, 2 surprised, 3 think, 4 blink, 5 neutral.
Usage: python3 -I make_noa_face.py <out_dir>"""
import os, sys
from PIL import Image, ImageDraw

W, H, S = 1024, 512, 2
TONES = {
    'light':  dict(skin=(244, 200, 166), shade=(222, 168, 134), blush=(246, 150, 140), lip=(196, 88, 84)),
    'medium': dict(skin=(214, 160, 118), shade=(190, 134, 96),  blush=(226, 130, 112), lip=(160, 70, 62)),
    'deep':   dict(skin=(150, 98, 66),   shade=(126, 78, 52),   blush=(176, 90, 70),   lip=(112, 46, 40)),
}
EXPRS = ['smile', 'happy', 'surprised', 'think', 'blink', 'neutral']
INK = (52, 30, 20)

def face(tone, expr):
    t = TONES[tone]
    im = Image.new('RGB', (W * S, H * S), t['skin']); d = ImageDraw.Draw(im); cx = W * S // 2
    def ell(x, y, rx, ry, fill, outline=None, width=0):
        d.ellipse([cx + (x - rx) * S, (y - ry) * S, cx + (x + rx) * S, (y + ry) * S], fill=fill, outline=outline, width=width * S)
    def arc(x, y, rx, ry, a0, a1, color, width):
        d.arc([cx + (x - rx) * S, (y - ry) * S, cx + (x + rx) * S, (y + ry) * S], a0, a1, fill=color, width=int(width * S))
    for sx in (-1, 1):
        ell(sx * 70, 300, 34, 20, t['blush'])                          # cheeks
        ell(sx * 70, 300, 24, 13, tuple(min(255, c + 12) for c in t['blush']))
    ell(0, 306, 9, 6, t['shade'])                                       # nose
    open_eyes = expr in ('smile', 'surprised', 'think', 'neutral')
    for sx in (-1, 1):
        ex = sx * 52; ey = 262
        if open_eyes:
            big = expr == 'surprised'
            rx, ry = (34, 34) if big else (31, 28)
            ell(ex, ey, rx, ry, (255, 255, 255)); 
            ix = ex + (sx * -2 if expr != 'think' else 8)
            ell(ix, ey + 2, 21 if not big else 18, 23 if not big else 20, (98, 58, 34)); ell(ix, ey + 4, 13 if not big else 10, 14 if not big else 12, (24, 14, 10))
            ell(ix - 7, ey - 6, 7, 7, (255, 255, 255)); ell(ix + 6, ey + 9, 3.5, 3.5, (255, 255, 255))
            arc(ex, ey + 1, rx + 2, ry + 2, 196, 344, INK, 6)            # upper lid / lashes
            d.line([cx + (ex + sx * (rx + 1)) * S, (ey - 6) * S, cx + (ex + sx * (rx + 7)) * S, (ey - 10) * S], fill=INK, width=4 * S)
        elif expr == 'happy':
            arc(ex, ey + 12, 30, 24, 200, 340, INK, 7)                   # ^ ^ eyes
        else:
            arc(ex, ey - 6, 30, 22, 20, 160, INK, 7)                     # closed eyes
    for sx in (-1, 1):                                                  # brows
        bx = sx * 56; by = 214 if expr != 'surprised' else 200
        if expr == 'think' and sx == 1: by = 200
        arc(bx, by + 14, 30, 13, 212, 328, (92, 56, 34), 5)
    # mouth
    if expr == 'happy':
        d.pieslice([cx - 34 * S, 318 * S, cx + 34 * S, 372 * S], 0, 180, fill=(120, 40, 44))
        d.pieslice([cx - 20 * S, 346 * S, cx + 20 * S, 372 * S], 0, 180, fill=(236, 120, 130))
        arc(0, 334, 36, 22, 10, 170, INK, 4)
    elif expr == 'surprised':
        ell(0, 346, 13, 17, (120, 40, 44)); ell(0, 352, 8, 8, (236, 120, 130))
    elif expr == 'think':
        arc(8, 336, 24, 14, 20, 150, t['lip'], 5)
    elif expr == 'neutral':
        d.line([cx - 14 * S, 342 * S, cx + 14 * S, 342 * S], fill=t['lip'], width=5 * S)
    else:
        arc(0, 328, 38, 24, 20, 160, t['lip'], 6)
        for sx in (-1, 1): ell(sx * 38, 340, 3, 3, t['shade'])
    return im.resize((W // 2, H // 2), Image.LANCZOS)

out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for tone in TONES:
    atlas = Image.new('RGB', (W // 2, (H // 2) * len(EXPRS)))
    for i, e in enumerate(EXPRS): atlas.paste(face(tone, e), (0, i * (H // 2)))
    atlas.save(os.path.join(out, f'face_{tone}.png')); print('saved', tone, atlas.size)
