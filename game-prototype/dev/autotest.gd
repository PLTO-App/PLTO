extends Node
# Development only: plays the first sale by itself and saves screenshots (godot -- --autotest out=/path).
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

func tap(logical: Vector2) -> void:
	var sc := Vector2(get_window().size) / get_viewport().get_visible_rect().size
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new(); e.index = 2; e.pressed = pressed; e.position = logical * sc
		Input.parse_input_event(e); await wait(0.08)

func walk_to(p: Vector3, limit: float) -> void:
	var t := 0.0
	main.ui.use_override = true
	while t < limit and main.input_toward(p) != Vector2.ZERO:
		main.ui.override_vec = main.input_toward(p)
		await get_tree().process_frame
		t += get_process_delta_time()
	main.ui.override_vec = Vector2.ZERO

func _closeup() -> void:
	await wait(0.8); main._on_card_button(); await wait(6.0)
	main.player.position = Vector3(2.2, 0, 1.3); main.player.rotation.y = -PI * 0.75; main.zoom = 0.24; await wait(1.2); shot("k0_both")
	main.customer.rig.set_expression("surprised"); await wait(0.5); shot("k1_surprised")
	main.customer.rig.set_expression("happy"); main.player.rig.set_expression("happy"); await wait(0.5); shot("k2_happy")
	main.player.position = Vector3(3.3, 0, 3.2); main.player.rotation.y = PI * 0.9; await wait(1.0); shot("k3_noa_front")
	get_tree().quit()

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "landscape=1": get_window().size = Vector2i(1266, 585)
		if a == "closeup=1": _closeup(); return
	await wait(1.0); shot("00_intro")
	await tap(main.ui.card_button.get_global_rect().get_center())
	await wait(0.6); shot("01_start")
	print("TEST start step=%d cash=%d level=%d" % [main.step, Game.profile.cash, Game.profile.level])
	await wait(3.0); shot("02_customer_arriving")
	await walk_to(main.PICKUP_SPOT, 20.0); main.ui.override_vec = Vector2.ZERO; await wait(0.4)
	shot("03_prompt")
	await tap(main.ui.action_button.get_global_rect().get_center()); await wait(1.5); shot("04_carry")
	print("TEST carrying=%s step=%d customer_ready=%s" % [main.player.carrying, main.step, main.customer_ready])
	await walk_to(main.PLACE_SPOT, 25.0); main.ui.override_vec = Vector2.ZERO; await wait(0.4)
	shot("05_serve_prompt")
	await tap(main.ui.action_button.get_global_rect().get_center()); await wait(0.5); shot("06_serve")
	await wait(1.4); shot("07_coins")
	await wait(0.5); shot("07b_coins")
	await wait(1.6); shot("08_xp")
	await wait(1.2); shot("09_levelup")
	await wait(2.6); shot("10_card")
	var p := Game.profile
	print("TEST after_sale cash=%d xp=%d level=%d rep=%d sales=%d" % [p.cash, p.xp, p.level, p.reputation, p.sales_count])
	var hd: Hud = main.ui.hud
	print("TEST hud_matches_profile=%s (shown cash=%d rep=%d level=%d; profile cash=%d rep=%d level=%d)" % [hd.shown_cash == p.cash and hd.shown_rep == p.reputation and hd.shown_level == p.level, hd.shown_cash, hd.shown_rep, hd.shown_level, p.cash, p.reputation, p.level])
	var saved := SaveStore.read(Game.save_path)
	print("TEST saved cash=%d level=%d" % [int(saved["profile"]["cash"]), int(saved["profile"]["level"])])
	await tap(main.ui.card_button.get_global_rect().get_center()); await wait(4.5); shot("11_next_customer")
	print("TEST next step=%d product=%s" % [main.step, main.product_id])
	await walk_to(main.PICKUP_SPOT, 20.0); main.ui.override_vec = Vector2.ZERO; await wait(0.3)
	print("TEST second_pick_prompt visible=%s near=%s pos=%s busy=%s step=%d" % [main.ui.action_button.visible, main._near(main.PICKUP_SPOT), main.player.global_position, main.busy, main.step])
	await tap(main.ui.action_button.get_global_rect().get_center()); await wait(1.5)
	print("TEST second_pick carrying=%s step=%d" % [main.player.carrying, main.step])
	await walk_to(main.PLACE_SPOT, 25.0); main.ui.override_vec = Vector2.ZERO
	var guard := 0.0
	while not main.customer_ready and guard < 20.0:
		await wait(0.25); guard += 0.25
	await wait(0.4)
	await tap(main.ui.action_button.get_global_rect().get_center()); await wait(7.0); shot("12_second_sale")
	print("TEST second_sale cash=%d sales=%d (expect cash 275 = 150 + 125, sales 2)" % [p.cash, p.sales_count])
	print("TEST hud_after_second=%s" % (hd.shown_cash == p.cash))
	var RS := RenderingServer
	print("PERF draw_calls=%d primitives=%d objects=%d vram_mb=%.1f (software renderer: counts are exact, timings are not)" % [RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	get_tree().quit()
