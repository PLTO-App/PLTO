class_name Inventory
extends RefCounted
# Raw ingredients (units, quality 0 to 100, and what they cost) and finished goods (fresh today, or old from yesterday).
# Whole numbers only. Unsold goods age: they sell at a discount the next day if the product keeps, otherwise they are thrown away.

var ing := {}      # id -> {units, quality, value}   value = total money paid for the units on hand
var goods := {}    # product -> {fresh, fresh_q, fresh_cost, old, old_q, old_cost}   cost = per piece

func reset(start_stock: Dictionary, ingredient_ids: Array, product_ids: Array) -> void:
	ing = {}; goods = {}
	for id in ingredient_ids: ing[id] = {"units": int(start_stock.get(id, 0)), "quality": 70, "value": 0}
	for p in product_ids: goods[p] = {"fresh": 0, "fresh_q": 0, "fresh_cost": 0, "old": 0, "old_q": 0, "old_cost": 0}

func units(id: String) -> int:
	return ing[id]["units"]

func avg_cost(id: String) -> int:
	var e: Dictionary = ing[id]
	return e["value"] / e["units"] if e["units"] > 0 else 0

func add_ingredient(id: String, qty: int, quality: int, price: int) -> void:
	if qty <= 0: return
	var e: Dictionary = ing[id]
	var total: int = e["units"] + qty
	e["quality"] = (e["quality"] * e["units"] + quality * qty) / total
	e["value"] += qty * price; e["units"] = total

func can_bake(recipe: Dictionary, pieces: int) -> bool:
	for id in recipe:
		if ing[id]["units"] < recipe[id] * pieces: return false
	return true

# Uses the ingredients and adds fresh pieces. Returns the cost per piece (whole shekels, rounded).
func bake(product: String, recipe: Dictionary, pieces: int) -> Dictionary:
	var total_cost := 0; var q_sum := 0; var q_units := 0
	for id in recipe:
		var used: int = recipe[id] * pieces
		var e: Dictionary = ing[id]
		var cost: int = e["value"] * used / e["units"] if e["units"] > 0 else 0
		total_cost += cost; q_sum += e["quality"] * used; q_units += used
		e["value"] -= cost; e["units"] -= used
	var quality: int = q_sum / maxi(1, q_units); var per_piece: int = (total_cost + pieces - 1) / pieces
	var g: Dictionary = goods[product]
	var n: int = g["fresh"] + pieces
	g["fresh_q"] = (g["fresh_q"] * g["fresh"] + quality * pieces) / n
	g["fresh_cost"] = (g["fresh_cost"] * g["fresh"] + per_piece * pieces) / n
	g["fresh"] = n
	return {"cost_pp": per_piece, "quality": quality}

func stock(product: String) -> int:
	var g: Dictionary = goods[product]; return g["fresh"] + g["old"]

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

# End of day: discard what is too old, age the rest. Returns [{product, pieces, cost, old}] for the waste report.
func close_day(shelf_days: Dictionary) -> Array:
	var waste: Array = []
	for pid in goods:
		var g: Dictionary = goods[pid]
		if g["old"] > 0: waste.append({"product": pid, "pieces": g["old"], "cost": g["old"] * g["old_cost"], "old": true})
		g["old"] = 0
		if g["fresh"] > 0:
			if int(shelf_days[pid]) >= 2:
				g["old"] = g["fresh"]; g["old_q"] = g["fresh_q"]; g["old_cost"] = g["fresh_cost"]
			else:
				waste.append({"product": pid, "pieces": g["fresh"], "cost": g["fresh"] * g["fresh_cost"], "old": false})
			g["fresh"] = 0
	return waste

func to_dict() -> Dictionary:
	return {"ing": ing.duplicate(true), "goods": goods.duplicate(true)}

func from_dict(d: Dictionary, ingredient_ids: Array, product_ids: Array) -> void:
	reset({}, ingredient_ids, product_ids)
	for id in ingredient_ids:
		var e: Dictionary = d.get("ing", {}).get(id, {})
		if not e.is_empty(): ing[id] = {"units": maxi(0, int(e["units"])), "quality": clampi(int(e["quality"]), 0, 100), "value": maxi(0, int(e["value"]))}
	for p in product_ids:
		var g: Dictionary = d.get("goods", {}).get(p, {})
		if not g.is_empty():
			for k in g: goods[p][k] = maxi(0, int(g[k]))
