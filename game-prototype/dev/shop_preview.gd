extends Node3D
# Development only: both shop interiors with stock, staff and customers, from the game camera (screenshots).
var out := "/tmp"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	var we := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color("2a1f1a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("fff1e0"); e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 0.75; sun.light_color = Color("fff0d8"); sun.shadow_enabled = true; add_child(sun)
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(150), 0)
	var cam := Camera3D.new(); add_child(cam)
	var folk: Array = Game.content.world["townsfolk"]
	for bid in ["bakery", "cafe"]:
		var room := ShopRoom.new(); add_child(room); room.build(bid)
		room.show_upgrades({"tables": true, "fridge": true, "terrace": true})
		room.show_certificate(true)
		room.set_menu(["קרואסון  14 ₪", "חלה  18 ₪", "עוגת גזר  95 ₪"] if bid == "bakery" else ["הפוך  16 ₪", "אמריקנו  13 ₪", "אייס קפה  18 ₪"])
		room.show_stock({"croissant": 8, "challah": 7, "carrot_cake": 2, "strawberry_cake": 3, "cookie": 9, "cappuccino": 3})
		var noa := CharacterRig.make(Game.content.world["people"]["noa"]["look"]); noa.position = room.lay["serve_spot"]; room.add_child(noa); noa.set_pose("work")
		var staff := CharacterRig.make(Game.content.world["staff_pool"][0]["look"]); staff.position = room.lay["staff_spot"]; room.add_child(staff); staff.set_pose("talk")
		var c0 := CharacterRig.make(folk[0]["look"]); c0.position = room.lay["customer_spot"]; c0.rotation.y = 0; room.add_child(c0); c0.set_expression("happy")
		for i in 3:
			var c := CharacterRig.make(folk[i + 1]["look"]); c.position = room.lay["queue"][i]; room.add_child(c); c.rotation.y = 0.6
		var s: Array = room.lay["seats"][1]
		var sit := CharacterRig.make(folk[6]["look"]); sit.position = s[0] + Vector3(0, 0.0, 0); sit.rotation.y = s[1] + PI; room.add_child(sit); sit.set_pose("sit_drink")
		for n in room.get_children(): if n is CharacterRig: n.set_meta("tick", true)
		for k in 2:
			var portrait := k == 0
			get_window().size = Vector2i(585, 1266) if portrait else Vector2i(1266, 585)
			cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT; cam.fov = 50.0 if portrait else 36.0
			var target := Vector3(0.0, 1.0, 0.4)
			var off := Vector3(sin(0.32) * 8.8, 7.6, cos(0.32) * 8.8) * (0.95 if portrait else 0.85)
			cam.look_at_from_position(target + off, target)
			cam.v_offset = -1.6 if portrait else 0.0
			await get_tree().create_timer(0.8).timeout
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, bid, "p" if portrait else "l"])
			var RS := RenderingServer
			print("PERF %s draws=%d prims=%d" % [bid, RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		room.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _process(delta: float) -> void:
	for r in get_children():
		if r is ShopRoom:
			for n in r.get_children(): if n is CharacterRig: n.tick(delta, 0.0, false)
