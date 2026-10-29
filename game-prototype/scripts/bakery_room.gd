class_name BakeryRoom
extends Node3D
# The bakery: semi-realistic Poly Haven props (CC0, decimated for phones), laid out as in the performance test.
# Built from code so the layout lives in one place. Solid furniture gets collision boxes from its mesh bounds.
const U := 1.43   # metres -> world units

var root := Node3D.new()
var sun_light: DirectionalLight3D = null
var pickup_cake: Node3D = null    # the cake on the display counter that Noa can take
var table_tea: Node3D = null      # tea set on the customers' table
var scene_cache := {}
var bodies := Node3D.new()        # all collision bodies (layer 1)

func build() -> void:
	add_child(root); add_child(bodies)
	build_env(); build_room(); build_bounds()

# ---------------------------------------------------------------- collision
func add_collider(center: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bs := BoxShape3D.new()
	bs.size = size; cs.shape = bs; sb.add_child(cs); sb.position = center; bodies.add_child(sb)

func add_solid_from_model(inst: Node3D) -> void:
	var box := AABB(); var first := true
	var stack: Array = [inst]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var wb: AABB = mi.global_transform * mi.mesh.get_aabb()
			if first: box = wb; first = false
			else: box = box.merge(wb)
	if first: return
	add_collider(box.get_center(), box.size)

func build_bounds() -> void:
	add_collider(Vector3(0, 1.5, -3.55), Vector3(13.4, 3, 1.1))       # back counters and wall
	add_collider(Vector3(-6.2, 1.5, 0), Vector3(0.6, 3, 9))           # left wall
	add_collider(Vector3(6.2, 1.5, 0), Vector3(0.6, 3, 9))            # right wall
	add_collider(Vector3(0, 1.5, 4.5), Vector3(13.4, 3, 0.6))         # open front (camera side)
	add_collider(Vector3(-1.6, 0.7, -0.4), Vector3(4.3, 1.4, 1.3))    # display island

# ---------------------------------------------------------------- materials
func tex(path: String) -> Texture2D:
	return load(path) as Texture2D

func pbr(id: String, tint: Color, tile: float, nscale: float, rough_mul := 1.0, painted := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var d := "res://assets/tex/%s" % id
	if not painted:
		m.albedo_texture = tex(d + "/diff.jpg")
	m.albedo_color = tint
	m.roughness_texture = tex(d + "/rough.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = rough_mul
	m.normal_enabled = true
	m.normal_texture = tex(d + "/nor.jpg")
	m.normal_scale = nscale
	m.set_meta("tile", tile)
	return m

func flat(c: Color, r := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = r; m.metallic = metal
	return m

# box with world-scale UVs (tile = world size of one texture repeat) and tangents
func make_box(size: Vector3, tile: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size / 2.0
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
		[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP], [Vector3.LEFT, Vector3.BACK, Vector3.UP]]
	for f in faces:
		var n: Vector3 = f[0]; var t: Vector3 = f[1]; var b: Vector3 = f[2]
		var ext_n := absf(n.x) * h.x + absf(n.y) * h.y + absf(n.z) * h.z
		var ext_t := absf(t.x) * h.x + absf(t.y) * h.y + absf(t.z) * h.z
		var ext_b := absf(b.x) * h.x + absf(b.y) * h.y + absf(b.z) * h.z
		var c := n * ext_n
		var pts := [c - t * ext_t - b * ext_b, c + t * ext_t - b * ext_b, c + t * ext_t + b * ext_b, c - t * ext_t + b * ext_b]
		var idx := [0, 1, 2, 0, 2, 3]
		for k in range(0, 6, 3):
			var a: Vector3 = pts[idx[k]]; var bb: Vector3 = pts[idx[k + 1]]; var cc: Vector3 = pts[idx[k + 2]]
			var order := [a, bb, cc]
			if (bb - a).cross(cc - a).dot(n) > 0.0: order = [a, cc, bb]   # Godot front faces are clockwise
			for p in order:
				st.set_normal(n); st.set_uv(Vector2((p as Vector3).dot(t), (p as Vector3).dot(b)) / tile); st.add_vertex(p)
	st.generate_tangents()
	return st.commit()

func add_box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, ry := 0.0) -> MeshInstance3D:
	var tile := 1.0
	if mat.has_meta("tile"): tile = mat.get_meta("tile")
	var mi := MeshInstance3D.new(); mi.mesh = make_box(size, tile); mi.material_override = mat
	mi.position = pos; mi.rotation.y = ry; parent.add_child(mi)
	return mi

func group(parent: Node3D, pos: Vector3, ry := 0.0) -> Node3D:
	var g := Node3D.new(); g.position = pos; g.rotation.y = ry; parent.add_child(g); return g

# ---------------------------------------------------------------- models
func model_path(id: String) -> String:
	return "res://assets/models/%s.glb" % id

func add_model(parent: Node3D, id: String, s: float, pos: Vector3, ry := 0.0, tint := Color.WHITE, solid := false) -> Node3D:
	var path := model_path(id)
	if not scene_cache.has(path): scene_cache[path] = load(path)
	var inst: Node3D = (scene_cache[path] as PackedScene).instantiate()
	inst.scale = Vector3.ONE * s * U; inst.position = pos; inst.rotation.y = ry
	parent.add_child(inst)
	if tint != Color.WHITE: tint_all(inst, tint)
	if solid: add_solid_from_model(inst)
	return inst

# A fresh instance of a prop that is not placed in the room yet (for example a cake Noa carries).
func instance_model(id: String, s: float) -> Node3D:
	var path := model_path(id)
	if not scene_cache.has(path): scene_cache[path] = load(path)
	var inst: Node3D = (scene_cache[path] as PackedScene).instantiate()
	inst.scale = Vector3.ONE * s * U
	return inst

func tint_all(n: Node, tint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.albedo_color = d.albedo_color * tint
				mi.set_surface_override_material(i, d)
	for c in n.get_children(): tint_all(c, tint)


# ---------------------------------------------------------------- scene
func build_env() -> void:
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("9bd27a")
	var sky := Sky.new(); var sm := PanoramaSkyMaterial.new(); sm.panorama = load("res://assets/shared/sky.hdr"); sky.sky_material = sm
	e.sky = sky; e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.ambient_light_energy = 0.3
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES; e.tonemap_exposure = 0.62
	e.glow_enabled = true; e.glow_intensity = 0.15; e.glow_hdr_threshold = 1.1
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_color = Color("ffe2b8"); sun.light_energy = 0.7
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun); sun.look_at_from_position(Vector3(11, 16, 12), Vector3.ZERO)
	sun_light = sun
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(200, 200); g.mesh = pm
	g.material_override = flat(Color("9bd27a"), 1.0); g.position.y = -0.32; add_child(g)

func build_room() -> void:
	var W := root
	var wood_floor := pbr("wood_floor", Color("fff3dc"), 2.6, 0.6)
	var tile_wall := pbr("square_tiled_wall", Color("35b7a6"), 1.6, 0.8)
	var plaster := pbr("plastered_wall_04", Color("f3bf9a"), 3.0, 0.7, 0.9, true)
	var terrazzo := pbr("terrazzo_tiles", Color.WHITE, 4.5, 0.4)
	var cab_teal := pbr("kitchen_wood", Color("2fb3a2"), 2.2, 0.5, 0.5, true)
	var cab_coral := pbr("kitchen_wood", Color("ff7a59"), 2.2, 0.5, 0.5, true)
	var cab_cream := pbr("kitchen_wood", Color("f7e4cc"), 2.2, 0.5, 0.55, true)
	var trim := flat(Color("fff6ea"), 0.55)
	add_box(W, Vector3(12.6, 0.3, 8.6), wood_floor, Vector3(0, -0.15, 0))
	# walls
	for w in [[13.2, 4.2, Vector3(0, 0, -4.25), 0.0], [8.6, 4.2, Vector3(-6.25, 0, 0), PI / 2], [8.6, 1.65, Vector3(6.25, 0, 0), PI / 2]]:
		var ln: float = w[0]; var h: float = w[1]; var g := group(W, w[2], w[3]); var th := 1.65
		add_box(g, Vector3(ln, th, 0.5), tile_wall, Vector3(0, th / 2, 0))
		if h > th: add_box(g, Vector3(ln, h - th, 0.5), plaster, Vector3(0, th + (h - th) / 2, 0))
		add_box(g, Vector3(ln, 0.12, 0.6), trim, Vector3(0, th, 0.02)); add_box(g, Vector3(ln, 0.28, 0.58), trim, Vector3(0, 0.14, 0.02))
		if h > th: add_box(g, Vector3(ln, 0.22, 0.62), trim, Vector3(0, h - 0.11, 0.02))
	# window (left wall)
	var wg := group(W, Vector3(-5.97, 2.5, 1.3))
	var sky_m := StandardMaterial3D.new(); sky_m.albedo_color = Color("cfeaff"); sky_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sk := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2(2.2, 1.7); sk.mesh = qm; sk.material_override = sky_m
	sk.rotation.y = PI / 2; sk.position.x = -0.04; wg.add_child(sk)
	var fm := flat(Color("fff6ea"), 0.5)
	for y in [0.9, -0.9]: add_box(wg, Vector3(0.12, 0.14, 2.5), fm, Vector3(0, y, 0))
	for z in [-1.2, 0.0, 1.2]: add_box(wg, Vector3(0.12, 1.9, 0.1), fm, Vector3(0, 0, z))
	add_box(wg, Vector3(0.12, 0.1, 2.4), fm, Vector3.ZERO); add_box(wg, Vector3(0.3, 0.1, 2.7), fm, Vector3(0.1, -0.98, 0))
	# kitchen run
	var cab_y := 1.28
	var knob_m := flat(Color("f0b44c"), 0.25, 0.85); var seam_m := flat(Color("8a4a30"), 0.6)
	for c in [[-4.9, 2.4, cab_teal], [-2.5, 2.4, cab_teal], [2.55, 2.0, cab_coral], [-0.65, 1.3, cab_teal], [1.18, 0.86, cab_teal]]:
		var x: float = c[0]; var w: float = c[1]; var mat: Material = c[2]; var z := -3.5; var d := 1.0
		add_box(W, Vector3(w, cab_y, d), mat, Vector3(x, cab_y / 2, z)); add_box(W, Vector3(w + 0.06, 0.07, d + 0.08), terrazzo, Vector3(x, cab_y + 0.035, z + 0.02))
		var nd := maxi(1, roundi(w / 1.0))
		for i in nd:
			var cx := x - w / 2 + (i + 0.5) * w / nd
			add_box(W, Vector3(0.03, cab_y * 0.8, 0.03), seam_m, Vector3(cx - w / nd / 2 + 0.01, cab_y / 2, z + d / 2 + 0.01))
			var kn := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.05; sm.height = 0.1; sm.radial_segments = 12; sm.rings = 6
			kn.mesh = sm; kn.material_override = knob_m; kn.position = Vector3(cx + 0.18, cab_y * 0.78, z + d / 2 + 0.05); W.add_child(kn)
	add_model(W, "electric_stove", 1.1, Vector3(0.35, 0, -3.45), 0.0, Color.WHITE, false)
	var steel := flat(Color("cfd3d8"), 0.28, 0.9)
	var cone := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.3; cm.bottom_radius = 0.95; cm.height = 0.8; cm.radial_segments = 4; cm.rings = 1
	cm.cap_top = false; cm.cap_bottom = false; cone.mesh = cm; cone.material_override = steel; steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.rotation.y = PI / 4; cone.scale = Vector3(1, 1, 0.8); cone.position = Vector3(0.35, 3.55, -3.7); W.add_child(cone)
	add_box(W, Vector3(0.4, 1.0, 0.4), steel, Vector3(0.35, 4.2, -3.8))
	add_box(W, Vector3(2.4, 1.3, 0.6), cab_cream, Vector3(-3.7, 3.25, -3.7))
	add_box(W, Vector3(2.0, 0.1, 0.55), cab_teal, Vector3(3.0, 3.1, -3.72)); add_box(W, Vector3(2.0, 0.1, 0.55), cab_teal, Vector3(3.0, 2.4, -3.72))
	# props on counters
	var top := cab_y + 0.07
	add_model(W, "vintage_electric_kettle", 1.0, Vector3(1.45, top, -3.45), 2.5)
	add_model(W, "brass_pot_01", 1.0, Vector3(0.2, 1.37, -3.4))
	add_model(W, "pot_enamel_01", 1.3, Vector3(-4.2, top, -3.5), 0.6)
	add_model(W, "wooden_cutting_board", 1.4, Vector3(-3.3, top, -3.4), 0.15)
	add_model(W, "croissant", 1.6, Vector3(-3.45, top + 0.06, -3.38), 0.5); add_model(W, "croissant", 1.6, Vector3(-3.1, top + 0.06, -3.42), 2.2)
	add_model(W, "wooden_bowl_01", 1.3, Vector3(-2.2, top, -3.45))
	add_model(W, "lemon", 1.6, Vector3(-2.2, top + 0.14, -3.45)); add_model(W, "lemon", 1.6, Vector3(-2.12, top + 0.1, -3.5), 1.0)
	add_model(W, "ceramic_vase_01", 1.2, Vector3(-5.7, top, -3.7)); add_model(W, "metal_jug", 1.3, Vector3(2.2, top, -3.7))
	add_model(W, "tea_set_01", 1.2, Vector3(3.1, top, -3.45), 0.1)
	add_model(W, "wicker_basket_01", 1.4, Vector3(3.0, 2.5, -3.7)); add_model(W, "croissant", 1.7, Vector3(3.0, 2.62, -3.7))
	add_model(W, "carrot_cake", 1.5, Vector3(3.5, 3.2, -3.72))
	add_model(W, "vintage_cabinet_01", 0.85, Vector3(5.0, 0, -3.65), 0.0, Color.WHITE, true)
	# display island
	var ig := group(W, Vector3(-1.6, 0, -0.4))
	add_box(ig, Vector3(4.2, 1.22, 1.2), cab_cream, Vector3(0, 0.61, 0)); add_box(ig, Vector3(4.3, 0.08, 1.3), terrazzo, Vector3(0, 1.26, 0))
	add_box(ig, Vector3(4.3, 0.1, 1.4), flat(Color("ff7a59"), 0.5), Vector3(0, 0.05, 0))
	var glass := StandardMaterial3D.new(); glass.albedo_color = Color(0.81, 0.91, 0.96, 0.07); glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.roughness = 0.04
	var gb := MeshInstance3D.new(); var gm := BoxMesh.new(); gm.size = Vector3(2.0, 0.86, 1.05); gb.mesh = gm; gb.material_override = glass; gb.position = Vector3(-1.05, 1.74, 0); ig.add_child(gb)
	var post_m := flat(Color("fff6ea"), 0.4)
	for sx in [-2.07, -0.03]:
		for sz in [-0.52, 0.52]: add_box(ig, Vector3(0.04, 0.9, 0.04), post_m, Vector3(sx, 1.74, sz))
	pickup_cake = add_model(ig, "strawberry_chocolate_cake", 1.5, Vector3(-1.6, 1.31, 0)); add_model(ig, "carrot_cake", 1.5, Vector3(-0.6, 1.31, 0))
	add_model(ig, "croissant", 1.7, Vector3(-1.1, 1.52, 0.18)); add_model(ig, "wooden_cutting_board", 1.25, Vector3(-1.1, 1.46, 0))
	add_model(ig, "wicker_basket_01", 1.5, Vector3(1.7, 1.3, 0.15)); add_model(ig, "croissant", 1.7, Vector3(1.7, 1.42, 0.15), 1.0); add_model(ig, "croissant", 1.7, Vector3(1.95, 1.4, 0), 3.0)
	add_model(W, "carrot_cake", 2.0, Vector3(-0.45, 1.3, -0.2))
	# seating
	add_model(W, "round_wooden_table_01", 0.8, Vector3(3.6, 0, 1.6), 0.0, Color("ffe2c8"), true)
	add_model(W, "painted_wooden_chair_01", 1.15, Vector3(3.6, 0, 2.85), PI, Color("53d6c5"), true); add_model(W, "painted_wooden_chair_01", 1.15, Vector3(4.95, 0, 1.6), -PI / 2, Color("ffb36b"), true)
	table_tea = add_model(W, "tea_set_01", 0.8, Vector3(3.6, 1.16, 1.6), 0.3)
	add_model(W, "standing_chalkboard_01", 1.1, Vector3(5.4, 0, 3.2), -2.5, Color.WHITE, true); add_model(W, "potted_plant_02", 1.35, Vector3(-5.2, 0, 3.2), 1.2, Color.WHITE, true)
	add_model(W, "planter_box_01", 1.3, Vector3(-5.2, 0, -0.8), PI / 2, Color.WHITE, true)
	add_model(W, "fancy_picture_frame_01", 1.5, Vector3(0, 3.1, -3.97)); add_model(W, "fancy_picture_frame_01", 1.3, Vector3(-5.97, 3.4, -1.6), PI / 2)
	add_model(W, "wooden_display_shelves_01", 1.35, Vector3(-5.6, 0, 1.9), PI / 2, Color.WHITE, true)
	var rug_m := StandardMaterial3D.new(); rug_m.albedo_texture = load("res://assets/shared/rug.png"); rug_m.roughness = 1.0
	var rg := MeshInstance3D.new(); var rb := BoxMesh.new(); rb.size = Vector3(3.2, 0.04, 2.0); rg.mesh = rb; rg.material_override = rug_m; rg.position = Vector3(1.6, 0.02, 2.3); W.add_child(rg)
	# pendants
	for p in [[-2.6, -0.4, 3.6, "ffc24d"], [-0.2, -0.4, 3.6, "ffc24d"], [3.6, 1.6, 3.5, "35b7a6"]]:
		var g := group(W, Vector3(p[0], 0, p[1])); var y: float = p[2]
		var cord := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 0.012; cy.bottom_radius = 0.012; cy.height = 4.2 - y; cy.radial_segments = 6; cord.mesh = cy
		cord.material_override = flat(Color("222222")); cord.position.y = (4.2 + y) / 2; g.add_child(cord)
		var sh := MeshInstance3D.new(); var sp := SphereMesh.new(); sp.radius = 0.42; sp.height = 0.42; sp.is_hemisphere = true; sp.radial_segments = 28; sp.rings = 8; sh.mesh = sp
		var shm := flat(Color(p[3]), 0.35, 0.3); shm.cull_mode = BaseMaterial3D.CULL_DISABLED; sh.material_override = shm; sh.position.y = y; g.add_child(sh)
		var bulb := MeshInstance3D.new(); var bs := SphereMesh.new(); bs.radius = 0.14; bs.height = 0.28; bs.radial_segments = 16; bs.rings = 8; bulb.mesh = bs
		var bm := StandardMaterial3D.new(); bm.albedo_color = Color("fff2c9"); bm.emission_enabled = true; bm.emission = Color("ffd889"); bm.emission_energy_multiplier = 3.0
		bulb.material_override = bm; bulb.position.y = y - 0.1; g.add_child(bulb)
		var ol := OmniLight3D.new(); ol.light_color = Color("ffc98a"); ol.light_energy = 0.3; ol.omni_range = 11.0; ol.position.y = y - 0.3; ol.add_to_group("pendant_lights"); g.add_child(ol)

