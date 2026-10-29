extends Node3D
# Development only: side views of the main animations at several moments, saved as screenshots.
var out := "/tmp"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("bfe3f0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("fff1e0"); e.ambient_light_energy = 0.35
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 1.0; add_child(sun); sun.look_at_from_position(Vector3(6, 8, 4), Vector3.ZERO)
	var names := ["walk", "carry_walk", "give", "happy", "work", "sit", "think", "talk"]
	var rigs := []
	for i in names.size():
		var r := CharacterRig.make({"body": "f" if i % 2 == 0 else "m", "hair_style": "bun" if i % 2 == 0 else "short", "apron": "ef6f8a" if i < 4 else ""})
		r.position = Vector3((i - 3.5) * 1.3, 0, 0); r.rotation.y = -PI / 2; add_child(r); rigs.append(r)
	var cam := Camera3D.new(); cam.fov = 45; add_child(cam); cam.look_at_from_position(Vector3(0, 1.5, 9.5), Vector3(0, 1.2, 0))
	await get_tree().process_frame
	for k in 4:
		for i in names.size():
			var r: CharacterRig = rigs[i]
			r.anim.play(names[i]); r.anim.seek(r.anim.current_animation_length * k / 4.0, true); r.anim.pause()
		await get_tree().process_frame; await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/anim_%d.png" % [out, k])
	get_tree().quit()
