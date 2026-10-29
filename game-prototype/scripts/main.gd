extends Node3D
# The bakery day, first slice: a customer comes in with an order, Noa takes it from the display, serves it and gets paid.
# The money, experience and reputation come from the Game systems (autoload); this script only runs the scene and tells the UI.

enum Step { INTRO, PICK, SERVE, BETWEEN }

const CAM_YAW := 0.32
const CAM_H := 7.6
const CAM_D := 8.8
const SPAWN := Vector3(0.6, 0, 2.7)
const DOOR := Vector3(1.8, 0, 8.6)             # where customers come from and leave to (in front of the open side of the room)
const CUSTOMER_SPOT := Vector3(3.7, 0, 0.0)          # behind the table, facing Noa and the camera
const CUSTOMER_PATH := [Vector3(1.6, 0, 4.2), Vector3(1.6, 0, 0.4)]
const PICKUP_SPOT := Vector3(-3.1, 0, 0.8)     # in front of the display counter
const PICKUP_AT := Vector3(-3.2, 1.3, -0.4)
const PLACE_SPOT := Vector3(2.3, 0, 1.6)       # next to the customers' table
const TABLE_AT := Vector3(3.2, 1.17, 1.9)
const REACH := 1.7

var room: BakeryRoom
var player: Player
var cam: Camera3D
var ui: TouchUi
var step: int = Step.INTRO
var busy := false
var customer: Npc = null
var customer_ready := false
var product_id := ""
var product: Dictionary = {}
var carried: Node3D = null
var marker := Node3D.new()
var arrow: MeshInstance3D
var ring: MeshInstance3D
var cam_target := Vector3.ZERO
var zoom := 0.86
var t := 0.0

func _ready() -> void:
	room = BakeryRoom.new(); add_child(room); room.build()
	player = Player.new(); player.position = SPAWN; add_child(player)
	cam = Camera3D.new(); cam.near = 0.1; cam.far = 200.0; add_child(cam)
	_build_marker()
	ui = TouchUi.new(); add_child(ui)
	ui.action_pressed.connect(_on_action)
	ui.card_button_pressed.connect(_on_card_button)
	ui.card_secondary_pressed.connect(_on_card_secondary)
	get_viewport().size_changed.connect(_apply_view)
	_apply_view()
	cam_target = player.position + Vector3(0, 1.0, 0)
	cam.global_position = cam_target + _cam_offset(); cam.look_at(cam_target)
	player.cam_yaw = CAM_YAW
	ui.hud.sync()
	var b := Game.business()
	ui.show_card({"title": "היום הראשון במאפייה של נועה", "body": "נועה פתחה מאפייה קטנה, והלקוחה הראשונה מגיעה בקרוב. בואו נמכור.",
		"button": "מתחילים", "secondary": "להתחיל מאפס" if Game.has_progress() else ""})
	if "--autotest" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/autotest.gd"):
		var at = load("res://dev/autotest.gd").new(); at.main = self; add_child(at)     # development only; not part of the APK

func _build_marker() -> void:
	var gold := StandardMaterial3D.new(); gold.albedo_color = UiStyle.GOLD; gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	get_window().content_scale_size = Vector2i(390, 844) if portrait else Vector2i(844, 390)

# ---------------------------------------------------------------- the day
func _on_card_button() -> void:
	ui.hide_card()
	if step == Step.INTRO:
		ui.show_hint("גוררים באצבע בצד שמאל כדי ללכת", 6.0)
		_next_customer()

func _on_card_secondary() -> void:
	Game.reset_progress(); get_tree().reload_current_scene()

# Picks the next order from the business content and sends the customer in. The first order is fixed (the guided one).
func _next_customer() -> void:
	var b := Game.business()
	var n := Game.profile.sales_count
	var cust: Dictionary
	if n == 0:
		for c in b["customers"]:
			if c["id"] == b["first_order"]["customer"]: cust = c
		product_id = b["first_order"]["product"]
	else:
		cust = b["customers"][n % b["customers"].size()]
		product_id = b["order_cycle"][(n - 1) % b["order_cycle"].size()]
	product = b["products"][product_id]
	step = Step.PICK; customer_ready = false
	ui.set_objective("לקחת %s מהדלפק" % product["name"])
	_mark(PICKUP_SPOT, PICKUP_AT + Vector3(0, 0.9, 0))
	customer = Npc.make(cust); customer.position = DOOR; room.add_child(customer)
	for p in CUSTOMER_PATH + [CUSTOMER_SPOT]:
		await customer.walk_to(p)
		if not is_instance_valid(customer): return
	customer.face_point(PLACE_SPOT); customer.set_solid(true)
	customer.show_order("res://assets/ui/%s.png" % product["icon"])
	Game.sfx.play("arrive"); customer_ready = true

func _mark(spot: Vector3, above: Vector3) -> void:
	marker.visible = true; ring.global_position = spot + Vector3(0, 0.07, 0); arrow.set_meta("base", above); arrow.global_position = above

func _near(p: Vector3) -> bool:
	var d := player.global_position - p
	return Vector2(d.x, d.z).length() <= REACH

func _on_action() -> void:
	if busy: return
	if step == Step.PICK and _near(PICKUP_SPOT): _pick()
	elif step == Step.SERVE and customer_ready and _near(PLACE_SPOT): _serve()

func _pick() -> void:
	busy = true; player.locked = true; ui.set_action(""); marker.visible = false
	await player.face_point(PICKUP_AT)
	player.rig.start_reach()
	await player.rig.action_peak
	Game.sfx.play("pickup")
	carried = room.instance_model(product["model"], product["scale"])
	player.rig.carry_anchor.add_child(carried); carried.position = Vector3(0, -0.08, 0)
	player.carrying = true
	await player.rig.action_done
	player.locked = false; busy = false; step = Step.SERVE
	ui.set_objective("להגיש ל%s" % customer.data["name"])
	_mark(PLACE_SPOT, TABLE_AT + Vector3(0, 1.1, 0))

func _serve() -> void:
	busy = true; player.locked = true; ui.set_action(""); marker.visible = false; ui.set_objective("")
	await player.face_point(TABLE_AT)
	player.rig.start_reach()
	await player.rig.action_peak
	carried.reparent(self, true)
	carried.rotation = Vector3.ZERO
	create_tween().tween_property(carried, "global_position", TABLE_AT, 0.25)
	Game.sfx.play("place"); player.carrying = false
	customer.hide_order(); customer.rig.set_expression("happy"); customer.rig.hop()
	await player.rig.action_done
	player.locked = false
	await _complete_sale()

func _complete_sale() -> void:
	var before := {"level": Game.profile.level, "xp": Game.profile.xp, "cash": Game.profile.cash, "rep": Game.profile.reputation}
	ui.hud.hold = true            # the top bar keeps the old numbers until the reward animation raises them
	var result := Game.complete_sale(product_id)
	var origin := cam.unproject_position(customer.global_position + Vector3(0, 2.7, 0))
	await get_tree().create_timer(0.35).timeout
	await ui.fx.play_sale(result, origin, before)
	if result["first_sale"]:
		ui.show_card({"title": "המכירה הראשונה בקופה!",
			"lines": ["מכירה: %s" % UiStyle.money(result["revenue"]), "חומרי גלם: %s" % UiStyle.money(result["cost"]), "רווח: %s" % UiStyle.money(result["profit"]),
				"ניסיון: %d" % result["xp"], "בונוס מכירה ראשונה: %d" % result["bonus_xp"], "מוניטין: %s" % _delta_text(result["reputation"])],
			"note": "המספרים להמחשה בלבד, ולא ייעוץ עסקי.", "button": "ממשיכים"})
		await ui.card_button_pressed
	else:
		ui.show_hint("מכירה ל%s, רווח של %s" % [customer.data["name"], UiStyle.money(result["profit"])], 3.0)
	step = Step.BETWEEN; busy = false
	_customer_leaves()
	await get_tree().create_timer(1.6).timeout
	_next_customer()

# "up 5%" without a plus sign, which flips direction in right to left text
func _delta_text(d: int) -> String:
	if d > 0: return "עלייה של %d%%" % d
	if d < 0: return "ירידה של %d%%" % absi(d)
	return "ללא שינוי"

func _customer_leaves() -> void:
	var c := customer; var cake := carried
	customer = null; carried = null
	c.set_solid(false); c.rig.set_expression("smile")
	if is_instance_valid(cake):
		var tw := create_tween(); tw.tween_property(cake, "scale", Vector3.ZERO, 0.4).set_delay(0.5); tw.tween_callback(cake.queue_free)
	for p in [Vector3(1.6, 0, 0.4), Vector3(1.6, 0, 4.2), DOOR]: await c.walk_to(p)
	c.queue_free()

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	t += delta
	player.input_vec = ui.current_move() if step != Step.INTRO else Vector2.ZERO
	cam_target = cam_target.lerp(player.global_position + Vector3(0, 1.0, 0), 1.0 - exp(-6.0 * delta))
	cam.global_position = cam_target + _cam_offset(); cam.look_at(cam_target)
	var prompt := ""
	if not busy and step != Step.INTRO:
		if step == Step.PICK and _near(PICKUP_SPOT): prompt = "לקחת"
		elif step == Step.SERVE and customer_ready and _near(PLACE_SPOT): prompt = "להגיש ולגבות"
	ui.set_action(prompt)
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
