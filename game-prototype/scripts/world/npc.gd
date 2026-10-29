class_name Npc
extends Node3D
# A customer: a character rig that walks between points, waits with an order bubble, and reacts.
# It has a collision body while it stands in the room so Noa cannot walk through it.

signal arrived

var data: Dictionary          # customer entry from the business content
var rig: CharacterRig
var body := StaticBody3D.new()
var bubble: Node3D
var _target := Vector3.ZERO
var _moving := false
const SPEED := 2.6

static func make(customer: Dictionary) -> Npc:
	var n := Npc.new(); n.data = customer; return n

func _ready() -> void:
	rig = CharacterRig.make(data.get("look", {}))
	add_child(BlobShadow.make(1.05)); add_child(rig)
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.42; cap.height = 2.0; cs.shape = cap; cs.position.y = 1.1
	body.add_child(cs); body.collision_layer = 0; add_child(body)     # enabled while waiting, see set_solid()

func set_solid(on: bool) -> void:
	body.collision_layer = 1 if on else 0

var at_counter := false            # standing at the counter, waiting to be served
var q_index := -1
var route_id := 0

# Walks a list of points in order. A newer route cancels an older one (returns false then).
func follow(points: Array) -> bool:
	route_id += 1; var mine := route_id
	for p in points:
		await walk_to(p)
		if mine != route_id or not is_inside_tree(): return false
	return true

# Walks to a point (flat), then emits "arrived". Await it.
func walk_to(p: Vector3) -> void:
	_target = Vector3(p.x, 0.0, p.z); _moving = true
	await arrived

func face_point(p: Vector3) -> void:
	var d := p - global_position
	rotation.y = atan2(-d.x, -d.z)

func _process(delta: float) -> void:
	var speed01 := 0.0
	if _moving:
		var d := _target - position; d.y = 0.0
		if d.length() < 0.08:
			_moving = false; arrived.emit()
		else:
			var step := minf(SPEED * delta, d.length())
			position += d.normalized() * step
			rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clampf(10.0 * delta, 0.0, 1.0))
			speed01 = 1.0
	rig.tick(delta, speed01, false)

# Order bubble above the head: white speech bubble with the product icon.
func show_order(icon_path: String) -> void:
	hide_order()
	bubble = Node3D.new(); bubble.position = Vector3(0, 3.35, 0); add_child(bubble)
	var bg := Sprite3D.new(); bg.texture = load("res://assets/ui/bubble.png"); bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bg.shaded = false; bg.pixel_size = 0.0075; bg.double_sided = true; bg.no_depth_test = true; bg.render_priority = 5; bg.position = Vector3(0, 0.15, 0); bubble.add_child(bg)
	var ic := Sprite3D.new(); ic.texture = load(icon_path); ic.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ic.shaded = false; ic.pixel_size = 0.0068; ic.no_depth_test = true; ic.render_priority = 6; ic.position = Vector3(0, 0.3, 0); bubble.add_child(ic)
	bubble.scale = Vector3.ZERO
	var tw := create_tween(); tw.tween_property(bubble, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_order() -> void:
	if bubble != null: bubble.queue_free(); bubble = null
