extends Node3D
# Development only: a line-up of characters in different looks and poses, saved as a screenshot.
# godot --path . res://dev/char_preview.tscn -- out=/path [anim=walk]
var out := "/tmp"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("bfe3f0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("fff1e0"); e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_color = Color("fff0d8"); sun.light_energy = 1.0; sun.shadow_enabled = true; add_child(sun)
	sun.look_at_from_position(Vector3(4, 8, 6), Vector3.ZERO)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color("e9d8c0"); floor.material_override = fm; add_child(floor)
	var looks := [
		{"body": "f", "skin": "light", "hair": "5b3a29", "hair_style": "bun", "top": "f7efe4", "bottom": "33415c", "apron": "ef6f8a"},
		{"body": "m", "skin": "medium", "hair": "2a1d14", "hair_style": "short", "top": "3f7d5c", "bottom": "3a3f4f", "acc": ["beard"]},
		{"body": "f", "skin": "deep", "hair": "17110d", "hair_style": "curly", "top": "e0a030", "bottom": "5a3e36", "sleeve": 100},
		{"body": "f", "skin": "fair", "hair": "a0522d", "hair_style": "long", "top": "1f2a44", "bottom": "1f2a44", "acc": ["glasses"], "sleeve": 100},
		{"body": "m", "skin": "tan", "hair": "1b1b1b", "hair_style": "buzz", "top": "2d5f9e", "bottom": "2b2d42", "acc": ["cap"], "acc_color": "203a6b"},
		{"body": "m", "skin": "light", "hair": "6b4a2b", "hair_style": "curly", "top": "ffffff", "bottom": "333333", "acc": ["toque"], "apron": "3a3a3a"},
		{"body": "f", "skin": "medium", "hair": "3b2416", "hair_style": "pony", "top": "9b2f4a", "bottom": "3d5a80", "pants": 55},
	]
	var poses := ["", "talk", "wave", "think", "work", "", "sad"]
	var exprs := ["smile", "talk", "happy", "think", "neutral", "smile", "sad"]
	for i in looks.size():
		var r := CharacterRig.make(looks[i]); r.position = Vector3((i - 3) * 1.15, 0, 0); add_child(r)
		r.rotation.y = PI; r.set_expression(exprs[i]); r.set_pose(poses[i]); r.set_meta("i", i)
	var cam := Camera3D.new(); cam.fov = 40; add_child(cam); cam.look_at_from_position(Vector3(0, 2.3, 7.8), Vector3(0, 1.4, 0))
	await get_tree().create_timer(1.3).timeout
	get_viewport().get_texture().get_image().save_png(out + "/lineup.png")
	cam.look_at_from_position(Vector3(-2.2, 2.25, 2.4), Vector3(-2.2, 2.0, 0))
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(out + "/closeup.png")
	for c in get_children(): if c is CharacterRig: c.tick(0.0, 0.0, false)
	get_tree().quit()

func _process(delta: float) -> void:
	for c in get_children():
		if c is CharacterRig: (c as CharacterRig).tick(delta, 0.0, false)
