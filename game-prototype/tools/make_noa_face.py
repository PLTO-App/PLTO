"""Draws the face texture for the stand-in Noa (equirectangular, front of the head at the centre). Own artwork, no external assets.
Usage: python3 -I make_noa_face.py <out.png>"""
import sys
from PIL import Image, ImageDraw

W, H = 1024, 512
S = 2  # supersample for smooth edges
im = Image.new('RGB', (W * S, H * S), (232, 184, 148))
d = ImageDraw.Draw(im)
cx = W * S // 2

def ell(x, y, rx, ry, fill, outline=None, width=0):
    d.ellipse([cx + (x - rx) * S, (y - ry) * S, cx + (x + rx) * S, (y + ry) * S], fill=fill, outline=outline, width=width)

# soft cheeks
for sx in (-1, 1):
    ell(sx * 62, 292, 30, 18, (240, 160, 140))
    ell(sx * 62, 292, 22, 13, (244, 150, 132))
# nose shade
ell(0, 300, 11, 8, (214, 160, 126))
# eyes
for sx in (-1, 1):
    ex = sx * 44
    ell(ex, 262, 24, 17, (255, 255, 255))
    ell(ex + sx * 1, 263, 13, 14, (84, 52, 30))
    ell(ex + sx * 1, 264, 7, 8, (20, 12, 8))
    ell(ex - 4, 257, 4, 4, (255, 255, 255))
    # upper lash line
    d.arc([cx + (ex - 26) * S, 242 * S, cx + (ex + 26) * S, 282 * S], 200, 340, fill=(40, 24, 16), width=5 * S)
    # brows
    bx = sx * 46
    d.arc([cx + (bx - 30) * S, 214 * S, cx + (bx + 30) * S, 250 * S], 205, 335, fill=(70, 42, 26), width=6 * S)
# smile
d.arc([cx - 36 * S, 322 * S, cx + 36 * S, 366 * S], 20, 160, fill=(150, 62, 56), width=5 * S)
im = im.resize((W, H), Image.LANCZOS)
im.save(sys.argv[1])
print('saved', sys.argv[1])
