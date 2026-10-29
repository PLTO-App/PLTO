# Post-process exported character GLBs: hair/brows/lashes/eyes -> alpha cut-out (MASK), everything else opaque.
import json, struct, sys
CUT = ('hair', 'ponytail', 'eyebrow', 'eyelash', 'high-poly')
for path in sys.argv[1:]:
    b = open(path, 'rb').read()
    magic, ver, total = struct.unpack('<III', b[:12]); jl, jt = struct.unpack('<II', b[12:20]); js = json.loads(b[20:20 + jl]); rest = b[20 + jl:]
    for m in js['materials']:
        if any(k in m['name'].lower() for k in CUT): m['alphaMode'] = 'MASK'; m['alphaCutoff'] = 0.5; m['doubleSided'] = True
        else: m.pop('alphaMode', None); m.pop('alphaCutoff', None); m['doubleSided'] = False
    js_b = json.dumps(js, separators=(',', ':')).encode(); js_b += b' ' * ((4 - len(js_b) % 4) % 4)
    out = struct.pack('<III', magic, ver, 12 + 8 + len(js_b) + len(rest)) + struct.pack('<II', len(js_b), jt) + js_b + rest
    open(path, 'wb').write(out); print('fixed', path.split('/')[-1], [(m['name'], m.get('alphaMode', 'OPAQUE')) for m in js['materials']])
