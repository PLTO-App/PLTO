class_name Coach
extends RefCounted
# Turns the numbers of a finished day into at most three short lines explaining why it went that way.
# The wording lives in content/common/coach_he.json, so it can be edited without touching code.

static func lines(summary: Dictionary, db: Dictionary, strings: Dictionary) -> Array:
	var out: Array = []   # [priority, text]
	var pname := func(pid: String) -> String: return db["products"][pid]["name"] if db["products"].has(pid) else ""
	if summary["lost_stock"] > 0:
		out.append([90, strings["stockout"].format({"product": pname.call(summary["top_stockout"]), "n": summary["lost_stock"]})])
	if summary["lost_price"] >= 2:
		out.append([70, strings["price_high"].format({"n": summary["lost_price"]})])
	if summary["walkouts"] > 0:
		out.append([80, strings["patience"].format({"n": summary["walkouts"]})])
	if summary["waste_pieces"] > 0:
		out.append([75, strings["waste"].format({"n": summary["waste_pieces"], "amount": UiMoney.fmt(summary["waste_cost"])})])
	if summary["marketing_id"] != "none" and (summary["marketing_cost"] > 0 or summary["campaign_customers"] > 0):
		var name: String = db["marketing"][summary["marketing_id"]]["name"]
		var key := "marketing" if summary["campaign_revenue"] >= summary["marketing_cost"] else "marketing_loss"
		out.append([60, strings[key].format({"campaign": name, "n": summary["campaign_customers"], "cost": UiMoney.fmt(summary["marketing_cost"]), "revenue": UiMoney.fmt(summary["campaign_revenue"])})])
	if absi(summary["profit"] - summary["cash_change"]) >= 80:
		out.append([65, strings["cash_vs_profit"].format({"profit": UiMoney.fmt(summary["profit"]), "cash": UiMoney.fmt(summary["cash_change"])})])
	if summary["cash_end"] < 200:
		out.append([85, strings["cash_low"].format({"cash": UiMoney.fmt(summary["cash_end"])})])
	if summary["profit"] < 0:
		out.append([55, strings["loss"].format({"amount": UiMoney.fmt(-summary["profit"])})])
	elif summary["avg_sat"] >= 70 and summary["served"] > 0:
		out.append([40, strings["great"].format({"profit": UiMoney.fmt(summary["profit"])})])
	if summary["first_day"]: out.append([10, strings["first"]])
	out.sort_custom(func(a, b): return a[0] > b[0])
	var res: Array = []
	for i in mini(3, out.size()): res.append(out[i][1])
	return res
