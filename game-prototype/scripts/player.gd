class_name Player
extends CharacterBody3D
# Noa's body on the floor plane. Input is a 2D vector (x = right, y = up on the screen), turned into world
# movement relative to the camera yaw. Collides with the room's static bodies.

const SPEED := 3.6
const ACCEL := 12.0

var input_vec := Vector2.ZERO
var cam_yaw := 0.0
var locked := false
var carrying := false
var rig := NoaRig.new()

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.4; cap.height = 2.0; cs.shape = cap; cs.position.y = 1.1
	add_child(cs); add_child(rig)

func _physics_process(delta: float) -> void:
	var want := Vector3.ZERO
	if not locked and input_vec.length() > 0.05:
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
	tw.tween_property(self, "rotation:y", rotation.y + angle_difference(rotation.y, target), 0.25)
	await tw.finished
