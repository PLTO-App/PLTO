extends Node3D
# Development only: renders the app icon (icon.png, 512 px) from the game's own bakery model and Noa.
func _ready() -> void:
	get_window().size = Vector2i(512, 512)
	var town := Town.new(); add_child(town); town.set_time(0.3)
	var noa := CharacterRig.make(Game.content.world["people"]["noa"]["look"]); add_child(noa); noa.position = Vector3(1.2, 0.12, 0.6); noa.rotation.y = PI + 0.25
	noa.set_expression("smile"); noa.set_pose("wave")
	var cam := Camera3D.new(); cam.fov = 42; add_child(cam)
	cam.look_at_from_position(Vector3(2.2, 2.9, 5.6), Vector3(0.9, 2.6, 0.0))
	for i in 30:
		noa.tick(0.033, 0.0, false); await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://icon.png")); print("saved icon")
	get_tree().quit()
