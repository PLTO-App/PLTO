"""Builds the town street in Blender from code (own work, no external assets) and exports one GLB per piece.

Style: chunky, rounded, toy-like buildings in warm colours. Every colour is a vertex colour (no textures), so a building is one
mesh and one draw call. Window panes are a separate object (Glass_*) so the game can light them at night.
Units are game units (1 = 1/1.43 m). Buildings face +Y in Blender (toward the street), which is +Z... the export turns Blender
-Y forward into glTF +Z, so the fronts here point to -Y and face the camera in Godot (+Z).

Run: blender -b --factory-startup --python make_town.py -- <out_dir>
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit import *
from kit import _finish
import kit

# ------------------------------------------------------------------ buildings
# Each building stands on its own ground plate, front edge at y = -D/2.

def bakery():
    new_asset()
    W, D, H1, H2 = 9.0, 7.0, 4.6, 3.6
    fy = -D / 2
    wall = '#f2d6b3'; brick = '#c8734a'; trim = '#fff6ea'; wood = '#7a4a2e'
    box((W, D, H1), (0, 0, H1 / 2), wall, 0.12)
    box((W - 0.4, D - 0.4, H2), (0, 0.1, H1 + H2 / 2), '#f6e2c6', 0.12)
    box((W + 0.2, D + 0.2, 0.3), (0, 0, H1 + 0.05), trim, 0.06)                 # floor band
    box((W + 0.3, 0.5, 0.9), (0, fy - 0.05, 0.45), brick, 0.08)                  # brick plinth
    stones(-W / 2 + 0.6, W / 2 - 0.6, 1.2, H1 - 0.6, fy, '#e6c39c', 22)
    for sx in (-1, 1): box((0.5, 0.5, H1 + H2), (sx * (W / 2 - 0.05), fy + 0.1, (H1 + H2) / 2), brick, 0.08)  # corner pillars
    window(-2.6, 2.45, 2.6, 2.3, fy, trim, arch=True)
    window(2.6, 2.45, 2.6, 2.3, fy, trim, arch=True)
    door(0, 0.05, 1.5, 2.9, fy, wood)
    for x in (-2.4, 0.0, 2.4): window(x, H1 + 1.8, 1.3, 1.5, fy + 0.2, trim, shutters='#2fb3a2', sill=True)
    for x in (-2.4, 2.4): flower_box(x, H1 + 0.75, 1.6, fy + 0.2)
    awning(W - 0.6, 1.7, 1.0, (0, fy - 0.05, H1 - 0.25), '#e94b4b', '#fff6ea', 11)
    prism_roof(W - 0.4, D - 0.4, 2.2, (0, 0.1, H1 + H2), '#d9663f')
    box((0.9, 0.9, 2.2), (2.6, 1.2, H1 + H2 + 1.5), brick, 0.06)              # chimney
    box((1.1, 1.1, 0.25), (2.6, 1.2, H1 + H2 + 2.6), '#8a4a30', 0.05)
    sign_board(0, H1 + 0.05 - 0.05 + 3.6 - 3.0, 3.6, 0.9, fy - 0.1, wood, '#f0b44c')
    # bread sign on the corner
    box((0.1, 1.4, 0.1), (W / 2 + 0.2, fy + 0.6, 3.9), wood, 0.02)
    ball(0.42, (W / 2 + 0.2, fy - 0.2, 3.5), '#e5a04a', (1.4, 0.55, 0.7), 14)
    # chalkboard and bench in front
    box((0.9, 0.08, 1.2), (-3.9, fy - 1.3, 0.75), '#2b2b2b', 0.03, rot=(0.25, 0, 0))
    box((1.0, 0.12, 1.3), (-3.9, fy - 1.25, 0.75), wood, 0.03, rot=(0.25, 0, 0))
    for sx in (-1, 1): box((0.08, 0.08, 1.5), (-3.9 + sx * 0.45, fy - 1.15, 0.7), wood, 0.02, rot=(0.25, 0, 0))
    # ---- the details that make the front inviting: bunting, lanterns, topiary, bread on display, a roof ridge cap
    flags = ['#e94b4b', '#fff6ea', '#2fb3a2', '#f0b44c']
    n = 15; x0, x1 = -W / 2 + 0.3, W / 2 - 0.3; zb = H1 + 0.55
    pts = [(x0 + (x1 - x0) * i / n, fy - 0.3, zb - 0.45 * math.sin(math.pi * i / n)) for i in range(n + 1)]
    wire(pts, '#6b4a33', 0.03)
    for i in range(n):
        a = pts[i]; b = pts[i + 1]; mx = (a[0] + b[0]) / 2; mz = (a[2] + b[2]) / 2
        tri_flag((a[0] + 0.05, a[1], a[2]), (b[0] - 0.05, b[1], b[2]), (mx, a[1] - 0.04, mz - 0.5), flags[i % 4])
    for sx in (-1, 1):                                                           # wall lanterns beside the door, topiary pots
        box((0.08, 0.2, 0.5), (sx * 1.25, fy - 0.12, 2.9), '#2f3b52', 0.02)
        box((0.26, 0.26, 0.36), (sx * 1.25, fy - 0.3, 2.7), '#ffd27a', 0.03, kind='glass')
        box((0.34, 0.34, 0.07), (sx * 1.25, fy - 0.3, 2.93), '#2f3b52', 0.02)
        cyl(0.27, 0.42, (sx * 1.25, fy - 0.62, 0.21), '#c8734a', 12, r2=0.2)
        ball(0.36, (sx * 1.25, fy - 0.62, 0.78), '#4aa65a', segs=10, grad=('#2f7a45', '#74c76a'))
        ball(0.22, (sx * 1.25, fy - 0.62, 1.2), '#4aa65a', segs=8, grad=('#3a8a4c', '#82d273'))
    # a trestle table of bread under the awning, left of the door (the bicycle with the bread basket is a separate prop)
    for sx in (-1, 1): box((0.08, 0.7, 0.9), (-3.1 + sx * 0.95, fy - 1.0, 0.45), wood, 0.02)
    box((2.2, 0.9, 0.1), (-3.1, fy - 1.0, 0.92), '#a0703f', 0.03)
    box((2.0, 0.7, 0.04), (-3.1, fy - 1.0, 0.99), '#fff6ea', 0.01)
    for i in range(5): ball(0.2, (-3.8 + i * 0.4, fy - 1.0, 1.12), '#e5a04a', (1.0, 0.7, 0.62), 10, grad=('#b9722f', '#f0bd62'))
    for i in range(3): ball(0.17, (-3.65 + i * 0.5, fy - 0.75, 1.4), '#d98d3a', (1.0, 0.7, 0.62), 10, grad=('#b9722f', '#f0bd62'))
    box((W - 0.4, 0.34, 0.2), (0, 0.1, H1 + H2 + 2.2), '#a64a2c', 0.05)         # ridge cap
    box((0.6, 0.6, 0.18), (2.6, 1.2, H1 + H2 + 2.75), '#5b3a29', 0.03)         # chimney pot
    export('bld_bakery')

def cafe(rented=False):
    new_asset()
    W, D, H1, H2 = 8.5, 7.0, 4.4, 3.4
    fy = -D / 2
    wall = '#8b5a3c' if not rented else '#cfc6bb'; trim = '#f7e7d0'; wood = '#5b3a29'
    box((W, D, H1), (0, 0, H1 / 2), wall, 0.12)
    box((W - 0.4, D - 0.4, H2), (0, 0.1, H1 + H2 / 2), '#e8d6c0' if not rented else '#dcd5cc', 0.12)
    box((W + 0.2, D + 0.2, 0.3), (0, 0, H1 + 0.05), trim, 0.06)
    if not rented:
        box((W - 1.0, 0.1, 2.9), (0, fy - 0.01, 2.0), '#ffd27a', 0, kind='glass')   # big shop window
        for x in (-W / 2 + 0.6, -1.4, 1.4, W / 2 - 0.6): box((0.2, 0.25, 3.1), (x, fy - 0.08, 2.0), trim, 0.04)
        box((W - 0.8, 0.25, 0.22), (0, fy - 0.08, 3.5), trim, 0.04); box((W - 0.8, 0.3, 0.3), (0, fy - 0.1, 0.45), wood, 0.05)
        door(0, 0.05, 1.4, 2.9, fy - 0.12, '#2f4858')
        awning(W - 0.4, 1.6, 0.9, (0, fy - 0.05, H1 - 0.2), '#2e7d5b', '#f7e7d0', 9)
        sign_board(0, H1 + 0.6, 3.2, 0.85, fy + 0.15, '#2f4858', '#f0b44c')
        # coffee cup on the sign corner
        cyl(0.42, 0.6, (W / 2 - 0.3, fy - 0.5, 4.9), '#fff6ea', 18, r2=0.33)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.18, minor_radius=0.06, location=(W / 2 + 0.12, fy - 0.5, 4.9), rotation=(math.pi / 2, 0, 0))
        _finish(bpy.context.active_object, '#fff6ea', 0)
        for i, x in enumerate((-2.0, 0.0, 2.0)): window(x, H1 + 1.7, 1.2, 1.4, fy + 0.2, trim, shutters='#2e7d5b')
    else:
        box((W - 1.0, 0.1, 2.9), (0, fy - 0.01, 2.0), '#e9e3d6', 0)                # papered window
        for x in (-W / 2 + 0.6, -1.4, 1.4, W / 2 - 0.6): box((0.2, 0.25, 3.1), (x, fy - 0.08, 2.0), '#bdb3a7', 0.04)
        box((W - 0.8, 0.25, 0.22), (0, fy - 0.08, 3.5), '#bdb3a7', 0.04)
        door(0, 0.05, 1.4, 2.9, fy - 0.12, '#8d8d8d', '#bdb3a7', glass=False)
        sign_board(0, 2.2, 2.6, 1.0, fy - 0.15, '#ffffff', '#e94b4b')            # "for rent"
        for x in (-2.0, 0.0, 2.0): window(x, H1 + 1.7, 1.2, 1.4, fy + 0.2, '#d8d0c5', shutters='#9e9e9e')
    prism_roof(W - 0.4, D - 0.4, 1.8, (0, 0.1, H1 + H2), '#7d4b32' if not rented else '#9b8e82')
    export('bld_cafe' + ('_rent' if rented else ''))

def minimarket():
    new_asset()
    W, D, H1, H2 = 9.0, 7.0, 4.3, 3.2
    fy = -D / 2
    box((W, D, H1), (0, 0, H1 / 2), '#f4f1ea', 0.12)
    box((W - 0.4, D - 0.4, H2), (0, 0.1, H1 + H2 / 2), '#dfe9f2', 0.12)
    box((W + 0.2, D + 0.2, 0.3), (0, 0, H1 + 0.05), '#2f6fb3', 0.06)
    box((W - 1.2, 0.1, 2.8), (0, fy - 0.01, 1.9), '#ffe6a6', 0, kind='glass')
    for x in (-W / 2 + 0.6, -1.5, 1.5, W / 2 - 0.6): box((0.2, 0.25, 3.0), (x, fy - 0.08, 1.9), '#2f6fb3', 0.04)
    door(0, 0.05, 1.6, 2.8, fy - 0.12, '#2f6fb3')
    awning(W - 0.4, 1.6, 0.9, (0, fy - 0.05, H1 - 0.2), '#2f6fb3', '#ffffff', 11)
    sign_board(0, H1 + 0.6, 4.0, 0.85, fy + 0.15, '#2f6fb3', '#ffffff')
    for x in (-2.4, 0.0, 2.4): window(x, H1 + 1.6, 1.3, 1.3, fy + 0.2, '#ffffff', sill=True)
    # fruit and vegetable crates
    fruit = ['#e74c3c', '#f39c12', '#2ecc71', '#f1c40f', '#8e44ad', '#e67e22']
    for i, x in enumerate((-3.5, -2.4, 2.4, 3.5)):
        box((0.95, 0.8, 0.55), (x, fy - 0.9, 0.55), '#a0703f', 0.04)
        box((0.95, 0.8, 0.12), (x, fy - 0.9, 0.12), '#7a5230', 0.03)
        for k in range(6):
            ball(0.13, (x - 0.3 + (k % 3) * 0.3, fy - 1.1 + (k // 3) * 0.35, 0.9), fruit[(i * 2 + k) % len(fruit)], segs=8)
    flat_roof(W - 0.4, D - 0.4, (0, 0.1, H1 + H2), '#9fb6c9')
    export('bld_minimarket')

def flat_roof(w, d, loc, col):
    box((w + 0.3, d + 0.3, 0.4), (loc[0], loc[1], loc[2] + 0.2), col, 0.08)
    box((1.4, 1.0, 0.9), (loc[0] + w * 0.25, loc[1] + 0.5, loc[2] + 0.85), '#b0bec5', 0.06)    # AC unit
    cyl(0.25, 0.08, (loc[0] + w * 0.25, loc[1] + 0.0, loc[2] + 0.9), '#78909c', 14, rot=(math.pi / 2, 0, 0))

def office():
    new_asset()
    W, D = 8.0, 7.0; H = 11.0
    fy = -D / 2
    box((W, D, H), (0, 0, H / 2), '#e8eef5', 0.12)
    box((W + 0.2, D + 0.2, 0.35), (0, 0, H + 0.15), '#5d7fa3', 0.06)
    for fl in range(3):
        z = 2.3 + fl * 3.4
        box((W - 0.8, 0.1, 2.2), (0, fy - 0.01, z), '#bfe3ff', 0, kind='glass')
        for x in (-W / 2 + 0.4, -1.3, 1.3, W / 2 - 0.4): box((0.18, 0.2, 2.4), (x, fy - 0.06, z), '#5d7fa3', 0.03)
        box((W - 0.4, 0.3, 0.25), (0, fy - 0.1, z - 1.25), '#d5dde6', 0.04)
    box((2.2, 0.3, 3.0), (2.2, fy - 0.1, 1.55), '#5d7fa3', 0.05)
    door(2.2, 0.05, 1.5, 2.8, fy - 0.15, '#3b5b7d')
    sign_board(-1.6, 3.7, 3.4, 0.75, fy - 0.1, '#1f3a5f', '#ffffff')
    for x in (-2.8, -0.6): cyl(0.35, 0.8, (x, fy - 0.8, 0.4), '#8d6e63', 12)
    for x in (-2.8, -0.6): ball(0.55, (x, fy - 0.8, 1.2), '#43a047', (1, 1, 1.2), 12)
    export('bld_office')

def bank():
    new_asset()
    W, D, H = 7.5, 7.0, 6.0
    fy = -D / 2
    stone = '#efe6d6'
    box((W, D, H), (0, 0, H / 2), stone, 0.1)
    box((W + 0.5, D + 0.5, 0.5), (0, 0, 0.25), '#d8ccb8', 0.06)
    for x in (-2.6, -0.9, 0.9, 2.6):
        cyl(0.32, 4.6, (x, fy - 0.8, 2.8), '#fbf6ec', 16)
        box((0.9, 0.9, 0.3), (x, fy - 0.8, 0.55), '#e2d7c4', 0.04); box((0.9, 0.9, 0.3), (x, fy - 0.8, 5.15), '#e2d7c4', 0.04)
    box((W + 0.6, 2.2, 0.6), (0, fy - 0.4, 5.6), '#f6efe2', 0.08)
    me = bpy.data.meshes.new('ped'); bm = bmesh.new()
    vs = [bm.verts.new(p) for p in [(-W / 2 - 0.3, 0, 0), (W / 2 + 0.3, 0, 0), (0, 0, 1.4)]]; bm.faces.new(vs); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new('ped', me); bpy.context.scene.collection.objects.link(o); o.location = (0, fy - 1.0, 5.9)
    bpy.context.view_layer.objects.active = o; s = o.modifiers.new('s', 'SOLIDIFY'); s.thickness = 1.2; bpy.ops.object.modifier_apply(modifier='s'); _finish(o, '#f6efe2', 0)
    door(0, 0.5, 1.8, 3.2, fy, '#6d4c41')
    window(-2.4, 3.0, 1.0, 2.0, fy, '#fbf6ec', sill=False)
    window(2.4, 3.0, 1.0, 2.0, fy, '#fbf6ec', sill=False)
    sign_board(0, 4.55, 3.2, 0.6, fy - 1.05, '#1f3a5f', '#f0b44c')
    export('bld_bank')

def warehouse():
    new_asset()
    W, D, H = 11.0, 8.0, 6.2
    fy = -D / 2
    box((W, D, H), (0, 0, H / 2), '#c9d3db', 0.1)
    for i in range(12): box((0.12, 0.1, H - 0.4), (-W / 2 + 0.5 + i * (W - 1) / 11, fy - 0.03, H / 2), '#b3bec7', 0.02, seg=1)   # ribbed cladding
    for x in (-2.6, 2.6):
        box((3.6, 0.2, 4.0), (x, fy - 0.08, 2.0), '#90a4ae', 0.04)
        for k in range(9): box((3.4, 0.1, 0.06), (x, fy - 0.2, 0.3 + k * 0.42), '#78909c', 0.01, seg=1)
    box((W + 0.4, 1.6, 0.3), (0, fy - 0.7, 4.6), '#ff9800', 0.06)
    sign_board(0, 5.4, 5.0, 0.8, fy - 0.15, '#ff9800', '#ffffff')
    box((W + 0.3, D + 0.3, 0.35), (0, 0, H + 0.1), '#90a4ae', 0.06)
    for k in range(4): box((1.0, 1.0, 0.8), (-4.5 + k * 1.1, fy - 1.0, 0.4), '#c8a26a', 0.04)   # boxes on a pallet
    box((4.6, 1.2, 0.15), (-2.9, fy - 1.0, 0.07), '#8d6e63', 0.02)
    export('bld_warehouse')

# ------------------------------------------------------------------ street props
def lamp():
    new_asset()
    cyl(0.12, 4.6, (0, 0, 2.3), '#2f3b52', 10)
    cyl(0.28, 0.4, (0, 0, 0.2), '#2f3b52', 12)
    box((0.1, 0.7, 0.1), (0, -0.35, 4.6), '#2f3b52', 0.02)
    cyl(0.32, 0.55, (0, -0.7, 4.35), '#2f3b52', 8, r2=0.18)
    ball(0.2, (0, -0.7, 4.1), '#fff2c9', segs=10, kind='glass')
    export('prop_lamp')

def tree(name, h=4.2, col='#5cb85c', lobes=9, blossom=None):
    """a rounder, fuller tree: a forked trunk, overlapping lobes that are dark underneath and light on top, a root flare"""
    new_asset()
    cyl(0.24, h * 0.55, (0, 0, h * 0.27), '#7b5a47', 10, r2=0.15)
    for sx in (-1, 1): cyl(0.1, h * 0.35, (sx * 0.22, 0.05, h * 0.56), '#7b5a47', 8, rot=(0, sx * 0.4, 0), r2=0.06)
    cyl(0.62, 0.22, (0, 0, 0.11), '#8d7466', 14, r2=0.34)
    dark = shade(col, 0.55); light = shade(col, 1.12)
    spots = [(0, 0, 0.72, 1.35), (0.85, 0.3, 0.6, 0.95), (-0.85, -0.2, 0.62, 1.0), (0.15, -0.8, 0.82, 0.9), (-0.25, 0.7, 0.86, 0.88),
             (0.6, -0.5, 0.95, 0.75), (-0.6, -0.4, 1.0, 0.7), (0.2, 0.2, 1.08, 0.82), (-0.3, 0.3, 0.55, 0.8), (0.45, 0.65, 0.78, 0.75)]
    for (x, y, zf, r) in spots[:lobes]:
        c = shade(col, random.uniform(0.9, 1.08))
        ball(r, (x, y, h * zf), c, segs=11, grad=(shade(dark, random.uniform(0.95, 1.05)), shade(light, random.uniform(0.95, 1.05))))
    if blossom:
        for i in range(20):
            a = random.uniform(0, math.tau); rr = random.uniform(0.7, 1.5); zz = h * random.uniform(0.62, 1.1)
            ball(0.15, (math.cos(a) * rr, math.sin(a) * rr, zz), blossom if i % 3 else '#fff0f4', segs=5)
    export(name)

def poplar(name='prop_tree_d', h=6.4):
    new_asset()
    cyl(0.2, 1.6, (0, 0, 0.8), '#7b5a47', 8, r2=0.14)
    for i, (z, r) in enumerate([(1.8, 0.95), (2.7, 1.05), (3.7, 0.98), (4.7, 0.8), (5.5, 0.5)]):
        ball(r, (random.uniform(-0.1, 0.1), 0, z), '#4f9d55', (1, 1, 1.5), 12, grad=('#2f6b3b', '#7fc272'))
    export(name)

def bush(name='prop_bush'):
    new_asset()
    for i, (x, r) in enumerate([(-0.9, 0.55), (-0.3, 0.7), (0.4, 0.65), (1.0, 0.5), (0.05, 0.55)]):
        ball(r, (x, random.uniform(-0.1, 0.1), r * 0.8), '#4aa65a', (1, 1, 0.85), 10, grad=('#2f7a45', '#79cc6e'))
    for i in range(7): ball(0.07, (random.uniform(-1.2, 1.2), -0.5, random.uniform(0.5, 1.0)), random.choice(['#ff7a8a', '#ffd23f', '#ffffff']), segs=5)
    export(name)

def hydrant():
    new_asset()
    cyl(0.2, 0.7, (0, 0, 0.35), '#d94b3d', 12)
    ball(0.21, (0, 0, 0.72), '#d94b3d', segs=10)
    cyl(0.08, 0.1, (0, 0, 0.96), '#a8352b', 8)
    for sx in (-1, 1): cyl(0.07, 0.2, (sx * 0.24, 0, 0.5), '#a8352b', 8, rot=(0, math.pi / 2, 0))
    cyl(0.26, 0.1, (0, 0, 0.05), '#a8352b', 12)
    export('prop_hydrant')

def mailbox():
    new_asset()
    cyl(0.06, 0.9, (0, 0, 0.45), '#2f3b52', 8)
    box((0.7, 0.5, 0.42), (0, 0, 1.1), '#2f6fb3', 0.1)
    cyl(0.25, 0.5, (0, 0, 1.31), '#2f6fb3', 14, rot=(math.pi / 2, 0, 0))
    box((0.35, 0.03, 0.06), (0, -0.26, 1.15), '#10223d', 0.01)
    export('prop_mailbox')

def trash_bin():
    new_asset()
    cyl(0.32, 0.8, (0, 0, 0.4), '#3e8e63', 14, r2=0.37)
    cyl(0.38, 0.1, (0, 0, 0.83), '#2f6f4c', 14)
    cyl(0.07, 0.07, (0, 0, 0.92), '#2f6f4c', 8)
    export('prop_bin')

def bike():
    """a bicycle with a bread basket"""
    new_asset()
    for x in (-0.62, 0.62):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.04, location=(x, 0, 0.46), rotation=(math.pi / 2, 0, 0), major_segments=20, minor_segments=6)
        _finish(bpy.context.active_object, '#2b2b2b', 0)
        cyl(0.05, 0.1, (x, 0, 0.46), '#c0c4c8', 8, rot=(math.pi / 2, 0, 0), bevel=0)
    wire([(-0.62, 0, 0.46), (-0.1, 0, 0.5), (0.35, 0, 1.0), (-0.3, 0, 1.0), (-0.62, 0, 0.46)], '#2fb3a2', 0.04)
    wire([(-0.1, 0, 0.5), (0.35, 0, 1.0)], '#2fb3a2', 0.04)
    wire([(0.35, 0, 1.0), (0.62, 0, 0.46)], '#2fb3a2', 0.04)
    wire([(0.3, 0, 1.0), (0.38, 0, 1.2), (0.3, 0.3, 1.25), (0.3, -0.3, 1.25)], '#2b2b2b', 0.03)
    box((0.34, 0.18, 0.07), (-0.3, 0, 1.05), '#2b2b2b', 0.02)
    box((0.5, 0.42, 0.34), (0.82, 0, 0.9), '#c9a06a', 0.05)
    for i in range(3): cyl(0.05, 0.62, (0.82 + (i - 1) * 0.11, 0.0, 1.2), '#e3a24a', 8, rot=(0, 0.35, 0), bevel=0)
    export('prop_bike')

def festoon(lamp_x, y_wire=-4.15, z_top=4.55, sag=0.55, name='prop_lights'):
    """string lights between the street lamps: a sagging cable and warm bulbs that glow at night (glass parts)"""
    new_asset()
    cols = ['#ffd27a', '#ffb7a0', '#ffe9a8', '#bfe3ff']
    for a, b in zip(lamp_x[:-1], lamp_x[1:]):
        n = 10
        pts = [(a + (b - a) * i / n, y_wire, z_top - sag * math.sin(math.pi * i / n)) for i in range(n + 1)]
        wire(pts, '#2f3b52', 0.025)
        for i in range(1, n):
            ball(0.11, (pts[i][0], pts[i][1], pts[i][2] - 0.14), cols[i % 4], segs=6, kind='glass')
    export(name)

def mix(c1, c2, k):
    c1 = c1.lstrip('#'); c2 = c2.lstrip('#')
    a = [int(c1[i:i + 2], 16) for i in (0, 2, 4)]; b = [int(c2[i:i + 2], 16) for i in (0, 2, 4)]
    return '#%02x%02x%02x' % tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))

def bench():
    new_asset()
    for k in range(3): box((2.2, 0.22, 0.08), (0, -0.25 + k * 0.25, 0.75), '#a0703f', 0.02)
    for k in range(2): box((2.2, 0.08, 0.2), (0, 0.38, 1.05 + k * 0.28), '#a0703f', 0.02)
    for sx in (-1, 1): box((0.1, 0.8, 0.75), (sx * 0.9, 0.05, 0.37), '#2f3b52', 0.02)
    export('prop_bench')

def planter():
    new_asset()
    box((1.6, 0.8, 0.6), (0, 0, 0.3), '#d7ccc8', 0.06)
    cols = ['#ff6b6b', '#ffd23f', '#ff9ff3', '#ffffff']
    for i in range(6):
        ball(0.3, (-0.55 + i * 0.22, random.uniform(-0.15, 0.15), 0.75), '#4caf50', (1, 1, 0.9), 8)
        ball(0.09, (-0.55 + i * 0.22, -0.25, 0.95), cols[i % 4], segs=6)
    export('prop_planter')

def umbrella_table():
    new_asset()
    cyl(0.55, 0.06, (0, 0, 1.0), '#fff6ea', 18)
    cyl(0.05, 1.0, (0, 0, 0.5), '#5b3a29', 8)
    cyl(0.35, 0.05, (0, 0, 0.03), '#5b3a29', 12)
    cyl(0.04, 2.6, (0, 0, 1.6), '#5b3a29', 8)
    cyl(1.6, 0.6, (0, 0, 2.9), '#fff6ea', 12, r2=0.05)
    for i in range(12):
        if i % 2: continue
        a = i / 12 * math.tau
    for sx in (-1, 1):
        box((0.5, 0.5, 0.06), (sx * 0.9, 0, 0.55), '#2e7d5b', 0.03)
        box((0.5, 0.06, 0.6), (sx * 0.9, 0.24 * sx * 0 + 0.24, 0.85), '#2e7d5b', 0.03)
        for dx in (-0.2, 0.2):
            for dy in (-0.2, 0.2): cyl(0.03, 0.55, (sx * 0.9 + dx, dy, 0.27), '#2f3b52', 6)
    export('prop_table')

def car(name, col):
    new_asset()
    box((3.6, 1.7, 0.8), (0, 0, 0.75), col, 0.25, seg=3)
    box((2.0, 1.5, 0.7), (-0.2, 0, 1.45), shade(col, 1.05), 0.25, seg=3)
    box((2.05, 1.52, 0.5), (-0.2, 0, 1.45), '#bfe3ff', 0.15, kind='glass')
    for sx in (-1, 1):
        for sy in (-1, 1): cyl(0.36, 0.3, (sx * 1.15, sy * 0.82, 0.38), '#263238', 14, rot=(math.pi / 2, 0, 0))
    for sy in (-0.55, 0.55): ball(0.12, (1.8, sy, 0.85), '#fff8e1', segs=8)
    export(name)

def truck():
    new_asset()
    box((4.2, 2.1, 2.4), (-0.8, 0, 1.75), '#ffffff', 0.12)
    box((1.8, 2.0, 1.6), (2.3, 0, 1.35), '#ff9800', 0.2, seg=3)
    box((0.1, 1.7, 0.7), (3.2, 0, 1.75), '#bfe3ff', 0.05, kind='glass')
    box((4.0, 0.06, 0.6), (-0.8, -1.07, 2.2), '#ff9800', 0.02)
    for x in (-2.2, 0.2, 2.4):
        for sy in (-1, 1): cyl(0.42, 0.32, (x, sy * 0.95, 0.42), '#263238', 14, rot=(math.pi / 2, 0, 0))
    export('prop_truck')

def fountain():
    new_asset()
    cyl(1.8, 0.6, (0, 0, 0.3), '#cfd8dc', 24)
    cyl(1.55, 0.1, (0, 0, 0.58), '#4fc3f7', 24, kind='glass')
    cyl(0.25, 1.4, (0, 0, 1.0), '#cfd8dc', 12)
    cyl(0.8, 0.25, (0, 0, 1.65), '#cfd8dc', 18)
    cyl(0.65, 0.06, (0, 0, 1.76), '#4fc3f7', 18, kind='glass')
    ball(0.22, (0, 0, 2.0), '#cfd8dc', segs=10)
    export('prop_fountain')

def skyline():
    """three layers of distance: round hills far back, pale tall blocks, then nearer pastel buildings with roof details and windows
    that glow at night (glass parts). The farther the layer, the closer its colours are to the haze, which gives depth."""
    new_asset()
    haze = '#cfe0ee'
    def hz(c, k): return mix(c, haze, k)
    x = -90.0
    while x < 90:
        r = random.uniform(11, 20)
        ball(r, (x, 16, -r * 0.35), hz(random.choice(['#8fb98f', '#86b087', '#9cc29a']), 0.45), (1.0, 0.8, 0.5), 14, grad=(hz('#7fa883', 0.45), hz('#a6cc9f', 0.4)))
        x += random.uniform(14, 22)
    x = -80.0
    while x < 80:
        w = random.uniform(5, 9); h = random.uniform(10, 24); c = hz(random.choice(['#a9c4dc', '#b8cde0', '#c2d3e4']), 0.35)
        box((w, 4, h), (x + w / 2, 8, h / 2), c, 0.1, seg=1)
        x += w + random.uniform(0.2, 1.2)
    cols = ['#b4cbe0', '#c6d6e6', '#a6bfd6', '#e6d3c0', '#dcc3ad', '#e8c6b0', '#cfd9c0', '#e9d8b6']
    x = -62.0
    while x < 62:
        w = random.uniform(4.5, 8.5); h = random.uniform(8, 20); c = hz(random.choice(cols), 0.12)
        box((w, 5, h), (x + w / 2, 0, h / 2), c, 0.1, seg=1)
        box((w + 0.4, 5.4, 0.45), (x + w / 2, 0, h + 0.1), shade(c, 0.86), 0.05, seg=1)
        r = random.random()
        if r < 0.3: cyl(0.8, 1.6, (x + w * 0.3, 0.5, h + 1.0), '#9b7a62', 10)
        elif r < 0.55:
            box((1.2, 1.2, 1.1), (x + w * 0.65, 0.5, h + 0.95), '#9aa7b3', 0.05)
            cyl(0.05, 2.2, (x + w * 0.3, 0.5, h + 1.4), '#5f6b78', 6)
        elif r < 0.7: box((w * 0.55, 3.0, 2.0), (x + w / 2, 0.4, h + 1.2), shade(c, 0.95), 0.08)
        for fl in range(int(h / 2.7)):
            for k in range(int(w / 1.7)):
                xx = x + 0.9 + k * 1.7; zz = 1.7 + fl * 2.7
                if zz > h - 1.2: continue
                lit = random.random()
                col = '#ffd68a' if lit < 0.35 else ('#7fa6c9' if lit < 0.75 else '#5f86ab')
                box((0.8, 0.12, 1.2), (xx, -2.55, zz), col, 0, kind='glass', seg=1)
                box((1.0, 0.14, 0.12), (xx, -2.55, zz - 0.68), shade(c, 0.78), 0, seg=1)
        x += w + random.uniform(0.3, 1.4)
    for i in range(26):
        tx = random.uniform(-58, 58)
        ball(random.uniform(1.6, 2.8), (tx, -3.6, 1.4), '#6fb36f', (1, 1, 0.9), 10, grad=(hz('#3f8a50', 0.12), hz('#86cc7c', 0.1)))
    export('town_skyline')

os.makedirs(OUT, exist_ok=True)
bakery(); cafe(False); cafe(True); minimarket(); office(); bank(); warehouse()
lamp(); tree('prop_tree'); tree('prop_tree_b', 5.0, '#7cc36b'); tree('prop_tree_c', 4.4, '#6dbd6a', 8, '#ff9fc0'); poplar(); bush()
bench(); planter(); umbrella_table(); hydrant(); mailbox(); trash_bin(); bike()
festoon([-24.0, -14.0, -4.5, 5.0, 15.0, 23.0, 33.0])
car('prop_car_red', '#e74c3c'); car('prop_car_blue', '#3b7dd8'); truck(); fountain(); skyline()
