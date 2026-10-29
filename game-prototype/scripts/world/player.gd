class_name Player
extends CharacterBody3D
# Noa's body on the floor. She moves either by the joystick (input_vec: x = right, y = up on the screen, turned by the camera yaw)
# or by herself to a point when the player taps an action (go_to). Collides with the room's furniture.

const SPEED := 3.6
const ACCEL := 12.0

signal reached

var input_vec := Vector2.ZERO
var cam_yaw := 0.0
var locked := false
var carrying := false
var rig: CharacterRig
var carried: Node3D
var _path: Array = []
var _stuck := 0.0

func _ready() -> void:
	rig = CharacterRig.make(Game.content.world["people"]["noa"]["look"])
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.38; cap.height = 2.0; cs.shape = cap; cs.position.y = 1.1
	add_child(cs); add_child(BlobShadow.make(1.1)); add_child(rig)

# Walks through the points by herself. Await it; returns when she is there (or gives up after being stuck).
func go_to(points: Array) -> void:
	_path = points.duplicate(); _stuck = 0.0
	if _path.is_empty(): return
	await reached

func walking() -> bool:
	return not _path.is_empty()

func _physics_process(delta: float) -> void:
	var want := Vector3.ZERO
	if not _path.is_empty():
		var t: Vector3 = _path[0]; var d := t - global_position; d.y = 0.0
		if d.length() < 0.18:
			_path.pop_front()
			if _path.is_empty(): velocity = Vector3.ZERO; reached.emit()
		else:
			want = d.normalized() * SPEED
			if velocity.length() < 0.3: _stuck += delta
			if _stuck > 1.6: _path.clear(); velocity = Vector3.ZERO; reached.emit()
	elif not locked and input_vec.length() > 0.05:
		var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw)); var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
		want = (right * input_vec.x + fwd * input_vec.y).limit_length(1.0) * SPEED
	velocity = velocity.lerp(want, clampf(ACCEL * delta, 0.0, 1.0))
	move_and_slide()
	position.y = 0.0
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.4:
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), clampf(12.0 * delta, 0.0, 1.0))

func _process(delta: float) -> void:
	rig.tick(delta, Vector2(velocity.x, velocity.z).length() / SPEED, carrying)

# Turns Noa toward a point on the floor (used before an interaction). Await it.
func face_point(p: Vector3) -> void:
	var d := p - global_position
	var target := atan2(-d.x, -d.z)
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", rotation.y + angle_difference(rotation.y, target), 0.22)
	await tw.finished

func hold(model: String) -> void:
	drop_item()
	carried = ShopRoom.food(model); rig.carry_anchor.add_child(carried); carried.position = Vector3(0, -0.12, 0)
	carrying = true

func drop_item() -> Node3D:
	var c := carried; carried = null; carrying = false
	return c
