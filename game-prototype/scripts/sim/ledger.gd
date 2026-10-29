class_name Ledger
extends RefCounted
# The itemized journal of every cash movement of the company. Cash on hand must always equal the starting cash plus the sum of the
# entries: that check is what keeps the money honest. Each entry names the business it belongs to ("" for the company itself).
# Internal moves between our own businesses are recorded on both sides with no cash effect (amount 0 and a "value" field).

const KEEP_DAYS := 21

var entries: Array = []        # {day, cat, amount (signed whole shekels), biz, note, value}
var start_cash := 0
var pruned_total := 0          # the sum of entries already pruned, so the reconciliation still holds

func add(day: int, cat: String, amount: int, biz := "", note := "", value := 0) -> void:
	entries.append({"day": day, "cat": cat, "amount": amount, "biz": biz, "note": note, "value": value})

func total(day := -1, cat := "", biz := "*") -> int:
	var t := 0
	for e in entries:
		if (day < 0 or e["day"] == day) and (cat == "" or e["cat"] == cat) and (biz == "*" or e["biz"] == biz): t += int(e["amount"])
	return t

func total_since(first_day: int, cat := "") -> int:
	var t := 0
	for e in entries:
		if e["day"] >= first_day and (cat == "" or e["cat"] == cat): t += int(e["amount"])
	return t

func balance() -> int:
	return start_cash + pruned_total + total()

func prune(current_day: int) -> void:
	var keep: Array = []
	for e in entries:
		if e["day"] > current_day - KEEP_DAYS: keep.append(e)
		else: pruned_total += int(e["amount"])
	entries = keep

func to_dict() -> Dictionary:
	return {"start_cash": start_cash, "pruned_total": pruned_total, "entries": entries.duplicate(true)}

func from_dict(d) -> void:
	entries = []
	if d is Array:    # an older save kept only the list
		d = {"entries": d}
	start_cash = int(d.get("start_cash", 0)); pruned_total = int(d.get("pruned_total", 0))
	for e in d.get("entries", []):
		entries.append({"day": int(e["day"]), "cat": str(e["cat"]), "amount": int(e["amount"]), "biz": str(e.get("biz", "")), "note": str(e.get("note", "")), "value": int(e.get("value", 0))})
