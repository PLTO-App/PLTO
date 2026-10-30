class_name Negotiation
extends RefCounted
# Haggling with a professional over a quote (the contractor): up to a few moves, each with a risk. The professional has a floor the
# player cannot see (how far the price can really come down), a patience that rude or pushy moves use up, and a mood that depends on
# things outside the player's hands (a busy season) and on what the player does (a real second quote, cash in hand, what the player
# learned from a reference check). Every answer is a roll from the seed, so the same moves give the same story.
#
# State in Company.setup["neg"]: {task, bid, open, list, price (their current offer), last_ask, patience, floor, adj (shift of the floor in
# shekels), moves, warranty, alt, cash, busy, lines: [{k, p}], result: "" | deal | walked | burned}. Money is whole shekels.

static func cfg(co: Company) -> Dictionary: return co.content.negotiation

static func state(co: Company) -> Dictionary: return co.setup.get("neg", {})

static func is_open(co: Company) -> bool: return not state(co).is_empty() and bool(state(co).get("open", false))

static func r10(x: int) -> int: return x / 10 * 10

static func _bid(co: Company, task_id: String, bid_id: String) -> Dictionary:
	for b in co.setup["bids"].get(task_id, []): if b["id"] == bid_id: return b
	return {}

static func eff_floor(co: Company) -> int:
	var n := state(co)
	return int(n["floor"]) + int(n["adj"])

# The mood the player can read: 3 calm, 2 getting annoyed, 1 about to leave.
static func mood(co: Company) -> int: return clampi(int(state(co)["patience"]), 1, 3)

static func begin(co: Company, task_id: String, bid_id: String) -> Dictionary:
	var t := SetupBoard.def_of(co, task_id)
	var b := _bid(co, task_id, bid_id)
	if t.is_empty() or b.is_empty() or SetupBoard.status(co, t) not in ["ready", "retry"] or b["neg"] != "none": return Loc.m("err.setup_unknown")
	var c := cfg(co); var list := int(b["price"])
	var r := co.rng("neg_open_" + bid_id)
	var flex := int(c["flex"][bid_id]) + r.int_range(-3, 3)
	var busy := r.int_range(1, 100) <= int(c["busy_pct"])
	if busy: flex -= int(c["busy_penalty"])
	if co.day - int(co.units[co.setup["biz"]].lease_day) >= int(c["urgent_days"]): flex -= int(c["urgent_penalty"])
	flex = maxi(flex, 2)
	var adj := 0
	# what the player learned from a reference check weighs in: a professional with a poor name knows it
	if bool(b["checked"]) and int(b["rel"]) < int(c["bad_reputation_below"]): adj -= list * int(c["bad_reputation_bonus"]) / 100
	co.setup["neg"] = {"task": task_id, "bid": bid_id, "open": true, "list": list, "price": list, "last_ask": 0, "patience": int(c["patience"][bid_id]),
		"floor": r10(list * (100 - flex) / 100), "adj": adj, "moves": 0, "warranty": false, "alt": false, "cash": false, "busy": busy, "lines": [], "result": ""}
	b["neg"] = "open"
	co._snap()
	return {}

# The moves the player may make now.
static func moves(co: Company) -> Array:
	var n := state(co); var out: Array = []
	if not is_open(co): return out
	if int(n["moves"]) < int(cfg(co)["max_moves"]):
		out.append_array(["ask_small", "ask_big", "ask_huge"])
		if not bool(n["warranty"]): out.append("warranty")
		if not bool(n["alt"]): out.append("alt")
		if not bool(n["cash"]): out.append("cash")
		if int(n["last_ask"]) > 0 and int(n["price"]) > int(n["last_ask"]): out.append_array(["compromise", "insist"])
	out.append_array(["accept", "walk"])
	return out

static func _say(n: Dictionary, k: String, p := {}) -> void: n["lines"].append({"k": k, "p": p})

# One move. Returns {} or an error message.
static func play(co: Company, move: String) -> Dictionary:
	if not is_open(co) or move not in moves(co): return Loc.m("err.setup_unknown")
	var n := state(co); var c := cfg(co); var b := _bid(co, n["task"], n["bid"])
	var list := int(n["list"])
	var r := co.rng("neg_%s_%d_%s" % [n["bid"], int(n["moves"]), move])
	n["moves"] = int(n["moves"]) + 1
	match move:
		"accept":
			_finish(co, "deal"); return {}
		"walk":
			_say(n, "neg.say.walk"); _finish(co, "walked"); return {}
		"ask_small", "ask_big", "ask_huge":
			_ask(co, r10(int(n["price"]) * (100 - int(c["asks"][move])) / 100), r)
		"compromise":
			_ask(co, r10((int(n["price"]) + int(n["last_ask"])) / 2), r, true)
		"insist":
			_ask(co, int(n["last_ask"]), r, false, true)
		"warranty":
			var p := int(c["warranty_pct"][n["bid"]]) - (int(c["warranty_busy_penalty"]) if bool(n["busy"]) else 0)
			if r.int_range(1, 100) <= p:
				n["warranty"] = true; n["price"] = r10(int(n["price"]) + list * int(c["warranty_charge_pct"]) / 100)
				_say(n, "neg.say.warranty_yes", {"price_m": n["price"]})
			else: _say(n, "neg.say.warranty_no")
		"alt":
			n["alt"] = true
			var credible := false
			for o in co.setup["bids"][n["task"]]:
				if o["id"] != n["bid"] and o["neg"] != "burned" and int(o["price"]) <= int(n["price"]) * 110 / 100: credible = true
			if credible:
				n["adj"] = int(n["adj"]) - list * int(c["alt_bonus"]) / 100
				_say(n, "neg.say.alt_real")
			elif r.int_range(1, 100) <= int(c["bluff_called_pct"]):
				n["adj"] = int(n["adj"]) + list * int(c["bluff_penalty"]) / 100; n["patience"] = int(n["patience"]) - 2
				_say(n, "neg.say.alt_called")
			else:
				n["adj"] = int(n["adj"]) - list * int(c["bluff_lucky_bonus"]) / 100
				_say(n, "neg.say.alt_bluff_worked")
		"cash":
			n["cash"] = true
			if co.profile.cash >= int(n["price"]) + int(c["cash_buffer"]):
				n["adj"] = int(n["adj"]) - list * int(c["cash_bonus"]) / 100; _say(n, "neg.say.cash_ok")
			else: _say(n, "neg.say.cash_no")
	if int(n["patience"]) <= 0 and bool(n["open"]):
		_say(n, "neg.say.walkout"); _finish(co, "burned")
	elif bool(n["open"]) and int(n["moves"]) >= int(c["max_moves"]) and not (moves(co).has("ask_small")):
		_say(n, "neg.say.last_word")
	co._snap()
	return {}

# The player asks for a price. The professional looks at the hidden floor.
static func _ask(co: Company, ask: int, r: SimRng, halfway := false, insist := false) -> void:
	var n := state(co); var c := cfg(co); var list := int(n["list"])
	var cur := int(n["price"])
	var ef := eff_floor(co)
	n["last_ask"] = ask
	_say(n, "neg.say.you_ask", {"price_m": ask})
	if ask >= ef:
		# reasonable: most of the time it is accepted; insisting on what was refused before costs patience
		if insist and r.int_range(1, 100) > 35 + int(n["patience"]) * 10:
			n["patience"] = int(n["patience"]) - 1; _say(n, "neg.say.no"); return
		if r.int_range(1, 100) <= int(c["yes_pct"]): n["price"] = ask; _say(n, "neg.say.yes", {"price_m": ask}); _finish(co, "deal"); return
	if ask >= ef - list * int(c["near_pct"]) / 100:
		var counter := r10(ef + (cur - ef) * int(c["counter_share"]) / 100)
		if counter < cur and counter > ask: n["price"] = counter; _say(n, "neg.say.counter", {"price_m": counter}); return
		if halfway: n["price"] = maxi(ask, ef); _say(n, "neg.say.counter", {"price_m": n["price"]}); return
	if ask >= ef - list * int(c["far_pct"]) / 100:
		n["patience"] = int(n["patience"]) - 1; _say(n, "neg.say.no"); return
	n["patience"] = int(n["patience"]) - 2; _say(n, "neg.say.offended")

# The end: a deal at their current offer, a polite walk away (the quote stays at its list price), or the professional leaves.
static func _finish(co: Company, result: String) -> void:
	var n := state(co); var b := _bid(co, n["task"], n["bid"])
	n["open"] = false; n["result"] = result
	match result:
		"deal":
			b["price"] = int(n["price"]); b["neg"] = "deal"; b["deal"] = true
			if bool(n["warranty"]): b["rel"] = mini(98, int(b["rel"]) + int(cfg(co)["warranty_rel"])); b["warranty"] = true
			SetupBoard.journal(co, "negotiation", n["task"], int(n["list"]) - int(n["price"]), 0, {"who_k": b["who"], "warranty": bool(n["warranty"])})
		"walked": b["neg"] = "closed"
		"burned":
			b["neg"] = "burned"
			SetupBoard.journal(co, "burned", n["task"], 0, 0, {"who_k": b["who"]})
