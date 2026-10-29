extends Node3D
# The bakery day. Each morning the owner plans (ManagePanel), then customers arrive and Noa serves them by hand in the 3D shop, and at the
# close the numbers are shown. The decisions and results come from the business simulation (Game.biz); this script runs the scene and the UI.

enum Step { IDLE, PICK, SERVE }
enum State { INTRO, PLANNING, DAY, CLOSING }

const CAM_YAW := 0.32
const CAM_H := 7.6
const CAM_D := 8.8
const PANEL_V_OFFSET := -2.1                   # shifts the view up while a sheet covers the lower part of a portrait screen
const SPAWN := Vector3(0.6, 0, 2.7)
const DOOR := Vector3(1.8, 0, 8.6)
const LANE_FRONT := Vector3(1.6, 0, 4.2)
const LANE_MID := Vector3(1.6, 0, 3.6)
const LANE_BACK := Vector3(1.6, 0, 0.4)
const CUSTOMER_SPOT := Vector3(3.7, 0, 0.0)    # behind the table, facing Noa and the camera
const QUEUE_SPOTS := [Vector3(0.6, 0, 3.9), Vector3(-0.2, 0, 3.9), Vector3(-1.0, 0, 3.9), Vector3(-1.8, 0, 3.9), Vector3(-2.6, 0, 3.9)]
const PICKUP_SPOT := Vector3(-3.1, 0, 0.8)     # in front of the display counter
const PICKUP_AT := Vector3(-3.2, 1.3, -0.4)
const PLACE_SPOT := Vector3(2.3, 0, 1.6)       # next to the customers' table
const TABLE_AT := Vector3(3.2, 1.17, 1.9)
const REACH := 1.7

signal front_done

var room: BakeryRoom
var player: Player
var cam: Camera3D
var ui: TouchUi
var state: int = State.INTRO
var step: int = Step.IDLE
var busy := false
var runner: DayRunner
var npcs := {}                                  # customer id -> Npc
var front_npc: Npc = null
var front_pre := {}
var product_id := ""
var product: Dictionary = {}
var carried: Node3D = null
var marker := Node3D.new()
var arrow: MeshInstance3D
var ring: MeshInstance3D
var cam_target := Vector3.ZERO
var zoom := 0.86
var panel_shift := 0.0
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
	ui.manage.plan_ready.connect(_on_plan_ready)
	get_viewport().size_changed.connect(_apply_view)
	_apply_view()
	cam_target = player.position + Vector3(0, 1.0, 0)
	cam.global_position = cam_target + _cam_offset(); cam.look_at(cam_target)
	player.cam_yaw = CAM_YAW
	ui.hud.sync()
	var biz := Game.biz
	if Game.has_progress():
		ui.show_card({"title": "המאפייה של נועה", "body": "יום %d מחכה. בקופה: %s." % [biz.day, UiMoney.fmt(biz.profile.cash)], "button": "ממשיכים", "secondary": "להתחיל מאפס"})
	else:
		ui.show_card({"title": "היום הראשון במאפייה של נועה", "body": "בבוקר מחליטים מה לאפות, כמה לקנות ובכמה למכור. במהלך היום משרתים לקוחות, ובסגירה רואים מה קרה ולמה.", "button": "מתחילים"})
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

func _panel_shift(on: bool) -> void:
	create_tween().tween_property(self, "panel_shift", 1.0 if on else 0.0, 0.35)

func _mark(spot: Vector3, above: Vector3) -> void:
	marker.visible = true; ring.global_position = spot + Vector3(0, 0.07, 0); arrow.set_meta("base", above); arrow.global_position = above

func _near(p: Vector3) -> bool:
	var d := player.global_position - p
	return Vector2(d.x, d.z).length() <= REACH

# ---------------------------------------------------------------- the morning
func _on_card_button() -> void:
	ui.hide_card()
	if state == State.INTRO:
		ui.show_hint("גוררים באצבע בצד שמאל כדי ללכת", 6.0)
		_start_morning()

func _on_card_secondary() -> void:
	Game.reset_progress(); get_tree().reload_current_scene()

func _start_morning() -> void:
	state = State.PLANNING; step = Step.IDLE
	var relief := Game.biz.morning_relief()
	ui.hud.sync(); ui.show_day_strip(false); ui.set_objective(""); marker.visible = false
	_panel_shift(true)
	if relief > 0: ui.show_hint("הקופה כמעט ריקה, והמשפחה עזרה ב-%s כדי להמשיך." % UiMoney.fmt(relief), 5.0)
	ui.manage.open_planner(Game.biz)

func _on_plan_ready(plan: Dictionary) -> void:
	var errs := Game.biz.commit_plan(plan)
	if not errs.is_empty():
		ui.manage.open_planner(Game.biz); ui.manage.note_l.text = errs[0]; return
	_panel_shift(false)
	_run_day()

# ---------------------------------------------------------------- the working day
func _stock_now() -> Dictionary:
	var d := {}
	for pid in Game.business()["products"]: d[pid] = Game.biz.inv.stock(pid)
	return d

func _update_strip() -> void:
	ui.set_day_strip("%s · %s" % [Game.biz.weekday_name(), runner.clock_text()], _stock_now(), runner.queue.size())

func _run_day() -> void:
	state = State.DAY; npcs = {}
	runner = Game.biz.begin_day()
	ui.show_day_strip(true); _update_strip()
	ui.show_hint("לקוחות מגיעים. מי שמחכה יותר מדי עלול לעזוב.", 4.0)
	while not runner.finished():
		var ev := runner.begin_slot()
		var first := true
		for c in ev["arrived"]:
			_spawn_customer(c)
			if first: Game.sfx.play("arrive"); first = false
		for o in ev["left"]: _customer_walkout(o)
		_reflow_queue(); _update_strip()
		if runner.queue.is_empty():
			runner.end_slot(); await get_tree().create_timer(0.25).timeout; continue
		await _serve_front()
		runner.end_slot()
	await _close_day()

func _spawn_customer(c: Dictionary) -> void:
	var npc := Npc.make(c); npc.position = DOOR; room.add_child(npc); npcs[c["id"]] = npc

# Sends every waiting customer to the right place in line. The first one walks to the counter.
func _reflow_queue() -> void:
	for i in runner.queue.size():
		var npc: Npc = npcs.get(runner.queue[i]["id"])
		if npc == null or npc.q_index == i: continue
		npc.q_index = i; npc.at_counter = false; _route(npc, i)

func _route(npc: Npc, i: int) -> void:
	var pts: Array = [LANE_FRONT] if npc.position.z > 6.0 else []
	if i == 0: pts += [LANE_MID, LANE_BACK, CUSTOMER_SPOT]
	else: pts += [QUEUE_SPOTS[mini(i - 1, QUEUE_SPOTS.size() - 1)]]
	var ok: bool = await npc.follow(pts)
	if ok and is_instance_valid(npc):
		npc.set_solid(true)
		if i == 0: npc.face_point(PLACE_SPOT); npc.at_counter = true
		else: npc.face_point(Vector3(1.6, 0, 1.0))

func _customer_walkout(o: Dictionary) -> void:
	var npc: Npc = npcs.get(o["customer"]["id"])
	if npc == null: return
	npcs.erase(o["customer"]["id"])
	npc.rig.set_expression("neutral")
	ui.show_hint("ל%s נמאס לחכות." % o["customer"]["name"], 2.5)
	_send_out(npc)

func _send_out(npc: Npc) -> void:
	npc.hide_order(); npc.set_solid(false)
	await npc.follow([LANE_MID, LANE_FRONT, DOOR])
	if is_instance_valid(npc): npc.queue_free()

func _serve_front() -> void:
	var c := runner.front(); var npc: Npc = npcs.get(c["id"])
	front_npc = npc
	while is_instance_valid(npc) and not npc.at_counter: await get_tree().process_frame
	front_pre = runner.preview_front()
	var db := Game.business()
	if front_pre["type"] == "sale":
		product_id = front_pre["product"]; product = db["products"][product_id]
		npc.show_order("res://assets/ui/%s.png" % product["icon"])
		if front_pre["substitute"]:
			ui.show_hint("אזל %s. מציעים ל%s את %s." % [db["products"][front_pre["wanted"]]["name"], c["name"], product["name"]], 3.5)
		step = Step.PICK
		ui.set_objective("לקחת %s מהדלפק" % product["name"])
		_mark(PICKUP_SPOT, PICKUP_AT + Vector3(0, 0.9, 0))
		await front_done
	else:
		var wanted: Dictionary = db["products"][front_pre["wanted"]]
		npc.show_order("res://assets/ui/%s.png" % wanted["icon"]); npc.rig.set_expression("think")
		ui.show_hint(("%s: זה יקר לי." % c["name"]) if front_pre["type"] == "lost_price" else "אזל המלאי של %s." % wanted["name"], 2.4)
		ui.set_objective("")
		await get_tree().create_timer(2.2).timeout
		runner.commit_front(); npc.rig.set_expression("neutral"); npcs.erase(c["id"])
		_update_strip(); _send_out(npc)
		await get_tree().create_timer(0.8).timeout

func _on_action() -> void:
	if busy: return
	if step == Step.PICK and _near(PICKUP_SPOT): _pick()
	elif step == Step.SERVE and _near(PLACE_SPOT): _serve()

func _pick() -> void:
	busy = true; player.locked = true; ui.set_action(""); marker.visible = false
	await player.face_point(PICKUP_AT)
	player.rig.start_reach()
	await player.rig.action_peak
	Game.sfx.play("pickup")
	carried = room.instance_model(product["model"], float(product["scale_pct"]) / 100.0)
	player.rig.carry_anchor.add_child(carried); carried.position = Vector3(0, -0.08, 0)
	player.carrying = true
	await player.rig.action_done
	player.locked = false; busy = false; step = Step.SERVE
	ui.set_objective("להגיש ל%s" % front_npc.data["name"])
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
	var npc := front_npc
	npc.hide_order(); npc.rig.set_expression("happy"); npc.rig.hop()
	await player.rig.action_done
	player.locked = false
	var p := Game.profile
	var before := {"level": p.level, "xp": p.xp, "cash": p.cash, "rep": p.reputation}
	ui.hud.hold = true
	var out := runner.commit_front()
	npcs.erase(npc.data["id"])
	var origin := cam.unproject_position(npc.global_position + Vector3(0, 2.7, 0))
	_update_strip()
	await get_tree().create_timer(0.3).timeout
	await ui.fx.play_sale({"profit": out["price"], "reputation": 0, "xp_total": out["xp"]}, origin, before)
	var cake := carried; carried = null
	if is_instance_valid(cake):
		var tw := create_tween(); tw.tween_property(cake, "scale", Vector3.ZERO, 0.4).set_delay(0.4); tw.tween_callback(cake.queue_free)
	npc.rig.set_expression("smile"); _send_out(npc)
	step = Step.IDLE; busy = false
	front_done.emit()

# ---------------------------------------------------------------- closing
func _close_day() -> void:
	state = State.CLOSING; step = Step.IDLE
	ui.set_objective(""); marker.visible = false; ui.show_day_strip(false)
	await get_tree().create_timer(0.6).timeout
	var p := Game.profile
	var before := {"level": p.level, "xp": p.xp, "cash": p.cash, "rep": p.reputation}
	ui.hud.hold = true
	var s := Game.biz.close_day(runner)
	Game.save_game()
	await ui.fx.play_xp(s["xp_bonus"], before)
	_panel_shift(true)
	ui.manage.open_summary(Game.biz, s)
	await ui.manage.summary_done
	_start_morning()

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	t += delta
	player.input_vec = ui.current_move() if state == State.DAY else Vector2.ZERO
	cam_target = cam_target.lerp(player.global_position + Vector3(0, 1.0, 0), 1.0 - exp(-6.0 * delta))
	cam.global_position = cam_target + _cam_offset(); cam.look_at(cam_target)
	var portrait := get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x
	cam.v_offset = panel_shift * PANEL_V_OFFSET if portrait else 0.0
	var prompt := ""
	if not busy and state == State.DAY:
		if step == Step.PICK and _near(PICKUP_SPOT): prompt = "לקחת"
		elif step == Step.SERVE and _near(PLACE_SPOT): prompt = "להגיש ולגבות"
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
