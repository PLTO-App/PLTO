extends Node
# Autoload "Game": the one place the game's systems live. Holds the content, the company simulation, the player's settings and the
# sounds, and saves the game. It knows nothing about the 3D world or the screen: those read it and call its methods.

const SETTINGS_PATH := "user://settings.json"

var content := ContentDb.new()
var co: Company
var profile: Profile
var sfx: Sfx
var settings := {"sound": true, "music": true, "locale": Loc.DEFAULT}
var save_path := "user://save.json"
var test_mode := false
var migrated_from := 0
var fresh_start := false      # a new game with no save yet: the player chooses how to begin (see Main._choose_start)

func _ready() -> void:
	_load_settings()
	Loc.setup(settings["locale"])
	content.load_all()
	for e in content.errors: push_error("content: " + e)
	sfx = Sfx.new(); add_child(sfx)
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args or "--coretest" in args:
		save_path = "user://autotest_save.json"; SaveStore.erase(save_path); test_mode = true
	load_game()
	apply_settings()

func business(bid := "") -> Dictionary:
	return content.businesses[bid if bid != "" else co.worker]

func load_game() -> void:
	co = Company.new(content); profile = co.profile
	var data := SaveStore.read(save_path)
	fresh_start = false
	var fresh_seed := 4242 if test_mode else int(Time.get_unix_time_from_system()) % 1000003
	if data.is_empty():
		co.new_game(fresh_seed)
		fresh_start = not test_mode or "owner=1" in OS.get_cmdline_user_args()
	elif data.has("company"):
		co.from_dict(data["company"])
	else:
		# a save from version 0.3 or 0.4: keep experience, level and the cash (at least the new starting cash); the town starts fresh
		migrated_from = 4 if data.has("business") else 3
		var old: Dictionary = data.get("profile", {})
		co.new_game(fresh_seed)
		co.profile.from_dict(old, content)
		co.profile.cash = maxi(int(old.get("cash", 0)), int(content.world["start"]["cash"]))
		co.ledger = Ledger.new(); co.ledger.start_cash = co.profile.cash
		co.stats["week_start_cash"] = co.profile.cash
		co._snap()
		save_game()

# Saves the last safe point (a morning). A day in progress is never written: if the app closes mid-day, the day starts again.
func save_game() -> bool:
	return SaveStore.write(save_path, {"schema": 4, "company": co.snapshot})

func has_progress() -> bool:
	return co.day > 1 or profile.sales_count > 0

func reset_progress() -> void:
	co.new_game(int(Time.get_unix_time_from_system()) % 1000003); save_game()
	fresh_start = true

# The owner track: an empty rented space. The first business, its size and the loan (or "") were chosen by the player.
func start_owner(biz: String, fmt: String, loan_id: String) -> Dictionary:
	co.start_owner(int(Time.get_unix_time_from_system()) % 1000003)
	var e := co.begin_business(biz, fmt, loan_id)
	if not e.is_empty(): co.new_game(int(Time.get_unix_time_from_system()) % 1000003); return e
	fresh_start = false
	save_game()
	return {}

# ---------------------------------------------------------------- settings (sound, music, language)
func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH): return
	var d = JSON.parse_string(FileAccess.open(SETTINGS_PATH, FileAccess.READ).get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		for k in settings: if d.has(k): settings[k] = d[k]

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(settings))
	apply_settings()

func apply_settings() -> void:
	if sfx != null:
		sfx.enabled = bool(settings["sound"]); sfx.set_music(bool(settings["music"]))
		if not sfx.enabled: sfx.amb.stop()
		elif sfx._amb_name != "" and not sfx.amb.playing:
			var n := sfx._amb_name
			sfx._amb_name = ""; sfx.play_ambience(n)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if co != null: save_game()
