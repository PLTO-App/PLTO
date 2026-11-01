extends Node3D
# Development only: a shop interior as it looks in the game (the town's environment with the shop's own light), from the game camera.
# godot --path . res://dev/bakery_preview.tscn -- out=/tmp/shots [biz=bakery] [stock=1]
var out := "/tmp"
var biz := "bakery"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("biz="): biz = a.substr(4)
	var town := Town.new(); add_child(town); town.visible = false
	town.set_time(0.42); town.set_indoor(true)
	var room := ShopRoom.new(); add_child(room); room.build(biz); room.position = Vector3(0, 0, 200)
	room.show_upgrades({"tables": true, "fridge": true, "terrace": true}); room.show_certificate(true)
	room.set_menu(["קרואסון  14 ₪", "חלה  18 ₪", "עוגת גזר  95 ₪"])
	room.show_stock({"croissant": 8, "challah": 7, "carrot_cake": 2, "strawberry_cake": 3, "cookie": 9, "cappuccino": 3})
	var folk: Array = Game.content.world["townsfolk"]
	var noa := CharacterRig.make(Game.content.world["people"]["noa"]["look"]); noa.position = room.lay["serve_spot"]; room.add_child(noa); noa.set_pose("work")
	for i in 3:
		var c := CharacterRig.make(folk[i + 1]["look"]); c.position = room.lay["queue"][i]; room.add_child(c); c.rotation.y = 0.6
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	for k in 2:
		var portrait := k == 0
		get_window().size = Vector2i(585, 1266) if portrait else Vector2i(1266, 585)
		cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT; cam.fov = 50.0 if portrait else 36.0
		var target: Vector3 = room.global_position + (room.lay["noa_home"] as Vector3) + Vector3(0, 1.0, 0)
		var off := Vector3(sin(0.32) * 8.8, 7.6, cos(0.32) * 8.8) * (0.95 if portrait else 0.82)
		cam.global_position = target + off; cam.look_at(target)
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, biz, "p" if portrait else "l"])
		var RS := RenderingServer
		print("PERF %s draws=%d prims=%d" % [biz, RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RS.get_rendering_info(RS.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()

func _process(delta: float) -> void:
	for r in get_children():
		if r is ShopRoom:
			for n in r.get_children(): if n is CharacterRig: n.tick(delta, 0.0, false)
