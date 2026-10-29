extends Node
# Development only: plays the game by itself through the real interface and saves screenshots.
# Day 1 in the bakery (intro, plan screens, supplier order, serving every customer, summary), the evening and the night,
# then the café is opened (cash and experience are given to get there quickly), a barista is hired, and a day is played in the café.
# godot --path . res://scenes/main.tscn -- --autotest out=/path [landscape=1] [fast=1] [days=N]
# Excluded from the exported APK.
var main: Node3D
var out := "/tmp"
var days := 2
var landscape := false
var errors: Array = []
var inspect := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("fast="): Engine.time_scale = 2.0 * float(a.substr(5))
		if a.begins_with("days="): days = int(a.substr(5))
		if a == "landscape=1": landscape = true
		if a == "inspect=1": inspect = true
	if landscape: get_window().size = Vector2i(1266, 585)
	_run()

func shot(name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func wait_until(cond: Callable, limit := 60.0) -> bool:
	var t := 0.0
	while not cond.call() and t < limit:
		await wait(0.2); t += 0.2
	return cond.call()

func ui() -> GameUi: return main.ui

# Answers every open card with its first choice (or a given one).
func answer_cards(choice := 0, name := "") -> void:
	var n := 0
	while ui().card_dim.visible and n < 12:
		if name != "" and n == 0: await shot(name)
		await wait(0.3); ui().card_choice.emit(choice); n += 1
		await wait(0.4)

func check(label: String, ok: bool, detail := "") -> void:
	print("TEST %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok: errors.append(label)

func _run() -> void:
	await wait(1.2)
	await answer_cards(0, "00_intro")
	await wait_until(func(): return ui().sheet.visible and ui().sheet.screen_id == "today")
	await wait(0.5); await shot("01_today")
	var co: Company = Game.co
	check("the morning checklist is open", ui().sheet.visible)
	# plan screens
	ui().screens.open_plan("bakery"); await wait(0.5)
	for i in 4:
		ui().sheet.tab = i; ui().sheet.refresh(); await wait(0.35); await shot("02_plan_tab%d" % i)
	# a supplier order for tomorrow
	ui().open_screen("orders"); await wait(0.4)
	for bid in co.units: ui().screens.draft["wholesale"] = {bid: co.suggest_order(bid)}
	ui().sheet.refresh(); await wait(0.3); await shot("03_orders")
	await ui().screens._send_orders(ui().sheet)
	check("an order was placed", not co.orders.is_empty())
	for s in ["staff", "finance", "goals", "settings"]:
		ui().open_screen(s); await wait(0.4); await shot("04_%s" % s)
	main._on_building("cafe"); await wait(0.6); await shot("05_building_cafe")
	ui().sheet.close(); main.town_x = -8.0; await wait(1.2); await shot("06_town_pan")
	main.town_x = 0.0
	for d in days:
		await play_day("d%d" % (d + 1))
		if d == 0:
			# fast-forward to the café: experience and cash, open it, and a barista
			co.profile.add_xp(700); co.book("relief", 9000, "", "autotest")
			ui().hud.sync()
			main._on_building("cafe"); await wait(0.6)
			var e := co.open_business("cafe"); check("the café opens", e.is_empty(), Loc.msg(e))
			main._flow("opened", {"biz": "cafe"}); await wait(0.6); await answer_cards(0, "07_cafe_opened")
			await wait(1.5); await shot("08_town_cafe_open")
		await night_to_morning("d%d" % (d + 2))
		if Game.co.contracts.has("minimarket"): print("TEST contract active=%s misses=%d" % [Game.co.contracts["minimarket"]["active"], Game.co.contracts["minimarket"]["misses"]])
		if co.owns("cafe") and co.unit_ready("cafe") and co.staff.is_empty():
			co.hire("yossi", "bakery"); co.worker = "cafe"
			ui().screens.new_morning(); ui().open_screen("today"); await wait(0.5); await shot("09_today_two_businesses")
	check("the ledger matches the cash", co.ledger.balance() == co.profile.cash, "%d vs %d" % [co.ledger.balance(), co.profile.cash])
	var RS := RenderingServer
	print("PERF draw_calls=%d primitives=%d vram_mb=%.1f fps=%d" % [RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, Engine.get_frames_per_second()])
	print("TEST RESULT failures=%d %s" % [errors.size(), str(errors)])
	get_tree().quit()

func play_day(name: String) -> void:
	var co: Company = Game.co
	ui().open_screen("today"); await wait(0.4)
	var cash0 := co.profile.cash
	if inspect: co.inspection_today = co.worker; co.units[co.worker].cleanliness = 40
	ui().screens._open_day(ui().sheet)
	await wait_until(func(): return main.state == "day" and main.runner != null, 20.0)
	await wait(1.0); await shot("%s_10_shop" % name)
	var served := 0; var t := 0.0; var shots := {}
	while main.state == "day" and t < 600.0:
		if ui().card_dim.visible:
			print("TEST %s day card: %s" % [name, ui().card_title.text])
			await answer_cards(0, "%s_inspection" % name if not shots.has("insp") else ""); shots["insp"] = true
		if ui().action_button.visible:
			if not shots.has("act"): shots["act"] = true; await shot("%s_11_action" % name)
			ui().action_pressed.emit(); served += 1
			await wait(0.5)
			if served == 3 and not shots.has("coins"): shots["coins"] = true; await wait(1.4); await shot("%s_12_serving" % name)
		else:
			await wait(0.25)
		if main.runner != null and main.runner.queue.size() >= 3 and not shots.has("queue"): shots["queue"] = true; await shot("%s_13_queue" % name)
		t += 0.25
	print("TEST %s day ended after ~%ds, actions %d" % [name, int(t), served])
	await wait_until(func(): return ui().card_dim.visible or (ui().sheet.visible and ui().sheet.screen_id == "summary"), 30.0)
	await answer_cards(0, "%s_14_goal" % name)
	await wait_until(func(): return ui().sheet.visible and ui().sheet.screen_id == "summary", 20.0)
	var s: Dictionary = co.last_summary
	for bid in s["units"]:
		var u: Dictionary = s["units"][bid]
		print("TEST %s %s served=%d/%d revenue=%d profit=%d walkouts=%d closed=%s" % [name, bid, u["served"], u["customers"], u["revenue"], u["profit"], u["walkouts"], u["closed"]])
	check("%s: customers were served" % name, int(s["units"][co.worker]["served"]) > 0 if s["units"].has(co.worker) else false)
	for i in 3:
		ui().sheet.tab = i; ui().sheet.refresh(); await wait(0.4); await shot("%s_15_summary_%d" % [name, i])
	ui().screens.flow.call("summary_done", {})
	await wait(0.6)
	if ui().sheet.visible and ui().sheet.screen_id == "week":
		await shot("%s_16_week" % name); ui().screens.flow.call("week_done", {}); await wait(0.6)
	await wait(1.0); await shot("%s_17_evening" % name)
	check("%s: the day was saved" % name, int(SaveStore.read(Game.save_path)["company"]["day"]) == co.day)

func night_to_morning(name: String) -> void:
	main._on_cta()
	await wait_until(func(): return main.state == "morning", 20.0)
	await wait(1.0)
	if ui().card_dim.visible: print("TEST %s morning card: %s" % [name, ui().card_title.text])
	await answer_cards(0, "%s_00_event" % name)
	await wait_until(func(): return ui().sheet.visible and ui().sheet.screen_id == "today", 10.0)
	await wait(0.6); await shot("%s_01_morning" % name)
