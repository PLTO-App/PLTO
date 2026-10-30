class_name SetupBoard
extends RefCounted
# The setup file of a business that is being set up (the owner track): the permits, the work and the choices before the doors open.
# Which tasks a business has comes from its setup packs (content/setup/*.json), so a bakery has a health inspection and fire safety
# and an office would not. Legal tasks must be done before opening; business tasks are choices (some are needed, some are not).
# Each task is started with one option (cost, days, a chance to fail); on its due day it is done or returns to the board.
# State lives in Company.setup, so it is saved. No screen here: the board is played by the screens and by the balance bots.
#
# A task with "bids" (the contractor) has quotes made when the setup begins: a few professionals with a price, days and a reliability
# the player cannot see until paying for a reference check. On the due day the work may go as quoted, run late, cost more, or leave a defect.
#
# Company.setup = {"biz", "tasks": {id: {"state": todo|active|done, "opt", "start", "due", "tries", "fails", "price", "rel", "defect", "resolved"}},
#                  "launch": {kind, value, days}, "bids": {task id: [{id, who, price, days, rel, checked}]}, "reserve": the budget held back for the contractor}

static func defs(co: Company) -> Array:
	return co.content.setup_tasks_for(co.setup.get("biz", ""))

static func def_of(co: Company, id: String) -> Dictionary:
	for t in defs(co): if t["id"] == id: return t
	return {}

static func init(co: Company, bid: String) -> void:
	co.setup = {"biz": bid, "tasks": {}, "launch": {}, "bids": {}, "reserve": reserve(co.content, bid, co.units[bid].format)}
	for t in co.content.setup_tasks_for(bid):
		co.setup["tasks"][t["id"]] = {"state": "todo", "opt": "", "start": 0, "due": 0, "tries": 0, "fails": 0, "price": 0, "rel": 0, "defect": false, "resolved": false}
		if t.has("bids"): co.setup["bids"][t["id"]] = _make_bids(co, t)

# The part of the setup cost that is held back as the contractor's budget: it is paid when a contractor is chosen, at the price quoted.
static func reserve(content: ContentDb, bid: String, fmt: String) -> int:
	for t in content.setup_tasks_for(bid):
		if t.has("bids"): return int(t["bids"]["budget"].get(fmt if fmt != "" else "regular", 0))
	return 0

static func _fmt(co: Company) -> String:
	var f: String = co.units[co.setup["biz"]].format
	return f if f != "" else "regular"

# Quotes from three professionals: cheap and not very reliable, middling, dear and reliable. Same seed, same quotes.
static func _make_bids(co: Company, t: Dictionary) -> Array:
	var B: Dictionary = t["bids"]; var f := _fmt(co)
	var r := co.rng("bids_" + t["id"])
	var pool: Array = B["pool"].duplicate(); var out: Array = []
	var budget := int(B["budget"][f]); var base_days := int(B["days"][f])
	for tier in B["tiers"]:
		var who: String = pool.pop_at(r.int_range(0, pool.size() - 1))
		var price := budget * (int(tier["price_pct"]) + r.int_range(-8, 8)) / 100 / 10 * 10
		var days := maxi(2, base_days + int(tier["days_delta"]) + r.int_range(0, 1))
		out.append({"id": tier["id"], "who": who, "price": price, "days": days, "rel": r.int_range(int(tier["rel"][0]), int(tier["rel"][1])), "checked": false})
	return out

static func st(co: Company, id: String) -> Dictionary: return co.setup["tasks"].get(id, {})

static func is_done(co: Company, id: String) -> bool: return st(co, id).get("state", "") == "done"

# The options of a task as the player sees them now: the fixed ones, and the quotes of the professionals when the task has bids.
static func options_of(co: Company, t: Dictionary) -> Array:
	var out: Array = []
	if t.has("bids"):
		for b in co.setup["bids"].get(t["id"], []):
			var known: bool = bool(b["checked"])
			out.append({"id": b["id"], "label": t["bids"]["bid_label"], "p": {"who_k": b["who"]}, "desc": t["bids"]["bid_desc"], "cost": int(b["price"]), "days": int(b["days"]),
				"fail_pct": 0, "rel": int(b["rel"]), "bid": true, "checked": known, "risk_k": risk_label(100 - int(b["rel"])) if known else "setup.risk_unknown"})
	for o in t["options"]:
		var c: Dictionary = o.duplicate()
		if t.has("bids"):
			c["days"] = int(t["bids"]["days"][_fmt(co)]) + int(o.get("days_delta", 0))
			c["risk_k"] = risk_label(100 - int(o.get("rel", 100)))
		out.append(c)
	return out

static func option(co: Company, t: Dictionary, oid: String) -> Dictionary:
	for o in options_of(co, t): if o["id"] == oid: return o
	return {}

# A reference check: pay to learn how reliable one professional is.
static func check_bid(co: Company, id: String, oid: String) -> Dictionary:
	var t := def_of(co, id)
	if t.is_empty() or not t.has("bids") or status(co, t) not in ["ready", "retry"]: return Loc.m("err.setup_unknown")
	var cost := int(t["bids"]["check_cost"])
	if cost > co.profile.cash: return Loc.m("err.no_cash", {"amount_m": cost - co.profile.cash})
	for b in co.setup["bids"][id]:
		if b["id"] == oid and not b["checked"]:
			b["checked"] = true; co.book("event", -cost, co.setup["biz"], "setup_check"); co._snap(); return {}
	return Loc.m("err.setup_unknown")

# Days for an option in the size of the business (a regular shop takes longer to fit out than a small one).
static func option_days(co: Company, o: Dictionary) -> int:
	var fmt: String = co.units[co.setup["biz"]].format
	return int(o.get("days_by_format", {}).get(fmt if fmt != "" else "regular", o["days"]))   # bids and the fit-out options already hold their days

# "done" | "active" | "ready" | "retry" | "blocked"
static func status(co: Company, t: Dictionary) -> String:
	var s := st(co, t["id"])
	if s["state"] == "done": return "done"
	if s["state"] == "active": return "active"
	for r in t["requires"]: if not is_done(co, r): return "blocked"
	return "retry" if int(s["fails"]) > 0 else "ready"

static func blockers(co: Company, t: Dictionary) -> Array:
	return t["requires"].filter(func(r): return not is_done(co, r))

# The chance, in percent, that the task fails when it comes due, with the choices already made.
static func fail_pct(co: Company, t: Dictionary, o: Dictionary) -> int:
	var pct := int(o.get("fail_pct", 0))
	if pct <= 0: return 0
	for m in o.get("fail_mods", []):
		if m.has("done") and is_done(co, m["done"]): pct += int(m["delta"])
		if m.has("opt"):
			var parts: PackedStringArray = str(m["opt"]).split(":")
			if st(co, parts[0]).get("opt", "") == parts[1] and is_done(co, parts[0]): pct += int(m["delta"])
		if m.has("per_fail"): pct += int(m["per_fail"]) * int(st(co, t["id"])["fails"])
		if m.has("defect") and bool(st(co, m["defect"]).get("defect", false)): pct += int(m["delta"])
	return clampi(pct, 0, 95)

# How risky the player sees it: a feeling, not a number.
static func risk_label(pct: int) -> String:
	if pct <= 0: return "setup.risk_none"
	if pct <= 12: return "setup.risk_low"
	if pct <= 30: return "setup.risk_mid"
	return "setup.risk_high"

static func start(co: Company, id: String, oid: String) -> Dictionary:
	var t := def_of(co, id)
	if t.is_empty() or status(co, t) not in ["ready", "retry"]: return Loc.m("err.setup_unknown")
	var o := option(co, t, oid)
	if o.is_empty(): return Loc.m("err.setup_unknown")
	var cost := int(o.get("cost", 0))
	if cost > 0 and cost > co.profile.cash: return Loc.m("err.no_cash", {"amount_m": cost - co.profile.cash})   # a free option is always open, even with an empty cash box
	if cost > 0: co.book("event", -cost, co.setup["biz"], "setup_" + id)
	var s := st(co, id)
	s["state"] = "active"; s["opt"] = oid; s["start"] = co.day; s["due"] = co.day + option_days(co, o)
	s["price"] = cost; s["rel"] = int(o.get("rel", 100)); s["resolved"] = false
	co._snap()
	return {}

# Called every morning of the setup, before the day's cards: tasks whose time has come are done or fail.
static func advance(co: Company, report: Dictionary) -> void:
	var out: Array = []
	var bid: String = co.setup["biz"]
	for t in defs(co):
		var s := st(co, t["id"])
		if s["state"] != "active" or int(s["due"]) > co.day: continue
		var o := option(co, t, s["opt"])
		if t.has("bids") and not bool(s["resolved"]):
			if _resolve_work(co, t, s, out): continue
		var pct := fail_pct(co, t, o)
		var failed := pct > 0 and co.rng("setup_%s_%d" % [t["id"], int(s["tries"])]).int_range(1, 100) <= pct
		s["tries"] = int(s["tries"]) + 1
		if failed:
			s["state"] = "todo"; s["fails"] = int(s["fails"]) + 1
			var fc := int(o.get("fail_cost", 0))
			if fc > 0: co.book("event", -fc, bid, "setup_fail_" + t["id"])
			out.append({"task": t["id"], "result": "failed", "cost": fc, "note_k": str(o.get("fail_note", ""))})
		else:
			s["state"] = "done"
			_apply(co, o.get("effects", []), bid)
			# nothing was paid up front (friends and family): the materials are billed when the work is done
			if int(o.get("settle_pct", 0)) > 0 and t.has("bids"):
				var mat := int(t["bids"]["budget"][_fmt(co)]) * int(o["settle_pct"]) / 100 / 10 * 10
				co.book("event", -mat, bid, "setup_materials")
				out.append({"task": t["id"], "result": "overrun", "cost": mat, "days": 0, "note_k": ""})
			out.append({"task": t["id"], "result": "done", "cost": 0, "note_k": ""})
	report["setup"] = out
	if mandatory_done(co) and co.in_setup(): _open(co, out)

# The work of a professional comes due: as quoted, or one of the usual troubles. The chance is the unreliability the player may have paid to learn.
# Returns true when the task goes on (a delay) so it is not done today.
static func _resolve_work(co: Company, t: Dictionary, s: Dictionary, out: Array) -> bool:
	s["resolved"] = true
	var r := co.rng("work_" + t["id"])
	if r.int_range(1, 100) <= int(s["rel"]): return false
	var kind: String = ["delay", "overrun", "defect"][r.weighted([int(t["bids"]["problems"]["delay"]), int(t["bids"]["problems"]["overrun"]), int(t["bids"]["problems"]["defect"])])]
	var bid: String = co.setup["biz"]
	match kind:
		"delay":
			var n := r.int_range(1, 2)
			s["due"] = co.day + n
			out.append({"task": t["id"], "result": "delayed", "cost": 0, "days": n, "note_k": ""})
			return true
		"overrun":
			var base: int = int(s["price"]) if int(s["price"]) > 0 else int(t["bids"]["budget"][_fmt(co)])
			var extra := base * r.int_range(15, 25) / 100 / 10 * 10
			co.book("event", -extra, bid, "setup_overrun")
			out.append({"task": t["id"], "result": "overrun", "cost": extra, "days": 0, "note_k": ""})
		"defect":
			s["defect"] = true
	return false

static func _apply(co: Company, effects: Array, bid: String) -> void:
	var b: Business = co.units[bid]
	for fx in effects:
		if fx.has("cash"): co.book("event", int(fx["cash"]), bid, "setup")
		if fx.has("equip"): b.equipment = int(fx["equip"]["set"])
		if fx.has("clean"): b.cleanliness = int(fx["clean"]["set"])
		if fx.has("rep"): b.reputation = clampi(b.reputation + int(fx["rep"]["delta"]), 0, 100)
		if fx.has("launch"): co.setup["launch"] = fx["launch"].duplicate()

static func pending_required(co: Company) -> Array:
	return defs(co).filter(func(t): return bool(t.get("required", false)) and not is_done(co, t["id"]))

static func mandatory_done(co: Company) -> bool: return pending_required(co).is_empty()

# Everything that had to be done is done: the doors open as soon as the minimum days of the size have passed.
static func _open(co: Company, out: Array) -> void:
	var bid: String = co.setup["biz"]; var b: Business = co.units[bid]
	# work that was not done well shows when the doors open: the equipment is worn
	for t in defs(co):
		if bool(st(co, t["id"]).get("defect", false)):
			b.equipment = maxi(0, b.equipment - 10)
			out.append({"task": t["id"], "result": "defect", "cost": 0, "days": 0, "note_k": ""})
	var fd := co.format_def(bid, b.format if b.format != "" else "regular")
	b.opened_day = maxi(co.day, b.lease_day + int(fd.get("setup_days", 1)))
	var L: Dictionary = co.setup.get("launch", {})
	if not L.is_empty(): co.add_mod(L["kind"], bid, int(L["value"]), int(L["days"]) + (b.opened_day - co.day))
	co.setup["launch"] = {}

# ---------------------------------------------------------------- for the balance bots and tests: play the board by a style
# style: "diy" (cheapest options), "pro" (the safest options, cleaning done), "mixed" (a consultant for the license only)
static func auto(co: Company, style: String) -> void:
	if co.setup.is_empty(): return
	for t in defs(co):
		if status(co, t) not in ["ready", "retry"]: continue
		if not bool(t.get("required", false)) and not (style != "diy" and t["id"] == "cleaning"): continue
		if t.has("bids"):
			# diy: friends and family; mixed: the middle quote; pro: the dear one that is reliable
			var pref: String = {"diy": "friends", "mixed": "mid", "pro": "premium"}.get(style, "mid")
			if start(co, t["id"], pref).is_empty(): continue
			for fallback in ["friends"]: if start(co, t["id"], fallback).is_empty(): break
			continue
		# the options in the order the style likes them; the first one the cash allows (the free ones are always there)
		var ranked: Array = []
		for o in options_of(co, t):
			var score := int(o.get("cost", 0)) if style == "diy" else (int(o.get("fail_pct", 0)) * 100 + int(o.get("cost", 0)) if style == "pro" else (0 if (t["id"] == "license_application" and o["id"] == "consultant") else int(o.get("cost", 0)) + 1))
			if t["id"] == "equipment" and o["id"] == "used" and style == "diy": score -= 1000
			ranked.append([score, o["id"]])
		ranked.sort_custom(func(x, y): return x[0] < y[0])
		for r in ranked:
			if start(co, t["id"], r[1]).is_empty(): break
