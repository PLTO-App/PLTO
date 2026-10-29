"""Shared modelling helpers for the town and interior builders: boxes, cylinders and balls with vertex colours,
windows, doors, awnings, roofs, and the GLB export (solid parts and Glass_ parts as two meshes)."""
import bpy, bmesh, math, sys, os, random
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else '.'
random.seed(7)

def lin(h):
    """'#rrggbb' -> linear RGBA (Blender colour attributes are linear)"""
    h = h.lstrip('#'); c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)

def shade(h, k):
    h = h.lstrip('#'); c = [min(255, max(0, int(int(h[i:i + 2], 16) * k))) for i in (0, 2, 4)]
    return '#%02x%02x%02x' % tuple(c)

def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)

PARTS = []      # (object, kind) collected for the current asset

def _finish(o, color, bevel=0.0, seg=2, kind='solid'):
    if bevel > 0:
        m = o.modifiers.new('bev', 'BEVEL'); m.width = bevel; m.segments = seg; m.limit_method = 'ANGLE'
        bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier='bev')
    me = o.data
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    c = lin(color)
    for i in range(len(ca.data)): ca.data[i].color = c
    for p in me.polygons: p.use_smooth = bevel > 0
    PARTS.append((o, kind))
    return o

def box(size, loc, color, bevel=0.06, rot=(0, 0, 0), kind='solid', seg=2):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(o, color, bevel, seg, kind)

def cyl(r, h, loc, color, verts=16, rot=(0, 0, 0), bevel=0.03, kind='solid', r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=verts, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, vertices=verts, location=loc, rotation=rot)
    o = bpy.context.active_object
    return _finish(o, color, bevel, 2, kind)

def ball(r, loc, color, scale=(1, 1, 1), segs=12, kind='solid'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=max(6, segs // 2), radius=r, location=loc)
    o = bpy.context.active_object; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o2 = _finish(o, color, 0, 2, kind)
    for p in o2.data.polygons: p.use_smooth = True
    return o2

def prism_roof(w, d, h, loc, color, overhang=0.35):
    """gable roof along X, ridge on top"""
    x0, y0, z0 = loc; hw = w / 2 + overhang; hd = d / 2 + overhang
    me = bpy.data.meshes.new('roof'); bm = bmesh.new()
    v = [bm.verts.new(p) for p in [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0), (-hw, 0, h), (hw, 0, h)]]
    for f in [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]: bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new('roof', me); bpy.context.scene.collection.objects.link(o); o.location = loc
    bpy.context.view_layer.objects.active = o
    sol = o.modifiers.new('sol', 'SOLIDIFY'); sol.thickness = 0.18; bpy.ops.object.modifier_apply(modifier='sol')
    _finish(o, color, 0.05)
    # tile rows: thin strips that make the slope read as tiles
    rows = 5
    for side in (-1, 1):
        for i in range(rows):
            t = (i + 0.5) / rows
            y = side * hd * (1 - t); z = h * t
            ang = math.atan2(h, hd) * (-side)
            box((w + overhang * 2 + 0.05, 0.28, 0.08), (x0, y0 + y, z0 + z + 0.1), shade(color, 0.86 if i % 2 else 0.95), 0.03, rot=(ang, 0, 0))
    return o

def awning(w, depth, drop, loc, c1, c2, stripes=9, scallops=True):
    """striped sloped awning; loc = top back centre (against the wall)"""
    x0, y0, z0 = loc
    sw = w / stripes
    ang = math.atan2(drop, depth)
    L = math.hypot(depth, drop)
    for i in range(stripes):
        x = x0 - w / 2 + sw * (i + 0.5)
        col = c1 if i % 2 == 0 else c2
        box((sw * 1.01, L, 0.08), (x, y0 - depth / 2, z0 - drop / 2), col, 0.02, rot=(ang, 0, 0), seg=1)
        if scallops:
            bpy.ops.mesh.primitive_cylinder_add(radius=sw / 2, depth=0.08, vertices=12, location=(x, y0 - depth - 0.02, z0 - drop), rotation=(math.pi / 2, 0, 0))
            o = bpy.context.active_object
            bm = bmesh.new(); bm.from_mesh(o.data)
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > 0.001], context='VERTS')   # keep the lower half (local y up before rotation)
            bm.to_mesh(o.data); bm.free()
            _finish(o, col, 0)
    # side cheeks
    for sx in (-1, 1):
        me = bpy.data.meshes.new('cheek'); bm = bmesh.new()
        pts = [(0, 0, 0), (0, -depth, -drop), (0, -depth, -drop - 0.35)]
        vs = [bm.verts.new(p) for p in pts]; bm.faces.new(vs); bm.to_mesh(me); bm.free()
        o = bpy.data.objects.new('cheek', me); bpy.context.scene.collection.objects.link(o)
        o.location = (x0 + sx * w / 2, y0, z0)
        bpy.context.view_layer.objects.active = o
        s = o.modifiers.new('s', 'SOLIDIFY'); s.thickness = 0.06; bpy.ops.object.modifier_apply(modifier='s')
        _finish(o, c1, 0)

def window(x, z, w, h, front_y, frame='#fff6ea', arch=False, sill=True, shutters=None, mullions=True):
    """a window on a facade whose front is at front_y (facing -Y)"""
    y = front_y - 0.02
    box((w + 0.3, 0.16, 0.16), (x, y - 0.05, z + h / 2 + 0.06), frame, 0.03)
    box((w + 0.3, 0.16, 0.16), (x, y - 0.05, z - h / 2 - 0.06), frame, 0.03)
    for sx in (-1, 1): box((0.16, 0.16, h + 0.2), (x + sx * (w / 2 + 0.07), y - 0.05, z), frame, 0.03)
    if arch:
        bpy.ops.mesh.primitive_cylinder_add(radius=w / 2 + 0.15, depth=0.16, vertices=24, location=(x, y - 0.05, z + h / 2), rotation=(math.pi / 2, 0, 0))
        o = bpy.context.active_object; bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.001], context='VERTS'); bm.to_mesh(o.data); bm.free()
        _finish(o, frame, 0)
        bpy.ops.mesh.primitive_cylinder_add(radius=w / 2, depth=0.04, vertices=24, location=(x, y + 0.02, z + h / 2), rotation=(math.pi / 2, 0, 0))
        o = bpy.context.active_object; bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.001], context='VERTS'); bm.to_mesh(o.data); bm.free()
        _finish(o, '#ffd27a', 0, kind='glass')
    box((w, 0.04, h), (x, y + 0.02, z), '#ffd27a', 0, kind='glass')
    if mullions:
        box((0.07, 0.08, h), (x, y - 0.02, z), frame, 0.01)
        box((w, 0.08, 0.07), (x, y - 0.02, z + h * 0.12), frame, 0.01)
    if sill:
        box((w + 0.5, 0.35, 0.12), (x, y - 0.18, z - h / 2 - 0.16), shade(frame, 0.9), 0.03)
    if shutters:
        for sx in (-1, 1):
            box((w * 0.45, 0.08, h + 0.1), (x + sx * (w / 2 + w * 0.25 + 0.2), y - 0.04, z), shutters, 0.03)

def door(x, z0, w, h, front_y, color, frame='#fff6ea', glass=True):
    y = front_y - 0.02
    box((w + 0.35, 0.18, 0.18), (x, y - 0.06, z0 + h + 0.06), frame, 0.03)
    for sx in (-1, 1): box((0.18, 0.18, h + 0.1), (x + sx * (w / 2 + 0.08), y - 0.06, z0 + h / 2), frame, 0.03)
    box((w, 0.1, h), (x, y, z0 + h / 2), color, 0.02)
    if glass: box((w * 0.62, 0.04, h * 0.45), (x, y - 0.06, z0 + h * 0.66), '#ffd27a', 0, kind='glass')
    ball(0.07, (x + w * 0.32, y - 0.1, z0 + h * 0.45), '#f0b44c', segs=8)
    box((w + 0.8, 0.6, 0.12), (x, y - 0.35, z0 + 0.06), '#c9bba8', 0.03)   # step

def flower_box(x, z, w, front_y, box_col='#8a5a3b'):
    y = front_y - 0.3
    box((w, 0.4, 0.3), (x, y, z), box_col, 0.04)
    cols = ['#ff6b6b', '#ffd23f', '#ff9ff3', '#ffffff', '#ff7a59']
    for i in range(int(w / 0.22)):
        xx = x - w / 2 + 0.12 + i * 0.22
        ball(0.13, (xx, y - 0.02, z + 0.2), '#4caf50', (1, 1, 0.8), segs=8)
        ball(0.07, (xx + 0.04, y - 0.12, z + 0.3), random.choice(cols), segs=6)

def stones(x0, x1, z0, z1, front_y, base, n=26):
    """a few raised stones on a facade: cheap texture and depth"""
    for i in range(n):
        x = random.uniform(x0, x1); z = random.uniform(z0, z1)
        box((random.uniform(0.35, 0.7), 0.06, random.uniform(0.2, 0.32)), (x, front_y - 0.02, z), shade(base, random.uniform(0.9, 1.06)), 0.03, seg=1)

def sign_board(x, z, w, h, front_y, color, border='#fff6ea'):
    box((w + 0.2, 0.2, h + 0.2), (x, front_y - 0.12, z), border, 0.06)
    box((w, 0.14, h), (x, front_y - 0.2, z), color, 0.05)

def export(name):
    solids = [o for o, k in PARTS if k == 'solid']; glass = [o for o, k in PARTS if k == 'glass']
    out = []
    for group, gname in ((solids, name), (glass, 'Glass_' + name)):
        if not group: continue
        for o in bpy.context.view_layer.objects: o.select_set(False)
        for o in group: o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        bpy.ops.object.join()
        j = bpy.context.active_object; j.name = gname
        out.append(j)
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for o in out: o.select_set(True)
    path = os.path.join(OUT, name + '.glb')
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_materials='NONE', export_yup=True, export_normals=True, export_apply=True)
    try: bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError: bpy.ops.export_scene.gltf(export_colors=True, **kw)
    print('EXPORTED', name, [len(o.data.polygons) for o in out])

def new_asset():
    clear(); PARTS.clear()

