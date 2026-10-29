extends Node
# Development only: plays two working days by itself (morning planner, customers, closing summary) and saves screenshots.
# godot -- --autotest out=/path [landscape=1] [fast=1]. Excluded from the exported APK.
var main: Node3D
var out := "/tmp"
var shots := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a == "fast=1": Engine.time_scale = 2.0
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

func tap_node(c: Control) -> void:
	await tap(c.get_global_rect().get_center())

func walk_to(p: Vector3, limit: float) -> void:
	var t := 0.0
	main.ui.use_override = true
	while t < limit and main.input_toward(p) != Vector2.ZERO:
		main.ui.override_vec = main.input_toward(p)
		await get_tree().process_frame
		t += get_process_delta_time()
	main.ui.override_vec = Vector2.ZERO

# Fills the planner by calling the same methods the buttons call, then walks through every page.
func wait_until(cond: Callable, limit := 30.0) -> bool:
	var t := 0.0
	while not cond.call() and t < limit:
		await wait(0.2); t += 0.2
	return cond.call()

func plan_morning(name: String, bake: Dictionary, marketing := "none") -> void:
	var m: ManagePanel = main.ui.manage
	await wait_until(func(): return m.visible and m.mode == "planner")
	await wait(0.6); shot("%s_p1_status" % name)
	for pid in bake: m.plan["bake"][pid] = bake[pid]
	m.plan["marketing"] = marketing
	m._fill_missing()
	for i in 5:
		await tap_node(m.next_b); await wait(0.4); shot("%s_p%d" % [name, i + 2])
		print("TEST %s plan errors=%s buy=%s bake=%s units=%s" % [name, str(Game.biz.validate_plan(m.plan)), m.plan["buy"], m.plan["bake"], {"base": Game.biz.inv.units("base"), "dairy": Game.biz.inv.units("dairy"), "sweet": Game.biz.inv.units("sweet")}])
	await tap_node(m.next_b); await wait(0.5)

func play_day(name: String) -> void:
	var guard := 0.0; var queue_shot := false; var sale_shot := false
	while main.state == main.State.DAY and guard < 900.0:
		var dt := 0.25
		if main.step == main.Step.PICK and not main.busy:
			await walk_to(main.PICKUP_SPOT, 25.0); main.ui.override_vec = Vector2.ZERO; await wait(0.3)
			await tap_node(main.ui.action_button); await wait(1.6)
		elif main.step == main.Step.SERVE and not main.busy:
			await walk_to(main.PLACE_SPOT, 25.0); main.ui.override_vec = Vector2.ZERO; await wait(0.3)
			if not queue_shot: shot("%s_serve_prompt" % name)
			await tap_node(main.ui.action_button); await wait(1.9)
			if not sale_shot: shot("%s_coins" % name); sale_shot = true
		else:
			await wait(dt)
		if main.runner != null and main.runner.queue.size() >= 2 and not queue_shot: queue_shot = true; shot("%s_queue" % name)
		guard += dt
	print("TEST %s day ended after ~%ds state=%d" % [name, int(guard), main.state])

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "landscape=1": get_window().size = Vector2i(1266, 585)
	await wait(1.0); shot("00_intro")
	await tap_node(main.ui.card_button)
	var start_cash := Game.profile.cash
	await plan_morning("d1", {"croissant": 5, "carrot_cake": 1, "strawberry_cake": 1})
	print("TEST d1 started state=%d cash=%d customers=%d" % [main.state, Game.profile.cash, main.runner.customers.size()])
	await play_day("d1")
	await wait_until(func(): return main.ui.manage.visible and main.ui.manage.mode == "summary")
	await wait(0.4)
	var s: Dictionary = Game.biz.last_summary
	print("TEST d1 summary revenue=%d profit=%d served=%d/%d lostP=%d lostS=%d walk=%d cash=%d rep=%d level=%d" % [s["revenue"], s["profit"], s["served"], s["customers"], s["lost_price"], s["lost_stock"], s["walkouts"], Game.profile.cash, Game.profile.reputation, Game.profile.level])
	print("TEST ledger_reconciles=%s" % (start_cash + Game.biz.ledger.total() == Game.profile.cash))
	shot("d1_summary_p1")
	await tap_node(main.ui.manage.next_b); await wait(0.4); shot("d1_summary_p2")
	await tap_node(main.ui.manage.next_b)
	await wait_until(func(): return main.state == main.State.PLANNING)
	print("TEST day2 morning state=%d day=%d" % [main.state, Game.biz.day])
	var saved := SaveStore.read(Game.save_path)
	print("TEST saved day=%d cash=%d" % [int(saved["business"]["day"]), int(saved["business"]["profile"]["cash"])])
	# upgrades screen
	var m: ManagePanel = main.ui.manage
	await wait(0.3); m.open_upgrades(Game.biz); await wait(0.4); shot("d2_upgrades"); m.mode = "planner"; m._render()
	await plan_morning("d2", {"croissant": 6, "carrot_cake": 2, "strawberry_cake": 1}, "social_post")
	await play_day("d2")
	await wait_until(func(): return main.ui.manage.visible and main.ui.manage.mode == "summary")
	await wait(0.4)
	s = Game.biz.last_summary
	print("TEST d2 summary revenue=%d profit=%d served=%d/%d cash=%d rep=%d level=%d" % [s["revenue"], s["profit"], s["served"], s["customers"], Game.profile.cash, Game.profile.reputation, Game.profile.level])
	print("TEST ledger_reconciles_2=%s" % (start_cash + Game.biz.ledger.total() == Game.profile.cash))
	shot("d2_summary")
	var RS := RenderingServer
	print("PERF draw_calls=%d primitives=%d vram_mb=%.1f" % [RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	get_tree().quit()
