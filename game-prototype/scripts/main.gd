extends Node3D
# Chapter 1, first minute: Noa gets the bakery ready before the first customer arrives.
# Walk with the joystick, take the cake from the counter, put it on the customers' table.

enum Step { INTRO, PICK_CAKE, PLACE_CAKE, DONE }

const CAM_YAW := 0.32
const CAM_H := 7.6
const CAM_D := 8.8
const SPAWN := Vector3(0.6, 0, 2.7)
const PICKUP_SPOT := Vector3(-3.1, 0, 0.8)     # in front of the display counter, next to the cake
const PICKUP_CAKE_AT := Vector3(-3.2, 1.3, -0.4)
const PLACE_SPOT := Vector3(2.3, 0, 1.6)       # next to the customers' table
const TABLE_CAKE_AT := Vector3(3.2, 1.17, 1.9)
const REACH := 1.7

var room: BakeryRoom
var player: Player
var cam: Camera3D
var ui: TouchUi
var state := GameState.new()
var step: int = Step.INTRO
var busy := false
var carried: Node3D = null
var marker := Node3D.new()
var arrow: MeshInstance3D
var ring: MeshInstance3D
var cam_target := Vector3.ZERO
var zoom := 1.0
var t := 0.0

func _ready() -> void:
	room = BakeryRoom.new(); add_child(room); room.build()
	player = Player.new(); player.position = SPAWN; add_child(player)
	cam = Camera3D.new(); cam.near = 0.1; cam.far = 200.0; add_child(cam)
	_build_marker()
	ui = TouchUi.new(); add_child(ui)
	ui.action_pressed.connect(_on_action)
	ui.card_button_pressed.connect(_on_card_button)
	get_viewport().size_changed.connect(_apply_view)
	_apply_view()
	cam_target = player.position + Vector3(0, 1.0, 0)
	cam.global_position = cam_target + _cam_offset(); cam.look_at(cam_target)
	player.cam_yaw = CAM_YAW
	ui.show_card("היום הראשון במאפייה של נועה",
		"נועה פתחה מאפייה קטנה, והלקוחה הראשונה מגיעה בקרוב. בואו נכין לה מקום.", "מתחילים")
	if "--autotest" in OS.get_cmdline_user_args():
		var at := preload("res://dev/autotest.gd").new(); at.main = self; add_child(at)

func _build_marker() -> void:
	var gold := StandardMaterial3D.new(); gold.albedo_color = Color("ffc24d"); gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.3; cone.height = 0.6; cone.radial_segments = 16
	arrow = MeshInstance3D.new(); arrow.mesh = cone; arrow.material_override = gold; arrow.rotation.z = PI
	var tor := TorusMesh.new(); tor.inner_radius = 1.2; tor.outer_radius = 1.38; tor.rings = 32; tor.ring_segments = 6
	var rm := StandardMaterial3D.new(); rm.albedo_color = Color(1.0, 0.76, 0.3, 0.85); rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring = MeshInstance3D.new(); ring.mesh = tor; ring.material_override = rm; ring.scale = Vector3(1, 0.05, 1)
	marker.add_child(arrow); marker.add_child(ring); marker.visible = false; add_child(marker)

func _cam_offset() -> Vector3:
	return Vector3(sin(CAM_YAW) * CAM_D, CAM_H, cos(CAM_YAW) * CAM_D) * zoom

# Portrait phones get a width-based field of view so the room fits; landscape keeps a height-based one.
func _apply_view() -> void:
	var vp := get_viewport().get_visible_rect().size
	var portrait := vp.y > vp.x
	cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	cam.fov = 42.0 if portrait else 34.0
	var win := get_window()
	win.content_scale_size = Vector2i(390, 844) if portrait else Vector2i(844, 390)

# ---------------------------------------------------------------- story steps
func _on_card_button() -> void:
	if step == Step.INTRO:
		ui.hide_card(); step = Step.PICK_CAKE
		ui.set_objective("לקחת עוגה מהדלפק")
		ui.show_hint("גוררים באצבע בצד שמאל כדי ללכת", 6.0)
		_mark(PICKUP_SPOT, PICKUP_CAKE_AT + Vector3(0, 0.9, 0))
	elif step == Step.DONE:
		get_tree().reload_current_scene()

func _mark(spot: Vector3, above: Vector3) -> void:
	marker.visible = true; ring.global_position = spot + Vector3(0, 0.03, 0); arrow.set_meta("base", above); arrow.global_position = above

func _near(p: Vector3) -> bool:
	var d := player.global_position - p
	return Vector2(d.x, d.z).length() <= REACH

func _on_action() -> void:
	if busy: return
	if step == Step.PICK_CAKE and _near(PICKUP_SPOT): _pick_cake()
	elif step == Step.PLACE_CAKE and _near(PLACE_SPOT): _place_cake()

func _pick_cake() -> void:
	busy = true; player.locked = true; ui.set_action(""); marker.visible = false
	await player.face_point(PICKUP_CAKE_AT)
	player.rig.start_reach()
	await player.rig.action_peak
	room.pickup_cake.queue_free()
	carried = room.instance_model("strawberry_chocolate_cake", 1.5)
	player.rig.carry_anchor.add_child(carried); carried.position = Vector3(0, -0.08, 0)
	player.carrying = true; state.set_flag("has_cake")
	await player.rig.action_done
	player.locked = false; busy = false; step = Step.PLACE_CAKE
	ui.set_objective("להניח את העוגה על שולחן הלקוחות")
	_mark(PLACE_SPOT, TABLE_CAKE_AT + Vector3(0, 1.1, 0))

func _place_cake() -> void:
	busy = true; player.locked = true; ui.set_action(""); marker.visible = false
	await player.face_point(TABLE_CAKE_AT)
	player.rig.start_reach()
	await player.rig.action_peak
	carried.reparent(self, true)
	var tw := create_tween(); tw.tween_property(carried, "global_position", TABLE_CAKE_AT, 0.25)
	carried.rotation = Vector3.ZERO
	player.carrying = false; state.set_flag("table_ready")
	await player.rig.action_done
	player.locked = false; busy = false; step = Step.DONE
	ui.set_objective("")
	await get_tree().create_timer(0.9).timeout
	ui.show_card("המקום מוכן", "העוגה על השולחן, ובדיוק עכשיו הטלפון של נועה מצלצל.", "שוב מההתחלה",
		"רונית: היי! ראיתי את העוגות שלך, כמה עולה עוגה?", "המפגש עם רונית ייכתב בגרסה הבאה.")

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	t += delta
	player.input_vec = ui.current_move() if step != Step.INTRO else Vector2.ZERO
	# follow camera
	cam_target = cam_target.lerp(player.global_position + Vector3(0, 1.0, 0), 1.0 - exp(-6.0 * delta))
	cam.global_position = cam_target + _cam_offset(); cam.look_at(cam_target)
	# contextual action button
	var prompt := ""
	if not busy:
		if step == Step.PICK_CAKE and _near(PICKUP_SPOT): prompt = "לקחת את העוגה"
		elif step == Step.PLACE_CAKE and _near(PLACE_SPOT): prompt = "להניח את העוגה"
	ui.set_action(prompt)
	# marker bob
	if marker.visible:
		var base: Vector3 = arrow.get_meta("base", Vector3.ZERO)
		arrow.global_position = base + Vector3(0, 0.15 * sin(t * 4.0), 0)
		ring.scale = Vector3(1, 0.05, 1) * (1.0 + 0.04 * sin(t * 4.0))

# Direction input that walks Noa toward a point (used by the automated test).
func input_toward(p: Vector3) -> Vector2:
	var d := p - player.global_position; d.y = 0.0
	if d.length() < 0.15: return Vector2.ZERO
	d = d.normalized()
	var fwd := Vector3(-sin(CAM_YAW), 0, -cos(CAM_YAW)); var right := Vector3(cos(CAM_YAW), 0, -sin(CAM_YAW))
	return Vector2(d.dot(right), d.dot(fwd))
