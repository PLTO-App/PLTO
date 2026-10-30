extends SceneTree
# Development only: how the bank answers across backgrounds, sizes, requests and guarantees; and how funding plans fare once the business runs.
# godot --headless --path game-prototype --script dev/sim_finance.gd [-- bank|plans|failure]
var content: ContentDb

func _init() -> void:
	Loc.setup("he"); content = ContentDb.new(); content.load_all()
	var mode := "bank"
	for a in OS.get_cmdline_user_args(): mode = a
	match mode:
		"bank": _bank()
	quit(0)

func _co(seed_value: int, bg: String) -> Company:
	var co := Company.new(content); co.start_owner(seed_value, bg, false); return co

func _bank() -> void:
	print("--- the bank's answer: background x size x request (weeks 52), savings all in, seed 1")
	for bg in ["fresh", "junior", "mid", "other"]:
		for fmt in ["small", "regular"]:
			var co := _co(1, bg)
			var nd := Finance.need(co, "bakery", fmt)
			var plan := Finance.new_plan(co, "bakery", fmt); plan["savings"] = int(co.finance["savings"])
			print("== %s (savings %d, family up to %d) %s: cost %d + reserve %d = %d" % [bg, co.finance["savings"], co.finance["family_cap"], fmt, nd["cost"], nd["reserve"], nd["total"]])
			for amount in [2000, 5000, 10000, 20000, 40000]:
				for g in [false, true]:
					var r := Finance.bank_review(co, plan, amount, 52, g)
					var o: Dictionary = r["offer"]
					print("   ask %5d %s -> %-14s score %3d | equity %3d%% | coverage %4d%% | offer %s" % [amount, "+guarantor" if g else "          ", r["verdict"], r["score"], r["equity_pct"], r["coverage"],
						("%d over %d weeks, %d a week, total %d" % [o["amount"], o["weeks"], o["weekly"], o["total"]]) if not o.is_empty() else "-"])
