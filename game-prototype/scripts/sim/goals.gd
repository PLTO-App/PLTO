class_name Goals
extends RefCounted
# Goals in chapters (content/goals.json). The first open goals are shown; each one is checked against the company after a day,
# and when it is met its reward (experience and cash) is paid at once.

const SHOWN := 3

static func all(co: Company) -> Array:
	var out: Array = []
	for ch in co.content.goals.get("chapters", []):
		for g in ch["goals"]:
			var x: Dictionary = g.duplicate(true); x["chapter"] = ch["name"]; out.append(x)
	return out

static func active(co: Company) -> Array:
	var out: Array = []
	for g in all(co):
		if g["id"] in co.goals_done: continue
		out.append(g)
		if out.size() >= SHOWN: break
	return out

static func chapter_name(co: Company) -> String:
	var a := active(co)
	return a[0]["chapter"] if not a.is_empty() else ""

# 0..100 how far a goal is (for the progress bar), and whether it is met.
static func progress(co: Company, g: Dictionary) -> int:
	var c: Dictionary = g["check"]
	match c["type"]:
		"sold_total": return clampi(int(co.stats["sold_total"]) * 100 / maxi(1, int(c["n"])), 0, 100)
		"biz_sold_total": return clampi((co.units[c["biz"]].sold_total if co.owns(c["biz"]) else 0) * 100 / maxi(1, int(c["n"])), 0, 100)
		"sold_product_day": return clampi(int(co.stats["sold_product_day"].get(c["product"], 0)) * 100 / maxi(1, int(c["n"])), 0, 100)
		"cash": return clampi(co.profile.cash * 100 / maxi(1, int(c["n"])), 0, 100)
		"no_debt_cash": return 100 if co.loans.is_empty() and co.profile.cash >= int(c["n"]) else clampi(co.profile.cash * 100 / maxi(1, int(c["n"])), 0, 99)
		"rep": return clampi((co.units[c["biz"]].reputation if co.owns(c["biz"]) else 0) * 100 / maxi(1, int(c["n"])), 0, 100)
		"rep_all":
			var lo := 100
			for bid in co.units: lo = mini(lo, co.units[bid].reputation)
			return clampi(lo * 100 / maxi(1, int(c["n"])), 0, 100) if co.units.size() >= 2 else clampi(lo * 50 / maxi(1, int(c["n"])), 0, 50)
		"upgrades": return clampi(co.upgrades_count() * 100 / maxi(1, int(c["n"])), 0, 100)
		"staff": return clampi(co.staff.size() * 100 / maxi(1, int(c["n"])), 0, 100)
		"transfers": return clampi(int(co.stats["transfers"]) * 100 / maxi(1, int(c["n"])), 0, 100)
		"week_profit": return clampi(int(co.stats["profit_weeks"]) * 100 / maxi(1, int(c["n"])), 0, 100)
		"no_stockout_day": return 100 if co.flags.has("no_stockout_day") else 0
		"supplier_order": return 100 if int(co.stats["supplier_orders"]) > 0 else 0
		"contract_active": return 100 if co.contracts.has(c["id"]) and co.contracts[c["id"]]["active"] else 0
		"service": return 100 if co.services.has(c["id"]) else 0
		"inspection_passed": return 100 if int(co.stats["inspections_passed"]) > 0 else 0
		"owns": return 100 if co.owns(c["biz"]) else 0
	return 0

# Marks newly met goals and pays their rewards. Returns the goals met now.
static func update(co: Company) -> Array:
	var met: Array = []
	for _pass in 4:
		var before := met.size()
		_update_once(co, met)
		if met.size() == before: break
	return met

static func _update_once(co: Company, met: Array) -> void:
	for g in active(co):
		if progress(co, g) >= 100:
			co.goals_done.append(g["id"])
			var rw: Dictionary = g.get("reward", {})
			if int(rw.get("cash", 0)) > 0: co.book("reward", int(rw["cash"]), "", g["id"])
			for lv in co.profile.add_xp(int(rw.get("xp", 0))): co.levels_today.append(lv)
			met.append({"id": g["id"], "name": g["name"], "xp": int(rw.get("xp", 0)), "cash": int(rw.get("cash", 0))})
