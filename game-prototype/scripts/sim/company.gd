class_name Company
extends RefCounted
# The player's company: one cash box and one ledger for all the businesses, the town around them (suppliers, partners, the bank,
# the accountant), staff, contracts, invoices to collect and to pay, events and goals. It runs the day across all businesses:
#   start_morning()  -> deliveries arrive, invoices are collected and paid, events are drawn
#   commit_day()     -> each business carries out its plan; deliveries to partners and to our own café; runners are created
#   close_day()      -> every business closes (the ones the player did not work in run by themselves), the books close,
#                       and on the eve of the rest day the week is settled (rent, wages, services, loans)
# No screen and no 3D here, so a whole season can be played in a test in seconds.

const SAVE_VERSION := 3
const OWNER_RATE := 250          # customers per half-hour slot, in percent, that Noa serves when the day is played automatically

var content: ContentDb
var world: Dictionary
var profile := Profile.new()
var units := {}                 # business id -> Business
var ledger := Ledger.new()
var day := 1
var seed_value := 1
var weather := "sunny"
var worker := "bakery"          # where Noa works today
var staff: Array = []           # {id, wage, skill, role, assigned, hired_day, sick_day, asked_raise}
var receivables: Array = []     # {id, partner_k, amount, due, late_until, biz}
var payables: Array = []        # {id, to_k, amount, due}
var loans: Array = []           # {id, weekly, weeks_left, interest_week}
var contracts := {}             # id -> {active, misses, prices, items, since}
var orders: Array = []          # supplier orders: {biz, sup, items, cost, arrive, credit}
var special: Array = []         # one-off partner orders: {biz, product, qty, price, terms, partner_k, deliver}
var mods: Array = []            # {kind, target, value, until}
var services := {}              # service id -> true
var flags := {}
var stats := {"sold_total": 0, "transfers": 0, "inspections_passed": 0, "supplier_orders": 0, "profit_weeks": 0, "best_no_stockout": 0,
	"sold_product_day": {}, "week_profit": 0, "week_revenue": 0, "week_start_cash": 0}
var goals_done: Array = []
var ev_state := {"last": {}, "times": {}, "next_inspection": 0}
var pending_events: Array = []
var inspection_today := ""      # a business the inspector visits today ("" = none)
var regulars := {}
var wages_due := 0
var levels_today: Array[int] = []
var phase := "morning"          # morning | day
var morning_day := 0            # the day whose morning already ran (deliveries, events): never run it twice
var runners := {}
var last_report := {}
var last_summary := {}
var last_week := {}
var last_goals: Array = []
var snapshot := {}
var _rng_calls := 0

func _init(content_db: ContentDb) -> void:
	content = content_db; world = content.world

# ---------------------------------------------------------------- start, save, load
func new_game(new_seed: int, keep_profile := false) -> void:
	seed_value = new_seed; day = 1
	if not keep_profile: profile.reset(content)
	profile.cash = int(world["start"]["cash"]) if not keep_profile else profile.cash
	ledger = Ledger.new(); ledger.start_cash = profile.cash
	units = {}
	for bid in world["start"]["businesses"]: _add_unit(bid)
	worker = world["start"]["worker"]
	staff = []; receivables = []; payables = []; loans = []; contracts = {}; orders = []; special = []; mods = []; services = {}; flags = {}
	stats = {"sold_total": 0, "transfers": 0, "inspections_passed": 0, "supplier_orders": 0, "profit_weeks": 0, "best_no_stockout": 0,
		"sold_product_day": {}, "week_profit": 0, "week_revenue": 0, "week_start_cash": profile.cash}
	goals_done = []; ev_state = {"last": {}, "times": {}, "next_inspection": int(world["inspection"]["first_day"])}
	pending_events = []; inspection_today = ""; regulars = {}; wages_due = 0; phase = "morning"; runners = {}; morning_day = 0; levels_today = []
	last_report = {}; last_summary = {}; last_week = {}; last_goals = []
	_snap()

func _add_unit(bid: String) -> Business:
	var b := Business.new(content.businesses[bid])
	b.new_unit(day, world["suppliers"]["wholesale"]["prices"])
	units[bid] = b
	return b

func to_dict() -> Dictionary:
	var u := {}
	for bid in units: u[bid] = units[bid].to_dict()
	return {"v": SAVE_VERSION, "profile": profile.to_dict(), "day": day, "seed": seed_value, "units": u, "ledger": ledger.to_dict(), "worker": worker,
		"staff": staff.duplicate(true), "receivables": receivables.duplicate(true), "payables": payables.duplicate(true), "loans": loans.duplicate(true),
		"contracts": contracts.duplicate(true), "orders": orders.duplicate(true), "special": special.duplicate(true), "mods": mods.duplicate(true),
		"services": services.duplicate(), "flags": flags.duplicate(true), "stats": stats.duplicate(true), "goals_done": goals_done.duplicate(),
		"ev_state": ev_state.duplicate(true), "regulars": regulars.duplicate(true), "wages_due": wages_due,
		"last_summary": last_summary.duplicate(true), "last_week": last_week.duplicate(true),
		"morning_day": morning_day, "pending_events": pending_events.duplicate(true), "last_report": last_report.duplicate(true), "inspection_today": inspection_today}

func from_dict(d: Dictionary) -> void:
	profile.from_dict(d.get("profile", {}), content)
	day = maxi(1, int(d.get("day", 1))); seed_value = int(d.get("seed", 1))
	units = {}
	for bid in d.get("units", {}):
		if content.businesses.has(bid):
			var b := Business.new(content.businesses[bid]); b.from_dict(d["units"][bid]); units[bid] = b
	if units.is_empty(): _add_unit("bakery")
	ledger = Ledger.new(); ledger.from_dict(d.get("ledger", {}))
	worker = str(d.get("worker", "bakery")) if units.has(str(d.get("worker", "bakery"))) else units.keys()[0]
	staff = _ints(d.get("staff", [])); receivables = _ints(d.get("receivables", [])); payables = _ints(d.get("payables", []))
	loans = _ints(d.get("loans", [])); contracts = _ints(d.get("contracts", {})); orders = _ints(d.get("orders", [])); special = _ints(d.get("special", []))
	mods = _ints(d.get("mods", [])); services = _ints(d.get("services", {})); flags = _ints(d.get("flags", {})); stats = _ints(d.get("stats", stats))
	goals_done = d.get("goals_done", []); ev_state = _ints(d.get("ev_state", ev_state)); regulars = _ints(d.get("regulars", {}))
	wages_due = int(d.get("wages_due", 0)); last_summary = _ints(d.get("last_summary", {})); last_week = _ints(d.get("last_week", {}))
	phase = "morning"; runners = {}
	morning_day = int(d.get("morning_day", 0)); pending_events = _ints(d.get("pending_events", [])) if morning_day == day else []
	last_report = _ints(d.get("last_report", {})) if morning_day == day else {}; inspection_today = str(d.get("inspection_today", "")) if morning_day == day else ""
	if morning_day == day: _roll_weather()
	# the books must match the cash; if an edited or broken save does not, start the journal again from the cash on hand
	if ledger.balance() != profile.cash:
		ledger = Ledger.new(); ledger.start_cash = profile.cash
	_snap()

# JSON turns every number into a float. Money and counts are whole numbers, so they are turned back into ints.
func _ints(v):
	match typeof(v):
		TYPE_FLOAT: return int(v)
		TYPE_ARRAY:
			var a: Array = []
			for x in v: a.append(_ints(x))
			return a
		TYPE_DICTIONARY:
			var o := {}
			for k in v: o[k] = _ints(v[k])
			return o
	return v

func _snap() -> void:
	snapshot = to_dict()

# ---------------------------------------------------------------- small helpers
func rng(purpose: String) -> SimRng:
	return SimRng.new(seed_value, day, purpose)

func weekday(d := -1) -> int:
	return ((day if d < 0 else d) - 1) % 7

func weekday_key(d := -1) -> String:
	return world["week"]["weekday_keys"][weekday(d)]

func is_workday(d := -1) -> bool:
	return weekday(d) in world["week"]["workdays"]

func level() -> int:
	return profile.level

func owns(bid: String) -> bool:
	return units.has(bid)

func book(cat: String, amount: int, biz := "", note := "") -> void:
	if amount == 0: return
	profile.add_cash(amount); ledger.add(day, cat, amount, biz, note)

func overdraft_limit() -> int:
	return int(world["bank"]["overdraft_limit"])

func cash_available() -> int:
	return profile.cash + overdraft_limit()

func mod_value(kind: String, target: String) -> int:
	var t := 0
	for m in mods:
		if m["kind"] == kind and (m["target"] == target or m["target"] == "*") and int(m["until"]) >= day: t += int(m["value"])
	return t

func add_mod(kind: String, target: String, value: int, days: int) -> void:
	mods.append({"kind": kind, "target": target, "value": value, "until": day + days - 1})

func supplier_unlocked(sid: String) -> bool:
	return level() >= int(world["suppliers"][sid]["unlock_level"])

func supplier_price(sid: String, item: String) -> int:
	var base := int(world["suppliers"][sid]["prices"].get(item, 0))
	return base * (100 + mod_value("ingredient_price_pct", item)) / 100

func supplier_prices(sid: String) -> Dictionary:
	var p := {}
	for item in world["suppliers"][sid]["prices"]: p[item] = supplier_price(sid, item)
	return p

# Things a business can buy (ingredients and ready goods).
func buyable_items(bid: String) -> Array:
	var b: Business = units[bid]
	return b.ingredient_ids() + b.goods_input_ids()

func item_name_key(bid: String, item: String) -> String:
	var b: Business = units[bid]
	if b.db["ingredients"].has(item): return b.db["ingredients"][item]["name"]
	return b.db.get("goods_inputs", {}).get(item, {}).get("name", item)

func item_step(bid: String, item: String) -> int:
	var b: Business = units[bid]
	if b.db["ingredients"].has(item): return int(b.db["ingredients"][item]["step"])
	return int(b.db.get("goods_inputs", {}).get(item, {}).get("step", 1))

func now_supplier() -> String:
	return "minimarket"

func plan_ctx(bid: String) -> Dictionary:
	var ns := now_supplier()
	return {"level": level(), "cash_available": cash_available(), "now_prices": supplier_prices(ns), "now_quality": int(world["suppliers"][ns]["quality"]),
		"capacity_pct": mod_value("capacity_pct", bid), "upkeep": world["upkeep"]}

# ---------------------------------------------------------------- staff
func staff_entry(sid: String) -> Dictionary:
	for s in staff: if s["id"] == sid: return s
	return {}

func staff_def(sid: String) -> Dictionary:
	for s in world["staff_pool"]: if s["id"] == sid: return s
	return {}

func candidates() -> Array:
	var out: Array = []
	if level() < 2: return out
	for s in world["staff_pool"]:
		if staff_entry(s["id"]).is_empty(): out.append(s)
	return out

func hire(sid: String, bid: String) -> Dictionary:
	var d := staff_def(sid)
	if d.is_empty() or not staff_entry(sid).is_empty(): return Loc.m("err.staff_unknown")
	if level() < 2: return Loc.m("err.staff_level")
	staff.append({"id": sid, "wage": int(d["wage"]), "skill": int(d["skill"]), "role": d["role"], "assigned": bid, "hired_day": day, "sick_day": 0, "asked_raise": 0})
	_snap()
	return {}

func fire(sid: String) -> void:
	staff = staff.filter(func(s): return s["id"] != sid)
	_snap()

func assign(sid: String, bid: String) -> void:
	var s := staff_entry(sid)
	if not s.is_empty(): s["assigned"] = bid
	_snap()

func staff_at(bid: String) -> Array:
	return staff.filter(func(s): return s["assigned"] == bid and int(s["sick_day"]) != day)

# Customers per half-hour slot served by the staff of a business (100 = one), on top of the player if the player works there.
func staff_rate(bid: String) -> int:
	var r := 0
	for s in staff_at(bid): r += 100 + int(s["skill"]) + (40 if (s["role"] == "barista") == (bid == "cafe") else 0)
	return r

func is_open_today(bid: String) -> bool:
	return bid == worker or not staff_at(bid).is_empty()

# ---------------------------------------------------------------- services, bank, opening a business
func subscribe(svc: String, on: bool) -> Dictionary:
	if on and level() < int(world["services"][svc]["unlock_level"]): return Loc.m("err.level", {"n": world["services"][svc]["unlock_level"]})
	if on: services[svc] = true
	else: services.erase(svc)
	_snap()
	return {}

func loan_open(lid: String) -> bool:
	for l in loans: if l["id"] == lid: return true
	return false

func take_loan(lid: String) -> Dictionary:
	var L: Dictionary = world["bank"]["loans"][lid]
	if level() < int(L["unlock_level"]): return Loc.m("err.level", {"n": L["unlock_level"]})
	if loan_open(lid): return Loc.m("err.loan_open")
	var interest_week: int = (int(L["weekly"]) * int(L["weeks"]) - int(L["amount"])) / int(L["weeks"])
	loans.append({"id": lid, "weekly": int(L["weekly"]), "weeks_left": int(L["weeks"]), "interest_week": interest_week})
	book("loan", int(L["amount"]), "", lid)
	_snap()
	return {}

func debt() -> int:
	var t := 0
	for l in loans: t += int(l["weekly"]) * int(l["weeks_left"])
	return t

func can_open(bid: String) -> Dictionary:
	if owns(bid): return Loc.m("err.already_open")
	var o: Dictionary = world["openable"][bid]
	if level() < int(o["unlock_level"]): return Loc.m("err.level", {"n": o["unlock_level"]})
	if profile.cash < int(o["cost"]): return Loc.m("err.no_cash", {"amount_m": int(o["cost"]) - profile.cash})
	return {}

func open_business(bid: String) -> Dictionary:
	var e := can_open(bid)
	if not e.is_empty(): return e
	book("investment", -int(world["openable"][bid]["cost"]), bid, "open")
	var b := _add_unit(bid)
	b.opened_day = day + int(world["openable"][bid].get("setup_days", 1))
	flags["opened_" + bid] = day
	_snap()
	return {}

func unit_ready(bid: String) -> bool:
	return owns(bid) and units[bid].opened_day <= day

# ---------------------------------------------------------------- supplier orders (delivered on a later morning)
func order_cost(sid: String, items: Dictionary) -> int:
	var c := 0
	for item in items: c += int(items[item]) * supplier_price(sid, item)
	return c

func credit_ok(sid: String) -> bool:
	return level() >= int(world["suppliers"][sid]["credit_level"])

func place_order(bid: String, sid: String, items: Dictionary) -> Dictionary:
	if not supplier_unlocked(sid): return Loc.m("err.supplier_locked")
	var clean := {}
	for item in items: if int(items[item]) > 0: clean[item] = int(items[item])
	if clean.is_empty(): return Loc.m("err.empty_order")
	# a shop has room for only so much on its shelves: what is there, what is on its way and this order
	var shop: Business = units[bid]
	if shop.is_retail():
		var pending := 0
		for o in orders_for(bid): for k in o["items"]: pending += int(o["items"][k])
		var add := 0
		for k in clean: add += int(clean[k])
		var room := shop.capacity(mod_value("capacity_pct", bid))
		var after := projected_stock(bid) + pending + add
		if after > room: return Loc.m("err.shelf_full", {"used": after, "cap": room})
	var cost := order_cost(sid, clean)
	var credit := credit_ok(sid)
	if not credit and cost > cash_available() - _orders_due_tomorrow(): return Loc.m("err.no_cash", {"amount_m": cost - (cash_available() - _orders_due_tomorrow())})
	var days := maxi(1, int(world["suppliers"][sid]["delivery_days"]))
	orders.append({"biz": bid, "sup": sid, "items": clean, "cost": cost, "arrive": day + days, "credit": credit,
		"quality": int(world["suppliers"][sid]["quality"])})
	stats["supplier_orders"] += 1
	_snap()
	return {}

# What will be on a shop's shelves tomorrow morning if nothing more is ordered: today's stock less what today is expected to sell
# (once the morning has run and the day is still to be played), so an order placed in the morning is judged by tomorrow's room.
func projected_stock(bid: String) -> int:
	var b: Business = units[bid]; var n := b.stock_total()
	if morning_day == day:
		var sold := 0
		var w := forecast_items(bid, b.empty_plan())
		for pid in w: sold += int(w[pid])
		n = maxi(0, n - sold)
	return n

func _orders_due_tomorrow() -> int:
	var t := 0
	for o in orders: if not o["credit"]: t += int(o["cost"])
	return t

func cancel_order(i: int) -> void:
	if i >= 0 and i < orders.size(): orders.remove_at(i); _snap()

func orders_for(bid: String) -> Array:
	return orders.filter(func(o): return o["biz"] == bid)

# ---------------------------------------------------------------- the morning
func start_morning() -> Dictionary:
	phase = "morning"; levels_today = []; inspection_today = ""; morning_day = day
	for bid in units: units[bid].reset_today()
	var r := {"day": day, "weekday_k": weekday_key(), "deliveries": [], "collected": [], "paid": [], "late": [], "relief": 0, "events": [], "notes": []}
	_roll_weather()
	r["weather"] = weather
	# deliveries from suppliers
	var keep: Array = []
	for o in orders:
		if int(o["arrive"]) > day: keep.append(o); continue
		if not units.has(o["biz"]): continue
		var b: Business = units[o["biz"]]
		for item in o["items"]:
			var n := int(o["items"][item]); var price := supplier_price_at(o, item)
			if b.db["ingredients"].has(item): b.inv.add_ingredient(item, n, int(o["quality"]), price)
			else:
				var pid := b.product_for_input(item)
				if pid != "": b.inv.add_goods(pid, n, int(o["quality"]), price)
		if o["credit"]:
			payables.append({"id": "%s-%d" % [o["sup"], day], "to_k": world["suppliers"][o["sup"]]["name"], "amount": int(o["cost"]), "due": day + int(world["suppliers"][o["sup"]]["credit_days"])})
		else:
			book("purchase", -int(o["cost"]), o["biz"], o["sup"])
		r["deliveries"].append({"biz": o["biz"], "sup": o["sup"], "cost": int(o["cost"]), "credit": o["credit"], "items": o["items"]})
	orders = keep
	# invoices our partners owe us
	var still: Array = []
	var rr := rng("collect")
	for v in receivables:
		if int(v["due"]) > day or int(v.get("late_until", 0)) > day: still.append(v); continue
		if not services.has("accountant") and int(v.get("late_until", 0)) == 0 and rr.int_range(1, 100) <= 35:
			v["late_until"] = day + 3; still.append(v); r["late"].append(v); continue
		book("collect", int(v["amount"]), v.get("biz", ""), v["partner_k"])
		r["collected"].append({"partner_k": v["partner_k"], "amount": int(v["amount"])})
	receivables = still
	# invoices we owe (paid on the due day)
	var open_p: Array = []
	for p in payables:
		if int(p["due"]) > day: open_p.append(p); continue
		book("pay_invoice", -int(p["amount"]), "", p["to_k"])
		r["paid"].append({"to_k": p["to_k"], "amount": int(p["amount"])})
	payables = open_p
	mods = mods.filter(func(m): return int(m["until"]) >= day)
	for s in staff: if int(s["sick_day"]) < day: s["sick_day"] = 0
	r["relief"] = morning_relief()
	pending_events = EventEngine.morning(self, r)
	r["events"] = pending_events
	last_report = r
	_snap()
	return r

# Today's weather comes from the seed and the day, so it is not saved: a morning that is loaded again gets the same weather.
func _roll_weather() -> void:
	var wk: Dictionary = world["weather"]["kinds"]; var ws: Array = wk.keys(); var ww: Array = []
	for k in ws: ww.append(int(wk[k]["w"]))
	weather = ws[rng("weather").weighted(ww)]

func supplier_price_at(o: Dictionary, item: String) -> int:
	# the price that was paid per unit when ordered (the cost is split by the list prices at the time of ordering)
	var list := 0
	for k in o["items"]: list += int(o["items"][k]) * int(world["suppliers"][o["sup"]]["prices"].get(k, 0))
	var base := int(world["suppliers"][o["sup"]]["prices"].get(item, 0))
	return base * int(o["cost"]) / maxi(1, list)

# If the cash is gone and there is nothing to sell or bake, the family helps once more, so the game never locks.
func morning_relief() -> int:
	var has_stock := false
	for bid in units:
		var b: Business = units[bid]
		if b.any_stock() or b.inv.ingredients_value() > 60: has_stock = true
	if not orders.is_empty(): has_stock = true
	# below the bank's limit nothing can be bought at all: the family steps in again so the game can go on
	if (profile.cash >= 150 or has_stock) and profile.cash > -overdraft_limit() + 100: return 0
	var help := 600 - profile.cash
	book("relief", help, "", "family")
	return help

func resolve_event(ev: Dictionary, choice: int) -> Dictionary:
	var res := EventEngine.resolve(self, ev, choice)
	pending_events.erase(ev)
	_snap()
	return res

# ---------------------------------------------------------------- the plan for the day
# What our own bakery has to deliver today: special orders, contracts and the café's request.
func reserved_for(bid: String, plans := {}) -> Dictionary:
	var r := {}
	for s in special:
		if s["biz"] == bid and int(s["deliver"]) == day: r[s["product"]] = r.get(s["product"], 0) + int(s["qty"])
	for cid in contracts:
		var c: Dictionary = contracts[cid]
		if c["active"] and world["contracts"][cid]["biz"] == bid and is_workday():
			for pid in c["items"]: r[pid] = r.get(pid, 0) + int(c["items"][pid])
	for other in plans:
		var internal: Dictionary = world.get("internal", {}).get(other, {})
		if internal.get("from", "") == bid:
			for pid in plans[other].get("transfer_in", {}): r[pid] = r.get(pid, 0) + int(plans[other]["transfer_in"][pid])
	return r

func validate_day(plans: Dictionary) -> Array:
	var errs: Array = []
	var spend := 0
	for bid in plans:
		if not units.has(bid): continue
		var ctx := plan_ctx(bid)
		for e in units[bid].validate_plan(plans[bid], ctx): errs.append(e)
		spend += units[bid].plan_costs(plans[bid], ctx)["total"]
	if errs.is_empty() and spend > 0 and spend > cash_available(): errs.append(Loc.m("err.no_cash", {"amount_m": spend - cash_available()}))
	return errs

# Carries out the plans of all businesses and opens the day. worker = the business Noa works in.
func commit_day(plans: Dictionary, p_worker: String) -> Array:
	var errs := validate_day(plans)
	if not errs.is_empty(): return errs
	worker = p_worker if units.has(p_worker) and unit_ready(p_worker) else _first_ready()
	stats["day_start_cash"] = profile.cash
	# the bakery first: what it bakes is delivered to partners and to our café
	var order_ids: Array = units.keys()
	order_ids.sort_custom(func(a, b): return _supplies_others(a) and not _supplies_others(b))
	for bid in order_ids:
		if not plans.has(bid) or not unit_ready(bid): continue
		for mv in units[bid].commit_plan(plans[bid], plan_ctx(bid)): book(mv["cat"], int(mv["amount"]), bid, mv["note"])
		_deliver_from(bid, plans)
	# the inspector comes today if one was drawn this morning and the business is open
	runners = {}
	for bid in units:
		if not unit_ready(bid): continue
		runners[bid] = begin_runner(bid)
	phase = "day"
	return []

func _supplies_others(bid: String) -> bool:
	for other in world.get("internal", {}):
		if world["internal"][other].get("from", "") == bid: return true
	return false

func _first_ready() -> String:
	for bid in units: if unit_ready(bid): return bid
	return units.keys()[0]

func _deliver_from(bid: String, plans: Dictionary) -> void:
	var b: Business = units[bid]
	# 1. one-off orders due today
	for s in special.duplicate():
		if s["biz"] != bid or int(s["deliver"]) != day: continue
		var got := b.inv.take_fresh(s["product"], int(s["qty"]))
		var rev: int = got["n"] * int(s["price"])
		b.today["b2b_revenue"] += rev; b.today["b2b_cost"] += got["cost"]
		if got["n"] < int(s["qty"]): b.today["b2b_missed"] += 1
		if rev > 0: receivables.append({"id": "sp-%d" % day, "partner_k": s["partner_k"], "amount": rev, "due": day + int(s["terms"]), "late_until": 0, "biz": bid})
		special.erase(s)
	# 2. contracts
	if is_workday():
		for cid in contracts:
			var c: Dictionary = contracts[cid]
			if not c["active"] or world["contracts"][cid]["biz"] != bid: continue
			var rev := 0; var missed := false
			for pid in c["items"]:
				var got := b.inv.take_fresh(pid, int(c["items"][pid]))
				rev += got["n"] * int(c["prices"][pid]); b.today["b2b_cost"] += got["cost"]
				if got["n"] < int(c["items"][pid]): missed = true
				b.today["delivered"][pid] = b.today["delivered"].get(pid, 0) + got["n"]
			b.today["b2b_revenue"] += rev
			if rev > 0: receivables.append({"id": "%s-%d" % [cid, day], "partner_k": world["contracts"][cid]["partner"], "amount": rev, "due": day + int(world["contracts"][cid]["terms_days"]), "late_until": 0, "biz": bid})
			if missed:
				b.today["b2b_missed"] += 1; c["misses"] = int(c["misses"]) + 1
				if int(c["misses"]) >= int(world["contracts"][cid]["max_misses"]):
					c["active"] = false; flags["contract_lost_" + cid] = day
	# 3. our own businesses that buy from this one (the café gets croissants from our bakery)
	for other in plans:
		var internal: Dictionary = world.get("internal", {}).get(other, {})
		if internal.get("from", "") != bid or not units.has(other): continue
		for pid in plans[other].get("transfer_in", {}):
			var want := int(plans[other]["transfer_in"][pid]); if want <= 0: continue
			var src: String = internal["products"].get(pid, pid)
			var got := b.inv.take_fresh(src, want)
			var tp := int(internal["transfer_price"].get(pid, 0))
			units[other].inv.add_goods(pid, got["n"], int(got["quality"]), tp)
			b.today["internal_revenue"] += got["n"] * tp; b.today["internal_cost"] += got["cost"]
			b.today["transfers_out"] += got["n"]; stats["transfers"] += got["n"]
			ledger.add(day, "internal", 0, bid, other, got["n"] * tp)

func begin_runner(bid: String) -> DayRunner:
	var b: Business = units[bid]
	var mk: Dictionary = b.db["marketing"][b.marketing]
	var today_prices := {}
	for pid in b.prices: today_prices[pid] = b.price_today(pid)
	var pmods := {}
	for pid in b.db["products"]: pmods[pid] = mod_value("product_pref_pct", pid)
	var ctx := {"weekday": weekday(), "weather": weather, "reputation": b.reputation, "price_index": Demand.price_index_pct(b.db, today_prices),
		"reach_pct": mk["reach_pct"], "base_bonus": b.effect("base_customers"), "demand_pct": mod_value("demand_pct", bid),
		"promo_product": b.promo_product if b.marketing == "promo" else "", "pref_mult": mk["pref_mult"], "product_pref_pct": pmods,
		"townsfolk": world["townsfolk"], "regulars": regulars, "patience_bonus": b.effect("patience") + int(b.db.get("patience", 0))}
	var custs := Demand.generate(b.db, rng("customers_" + bid), ctx)
	var runner := DayRunner.new(b, custs, Demand.slots_today(b.db, weekday()), b.capacity(mod_value("capacity_pct", bid)))
	runner.on_sale = _on_sale.bind(bid)
	return runner

func forecast(bid: String, plan: Dictionary) -> Vector2i:
	var b: Business = units[bid]
	var mk: Dictionary = b.db["marketing"][plan.get("marketing", "none")]
	var ctx := {"weekday": weekday(), "weather": weather, "reputation": b.reputation, "price_index": Demand.price_index_pct(b.db, plan.get("prices", b.prices)),
		"reach_pct": mk["reach_pct"], "base_bonus": b.effect("base_customers"), "demand_pct": mod_value("demand_pct", bid)}
	var e := Demand.expected(b.db, ctx)
	return Vector2i(maxi(1, roundi(e) - 2), roundi(e) + 2)

# Expected pieces per product today (for the planner's hint). Rough, like a real owner's estimate.
func forecast_items(bid: String, plan: Dictionary) -> Dictionary:
	var b: Business = units[bid]
	var fc := forecast(bid, plan); var n := float(fc.x + fc.y) / 2.0
	var pmods := {}
	for pid in b.db["products"]: pmods[pid] = mod_value("product_pref_pct", pid)
	var w := Demand.product_weights(b.db, {"weekday": weekday(), "weather": weather, "product_pref_pct": pmods})
	var tot := 0
	for pid in w: tot += int(w[pid])
	var out := {}
	for pid in w:
		var q: Array = b.db["products"][pid].get("qty", [1, 1])
		out[pid] = roundi(n * float(w[pid]) / float(maxi(1, tot)) * (float(q[0]) + float(q[1])) / 2.0)
	return out

func _on_sale(o: Dictionary, bid: String) -> void:
	book("revenue", int(o["revenue"]), bid, o["product"])
	profile.sales_count += 1; profile.total_revenue += int(o["revenue"]); profile.total_profit += int(o["revenue"]) - int(o["cost"])
	stats["sold_total"] += int(o["qty"])
	for lv in profile.add_xp(int(o["xp"])): levels_today.append(lv)
	var who: String = o["customer"].get("who", "")
	if who != "":
		var reg: Dictionary = regulars.get(who, {"visits": 0, "sat": 70})
		reg["visits"] = int(reg["visits"]) + 1; reg["sat"] = (int(reg["sat"]) * 2 + int(o["sat"])) / 3
		regulars[who] = reg

# ---------------------------------------------------------------- inspection
func run_inspection(bid: String) -> Dictionary:
	var b: Business = units[bid]; var ins: Dictionary = world["inspection"]
	var old_on_shelf := 0
	for pid in b.db["products"]: old_on_shelf += b.inv.old(pid)
	var checks := [
		{"k": "insp.clean", "ok": b.cleanliness >= int(ins["clean_min"])},
		{"k": "insp.storage", "ok": b.storage_ok(int(ins["storage_units"]))},
		{"k": "insp.expiry", "ok": old_on_shelf <= int(ins["old_on_shelf"])},
		{"k": "insp.equipment", "ok": b.equipment >= int(ins["equip_min"])}]
	var fails := 0
	for c in checks: if not c["ok"]: fails += 1
	var res := {"biz": bid, "checks": checks, "fails": fails, "fine": 0, "closed": false, "passed": fails == 0}
	if fails == 0:
		stats["inspections_passed"] += 1; flags["certificate_" + bid] = day; b.reputation = mini(100, b.reputation + 3)
		ev_state["next_inspection"] = day + rng("insp").int_range(int(ins["every_min"]), int(ins["every_max"]))
	elif fails == 1:
		ev_state["next_inspection"] = day + 3
	else:
		var fine := int(ins["fine_2"]) if fails == 2 else int(ins["fine_3"])
		res["fine"] = fine; book("fine", -fine, bid, "inspection"); b.today["other"] += fine
		b.reputation = maxi(0, b.reputation - 4)
		ev_state["next_inspection"] = day + 4
		if fails >= 3: res["closed"] = true
	inspection_today = ""
	flags["last_inspection"] = res
	return res

# ---------------------------------------------------------------- closing
func close_day() -> Dictionary:
	if inspection_today != "" and runners.has(inspection_today):
		var target := inspection_today
		var res := run_inspection(target)
		if res["closed"]:
			if runners[target].slot == 0: runners[target].run_closed()
			else: runners[target].closed = true
	var sums := {}
	var first_day := day == 1
	var wages_today := 0
	for bid in units:
		if not runners.has(bid):
			continue
		var r: DayRunner = runners[bid]
		if not r.finished():
			if bid != worker and staff_at(bid).is_empty(): r.run_closed()
			else: r.run_auto((staff_rate(bid) + (OWNER_RATE if bid == worker else 0)) * int(units[bid].db.get("service_pct", 100)) / 100)
		var w := 0
		if is_workday() and not r.closed:
			for s in staff_at(bid): w += int(s["wage"])
		wages_today += w
		var weekly := 0
		for k in units[bid].db["weekly_costs"]: weekly += int(units[bid].db["weekly_costs"][k])
		var ctx := {"day": day, "fixed": weekly / 6, "wages": w, "level": level(), "first_day": first_day, "upkeep": world["upkeep"],
			"clean_bonus": 30 if services.has("cleaning") else 0}
		sums[bid] = units[bid].close_day(r, ctx)
		for lv in profile.add_xp(int(sums[bid]["xp_bonus"])): levels_today.append(lv)
		for pid in sums[bid]["sold"]:
			stats["sold_product_day"][pid] = maxi(int(stats["sold_product_day"].get(pid, 0)), int(sums[bid]["sold"][pid]))
	wages_due += wages_today
	# company-level costs: services and loan interest accrue every working day; an overdraft costs a small fee
	var svc := 0
	for sv in services: svc += int(world["services"][sv]["weekly"]) / 6
	var interest := 0
	for l in loans: interest += int(l["interest_week"]) / 6
	var fee := 0
	if profile.cash < 0:
		fee = 2 + (-profile.cash) / 500
		book("bank_fee", -fee, "", "overdraft")
	var s := {"day": day, "weekday_k": weekday_key(), "weather": weather, "units": sums, "services": svc, "interest": interest, "bank_fee": fee,
		"levels": levels_today.duplicate()}
	var profit := -svc - interest - fee
	var revenue := 0
	for bid in sums: profit += int(sums[bid]["profit"]); revenue += int(sums[bid]["revenue"]) + int(sums[bid]["b2b_revenue"])
	s["profit"] = profit; s["revenue"] = revenue
	s["cash_end"] = profile.cash; s["cash_change"] = profile.cash - int(stats.get("day_start_cash", profile.cash))
	s["receivables"] = receivables_total(); s["payables"] = payables_total()
	stats["week_profit"] = int(stats["week_profit"]) + profit; stats["week_revenue"] = int(stats["week_revenue"]) + revenue
	var no_stockout := true
	for bid in sums: if int(sums[bid]["lost_stock"]) > 0 or bool(sums[bid]["closed"]): no_stockout = false
	if no_stockout: flags["no_stockout_day"] = day
	s["coach"] = Coach.lines(s, self)
	last_goals = Goals.update(self)
	s["goals"] = last_goals
	last_summary = s
	# the next day; the eve of the rest day settles the week
	day += 1
	if not is_workday():
		last_week = _settle_week()
		day += 1
	else:
		last_week = {}
	s["week"] = last_week
	phase = "morning"; runners = {}
	ledger.prune(day)
	_snap()
	return s

func _settle_week() -> Dictionary:
	var w := {"day": day, "rent": 0, "wages": wages_due, "services": 0, "loans": 0, "profit": int(stats["week_profit"]), "revenue": int(stats["week_revenue"]),
		"cash_start": int(stats["week_start_cash"]), "units": {}}
	for bid in units:
		var b: Business = units[bid]
		var weekly := 0
		for k in b.db["weekly_costs"]: weekly += int(b.db["weekly_costs"][k])
		var days_open := clampi(day - b.opened_day, 0, 6)
		var rent := weekly * days_open / 6
		book("rent", -rent, bid, "week"); w["rent"] += rent; w["units"][bid] = rent
	book("wages", -wages_due, "", "week"); wages_due = 0
	for sv in services:
		var f := int(world["services"][sv]["weekly"]); book("service", -f, "", sv); w["services"] += f
	for l in loans:
		book("loan_payment", -int(l["weekly"]), "", l["id"]); w["loans"] += int(l["weekly"]); l["weeks_left"] = int(l["weeks_left"]) - 1
	loans = loans.filter(func(l): return int(l["weeks_left"]) > 0)
	# paperwork: every business, partner and loan adds reports; without an accountant some are filed late and fined
	w["fine"] = 0
	if not services.has("accountant"):
		var acc: Dictionary = world["services"]["accountant"]
		var load := units.size() - 1 + loans.size()
		for cid in contracts: if contracts[cid]["active"]: load += 1
		if load > 0 and rng("paperwork").int_range(1, 100) <= int(acc["paperwork_pct"]) * load:
			w["fine"] = int(acc["paperwork_fine"]); book("fine", -w["fine"], "", "paperwork")
	if w["profit"] > 0: stats["profit_weeks"] = int(stats["profit_weeks"]) + 1
	w["cash_end"] = profile.cash
	w["receivables"] = receivables_total(); w["debt"] = debt()
	w["notes"] = Coach.week_lines(w, self)
	stats["week_profit"] = 0; stats["week_revenue"] = 0; stats["week_start_cash"] = profile.cash
	return w

func receivables_total() -> int:
	var t := 0
	for v in receivables: t += int(v["amount"])
	return t

func payables_total() -> int:
	var t := 0
	for p in payables: t += int(p["amount"])
	for o in orders: t += int(o["cost"])
	return t + wages_due

# ---------------------------------------------------------------- buying upgrades
func buy_upgrade(bid: String, uid: String) -> Dictionary:
	var b: Business = units[bid]
	if not b.db["upgrades"].has(uid) or b.upgrades.has(uid): return Loc.m("err.owned")
	if not b.unlocked("upgrades", uid, level()): return Loc.m("err.level", {"n": b.db["upgrades"][uid]["unlock_level"]})
	var cost: int = b.db["upgrades"][uid]["cost"]
	if cost > profile.cash: return Loc.m("err.no_cash", {"amount_m": cost - profile.cash})
	book("upgrade", -cost, bid, uid); b.upgrades[uid] = true
	_snap()
	return {}

func upgrades_count() -> int:
	var t := 0
	for bid in units: t += units[bid].upgrades.size()
	return t

# ---------------------------------------------------------------- suggestions for the player (a starting point, not a decision)
# A sensible morning plan: bake what the forecast suggests plus what partners and our café need, buy in the morning only what is
# still missing, keep the current prices, clean and maintain when it is due. The player adjusts it.
func suggest_plan(bid: String, plans := {}) -> Dictionary:
	var b: Business = units[bid]
	var plan := b.empty_plan()
	if not b.last_plan.is_empty():
		plan["marketing"] = "none"
	var want := forecast_items(bid, plan)
	if b.is_retail():
		# restock to a little above what is expected today, the busiest products first, as far as the shelves allow
		var room := b.capacity(mod_value("capacity_pct", bid)) - b.stock_total()
		var ids: Array = b.db["products"].keys()
		ids.sort_custom(func(x, y): return int(b.db["products"][x]["pref"]) > int(b.db["products"][y]["pref"]))
		for pid in ids:
			var item: String = b.db["products"][pid]["resale"]
			var miss := int(want.get(pid, 0)) * 11 / 10 + 1 - b.inv.stock(pid)
			if miss <= 0: continue
			var st := item_step(bid, item)
			var n := mini((miss + st - 1) / st * st, room / st * st)
			if n > 0: plan["buy_now"][item] = n; room -= n
	elif bid == "cafe":
		var src: String = world.get("internal", {}).get("cafe", {}).get("from", "")
		if owns(src):
			plan["transfer_in"] = {"croissant": maxi(0, int(want.get("croissant", 0)) - b.inv.stock("croissant"))}
		var drinks := 0
		for pid in b.db["products"]: if b.is_mto(pid): drinks += int(want.get(pid, 0))
		for iid in b.ingredient_ids():
			var miss := drinks + 4 - b.inv.units(iid)
			if miss > 0: plan["buy_now"][iid] = (miss + item_step(bid, iid) - 1) / item_step(bid, iid) * item_step(bid, iid)
		var ck := int(want.get("cookie", 0)) - b.inv.stock("cookie")
		if ck > 0 and not owns(src): plan["buy_now"]["cookie"] = (ck + 9) / 10 * 10
		if not owns(src):
			var cr := int(want.get("croissant", 0)) - b.inv.stock("croissant")
			if cr > 0: plan["buy_now"]["croissant"] = (cr + 4) / 5 * 5
	else:
		var reserved := reserved_for(bid, plans)
		var cap := b.capacity(mod_value("capacity_pct", bid)); var used := 0
		var ids: Array = b.db["products"].keys()
		ids.sort_custom(func(x, y): return int(want.get(x, 0)) > int(want.get(y, 0)))
		for pid in ids:
			if not b.is_baked(pid): continue
			var per: int = b.db["products"][pid]["cap"]
			var n := int(want.get(pid, 0)) + int(reserved.get(pid, 0)) - b.inv.old(pid)
			n = clampi(n, 0, (cap - used) / maxi(1, per))
			plan["bake"][pid] = n; used += n * per
		var need := b.bake_needs(plan)
		for iid in need:
			var miss: int = int(need[iid]) - b.inv.units(iid)
			if miss > 0: plan["buy_now"][iid] = miss
	plan["deep_clean"] = b.cleanliness < 55
	plan["maintenance"] = b.equipment < 50
	return plan

# What to order from a supplier today for tomorrow: about a day of ingredients beyond what is on hand.
func suggest_order(bid: String) -> Dictionary:
	var b: Business = units[bid]
	var want := forecast_items(bid, b.empty_plan())
	var need := {}
	for pid in b.db["products"]:
		var pr: Dictionary = b.db["products"][pid]
		var n := int(want.get(pid, 0)) * 12 / 10 + 2
		for cid in contracts:
			if contracts[cid]["active"] and world["contracts"][cid]["biz"] == bid: n += int(contracts[cid]["items"].get(pid, 0))
		if bid == "bakery" and owns("cafe") and pid == "croissant": n += int(forecast_items("cafe", units["cafe"].empty_plan()).get("croissant", 0))
		for iid in pr.get("recipe", {}): need[iid] = int(need.get(iid, 0)) + int(pr["recipe"][iid]) * n
		if pr.has("resale") and not (bid == "cafe" and owns(world.get("internal", {}).get("cafe", {}).get("from", "")) and pid == "croissant"):
			need[pr["resale"]] = int(need.get(pr["resale"], 0)) + n
	var items := {}
	for iid in need:
		var have := b.inv.units(iid) if b.db["ingredients"].has(iid) else b.inv.stock(b.product_for_input(iid))
		# a shop sells today what is on its shelves: only what is left after today's expected sales is there tomorrow
		if b.is_retail(): have = maxi(0, have - int(want.get(b.product_for_input(iid), 0)))
		for o in orders_for(bid): have += int(o["items"].get(iid, 0))
		var miss: int = int(need[iid]) - have
		if miss > 0:
			var st := item_step(bid, iid)
			items[iid] = (miss + st - 1) / st * st
	if b.is_retail() and not items.is_empty():
		# keep it within the shelves: shrink every line by the same share, in whole steps
		var pending := 0
		for o in orders_for(bid): for k in o["items"]: pending += int(o["items"][k])
		var room := maxi(0, b.capacity(mod_value("capacity_pct", bid)) - projected_stock(bid) - pending)
		var total := 0
		for iid in items: total += int(items[iid])
		if total > room:
			# the busiest products first, in whole steps, until the shelves are full
			var order: Array = items.keys()
			order.sort_custom(func(x, y): return int(b.db["products"][b.product_for_input(x)]["pref"]) > int(b.db["products"][b.product_for_input(y)]["pref"]))
			for iid in order:
				var st2 := item_step(bid, iid)
				var n2 := mini(int(items[iid]), room / st2 * st2)
				if n2 > 0: items[iid] = n2; room -= n2
				else: items.erase(iid)
	return items
