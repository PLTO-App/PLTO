class_name ManagePanel
extends Control
# The owner's screens, as a sheet over the lower part of the phone screen (or the right side in landscape) so the shop stays visible:
# the morning planner (5 short pages: situation, baking, buying, prices and marketing, ready?), the upgrades list and the closing summary.
# It edits a plan dictionary and shows what the business simulation says; it contains no business rules of its own.

signal plan_ready(plan: Dictionary)
signal summary_done

const PLANNER_PAGES := 6
var biz: Business
var plan := {}
var page := 0
var mode := ""                 # planner | upgrades | summary
var summary := {}
var sheet: PanelContainer
var title_l: Label
var step_l: Label
var body: VBoxContainer
var note_l: Label
var back_b: Button
var next_b: Button
var _scroll: ScrollContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet = PanelContainer.new(); sheet.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.CREAM, 0.985), 24, 14)); add_child(sheet)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 8); sheet.add_child(col)
	var head := HBoxContainer.new(); col.add_child(head)
	title_l = UiStyle.label("", 21, UiStyle.INK, true); title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; head.add_child(title_l)
	step_l = UiStyle.label("", 13, UiStyle.MUTED); step_l.autowrap_mode = TextServer.AUTOWRAP_OFF; step_l.text_direction = Control.TEXT_DIRECTION_LTR; head.add_child(step_l)
	_scroll = ScrollContainer.new(); _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; col.add_child(_scroll)
	body = VBoxContainer.new(); body.add_theme_constant_override("separation", 8); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _scroll.add_child(body)
	note_l = UiStyle.label("", 13, Color("b3401f")); col.add_child(note_l)
	var foot := HBoxContainer.new(); foot.add_theme_constant_override("separation", 10); col.add_child(foot)
	back_b = UiStyle.pill_button("חזרה", 17, UiStyle.MUTED); back_b.custom_minimum_size = Vector2(0, 52); back_b.pressed.connect(_on_back); foot.add_child(back_b)
	next_b = UiStyle.pill_button("הבא", 18, UiStyle.TEAL); next_b.custom_minimum_size = Vector2(0, 52); next_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; next_b.pressed.connect(_on_next); foot.add_child(next_b)
	get_viewport().size_changed.connect(_layout)
	visible = false

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.y > vp.x:
		sheet.position = Vector2(8, vp.y * 0.36); sheet.size = Vector2(vp.x - 16, vp.y * 0.64 - 8)
	else:
		sheet.position = Vector2(vp.x * 0.42, 6); sheet.size = Vector2(vp.x * 0.58 - 8, vp.y - 12)

func is_open() -> bool:
	return visible

func close() -> void:
	visible = false; mode = ""

# ---------------------------------------------------------------- helpers
func _clear() -> void:
	for c in body.get_children(): c.queue_free()
	note_l.text = ""; _scroll.scroll_vertical = 0

func _line(text: String, size := 15, color := UiStyle.INK, is_bold := false) -> Label:
	var l := UiStyle.label(text, size, color, is_bold); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; body.add_child(l); return l

func _card() -> HBoxContainer:
	var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", UiStyle.panel(Color(1, 1, 1, 0.75), 14, 8, false)); body.add_child(pc)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 8); pc.add_child(h); return h

func _icon(pid: String) -> TextureRect:
	var t := TextureRect.new(); t.texture = load("res://assets/ui/%s.png" % biz.db["products"][pid]["icon"]); t.custom_minimum_size = Vector2(40, 40)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; return t

func _round(text: String) -> Button:
	var b := UiStyle.pill_button(text, 22, UiStyle.TEAL); b.custom_minimum_size = Vector2(42, 42)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := UiStyle.panel(UiStyle.TEAL if st != "pressed" else UiStyle.TEAL.darkened(0.2), 23, 4, false)
		if st == "disabled": sb.bg_color = Color("c8cdd6")
		b.add_theme_stylebox_override(st, sb)
	return b

# A row: [title and subtitle] [- value +]. Returns the two buttons so a page can disable them.
func _stepper(parent: HBoxContainer, title: String, subtitle: String, value: String, on_minus: Callable, on_plus: Callable, icon: Control = null) -> Dictionary:
	if icon != null: parent.add_child(icon)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_theme_constant_override("separation", 0); parent.add_child(v)
	var t := UiStyle.label(title, 15, UiStyle.INK, true); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; v.add_child(t)
	var st := UiStyle.label(subtitle, 12, UiStyle.MUTED); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; v.add_child(st)
	var plus := _round("+"); plus.pressed.connect(on_plus); parent.add_child(plus)
	var val := UiStyle.label(value, 17, UiStyle.INK, true); val.autowrap_mode = TextServer.AUTOWRAP_OFF; val.custom_minimum_size = Vector2(52, 0); val.text_direction = Control.TEXT_DIRECTION_LTR; parent.add_child(val)
	var minus := _round("−"); minus.pressed.connect(on_minus); parent.add_child(minus)
	return {"minus": minus, "plus": plus}

func _tap() -> void:
	Game.sfx.play("tap", 1.0, -6.0)

# ---------------------------------------------------------------- planner
func open_planner(business: Business) -> void:
	biz = business; mode = "planner"; page = 0; summary = {}
	plan = {"supplier": "wholesale", "buy": {}, "bake": {}, "prices": biz.prices.duplicate(), "marketing": "none", "promo_product": "croissant"}
	for iid in biz.db["ingredients"]: plan["buy"][iid] = 0
	for pid in biz.db["products"]: plan["bake"][pid] = 0
	visible = true; _layout(); _render()

func _need() -> Dictionary:
	var need := {}
	for iid in biz.db["ingredients"]: need[iid] = 0
	for pid in plan["bake"]:
		for iid in biz.db["products"][pid]["recipe"]: need[iid] += biz.db["products"][pid]["recipe"][iid] * plan["bake"][pid]
	return need

func _oven_used() -> int:
	var u := 0
	for pid in plan["bake"]: u += plan["bake"][pid] * biz.db["products"][pid]["oven"]
	return u

func _render() -> void:
	_clear()
	match mode:
		"planner":
			step_l.text = "%d/%d" % [page + 1, PLANNER_PAGES]
			back_b.visible = page > 0; next_b.text = "הבא" if page < PLANNER_PAGES - 1 else "פתיחת העסק"
			[_p_status, _p_bake, _p_buy, _p_price, _p_marketing, _p_ready][page].call()
		"upgrades": _p_upgrades()
		"summary": _p_summary()

func _on_back() -> void:
	_tap()
	if mode == "upgrades": mode = "planner"; _render()
	elif mode == "summary" and page > 0: page -= 1; _render()
	elif mode == "planner" and page > 0: page -= 1; _render()

func _on_next() -> void:
	_tap()
	if mode == "upgrades": mode = "planner"; _render(); return
	if mode == "summary":
		if page == 0: page = 1; _render()
		else: close(); summary_done.emit()
		return
	if page < PLANNER_PAGES - 1: page += 1; _render()
	else:
		var errs := biz.validate_plan(plan)
		if errs.is_empty(): close(); plan_ready.emit(plan)
		else: note_l.text = errs[0]

func _p_status() -> void:
	title_l.text = "יום %d, %s" % [biz.day, biz.weekday_name()]
	var fc := biz.forecast(plan)
	_line("בקופה: %s    מוניטין: %d%%" % [UiMoney.fmt(biz.profile.cash), biz.profile.reputation], 17, UiStyle.INK, true)
	_line("צפי להיום: כ-%d עד %d לקוחות. זו הערכה, לא הבטחה." % [fc.x, fc.y], 14, UiStyle.MUTED)
	_line("במלאי חומרי גלם:", 14, UiStyle.MUTED)
	for iid in biz.db["ingredients"]: _line("%s: %d" % [biz.db["ingredients"][iid]["name"], biz.inv.units(iid)], 14)
	var goods := ""
	for pid in biz.db["products"]:
		var n := biz.inv.stock(pid)
		if n > 0: goods += "%s %d   " % [biz.db["products"][pid]["name"], n]
	_line("מוצרים מאתמול: %s" % (goods if goods != "" else "אין"), 14)
	if not biz.last_summary.is_empty() and not biz.last_summary["coach"].is_empty():
		_line("שירה: " + biz.last_summary["coach"][0], 13, UiStyle.TEAL.darkened(0.3))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); body.add_child(row)
	var up := UiStyle.pill_button("שדרוגים", 15, UiStyle.GOLD_DEEP); up.custom_minimum_size = Vector2(0, 44); up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.pressed.connect(func(): _tap(); mode = "upgrades"; _render()); row.add_child(up)
	if not biz.last_plan.is_empty():
		var same := UiStyle.pill_button("כמו אתמול", 15, UiStyle.MUTED); same.custom_minimum_size = Vector2(0, 44); same.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		same.pressed.connect(_same_as_yesterday); row.add_child(same)

func _same_as_yesterday() -> void:
	_tap()
	var lp := biz.last_plan
	for pid in biz.db["products"]: plan["bake"][pid] = int(lp.get("bake", {}).get(pid, 0))
	if biz.unlocked("marketing", lp.get("marketing", "none")): plan["marketing"] = lp.get("marketing", "none")
	plan["promo_product"] = lp.get("promo_product", "croissant")
	_fill_missing(); note_l.text = "התוכנית של אתמול נטענה."

func _fill_missing() -> void:
	var need := _need()
	for iid in biz.db["ingredients"]: plan["buy"][iid] = maxi(0, need[iid] - biz.inv.units(iid))

func _p_bake() -> void:
	title_l.text = "מה אופים היום?"
	var cap := biz.oven_capacity(); var used := _oven_used()
	_line("תפוקת התנור: %d מתוך %d" % [used, cap], 15, UiStyle.INK, true)
	_line("מה שלא נמכר היום ייזרק, או יימכר בהנחה מחר אם המוצר נשמר.", 12, UiStyle.MUTED)
	for pid in biz.db["products"]:
		var pr: Dictionary = biz.db["products"][pid]
		var h := _card(); var n: int = plan["bake"][pid]
		var sub := "תנור %d ליחידה · יש מאתמול %d" % [pr["oven"], biz.inv.stock(pid)]
		var btns := _stepper(h, pr["name"], sub, str(n), func(): plan["bake"][pid] = maxi(0, plan["bake"][pid] - 1); _fill_missing(); _tap(); _render(),
			func(): plan["bake"][pid] += 1; _fill_missing(); _tap(); _render(), _icon(pid))
		btns["plus"].disabled = used + pr["oven"] > cap; btns["minus"].disabled = n <= 0
	var miss := []
	var need := _need()
	for iid in biz.db["ingredients"]:
		var m: int = need[iid] - biz.inv.units(iid)
		if m > 0: miss.append("%s (%d)" % [biz.db["ingredients"][iid]["name"], m])
	if not miss.is_empty(): _line("חסר לאפייה, ייקנה בעמוד הבא: " + ", ".join(miss), 12, UiStyle.MUTED)

func _p_buy() -> void:
	title_l.text = "קנייה מהספק"
	var chips := HBoxContainer.new(); chips.add_theme_constant_override("separation", 8); body.add_child(chips)
	for sid in biz.db["suppliers"]:
		var sp: Dictionary = biz.db["suppliers"][sid]; var open := biz.unlocked("suppliers", sid)
		var txt: String = "%s · איכות %d" % [sp["name"], sp["quality"]] if open else "%s · ייפתח בדרגה %d" % [sp["name"], sp["unlock_level"]]
		var b := UiStyle.pill_button(txt, 13, UiStyle.TEAL if plan["supplier"] == sid else UiStyle.MUTED); b.custom_minimum_size = Vector2(0, 46); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not open; b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func(): plan["supplier"] = sid; _tap(); _render()); chips.add_child(b)
	var sup: Dictionary = biz.db["suppliers"][plan["supplier"]]; var need := _need()
	for iid in biz.db["ingredients"]:
		var ing: Dictionary = biz.db["ingredients"][iid]; var h := _card(); var step: int = ing["step"]
		var sub := "מחיר %d ₪ ליחידה · יש %d · נדרש %d" % [sup["prices"][iid], biz.inv.units(iid), need[iid]]
		var btns := _stepper(h, ing["name"], sub, str(plan["buy"][iid]), func(): plan["buy"][iid] = maxi(0, plan["buy"][iid] - step); _tap(); _render(),
			func(): plan["buy"][iid] += step; _tap(); _render())
		btns["minus"].disabled = plan["buy"][iid] <= 0
	var fill := UiStyle.pill_button("להשלים את מה שחסר לאפייה", 15, UiStyle.GOLD_DEEP); fill.custom_minimum_size = Vector2(0, 44)
	fill.pressed.connect(func(): _fill_missing(); _tap(); _render()); body.add_child(fill)
	var cost := biz.plan_costs(plan)
	_line("עלות הקנייה: %s · בקופה: %s" % [UiMoney.fmt(cost["buy"]), UiMoney.fmt(biz.profile.cash)], 14, UiStyle.INK, true)

func _p_price() -> void:
	title_l.text = "מחירים"
	for pid in biz.db["products"]:
		var pr: Dictionary = biz.db["products"][pid]; var b := biz.price_bounds(pid); var h := _card()
		var cost := biz.unit_cost(pid, plan["supplier"])
		var sub := "מחיר שוק %d · עלות חומרים כ-%d · רווח ליחידה כ-%d" % [pr["price"], cost, plan["prices"][pid] - cost]
		var btns := _stepper(h, pr["name"], sub, "%d" % plan["prices"][pid], func(): plan["prices"][pid] = maxi(b.x, plan["prices"][pid] - Business.PRICE_STEP); _tap(); _render(),
			func(): plan["prices"][pid] = mini(b.y, plan["prices"][pid] + Business.PRICE_STEP); _tap(); _render(), _icon(pid))
		btns["minus"].disabled = plan["prices"][pid] <= b.x; btns["plus"].disabled = plan["prices"][pid] >= b.y

func _p_marketing() -> void:
	title_l.text = "שיווק להיום"
	var fc := biz.forecast(plan)
	_line("בלי שיווק צפויים כ-%d עד %d לקוחות. שיווק מביא עוד, אבל צריך מלאי וידיים כדי לשרת אותם." % [fc.x, fc.y], 13, UiStyle.MUTED)
	for mid in biz.db["marketing"]:
		var mk: Dictionary = biz.db["marketing"][mid]; var open := biz.unlocked("marketing", mid)
		var what := "עלות %s" % UiMoney.fmt(mk["cost"]) if mk["cost"] > 0 else ("בלי עלות" if mid != "none" else "")
		if mk["reach_pct"] > 0: what += (" · " if what != "" else "") + "כ-%d אחוז יותר לקוחות" % mk["reach_pct"]
		if mk["discount_pct"] > 0: what += " · %d אחוז הנחה על מוצר" % mk["discount_pct"]
		var txt: String = mk["name"] + ((" · " + what) if what != "" and open else "") if open else "%s · ייפתח בדרגה %d" % [mk["name"], mk["unlock_level"]]
		var b := UiStyle.pill_button(txt, 13, UiStyle.TEAL if plan["marketing"] == mid else UiStyle.MUTED); b.custom_minimum_size = Vector2(0, 44); b.disabled = not open; b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func(): plan["marketing"] = mid; _tap(); _render()); body.add_child(b)
	if plan["marketing"] == "promo":
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); body.add_child(row)
		for pid in biz.db["products"]:
			var b := UiStyle.pill_button(biz.db["products"][pid]["name"], 12, UiStyle.GOLD_DEEP if plan["promo_product"] == pid else UiStyle.MUTED); b.custom_minimum_size = Vector2(0, 40); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; b.pressed.connect(func(): plan["promo_product"] = pid; _tap(); _render()); row.add_child(b)

func _p_ready() -> void:
	title_l.text = "מוכנים לפתוח?"
	var cost := biz.plan_costs(plan); var fc := biz.forecast(plan)
	for pid in biz.db["products"]:
		var n: int = plan["bake"][pid] + biz.inv.stock(pid)
		_line("%s: %d במלאי להיום" % [biz.db["products"][pid]["name"], n], 15)
	_line("קנייה: %s · שיווק: %s" % [UiMoney.fmt(cost["buy"]), UiMoney.fmt(cost["marketing"])], 15, UiStyle.INK, true)
	_line("הקופה אחרי ההכנות: %s" % UiMoney.fmt(biz.profile.cash - cost["total"]), 15, UiStyle.INK, true)
	_line("צפי: כ-%d עד %d לקוחות. הוצאות קבועות של %s ייגבו בסגירה." % [fc.x, fc.y, UiMoney.fmt(int(biz.db["fixed_costs"]["rent_utilities"]))], 13, UiStyle.MUTED)
	var errs := biz.validate_plan(plan)
	if not errs.is_empty(): note_l.text = errs[0]
	elif plan["bake"].values().all(func(n): return n == 0) and not _any_stock():
		note_l.text = "אין מה למכור היום. אפשר לחזור ולתכנן אפייה."

func _any_stock() -> bool:
	for pid in biz.db["products"]: if biz.inv.stock(pid) > 0: return true
	return false

# ---------------------------------------------------------------- upgrades
func open_upgrades(business: Business) -> void:
	biz = business; mode = "upgrades"; visible = true; _layout(); _render()

func _p_upgrades() -> void:
	title_l.text = "שדרוגים"; step_l.text = ""; back_b.visible = false; next_b.text = "חזרה"
	_line("בקופה: %s" % UiMoney.fmt(biz.profile.cash), 16, UiStyle.INK, true)
	for uid in biz.db["upgrades"]:
		var u: Dictionary = biz.db["upgrades"][uid]; var h := _card()
		var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
		var t := UiStyle.label(u["name"], 15, UiStyle.INK, true); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; v.add_child(t)
		var d := UiStyle.label(u["desc"], 12, UiStyle.MUTED); d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; v.add_child(d)
		var owned := biz.upgrades.has(uid); var open := biz.unlocked("upgrades", uid)
		var label := "נרכש" if owned else (UiMoney.fmt(u["cost"]) if open else "דרגה %d" % u["unlock_level"])
		var b := UiStyle.pill_button(label, 14, UiStyle.TEAL); b.custom_minimum_size = Vector2(110, 46)
		b.disabled = owned or not open or u["cost"] > biz.profile.cash
		b.pressed.connect(func():
			var err := biz.buy_upgrade(uid)
			if err == "": Game.sfx.play("coin"); Game.save_game()
			else: note_l.text = err
			_render())
		h.add_child(b)

# ---------------------------------------------------------------- closing summary
func open_summary(business: Business, s: Dictionary) -> void:
	biz = business; summary = s; mode = "summary"; page = 0; visible = true; _layout(); _render()

func _pl(label: String, value: int, bold := false, sign := false) -> void:
	var t := UiMoney.ltr(value, sign)
	var h := HBoxContainer.new(); body.add_child(h)
	var a := UiStyle.label(label, 15 if not bold else 17, UiStyle.INK, bold); a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; a.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(a)
	var b := UiStyle.label(t, 15 if not bold else 17, UiStyle.INK if value >= 0 or not bold else Color("b3401f"), bold); b.autowrap_mode = TextServer.AUTOWRAP_OFF; b.text_direction = Control.TEXT_DIRECTION_LTR; h.add_child(b)

func _p_summary() -> void:
	var s := summary
	back_b.visible = page > 0; step_l.text = "%d/2" % (page + 1)
	if page == 0:
		next_b.text = "הבא"; title_l.text = "סגירה של יום %d" % s["day"]
		_pl("הכנסות", s["revenue"]); _pl("עלות חומרי הגלם שנמכרו", -s["cogs"]); _pl("מה שנזרק", -s["waste_cost"])
		_pl("שיווק", -s["marketing_cost"]); _pl("שכירות וחשמל", -s["fixed"]); _pl("רווח או הפסד", s["profit"], true, true)
		_line("שינוי בקופה: %s · בקופה עכשיו: %s" % [UiMoney.fmt(s["cash_change"]), UiMoney.fmt(s["cash_end"])], 14, UiStyle.MUTED)
		var lv := ""
		if not s["levels"].is_empty(): lv = " · דרגה חדשה: %d" % s["levels"][s["levels"].size() - 1]
		var rd: int = s["rep_delta"]
		var rep_t := "עלייה של %d%%" % rd if rd > 0 else ("ירידה של %d%%" % -rd if rd < 0 else "ללא שינוי")
		_line("מוניטין: %s · ניסיון נוסף מהיום: %d%s" % [rep_t, s["xp_bonus"], lv], 14, UiStyle.INK)
	else:
		next_b.text = "ליום הבא"; title_l.text = "מה קרה היום"
		_line("שירתנו %d מתוך %d לקוחות." % [s["served"], s["customers"]], 15, UiStyle.INK, true)
		if s["lost_price"] > 0: _line("%d אמרו שזה יקר מדי." % s["lost_price"], 14)
		if s["lost_stock"] > 0: _line("%d לא מצאו מה שרצו ועזבו." % s["lost_stock"], 14)
		if s["walkouts"] > 0: _line("%d עזבו כי חיכו יותר מדי." % s["walkouts"], 14)
		if s["substitutes"] > 0: _line("%d לקחו חלופה." % s["substitutes"], 14)
		if s["served"] > 0: _line("שביעות רצון ממוצעת: %d מתוך 100." % s["avg_sat"], 14)
		for c in s["coach"]: _line("שירה: " + c, 14, UiStyle.TEAL.darkened(0.35))
