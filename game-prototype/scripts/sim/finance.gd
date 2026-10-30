class_name Finance
extends RefCounted
# Where the money of a new business comes from, and what it costs. The player puts a funding plan together before signing the lease:
# savings (what the player's own background gives, shown openly), help from the family (a gift or a soft loan, limited by what they
# have and how much they trust the player), a partner (who takes a share of the profit) and a bank (which reviews the plan).
# Nothing is handed out: the cash box starts at zero and every shekel is booked from one of these sources. Loans stay with the
# player when the business fails (see fail and carry). No screen here: the screens and the balance bots use these functions.
#
# Company.finance = {bg, savings, exp (years in the field), trust (family), family_cap, family_used, failures, invested}
# plan = {bg, biz, fmt, savings, family_gift, family_loan, partner: {amount, share}, bank: {amount, weeks, weekly, total, cost, guarantor}, guarantor, last}
# Every lender is named on its loan (`lender`), so other lenders and other kinds of money (taxes, public funds) can be added later
# without changing how a loan is paid.

static func cfg(co: Company) -> Dictionary: return co.content.finance

static func background(co: Company, id: String) -> Dictionary: return cfg(co)["backgrounds"][id]

static func savings_of(co: Company, id: String) -> int:
	var b := background(co, id); return int(b["years"]) * int(b["yearly"])

# The profile of a new owner: savings and experience from the background, the family from the seed. Nothing is in the cash box yet.
static func start_profile(co: Company, bg_id: String) -> void:
	var b := background(co, bg_id)
	var r := co.rng("family_" + bg_id)
	co.finance = {"bg": bg_id, "savings": savings_of(co, bg_id), "exp": int(b["exp"]), "trust": r.int_range(int(b["trust"][0]), int(b["trust"][1])),
		"family_cap": r.int_range(int(b["family"][0]), int(b["family"][1])) / 100 * 100, "family_used": 0, "failures": 0, "invested": 0}

static func new_plan(co: Company, biz: String, fmt: String) -> Dictionary:
	return {"bg": co.finance["bg"], "biz": biz, "fmt": fmt, "savings": 0, "family_gift": 0, "family_loan": 0, "partner": {"amount": 0, "share": 0},
		"bank": {}, "guarantor": false, "last": {}}

# What the plan needs: the setup cost, and a reserve of a few weeks of fixed costs so the first weeks are not a gamble.
static func need(co: Company, biz: String, fmt: String) -> Dictionary:
	var f := co.format_def(biz, fmt)
	var db := co.content.business_db(biz, fmt)
	var weekly := 0
	for k in db["weekly_costs"]: weekly += int(db["weekly_costs"][k])
	var reserve := weekly * int(cfg(co)["plan"]["reserve_weeks"])
	return {"cost": int(f["setup_cost"]), "weekly_fixed": weekly, "reserve": reserve, "total": int(f["setup_cost"]) + reserve}

static func raised(plan: Dictionary) -> int:
	return int(plan["savings"]) + int(plan["family_gift"]) + int(plan["family_loan"]) + int(plan["partner"]["amount"]) + int(plan["bank"].get("amount", 0))

# Own money in the business as a bank sees it: savings, gifts and the partner's share capital; a family loan counts for half.
static func equity(plan: Dictionary) -> int:
	return int(plan["savings"]) + int(plan["family_gift"]) + int(plan["partner"]["amount"]) + int(plan["family_loan"]) / 2

# ---------------------------------------------------------------- the family
static func family_left(co: Company, plan: Dictionary) -> int:
	return maxi(0, int(co.finance["family_cap"]) - int(co.finance["family_used"]) - int(plan["family_gift"]) - int(plan["family_loan"]))

# What the relatives can give, as a gift (less) or as a loan (more), on top of what is already in the plan.
static func family_limits(co: Company, plan: Dictionary, kind: String) -> int:
	var other := int(plan["family_loan" if kind == "gift" else "family_gift"])
	var left := maxi(0, int(co.finance["family_cap"]) - int(co.finance["family_used"]) - other)
	return left * int(cfg(co)["family"]["gift_share"]) / 100 / 100 * 100 if kind == "gift" else left

# Asks the family for an amount: they give what they can. Returns {given, said_k, max}.
static func family_ask(co: Company, plan: Dictionary, kind: String, amount: int) -> Dictionary:
	var mx := family_limits(co, plan, kind)
	var given := clampi(amount, 0, mx)
	plan["family_gift" if kind == "gift" else "family_loan"] = given
	plan["bank"] = {}                                    # a changed plan needs a new look from the bank
	var said := "fin.say.family_yes" if given >= amount else "fin.say.family_less"
	if amount > 0 and given == 0: said = "fin.say.family_no"
	return {"given": given, "max": mx, "said_k": said}

# Whether a relative will stand as a guarantor for a bank loan: they need to trust the player and be able to cover it.
static func family_guarantee(co: Company, plan: Dictionary) -> Dictionary:
	var f: Dictionary = cfg(co)["family"]
	var amount := int(plan["bank"].get("amount", 0))
	if int(co.finance["trust"]) < int(f["guarantee_min_trust"]): return {"ok": false, "said_k": "fin.say.guar_no_trust"}
	if int(co.finance["family_cap"]) - int(co.finance["family_used"]) < amount / 2: return {"ok": false, "said_k": "fin.say.guar_no_cap"}
	return {"ok": true, "said_k": "fin.say.guar_yes"}

# ---------------------------------------------------------------- a partner
# The most a partner may put in: beyond that he would own too much of the business.
static func partner_max(co: Company, plan: Dictionary) -> int:
	var own := int(plan["savings"]) + int(plan["family_gift"])
	var p: Dictionary = cfg(co)["partner"]
	return own * int(p["max_share"]) / maxi(1, int(p["premium"]) - int(p["max_share"])) / 100 * 100

static func partner_share(co: Company, plan: Dictionary, amount: int) -> int:
	var own := int(plan["savings"]) + int(plan["family_gift"])
	var p: Dictionary = cfg(co)["partner"]
	if amount <= 0: return 0
	return clampi(int(p["premium"]) * amount / maxi(1, own + amount), int(p["min_share"]), int(p["max_share"]))

static func partner_ask(co: Company, plan: Dictionary, amount: int) -> Dictionary:
	var mx := partner_max(co, plan)
	var given := clampi(amount, 0, mx)
	plan["partner"] = {"amount": given, "share": partner_share(co, plan, given)}
	plan["bank"] = {}
	return {"given": given, "max": mx, "share": plan["partner"]["share"]}

# ---------------------------------------------------------------- the bank
static func expected_profit(co: Company, fmt: String, exp_years: int) -> int:
	var e: Dictionary = cfg(co)["experience_factor"]
	var factor := mini(int(e["max"]), int(e["base"]) + int(e["per_year"]) * exp_years)
	return int(cfg(co)["expected_weekly_profit"][fmt if fmt != "" else "regular"]) * factor / 100

static func cost_pct(co: Company, weeks: int, surcharge: int) -> int:
	var b: Dictionary = cfg(co)["bank"]
	return int(b["base_cost"]) + weeks / int(b["term_div"]) + surcharge

# Weekly payment on a loan with a flat cost for the term (rounded up to a whole shekel).
static func payment(co: Company, amount: int, weeks: int, surcharge: int) -> Dictionary:
	var total := amount * (100 + cost_pct(co, weeks, surcharge)) / 100
	return {"amount": amount, "weeks": weeks, "weekly": (total + weeks - 1) / maxi(1, weeks), "total": total, "cost": total - amount}

static func _existing_weekly(co: Company) -> int:
	var t := 0
	for l in co.loans: t += int(l["weekly"])
	return t

# The bank looks at the plan (or, with the business running, at the business) and answers a request for `amount` over `weeks`.
# verdict: full | partial | terms | need_guarantor | reject. offer: the loan on offer. reasons: what weighed, for or against.
static func bank_review(co: Company, plan: Dictionary, amount: int, weeks: int, guarantor: bool, running := false) -> Dictionary:
	var b: Dictionary = cfg(co)["bank"]; var P: Dictionary = b["points"]
	var fmt: String; var eq: int; var exp_years: int; var weekly_fixed: int; var funds_beyond_cost: int; var collateral: int
	var partner_pct := 0
	var cap_plan := 1 << 30          # a lender does not lend more than the plan needs (a running business is judged on its figures instead)
	for p in co.partners: partner_pct += int(p["share"])
	if running:
		var u: Business = co.units[co.worker] if co.units.has(co.worker) else co.units[co.units.keys()[0]]
		fmt = u.format if u.format != "" else "regular"
		weekly_fixed = 0
		for k in u.db["weekly_costs"]: weekly_fixed += int(u.db["weekly_costs"][k])
		eq = maxi(0, co.profile.cash - co.debt()) + int(co.finance.get("invested", 0)) / 2
		exp_years = int(co.finance["exp"]) + co.week_profits.size() / 52
		funds_beyond_cost = co.profile.cash + amount
		collateral = int(co.format_def(u.id, fmt).get("setup_cost", 0)) * int(b["collateral_pct"]) / 100
	else:
		fmt = plan["fmt"]; var nd := need(co, plan["biz"], fmt)
		weekly_fixed = nd["weekly_fixed"]; eq = equity(plan); exp_years = int(co.finance["exp"])
		funds_beyond_cost = raised(plan) - int(plan["bank"].get("amount", 0)) + amount - int(nd["cost"])
		collateral = int(nd["cost"]) * int(b["collateral_pct"]) / 100
		cap_plan = maxi(0, int(nd["total"]) * int(b["plan_slack_pct"]) / 100 - (raised(plan) - int(plan["bank"].get("amount", 0)))) / 100 * 100
	var expected := expected_profit(co, fmt, exp_years)
	if running and not co.week_profits.is_empty():
		var s := 0
		for w in co.week_profits: s += int(w)
		expected = maxi(0, s / co.week_profits.size())
	var existing := _existing_weekly(co)
	var capacity := expected * int(b["capacity_share_pct"]) / 100 - existing - expected * partner_pct / 100
	var pay0 := payment(co, amount, weeks, 0)
	var coverage := 1000 if int(pay0["weekly"]) <= 0 else capacity * 100 / int(pay0["weekly"])
	var eq_pct := eq * 100 / maxi(1, eq + amount)
	var res_weeks_x10 := maxi(0, funds_beyond_cost) * 10 / maxi(1, weekly_fixed)
	var pts_equity := mini(int(P["equity"]), eq_pct * int(P["equity"]) / int(b["equity_full_pct"]))
	var pts_exp := mini(int(P["experience"]), exp_years * int(b["exp_pts_per_year"]))
	var pts_cap := clampi(coverage * int(P["capacity"]) / int(b["coverage_full_pct"]), 0, int(P["capacity"]))
	var pts_res := clampi(res_weeks_x10 * int(P["reserve"]) / (int(b["reserve_weeks_full"]) * 10), 0, int(P["reserve"]))
	var pts_sec := (int(b["guarantor_pts"]) if guarantor else 0) + mini(int(b["collateral_pts"]), collateral * 100 / maxi(1, amount) * int(b["collateral_pts"]) / 100)
	var pen_debt := mini(int(b["debt_penalty_max"]), existing * int(b["debt_penalty_max"]) / maxi(1, expected * 30 / 100))
	var pen_fail := int(b["failure_penalty"]) * mini(2, int(co.finance["failures"]))
	var score := pts_equity + pts_exp + pts_cap + pts_res + pts_sec - pen_debt - pen_fail
	var tier := "reject"
	if score >= int(b["approve_full"]): tier = "full"
	elif score >= int(b["approve_partial"]): tier = "partial"
	elif score >= int(b["counter"]): tier = "counter"
	var out := {"verdict": "reject", "tier": tier, "score": score, "requested": amount, "weeks": weeks, "offer": {}, "reasons": [], "capacity": capacity, "coverage": coverage,
		"equity": eq, "equity_pct": eq_pct, "expected": expected, "reserve_weeks_x10": res_weeks_x10}
	var R: Array = out["reasons"]
	R.append({"k": "fin.why.equity", "p": {"pct": eq_pct, "need_pct": int(b["equity_full_pct"])}, "good": eq_pct >= int(b["equity_full_pct"])})
	R.append({"k": "fin.why.experience", "p": {"n": exp_years}, "good": exp_years >= 3})
	R.append({"k": "fin.why.capacity", "p": {"weekly_m": int(pay0["weekly"]), "cap_m": maxi(0, capacity)}, "good": coverage >= 100})
	R.append({"k": "fin.why.reserve", "p": {"n": res_weeks_x10 / 10}, "good": res_weeks_x10 >= 20})
	if existing > 0: R.append({"k": "fin.why.debts", "p": {"weekly_m": existing}, "good": false})
	if pen_fail > 0: R.append({"k": "fin.why.failure", "p": {}, "good": false})
	if guarantor: R.append({"k": "fin.why.guarantor", "p": {}, "good": true})
	if amount <= 0 or tier == "reject": return out
	var sur: int = int(b["surcharge"][tier])
	var cap_equity := eq * int(b["cap_mult_pct"][tier]) / 100
	var cap_pay := capacity * weeks * 100 / (100 + cost_pct(co, weeks, sur))
	var approved := mini(amount, mini(cap_plan, mini(cap_equity, maxi(0, cap_pay))))
	if cap_plan < amount: R.append({"k": "fin.why.plan_cap", "p": {"amount_m": cap_plan}, "good": false})
	if approved >= amount:
		out["offer"] = payment(co, amount, weeks, sur)
		out["verdict"] = "need_guarantor" if (tier == "counter" and not guarantor) else "full"
		if tier == "counter" and not guarantor: R.append({"k": "fin.why.needs_guarantor", "p": {}, "good": false})
		return out
	# a longer term lowers the weekly payment: another way to the same amount
	for t in b["terms"]:
		if int(t) <= weeks: continue
		var cp := capacity * int(t) * 100 / (100 + cost_pct(co, int(t), sur))
		if mini(amount, mini(cap_plan, mini(cap_equity, maxi(0, cp)))) >= amount:
			out["offer"] = payment(co, amount, int(t), sur); out["verdict"] = "terms"; out["weeks"] = int(t)
			if tier == "counter" and not guarantor: out["verdict"] = "need_guarantor"
			return out
	if approved >= maxi(int(b["min_amount"]), amount * int(b["min_partial_pct"]) / 100):
		approved = approved / 100 * 100
		out["offer"] = payment(co, approved, weeks, sur); out["verdict"] = "partial"
		R.append({"k": ("fin.why.cap_equity" if cap_equity <= maxi(0, cap_pay) else "fin.why.cap_capacity") if approved < cap_plan else "fin.why.plan_offer", "p": {"amount_m": approved}, "good": false})
		return out
	R.append({"k": "fin.why.too_much", "p": {}, "good": false})
	return out

# The offer is taken: it goes into the plan (and a guarantee, if the family stands behind it).
static func take_offer(plan: Dictionary, review: Dictionary, guarantor: bool) -> void:
	var o: Dictionary = review["offer"]
	plan["bank"] = {"amount": int(o["amount"]), "weeks": int(o["weeks"]), "weekly": int(o["weekly"]), "total": int(o["total"]), "cost": int(o["cost"]), "guarantor": guarantor}
	plan["guarantor"] = guarantor

# ---------------------------------------------------------------- committing the plan
# Every shekel arrives from its source: savings and gifts are the owner's capital, the rest are loans and a partner.
# Returns {} or a message. The business is then set up with begin_business.
static func commit(co: Company, plan: Dictionary) -> Dictionary:
	var nd := need(co, plan["biz"], plan["fmt"])
	if raised(plan) < int(nd["cost"]): return Loc.m("err.no_cash", {"amount_m": int(nd["cost"]) - raised(plan)})
	co.book("capital", int(plan["savings"]), "", "savings"); co.finance["invested"] = int(plan["savings"]) + int(plan["family_gift"]) + int(plan["partner"]["amount"])
	if int(plan["family_gift"]) > 0: co.book("capital", int(plan["family_gift"]), "", "family_gift")
	if int(plan["family_loan"]) > 0:
		var weeks := int(cfg(co)["family"]["loan_weeks"]); var amt := int(plan["family_loan"])
		co.book("loan", amt, "", "family")
		co.loans.append({"id": "family_%d" % co.loans.size(), "weekly": (amt + weeks - 1) / weeks, "weeks_left": weeks, "interest_week": 0, "source": "family", "lender": "family", "amount": amt, "guarantor": false})
	if int(plan["partner"]["amount"]) > 0:
		co.book("capital", int(plan["partner"]["amount"]), "", "partner")
		co.partners.append({"id": "partner_%d" % co.partners.size(), "amount": int(plan["partner"]["amount"]), "share": int(plan["partner"]["share"])})
	var bk: Dictionary = plan["bank"]
	if not bk.is_empty() and int(bk["amount"]) > 0:
		co.book("loan", int(bk["amount"]), "", "bank")
		co.loans.append({"id": "bank_%d" % co.loans.size(), "weekly": int(bk["weekly"]), "weeks_left": int(bk["weeks"]), "interest_week": int(bk["cost"]) / maxi(1, int(bk["weeks"])),
			"source": "bank", "lender": "bank", "amount": int(bk["amount"]), "guarantor": bool(bk.get("guarantor", false))})
	co.finance["family_used"] = int(co.finance["family_used"]) + int(plan["family_gift"]) + int(plan["family_loan"])
	var f: Dictionary = cfg(co)["family"]
	if int(plan["family_gift"]) > 0: co.finance["trust"] = clampi(int(co.finance["trust"]) + int(f["trust_gift"]), 0, 100)
	if int(plan["family_loan"]) > 0: co.finance["trust"] = clampi(int(co.finance["trust"]) + int(f["trust_loan"]), 0, 100)
	if bool(bk.get("guarantor", false)): co.finance["trust"] = clampi(int(co.finance["trust"]) + int(f["guarantee_trust"]), 0, 100)
	co._snap()
	return {}

# A later loan with the business running (the same review, from the live figures).
static func take_running_loan(co: Company, review: Dictionary, guarantor: bool) -> Dictionary:
	var o: Dictionary = review["offer"]
	if o.is_empty(): return Loc.m("err.setup_unknown")
	co.book("loan", int(o["amount"]), "", "bank")
	co.loans.append({"id": "bank_%d" % co.loans.size(), "weekly": int(o["weekly"]), "weeks_left": int(o["weeks"]), "interest_week": int(o["cost"]) / maxi(1, int(o["weeks"])),
		"source": "bank", "lender": "bank", "amount": int(o["amount"]), "guarantor": guarantor})
	co._snap()
	return {}

# ---------------------------------------------------------------- failure: the cash box is empty and cannot be filled
# There is no rescue: when the account stays below the overdraft limit for three mornings in a row, the bank freezes it and the
# business closes. The loans stay. (A business with stock and customers can still climb out in those days.)
static func insolvent(co: Company) -> bool:
	if co.track != "owner" or co.units.is_empty() or co.in_setup() or co.failed: return false
	if co.profile.cash > -co.overdraft_limit():
		co.finance["frozen"] = 0
		return false
	co.finance["frozen"] = int(co.finance.get("frozen", 0)) + 1
	return int(co.finance["frozen"]) >= 3

static func fail(co: Company) -> void:
	var guaranteed := 0; var rest := 0
	for l in co.loans:
		var owed := int(l["weekly"]) * int(l["weeks_left"])
		if bool(l.get("guarantor", false)): guaranteed += owed
		else: rest += owed
	co.failed = true
	co.failure = {"day": co.day, "debt": guaranteed + rest, "guaranteed": guaranteed, "cash": co.profile.cash, "loans": co.loans.size()}
	co.phase = "morning"

# What goes with the player into the next try: the loans (a guaranteed bank loan is now owed to the family), and a record.
static func carry(co: Company) -> Dictionary:
	var loans: Array = []
	for l in co.loans:
		var c: Dictionary = l.duplicate(true)
		if bool(c.get("guarantor", false)):
			var owed := int(c["weekly"]) * int(c["weeks_left"]); var weeks := 60
			c = {"id": "family_%d" % loans.size(), "weekly": (owed + weeks - 1) / weeks, "weeks_left": weeks, "interest_week": 0, "source": "family", "lender": "family", "amount": owed, "guarantor": false}
		loans.append(c)
	var trust := int(co.finance["trust"])
	if co.failure.get("guaranteed", 0) > 0: trust = int(cfg(co)["family"]["failed_trust"])
	return {"loans": loans, "failures": int(co.finance["failures"]) + 1, "trust": trust, "family_used": int(co.finance["family_used"]), "exp": int(co.finance["exp"])}

# ---------------------------------------------------------------- plans played by style (balance runs, tests, the automatic player)
# own | family | partner | bank | reckless
static func auto_plan(co: Company, biz: String, fmt: String, style: String) -> Dictionary:
	var plan := new_plan(co, biz, fmt)
	var nd := need(co, biz, fmt)
	plan["savings"] = int(co.finance["savings"])
	match style:
		"family":
			family_ask(co, plan, "loan", maxi(0, int(nd["total"]) - raised(plan)))
		"partner":
			partner_ask(co, plan, maxi(0, int(nd["total"]) - raised(plan)))
		"bank":
			var want := maxi(0, int(nd["total"]) - raised(plan))
			var weeks := int(cfg(co)["bank"]["default_term"])
			var g := false
			var rv := bank_review(co, plan, want, weeks, false)
			if rv["verdict"] == "need_guarantor":
				plan["bank"] = {"amount": want}
				var fg := family_guarantee(co, plan)
				plan["bank"] = {}
				if fg["ok"]:
					g = true; rv = bank_review(co, plan, want, weeks, true)
			if not rv["offer"].is_empty() and rv["verdict"] != "need_guarantor": take_offer(plan, rv, g)
		"reckless":
			# every source as far as it goes: the family's whole loan, the biggest partner, and the most the bank will give (with a guarantee when it helps)
			family_ask(co, plan, "loan", 1000000)
			partner_ask(co, plan, 1000000)
			for want in [30000, 20000, 12000, 8000, 5000, 3000, 2000, 1000]:
				var g2 := false
				var rv2 := bank_review(co, plan, want, 52, false)
				if rv2["verdict"] in ["need_guarantor", "reject", "partial"]:
					plan["bank"] = {"amount": want}
					var fg2 := family_guarantee(co, plan)
					plan["bank"] = {}
					if fg2["ok"]:
						var alt := bank_review(co, plan, want, 52, true)
						if not alt["offer"].is_empty() and int(alt["offer"]["amount"]) >= (0 if rv2["offer"].is_empty() else int(rv2["offer"]["amount"])): g2 = true; rv2 = alt
				if not rv2["offer"].is_empty() and rv2["verdict"] != "need_guarantor":
					take_offer(plan, rv2, g2); break
	return plan
