extends SceneTree
# Development only: saving and loading must not change how the game goes. Two identical companies play the same seasons;
# one of them is written to JSON and read back (like a closed and reopened app) at every morning and every evening.
# After each day both must be identical, and a game saved mid-week must settle the week the same way.
# godot --headless --path game-prototype --script dev/test_saveload.gd
var fails := 0
var content: ContentDb

func check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok: fails += 1

# The same numbers, whether JSON turned them into floats or not.
var diffs: Array = []
func same(a, b, path := "") -> String:
	diffs = []; _same(a, b, path)
	return "; ".join(diffs.slice(0, 12))

func _same(a, b, path: String) -> void:
	if diffs.size() >= 12: return
	var r := _same1(a, b, path)
	if r != "": diffs.append(r)

func _same1(a, b, path := "") -> String:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return "" if is_equal_approx(float(a), float(b)) else "%s: %s != %s" % [path, str(a), str(b)]
	if typeof(a) != typeof(b): return "%s: type %d (%s) != %d (%s)" % [path, typeof(a), str(a).substr(0, 40), typeof(b), str(b).substr(0, 40)]
	if a is Dictionary:
		for k in a:
			if not b.has(k): return "%s/%s: missing after reload" % [path, str(k)]
			_same(a[k], b[k], path + "/" + str(k))
		for k in b:
			if not a.has(k): return "%s/%s: appeared after reload" % [path, str(k)]
		return ""
	if a is Array:
		if a.size() != b.size(): return "%s: size %d != %d" % [path, a.size(), b.size()]
		for i in a.size():
			_same(a[i], b[i], path + "[%d]" % i)
		return ""
	return "" if a == b else "%s: %s != %s" % [path, str(a), str(b)]

func reload(co: Company) -> Company:
	var text := JSON.stringify(co.snapshot)
	var d = JSON.parse_string(text)
	var c := Company.new(content)
	c.from_dict(d)
	return c

func _init() -> void:
	Loc.setup("he")
	content = ContentDb.new(); content.load_all()
	for seed_value in [11, 12, 13]:
		_season(seed_value, {"order_ahead": true, "contract": true, "accountant": true, "cafe": true, "upgrades": true, "loan": true}, 36)
	_season(31, {"order_ahead": true, "contract": true, "accountant": true, "cafe": true, "upgrades": true, "loan": true, "market": true}, 60)
	_season(21, {"order_ahead": false}, 20)
	_season(22, {"idle": true}, 14)
	_test_reset()
	print("RESULT failures=%d" % fails)
	quit(1 if fails > 0 else 0)

func decide(co: Company, opts: Dictionary) -> void:
	if opts.get("accountant", false) and not co.services.has("accountant") and co.level() >= 2: co.subscribe("accountant", true)
	if opts.get("cafe", false) and not co.owns("cafe"):
		if opts.get("loan", false) and co.level() >= 3 and not co.loan_open("large") and co.profile.cash < 6500: co.take_loan("large")
		if co.can_open("cafe").is_empty() and co.profile.cash >= int(co.world["openable"]["cafe"]["cost"]) + (1200 if not opts.get("loan", false) else 0): co.open_business("cafe")
	if co.owns("cafe") and co.staff.is_empty() and co.level() >= 2: co.hire("yossi", "cafe")
	if opts.get("market", false):
		if not co.owns("market") and co.level() >= 6 and co.can_open("market").is_empty() and co.profile.cash >= int(co.world["openable"]["market"]["cost"]) + 1500: co.open_business("market")
		if co.owns("market") and co.staff_at("market").is_empty() and co.level() >= 2: co.hire("maya", "market")
	if opts.get("upgrades", false):
		for bid in co.units:
			for uid in co.units[bid].db["upgrades"]:
				var u: Dictionary = co.units[bid].db["upgrades"][uid]
				if not co.units[bid].upgrades.has(uid) and co.level() >= int(u["unlock_level"]) and co.profile.cash > int(u["cost"]) + 4500: co.buy_upgrade(bid, uid)

func play_day(co: Company, opts: Dictionary, reload_morning: bool) -> Company:
	var rep := co.start_morning()
	if reload_morning:
		co = reload(co)
		check_events_survive(co, rep)
	for ev in co.pending_events.duplicate(): co.resolve_event(ev, SimPolicies.choose(co, ev, opts))
	decide(co, opts)
	var plans := {}
	for bid in co.units:
		if co.unit_ready(bid): plans[bid] = SimPolicies.plan_for(co, bid, opts)
	var errs := co.commit_day(plans, "bakery")
	if not errs.is_empty():
		for bid in plans: plans[bid] = co.units[bid].empty_plan()
		co.commit_day(plans, "bakery")
	if opts.get("order_ahead", false) and not opts.get("idle", false):
		for bid in co.units: SimPolicies.order_ahead(co, bid)
	co.close_day()
	return co

func check_events_survive(co: Company, rep: Dictionary) -> void:
	if co.pending_events.size() != rep["events"].size(): check("pending events survive a reload (day %d)" % co.day, false, "%d vs %d" % [co.pending_events.size(), rep["events"].size()])

func _season(seed_value: int, opts: Dictionary, days: int) -> void:
	var a := Company.new(content); a.new_game(seed_value)
	var b := Company.new(content); b.new_game(seed_value)
	var bad := ""
	var played := 0
	while a.day <= days and bad == "":
		a = play_day(a, opts, false)
		b = play_day(b, opts, true)
		b = reload(b)                       # the evening save
		played += 1
		var da: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
		if int(da["morning_day"]) != int(da["day"]):       # the morning's news is not kept past its day
			da["last_report"] = {}; da["pending_events"] = []; da["inspection_today"] = ""
		var r := same(da, JSON.parse_string(JSON.stringify(b.to_dict())), "day%d" % a.day)
		if r != "": bad = r
		if a.ledger.balance() != a.profile.cash or b.ledger.balance() != b.profile.cash: bad = "ledger != cash on day %d" % a.day
	check("seed %d (%d days): reloading every morning and evening changes nothing" % [seed_value, played], bad == "", bad)
	check("seed %d: the money is the same at the end" % seed_value, a.profile.cash == b.profile.cash, "%d vs %d" % [a.profile.cash, b.profile.cash])
	# numbers read back from a save are whole numbers, so they print and compare like the live ones
	var kinds := {}
	_floats(b.to_dict(), "", kinds)
	print("INFO seed %d: whole numbers that came back as floats (by field): %s" % [seed_value, str(kinds.keys())])

func _floats(v, path: String, kinds: Dictionary) -> void:
	if typeof(v) == TYPE_FLOAT and v == floorf(v) and absf(v) < 1e12:
		var parts := path.split("/")
		var key := "/".join(parts.slice(0, mini(parts.size(), 4)))
		for d in "0123456789": key = key.replace(d, "")
		kinds[key] = true
	elif v is Dictionary:
		for k in v: _floats(v[k], path + "/" + str(k), kinds)
	elif v is Array:
		for i in v.size(): _floats(v[i], path + "/*", kinds)

# Starting over (Settings, reset) on the first morning must run a fresh morning, not skip it because the old one "already ran".
func _test_reset() -> void:
	var co := Company.new(content); co.new_game(5)
	co.start_morning()
	check("the first morning ran", co.morning_day == 1)
	co.new_game(6)
	check("a new game has not run its morning yet", co.morning_day == 0 and co.pending_events.is_empty() and co.last_report.is_empty())
