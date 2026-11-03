#!/usr/bin/env python3
"""ממיר את תמונות ה-PNG של דף הנחיתה (פלט של compose-landing-visuals.mjs) ל-AVIF ול-WebP,
ואת תמונת השיתוף ל-JPG. שומר שקיפות. שימוש: python3 -I scripts/export-landing-images.py <תיקיית PNG> <תיקיית פלט>
כל קובץ מקבל גרסת @1x (רוחב חצי) כדי שאפשר יהיה להגיש srcset."""
import sys
from pathlib import Path
from PIL import Image

src, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

def save(im, name, fmt, **kw):
    p = out / f"{name}.{fmt}"
    im.save(p, fmt.upper() if fmt != "jpg" else "JPEG", **kw)
    return p.stat().st_size

rows = []
for png in sorted(src.glob("*.png")):
    name = png.stem
    im = Image.open(png)
    if name == "og":
        im = im.convert("RGB").resize((1200, 630), Image.LANCZOS)
        size = save(im, "og", "jpg", quality=84, optimize=True, progressive=True)
        rows.append((name, im.size, "jpg", size))
        continue
    im = im.convert("RGBA")
    for scale, suffix in ((1.0, ""), (0.5, "@1x")):
        v = im if scale == 1.0 else im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        n = name + suffix
        rows.append((n, v.size, "avif", save(v, n, "avif", quality=55, speed=4)))
        rows.append((n, v.size, "webp", save(v, n, "webp", quality=82, method=6)))

for n, sz, fmt, b in rows:
    print(f"{n}.{fmt}\t{sz[0]}x{sz[1]}\t{b/1024:.1f}KB")
