class_name Town
extends Node3D
# The street: our businesses and the neighbours (minimarket, accountant, bank, suppliers' warehouse), built from the GLB pieces made
# by tools/blender/make_town.py, with Hebrew signs, trees, lamps, parked cars, people walking, and light that follows the time of day.
# It shows the state of the company (the café is "for rent" until it is opened) and reports taps on buildings. No game rules here.

signal building_tapped(id: String)

const BUILDINGS := [
	# id, model, x, sign key, sign position (y, z in front of the board, x offset), board width, building width
	{"id": "warehouse", "model": "bld_warehouse", "x": -31.0, "sign": "sign.warehouse", "sy": 5.4, "sz": 4.46, "bw": 5.0, "w": 11.0},
	{"id": "office", "model": "bld_office", "x": -19.5, "sign": "sign.office", "sy": 3.7, "sz": 3.91, "sx": -1.6, "bw": 3.4, "w": 8.0},
	{"id": "cafe", "model": "bld_cafe", "x": -9.5, "sign": "sign.cafe", "sy": 5.0, "sz": 3.66, "bw": 3.2, "w": 8.5},
	{"id": "bakery", "model": "bld_bakery", "x": 0.0, "sign": "sign.bakery", "sy": 5.2, "sz": 3.91, "bw": 3.6, "w": 9.0},
	{"id": "minimarket", "model": "bld_minimarket", "x": 10.0, "sign": "sign.minimarket", "sy": 4.9, "sz": 3.66, "bw": 4.0, "w": 9.0},
	{"id": "bank", "model": "bld_bank", "x": 19.5, "sign": "sign.bank", "sy": 4.55, "sz": 4.86, "bw": 3.2, "w": 7.5},
	# the third business of ours: for rent (the same empty shop as the café's) until it is opened; the neighbour's minimarket
	# building in green so that the two are not mistaken for each other
	{"id": "market", "model": "bld_cafe_rent", "x": 29.0, "sign": "sign.for_rent", "sy": 2.2, "sz": 4.0, "bw": 2.8, "w": 9.0,
		"owned_model": "bld_minimarket", "owned_tint": Color("6fcf8a"), "owned_sign": "sign.market", "owned_sy": 4.9, "owned_sz": 3.66, "owned_bw": 4.0},
]
const BACK_Z := -4.0          # building origins; their fronts are at about z = -0.5
const WALK_NEAR := 1.6        # the sidewalk in front of the shops
const WALK_FAR := 12.6        # the far sidewalk
const LAMP_X := [-24.0, -14.0, -4.5, 5.0, 15.0, 23.0, 33.0]   # the string lights (make_town.py: festoon) hang between these
const MIN_X := -34.0
const MAX_X := 35.0

static var _scenes := {}
static var _mat_world: ShaderMaterial
static var _mat_glass: ShaderMaterial

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var cloud_clock := 0.0
var indoor := false            # the camera is inside one of our shops: warm ambient light, no fog, a calm backdrop instead of the sky
var lamps: Array[OmniLight3D] = []
var buildings := {}            # id -> Node3D
var signs := {}                # id -> Label3D
var walkers: Array = []
var truck: Node3D
var time01 := 0.3              # 0 = dawn, 0.5 = noon, 1 = night

func _ready() -> void:
	_build_env()
	_build_ground()
	for b in BUILDINGS: _place_building(b)
	_build_props()
	set_time(time01)

static func scene(name: String) -> PackedScene:
	if not _scenes.has(name): _scenes[name] = load("res://assets/town/%s.glb" % name)
	return _scenes[name]

static func world_material() -> ShaderMaterial:
	if _mat_world == null:
		_mat_world = ShaderMaterial.new(); _mat_world.shader = load("res://assets/shaders/world.gdshader")
		_mat_world.set_shader_parameter("shadow_lift", 0.55); _mat_world.set_shader_parameter("rim_amount", 0.08)
	return _mat_world

static func glass_material() -> ShaderMaterial:
	if _mat_glass == null:
		_mat_glass = ShaderMaterial.new(); _mat_glass.shader = load("res://assets/shaders/glass.gdshader")
	return _mat_glass

# An instance of a town piece with the town's materials. shadows: whether it casts sun shadows.
static func piece(name: String, shadows := true) -> Node3D:
	var n: Node3D = scene(name).instantiate()
	_apply(n, shadows)
	return n

static func _apply(n: Node, shadows: bool) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var glass := String(mi.name).begins_with("Glass_")
		mi.material_override = glass_material() if glass else world_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and not glass else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children(): _apply(c, shadows)

# ---------------------------------------------------------------- building the street
func _build_env() -> void:
	var we := WorldEnvironment.new(); env = Environment.new()
	var sky := Sky.new(); sky_mat = ShaderMaterial.new(); sky_mat.shader = load("res://assets/shaders/sky.gdshader"); sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("a9c4ee"); env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC; env.tonemap_exposure = 1.0; env.tonemap_white = 6.0
	env.glow_enabled = true; env.glow_intensity = 0.3; env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true; env.adjustment_saturation = 1.22; env.adjustment_contrast = 1.14
	env.fog_enabled = true; env.fog_light_color = Color("cfe3f2"); env.fog_density = 0.0032; env.fog_sky_affect = 0.0
	we.environment = env; add_child(we)
	sun = DirectionalLight3D.new(); sun.shadow_enabled = true; sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL; sun.shadow_blur = 1.5
	add_child(sun)

func _slab(size: Vector3, pos: Vector3, kind: int, base: Color, tile := 1.2, line := Color("cfc7bb")) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm; mi.position = pos
	var m := ShaderMaterial.new(); m.shader = load("res://assets/shaders/pavement.gdshader")
	m.set_shader_parameter("kind", kind); m.set_shader_parameter("base", base); m.set_shader_parameter("tile", tile); m.set_shader_parameter("line", line)
	m.set_shader_parameter("shadow_lift", 0.6); m.set_shader_parameter("rim_amount", 0.0)
	mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi); return mi

func _build_ground() -> void:
	_slab(Vector3(160, 0.2, 60), Vector3(5, -0.15, -20), 2, Color("6fb35c"))                       # grass behind and around
	_slab(Vector3(92, 0.3, 4.6), Vector3(3, 0.0, 1.6), 1, Color("d9c3a5"), 1.1, Color("b9a68c"))  # near sidewalk
	_slab(Vector3(92, 0.3, 30), Vector3(3, -0.02, -15.0), 1, Color("c9bba6"), 1.6, Color("ad9f8a"))  # yard behind the row
	_slab(Vector3(140, 0.2, 7.2), Vector3(-5, -0.06, 7.5), 0, Color("4a4d57"))                      # road
	_slab(Vector3(92, 0.3, 3.6), Vector3(3, 0.0, WALK_FAR), 1, Color("d9c3a5"), 1.1, Color("b9a68c"))  # far sidewalk
	_slab(Vector3(140, 0.2, 40), Vector3(-5, -0.12, 34.0), 2, Color("6fb35c"))                     # park on the near side
	var kerb := StandardMaterial3D.new(); kerb.albedo_color = Color("c7c2b8"); kerb.roughness = 0.9
	for z in [3.9, 11.1, -0.7]:
		var k := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(92, 0.34, 0.25); k.mesh = bm; k.position = Vector3(3, 0.02, z)
		k.material_override = kerb; add_child(k)
	# lane markings and a crosswalk in front of the bakery
	var paint := StandardMaterial3D.new(); paint.albedo_color = Color("f2efe6"); paint.roughness = 0.8
	var x := -40.0
	while x < 46.0:
		if absf(x - 1.0) > 3.0:
			var d := MeshInstance3D.new(); var dm := BoxMesh.new(); dm.size = Vector3(1.8, 0.02, 0.18); d.mesh = dm; d.position = Vector3(x, 0.05, 7.5); d.material_override = paint; add_child(d)
		x += 3.6
	for i in 7:
		var s := MeshInstance3D.new(); var sm := BoxMesh.new(); sm.size = Vector3(0.55, 0.02, 6.6); s.mesh = sm; s.position = Vector3(-1.2 + i * 0.9, 0.05, 7.5); s.material_override = paint; add_child(s)
	var sky := piece("town_skyline", false); sky.position = Vector3(-5, -0.2, -32); add_child(sky)

func _place_building(b: Dictionary) -> void:
	var holder := Node3D.new(); holder.position = Vector3(b["x"], 0, BACK_Z); holder.name = b["id"]; add_child(holder)
	var bld := piece(b["model"]); holder.add_child(bld); holder.set_meta("bld_node", bld)
	buildings[b["id"]] = holder
	var lab := Label3D.new(); lab.font = Fonts.get_font(true); lab.font_size = 110; lab.pixel_size = 0.0055
	lab.outline_size = 18; lab.outline_modulate = Color(0.12, 0.07, 0.04, 0.9); lab.modulate = Color("fff6ea")
	lab.position = Vector3(b.get("sx", 0.0), b["sy"], b["sz"]); lab.text = Loc.t(b["sign"])
	_fit(lab, float(b["bw"]) - 0.4)
	lab.double_sided = false; lab.shaded = false
	if b.has("owned_model"): lab.modulate = Color("e94b4b")          # a shop for rent until it is opened
	holder.add_child(lab); signs[b["id"]] = lab
	# tap area
	var area := Area3D.new(); var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(b["w"], 9, 8)
	cs.shape = bs; cs.position = Vector3(0, 4.5, 0); area.add_child(cs); area.input_ray_pickable = true
	area.input_event.connect(func(_cam, ev, _p, _n, _i):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed): building_tapped.emit(b["id"]))
	holder.add_child(area)

# Shrinks a sign's text so it fits its board.
func _fit(lab: Label3D, width: float) -> void:
	var w := lab.font.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lab.font_size).x * 0.0055
	lab.pixel_size = 0.0055 * minf(1.0, width / maxf(0.01, w))

# Swaps a shop of ours between "for rent" and open (the café and the market). owned: {id: true}
func show_owned(owned: Dictionary) -> void:
	for b in BUILDINGS:
		if b["id"] != "cafe" and not b.has("owned_model"): continue
		var id: String = b["id"]; var has := owned.has(id)
		var holder: Node3D = buildings[id]
		var want: String = String(b.get("owned_model", "bld_cafe")) if has else String(b.get("rent_model", "bld_cafe_rent"))
		if holder.get_meta("model", "") == want: continue
		if holder.has_meta("bld_node") and is_instance_valid(holder.get_meta("bld_node")): (holder.get_meta("bld_node") as Node).queue_free()
		var bld := piece(want)
		if has and b.has("owned_tint"): _tint(bld, b["owned_tint"])
		holder.add_child(bld); holder.move_child(bld, 0); holder.set_meta("bld_node", bld); holder.set_meta("model", want)
		var lab: Label3D = signs[id]
		lab.text = Loc.t(String(b.get("owned_sign", "sign.cafe"))) if has else Loc.t("sign.for_rent")
		lab.position = Vector3(0, float(b.get("owned_sy", 5.0)), float(b.get("owned_sz", 3.66))) if has else Vector3(0, 2.2, 4.0)
		_fit(lab, float(b.get("owned_bw", 2.8)) if has else 2.8)
		lab.modulate = Color("fff6ea") if has else Color("e94b4b")
		if id == "cafe": for t in get_tree().get_nodes_in_group("cafe_tables"): t.visible = has

static var _tint_mats := {}

# A copy of a building in another colour: the vertex colours are multiplied by the tint.
static func _tint(n: Node, color: Color) -> void:
	if n is MeshInstance3D and not String(n.name).begins_with("Glass_"):
		var key := color.to_html()
		if not _tint_mats.has(key):
			var m := world_material().duplicate() as ShaderMaterial
			m.set_shader_parameter("tint_amount", 0.85); m.set_shader_parameter("tint", color)
			_tint_mats[key] = m
		(n as MeshInstance3D).material_override = _tint_mats[key]
	for c in n.get_children(): _tint(c, color)

func _build_props() -> void:
	for x in LAMP_X:
		var l := piece("prop_lamp", false); l.position = Vector3(x, 0, 3.4); l.rotation.y = 0.0; add_child(l)
		var ol := OmniLight3D.new(); ol.position = Vector3(x, 4.0, 2.6); ol.omni_range = 8.0; ol.light_color = Color("ffcf8a"); ol.light_energy = 0.0
		ol.shadow_enabled = false; add_child(ol); lamps.append(ol)
	add_child(piece("prop_lights", false))                                # string lights between the lamps, glowing at night
	var trees := ["prop_tree", "prop_tree_b", "prop_tree_c", "prop_tree_b"]
	var ti := 0
	for x in [-26.0, -15.0, -3.0, 6.0, 15.0, 26.0, -36.0, 36.0]:
		var t := piece(trees[ti % trees.size()]); ti += 1; t.position = Vector3(x, 0, 13.6); t.rotation.y = x; add_child(t)
	for x in [-20.0, 9.0]:
		var bn := piece("prop_bench"); bn.position = Vector3(x, 0, 12.4); bn.rotation.y = PI; add_child(bn)
	for x in [-5.0, 4.6, 14.4]:
		var pl := piece("prop_planter"); pl.position = Vector3(x, 0.12, 0.2); add_child(pl)
	var f := piece("prop_fountain"); f.position = Vector3(-6.0, 0.1, 19.0); add_child(f)
	var prng := RandomNumberGenerator.new(); prng.seed = 11
	for i in 16:
		var px := prng.randf_range(-40.0, 30.0); var pz := prng.randf_range(16.5, 30.0)
		if absf(px + 6.0) < 4.0 and pz < 23.0: continue
		var tr := piece(["prop_tree", "prop_tree_b", "prop_tree_d", "prop_tree_c"][i % 4]); tr.position = Vector3(px, 0, pz); tr.rotation.y = px; tr.scale = Vector3.ONE * prng.randf_range(0.8, 1.25); add_child(tr)
	for x in [-12.0, 0.0, 12.0, -28.0]:
		var bed := piece("prop_planter"); bed.position = Vector3(x, 0, 16.2); bed.scale = Vector3(1.6, 1.0, 1.2); add_child(bed)
	for x in [-24.0, -16.0, -9.0, 3.0, 9.5, 18.0, 27.0]:                    # low hedges and flowers along the far sidewalk
		var bs := piece("prop_bush"); bs.position = Vector3(x, 0.1, 15.0 + prng.randf_range(-0.3, 0.3)); bs.rotation.y = prng.randf_range(-0.2, 0.2); bs.scale = Vector3.ONE * prng.randf_range(0.9, 1.3); add_child(bs)
	for x in [-11.5, -7.5]:
		var tb := piece("prop_table"); tb.position = Vector3(x, 0.12, 1.4); tb.add_to_group("cafe_tables"); add_child(tb)
	# small street life: a hydrant, a mailbox, bins and the baker's bicycle
	var hy := piece("prop_hydrant"); hy.position = Vector3(-6.6, 0.12, 3.35); add_child(hy)
	var mb := piece("prop_mailbox"); mb.position = Vector3(13.2, 0.12, 3.3); mb.rotation.y = PI; add_child(mb)
	for bp in [Vector3(7.0, 0.12, 3.3), Vector3(-16.4, 0.12, 3.3), Vector3(24.8, 0.12, 3.3)]:
		var bin := piece("prop_bin"); bin.position = bp; add_child(bin)
	var bk := piece("prop_bike"); bk.position = Vector3(3.5, 0.12, 0.7); bk.rotation.y = 0.12; add_child(bk)
	var c1 := piece("prop_car_red"); c1.position = Vector3(-17.0, 0, 9.4); add_child(c1)
	var c2 := piece("prop_car_blue"); c2.position = Vector3(18.0, 0, 5.6); c2.rotation.y = PI; add_child(c2)
	truck = piece("prop_truck"); truck.position = Vector3(-29.0, 0, 5.4); truck.rotation.y = PI; add_child(truck)
	_build_smoke(Vector3(2.6, 10.95, -1.2), buildings["bakery"])

# Steam rising from the bakery chimney: a few soft puffs that drift up, grow and fade (CPU particles, cheap on phones).
func _build_smoke(at: Vector3, parent: Node3D) -> void:
	var p := CPUParticles3D.new(); p.position = at; p.amount = 12; p.lifetime = 4.6; p.local_coords = false
	var sm := SphereMesh.new(); sm.radius = 0.42; sm.height = 0.84; sm.radial_segments = 8; sm.rings = 4
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true; mat.albedo_color = Color("ffffff")
	sm.material = mat; p.mesh = sm
	p.direction = Vector3(0.25, 1, 0.1); p.spread = 10.0; p.initial_velocity_min = 0.7; p.initial_velocity_max = 1.1; p.gravity = Vector3(0.12, 0.05, 0)
	p.scale_amount_min = 0.7; p.scale_amount_max = 1.1
	var curve := Curve.new(); curve.add_point(Vector2(0, 0.35)); curve.add_point(Vector2(1, 2.1)); p.scale_amount_curve = curve
	var grad := Gradient.new(); grad.set_color(0, Color(1, 1, 1, 0.0)); grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.2, Color(1, 1, 1, 0.38)); grad.add_point(0.65, Color(0.95, 0.95, 1.0, 0.2))
	p.color_ramp = grad; p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)

# The hub camera: from the front right, looking down along the street (like a corner view), centred on x.
static func camera_pose(x: float, portrait: bool) -> Transform3D:
	var target := Vector3(x, 2.2, 2.5)
	var off := Vector3(0, 15.5, 21.0) if portrait else Vector3(0, 13.0, 19.0)
	off = off.rotated(Vector3.UP, deg_to_rad(28.0))
	return Transform3D.IDENTITY.looking_at(-off, Vector3.UP).translated(target + off)

# ---------------------------------------------------------------- people on the street
func spawn_walkers(looks: Array, n: int, seed_value: int) -> void:
	for w in walkers: if is_instance_valid(w["rig"]): w["rig"].queue_free()
	walkers = []
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	for i in mini(n, looks.size()):
		var rig := CharacterRig.make(looks[i]); add_child(rig)
		var far := i % 2 == 1
		var z := (WALK_FAR + rng.randf_range(-0.5, 0.5)) if far else (WALK_NEAR + rng.randf_range(-0.4, 0.6))
		var x := rng.randf_range(MIN_X + 4, MAX_X - 4)
		rig.position = Vector3(x, 0.12, z)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		walkers.append({"rig": rig, "dir": dir, "speed": rng.randf_range(1.3, 1.9), "pause": rng.randf_range(0.0, 3.0), "z": z})

func _process(delta: float) -> void:
	cloud_clock += delta * 0.004
	sky_mat.set_shader_parameter("drift", cloud_clock)
	for w in walkers:
		var rig: CharacterRig = w["rig"]
		if not is_instance_valid(rig): continue
		if w["pause"] > 0.0:
			w["pause"] -= delta; rig.tick(delta, 0.0, false); continue
		rig.position.x += w["dir"] * w["speed"] * delta
		rig.rotation.y = lerp_angle(rig.rotation.y, -PI / 2 * w["dir"], clampf(8.0 * delta, 0, 1))
		rig.tick(delta, w["speed"] / 3.0, false)
		if rig.position.x > MAX_X or rig.position.x < MIN_X:
			w["dir"] = -w["dir"]; w["pause"] = randf_range(0.5, 3.0)
		elif randf() < delta * 0.05:
			w["pause"] = randf_range(1.0, 3.5)

# ---------------------------------------------------------------- time of day
# t: 0 early morning, 0.5 midday, 0.8 sunset, 1 night.
# Key columns: t, sun colour, sun energy, sun elevation, sky top, sky horizon, ambient energy, window glow,
#              ambient colour, cloud light, cloud shade, cloud amount, ground colour of the sky, night amount
const TIME_KEYS := [
	[0.0, Color("ffc88f"), 0.78, 16.0, Color("6f9fe0"), Color("f7c9a0"), 0.36, 0.25, Color("b9b4d8"), Color("fff0df"), Color("d8a9a8"), 0.46, Color("8a8f7a"), 0.0],
	[0.35, Color("ffeccc"), 0.95, 50.0, Color("3f86df"), Color("c4e4fa"), 0.37, 0.0, Color("a4c2f0"), Color("ffffff"), Color("a9bfdc"), 0.5, Color("7da668"), 0.0],
	[0.6, Color("ffeccc"), 0.95, 56.0, Color("3f86df"), Color("c4e4fa"), 0.37, 0.0, Color("a4c2f0"), Color("ffffff"), Color("a9bfdc"), 0.5, Color("7da668"), 0.0],
	[0.82, Color("ff9a5c"), 0.78, 13.0, Color("4d5fb5"), Color("ffa67e"), 0.34, 0.45, Color("c3a3cf"), Color("ffd2b0"), Color("a2658f"), 0.55, Color("8a6a62"), 0.0],
	[1.0, Color("7088d8"), 0.14, 30.0, Color("070d2a"), Color("1c2750"), 0.22, 1.25, Color("3b4a8f"), Color("5a6aa8"), Color("1a2246"), 0.3, Color("0d1428"), 1.0]]

func set_time(t: float) -> void:
	time01 = clampf(t, 0.0, 1.0)
	var a: Array = TIME_KEYS[0]; var b: Array = TIME_KEYS[TIME_KEYS.size() - 1]
	for i in TIME_KEYS.size() - 1:
		if time01 >= TIME_KEYS[i][0] and time01 <= TIME_KEYS[i + 1][0]: a = TIME_KEYS[i]; b = TIME_KEYS[i + 1]
	var k: float = 0.0 if b[0] == a[0] else (time01 - float(a[0])) / (float(b[0]) - float(a[0]))
	sun.light_color = (a[1] as Color).lerp(b[1], k); sun.light_energy = lerpf(a[2], b[2], k)
	var elev := deg_to_rad(lerpf(a[3], b[3], k))
	sun.rotation = Vector3(-elev, deg_to_rad(150.0), 0)      # from the front left, so the shop fronts are in the light
	var horizon: Color = (a[5] as Color).lerp(b[5], k)
	sky_mat.set_shader_parameter("top_color", (a[4] as Color).lerp(b[4], k))
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", (a[12] as Color).lerp(b[12], k))
	sky_mat.set_shader_parameter("sun_color", (a[1] as Color).lerp(b[1], k))
	sky_mat.set_shader_parameter("cloud_color", (a[9] as Color).lerp(b[9], k))
	sky_mat.set_shader_parameter("cloud_shade", (a[10] as Color).lerp(b[10], k))
	sky_mat.set_shader_parameter("cloud_amount", lerpf(a[11], b[11], k))
	sky_mat.set_shader_parameter("night", lerpf(a[13], b[13], k))
	env.ambient_light_color = (a[8] as Color).lerp(b[8], k)
	env.ambient_light_energy = lerpf(a[6], b[6], k)
	env.fog_light_color = horizon
	var glow: float = lerpf(a[7], b[7], k)
	glass_material().set_shader_parameter("glow", glow)
	for l in lamps: l.light_energy = clampf((glow - 0.3) * 1.6, 0.0, 1.6)
	_apply_indoor()

# The shops light themselves (a window light inside ShopRoom), so inside only the ambient light and the backdrop come from here.
func set_indoor(on: bool) -> void:
	indoor = on; _apply_indoor()

func _apply_indoor() -> void:
	env.fog_enabled = not indoor
	env.glow_enabled = not indoor
	env.background_mode = Environment.BG_COLOR if indoor else Environment.BG_SKY
	env.background_color = Color("1b2a47")
	if indoor:
		env.ambient_light_color = Color("ffe0c0"); env.ambient_light_energy = 0.42
