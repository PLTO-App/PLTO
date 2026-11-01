extends Node3D
# Development only: the sky at several heights and times of day (screenshots).
var out := "/tmp"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	var town := Town.new(); add_child(town)
	var cam := Camera3D.new(); cam.fov = 60; add_child(cam)
	get_window().size = Vector2i(585, 585)
	for t in [0.1, 0.45, 0.8, 1.0]:
		town.set_time(t)
		for pitch in [10.0, 35.0]:
			cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(20), 0)), Vector3(0, 30, 0))
			await get_tree().create_timer(0.4).timeout
			get_viewport().get_texture().get_image().save_png("%s/sky_%d_%d.png" % [out, int(t * 100), int(pitch)])
	get_tree().quit()
