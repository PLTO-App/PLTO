extends Node3D
# Development only: the street from the hub camera at several times of day (portrait and landscape screenshots).
var out := "/tmp"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	var town := Town.new(); add_child(town)
	town.show_owned({"bakery": true})
	town.spawn_walkers(Game.content.world["townsfolk"], 8, 3)
	var cam := Camera3D.new(); cam.fov = 38; add_child(cam)
	var shots := [["p_morning", 0.15, Vector3(0, 0, 0), false], ["p_noon", 0.45, Vector3(-6, 0, 0), false], ["p_sunset", 0.8, Vector3(3, 0, 0), false],
		["p_night", 1.0, Vector3(0, 0, 0), false], ["l_noon", 0.45, Vector3(-4, 0, 0), true], ["p_cafe_open", 0.45, Vector3(-9.5, 0, 0), false]]
	for s in shots:
		get_window().size = Vector2i(1266, 585) if s[3] else Vector2i(585, 1266)
		cam.keep_aspect = Camera3D.KEEP_HEIGHT if s[3] else Camera3D.KEEP_WIDTH
		cam.fov = 34.0 if s[3] else 46.0
		if s[0] == "p_cafe_open": town.show_owned({"bakery": true, "cafe": true})
		town.set_time(s[1])
		cam.global_transform = Town.camera_pose(s[2].x, not s[3])
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
		var RS := RenderingServer
		print("PERF %s draws=%d prims=%d" % [s[0], RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()
