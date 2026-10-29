class_name SaveStore
extends RefCounted
# Local save file in user:// (stays on the phone, nothing is sent anywhere). Written to a temp file first, then renamed,
# so a crash mid-write cannot destroy the previous save. A broken file is set aside and ignored.

const VERSION := 1

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		DirAccess.rename_absolute(path, path + ".bad")
		return {}
	return data

static func write(path: String, payload: Dictionary) -> bool:
	payload["version"] = VERSION
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(payload)); f.close()
	return DirAccess.rename_absolute(tmp, path) == OK

static func erase(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
