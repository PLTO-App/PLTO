class_name Screens
extends RefCounted
# The contents of the management sheet: the day's checklist, the plan of each business, supplier orders, staff, money and
# loans, upgrades, goals, settings, buildings in town, and the day and week summaries. Each function fills a Sheet. Screens read
# and change the company (Game.co) and ask the game to move on through `flow` (a Callable: flow.call(action, data)).

var ui                        # GameUi
var flow: Callable
var plans := {}               # business id -> today's plan being edited
var reviewed := {}            # business id -> the player opened its plan today
var draft := {}               # supplier id -> business id -> {item: qty}
var order_sup := "wholesale"
var reset_armed := false

func co() -> Company: return Game.co

func _init(p_ui) -> void:
	ui = p_ui

# Called every morning: fresh suggested plans for every business that opens today.
func new_morning() -> void:
	plans = {}; reviewed = {}; draft = {}
	for bid in co().units:
		if co().unit_ready(bid): plans[bid] = co().suggest_plan(bid, plans)
	if plans.has("bakery") and plans.has("cafe"): plans["bakery"] = co().suggest_plan("bakery", plans)

func biz_name(bid: String) -> String:
	return Loc.t(co().units[bid].db["name"]) if co().units.has(bid) else Loc.t(Game.content.businesses[bid]["name"])

# ================================================================ today
func today(sh: Sheet) -> void:
	var c := co()
	sh.set_title(Loc.t("today.title", {"day": c.day, "weekday_k": c.weekday_key()}), Loc.t("today.sub", {"weather_k": c.world["weather"]["kinds"][c.weather]["name"]}))
	var r: Dictionary = c.last_report
	var news: Array = []
	for d in r.get("deliveries", []):
		news.append(Loc.t("today.delivery_credit" if d["credit"] else "today.delivery", {"sup_k": c.world["suppliers"][d["sup"]]["name"], "amount_m": d["cost"]}))
	for v in r.get("collected", []): news.append(Loc.t("today.collected", {"partner_k": v["partner_k"], "amount_m": v["amount"]}))
	for p in r.get("paid", []): news.append(Loc.t("today.paid", {"to_k": p["to_k"], "amount_m": p["amount"]}))
	if int(r.get("relief", 0)) > 0: news.append(Loc.t("today.relief", {"amount_m": r["relief"]}))
	if not news.is_empty():
		var nc := sh.card()
		nc.add_child(UiStyle.label(Loc.t("today.news"), 14, UiStyle.MUTED, true))
		for n in news: nc.add_child(UiStyle.label("• " + n, 14))
	if c.in_setup():
		_setup_today(sh); return
	if c.day <= 2: _tip_card(sh, _today_tip())
	var list := sh.card()
	list.add_child(UiStyle.label(Loc.t("today.checklist"), 14, UiStyle.MUTED, true))
	for bid in plans:
		var p: Dictionary = plans[bid]
		var sub := _plan_summary(bid, p)
		_task(list, reviewed.has(bid), Loc.t("today.plan_biz", {"biz_k": c.units[bid].db["name"]}), sub, func(): open_plan(bid))
	var placed := 0
	for o in c.orders: placed += int(o["cost"])
	_task(list, placed > 0, Loc.t("today.orders"), Loc.t("today.orders_placed", {"amount_m": placed}) if placed > 0 else Loc.t("today.orders_none"), func(): ui.open_screen("orders"))
	var deliveries := _partner_deliveries()
	if deliveries != "": _task(list, true, Loc.t("today.partners"), deliveries, Callable())
	for bid in c.units:
		if not c.unit_ready(bid) or bid == c.worker: continue
		if c.staff_at(bid).is_empty():
			_task(list, false, Loc.t("today.nobody", {"biz_k": c.units[bid].db["name"]}), Loc.t("today.nobody_sub"), func(): ui.open_screen("staff"))
	# where Noa works today
	var ready: Array = c.units.keys().filter(func(b): return c.unit_ready(b))
	if ready.size() > 1:
		var wc := sh.card()
		wc.add_child(UiStyle.label(Loc.t("today.where"), 14, UiStyle.MUTED, true))
		var h := sh.row(wc)
		for bid in ready:
			var b := UiStyle.chip(biz_name(bid), c.worker == bid); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): c.worker = bid; sh.refresh())
			h.add_child(b)
		wc.add_child(UiStyle.label(Loc.t("today.where_sub"), 12, UiStyle.MUTED))
	var g: Array = Goals.active(c)
	if not g.is_empty():
		var gc := sh.card(); var gh := sh.row(gc)
		gh.add_child(UiIcons.glyph("goals", 22, UiStyle.GOLD_DEEP))
		var gl := UiStyle.label(Loc.t(g[0]["name"]), 14, UiStyle.INK, true); gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; gh.add_child(gl)
		var gb := UiStyle.bar(Goals.progress(c, g[0]), 100, UiStyle.GOLD_DEEP, 12); gb.custom_minimum_size = Vector2(80, 12); gh.add_child(gb)
	var errs := c.validate_day(plans)
	if not errs.is_empty(): sh.note(Loc.msg(errs[0]))
	sh.add_footer(Loc.t("today.open"), "cta", func(): _open_day(sh))

# A morning of the setup period: the space is rented and being fitted out, so there is no working day yet. The checklist shows what
# can still be done before the doors open; the day itself passes with the button at the bottom.
func _setup_today(sh: Sheet) -> void:
	var c := co(); var bid := c.setup_bid(); var left := c.setup_left(bid)
	var total: int = int(c.format_def(bid, c.units[bid].format).get("setup_days", left))
	var weekly := 0
	for k in c.units[bid].db["weekly_costs"]: weekly += int(c.units[bid].db["weekly_costs"][k])
	var card := sh.card()
	card.add_child(UiStyle.label(Loc.t("setup.title", {"biz_k": c.units[bid].db["name"]}), 16, UiStyle.INK, true))
	var bar := UiStyle.bar(maxi(0, total - left), maxi(1, total), UiStyle.TEAL, 12); bar.custom_minimum_size = Vector2(0, 12); card.add_child(bar)
	card.add_child(UiStyle.label(Loc.t("setup.left_one" if left == 1 else "setup.left", {"n": left}), 14))
	card.add_child(UiStyle.label(Loc.t("setup.rent", {"weekly_m": weekly}), 13, UiStyle.MUTED))
	if c.day - c.units[bid].lease_day == 0: _tip_card(sh, "setup.tip")
	var list := sh.card()
	list.add_child(UiStyle.label(Loc.t("today.checklist"), 14, UiStyle.MUTED, true))
	var placed := 0
	for o in c.orders: placed += int(o["cost"])
	_task(list, placed > 0, Loc.t("setup.order"), Loc.t("setup.order_sub", {"amount_m": placed}) if placed > 0 else Loc.t("setup.order_none"), func(): ui.open_screen("orders"))
	_task(list, false, Loc.t("setup.money"), Loc.t("setup.money_sub", {"cash_m": c.profile.cash}), func(): ui.open_screen("finance", {"tab": 1}))
	sh.add_footer(Loc.t("setup.end"), "cta", func(): flow.call("setup_day", {}))

# The first mornings: one short sentence from Shira about the next step, following what was already done.
func _today_tip() -> String:
	if reviewed.is_empty(): return "tut.tip_plan"
	if co().orders.is_empty(): return "tut.tip_orders"
	return "tut.tip_open"

func _tip_card(sh: Sheet, key: String) -> void:
	var tc := sh.card(); var th := sh.row(tc)
	th.add_child(UiStyle.portrait("shira", 44, UiStyle.TEAL))
	var tl := UiStyle.label(Loc.t(key), 14); tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; th.add_child(tl)

func _open_day(sh: Sheet) -> void:
	var errs := co().validate_day(plans)
	if not errs.is_empty(): sh.note(Loc.msg(errs[0])); return
	flow.call("open_day", {"plans": plans})

func _task(parent: Control, done: bool, title: String, sub: String, cb: Callable) -> void:
	var b := Button.new(); b.flat = true; b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(0, 54)
	var sb := UiStyle.panel(Color("ffffff"), 14, 8, false); sb.border_color = UiStyle.LINE; sb.set_border_width_all(1)
	for st in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(st, sb if st != "pressed" else UiStyle.panel(Color("eef3ff"), 14, 8, false))
	var h := UiStyle.hbox(10); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_left = 10; h.offset_right = -10; h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := UiIcons.glyph("check" if done else "dot", 22, UiStyle.CTA if done else UiStyle.GOLD_DEEP); dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(dot)
	var v := UiStyle.vbox(0); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.alignment = BoxContainer.ALIGNMENT_CENTER; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(v)
	v.add_child(UiStyle.label(title, 15, UiStyle.INK, true)); if sub != "": v.add_child(UiStyle.label(sub, 12, UiStyle.MUTED))
	b.add_child(h)
	if cb.is_valid(): b.pressed.connect(func(): Game.sfx.play("tap", 1.0, -6.0); cb.call())
	else: b.disabled = true
	parent.add_child(b)
	await b.get_tree().process_frame
	if is_instance_valid(b): b.custom_minimum_size.y = maxf(54, h.get_combined_minimum_size().y + 12)

func _plan_summary(bid: String, p: Dictionary) -> String:
	var c := co(); var b: Business = c.units[bid]
	var n := 0
	for pid in p.get("bake", {}): n += int(p["bake"][pid])
	var cost: int = b.plan_costs(p, c.plan_ctx(bid))["total"]
	if b.is_retail(): return Loc.t("today.plan_market_sub", {"n": b.stock_total(), "amount_m": cost})
	if bid == "cafe":
		var t := 0
		for pid in p.get("transfer_in", {}): t += int(p["transfer_in"][pid])
		return Loc.t("today.plan_cafe_sub", {"n": t, "amount_m": cost})
	return Loc.t("today.plan_sub", {"n": n, "amount_m": cost})

func _partner_deliveries() -> String:
	var c := co(); var parts: Array = []
	for cid in c.contracts:
		if c.contracts[cid]["active"] and c.is_workday():
			var items: Array = []
			for pid in c.contracts[cid]["items"]: items.append("%d %s" % [c.contracts[cid]["items"][pid], Loc.t(c.units[c.world["contracts"][cid]["biz"]].db["products"][pid]["name"])])
			parts.append(Loc.t("today.to_partner", {"partner_k": c.world["contracts"][cid]["partner"], "items": ", ".join(items)}))
	for s in c.special:
		if int(s["deliver"]) == c.day: parts.append(Loc.t("today.to_partner", {"partner_k": s["partner_k"], "items": "%d %s" % [s["qty"], Loc.t(c.units[s["biz"]].db["products"][s["product"]]["name"])]}))
	return " · ".join(parts)

# ================================================================ the plan of a business
func open_plan(bid: String) -> void:
	reviewed[bid] = true
	ui.sheet.open(Loc.t("plan.title", {"biz_k": co().units[bid].db["name"]}), func(sh): plan(sh, bid),
		{"tabs": [Loc.t("plan.tab_make"), Loc.t("plan.tab_prices"), Loc.t("plan.tab_marketing"), Loc.t("plan.tab_upkeep")], "id": "plan_" + bid})

func plan(sh: Sheet, bid: String) -> void:
	var c := co(); var b: Business = c.units[bid]; var p: Dictionary = plans[bid]
	var fc := c.forecast(bid, p)
	sh.set_title(Loc.t("plan.title", {"biz_k": b.db["name"]}), Loc.t("plan.forecast", {"lo": fc.x, "hi": fc.y}))
	match sh.tab:
		0:
			if b.is_retail(): _plan_retail(sh, bid, b, p)
			elif bid == "cafe": _plan_cafe(sh, bid, b, p)
			else: _plan_make(sh, bid, b, p)
		1: _plan_prices(sh, bid, b, p)
		2: _plan_marketing(sh, bid, b, p)
		3: _plan_upkeep(sh, bid, b, p)
	var errs := b.validate_plan(p, c.plan_ctx(bid))
	if not errs.is_empty(): sh.note(Loc.msg(errs[0]))
	sh.add_footer(Loc.t("plan.suggest"), "secondary", func():
		plans[bid] = c.suggest_plan(bid, plans); sh.refresh(); sh.note(Loc.t("plan.suggested"), true))
	sh.add_footer(Loc.t("plan.done"), "primary", func(): ui.open_screen("today"))

func _auto_buy(bid: String, b: Business, p: Dictionary) -> void:
	var need := b.bake_needs(p)
	for iid in need:
		var miss: int = int(need[iid]) - b.inv.units(iid)
		if miss > 0: p["buy_now"][iid] = miss
		else: p["buy_now"].erase(iid)

func _plan_make(sh: Sheet, bid: String, b: Business, p: Dictionary) -> void:
	var c := co()
	var cap := b.capacity(c.mod_value("capacity_pct", bid)); var used := b.capacity_used(p)
	var cc := sh.card()
	sh.meter(cc, Loc.t(b.db["capacity"]["name"]), used, cap, UiStyle.GOLD_DEEP if used <= cap else UiStyle.BAD)
	cc.add_child(UiStyle.label(Loc.t("plan.capacity_sub", {"used": used, "cap": cap}), 12, UiStyle.MUTED))
	var want := c.forecast_items(bid, p); var res := c.reserved_for(bid, plans)
	var list := sh.card()
	for pid in b.db["products"]:
		if not b.is_baked(pid): continue
		var pr: Dictionary = b.db["products"][pid]; var n: int = int(p["bake"].get(pid, 0))
		var sub := Loc.t("plan.bake_sub", {"want": want.get(pid, 0), "old": b.inv.old(pid), "cap": pr["cap"]})
		if int(res.get(pid, 0)) > 0: sub += " · " + Loc.t("plan.reserved", {"n": res[pid]})
		var btns := sh.stepper(list, UiStyle.item_icon_id(pid), Loc.t(pr["name"]), sub, str(n),
			func(): p["bake"][pid] = maxi(0, n - 1); _auto_buy(bid, b, p); sh.refresh(),
			func(): p["bake"][pid] = n + 1; _auto_buy(bid, b, p); sh.refresh())
		btns["minus"].disabled = n <= 0; btns["plus"].disabled = used + int(pr["cap"]) > cap
	var ic := sh.card()
	ic.add_child(UiStyle.label(Loc.t("plan.ingredients"), 14, UiStyle.MUTED, true))
	var need := b.bake_needs(p); var np: Dictionary = c.plan_ctx(bid)["now_prices"]; var buy := 0
	for iid in b.db["ingredients"]:
		var have := b.inv.units(iid); var miss := maxi(0, int(need[iid]) - have)
		var h := sh.row(ic); h.add_child(UiStyle.icon(iid, 32))
		var t := UiStyle.label(Loc.t(b.db["ingredients"][iid]["name"]), 14, UiStyle.INK, true); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
		var st := Loc.t("plan.ing_ok", {"have": have, "need": need[iid]}) if miss == 0 else Loc.t("plan.ing_buy", {"n": miss, "amount_m": miss * int(np.get(iid, 0))})
		h.add_child(UiStyle.one_line(UiStyle.label(st, 13, UiStyle.GOOD if miss == 0 else UiStyle.GOLD_DEEP, true)))
		buy += miss * int(np.get(iid, 0))
	if buy > 0:
		ic.add_child(UiStyle.label(Loc.t("plan.buy_now_note", {"amount_m": buy}), 12, UiStyle.MUTED))
		var ob := UiStyle.button(Loc.t("plan.to_orders"), "secondary", 14, 44); ob.pressed.connect(func(): ui.open_screen("orders")); ic.add_child(ob)

# A shop that makes nothing: the shelves, and what to buy this morning (at the neighbour's price) for what is still missing.
func _plan_retail(sh: Sheet, bid: String, b: Business, p: Dictionary) -> void:
	var c := co(); var np: Dictionary = c.plan_ctx(bid)["now_prices"]
	var want := c.forecast_items(bid, p)
	var cap := b.capacity(c.mod_value("capacity_pct", bid))
	var held := b.stock_total(); var adding := 0
	for item in p["buy_now"]: adding += int(p["buy_now"][item])
	var cc := sh.card()
	sh.meter(cc, Loc.t(b.db["capacity"]["name"]), held + adding, cap, UiStyle.GOLD_DEEP if held + adding <= cap else UiStyle.BAD)
	cc.add_child(UiStyle.label(Loc.t("plan.shelf_sub", {"have": held, "add": adding, "cap": cap}), 12, UiStyle.MUTED))
	var list := sh.card()
	var ids: Array = b.db["products"].keys()
	ids.sort_custom(func(x, y): return int(b.db["products"][x]["pref"]) > int(b.db["products"][y]["pref"]))
	for pid in ids:
		var pr: Dictionary = b.db["products"][pid]; var item: String = pr["resale"]
		var add := int(p["buy_now"].get(item, 0)); var st := c.item_step(bid, item)
		var sub := Loc.t("plan.goods_sub", {"want": want.get(pid, 0), "have": b.inv.stock(pid), "price_m": np.get(item, 0)})
		if b.inv.old(pid) > 0: sub += " · " + Loc.t("plan.old_n", {"n": b.inv.old(pid)})
		var btns := sh.stepper(list, UiStyle.item_icon_id(pid), Loc.t(pr["name"]), sub, "+%d" % add,
			func(): p["buy_now"][item] = maxi(0, add - st); sh.refresh(), func(): p["buy_now"][item] = add + st; sh.refresh())
		btns["minus"].disabled = add <= 0; btns["plus"].disabled = held + adding + st > cap
	var cost: int = b.plan_costs(p, c.plan_ctx(bid))["buy"]
	if cost > 0: sh.line(Loc.t("plan.buy_now_note", {"amount_m": cost}), 12, UiStyle.MUTED)

func _plan_cafe(sh: Sheet, bid: String, b: Business, p: Dictionary) -> void:
	var c := co(); var np: Dictionary = c.plan_ctx(bid)["now_prices"]
	var want := c.forecast_items(bid, p)
	var cap := b.capacity(c.mod_value("capacity_pct", bid))
	var dc := sh.card()
	dc.add_child(UiStyle.label(Loc.t("plan.drinks"), 14, UiStyle.MUTED, true))
	var drinks := 0
	for pid in b.db["products"]: if b.is_mto(pid): drinks += int(want.get(pid, 0))
	dc.add_child(UiStyle.label(Loc.t("plan.drinks_sub", {"want": drinks, "cap": cap}), 13))
	for iid in b.db["ingredients"]:
		var have := b.inv.units(iid); var add := int(p["buy_now"].get(iid, 0)); var st := c.item_step(bid, iid)
		var btns := sh.stepper(dc, iid, Loc.t(b.db["ingredients"][iid]["name"]), Loc.t("plan.cups_have", {"have": have, "price_m": np.get(iid, 0)}), "+%d" % add,
			func(): p["buy_now"][iid] = maxi(0, add - st); sh.refresh(), func(): p["buy_now"][iid] = add + st; sh.refresh())
		btns["minus"].disabled = add <= 0
	var pc := sh.card()
	pc.add_child(UiStyle.label(Loc.t("plan.pastries"), 14, UiStyle.MUTED, true))
	var internal: Dictionary = c.world.get("internal", {}).get(bid, {})
	if c.owns(internal.get("from", "")):
		for pid in internal["products"]:
			var n := int(p["transfer_in"].get(pid, 0)); var tp := int(internal["transfer_price"].get(pid, 0))
			var btns := sh.stepper(pc, pid, Loc.t("plan.from_bakery", {"product_k": b.db["products"][pid]["name"]}),
				Loc.t("plan.from_bakery_sub", {"want": want.get(pid, 0), "have": b.inv.stock(pid), "price_m": tp}), str(n),
				func(): p["transfer_in"][pid] = maxi(0, n - 1); sh.refresh(), func(): p["transfer_in"][pid] = n + 1; sh.refresh())
			btns["minus"].disabled = n <= 0
	for item in b.goods_input_ids():
		var pid := b.product_for_input(item)
		if c.owns(internal.get("from", "")) and internal["products"].has(pid): continue
		var add := int(p["buy_now"].get(item, 0)); var st := c.item_step(bid, item)
		var btns := sh.stepper(pc, pid, Loc.t(b.db["products"][pid]["name"]), Loc.t("plan.goods_sub", {"want": want.get(pid, 0), "have": b.inv.stock(pid), "price_m": np.get(item, 0)}), "+%d" % add,
			func(): p["buy_now"][item] = maxi(0, add - st); sh.refresh(), func(): p["buy_now"][item] = add + st; sh.refresh())
		btns["minus"].disabled = add <= 0
	var cost: int = b.plan_costs(p, c.plan_ctx(bid))["buy"]
	if cost > 0: sh.line(Loc.t("plan.buy_now_note", {"amount_m": cost}), 12, UiStyle.MUTED)

func _plan_prices(sh: Sheet, bid: String, b: Business, p: Dictionary) -> void:
	var c := co(); var sup := c.supplier_prices("wholesale")
	var list := sh.card()
	for pid in b.db["products"]:
		var pr: Dictionary = b.db["products"][pid]; var bnd := b.price_bounds(pid); var step := b.price_step(pid)
		var price: int = int(p["prices"][pid]); var cost := b.unit_cost(pid, sup)
		if bid == "cafe" and c.world.get("internal", {}).get("cafe", {}).get("products", {}).has(pid) and c.owns("bakery"):
			cost = int(c.world["internal"]["cafe"]["transfer_price"][pid])
		var sub := Loc.t("plan.price_sub", {"market_m": pr["price"], "cost_m": cost, "margin_m": price - cost})
		var btns := sh.stepper(list, UiStyle.item_icon_id(pid), Loc.t(pr["name"]), sub, Loc.money_short(price),
			func(): p["prices"][pid] = maxi(bnd.x, price - step); sh.refresh(), func(): p["prices"][pid] = mini(bnd.y, price + step); sh.refresh())
		btns["minus"].disabled = price <= bnd.x; btns["plus"].disabled = price >= bnd.y
	sh.line(Loc.t("plan.price_hint"), 12, UiStyle.MUTED)

func _plan_marketing(sh: Sheet, bid: String, b: Business, p: Dictionary) -> void:
	var c := co()
	for mid in b.db["marketing"]:
		var mk: Dictionary = b.db["marketing"][mid]; var open := b.unlocked("marketing", mid, c.level())
		var parts: Array = []
		if int(mk["cost"]) > 0: parts.append(Loc.t("mk.cost", {"amount_m": mk["cost"]}))
		if int(mk["reach_pct"]) > 0: parts.append(Loc.t("mk.reach", {"pct": mk["reach_pct"]}))
		if int(mk["discount_pct"]) > 0: parts.append(Loc.t("mk.discount", {"pct": mk["discount_pct"]}))
		var txt := Loc.t(mk["name"]) + ((" · " + " · ".join(parts)) if not parts.is_empty() else "")
		if not open: txt = Loc.t(mk["name"]) + " · " + Loc.t("err.level", {"n": mk["unlock_level"]})
		var ch := UiStyle.chip(txt, p["marketing"] == mid); ch.disabled = not open
		ch.pressed.connect(func(): p["marketing"] = mid; sh.refresh()); sh.body.add_child(ch)
	if p["marketing"] == "promo":
		sh.line(Loc.t("plan.promo_which"), 13, UiStyle.MUTED, true)
		var h := sh.row(sh.body)
		for pid in b.db["products"]:
			var ch := UiStyle.chip(Loc.t(b.db["products"][pid]["name"]), p["promo_product"] == pid, 12); ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ch.pressed.connect(func(): p["promo_product"] = pid; sh.refresh()); h.add_child(ch)
	sh.line(Loc.t("plan.marketing_hint"), 12, UiStyle.MUTED)

func _plan_upkeep(sh: Sheet, bid: String, b: Business, p: Dictionary) -> void:
	var c := co(); var up: Dictionary = c.world["upkeep"]
	var cc := sh.card()
	sh.meter(cc, Loc.t("plan.clean"), b.cleanliness, 100, UiStyle.TEAL if b.cleanliness >= 60 else UiStyle.BAD)
	var ch := UiStyle.chip(Loc.t("plan.deep_clean", {"amount_m": up["deep_clean_cost"]}), p.get("deep_clean", false))
	ch.pressed.connect(func(): p["deep_clean"] = not p.get("deep_clean", false); sh.refresh()); cc.add_child(ch)
	sh.meter(cc, Loc.t("plan.equipment"), b.equipment, 100, UiStyle.TEAL if b.equipment >= 50 else UiStyle.BAD)
	var ch2 := UiStyle.chip(Loc.t("plan.maintenance", {"amount_m": up["maintenance_cost"]}), p.get("maintenance", false))
	ch2.pressed.connect(func(): p["maintenance"] = not p.get("maintenance", false); sh.refresh()); cc.add_child(ch2)
	sh.line(Loc.t("plan.upkeep_hint"), 12, UiStyle.MUTED)
	if c.flags.has("certificate_" + bid): sh.line(Loc.t("plan.certificate"), 13, UiStyle.GOOD, true)

# ================================================================ suppliers
func orders(sh: Sheet) -> void:
	var c := co()
	sh.set_title(Loc.t("orders.title"), Loc.t("orders.sub"))
	var sups: Array = ["wholesale", "galil"]
	var h := sh.row(sh.body)
	for sid in sups:
		var open := c.supplier_unlocked(sid)
		var ch := UiStyle.chip(Loc.t(c.world["suppliers"][sid]["name"]) + ("" if open else " · " + Loc.t("err.level", {"n": c.world["suppliers"][sid]["unlock_level"]})), order_sup == sid, 13)
		ch.disabled = not open; ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch.pressed.connect(func(): order_sup = sid; sh.refresh()); h.add_child(ch)
	var sp: Dictionary = c.world["suppliers"][order_sup]
	sh.line(Loc.t(sp["who"]) + " · " + Loc.t("orders.quality", {"q": sp["quality"]}), 12, UiStyle.MUTED)
	if not draft.has(order_sup): draft[order_sup] = {}
	var total := 0
	for bid in c.units:
		if not draft[order_sup].has(bid): draft[order_sup][bid] = {}
		var d: Dictionary = draft[order_sup][bid]
		var card := sh.card()
		card.add_child(UiStyle.label(biz_name(bid), 15, UiStyle.INK, true))
		var b: Business = c.units[bid]
		for item in c.buyable_items(bid):
			if bid == "cafe" and item == "croissant" and c.owns("bakery"): continue
			var q := int(d.get(item, 0)); var st := c.item_step(bid, item); var price := c.supplier_price(order_sup, item)
			var have := b.inv.units(item) if b.db["ingredients"].has(item) else b.inv.stock(b.product_for_input(item))
			var btns := sh.stepper(card, UiStyle.item_icon_id(item if b.db["ingredients"].has(item) else b.product_for_input(item)), Loc.t(c.item_name_key(bid, item)),
				Loc.t("orders.item_sub", {"price_m": price, "have": have}), str(q),
				func(): d[item] = maxi(0, q - st); sh.refresh(), func(): d[item] = q + st; sh.refresh())
			btns["minus"].disabled = q <= 0
		total += c.order_cost(order_sup, d)
	var credit := c.credit_ok(order_sup)
	sh.line(Loc.t("orders.total", {"amount_m": total}) + " · " + (Loc.t("orders.credit", {"days": sp["credit_days"]}) if credit else Loc.t("orders.cash")), 14, UiStyle.INK, true)
	if not c.orders.is_empty():
		var pc := sh.card(); pc.add_child(UiStyle.label(Loc.t("orders.pending"), 14, UiStyle.MUTED, true))
		for i in c.orders.size():
			var o: Dictionary = c.orders[i]
			var row := sh.row(pc)
			var t := UiStyle.label(Loc.t("orders.pending_line", {"sup_k": c.world["suppliers"][o["sup"]]["name"], "biz_k": c.units[o["biz"]].db["name"], "amount_m": o["cost"]}), 13)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(t)
			var x := UiStyle.button(Loc.t("orders.cancel"), "ghost", 13, 44); x.pressed.connect(func(): c.cancel_order(i); sh.refresh()); row.add_child(x)
	sh.add_footer(Loc.t("orders.suggest"), "secondary", func():
		for bid in c.units: draft[order_sup][bid] = c.suggest_order(bid)
		sh.refresh())
	sh.add_footer(Loc.t("orders.send"), "primary", func(): _send_orders(sh))

func _send_orders(sh: Sheet) -> void:
	var c := co(); var sent := 0
	for bid in draft.get(order_sup, {}):
		var items: Dictionary = draft[order_sup][bid]
		var any := false
		for k in items: if int(items[k]) > 0: any = true
		if not any: continue
		var e := c.place_order(bid, order_sup, items)
		if not e.is_empty(): sh.refresh(); sh.note(Loc.msg(e)); return
		sent += 1; draft[order_sup][bid] = {}
	Game.save_game()
	sh.refresh()
	if sent > 0:
		Game.sfx.play("coin", 0.8, -6.0)
		await sh.get_tree().process_frame
		sh.note(Loc.t("orders.sent"), true)

# ================================================================ staff
func staff(sh: Sheet) -> void:
	var c := co()
	sh.set_title(Loc.t("staff.title"), Loc.t("staff.sub"))
	if c.staff.is_empty(): sh.line(Loc.t("staff.none"), 14, UiStyle.MUTED)
	for s in c.staff:
		var d := c.staff_def(s["id"]); var card := sh.card(); var h := sh.row(card)
		h.add_child(UiStyle.portrait(s["id"], 56))
		var v := UiStyle.vbox(2); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
		v.add_child(UiStyle.label("%s · %s" % [Loc.t(d["name"]), Loc.t("role." + str(s["role"]))], 15, UiStyle.INK, true))
		v.add_child(UiStyle.label(Loc.t("staff.line", {"skill": s["skill"], "wage_m": s["wage"]}) + (" · " + Loc.t("staff.sick") if int(s["sick_day"]) == c.day else ""), 12, UiStyle.MUTED))
		var ah := sh.row(card)
		for bid in c.units:
			var ch := UiStyle.chip(biz_name(bid), s["assigned"] == bid, 13); ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ch.pressed.connect(func(): c.assign(s["id"], bid); sh.refresh()); ah.add_child(ch)
		var fire := UiStyle.button(Loc.t("staff.fire"), "ghost", 13, 44)
		fire.pressed.connect(func(): c.fire(s["id"]); Game.save_game(); sh.refresh()); card.add_child(fire)
	var cand := c.candidates()
	if c.level() < 2: sh.line(Loc.t("err.staff_level"), 13, UiStyle.MUTED)
	elif not cand.is_empty():
		sh.heading(Loc.t("staff.candidates"))
		for d in cand:
			var card := sh.card(); var h := sh.row(card)
			h.add_child(UiStyle.portrait(d["id"], 56, UiStyle.ACCENT))
			var v := UiStyle.vbox(2); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
			v.add_child(UiStyle.label("%s · %s" % [Loc.t(d["name"]), Loc.t("role." + str(d["role"]))], 15, UiStyle.INK, true))
			v.add_child(UiStyle.label(Loc.t("staff.line", {"skill": d["skill"], "wage_m": d["wage"]}), 12, UiStyle.MUTED))
			var bh := sh.row(card)
			for bid in c.units:
				var hb := UiStyle.button(Loc.t("staff.hire_to", {"biz_k": c.units[bid].db["name"]}), "primary", 13, 44); hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hb.pressed.connect(func():
					var e := c.hire(d["id"], bid)
					if not e.is_empty(): sh.note(Loc.msg(e))
					else: Game.save_game(); Game.sfx.play("levelup", 1.3, -10.0); sh.refresh())
				bh.add_child(hb)
	sh.line(Loc.t("staff.hint"), 12, UiStyle.MUTED)

# ================================================================ money: status, loans, services
func finance(sh: Sheet) -> void:
	var c := co()
	sh.set_title(Loc.t("fin.title"), Loc.t("fin.sub"))
	match sh.tab:
		0:
			var cc := sh.card()
			sh.kv(cc, Loc.t("fin.cash"), Loc.money(c.profile.cash), true, UiStyle.INK if c.profile.cash >= 0 else UiStyle.BAD)
			sh.kv(cc, Loc.t("fin.overdraft"), Loc.money(c.overdraft_limit()))
			sh.kv(cc, Loc.t("fin.week_profit"), Loc.money(int(c.stats["week_profit"]), true), false, UiStyle.GOOD if int(c.stats["week_profit"]) >= 0 else UiStyle.BAD)
			var rc := sh.card(); rc.add_child(UiStyle.label(Loc.t("fin.receivables"), 14, UiStyle.MUTED, true))
			if c.receivables.is_empty(): rc.add_child(UiStyle.label(Loc.t("fin.none"), 13, UiStyle.MUTED))
			for v in c.receivables: sh.kv(rc, Loc.t("fin.recv_line", {"partner_k": v["partner_k"], "days": maxi(0, maxi(int(v["due"]), int(v.get("late_until", 0))) - c.day)}), Loc.money(int(v["amount"])))
			var pc := sh.card(); pc.add_child(UiStyle.label(Loc.t("fin.payables"), 14, UiStyle.MUTED, true))
			for o in c.orders: sh.kv(pc, Loc.t("fin.order_line", {"sup_k": c.world["suppliers"][o["sup"]]["name"]}), Loc.money(int(o["cost"])))
			for p in c.payables: sh.kv(pc, Loc.t("fin.invoice_line", {"to_k": p["to_k"], "days": maxi(0, int(p["due"]) - c.day)}), Loc.money(int(p["amount"])))
			if c.wages_due > 0: sh.kv(pc, Loc.t("fin.wages_due"), Loc.money(c.wages_due))
			for bid in c.units:
				var wk := 0
				for k in c.units[bid].db["weekly_costs"]: wk += int(c.units[bid].db["weekly_costs"][k])
				sh.kv(pc, Loc.t("fin.rent_line", {"biz_k": c.units[bid].db["name"]}), Loc.money(wk))
			sh.line(Loc.t("fin.hint"), 12, UiStyle.MUTED)
		1:
			for lid in c.world["bank"]["loans"]:
				var L: Dictionary = c.world["bank"]["loans"][lid]; var card := sh.card()
				card.add_child(UiStyle.label(Loc.t("fin.loan_title", {"amount_m": L["amount"]}), 16, UiStyle.INK, true))
				card.add_child(UiStyle.label(Loc.t("fin.loan_terms", {"weeks": L["weeks"], "weekly_m": L["weekly"], "total_m": int(L["weekly"]) * int(L["weeks"]), "cost_m": int(L["weekly"]) * int(L["weeks"]) - int(L["amount"])}), 13, UiStyle.MUTED))
				var open := c.loan_available(lid); var active := c.loan_open(lid)
				var b := UiStyle.button(Loc.t("fin.loan_active") if active else (Loc.t("fin.loan_take") if open else Loc.t("err.level", {"n": L["unlock_level"]})), "gold", 15, 44)
				b.disabled = active or not open
				b.pressed.connect(func():
					var e := c.take_loan(lid)
					if not e.is_empty(): sh.note(Loc.msg(e))
					else: Game.save_game(); Game.sfx.play("coin"); ui.hud.sync(); sh.refresh())
				card.add_child(b)
			for l in c.loans: sh.line(Loc.t("fin.loan_left", {"weeks": l["weeks_left"], "weekly_m": l["weekly"]}), 13, UiStyle.INK, true)
			sh.line(Loc.t("fin.loan_hint"), 12, UiStyle.MUTED)
		2:
			for svc in c.world["services"]:
				var S: Dictionary = c.world["services"][svc]; var card := sh.card(); var h := sh.row(card)
				if svc == "accountant": h.add_child(UiStyle.portrait("michal", 52))
				var v := UiStyle.vbox(2); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
				v.add_child(UiStyle.label(Loc.t(S["name"]) + " · " + Loc.t("fin.weekly", {"amount_m": S["weekly"]}), 15, UiStyle.INK, true))
				v.add_child(UiStyle.label(Loc.t(S["who"]), 12, UiStyle.MUTED))
				var on := c.services.has(svc); var open := c.level() >= int(S["unlock_level"])
				var b := UiStyle.button(Loc.t("fin.svc_stop") if on else (Loc.t("fin.svc_start") if open else Loc.t("err.level", {"n": S["unlock_level"]})), "secondary" if on else "primary", 14, 44)
				b.disabled = not open and not on
				b.pressed.connect(func(): c.subscribe(svc, not on); Game.save_game(); sh.refresh()); card.add_child(b)

# ================================================================ upgrades
func upgrades(sh: Sheet) -> void:
	var c := co(); var ids: Array = c.units.keys()
	var bid: String = ids[clampi(sh.tab, 0, ids.size() - 1)]; var b: Business = c.units[bid]
	sh.set_title(Loc.t("upg.title"), Loc.t("upg.sub", {"amount_m": c.profile.cash}))
	for uid in b.db["upgrades"]:
		var u: Dictionary = b.db["upgrades"][uid]; var card := sh.card(); var h := sh.row(card)
		var v := UiStyle.vbox(2); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
		v.add_child(UiStyle.label(Loc.t(u["name"]), 15, UiStyle.INK, true)); v.add_child(UiStyle.label(Loc.t(u["desc"]), 12, UiStyle.MUTED))
		var owned := b.upgrades.has(uid); var open := b.unlocked("upgrades", uid, c.level())
		var txt := Loc.t("upg.owned") if owned else (Loc.money(int(u["cost"])) if open else Loc.t("err.level", {"n": u["unlock_level"]}))
		var bt := UiStyle.button(txt, "gold" if not owned else "secondary", 14, 44); bt.custom_minimum_size.x = 110
		bt.disabled = owned or not open or int(u["cost"]) > c.profile.cash
		bt.pressed.connect(func():
			var e := c.buy_upgrade(bid, uid)
			if e.is_empty(): Game.sfx.play("levelup", 1.2, -6.0); Game.save_game(); ui.hud.sync(); flow.call("upgraded", {"biz": bid}); sh.refresh()
			else: sh.note(Loc.msg(e)))
		h.add_child(bt)

# ================================================================ goals
func goals(sh: Sheet) -> void:
	var c := co()
	sh.set_title(Loc.t(Goals.chapter_name(c)) if Goals.chapter_name(c) != "" else Loc.t("goal.all_done"), Loc.t("goal.done_count", {"n": c.goals_done.size(), "total": Goals.all(c).size()}))
	for g in Goals.active(c):
		var card := sh.card(); var h := sh.row(card)
		h.add_child(UiIcons.glyph("goals", 26, UiStyle.GOLD_DEEP))
		var v := UiStyle.vbox(4); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
		v.add_child(UiStyle.label(Loc.t(g["name"]), 15, UiStyle.INK, true))
		var pb := UiStyle.bar(Goals.progress(c, g), 100, UiStyle.GOLD_DEEP, 12); pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_child(pb)
		var rw: Dictionary = g.get("reward", {})
		var rtxt := Loc.t("goal.reward_xp", {"n": rw.get("xp", 0)}) + ((" · " + Loc.money(int(rw["cash"]))) if int(rw.get("cash", 0)) > 0 else "")
		v.add_child(UiStyle.label(rtxt, 12, UiStyle.MUTED))
	sh.line(Loc.t("goal.hint"), 12, UiStyle.MUTED)

# ================================================================ settings
func settings(sh: Sheet) -> void:
	sh.set_title(Loc.t("set.title"))
	var cc := sh.card()
	for key in ["sound", "music"]:
		var on: bool = Game.settings[key]
		var ch := UiStyle.chip(Loc.t("set." + key) + " · " + Loc.t("set.on" if on else "set.off"), on)
		ch.pressed.connect(func(): Game.settings[key] = not on; Game.save_settings(); sh.refresh()); cc.add_child(ch)
	var lc := sh.card(); lc.add_child(UiStyle.label(Loc.t("set.language"), 14, UiStyle.MUTED, true))
	lc.add_child(UiStyle.chip("עברית", true))
	var rc := sh.card()
	var rb := UiStyle.button(Loc.t("set.reset_confirm") if reset_armed else Loc.t("set.reset"), "danger" if reset_armed else "secondary", 14, 44)
	rb.pressed.connect(func():
		if reset_armed: reset_armed = false; flow.call("reset", {})
		else: reset_armed = true; sh.refresh())
	rc.add_child(rb)
	sh.line(Loc.t("set.disclaimer"), 12, UiStyle.MUTED)
	sh.line(Loc.t("set.credits"), 11, UiStyle.MUTED)

# ================================================================ buildings in town
func building(sh: Sheet, id: String) -> void:
	var c := co()
	match id:
		"bakery", "cafe", "market":
			if not c.owns(id):
				sh.set_title(Loc.t("bld.%s_rent" % id), Loc.t("bld.%s_rent_sub" % id))
				var o: Dictionary = c.world["openable"][id]; var card := sh.card()
				card.add_child(UiStyle.label(Loc.t("bld.open_cost_%s" % id, {"amount_m": o["cost"], "level": o["unlock_level"]}), 15, UiStyle.INK, true))
				card.add_child(UiStyle.label(Loc.t("bld.%s_pitch" % id), 13, UiStyle.MUTED))
				var e := c.can_open(id)
				var b := UiStyle.button(Loc.t("bld.open_%s" % id) if e.is_empty() else Loc.msg(e), "cta", 16, 50); b.disabled = not e.is_empty()
				b.pressed.connect(func():
					var err := c.open_business(id)
					if err.is_empty(): Game.save_game(); flow.call("opened", {"biz": id}); sh.close()
					else: sh.note(Loc.msg(err)))
				card.add_child(b)
				return
			var u: Business = c.units[id]
			sh.set_title(biz_name(id), Loc.t("bld.rep", {"rep": u.reputation}))
			var card := sh.card()
			sh.meter(card, Loc.t("plan.clean"), u.cleanliness, 100, UiStyle.TEAL)
			sh.meter(card, Loc.t("plan.equipment"), u.equipment, 100, UiStyle.TEAL)
			if not u.last_summary.is_empty(): sh.kv(card, Loc.t("bld.last_profit"), Loc.money(int(u.last_summary["profit"]), true), true, UiStyle.GOOD if int(u.last_summary["profit"]) >= 0 else UiStyle.BAD)
			sh.add_footer(Loc.t("upg.title"), "gold", func(): ui.open_screen("upgrades", {"tab": c.units.keys().find(id)}))
			if plans.has(id): sh.add_footer(Loc.t("bld.to_plan"), "primary", func(): open_plan(id))
		"minimarket":
			sh.set_title(Loc.t("biz.minimarket"), Loc.t("bld.mm_sub"))
			var card := sh.card()
			var ct: Dictionary = c.contracts.get("minimarket", {})
			if ct.is_empty() or not ct.get("active", false): card.add_child(UiStyle.label(Loc.t("bld.mm_no_contract"), 14))
			else:
				var items: Array = []
				for pid in ct["items"]: items.append("%d %s · %s" % [ct["items"][pid], Loc.t(c.units["bakery"].db["products"][pid]["name"]), Loc.money(int(ct["prices"][pid]))])
				card.add_child(UiStyle.label(Loc.t("bld.mm_contract", {"items": ", ".join(items), "misses": ct["misses"]}), 14))
			card.add_child(UiStyle.label(Loc.t("bld.mm_emergency"), 12, UiStyle.MUTED))
		"warehouse":
			ui.open_screen("orders"); return
		"office":
			ui.open_screen("finance", {"tab": 2}); return
		"bank":
			ui.open_screen("finance", {"tab": 1}); return

# ================================================================ the day's summary and the week
func summary(sh: Sheet, s: Dictionary) -> void:
	var c := co()
	sh.set_title(Loc.t("sum.title", {"day": s["day"], "weekday_k": s["weekday_k"]}), "")
	match sh.tab:
		0:
			var first_view: bool = ui.stars_day != int(s["day"])         # the count-up and the stars play once per day
			if int(s["day"]) <= 1: _tip_card(sh, "tut.tip_summary")
			var big := sh.card(); var h := sh.row(big)
			var t := UiStyle.label(Loc.t("sum.profit") if int(s["profit"]) >= 0 else Loc.t("sum.loss"), 18, UiStyle.INK, true); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
			var v := UiStyle.one_line(UiStyle.label(Loc.money(int(s["profit"]), true), 24, UiStyle.GOOD if int(s["profit"]) >= 0 else UiStyle.BAD, true)); v.text_direction = Control.TEXT_DIRECTION_LTR; h.add_child(v)
			if first_view: _count_up(v, int(s["profit"]))
			_stars_card(sh, Coach.stars(s), first_view, int(s["profit"]) > 0)
			ui.stars_day = int(s["day"])
			for bid in s["units"]:
				var u: Dictionary = s["units"][bid]
				big.add_child(UiStyle.label(Loc.t("sum.unit_line", {"biz_k": c.units[bid].db["name"], "served": u["served"], "customers": u["customers"], "profit_m": u["profit"]}), 13, UiStyle.MUTED))
			if not s.get("goals", []).is_empty():
				var gc := sh.card()
				for g in s["goals"]: gc.add_child(UiStyle.label(Loc.t("sum.goal_done", {"name_k": g["name"], "xp": g["xp"]}) + ((" · " + Loc.money(int(g["cash"]), true)) if int(g["cash"]) > 0 else ""), 14, UiStyle.GOOD, true))
			var coach := sh.card(); var ch := sh.row(coach)
			ch.add_child(UiStyle.portrait("shira", 54, UiStyle.TEAL))
			var cv := UiStyle.vbox(4); cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ch.add_child(cv)
			cv.add_child(UiStyle.label(Loc.t("npc.shira"), 13, UiStyle.TEAL, true))
			for line in s["coach"]: cv.add_child(UiStyle.label(Loc.msg(line), 14))
		1:
			var t := {"rev": 0, "b2b": 0, "int": 0, "cogs": 0, "waste": 0, "mk": 0, "fixed": 0, "wages": 0, "other": 0}
			for bid in s["units"]:
				var u: Dictionary = s["units"][bid]
				t["rev"] += int(u["revenue"]); t["b2b"] += int(u["b2b_revenue"]); t["int"] += int(u["internal_revenue"])
				t["cogs"] += int(u["cogs"]) + int(u["b2b_cost"]) + int(u["internal_cost"]); t["waste"] += int(u["waste_cost"]); t["mk"] += int(u["marketing_cost"])
				t["fixed"] += int(u["fixed"]); t["wages"] += int(u["wages"]); t["other"] += int(u["other"])
			var pc := sh.card()
			sh.kv(pc, Loc.t("sum.sales"), Loc.money(t["rev"]))
			if t["b2b"] > 0: sh.kv(pc, Loc.t("sum.b2b"), Loc.money(t["b2b"]))
			if t["int"] > 0: sh.kv(pc, Loc.t("sum.internal"), Loc.money(t["int"]))
			sh.kv(pc, Loc.t("sum.cogs"), Loc.money(-t["cogs"]))
			if t["waste"] > 0: sh.kv(pc, Loc.t("sum.waste"), Loc.money(-t["waste"]))
			if t["mk"] > 0: sh.kv(pc, Loc.t("sum.marketing"), Loc.money(-t["mk"]))
			sh.kv(pc, Loc.t("sum.fixed"), Loc.money(-t["fixed"]))
			if t["wages"] > 0: sh.kv(pc, Loc.t("sum.wages"), Loc.money(-t["wages"]))
			if t["other"] > 0: sh.kv(pc, Loc.t("sum.other"), Loc.money(-t["other"]))
			var comp := int(s["services"]) + int(s["interest"]) + int(s["bank_fee"])
			if comp > 0: sh.kv(pc, Loc.t("sum.company"), Loc.money(-comp))
			sh.kv(pc, Loc.t("sum.profit_line"), Loc.money(int(s["profit"]), true), true, UiStyle.GOOD if int(s["profit"]) >= 0 else UiStyle.BAD)
			var cc := sh.card()
			sh.kv(cc, Loc.t("sum.cash_change"), Loc.money(int(s["cash_change"]), true))
			sh.kv(cc, Loc.t("sum.cash_end"), Loc.money(int(s["cash_end"])), true)
			if int(s["receivables"]) > 0: sh.kv(cc, Loc.t("sum.receivables"), Loc.money(int(s["receivables"])))
			sh.line(Loc.t("sum.disclaimer"), 11, UiStyle.MUTED)
		2:
			for bid in s["units"]:
				var u: Dictionary = s["units"][bid]; var card := sh.card()
				card.add_child(UiStyle.label(biz_name(bid), 15, UiStyle.INK, true))
				if u["closed"]: card.add_child(UiStyle.label(Loc.t("sum.closed"), 13, UiStyle.BAD)); continue
				card.add_child(UiStyle.label(Loc.t("sum.served", {"served": u["served"], "customers": u["customers"]}), 13))
				if int(u["lost_price"]) > 0: card.add_child(UiStyle.label(Loc.t("sum.lost_price", {"n": u["lost_price"]}), 13))
				if int(u["lost_stock"]) > 0: card.add_child(UiStyle.label(Loc.t("sum.lost_stock", {"n": u["lost_stock"]}), 13))
				if int(u["walkouts"]) > 0: card.add_child(UiStyle.label(Loc.t("sum.walkouts", {"n": u["walkouts"]}), 13))
				if int(u["served"]) > 0: card.add_child(UiStyle.label(Loc.t("sum.sat", {"n": u["avg_sat"]}), 13))
				var rd := int(u["rep_delta"])
				card.add_child(UiStyle.label(Loc.t("sum.rep_up", {"n": rd}) if rd > 0 else (Loc.t("sum.rep_down", {"n": -rd}) if rd < 0 else Loc.t("sum.rep_same")), 13, UiStyle.MUTED))
				sh.kv(card, Loc.t("sum.profit_line"), Loc.money(int(u["profit"]), true), true, UiStyle.GOOD if int(u["profit"]) >= 0 else UiStyle.BAD)
	sh.add_footer(Loc.t("sum.next"), "cta", func(): flow.call("summary_done", {}))

func _count_up(l: Label, target: int) -> void:
	var tw := l.create_tween()
	tw.tween_method(func(x: float): l.text = Loc.money(roundi(x), true), 0.0, float(target), 0.8).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

# Three stars for the day: they pop in one after the other, each earned one with a rising ping.
func _stars_card(sh: Sheet, n: int, animate: bool, profitable: bool) -> void:
	var card := sh.card()
	var row := UiStyle.hbox(10); row.alignment = BoxContainer.ALIGNMENT_CENTER; card.add_child(row)
	for i in 3:
		var st := UiIcons.rating_star(40, i < n); row.add_child(st)
		if not animate: continue
		st.scale = Vector2.ZERO
		var tw := st.create_tween(); tw.tween_interval(0.35 + 0.3 * i)
		if i < n: tw.tween_callback(func(): Game.sfx.play("star", 1.0 + 0.12 * i, -4.0))
		tw.tween_property(st, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var headline := Loc.t("sum.stars_%d" % n) if (profitable or n == 0) else Loc.t("sum.stars_loss")      # a day with a loss is not called good
	card.add_child(UiStyle.label(headline, 16, UiStyle.INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	card.add_child(UiStyle.label(Loc.t("sum.stars_legend"), 12, UiStyle.MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))

func week(sh: Sheet, w: Dictionary) -> void:
	var c := co()
	sh.set_title(Loc.t("week.title"), Loc.t("week.sub"))
	var card := sh.card(); var h := sh.row(card)
	var acc := c.services.has("accountant")
	h.add_child(UiStyle.portrait("michal" if acc else "shira", 56, UiStyle.ACCENT))
	var v := UiStyle.vbox(4); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
	v.add_child(UiStyle.label(Loc.t("npc.michal") if acc else Loc.t("npc.shira"), 13, UiStyle.ACCENT, true))
	for n in w.get("notes", []): v.add_child(UiStyle.label(Loc.msg(n), 14))
	var nc := sh.card()
	sh.kv(nc, Loc.t("week.revenue"), Loc.money(int(w["revenue"])))
	sh.kv(nc, Loc.t("week.rent"), Loc.money(-int(w["rent"])))
	if int(w["wages"]) > 0: sh.kv(nc, Loc.t("week.wages"), Loc.money(-int(w["wages"])))
	if int(w["services"]) > 0: sh.kv(nc, Loc.t("week.services"), Loc.money(-int(w["services"])))
	if int(w["loans"]) > 0: sh.kv(nc, Loc.t("week.loans"), Loc.money(-int(w["loans"])))
	if int(w.get("fine", 0)) > 0: sh.kv(nc, Loc.t("week.fine"), Loc.money(-int(w["fine"])))
	sh.kv(nc, Loc.t("week.profit_line"), Loc.money(int(w["profit"]), true), true, UiStyle.GOOD if int(w["profit"]) >= 0 else UiStyle.BAD)
	sh.kv(nc, Loc.t("week.cash"), Loc.money(int(w["cash_end"])), true)
	sh.add_footer(Loc.t("week.next"), "cta", func(): flow.call("week_done", {}))
