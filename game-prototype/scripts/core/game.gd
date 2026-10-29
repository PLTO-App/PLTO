extends Node
# Autoload "Game": the one place the game's systems live. Holds the content, the player's profile, the business simulation, the story
# flags and the sounds, and saves the game. It knows nothing about the 3D world or the screen: those read it and call its methods.

var content := ContentDb.new()
var profile := Profile.new()
var biz: Business
var sfx: Sfx
var flags := {}
var business_id := "bakery"
var save_path := "user://save.json"
var test_mode := false

func _ready() -> void:
	content.load_all()
	for e in content.errors: push_error("content: " + e)
	sfx = Sfx.new(); add_child(sfx)
	if "--autotest" in OS.get_cmdline_user_args() or "--coretest" in OS.get_cmdline_user_args():
		save_path = "user://autotest_save.json"; SaveStore.erase(save_path); test_mode = true
	load_game()

func business() -> Dictionary:
	return content.businesses[business_id]

func load_game() -> void:
	biz = Business.new(content, business_id, profile)
	var data := SaveStore.read(save_path)
	var fresh_seed := 4242 if test_mode else int(Time.get_unix_time_from_system()) % 1000003
	if data.is_empty():
		biz.new_game(false, fresh_seed); flags = {}
	elif data.has("business"):
		biz.from_dict(data["business"]); flags = data.get("flags", {})
	else:   # a save from version 0.3: keep cash, experience, level and reputation, start the simulation fresh
		profile.from_dict(data.get("profile", {}), content); biz.new_game(true, fresh_seed); flags = data.get("flags", {})

# Saves the last safe point of the business (a mid-day state is never written), plus the story flags.
func save_game() -> bool:
	return SaveStore.write(save_path, {"schema": 2, "business": biz.snapshot, "profile": biz.snapshot["profile"], "flags": flags})

func has_progress() -> bool:
	return biz.day > 1 or profile.sales_count > 0

func reset_progress() -> void:
	biz.new_game(false, int(Time.get_unix_time_from_system()) % 1000003); flags = {}; save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST: save_game()
