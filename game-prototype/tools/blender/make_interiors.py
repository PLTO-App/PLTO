"""Builds the shop interiors and the food in Blender from code (own work, no external assets), in the same toy style as the town.

Rooms: room_bakery, room_cafe (floor is drawn by the game). Furniture: display case, oven, work table, bread shelf, register,
espresso bar, pastry case, tables, chairs, fridge, plants, menu boards. Food: croissant, challah, carrot cake, strawberry cake,
cappuccino, iced coffee, cookie, a paper bag. Fronts face the camera (Blender -Y -> Godot +Z).

Run: blender -b --factory-startup --python make_interiors.py -- <out_dir>
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit import *
from kit import _finish
import kit
import bpy, bmesh

random.seed(3)

# ------------------------------------------------------------------ rooms
def room(name, wall, wainscot, trim, accent, windows_left=True):
    new_asset()
    W, D, H = 12.6, 8.6, 4.4
    # back wall and the two side walls (the front is open toward the camera); y back = +D/2 in Blender is the far side
    box((W + 0.5, 0.5, H), (0, D / 2 + 0.25, H / 2), wall, 0.08)
    for sx in (-1, 1): box((0.5, D, H), (sx * (W / 2 + 0.25), 0, H / 2), wall, 0.08)
    # wainscoting band and trims
    box((W, 0.12, 1.5), (0, D / 2 - 0.02, 0.75), wainscot, 0.03)
    for sx in (-1, 1): box((0.12, D, 1.5), (sx * (W / 2 - 0.02), 0, 0.75), wainscot, 0.03)
    for z in (1.52, H - 0.12):
        box((W, 0.2, 0.14), (0, D / 2 - 0.06, z), trim, 0.03)
        for sx in (-1, 1): box((0.2, D, 0.14), (sx * (W / 2 - 0.06), 0, z), trim, 0.03)
    for i in range(int(W / 0.7)):
        box((0.06, 0.06, 1.3), (-W / 2 + 0.35 + i * 0.7, D / 2 - 0.1, 0.75), shade(wainscot, 0.9), 0.01, seg=1)
    if windows_left:
        for y in (-1.6, 1.4):
            box((0.1, 2.0, 1.8), (-W / 2 + 0.02, y, 2.6), '#cfeaff', 0, kind='glass')
            box((0.2, 2.3, 0.15), (-W / 2 + 0.05, y, 3.55), trim, 0.03); box((0.3, 2.4, 0.15), (-W / 2 + 0.08, y, 1.65), trim, 0.03)
            for yy in (-1.05, 0, 1.05): box((0.2, 0.12, 1.9), (-W / 2 + 0.05, y + yy, 2.6), trim, 0.02)
    # picture frames and a clock on the back wall
    for (x, w, h, c) in [(-3.6, 1.4, 1.0, accent), (4.4, 1.0, 1.3, '#7fb3d5')]:
        box((w + 0.2, 0.1, h + 0.2), (x, D / 2 - 0.08, 3.0), '#8d5a3b', 0.03)
        box((w, 0.1, h), (x, D / 2 - 0.12, 3.0), c, 0.02)
        ball(0.18, (x - w * 0.2, D / 2 - 0.16, 3.0 + h * 0.15), '#fff6ea', (1, 0.3, 1), 8)
    cyl(0.42, 0.12, (1.6, D / 2 - 0.1, 3.6), '#fff6ea', 20, rot=(math.pi / 2, 0, 0))
    cyl(0.46, 0.08, (1.6, D / 2 - 0.06, 3.6), '#2f3b52', 20, rot=(math.pi / 2, 0, 0))
    box((0.04, 0.05, 0.3), (1.6, D / 2 - 0.2, 3.7), '#2f3b52', 0, seg=1); box((0.22, 0.05, 0.04), (1.68, D / 2 - 0.2, 3.6), '#2f3b52', 0, seg=1)
    # pendant lamps
    for x in (-3.0, 0.2, 3.4):
        cyl(0.015, 1.0, (x, 0.2, H - 0.5), '#2f3b52', 6, bevel=0)
        cyl(0.45, 0.4, (x, 0.2, H - 1.1), accent, 16, r2=0.12)
        ball(0.15, (x, 0.2, H - 1.3), '#fff2c9', segs=10, kind='glass')
    export(name)

# ------------------------------------------------------------------ furniture
def display_case():
    """bakery glass display: 3 levels (z = 0.95, 1.35 inside the glass, 1.75 on top). 4.2 wide."""
    new_asset()
    box((4.2, 1.2, 1.0), (0, 0, 0.5), '#f6e3c8', 0.06)
    box((4.3, 1.3, 0.1), (0, 0, 1.03), '#e9d5bb', 0.03)
    for i in range(6): box((0.06, 0.05, 0.8), (-1.9 + i * 0.76, -0.62, 0.5), '#d9c2a3', 0.01, seg=1)
    box((4.3, 0.12, 0.12), (0, 0, 0.06), '#e94b4b', 0.03)
    box((4.1, 1.05, 0.04), (0, 0.02, 1.42), '#d9eef7', 0, kind='glass')
    box((4.1, 0.04, 0.75), (0, -0.52, 1.42), '#d9eef7', 0, kind='glass')
    for sx in (-2.07, 2.07):
        for sy in (-0.52, 0.52): box((0.05, 0.05, 0.8), (sx, sy, 1.43), '#fff6ea', 0.01, seg=1)
    box((4.2, 1.1, 0.06), (0, 0, 1.83), '#fff6ea', 0.02)
    export('f_display')

def oven():
    new_asset()
    box((2.2, 1.2, 2.6), (0, 0, 1.3), '#b0bec5', 0.1)
    for k in range(2):
        z = 0.85 + k * 1.05
        box((1.8, 0.1, 0.8), (0, -0.6, z), '#78909c', 0.04)
        box((1.4, 0.06, 0.45), (0, -0.66, z), '#ff9a3c', 0.02, kind='glass')
        box((1.5, 0.12, 0.08), (0, -0.7, z + 0.48), '#eceff1', 0.03)
    for x in (-0.7, -0.35, 0.0): cyl(0.07, 0.08, (x + 0.35, -0.65, 2.42), '#263238', 12, rot=(math.pi / 2, 0, 0))
    box((2.3, 1.3, 0.15), (0, 0, 2.65), '#90a4ae', 0.04)
    cyl(0.18, 1.6, (0.6, 0.3, 3.4), '#b0bec5', 12)
    export('f_oven')

def work_table():
    new_asset()
    box((2.4, 1.1, 0.12), (0, 0, 1.25), '#d7b48a', 0.03)
    for sx in (-1, 1):
        for sy in (-1, 1): box((0.12, 0.12, 1.2), (sx * 1.05, sy * 0.45, 0.6), '#8d6e63', 0.02)
    box((2.2, 0.9, 0.08), (0, 0, 0.35), '#8d6e63', 0.02)
    ball(0.28, (-0.4, 0, 1.4), '#f5e6c8', (1.3, 1, 0.45), 12)               # dough
    cyl(0.06, 0.7, (0.5, 0.1, 1.38), '#c8a26a', 10, rot=(0, math.pi / 2, 0.3))  # rolling pin
    for k in range(3): cyl(0.25 - k * 0.04, 0.18, (0.0 + k * 0.05, 0.3, 0.45 + k * 0.18), '#eceff1', 14)  # bowls
    export('f_worktable')

def bread_shelf():
    """wall shelf, 3 boards (z 0.9, 1.6, 2.3), 2.4 wide"""
    new_asset()
    for sx in (-1, 1): box((0.12, 0.6, 2.7), (sx * 1.2, 0, 1.35), '#8d5a3b', 0.03)
    for z in (0.9, 1.6, 2.3): box((2.5, 0.62, 0.08), (0, 0, z), '#a0703f', 0.02)
    box((2.5, 0.06, 2.7), (0, 0.3, 1.35), '#7a4a2e', 0.02)
    for z in (0.9, 1.6, 2.3):
        bpy.ops.mesh.primitive_cylinder_add(radius=1.0, depth=0.3, vertices=16, location=(0, -0.02, z + 0.12))
        o = bpy.context.active_object; o.scale = (1.15, 0.27, 1); bpy.ops.object.transform_apply(scale=True)
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z > 0.5], context='FACES'); bm.to_mesh(o.data); bm.free()
        _finish(o, '#c8a26a', 0)
    export('f_breadshelf')

def register_counter():
    new_asset()
    box((2.0, 1.1, 1.2), (0, 0, 0.6), '#2fb3a2', 0.08)
    box((2.1, 1.2, 0.1), (0, 0, 1.25), '#e9d5bb', 0.03)
    box((0.7, 0.55, 0.35), (0.3, 0.05, 1.47), '#37474f', 0.06)
    box((0.55, 0.06, 0.32), (0.3, -0.12, 1.78), '#263238', 0.03, rot=(0.4, 0, 0))
    box((0.45, 0.02, 0.24), (0.3, -0.15, 1.78), '#7ee0d1', 0, rot=(0.4, 0, 0), kind='glass')
    ball(0.12, (-0.5, 0.1, 1.4), '#ffffff', (1.4, 1, 0.4), 8)  # tray of change
    box((0.35, 0.25, 0.4), (-0.6, 0.2, 1.5), '#c8a26a', 0.04)   # tip jar
    export('f_register')

def espresso_bar():
    """café counter with the machine on top (machine centre x = 0.6), 4.0 wide"""
    new_asset()
    box((4.0, 1.2, 1.2), (0, 0, 0.6), '#5b3a29', 0.08)
    for i in range(8): box((0.08, 0.05, 1.0), (-1.75 + i * 0.5, -0.62, 0.6), '#7a4a2e', 0.01, seg=1)
    box((4.1, 1.3, 0.1), (0, 0, 1.25), '#e9d5bb', 0.03)
    box((1.3, 0.75, 0.75), (0.6, 0.15, 1.68), '#c62828', 0.12)
    box((1.36, 0.8, 0.12), (0.6, 0.15, 2.08), '#eceff1', 0.04)
    for x in (0.35, 0.85):
        cyl(0.07, 0.25, (x, -0.28, 1.6), '#cfd8dc', 10)
        cyl(0.11, 0.06, (x, -0.28, 1.47), '#cfd8dc', 12)
    cyl(0.04, 0.3, (1.15, -0.2, 1.75), '#cfd8dc', 8, rot=(0.6, 0, 0))
    cyl(0.12, 0.35, (1.05, 0.2, 2.3), '#3e2723', 14, r2=0.18)        # grinder hopper
    box((0.3, 0.3, 0.35), (1.05, 0.2, 2.05), '#eceff1', 0.04)
    for k in range(4): cyl(0.08, 0.12, (-0.6 + k * 0.22, 0.25, 1.36), '#fff6ea', 12)    # cups
    for k in range(3): cyl(0.07, 0.35, (-1.5 + k * 0.2, 0.3, 1.48), ['#6d4c41', '#8d6e63', '#a1887f'][k], 10)  # syrups
    export('f_espresso')

def pastry_case():
    """small glass case for the café (2 levels z 1.32 inside, 1.75 on top), 2.0 wide"""
    new_asset()
    box((2.0, 1.1, 1.2), (0, 0, 0.6), '#5b3a29', 0.08)
    box((2.1, 1.2, 0.1), (0, 0, 1.25), '#e9d5bb', 0.03)
    box((1.9, 0.95, 0.04), (0, 0.02, 1.7), '#d9eef7', 0, kind='glass')
    box((1.9, 0.04, 0.42), (0, -0.48, 1.5), '#d9eef7', 0, kind='glass')
    box((2.0, 1.0, 0.05), (0, 0, 1.73), '#fff6ea', 0.02)
    export('f_pastrycase')

def table(name, top='#fff6ea', leg='#2f3b52', r=0.75):
    new_asset()
    cyl(r, 0.08, (0, 0, 1.2), top, 22)
    cyl(0.06, 1.15, (0, 0, 0.6), leg, 8)
    cyl(0.4, 0.06, (0, 0, 0.03), leg, 14)
    export(name)

def chair(name, col):
    new_asset()
    box((0.75, 0.75, 0.1), (0, 0, 0.78), col, 0.04)
    box((0.75, 0.1, 0.8), (0, 0.33, 1.2), col, 0.04)
    for sx in (-1, 1):
        for sy in (-1, 1): cyl(0.035, 0.78, (sx * 0.3, sy * 0.3, 0.39), '#2f3b52', 6)
    export(name)

def fridge():
    new_asset()
    box((1.6, 1.0, 3.0), (0, 0, 1.5), '#eceff1', 0.1)
    box((1.4, 0.06, 2.6), (0, -0.5, 1.6), '#cfeaff', 0, kind='glass')
    for z in (0.8, 1.5, 2.2): box((1.4, 0.8, 0.04), (0, 0, z), '#b0bec5', 0.01, seg=1)
    for z in (0.95, 1.65, 2.35):
        for k in range(4): cyl(0.08, 0.3, (-0.5 + k * 0.33, -0.1, z), ['#ffffff', '#ffd54f', '#81c784', '#e57373'][k], 10)
    box((0.06, 0.08, 0.8), (0.6, -0.56, 1.8), '#90a4ae', 0.02)
    export('f_fridge')

def plant(name, h=1.6):
    new_asset()
    cyl(0.35, 0.6, (0, 0, 0.3), '#d7845a', 14, r2=0.28)
    for i in range(7):
        a = i / 7 * math.tau
        ball(0.32, (math.cos(a) * 0.25, math.sin(a) * 0.25, 0.7 + (i % 3) * h * 0.2), shade('#4caf50', random.uniform(0.85, 1.1)), (1, 1, 1.4), 10)
    ball(0.35, (0, 0, h), '#5cb85c', (1, 1, 1.2), 10)
    export(name)

def menu_board(name, frame='#5b3a29'):
    new_asset()
    box((2.4, 0.1, 1.5), (0, 0, 0), frame, 0.04)
    box((2.2, 0.1, 1.3), (0, -0.03, 0), '#263238', 0.02)
    export(name)

def stool():
    new_asset()
    cyl(0.3, 0.1, (0, 0, 1.3), '#c62828', 16)
    cyl(0.05, 1.25, (0, 0, 0.62), '#2f3b52', 8)
    cyl(0.28, 0.05, (0, 0, 0.03), '#2f3b52', 14)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.02, location=(0, 0, 0.5)); _finish(bpy.context.active_object, '#2f3b52', 0)
    export('f_stool')

def certificate():
    new_asset()
    box((0.9, 0.06, 0.7), (0, 0, 0), '#c8a26a', 0.02)
    box((0.75, 0.06, 0.55), (0, -0.02, 0), '#fffdf5', 0.01)
    ball(0.08, (0.22, -0.06, -0.15), '#1e88e5', (1, 0.3, 1), 10)
    for k in range(3): box((0.45, 0.02, 0.03), (-0.05, -0.06, 0.15 - k * 0.09), '#90a4ae', 0, seg=1)
    export('f_certificate')

# ------------------------------------------------------------------ food (about life size in game units)
def croissant():
    new_asset()
    for i in range(7):
        t = (i - 3) / 3.0
        a = t * 1.15
        r = 0.11 * (1.0 - 0.55 * abs(t))
        ball(r + 0.02, (math.sin(a) * 0.22, -math.cos(a) * 0.22 + 0.22, r * 0.75), shade('#d98f3c', 1.0 - 0.08 * (i % 2)), (1.0, 1.0, 0.8), 10)
    export('food_croissant')

def challah():
    new_asset()
    for i in range(6):
        x = -0.26 + i * 0.105
        for s, (dy, dz) in enumerate(((-0.05, 0.08), (0.05, 0.08), (0.0, 0.15))):
            off = 0.05 * (1 if (i + s) % 2 else -1)
            ball(0.085 - 0.012 * abs(i - 2.5) / 2.5, (x + off * 0.3, dy, dz), shade('#c97c2c', 0.95 + 0.07 * ((i + s) % 2)), (1.25, 1.0, 0.85), 10)
    for k in range(10): ball(0.012, (random.uniform(-0.25, 0.25), random.uniform(-0.05, 0.05), 0.24), '#fff3d0', segs=4)
    export('food_challah')

def cake(name, base, top, deco):
    new_asset()
    cyl(0.32, 0.04, (0, 0, 0.02), '#ffffff', 24)
    cyl(0.27, 0.26, (0, 0, 0.17), base, 24)
    cyl(0.275, 0.05, (0, 0, 0.32), top, 24)
    for k in range(8):
        a = k / 8 * math.tau
        if deco == 'berries': ball(0.045, (math.cos(a) * 0.19, math.sin(a) * 0.19, 0.37), '#e53935', segs=8)
        else:
            cyl(0.02, 0.09, (math.cos(a) * 0.19, math.sin(a) * 0.19, 0.38), '#ff8a1d', 6, r2=0.003)
    if deco == 'berries': ball(0.06, (0, 0, 0.38), '#e53935', segs=8)
    export(name)

def cup():
    new_asset()
    cyl(0.16, 0.025, (0, 0, 0.012), '#ffffff', 18)
    cyl(0.11, 0.16, (0, 0, 0.1), '#ffffff', 18, r2=0.09)
    cyl(0.1, 0.01, (0, 0, 0.18), '#e8cfa8', 18)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.05, minor_radius=0.015, location=(0.13, 0, 0.1), rotation=(math.pi / 2, 0, 0)); _finish(bpy.context.active_object, '#ffffff', 0)
    export('food_cup')

def cup_iced():
    new_asset()
    cyl(0.1, 0.32, (0, 0, 0.16), '#d9eef7', 16, r2=0.12, kind='glass')
    cyl(0.095, 0.24, (0, 0, 0.12), '#a1683a', 16, r2=0.11)
    for k in range(3): box((0.06, 0.06, 0.06), (0.03 * k - 0.03, 0.02 * k - 0.02, 0.27), '#e3f2fd', 0.01)
    cyl(0.012, 0.4, (0.04, 0, 0.35), '#2fb3a2', 6, rot=(0, 0.2, 0))
    export('food_iced')

def cookie():
    new_asset()
    cyl(0.12, 0.035, (0, 0, 0.018), '#d9a35c', 16)
    for k in range(5): ball(0.018, (random.uniform(-0.07, 0.07), random.uniform(-0.07, 0.07), 0.04), '#4e342e', segs=5)
    export('food_cookie')

def bag():
    new_asset()
    box((0.32, 0.22, 0.42), (0, 0, 0.21), '#c8a26a', 0.02)
    box((0.33, 0.23, 0.06), (0, 0, 0.42), '#b08a55', 0.01)
    box((0.12, 0.02, 0.12), (0, -0.115, 0.25), '#e94b4b', 0.01)
    export('food_bag')

def basket():
    new_asset()
    cyl(0.4, 0.22, (0, 0, 0.11), '#b9864d', 16, r2=0.46)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.45, minor_radius=0.04, location=(0, 0, 0.23)); _finish(bpy.context.active_object, '#9c6b38', 0)
    export('food_basket')

os.makedirs(kit.OUT, exist_ok=True)
room('room_bakery', '#f8e6cf', '#2fb3a2', '#fff6ea', '#ff7a59')
room('room_cafe', '#efe0cc', '#5b3a29', '#f7e7d0', '#2e7d5b')
display_case(); oven(); work_table(); bread_shelf(); register_counter(); espresso_bar(); pastry_case()
table('f_table', '#fff6ea'); table('f_table_wood', '#a0703f', '#5b3a29', 0.7)
chair('f_chair_teal', '#2fb3a2'); chair('f_chair_coral', '#ff7a59'); chair('f_chair_green', '#2e7d5b')
fridge(); plant('f_plant'); plant('f_plant_tall', 2.2); menu_board('f_menu'); stool(); certificate()
croissant(); challah(); cake('food_carrot_cake', '#e8a659', '#fff3e0', 'carrots'); cake('food_strawberry_cake', '#5d3a28', '#4e2c1d', 'berries')
cup(); cup_iced(); cookie(); bag(); basket()
