class_name Profile
extends RefCounted
# The player's progress: cash (fictional shekels), experience, level, reputation (0 to 100). Whole numbers only.
# No UI, no 3D: it reports what happened through signals and return values.

signal changed

var db: ContentDb
var cash := 0
var xp := 0
var level := 1
var reputation := 50
var sales_count := 0
var total_revenue := 0
var total_profit := 0

func reset(content: ContentDb) -> void:
	db = content
	cash = content.start_cash; xp = 0; level = 1; reputation = content.start_reputation
	sales_count = 0; total_revenue = 0; total_profit = 0
	changed.emit()

func add_cash(amount: int) -> void:
	cash += amount; changed.emit()

# Adds experience and returns the levels newly reached (for example [2] or [2, 3]).
func add_xp(amount: int) -> Array[int]:
	var gained: Array[int] = []
	xp += maxi(0, amount)
	var lv := db.level_for_xp(xp)
	while level < lv:
		level += 1; gained.append(level)
	changed.emit()
	return gained

func add_reputation(delta: int) -> void:
	reputation = clampi(reputation + delta, db.rep_min, db.rep_max); changed.emit()

func level_floor() -> int:
	return db.levels[mini(level - 1, db.levels.size() - 1)]

# Experience needed to go from this level to the next. 0 at the top level.
func level_span() -> int:
	if level >= db.levels.size(): return 0
	return db.levels[level] - db.levels[level - 1]

func xp_in_level() -> int:
	return xp - level_floor()

func to_dict() -> Dictionary:
	return {"cash": cash, "xp": xp, "level": level, "reputation": reputation, "sales_count": sales_count, "total_revenue": total_revenue, "total_profit": total_profit}

func from_dict(d: Dictionary, content: ContentDb) -> void:
	db = content
	cash = int(d.get("cash", content.start_cash)); xp = maxi(0, int(d.get("xp", 0)))
	reputation = clampi(int(d.get("reputation", content.start_reputation)), content.rep_min, content.rep_max)
	level = content.level_for_xp(xp)       # always derived, so an edited save cannot hold an impossible level
	sales_count = maxi(0, int(d.get("sales_count", 0))); total_revenue = int(d.get("total_revenue", 0)); total_profit = int(d.get("total_profit", 0))
	changed.emit()
