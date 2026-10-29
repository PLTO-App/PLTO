extends Node
# Development only: saving and loading through the Game autoload (run as a scene so the autoload exists).
# godot --headless --path . res://dev/test_save.tscn
var fails := 0

func check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok: fails += 1

func _ready() -> void:
	Game.save_path = "user://test_save.json"; Game.test_mode = true
	# a save written by version 0.4
	SaveStore.write(Game.save_path, {"schema": 2, "profile": {"cash": 1107, "xp": 250, "level": 2, "reputation": 51, "sales_count": 13},
		"business": {"day": 3, "seed": 9, "prices": {"croissant": 35}, "profile": {"cash": 1107, "xp": 250}}, "flags": {}})
	Game.load_game()
	var co: Company = Game.co
	check("a 0.4 save loads: experience and level are kept", co.profile.xp == 250 and co.profile.level == 2, "xp=%d level=%d" % [co.profile.xp, co.profile.level])
	check("a 0.4 save loads: cash is at least the new starting cash", co.profile.cash == 3000)
	check("a 0.4 save loads: the books match the cash", co.ledger.balance() == co.profile.cash)
	check("the player is told about the new version", Game.migrated_from == 4)
	var saved := SaveStore.read(Game.save_path)
	check("the migrated game is saved in the new format", saved.has("company") and int(saved["schema"]) == 3)
	# a morning that already ran is not run again after a restart (no double deliveries)
	co.place_order("bakery", "wholesale", {"base": 20})
	co.start_morning(); co.commit_day({"bakery": co.units["bakery"].empty_plan()}, "bakery"); co.close_day()
	co.start_morning(); Game.save_game()
	var base_units: int = co.units["bakery"].inv.units("base")
	Game.load_game()
	check("after a restart the same morning is kept, not run again", Game.co.morning_day == Game.co.day and Game.co.units["bakery"].inv.units("base") == base_units)
	check("pending events survive the restart", Game.co.pending_events.size() == co.pending_events.size())
	# a file that is cut off or not a save at all: the game starts fresh and the bad file is set aside, not deleted
	var f := FileAccess.open(Game.save_path, FileAccess.WRITE); f.store_string('{"version":1,"schema":3,"company":{"day":4,"profi'); f.close()
	Game.load_game()
	check("a cut-off save starts a new game", Game.co.day == 1 and Game.co.profile.cash == 3000)
	check("the broken file is kept aside", FileAccess.file_exists(Game.save_path + ".bad") and not FileAccess.file_exists(Game.save_path))
	DirAccess.remove_absolute(Game.save_path + ".bad")
	# a save written by a different version of the format is also set aside
	SaveStore.write(Game.save_path, {"schema": 3, "company": Game.co.snapshot}); var raw := FileAccess.get_file_as_string(Game.save_path).replace('"version":1', '"version":99')
	f = FileAccess.open(Game.save_path, FileAccess.WRITE); f.store_string(raw); f.close()
	check("an unknown format version is not read", SaveStore.read(Game.save_path).is_empty())
	DirAccess.remove_absolute(Game.save_path + ".bad")
	# the weather of a morning that is loaded again is the same as before
	Game.load_game(); var w: String = Game.co.start_morning()["weather"]; Game.save_game(); Game.load_game()
	check("a loaded morning keeps its weather", Game.co.weather == w, "%s vs %s" % [Game.co.weather, w])
	SaveStore.erase(Game.save_path)
	print("RESULT failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
