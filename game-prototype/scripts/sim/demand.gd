class_name Demand
extends RefCounted
# Who comes to the shop on a given day: how many customers, when, what each wants and how much each would pay.
# Everything comes from the business content plus the day's conditions (weekday, reputation, prices, marketing).

# Average price level across the menu, weighted by how popular each product is. 100 = the market price.
static func price_index_pct(db: Dictionary, prices: Dictionary) -> int:
	var num := 0; var den := 0
	for pid in db["products"]:
		var pr: Dictionary = db["products"][pid]
		num += pr["pref"] * prices.get(pid, pr["price"]) * 100 / pr["price"]; den += pr["pref"]
	return num / maxi(1, den)

# Expected customers (a float, rounded when customers are drawn). reach_pct is the marketing boost.
static func expected(db: Dictionary, day: int, reputation: int, price_index: int, reach_pct: int, base_bonus: int) -> float:
	var base := float(db["base_customers"] + base_bonus)
	var weekday := float(db["weekday_factor"][(day - 1) % 7]) / 100.0
	var rep := 0.7 + 0.6 * float(reputation) / 100.0
	var price := clampf(1.0 + float(100 - price_index) * 0.005, 0.7, 1.2)
	return base * weekday * rep * price * (1.0 + float(reach_pct) / 100.0)

static func generate(db: Dictionary, rng: SimRng, day: int, reputation: int, price_index: int, reach_pct: int, base_bonus: int, promo_product: String, pref_mult: int) -> Array:
	var noise := rng.int_range(-1, 1)
	var n_base := maxi(2, roundi(expected(db, day, reputation, price_index, 0, base_bonus)) + noise)
	var n_total := maxi(n_base, roundi(expected(db, day, reputation, price_index, reach_pct, base_bonus)) + noise)
	var pids: Array = db["products"].keys()
	var sens_w: Array = []
	for s in db["sensitivity"]: sens_w.append(s["w"])
	var out: Array = []
	for i in n_total:
		var weights: Array = []
		for pid in pids: weights.append(db["products"][pid]["pref"] * (pref_mult if pid == promo_product else 100) / 100)
		var look: Dictionary = db["customers"][(day * 7 + i) % db["customers"].size()]
		out.append({"id": i, "name": look["name"], "g": look["g"], "look": look["look"], "arrival": rng.weighted(db["arrival_weights"]),
			"mult": db["sensitivity"][_sens_index(rng, sens_w, i >= n_base and promo_product != "")]["mult"], "patience": rng.int_range(2, 4), "wants": pids[rng.weighted(weights)],
			"source": "campaign" if i >= n_base else "walk_in"})
	out.sort_custom(func(a, b): return a["arrival"] < b["arrival"] or (a["arrival"] == b["arrival"] and a["id"] < b["id"]))
	return out

# A promotion attracts price-hunters: customers who come for it only accept the lower half of the price range.
static func _sens_index(rng: SimRng, weights: Array, price_hunter: bool) -> int:
	var i := rng.weighted(weights)
	return mini(i, 2) if price_hunter else i
