class_name CharacterRig
extends Node3D
# A modeled character (tools/blender/make_characters.py): a skinned body with a real skeleton, hair styles and accessories,
# painted by the character shader from a "look" (skin, clothes, hair, accessories), with a toon light and an ink outline.
# Every person in the game uses this one rig, so a new person is data, not code.
# The game talks to it through tick(), start_reach(), hop(), set_expression(), set_pose(), carry_anchor and the signals.
# Faces -Z. 1 unit = 1/1.43 m. About 2.45 units tall.

signal action_peak   # the middle of a reach: the moment an object is picked up or put down
signal action_done

const FACE_CELLS := {"neutral": Vector2(0, 0), "smile": Vector2(1, 0), "happy": Vector2(2, 0), "surprised": Vector2(0, 1), "think": Vector2(1, 1),
	"sad": Vector2(2, 1), "annoyed": Vector2(0, 2), "blink": Vector2(1, 2), "talk": Vector2(2, 2)}
const EXPRESSIONS := ["neutral", "smile", "happy", "surprised", "think", "sad", "annoyed", "blink", "talk"]
const SKINS := {"light": Color("f6cfb2"), "fair": Color("f3c09a"), "medium": Color("d9a17a"), "tan": Color("bf865c"), "deep": Color("8f5b3e")}
const LOOPS := ["idle", "walk", "carry_idle", "carry_walk", "wave", "talk", "think", "sad", "work", "sit", "sit_type", "sit_drink"]
const POSES := ["wave", "talk", "think", "sad", "work", "sit", "sit_type", "sit_drink"]
const DEFAULT_LOOK := {"body": "f", "skin": "light", "hair": "5b3a29", "hair_style": "bun", "top": "f7efe4", "bottom": "33415c", "shoes": "6b3f2a",
	"apron": "", "sleeve": 42, "pants": 100, "acc": [], "acc_color": "2f3b52", "height": 100, "build": 100}

static var _scenes := {}
static var _outline: ShaderMaterial
static var _faces := {}

var look := DEFAULT_LOOK.duplicate(true)
var model: Node3D
var anim: AnimationPlayer
var body_mat: ShaderMaterial
var carry_anchor := Node3D.new()
var base_expression := "smile"
var pose := ""                  # a looping pose (sit, work, talk...) that replaces idle and walk
var _action := ""               # a one-shot: give or happy
var _action_t := 0.0
var _action_len := 0.0
var _peak_fired := false
var _current := ""
var _shown := ""
var _blink_in := 2.5
var _blink_hold := 0.0
var _talk_t := 0.0

static func make(p_look: Dictionary) -> CharacterRig:
	var r := CharacterRig.new()
	for k in p_look: r.look[k] = p_look[k]
	return r

static func _scene(kind: String) -> PackedScene:
	if not _scenes.has(kind): _scenes[kind] = load("res://assets/characters/models/char_%s.glb" % kind)
	return _scenes[kind]

static func outline_material() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new(); _outline.shader = load("res://assets/shaders/outline.gdshader")
	return _outline

static func toon_material(c: Color, sheen := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = load("res://assets/shaders/toon.gdshader")
	m.set_shader_parameter("albedo", c); m.set_shader_parameter("sheen", sheen); m.next_pass = outline_material()
	return m

func _ready() -> void:
	var kind: String = "m" if str(look.get("body", "f")) == "m" else "f"
	model = _scene(kind).instantiate()
	var hs := float(look["height"]) / 100.0; var bs := float(look["build"]) / 100.0
	model.scale = Vector3(bs, hs, bs * 0.5 + 0.5)
	add_child(model)
	anim = _find_anim(model)
	body_mat = ShaderMaterial.new(); body_mat.shader = load("res://assets/shaders/character.gdshader")
	if not _faces.has(kind): _faces[kind] = load("res://assets/characters/face_%s.png" % kind)
	body_mat.set_shader_parameter("face_tex", _faces[kind])
	body_mat.set_shader_parameter("skin_color", SKINS.get(look["skin"], SKINS["light"]))
	body_mat.set_shader_parameter("top_color", Color(look["top"]))
	body_mat.set_shader_parameter("bottom_color", Color(look["bottom"]))
	body_mat.set_shader_parameter("shoes_color", Color(look["shoes"]))
	body_mat.set_shader_parameter("sleeve", float(look["sleeve"]) / 100.0)
	body_mat.set_shader_parameter("pants", float(look["pants"]) / 100.0)
	body_mat.set_shader_parameter("apron_on", 1.0 if str(look["apron"]) != "" else 0.0)
	if str(look["apron"]) != "": body_mat.set_shader_parameter("apron_color", Color(look["apron"]))
	body_mat.next_pass = outline_material()
	var hair_c := Color(look["hair"])
	var accs: Array = look["acc"]
	for mi in _meshes(model):
		var n := String(mi.name)
		if n.begins_with("Hair_"):
			mi.visible = n == "Hair_" + str(look["hair_style"])
			mi.material_override = toon_material(hair_c, 1.0); mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("Acc_"):
			var a := n.substr(4); mi.visible = a in accs; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var c := hair_c.darkened(0.1) if a == "beard" else (Color("f7f4ef") if a == "toque" else (Color("2a2420") if a == "glasses" else Color(look["acc_color"])))
			mi.material_override = toon_material(c, 0.3 if a != "glasses" else 0.0)
		else:
			mi.material_override = body_mat
	carry_anchor.position = Vector3(0, 1.38 * hs, -0.42); add_child(carry_anchor)
	if anim != null:
		for an in LOOPS:
			if anim.has_animation(an): anim.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	_blink_in = 1.5 + randf() * 2.0
	set_expression(base_expression)
	_play("idle", 0.0)
	if anim != null: anim.seek(randf() * 2.0, true)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a != null: return a
	return null

func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D: out.append(n)
	for c in n.get_children(): out.append_array(_meshes(c))
	return out

func _play(name: String, blend := 0.2) -> void:
	if anim == null or name == _current or not anim.has_animation(name): return
	_current = name; anim.play(name, blend)

# ---------------------------------------------------------------- expressions
func set_expression(name: String) -> void:
	base_expression = name
	_show(name)

func _show(name: String) -> void:
	if name == _shown or body_mat == null: return
	_shown = name
	body_mat.set_shader_parameter("face_cell", FACE_CELLS.get(name, Vector2(1, 0)))

# ---------------------------------------------------------------- actions and poses
func start_reach() -> void:
	_start_action("give")

# A small happy jump (used when a customer is pleased).
func hop() -> void:
	_start_action("happy")

func _start_action(name: String) -> void:
	if anim == null or not anim.has_animation(name):
		action_peak.emit(); action_done.emit(); return
	_action = name; _action_t = 0.0; _peak_fired = false
	_action_len = anim.get_animation(name).length
	_current = ""; anim.speed_scale = 1.0 if name == "give" else 1.0
	_play(name, 0.12)

func is_busy() -> bool:
	return _action != ""

# A looping pose that replaces idle and walking: "sit", "work", "talk", "think", "wave", "sad", "sit_type", "sit_drink", or "" to clear.
func set_pose(name: String) -> void:
	pose = name if name in POSES else ""

func tick(delta: float, speed01: float, carrying: bool) -> void:
	if anim == null: return
	if _action != "":
		_action_t += delta
		if not _peak_fired and _action_t >= _action_len * 0.5:
			_peak_fired = true
			if _action == "give": action_peak.emit()
		if _action_t >= _action_len:
			var was := _action; _action = ""
			if was == "give": action_done.emit()
	if _action == "":
		var moving := speed01 > 0.08
		if pose != "" and not moving:
			anim.speed_scale = 1.0; _play(pose)
		elif moving:
			anim.speed_scale = 0.75 + 1.25 * clampf(speed01, 0.0, 1.0); _play("carry_walk" if carrying else "walk", 0.15)
		else:
			anim.speed_scale = 1.0; _play("carry_idle" if carrying else "idle", 0.25)
	# blinking and talking
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_hold = 0.13; _blink_in = 2.4 + randf() * 2.4
	_blink_hold = maxf(0.0, _blink_hold - delta)
	var face := base_expression
	if pose == "talk" and _action == "":
		_talk_t += delta
		face = "talk" if fmod(_talk_t, 0.32) < 0.16 else "smile"
	if _blink_hold > 0.0 and face in ["neutral", "smile", "think", "talk", "sad", "surprised"]: face = "blink"
	_show(face)
