class_name DayRunner
extends RefCounted
# Runs one working day of one business, slot by slot. Time moves with actions, not a clock: each slot customers arrive, the impatient
# leave, and customers are served (by the player in the 3D world, by staff, or by run_auto() when nobody watches this business).
# A sale is reported through `on_sale` so the company books the cash at once. Nothing here knows about the screen.

var biz: Business
var db: Dictionary
var customers: Array
var slot := 0
var slots := 12
var queue: Array = []
var outcomes: Array = []
var cap_left := 0             # what the machine can still make today (made-to-order products)
var closed := false
var on_sale: Callable         # func(outcome: Dictionary) -> void
var _next := 0
var _acc := 0.0
var minute := 0               # minutes since opening (the hands-on day moves time by actions)

func _init(business: Business, custs: Array, slots_today: int, capacity_today: int) -> void:
	biz = business; db = business.db; customers = custs; slots = slots_today; cap_left = capacity_today

func finished() -> bool:
	return slot >= slots and queue.is_empty()

func clock_text() -> String:
	var minutes: int = maxi(db["day_start_hour"] * 60 + mini(slot, slots) * db["slot_minutes"], clock_minutes())
	return "%02d:%02d" % [minutes / 60, minutes % 60]

func progress() -> float:
	return clampf(float(slot) / float(maxi(1, slots)), 0.0, 1.0)

# Opens a slot: returns {arrived: [customers], left: [outcomes]} so the world can show them walking in and out.
func begin_slot() -> Dictionary:
	var arrived: Array = []; var left: Array = []
	while _next < customers.size() and customers[_next]["arrival"] <= slot:
		var c: Dictionary = customers[_next]; _next += 1
		queue.append(c); arrived.append(c)
	for c in queue.duplicate():
		if slot - c["arrival"] > c["patience"]:
			queue.erase(c)
			var o := {"type": "walkout", "customer": c, "waited": slot - c["arrival"]}
			outcomes.append(o); left.append(o)
	return {"arrived": arrived, "left": left}

func end_slot() -> void:
	slot += 1
	minute = maxi(minute, slot * int(db["slot_minutes"]))

# Moves the clock of a hands-on day: every half hour that passes opens a new slot (arrivals, impatient customers leave).
# Returns the events of the slots that opened.
func advance(minutes: int) -> Array:
	var events: Array = []
	minute += minutes
	var sm := int(db["slot_minutes"])
	while slot < slots and minute >= (slot + 1) * sm:
		slot += 1
		if slot < slots: events.append(begin_slot())
		else: events.append(_walkouts_only())
	if slot >= slots: events.append(_walkouts_only())
	return events

func _walkouts_only() -> Dictionary:
	var left: Array = []
	for c in queue.duplicate():
		if slot - c["arrival"] > c["patience"] + 1:
			queue.erase(c)
			var o := {"type": "walkout", "customer": c, "waited": slot - c["arrival"]}
			outcomes.append(o); left.append(o)
	return {"arrived": [], "left": left}

func clock_minutes() -> int:
	return int(db["day_start_hour"]) * 60 + minute

func front() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}

# How many pieces of a product could be sold right now.
func available(pid: String) -> int:
	var pr: Dictionary = db["products"][pid]
	if pr.get("made_to_order", false):
		var by_cap: int = cap_left / maxi(1, int(pr["cap"]))
		return mini(by_cap, biz.inv.max_pieces(pr["recipe"]))
	return biz.inv.stock(pid)

# What a customer would do right now, without changing anything.
func preview(c: Dictionary) -> Dictionary:
	return _resolve(c)

func preview_front() -> Dictionary:
	return _resolve(front())

# Serves a customer (the front one by default): stock, capacity and the outcome change; the company books the money via on_sale.
func commit(c: Dictionary) -> Dictionary:
	var o := _resolve(c)
	queue.erase(c)
	if o["type"] == "sale":
		var pr: Dictionary = db["products"][o["product"]]
		var revenue := 0; var cost := 0
		if pr.get("made_to_order", false):
			var u := biz.inv.use(pr["recipe"], o["qty"])
			cost = u["cost"]; cap_left -= int(pr["cap"]) * o["qty"]
			revenue = o["unit_price"] * o["qty"]
		else:
			for i in o["qty"]:
				var item := biz.inv.take(o["product"])
				if item.is_empty(): break
				revenue += _price_for(o["product"], item["kind"]); cost += int(item["cost"])
		o["revenue"] = revenue; o["cost"] = cost
		var add := _addon(c, o)
		if not add.is_empty():
			o["addon"] = add; o["revenue"] += int(add["price"]); o["cost"] += int(add["cost"])
		o["xp"] = int(pr["xp"])
		if on_sale.is_valid(): on_sale.call(o)
	outcomes.append(o)
	return o

# The next waiting customer after the first `skip` ones ({} if none).
func waiting(skip: int) -> Dictionary:
	return queue[skip] if queue.size() > skip else {}

func commit_front() -> Dictionary:
	return commit(front())

# "And a croissant with that?" Some customers who buy a drink add one pastry, if there is one at a price they accept.
func _addon(c: Dictionary, o: Dictionary) -> Dictionary:
	var ad: Dictionary = db.get("addon", {})
	if ad.is_empty() or not (o["product"] in ad["from"]) or int(c.get("addon_roll", 100)) >= int(ad["pct"]): return {}
	for pid in ad["products"]:
		if available(pid) <= 0: continue
		var info := _item_info(pid)
		var price := _price_for(pid, info["kind"])
		if price > _wtp(pid, int(c["mult"])): continue
		var item := biz.inv.take(pid)
		return {"product": pid, "price": price, "cost": int(item.get("cost", 0))}
	return {}

func _price_for(pid: String, kind: String) -> int:
	var p := biz.price_today(pid)
	return p * int(db["products"][pid].get("old_price_pct", 100)) / 100 if kind == "old" else p

func _wtp(pid: String, mult: int) -> int:
	return int(db["products"][pid]["price"]) * mult / 100 * (100 + biz.wtp_bonus_pct()) / 100

func _item_info(pid: String) -> Dictionary:
	var pr: Dictionary = db["products"][pid]
	if pr.get("made_to_order", false):
		var q := 0; var n := 0
		for iid in pr["recipe"]: q += int(biz.inv.ing[iid]["quality"]); n += 1
		return {"kind": "fresh", "quality": q / maxi(1, n)}
	return biz.inv.peek(pid)

func _resolve(c: Dictionary) -> Dictionary:
	if c.is_empty(): return {"type": "none"}
	var wanted: String = c["wants"]; var waited: int = slot - c["arrival"]
	var others: Array = db["products"].keys().filter(func(p): return p != wanted)
	others.sort_custom(func(a, b): return db["products"][a]["pref"] > db["products"][b]["pref"])
	var reason := ""
	for i in others.size() + 1:
		var pid: String = wanted if i == 0 else others[i - 1]
		var avail := available(pid)
		if avail <= 0:
			if i == 0: reason = "stock"
			continue
		var item := _item_info(pid)
		var price := _price_for(pid, item["kind"])
		if price > _wtp(pid, c["mult"]):
			if i == 0: reason = "price"
			continue
		var want_n: int = int(c.get("qty", 1)) if i == 0 else 1
		var n := mini(want_n, avail)
		var ref: int = db["products"][pid]["price"]
		var sat: int = 72 + (int(item["quality"]) - 70) * 3 / 5
		var base_ref := ref if item["kind"] == "fresh" else ref * int(db["products"][pid].get("old_price_pct", 100)) / 100
		var ratio: int = price * 100 / maxi(1, base_ref)
		if ratio <= 90: sat += 10
		elif ratio > 110: sat -= 10
		if i > 0: sat -= 10
		if n < want_n: sat -= 8
		if item["kind"] == "old": sat -= 15
		sat = clampi(sat - 5 * waited, 0, 100)
		return {"type": "sale", "customer": c, "product": pid, "wanted": wanted, "qty": n, "unit_price": price, "revenue": price * n, "cost": 0,
			"quality": item["quality"], "sat": sat, "waited": waited, "substitute": i > 0, "partial": n < want_n, "old": item["kind"] == "old"}
	return {"type": "lost_" + reason, "customer": c, "wanted": wanted, "waited": waited}

# Serves up to rate_pct/100 customers this slot (fractions carry over). Staff help works this way, and so does run_auto().
func serve_by_rate(rate_pct: int) -> Array:
	var served: Array = []
	_acc += float(rate_pct) / 100.0
	while _acc >= 1.0 and not queue.is_empty():
		served.append(commit_front()); _acc -= 1.0
	if queue.is_empty(): _acc = minf(_acc, 1.0)
	return served

# Plays the whole day with no player here: service at rate_pct per slot (100 = one customer per half hour).
func run_auto(rate_pct: int) -> void:
	while not finished():
		begin_slot()
		serve_by_rate(rate_pct)
		end_slot()
		if slot > slots + 12: break

# The business did not open today: everyone who came found it closed.
func run_closed() -> void:
	closed = true
	for c in customers: outcomes.append({"type": "closed", "customer": c, "waited": 0})
	queue.clear(); slot = slots; _next = customers.size()
