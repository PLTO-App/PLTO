extends Node
# Autoload "Game": the one place the game's systems live. Holds the content, the player's profile, the story flags and the sounds,
# and records a sale. It knows nothing about the 3D world or the screen: those listen to its signals.

signal sale_completed(result: Dictionary)
signal level_reached(level: int)

var content := ContentDb.new()
var profile := Profile.new()
var sfx: Sfx
var flags := {}
var business_id := "bakery"
var save_path := "user://save.json"

func _ready() -> void:
	content.load_all()
	for e in content.errors: push_error("content: " + e)
	sfx = Sfx.new(); add_child(sfx)
	if "--autotest" in OS.get_cmdline_user_args() or "--coretest" in OS.get_cmdline_user_args():
		save_path = "user://autotest_save.json"; SaveStore.erase(save_path)
	load_game()

func business() -> Dictionary:
	return content.businesses[business_id]

func load_game() -> void:
	var data := SaveStore.read(save_path)
	if data.is_empty():
		profile.reset(content); flags = {}
	else:
		profile.from_dict(data.get("profile", {}), content); flags = data.get("flags", {})

func save_game() -> bool:
	return SaveStore.write(save_path, {"profile": profile.to_dict(), "flags": flags})

func has_progress() -> bool:
	return profile.sales_count > 0

func reset_progress() -> void:
	profile.reset(content); flags = {}; save_game()

# Records one sale: applies the money, experience and reputation, saves, and announces it.
func complete_sale(product_id: String, ctx := {}) -> Dictionary:
	var b := business()
	var product: Dictionary = b["products"][product_id]
	var first := profile.sales_count == 0
	var r := SaleCalc.compute(product, ctx, b["reputation_per_sale"], first, content.first_sale_xp)
	profile.sales_count += 1; profile.total_revenue += r["revenue"]; profile.total_profit += r["profit"]
	profile.add_cash(r["profit"])
	var gained := profile.add_xp(r["xp_total"])
	profile.add_reputation(r["reputation"])
	r["product_id"] = product_id; r["levels"] = gained
	save_game()
	sale_completed.emit(r)
	for lv in gained: level_reached.emit(lv)
	return r

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST: save_game()
