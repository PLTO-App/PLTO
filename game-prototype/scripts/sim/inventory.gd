class_name Inventory
extends RefCounted
# Raw ingredients (units, quality 0 to 100, and the money paid for them) and finished goods (fresh today, or old from yesterday).
# Goods come from baking (Business.produce) or from buying them ready (a café buys croissants and cookies). Whole numbers only.
# Unsold goods age: they sell at a discount the next day if the product keeps, otherwise they are thrown away.

var ing := {}      # id -> {units, quality, value}   value = total money paid for the units on hand
var goods := {}    # product -> {fresh, fresh_q, fresh_cost, old, old_q, old_cost, age}   cost = per piece

func reset(start_stock: Dictionary, ingredient_ids: Array, product_ids: Array, start_price := {}) -> void:
	ing = {}; goods = {}
	for id in ingredient_ids:
		var u := int(start_stock.get(id, 0))
		ing[id] = {"units": u, "quality": 70, "value": u * int(start_price.get(id, 0))}
	for p in product_ids: goods[p] = {"fresh": 0, "fresh_q": 0, "fresh_cost": 0, "old": 0, "old_q": 0, "old_cost": 0, "old_age": 0}

func units(id: String) -> int:
	return ing[id]["units"] if ing.has(id) else 0

func total_units() -> int:
	var t := 0
	for id in ing: t += ing[id]["units"]
	return t

func avg_cost(id: String) -> int:
	var e: Dictionary = ing[id]
	return e["value"] / e["units"] if e["units"] > 0 else 0

func add_ingredient(id: String, qty: int, quality: int, price: int) -> void:
	if qty <= 0: return
	var e: Dictionary = ing[id]
	var total: int = e["units"] + qty
	e["quality"] = (e["quality"] * e["units"] + quality * qty) / total
	e["value"] += qty * price; e["units"] = total

func can_use(recipe: Dictionary, pieces: int) -> bool:
	for id in recipe:
		if units(id) < recipe[id] * pieces: return false
	return true

# How many pieces the ingredients on hand allow.
func max_pieces(recipe: Dictionary) -> int:
	var n := 1 << 30
	for id in recipe: n = mini(n, units(id) / maxi(1, int(recipe[id])))
	return 0 if recipe.is_empty() else n

# Takes the ingredients for some pieces. Returns {cost (total, whole shekels), quality}.
func use(recipe: Dictionary, pieces: int) -> Dictionary:
	var total_cost := 0; var q_sum := 0; var q_units := 0
	for id in recipe:
		var used: int = recipe[id] * pieces
		var e: Dictionary = ing[id]
		var cost: int = e["value"] * used / e["units"] if e["units"] > 0 else 0
		total_cost += cost; q_sum += e["quality"] * used; q_units += used
		e["value"] -= cost; e["units"] -= used
	return {"cost": total_cost, "quality": q_sum / maxi(1, q_units)}

# Uses the ingredients and adds fresh pieces. Returns the cost per piece (rounded up) and the quality.
func bake(product: String, recipe: Dictionary, pieces: int) -> Dictionary:
	var u := use(recipe, pieces)
	var per_piece: int = (u["cost"] + pieces - 1) / pieces
	add_goods(product, pieces, u["quality"], per_piece)
	return {"cost_pp": per_piece, "quality": u["quality"]}

# Ready goods (bought from a supplier, or moved from our own bakery). cost_pp per piece.
func add_goods(product: String, pieces: int, quality: int, cost_pp: int) -> void:
	if pieces <= 0: return
	var g: Dictionary = goods[product]
	var n: int = g["fresh"] + pieces
	g["fresh_q"] = (g["fresh_q"] * g["fresh"] + quality * pieces) / n
	g["fresh_cost"] = (g["fresh_cost"] * g["fresh"] + cost_pp * pieces) / n
	g["fresh"] = n

func stock(product: String) -> int:
	if not goods.has(product): return 0
	var g: Dictionary = goods[product]; return g["fresh"] + g["old"]

func fresh(product: String) -> int:
	return goods[product]["fresh"] if goods.has(product) else 0

func old(product: String) -> int:
	return goods[product]["old"] if goods.has(product) else 0

# What would be sold next: fresh first, then old. {} when nothing is left.
func peek(product: String) -> Dictionary:
	var g: Dictionary = goods[product]
	if g["fresh"] > 0: return {"kind": "fresh", "quality": g["fresh_q"], "cost": g["fresh_cost"]}
	if g["old"] > 0: return {"kind": "old", "quality": g["old_q"], "cost": g["old_cost"]}
	return {}

func take(product: String) -> Dictionary:
	var p := peek(product)
	if p.is_empty(): return p
	goods[product][p["kind"]] -= 1
	return p

# Takes fresh pieces only (for deliveries to other businesses). Returns {n, cost (total), quality}.
func take_fresh(product: String, n: int) -> Dictionary:
	var g: Dictionary = goods[product]; var k := mini(n, int(g["fresh"]))
	g["fresh"] -= k
	return {"n": k, "cost": k * int(g["fresh_cost"]), "quality": g["fresh_q"]}

# End of day: discard what is too old, age the rest. shelf_days[pid] = days a product keeps (1 = today only).
# Returns [{product, pieces, cost, old}] for the waste report.
func close_day(shelf_days: Dictionary) -> Array:
	var waste: Array = []
	for pid in goods:
		var g: Dictionary = goods[pid]
		var keep: int = int(shelf_days.get(pid, 1))
		if g["old"] > 0:
			g["old_age"] += 1
			if g["old_age"] >= keep:
				waste.append({"product": pid, "pieces": g["old"], "cost": g["old"] * g["old_cost"], "old": true})
				g["old"] = 0; g["old_age"] = 0
		if g["fresh"] > 0:
			if keep >= 2:
				var n: int = g["old"] + g["fresh"]
				g["old_q"] = (g["old_q"] * g["old"] + g["fresh_q"] * g["fresh"]) / n
				g["old_cost"] = (g["old_cost"] * g["old"] + g["fresh_cost"] * g["fresh"]) / n
				if g["old"] == 0: g["old_age"] = 1
				g["old"] = n
			else:
				waste.append({"product": pid, "pieces": g["fresh"], "cost": g["fresh"] * g["fresh_cost"], "old": false})
			g["fresh"] = 0
	return waste

func goods_value() -> int:
	var t := 0
	for pid in goods: t += goods[pid]["fresh"] * goods[pid]["fresh_cost"] + goods[pid]["old"] * goods[pid]["old_cost"]
	return t

func ingredients_value() -> int:
	var t := 0
	for id in ing: t += ing[id]["value"]
	return t

func to_dict() -> Dictionary:
	return {"ing": ing.duplicate(true), "goods": goods.duplicate(true)}

func from_dict(d: Dictionary, ingredient_ids: Array, product_ids: Array) -> void:
	reset({}, ingredient_ids, product_ids)
	for id in ingredient_ids:
		var e: Dictionary = d.get("ing", {}).get(id, {})
		if not e.is_empty(): ing[id] = {"units": maxi(0, int(e["units"])), "quality": clampi(int(e["quality"]), 0, 100), "value": maxi(0, int(e["value"]))}
	for p in product_ids:
		var g: Dictionary = d.get("goods", {}).get(p, {})
		for k in g:
			if goods[p].has(k): goods[p][k] = maxi(0, int(g[k]))
