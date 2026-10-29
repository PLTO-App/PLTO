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

def tree(name, h=4.2, col='#5cb85c'):
    new_asset()
    cyl(0.22, h * 0.55, (0, 0, h * 0.27), '#8d6e63', 10, r2=0.16)
    for (x, y, z, r) in [(0, 0, h * 0.7, 1.3), (0.7, 0.3, h * 0.6, 0.9), (-0.7, -0.2, h * 0.62, 0.95), (0.1, -0.6, h * 0.85, 0.85), (-0.2, 0.5, h * 0.9, 0.8)]:
        ball(r, (x, y, z), shade(col, random.uniform(0.85, 1.08)), segs=12)
    cyl(0.75, 0.25, (0, 0, 0.12), '#a1887f', 14)
    export(name)

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
    new_asset()
    cols = ['#a9c4dc', '#b9cfe3', '#9fb8d2', '#c6d6e6', '#98b3cc', '#d8c3ae', '#c9b29d', '#e0b9a0']
    x = -60.0
    while x < 60:
        w = random.uniform(4, 8); h = random.uniform(7, 19)
        c = random.choice(cols)
        box((w, 5, h), (x + w / 2, 0, h / 2), c, 0.1, seg=1)
        for fl in range(int(h / 2.6)):
            for k in range(int(w / 1.6)):
                if random.random() < 0.7:
                    box((0.7, 0.1, 1.0), (x + 0.8 + k * 1.6, -2.55, 1.6 + fl * 2.6), shade(c, 0.82), 0, seg=1)
        x += w + random.uniform(0.3, 1.5)
    for i in range(14):
        tree_x = random.uniform(-55, 55)
        ball(random.uniform(1.6, 2.6), (tree_x, -3.5, 1.5), shade('#7cb87c', random.uniform(0.85, 1.05)), segs=8)
    export('town_skyline')

os.makedirs(OUT, exist_ok=True)
bakery(); cafe(False); cafe(True); minimarket(); office(); bank(); warehouse()
lamp(); tree('prop_tree'); tree('prop_tree_b', 5.0, '#7cc36b'); bench(); planter(); umbrella_table()
car('prop_car_red', '#e74c3c'); car('prop_car_blue', '#3b7dd8'); truck(); fountain(); skyline()
