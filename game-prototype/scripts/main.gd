extends Node3D
# The game: the town in the morning and the evening, and the inside of the business where Noa works during the day.
#   morning:  deliveries and events (cards), the day's checklist and the plans (GameUi + Screens)
#   day:      customers arrive and queue; Noa takes each order and hands it over (one tap does it, or walk with the joystick);
#             staff serve the next ones; the other business runs by itself; sometimes the health inspector comes
#   closing:  the books close (Company.close_day), the summary and, at the end of the week, the weekly report
# The decisions and numbers come from the simulation (Game.co); this script runs the scenes, the people and the camera.

const SERVE_MIN := 12          # minutes one hand-served order takes
const IDLE_MIN := 6            # minutes that pass per idle tick when nobody is waiting
const WAIT_MIN := 3            # minutes per tick while the next customer walks to the counter
const IDLE_TICK := 0.3         # seconds per tick
const CAM_YAW := 0.32
const CAM_H := 7.6
const CAM_D := 8.8
const REACH := 1.5

var town: Town
var shops := {}
var shop: ShopRoom
var player: Player
var cam: Camera3D
var ui: GameUi
var state := "boot"            # boot | morning | day | closing | evening
var runner: DayRunner
var worker := ""
var npcs := {}                 # customer id -> Npc
var staff_npcs: Array = []
var noa_busy := false
var staff_acc := 0.0
var inspected := false
var stopped := false
var town_x := 0.0
var cam_target := Vector3.ZERO
var marker := Node3D.new()
var arrow: MeshInstance3D
var ring: MeshInstance3D
var action_target := Vector3.ZERO
var t := 0.0
var _dragging := false

func _ready() -> void:
	town = Town.new(); add_child(town)
	town.building_tapped.connect(_on_building)
	cam = Camera3D.new(); cam.near = 0.1; cam.far = 260.0; add_child(cam); cam.current = true
	ui = GameUi.new(); add_child(ui)
	ui.screens.flow = _flow
	ui.cta_pressed.connect(_on_cta)
	ui.sheet.closed.connect(func(): _apply_view())
	_build_marker()
	get_viewport().size_changed.connect(_apply_view)
	town.spawn_walkers(Game.content.world["townsfolk"], 7, Game.co.day)
	_apply_view()
	if "--autotest" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://dev/autotest.gd"):
		var at = load("res://dev/autotest.gd").new(); at.main = self; add_child(at)     # development only; not part of the APK
	_boot()

func _boot() -> void:
	var co := Game.co
	town.show_owned(co.units)
	ui.hud.sync()
	_enter_town_now(0.12)
	if not co.flags.has("tut_intro") and co.day == 1:
		await _intro()
	elif Game.migrated_from > 0:
		await ui.ask({"who": "shira", "who_name": Loc.t("npc.shira"), "title": Loc.t("tut.welcome_back"), "body": Loc.t("tut.welcome_back_body"), "choices": [Loc.t("ui.continue")]})
		Game.migrated_from = 0
	morning()

func _intro() -> void:
	for i in 3:
		await ui.ask({"who": "shira", "who_name": Loc.t("npc.shira"), "title": Loc.t("tut.intro%d.title" % (i + 1)), "body": Loc.t("tut.intro%d.body" % (i + 1)),
			"choices": [Loc.t("ui.continue") if i < 2 else Loc.t("tut.lets_go")]})
	Game.co.flags["tut_intro"] = 1

# ================================================================ morning in town
func morning() -> void:
	state = "morning"; stopped = false
	var co := Game.co
	_enter_town_now(0.14)
	if co.morning_day != co.day:
		var rep := co.start_morning()
		Game.save_game()
		if not rep["deliveries"].is_empty(): Game.sfx.play("truck", 1.0, -6.0)
	town.show_owned(co.units)
	ui.screens.new_morning()
	ui.hud.rep_biz = co.worker; ui.hud.sync(); _set_info()
	ui.show_day_ui(false); ui.show_town_bar(true, Loc.t("ui.cta_morning"))
	ui.update_goals_badge()
	for ev in co.pending_events.duplicate():
		await _event_card(ev)
	Game.save_game()
	ui.open_screen("today")
	_apply_view()

func _set_info(clock := "") -> void:
	var co := Game.co
	var txt := Loc.t("ui.info_day", {"day": co.day, "weekday_k": co.weekday_key()})
	if clock != "": txt += " · " + clock
	ui.hud.set_info(txt, co.weather)

func _event_card(ev: Dictionary) -> void:
	var who: String = ev.get("who", "")
	var people: Dictionary = Game.content.world["people"]
	var names: Array = []
	for ch in ev["choices"]:
		var cost := int(ch.get("cost", 0))
		names.append(Loc.t(ch["label_k"]) + ((" (" + Loc.money(cost) + ")") if cost > 0 else ""))
	var spec := {"who": who if people.has(who) else "", "who_name": Loc.t(people[who]["name"]) if people.has(who) else "",
		"title": Loc.t(ev["title_k"], ev.get("p", {})), "body": Loc.t(ev["body_k"], ev.get("p", {})), "choices": names}
	var i := await ui.ask(spec)
	var res := Game.co.resolve_event(ev, i)
	ui.hud.sync()
	var note = res.get("note", {})
	if note is Dictionary and not note.is_empty() and str(note.get("k", "")) != "":
		await ui.ask({"who": spec["who"], "who_name": spec["who_name"], "title": spec["title"], "body": Loc.msg(note), "choices": [Loc.t("ui.continue")]})

func _on_cta() -> void:
	if state == "morning": ui.open_screen("today")
	elif state == "evening": _night()

func _on_building(id: String) -> void:
	if state not in ["morning", "evening"] or ui.card_dim.visible or _dragging: return
	Game.sfx.play("tap")
	ui.open_screen("building", {"building": id})
	town_x = clampf(Town.BUILDINGS.filter(func(b): return b["id"] == id)[0]["x"], Town.MIN_X + 3, Town.MAX_X - 4)

func _flow(action: String, data: Dictionary) -> void:
	var co := Game.co
	match action:
		"open_day":
			var errs := co.commit_day(data["plans"], co.worker)
			if not errs.is_empty(): ui.sheet.note(Loc.msg(errs[0])); return
			ui.sheet.close()
			_run_day()
		"summary_done":
			if not co.last_week.is_empty(): ui.open_screen("week", {"week": co.last_week})
			else: _evening()
		"week_done":
			_evening()
		"opened":
			town.show_owned(co.units); Game.sfx.play("levelup")
			await ui.ask({"who": "shira", "who_name": Loc.t("npc.shira"), "title": Loc.t("tut.cafe_title"), "body": Loc.t("tut.cafe_body"), "choices": [Loc.t("ui.continue")]})
			ui.screens.new_morning()
		"upgraded":
			if shops.has(data["biz"]): _refresh_shop(shops[data["biz"]], data["biz"])
		"reset":
			Game.reset_progress(); get_tree().reload_current_scene()

# ================================================================ evening and night
func _evening() -> void:
	state = "evening"
	ui.sheet.close()
	town.set_time(0.88)
	ui.show_town_bar(true, Loc.t("ui.cta_evening"))
	ui.update_goals_badge(); ui.hud.sync()
	_set_info()
	_apply_view()

func _night() -> void:
	ui.show_town_bar(false)
	var tw := create_tween(); tw.tween_method(town.set_time, 0.88, 1.0, 1.2); await tw.finished
	await ui.fade_out(0.5)
	town.spawn_walkers(Game.content.world["townsfolk"], 7, Game.co.day)
	town.set_time(0.12)
	await ui.fade_in(0.6)
	morning()

# ================================================================ scenes
func _enter_town_now(time01: float) -> void:
	town.visible = true; town.process_mode = Node.PROCESS_MODE_INHERIT
	Game.sfx.play_music("music_day"); Game.sfx.play_ambience("amb_town")
	for bid in shops: shops[bid].visible = false
	if player != null: player.visible = false
	town.set_time(time01)
	marker.visible = false
	_apply_view()

func _get_shop(bid: String) -> ShopRoom:
	if not shops.has(bid):
		var s := ShopRoom.new(); s.build(bid); s.position = Vector3(0, 0, 200.0 + 40.0 * shops.size()); add_child(s); shops[bid] = s
	return shops[bid]

func _refresh_shop(s: ShopRoom, bid: String) -> void:
	var u: Business = Game.co.units[bid]
	s.show_upgrades(u.upgrades); s.show_certificate(Game.co.flags.has("certificate_" + bid))
	var lines: Array = []
	for pid in u.db["products"]: lines.append("%s  %s" % [Loc.t(u.db["products"][pid]["name"]), Loc.money(u.price_today(pid))])
	s.set_menu(lines)
	_show_stock()

func _show_stock() -> void:
	if shop == null or worker == "": return
	var u: Business = Game.co.units[worker]; var st := {}
	for pid in u.db["products"]:
		st[pid] = u.inv.stock(pid) if not u.is_mto(pid) else (runner.available(pid) if runner != null else 0)
	shop.show_stock(st)

func _enter_shop(bid: String) -> void:
	await ui.fade_out(0.35)
	town.visible = false; town.process_mode = Node.PROCESS_MODE_DISABLED
	town.set_time(0.42)      # the shop shares the town's light: daytime inside
	for k in shops: shops[k].visible = false
	shop = _get_shop(bid); shop.visible = true
	worker = bid
	if player == null:
		player = Player.new(); add_child(player)
	player.visible = true; player.reparent(shop, false); player.position = shop.lay["noa_home"]; player.rotation.y = 0.0; player.cam_yaw = CAM_YAW
	player.drop_item()
	for n in staff_npcs: if is_instance_valid(n): n.queue_free()
	staff_npcs = []
	var spots: Array = [shop.lay["staff_spot"], shop.lay["staff_spot"] + Vector3(-1.4, 0, 0)]
	var i := 0
	for s in Game.co.staff_at(bid):
		var d := Game.co.staff_def(s["id"])
		var n := Npc.make({"look": d["look"], "name": d["name"]}); n.role = "staff"; shop.add_child(n)
		n.position = spots[mini(i, spots.size() - 1)]; n.rotation.y = 0.0; n.set_solid(true); staff_npcs.append(n); i += 1
	marker.reparent(shop, false); marker.visible = false
	_refresh_shop(shop, bid)
	cam_target = player.global_position + Vector3(0, 1.0, 0)
	ui.show_town_bar(false); ui.show_day_ui(true); ui.setup_strip(bid); ui.stick_enabled = true
	Game.sfx.play_ambience("amb_shop")
	ui.hud.rep_biz = bid; ui.hud.sync()
	_apply_view()
	await ui.fade_in(0.35)

# ================================================================ the working day
func _run_day() -> void:
	state = "day"; var co := Game.co
	await _enter_shop(co.worker)
	runner = co.runners[worker]
	npcs = {}; noa_busy = false; staff_acc = 0.0; inspected = false
	_apply_slot_events(runner.begin_slot())
	_update_strip()
	if not co.flags.has("tut_day"):
		co.flags["tut_day"] = 1
		ui.show_hint(Loc.t("tut.day_hint"), 6.0)
	elif not co.staff_at(worker).is_empty():
		ui.show_hint(Loc.t("tut.staff_hint", {"n": co.staff_at(worker).size()}), 4.0)
	var guard := 0
	while not runner.finished() and not stopped and guard < 4000:
		guard += 1
		if co.inspection_today == worker and not inspected and runner.slot >= 2:
			await _inspection_visit()
			if runner.closed: break
		var front := runner.front()
		var npc: Npc = npcs.get(front.get("id", -1)) if not front.is_empty() else null
		if npc != null and npc.at_counter and not noa_busy:
			await _serve(front, npc)
			_advance(SERVE_MIN * 100 / int(co.units[worker].db.get("service_pct", 100)))
			continue
		await get_tree().create_timer(IDLE_TICK).timeout
		_advance(IDLE_MIN if runner.queue.is_empty() else WAIT_MIN)
	await _close_day()

func _advance(minutes: int) -> void:
	for e in runner.advance(minutes): _apply_slot_events(e)
	_staff_tick(minutes)
	_update_strip()

func _update_strip() -> void:
	var u: Business = Game.co.units[worker]; var st := {}
	for pid in u.db["products"]: st[pid] = u.inv.stock(pid) if not u.is_mto(pid) else runner.available(pid)
	ui.set_strip(runner.clock_text(), st, runner.queue.size())
	_set_info(runner.clock_text())
	_show_stock()

func _apply_slot_events(e: Dictionary) -> void:
	var first := true
	for c in e.get("arrived", []):
		var npc := Npc.make(c); shop.add_child(npc); npc.position = shop.lay["door"]; npcs[c["id"]] = npc
		if first: Game.sfx.play("bell", 1.0, -6.0); first = false
	for o in e.get("left", []): _walkout(o)
	_reflow()

# Sends every waiting customer to the right place in line. The first one walks to the counter.
func _reflow() -> void:
	var qi := 0
	for i in runner.queue.size():
		var npc: Npc = npcs.get(runner.queue[i]["id"])
		if npc == null or npc.busy: continue
		if npc.q_index == qi: qi += 1; continue
		npc.q_index = qi; npc.at_counter = false; _route(npc, qi); qi += 1

func _route(npc: Npc, i: int) -> void:
	var pts: Array = []
	if npc.position.distance_to(shop.lay["door"]) < 1.0: pts.append(shop.lay["entry"])
	var spots: Array = shop.lay["queue"]
	pts.append(shop.lay["customer_spot"] if i == 0 else spots[mini(i - 1, spots.size() - 1)])
	var ok: bool = await npc.follow(pts)
	if ok and is_instance_valid(npc):
		npc.set_solid(true)
		if i == 0: npc.face_point(shop.lay["serve_spot"]); npc.at_counter = true
		else: npc.face_point(shop.lay["customer_spot"])

func _walkout(o: Dictionary) -> void:
	var npc: Npc = npcs.get(o["customer"]["id"])
	if npc == null: return
	npcs.erase(o["customer"]["id"])
	npc.rig.set_expression("annoyed")
	ui.show_hint(Loc.t("act.walkout", {"name_k": o["customer"].get("name", "")}), 2.5)
	_send_out(npc)

func _send_out(npc: Npc) -> void:
	npc.hide_order(); npc.busy = true
	await npc.follow([shop.lay["entry"], shop.lay["door"]])
	if is_instance_valid(npc): npc.queue_free()

# ---------------------------------------------------------------- Noa serves the customer at the counter
func _serve(c: Dictionary, npc: Npc) -> void:
	noa_busy = true; npc.busy = true
	var u: Business = Game.co.units[worker]
	var pre := runner.preview(c)
	if pre["type"] == "sale":
		var pid: String = pre["product"]; var qty: int = pre["qty"]
		npc.show_order(pid, qty)
		var pname := Loc.t(u.db["products"][pid]["name"]) if qty == 1 else Loc.t(u.db["products"][pid].get("name_pl", u.db["products"][pid]["name"]))
		if pre["substitute"]:
			ui.show_hint(Loc.t("act.substitute", {"wanted_k": u.db["products"][pre["wanted"]]["name"], "name_k": c.get("name", ""), "product": pname}), 3.5)
		elif pre["partial"]:
			ui.show_hint(Loc.t("act.partial", {"n": qty, "product": pname}), 3.0)
		var mto := u.is_mto(pid)
		var act_key := ("act.make" if mto else "act.pick") + ("1" if qty == 1 else "")
		await _do_action(Loc.t(act_key, {"n": qty, "product": pname}), shop.pick_spot(pid))
		await _pick(pid, mto)
		await _do_action(Loc.t("act.serve", {"name_k": c.get("name", "")}), shop.lay["serve_spot"])
		await _hand_over(c, npc, pid)
	else:
		npc.show_order(pre["wanted"], int(c.get("qty", 1)), true); npc.rig.set_expression("think" if pre["type"] == "lost_price" else "sad")
		var wanted_k: String = u.db["products"][pre["wanted"]]["name"]
		ui.show_hint(Loc.t("act.too_expensive", {"name_k": c.get("name", "")}) if pre["type"] == "lost_price" else Loc.t("act.sold_out", {"product_k": wanted_k}), 2.6)
		await get_tree().create_timer(2.0).timeout
		runner.commit(c); npcs.erase(c["id"]); _send_out(npc)
		await get_tree().create_timer(0.4).timeout
	noa_busy = false
	_reflow()

# Shows the action button and waits for it; if Noa is not near the spot, she walks there by herself first.
func _do_action(label: String, spot: Vector3) -> void:
	action_target = shop.to_global(spot)
	ui.set_objective(label); _mark(action_target)
	ui.set_action(label)
	await ui.action_pressed
	ui.set_action(""); ui.set_objective("")
	if not _near(action_target):
		await player.go_to(_path_to(spot))
	marker.visible = false

func _path_to(spot: Vector3) -> Array:
	var here := shop.to_local(player.global_position)
	var pts: Array = []
	# behind the counters is reached around them (Noa usually stays there)
	if spot.z < -0.3 and here.z > 0.3: pts.append(Vector3(-5.0, 0, 0.0)); pts.append(Vector3(-5.0, 0, -1.6))
	pts.append(spot)
	return pts.map(func(p): return shop.to_global(p))

func _near(p: Vector3) -> bool:
	var d := player.global_position - p
	return Vector2(d.x, d.z).length() <= REACH

func _pick(pid: String, mto: bool) -> void:
	player.locked = true
	await player.face_point(action_target + Vector3(0, 0, -1))
	if mto:
		player.rig.set_pose("work"); Game.sfx.play("steam", 1.0, -6.0)
		await get_tree().create_timer(1.1).timeout
		player.rig.set_pose("")
	else:
		player.rig.start_reach(); await player.rig.action_peak
	Game.sfx.play("pickup")
	player.hold(_carry_model(pid))
	player.locked = false

func _carry_model(pid: String) -> String:
	match pid:
		"cappuccino", "americano": return "food_cup"
		"iced": return "food_iced"
		"carrot_cake": return "food_carrot_cake"
		"strawberry_cake": return "food_strawberry_cake"
	return "food_bag"

func _hand_over(c: Dictionary, npc: Npc, pid: String) -> void:
	player.locked = true
	await player.face_point(npc.global_position)
	player.rig.start_reach(); await player.rig.action_peak
	var item := player.drop_item()
	if item != null: item.queue_free()
	Game.sfx.play("place"); Game.sfx.play("register", 1.0, -8.0)
	npc.hide_order(); npc.give(_carry_model(pid)); npc.rig.set_expression("happy"); npc.rig.hop()
	var p := Game.profile
	var before := {"level": p.level, "xp": p.xp, "cash": p.cash, "rep": Game.co.units[worker].reputation}
	ui.hud.hold = true
	var out := runner.commit(c)
	npcs.erase(c["id"])
	var origin := cam.unproject_position(npc.global_position + Vector3(0, 2.7, 0))
	_update_strip()
	player.locked = false
	await ui.fx.play_sale({"profit": int(out.get("revenue", 0)), "reputation": 0, "xp_total": int(out.get("xp", 0))}, origin, before)
	if out.has("addon"): ui.show_hint(Loc.t("act.addon", {"product_k": Game.co.units[worker].db["products"][out["addon"]["product"]]["name"]}), 2.0)
	npc.rig.set_expression("smile")
	_after_purchase(npc, pid)

func _after_purchase(npc: Npc, pid: String) -> void:
	var u: Business = Game.co.units[worker]
	var seat := shop.free_seat(u.upgrades) if (u.is_mto(pid) or worker == "bakery") and randf() < (0.55 if worker == "cafe" else 0.25) else -1
	if seat < 0:
		_send_out(npc); return
	shop.seats_taken[seat] = true
	var s: Array = shop.lay["seats"][seat]
	var ok: bool = await npc.follow([s[0] + Vector3(0, 0, 0.9), s[0]])
	if not ok or not is_instance_valid(npc): shop.seats_taken.erase(seat); return
	npc.sit(s[0], s[1])
	await get_tree().create_timer(randf_range(7.0, 13.0)).timeout
	shop.seats_taken.erase(seat)
	if is_instance_valid(npc):
		npc.stand_up(); _send_out(npc)

# ---------------------------------------------------------------- staff serve the next customers
func _staff_tick(minutes: int) -> void:
	var co := Game.co
	var rate := co.staff_rate(worker) * int(co.units[worker].db.get("service_pct", 100)) / 100
	if rate <= 0 or staff_npcs.is_empty(): return
	staff_acc += float(rate) / 100.0 * float(minutes) / float(co.units[worker].db["slot_minutes"])
	while staff_acc >= 1.0:
		var c := runner.waiting(1)
		if c.is_empty(): break
		staff_acc -= 1.0
		var npc: Npc = npcs.get(c["id"])
		var out := runner.commit(c)
		npcs.erase(c["id"])
		if npc != null: _staff_serve_visual(npc, out)
	staff_acc = minf(staff_acc, 1.0)

func _staff_serve_visual(npc: Npc, out: Dictionary) -> void:
	npc.busy = true
	var st: Npc = staff_npcs[randi() % staff_npcs.size()]
	await npc.follow([shop.lay["staff_customer"]])
	if not is_instance_valid(npc): return
	npc.face_point(shop.to_global(shop.lay["staff_spot"]))
	if is_instance_valid(st):
		st.face_point(npc.global_position); st.rig.start_reach()
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(npc): return
	if out["type"] == "sale":
		npc.give(_carry_model(out["product"])); npc.rig.set_expression("happy")
		ui.fx.float_text(Loc.money_short(int(out["revenue"]), true), cam.unproject_position(npc.global_position + Vector3(0, 2.6, 0)), UiStyle.GOLD, 20)
		Game.sfx.play("coin", 1.2, -10.0)
		ui.hud.sync()
		_after_purchase(npc, out["product"])
	else:
		npc.rig.set_expression("sad"); _send_out(npc)
	_update_strip()

# ---------------------------------------------------------------- the health inspector
func _inspection_visit() -> void:
	inspected = true
	var who: Dictionary = Game.content.world["people"]["inspector"]
	var n := Npc.make({"look": who["look"], "name": who["name"]}); n.role = "visitor"; shop.add_child(n); n.position = shop.lay["door"]
	ui.show_hint(Loc.t("insp.arrives"), 3.0)
	await n.follow([shop.lay["entry"], Vector3(-2.0, 0, 1.8)])
	n.face_point(shop.to_global(Vector3(-2.0, 0, -3.0))); n.rig.set_pose("think")
	await get_tree().create_timer(2.4).timeout
	var res := Game.co.run_inspection(worker)
	var lines: Array = []
	for ch in res["checks"]: lines.append(("✓ " if ch["ok"] else "✗ ") + Loc.t(ch["k"]))
	var verdict := "insp.passed" if res["passed"] else ("insp.warning" if res["fails"] == 1 else ("insp.closed" if res["closed"] else "insp.fined"))
	n.rig.set_pose(""); n.rig.set_expression("smile" if res["passed"] else "annoyed")
	if res["passed"]: Game.sfx.play("levelup"); shop.show_certificate(true)
	await ui.ask({"who": "inspector", "who_name": Loc.t(who["name"]), "title": Loc.t("insp.result_title"), "body": "\n".join(lines) + "\n\n" + Loc.t(verdict, {"amount_m": res["fine"]}),
		"choices": [Loc.t("ui.continue")]})
	ui.hud.sync()
	_send_out(n)
	if res["closed"]:
		runner.closed = true
		for c in runner.queue.duplicate():
			runner.queue.erase(c); runner.outcomes.append({"type": "walkout", "customer": c, "waited": 0})
			var np: Npc = npcs.get(c["id"])
			if np != null: npcs.erase(c["id"]); _send_out(np)
		runner.slot = runner.slots

# ---------------------------------------------------------------- closing
func _close_day() -> void:
	state = "closing"; ui.set_action(""); ui.set_objective(""); marker.visible = false; ui.stick_enabled = false
	ui.show_hint(Loc.t("act.closing"), 2.0)
	await get_tree().create_timer(1.0).timeout
	var co := Game.co
	var p := co.profile
	var before := {"level": p.level, "xp": p.xp, "cash": p.cash, "rep": co.units[worker].reputation}
	ui.hud.hold = true
	var s := co.close_day()
	Game.save_game()
	await ui.fx.play_xp(p.xp - int(before["xp"]), before)
	for n in npcs.values(): if is_instance_valid(n): n.queue_free()
	npcs = {}
	await ui.fade_out(0.4)
	runner = null
	_enter_town_now(0.82)
	ui.show_day_ui(false); ui.hud.rep_biz = co.worker; ui.hud.sync(); _set_info()
	await ui.fade_in(0.4)
	for g in s.get("goals", []):
		Game.sfx.play("levelup")
		await ui.ask({"who": "shira", "who_name": Loc.t("npc.shira"), "title": Loc.t("ui.goal_done"), "body": Loc.t(g["name"]) + "\n" + Loc.t("goal.reward_xp", {"n": g["xp"]}) + ((" · " + Loc.money(int(g["cash"]), true)) if int(g["cash"]) > 0 else ""),
			"choices": [Loc.t("ui.continue")]})
	state = "evening"
	ui.open_screen("summary", {"summary": s})
	_apply_view()

# ================================================================ camera and view
func _build_marker() -> void:
	var gold := StandardMaterial3D.new(); gold.albedo_color = UiStyle.GOLD; gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.28; cone.height = 0.55; cone.radial_segments = 16
	arrow = MeshInstance3D.new(); arrow.mesh = cone; arrow.material_override = gold; arrow.rotation.z = PI
	var tor := TorusMesh.new(); tor.inner_radius = 0.9; tor.outer_radius = 1.05; tor.rings = 32; tor.ring_segments = 6
	var rm := StandardMaterial3D.new(); rm.albedo_color = Color(1.0, 0.76, 0.3, 0.85); rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring = MeshInstance3D.new(); ring.mesh = tor; ring.material_override = rm; ring.scale = Vector3(1, 0.05, 1)
	marker.add_child(arrow); marker.add_child(ring); marker.visible = false; add_child(marker)

func _mark(at: Vector3) -> void:
	marker.visible = true; ring.global_position = at + Vector3(0, 0.07, 0); arrow.set_meta("base", at + Vector3(0, 2.6, 0)); arrow.global_position = at + Vector3(0, 2.6, 0)

# The orientation comes from the window itself (not from the scaled viewport, which depends on the orientation chosen).
func _portrait() -> bool:
	var ws := get_window().size
	return ws.y > ws.x

func _apply_view() -> void:
	var portrait := _portrait()
	var win := get_window()
	var base := Vector2(390, 844) if portrait else Vector2(844, 390)
	win.content_scale_size = Vector2i(base)
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	# A phone screen is scaled by its short side (390 points wide in portrait, 390 high in landscape), so buttons and text keep their
	# size on short 16:9 screens too, where fitting the whole 390x844 would shrink everything. Near-square screens (tablets) would get
	# too little room that way, so they keep the plain fit.
	var ws := Vector2(win.size)
	var long_ratio := maxf(ws.x, ws.y) / maxf(1.0, minf(ws.x, ws.y))
	var factor := 1.0
	if long_ratio >= 1.74 and ws.x > 0.0 and ws.y > 0.0:
		var fit := minf(ws.x / base.x, ws.y / base.y)
		factor = (minf(ws.x, ws.y) / 390.0) / fit
	if not is_equal_approx(win.content_scale_factor, factor): win.content_scale_factor = factor
	cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	if state == "day" or state == "closing":
		cam.fov = 50.0 if portrait else 36.0
	else:
		cam.fov = 46.0 if portrait else 34.0

func _unhandled_input(e: InputEvent) -> void:
	if state not in ["morning", "evening"] or ui.card_dim.visible: return
	if e is InputEventScreenDrag:
		var d := (e as InputEventScreenDrag).relative
		if absf(d.x) > 2.0: _dragging = true
		town_x = clampf(town_x - d.x * 0.045, Town.MIN_X + 3, Town.MAX_X - 4)
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not DisplayServer.is_touchscreen_available():
		var d2 := (e as InputEventMouseMotion).relative
		if absf(d2.x) > 2.0: _dragging = true
		town_x = clampf(town_x - d2.x * 0.045, Town.MIN_X + 3, Town.MAX_X - 4)
	elif (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed) or (e is InputEventMouseButton and not (e as InputEventMouseButton).pressed):
		await get_tree().process_frame
		_dragging = false

func _process(delta: float) -> void:
	t += delta
	var portrait := _portrait()
	if state in ["day", "closing"] and player != null and player.visible:
		player.input_vec = ui.current_move() if not noa_busy or not player.locked else Vector2.ZERO
		cam_target = cam_target.lerp(player.global_position + Vector3(0, 1.0, 0), 1.0 - exp(-6.0 * delta))
		var off := Vector3(sin(CAM_YAW) * CAM_D, CAM_H, cos(CAM_YAW) * CAM_D) * (0.95 if portrait else 0.82)
		cam.global_position = cam_target + off; cam.look_at(cam_target)
		cam.v_offset = 0.0
	else:
		var want := Town.camera_pose(town_x, portrait)
		cam.global_transform = cam.global_transform.interpolate_with(want, 1.0 - exp(-5.0 * delta))
		cam.v_offset = lerpf(cam.v_offset, -3.2 if (ui.sheet.visible and portrait) else 0.0, 1.0 - exp(-6.0 * delta))
	if marker.visible:
		var base: Vector3 = arrow.get_meta("base", Vector3.ZERO)
		arrow.global_position = base + Vector3(0, 0.15 * sin(t * 4.0), 0)
		ring.scale = Vector3(1, 0.05, 1) * (1.0 + 0.05 * sin(t * 4.0))
