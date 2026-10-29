extends Node3D
# Performance test scene: the semi-realistic bakery, built from code (same layout as the three.js still).
# Usage: godot --path . --rendering-driver opengl3 -- set=orig|opt mode=shot|bench|chars|anim chars=N out=/path
const U := 1.43   # metres -> world units

var set_name := "opt"
var mode := "shot"
var n_chars := 0
var out_dir := "/tmp"
var base := "res://assets_opt"
var root := Node3D.new()
var scene_cache := {}
var stats := {}
var noa: Node3D = null
var cam: Camera3D
var opt_size := Vector2i(0, 0)
var opt_shadow := true
var opt_lights := true
var opt_merge := false
var tag := ""
var opt_cam := "wide"
var static_pose := true
var fix_mats := true
var opt_anim := "talk"
var anim_lib: AnimationLibrary = null
var src_cache := {}
var box_nodes: Array = []

# ---------------------------------------------------------------- args
func parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2: continue
		match kv[0]:
			"set": set_name = kv[1]
			"mode": mode = kv[1]
			"chars": n_chars = int(kv[1])
			"out": out_dir = kv[1]
			"size": opt_size = Vector2i(int(kv[1].split("x")[0]), int(kv[1].split("x")[1]))
			"shadow": opt_shadow = kv[1] == "1"
			"lights": opt_lights = kv[1] == "1"
			"merge": opt_merge = kv[1] == "1"
			"tag": tag = kv[1]
			"cam": opt_cam = kv[1]
			"fixmat": fix_mats = kv[1] == "1"
			"anim": opt_anim = kv[1]
	base = "res://assets_%s" % set_name

# ---------------------------------------------------------------- materials
func tex(path: String) -> Texture2D:
	return load(path) as Texture2D

func pbr(id: String, tint: Color, tile: float, nscale: float, rough_mul := 1.0, painted := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var d := "%s/tex/%s" % [base, id]
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
	box_nodes.append(mi)
	return mi

func group(parent: Node3D, pos: Vector3, ry := 0.0) -> Node3D:
	var g := Node3D.new(); g.position = pos; g.rotation.y = ry; parent.add_child(g); return g

# ---------------------------------------------------------------- models
func model_path(id: String) -> String:
	if set_name == "orig": return "res://assets_orig/models/%s/%s.gltf" % [id, id]
	return "res://assets_opt/models/%s.glb" % id

func add_model(parent: Node3D, id: String, s: float, pos: Vector3, ry := 0.0, tint := Color.WHITE) -> Node3D:
	var path := model_path(id)
	if not scene_cache.has(path): scene_cache[path] = load(path)
	var inst: Node3D = (scene_cache[path] as PackedScene).instantiate()
	inst.scale = Vector3.ONE * s * U; inst.position = pos; inst.rotation.y = ry
	parent.add_child(inst)
	if tint != Color.WHITE: tint_all(inst, tint)
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
	var sky := Sky.new(); var sm := PanoramaSkyMaterial.new(); sm.panorama = load("res://shared/sky.hdr"); sky.sky_material = sm
	e.sky = sky; e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.ambient_light_energy = 0.3
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES; e.tonemap_exposure = 0.62
	e.glow_enabled = true; e.glow_intensity = 0.15; e.glow_hdr_threshold = 1.1
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_color = Color("ffe2b8"); sun.light_energy = 0.7
	sun.shadow_enabled = opt_shadow; sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun); sun.look_at_from_position(Vector3(11, 16, 12), Vector3.ZERO)
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
	add_model(W, "electric_stove", 1.1, Vector3(0.35, 0, -3.45))
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
	add_model(W, "vintage_cabinet_01", 0.85, Vector3(5.0, 0, -3.65))
	# display island
	var ig := group(W, Vector3(-1.6, 0, -0.4))
	add_box(ig, Vector3(4.2, 1.22, 1.2), cab_cream, Vector3(0, 0.61, 0)); add_box(ig, Vector3(4.3, 0.08, 1.3), terrazzo, Vector3(0, 1.26, 0))
	add_box(ig, Vector3(4.3, 0.1, 1.4), flat(Color("ff7a59"), 0.5), Vector3(0, 0.05, 0))
	var glass := StandardMaterial3D.new(); glass.albedo_color = Color(0.81, 0.91, 0.96, 0.07); glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.roughness = 0.04
	var gb := MeshInstance3D.new(); var gm := BoxMesh.new(); gm.size = Vector3(2.0, 0.86, 1.05); gb.mesh = gm; gb.material_override = glass; gb.position = Vector3(-1.05, 1.74, 0); ig.add_child(gb)
	var post_m := flat(Color("fff6ea"), 0.4)
	for sx in [-2.07, -0.03]:
		for sz in [-0.52, 0.52]: add_box(ig, Vector3(0.04, 0.9, 0.04), post_m, Vector3(sx, 1.74, sz))
	add_model(ig, "strawberry_chocolate_cake", 1.5, Vector3(-1.6, 1.31, 0)); add_model(ig, "carrot_cake", 1.5, Vector3(-0.6, 1.31, 0))
	add_model(ig, "croissant", 1.7, Vector3(-1.1, 1.52, 0.18)); add_model(ig, "wooden_cutting_board", 1.25, Vector3(-1.1, 1.46, 0))
	add_model(ig, "wicker_basket_01", 1.5, Vector3(1.7, 1.3, 0.15)); add_model(ig, "croissant", 1.7, Vector3(1.7, 1.42, 0.15), 1.0); add_model(ig, "croissant", 1.7, Vector3(1.95, 1.4, 0), 3.0)
	add_model(W, "carrot_cake", 2.0, Vector3(-0.45, 1.3, -0.2))
	# seating
	add_model(W, "round_wooden_table_01", 0.8, Vector3(3.6, 0, 1.6), 0.0, Color("ffe2c8"))
	add_model(W, "painted_wooden_chair_01", 1.15, Vector3(3.6, 0, 2.85), PI, Color("53d6c5")); add_model(W, "painted_wooden_chair_01", 1.15, Vector3(4.95, 0, 1.6), -PI / 2, Color("ffb36b"))
	add_model(W, "tea_set_01", 0.8, Vector3(3.6, 1.16, 1.6), 0.3)
	add_model(W, "standing_chalkboard_01", 1.1, Vector3(5.4, 0, 3.2), -2.5); add_model(W, "potted_plant_02", 1.35, Vector3(-5.2, 0, 3.2), 1.2)
	add_model(W, "planter_box_01", 1.3, Vector3(-5.2, 0, -0.8), PI / 2)
	add_model(W, "fancy_picture_frame_01", 1.5, Vector3(0, 3.1, -3.97)); add_model(W, "fancy_picture_frame_01", 1.3, Vector3(-5.97, 3.4, -1.6), PI / 2)
	add_model(W, "wooden_display_shelves_01", 1.35, Vector3(-5.6, 0, 1.9), PI / 2)
	var rug_m := StandardMaterial3D.new(); rug_m.albedo_texture = load("res://shared/rug.png"); rug_m.roughness = 1.0
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
		if not opt_lights: continue
		var ol := OmniLight3D.new(); ol.light_color = Color("ffc98a"); ol.light_energy = 0.3; ol.omni_range = 11.0; ol.position.y = y - 0.3; g.add_child(ol)

func merge_boxes() -> void:
	var groups := {}
	for n in box_nodes:
		var mi := n as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or mi.mesh == null: continue
		var key := mi.material_override.get_rid()
		if not groups.has(key): groups[key] = {"mat": mi.material_override, "st": SurfaceTool.new(), "n": 0}
		var g: Dictionary = groups[key]
		if g["n"] == 0: (g["st"] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
		(g["st"] as SurfaceTool).append_from(mi.mesh, 0, root.global_transform.affine_inverse() * mi.global_transform)
		g["n"] += 1
		mi.get_parent().remove_child(mi); mi.queue_free()
	for k in groups:
		var g: Dictionary = groups[k]
		var out := MeshInstance3D.new(); out.mesh = (g["st"] as SurfaceTool).commit(); out.material_override = g["mat"]; root.add_child(out)
	stats["merged_groups"] = groups.size()

# ---------------------------------------------------------------- characters
func char_path(variant: String) -> String:
	if set_name == "orig": return "res://assets_orig/char/noa.glb"
	return "res://assets_opt/char/char_%s.glb" % variant

func fix_char_materials(n: Node) -> void:
	# the exported glTF marks every material as alpha-blended; hair, brows and lashes need alpha-scissor, everything else opaque
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				var nm := (m.resource_name + " " + mi.name).to_lower()
				if nm.contains("hair") or nm.contains("ponytail") or nm.contains("eyebrow") or nm.contains("eyelash") or nm.contains("high-poly"):
					d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; d.alpha_scissor_threshold = 0.5; d.cull_mode = BaseMaterial3D.CULL_DISABLED
				else:
					d.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				mi.set_surface_override_material(i, d)
	for c in n.get_children(): fix_char_materials(c)

func find_nodes(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls): out.append(n)
	for c in n.get_children(): find_nodes(c, cls, out)

func aim_bone(sk: Skeleton3D, bone: String, child: String, dir: Vector3) -> void:
	var ib := sk.find_bone(bone); var ic := sk.find_bone(child)
	if ib < 0 or ic < 0: return
	var gb := sk.get_bone_global_pose(ib); var gc := sk.get_bone_global_pose(ic)
	var cur := (gc.origin - gb.origin).normalized()
	var q := Quaternion(cur, dir.normalized())
	var nb := Basis(q) * gb.basis
	var par := sk.get_bone_parent(ib)
	var pb := sk.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(ib, (pb.inverse() * nb).get_rotation_quaternion())

func spawn_char(variant: String, pos: Vector3, ry: float, scale_f := 1.6, smile := true) -> Node3D:
	var path := char_path(variant)
	if not scene_cache.has(path): scene_cache[path] = load(path)
	var c: Node3D = (scene_cache[path] as PackedScene).instantiate()
	c.scale = Vector3.ONE * scale_f; c.position = pos; c.rotation.y = ry
	add_child(c)
	if fix_mats and set_name == "orig": fix_char_materials(c)
	var sks := []; find_nodes(c, "Skeleton3D", sks)
	if sks.size() > 0 and static_pose:
		var sk: Skeleton3D = sks[0]
		aim_bone(sk, "upperarm_l", "lowerarm_l", Vector3(0.2, -1.0, 0.12)); aim_bone(sk, "upperarm_r", "lowerarm_r", Vector3(-0.2, -1.0, 0.12))
		aim_bone(sk, "lowerarm_l", "hand_l", Vector3(-0.3, -0.45, 0.85)); aim_bone(sk, "lowerarm_r", "hand_r", Vector3(0.3, -0.45, 0.85))
	if smile:
		var mis := []; find_nodes(c, "MeshInstance3D", mis)
		for mi in mis:
			var m: MeshInstance3D = mi
			if m.mesh == null or m.mesh.get_blend_shape_count() == 0: continue
			for kv in {"!ex-mouthSmileLeft": 0.55, "!ex-mouthSmileRight": 0.55, "!ex-cheekSquintLeft": 0.3, "!ex-cheekSquintRight": 0.3, "!ex-eyeSquintLeft": 0.12, "!ex-eyeSquintRight": 0.12, "!ex-browInnerUp": 0.15}.keys():
				var idx := m.find_blend_shape_by_name(kv)
				if idx >= 0: m.set_blend_shape_value(idx, {"!ex-mouthSmileLeft": 0.55, "!ex-mouthSmileRight": 0.55, "!ex-cheekSquintLeft": 0.3, "!ex-cheekSquintRight": 0.3, "!ex-eyeSquintLeft": 0.12, "!ex-eyeSquintRight": 0.12, "!ex-browInnerUp": 0.15}[kv])
	return c


# ---------------------------------------------------------------- animation retargeting (runtime bake)
const CHAIN := {"spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head", "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "thigh_l": "calf_l", "calf_l": "foot_l", "thigh_r": "calf_r", "calf_r": "foot_r"}
const FLAT := ["foot_l", "foot_r", "ball_l", "ball_r"]
const DELTA := ["pelvis", "head"]

func map_name(src_name: String, lib: String) -> String:
	if lib == "ual2":
		if src_name == "root": return "Root"
		if src_name == "Head": return "head"
		if src_name.contains("leaf"): return ""
		return src_name
	# ual1: Rigify-style DEF- names
	if not src_name.begins_with("DEF-"):
		return "Root" if src_name == "root" else ""
	var n := src_name.substr(4); var side := ""
	if n.ends_with(".L"): side = "_l"; n = n.substr(0, n.length() - 2)
	elif n.ends_with(".R"): side = "_r"; n = n.substr(0, n.length() - 2)
	var base := {"hips": "pelvis", "spine.001": "spine_01", "spine.002": "spine_02", "spine.003": "spine_03", "neck": "neck_01", "head": "head", "shoulder": "clavicle", "upper_arm": "upperarm", "forearm": "lowerarm",
		"hand": "hand", "thigh": "thigh", "shin": "calf", "foot": "foot", "toe": "ball"}
	if base.has(n): return str(base[n]) + side
	var m := RegEx.new(); m.compile("^(f_)?(index|middle|pinky|ring|thumb)\\.0(\\d)$")
	var r := m.search(n)
	if r: return "%s_0%s%s" % [r.get_string(2), r.get_string(3), side]
	return ""

func load_source(key: String) -> Dictionary:
	if src_cache.has(key): return src_cache[key]
	var src: Node3D = (load("res://shared/%s.glb" % key) as PackedScene).instantiate(); src.visible = false; add_child(src)
	var sks := []; find_nodes(src, "Skeleton3D", sks); var aps := []; find_nodes(src, "AnimationPlayer", aps)
	var ap: AnimationPlayer = aps[0]; ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	src_cache[key] = {"skel": sks[0], "ap": ap, "key": key}
	return src_cache[key]

func bake(srcd: Dictionary, anim_name: String, ch: Node3D, tgt: Skeleton3D, talk := false) -> Animation:
	var src: Skeleton3D = srcd["skel"]; var ap: AnimationPlayer = srcd["ap"]; var lib: String = srcd["key"]
	var a := ap.get_animation(anim_name)
	var t2s := {}; var s2t := {}
	for i in src.get_bone_count():
		var tn := map_name(src.get_bone_name(i), lib)
		if tn != "":
			var ti := tgt.find_bone(tn)
			if ti >= 0: t2s[ti] = i; s2t[i] = ti
	var order: Array = []
	var visit := func(b: int, f: Callable) -> void:
		if order.has(b): return
		var p := tgt.get_bone_parent(b)
		if p >= 0: f.call(p, f)
		order.append(b)
	for b in tgt.get_bone_count(): visit.call(b, visit)
	var out := Animation.new(); out.length = a.length; out.loop_mode = a.loop_mode
	var skel_path := str(ch.get_path_to(tgt)); var tracks := {}
	for b in order:
		if tgt.get_bone_name(b) == "Root": continue
		var tr := out.add_track(Animation.TYPE_ROTATION_3D); out.track_set_path(tr, NodePath("%s:%s" % [skel_path, tgt.get_bone_name(b)])); tracks[b] = tr
	var pelv := tgt.find_bone("pelvis"); var pos_tr := out.add_track(Animation.TYPE_POSITION_3D); out.track_set_path(pos_tr, NodePath("%s:pelvis" % skel_path))
	var rest_s: Array = []; for i in src.get_bone_count(): rest_s.append(src.get_bone_global_rest(i))
	var rest_t: Array = []; for i in tgt.get_bone_count(): rest_t.append(tgt.get_bone_global_rest(i))
	var sp := src.find_bone("DEF-hips") if lib == "ual1" else src.find_bone("pelvis")
	var scale_h := 1.0
	if sp >= 0 and pelv >= 0 and (rest_s[sp] as Transform3D).origin.y > 0.01: scale_h = (rest_t[pelv] as Transform3D).origin.y / (rest_s[sp] as Transform3D).origin.y
	ap.play(anim_name); var step := 1.0 / 20.0; var t := 0.0
	while t <= a.length + 0.0001:
		ap.seek(minf(t, a.length), true); ap.advance(0.0); src.force_update_all_bone_transforms()
		var Gt := {}
		for b in order:
			var name := tgt.get_bone_name(b); var par := tgt.get_bone_parent(b)
			var Gp: Basis = Gt[par] if (par >= 0 and Gt.has(par)) else Basis.IDENTITY
			var Gb: Basis
			var rt: Transform3D = rest_t[b]
			if name == "Root": Gb = rt.basis
			elif DELTA.has(name) and t2s.has(b):
				var si: int = t2s[b]; Gb = (src.get_bone_global_pose(si).basis * (rest_s[si] as Transform3D).basis.inverse()) * rt.basis
			elif CHAIN.has(name) and t2s.has(b) and tgt.find_bone(CHAIN[name]) >= 0 and t2s.has(tgt.find_bone(CHAIN[name])):
				var c := tgt.find_bone(CHAIN[name]); var si: int = t2s[b]; var sc: int = t2s[c]
				var d_src := (src.get_bone_global_pose(sc).origin - src.get_bone_global_pose(si).origin).normalized()
				var d_rest := ((rest_t[c] as Transform3D).origin - rt.origin).normalized()
				Gb = Basis(Quaternion(d_rest, d_src)) * rt.basis
			elif FLAT.has(name): Gb = rt.basis
			else:
				var rp: Basis = (rest_t[par] as Transform3D).basis if par >= 0 else Basis.IDENTITY
				Gb = Gp * (rp.inverse() * rt.basis)
			Gt[b] = Gb
			if tracks.has(b): out.rotation_track_insert_key(tracks[b], t, (Gp.inverse() * Gb).get_rotation_quaternion().normalized())
		if pelv >= 0 and t2s.has(pelv):
			var si: int = t2s[pelv]; var dpos := (src.get_bone_global_pose(si).origin - (rest_s[si] as Transform3D).origin) * scale_h
			out.position_track_insert_key(pos_tr, t, tgt.get_bone_rest(pelv).origin + dpos)
		t += step
	ap.stop()
	if talk:
		var mis := []; find_nodes(ch, "MeshInstance3D", mis)
		for mi in mis:
			var m: MeshInstance3D = mi
			if m.mesh and m.find_blend_shape_by_name("!ex-jawOpen") >= 0:
				var bt := out.add_track(Animation.TYPE_BLEND_SHAPE); out.track_set_path(bt, NodePath("%s:!ex-jawOpen" % str(ch.get_path_to(m))))
				var k := 0.0
				while k <= out.length: out.blend_shape_track_insert_key(bt, k, 0.45 if int(k / 0.25) % 2 == 0 else 0.05); k += 0.25
	return out

func ensure_lib(ch: Node3D) -> AnimationLibrary:
	if anim_lib != null: return anim_lib
	var sks := []; find_nodes(ch, "Skeleton3D", sks); var tgt: Skeleton3D = sks[0]
	var l1 := load_source("ual1"); var l2 := load_source("ual2")
	anim_lib = AnimationLibrary.new()
	var t0 := Time.get_ticks_msec()
	anim_lib.add_animation("talk", bake(l1, "Idle_Talking", ch, tgt, true))
	anim_lib.add_animation("walk", bake(l1, "Walk_Formal", ch, tgt))
	anim_lib.add_animation("interact", bake(l1, "Interact", ch, tgt))
	anim_lib.add_animation("sit", bake(l1, "Sitting_Talking", ch, tgt))
	anim_lib.add_animation("yes", bake(l2, "Yes", ch, tgt))
	anim_lib.add_animation("fold", bake(l2, "Idle_FoldArms", ch, tgt))
	stats["bake_ms"] = Time.get_ticks_msec() - t0
	var tot_keys := 0
	for n in anim_lib.get_animation_list():
		var an := anim_lib.get_animation(n)
		for i in an.get_track_count(): tot_keys += an.track_get_key_count(i)
	stats["anim_count"] = anim_lib.get_animation_list().size(); stats["anim_keys_total"] = tot_keys
	return anim_lib

func attach_anim(ch: Node3D, name: String, offset: float) -> AnimationPlayer:
	var ap := AnimationPlayer.new(); ch.add_child(ap)
	ap.add_animation_library("", ensure_lib(ch)); ap.root_node = NodePath("..")
	ap.play(name); ap.seek(offset, true)
	return ap

# ---------------------------------------------------------------- measurement
func collect_stats() -> Dictionary:
	var tris := 0; var meshes := 0; var unique_mesh := {}; var tex_seen := {}
	var stack: Array = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			var mi := n as MeshInstance3D
			if mi.mesh == null: continue
			meshes += 1
			var rid := mi.mesh.get_rid()
			if not unique_mesh.has(rid):
				var cnt := 0
				for s in mi.mesh.get_surface_count():
					var arr := mi.mesh.surface_get_arrays(s)
					var ind = arr[Mesh.ARRAY_INDEX]
					if ind != null and (ind as PackedInt32Array).size() > 0: cnt += (ind as PackedInt32Array).size() / 3
					else: cnt += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				unique_mesh[rid] = cnt
			tris += unique_mesh[rid]
			var mats: Array = []
			if mi.material_override: mats.append(mi.material_override)
			for s in mi.mesh.get_surface_count():
				var sm := mi.get_surface_override_material(s)
				if sm == null: sm = mi.mesh.surface_get_material(s)
				if sm: mats.append(sm)
			for m in mats:
				if m is BaseMaterial3D:
					for p in BaseMaterial3D.TEXTURE_MAX:
						var t := (m as BaseMaterial3D).get_texture(p)
						if t: tex_seen[t.get_rid()] = t
	var tex_info := []; var rgba := 0.0; var astc := 0.0; var max_dim := 0
	for t in tex_seen.values():
		var w: int = t.get_width(); var h: int = t.get_height(); max_dim = maxi(max_dim, maxi(w, h))
		rgba += w * h * 4.0 * 4.0 / 3.0; astc += w * h * 1.0 * 4.0 / 3.0
		tex_info.append([w, h])
	return {"mesh_instances": meshes, "unique_meshes": unique_mesh.size(), "static_tris": tris, "unique_textures": tex_seen.size(), "tex_max_dim": max_dim,
		"tex_mb_rgba8_mips": snappedf(rgba / 1048576.0, 0.1), "tex_mb_astc4x4_mips": snappedf(astc / 1048576.0, 0.1)}

func rinfo() -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	return {
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives_all_passes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"tex_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)}

func bench(frames: int) -> Dictionary:
	for i in 8: await RenderingServer.frame_post_draw
	var ts: Array = []
	for i in frames:
		var t0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		ts.append((Time.get_ticks_usec() - t0) / 1000.0)
	ts.sort()
	var sum := 0.0
	for v in ts: sum += v
	return {"frames": frames, "avg_ms": snappedf(sum / frames, 0.1), "median_ms": snappedf(ts[frames / 2], 0.1), "p95_ms": snappedf(ts[int(frames * 0.95)], 0.1)}

func save_json(name: String, d: Dictionary) -> void:
	var f := FileAccess.open("%s/%s.json" % [out_dir, name], FileAccess.WRITE); f.store_string(JSON.stringify(d, "  ")); f.close()

# ---------------------------------------------------------------- main
func _ready() -> void:
	parse_args()
	add_child(root)
	var t0 := Time.get_ticks_msec()
	if opt_size != Vector2i.ZERO: get_window().size = opt_size
	build_env(); build_room()
	if opt_merge: merge_boxes()
	static_pose = (mode != "anim")
	noa = spawn_char("hero", Vector3(-0.4, 0.02, -1.75), 0.45)
	if mode == "chars" or mode == "anim":
		var spots := [Vector3(1.2, 0.02, 4.6), Vector3(-3.2, 0.02, 4.4), Vector3(2.6, 0.02, 0.2), Vector3(-4.4, 0.02, 1.0), Vector3(0.4, 0.02, 3.4), Vector3(5.0, 0.02, -1.4), Vector3(-2.0, 0.02, 2.4), Vector3(-5.0, 0.02, 5.2)]
		var names := ["talk", "walk", "interact", "yes", "fold", "sit"]
		for i in n_chars:
			var c := spawn_char("npc", spots[i % spots.size()] + Vector3(0.45 * (i / spots.size()), 0, 0.3 * (i / spots.size())), randf_range(0, TAU), 1.6, false)
			if mode == "anim": attach_anim(c, names[(i + 1) % names.size()], randf() * 2.0)
		if mode == "anim": attach_anim(noa, opt_anim, 0.6)
	cam = Camera3D.new(); cam.near = 0.05; cam.far = 200.0; add_child(cam)
	if opt_cam == "body":
		cam.fov = 30.0; cam.look_at_from_position(Vector3(1.4, 2.6, 5.2), Vector3(-0.4, 1.3, -1.75))
	elif opt_cam == "close":
		cam.fov = 22.0; cam.look_at_from_position(Vector3(1.6, 3.1, 3.4), Vector3(-0.45, 1.85, -1.75))
	else:
		cam.fov = 34.0; cam.look_at_from_position(Vector3(7.5, 12.5, 15.5), Vector3(-0.6, 0.6, 0.2))
	cam.current = true
	stats["build_ms"] = Time.get_ticks_msec() - t0
	for i in 6: await RenderingServer.frame_post_draw
	stats["scene"] = collect_stats(); stats["render"] = rinfo(); stats["set"] = set_name; stats["window"] = [get_window().size.x, get_window().size.y]; stats["mode"] = mode; stats["chars"] = n_chars
	stats["gpu"] = RenderingServer.get_video_adapter_name(); stats["renderer"] = RenderingServer.get_current_rendering_method()
	if mode == "anim" and n_chars == 0:
		attach_anim(noa, opt_anim, 0.6)
		for i in 4: await RenderingServer.frame_post_draw
	if mode == "shot" or mode == "bench" or mode == "anim":
		get_viewport().get_texture().get_image().save_png("%s/%s_%s%s.png" % [out_dir, set_name, mode, ("_" + tag) if tag != "" else ""])
	if mode == "bench" or mode == "chars" or mode == "anim": stats["bench"] = await bench(60)
	save_json("%s_%s%s%s" % [set_name, mode, ("_" + str(n_chars)) if n_chars > 0 else "", ("_" + tag) if tag != "" else ""], stats)
	print("RESULT ", JSON.stringify(stats))
	get_tree().quit()
