"""Draws the app icon (a cake with a candle). Own artwork. Usage: python3 -I make_icon.py <out.png>"""
import sys
from PIL import Image, ImageDraw
S = 4; N = 512 * S
im = Image.new('RGB', (N, N), (47, 179, 162)); d = ImageDraw.Draw(im)
def r(x0, y0, x1, y1, rad, fill): d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=rad * S, fill=fill)
r(96, 270, 416, 420, 34, (255, 246, 234))      # cake base
r(96, 236, 416, 318, 34, (255, 122, 89))       # frosting
for x in (140, 214, 288, 362): d.ellipse([(x - 22) * S, 296 * S, (x + 22) * S, 352 * S], fill=(255, 122, 89))
d.ellipse([236 * S, 214 * S, 276 * S, 254 * S], fill=(255, 246, 234))   # candle top blob
r(246, 160, 266, 240, 8, (255, 246, 234))      # candle
d.polygon([(256 * S, 90 * S), (284 * S, 138 * S), (256 * S, 160 * S), (228 * S, 138 * S)], fill=(255, 194, 77))   # flame
im.resize((512, 512), Image.LANCZOS).save(sys.argv[1]); print('saved')
