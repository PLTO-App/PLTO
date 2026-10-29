class_name SimPolicies
extends RefCounted
# Automatic "owners" used by the balance tests: they make the morning decisions by simple rules.

# opts: bake_factor (1.0 = forecast), price_pct, supplier ("wholesale"/"family"/"best"), marketing, max_bake (bool), idle (bool)
static func make_plan(biz: Business, opts: Dictionary) -> Dictionary:
	var mk_id: String = opts.get("marketing", "none")
	if not biz.unlocked("marketing", mk_id): mk_id = "none"
	var plan := {"supplier": "wholesale", "buy": {}, "bake": {}, "prices": {}, "marketing": mk_id, "promo_product": "croissant"}
	if opts.get("idle", false): return plan
	var db := biz.db
	if opts.get("supplier", "wholesale") != "wholesale" and biz.unlocked("suppliers", "family") and biz.profile.cash > 900: plan["supplier"] = "family"
	for pid in db["products"]:
		var ref: int = db["products"][pid]["price"]
		var p: int = ref * int(opts.get("price_pct", 100)) / 100 / 5 * 5
		var b := biz.price_bounds(pid)
		plan["prices"][pid] = clampi(p, b.x, b.y)
	var fc := biz.forecast(plan); var expected := float(fc.x + fc.y) / 2.0
	var mk: Dictionary = db["marketing"][plan["marketing"]]
	var pref_total := 0
	for pid in db["products"]: pref_total += db["products"][pid]["pref"]
	var oven_left := biz.oven_capacity()
	var wanted := {}
	for pid in db["products"]:
		var share := float(db["products"][pid]["pref"]) / pref_total
		var n := int(ceil(expected * share * 0.8 * float(opts.get("bake_factor", 1.0))))
		wanted[pid] = n
	if opts.get("max_bake", false):
		for pid in db["products"]: wanted[pid] = 0
		var ids: Array = db["products"].keys()
		var i := 0
		while oven_left > 0 and i < 200:
			var pid: String = ids[i % ids.size()]
			if db["products"][pid]["oven"] <= oven_left: wanted[pid] += 1; oven_left -= db["products"][pid]["oven"]
			i += 1
		oven_left = 0
	var used := 0
	var sorted_ids: Array = db["products"].keys()
	sorted_ids.sort_custom(func(a, b): return db["products"][a]["pref"] > db["products"][b]["pref"])
	for pid in sorted_ids:
		var n: int = wanted[pid] - biz.inv.stock(pid)
		n = maxi(0, n)
		while n > 0 and used + n * db["products"][pid]["oven"] > biz.oven_capacity(): n -= 1
		plan["bake"][pid] = n; used += n * db["products"][pid]["oven"]
	# buy what the bake needs and is missing, never more than the cash allows
	var need := {}
	for iid in db["ingredients"]: need[iid] = 0
	for pid in plan["bake"]:
		for iid in db["products"][pid]["recipe"]: need[iid] += db["products"][pid]["recipe"][iid] * plan["bake"][pid]
	for iid in need:
		var missing: int = maxi(0, need[iid] - biz.inv.units(iid))
		plan["buy"][iid] = missing
	# if the cash is short, bake less until it fits
	var guard := 0
	while not biz.validate_plan(plan).is_empty() and guard < 200:
		guard += 1
		var rev: Array = sorted_ids.duplicate(); rev.reverse()
		for pid in rev:
			if plan["bake"][pid] > 0: plan["bake"][pid] -= 1; break
		for iid in db["ingredients"]: plan["buy"][iid] = 0
		for iid in need: need[iid] = 0
		for pid in plan["bake"]:
			for iid in db["products"][pid]["recipe"]: need[iid] += db["products"][pid]["recipe"][iid] * plan["bake"][pid]
		for iid in need: plan["buy"][iid] = maxi(0, need[iid] - biz.inv.units(iid))
	return plan

# Plays `days` days; returns stats. `upgrade_when_rich`: buys upgrades when cash allows.
static func play(content: ContentDb, seed_value: int, days: int, opts: Dictionary) -> Dictionary:
	var prof := Profile.new(); var biz := Business.new(content, "bakery", prof)
	biz.new_game(false, seed_value)
	var start_cash := prof.cash
	var total_profit := 0; var served := 0; var lost := 0; var waste := 0; var bankrupt_days := 0; var min_cash := prof.cash
	var errors: Array = []
	for d in days:
		if opts.get("upgrades", false) and prof.cash > 1500:
			for u in ["sign", "oven", "display"]:
				if not biz.upgrades.has(u) and biz.unlocked("upgrades", u): biz.buy_upgrade(u); break
		biz.morning_relief()
		var plan := make_plan(biz, opts)
		var errs := biz.commit_plan(plan)
		if not errs.is_empty():
			errors.append("day %d: %s" % [biz.day, str(errs)]); plan = make_plan(biz, {"idle": true}); biz.commit_plan(plan)
		var runner := biz.begin_day(); runner.run_auto()
		var s := biz.close_day(runner)
		total_profit += s["profit"]; served += s["served"]; lost += s["lost_price"] + s["lost_stock"] + s["walkouts"]; waste += s["waste_cost"]
		min_cash = mini(min_cash, prof.cash)
		if prof.cash < 0: bankrupt_days += 1
		# invariants
		if start_cash + biz.ledger.total() != prof.cash and days <= 14: errors.append("ledger mismatch on day %d" % s["day"])
		for iid in biz.inv.ing: if biz.inv.ing[iid]["units"] < 0: errors.append("negative ingredient")
		for pid in biz.inv.goods: if biz.inv.goods[pid]["fresh"] < 0 or biz.inv.goods[pid]["old"] < 0: errors.append("negative goods")
		if s["customers"] < 2 or s["customers"] > 30: errors.append("customer count %d" % s["customers"])
	return {"profit_per_day": total_profit / days, "cash": prof.cash, "rep": prof.reputation, "level": prof.level, "served": served, "lost": lost,
		"waste": waste, "min_cash": min_cash, "bankrupt_days": bankrupt_days, "errors": errors, "upgrades": biz.upgrades.keys()}
