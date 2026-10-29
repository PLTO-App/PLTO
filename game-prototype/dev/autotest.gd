extends Node
# Development only: plays the first minute by itself and saves screenshots (godot -- --autotest out=/path).
# Excluded from the exported APK.
var main: Node3D
var out := "/tmp"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	_run()

func shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func walk_to(p: Vector3, limit: float) -> void:
	var t := 0.0
	main.ui.use_override = true
	while t < limit and main.input_toward(p) != Vector2.ZERO:
		main.ui.override_vec = main.input_toward(p)
		await get_tree().process_frame
		t += get_process_delta_time()
	main.ui.override_vec = Vector2.ZERO

func tap(logical: Vector2) -> void:
	var sc := Vector2(get_window().size) / get_viewport().get_visible_rect().size
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new(); e.index = 2; e.pressed = pressed; e.position = logical * sc
		Input.parse_input_event(e); await wait(0.08)

func touch_joystick_test() -> void:
	var sc := Vector2(get_window().size) / get_viewport().get_visible_rect().size
	var e := InputEventScreenTouch.new(); e.index = 1; e.pressed = true; e.position = Vector2(100, 600) * sc; Input.parse_input_event(e)
	await wait(0.2)
	var d := InputEventScreenDrag.new(); d.index = 1; d.position = Vector2(150, 560) * sc; d.relative = Vector2(50, -40) * sc; Input.parse_input_event(d)
	await wait(0.3)
	var v: Vector2 = main.ui.move_vec; var p0: Vector3 = main.player.global_position
	await wait(1.0)
	var moved: float = (main.player.global_position - p0).length()
	print("TEST touch_joystick move_vec=(%.2f, %.2f) moved=%.2f (expect x>0, y>0, moved>0.5)" % [v.x, v.y, moved])
	var u := InputEventScreenTouch.new(); u.index = 1; u.pressed = false; u.position = d.position; Input.parse_input_event(u)
	await wait(0.2); print("TEST touch_release move_vec=", main.ui.move_vec)

func _closeup() -> void:
	await wait(0.8); main._on_card_button(); await wait(0.5)
	main.zoom = 0.22; main.player.rotation.y = -PI * 0.9; await wait(1.0); shot("c0_face_idle")
	main.player.rotation.y = -PI * 0.5; main.zoom = 0.4
	main.ui.use_override = true; main.ui.override_vec = Vector2(1.0, 0.0)
	for i in 6:
		await wait(0.25); shot("c1_walk_%d" % i)
	main.ui.override_vec = Vector2.ZERO; get_tree().quit()

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "landscape=1": get_window().size = Vector2i(1266, 585)
		if a == "closeup=1": _closeup(); return
	await wait(1.2); shot("00_intro")
	await tap(main.ui.card_button.get_global_rect().get_center())
	print("TEST card_tap step=%d (expect 1)" % main.step); await wait(0.5); shot("01_start")
	await touch_joystick_test()
	# collision check: push into the back counters
	await walk_to(Vector3(1.6, 0, 2.7), 6.0)
	main.ui.use_override = true; main.ui.override_vec = Vector2(0.0, 1.0)
	await wait(6.0)
	print("TEST collision_back_counters z=%.2f (expect > -3.0)" % main.player.global_position.z)
	shot("02_at_counters")
	await walk_to(main.PICKUP_SPOT, 20.0); main.ui.override_vec = Vector2.ZERO; await wait(0.5)
	print("TEST near_pickup=%s" % main._near(main.PICKUP_SPOT)); shot("03_prompt")
	await tap(main.ui.action_button.get_global_rect().get_center()); await wait(0.45); shot("04_reach"); await wait(1.2); shot("05_carry")
	print("TEST carrying=%s step=%d" % [main.player.carrying, main.step])
	await walk_to(main.PLACE_SPOT, 25.0); main.ui.override_vec = Vector2.ZERO; await wait(0.5)
	shot("06_place_prompt")
	await tap(main.ui.action_button.get_global_rect().get_center()); await wait(0.4); shot("07_place"); await wait(1.2); shot("07b_placed"); await wait(1.6); shot("08_end")
	print("TEST done step=%d table_ready=%s" % [main.step, main.state.has_flag("table_ready")])
	get_tree().quit()
