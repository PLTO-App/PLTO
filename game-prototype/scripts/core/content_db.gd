class_name ContentDb
extends RefCounted
# Loads the game content from JSON (progression, the town, the businesses, events, goals) and checks it.
# JSON numbers arrive as floats in Godot, so every number is turned into an int and rejected if it was fractional:
# money, experience and percentages in this game are whole numbers.

var levels: Array[int] = []
var start_cash := 0
var start_reputation := 50
var rep_min := 0
var rep_max := 100
var world := {}
var businesses := {}      # id -> Dictionary
var events: Array = []
var goals := {}
var tracks := {}          # id -> Dictionary (where the company can start)
var track_order: Array = []
var setup_packs := {}      # pack id -> Array of tasks (content/setup/*.json)
var _format_cache := {}   # "business/format" -> the business as that format
var errors: Array[String] = []

static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return null
	return JSON.parse_string(f.get_as_text())

func load_all() -> void:
	errors.clear()
	var p = read_json("res://content/common/progression.json")
	if typeof(p) != TYPE_DICTIONARY:
		errors.append("progression.json missing or invalid"); return
	_intify(p, "progression")
	levels.clear()
	for v in p["levels"]: levels.append(int(v))
	for i in range(1, levels.size()):
		if levels[i] <= levels[i - 1]: errors.append("levels must increase (index %d)" % i)
	start_cash = int(p["start"]["cash"]); start_reputation = int(p["start"]["reputation"])
	rep_min = int(p["reputation_min"]); rep_max = int(p["reputation_max"])
	var w = read_json("res://content/world.json")
	if typeof(w) != TYPE_DICTIONARY: errors.append("world.json missing or invalid"); return
	world = _intify(w, "world")
	businesses.clear()
	var dir := DirAccess.open("res://content/businesses")
	if dir == null: errors.append("content/businesses missing"); return
	for fn in dir.get_files():
		if not fn.ends_with(".json"): continue
		var b = read_json("res://content/businesses/" + fn)
		if typeof(b) != TYPE_DICTIONARY: errors.append(fn + ": invalid"); continue
		_intify(b, fn); _check_business(b, fn); businesses[b.get("id", fn)] = b
	var ev = read_json("res://content/events.json")
	events = _intify(ev, "events")["events"] if typeof(ev) == TYPE_DICTIONARY else []
	var g = read_json("res://content/goals.json")
	goals = _intify(g, "goals") if typeof(g) == TYPE_DICTIONARY else {}
	var tr = read_json("res://content/tracks.json")
	tracks = {}; track_order = []; _format_cache = {}
	if typeof(tr) == TYPE_DICTIONARY:
		_intify(tr, "tracks"); tracks = tr.get("tracks", {}); track_order = tr.get("order", [])
	else: errors.append("tracks.json missing or invalid")
	setup_packs = {}
	var sd := DirAccess.open("res://content/setup")
	if sd != null:
		for fn in sd.get_files():
			if not fn.ends_with(".json"): continue
			var sp = read_json("res://content/setup/" + fn)
			if typeof(sp) != TYPE_DICTIONARY or not sp.has("id") or not sp.has("tasks"): errors.append("setup/" + fn + ": invalid"); continue
			_intify(sp, fn); setup_packs[sp["id"]] = sp["tasks"]
	_check_world()
	_check_tracks()
	_check_setup()

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

func _check_business(b: Dictionary, fn: String) -> void:
	for key in ["id", "name", "kind", "start", "slots", "base_customers", "capacity", "weekly_costs", "arrival_weights", "weekday_factor", "sensitivity",
			"ingredients", "products", "marketing", "upgrades", "xp_rules", "supplier_ids"]:
		if not b.has(key): errors.append("%s: missing %s" % [fn, key])
	if not (b.has("products") and b.has("ingredients")): return
	if b["arrival_weights"].size() < b["slots"]: errors.append(fn + ": arrival_weights needs one weight per slot")
	if b["weekday_factor"].size() != 7: errors.append(fn + ": weekday_factor needs 7 entries")
	for pid in b["products"]:
		var pr: Dictionary = b["products"][pid]
		for k in ["name", "price", "xp", "pref", "cap", "icon", "qty"]:
			if not pr.has(k): errors.append("%s.%s: missing %s" % [fn, pid, k])
		for iid in pr.get("recipe", {}):
			if not b["ingredients"].has(iid): errors.append("%s.%s: unknown ingredient %s" % [fn, pid, iid])
		if pr.has("resale") and not b.get("goods_inputs", {}).has(pr["resale"]): errors.append("%s.%s: resale input %s not in goods_inputs" % [fn, pid, pr["resale"]])
		if pr.has("weekday_pref") and pr["weekday_pref"].size() != 7: errors.append("%s.%s: weekday_pref needs 7 entries" % [fn, pid])
	if not b["marketing"].has("none"): errors.append(fn + ": marketing needs a 'none' option")

func _check_world() -> void:
	for key in ["start", "week", "suppliers", "contracts", "services", "bank", "staff_pool", "weather", "upkeep", "inspection", "townsfolk", "people"]:
		if not world.has(key): errors.append("world: missing %s" % key)
	if errors.size() > 0: return
	# every business can buy all it needs from every supplier it lists, and can make money at the cheapest prices
	for bid in businesses:
		var b: Dictionary = businesses[bid]
		var items: Array = b["ingredients"].keys() + b.get("goods_inputs", {}).keys()
		for sid in b["supplier_ids"]:
			if not world["suppliers"].has(sid): errors.append("%s: unknown supplier %s" % [bid, sid]); continue
			for it in items:
				if not world["suppliers"][sid]["prices"].has(it): errors.append("%s: supplier %s has no price for %s" % [bid, sid, it])
		var cheap: Dictionary = world["suppliers"]["wholesale"]["prices"]
		for pid in b["products"]:
			var pr: Dictionary = b["products"][pid]; var unit := 0
			if pr.has("resale"): unit = int(cheap.get(pr["resale"], 0))
			for iid in pr.get("recipe", {}): unit += int(pr["recipe"][iid]) * int(cheap.get(iid, 0))
			if unit >= int(pr["price"]): errors.append("%s.%s: cost %d is not below the price" % [bid, pid, unit])
	for bid in world["start"]["businesses"]:
		if not businesses.has(bid): errors.append("world.start: unknown business %s" % bid)
	for cid in world["contracts"]:
		var c: Dictionary = world["contracts"][cid]
		for pid in c["items"]:
			if not businesses[c["biz"]]["products"].has(pid): errors.append("contract %s: unknown product %s" % [cid, pid])
	for e in events:
		if not e.has("id") or not e.has("title") or not e.has("body"): errors.append("event missing id/title/body: %s" % str(e).left(60))

# A business as one of its formats. "" and "regular" are the file itself; another format overrides top-level keys (a smaller space:
# fewer customers, a smaller oven, a lower rent) and is the same business with the same id.
func business_db(bid: String, fmt := "") -> Dictionary:
	var base: Dictionary = businesses[bid]
	var f: Dictionary = base.get("formats", {}).get(fmt, {})
	if fmt == "" or fmt == "regular" or not f.has("set"): return base
	var key := bid + "/" + fmt
	if not _format_cache.has(key):
		var d: Dictionary = base.duplicate(true)
		for k in f["set"]: d[k] = f["set"][k]
		_format_cache[key] = d
	return _format_cache[key]

# The setup tasks of a business: its packs in order. A business with no packs has none.
func setup_tasks_for(bid: String) -> Array:
	var out: Array = []
	if not businesses.has(bid): return out
	for pack in businesses[bid].get("setup_packs", []): out.append_array(setup_packs.get(pack, []))
	return out

func _check_setup() -> void:
	for bid in businesses:
		var ids := {}
		var tasks := setup_tasks_for(bid)
		for pack in businesses[bid].get("setup_packs", []):
			if not setup_packs.has(pack): errors.append("%s: unknown setup pack %s" % [bid, pack])
		for t in tasks:
			for k in ["id", "kind", "name", "desc", "requires", "options"]:
				if not t.has(k): errors.append("setup task %s: missing %s" % [t.get("id", "?"), k])
			if ids.has(t.get("id", "")): errors.append("%s: duplicate setup task %s" % [bid, t["id"]])
			ids[t.get("id", "")] = true
			if t.get("kind", "") not in ["legal", "business"]: errors.append("setup task %s: kind must be legal or business" % t.get("id", "?"))
			if t.get("kind", "") == "legal" and not t.has("real"): errors.append("setup task %s: a legal task must say whether it is real" % t.get("id", "?"))
			var free := false
			for o in t.get("options", []):
				for k in ["id", "label", "desc", "cost", "fail_pct"]:
					if not o.has(k): errors.append("setup task %s option: missing %s" % [t.get("id", "?"), k])
				if not (o.has("days") or o.has("days_delta")): errors.append("setup task %s option: missing days" % t.get("id", "?"))
				if int(o.get("cost", 1)) == 0: free = true
			# a player with no cash must never be stuck: every required task has a free option
			if bool(t.get("required", false)) and not free: errors.append("setup task %s: a required task needs a free option" % t.get("id", "?"))
		for t in tasks:
			for r in t.get("requires", []):
				if not ids.has(r): errors.append("%s: setup task %s requires unknown %s" % [bid, t.get("id", "?"), r])

func _check_tracks() -> void:
	for tid in tracks:
		var t: Dictionary = tracks[tid]
		for key in ["name", "desc"]:
			if not t.has(key): errors.append("track %s: missing %s" % [tid, key])
		for bid in t.get("choose", []):
			if not businesses.has(bid): errors.append("track %s: unknown business %s" % [tid, bid]); continue
			var fm: Dictionary = businesses[bid].get("formats", {})
			if fm.is_empty(): errors.append("track %s: %s has no formats" % [tid, bid])
			for fid in fm:
				for k in ["name", "setup_cost", "setup_days"]:
					if not fm[fid].has(k): errors.append("%s format %s: missing %s" % [bid, fid, k])
				for k in fm[fid].get("set", {}):
					if not businesses[bid].has(k): errors.append("%s format %s: sets unknown key %s" % [bid, fid, k])
	for tid in track_order:
		if not tracks.has(tid): errors.append("tracks order: unknown track %s" % tid)

# Level reached with a given total experience (1-based, capped at the table's end).
func level_for_xp(xp: int) -> int:
	var lv := 1
	for i in range(1, levels.size()):
		if xp >= levels[i]: lv = i + 1
	return lv
