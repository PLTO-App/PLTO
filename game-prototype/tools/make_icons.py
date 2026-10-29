"""Draws the product icons and the order bubble (own artwork). Usage: python3 -I make_icons.py <out_dir>"""
import os, sys
from PIL import Image, ImageDraw
S = 4
def canvas(w, h): return Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
def fin(im, w, h, path): im.resize((w, h), Image.LANCZOS).save(path)
def rr(d, b, r, fill, outline=None, width=0): d.rounded_rectangle([v * S for v in b], radius=r * S, fill=fill, outline=outline, width=width * S)
def el(d, b, fill, outline=None, width=0): d.ellipse([v * S for v in b], fill=fill, outline=outline, width=width * S)
out = sys.argv[1]; os.makedirs(out, exist_ok=True)

# strawberry chocolate cake
im = canvas(128, 128); d = ImageDraw.Draw(im)
el(d, (14, 98, 114, 118), (190, 140, 110)); rr(d, (22, 62, 106, 108), 8, (92, 52, 38)); rr(d, (22, 82, 106, 92), 2, (250, 220, 220))
rr(d, (18, 50, 110, 72), 10, (255, 122, 150))
for x in (30, 52, 74, 96): el(d, (x - 8, 62, x + 8, 82), (255, 122, 150))
for x, y in ((40, 42), (64, 36), (88, 42)):
    el(d, (x - 10, y - 8, x + 10, y + 14), (216, 40, 60)); d.polygon([(x * S, (y - 14) * S), ((x - 6) * S, (y - 6) * S), ((x + 6) * S, (y - 6) * S)], fill=(70, 150, 70))
fin(im, 128, 128, os.path.join(out, 'icon_cake.png'))
# carrot cake
im = canvas(128, 128); d = ImageDraw.Draw(im)
el(d, (14, 98, 114, 118), (190, 140, 110)); rr(d, (22, 58, 106, 108), 8, (200, 120, 60)); rr(d, (22, 76, 106, 86), 2, (255, 246, 234)); rr(d, (18, 44, 110, 66), 10, (255, 246, 234))
for x in (36, 64, 92): d.polygon([((x - 8) * S, 36 * S), ((x + 8) * S, 36 * S), (x * S, 66 * S)], fill=(240, 130, 40)); d.polygon([(x * S, 30 * S), ((x - 5) * S, 38 * S), ((x + 5) * S, 38 * S)], fill=(80, 160, 70))
fin(im, 128, 128, os.path.join(out, 'icon_carrot.png'))
# croissant
im = canvas(128, 128); d = ImageDraw.Draw(im)
el(d, (14, 100, 114, 118), (190, 140, 110))
d.pieslice([14 * S, 40 * S, 114 * S, 130 * S], 180, 360, fill=(222, 150, 70))
for i, x in enumerate((38, 52, 64, 76, 90)):
    d.arc([(x - 22) * S, 38 * S, (x + 22) * S, 120 * S], 200, 340, fill=(160, 90, 40), width=3 * S)
d.pieslice([30 * S, 56 * S, 98 * S, 112 * S], 180, 360, fill=(236, 170, 90))
fin(im, 128, 128, os.path.join(out, 'icon_croissant.png'))
# order bubble (with tail)
im = canvas(192, 176); d = ImageDraw.Draw(im)
rr(d, (8, 8, 184, 140), 38, (0, 0, 0, 70)); rr(d, (4, 4, 180, 136), 38, (255, 250, 240), (255, 255, 255), 0)
d.polygon([(70 * S, 130 * S), (110 * S, 130 * S), (86 * S, 168 * S)], fill=(255, 250, 240))
fin(im, 192, 176, os.path.join(out, 'bubble.png'))
# soft blob shadow
sh = Image.new('RGBA', (128, 128), (0, 0, 0, 0)); px = sh.load()
for y in range(128):
    for x in range(128):
        r = (((x - 63.5) ** 2 + (y - 63.5) ** 2) ** 0.5) / 63.5
        px[x, y] = (0, 0, 0, int(max(0.0, 1.0 - r) ** 1.4 * 150))
sh.save(os.path.join(out, 'blob_shadow.png'))
print('ok', sorted(os.listdir(out)))
