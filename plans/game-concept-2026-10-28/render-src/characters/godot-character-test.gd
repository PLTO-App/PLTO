extends Node3D
func find_all(n: Node, cls: String, out: Array):
	if n.is_class(cls): out.append(n)
	for c in n.get_children(): find_all(c, cls, out)
func _ready():
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("#bfe3ff")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("#fff4e6"); e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_ACES; env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); sun.shadow_enabled = true; sun.light_energy = 1.3; add_child(sun)
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	var err := doc.append_from_file("res://assets/noa_rigged.glb", st)
	var noa: Node3D = doc.generate_scene(st); add_child(noa)
	var meshes := []; find_all(noa, "MeshInstance3D", meshes)
	var skels := []; find_all(noa, "Skeleton3D", skels)
	var report := "load_err=%d meshes=%d skeletons=%d" % [err, meshes.size(), skels.size()]
	for mi in meshes:
		var m: MeshInstance3D = mi
		if m.mesh and m.mesh.get_blend_shape_count() > 10:
			report += " body_blendshapes=%d" % m.mesh.get_blend_shape_count()
			for bs in {"!ex-mouthSmileLeft": 0.6, "!ex-mouthSmileRight": 0.6, "!ex-cheekSquintLeft": 0.3, "!ex-cheekSquintRight": 0.3, "!ex-browInnerUp": 0.2}.keys():
				var idx := m.find_blend_shape_by_name(bs)
				report += " %s=%d" % [bs, idx]
				if idx >= 0: m.set_blend_shape_value(idx, {"!ex-mouthSmileLeft": 0.6, "!ex-mouthSmileRight": 0.6, "!ex-cheekSquintLeft": 0.3, "!ex-cheekSquintRight": 0.3, "!ex-browInnerUp": 0.2}[bs])
	if skels.size() > 0:
		var sk: Skeleton3D = skels[0]
		for b in [["upperarm_l", -1.0], ["upperarm_r", 1.0]]:
			var i := sk.find_bone(b[0]); report += " %s=%d" % [b[0], i]
			if i >= 0: sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion(Vector3(0, 0, 1), b[1] * 0.0) * Quaternion(Vector3(1, 0, 0), 0.0))
	print("REPORT ", report)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(12, 12); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color("#e9dcc8"); floor.material_override = fm; add_child(floor)
	var cam := Camera3D.new(); cam.fov = 28; cam.position = Vector3(0.0, 1.35, 2.6); add_child(cam); cam.look_at(Vector3(0, 1.25, 0))
	var ui := CanvasLayer.new(); add_child(ui)
	var lbl := Label.new(); lbl.add_theme_font_override("font", load("res://assets/Heebo.ttf")); lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color("#0F1F3D")); lbl.text = "נועה ב-Godot 4.5: חיוך מ-blend shapes"
	lbl.text_direction = Control.TEXT_DIRECTION_RTL; lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.position = Vector2(16, 24); lbl.size = Vector2(358, 80); ui.add_child(lbl)
	for k in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://out.png"); get_tree().quit()
