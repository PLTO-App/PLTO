extends Node
# Development only: a layout audit of the real interface at many phone sizes, portrait and landscape.
# It builds a rich company (both businesses, staff, loan, upgrades, a contract), opens every screen, tab and card at every window
# size and checks, from the live node tree: controls outside the screen, content cut on the side of a scroll area, buttons covered by
# another control, overlapping bars, touch targets that are too small, text that is too small, and a sheet with almost no room to scroll.
# godot --path . res://dev/layout_audit.tscn -- out=/path [sizes=360x640,844x390] [shots=all|flagged|none] [only=scenario,...]
# Excluded from the exported APK.

const SIZES := [
	[320, 568], [360, 640], [360, 740], [360, 800], [375, 667], [390, 844], [393, 873], [412, 915], [430, 932], [768, 1024],
	[568, 320], [640, 360], [740, 360], [800, 360], [844, 390], [915, 412], [932, 430], [1024, 768],
]
const MIN_TOUCH := 40.0        # physical points (the guideline is 44 to 48)
const MIN_TEXT := 9.0

var main: Node3D
var out := "/tmp"
var shots_mode := "flagged"
var only: Array = []
var sizes: Array = SIZES.duplicate()
var findings: Array = []
var counts := {}
var summary: Dictionary
var week: Dictionary
var vp := Vector2.ZERO
var scale_px := 1.0
var cur_size := ""
var cur_scn := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("shots="): shots_mode = a.substr(6)
		if a.begins_with("only="): only = a.substr(5).split(",")
		if a.begins_with("sizes="):
			sizes = []
			for s in a.substr(6).split(","):
				var p := s.split("x"); sizes.append([int(p[0]), int(p[1])])
	DirAccess.make_dir_recursive_absolute(out)
	Game.save_path = "user://layout_audit_save.json"; Game.test_mode = true
	SaveStore.erase(Game.save_path)
	_rich_company()
	main = load("res://scenes/main.tscn").instantiate(); add_child(main)
	_run()

# ---------------------------------------------------------------- a company with everything switched on
func _rich_company() -> void:
	var co: Company = Game.co
	co.new_game(777)
	co.profile.add_xp(9000); co.book("relief", 60000, "", "audit")
	var days_target := 16
	var last_week := {}
	var last_s := {}
	while co.day <= days_target:
		var rep := co.start_morning()
		for ev in rep["events"].duplicate(): co.resolve_event(ev, SimPolicies.choose(co, ev, {"contract": true}))
		if not co.services.has("accountant"): co.subscribe("accountant", true)
		if not co.owns("cafe") and co.can_open("cafe").is_empty(): co.open_business("cafe")
		if co.owns("cafe") and co.staff.is_empty():
			co.hire("yossi", "cafe")
			if not co.loan_open("large"): co.take_loan("large")
		if co.day == 10:
			for bid in co.units:
				for uid in co.units[bid].db["upgrades"]:
					if not co.units[bid].upgrades.has(uid): co.buy_upgrade(bid, uid)
		var plans := {}
		for bid in co.units:
			if co.unit_ready(bid): plans[bid] = SimPolicies.plan_for(co, bid, {"order_ahead": true})
		if co.commit_day(plans, "bakery").is_empty():
			var s := co.close_day()
			last_s = s
			if not co.last_week.is_empty(): last_week = co.last_week
		else:
			co.close_day()
	summary = last_s; week = last_week if not last_week.is_empty() else co.last_week
	co.flags["tut_intro"] = 1; co.flags["tut_day"] = 1
	co.start_morning(); co.pending_events = []
	co.worker = "bakery"
	Game.save_game()
	print("AUDIT company: day %d level %d cash %d units %s staff %d loans %d week_report %s" % [co.day, co.level(), co.profile.cash, str(co.units.keys()), co.staff.size(), co.loans.size(), str(not week.is_empty())])

func ui() -> GameUi: return main.ui

func wait_frames(n := 3) -> void:
	for i in n: await get_tree().process_frame

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while ui().card_dim.visible: ui().card_choice.emit(0); await wait_frames(4)
	await _test_back_button()
	for sz in sizes:
		cur_size = "%dx%d" % [sz[0], sz[1]]
		get_window().size = Vector2i(sz[0], sz[1])
		await wait_frames(6)
		vp = get_viewport().get_visible_rect().size
		scale_px = float(get_window().size.x) / vp.x
		print("AUDIT size %s window %s viewport %dx%d scale %.3f aspect %d base %s" % [cur_size, str(get_window().size), vp.x, vp.y, scale_px, get_window().content_scale_aspect, str(get_window().content_scale_size)])
		await _scenarios()
	await _rotation_tests()
	_report()
	get_tree().quit()

# Turning the phone with something open: the layout must follow, with nothing cut or covered.
func _set_size(w: int, h: int) -> void:
	get_window().size = Vector2i(w, h)
	await wait_frames(8)
	vp = get_viewport().get_visible_rect().size
	scale_px = float(get_window().size.x) / vp.x

func _rotation_tests() -> void:
	var s := ui()
	var pairs := [[390, 844, 844, 390], [844, 390, 390, 844], [360, 640, 640, 360], [640, 360, 360, 640]]
	var states := {
		"sheet_plan": func(): s.screens.new_morning(); s.screens.open_plan("bakery"),
		"sheet_finance": func(): s.open_screen("finance", {"tab": 1}),
		"card_event": func(): _event_card(Game.content.events[0]),
		"day_ui": func(): _day("bakery", false),
	}
	for pr in pairs:
		for name in states:
			cur_size = "%dx%d>%dx%d" % pr; cur_scn = "rotate_" + name
			if not only.is_empty() and not (cur_scn in only): continue
			await _set_size(pr[0], pr[1]); _reset(); await wait_frames(3)
			states[name].call(); await wait_frames(4)
			await _set_size(pr[2], pr[3]); await get_tree().create_timer(0.3).timeout
			var before := findings.size()
			_audit()
			if shots_mode == "all" or (shots_mode == "flagged" and findings.size() > before):
				get_viewport().get_texture().get_image().save_png("%s/%s__%s.png" % [out, cur_size, cur_scn])
	_reset()

# The Android back button: closes an open sheet, and does nothing while a card waits for an answer (leaving the app is not tested here).
func _test_back_button() -> void:
	var s := ui()
	s.open_screen("today"); await wait_frames(3)
	s.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST); await wait_frames(2)
	print("AUDIT TEST %s back button closes the open sheet" % ("PASS" if not s.sheet.visible else "FAIL"))
	s.show_card({"title": "t", "body": "b", "choices": ["ok"]}); await wait_frames(2)
	s.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST); await wait_frames(2)
	print("AUDIT TEST %s back button leaves an open card alone" % ("PASS" if s.card_dim.visible else "FAIL"))
	s.hide_card()

# ---------------------------------------------------------------- the scenarios
func _scenarios() -> void:
	var co: Company = Game.co
	var s := ui()
	var list: Array = []
	list.append(["town_morning", func(): _town(false)])
	list.append(["town_evening", func(): _town(true)])
	list.append(["hud_extremes", func(): _town(false); _hud_extremes()])
	for scr in ["today", "orders", "staff", "goals", "settings"]: list.append([scr, func(): s.open_screen(scr)])
	for t in 3: list.append(["finance_%d" % t, func(): s.open_screen("finance", {"tab": t})])
	for t in 2: list.append(["upgrades_%d" % t, func(): s.open_screen("upgrades", {"tab": t})])
	for bid in ["bakery", "cafe"]:
		for t in 4: list.append(["plan_%s_%d" % [bid, t], func(): s.screens.new_morning(); s.screens.open_plan(bid); s.sheet.tab = t; s.sheet.refresh()])
	for b in ["bakery", "cafe", "minimarket"]: list.append(["building_" + b, func(): s.open_screen("building", {"building": b})])
	list.append(["settings_reset_armed", func(): s.screens.reset_armed = true; s.open_screen("settings")])
	for t in 3: list.append(["summary_%d" % t, func(): s.open_screen("summary", {"summary": summary}); s.sheet.tab = t; s.sheet.refresh()])
	if not week.is_empty(): list.append(["week", func(): s.open_screen("week", {"week": week})])
	list.append(["day_bakery", func(): _day("bakery", false)])
	list.append(["day_cafe_long", func(): _day("cafe", true)])
	# cards: a long synthetic one, and every real event
	list.append(["card_stress", func(): _stress_card()])
	list.append(["card_one_choice", func(): s.show_card({"who": "shira", "who_name": Loc.t("npc.shira"), "title": Loc.t("tut.intro1.title"), "body": Loc.t("tut.intro1.body"), "choices": [Loc.t("ui.continue")]})])
	for ev in Game.content.events:
		var e: Dictionary = ev
		list.append(["event_" + str(e["id"]), func(): _event_card(e)])
	list.append(["inspection_card", func(): _inspection_card()])
	for item in list:
		if not only.is_empty() and not (item[0] in only): continue
		cur_scn = item[0]
		_reset()
		item[1].call()
		await wait_frames(4)
		await get_tree().create_timer(0.2).timeout
		var before := findings.size()
		_audit()
		if shots_mode == "all" or (shots_mode == "flagged" and findings.size() > before):
			get_viewport().get_texture().get_image().save_png("%s/%s__%s.png" % [out, cur_size, cur_scn])

func _reset() -> void:
	var s := ui()
	s.hide_card(); s.sheet.close(); s.screens.reset_armed = false
	s.show_day_ui(false); s.set_action(""); s.set_objective("")
	s.hint_panel.visible = false
	main.state = "morning"; s.show_town_bar(true, Loc.t("ui.cta_morning"))
	s.hud.sync(); main._set_info()
	main.town_x = 0.0

func _town(evening: bool) -> void:
	ui().show_town_bar(true, Loc.t("ui.cta_evening") if evening else Loc.t("ui.cta_morning"))

func _hud_extremes() -> void:
	var h := ui().hud
	h.shown_cash = -1234567; h.shown_rep = 100; h.set_xp_display(15, 99999, 99999); h.set_info("יום 14 · שישי · 12:30 · עיצוב מאוד ארוך", "rain")

func _day(bid: String, long_texts: bool) -> void:
	var s := ui()
	s.hide_card(); s.show_town_bar(false); s.show_day_ui(true); s.setup_strip(bid)
	var st := {}
	for pid in Game.co.units[bid].db["products"]: st[pid] = 99
	s.set_strip("12:30", st, 14)
	var obj := "הולכים לקחת את הקרואסון"
	var act := "לוקחים קרואסון"
	var hint := Loc.t("tut.day_hint")
	if long_texts:
		obj = _longest("act.")
		act = _longest("act.")
		hint = _longest("tut.")
	s.set_objective(obj); s.set_action(act); s.show_hint(hint, 30.0)
	s.stick_enabled = true
	s.hud.set_info("יום 3 · שלישי · 12:30", "sunny")

func _longest(prefix: String) -> String:
	var best := ""
	var f := FileAccess.open("res://locale/strings.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0].begins_with(prefix):
			var t := Loc.t(row[0], {"n": 3, "product": "קפה קר", "name_k": "אורנית", "wanted_k": "biz.bakery", "product_k": "biz.bakery", "amount_m": 12345})
			if t.length() > best.length() and not t.contains("{"): best = t
	return best

func _stress_card() -> void:
	var best := ""
	var f := FileAccess.open("res://locale/strings.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and (row[0].ends_with(".body") or row[0].begins_with("tut.")) and row[1].length() > best.length(): best = row[1]
	best = best.replace("{amount_m}", "12,345 ₪").replace("{partner_k}", "המכולת של שלומי").replace("{n}", "5")
	ui().show_card({"who": "inspector", "who_name": Loc.t("npc.shira"), "title": Loc.t("insp.result_title") + " " + Loc.t("insp.result_title"), "body": best + "\n" + best,
		"note": best, "choices": [Loc.t("ui.continue"), best.substr(0, 42), best.substr(0, 42)]})

func _event_card(ev: Dictionary) -> void:
	var people: Dictionary = Game.content.world["people"]
	var who: String = ev.get("who", "")
	var names: Array = []
	for ch in ev.get("choices", []): names.append(Loc.t(ch["label"]) + (" (" + Loc.money(int(ch.get("cost", 0))) + ")" if int(ch.get("cost", 0)) > 0 else ""))
	var p := {"partner_k": "biz.bakery", "amount_m": 12345, "n": 5, "product_k": "biz.bakery", "pct": 15, "name_k": "biz.bakery", "item_k": "biz.bakery", "biz_k": "biz.bakery", "price_m": 99}
	ui().show_card({"who": who if people.has(who) else "", "who_name": Loc.t(people[who]["name"]) if people.has(who) else "",
		"title": Loc.t(ev["title"], p), "body": Loc.t(ev["body"], p), "choices": names})

func _inspection_card() -> void:
	var lines: Array = []
	for k in ["insp.clean", "insp.storage", "insp.expiry", "insp.equipment"]: lines.append("✗ " + Loc.t(k))
	ui().show_card({"who": "inspector", "who_name": Loc.t(Game.content.world["people"]["inspector"]["name"]), "title": Loc.t("insp.result_title"),
		"body": "\n".join(lines) + "\n\n" + Loc.t("insp.fined", {"amount_m": 1500}), "choices": [Loc.t("ui.continue")]})

# ---------------------------------------------------------------- the checks
func flag(kind: String, detail: String) -> void:
	findings.append({"size": cur_size, "scn": cur_scn, "kind": kind, "detail": detail})
	counts[kind] = int(counts.get(kind, 0)) + 1

func _desc(c: Control) -> String:
	var t := ""
	if c is Button: t = (c as Button).text
	elif c is Label: t = (c as Label).text
	t = t.replace("\n", " ").substr(0, 28)
	return "%s[%s]%s" % [c.get_class(), t, " " + str(c.name) if t == "" else ""]

func _ancestor_scroll(c: Control) -> ScrollContainer:
	var n := c.get_parent()
	while n != null and n != ui().root:
		if n is ScrollContainer: return n
		n = n.get_parent()
	return null

# Visible controls in drawing order (pre-order), without the full-screen helpers.
func _collect(n: Node, acc: Array) -> void:
	for ch in n.get_children():
		if ch is Control:
			var c := ch as Control
			if not c.visible: continue
			acc.append(c)
		_collect(ch, acc)

func _skip(c: Control) -> bool:
	if c == ui().root or c == ui().fx or c == ui().fade or c == ui().stick or c == ui().sheet or c == ui().hud or c == ui().card_dim: return true
	if c == ui().sheet.dim or c is ColorRect or c is TextureRect and c.get_parent() == ui().root: return true
	return false

func _audit() -> void:
	var s := ui()
	var all: Array = []
	_collect(s.root, all)
	var screen := Rect2(Vector2.ZERO, vp)
	var modal_card := s.card_dim.visible
	for c: Control in all:
		if _skip(c): continue
		if modal_card and not s.card_dim.is_ancestor_of(c): continue
		if not modal_card and s.card_dim.is_ancestor_of(c): continue
		var r := c.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0: continue
		var sc := _ancestor_scroll(c)
		if sc == null:
			if not screen.grow(1.5).encloses(r) and c.get_parent() != null:
				if not (c.get_parent() is Button and c is PanelContainer):
					flag("off_screen", "%s %s vs screen %s" % [_desc(c), str(r), str(screen)])
		else:
			var sr := sc.get_global_rect()
			if r.end.x > sr.end.x + 1.5 or r.position.x < sr.position.x - 1.5:
				flag("cut_sideways", "%s %s in scroll %s" % [_desc(c), str(r), str(sr)])
	# content wider than the scroll area
	if s.sheet.visible:
		var sc2 := s.sheet.scroll
		if s.sheet.body.get_combined_minimum_size().x > sc2.size.x + 1.0:
			flag("body_wider_than_scroll", "min %d vs %d" % [s.sheet.body.get_combined_minimum_size().x, sc2.size.x])
		if sc2.size.y < 120.0 or sc2.size.y < vp.y * 0.18:
			flag("sheet_too_short", "scroll area %dpx of %dpx" % [sc2.size.y, vp.y])
		var pr := s.sheet.panel.get_global_rect()
		if not screen.grow(1.5).encloses(pr): flag("sheet_off_screen", "%s vs %s" % [str(pr), str(screen)])
		# the footer buttons and the close button are inside the panel and reachable
		for b: Control in s.sheet.foot.get_children():
			if b.visible and not pr.grow(1.5).encloses(b.get_global_rect()): flag("footer_cut", "%s %s panel %s" % [_desc(b), str(b.get_global_rect()), str(pr)])
	# buttons: covered, too small. With a card open only its buttons count; with a sheet open only the sheet's (the bars under it are covered on purpose)
	for c: Control in all:
		if not (c is BaseButton) or _skip(c): continue
		if modal_card and not s.card_dim.is_ancestor_of(c): continue
		if not modal_card and s.card_dim.is_ancestor_of(c): continue
		if s.sheet.visible and not modal_card and not s.sheet.panel.is_ancestor_of(c): continue
		var r2 := c.get_global_rect()
		if r2.size.x < 1.0: continue
		var sc3 := _ancestor_scroll(c)
		var vis := r2
		if sc3 != null:
			vis = r2.intersection(sc3.get_global_rect())
			if vis.size.y < 4.0: continue         # scrolled out of view, fine
			if vis.size.y < r2.size.y - 1.0 and sc3.get_v_scroll_bar().max_value - sc3.get_v_scroll_bar().page <= 1.0:
				flag("button_clipped_no_scroll", "%s %s" % [_desc(c), str(r2)])
		var phys := Vector2(r2.size.x, r2.size.y) * scale_px
		if (phys.x < MIN_TOUCH or phys.y < MIN_TOUCH) and not (c as BaseButton).disabled:
			flag("small_touch", "%s %.0fx%.0f pt" % [_desc(c), phys.x, phys.y])
		var top := _topmost(all, vis.get_center())
		if top != null and top != c and not c.is_ancestor_of(top) and not top.is_ancestor_of(c):
			flag("button_covered", "%s hidden under %s at %s" % [_desc(c), _desc(top), str(vis.get_center())])
	# text size
	for c: Control in all:
		if c is Label and not _skip(c):
			if modal_card != s.card_dim.is_ancestor_of(c): continue
			var fs := (c as Label).get_theme_font_size("font_size") * scale_px
			if fs < MIN_TEXT and (c as Label).text != "": flag("tiny_text", "%s %.1fpt" % [_desc(c), fs])
	# overlapping bars (only when no modal card)
	if not modal_card:
		var items := {"top_card": s.hud.card, "cash": s.hud.cash_pill, "rep": s.hud.rep_pill, "info": s.hud.info_label.get_parent(), "side": s.side, "bottom": s.bottom, "strip": s.strip, "objective": s.objective_panel, "action": s.action_button, "hint": s.hint_panel, "sheet": s.sheet.panel}
		var keys := items.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				var a: Control = items[keys[i]]; var b: Control = items[keys[j]]
				if not (a.is_visible_in_tree() and b.is_visible_in_tree()): continue
				if keys[i] == "sheet" or keys[j] == "sheet":
					var other: String = keys[j] if keys[i] == "sheet" else keys[i]
					if other in ["bottom", "hint"]: continue
				var inter := a.get_global_rect().intersection(b.get_global_rect())
				if inter.size.x > 3.0 and inter.size.y > 3.0:
					flag("overlap", "%s x %s (%dx%d at %s)" % [keys[i], keys[j], inter.size.x, inter.size.y, str(inter.position)])

func _topmost(all: Array, p: Vector2) -> Control:
	var hit: Control = null
	for c: Control in all:
		if c.mouse_filter != Control.MOUSE_FILTER_STOP: continue
		if not c.get_global_rect().has_point(p): continue
		var sc := _ancestor_scroll(c)
		if sc != null and not sc.get_global_rect().has_point(p): continue
		if _clipped_by_other_modal(c): continue
		hit = c
	return hit

func _clipped_by_other_modal(c: Control) -> bool:
	return false

func _report() -> void:
	var lines: Array = []
	lines.append("AUDIT FINDINGS: %d" % findings.size())
	for k in counts: lines.append("  %s: %d" % [k, counts[k]])
	var seen := {}
	for f in findings:
		var key := "%s|%s|%s" % [f["size"], f["scn"], f["kind"]]
		var n := int(seen.get(key, 0)); seen[key] = n + 1
		if n < 3: lines.append("FINDING %s %s %s %s" % [f["size"], f["scn"], f["kind"], f["detail"]])
	var fo := FileAccess.open("%s/findings.txt" % out, FileAccess.WRITE)
	fo.store_string("\n".join(lines)); fo.close()
	print("\n".join(lines))
