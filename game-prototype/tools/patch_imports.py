# One shared compression policy for BOTH asset sets: VRAM compressed + mipmaps, normal maps flagged.
import sys, glob, re, os
G = sys.argv[1]; n = 0
for f in glob.glob(G + '/**/*.import', recursive=True):
    if '/.godot/' in f: continue
    t = open(f).read()
    if 'importer="texture"' not in t: continue
    src = re.search(r'source_file="([^"]+)"', t).group(1).lower()
    if src.endswith('.hdr'): continue
    is_nor = ('nor' in os.path.basename(src)) and ('norm' in os.path.basename(src) or 'nor_gl' in src or os.path.basename(src).startswith('nor.') or '_nor' in src)
    t = re.sub(r'compress/mode=\d', 'compress/mode=2', t)
    t = re.sub(r'mipmaps/generate=\w+', 'mipmaps/generate=true', t)
    t = re.sub(r'compress/normal_map=\d', 'compress/normal_map=%d' % (1 if is_nor else 0), t)
    open(f, 'w').write(t); n += 1
print('patched', n)
