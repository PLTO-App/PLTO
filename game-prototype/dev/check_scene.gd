extends Node
# Development only: compiles every script with the game's autoloads present (run as a scene) and reports failures.
# godot --headless --path game-prototype res://dev/check_scene.tscn
func _ready() -> void:
	var bad := 0; var n := 0
	for dir in ["res://scripts", "res://dev"]:
		for path in _files(dir):
			n += 1
			var s = load(path)
			if s == null or not (s as Script).can_instantiate(): print("FAILED ", path); bad += 1
	print("CHECKED %d scripts, %d failed" % [n, bad])
	get_tree().quit(1 if bad > 0 else 0)

func _files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	for f in d.get_files(): if f.ends_with(".gd"): out.append(dir + "/" + f)
	for sub in d.get_directories(): out.append_array(_files(dir + "/" + sub))
	return out
