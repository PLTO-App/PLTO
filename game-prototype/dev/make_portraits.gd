extends Node3D
# Development only: renders the UI pictures from the game's own 3D models (transparent PNGs):
#   assets/ui/portraits/<person>.png  head and shoulders of the main people and the staff
#   assets/ui/icons/<item>.png         products and ingredients
# godot --path . res://dev/make_portraits.tscn   (needs a display; use xvfb-run)
const OUT_P := "res://assets/ui/portraits/"
const OUT_I := "res://assets/ui/icons/"

func _ready() -> void:
	get_window().size = Vector2i(256, 256)
	get_viewport().transparent_bg = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_P)); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_I))
	var we := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("fff1e0"); e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 0.9; sun.light_color = Color("fff3e0"); add_child(sun); sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(20), 0)
	var cam := Camera3D.new(); cam.fov = 26; add_child(cam)
	var only_goods := "goods" in OS.get_cmdline_user_args()      # just the minimarket's goods, leaving every other picture as it is
	var people := {}
	if not only_goods:
		for id in Game.content.world["people"]: people[id] = Game.content.world["people"][id]["look"]
		for s in Game.content.world["staff_pool"]: people[s["id"]] = s["look"]
	for id in people:
		var r := CharacterRig.make(people[id]); r.rotation.y = PI; add_child(r)
		r.set_expression("smile")
		cam.look_at_from_position(Vector3(0.0, 2.05, 2.6), Vector3(0, 1.88, 0))
		await _frames(4)
		_save(OUT_P + id + ".png")
		r.queue_free(); await _frames(1)
	var items: Array = ["croissant", "challah", "carrot_cake", "strawberry_cake", "cup", "iced", "cookie", "base", "dairy", "sweet", "beans", "milk", "bag"]
	if only_goods: items = PrimGoods.IDS
	for it in items:
		var model: String = ("ing_" + it) if it in ["base", "dairy", "sweet", "beans", "milk"] else ("food_" + it)
		if only_goods: model = "goods_" + it
		var n := ShopRoom.food(model); add_child(n)
		var box := _aabb(n); var c := box.get_center(); var size := box.size.length()
		cam.fov = 30
		cam.look_at_from_position(c + Vector3(0, size * 0.9, size * 1.55), c)
		await _frames(4)
		_save(OUT_I + it + ".png")
		n.queue_free(); await _frames(1)
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path)); print("saved ", path)

func _aabb(root: Node) -> AABB:
	var box := AABB(); var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children(): stack.append(ch)
		if n is MeshInstance3D:
			var wb: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			if first: box = wb; first = false
			else: box = box.merge(wb)
	return box
