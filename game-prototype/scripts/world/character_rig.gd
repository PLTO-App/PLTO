class_name CharacterRig
extends Node3D
# A stylized character built from simple shapes and animated by code: idle, walk, carry, reach, expressions.
# Noa and every customer use this one rig with a different "look" (skin tone, hair, clothes), so a new customer is data, not code.
# It is a stand-in for a modeled character: the game only uses tick(), start_reach(), set_expression(), carry_anchor and the signals,
# so a modeled version can replace this file. Faces -Z. Left is -X, right is +X. 1 unit = 1/1.43 m.

signal action_peak   # the middle of a reach: the moment an object is picked up or put down
signal action_done

const HIP_Y := 1.22
const ACTION_LEN := 0.7
const EXPRESSIONS := ["smile", "happy", "surprised", "think", "blink", "neutral"]
const DEFAULT_LOOK := {"skin": "light", "hair": "5b3a29", "hair_style": "bun", "top": "f7efe4", "bottom": "33415c", "apron": "", "shoes": "6b3f2a"}

var look := DEFAULT_LOOK.duplicate()
var hips := Node3D.new()
var spine := Node3D.new()
var neck := Node3D.new()
var head := Node3D.new()
var torso_mesh: MeshInstance3D
var arm_l := Node3D.new()
var arm_r := Node3D.new()
var elbow_l := Node3D.new()
var elbow_r := Node3D.new()
var thigh_l := Node3D.new()
var thigh_r := Node3D.new()
var knee_l := Node3D.new()
var knee_r := Node3D.new()
var carry_anchor := Node3D.new()
var face_mat: StandardMaterial3D

var t := 0.0
var walk_phase := 0.0
var walk_w := 0.0
var carry_w := 0.0
var action_t := -1.0
var _peak_fired := false
var base_expression := "smile"
var _shown_expression := ""
var _blink_in := 2.5
var _blink_hold := 0.0
var _hop := 0.0

static func make(p_look: Dictionary) -> CharacterRig:
	var r := CharacterRig.new()
	for k in p_look: r.look[k] = p_look[k]
	return r

func _ready() -> void:
	var skin_color := {"light": Color("f4c8a6"), "medium": Color("d6a076"), "deep": Color("966242")}.get(look["skin"], Color("f4c8a6")) as Color
	var m_skin := _mat(skin_color, 0.7); var m_top := _mat(Color(look["top"])); var m_pants := _mat(Color(look["bottom"]))
	var m_hair := _mat(Color(look["hair"]), 0.5); var m_shoes := _mat(Color(look["shoes"]), 0.6)
	hips.position.y = HIP_Y; add_child(hips)
	_sphere(hips, 0.25, m_pants, Vector3(0, 0.02, 0), Vector3(1.1, 0.72, 0.85))
	spine.position = Vector3(0, 0.05, 0); hips.add_child(spine)
	torso_mesh = _capsule(spine, 0.2, 0.72, m_top, Vector3(0, 0.3, 0), true); torso_mesh.scale = Vector3(1.1, 1.0, 0.8)
	if look["apron"] != "": _apron(Color(look["apron"]))
	neck.position = Vector3(0, 0.62, 0); spine.add_child(neck)
	_capsule(neck, 0.055, 0.18, m_skin, Vector3(0, 0.05, 0))
	head.position = Vector3(0, 0.1, 0); neck.add_child(head)
	_build_head(skin_color, m_hair, m_skin)
	_arm(arm_l, elbow_l, -0.3, m_top, m_skin)
	_arm(arm_r, elbow_r, 0.3, m_top, m_skin)
	_leg(thigh_l, knee_l, -0.13, m_pants, m_shoes)
	_leg(thigh_r, knee_r, 0.13, m_pants, m_shoes)
	carry_anchor.position = Vector3(0, 0.5, -0.62); spine.add_child(carry_anchor)
	set_expression(base_expression)

func _apron(c: Color) -> void:
	var m := _mat(c); var emblem := _mat(Color("fff6ea"))
	var cm := CylinderMesh.new(); cm.top_radius = 0.22; cm.bottom_radius = 0.3; cm.height = 0.52; cm.radial_segments = 20; cm.rings = 1
	var skirt := MeshInstance3D.new(); skirt.mesh = cm; skirt.material_override = m; skirt.position = Vector3(0, 0.08, 0); skirt.scale = Vector3(1.05, 1.0, 0.82); spine.add_child(skirt)
	_sphere(spine, 0.17, m, Vector3(0, 0.5, -0.095), Vector3(1.0, 1.15, 0.5))                                    # rounded bib
	_sphere(spine, 0.05, emblem, Vector3(0, 0.5, -0.178), Vector3(1, 1, 0.35))                                  # little cupcake badge
	_box(spine, Vector3(0.17, 0.1, 0.03), emblem, Vector3(0, 0.02, -0.225))                                      # pocket

func _build_head(skin_color: Color, m_hair: Material, m_skin: Material) -> void:
	face_mat = StandardMaterial3D.new(); face_mat.roughness = 0.65
	face_mat.albedo_texture = load("res://assets/characters/face_%s.png" % look["skin"])
	face_mat.uv1_scale = Vector3(1, 1.0 / EXPRESSIONS.size(), 1); face_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	face_mat.texture_repeat = false
	var hm := MeshInstance3D.new(); hm.mesh = uv_sphere(0.2, 32, 18); hm.material_override = face_mat
	hm.position = Vector3(0, 0.22, 0); hm.scale = Vector3(1.1, 1.22, 1.1); head.add_child(hm)
	_sphere(head, 0.262, m_hair, Vector3(0, 0.25, 0.04), Vector3.ONE, true)                                   # hair cap over the top and back
	for p in [[-0.07, 0.41, -0.2, 0.095], [0.07, 0.41, -0.2, 0.095]]:   # fringe, gives a clean hairline
		_sphere(head, p[3], m_hair, Vector3(p[0], p[1], p[2]), Vector3(1.0, 0.72, 0.6))
	match look["hair_style"]:
		"bun":
			_sphere(head, 0.12, m_hair, Vector3(0, 0.55, 0.07))
		"long":
			_capsule(head, 0.13, 0.56, m_hair, Vector3(0, 0.02, 0.19))
			for sx in [-1, 1]: _capsule(head, 0.07, 0.4, m_hair, Vector3(sx * 0.21, 0.08, 0.03))
		"pony":
			var pony := _capsule(head, 0.08, 0.38, m_hair, Vector3(0, 0.22, 0.3)); pony.rotation.x = -0.55
			_sphere(head, 0.06, _mat(Color("2fb3a2")), Vector3(0, 0.36, 0.27), Vector3(1, 0.7, 1))
		_:
			for sx in [-1, 1]: _sphere(head, 0.07, m_hair, Vector3(sx * 0.2, 0.3, -0.04))

func _arm(shoulder: Node3D, elbow: Node3D, x: float, sleeve: Material, skin: Material) -> void:
	shoulder.position = Vector3(x, 0.56, 0); spine.add_child(shoulder)
	_capsule(shoulder, 0.07, 0.4, sleeve, Vector3(0, -0.19, 0))
	elbow.position = Vector3(0, -0.4, 0); shoulder.add_child(elbow)
	_capsule(elbow, 0.055, 0.42, skin, Vector3(0, -0.2, 0))
	_sphere(elbow, 0.065, skin, Vector3(0, -0.43, 0), Vector3(0.9, 1.1, 0.7))

func _leg(thigh: Node3D, knee: Node3D, x: float, pants: Material, shoe: Material) -> void:
	thigh.position = Vector3(x, 0, 0); hips.add_child(thigh)
	_capsule(thigh, 0.11, 0.6, pants, Vector3(0, -0.28, 0), true)
	knee.position = Vector3(0, -0.55, 0); thigh.add_child(knee)
	_capsule(knee, 0.085, 0.58, pants, Vector3(0, -0.27, 0), true)
	_box(knee, Vector3(0.17, 0.12, 0.36), shoe, Vector3(0, -0.58, -0.07))

# ---------------------------------------------------------------- expressions
func set_expression(name: String) -> void:
	base_expression = name
	_show(name)

func _show(name: String) -> void:
	if name == _shown_expression or face_mat == null: return
	_shown_expression = name
	face_mat.uv1_offset = Vector3(0, float(EXPRESSIONS.find(name)) / EXPRESSIONS.size(), 0)

# A small happy jump (used when a customer is pleased).
func hop() -> void:
	_hop = 1.0

# ---------------------------------------------------------------- animation
func start_reach() -> void:
	action_t = 0.0; _peak_fired = false

func is_busy() -> bool:
	return action_t >= 0.0

func tick(delta: float, speed01: float, carrying: bool) -> void:
	t += delta
	walk_w = move_toward(walk_w, clampf(speed01, 0.0, 1.0), delta * 7.0)
	carry_w = move_toward(carry_w, 1.0 if carrying else 0.0, delta * 5.0)
	var reach := 0.0
	if action_t >= 0.0:
		action_t += delta
		reach = sin(PI * clampf(action_t / ACTION_LEN, 0.0, 1.0))
		if not _peak_fired and action_t >= ACTION_LEN * 0.5:
			_peak_fired = true; action_peak.emit()
		if action_t >= ACTION_LEN:
			action_t = -1.0; action_done.emit()
	# blink every few seconds when the base expression has open eyes
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_hold = 0.12; _blink_in = 2.6 + fmod(t * 1.7, 1.8)
	_blink_hold = maxf(0.0, _blink_hold - delta)
	if base_expression in ["smile", "neutral", "think"]: _show("blink" if _blink_hold > 0.0 else base_expression)
	walk_phase += delta * (7.5 + 2.5 * walk_w) * walk_w
	var s := sin(walk_phase); var c := cos(walk_phase); var w := walk_w
	thigh_l.rotation.x = 0.55 * s * w
	thigh_r.rotation.x = -0.55 * s * w
	knee_l.rotation.x = -(0.05 + 0.8 * maxf(0.0, c) * w)
	knee_r.rotation.x = -(0.05 + 0.8 * maxf(0.0, -c) * w)
	_hop = move_toward(_hop, 0.0, delta * 2.2)
	hips.position.y = HIP_Y + 0.04 * absf(s) * w + 0.35 * sin(PI * (1.0 - _hop)) * (1.0 if _hop > 0.0 else 0.0)
	spine.rotation.y = 0.14 * s * w
	spine.rotation.x = 0.05 * w + 0.3 * reach
	var breath := sin(t * 1.9)
	torso_mesh.scale.y = 1.0 + 0.012 * breath
	var swing := 0.45 * s * w
	var free := 1.0 - carry_w
	arm_r.rotation.x = lerpf(swing * free + 0.03 * breath, 0.85, carry_w) + 0.5 * reach
	arm_l.rotation.x = lerpf(-swing * free - 0.03 * breath, 0.85, carry_w) + 0.5 * reach
	elbow_r.rotation.x = lerpf(0.2 + 0.25 * w, 1.25, carry_w) - 0.5 * reach
	elbow_l.rotation.x = lerpf(0.2 + 0.25 * w, 1.25, carry_w) - 0.5 * reach
	arm_r.rotation.z = lerpf(-0.07, -0.3, carry_w)
	arm_l.rotation.z = lerpf(0.07, 0.3, carry_w)
	head.rotation.y = 0.12 * sin(t * 0.6) * (1.0 - w)
	head.rotation.x = 0.03 * breath - 0.1 * reach

# ---------------------------------------------------------------- mesh helpers
func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = rough; return m

func _capsule(parent: Node3D, r: float, h: float, m: Material, pos: Vector3, shadow := false) -> MeshInstance3D:
	var cm := CapsuleMesh.new(); cm.radius = r; cm.height = h; cm.radial_segments = 12; cm.rings = 3
	var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = m; mi.position = pos; _shadow(mi, shadow); parent.add_child(mi); return mi

func _sphere(parent: Node3D, r: float, m: Material, pos: Vector3, sc := Vector3.ONE, shadow := false) -> MeshInstance3D:
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 14; sm.rings = 7
	var mi := MeshInstance3D.new(); mi.mesh = sm; mi.material_override = m; mi.position = pos; mi.scale = sc; _shadow(mi, shadow); parent.add_child(mi); return mi

func _box(parent: Node3D, size: Vector3, m: Material, pos: Vector3) -> MeshInstance3D:
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = m; mi.position = pos; _shadow(mi, false); parent.add_child(mi); return mi

# Each mesh that casts a sun shadow is drawn twice, so only the big parts do (a character has ~25 parts, not ~50 draws).
func _shadow(mi: MeshInstance3D, on: bool) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# UV sphere with the texture centre (u = 0.5, v = 0.5) on the -Z side, so a face texture lands on the front of the head.
static func uv_sphere(radius: float, segs: int, rings: int) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings:
		for s in segs:
			var idx := [[r, s], [r, s + 1], [r + 1, s + 1], [r + 1, s]]
			var pts: Array = []; var uvs: Array = []
			for ij in idx:
				var th := PI * float(ij[0]) / rings; var al := TAU * float(ij[1]) / segs
				pts.append(Vector3(sin(th) * sin(al), cos(th), sin(th) * cos(al)))
				uvs.append(Vector2(float(ij[1]) / segs, float(ij[0]) / rings))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = pts[tri[0]]; var b: Vector3 = pts[tri[1]]; var c: Vector3 = pts[tri[2]]
				var order: Array = tri
				if (b - a).cross(c - a).dot((a + b + c) / 3.0) > 0.0: order = [tri[0], tri[2], tri[1]]   # Godot front faces are clockwise
				for k in order:
					var p: Vector3 = pts[k]; st.set_normal(p); st.set_uv(uvs[k]); st.add_vertex(p * radius)
	return st.commit()
