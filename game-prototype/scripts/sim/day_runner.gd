class_name DayRunner
extends RefCounted
# Runs one working day slot by slot. Time moves with actions, not a clock: each slot customers arrive, the impatient leave,
# and one customer is served (the player does it by hand in the 3D world, or run_auto() does it for balance tests).
# Nothing here knows about the screen.

var biz: Business
var db: Dictionary
var customers: Array
var slot := 0
var queue: Array = []
var outcomes: Array = []
var levels_gained: Array[int] = []
var _next := 0

func _init(business: Business, custs: Array) -> void:
	biz = business; db = business.db; customers = custs

func finished() -> bool:
	return slot >= db["slots"] and queue.is_empty()

func clock_text() -> String:
	var minutes: int = db["day_start_hour"] * 60 + mini(slot, db["slots"]) * db["slot_minutes"]
	return "%02d:%02d" % [minutes / 60, minutes % 60]

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

func front() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}

# What the front customer would do right now, without changing anything.
func preview_front() -> Dictionary:
	return _resolve(front())

# The front customer is served: stock, cash, ledger and experience change.
func commit_front() -> Dictionary:
	var c := front()
	var o := _resolve(c)
	queue.pop_front()
	if o["type"] == "sale":
		var item := biz.inv.take(o["product"])
		biz.profile.add_cash(o["price"]); biz.ledger.add(biz.day, "revenue", o["price"], o["product"])
		biz.profile.sales_count += 1; biz.profile.total_revenue += o["price"]; biz.profile.total_profit += o["price"] - item["cost"]
		var xp: int = db["products"][o["product"]]["xp"]
		o["xp"] = xp
		for lv in biz.profile.add_xp(xp): levels_gained.append(lv)
	outcomes.append(o)
	return o

func _price_for(pid: String, kind: String) -> int:
	var p := biz.price_today(pid)
	return p * db["products"][pid]["old_price_pct"] / 100 if kind == "old" else p

func _wtp(pid: String, mult: int) -> int:
	return db["products"][pid]["price"] * mult / 100 * (100 + biz.wtp_bonus_pct()) / 100

func _resolve(c: Dictionary) -> Dictionary:
	var wanted: String = c["wants"]; var waited: int = slot - c["arrival"]
	var order: Array = [wanted]
	var others: Array = db["products"].keys().filter(func(p): return p != wanted)
	others.sort_custom(func(a, b): return db["products"][a]["pref"] > db["products"][b]["pref"])
	var reason := ""
	for i in order.size() + others.size():
		var pid: String = wanted if i == 0 else others[i - 1]
		var item := biz.inv.peek(pid)
		if item.is_empty():
			if i == 0: reason = "stock"
			continue
		var price := _price_for(pid, item["kind"])
		if price > _wtp(pid, c["mult"]):
			if i == 0: reason = "price"
			continue
		var ref: int = db["products"][pid]["price"]
		var sat: int = 72 + (item["quality"] - 70) * 3 / 5
		var ratio: int = price * 100 / maxi(1, ref if item["kind"] == "fresh" else ref * db["products"][pid]["old_price_pct"] / 100)
		if ratio <= 90: sat += 10
		elif ratio > 110: sat -= 10
		if i > 0: sat -= 10
		if item["kind"] == "old": sat -= 15
		sat = clampi(sat - 5 * waited, 0, 100)
		return {"type": "sale", "customer": c, "product": pid, "wanted": wanted, "price": price, "cost": item["cost"], "quality": item["quality"],
			"sat": sat, "waited": waited, "substitute": i > 0, "old": item["kind"] == "old"}
	return {"type": "lost_" + reason, "customer": c, "wanted": wanted, "waited": waited}

# Plays the whole day with the best possible service (no hands needed). Used by the balance tests.
func run_auto() -> void:
	while not finished():
		begin_slot()
		if not queue.is_empty(): commit_front()
		end_slot()
