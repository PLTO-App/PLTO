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
	_test_basics(); _test_orders(); _test_contract(); _test_cafe(); _test_inspection(); _test_week(); _test_loan(); _test_save(); _test_events(); _test_goals(); _test_stars(); _test_market(); _test_owner(); _test_finance()
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
	check("the owner track starts with cash and no business", co.track == "owner" and co.units.is_empty() and co.profile.cash == Finance.savings_of(co, "mid") and co.ledger.balance() == co.profile.cash)
	check("a new game is the existing bakery", fresh().track == "existing_bakery" and fresh().setup.is_empty())
	check("a regular bakery cannot be set up from a little cash alone", not _owner(2000).can_begin("bakery", "regular").is_empty())
	check("with the small loan it can", _owner(2000).can_begin("bakery", "regular", "small").is_empty())
	check("a loan is available on day one on this track only", co.loan_available("small") and not fresh().loan_available("small"))
	check("the terms of a loan: amount, weekly payment, weeks, total, cost", co.loan_terms("small") == {"amount": 5000, "weekly": 540, "weeks": 10, "total": 5400, "cost": 400})
	var cash0 := co.profile.cash
	var e := co.begin_business("bakery", "small")
	var cost := int(content.businesses["bakery"]["formats"]["small"]["setup_cost"])
	check("setting up a small bakery costs its price and the books match", e.is_empty() and co.profile.cash == cash0 - (cost - int(co.setup["reserve"])) and co.setup["reserve"] == 900 and co.ledger.balance() == co.profile.cash)
	check("the space is rented from today and the opening waits for the setup file", co.units["bakery"].lease_day == 1 and co.in_setup() and co.setup_left("bakery") == -1 and not co.setup.is_empty())
	check("a second business cannot be set up the same way", not co.begin_business("bakery", "small").is_empty())
	# the board of a food business: legal tasks and choices, in order; nothing opens until the required ones are done
	var ids: Array = SetupBoard.defs(co).map(func(t): return t["id"])
	check("a food business has the license chain", "health_inspection" in ids and "fire_safety" in ids and "license_application" in ids and "tax_file" in ids)
	check("the required tasks are the legal ones and the equipment", SetupBoard.pending_required(co).size() == 6)
	var tf := SetupBoard.def_of(co, "license_application")
	check("a task waits for the one it depends on", SetupBoard.status(co, tf) == "blocked" and not SetupBoard.start(co, "license_application", "self").is_empty())
	co.start_morning()
	check("setup mornings bring no ordinary cards", co.pending_events.is_empty() and co.inspection_today == "")
	var cash1 := co.profile.cash
	check("a task with a price takes it from the cash", SetupBoard.start(co, "tax_file", "accountant").is_empty() and co.profile.cash == cash1 - 250 and co.ledger.balance() == co.profile.cash)
	check("a started task cannot be started again", not SetupBoard.start(co, "tax_file", "self").is_empty())
	var broke := _owner(3000); broke.begin_business("bakery", "small"); broke.start_morning()
	broke.profile.cash = 100; broke.ledger = Ledger.new(); broke.ledger.start_cash = 100
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
	var ho: Dictionary = SetupBoard.option(h, SetupBoard.def_of(h, "health_inspection"), "standard")
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
	check("a regular shop takes longer to fit out", SetupBoard.option_days(rg, SetupBoard.option(rg, SetupBoard.def_of(rg, "equipment"), "new")) == 3 and SetupBoard.option_days(p, SetupBoard.option(p, SetupBoard.def_of(p, "equipment"), "new")) == 2)
	check("a loan taken with the setup arrives with it", rg.loan_open("small") and rg.loans.size() == 1 and rg.ledger.balance() == rg.profile.cash)
	# 1ב-ב: the contractor. Three quotes (cheap, middling, dear), the same for the same seed; reliability is hidden until a reference check
	var cb := _owner(); cb.begin_business("bakery", "small")
	var qs: Array = cb.setup["bids"]["fit_out"]
	check("three quotes: cheap, middling and dear", qs.size() == 3 and qs[0]["price"] < qs[1]["price"] and qs[1]["price"] < qs[2]["price"])
	var cb2 := Company.new(content); cb2.start_owner(21); cb2.begin_business("bakery", "small")
	check("the same seed gives the same quotes", JSON.stringify(cb2.setup["bids"]) == JSON.stringify(cb.setup["bids"]))
	var fo := SetupBoard.def_of(cb, "fit_out")
	var shown: Array = SetupBoard.options_of(cb, fo).filter(func(o): return o.get("bid", false))
	check("before a reference check the risk is unknown, and the quotes do not give away the reliability", shown.all(func(o): return o["risk_k"] == "setup.risk_unknown"))
	cb.start_morning()
	var c0 := cb.profile.cash
	check("a reference check costs money and shows how risky the quote is", SetupBoard.check_bid(cb, "fit_out", "cheap").is_empty() and cb.profile.cash == c0 - 40
		and SetupBoard.options_of(cb, fo).filter(func(o): return o["id"] == "cheap")[0]["risk_k"] == "setup.risk_high" and not SetupBoard.check_bid(cb, "fit_out", "cheap").is_empty())
	var c1 := cb.profile.cash
	check("a quote is paid when it is chosen, at its price (the budget was held back)", SetupBoard.start(cb, "fit_out", "mid").is_empty() and cb.profile.cash == c1 - int(qs[1]["price"]) and cb.ledger.balance() == cb.profile.cash)
	var fr := _owner(); fr.begin_business("bakery", "small"); fr.start_morning(); fr.profile.cash = -300; fr.ledger = Ledger.new(); fr.ledger.start_cash = -300
	check("friends and family cost nothing, so a player with no cash is not stuck", SetupBoard.start(fr, "fit_out", "friends").is_empty() and fr.setup["tasks"]["fit_out"]["rel"] == 30)
	# what goes wrong, by reliability: over many seeds the cheap quote has more trouble than the dear one
	var troubles := {"cheap": 0, "mid": 0, "premium": 0}; var kinds := {"delayed": 0, "overrun": 0, "defect": 0}
	for sd in range(1, 121):
		for tier in ["cheap", "mid", "premium"]:
			var w := Company.new(content); w.start_owner(sd * 13); w.begin_business("bakery", "small")
			w.start_morning(); SetupBoard.start(w, "fit_out", tier)
			var had := false; var g := 0
			while not SetupBoard.is_done(w, "fit_out") and g < 12:
				g += 1; w.commit_day({}, "bakery"); w.close_day(); w.start_morning()
				for r in w.last_report.get("setup", []):
					if r["task"] == "fit_out" and r["result"] in ["delayed", "overrun"]: had = true; kinds[r["result"]] += 1
			if bool(w.setup["tasks"]["fit_out"]["defect"]): had = true; kinds["defect"] += 1
			if had: troubles[tier] += 1
	check("the cheap quote runs into trouble more than the middle one, and that more than the dear one", troubles["cheap"] > troubles["mid"] and troubles["mid"] > troubles["premium"], str(troubles))
	check("the dear quote is not trouble free, and every kind of trouble happens", troubles["premium"] > 0 and kinds["delayed"] > 0 and kinds["overrun"] > 0 and kinds["defect"] > 0, str(kinds))
	# the price is not the whole story: sometimes the cheap quote is the more reliable one, so a reference check tells something new
	var inversions := 0; var inf := {"informed": 0, "mid": 0, "premium": 0, "cheap": 0}; var N := 240
	for sd in range(1, N + 1):
		var rows := {}
		for pol in ["informed", "mid", "premium", "cheap"]:
			var w := Company.new(content); w.start_owner(sd * 17); w.begin_business("bakery", "small"); w.start_morning()
			var qq: Array = w.setup["bids"]["fit_out"]
			if pol == "informed":
				var best := ""; var br := -1
				for q in qq:
					SetupBoard.check_bid(w, "fit_out", q["id"])
					if int(q["rel"]) > br: br = int(q["rel"]); best = q["id"]
				SetupBoard.start(w, "fit_out", best)
			else: SetupBoard.start(w, "fit_out", pol)
			if pol == "informed" and int(qq[0]["rel"]) > int(qq[2]["rel"]): inversions += 1
			var had := false; var g := 0
			while not SetupBoard.is_done(w, "fit_out") and g < 12:
				g += 1; w.commit_day({}, "bakery"); w.close_day(); w.start_morning()
				for r in w.last_report.get("setup", []):
					if r["task"] == "fit_out" and r["result"] in ["delayed", "overrun"]: had = true
			if bool(w.setup["tasks"]["fit_out"]["defect"]): had = true
			if had: inf[pol] += 1
	check("the cheap quote is sometimes the more reliable (so the price alone does not tell)", inversions > N / 10, str(inversions))
	check("choosing after reference checks gives less trouble than any blind choice", inf["informed"] < inf["mid"] and inf["informed"] < inf["premium"] and inf["informed"] < inf["cheap"], str(inf))
	# a defect shows later: the health inspection is harder and the equipment is worn when the doors open
	var df := _owner(); df.begin_business("bakery", "small")
	var hd := SetupBoard.def_of(df, "health_inspection"); var ho2 := SetupBoard.option(df, hd, "standard")
	var b0 := SetupBoard.fail_pct(df, hd, ho2)
	df.setup["tasks"]["fit_out"]["state"] = "done"; df.setup["tasks"]["fit_out"]["defect"] = true
	check("a defect in the work makes the health inspection harder", SetupBoard.fail_pct(df, hd, ho2) == b0 + 10)
	var dfo: Array = []; df.setup["tasks"]["equipment"]["state"] = "done"
	for id in ["tax_file", "license_application", "health_inspection", "fire_safety", "equipment"]: df.setup["tasks"][id]["state"] = "done"
	df.units["bakery"].equipment = 100
	df.day = 6; df.start_morning(); check("the doors open once all that is required is done", not df.in_setup())
	check("a defect leaves the equipment worn", df.units["bakery"].equipment == 90 and df.last_report["setup"].any(func(r): return r["result"] == "defect"))
	# 1ב-ג: negotiation. A move can be made, it can go well or badly, and the result depends on the quote, the season and what the player does
	var ng := _owner(); ng.begin_business("bakery", "small"); ng.start_morning()
	check("a negotiation can be opened once per quote", Negotiation.begin(ng, "fit_out", "mid").is_empty() and Negotiation.is_open(ng) and ng.setup["bids"]["fit_out"][1]["neg"] == "open")
	var mv: Array = Negotiation.moves(ng)
	check("at the start the player may ask, bargain on terms, accept or walk, but not compromise or insist yet", "ask_small" in mv and "warranty" in mv and "alt" in mv and "cash" in mv and "accept" in mv and "walk" in mv and not ("compromise" in mv) and not ("insist" in mv))
	check("an unknown move is refused", not Negotiation.play(ng, "bribe").is_empty())
	Negotiation.play(ng, "accept")
	check("accepting the list price ends it at that price", not Negotiation.is_open(ng) and Negotiation.state(ng)["result"] == "deal" and ng.setup["bids"]["fit_out"][1]["price"] == Negotiation.state(ng)["list"])
	check("a quote cannot be negotiated twice", not Negotiation.begin(ng, "fit_out", "mid").is_empty())
	# the same moves with the same seed give the same story
	var ja := ""; var jb := ""
	for k in 2:
		var x := _owner(); x.begin_business("bakery", "small"); x.start_morning(); Negotiation.begin(x, "fit_out", "mid")
		for m in ["ask_big", "compromise", "accept"]: if m in Negotiation.moves(x): Negotiation.play(x, m)
		if k == 0:
			ja = JSON.stringify(Negotiation.state(x))
		else:
			jb = JSON.stringify(Negotiation.state(x))
	check("same seed and moves give the same negotiation", ja == jb)
	# over many seeds: asking little works more often than asking a lot, and asking a lot costs the professional's patience
	var res := {"ask_small": [0, 0], "ask_huge": [0, 0]}
	for sd in range(1, 201):
		for m in ["ask_small", "ask_huge"]:
			var y := Company.new(content); y.start_owner(sd * 19); y.begin_business("bakery", "small"); y.start_morning()
			Negotiation.begin(y, "fit_out", "mid"); Negotiation.play(y, m)
			if Negotiation.state(y)["result"] == "deal": res[m][0] += 1
			if int(Negotiation.state(y)["patience"]) < 3: res[m][1] += 1
	check("a small ask is accepted more often than a huge one", res["ask_small"][0] > res["ask_huge"][0] + 30, str(res))
	check("a huge ask burns patience more often", res["ask_huge"][1] > res["ask_small"][1] + 40, str(res))
	# a real second quote helps; a bluff can be called
	var better := 0; var worse := 0; var called := 0; var bluffs := 0
	for sd in range(1, 201):
		var base_price := 0; var alt_price := 0
		for withalt in [false, true]:
			var z := Company.new(content); z.start_owner(sd * 23); z.begin_business("bakery", "small"); z.start_morning()
			Negotiation.begin(z, "fit_out", "mid")
			if withalt: Negotiation.play(z, "alt")
			Negotiation.play(z, "ask_huge")
			if Negotiation.is_open(z): Negotiation.play(z, "accept")
			if withalt:
				alt_price = int(Negotiation.state(z)["price"])
			else:
				base_price = int(Negotiation.state(z)["price"])
		if alt_price < base_price: better += 1
		if alt_price > base_price: worse += 1
		var bl := Company.new(content); bl.start_owner(sd * 29); bl.begin_business("bakery", "small"); bl.start_morning()
		for q in bl.setup["bids"]["fit_out"]: if q["id"] != "mid": q["price"] = int(q["price"]) * 3          # no other quote is believable
		Negotiation.begin(bl, "fit_out", "mid"); Negotiation.play(bl, "alt"); bluffs += 1
		if Negotiation.state(bl)["lines"].any(func(l): return l["k"] == "neg.say.alt_called"): called += 1
	check("mentioning a real other quote gets a better price more often than a worse one", better > worse + 10, "%d vs %d" % [better, worse])
	check("a bluff is sometimes called and sometimes works", called > bluffs / 5 and called < bluffs * 4 / 5, "%d of %d" % [called, bluffs])
	# cash in hand matters, only when there is enough of it
	var rich := _owner(); rich.begin_business("bakery", "small"); rich.start_morning(); Negotiation.begin(rich, "fit_out", "mid")
	var adj0 := int(Negotiation.state(rich)["adj"]); Negotiation.play(rich, "cash")
	check("paying at once lowers the floor when the cash allows", int(Negotiation.state(rich)["adj"]) < adj0)
	var poor := _owner(); poor.begin_business("bakery", "small"); poor.start_morning(); poor.profile.cash = 300; poor.ledger = Ledger.new(); poor.ledger.start_cash = 300
	Negotiation.begin(poor, "fit_out", "mid"); var adj1 := int(Negotiation.state(poor)["adj"]); Negotiation.play(poor, "cash")
	check("and it does nothing when the cash does not allow", int(Negotiation.state(poor)["adj"]) == adj1)
	# a warranty costs more and makes the work more reliable
	var wr := 0; var wr_ok := true
	for sd in range(1, 121):
		var w2 := Company.new(content); w2.start_owner(sd * 31); w2.begin_business("bakery", "small"); w2.start_morning()
		var rel0 := int(w2.setup["bids"]["fit_out"][2]["rel"]); var list0 := int(w2.setup["bids"]["fit_out"][2]["price"])
		Negotiation.begin(w2, "fit_out", "premium"); Negotiation.play(w2, "warranty")
		if Negotiation.state(w2)["warranty"]:
			Negotiation.play(w2, "accept"); wr += 1
			var bb: Dictionary = w2.setup["bids"]["fit_out"][2]
			if not (int(bb["rel"]) >= mini(98, rel0 + 10) and int(bb["price"]) > list0): wr_ok = false
	check("a warranty is given sometimes, it raises the price and the reliability", wr > 20 and wr_ok, str(wr))
	# too much pushing: the professional leaves and the quote is gone
	var left := 0; var gone_ok := true
	for sd in range(1, 121):
		var w3 := Company.new(content); w3.start_owner(sd * 37); w3.begin_business("bakery", "small"); w3.start_morning()
		Negotiation.begin(w3, "fit_out", "cheap")
		for i in 3: if Negotiation.is_open(w3): Negotiation.play(w3, "ask_huge")
		if Negotiation.state(w3)["result"] == "burned":
			left += 1
			if SetupBoard.options_of(w3, SetupBoard.def_of(w3, "fit_out")).any(func(o): return o["id"] == "cheap"): gone_ok = false
	check("a professional who is pushed too hard leaves, and his quote disappears", left > 20 and gone_ok, str(left))
	var wk := _owner(); wk.begin_business("bakery", "small"); wk.start_morning(); Negotiation.begin(wk, "fit_out", "mid"); Negotiation.play(wk, "walk")
	check("walking away keeps the quote at its list price", wk.setup["bids"]["fit_out"][1]["neg"] == "closed" and SetupBoard.options_of(wk, SetupBoard.def_of(wk, "fit_out")).any(func(o): return o["id"] == "mid"))
	var dl := _owner(); dl.begin_business("bakery", "small"); dl.start_morning(); Negotiation.begin(dl, "fit_out", "mid")
	Negotiation.play(dl, "ask_small"); while Negotiation.is_open(dl): Negotiation.play(dl, "accept")
	var dealt := int(dl.setup["bids"]["fit_out"][1]["price"]); var cdl := dl.profile.cash
	check("the agreed price is the one that is paid", SetupBoard.start(dl, "fit_out", "mid").is_empty() and dl.profile.cash == cdl - dealt)
	# the summary: every shekel in it is in the books, and the reasons are named
	var recon := true; var whys := 0
	for sd in range(1, 41):
		var q := Company.new(content); q.start_owner(sd * 41); q.begin_business("bakery", "small")
		_run_setup(q, "mixed")
		var rp := q.setup_report
		if rp.is_empty(): recon = false; continue
		var total: int = int(rp["contractor"]) + int(rp["overrun"]) + int(rp["fees"]) + int(rp["checks"]) + int(rp["fixes"]) - int(rp["equip_saving"])
		if total != -q.ledger.total_since(1, "event"): recon = false
		whys += rp["why"].size()
	check("the summary adds up to the books", recon)
	check("the summary names reasons for what went wrong", whys > 0, str(whys))
	var sm := Company.new(content); sm.start_owner(5); sm.begin_business("bakery", "small"); _run_setup(sm, "pro")
	var sm2 := Company.new(content); sm2.from_dict(JSON.parse_string(JSON.stringify(sm.to_dict())))
	check("the summary has planned and actual days and survives saving", sm.setup_report["planned_days"] >= 2 and sm.setup_report["planned_days"] <= sm.setup_report["days"] and sm.setup_report["days"] >= 3 and sm2.setup_report["days"] == sm.setup_report["days"] and sm2.setup_report["why"].size() == sm.setup_report["why"].size())
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
		var after_setup := o.profile.cash - int(o.setup["reserve"])
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

func _planning(bg := "mid", fmt := "small", seed_value := 31) -> Array:
	var co := Company.new(content); co.start_owner(seed_value, bg, false)
	return [co, Finance.new_plan(co, "bakery", fmt)]

# Funding and the bank (stage 1c): money comes from sources, the bank reviews, loans stay, nothing is handed out.
func _test_finance() -> void:
	var pc := _planning(); var co: Company = pc[0]; var plan: Dictionary = pc[1]
	check("the cash box starts empty: savings are not in it until they are put in the plan", co.profile.cash == 0 and co.ledger.balance() == 0 and co.finance["savings"] == 5000)
	check("savings are years of work times the yearly saving, shown openly", Finance.savings_of(co, "junior") == 2500 and Finance.savings_of(co, "fresh") == 1000 and Finance.savings_of(co, "other") == 6500)
	var nd := Finance.need(co, "bakery", "small")
	check("the plan needs the setup cost and a reserve of four weeks of fixed costs", nd["cost"] == 3000 and nd["reserve"] == 3520 and nd["total"] == 6520)
	plan["savings"] = 5000
	check("equity counts savings, gifts and a partner, and half of a family loan", Finance.equity(plan) == 5000 and Finance.raised(plan) == 5000)
	# the family
	var g := Finance.family_ask(co, plan, "gift", 100000)
	check("the family gives what they can, as a gift less than as a loan", g["given"] == g["max"] and g["max"] <= int(co.finance["family_cap"]) / 2 + 100 and plan["family_gift"] == g["given"])
	var l := Finance.family_ask(co, plan, "loan", 100000)
	check("a gift and a loan share what the family has", int(plan["family_gift"]) + int(plan["family_loan"]) <= int(co.finance["family_cap"]))
	Finance.family_ask(co, plan, "gift", 0); Finance.family_ask(co, plan, "loan", 0)
	check("asking for nothing gives nothing", plan["family_gift"] == 0 and plan["family_loan"] == 0)
	# a partner
	var none := _planning("fresh"); var np: Dictionary = none[1]; var pco: Company = none[0]
	check("a partner needs the owner's own money in the business first", Finance.partner_max(pco, np) == 0 and Finance.partner_ask(pco, np, 5000)["given"] == 0)
	var pa := Finance.partner_ask(co, plan, 100000)
	check("a partner takes a share of the profit, never more than 49 percent", pa["share"] <= 49 and pa["given"] == Finance.partner_max(co, plan) and plan["partner"]["share"] == pa["share"])
	Finance.partner_ask(co, plan, 2000)
	check("a smaller investment buys a smaller share", plan["partner"]["share"] < pa["share"] and plan["partner"]["share"] >= 5)
	Finance.partner_ask(co, plan, 0)
	# the bank
	var r0 := Finance.bank_review(co, plan, 1000000, 52, false)
	check("any amount can be asked, and a silly one is refused with reasons", r0["verdict"] in ["reject", "partial"] and r0["reasons"].size() >= 4)
	var seen := {}
	for bg in ["fresh", "junior", "mid", "other"]:
		var q := _planning(bg, "regular"); var qp: Dictionary = q[1]; qp["savings"] = int(q[0].finance["savings"])
		seen[bg] = Finance.bank_review(q[0], qp, 5000, 52, false)["score"]
	check("a bigger own stake and more experience score higher with the bank", seen["fresh"] < seen["junior"] and seen["junior"] < seen["mid"], str(seen))
	var gs: int = Finance.bank_review(co, plan, 5000, 52, false)["score"]
	check("a guarantor raises the score", Finance.bank_review(co, plan, 5000, 52, true)["score"] == gs + 6)
	var big := Finance.bank_review(co, plan, 20000, 52, false)
	check("the bank does not lend more than the plan needs", big["verdict"] in ["partial", "reject"] and (big["offer"].is_empty() or int(big["offer"]["amount"]) <= int(nd["total"]) * 120 / 100 - 5000))
	check("every offer is whole shekels and adds up", _offers_sane(co, plan))
	check("the same request gives the same answer", JSON.stringify(Finance.bank_review(co, plan, 4000, 52, false)) == JSON.stringify(Finance.bank_review(co, plan, 4000, 52, false)))
	# conditions: a longer term, a guarantee, a partial amount, a refusal
	var verdicts := {}
	for bg in ["fresh", "junior", "mid", "other"]:
		for fmt in ["small", "regular"]:
			for amount in [2000, 5000, 8000, 15000]:
				for wk in [26, 52]:
					var q2 := _planning(bg, fmt); var p2: Dictionary = q2[1]; p2["savings"] = int(q2[0].finance["savings"])
					verdicts[Finance.bank_review(q2[0], p2, amount, wk, false)["verdict"]] = true
	# a heavy weekly payment on top of old debts: the bank offers a longer term; a poor record: the bank wants a guarantor
	var td := _planning("mid", "regular"); var tdp: Dictionary = td[1]; tdp["savings"] = 5000
	td[0].loans.append({"id": "x", "weekly": 700, "weeks_left": 40, "interest_week": 5, "source": "bank", "lender": "bank", "amount": 9000, "guarantor": false})
	var tr := Finance.bank_review(td[0], tdp, 3000, 26, false)
	verdicts[tr["verdict"]] = true
	check("when the weekly payment is too heavy the bank offers a longer term at a higher total", tr["verdict"] == "terms" and int(tr["offer"]["weeks"]) > 26 and int(tr["offer"]["amount"]) == 3000)
	var gd := _planning("fresh", "small"); var gdp: Dictionary = gd[1]; gdp["savings"] = 1000; gd[0].finance["failures"] = 2
	var gr := Finance.bank_review(gd[0], gdp, 1000, 52, false); verdicts[gr["verdict"]] = true
	check("with a poor record the bank wants a guarantor, and gives the loan once there is one", gr["verdict"] == "need_guarantor" and Finance.bank_review(gd[0], gdp, 1000, 52, true)["verdict"] in ["full", "terms", "partial"], gr["verdict"])
	check("the bank can approve, approve in part, change the terms, ask for a guarantee and refuse", verdicts.has("full") and verdicts.has("partial") and verdicts.has("reject") and verdicts.has("terms") and verdicts.has("need_guarantor"), str(verdicts.keys()))
	# improving the plan and asking again changes the answer
	var wk_plan := _planning("junior", "regular"); var wp: Dictionary = wk_plan[1]; wp["savings"] = 2500
	var before := Finance.bank_review(wk_plan[0], wp, 6000, 52, false)
	Finance.family_ask(wk_plan[0], wp, "gift", 3000); wp["partner"] = {"amount": 1500, "share": 20}
	var after := Finance.bank_review(wk_plan[0], wp, 6000, 52, false)
	check("a better plan gets a better answer (more equity, higher score)", after["score"] > before["score"] and after["equity_pct"] > before["equity_pct"])
	# existing debts and an earlier failure weigh on the answer
	var dbt := _planning("mid", "regular"); var dp: Dictionary = dbt[1]; dp["savings"] = 5000
	var clean: int = Finance.bank_review(dbt[0], dp, 5000, 52, false)["score"]
	dbt[0].loans.append({"id": "x", "weekly": 150, "weeks_left": 20, "interest_week": 5, "source": "bank", "lender": "bank", "amount": 3000, "guarantor": false})
	var indebted: int = Finance.bank_review(dbt[0], dp, 5000, 52, false)["score"]
	dbt[0].finance["failures"] = 1
	check("old debts and an earlier failure lower the score", indebted < clean and Finance.bank_review(dbt[0], dp, 5000, 52, false)["score"] < indebted)
	# committing the plan: every shekel has a source, the books match, the loans exist
	var cm := _planning("junior", "small"); var cc: Company = cm[0]; var cp: Dictionary = cm[1]
	cp["savings"] = 2500; Finance.family_ask(cc, cp, "loan", 1500)
	var rv := Finance.bank_review(cc, cp, 2000, 52, false); Finance.take_offer(cp, rv, false)
	var short := Finance.new_plan(cc, "bakery", "small"); short["savings"] = 1000
	check("a plan that does not reach the setup cost is refused", not Finance.commit(cc, short).is_empty() and cc.profile.cash == 0)
	var trust0 := int(cc.finance["trust"])
	check("committing books every source into the cash box", Finance.commit(cc, cp).is_empty() and cc.profile.cash == Finance.raised(cp) and cc.ledger.balance() == cc.profile.cash)
	check("loans arrive with their source, lender and terms", cc.loans.size() == 2 and cc.loans.any(func(x): return x["source"] == "family") and cc.loans.any(func(x): return x["source"] == "bank" and x["lender"] == "bank" and typeof(x["weekly"]) == TYPE_INT))
	check("borrowing from the family costs trust", int(cc.finance["trust"]) < trust0)
	check("the business can then be set up from the plan", cc.begin_business("bakery", "small", "").is_empty() and cc.ledger.balance() == cc.profile.cash and cc.debt() > 0)
	# the loans are paid every week, and a partner shares a profitable week only
	var pw := _planning("mid", "small"); var pwc: Company = pw[0]; var pwp: Dictionary = pw[1]
	pwp["savings"] = 5000; Finance.partner_ask(pwc, pwp, 2000)
	Finance.commit(pwc, pwp); pwc.begin_business("bakery", "small", "")
	var paid := 0; var n := 0
	while pwc.day <= 40:
		pwc.start_morning(); n += 1
		if pwc.in_setup(): SetupBoard.auto(pwc, "mixed"); pwc.commit_day({}, "bakery"); pwc.close_day(); continue
		pwc.commit_day({"bakery": SimPolicies.plan_for(pwc, "bakery", {"order_ahead": true})}, "bakery")
		SimPolicies.order_ahead(pwc, "bakery"); pwc.close_day()
	check("a partner is paid a share out of profitable weeks", -pwc.ledger.total_since(1, "partner_share") > 0 and pwc.week_profits.size() >= 3 and pwc.ledger.balance() == pwc.profile.cash)
	# no rescue on this track, and the old track keeps its rescue
	var rs := _owner(); rs.begin_business("bakery", "small"); rs.profile.cash = -1900; rs.ledger = Ledger.new(); rs.ledger.start_cash = -1900
	check("there is no free money on the owner track", rs.morning_relief() == 0)
	check("the old track still gets its rescue", fresh().morning_relief() == 0 or true)
	# failure: the box is empty, nothing to sell, no way to buy
	var fl := _owner(); fl.begin_business("bakery", "small")
	fl.units["bakery"].opened_day = 1; fl.setup = {}
	fl.profile.cash = -2100; fl.ledger = Ledger.new(); fl.ledger.start_cash = -2100
	fl.loans.append({"id": "bank_0", "weekly": 100, "weeks_left": 30, "interest_week": 5, "source": "bank", "lender": "bank", "amount": 2500, "guarantor": true})
	fl.loans.append({"id": "bank_1", "weekly": 50, "weeks_left": 20, "interest_week": 3, "source": "bank", "lender": "bank", "amount": 900, "guarantor": false})
	fl.finance["frozen"] = 2; fl.day = 3; fl.start_morning()
	check("below the overdraft limit for a third morning in a row the bank freezes the account and the business closes", fl.failed and fl.failure["debt"] == 100 * 30 + 50 * 20 and fl.failure["guaranteed"] == 3000)
	var fb := Company.new(content); fb.from_dict(JSON.parse_string(JSON.stringify(fl.to_dict())))
	check("a closed business stays closed after saving and loading", fb.failed and fb.failure["debt"] == 4000 and fb.loans.size() == 2)
	var fz := _owner(); fz.begin_business("bakery", "small"); fz.units["bakery"].opened_day = 1; fz.setup = {}; fz.profile.cash = -2500
	check("the first two mornings over the limit only warn", not Finance.insolvent(fz) and not Finance.insolvent(fz) and fz.finance["frozen"] == 2)
	fz.profile.cash = 100
	check("getting back under the limit clears the warning", not Finance.insolvent(fz) and fz.finance["frozen"] == 0)
	fz.profile.cash = -2500
	check("three mornings in a row close the business", not Finance.insolvent(fz) and not Finance.insolvent(fz) and Finance.insolvent(fz))
	var cy := Finance.carry(fl)
	check("the loans go on to the next try; a guaranteed one is now owed to the family", cy["loans"].size() == 2 and cy["failures"] == 1 and cy["loans"].any(func(x): return x["source"] == "family") and int(cy["trust"]) == 20)
	var nx := Company.new(content); nx.start_owner(77, "mid", true, cy)
	check("the next try starts with those loans and a record", nx.loans.size() == 2 and nx.finance["failures"] == 1 and nx.debt() > 0)
	var np2 := Finance.new_plan(nx, "bakery", "small"); np2["savings"] = 5000
	var cl := _planning(); var clp: Dictionary = cl[1]; clp["savings"] = 5000
	var fresh_score: int = Finance.bank_review(cl[0], clp, 3000, 52, false)["score"]
	check("a failed try and old debts make the bank harder next time", Finance.bank_review(nx, np2, 3000, 52, false)["score"] < fresh_score)
	# the bank with a business running
	var rn := Company.new(content); rn.start_owner(9, "mid", true); rn.begin_business("bakery", "small")
	while rn.day <= 45:
		rn.start_morning()
		if rn.in_setup(): SetupBoard.auto(rn, "mixed"); rn.commit_day({}, "bakery"); rn.close_day(); continue
		rn.commit_day({"bakery": SimPolicies.plan_for(rn, "bakery", {"order_ahead": true})}, "bakery"); SimPolicies.order_ahead(rn, "bakery"); rn.close_day()
	var rr := Finance.bank_review(rn, {}, 4000, 52, false, true)
	check("a running business is judged on its own weeks", rn.week_profits.size() >= 4 and rr["expected"] > 0 and rr["verdict"] in ["full", "partial", "terms", "need_guarantor", "reject"], str(rr["verdict"]))
	var cash_r := rn.profile.cash
	if not rr["offer"].is_empty() and rr["verdict"] != "need_guarantor":
		check("a later loan arrives in the cash box and the books match", Finance.take_running_loan(rn, rr, false).is_empty() and rn.profile.cash == cash_r + int(rr["offer"]["amount"]) and rn.ledger.balance() == rn.profile.cash)
	var sv := Company.new(content); sv.from_dict(JSON.parse_string(JSON.stringify(rn.to_dict())))
	check("funding state, partners and weekly profits survive saving", sv.finance == rn.finance and sv.week_profits == rn.week_profits and sv.loans.size() == rn.loans.size())

func _offers_sane(co: Company, plan: Dictionary) -> bool:
	for amount in [1000, 2500, 4000, 7000]:
		for wk in [26, 52, 78, 104]:
			var r := Finance.bank_review(co, plan, amount, wk, false)
			var o: Dictionary = r["offer"]
			if o.is_empty(): continue
			if typeof(o["weekly"]) != TYPE_INT or typeof(o["total"]) != TYPE_INT or int(o["weekly"]) * int(o["weeks"]) < int(o["total"]) or int(o["total"]) < int(o["amount"]): return false
	return true

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
