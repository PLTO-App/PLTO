"""The app icon of PLTO Virtual, drawn by code (Pillow): an original isometric mini-city on a navy field, with an orbit ring for "virtual".
Colours follow the PLTO brand: navy #0F1F3D, blue #2563EB, gold. Writes:
  icon.png (512, the project icon), assets/icon/launcher_192.png (legacy launcher icon),
  assets/icon/adaptive_fg_432.png, adaptive_bg_432.png, adaptive_mono_432.png (Android adaptive icon layers; the artwork stays in the central 66%).
  python3 -I tools/make_virtual_icon.py <game_dir>"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

game = sys.argv[1]
S = 1728                                  # 432 x 4, drawn big and scaled down for smooth edges
NAVY = (15, 31, 61); NAVY2 = (22, 52, 100); BLUE = (37, 99, 235)

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def background():
    im = Image.new("RGB", (S, S), NAVY)
    d = ImageDraw.Draw(im)
    for y in range(S):                    # vertical gradient, lighter at the top
        d.line([(0, y), (S, y)], fill=lerp(NAVY2, NAVY, y / S))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.ellipse([S * 0.12, S * 0.45, S * 0.88, S * 1.15], fill=BLUE + (120,))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.09))
    im = Image.alpha_composite(im.convert("RGBA"), glow)
    d = ImageDraw.Draw(im, "RGBA")
    # a faint street grid in perspective and a dark skyline at the bottom: the world around the icon
    for i in range(-8, 9):
        d.line([(S / 2 + i * S * 0.07, S * 0.62), (S / 2 + i * S * 0.25, S)], fill=(120, 160, 255, 26), width=3)
    for k in range(1, 6):
        y = S * (0.62 + 0.38 * (k / 5) ** 1.7)
        d.line([(0, y), (S, y)], fill=(120, 160, 255, 22), width=3)
    x = 0
    seed = [0.10, 0.17, 0.12, 0.22, 0.14, 0.19, 0.11, 0.16, 0.21, 0.13, 0.18, 0.12]
    for i, h in enumerate(seed):
        w = S * 0.085
        d.rectangle([x, S * (1 - h), x + w, S], fill=(10, 22, 46, 255)); x += w + 2
    return im

def iso(cx, cy, u):
    c, s = math.cos(math.radians(30)), math.sin(math.radians(30))
    return lambda x, y, z: (cx + (x - y) * c * u, cy + (x + y) * s * u - z * u)

def box(d, p, x, y, w, dd, h, top, left, right, windows=None):
    A = p(x, y, h); B = p(x + w, y, h); C = p(x + w, y + dd, h); D = p(x, y + dd, h)
    d.polygon([A, B, C, D], fill=top)
    d.polygon([D, C, p(x + w, y + dd, 0), p(x, y + dd, 0)], fill=left)
    d.polygon([C, B, p(x + w, y, 0), p(x + w, y + dd, 0)], fill=right)
    if windows:                            # small lit windows on the left face
        cols, rows, col = windows
        for i in range(cols):
            for j in range(rows):
                x0 = x + w * (0.14 + 0.86 * i / cols * 0.98); x1 = x0 + w * 0.5 / cols
                z0 = h * (0.12 + 0.8 * j / rows); z1 = z0 + h * 0.42 / rows
                d.polygon([p(x0, y + dd, z1), p(x1, y + dd, z1), p(x1, y + dd, z0), p(x0, y + dd, z0)], fill=col)

def foreground(mono=False):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im, "RGBA")
    p = iso(S * 0.5, S * 0.60, S * 0.092)
    W = (255, 255, 255, 255)
    if mono:
        top = left = right = W; ring = W; gold_t = gold_l = gold_r = W; win = None
    else:
        top, left, right = (96, 142, 250, 255), (37, 99, 235, 255), (26, 68, 176, 255)
        gold_t, gold_l, gold_r = (255, 217, 120, 255), (245, 166, 35, 255), (196, 124, 20, 255)
        ring = (255, 215, 120, 235); win = (255, 236, 170, 255)
    # the orbit ring: behind the buildings, with its lower half drawn again in front
    bb = [S * 0.14, S * 0.40, S * 0.86, S * 0.80]
    d.ellipse(bb, outline=ring, width=int(S * 0.018))
    # three buildings stepping up from the left, and a gold cube on the tallest
    box(d, p, -3.1, -0.6, 1.5, 1.5, 2.3, (236, 242, 255, 255) if not mono else W, (210, 222, 246, 255) if not mono else W, (170, 188, 224, 255) if not mono else W, None if mono else (2, 3, (120, 160, 255, 255)))
    box(d, p, -1.0, -0.2, 1.6, 1.6, 3.6, top, left, right, None if mono else (2, 4, win))
    box(d, p, 1.2, -0.5, 1.4, 1.4, 1.7, (236, 242, 255, 255) if not mono else W, (210, 222, 246, 255) if not mono else W, (170, 188, 224, 255) if not mono else W, None if mono else (2, 2, (120, 160, 255, 255)))
    pt = lambda x, y, z: p(x, y, z + 3.6)          # the gold cube sits on top of the blue tower
    box(d, pt, -0.6, 0.2, 0.8, 0.8, 1.0, gold_t, gold_l, gold_r)
    d.arc(bb, 12, 168, fill=ring, width=int(S * 0.018))
    # a soft shadow under the group for depth
    if not mono:
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse([S * 0.18, S * 0.70, S * 0.82, S * 0.84], fill=(0, 0, 0, 90))
        sh = sh.filter(ImageFilter.GaussianBlur(S * 0.025))
        im = Image.alpha_composite(sh, im)
    # the artwork stays inside the safe zone of an adaptive icon (the launcher may crop to a circle)
    k = 0.84
    small = im.resize((int(S * k), int(S * k)), Image.LANCZOS)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0)); out.paste(small, (int(S * (1 - k) / 2), int(S * (1 - k) / 2 + S * 0.01)))
    return out

def rounded(im, r):
    m = Image.new("L", im.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], radius=int(im.size[0] * r), fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0)); out.paste(im, (0, 0), m); return out

bg = background(); fg = foreground(); mono = foreground(True)
full = Image.alpha_composite(bg.convert("RGBA"), fg)
os.makedirs(os.path.join(game, "assets", "icon"), exist_ok=True)
rounded(full, 0.22).resize((512, 512), Image.LANCZOS).save(os.path.join(game, "icon.png"))
rounded(full, 0.22).resize((192, 192), Image.LANCZOS).save(os.path.join(game, "assets/icon/launcher_192.png"))
fg.resize((432, 432), Image.LANCZOS).save(os.path.join(game, "assets/icon/adaptive_fg_432.png"))
bg.convert("RGB").resize((432, 432), Image.LANCZOS).save(os.path.join(game, "assets/icon/adaptive_bg_432.png"))
mono.resize((432, 432), Image.LANCZOS).save(os.path.join(game, "assets/icon/adaptive_mono_432.png"))
print("icons written")
