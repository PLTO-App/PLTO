"""Builds Noa's round portrait for the top bar from the face atlas (own artwork).
Usage: python3 -I make_avatar.py <face_light.png> <out.png>"""
import sys
from PIL import Image, ImageDraw
S = 4; N = 128 * S
atlas = Image.open(sys.argv[1]).convert('RGB')
face = atlas.crop((176, 62, 336, 222)).resize((N, N), Image.LANCZOS)
im = Image.new('RGBA', (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.ellipse([0, 0, N - 1, N - 1], fill=(255, 194, 77, 255))                      # gold ring
mask = Image.new('L', (N, N), 0); ImageDraw.Draw(mask).ellipse([6 * S, 6 * S, N - 6 * S, N - 6 * S], fill=255)
disc = Image.new('RGBA', (N, N), (0, 0, 0, 0)); disc.paste(face, (0, 0), mask); im.alpha_composite(disc)
hair = Image.new('RGBA', (N, N), (0, 0, 0, 0)); hd = ImageDraw.Draw(hair)
hd.pieslice([6 * S, 6 * S, N - 6 * S, N - 6 * S], 180, 360, fill=(91, 58, 41, 255))                    # hair across the top
hd.ellipse([20 * S, 22 * S, N - 20 * S, 66 * S], fill=(244, 200, 166, 255))                           # forehead
hd.pieslice([14 * S, 14 * S, N - 14 * S, 60 * S], 190, 350, fill=(91, 58, 41, 255))                   # fringe
hair2 = Image.new('RGBA', (N, N), (0, 0, 0, 0)); hair2.paste(hair, (0, 0), mask); im.alpha_composite(hair2)
d2 = ImageDraw.Draw(im); d2.ellipse([0, 0, N - 1, N - 1], outline=(255, 194, 77, 255), width=6 * S)
im.resize((128, 128), Image.LANCZOS).save(sys.argv[2]); print('saved')
