class_name SimPolicies
extends RefCounted
# Development only: automatic "owners" for the balance tests. They make the morning decisions by simple rules, like a careful
# (or careless) player would, and play whole seasons of the company without a screen.
#
# opts: idle, bake_factor (100 = the forecast), price_pct, marketing, max_bake, order_ahead, contract (accept offers),
#       accountant, upgrades, cafe (open the café when possible), loan (borrow to open it), upkeep (clean and maintain), counter

static func plan_for(co: Company, bid: String, opts: Dictionary) -> Dictionary:
	var b: Business = co.units[bid]
	var plan := b.empty_plan()
	if opts.get("idle", false): return plan
	var mk_id: String = opts.get("marketing", "none")
	if not b.db["marketing"].has(mk_id) or not b.unlocked("marketing", mk_id, co.level()): mk_id = "none"
	plan["marketing"] = mk_id
	if mk_id == "promo": plan["promo_product"] = b.db["products"].keys()[0]
	for pid in b.db["products"]:
		var bnd := b.price_bounds(pid)
		plan["prices"][pid] = clampi(int(b.db["products"][pid]["price"]) * int(opts.get("price_pct", 100)) / 100, bnd.x, bnd.y)
	var want := co.forecast_items(bid, plan)
	var hint := {}
	if bid == "bakery" and co.unit_ready("cafe"):
		hint["cafe"] = {"transfer_in": {"croissant": int(co.forecast_items("cafe", co.units["cafe"].empty_plan()).get("croissant", 0))}}
	var reserved := co.reserved_for(bid, hint)
	var cap := b.capacity(co.mod_value("capacity_pct", bid)); var used := 0
	if b.db["capacity"]["name"] == "cap.oven":
		var ids: Array = b.db["products"].keys()
		ids.sort_custom(func(x, y): return int(want.get(x, 0)) > int(want.get(y, 0)))
		for pid in ids:
			if not b.is_baked(pid): continue
			var n := int(want.get(pid, 0)) * int(opts.get("bake_factor", 100)) / 100 + int(reserved.get(pid, 0)) - b.inv.old(pid)
			if opts.get("max_bake", false): n = 999
			var per: int = b.db["products"][pid]["cap"]
			n = clampi(n, 0, (cap - used) / maxi(1, per))
			plan["bake"][pid] = n; used += n * per
	# buy now what is missing for today (expensive), the rest is ordered for tomorrow
	var need := b.bake_needs(plan)
	for iid in need:
		var miss: int = int(need[iid]) - b.inv.units(iid)
		if miss > 0:
			var st := co.item_step(bid, iid)
			plan["buy_now"][iid] = (miss + st - 1) / st * st
	if bid == "cafe":
		plan["transfer_in"] = {"croissant": int(want.get("croissant", 0))}
		var cookies := int(want.get("cookie", 0)) - b.inv.stock("cookie")
		if cookies > 0 and not opts.get("order_ahead", false): plan["buy_now"]["cookie"] = (cookies + 9) / 10 * 10
		for iid in ["beans", "milk"]:
			var drinks := int(want.get("cappuccino", 0)) + int(want.get("americano", 0)) + int(want.get("iced", 0))
			var miss2 := drinks + 4 - b.inv.units(iid)
			if miss2 > 0 and not opts.get("order_ahead", false): plan["buy_now"][iid] = (miss2 + 9) / 10 * 10
	if opts.get("upkeep", true):
		plan["deep_clean"] = b.cleanliness < 60
		plan["maintenance"] = b.equipment < 55
	# never more than the cash allows: drop the extras first
	var ctx := co.plan_ctx(bid)
	while not b.validate_plan(plan, ctx).is_empty() and plan["marketing"] != "none":
		plan["marketing"] = "none"
	return plan

# Orders tomorrow's ingredients from the wholesaler (cheaper than buying in the morning).
static func order_ahead(co: Company, bid: String) -> void:
	var b: Business = co.units[bid]
	var want := co.forecast_items(bid, b.empty_plan())
	var need := {}
	for pid in b.db["products"]:
		var pr: Dictionary = b.db["products"][pid]
		var n := int(want.get(pid, 0)) + 2
		if bid == "bakery" and pid in ["croissant", "challah"]: n += 8
		if bid == "cafe": n = n * 13 / 10 + 2
		for iid in pr.get("recipe", {}): need[iid] = int(need.get(iid, 0)) + int(pr["recipe"][iid]) * n
		if pr.has("resale") and bid == "cafe" and pid == "cookie": need["cookie"] = int(need.get("cookie", 0)) + n
	var items := {}
	for iid in need:
		var st := co.item_step(bid, iid)
		var miss: int = int(need[iid]) - b.inv.units(iid) - (b.inv.stock(iid) if not b.db["ingredients"].has(iid) else 0)
		if miss > 0: items[iid] = (miss + st - 1) / st * st
	if not items.is_empty(): co.place_order(bid, "wholesale", items)

static func choose(co: Company, ev: Dictionary, opts: Dictionary) -> int:
	match ev["kind"]:
		"contract_offer": return (1 if opts.get("counter", false) else 0) if opts.get("contract", false) else 2
		"payment_late": return 0
		"staff_raise": return 0
	if ev["id"] == "catering": return 0 if opts.get("contract", false) else 1
	if ev["id"] == "influencer": return 1
	return 0

static func play(content: ContentDb, seed_value: int, days: int, opts: Dictionary) -> Dictionary:
	var co := Company.new(content); co.new_game(seed_value)
	var res := {"profit_per_day": 0, "cash": 0, "rep": 0, "served": 0, "lost": 0, "waste": 0, "bankrupt_days": 0, "min_cash": 1 << 30, "errors": [],
		"cafe_day": 0, "level": 0, "inspections": 0, "fines": 0, "contract": 0, "days_played": 0, "late_profit": 0, "invested": 0}
	var late := []
	var total_profit := 0
	while co.day <= days:
		var rep := co.start_morning()
		for ev in rep["events"].duplicate(): co.resolve_event(ev, choose(co, ev, opts))
		if opts.get("accountant", false) and not co.services.has("accountant") and co.level() >= 2: co.subscribe("accountant", true)
		if opts.get("cafe", false) and not co.owns("cafe"):
			if opts.get("loan", false) and co.level() >= 3 and not co.loan_open("large") and co.profile.cash < 6500: co.take_loan("large")
			if co.can_open("cafe").is_empty() and co.profile.cash >= int(co.world["openable"]["cafe"]["cost"]) + (1200 if not opts.get("loan", false) else 0):
				co.open_business("cafe"); res["cafe_day"] = co.day
		if co.owns("cafe") and co.staff.is_empty() and co.level() >= 2: co.hire("yossi", "cafe")
		if opts.get("upgrades", false) and (co.owns("cafe") or not opts.get("cafe", false)):
			for bid in co.units:
				for uid in co.units[bid].db["upgrades"]:
					var u: Dictionary = co.units[bid].db["upgrades"][uid]
					if not co.units[bid].upgrades.has(uid) and co.level() >= int(u["unlock_level"]) and co.profile.cash > int(u["cost"]) + 4500: co.buy_upgrade(bid, uid)
		var plans := {}
		for bid in co.units:
			if co.unit_ready(bid): plans[bid] = plan_for(co, bid, opts)
		var errs := co.commit_day(plans, "bakery")
		if not errs.is_empty():
			for bid in plans: plans[bid] = co.units[bid].empty_plan()
			errs = co.commit_day(plans, "bakery")
			if not errs.is_empty(): res["errors"].append("day %d: %s" % [co.day, Loc.msg(errs[0])]); break
		if opts.get("order_ahead", false) and not opts.get("idle", false):
			for bid in co.units: order_ahead(co, bid)
		var s := co.close_day()
		total_profit += int(s["profit"]); res["days_played"] += 1
		late.append(int(s["profit"]))
		if late.size() > 12: late.pop_front()
		for bid in s["units"]:
			var u: Dictionary = s["units"][bid]
			res["served"] += u["served"]; res["lost"] += u["lost_stock"] + u["lost_price"] + u["walkouts"]; res["waste"] += u["waste_cost"]
		res["min_cash"] = mini(res["min_cash"], co.profile.cash)
		if co.profile.cash < -co.overdraft_limit(): res["bankrupt_days"] += 1
		# invariants
		if co.ledger.balance() != co.profile.cash: res["errors"].append("day %d: ledger %d != cash %d" % [co.day, co.ledger.balance(), co.profile.cash])
		for bid in co.units:
			for iid in co.units[bid].inv.ing:
				if co.units[bid].inv.ing[iid]["units"] < 0: res["errors"].append("negative stock %s" % iid)
		if typeof(s["profit"]) != TYPE_INT: res["errors"].append("profit is not an int")
	res["profit_per_day"] = total_profit / maxi(1, res["days_played"])
	res["cash"] = co.profile.cash - co.debt()
	var lt := 0
	for x in late: lt += x
	res["late_profit"] = lt / maxi(1, late.size())
	res["invested"] = -co.ledger.total_since(1, "investment") - co.ledger.total_since(1, "upgrade")
	var r := 0
	for bid in co.units: r += co.units[bid].reputation
	res["rep"] = r / co.units.size()
	res["level"] = co.level(); res["inspections"] = int(co.stats["inspections_passed"])
	res["contract"] = 1 if co.contracts.has("minimarket") and co.contracts["minimarket"]["active"] else 0
	res["goals"] = co.goals_done.size()
	return res
