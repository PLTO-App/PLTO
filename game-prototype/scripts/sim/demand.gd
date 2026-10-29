class_name Demand
extends RefCounted
# Who comes to a business on a given day: how many customers, when, what each wants, how many pieces, and how much each would pay.
# Everything comes from the business content plus the day's conditions (weekday, weather, reputation, prices, marketing, events).
# Customers are drawn from the townsfolk, so the same people come back and remember how they were treated.

# Average price level across the menu, weighted by how popular each product is. 100 = the market price.
static func price_index_pct(db: Dictionary, prices: Dictionary) -> int:
	var num := 0; var den := 0
	for pid in db["products"]:
		var pr: Dictionary = db["products"][pid]
		num += pr["pref"] * prices.get(pid, pr["price"]) * 100 / pr["price"]; den += pr["pref"]
	return num / maxi(1, den)

# ctx: {weekday (0..6), weather, reputation, price_index, reach_pct, base_bonus, demand_pct (events)}
static func expected(db: Dictionary, ctx: Dictionary) -> float:
	var base := float(db["base_customers"] + int(ctx.get("base_bonus", 0)))
	var weekday := float(db["weekday_factor"][int(ctx.get("weekday", 0))]) / 100.0
	var rep := 0.7 + 0.6 * float(ctx.get("reputation", 50)) / 100.0
	var price := clampf(1.0 + float(100 - int(ctx.get("price_index", 100))) * 0.006, 0.6, 1.25)
	var wx := float(db.get("weather", {}).get(ctx.get("weather", "sunny"), 100)) / 100.0
	var ev := float(100 + int(ctx.get("demand_pct", 0))) / 100.0
	return base * weekday * rep * price * wx * ev * (1.0 + float(ctx.get("reach_pct", 0)) / 100.0)

static func slots_today(db: Dictionary, weekday: int) -> int:
	return int(db.get("slots_friday", db["slots"])) if weekday == 5 else int(db["slots"])

# Product weights for today (before a promotion).
static func product_weights(db: Dictionary, ctx: Dictionary) -> Dictionary:
	var w := {}
	var wd := int(ctx.get("weekday", 0)); var wx: String = ctx.get("weather", "sunny")
	var pmods: Dictionary = ctx.get("product_pref_pct", {})
	for pid in db["products"]:
		var pr: Dictionary = db["products"][pid]
		var x: int = pr["pref"] * 100
		if pr.has("weekday_pref"): x = x * int(pr["weekday_pref"][wd]) / 100
		if pr.has("weather_pref"): x = x * int(pr["weather_pref"].get(wx, 100)) / 100
		x = x * (100 + int(pmods.get(pid, 0))) / 100
		w[pid] = maxi(0, x)
	return w

# ctx also: promo_product, pref_mult, townsfolk (Array), regulars ({id: {visits, sat}}), patience_bonus
static func generate(db: Dictionary, rng: SimRng, ctx: Dictionary) -> Array:
	var noise := rng.int_range(-1, 1)
	var base_ctx := ctx.duplicate(); base_ctx["reach_pct"] = 0
	var n_base := maxi(2, roundi(expected(db, base_ctx)) + noise)
	var n_total := maxi(n_base, roundi(expected(db, ctx)) + noise)
	var slots := slots_today(db, int(ctx.get("weekday", 0)))
	var arrival: Array = (db["arrival_weights"] as Array).slice(0, slots)
	var pids: Array = db["products"].keys()
	var pw := product_weights(db, ctx)
	var promo: String = ctx.get("promo_product", "")
	var sens_w: Array = []
	for s in db["sensitivity"]: sens_w.append(s["w"])
	var folk: Array = ctx.get("townsfolk", [])
	var regulars: Dictionary = ctx.get("regulars", {})
	var used := {}
	var out: Array = []
	for i in n_total:
		var weights: Array = []
		for pid in pids: weights.append(pw[pid] * (int(ctx.get("pref_mult", 100)) if pid == promo else 100) / 100)
		var campaign := i >= n_base
		var who := {}
		if not folk.is_empty():
			# a person not yet in the shop today; regulars who were happy come a little more often
			var tries := 0
			while tries < 6:
				var cand: Dictionary = folk[rng.int_range(0, folk.size() - 1)]
				tries += 1
				if not used.has(cand["id"]): who = cand; break
			if who.is_empty(): who = folk[i % folk.size()]
			used[who["id"]] = true
		var reg: Dictionary = regulars.get(who.get("id", ""), {})
		var patience := rng.int_range(2, 4) + int(ctx.get("patience_bonus", 0))
		if int(reg.get("sat", 70)) >= 80: patience += 1
		elif int(reg.get("sat", 70)) < 50 and int(reg.get("visits", 0)) > 0: patience -= 1
		var pid: String = pids[rng.weighted(weights)]
		var q: Array = db["products"][pid].get("qty", [1, 1])
		out.append({"id": i, "who": who.get("id", "c%d" % i), "name": who.get("name", ""), "look": who.get("look", {}),
			"arrival": rng.weighted(arrival), "mult": db["sensitivity"][_sens_index(rng, sens_w, campaign and promo != "")]["mult"],
			"patience": maxi(1, patience), "wants": pid, "qty": rng.int_range(int(q[0]), int(q[1])),
			"source": "campaign" if campaign else "walk_in", "visits": int(reg.get("visits", 0)), "addon_roll": rng.int_range(0, 99)})
	out.sort_custom(func(a, b): return a["arrival"] < b["arrival"] or (a["arrival"] == b["arrival"] and a["id"] < b["id"]))
	return out

# A promotion attracts price-hunters: customers who come for it only accept the lower half of the price range.
static func _sens_index(rng: SimRng, weights: Array, price_hunter: bool) -> int:
	var i := rng.weighted(weights)
	return mini(i, 2) if price_hunter else i
