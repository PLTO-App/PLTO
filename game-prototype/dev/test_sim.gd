extends SceneTree
# Development only: tests and balance simulations for the company simulation (no screen, no 3D).
# godot --headless --path game-prototype --script dev/test_sim.gd [-- quick]
var fails := 0
var content: ContentDb

func check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok: fails += 1

func fresh(seed_value := 7) -> Company:
	var co := Company.new(content); co.new_game(seed_value); return co

func starter_plan(co: Company) -> Dictionary:
	var p: Dictionary = co.units["bakery"].empty_plan()
	p["bake"] = {"croissant": 10, "challah": 6, "carrot_cake": 1, "strawberry_cake": 1}
	return fill(co, "bakery", p)

# Adds a morning purchase of whatever the bake still misses.
func fill(co: Company, bid: String, p: Dictionary) -> Dictionary:
	var b: Business = co.units[bid]; var need := b.bake_needs(p)
	p["buy_now"] = {}
	for iid in need:
		var miss: int = int(need[iid]) - b.inv.units(iid)
		if miss > 0: p["buy_now"][iid] = miss
	return p

func _init() -> void:
	Loc.setup("he")
	content = ContentDb.new(); content.load_all()
	check("content loads without errors", content.errors.is_empty(), str(content.errors))
	check("translations are loaded (a key becomes Hebrew text)", Loc.t("biz.bakery") != "biz.bakery", Loc.t("biz.bakery"))
	_test_basics(); _test_orders(); _test_contract(); _test_cafe(); _test_inspection(); _test_week(); _test_loan(); _test_save(); _test_events(); _test_goals(); _test_stars(); _test_market(); _test_owner()
	if not "quick" in OS.get_cmdline_user_args(): _balance(); _balance_market()
	print("RESULT failures=%d" % fails)
	quit(1 if fails > 0 else 0)

func _test_basics() -> void:
	var co := fresh()
	check("new game: 3,000 in cash, the bakery only, day 1", co.profile.cash == 3000 and co.units.keys() == ["bakery"] and co.day == 1)
	var b: Business = co.units["bakery"]; var ctx := co.plan_ctx("bakery")
	var over := b.empty_plan(); over["bake"]["carrot_cake"] = 20
	check("over the oven's capacity is rejected", not b.validate_plan(over, ctx).is_empty())
	var poor := b.empty_plan(); poor["buy_now"] = {"sweet": 2000}
	check("buying more than the cash allows is rejected", not co.validate_day({"bakery": poor}).is_empty())
	var locked := b.empty_plan(); locked["marketing"] = "flyers"
	check("a locked marketing option is rejected", not b.validate_plan(locked, ctx).is_empty())
	var miss := b.empty_plan(); miss["bake"]["strawberry_cake"] = 4
	check("missing ingredients are rejected", not b.validate_plan(miss, ctx).is_empty())
	check("an empty plan is valid", b.validate_plan(b.empty_plan(), ctx).is_empty())
	var a := fresh(42); var c := fresh(42); var d := fresh(43)
	a.start_morning(); c.start_morning(); d.start_morning()
	var ra := a.begin_runner("bakery"); var rc := c.begin_runner("bakery"); var rd := d.begin_runner("bakery")
	check("the same seed gives the same customers", str(ra.customers) == str(rc.customers), "n=%d" % ra.customers.size())
	check("a different seed gives different customers", str(ra.customers) != str(rd.customers))
	co.start_morning()
	var errs := co.commit_day({"bakery": starter_plan(co)}, "bakery")
	check("a starter plan is valid", errs.is_empty(), str(errs))
	var s := co.close_day()
	var u: Dictionary = s["units"]["bakery"]
	check("day 1 closes with sales", u["served"] > 0 and u["revenue"] > 0, "served=%d/%d revenue=%d profit=%d cash=%d" % [u["served"], u["customers"], u["revenue"], u["profit"], co.profile.cash])
	check("profit adds up", u["profit"] == u["revenue"] + u["b2b_revenue"] + u["internal_revenue"] - u["cogs"] - u["b2b_cost"] - u["internal_cost"] - u["waste_cost"] - u["marketing_cost"] - u["fixed"] - u["wages"] - u["other"])
	check("cash on hand equals the ledger", co.ledger.balance() == co.profile.cash, "%d vs %d" % [co.ledger.balance(), co.profile.cash])
	check("rent is an expense every day but is paid at the end of the week", u["fixed"] > 0 and co.ledger.total(-1, "rent") == 0)
	check("money values are whole numbers", typeof(u["revenue"]) == TYPE_INT and typeof(s["profit"]) == TYPE_INT and typeof(co.profile.cash) == TYPE_INT)
	check("the coach has something to say (1 to 3 lines)", s["coach"].size() >= 1 and s["coach"].size() <= 3, str(s["coach"].map(func(x): return Loc.msg(x))))
	check("the day advanced", co.day == 2 and co.phase == "morning")
	# goods: croissants do not keep, cakes sell old for a day and are thrown away after
	var inv := Inventory.new(); inv.reset({"base": 30, "dairy": 30, "sweet": 30}, ["base", "dairy", "sweet"], ["croissant", "carrot_cake"])
	inv.bake("croissant", {"base": 1, "dairy": 1}, 3); inv.bake("carrot_cake", {"base": 3, "dairy": 2, "sweet": 2}, 2)
	var w := inv.close_day({"croissant": 1, "carrot_cake": 2})
	check("unsold croissants are thrown away, cakes age", inv.stock("croissant") == 0 and inv.old("carrot_cake") == 2 and w.size() == 1)
	w = inv.close_day({"croissant": 1, "carrot_cake": 2})
	check("old cakes are thrown away after the second day", inv.stock("carrot_cake") == 0 and w.size() == 1)

func _test_orders() -> void:
	var co := fresh(); co.start_morning()
	var cash0 := co.profile.cash
	var e := co.place_order("bakery", "wholesale", {"base": 20, "dairy": 12})
	check("an order to the wholesaler is placed", e.is_empty(), Loc.msg(e))
	check("nothing is paid when ordering", co.profile.cash == cash0)
	co.commit_day({"bakery": co.units["bakery"].empty_plan()}, "bakery"); co.close_day()
	var units_before: int = co.units["bakery"].inv.units("base")
	var cash1 := co.profile.cash
	var r := co.start_morning()
	check("the order arrives the next morning and is paid on delivery", r["deliveries"].size() == 1 and co.units["bakery"].inv.units("base") == units_before + 20 and co.profile.cash == cash1 - (20 * 2 + 12 * 3))
	check("the galil supplier is locked at level 1", not co.place_order("bakery", "galil", {"base": 10}).is_empty())
	var b: Business = co.units["bakery"]
	var p := b.empty_plan(); p["buy_now"] = {"sweet": 5}
	var cash2 := co.profile.cash
	co.commit_day({"bakery": p}, "bakery")
	check("buying in the morning from the minimarket costs more", cash2 - co.profile.cash == 5 * int(content.world["suppliers"]["minimarket"]["prices"]["sweet"]))

func _test_contract() -> void:
	var co := fresh(); co.profile.add_xp(400); co.day = 4
	co.start_morning()
	var offer := {}
	for ev in co.pending_events: if ev["kind"] == "contract_offer": offer = ev
	check("the minimarket offers a contract (level 2, day 4)", not offer.is_empty())
	if offer.is_empty(): return
	co.resolve_event(offer, 0)
	check("the contract is active", co.contracts.has("minimarket") and co.contracts["minimarket"]["active"])
	co.subscribe("accountant", true)
	var p := starter_plan(co); p["bake"]["challah"] = 12; p["bake"]["croissant"] = 16; fill(co, "bakery", p)
	var res := co.reserved_for("bakery")
	check("the contract reserves today's bread", int(res.get("challah", 0)) == 6 and int(res.get("croissant", 0)) == 6, str(res))
	co.commit_day({"bakery": p}, "bakery")
	check("the delivery leaves the bakery and an invoice is opened", co.receivables.size() == 1 and co.units["bakery"].today["b2b_revenue"] == 6 * 12 + 6 * 9)
	var s := co.close_day()
	check("the delivery is income in the day's profit", s["units"]["bakery"]["b2b_revenue"] == 126)
	var due := int(co.receivables[0]["due"]) if not co.receivables.is_empty() else 0
	var got := 0
	while co.day <= due + 1:
		var r := co.start_morning()
		for v in r["collected"]: got += int(v["amount"])
		co.commit_day({"bakery": starter_plan(co)} if co.validate_day({"bakery": starter_plan(co)}).is_empty() else {"bakery": co.units["bakery"].empty_plan()}, "bakery")
		co.close_day()
	check("with the accountant the invoice is collected on its due day", got >= 126, "collected %d" % got)
	# missing deliveries cancel the contract
	var co2 := fresh(9); co2.profile.add_xp(400); co2.day = 4; co2.start_morning()
	for ev in co2.pending_events.duplicate(): if ev["kind"] == "contract_offer": co2.resolve_event(ev, 0)
	for i in 3:
		co2.start_morning(); co2.commit_day({"bakery": co2.units["bakery"].empty_plan()}, "bakery"); co2.close_day()
	check("three missed deliveries end the contract", co2.contracts.has("minimarket") and not co2.contracts["minimarket"]["active"])

func _test_cafe() -> void:
	var co := fresh(); co.start_morning()
	check("the café cannot open at level 1", not co.can_open("cafe").is_empty())
	co.profile.add_xp(400); co.profile.cash = 9000; co.ledger = Ledger.new(); co.ledger.start_cash = 9000
	var e := co.open_business("cafe")
	check("the café opens at level 3 and costs 6,500", e.is_empty() and co.profile.cash == 2500 and co.owns("cafe"), Loc.msg(e))
	check("the café is ready the next day", not co.unit_ready("cafe"))
	co.commit_day({"bakery": starter_plan(co)}, "bakery"); co.close_day()
	co.start_morning()
	check("the café is ready", co.unit_ready("cafe"))
	co.hire("yossi", "cafe")
	var bp := starter_plan(co); bp["bake"]["croissant"] = 22; fill(co, "bakery", bp)
	var cp: Dictionary = co.units["cafe"].empty_plan(); cp["transfer_in"] = {"croissant": 10}
	var errs := co.commit_day({"bakery": bp, "cafe": cp}, "bakery")
	check("both businesses open", errs.is_empty() and co.runners.size() == 2, str(errs))
	check("the café got 10 croissants from our bakery at the transfer price", co.units["cafe"].inv.stock("croissant") == 10 and co.units["cafe"].inv.goods["croissant"]["fresh_cost"] == 7)
	check("the transfer moves no cash", co.ledger.total(co.day, "internal") == 0)
	var s := co.close_day()
	var cu: Dictionary = s["units"]["cafe"]; var bu: Dictionary = s["units"]["bakery"]
	check("the café sold drinks made to order", cu["served"] > 0 and int(cu["sold"].get("cappuccino", 0)) + int(cu["sold"].get("americano", 0)) + int(cu["sold"].get("iced", 0)) > 0, str(cu["sold"]))
	check("the bakery booked the transfer as internal income", bu["internal_revenue"] == 70)
	check("the café's wages are an expense", cu["wages"] == 310)
	check("the company profit is the sum of both businesses minus company costs", s["profit"] == bu["profit"] + cu["profit"] - s["services"] - s["interest"] - s["bank_fee"])
	check("the ledger still matches the cash", co.ledger.balance() == co.profile.cash)

func _test_inspection() -> void:
	var co := fresh(); co.start_morning()
	var b: Business = co.units["bakery"]
	b.cleanliness = 30; b.equipment = 30
	var r := co.run_inspection("bakery")
	check("a dirty bakery with broken equipment fails the inspection and is fined", r["fails"] >= 2 and r["fine"] > 0 and co.ledger.total(-1, "fine") < 0, str(r["checks"]))
	b.cleanliness = 100; b.equipment = 100
	var r2 := co.run_inspection("bakery")
	check("a clean, maintained bakery passes", r2["passed"] and co.stats["inspections_passed"] == 1)

func _test_week() -> void:
	var co := fresh(); var cash_rent := 0
	for i in 6:
		co.start_morning()
		var p := starter_plan(co)
		if not co.validate_day({"bakery": p}).is_empty(): p = co.units["bakery"].empty_plan()
		co.commit_day({"bakery": p}, "bakery"); co.close_day()
	cash_rent = co.ledger.total(-1, "rent")
	check("after six working days the week is settled: rent paid", cash_rent == -(1400 + 280), str(cash_rent))
	check("the rest day is skipped", co.day == 8 and co.weekday() == 0, "day %d" % co.day)
	check("the weekly report is ready", not co.last_week.is_empty() and co.last_week["notes"].size() >= 2)

func _test_loan() -> void:
	var co := fresh(); co.profile.add_xp(400)
	var cash0 := co.profile.cash
	check("a loan can be taken", co.take_loan("large").is_empty() and co.profile.cash == cash0 + 10000)
	check("the same loan cannot be taken twice", not co.take_loan("large").is_empty())
	for i in 12:
		co.start_morning(); co.commit_day({"bakery": co.units["bakery"].empty_plan()}, "bakery"); co.close_day()
	check("weekly loan payments are made", co.ledger.total(-1, "loan_payment") == -920 * 2, str(co.ledger.total(-1, "loan_payment")))

func _test_save() -> void:
	var co := fresh(); co.profile.add_xp(400)
	for i in 3:
		co.start_morning(); co.commit_day({"bakery": starter_plan(co)}, "bakery"); co.close_day()
	co.place_order("bakery", "wholesale", {"base": 10})
	var d: Dictionary = JSON.parse_string(JSON.stringify(co.to_dict()))
	var e := Company.new(content); e.from_dict(d)
	check("the company survives saving and loading", e.day == co.day and e.profile.cash == co.profile.cash and e.units["bakery"].inv.units("base") == co.units["bakery"].inv.units("base")
		and e.orders.size() == 1 and e.ledger.balance() == e.profile.cash and typeof(e.orders[0]["cost"]) == TYPE_INT)
	var old := {"version": 1, "schema": 2, "profile": {"cash": 1107, "xp": 250, "level": 2, "reputation": 51}, "business": {"day": 3}}
	var g := Company.new(content); g.new_game(5); g.profile.from_dict(old["profile"], content)
	check("a 0.4 profile keeps experience and level", g.profile.xp == 250 and g.profile.level == 2)

func _owner(cash := -1) -> Company:
	var co := Company.new(content); co.start_owner(21)
	if cash >= 0: co.profile.cash = cash; co.ledger = Ledger.new(); co.ledger.start_cash = cash
	return co

# Plays the setup mornings by a style until the doors open; returns the days it took (or -1) and leaves the company on the opening morning.
func _run_setup(co: Company, style: String, limit := 20) -> int:
	var n := 0
	while co.in_setup() and n < limit:
		n += 1
		co.start_morning()
		if not co.in_setup(): break
		SetupBoard.auto(co, style)
		co.commit_day({}, co.worker); co.close_day()
	return n if not co.in_setup() else -1

func _test_owner() -> void:
	# the formats: a small space is the same business with smaller numbers; the file itself is untouched
	var small := content.business_db("bakery", "small")
	check("a small bakery has a smaller oven and a lower rent, the regular one is untouched",
		small["capacity"]["amount"] == 50 and small["weekly_costs"]["rent"] == 700 and content.businesses["bakery"]["capacity"]["amount"] == 80 and content.business_db("bakery", "regular") == content.businesses["bakery"])
	var co := _owner()
	check("the owner track starts with cash and no business", co.track == "owner" and co.units.is_empty() and co.profile.cash == int(content.tracks["owner"]["cash"]) and co.ledger.balance() == co.profile.cash)
	check("a new game is the existing bakery", fresh().track == "existing_bakery" and fresh().setup.is_empty())
	check("a regular bakery cannot be set up from a little cash alone", not _owner(2000).can_begin("bakery", "regular").is_empty())
	check("with the small loan it can", _owner(2000).can_begin("bakery", "regular", "small").is_empty())
	check("a loan is available on day one on this track only", co.loan_available("small") and not fresh().loan_available("small"))
	check("the terms of a loan: amount, weekly payment, weeks, total, cost", co.loan_terms("small") == {"amount": 5000, "weekly": 540, "weeks": 10, "total": 5400, "cost": 400})
	var cash0 := co.profile.cash
	var e := co.begin_business("bakery", "small")
	var cost := int(content.businesses["bakery"]["formats"]["small"]["setup_cost"])
	check("setting up a small bakery costs its price and the books match", e.is_empty() and co.profile.cash == cash0 - cost and co.ledger.balance() == co.profile.cash)
	check("the space is rented from today and the opening waits for the setup file", co.units["bakery"].lease_day == 1 and co.in_setup() and co.setup_left("bakery") == -1 and not co.setup.is_empty())
	check("a second business cannot be set up the same way", not co.begin_business("bakery", "small").is_empty())
	# the board of a food business: legal tasks and choices, in order; nothing opens until the required ones are done
	var ids: Array = SetupBoard.defs(co).map(func(t): return t["id"])
	check("a food business has the license chain", "health_inspection" in ids and "fire_safety" in ids and "license_application" in ids and "tax_file" in ids)
	check("the required tasks are the legal ones and the equipment", SetupBoard.pending_required(co).size() == 5)
	var tf := SetupBoard.def_of(co, "license_application")
	check("a task waits for the one it depends on", SetupBoard.status(co, tf) == "blocked" and not SetupBoard.start(co, "license_application", "self").is_empty())
	co.start_morning()
	check("setup mornings bring no ordinary cards", co.pending_events.is_empty() and co.inspection_today == "")
	var cash1 := co.profile.cash
	check("a task with a price takes it from the cash", SetupBoard.start(co, "tax_file", "accountant").is_empty() and co.profile.cash == cash1 - 250 and co.ledger.balance() == co.profile.cash)
	check("a started task cannot be started again", not SetupBoard.start(co, "tax_file", "self").is_empty())
	var broke := _owner(3000); broke.begin_business("bakery", "small"); broke.start_morning()
	check("a task you cannot afford is refused", not SetupBoard.start(broke, "tax_file", "accountant").is_empty())
	broke.profile.cash = -300; broke.ledger = Ledger.new(); broke.ledger.start_cash = -300
	check("with the cash box in the red a free option can still be started, so nobody is stuck", SetupBoard.start(broke, "tax_file", "self").is_empty())
	# a day passes; the tax file comes through (the accountant never fails), the license can start
	co.commit_day({}, "bakery"); var s := co.close_day()
	check("a setup day has no business results and the books match", s["units"].is_empty() and co.ledger.balance() == co.profile.cash)
	co.start_morning()
	check("the finished task is reported and done", SetupBoard.is_done(co, "tax_file") and co.last_report["setup"].size() == 1 and co.last_report["setup"][0]["result"] == "done")
	check("the next task opens up", SetupBoard.status(co, tf) == "ready")
	# the whole chain, by the careful style: it opens, and the doors open only when the required tasks are done
	var p := _owner(); p.begin_business("bakery", "small")
	var n := _run_setup(p, "pro")
	check("a careful owner gets through the setup and opens", n > 0 and p.unit_ready("bakery") and SetupBoard.mandatory_done(p), str(n))
	check("it takes more than the old fixed two days", n >= 4, str(n))
	check("rent ran during the setup and the books match", p.ledger.balance() == p.profile.cash)
	# a do-it-yourself owner is slower or the same, never faster, and can fail steps
	var worst := 0; var fastest := 99; var fails := 0
	for sd in range(1, 13):
		var q := Company.new(content); q.start_owner(sd * 11); q.begin_business("bakery", "small")
		var m := _run_setup(q, "diy"); worst = maxi(worst, m); fastest = mini(fastest, m)
		for id in q.setup["tasks"]: fails += int(q.setup["tasks"][id]["fails"])
	check("a do-it-yourself owner sometimes fails a step", fails > 0, str(fails))
	check("a do-it-yourself owner is not faster than a careful one", fastest >= n, "%d vs %d" % [fastest, n])
	# the same seed gives the same story
	var a1 := Company.new(content); a1.start_owner(77); a1.begin_business("bakery", "small"); var d1 := _run_setup(a1, "diy")
	var a2 := Company.new(content); a2.start_owner(77); a2.begin_business("bakery", "small"); var d2 := _run_setup(a2, "diy")
	check("the same seed and choices give the same setup", d1 == d2 and a1.profile.cash == a2.profile.cash)
	# the chances: cleaning and equipment change the health inspection; each failure makes the next try easier
	var h := _owner(); h.begin_business("bakery", "small")
	var ho: Dictionary = SetupBoard.option(SetupBoard.def_of(h, "health_inspection"), "standard")
	var base := SetupBoard.fail_pct(h, SetupBoard.def_of(h, "health_inspection"), ho)
	h.setup["tasks"]["cleaning"]["state"] = "done"
	check("a deep clean lowers the chance of failing the health inspection", SetupBoard.fail_pct(h, SetupBoard.def_of(h, "health_inspection"), ho) == base - 20)
	h.setup["tasks"]["equipment"]["state"] = "done"; h.setup["tasks"]["equipment"]["opt"] = "used"
	check("used equipment raises it", SetupBoard.fail_pct(h, SetupBoard.def_of(h, "health_inspection"), ho) == base - 10)
	h.setup["tasks"]["health_inspection"]["fails"] = 1
	check("after a failure the next try is easier", SetupBoard.fail_pct(h, SetupBoard.def_of(h, "health_inspection"), ho) == base - 25)
	# used equipment brings cash and a worn oven; new equipment is in perfect shape
	var u := _owner(); u.begin_business("bakery", "small"); u.start_morning()
	var cu := u.profile.cash
	SetupBoard.start(u, "equipment", "used")
	u.commit_day({}, "bakery"); u.close_day(); u.start_morning(); u.commit_day({}, "bakery"); u.close_day(); u.start_morning()
	check("used equipment brings cash and a worn oven", u.profile.cash >= cu + 300 - 200 and u.units["bakery"].equipment == 60, "%d %d" % [u.profile.cash - cu, u.units["bakery"].equipment])
	# a regular shop takes longer to fit out than a small one
	var rg := _owner(9000); rg.begin_business("bakery", "regular", "small")
	check("a regular shop takes longer to fit out", SetupBoard.option_days(rg, SetupBoard.option(SetupBoard.def_of(rg, "equipment"), "new")) == 3 and SetupBoard.option_days(p, SetupBoard.option(SetupBoard.def_of(p, "equipment"), "new")) == 2)
	check("a loan taken with the setup arrives with it", rg.loan_open("small") and rg.loans.size() == 1 and rg.ledger.balance() == rg.profile.cash)
	# the requirements follow the kind of business: no food pack, no health inspection
	var saved: Array = content.businesses["bakery"]["setup_packs"]
	content.businesses["bakery"]["setup_packs"] = ["common"]
	var o2 := Company.new(content); o2.start_owner(5); o2.begin_business("bakery", "small")
	var ids2: Array = SetupBoard.defs(o2).map(func(t): return t["id"])
	check("a business without the food pack has no health inspection or fire safety", not ("health_inspection" in ids2) and not ("fire_safety" in ids2) and "tax_file" in ids2)
	check("and it opens as soon as its own required tasks are done", _run_setup(o2, "pro") > 0 and o2.unit_ready("bakery"))
	content.businesses["bakery"]["setup_packs"] = saved
	# every legal task says whether it is a real requirement; every required task has a free option
	var allgood := true
	for t in content.setup_tasks_for("bakery"):
		if t["kind"] == "legal" and not t.has("real"): allgood = false
		if bool(t.get("required", false)) and not t["options"].any(func(o): return int(o["cost"]) == 0): allgood = false
	check("legal tasks are marked real or illustrative, and nobody can get stuck without cash", allgood)
	# saving in the middle of a setup keeps the board
	var sv := _owner(); sv.begin_business("bakery", "small"); sv.start_morning(); SetupBoard.start(sv, "tax_file", "accountant")
	var back := Company.new(content); back.from_dict(JSON.parse_string(JSON.stringify(sv.to_dict())))
	check("a setup in progress survives saving and loading", back.track == "owner" and back.in_setup() and back.units["bakery"].format == "small" and back.units["bakery"].lease_day == 1
		and back.units["bakery"].db["capacity"]["amount"] == 50 and back.ledger.balance() == back.profile.cash and back.setup["tasks"]["tax_file"]["state"] == "active" and typeof(back.setup["tasks"]["tax_file"]["due"]) == TYPE_INT)
	# the owner track is not a shortcut: a careless owner loses money, and a balanced one does not
	for sk in ["good", "poor"]:
		var o := _owner(); o.begin_business("bakery", "small")
		var after_setup := o.profile.cash
		while o.day <= 45:
			o.start_morning()
			for ev in o.pending_events.duplicate(): o.resolve_event(ev, 0)
			if o.in_setup(): SetupBoard.auto(o, "pro"); o.commit_day({}, "bakery"); o.close_day(); continue
			var pl := SimPolicies.plan_for(o, "bakery", {"order_ahead": true} if sk == "good" else {"max_bake": true, "upkeep": false})
			if not o.commit_day({"bakery": pl}, "bakery").is_empty(): o.commit_day({"bakery": o.units["bakery"].empty_plan()}, "bakery")
			if sk == "good": SimPolicies.order_ahead(o, "bakery")
			o.close_day()
		if sk == "good": check("a balanced small owner has more than the cash left after paying for the setup", o.profile.cash - o.debt() > after_setup + 1500, "%d vs %d" % [o.profile.cash, after_setup])
		else: check("a careless owner has less", o.profile.cash - o.debt() < after_setup, "%d vs %d" % [o.profile.cash, after_setup])

func _test_events() -> void:
	var co := fresh(); co.day = 6
	co.units["bakery"].equipment = 5
	var found := {}
	for i in 12:
		co.start_morning()
		for ev in co.pending_events: if ev["id"] == "oven_breakdown": found = ev
		if not found.is_empty(): break
		co.day += 1; co.ev_state["last"] = {}
	check("a neglected oven breaks down", not found.is_empty())
	if found.is_empty(): return
	var cash0 := co.profile.cash
	co.resolve_event(found, 0)
	check("fixing it now costs 450 and restores the oven", co.profile.cash == cash0 - 450 and co.units["bakery"].equipment == 100)

func _test_goals() -> void:
	var co := fresh()
	var first: Array = Goals.active(co)
	check("three goals are shown", first.size() == 3)
	co.stats["sold_total"] = 20
	var met := Goals.update(co)
	check("selling 15 items completes the first goal and pays experience", met.size() >= 1 and met[0]["id"] == "first_sales" and co.profile.xp >= 30)

func _balance() -> void:
	var days := 42
	print("--- balance: %d days x 5 seeds per strategy" % days)
	var strategies := {
		"idle (does nothing)": {"idle": true},
		"bakes the oven full": {"max_bake": true},
		"balanced": {},
		"balanced + orders ahead": {"order_ahead": true},
		"balanced + social post": {"marketing": "social_post", "order_ahead": true},
		"balanced + promo": {"marketing": "promo", "order_ahead": true},
		"overpriced (150%)": {"price_pct": 150, "order_ahead": true},
		"underpriced (65%)": {"price_pct": 65, "order_ahead": true},
		"no upkeep": {"upkeep": false, "order_ahead": true},
		"contract + accountant": {"order_ahead": true, "contract": true, "accountant": true},
		"full: café + upgrades": {"order_ahead": true, "contract": true, "accountant": true, "cafe": true, "upgrades": true},
		"full + loan for the café": {"order_ahead": true, "contract": true, "accountant": true, "cafe": true, "upgrades": true, "loan": true},
	}
	var res := {}
	for name in strategies:
		var sum := {"profit_per_day": 0, "cash": 0, "rep": 0, "served": 0, "lost": 0, "waste": 0, "bankrupt_days": 0, "cafe_day": 0, "level": 0, "inspections": 0, "goals": 0, "late_profit": 0}
		var errors: Array = []; var min_cash := 1 << 30; var cafe_n := 0
		for sd in 5:
			var r := SimPolicies.play(content, 100 + sd, days, strategies[name])
			for k in sum: sum[k] += int(r[k])
			if int(r["cafe_day"]) > 0: cafe_n += 1
			min_cash = mini(min_cash, r["min_cash"]); errors.append_array(r["errors"])
		for k in sum: sum[k] /= 5
		res[name] = sum
		print("%-26s late %5d | profit/day %5d | worth %7d | rep %3d | served %4d lost %4d | waste %5d | low cash %6d | broke %d | café %d (day %d) | lvl %d | goals %d" % [name, sum["late_profit"], sum["profit_per_day"], sum["cash"], sum["rep"], sum["served"], sum["lost"], sum["waste"], min_cash, sum["bankrupt_days"], cafe_n, sum["cafe_day"], sum["level"], sum["goals"]])
		if not errors.is_empty(): check("no invariant errors in '%s'" % name, false, str(errors.slice(0, 3)))
	var bal: int = res["balanced + orders ahead"]["profit_per_day"]
	check("doing nothing loses money (rent is due anyway)", res["idle (does nothing)"]["profit_per_day"] < 0)
	check("a balanced owner makes a profit", res["balanced"]["profit_per_day"] > 80, str(res["balanced"]["profit_per_day"]))
	check("ordering ahead beats buying every morning", bal > res["balanced"]["profit_per_day"], "%d vs %d" % [bal, res["balanced"]["profit_per_day"]])
	check("baking blindly wastes more than planning", res["bakes the oven full"]["waste"] > res["balanced"]["waste"])
	check("overpricing is worse than a fair price", res["overpriced (150%)"]["profit_per_day"] < bal)
	check("underpricing is worse than a fair price", res["underpriced (65%)"]["profit_per_day"] < bal)
	check("skipping cleaning and maintenance costs money (fines, breakdowns)", res["no upkeep"]["profit_per_day"] < bal, "%d vs %d" % [res["no upkeep"]["profit_per_day"], bal])
	check("the promotion helps but does not dominate (under 25 percent better)", res["balanced + promo"]["profit_per_day"] < bal * 125 / 100, "%d vs %d" % [res["balanced + promo"]["profit_per_day"], bal])
	check("a contract with the minimarket does not cost profit (with the accountant's fee)", res["contract + accountant"]["profit_per_day"] > bal - 40, "%d vs %d" % [res["contract + accountant"]["profit_per_day"], bal])
	check("the café opens within six weeks for a careful owner", res["full: café + upgrades"]["cafe_day"] > 0)
	check("with the café open, the company earns clearly more per day (last two weeks)", res["full: café + upgrades"]["late_profit"] > res["contract + accountant"]["late_profit"] + 40, "%d vs %d" % [res["full: café + upgrades"]["late_profit"], res["contract + accountant"]["late_profit"]])
	check("no strategy runs away (worth after 6 weeks under 60,000)", res["full: café + upgrades"]["cash"] < 60000, str(res["full: café + upgrades"]["cash"]))
	check("a profitable business keeps its customers (reputation 45+)", res["balanced + orders ahead"]["rep"] >= 45, str(res["balanced + orders ahead"]["rep"]))

func _test_stars() -> void:
	var good := {"profit": 120, "units": {"bakery": {"closed": false, "served": 10, "customers": 11, "lost_stock": 0, "walkouts": 0}}}
	check("a profitable day with everyone served and nobody lost has three stars", Coach.stars(good) == 3)
	var loss := {"profit": -50, "units": {"bakery": {"closed": false, "served": 10, "customers": 11, "lost_stock": 0, "walkouts": 0}}}
	check("a loss takes the profit star", Coach.stars(loss) == 2)
	var lost := {"profit": 80, "units": {"bakery": {"closed": false, "served": 6, "customers": 11, "lost_stock": 3, "walkouts": 2}}}
	check("losing customers takes the other two stars", Coach.stars(lost) == 1)
	var closed := {"profit": -300, "units": {"bakery": {"closed": true, "served": 0, "customers": 0, "lost_stock": 0, "walkouts": 0}}}
	check("a day with every business closed has no stars", Coach.stars(closed) == 0)
	var two := {"profit": 90, "units": {"bakery": {"closed": false, "served": 8, "customers": 8, "lost_stock": 0, "walkouts": 0}, "cafe": {"closed": true, "served": 0, "customers": 0, "lost_stock": 0, "walkouts": 0}}}
	check("a closed business does not count against the open one", Coach.stars(two) == 3)
	# the real first day of the starter plan
	var co := fresh(); co.start_morning(); co.commit_day({"bakery": starter_plan(co)}, "bakery")
	var s := co.close_day()
	check("a real first day has a rating between 0 and 3", Coach.stars(s) >= 0 and Coach.stars(s) <= 3, str(Coach.stars(s)))

# ---------------------------------------------------------------- the minimarket
func _market_company(seed_value := 7) -> Company:
	var co := fresh(seed_value)
	co.profile.add_xp(1600); co.book("relief", 20000, "", "test")
	return co

func _test_market() -> void:
	var co := fresh()
	check("the market is not open at level 1", not co.can_open("market").is_empty())
	co = _market_company()
	check("at level 6 with the cash the market can open", co.can_open("market").is_empty(), str(co.can_open("market")))
	var cash0 := co.profile.cash
	check("opening it costs 9,000", co.open_business("market").is_empty() and co.profile.cash == cash0 - 9000)
	check("it is ready the next day, not today", not co.unit_ready("market") and co.owns("market"))
	co.start_morning(); co.commit_day({"bakery": co.units["bakery"].empty_plan()}, "bakery"); co.close_day()
	check("the day after it is ready", co.unit_ready("market"))
	var m: Business = co.units["market"]
	check("a retail shop makes nothing and sells goods it buys", m.is_retail() and m.db["ingredients"].is_empty() and m.goods_input_ids().size() == 8)
	# shelves
	var cap := m.capacity(0)
	var big := {"eggs": cap + 6}
	check("an order that does not fit the shelves is refused", co.place_order("market", "wholesale", big).has("k"), str(co.place_order("market", "wholesale", big)))
	var sug := co.suggest_order("market"); var pieces := 0
	for k in sug: pieces += int(sug[k])
	check("the suggested order fits the shelves", pieces <= cap and pieces > 0, "%d of %d" % [pieces, cap])
	check("the suggested order can be placed", co.place_order("market", "wholesale", sug).is_empty())
	var over := m.empty_plan(); over["buy_now"] = {"water": cap + 12}
	check("a plan that buys more than the shelves hold is invalid", not m.validate_plan(over, co.plan_ctx("market")).is_empty())
	# a morning with deliveries, a suggested plan, a day, and the books
	co.start_morning()
	var plans := {}
	for bid in co.units: if co.unit_ready(bid): plans[bid] = co.suggest_plan(bid, plans)
	var errs := co.validate_day(plans)
	check("the suggested plans are valid", errs.is_empty(), str(errs))
	check("the suggested plan for the market fits the shelves", m.stock_total() + _sum(plans["market"]["buy_now"]) <= cap)
	co.commit_day(plans, "market")
	var s := co.close_day()
	var u: Dictionary = s["units"]["market"]
	check("the market sold goods", u["served"] > 0 and u["revenue"] > 0, "served %d of %d, revenue %d" % [u["served"], u["customers"], u["revenue"]])
	check("the books match the cash", co.ledger.balance() == co.profile.cash)
	check("the market's profit adds up", u["profit"] == u["revenue"] + u["b2b_revenue"] + u["internal_revenue"] - u["cogs"] - u["b2b_cost"] - u["internal_cost"] - u["waste_cost"] - u["marketing_cost"] - u["fixed"] - u["wages"] - u["other"])
	# fruit spoils: a shelf of fruit nobody buys is thrown away after two days
	var inv: Inventory = m.inv
	inv.add_goods("fruit", 10, 70, 7)
	var w1 := inv.close_day(m.shelf_days()); var w2 := inv.close_day(m.shelf_days())
	var wasted := 0
	for w in w1 + w2: if w["product"] == "fruit": wasted += int(w["pieces"])
	check("unsold fruit is thrown away after its two days", wasted == 10 and inv.stock("fruit") == 0, "wasted %d" % wasted)

func _sum(d: Dictionary) -> int:
	var t := 0
	for k in d: t += int(d[k])
	return t

func _balance_market() -> void:
	var days := 90
	print("--- market balance: %d days x 3 seeds" % days)
	var base := {"order_ahead": true, "contract": true, "accountant": true, "cafe": true, "loan": true}
	var variants := {"café, no market": base, "café + market": base.merged({"market": true})}
	var out := {}
	for name in variants:
		var late := 0; var worth := 0; var opened := 0; var mday := 0; var errors: Array = []; var broke := 0
		for sd in 3:
			var r := SimPolicies.play(content, 200 + sd, days, variants[name])
			late += int(r["late_profit"]); worth += int(r["cash"]); broke += int(r["bankrupt_days"]); errors.append_array(r["errors"])
			if int(r["market_day"]) > 0: opened += 1; mday += int(r["market_day"])
		out[name] = {"late": late / 3, "worth": worth / 3, "opened": opened, "mday": mday / maxi(1, opened), "broke": broke}
		print("%-18s late profit/day %5d | worth %7d | market opened in %d of 3 (day %d) | broke days %d" % [name, late / 3, worth / 3, opened, mday / maxi(1, opened), broke])
		if not errors.is_empty(): check("no invariant errors in '%s'" % name, false, str(errors.slice(0, 3)))
	check("the market opens for a careful owner within 90 days", out["café + market"]["opened"] >= 2, str(out["café + market"]))
	check("with the market open the company earns more per day than without it", out["café + market"]["late"] > out["café, no market"]["late"] + 30, "%d vs %d" % [out["café + market"]["late"], out["café, no market"]["late"]])
	check("the market does not make the game run away (worth under 90,000 after 90 days)", out["café + market"]["worth"] < 90000, str(out["café + market"]["worth"]))
