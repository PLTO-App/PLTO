extends SceneTree
# Development only: tests and balance simulations for the business simulation (no screen, no 3D).
# godot --headless --path game-prototype --script dev/test_sim.gd
var fails := 0

func check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok: fails += 1

func _init() -> void:
	var content := ContentDb.new(); content.load_all()
	check("content loads without errors", content.errors.is_empty(), str(content.errors))
	var prof := Profile.new(); var biz := Business.new(content, "bakery", prof); biz.new_game(false, 7)
	check("new game starts with 500 shekels", prof.cash == 500 and biz.day == 1)
	# plan validation
	var bad := {"supplier": "wholesale", "buy": {}, "bake": {"strawberry_cake": 6}, "prices": {}, "marketing": "none"}
	check("oven over capacity is rejected", not biz.validate_plan(bad).is_empty(), str(biz.validate_plan(bad)))
	var poor := {"supplier": "wholesale", "buy": {"base": 200}, "bake": {}, "prices": {}, "marketing": "none"}
	check("buying more than the cash is rejected", not biz.validate_plan(poor).is_empty())
	check("a locked supplier is rejected", not biz.validate_plan({"supplier": "family", "buy": {}, "bake": {}, "prices": {}, "marketing": "none"}).is_empty())
	check("a locked marketing option is rejected", not biz.validate_plan({"supplier": "wholesale", "buy": {}, "bake": {}, "prices": {}, "marketing": "flyers"}).is_empty())
	check("missing ingredients are rejected", not biz.validate_plan({"supplier": "wholesale", "buy": {}, "bake": {"strawberry_cake": 3}, "prices": {}, "marketing": "none"}).is_empty())
	check("an empty plan is valid", biz.validate_plan({"supplier": "wholesale", "buy": {}, "bake": {}, "prices": {}, "marketing": "none"}).is_empty())
	# determinism
	var a := Business.new(content, "bakery", Profile.new()); a.new_game(false, 42)
	var b := Business.new(content, "bakery", Profile.new()); b.new_game(false, 42)
	var ca := a.begin_day().customers; var cb := b.begin_day().customers
	check("the same seed gives the same customers", str(ca) == str(cb), "n=%d" % ca.size())
	var c: Business = Business.new(content, "bakery", Profile.new()); c.new_game(false, 43)
	check("a different seed gives different customers", str(c.begin_day().customers) != str(ca))
	# one full day with a simple plan
	var plan := {"supplier": "wholesale", "buy": {}, "bake": {"croissant": 5, "carrot_cake": 1}, "prices": {}, "marketing": "none"}
	for iid in content.businesses["bakery"]["ingredients"]: plan["buy"][iid] = 0
	check("a starter plan is valid", a.commit_plan(plan).is_empty(), str(a.validate_plan(plan)))
	var runner := a.begin_day(); runner.run_auto(); var s := a.close_day(runner)
	check("day 1 closes with sales", s["served"] > 0 and s["revenue"] > 0, "served=%d revenue=%d profit=%d cash=%d" % [s["served"], s["revenue"], s["profit"], a.profile.cash])
	check("profit adds up: revenue - cogs - waste - marketing - fixed", s["profit"] == s["revenue"] - s["cogs"] - s["waste_cost"] - s["marketing_cost"] - s["fixed"])
	check("cash on hand equals start plus the ledger", 500 + a.ledger.total() == a.profile.cash, "%d vs %d" % [500 + a.ledger.total(), a.profile.cash])
	check("all money values are whole numbers", typeof(s["revenue"]) == TYPE_INT and typeof(s["profit"]) == TYPE_INT and typeof(s["cash_end"]) == TYPE_INT)
	check("the first day gives experience and the first-day bonus", s["xp_bonus"] >= 25, str(s["xp_bonus"]))
	check("the coach has something to say", s["coach"].size() >= 1 and s["coach"].size() <= 3, str(s["coach"]))
	check("the day advanced", a.day == 2 and a.phase == "morning")
	# ageing: croissants do not keep, cakes sell old at a discount next day
	var inv := Inventory.new(); inv.reset({"base": 20, "dairy": 20, "sweet": 20}, ["base", "dairy", "sweet"], ["croissant", "carrot_cake"])
	inv.bake("croissant", {"base": 1, "dairy": 1}, 3); inv.bake("carrot_cake", {"base": 3, "dairy": 2, "sweet": 1}, 2)
	var w := inv.close_day({"croissant": 1, "carrot_cake": 2})
	check("unsold croissants are thrown away, cakes age", inv.stock("croissant") == 0 and inv.goods["carrot_cake"]["old"] == 2 and w.size() == 1)
	w = inv.close_day({"croissant": 1, "carrot_cake": 2})
	check("old cakes are thrown away after a second day", inv.stock("carrot_cake") == 0 and w.size() == 1)
	# save round trip
	var d := a.to_dict(); var e := Business.new(content, "bakery", Profile.new()); e.new_game(false, 1); e.from_dict(JSON.parse_string(JSON.stringify(d)))
	check("a business survives saving and loading", e.day == a.day and e.profile.cash == a.profile.cash and e.inv.units("base") == a.inv.units("base") and e.prices == a.prices)
	check("upgrade: the sign is bought and effects apply", _upgrade(content))
	_balance(content)
	print("RESULT failures=%d" % fails)
	quit(1 if fails > 0 else 0)

func _upgrade(content: ContentDb) -> bool:
	var p := Profile.new(); var bz := Business.new(content, "bakery", p); bz.new_game(false, 3)
	p.cash = 1000
	return bz.buy_upgrade("sign") == "" and p.cash == 600 and bz.buy_upgrade("sign") != "" and bz.buy_upgrade("oven") != ""

func _balance(content: ContentDb) -> void:
	print("--- balance: 30 days x 6 seeds per strategy")
	var strategies := {
		"idle (does nothing)": {"idle": true},
		"bakes the oven full": {"max_bake": true},
		"balanced, market price": {},
		"balanced, family supplier": {"supplier": "family"},
		"balanced + social post": {"marketing": "social_post"},
		"balanced + flyers (day 3+)": {"marketing": "flyers"},
		"balanced + promo": {"marketing": "promo"},
		"overpriced (150%)": {"price_pct": 150},
		"underpriced (65%)": {"price_pct": 65},
		"balanced + upgrades": {"upgrades": true},
		"upgrades + social post": {"upgrades": true, "marketing": "social_post"},
		"upgrades + flyers": {"upgrades": true, "marketing": "flyers"},
	}
	var res := {}
	for name in strategies:
		var sum := {"profit_per_day": 0, "cash": 0, "rep": 0, "served": 0, "lost": 0, "waste": 0, "bankrupt_days": 0}
		var errors: Array = []; var min_cash := 999999
		for sd in 6:
			var r := SimPolicies.play(content, 100 + sd, 30, strategies[name])
			for k in sum: sum[k] += r[k]
			min_cash = mini(min_cash, r["min_cash"]); errors.append_array(r["errors"])
		for k in sum: sum[k] /= 6
		res[name] = sum
		print("%-28s profit/day %5d | cash after 30d %6d | rep %3d | served %3d lost %3d | waste %5d | lowest cash %5d | broke days %d" % [name, sum["profit_per_day"], sum["cash"], sum["rep"], sum["served"], sum["lost"], sum["waste"], min_cash, sum["bankrupt_days"]])
		if not errors.is_empty(): check("no invariant errors in '%s'" % name, false, str(errors.slice(0, 3)))
	check("doing nothing loses money (fixed costs)", res["idle (does nothing)"]["profit_per_day"] < 0)
	check("a balanced owner makes a profit", res["balanced, market price"]["profit_per_day"] > 100, str(res["balanced, market price"]["profit_per_day"]))
	check("a balanced owner wastes less than one who bakes blindly, with about the same profit", res["balanced, market price"]["waste"] < res["bakes the oven full"]["waste"] and res["balanced, market price"]["profit_per_day"] * 100 >= res["bakes the oven full"]["profit_per_day"] * 90)
	check("overpricing is worse than a fair price", res["overpriced (150%)"]["profit_per_day"] < res["balanced, market price"]["profit_per_day"])
	check("underpricing is worse than a fair price", res["underpriced (65%)"]["profit_per_day"] < res["balanced, market price"]["profit_per_day"])
	check("no strategy runs away: cash after 30 days stays reasonable", res["balanced + upgrades"]["cash"] < 40000, str(res["balanced + upgrades"]["cash"]))
	check("a profitable business keeps its customers (reputation does not collapse)", res["balanced, market price"]["rep"] >= 40, str(res["balanced, market price"]["rep"]))
	check("the promotion helps but does not dominate (under 25 percent better)", res["balanced + promo"]["profit_per_day"] < res["balanced, market price"]["profit_per_day"] * 125 / 100, "%d vs %d" % [res["balanced + promo"]["profit_per_day"], res["balanced, market price"]["profit_per_day"]])
