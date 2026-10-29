extends SceneTree
# Development only: checks the game systems without the 3D world or the screen.
# godot --headless --path game-prototype --script dev/test_core.gd -- --coretest
var fails := 0

func check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok: fails += 1

func _init() -> void:
	var db := ContentDb.new(); db.load_all()
	check("content loads without errors", db.errors.is_empty(), str(db.errors))
	check("level 1 at 0 xp, level 2 at 100", db.level_for_xp(0) == 1 and db.level_for_xp(99) == 1 and db.level_for_xp(100) == 2)
	check("level capped at table end", db.level_for_xp(999999) == db.levels.size())
	var pr := Profile.new(); pr.reset(db)
	check("start values", pr.cash == 0 and pr.level == 1 and pr.reputation == 50)
	var lv := pr.add_xp(105)
	check("105 xp reaches level 2 and reports it", lv == [2] and pr.level == 2 and pr.xp_in_level() == 5 and pr.level_span() == 150, "span=%d" % pr.level_span())
	check("a big gain can pass several levels", pr.add_xp(400) == [3, 4], str(pr.level))
	pr.add_reputation(500); check("reputation clamps at 100", pr.reputation == 100)
	pr.add_reputation(-500); check("reputation clamps at 0", pr.reputation == 0)
	# save round trip
	var path := "user://core_test_save.json"; SaveStore.erase(path)
	pr.cash = 1234
	check("save writes", SaveStore.write(path, {"profile": pr.to_dict()}))
	var back := Profile.new(); back.from_dict(SaveStore.read(path)["profile"], db)
	check("save round trip keeps cash, xp and level", back.cash == 1234 and back.xp == pr.xp and back.level == pr.level)
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string('{"version":1,"profile":{"xp":120,"level":99,"cash":5}}'); f.close()
	var edited := Profile.new(); edited.from_dict(SaveStore.read(path)["profile"], db)
	check("an edited level is ignored (derived from xp)", edited.level == 2)
	f = FileAccess.open(path, FileAccess.WRITE); f.store_string("{broken"); f.close()
	check("a corrupt save is ignored", SaveStore.read(path).is_empty())
	SaveStore.erase(path); SaveStore.erase(path + ".bad")
	print("RESULT failures=%d" % fails)
	quit(1 if fails > 0 else 0)
