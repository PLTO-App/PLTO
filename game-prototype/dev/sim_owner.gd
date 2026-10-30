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
		"payback_day": 0, "setup_spend": 0, "errors": [], "served": 0, "lost": 0, "waste": 0, "fines": 0, "first_profit_week": 0}
	var e := co.begin_business(bid, opts["fmt"], opts.get("loan", ""))
	if not e.is_empty(): res["errors"].append(Loc.msg(e)); return res
	res["ok"] = true
	var days: int = opts.get("days", 70)
	var inv_total := -co.ledger.total_since(1, "investment")
	var late: Array = []; var total_profit := 0; var played := 0; var cum_cash_from_ops := 0
	var weeks_seen := 0
	while co.day <= days:
		var rep := co.start_morning()
		for ev in rep["events"].duplicate(): co.resolve_event(ev, _choose(ev, opts))
		if co.in_setup():
			var left := co.setup_left(bid)
			if left == 1 and opts.get("order_ahead", true): SimPolicies.order_ahead(co, bid)
			co.commit_day({}, bid)
			var ss := co.close_day()
			if int(ss["units"].size()) != 0: res["errors"].append("setup day with units")
			res["min_cash"] = mini(res["min_cash"], co.profile.cash)
			if co.ledger.balance() != co.profile.cash: res["errors"].append("day %d: ledger %d != cash %d" % [co.day, co.ledger.balance(), co.profile.cash])
			continue
		if res["open_day"] == 0: res["open_day"] = co.day
		var plans := {}
		for b in co.units: if co.unit_ready(b): plans[b] = SimPolicies.plan_for(co, b, opts)
		var errs := co.commit_day(plans, bid)
		if not errs.is_empty():
			for b in plans: plans[b] = co.units[b].empty_plan()
			errs = co.commit_day(plans, bid)
			if not errs.is_empty(): res["errors"].append("day %d: %s" % [co.day, Loc.msg(errs[0])]); break
		if opts.get("order_ahead", true):
			for b in co.units: SimPolicies.order_ahead(co, b)
		var s := co.close_day()
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
	return o

func _choose(ev: Dictionary, opts: Dictionary) -> int:
	match ev["id"]:
		"setup_contractor": return int(opts.get("contractor", 1))
		"setup_equipment": return int(opts.get("equip", 1))
		"setup_launch": return int(opts.get("launch", 0))
	return SimPolicies.choose(null, ev, opts)

func avg(opts: Dictionary, n := 4) -> Dictionary:
	var sum := {}; var errors: Array = []; var min_cash := 1 << 30; var ok := 0; var broke := 0
	for sd in n:
		var r := play(300 + sd, opts)
		if not r["ok"]: errors.append_array(r["errors"]); continue
		ok += 1
		for k in ["profit_per_day", "late_profit", "worth", "rep", "open_day", "served", "lost", "waste", "fines", "first_profit_week"]: sum[k] = int(sum.get(k, 0)) + int(r[k])
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

# The setup choices: no option should dominate
func _setup_choices() -> void:
	print("--- setup choices (bakery regular, cash 3500, small loan) and (bakery small, cash 3500, no loan)")
	for cfg in [{"biz": "bakery", "fmt": "regular", "cash": 3500, "loan": "small"}, {"biz": "bakery", "fmt": "small", "cash": 3500, "loan": ""}]:
		for ch in [{"contractor": 1, "equip": 1, "launch": 2}, {"contractor": 0, "equip": 1, "launch": 2}, {"contractor": 1, "equip": 0, "launch": 2}, {"contractor": 1, "equip": 1, "launch": 0}, {"contractor": 1, "equip": 1, "launch": 1}, {"contractor": 0, "equip": 0, "launch": 0}]:
			var o: Dictionary = cfg.duplicate(); o.merge(ch)
			line("%s %s c%d e%d l%d" % [cfg["biz"], cfg["fmt"], ch["contractor"], ch["equip"], ch["launch"]], avg(o, 6))

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
