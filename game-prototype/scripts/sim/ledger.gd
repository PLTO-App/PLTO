class_name Ledger
extends RefCounted
# The itemized journal of every cash movement. Cash on hand must always equal the starting cash plus the sum of the entries:
# that check is what keeps the money honest.

const KEEP_DAYS := 14

var entries: Array = []        # {day, cat, amount (signed whole shekels), note}

func add(day: int, cat: String, amount: int, note := "") -> void:
	entries.append({"day": day, "cat": cat, "amount": amount, "note": note})

func total(day := -1, cat := "") -> int:
	var t := 0
	for e in entries:
		if (day < 0 or e["day"] == day) and (cat == "" or e["cat"] == cat): t += int(e["amount"])
	return t

func prune(current_day: int) -> void:
	entries = entries.filter(func(e): return e["day"] > current_day - KEEP_DAYS)

func to_array() -> Array:
	return entries.duplicate(true)

func from_array(a: Array) -> void:
	entries = []
	for e in a: entries.append({"day": int(e["day"]), "cat": str(e["cat"]), "amount": int(e["amount"]), "note": str(e.get("note", ""))})
