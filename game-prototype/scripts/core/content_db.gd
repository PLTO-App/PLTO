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

# Turns every whole-number float into an int (JSON numbers arrive as floats) and reports any real fraction.
func _intify(v: Variant, path: String) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			if not is_equal_approx(v, roundf(v)): errors.append("%s: must be a whole number" % path)
			return int(roundf(v))
		TYPE_DICTIONARY:
			for k in (v as Dictionary).keys(): v[k] = _intify(v[k], "%s.%s" % [path, k])
			return v
		TYPE_ARRAY:
			for i in (v as Array).size(): v[i] = _intify(v[i], "%s[%d]" % [path, i])
			return v
	return v

func _normalize_business(b: Dictionary, fn: String) -> void:
	_intify(b, fn)
	for key in ["id", "name", "start", "slots", "base_customers", "oven_capacity", "fixed_costs", "arrival_weights", "weekday_factor", "weekday_names", "sensitivity",
			"ingredients", "suppliers", "products", "marketing", "upgrades", "xp_rules", "customers"]:
		if not b.has(key): errors.append("%s: missing %s" % [fn, key])
	if not (b.has("products") and b.has("ingredients") and b.has("suppliers")): return
	if b["arrival_weights"].size() != b["slots"]: errors.append(fn + ": arrival_weights must have one weight per slot")
	if b["weekday_factor"].size() != 7 or b["weekday_names"].size() != 7: errors.append(fn + ": weekday lists need 7 entries")
	for sid in b["suppliers"]:
		for iid in b["ingredients"]:
			if not b["suppliers"][sid]["prices"].has(iid): errors.append("%s.%s: no price for %s" % [fn, sid, iid])
	for pid in b["products"]:
		var pr: Dictionary = b["products"][pid]
		for k in ["price", "xp", "pref", "oven", "shelf_days", "old_price_pct", "recipe", "model", "icon"]:
			if not pr.has(k): errors.append("%s.%s: missing %s" % [fn, pid, k])
		for iid in pr.get("recipe", {}):
			if not b["ingredients"].has(iid): errors.append("%s.%s: unknown ingredient %s" % [fn, pid, iid])
		# cheapest possible unit cost must stay below the price, so the business can make money at all
		var unit := 0
		for iid in pr.get("recipe", {}): unit += pr["recipe"][iid] * (b["suppliers"]["wholesale"]["prices"][iid] if b["suppliers"].has("wholesale") else 0)
		if unit >= pr.get("price", 0): errors.append("%s.%s: ingredient cost %d is not below the price" % [fn, pid, unit])
	if not b["marketing"].has("none"): errors.append(fn + ": marketing needs a 'none' option")

# Level reached with a given total experience (1-based, capped at the table's end).
func level_for_xp(xp: int) -> int:
	var lv := 1
	for i in range(1, levels.size()):
		if xp >= levels[i]: lv = i + 1
	return lv
