class_name ShopRoom
extends Node3D
# The inside of one of our businesses (bakery or café), built from the interior kit (tools/blender/make_interiors.py).
# The layout is data (LAYOUTS): furniture, where Noa picks up and hands over, where customers queue and sit, and where each product
# is shown. The shelves show the real stock, the menu board shows today's prices, and bought upgrades appear in the room.
# Coordinates: back wall at z = -4.3, open front toward the camera (+z), door at the front right.

const LAYOUTS := {
	"bakery": {
		"room": "room_bakery", "floor": Color("c99f74"), "floor_line": Color("a97f57"), "floor_tile": 1.0,
		"furniture": [
			["f_breadshelf", Vector3(-4.6, 0, -3.95), 0.0], ["f_oven", Vector3(-1.4, 0, -3.6), 0.0], ["f_worktable", Vector3(1.6, 0, -3.2), 0.0],
			["f_display", Vector3(-1.2, 0, 0.1), 0.0], ["f_register", Vector3(3.3, 0, 0.1), 0.0],
			["f_plant_tall", Vector3(-5.6, 0, 3.4), 0.0], ["f_plant", Vector3(5.6, 0, -3.6), 0.0]],
		"upgrades": {"fridge": [["f_fridge", Vector3(4.6, 0, -3.6), 0.0]],
			"tables": [["f_table", Vector3(-4.2, 0, 2.6), 0.0], ["f_chair_teal", Vector3(-5.2, 0, 2.6), -PI / 2], ["f_chair_coral", Vector3(-3.2, 0, 2.6), PI / 2]],
			"display": [["f_plant", Vector3(-3.6, 1.83, 0.1), 0.0]]},
		"menu": [Vector3(1.6, 2.75, -4.17), 0.0], "cert": Vector3(-6.22, 2.9, 0.4),
		"noa_home": Vector3(0.6, 0, -1.3), "serve_spot": Vector3(3.3, 0, -1.15), "serve_at": Vector3(3.3, 1.35, 0.1),
		"customer_spot": Vector3(3.3, 0, 1.55), "queue": [Vector3(4.5, 0, 2.3), Vector3(5.2, 0, 3.2), Vector3(4.2, 0, 3.7), Vector3(3.0, 0, 3.8), Vector3(1.8, 0, 3.8), Vector3(0.6, 0, 3.8)],
		"door": Vector3(6.4, 0, 6.5), "entry": Vector3(5.6, 0, 4.6),
		"staff_spot": Vector3(-1.2, 0, -1.25), "staff_customer": Vector3(-1.2, 0, 1.55),
		"seats": [[Vector3(-5.2, 0, 2.6), PI / 2, "tables"], [Vector3(-3.2, 0, 2.6), -PI / 2, "tables"]],
		"pick": {"croissant": Vector3(-2.3, 0, -1.15), "challah": Vector3(-4.6, 0, -2.9), "carrot_cake": Vector3(-1.8, 0, -1.15), "strawberry_cake": Vector3(-0.4, 0, -1.15)},
		"slots": {
			"croissant": {"model": "food_croissant", "base": Vector3(-2.6, 1.9, 0.1), "basket": true, "max": 10},
			"challah": {"model": "food_challah", "rows": [Vector3(-4.6, 0.98, -3.85), Vector3(-4.6, 1.68, -3.85), Vector3(-4.6, 2.38, -3.85)], "per_row": 3, "dx": 0.7, "max": 9},
			"carrot_cake": {"model": "food_carrot_cake", "base": Vector3(-2.0, 1.07, 0.1), "dx": 0.62, "max": 3},
			"strawberry_cake": {"model": "food_strawberry_cake", "base": Vector3(-0.1, 1.07, 0.1), "dx": 0.62, "max": 3}}
	},
	"cafe": {
		"room": "room_cafe", "floor": Color("b98b63"), "floor_line": Color("9b7350"), "floor_tile": 0.8,
		"furniture": [
			["f_espresso", Vector3(1.4, 0, -0.9), 0.0], ["f_pastrycase", Vector3(-1.6, 0, -0.9), 0.0],
			["f_breadshelf", Vector3(-4.6, 0, -3.95), 0.0], ["f_plant_tall", Vector3(5.6, 0, -3.6), 0.0], ["f_plant", Vector3(-5.6, 0, 3.6), 0.0],
			["f_table_wood", Vector3(-4.4, 0, 2.2), 0.0], ["f_chair_green", Vector3(-5.4, 0, 2.2), -PI / 2], ["f_chair_green", Vector3(-3.4, 0, 2.2), PI / 2],
			["f_table_wood", Vector3(-0.8, 0, 2.9), 0.0], ["f_chair_green", Vector3(-1.8, 0, 2.9), -PI / 2], ["f_chair_green", Vector3(0.2, 0, 2.9), PI / 2]],
		"upgrades": {"terrace": [["f_table_wood", Vector3(4.4, 0, 3.6), 0.0], ["f_chair_green", Vector3(3.4, 0, 3.6), -PI / 2]],
			"fridge": [["f_fridge", Vector3(3.9, 0, -3.6), 0.0]], "machine": [["f_espresso", Vector3(4.6, 0, -0.9), 0.0]]},
		"menu": [Vector3(1.4, 2.8, -4.17), 0.0], "cert": Vector3(-6.22, 2.9, 0.4),
		"noa_home": Vector3(0.2, 0, -2.0), "serve_spot": Vector3(1.0, 0, -2.0), "serve_at": Vector3(0.6, 1.35, -0.9),
		"customer_spot": Vector3(0.6, 0, 0.45), "queue": [Vector3(2.0, 0, 1.2), Vector3(3.0, 0, 1.6), Vector3(4.0, 0, 2.0), Vector3(5.0, 0, 2.6), Vector3(5.3, 0, 3.5)],
		"door": Vector3(6.4, 0, 6.5), "entry": Vector3(5.8, 0, 4.4),
		"staff_spot": Vector3(2.6, 0, -2.0), "staff_customer": Vector3(2.6, 0, 0.45),
		"seats": [[Vector3(-5.4, 0, 2.2), PI / 2, ""], [Vector3(-3.4, 0, 2.2), -PI / 2, ""], [Vector3(-1.8, 0, 2.9), PI / 2, ""], [Vector3(0.2, 0, 2.9), -PI / 2, ""],
			[Vector3(3.4, 0, 3.6), PI / 2, "terrace"]],
		"pick": {"cappuccino": Vector3(1.8, 0, -2.0), "americano": Vector3(1.8, 0, -2.0), "iced": Vector3(1.8, 0, -2.0), "croissant": Vector3(-1.9, 0, -2.0), "cookie": Vector3(-1.2, 0, -2.0)},
		"slots": {
			"croissant": {"model": "food_croissant", "base": Vector3(-2.3, 1.33, -0.9), "dx": 0.36, "max": 6},
			"cookie": {"model": "food_cookie", "base": Vector3(-1.3, 1.78, -0.9), "pile": true, "max": 10},
			"cappuccino": {"model": "food_cup", "base": Vector3(-0.5, 1.3, -1.25), "dx": 0.28, "max": 4, "machine": true}}
	},
}

static var _scenes := {}

var biz_id := ""
var lay: Dictionary
var bodies := Node3D.new()
var stock_nodes := {}         # product -> Array of shown nodes
var menu_label: Label3D
var cert: Node3D
var upgrade_nodes := {}       # upgrade id -> Array[Node3D]
var seats_taken := {}         # seat index -> true

static func food(model: String) -> Node3D:
	if not _scenes.has(model): _scenes[model] = load("res://assets/interior/%s.glb" % model)
	var n: Node3D = (_scenes[model] as PackedScene).instantiate()
	Town._apply(n, false)
	return n

static func kit(model: String, shadows := true) -> Node3D:
	if not _scenes.has(model): _scenes[model] = load("res://assets/interior/%s.glb" % model)
	var n: Node3D = (_scenes[model] as PackedScene).instantiate()
	Town._apply(n, shadows)
	return n

func build(p_biz: String) -> void:
	biz_id = p_biz; lay = LAYOUTS[p_biz]
	add_child(bodies)
	var room := kit(lay["room"]); add_child(room)
	_floor()
	for f in lay["furniture"]: _place(f, true)
	for uid in lay["upgrades"]:
		upgrade_nodes[uid] = []
		for f in lay["upgrades"][uid]: upgrade_nodes[uid].append(_place(f, true))
	_bounds()
	menu_label = Label3D.new(); menu_label.font = Fonts.get_font(true); menu_label.font_size = 64; menu_label.pixel_size = 0.0042
	menu_label.modulate = Color("fff6ea"); menu_label.outline_size = 0; menu_label.shaded = false
	var board := kit("f_menu", false); board.position = lay["menu"][0]; add_child(board)
	menu_label.position = lay["menu"][0] + Vector3(0, 0, 0.1); menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(menu_label)
	cert = kit("f_certificate", false); cert.position = lay["cert"]; cert.rotation.y = PI / 2; cert.visible = false; add_child(cert)
	var light := OmniLight3D.new(); light.position = Vector3(0, 3.6, 0.5); light.omni_range = 12.0; light.light_color = Color("ffd8a8"); light.light_energy = 0.45
	add_child(light)

func _floor() -> void:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(12.6, 0.3, 8.6); mi.mesh = bm; mi.position = Vector3(0, -0.15, 0)
	var m := ShaderMaterial.new(); m.shader = load("res://assets/shaders/pavement.gdshader")
	m.set_shader_parameter("kind", 1); m.set_shader_parameter("base", lay["floor"]); m.set_shader_parameter("line", lay["floor_line"]); m.set_shader_parameter("tile", lay["floor_tile"])
	m.set_shader_parameter("shadow_lift", 0.6); m.set_shader_parameter("rim_amount", 0.0)
	mi.material_override = m; add_child(mi)
	# the street beyond the open front
	var st := MeshInstance3D.new(); var sm := BoxMesh.new(); sm.size = Vector3(40, 0.2, 20); st.mesh = sm; st.position = Vector3(0, -0.4, 14)
	var m2 := m.duplicate(); m2.set_shader_parameter("base", Color("d9c3a5")); m2.set_shader_parameter("line", Color("b9a68c")); m2.set_shader_parameter("tile", 1.1)
	st.material_override = m2; add_child(st)

func _place(f: Array, solid: bool) -> Node3D:
	var n := kit(f[0]); n.position = f[1]; n.rotation.y = f[2]; add_child(n)
	if solid and f[1].y < 0.5: _solid_from(n)
	return n

func _solid_from(inst: Node3D) -> void:
	var box := AABB(); var first := true
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var wb: AABB = mi.global_transform * mi.mesh.get_aabb() if mi.is_inside_tree() else (inst.transform * mi.transform) * mi.mesh.get_aabb()
			if first: box = wb; first = false
			else: box = box.merge(wb)
	if first or box.size.y < 0.3: return
	_collider(box.get_center(), Vector3(box.size.x, maxf(box.size.y, 1.0), box.size.z))

func _collider(center: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bs := BoxShape3D.new()
	bs.size = size; cs.shape = bs; sb.add_child(cs); sb.position = center; bodies.add_child(sb)

func _bounds() -> void:
	_collider(Vector3(0, 1.5, -4.6), Vector3(13.4, 3, 0.8))
	_collider(Vector3(-6.7, 1.5, 0), Vector3(0.8, 3, 9))
	_collider(Vector3(6.7, 1.5, -1.5), Vector3(0.8, 3, 6))

# ---------------------------------------------------------------- state shown in the room
func show_upgrades(owned: Dictionary) -> void:
	for uid in upgrade_nodes:
		for n in upgrade_nodes[uid]: n.visible = owned.has(uid)

func show_certificate(on: bool) -> void:
	cert.visible = on

func set_menu(lines: Array) -> void:
	menu_label.text = "\n".join(lines)

# Shows the stock: one model per piece up to each slot's maximum.
func show_stock(stock: Dictionary) -> void:
	for pid in lay["slots"]:
		var sl: Dictionary = lay["slots"][pid]
		var n := mini(int(stock.get(pid, 0)), int(sl["max"]))
		var have: Array = stock_nodes.get(pid, [])
		while have.size() > n:
			var x: Node3D = have.pop_back(); x.queue_free()
		while have.size() < n:
			var i := have.size()
			var m := food(sl["model"]); add_child(m); m.position = _slot_pos(sl, i)
			m.rotation.y = (i * 1.7) if not sl.has("rows") else PI / 2
			if sl.get("basket", false) and i == 0:
				var b := food("food_basket"); b.position = sl["base"] + Vector3(0, -0.02, 0); add_child(b); m.set_meta("basket", b)
			have.append(m)
		stock_nodes[pid] = have

func _slot_pos(sl: Dictionary, i: int) -> Vector3:
	if sl.has("rows"):
		var row: int = i / int(sl["per_row"]); var col: int = i % int(sl["per_row"])
		return (sl["rows"][mini(row, sl["rows"].size() - 1)] as Vector3) + Vector3((col - 1) * float(sl["dx"]), 0, 0)
	if sl.get("basket", false):
		var ring := [Vector3(0, 0.12, 0), Vector3(0.18, 0.12, 0.08), Vector3(-0.18, 0.12, -0.06), Vector3(0.05, 0.12, -0.2), Vector3(-0.08, 0.13, 0.2),
			Vector3(0.1, 0.24, 0.05), Vector3(-0.12, 0.24, -0.02), Vector3(0.02, 0.24, 0.16), Vector3(0, 0.34, 0), Vector3(-0.2, 0.2, 0.15)]
		return (sl["base"] as Vector3) + ring[i % ring.size()]
	if sl.get("pile", false):
		return (sl["base"] as Vector3) + Vector3((i % 3 - 1) * 0.16, 0.035 * (i / 3), (i % 2) * 0.06)
	return (sl["base"] as Vector3) + Vector3(i * float(sl.get("dx", 0.4)), 0, 0)

func pick_spot(pid: String) -> Vector3:
	return lay["pick"].get(pid, lay["serve_spot"])

func free_seat(owned_upgrades: Dictionary) -> int:
	var seats: Array = lay["seats"]
	for i in seats.size():
		var need: String = seats[i][2]
		if seats_taken.has(i) or (need != "" and not owned_upgrades.has(need)): continue
		return i
	return -1
