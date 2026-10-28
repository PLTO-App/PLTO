extends Node3D
func _ready():
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("#bfe3ff")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("#fff4e6"); e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 35, 0); sun.shadow_enabled = true; sun.light_energy = 1.4; add_child(sun)
	for f in ["oven", "kitchencounter_straight_A"]:
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		var err := doc.append_from_file("res://assets/%s.gltf" % f, st)
		var n: Node3D = doc.generate_scene(st)
		n.position = Vector3(1.2 if f == "oven" else -1.2, 0, 0); add_child(n)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(12, 12); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color("#e9dcc8"); floor.material_override = fm; add_child(floor)
	var cam := Camera3D.new(); cam.position = Vector3(4, 5, 8); add_child(cam); cam.look_at(Vector3(0, 1, 0))
	var ui := CanvasLayer.new(); add_child(ui)
	var lbl := Label.new(); var font := load("res://assets/Heebo.ttf")
	lbl.add_theme_font_override("font", font); lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color("#0F1F3D"))
	lbl.text = "העוגות של נועה: עוגה ב-320 ₪ ל-20 ילדים 🦖"
	lbl.text_direction = Control.TEXT_DIRECTION_RTL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(16, 40); lbl.size = Vector2(358, 200); ui.add_child(lbl)
	await get_tree().process_frame; await get_tree().process_frame; await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://out.png")
	print("TEXTSERVER: ", TextServerManager.get_primary_interface().get_name())
	get_tree().quit()
