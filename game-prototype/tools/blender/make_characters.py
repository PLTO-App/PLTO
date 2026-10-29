"""Builds the game's characters in Blender from code (own work, no external assets) and exports them to GLB.

One file per body type (char_f.glb, char_m.glb). Each holds:
  - Armature with a small human skeleton (Z up, the character looks toward -Y, which becomes +Z in Godot).
  - Body: one skinned mesh (body + head) built with a Skin modifier and subdivision, so joints bend smoothly.
    Vertex colours are masks for the clothing (R top, G bottom, B shoes, A sleeves area) and UV2 holds
    (limb position 0..1, apron mask). The character shader in Godot paints skin, clothes and the face from them,
    so every outfit is just a few colours, and the whole body is a single draw call.
  - Hair_* and Acc_* meshes (hair styles, beard, glasses, cap), all bound to the head bone. Godot shows one hair style.
  - Animations (actions): idle, walk, carry_idle, carry_walk, give, happy, wave, talk, think, sad, work, sit, sit_type, sit_drink.

Run: blender -b --factory-startup --python make_characters.py -- <out_dir>
"""
import bpy, bmesh, math, sys, os
from mathutils import Vector

OUT = sys.argv[sys.argv.index('--') + 1]
FPS = 24

# ------------------------------------------------------------------ proportions
# Joint positions are shared; widths differ by body type. Units are game units (1 unit = 1/1.43 m), 2.45 tall.
COMMON = dict(pelvis=1.02, waist=1.2, chest=1.42, upper=1.58, neck=1.68, neck_top=1.84, head_c=2.08,
              hip_x=0.1, knee_z=0.55, ankle_z=0.12, arm_tilt=30.0, upper_arm=0.3, forearm=0.27, hand=0.13)
BODY = {
    'f': dict(shoulder_x=0.18, r_pelvis=(0.215, 0.16), r_waist=(0.16, 0.125), r_chest=(0.185, 0.16), r_upper=(0.19, 0.125),
              r_neck=0.062, r_shoulder=0.08, r_elbow=0.062, r_wrist=0.05, r_hand=0.062, r_thigh=0.125, r_knee=0.082, r_ankle=0.062,
              r_toe=0.072, head=(0.27, 0.265, 0.295)),
    'm': dict(shoulder_x=0.22, r_pelvis=(0.19, 0.145), r_waist=(0.185, 0.14), r_chest=(0.215, 0.15), r_upper=(0.23, 0.135),
              r_neck=0.075, r_shoulder=0.092, r_elbow=0.072, r_wrist=0.058, r_hand=0.068, r_thigh=0.125, r_knee=0.088, r_ankle=0.066,
              r_toe=0.078, head=(0.27, 0.265, 0.295)),
}

def V(x, y, z): return Vector((x, y, z))

def joints(b):
    c = COMMON; j = {}
    j['pelvis'] = V(0, 0, c['pelvis']); j['waist'] = V(0, 0, c['waist']); j['chest'] = V(0, 0, c['chest'])
    j['upper'] = V(0, 0, c['upper']); j['neck'] = V(0, 0, c['neck']); j['neck_top'] = V(0, 0, c['neck_top'])
    j['head_top'] = V(0, 0, c['head_c'] + b['head'][2])
    a = math.radians(c['arm_tilt'])
    for side, sx in (('L', 1), ('R', -1)):
        d = V(sx * math.sin(a), 0, -math.cos(a))
        sh = V(sx * b['shoulder_x'], 0, c['upper'] + 0.01)
        j['sh' + side] = sh; j['el' + side] = sh + d * c['upper_arm']; j['wr' + side] = j['el' + side] + d * c['forearm']
        j['hm' + side] = j['wr' + side] + d * 0.065; j['he' + side] = j['wr' + side] + d * c['hand']
        j['th' + side] = j['wr' + side] + d * 0.02 + V(0, -0.045, -0.02)
        j['hp' + side] = V(sx * c['hip_x'], 0, c['pelvis'] - 0.04); j['kn' + side] = V(sx * (c['hip_x'] + 0.005), -0.01, c['knee_z'])
        j['an' + side] = V(sx * (c['hip_x'] + 0.005), 0, c['ankle_z']); j['to' + side] = V(sx * (c['hip_x'] + 0.008), -0.17, 0.05)
        j['hl' + side] = V(sx * (c['hip_x'] + 0.005), 0.045, 0.06)
    return j

# ------------------------------------------------------------------ helpers
def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS

def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj

def activate(obj):
    for o in bpy.context.view_layer.objects: o.select_set(False)
    bpy.context.view_layer.objects.active = obj; obj.select_set(True)

def apply_mods(obj):
    activate(obj)
    for m in list(obj.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)

def smoothstep(a, b, x):
    if b == a: return 1.0 if x >= b else 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a))); return t * t * (3 - 2 * t)

def seg_project(p, a, b):
    ab = b - a; L2 = ab.length_squared
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, (p - a).dot(ab) / L2))
    return t, (a + ab * t - p).length

def poly_project(p, pts, radii):
    """distance to a polyline, normalised by the local radius, and the position along it (0..1 by length)"""
    total = sum((pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)); best = (1e9, 0.0, 0.0); acc = 0.0
    for i in range(len(pts) - 1):
        t, d = seg_project(p, pts[i], pts[i + 1]); L = (pts[i + 1] - pts[i]).length
        r = radii[i] + (radii[i + 1] - radii[i]) * t
        nd = d / max(0.02, r)
        if nd < best[0]: best = (nd, (acc + L * t) / total, d)
        acc += L
    return best    # (normalised distance, param, distance)

# ------------------------------------------------------------------ armature
BONES = []   # (name, head, tail, parent, roll_axis)

def build_armature(j):
    arm_data = bpy.data.armatures.new('Armature'); arm = link(bpy.data.objects.new('Armature', arm_data))
    activate(arm); bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones; fwd = V(0, -1, 0); up = V(0, 0, 1)
    spec = [('root', V(0, 0, 0), V(0, 0, 0.3), None, fwd),
            ('hips', j['pelvis'], j['waist'], 'root', fwd), ('spine', j['waist'], j['chest'], 'hips', fwd),
            ('chest', j['chest'], j['neck'], 'spine', fwd), ('neck', j['neck'], j['neck_top'] - V(0, 0, 0.04), 'chest', fwd),
            ('head', j['neck_top'] - V(0, 0, 0.04), j['head_top'], 'neck', fwd)]
    for s in ('L', 'R'):
        spec += [('upper_arm.' + s, j['sh' + s], j['el' + s], 'chest', fwd), ('forearm.' + s, j['el' + s], j['wr' + s], 'upper_arm.' + s, fwd),
                 ('hand.' + s, j['wr' + s], j['he' + s], 'forearm.' + s, fwd),
                 ('thigh.' + s, j['hp' + s], j['kn' + s], 'hips', fwd), ('shin.' + s, j['kn' + s], j['an' + s], 'thigh.' + s, fwd),
                 ('foot.' + s, j['an' + s], j['to' + s], 'shin.' + s, up)]
    for name, h, t, parent, roll in spec:
        b = eb.new(name); b.head = h; b.tail = t; b.align_roll(roll)
        if parent: b.parent = eb[parent]; b.use_connect = (parent not in ('root', 'hips', 'chest') and (eb[parent].tail - h).length < 1e-4)
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in arm.pose.bones: pb.rotation_mode = 'XYZ'
    return arm

# ------------------------------------------------------------------ body mesh
def build_body(kind, j):
    b = BODY[kind]; c = COMMON
    verts = []; edges = []; radii = []
    def add(p, r):
        verts.append(p); radii.append(r if isinstance(r, tuple) else (r, r)); return len(verts) - 1
    iP = add(j['pelvis'], b['r_pelvis']); iW = add(j['waist'], b['r_waist']); iC = add(j['chest'], b['r_chest'])
    iU = add(j['upper'], b['r_upper']); iN = add(j['neck'], b['r_neck']); iNT = add(j['neck_top'], b['r_neck'] * 0.95)
    edges += [(iP, iW), (iW, iC), (iC, iU), (iU, iN), (iN, iNT)]
    for s in ('L', 'R'):
        iS = add(j['sh' + s], b['r_shoulder']); iE = add(j['el' + s], b['r_elbow']); iWr = add(j['wr' + s], b['r_wrist'])
        iHm = add(j['hm' + s], b['r_hand']); iHe = add(j['he' + s], b['r_hand'] * 0.72); iTh = add(j['th' + s], 0.022)
        edges += [(iU, iS), (iS, iE), (iE, iWr), (iWr, iHm), (iHm, iHe), (iWr, iTh)]
        iHp = add(j['hp' + s], b['r_thigh']); iK = add(j['kn' + s], b['r_knee']); iA = add(j['an' + s], b['r_ankle'])
        iT = add(j['to' + s], b['r_toe']); iHl = add(j['hl' + s], b['r_ankle'] * 1.05)
        edges += [(iP, iHp), (iHp, iK), (iK, iA), (iA, iT), (iA, iHl)]
    me = bpy.data.meshes.new('Body'); me.from_pydata([tuple(v) for v in verts], edges, [])
    ob = link(bpy.data.objects.new('Body', me))
    sk = ob.modifiers.new('skin', 'SKIN'); sk.branch_smoothing = 0.6; sk.use_smooth_shade = True
    for i, r in enumerate(radii):
        sv = me.skin_vertices[0].data[i]; sv.radius = r; sv.use_root = (i == iP)
    sub = ob.modifiers.new('sub', 'SUBSURF'); sub.levels = 2
    apply_mods(ob)
    head = build_head(kind, j)
    return ob, head

def head_shape(p, rx, ry, rz):
    """unit sphere point -> offset from the head centre (round skull, narrower jaw)"""
    x, y, z = p.x * rx, p.y * ry, p.z * rz
    if z < 0:
        k = (-z / rz); x *= 1.0 - 0.2 * k * k; y *= 1.0 - 0.08 * k * k
    if z > 0: y *= 1.0 + 0.04 * (z / rz)
    if y < 0 and abs(z) < rz * 0.4: y *= 1.0 - 0.03
    return V(x, y, z)

def build_head(kind, j):
    rx, ry, rz = BODY[kind]['head']; hc = V(0, 0.0, COMMON['head_c'])
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1.0, location=(0, 0, 0))
    h = bpy.context.active_object; h.name = 'Head'
    for v in h.data.vertices: v.co = hc + head_shape(v.co, rx, ry, rz)
    # nose and ears
    parts = [h]
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1.0, location=hc + V(0, -ry * 0.96, -0.06)); n = bpy.context.active_object
    n.scale = (0.042, 0.04, 0.036); parts.append(n)
    for sx in (1, -1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1.0, location=hc + V(sx * rx * 0.97, 0.02, -0.01)); e = bpy.context.active_object
        e.scale = (0.03, 0.045, 0.065); parts.append(e)
    for p in parts: p.select_set(True)
    bpy.context.view_layer.objects.active = h; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.join()
    for poly in h.data.polygons: poly.use_smooth = True
    return h

def body_attributes(body, j, kind, is_head_set):
    """Skin weights (made by hand from the skeleton, more predictable than heat weights) and the data the character shader paints from:
    COLOR.r = region / 4 (0 arm, 1 torso and neck, 2 leg, 3 foot, 4 head; neighbours have neighbouring numbers so a blend between
    two regions never passes through a third), UV = rest position (x, z) on the body or the face projection on the head,
    UV2 = (position along the limb 0..1, rest y). Continuous values give smooth clothing edges when the shader thresholds them."""
    me = body.data; b = BODY[kind]
    arm_pts = {s: [j['sh' + s], j['el' + s], j['wr' + s], j['he' + s]] for s in ('L', 'R')}
    arm_r = [b['r_shoulder'], b['r_elbow'], b['r_wrist'], b['r_hand']]
    leg_pts = {s: [j['hp' + s], j['kn' + s], j['an' + s]] for s in ('L', 'R')}
    leg_r = [b['r_thigh'], b['r_knee'], b['r_ankle']]
    torso_pts = [j['pelvis'] - V(0, 0, 0.05), j['waist'], j['chest'], j['upper'], j['neck'], j['neck_top']]
    torso_r = [b['r_pelvis'][0], b['r_waist'][0], b['r_chest'][0], b['r_upper'][0], b['r_neck'], b['r_neck']]
    arm_len = COMMON['upper_arm'] + COMMON['forearm'] + COMMON['hand']; ua = COMMON['upper_arm'] / arm_len; fa = (COMMON['upper_arm'] + COMMON['forearm']) / arm_len
    names = ['root', 'hips', 'spine', 'chest', 'neck', 'head'] + [n + '.' + s for s in ('L', 'R') for n in ('upper_arm', 'forearm', 'hand', 'thigh', 'shin', 'foot')]
    groups = {n: body.vertex_groups.new(name=n) for n in names}
    col = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    rx, ry, rz = b['head']; hc = COMMON['head_c']
    per_vert_uv2 = {}; per_vert_uv = {}; weights = []; colors = []
    for v in me.vertices:
        p = v.co; w = {}; mask = [0.0, 0.0, 0.0, 0.0]; t = 0.0; apron = 0.0; kind_ = 'head'
        if v.index in is_head_set:
            w = {'head': 1.0}
            if p.y < 0.02:
                u = 0.5 + p.x / (rx * 1.22) * 0.5; vv = 0.5 - (p.z - (hc - 0.01)) / (rz * 1.08) * 0.5
                per_vert_uv[v.index] = (u, 1.0 - vv)        # Blender V runs bottom to top; the glTF export flips it back
            else:
                per_vert_uv[v.index] = (5.0, 5.0)
        else:
            per_vert_uv[v.index] = (p.x, 1.0 - p.z)
            cands = []
            dt = poly_project(p, torso_pts, torso_r); cands.append(('torso', dt))
            for s in ('L', 'R'):
                cands.append(('arm' + s, poly_project(p, arm_pts[s], arm_r)))
                cands.append(('leg' + s, poly_project(p, leg_pts[s], leg_r)))
            # feet: anything below the ankle line belongs to the foot of its side
            kind_, (nd, par, dist) = min(cands, key=lambda c: c[1][0])
            if p.z < COMMON['ankle_z'] + 0.02 and kind_.startswith('leg') or (p.z < COMMON['ankle_z'] + 0.02 and kind_ == 'torso'):
                s = 'L' if p.x > 0 else 'R'; kind_ = 'foot' + s
            if kind_ == 'torso':
                z = p.z
                if z < 1.13: w = {'hips': 1.0}
                elif z < 1.4:
                    k = smoothstep(1.24, 1.36, z); w = {'hips': 1 - k, 'spine': k} if z < 1.3 else {'spine': 1 - smoothstep(1.34, 1.46, z), 'chest': smoothstep(1.34, 1.46, z)}
                elif z < 1.66: k = smoothstep(1.34, 1.46, z); w = {'spine': 1 - k, 'chest': k}
                else: k = smoothstep(1.64, 1.72, z); w = {'chest': 1 - k, 'neck': k}
                if z > 1.84: w = {'neck': 0.5, 'head': 0.5}
                # wide hips are bottom clothes, the rest is top
                if z < COMMON['pelvis'] + 0.08: mask[1] = 1.0
                elif z < 1.66: mask[0] = 1.0
                if z > 1.67: mask = [0.0, 0.0, 0.0, 0.0]
            elif kind_.startswith('arm'):
                s = kind_[-1]; t = par; mask[3] = 1.0
                if t < ua: k = smoothstep(ua - 0.06, ua + 0.04, t); w = {'upper_arm.' + s: 1 - k, 'forearm.' + s: k}
                elif t < fa: k = smoothstep(fa - 0.05, fa + 0.03, t); w = {'forearm.' + s: 1 - k, 'hand.' + s: k}
                else: w = {'hand.' + s: 1.0}
                if t < ua:
                    k0 = 1 - smoothstep(0.0, 0.12, t)
                    if k0 > 0:
                        w = {kk: vv * (1 - 0.6 * k0) for kk, vv in w.items()}; w['chest'] = 0.6 * k0
                if t < ua - 0.06: k = smoothstep(ua - 0.06, ua + 0.04, t)
            elif kind_.startswith('leg'):
                s = kind_[-1]; t = par; mask[1] = 1.0
                if t < 0.5: k = smoothstep(0.42, 0.56, t); w = {'thigh.' + s: 1 - k, 'shin.' + s: k}
                else: k = smoothstep(0.42, 0.56, t); w = {'thigh.' + s: 1 - k, 'shin.' + s: k}
                k0 = 1 - smoothstep(0.0, 0.14, t)
                if k0 > 0:
                    w = {kk: vv * (1 - 0.5 * k0) for kk, vv in w.items()}; w['hips'] = w.get('hips', 0) + 0.5 * k0
            else:   # foot
                s = kind_[-1]; mask[2] = 1.0; t = 1.0
                k = smoothstep(COMMON['ankle_z'] - 0.02, COMMON['ankle_z'] + 0.04, p.z)
                w = {'foot.' + s: 1 - k, 'shin.' + s: k}
            # apron: the front of the body from the chest down to the upper thighs
            if p.y < -0.03 and abs(p.x) < 0.2 and 0.66 < p.z < 1.5 and not kind_.startswith('arm'):
                if p.z < 1.24 or abs(p.x) < 0.13: apron = 1.0
        tot = sum(w.values())
        for n, val in w.items(): weights.append((n, v.index, val / tot))
        region = {'arm': 0, 'torso': 1, 'leg': 2, 'foot': 3, 'head': 4}[kind_.rstrip('LR') if kind_ != 'torso' else 'torso']
        colors.append((v.index, (region / 4.0, 0.0, 0.0, 1.0)))
        per_vert_uv2[v.index] = (t, 1.0 - p.y)          # V is flipped by the export, like every V
    # colours first, then weights: in Blender 4.2 writing the colour attribute drops weights that were added before it
    for i, c in colors: col.data[i].color = c
    for n, i, val in weights: groups[n].add([i], val, 'ADD')
    while len(me.uv_layers): me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name='UVMap'); uv2 = me.uv_layers.new(name='UV2')
    for loop in me.loops:
        uv.data[loop.index].uv = per_vert_uv[loop.vertex_index]
        uv2.data[loop.index].uv = per_vert_uv2[loop.vertex_index]
    me.color_attributes.active_color = col

def join_head(body, head):
    n_body = len(body.data.vertices)
    activate(body); head.select_set(True); bpy.ops.object.join()
    return set(range(n_body, len(body.data.vertices)))

# ------------------------------------------------------------------ hair and accessories (metaballs -> mesh)
def metaball_mesh(name, balls, res=0.022, decimate=0.5):
    mb = bpy.data.metaballs.new(name); mb.resolution = res; mb.render_resolution = res; mb.threshold = 0.6
    ob = link(bpy.data.objects.new(name, mb))
    for (pos, rad, scale, neg) in balls:
        e = mb.elements.new(); e.co = pos; e.radius = rad / 0.575; e.use_negative = neg
        if scale != (1, 1, 1):
            e.type = 'ELLIPSOID'; e.size_x, e.size_y, e.size_z = scale
    activate(ob); bpy.context.view_layer.update()
    bpy.ops.object.convert(target='MESH'); m = bpy.context.active_object; m.name = name
    if decimate < 1.0:
        d = m.modifiers.new('dec', 'DECIMATE'); d.ratio = decimate; apply_mods(m)
    for poly in m.data.polygons: poly.use_smooth = True
    return m

def lerp(a, b, t): return a + (b - a) * t

def hair_cap(name, kind, hairline, scale=1.07, thick=0.04):
    """A shell over the skull, cut along a hairline: hairline(x, y, z) gives the lowest kept height for a direction
    on the unit sphere (y < 0 is the face side). Fits the head exactly because it uses the same head shape."""
    rx, ry, rz = BODY[kind]['head']; hc = V(0, 0, COMMON['head_c'])
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1.0); ob = bpy.context.active_object; ob.name = name
    bm = bmesh.new(); bm.from_mesh(ob.data)
    kill = [v for v in bm.verts if v.co.z < hairline(v.co.x, v.co.y, v.co.z)]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    for v in bm.verts: v.co = hc + head_shape(v.co, rx, ry, rz) * scale
    bm.to_mesh(ob.data); bm.free()
    so = ob.modifiers.new('sol', 'SOLIDIFY'); so.thickness = thick; so.offset = 1.0; so.use_rim = True
    sub = ob.modifiers.new('sub', 'SUBSURF'); sub.levels = 1
    apply_mods(ob)
    return ob

def blob(pos, scale, rot=(0, 0, 0), segs=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=max(8, segs // 2), radius=1.0, location=pos, rotation=rot)
    o = bpy.context.active_object; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return o

def join_all(main, parts, name):
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for p in parts: p.select_set(True)
    main.select_set(True); bpy.context.view_layer.objects.active = main
    if parts: bpy.ops.object.join()
    main.name = name
    for poly in main.data.polygons: poly.use_smooth = True
    return main

def front(y): return max(0.0, min(1.0, (-y + 0.15) / 1.0))

def hair_styles(kind, j):
    rx, ry, rz = BODY[kind]['head']; hc = V(0, 0, COMMON['head_c'])
    H = lambda x, y, z: hc + V(x, y, z)
    meshes = {}
    # short: neat, above the ears, a small quiff
    def hl_short(x, y, z):
        h = lerp(-0.3, 0.5, front(y) ** 1.2)
        if abs(x) > 0.75 and y > -0.5: h = max(h, 0.15)
        return h
    cap = hair_cap('Hair_short', kind, hl_short, 1.06, 0.045)
    meshes['Hair_short'] = join_all(cap, [blob(H(0.03, -0.17, 0.27), (0.15, 0.1, 0.07), (0.3, 0, 0.2))], 'Hair_short')
    meshes['Hair_buzz'] = hair_cap('Hair_buzz', kind, hl_short, 1.03, 0.018)
    # pulled back (bun, pony): clear forehead, covers the back of the head
    def hl_back(x, y, z):
        h = lerp(-0.38, 0.4, front(y) ** 1.1)
        if abs(x) > 0.8 and y > -0.4: h = max(h, 0.05)
        return h
    cap = hair_cap('Hair_bun', kind, hl_back, 1.06, 0.035)
    meshes['Hair_bun'] = join_all(cap, [blob(H(0, 0.1, 0.33), (0.14, 0.13, 0.12)), blob(H(0, 0.06, 0.26), (0.09, 0.09, 0.05))], 'Hair_bun')
    cap = hair_cap('Hair_pony', kind, hl_back, 1.06, 0.035)
    meshes['Hair_pony'] = join_all(cap, [blob(H(0, 0.29, 0.07), (0.07, 0.06, 0.07)), blob(H(0, 0.36, -0.14), (0.095, 0.1, 0.25), (-0.25, 0, 0))], 'Hair_pony')
    # long: side-swept fringe, covers the ears, falls to the shoulders
    def hl_long(x, y, z):
        f = front(y) ** 1.3
        h = lerp(-1.1, 0.3 + 0.18 * x, f)
        if f < 0.5 and abs(x) > 0.6: h = min(h, -0.35)
        return h
    cap = hair_cap('Hair_long', kind, hl_long, 1.07, 0.04)
    meshes['Hair_long'] = join_all(cap, [blob(H(0, 0.13, -0.3), (0.29, 0.13, 0.36)), blob(H(0.235, 0.0, -0.27), (0.075, 0.1, 0.27)),
                                        blob(H(-0.235, 0.0, -0.27), (0.075, 0.1, 0.27)), blob(H(0, 0.16, -0.58), (0.24, 0.1, 0.12))], 'Hair_long')
    # bob: straight bangs, chin length
    def hl_bob(x, y, z):
        f = front(y) ** 1.2
        h = lerp(-0.7, 0.34, f)
        if f < 0.55 and abs(x) > 0.55: h = min(h, -0.55)
        return h
    cap = hair_cap('Hair_bob', kind, hl_bob, 1.08, 0.04)
    meshes['Hair_bob'] = join_all(cap, [blob(H(0.22, 0.03, -0.12), (0.1, 0.17, 0.2)), blob(H(-0.22, 0.03, -0.12), (0.1, 0.17, 0.2)),
                                       blob(H(0, 0.14, -0.1), (0.27, 0.12, 0.21))], 'Hair_bob')
    # curly: a cloud of curls
    def hl_curly(x, y, z):
        return lerp(-0.3, 0.45, front(y) ** 1.2)
    cap = hair_cap('Hair_curly', kind, hl_curly, 1.1, 0.05)
    curls = []
    for i in range(22):
        a = i / 22.0 * math.tau; el = 0.35 + 0.45 * ((i * 7) % 5) / 4.0
        d = V(math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el))
        if d.y < -0.55 and d.z < 0.6: continue
        p = hc + head_shape(d, rx, ry, rz) * 1.12
        curls.append(blob(p, (0.085, 0.085, 0.08), segs=12))
    meshes['Hair_curly'] = join_all(cap, curls, 'Hair_curly')
    # accessories
    meshes['Acc_beard'] = metaball_mesh('Acc_beard', [(hc + V(0, -0.17, -0.2), 0.2, (1.05, 0.7, 0.62), False), (hc + V(0, -0.02, -0.08), 0.26, (1.0, 0.9, 0.85), True),
                                                     (hc + V(0, -0.33, -0.02), 0.13, (1.0, 0.6, 0.6), True)], 0.018, 0.5)
    def hl_cap(x, y, z): return 0.28
    cap = hair_cap('Acc_cap', kind, hl_cap, 1.1, 0.05)
    meshes['Acc_cap'] = join_all(cap, [blob(H(0, -0.27, 0.11), (0.17, 0.13, 0.025), (0.25, 0, 0))], 'Acc_cap')
    cap = hair_cap('Acc_toque', kind, lambda x, y, z: 0.32, 1.1, 0.04)
    meshes['Acc_toque'] = join_all(cap, [blob(H(0, 0.02, 0.38), (0.25, 0.25, 0.17)), blob(H(0.11, -0.04, 0.45), (0.15, 0.15, 0.12)),
                                        blob(H(-0.11, 0.05, 0.46), (0.15, 0.15, 0.12))], 'Acc_toque')
    meshes['Acc_glasses'] = glasses(hc, ry)
    return meshes

def glasses(hc, ry):
    parts = []
    for sx in (1, -1):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.085, minor_radius=0.011, major_segments=24, minor_segments=6,
                                         location=hc + V(sx * 0.1, -ry * 1.0, -0.005), rotation=(math.pi / 2, 0, 0))
        parts.append(bpy.context.active_object)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.009, depth=0.24, vertices=6, location=hc + V(sx * 0.2, -ry * 0.55, 0.02), rotation=(math.pi / 2, 0, 0))
        parts.append(bpy.context.active_object)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.008, depth=0.05, vertices=6, location=hc + V(0, -ry * 1.03, 0.01), rotation=(0, math.pi / 2, 0))
    parts.append(bpy.context.active_object)
    for p in parts: p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]; bpy.ops.object.join()
    g = bpy.context.active_object; g.name = 'Acc_glasses'
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return g

def bind_to_head(obj, arm):
    vg = obj.vertex_groups.new(name='head'); vg.add(list(range(len(obj.data.vertices))), 1.0, 'ADD')
    m = obj.modifiers.new('arm', 'ARMATURE'); m.object = arm; obj.parent = arm

# ------------------------------------------------------------------ animation
D = math.radians

def set_pose(arm, pose):
    for pb in arm.pose.bones:
        r = pose.get(pb.name, (0, 0, 0)); pb.rotation_euler = (D(r[0]), D(r[1]), D(r[2])); pb.location = (0, 0, 0)
    if 'hips_loc' in pose:
        x, y, z = pose['hips_loc']; arm.pose.bones['hips'].location = (x, y, z)

def key(arm, frame):
    for pb in arm.pose.bones:
        pb.keyframe_insert('rotation_euler', frame=frame); pb.keyframe_insert('location', frame=frame)

def make_action(arm, name, keys):
    act = bpy.data.actions.new(name); act.use_fake_user = True
    arm.animation_data_create(); arm.animation_data.action = act
    for frame, pose in keys:
        set_pose(arm, pose); key(arm, frame)
    return act

def merge(*ps):
    out = {}
    for p in ps:
        for k, v in p.items():
            if k in out and k != 'hips_loc': out[k] = tuple(a + b for a, b in zip(out[k], v))
            else: out[k] = v
    return out

def mirror(p):
    """swap left and right (rotations about Y and Z change sign across the mirror)"""
    out = {}
    for k, v in p.items():
        if k.endswith('.L'): nk = k[:-2] + '.R'
        elif k.endswith('.R'): nk = k[:-2] + '.L'
        else: nk = k
        out[nk] = (v[0], -v[1], -v[2]) if k != 'hips_loc' else (-v[0], v[1], v[2])
    return out

# relaxed arms (A pose -> close to the body). Abduction about Z: + raises the left arm, - raises the right arm.
ARMS = {'upper_arm.L': (2, 0, -20), 'upper_arm.R': (2, 0, 20), 'forearm.L': (12, 0, 0), 'forearm.R': (12, 0, 0), 'hand.L': (0, 8, 0), 'hand.R': (0, -8, 0)}
CARRY = {'upper_arm.L': (38, 0, -14), 'upper_arm.R': (38, 0, 14), 'forearm.L': (72, 0, 6), 'forearm.R': (72, 0, -6), 'hand.L': (-12, 0, 0), 'hand.R': (-12, 0, 0)}

def walk_legs(phase):
    """phase 0: left heel strike, 1: passing (left planted, right lifting)"""
    if phase == 0:
        return {'thigh.L': (26, 0, 0), 'shin.L': (-6, 0, 0), 'foot.L': (12, 0, 0), 'thigh.R': (-20, 0, 0), 'shin.R': (-18, 0, 0), 'foot.R': (-14, 0, 0),
                'hips_loc': (0, -0.022, 0), 'hips': (0, -5, 0), 'spine': (3, 4, 0), 'chest': (2, 3, 0)}
    return {'thigh.L': (-2, 0, 0), 'shin.L': (-4, 0, 0), 'foot.L': (2, 0, 0), 'thigh.R': (16, 0, 0), 'shin.R': (-62, 0, 0), 'foot.R': (8, 0, 0),
            'hips_loc': (0, 0.025, 0), 'hips': (0, 0, 0), 'spine': (3, 0, 0), 'chest': (2, 0, 0)}

def walk_arms(phase):
    if phase == 0:
        return {'upper_arm.L': (-24, 0, -18), 'upper_arm.R': (26, 0, 18), 'forearm.L': (10, 0, 0), 'forearm.R': (30, 0, 0), 'hand.L': (0, 8, 0), 'hand.R': (0, -8, 0)}
    return dict(ARMS)

def build_actions(arm):
    acts = []
    idle0 = merge(ARMS, {'spine': (2, 0, 0)}); idle1 = merge(ARMS, {'spine': (2, 0, 0), 'chest': (2.5, 0, 0), 'neck': (-1.5, 0, 0), 'head': (-1.5, 3, 0), 'hips_loc': (0, -0.006, 0),
                                                                    'upper_arm.L': (-1, 0, 1.5), 'upper_arm.R': (-1, 0, -1.5)})
    idle2 = merge(ARMS, {'spine': (2, 0, 0), 'head': (0, -3, 1)})
    acts.append(make_action(arm, 'idle', [(0, idle0), (24, idle1), (48, idle2), (72, idle1), (96, idle0)]))
    w0 = merge(walk_legs(0), walk_arms(0)); w1 = merge(walk_legs(1), walk_arms(1))
    acts.append(make_action(arm, 'walk', [(0, w0), (6, w1), (12, mirror(w0)), (18, mirror(w1)), (24, w0)]))
    c0 = merge(walk_legs(0), CARRY); c1 = merge(walk_legs(1), CARRY)
    acts.append(make_action(arm, 'carry_walk', [(0, c0), (6, c1), (12, merge(mirror(walk_legs(0)), CARRY)), (18, merge(mirror(walk_legs(1)), CARRY)), (24, c0)]))
    acts.append(make_action(arm, 'carry_idle', [(0, merge(CARRY, {'spine': (-2, 0, 0)})), (24, merge(CARRY, {'chest': (2, 0, 0), 'head': (-2, 0, 0), 'hips_loc': (0, -0.005, 0)})), (48, merge(CARRY, {'spine': (-2, 0, 0)}))]))
    reach = merge({'upper_arm.L': (62, 0, -8), 'upper_arm.R': (62, 0, 8), 'forearm.L': (22, 0, 0), 'forearm.R': (22, 0, 0), 'hand.L': (-10, 0, 0), 'hand.R': (-10, 0, 0)},
                  {'spine': (10, 0, 0), 'chest': (6, 0, 0), 'head': (-8, 0, 0), 'thigh.L': (4, 0, 0), 'thigh.R': (-6, 0, 0)})
    acts.append(make_action(arm, 'give', [(0, idle0), (8, reach), (12, reach), (20, idle0)]))
    crouch = merge(ARMS, {'hips_loc': (0, -0.08, 0), 'thigh.L': (30, 0, 0), 'thigh.R': (30, 0, 0), 'shin.L': (-55, 0, 0), 'shin.R': (-55, 0, 0), 'foot.L': (25, 0, 0), 'foot.R': (25, 0, 0),
                       'spine': (10, 0, 0), 'upper_arm.L': (-20, 0, -10), 'upper_arm.R': (-20, 0, 10)})
    air = {'hips_loc': (0, 0.22, 0), 'thigh.L': (-6, 0, 3), 'thigh.R': (-6, 0, -3), 'shin.L': (-25, 0, 0), 'shin.R': (-25, 0, 0), 'foot.L': (-20, 0, 0), 'foot.R': (-20, 0, 0),
           'upper_arm.L': (5, 0, 135), 'upper_arm.R': (5, 0, -135), 'forearm.L': (15, 0, 0), 'forearm.R': (15, 0, 0), 'head': (-12, 0, 0), 'chest': (-6, 0, 0)}
    acts.append(make_action(arm, 'happy', [(0, idle0), (5, crouch), (11, air), (14, air), (19, crouch), (26, idle0)]))
    wave_a = merge(ARMS, {'upper_arm.R': (10, 0, -150), 'forearm.R': (20, 0, -18), 'hand.R': (0, 0, -10), 'head': (0, -6, 4), 'chest': (0, -4, 3)})
    wave_b = merge(wave_a, {'forearm.R': (0, 0, 36), 'hand.R': (0, 0, 20)})
    acts.append(make_action(arm, 'wave', [(0, wave_a), (6, wave_b), (12, wave_a), (18, wave_b), (24, wave_a)]))
    t0 = merge(ARMS, {'upper_arm.R': (18, 0, 10), 'forearm.R': (55, 0, -10), 'hand.R': (-10, 0, 0), 'head': (-3, 4, 0)})
    t1 = merge(ARMS, {'upper_arm.L': (16, 0, -6), 'upper_arm.R': (16, 0, 6), 'forearm.L': (48, 0, 12), 'forearm.R': (48, 0, -12), 'head': (3, -2, 2), 'chest': (0, 3, 0)})
    t2 = merge(ARMS, {'upper_arm.L': (20, 0, -8), 'forearm.L': (58, 0, 10), 'head': (-2, -5, -1), 'chest': (0, -4, 0)})
    acts.append(make_action(arm, 'talk', [(0, idle0), (12, t0), (24, t1), (36, t2), (48, idle0)]))
    th = merge(ARMS, {'upper_arm.R': (28, 0, 22), 'forearm.R': (128, 0, -14), 'hand.R': (-22, 0, 0), 'upper_arm.L': (22, 0, 14), 'forearm.L': (84, 0, 22),
                      'head': (6, -6, 8), 'spine': (2, 0, 2)})
    th2 = merge(th, {'head': (2, -9, 9), 'hips_loc': (0, -0.006, 0)})
    acts.append(make_action(arm, 'think', [(0, th), (36, th2), (72, th)]))
    sad = merge(ARMS, {'spine': (10, 0, 0), 'chest': (8, 0, 0), 'neck': (8, 0, 0), 'head': (14, 0, 0), 'upper_arm.L': (6, 0, -26), 'upper_arm.R': (6, 0, 26), 'hips_loc': (0, -0.015, 0)})
    acts.append(make_action(arm, 'sad', [(0, sad), (48, merge(sad, {'head': (2, 6, 0)})), (96, sad)]))
    work_a = merge(ARMS, {'upper_arm.L': (34, 0, -6), 'upper_arm.R': (44, 0, 6), 'forearm.L': (62, 0, 8), 'forearm.R': (52, 0, -8), 'spine': (8, 0, 0), 'head': (12, 0, 0)})
    work_b = merge(work_a, {'upper_arm.L': (10, 0, 0), 'upper_arm.R': (-10, 0, 0), 'forearm.L': (-8, 0, 0), 'forearm.R': (8, 0, 0), 'chest': (0, 4, 0)})
    acts.append(make_action(arm, 'work', [(0, work_a), (12, work_b), (24, work_a)]))
    seat = {'hips_loc': (0, -0.43, -0.05), 'thigh.L': (88, 0, 4), 'thigh.R': (88, 0, -4), 'shin.L': (-86, 0, 0), 'shin.R': (-86, 0, 0), 'foot.L': (0, 0, 0), 'foot.R': (0, 0, 0)}
    sit = merge(seat, {'upper_arm.L': (22, 0, -14), 'upper_arm.R': (22, 0, 14), 'forearm.L': (50, 0, 10), 'forearm.R': (50, 0, -10), 'spine': (-2, 0, 0)})
    acts.append(make_action(arm, 'sit', [(0, sit), (48, merge(sit, {'chest': (2.5, 0, 0), 'head': (-2, 5, 0)})), (96, sit)]))
    ty_a = merge(seat, {'upper_arm.L': (30, 0, -10), 'upper_arm.R': (30, 0, 10), 'forearm.L': (70, 0, 14), 'forearm.R': (70, 0, -14), 'spine': (6, 0, 0), 'head': (10, 0, 0),
                        'hand.L': (-14, 0, 0), 'hand.R': (-6, 0, 0)})
    ty_b = merge(ty_a, {'hand.L': (10, 0, 0), 'hand.R': (-10, 0, 0), 'forearm.L': (0, 0, 3)})
    acts.append(make_action(arm, 'sit_type', [(0, ty_a), (4, ty_b), (8, ty_a), (12, ty_b), (16, ty_a), (24, merge(ty_a, {'head': (0, 4, 0)})), (32, ty_a)]))
    dr = merge(sit, {'upper_arm.R': (34, 0, 18), 'forearm.R': (118, 0, -18), 'hand.R': (-10, 0, 0), 'head': (-10, 0, 0)})
    acts.append(make_action(arm, 'sit_drink', [(0, sit), (30, sit), (42, dr), (54, dr), (66, sit), (96, sit)]))
    for a in acts:
        for fc in a.fcurves:
            for kp in fc.keyframe_points: kp.interpolation = 'BEZIER'
    arm.animation_data.action = None
    set_pose(arm, {})
    return acts

# ------------------------------------------------------------------ build and export
def build(kind):
    clear()
    j = joints(BODY[kind])
    arm = build_armature(j)
    body, head = build_body(kind, j)
    head_set = join_head(body, head)
    body_attributes(body, j, kind, head_set)
    m = body.modifiers.new('arm', 'ARMATURE'); m.object = arm; body.parent = arm
    extras = hair_styles(kind, j)
    for o in extras.values(): bind_to_head(o, arm)
    build_actions(arm)
    for o in bpy.context.scene.objects: o.select_set(True)
    path = os.path.join(OUT, 'char_%s.glb' % kind)
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_animations=True, export_animation_mode='ACTIONS', export_skins=True,
              export_morph=False, export_yup=True, export_texcoords=True, export_normals=True, export_materials='NONE',
              export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kw)
    nb = len(body.data.polygons)
    print('EXPORTED', path, 'body faces', nb, 'verts', len(body.data.vertices), {k: len(v.data.polygons) for k, v in extras.items()})

os.makedirs(OUT, exist_ok=True)
for k in ('f', 'm'): build(k)
