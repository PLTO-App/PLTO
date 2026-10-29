class_name NoaRig
extends Node3D
# Stand-in body for Noa: built from simple shapes and animated by code (idle, walk, carry, reach).
# It is a placeholder until a verified character model is approved. The game only talks to
# tick(), start_reach(), carry_anchor and the two signals, so the real model can replace this file.
# Faces -Z (Godot forward). Left is -X, right is +X. 1 unit = 1/1.43 m.

signal action_peak   # the middle of a reach: the moment an object is picked up or put down
signal action_done

const HIP_Y := 1.22
const ACTION_LEN := 0.7

const SKIN := Color("e8b894")
const HAIR := Color("3a2418")
const BLOUSE := Color("f7efe4")
const APRON := Color("2fb3a2")
const APRON_TRIM := Color("fff6ea")
const POCKET := Color("ff7a59")
const PANTS := Color("33415c")
const SHOES := Color("6b3f2a")

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

var t := 0.0
var walk_phase := 0.0
var walk_w := 0.0
var carry_w := 0.0
var action_t := -1.0
var _peak_fired := false

func _ready() -> void:
	hips.position.y = HIP_Y; add_child(hips)
	var m_skin := _mat(SKIN, 0.7); var m_blouse := _mat(BLOUSE); var m_pants := _mat(PANTS); var m_hair := _mat(HAIR, 0.55)
	var m_apron := _mat(APRON); var m_trim := _mat(APRON_TRIM); var m_pocket := _mat(POCKET); var m_shoes := _mat(SHOES, 0.6)
	# pelvis
	_sphere(hips, 0.25, m_pants, Vector3(0, 0.02, 0), Vector3(1.1, 0.72, 0.85))
	# torso
	spine.position = Vector3(0, 0.05, 0); hips.add_child(spine)
	torso_mesh = _capsule(spine, 0.2, 0.72, m_blouse, Vector3(0, 0.3, 0)); torso_mesh.scale = Vector3(1.12, 1.0, 0.8)
	# apron: bib, skirt, trim and pocket
	_box(spine, Vector3(0.3, 0.3, 0.03), m_apron, Vector3(0, 0.5, -0.158))
	_box(spine, Vector3(0.46, 0.5, 0.03), m_apron, Vector3(0, 0.12, -0.178))
	_box(spine, Vector3(0.48, 0.045, 0.034), m_trim, Vector3(0, -0.14, -0.18))
	_box(spine, Vector3(0.17, 0.12, 0.034), m_pocket, Vector3(0.0, 0.08, -0.19))
	# neck and head
	neck.position = Vector3(0, 0.62, 0); spine.add_child(neck)
	_capsule(neck, 0.055, 0.18, m_skin, Vector3(0, 0.05, 0))
	head.position = Vector3(0, 0.1, 0); neck.add_child(head)
	var face_mat := StandardMaterial3D.new(); face_mat.albedo_texture = load("res://assets/shared/noa_face.png"); face_mat.roughness = 0.65
	var hm := MeshInstance3D.new(); hm.mesh = uv_sphere(0.2, 28, 16); hm.material_override = face_mat; hm.position = Vector3(0, 0.19, 0); hm.scale = Vector3(0.95, 1.06, 1.0); head.add_child(hm)
	_sphere(head, 0.228, m_hair, Vector3(0, 0.215, 0.034), Vector3(1.0, 0.98, 1.0))      # hair: covers the top and back of the head
	var pony := _capsule(head, 0.07, 0.34, m_hair, Vector3(0, 0.12, 0.26)); pony.rotation.x = -0.45
	_sphere(head, 0.062, _mat(APRON), Vector3(0, 0.24, 0.235), Vector3(1, 0.7, 1))      # scrunchie
	for sx in [-1, 1]: _sphere(head, 0.035, m_skin, Vector3(sx * 0.2, 0.18, 0.0), Vector3(0.5, 1, 0.8))   # ears
	# arms: sleeve (blouse) over a skin forearm and hand
	_arm(arm_l, elbow_l, -0.3, m_blouse, m_skin)
	_arm(arm_r, elbow_r, 0.3, m_blouse, m_skin)
	# legs: pants, shoes
	_leg(thigh_l, knee_l, -0.13, m_pants, m_shoes)
	_leg(thigh_r, knee_r, 0.13, m_pants, m_shoes)
	# held objects attach here (in front of the chest)
	carry_anchor.position = Vector3(0, 0.5, -0.62); spine.add_child(carry_anchor)

func _arm(shoulder: Node3D, elbow: Node3D, x: float, sleeve: Material, skin: Material) -> void:
	shoulder.position = Vector3(x, 0.56, 0); spine.add_child(shoulder)
	_sphere(shoulder, 0.085, sleeve, Vector3.ZERO)
	_capsule(shoulder, 0.07, 0.4, sleeve, Vector3(0, -0.19, 0))
	elbow.position = Vector3(0, -0.4, 0); shoulder.add_child(elbow)
	_capsule(elbow, 0.055, 0.42, skin, Vector3(0, -0.2, 0))
	_sphere(elbow, 0.065, skin, Vector3(0, -0.43, 0), Vector3(0.9, 1.1, 0.7))

func _leg(thigh: Node3D, knee: Node3D, x: float, pants: Material, shoe: Material) -> void:
	thigh.position = Vector3(x, 0, 0); hips.add_child(thigh)
	_capsule(thigh, 0.11, 0.6, pants, Vector3(0, -0.28, 0))
	knee.position = Vector3(0, -0.55, 0); thigh.add_child(knee)
	_capsule(knee, 0.085, 0.58, pants, Vector3(0, -0.27, 0))
	_box(knee, Vector3(0.17, 0.12, 0.36), shoe, Vector3(0, -0.58, -0.07))

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
	walk_phase += delta * (7.5 + 2.5 * walk_w) * walk_w
	var s := sin(walk_phase); var c := cos(walk_phase); var w := walk_w
	thigh_l.rotation.x = 0.55 * s * w
	thigh_r.rotation.x = -0.55 * s * w
	knee_l.rotation.x = -(0.05 + 0.8 * maxf(0.0, c) * w)
	knee_r.rotation.x = -(0.05 + 0.8 * maxf(0.0, -c) * w)
	hips.position.y = HIP_Y + 0.04 * absf(s) * w
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

func _capsule(parent: Node3D, r: float, h: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var cm := CapsuleMesh.new(); cm.radius = r; cm.height = h; cm.radial_segments = 14; cm.rings = 4
	var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = m; mi.position = pos; parent.add_child(mi); return mi

func _sphere(parent: Node3D, r: float, m: Material, pos: Vector3, sc := Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 16; sm.rings = 8
	var mi := MeshInstance3D.new(); mi.mesh = sm; mi.material_override = m; mi.position = pos; mi.scale = sc; parent.add_child(mi); return mi

func _box(parent: Node3D, size: Vector3, m: Material, pos: Vector3) -> MeshInstance3D:
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = m; mi.position = pos; parent.add_child(mi); return mi

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
