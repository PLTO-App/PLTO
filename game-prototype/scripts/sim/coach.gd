class_name Coach
extends RefCounted
# Turns the numbers of a finished day (and week) into a few short lines that explain why it went that way: Shira, the mentor, after a
# day; Michal, the accountant, after a week when the company uses her service. Lines are messages ({k, p}), worded in
# locale/strings.csv, so they can be edited (and translated) without touching code.

const SHOWN := 3

static func lines(s: Dictionary, co: Company) -> Array:
	var out: Array = []   # [priority, message]
	var many: bool = s["units"].size() > 1
	for bid in s["units"]:
		var u: Dictionary = s["units"][bid]; var db: Dictionary = co.units[bid].db
		var tag := {"biz_k": db["name"]}
		var pre := func(k: String, p: Dictionary) -> Dictionary:
			var q := p.duplicate(); q.merge(tag)
			return Loc.m(k + (".at" if many else ""), q)
		if u["closed"]:
			out.append([95, pre.call("coach.closed", {})]); continue
		if u["lost_stock"] > 0 and u["top_stockout"] != "":
			out.append([90, pre.call("coach.stockout", {"product_k": db["products"][u["top_stockout"]]["name"], "n": u["lost_stock"]})])
		if u["walkouts"] > 0: out.append([80, pre.call("coach.patience", {"n": u["walkouts"]})])
		if u["b2b_missed"] > 0: out.append([88, pre.call("coach.b2b_missed", {})])
		if u["waste_pieces"] > 0: out.append([72, pre.call("coach.waste", {"n": u["waste_pieces"], "amount_m": u["waste_cost"]})])
		if u["lost_price"] >= 2: out.append([70, pre.call("coach.price_high", {"n": u["lost_price"]})])
		if u["marketing_id"] != "none" and (u["marketing_cost"] > 0 or u["campaign_customers"] > 0):
			var key := "coach.marketing" if u["campaign_revenue"] >= u["marketing_cost"] else "coach.marketing_loss"
			out.append([60, pre.call(key, {"campaign_k": db["marketing"][u["marketing_id"]]["name"], "n": u["campaign_customers"], "cost_m": u["marketing_cost"], "revenue_m": u["campaign_revenue"]})])
		if u["cleanliness"] < 45: out.append([66, pre.call("coach.dirty", {})])
		if u["equipment"] < 45: out.append([64, pre.call("coach.equipment", {})])
		if u["internal_revenue"] > 0 and not co.flags.has("told_internal"):
			co.flags["told_internal"] = s["day"]; out.append([68, Loc.m("coach.internal", {"amount_m": u["internal_revenue"]})])
	if s["bank_fee"] > 0: out.append([86, Loc.m("coach.overdraft", {"fee_m": s["bank_fee"]})])
	if s["cash_end"] < 300: out.append([84, Loc.m("coach.cash_low", {"cash_m": s["cash_end"]})])
	if absi(s["profit"] - s["cash_change"]) >= 150:
		out.append([62, Loc.m("coach.cash_vs_profit", {"profit_m": s["profit"], "cash_m": s["cash_change"]})])
	if not co.flags.has("told_accrual"):
		co.flags["told_accrual"] = s["day"]; out.append([58, Loc.m("coach.accrual")])
	if s["receivables"] >= 600 and not co.flags.has("told_receivables"):
		co.flags["told_receivables"] = s["day"]; out.append([63, Loc.m("coach.receivables", {"amount_m": s["receivables"]})])
	if s["profit"] < 0: out.append([55, Loc.m("coach.loss", {"amount_m": -s["profit"]})])
	elif s["profit"] > 0: out.append([40, Loc.m("coach.great", {"profit_m": s["profit"]})])
	if s["day"] == 1: out.append([10, Loc.m("coach.first")])
	out.sort_custom(func(a, b): return a[0] > b[0])
	var res: Array = []
	for i in mini(SHOWN, out.size()): res.append(out[i][1])
	return res

static func week_lines(w: Dictionary, co: Company) -> Array:
	var out: Array = []
	var acc := co.services.has("accountant")
	if w["profit"] >= 0: out.append(Loc.m("week.profit", {"amount_m": w["profit"]}))
	else: out.append(Loc.m("week.loss", {"amount_m": -w["profit"]}))
	out.append(Loc.m("week.paid", {"rent_m": w["rent"], "wages_m": w["wages"]}))
	if int(w.get("fine", 0)) > 0: out.append(Loc.m("week.fine_paperwork", {"amount_m": w["fine"]}))
	if acc:
		if w["receivables"] > 0: out.append(Loc.m("week.acc_receivables", {"amount_m": w["receivables"]}))
		if w["debt"] > 0: out.append(Loc.m("week.acc_debt", {"amount_m": w["debt"]}))
		var margin: int = int(w["profit"]) * 100 / maxi(1, int(w["revenue"]))
		out.append(Loc.m("week.acc_margin", {"pct": margin}))
	else:
		if co.level() >= int(co.world["services"]["accountant"]["unlock_level"]) and not co.flags.has("told_accountant"):
			co.flags["told_accountant"] = w["day"]; out.append(Loc.m("week.suggest_accountant"))
	return out
