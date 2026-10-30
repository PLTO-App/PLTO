class_name Business
extends RefCounted
# One business the player owns (a bakery, a café...): its stock, prices, upgrades, reputation, cleanliness and equipment, the morning
# plan, and the numbers of its day. The company (Company) owns the cash and runs the day across businesses; this class never touches
# cash itself, it returns the cash movements for the company to book. It knows nothing about the screen or the 3D world.

const MIN_PRICE_PCT := 50
const MAX_PRICE_PCT := 160

var id := ""
var db: Dictionary
var inv := Inventory.new()
var prices := {}
var upgrades := {}
var reputation := 50
var cleanliness := 100
var equipment := 100
var marketing := "none"
var promo_product := ""
var last_plan := {}
var last_summary := {}
var history: Array = []
var sold_total := 0
var opened_day := 1
var today := {}                # what happened today outside the counter: deliveries to partners, internal transfers, extra costs

func _init(p_db: Dictionary) -> void:
	db = p_db; id = db["id"]

func new_unit(day: int, start_prices: Dictionary) -> void:
	inv.reset(db["start"]["stock"], ingredient_ids(), product_ids(), start_prices)
	prices = {}
	for pid in db["products"]: prices[pid] = int(db["products"][pid]["price"])
	upgrades = {}; reputation = int(db["start"]["reputation"]); cleanliness = 100; equipment = 100
	marketing = "none"; promo_product = ""; last_plan = {}; last_summary = {}; history = []; sold_total = 0; opened_day = day
	reset_today()

func reset_today() -> void:
	today = {"b2b_revenue": 0, "b2b_cost": 0, "internal_revenue": 0, "internal_cost": 0, "b2b_missed": 0, "other": 0, "extras": 0,
		"delivered": {}, "transfers_out": 0}

func ingredient_ids() -> Array: return db["ingredients"].keys()
func product_ids() -> Array: return db["products"].keys()
func goods_input_ids() -> Array: return db.get("goods_inputs", {}).keys()

func is_mto(pid: String) -> bool: return bool(db["products"][pid].get("made_to_order", false))
func is_resale(pid: String) -> bool: return db["products"][pid].has("resale")
func is_baked(pid: String) -> bool: return not is_mto(pid) and not is_resale(pid)

# A shop that makes nothing: everything is bought ready and sold from shelves with limited room.
func is_retail() -> bool: return str(db.get("kind", "")) == "retail"

# Pieces on the shelves (fresh and old, all products).
func stock_total() -> int:
	var n := 0
	for pid in db["products"]: n += inv.stock(pid)
	return n

# The product a bought input becomes (a café buys "croissant" goods and sells them as its "croissant" product).
func product_for_input(input_id: String) -> String:
	for pid in db["products"]:
		if str(db["products"][pid].get("resale", "")) == input_id: return pid
	return ""

func shelf_days() -> Dictionary:
	var s := {}
	for pid in db["products"]: s[pid] = int(db["products"][pid].get("shelf_days", 1))
	return s

# ---------------------------------------------------------------- derived numbers
func effect(key: String) -> int:
	var t := 0
	for u in upgrades: t += int(db["upgrades"][u]["effect"].get(key, 0))
	return t

func capacity(mod_pct := 0) -> int:
	return (int(db["capacity"]["amount"]) + effect("capacity")) * (100 + mod_pct) / 100

func wtp_bonus_pct() -> int:
	return effect("wtp_pct")

func price_today(pid: String) -> int:
	var p: int = prices[pid]
	if marketing == "promo" and promo_product == pid: p = p * (100 - int(db["marketing"]["promo"]["discount_pct"])) / 100
	return p

func price_bounds(pid: String) -> Vector2i:
	var ref: int = db["products"][pid]["price"]
	return Vector2i(maxi(1, ref * MIN_PRICE_PCT / 100), ref * MAX_PRICE_PCT / 100)

func price_step(pid: String) -> int:
	return 1 if int(db["products"][pid]["price"]) < 40 else 5

# Cost of the ingredients (or of the bought item) of one piece at a supplier's prices.
func unit_cost(pid: String, supplier_prices: Dictionary) -> int:
	var pr: Dictionary = db["products"][pid]
	if pr.has("resale"): return int(supplier_prices.get(pr["resale"], 0))
	var c := 0
	for iid in pr.get("recipe", {}): c += int(pr["recipe"][iid]) * int(supplier_prices.get(iid, 0))
	return c

func storage_ok(limit_units: int) -> bool:
	return upgrades.has("fridge") or inv.total_units() <= limit_units

func any_stock() -> bool:
	for pid in db["products"]:
		if inv.stock(pid) > 0: return true
		if is_mto(pid) and inv.max_pieces(db["products"][pid]["recipe"]) > 0: return true
	return false

func unlocked(kind: String, key: String, level: int) -> bool:
	return level >= int(db[kind][key].get("unlock_level", 1))

# ---------------------------------------------------------------- the morning plan
# plan: {bake: {pid: n}, buy_now: {item: qty}, prices: {pid: price}, marketing, promo_product, deep_clean: bool, maintenance: bool}
# ctx:  {level, cash_available, now_prices: {item: price}, now_quality, capacity_pct, upkeep: {...}}
func empty_plan() -> Dictionary:
	var p := {"bake": {}, "buy_now": {}, "prices": prices.duplicate(), "marketing": "none", "promo_product": "", "deep_clean": false, "maintenance": false, "transfer_in": {}}
	for pid in db["products"]:
		if is_baked(pid): p["bake"][pid] = 0
		if p["promo_product"] == "": p["promo_product"] = pid
	return p

func plan_costs(plan: Dictionary, ctx: Dictionary) -> Dictionary:
	var buy := 0
	var np: Dictionary = ctx.get("now_prices", {})
	for item in plan.get("buy_now", {}): buy += int(plan["buy_now"][item]) * int(np.get(item, 0))
	var mk := int(db["marketing"][plan.get("marketing", "none")]["cost"])
	var up: Dictionary = ctx.get("upkeep", {})
	var extras := (int(up.get("deep_clean_cost", 0)) if plan.get("deep_clean", false) else 0) + (int(up.get("maintenance_cost", 0)) if plan.get("maintenance", false) else 0)
	return {"buy": buy, "marketing": mk, "extras": extras, "total": buy + mk + extras}

func capacity_used(plan: Dictionary) -> int:
	var u := 0
	for pid in plan.get("bake", {}): u += int(plan["bake"][pid]) * int(db["products"][pid]["cap"])
	return u

# Ingredient units the bake needs.
func bake_needs(plan: Dictionary) -> Dictionary:
	var need := {}
	for iid in db["ingredients"]: need[iid] = 0
	for pid in plan.get("bake", {}):
		for iid in db["products"][pid].get("recipe", {}): need[iid] += int(db["products"][pid]["recipe"][iid]) * int(plan["bake"][pid])
	return need

# Returns a list of problems as messages ({k, p}). Empty means the plan can be carried out.
func validate_plan(plan: Dictionary, ctx: Dictionary) -> Array:
	var errs: Array = []
	var level := int(ctx.get("level", 1))
	var mk_id: String = plan.get("marketing", "none")
	if not db["marketing"].has(mk_id) or not unlocked("marketing", mk_id, level): errs.append(Loc.m("err.marketing_locked"))
	if mk_id == "promo" and not db["products"].has(plan.get("promo_product", "")): errs.append(Loc.m("err.promo_product"))
	if not errs.is_empty(): return errs
	var costs := plan_costs(plan, ctx)
	if costs["total"] > 0 and costs["total"] > int(ctx.get("cash_available", 0)):
		errs.append(Loc.m("err.no_cash", {"amount_m": costs["total"] - int(ctx.get("cash_available", 0))}))
	var cap := capacity(int(ctx.get("capacity_pct", 0))); var used := capacity_used(plan)
	if used > cap: errs.append(Loc.m("err.capacity", {"cap_k": db["capacity"]["name"], "max": cap, "used": used}))
	if is_retail():
		var held := stock_total(); var buying := 0
		for item in plan.get("buy_now", {}): buying += int(plan["buy_now"][item])
		if buying > 0 and held + buying > cap: errs.append(Loc.m("err.shelf_full", {"used": held + buying, "cap": cap}))
	var need := bake_needs(plan)
	for iid in need:
		if inv.units(iid) + int(plan.get("buy_now", {}).get(iid, 0)) < need[iid]: errs.append(Loc.m("err.missing", {"item_k": db["ingredients"][iid]["name"]}))
	for pid in plan.get("prices", {}):
		var b := price_bounds(pid); var p := int(plan["prices"][pid])
		if p < b.x or p > b.y: errs.append(Loc.m("err.price_range", {"product_k": db["products"][pid]["name"]}))
	return errs

# Carries the plan out. Returns the cash movements for the company: [{cat, amount, note}].
func commit_plan(plan: Dictionary, ctx: Dictionary) -> Array:
	var cash: Array = []
	var np: Dictionary = ctx.get("now_prices", {}); var q := int(ctx.get("now_quality", 75))
	for item in plan.get("buy_now", {}):
		var n := int(plan["buy_now"][item]); if n <= 0: continue
		var price := int(np.get(item, 0))
		cash.append({"cat": "purchase", "amount": -n * price, "note": item})
		if db["ingredients"].has(item): inv.add_ingredient(item, n, q, price)
		else:
			var pid := product_for_input(item)
			if pid != "": inv.add_goods(pid, n, q, price)
	var up: Dictionary = ctx.get("upkeep", {})
	if plan.get("deep_clean", false):
		cleanliness = 100; var c := int(up.get("deep_clean_cost", 0)); cash.append({"cat": "upkeep", "amount": -c, "note": "clean"}); today["extras"] += c
	if plan.get("maintenance", false):
		equipment = 100; var c2 := int(up.get("maintenance_cost", 0)); cash.append({"cat": "upkeep", "amount": -c2, "note": "maintenance"}); today["extras"] += c2
	for pid in plan.get("bake", {}):
		var n := int(plan["bake"][pid]); if n > 0: inv.bake(pid, db["products"][pid]["recipe"], n)
	for pid in plan.get("prices", {}): prices[pid] = int(plan["prices"][pid])
	marketing = plan.get("marketing", "none"); promo_product = plan.get("promo_product", "")
	var mk := int(db["marketing"][marketing]["cost"])
	if mk > 0: cash.append({"cat": "marketing", "amount": -mk, "note": marketing})
	last_plan = plan.duplicate(true)
	return cash

# ---------------------------------------------------------------- closing
# ctx: {day, weekday_k, fixed (accrual today), wages (today), level, first_day, xp_rules}
func close_day(runner: DayRunner, ctx: Dictionary) -> Dictionary:
	for c in runner.queue: runner.outcomes.append({"type": "walkout", "customer": c, "waited": 0})
	runner.queue.clear()
	var s := {"biz": id, "day": ctx["day"], "closed": runner.closed, "customers": runner.customers.size(), "served": 0, "lost_price": 0, "lost_stock": 0,
		"walkouts": 0, "substitutes": 0, "partial": 0, "revenue": 0, "cogs": 0, "items": 0, "campaign_customers": 0, "campaign_revenue": 0,
		"marketing_id": marketing, "sat_sum": 0, "sold": {}}
	var stock_lost := {}
	for o in runner.outcomes:
		var campaign: bool = o["customer"]["source"] == "campaign"
		match o["type"]:
			"sale":
				s["served"] += 1; s["revenue"] += o["revenue"]; s["cogs"] += o["cost"]; s["sat_sum"] += o["sat"]; s["items"] += o["qty"]
				s["sold"][o["product"]] = s["sold"].get(o["product"], 0) + o["qty"]
				if o.has("addon"): s["sold"][o["addon"]["product"]] = s["sold"].get(o["addon"]["product"], 0) + 1; s["items"] += 1
				if o["substitute"]: s["substitutes"] += 1
				if o["partial"]: s["partial"] += 1
				if campaign: s["campaign_customers"] += 1; s["campaign_revenue"] += o["revenue"]
			"lost_price": s["lost_price"] += 1
			"lost_stock": s["lost_stock"] += 1; stock_lost[o["wanted"]] = stock_lost.get(o["wanted"], 0) + 1
			"walkout", "closed": s["walkouts"] += 1
	var top := ""; var top_n := 0
	for pid in stock_lost: if stock_lost[pid] > top_n: top = pid; top_n = stock_lost[pid]
	s["top_stockout"] = top
	s["avg_sat"] = s["sat_sum"] / s["served"] if s["served"] > 0 else 0
	var waste := inv.close_day(shelf_days())
	s["waste_pieces"] = 0; s["waste_cost"] = 0
	for w in waste: s["waste_pieces"] += w["pieces"]; s["waste_cost"] += w["cost"]
	s["marketing_cost"] = int(db["marketing"][marketing]["cost"])
	s["fixed"] = int(ctx.get("fixed", 0)); s["wages"] = int(ctx.get("wages", 0))
	s["b2b_revenue"] = today["b2b_revenue"]; s["b2b_cost"] = today["b2b_cost"]; s["b2b_missed"] = today["b2b_missed"]
	s["internal_revenue"] = today["internal_revenue"]; s["internal_cost"] = today["internal_cost"]
	s["other"] = today["other"] + today["extras"]
	s["profit"] = s["revenue"] + s["b2b_revenue"] + s["internal_revenue"] - s["cogs"] - s["b2b_cost"] - s["internal_cost"] - s["waste_cost"] - s["marketing_cost"] - s["fixed"] - s["wages"] - s["other"]
	# reputation: how people felt, minus those who left unhappy, minus deliveries we missed
	var rep := 0
	if runner.closed: rep = -2
	elif s["served"] > 0: rep = clampi((s["avg_sat"] - 62) / 5, -5, 5)
	else: rep = -2
	rep = clampi(rep - mini(2, s["walkouts"] / 3) - mini(2, s["lost_stock"] / 3) - mini(2, s["b2b_missed"]), -8, 8)
	s["rep_delta"] = rep; reputation = clampi(reputation + rep, 0, 100)
	# cleanliness and equipment wear with use
	var up: Dictionary = ctx.get("upkeep", {})
	cleanliness = clampi(cleanliness - int(up.get("clean_decay", 9)) - s["served"] / maxi(1, int(up.get("clean_per_customers", 6))) + int(ctx.get("clean_bonus", 0)), 0, 100)
	equipment = clampi(equipment - int(up.get("equip_decay", 4)), 0, 100)
	s["cleanliness"] = cleanliness; s["equipment"] = equipment
	var xr: Dictionary = db["xp_rules"]; var bonus := 0
	if not runner.closed:
		if s["profit"] > 0: bonus += xr["profitable_day"]
		if s["lost_stock"] == 0 and s["served"] > 0: bonus += xr["no_stockout"]
		if s["avg_sat"] >= xr["happy_threshold"] and s["served"] > 0: bonus += xr["happy_customers"]
		if ctx.get("first_day", false): bonus += xr["first_day"]
	s["xp_bonus"] = bonus
	sold_total += s["items"]
	s.erase("sat_sum")
	last_summary = s
	history.append({"day": ctx["day"], "revenue": s["revenue"] + s["b2b_revenue"] + s["internal_revenue"], "profit": s["profit"], "rep": reputation, "served": s["served"]})
	if history.size() > 14: history.pop_front()
	marketing = "none"; promo_product = ""
	return s

# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	return {"id": id, "prices": prices.duplicate(), "upgrades": upgrades.duplicate(), "reputation": reputation, "cleanliness": cleanliness, "equipment": equipment,
		"last_plan": last_plan.duplicate(true), "last_summary": last_summary.duplicate(true), "history": history.duplicate(true), "sold_total": sold_total,
		"opened_day": opened_day, "inv": inv.to_dict()}

func from_dict(d: Dictionary) -> void:
	prices = {}
	for pid in db["products"]:
		var b := price_bounds(pid)
		prices[pid] = clampi(int(d.get("prices", {}).get(pid, db["products"][pid]["price"])), b.x, b.y)
	upgrades = {}
	for u in d.get("upgrades", {}): if db["upgrades"].has(u): upgrades[u] = true
	reputation = clampi(int(d.get("reputation", 50)), 0, 100); cleanliness = clampi(int(d.get("cleanliness", 100)), 0, 100)
	equipment = clampi(int(d.get("equipment", 100)), 0, 100)
	last_plan = d.get("last_plan", {}); last_summary = d.get("last_summary", {}); history = d.get("history", [])
	sold_total = maxi(0, int(d.get("sold_total", 0))); opened_day = int(d.get("opened_day", 1))
	inv.from_dict(d.get("inv", {}), ingredient_ids(), product_ids())
	marketing = "none"; promo_product = ""
	reset_today()
