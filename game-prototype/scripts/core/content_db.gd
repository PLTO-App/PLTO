class_name ContentDb
extends RefCounted
# Loads game content from JSON (progression curve, business definitions) and checks it.
# JSON numbers arrive as floats in Godot, so every money or experience value is converted to int and rejected if it was fractional.

var levels: Array[int] = []
var first_sale_xp := 0
var start_cash := 0
var start_reputation := 50
var rep_min := 0
var rep_max := 100
var businesses := {}      # id -> Dictionary (products, customers, ...)
var errors: Array[String] = []

static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return null
	return JSON.parse_string(f.get_as_text())

func _int(v: Variant, where: String) -> int:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		errors.append("%s: not a number" % where); return 0
	if typeof(v) == TYPE_FLOAT and not is_equal_approx(v, roundf(v)):
		errors.append("%s: must be a whole number" % where)
	return int(v)

func load_all() -> void:
	errors.clear()
	var p = read_json("res://content/common/progression.json")
	if typeof(p) != TYPE_DICTIONARY:
		errors.append("progression.json missing or invalid"); return
	levels.clear()
	for i in (p["levels"] as Array).size(): levels.append(_int(p["levels"][i], "levels[%d]" % i))
	for i in range(1, levels.size()):
		if levels[i] <= levels[i - 1]: errors.append("levels must increase (index %d)" % i)
	first_sale_xp = _int(p["bonuses"]["first_sale_xp"], "bonuses.first_sale_xp")
	start_cash = _int(p["start"]["cash"], "start.cash"); start_reputation = _int(p["start"]["reputation"], "start.reputation")
	rep_min = _int(p["reputation_min"], "reputation_min"); rep_max = _int(p["reputation_max"], "reputation_max")
	businesses.clear()
	var dir := DirAccess.open("res://content/businesses")
	if dir == null: errors.append("content/businesses missing"); return
	for fn in dir.get_files():
		if not fn.ends_with(".json"): continue
		var b = read_json("res://content/businesses/" + fn)
		if typeof(b) != TYPE_DICTIONARY: errors.append(fn + ": invalid"); continue
		_normalize_business(b, fn); businesses[b.get("id", fn)] = b

func _normalize_business(b: Dictionary, fn: String) -> void:
	for key in ["id", "name", "products", "customers", "first_order", "order_cycle", "reputation_per_sale"]:
		if not b.has(key): errors.append("%s: missing %s" % [fn, key])
	if not b.has("products"): return
	for pid in b["products"]:
		var pr: Dictionary = b["products"][pid]
		for k in ["price", "cost", "xp"]: pr[k] = _int(pr.get(k), "%s.%s.%s" % [fn, pid, k])
		if pr["cost"] > pr["price"]: errors.append("%s.%s: cost above price" % [fn, pid])
	b["reputation_per_sale"] = _int(b.get("reputation_per_sale"), fn + ".reputation_per_sale")
	for pid in b.get("order_cycle", []):
		if not b["products"].has(pid): errors.append("%s: order_cycle has unknown product %s" % [fn, pid])
	var fo: Dictionary = b.get("first_order", {})
	if not b["products"].has(fo.get("product", "")): errors.append(fn + ": first_order product unknown")
	var ids := []
	for c in b.get("customers", []): ids.append(c.get("id"))
	if not ids.has(fo.get("customer", "")): errors.append(fn + ": first_order customer unknown")

# Level reached with a given total experience (1-based, capped at the table's end).
func level_for_xp(xp: int) -> int:
	var lv := 1
	for i in range(1, levels.size()):
		if xp >= levels[i]: lv = i + 1
	return lv
