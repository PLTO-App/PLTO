class_name Business
extends RefCounted
# The business simulation: what the owner decides in the morning (what to bake and buy, prices, marketing), the working day
# (see DayRunner), and the closing numbers (profit and loss, cash, reputation, experience). It knows nothing about the screen
# or the 3D world, so a whole month can be played in a test in a second.

const MIN_PRICE_PCT := 50
const MAX_PRICE_PCT := 150
const PRICE_STEP := 5

var db: Dictionary
var content: ContentDb
var profile: Profile
var ledger := Ledger.new()
var inv := Inventory.new()
var day := 1
var seed_value := 1
var prices := {}
var upgrades := {}
var history: Array = []
var last_plan := {}
var last_summary := {}
var marketing := "none"
var promo_product := ""
var phase := "morning"        # morning | day
var day_start_cash := 0
var snapshot := {}             # the last safe point to save (a mid-day state is never saved)

func _init(content_db: ContentDb, business_id: String, p: Profile) -> void:
	content = content_db; db = content_db.businesses[business_id]; profile = p

# ---------------------------------------------------------------- start / load / save
func new_game(keep_progress: bool, new_seed: int) -> void:
	if not keep_progress:
		profile.reset(content); profile.cash = db["start"]["cash"]; profile.reputation = db["start"]["reputation"]
	seed_value = new_seed; day = 1; ledger = Ledger.new(); history = []; upgrades = {}; last_plan = {}; last_summary = {}
	inv.reset(db["start"]["stock"], db["ingredients"].keys(), db["products"].keys())
	prices = {}
	for pid in db["products"]: prices[pid] = db["products"][pid]["price"]
	marketing = "none"; promo_product = ""; phase = "morning"
	_snap()

func to_dict() -> Dictionary:
	return {"profile": profile.to_dict(), "day": day, "seed": seed_value, "prices": prices.duplicate(), "upgrades": upgrades.duplicate(),
		"history": history.duplicate(true), "last_plan": last_plan.duplicate(true), "last_summary": last_summary.duplicate(true),
		"inv": inv.to_dict(), "ledger": ledger.to_array()}

func from_dict(d: Dictionary) -> void:
	profile.from_dict(d.get("profile", {}), content)
	day = maxi(1, int(d.get("day", 1))); seed_value = int(d.get("seed", 1))
	prices = {}
	for pid in db["products"]: prices[pid] = int(d.get("prices", {}).get(pid, db["products"][pid]["price"]))
	upgrades = {}
	for u in d.get("upgrades", {}): if db["upgrades"].has(u): upgrades[u] = true
	history = d.get("history", []); last_plan = d.get("last_plan", {}); last_summary = d.get("last_summary", {})
	inv.from_dict(d.get("inv", {}), db["ingredients"].keys(), db["products"].keys())
	ledger.from_array(d.get("ledger", []))
	marketing = "none"; promo_product = ""; phase = "morning"
	_snap()

func _snap() -> void:
	snapshot = to_dict()

# ---------------------------------------------------------------- derived numbers
func _effect(key: String) -> int:
	var t := 0
	for u in upgrades: t += int(db["upgrades"][u]["effect"].get(key, 0))
	return t

func oven_capacity() -> int:
	return db["oven_capacity"] + _effect("oven_capacity")

func wtp_bonus_pct() -> int:
	return _effect("wtp_pct")

func weekday_name() -> String:
	return db["weekday_names"][(day - 1) % 7]

func price_today(pid: String) -> int:
	var p: int = prices[pid]
	if marketing == "promo" and promo_product == pid: p = p * (100 - db["marketing"]["promo"]["discount_pct"]) / 100
	return p

func price_bounds(pid: String) -> Vector2i:
	var ref: int = db["products"][pid]["price"]
	return Vector2i(ref * MIN_PRICE_PCT / 100 / PRICE_STEP * PRICE_STEP, ref * MAX_PRICE_PCT / 100 / PRICE_STEP * PRICE_STEP)

func unit_cost(pid: String, supplier: String) -> int:
	var c := 0
	for iid in db["products"][pid]["recipe"]: c += db["products"][pid]["recipe"][iid] * db["suppliers"][supplier]["prices"][iid]
	return c

# A rough forecast (low, high) for the morning planner. Real owners estimate; they do not know.
func forecast(plan: Dictionary) -> Vector2i:
	var mk: Dictionary = db["marketing"][plan.get("marketing", "none")]
	var idx := Demand.price_index_pct(db, plan.get("prices", prices))
	var e := Demand.expected(db, day, profile.reputation, idx, mk["reach_pct"], _effect("base_customers"))
	return Vector2i(maxi(1, roundi(e) - 2), roundi(e) + 2)

func unlocked(kind: String, id: String) -> bool:
	return profile.level >= int(db[kind][id]["unlock_level"])

# ---------------------------------------------------------------- the morning plan
# plan: {supplier, buy: {ingredient: qty}, bake: {product: pieces}, prices: {product: price}, marketing, promo_product}
func plan_costs(plan: Dictionary) -> Dictionary:
	var sup: Dictionary = db["suppliers"][plan.get("supplier", "wholesale")]
	var buy := 0
	for iid in plan.get("buy", {}): buy += int(plan["buy"][iid]) * sup["prices"][iid]
	var mk := int(db["marketing"][plan.get("marketing", "none")]["cost"])
	return {"buy": buy, "marketing": mk, "total": buy + mk}

# Returns a list of problems (Hebrew, short). Empty means the plan can be carried out.
func validate_plan(plan: Dictionary) -> Array:
	var errs: Array = []
	var sup_id: String = plan.get("supplier", "wholesale")
	if not db["suppliers"].has(sup_id) or not unlocked("suppliers", sup_id): errs.append("הספק הזה עדיין נעול.")
	var mk_id: String = plan.get("marketing", "none")
	if not db["marketing"].has(mk_id) or not unlocked("marketing", mk_id): errs.append("סוג השיווק הזה עדיין נעול.")
	if mk_id == "promo" and not db["products"].has(plan.get("promo_product", "")): errs.append("במבצע צריך לבחור מוצר.")
	if not errs.is_empty(): return errs
	var costs := plan_costs(plan)
	if costs["total"] > 0 and costs["total"] > profile.cash: errs.append("אין מספיק כסף בקופה: חסרים %s." % UiMoney.fmt(costs["total"] - profile.cash))
	var have := {}
	for iid in db["ingredients"]: have[iid] = inv.units(iid) + int(plan.get("buy", {}).get(iid, 0))
	var oven := 0
	for pid in plan.get("bake", {}):
		var n := int(plan["bake"][pid]); if n <= 0: continue
		oven += n * db["products"][pid]["oven"]
		for iid in db["products"][pid]["recipe"]: have[iid] -= db["products"][pid]["recipe"][iid] * n
	if oven > oven_capacity(): errs.append("התנור מכיל עד %d יחידות תפוקה, ובתוכנית %d." % [oven_capacity(), oven])
	for iid in have:
		if have[iid] < 0: errs.append("חסר %s לאפייה." % db["ingredients"][iid]["name"])
	for pid in plan.get("prices", {}):
		var b := price_bounds(pid); var p := int(plan["prices"][pid])
		if p < b.x or p > b.y: errs.append("המחיר של %s מחוץ לטווח." % db["products"][pid]["name"])
	return errs

# Carries the plan out: pays, buys, bakes, sets prices and marketing. The working day can start after this.
func commit_plan(plan: Dictionary) -> Array:
	var errs := validate_plan(plan)
	if not errs.is_empty(): return errs
	day_start_cash = profile.cash
	var sup_id: String = plan.get("supplier", "wholesale"); var sup: Dictionary = db["suppliers"][sup_id]
	for iid in plan.get("buy", {}):
		var q := int(plan["buy"][iid]); if q <= 0: continue
		var price: int = sup["prices"][iid]
		profile.add_cash(-q * price); ledger.add(day, "purchase", -q * price, iid)
		inv.add_ingredient(iid, q, sup["quality"], price)
	for pid in plan.get("bake", {}):
		var n := int(plan["bake"][pid]); if n > 0: inv.bake(pid, db["products"][pid]["recipe"], n)
	for pid in plan.get("prices", {}): prices[pid] = int(plan["prices"][pid])
	marketing = plan.get("marketing", "none"); promo_product = plan.get("promo_product", "")
	var mk := int(db["marketing"][marketing]["cost"])
	if mk > 0: profile.add_cash(-mk); ledger.add(day, "marketing", -mk, marketing)
	last_plan = plan.duplicate(true); phase = "day"
	return []

func buy_upgrade(id: String) -> String:
	if not db["upgrades"].has(id) or upgrades.has(id): return "השדרוג הזה כבר נרכש."
	if not unlocked("upgrades", id): return "השדרוג ייפתח בדרגה %d." % db["upgrades"][id]["unlock_level"]
	var cost: int = db["upgrades"][id]["cost"]
	if cost > profile.cash: return "אין מספיק כסף בקופה."
	profile.add_cash(-cost); ledger.add(day, "upgrade", -cost, id); upgrades[id] = true
	_snap()
	return ""

# ---------------------------------------------------------------- the day
# Called when a morning starts. If the cash is nearly gone and there is nothing to bake or sell, the family helps once more,
# so the game can never lock. Returns the amount given (0 when nothing was needed).
func morning_relief() -> int:
	var goods_left := 0
	for pid in inv.goods: goods_left += inv.stock(pid)
	var ing_value := 0
	for iid in inv.ing: ing_value += inv.ing[iid]["value"]
	if profile.cash >= 150 or goods_left > 0 or ing_value > 60: return 0
	var help := 300 - maxi(0, profile.cash)
	profile.add_cash(help); ledger.add(day, "relief", help, "family")
	_snap()
	return help

func begin_day() -> DayRunner:
	var mk: Dictionary = db["marketing"][marketing]
	var idx := Demand.price_index_pct(db, _today_prices())
	var rng := SimRng.new(seed_value, day, "customers")
	var custs := Demand.generate(db, rng, day, profile.reputation, idx, mk["reach_pct"], _effect("base_customers"), promo_product if marketing == "promo" else "", mk["pref_mult"])
	return DayRunner.new(self, custs)

func _today_prices() -> Dictionary:
	var t := {}
	for pid in prices: t[pid] = price_today(pid)
	return t

# Closes the books for the day. `runner` must be finished (or the remaining customers are counted as lost).
func close_day(runner: DayRunner) -> Dictionary:
	for c in runner.queue: runner.outcomes.append({"type": "walkout", "customer": c, "waited": 0})
	runner.queue.clear()
	var s := {"day": day, "weekday": weekday_name(), "first_day": day == 1, "customers": runner.customers.size(), "served": 0, "lost_price": 0, "lost_stock": 0,
		"walkouts": 0, "substitutes": 0, "revenue": 0, "cogs": 0, "campaign_customers": 0, "campaign_revenue": 0, "marketing_id": marketing, "sat_sum": 0}
	var stock_lost := {}
	for o in runner.outcomes:
		var campaign: bool = o["customer"]["source"] == "campaign"
		match o["type"]:
			"sale":
				s["served"] += 1; s["revenue"] += o["price"]; s["cogs"] += o["cost"]; s["sat_sum"] += o["sat"]
				if o["substitute"]: s["substitutes"] += 1
				if campaign: s["campaign_customers"] += 1; s["campaign_revenue"] += o["price"]
			"lost_price": s["lost_price"] += 1
			"lost_stock": s["lost_stock"] += 1; stock_lost[o["wanted"]] = stock_lost.get(o["wanted"], 0) + 1
			"walkout": s["walkouts"] += 1
	var top := ""; var top_n := 0
	for pid in stock_lost: if stock_lost[pid] > top_n: top = pid; top_n = stock_lost[pid]
	s["top_stockout"] = top
	s["avg_sat"] = s["sat_sum"] / s["served"] if s["served"] > 0 else 0
	# fixed costs are paid in cash at the end of the day
	var fixed := 0
	for k in db["fixed_costs"]: fixed += int(db["fixed_costs"][k])
	profile.add_cash(-fixed); ledger.add(day, "fixed", -fixed, "")
	var shelf := {}
	for pid in db["products"]: shelf[pid] = db["products"][pid]["shelf_days"]
	var waste := inv.close_day(shelf)
	s["waste_pieces"] = 0; s["waste_cost"] = 0
	for w in waste: s["waste_pieces"] += w["pieces"]; s["waste_cost"] += w["cost"]
	s["marketing_cost"] = int(db["marketing"][marketing]["cost"]); s["fixed"] = fixed
	s["purchases"] = -ledger.total(day, "purchase")
	s["profit"] = s["revenue"] - s["cogs"] - s["waste_cost"] - s["marketing_cost"] - fixed
	s["cash_change"] = ledger.total(day) - ledger.total(day, "upgrade")
	s["cash_end"] = profile.cash
	# reputation and experience
	var rep := 0
	if s["served"] > 0: rep = clampi((s["avg_sat"] - 62) / 5, -5, 5)
	else: rep = -2
	rep = clampi(rep - mini(3, s["walkouts"]) - mini(2, s["lost_stock"]), -8, 8)
	s["rep_delta"] = rep; profile.add_reputation(rep)
	var xr: Dictionary = db["xp_rules"]; var bonus := 0
	if s["profit"] > 0: bonus += xr["profitable_day"]
	if s["lost_stock"] == 0 and s["served"] > 0: bonus += xr["no_stockout"]
	if s["avg_sat"] >= xr["happy_threshold"] and s["served"] > 0: bonus += xr["happy_customers"]
	if day == 1: bonus += xr["first_day"]
	s["xp_bonus"] = bonus
	var gained := profile.add_xp(bonus)
	s["levels"] = runner.levels_gained + gained
	s["coach"] = Coach.lines(s, db, ContentDb.read_json("res://content/common/coach_he.json"))
	s.erase("sat_sum")
	last_summary = s
	history.append({"day": day, "revenue": s["revenue"], "profit": s["profit"], "cash": profile.cash, "rep": profile.reputation, "served": s["served"]})
	if history.size() > 14: history.pop_front()
	day += 1; phase = "morning"; marketing = "none"; promo_product = ""
	ledger.prune(day)
	_snap()
	return s
