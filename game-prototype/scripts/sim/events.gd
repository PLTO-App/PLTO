class_name EventEngine
extends RefCounted
# Morning events from content/events.json: what happens in the town and in the businesses before they open. Some come because of
# the state of the business (a machine that was not maintained breaks down, a partner pays late), some are offers (a contract,
# a catering order), some are chance (prices, a holiday, road works). At most two cards a morning, the urgent ones first.
# Each card has choices; every choice has a price and consequences, written in the content file.

const MAX_CARDS := 2

static func _ok_common(co: Company, e: Dictionary) -> bool:
	var id: String = e["id"]
	if e.has("biz") and not co.unit_ready(e["biz"]): return false
	if co.day < int(e.get("min_day", 1)) or co.day > int(e.get("max_day", 100000)): return false
	if co.level() < int(e.get("min_level", 1)): return false
	if e.has("weekdays") and not (co.weekday() in e["weekdays"]): return false
	if e.has("min_rep"):
		var best := 0
		for bid in co.units: best = maxi(best, co.units[bid].reputation)
		if best < int(e["min_rep"]): return false
	var last := int(co.ev_state["last"].get(id, -1000))
	if co.day - last < int(e.get("cooldown", 0)): return false
	if e.has("max_times") and int(co.ev_state["times"].get(id, 0)) >= int(e["max_times"]): return false
	return true

static func _mark(co: Company, id: String) -> void:
	co.ev_state["last"][id] = co.day
	co.ev_state["times"][id] = int(co.ev_state["times"].get(id, 0)) + 1

static func _card(e: Dictionary, p := {}, choices := []) -> Dictionary:
	var ch: Array = []
	if choices.is_empty():
		for c in e.get("choices", []): ch.append({"label_k": c["label"], "cost": int(c.get("cost", 0)), "note_k": c.get("note", "")})
	else: ch = choices
	return {"id": e["id"], "kind": e.get("kind", "generic"), "title_k": e["title"], "body_k": e["body"], "p": p, "who": e.get("who", ""), "choices": ch, "biz": e.get("biz", "")}

static func morning(co: Company, report: Dictionary) -> Array:
	var cards: Array = []
	var defs: Array = co.content.events
	var by_id := {}
	for e in defs: by_id[e["id"]] = e
	var r := co.rng("events")
	# 1. a partner who did not pay on time
	if not report.get("late", []).is_empty() and by_id.has("payment_late") and _ok_common(co, by_id["payment_late"]):
		var v: Dictionary = report["late"][0]
		cards.append(_card(by_id["payment_late"], {"partner_k": v["partner_k"], "amount_m": v["amount"]},
			[{"label_k": "ev.late.remind", "cost": 0, "note_k": "ev.late.remind.note"}, {"label_k": "ev.late.wait", "cost": 0, "note_k": "ev.late.wait.note"}]))
		cards[-1]["data"] = {"ids": report["late"].map(func(x): return x["id"])}
		_mark(co, "payment_late")
	# 2. machines that were not looked after break down
	for bid in co.units:
		if not co.unit_ready(bid): continue
		var b: Business = co.units[bid]
		var below := int(co.world["upkeep"]["breakdown_below"])
		if b.equipment < below and r.int_range(1, 100) <= (below - b.equipment) * 3:
			for e in defs:
				if e.get("trigger", "") == "breakdown" and e.get("biz", "") == bid and _ok_common(co, e):
					cards.append(_card(e)); _mark(co, e["id"]); break
	# 3. the health inspector: a surprise visit during the day (no card in the morning)
	if co.day >= int(co.ev_state["next_inspection"]) and co.inspection_today == "":
		var target := ""
		if co.unit_ready(co.worker) and co.units[co.worker].db.get("kind", "") == "food": target = co.worker
		else:
			for bid in co.units:
				if co.unit_ready(bid) and co.units[bid].db.get("kind", "") == "food": target = bid; break
		co.inspection_today = target
	# 4. offers from partners
	for cid in co.world["contracts"]:
		if cards.size() >= MAX_CARDS: break
		var c: Dictionary = co.world["contracts"][cid]
		if co.contracts.has(cid) and co.contracts[cid]["active"]: continue
		if not co.owns(c["biz"]) or co.level() < int(c["unlock_level"]) or co.day < int(c["min_day"]): continue
		var e: Dictionary = by_id.get("contract_" + cid, {})
		if e.is_empty() or not _ok_common(co, e): continue
		var p := {"partner_k": c["partner"], "terms": c["terms_days"]}
		for pid in c["items"]: p["qty_" + pid] = c["items"][pid]; p["price_" + pid + "_m"] = c["prices"][pid]
		var card := _card(e, p, [{"label_k": "ev.contract.accept", "cost": 0, "note_k": "ev.contract.accept.note"},
			{"label_k": "ev.contract.counter", "cost": 0, "note_k": "ev.contract.counter.note"},
			{"label_k": "ev.contract.decline", "cost": 0, "note_k": "ev.contract.decline.note"}])
		card["data"] = {"contract": cid}
		cards.append(card); _mark(co, e["id"])
	# 5. staff
	if cards.size() < MAX_CARDS and not co.staff.is_empty():
		var e: Dictionary = by_id.get("staff_raise", {})
		var s: Dictionary = co.staff[r.int_range(0, co.staff.size() - 1)]
		if not e.is_empty() and _ok_common(co, e) and co.day - int(s["hired_day"]) >= 10 and int(s["asked_raise"]) == 0 and r.int_range(1, 100) <= int(e.get("weight", 5)) * 3:
			var card := _card(e, {"name_k": co.staff_def(s["id"])["name"], "amount_m": 30},
				[{"label_k": "ev.raise.yes", "cost": 0, "note_k": "ev.raise.yes.note"}, {"label_k": "ev.raise.no", "cost": 0, "note_k": "ev.raise.no.note"}])
			card["data"] = {"staff": s["id"]}; s["asked_raise"] = co.day
			cards.append(card); _mark(co, "staff_raise")
	if cards.size() < MAX_CARDS and not co.staff.is_empty():
		var e: Dictionary = by_id.get("staff_sick", {})
		var s: Dictionary = co.staff[r.int_range(0, co.staff.size() - 1)]
		if not e.is_empty() and _ok_common(co, e) and r.int_range(1, 100) <= int(e.get("weight", 5)) * 2:
			s["sick_day"] = co.day
			var card := _card(e, {"name_k": co.staff_def(s["id"])["name"]}, [{"label_k": "ev.ok", "cost": 0, "note_k": "ev.sick.note"}])
			card["data"] = {"staff": s["id"]}
			cards.append(card); _mark(co, "staff_sick")
	# 6. one chance event, some mornings
	if cards.size() < MAX_CARDS and r.int_range(1, 100) <= 45:
		var pool: Array = []; var weights: Array = []
		for e in defs:
			if e.get("kind", "generic") != "generic" or e.has("trigger"): continue
			if e["id"].begins_with("contract_"): continue
			if not _ok_common(co, e): continue
			pool.append(e); weights.append(int(e.get("weight", 1)))
		if not pool.is_empty():
			var e: Dictionary = pool[r.weighted(weights)]
			cards.append(_card(e)); _mark(co, e["id"])
	return cards

# Applies a choice. Returns {"note": message to show}.
static func resolve(co: Company, ev: Dictionary, choice: int) -> Dictionary:
	var ch: Dictionary = ev["choices"][clampi(choice, 0, ev["choices"].size() - 1)]
	var note: Variant = Loc.m(ch.get("note_k", "")) if str(ch.get("note_k", "")) != "" else {}
	match ev["kind"]:
		"contract_offer":
			var cid: String = ev["data"]["contract"]; var c: Dictionary = co.world["contracts"][cid]
			if choice == 0:
				co.contracts[cid] = {"active": true, "misses": 0, "prices": c["prices"].duplicate(), "items": c["items"].duplicate(), "since": co.day}
			elif choice == 1:
				var best := 0
				for bid in co.units: best = maxi(best, co.units[bid].reputation)
				if best >= int(c["counter_rep"]):
					var pr := {}
					for pid in c["prices"]: pr[pid] = int(c["prices"][pid]) * (100 + int(c["counter_pct"])) / 100
					co.contracts[cid] = {"active": true, "misses": 0, "prices": pr, "items": c["items"].duplicate(), "since": co.day}
					note = Loc.m("ev.contract.counter.yes")
				else:
					note = Loc.m("ev.contract.counter.no")
			return {"note": note}
		"staff_raise":
			var s := co.staff_entry(ev["data"]["staff"])
			if not s.is_empty():
				if choice == 0: s["wage"] = int(s["wage"]) + 30
				else: s["skill"] = maxi(30, int(s["skill"]) - 8)
			return {"note": note}
		"payment_late":
			if choice == 0:
				for v in co.receivables:
					if v["id"] in ev["data"]["ids"]: v["late_until"] = co.day + 1
			return {"note": note}
		"staff_sick":
			return {"note": note}
	# generic: pay, then apply the effects
	var cost := int(ch.get("cost", 0))
	var biz: String = ev.get("biz", "")
	if cost > 0:
		co.book("event", -cost, biz, ev["id"])
		if biz != "" and co.units.has(biz): co.units[biz].today["other"] += cost
	var defs: Array = co.content.events
	var src: Dictionary = {}
	for e in defs: if e["id"] == ev["id"]: src = e
	var effects: Array = src.get("choices", [])[clampi(choice, 0, src.get("choices", []).size() - 1)].get("effects", []) if not src.is_empty() and not src.get("choices", []).is_empty() else []
	for fx in effects:
		if fx.has("rep") and co.units.has(fx["rep"]["biz"]):
			var b: Business = co.units[fx["rep"]["biz"]]; b.reputation = clampi(b.reputation + int(fx["rep"]["delta"]), 0, 100)
		if fx.has("mod"):
			co.add_mod(fx["mod"]["kind"], str(fx["mod"].get("target", fx["mod"].get("biz", "*"))), int(fx["mod"]["value"]), int(fx["mod"]["days"]))
		if fx.has("equip") and co.units.has(fx["equip"]["biz"]): co.units[fx["equip"]["biz"]].equipment = int(fx["equip"]["set"])
		if fx.has("clean") and co.units.has(fx["clean"]["biz"]): co.units[fx["clean"]["biz"]].cleanliness = int(fx["clean"]["set"])
		if fx.has("order"):
			var o: Dictionary = fx["order"]
			co.special.append({"biz": o["biz"], "product": o["product"], "qty": int(o["qty"]), "price": int(o["price"]), "terms": int(o["terms_days"]),
				"partner_k": o["partner"], "deliver": co.day + 1})
		if fx.has("xp"): co.profile.add_xp(int(fx["xp"]))
		if fx.has("flag"): co.flags[fx["flag"]] = co.day
	return {"note": note}
