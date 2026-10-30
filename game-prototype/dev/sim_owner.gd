extends SceneTree
# Development only: balance runs for the owner track (an empty rented space, a business to build, funded by cash and loans).
# Not part of the APK. Prints tables; the numbers in content/tracks.json and the business formats are chosen from these runs.
# godot --headless --path game-prototype --script dev/sim_owner.gd [-- sweep|setup|choices|check]
var content: ContentDb

# opts: biz, fmt, loan ("" | small | large), cash, days, contractor (0 fast | 1 normal), equip (0 used | 1 new), launch (0 flyers | 1 post | 2 none),
#       plus the usual SimPolicies options for the days the business runs (order_ahead, upkeep ...)
func play(seed_value: int, opts: Dictionary) -> Dictionary:
	_apply_formats(opts)
	opts = _skill(opts)
	var co := Company.new(content); co.start_owner(seed_value)
	if opts.has("cash"): co.profile.cash = int(opts["cash"]); co.ledger = Ledger.new(); co.ledger.start_cash = co.profile.cash
	var bid: String = opts["biz"]
	var res := {"ok": false, "cash0": co.profile.cash, "open_day": 0, "profit_per_day": 0, "late_profit": 0, "worth": 0, "min_cash": 1 << 30, "broke_days": 0, "rep": 0,
		"payback_day": 0, "setup_spend": 0, "errors": [], "served": 0, "lost": 0, "waste": 0, "fines": 0, "first_profit_week": 0, "cash_open": 0, "setup_fails": 0, "saved": 0, "burned": 0, "negotiated": 0}
	var e := co.begin_business(bid, opts["fmt"], opts.get("loan", ""))
	if not e.is_empty(): res["errors"].append(Loc.msg(e)); return res
	res["ok"] = true
	# a second, unneeded loan: the owner borrows more than the setup needs
	if opts.get("extra_loan", "") != "": co.take_loan(opts["extra_loan"])
	res["cash_after_setup"] = co.profile.cash
	var weekly_fixed := 0
	for k in co.units[bid].db["weekly_costs"]: weekly_fixed += int(co.units[bid].db["weekly_costs"][k])
	for l in co.loans: weekly_fixed += int(l["weekly"])
	res["runway_weeks_x10"] = co.profile.cash * 10 / maxi(1, weekly_fixed)
	res["min21"] = 1 << 30; res["neg_days"] = 0; res["cash_w1"] = 0; res["shock_total"] = 0
	var rnd := RandomNumberGenerator.new(); rnd.seed = seed_value * 7 + 1
	var days: int = opts.get("days", 70)
	var inv_total := -co.ledger.total_since(1, "investment")
	var late: Array = []; var total_profit := 0; var played := 0; var cum_cash_from_ops := 0
	var weeks_seen := 0
	while co.day <= days:
		var rep := co.start_morning()
		for ev in rep["events"].duplicate(): co.resolve_event(ev, _choose(ev, opts))
		# unexpected expenses (a repair, a fine, a supplier that raises a price): booked on fixed days
		for sh in opts.get("shocks", []):
			if int(sh[0]) == co.day: co.book("event", -int(sh[1]), bid, "shock"); res["shock_total"] += int(sh[1])
		if co.in_setup():
			# the setup file is played by a style (diy | mixed | pro); the launch task is started on the first morning if asked for
			# the contractor: a fixed tier, or "checked" (pay for the reference checks, take the middle quote if it is reliable enough, else the dear one)
			var ct := str(opts.get("contractor", ""))
			if ct != "" and SetupBoard.status(co, SetupBoard.def_of(co, "fit_out")) == "ready":
				if ct == "informed":
					# pays for every reference check, then takes the quote with the lowest expected cost: price plus the chance of trouble times what trouble costs
					var trouble_cost := int(SetupBoard.def_of(co, "fit_out")["bids"]["budget"][SetupBoard._fmt(co)]) * 45 / 100
					var best_score := 1 << 30
					for q in ["cheap", "mid", "premium"]: SetupBoard.check_bid(co, "fit_out", q)
					for q in co.setup["bids"]["fit_out"]:
						var sc := int(q["price"]) + (100 - int(q["rel"])) * trouble_cost / 100 + int(q["days"]) * trouble_cost * 8 / 10   # a day is worth about the trouble cost
						if sc < best_score: best_score = sc; ct = q["id"]
				elif ct == "checked":
					for q in ["mid", "premium"]: SetupBoard.check_bid(co, "fit_out", q)
					var mid_rel := 0
					for q in co.setup["bids"]["fit_out"]: if q["id"] == "mid": mid_rel = int(q["rel"])
					ct = "mid" if mid_rel >= 70 else "premium"
				_negotiate(co, ct, str(opts.get("negotiate", "none")), res)
				var order: Array = [ct, "mid", "cheap", "premium", "friends"]
				for q in order: if SetupBoard.start(co, "fit_out", q).is_empty(): break
			SetupBoard.auto(co, str(opts.get("setup_style", "mixed")))
			if opts.has("launch") and SetupBoard.status(co, SetupBoard.def_of(co, "launch")) == "ready": SetupBoard.start(co, "launch", ["flyers", "post"][int(opts["launch"])])
			if not res.get("ordered", false) and SetupBoard.pending_required(co).all(func(t): return SetupBoard.st(co, t["id"])["state"] == "active"):
				res["ordered"] = true
				if opts.get("order_ahead", true): SimPolicies.order_ahead(co, bid)
			co.commit_day({}, bid)
			var ss := co.close_day()
			if int(ss["units"].size()) != 0: res["errors"].append("setup day with units")
			res["min_cash"] = mini(res["min_cash"], co.profile.cash)
			if co.ledger.balance() != co.profile.cash: res["errors"].append("day %d: ledger %d != cash %d" % [co.day, co.ledger.balance(), co.profile.cash])
			continue
		if res["open_day"] == 0:
			res["open_day"] = co.day; res["cash_open"] = co.profile.cash
			for id in co.setup.get("tasks", {}): res["setup_fails"] += int(co.setup["tasks"][id]["fails"])
		var plans := {}
		for b in co.units: if co.unit_ready(b): plans[b] = SimPolicies.plan_for(co, b, opts)
		# mistakes: now and then the owner forgets to plan, bakes far too much, or skips ordering for tomorrow; or does nothing for the first days
		var slip := -1
		if rnd.randi_range(1, 100) <= int(opts.get("mistakes", 0)): slip = rnd.randi_range(0, 2)
		if res["open_day"] != 0 and co.day < res["open_day"] + int(opts.get("idle_start", 0)): slip = 0
		for b in plans:
			if slip == 0: plans[b] = co.units[b].empty_plan()
			elif slip == 1:
				for pid in plans[b]["bake"]: plans[b]["bake"][pid] = int(plans[b]["bake"][pid]) * 16 / 10
		var errs := co.commit_day(plans, bid)
		if not errs.is_empty():
			for b in plans: plans[b] = co.units[b].empty_plan()
			errs = co.commit_day(plans, bid)
			if not errs.is_empty(): res["errors"].append("day %d: %s" % [co.day, Loc.msg(errs[0])]); break
		if opts.get("order_ahead", true) and slip != 2:
			for b in co.units: SimPolicies.order_ahead(co, b)
		var s := co.close_day()
		if co.day <= 22: res["min21"] = mini(res["min21"], co.profile.cash)
		if co.profile.cash < 0: res["neg_days"] += 1
		if res["cash_w1"] == 0 and not s["week"].is_empty(): res["cash_w1"] = co.profile.cash
		if opts.get("spree", false):
			for uid in co.units[bid].db["upgrades"]:
				var u2: Dictionary = co.units[bid].db["upgrades"][uid]
				if not co.units[bid].upgrades.has(uid) and co.level() >= int(u2["unlock_level"]) and co.profile.cash > int(u2["cost"]): co.buy_upgrade(bid, uid)
		if opts.get("upgrades", false):
			for uid in co.units[bid].db["upgrades"]:
				var u: Dictionary = co.units[bid].db["upgrades"][uid]
				if not co.units[bid].upgrades.has(uid) and co.level() >= int(u["unlock_level"]) and co.profile.cash > int(u["cost"]) + 2500: co.buy_upgrade(bid, uid)
		total_profit += int(s["profit"]); played += 1
		late.append(int(s["profit"])); if late.size() > 12: late.pop_front()
		for b in s["units"]:
			var u: Dictionary = s["units"][b]
			res["served"] += u["served"]; res["lost"] += u["lost_stock"] + u["lost_price"] + u["walkouts"]; res["waste"] += u["waste_cost"]
		res["min_cash"] = mini(res["min_cash"], co.profile.cash)
		if co.profile.cash < -co.overdraft_limit(): res["broke_days"] += 1
		if not s["week"].is_empty() and res["first_profit_week"] == 0 and int(s["week"]["profit"]) > 0: res["first_profit_week"] = co.day
		if co.ledger.balance() != co.profile.cash: res["errors"].append("day %d: ledger %d != cash %d" % [co.day, co.ledger.balance(), co.profile.cash])
	res["profit_per_day"] = total_profit / maxi(1, played)
	var lt := 0
	for x in late: lt += x
	res["late_profit"] = lt / maxi(1, late.size())
	res["worth"] = co.profile.cash - co.debt()
	res["rep"] = co.units[bid].reputation
	res["fines"] = -co.ledger.total_since(1, "fine")
	res["played"] = played
	return res

# The numbers under test: setup cost and days per size (small_cost, small_days, reg_cost, reg_days)
func _apply_formats(opts: Dictionary) -> void:
	var f: Dictionary = content.businesses["bakery"]["formats"]
	f["small"]["setup_cost"] = int(opts.get("small_cost", 3000)); f["small"]["setup_days"] = int(opts.get("small_days", 2))
	f["regular"]["setup_cost"] = int(opts.get("reg_cost", 6500)); f["regular"]["setup_days"] = int(opts.get("reg_days", 4))

# How well the owner runs the days: good plans and orders ahead; average buys every morning; poor bakes blindly and skips upkeep
func _skill(opts: Dictionary) -> Dictionary:
	var o: Dictionary = opts.duplicate()
	match str(opts.get("skill", "good")):
		"good": o["order_ahead"] = true
		"average": o["order_ahead"] = false
		"poor": o["order_ahead"] = false; o["max_bake"] = true; o["upkeep"] = false
		"overpriced": o["order_ahead"] = true; o["price_pct"] = 130
		"underpriced": o["order_ahead"] = true; o["price_pct"] = 75
		"careless": o["order_ahead"] = true; o["mistakes"] = 20
		"slow_start": o["order_ahead"] = true; o["idle_start"] = 4
		"spree": o["order_ahead"] = true; o["spree"] = true
	return o

func _choose(ev: Dictionary, opts: Dictionary) -> int:
	return SimPolicies.choose(null, ev, opts)

func avg(opts: Dictionary, n := 4) -> Dictionary:
	var sum := {}; var errors: Array = []; var min_cash := 1 << 30; var ok := 0; var broke := 0
	for sd in n:
		var r := play(300 + sd, opts)
		if not r["ok"]: errors.append_array(r["errors"]); continue
		ok += 1
		for k in ["profit_per_day", "late_profit", "worth", "rep", "open_day", "served", "lost", "waste", "fines", "first_profit_week", "cash_after_setup", "runway_weeks_x10", "min21", "neg_days", "cash_w1", "cash_open", "setup_fails", "saved", "burned", "negotiated"]: sum[k] = int(sum.get(k, 0)) + int(r[k])
		sum["min21_worst"] = mini(int(sum.get("min21_worst", 1 << 30)), int(r["min21"]))
		min_cash = mini(min_cash, r["min_cash"]); errors.append_array(r["errors"])
		if r["broke_days"] > 0: broke += 1
	if ok == 0: return {"ok": false, "errors": errors}
	for k in sum: sum[k] /= ok
	sum["ok"] = true; sum["min_cash"] = min_cash; sum["errors"] = errors; sum["broke"] = broke; sum["n"] = ok
	return sum

func line(label: String, r: Dictionary) -> void:
	if not r["ok"]: print("%-34s  (not possible: %s)" % [label, str(r["errors"].slice(0, 1))]); return
	print("%-34s  opens day %2d | late profit/day %4d | profit/day %4d | worth@70 %6d | lowest cash %6d | broke runs %d/%d | rep %3d | first profit week %s | errors %d" % [
		label, r["open_day"], r["late_profit"], r["profit_per_day"], r["worth"], r["min_cash"], r["broke"], r["n"], r["rep"], str(r["first_profit_week"]) if r["first_profit_week"] > 0 else "-", r["errors"].size()])

func _init() -> void:
	Loc.setup("he")
	content = ContentDb.new(); content.load_all()
	var mode := "sweep"
	for a in OS.get_cmdline_user_args(): mode = a
	match mode:
		"sweep": _sweep()
		"setup": _setup_choices()
		"check": _check()
		"grid": _grid()
		"baseline": _baseline()
		"long": _long()
		"room": _room()
		"mistakes": _mistakes()
		"negotiate": _negotiate_modes()
		"contractor": _contractor()
		"buffer": _buffer()
	quit(0)

# Business x size x funding x opening cash
func _sweep() -> void:
	print("--- owner track: 70 days x 4 seeds, balanced owner who orders ahead")
	for bid in ["bakery", "cafe"]:
		for fmt in ["small", "regular"]:
			for cash in [2000, 3500, 5000]:
				for loan in ["", "small", "large"]:
					var f: Dictionary = content.businesses[bid]["formats"][fmt]
					var avail: int = cash + (int(content.world["bank"]["loans"][loan]["amount"]) if loan != "" else 0)
					if avail < int(f["setup_cost"]): continue
					line("%s %s cash %d loan %s (cost %d)" % [bid, fmt, cash, loan if loan != "" else "-", f["setup_cost"]], avg({"biz": bid, "fmt": fmt, "cash": cash, "loan": loan}))

# The setup file played three ways: do it yourself, a consultant for the license only, a professional for everything
func _setup_choices() -> void:
	print("--- setup file by style: 70 days x 12 seeds, opening cash 5000, with unexpected expenses")
	for cfg in [{"fmt": "small", "loan": ""}, {"fmt": "regular", "loan": "small"}]:
		for style in ["diy", "mixed", "pro"]:
			var o := {"biz": "bakery", "cash": 5000, "setup_style": style, "shocks": SHOCKS}; o.merge(cfg)
			var r := avg(o, 12)
			if not r["ok"]: print("not possible"); continue
			print("%-7s loan %-5s %-6s opens day %4.1f (setup days %4.1f) | step failures %4.1f | cash on opening day %5d | lowest in 3 weeks %5d (worst %5d) | days below zero %4.1f | late/day %4d | worth@70 %6d" % [
				cfg["fmt"], cfg["loan"] if cfg["loan"] != "" else "-", style, float(r["open_day"]), float(r["open_day"]) - 1.0, float(r["setup_fails"]), r["cash_open"], r["min21"], r["min21_worst"], float(r["neg_days"]), r["late_profit"], r["worth"]])

func _check() -> void:
	var r := play(11, {"biz": "bakery", "fmt": "small", "cash": 3500, "loan": ""})
	print(r)

func _baseline() -> void:
	print("--- the existing bakery (3,000 cash, open from day 1), 70 days x 4 seeds")
	for skill in [{"name": "good", "o": {"order_ahead": true}}, {"name": "average", "o": {}}, {"name": "poor", "o": {"order_ahead": false, "max_bake": true, "upkeep": false}}, {"name": "idle", "o": {"idle": true}}]:
		var sum := {"late": 0, "profit": 0, "worth": 0}; var low := 1 << 30; var broke := 0
		for sd in 4:
			var r := SimPolicies.play(content, 300 + sd, 70, skill["o"])
			sum["late"] += r["late_profit"]; sum["profit"] += r["profit_per_day"]; sum["worth"] += r["cash"]; low = mini(low, r["min_cash"]); if r["bankrupt_days"] > 0: broke += 1
		print("%-8s late profit/day %4d | profit/day %4d | worth@70 %6d | lowest cash %6d | broke runs %d/4" % [skill["name"], sum["late"] / 4, sum["profit"] / 4, sum["worth"] / 4, low, broke])

# Size x cost x opening cash x loan x how well the owner plays (bakery only)
func _grid() -> void:
	print("--- bakery owner track: 70 days x 4 seeds")
	for fmt in ["small", "regular"]:
		var costs: Array = [2500, 3000, 3500] if fmt == "small" else [5500, 6500, 7500]
		for cost in costs:
			for cash in [2500, 3500]:
				for loan in ["", "small", "large"]:
					var line_out := ""
					var any := false
					for skill in ["good", "average", "poor"]:
						var o := {"biz": "bakery", "fmt": fmt, "cash": cash, "loan": loan, "skill": skill}
						o["small_cost" if fmt == "small" else "reg_cost"] = cost
						var avail: int = cash + (int(content.world["bank"]["loans"][loan]["amount"]) if loan != "" else 0)
						if avail < cost: continue
						var r := avg(o, 4)
						if not r["ok"]: continue
						any = true
						line_out += " | %s: late %4d worth %6d low %6d broke %d/%d" % [skill, r["late_profit"], r["worth"], r["min_cash"], r["broke"], r["n"]]
					if any: print("%-8s cost %4d cash %4d loan %-5s%s" % [fmt, cost, cash, loan if loan != "" else "-", line_out])

# A longer horizon with upgrades: does a small start fall behind for good?
func _long() -> void:
	print("--- 150 days, good owner who buys upgrades")
	for cfg in [{"fmt": "small", "loan": ""}, {"fmt": "small", "loan": "small"}, {"fmt": "regular", "loan": "small"}, {"fmt": "regular", "loan": "large"}]:
		var o := {"biz": "bakery", "cash": 3500, "days": 150, "upgrades": true, "skill": "good"}; o.merge(cfg)
		line("%s loan %s" % [cfg["fmt"], cfg["loan"] if cfg["loan"] != "" else "-"], avg(o, 4))

const SHOCKS := [[5, 500], [12, 700], [24, 600]]   # a repair, a fine, a price rise: 1,800 over the first four weeks

func room_line(label: String, r: Dictionary) -> void:
	if not r["ok"]: print("%-44s (not possible)" % label); return
	print("%-44s after setup %5d (%4.1f weeks of fixed costs) | week-1 cash %5d | lowest in 3 weeks: avg %5d worst %5d | days below zero %4.1f | broke %d/%d | late/day %4d | worth@70 %6d" % [
		label, r["cash_after_setup"], float(r["runway_weeks_x10"]) / 10.0, r["cash_w1"], r["min21"], r["min21_worst"], float(r["neg_days"]), r["broke"], r["n"], r["late_profit"], r["worth"]])

# Does the opening cash leave room to breathe after the setup? Cash x size x funding x behaviour, with unexpected expenses.
func _room() -> void:
	print("--- breathing room: 70 days x 6 seeds, unexpected expenses %s (days: 5, 12, 24)" % str(SHOCKS))
	var cfgs := [{"fmt": "small", "loan": ""}, {"fmt": "small", "loan": "small"}, {"fmt": "regular", "loan": "small"}, {"fmt": "regular", "loan": "large"}]
	for cash in [4000, 4500, 5000, 5500]:
		print("== opening cash %d" % cash)
		for cfg in cfgs:
			var cost: int = 3000 if cfg["fmt"] == "small" else 6500
			var avail: int = cash + (int(content.world["bank"]["loans"][cfg["loan"]]["amount"]) if cfg["loan"] != "" else 0)
			if avail < cost: continue
			for skill in ["good", "careless", "average", "poor"]:
				var o := {"biz": "bakery", "cash": cash, "skill": skill, "shocks": SHOCKS}; o.merge(cfg)
				room_line("%-7s loan %-5s %-8s" % [cfg["fmt"], cfg["loan"] if cfg["loan"] != "" else "-", skill], avg(o, 6))

# Mistakes, bad pricing, a slow start, unneeded loans and spending sprees (opening cash 3,500)
func _mistakes() -> void:
	print("--- mistakes and bad habits: opening cash 3500, 70 days x 6 seeds, with and without unexpected expenses")
	for shocks in [[], SHOCKS]:
		print("== unexpected expenses: %s" % ("none" if shocks.is_empty() else "yes"))
		for cfg in [{"fmt": "small", "loan": ""}, {"fmt": "small", "loan": "", "extra_loan": "large"}, {"fmt": "small", "loan": "small", "extra_loan": "large"}, {"fmt": "regular", "loan": "small"}]:
			for skill in ["good", "careless", "slow_start", "overpriced", "underpriced", "spree"]:
				var o := {"biz": "bakery", "cash": 3500, "skill": skill, "shocks": shocks}; o.merge(cfg)
				room_line("%-7s loan %-5s%s %-10s" % [cfg["fmt"], cfg["loan"] if cfg["loan"] != "" else "-", (" +extra " + cfg["extra_loan"]) if cfg.has("extra_loan") else "            ", skill], avg(o, 6))

# The opening cash against a bad first weeks (a slow start, careless days, a spending spree) with the unexpected expenses
func _buffer() -> void:
	print("--- buffer: bad first weeks with unexpected expenses, 70 days x 8 seeds")
	for cfg in [{"fmt": "small", "loan": ""}, {"fmt": "regular", "loan": "small"}]:
		for cash in [3500, 4000, 4500, 5000]:
			for skill in ["slow_start", "careless", "spree"]:
				var o := {"biz": "bakery", "cash": cash, "skill": skill, "shocks": SHOCKS}; o.merge(cfg)
				room_line("%-7s loan %-5s cash %d %-10s" % [cfg["fmt"], cfg["loan"] if cfg["loan"] != "" else "-", cash, skill], avg(o, 8))

# The contractor choice with everything else played the same way (a consultant for the license): which quote pays?
func _contractor() -> void:
	print("--- contractor: 70 days x 16 seeds, opening cash 5000, unexpected expenses")
	for cfg in [{"fmt": "small", "loan": ""}, {"fmt": "regular", "loan": "small"}]:
		for ct in ["friends", "cheap", "mid", "premium", "informed"]:
			var o := {"biz": "bakery", "cash": 5000, "setup_style": "mixed", "contractor": ct, "shocks": SHOCKS}; o.merge(cfg)
			var r := avg(o, 64)
			print("%-7s %-8s opens day %4.1f | step failures %4.1f | cash on opening day %5d | lowest in 3 weeks %5d (worst %5d) | days below zero %4.1f | worth@70 %6d" % [
				cfg["fmt"], ct, float(r["open_day"]), float(r["setup_fails"]), r["cash_open"], r["min21"], r["min21_worst"], float(r["neg_days"]), r["worth"]])

# Haggling styles over the contractor quote. moves that cannot be made are skipped.
func _negotiate(co: Company, tier: String, style: String, res: Dictionary) -> void:
	if style == "none": return
	var plan: Array = {"polite": ["ask_small", "accept"], "firm": ["ask_big", "compromise", "accept"], "hard": ["ask_huge", "insist", "insist", "accept"],
		"smart": ["alt", "ask_big", "compromise", "accept"], "bluffer": ["alt", "ask_huge", "accept"], "greedy": ["ask_huge", "ask_huge", "ask_huge", "accept"]}[style]
	if not Negotiation.begin(co, "fit_out", tier).is_empty(): return
	var list := int(Negotiation.state(co)["list"])
	for m in plan:
		if not Negotiation.is_open(co): break
		if m in Negotiation.moves(co): Negotiation.play(co, m)
	if Negotiation.is_open(co): Negotiation.play(co, "accept")
	var n := Negotiation.state(co)
	res["negotiated"] += 1
	if n["result"] == "deal": res["saved"] += list - int(n["price"])
	if n["result"] == "burned": res["burned"] += 1

func _negotiate_modes() -> void:
	var N := 48
	print("--- negotiating the contractor quote: 70 days x %d seeds, mid quote, opening cash 5000" % N)
	for style in ["none", "polite", "firm", "smart", "bluffer", "hard", "greedy"]:
		var saved := 0; var burned := 0; var worth := 0; var opened := 0; var ok := 0
		for sd in N:
			var r := play(500 + sd, {"biz": "bakery", "fmt": "small", "loan": "", "cash": 5000, "setup_style": "mixed", "contractor": "mid", "negotiate": style, "shocks": SHOCKS})
			if not r["ok"]: continue
			ok += 1; saved += r["saved"]; burned += r["burned"]; worth += r["worth"]; opened += r["open_day"]
		print("%-8s saved on the quote (avg) %4d | the professional left in %2d of %d | opens day %4.1f | worth@70 %6d" % [style, saved / maxi(1, ok), burned, ok, float(opened) / maxi(1, ok), worth / maxi(1, ok)])
