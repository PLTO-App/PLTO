class_name Npc
extends Node3D
# A person in a shop (customer, staff, inspector): a character that walks along points, waits with an order bubble, carries what
# was bought, sits down with a drink, and reacts. It has a collision body while it stands in the room so Noa cannot walk through it.

signal arrived

var data: Dictionary          # customer entry from the day's demand (or a look for staff)
var rig: CharacterRig
var body := StaticBody3D.new()
var bubble: Node3D
var carried: Node3D
var _target := Vector3.ZERO
var _moving := false
var speed := 2.6
var at_counter := false            # standing where it is served
var q_index := -1
var route_id := 0
var role := "customer"             # customer | staff | visitor
var busy := false                  # being served (by Noa or staff)

static func make(customer: Dictionary) -> Npc:
	var n := Npc.new(); n.data = customer; return n

func _ready() -> void:
	rig = CharacterRig.make(data.get("look", {}))
	add_child(BlobShadow.make(1.0)); add_child(rig)
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.4; cap.height = 2.0; cs.shape = cap; cs.position.y = 1.1
	body.add_child(cs); body.collision_layer = 0; add_child(body)     # enabled while standing, see set_solid()

func set_solid(on: bool) -> void:
	body.collision_layer = 1 if on else 0

# Walks a list of points in order. A newer route cancels an older one (returns false then).
func follow(points: Array) -> bool:
	route_id += 1; var mine := route_id
	set_solid(false)
	for p in points:
		await walk_to(p)
		if mine != route_id or not is_inside_tree(): return false
	return true

func walk_to(p: Vector3) -> void:
	_target = Vector3(p.x, 0.0, p.z); _moving = true
	await arrived

func face_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.01: rotation.y = atan2(-d.x, -d.z)

func _process(delta: float) -> void:
	var speed01 := 0.0
	if _moving:
		var d := _target - position; d.y = 0.0
		if d.length() < 0.08:
			_moving = false; arrived.emit()
		else:
			var step := minf(speed * delta, d.length())
			position += d.normalized() * step
			rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clampf(10.0 * delta, 0.0, 1.0))
			speed01 = 0.8
	rig.tick(delta, speed01, carried != null)

# Order bubble above the head: the product's picture and how many.
func show_order(pid: String, qty: int, refused := false) -> void:
	hide_order()
	bubble = Node3D.new(); bubble.position = Vector3(0, 3.25, 0); add_child(bubble)
	var bg := Sprite3D.new(); bg.texture = load("res://assets/ui/bubble.png"); bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bg.shaded = false; bg.pixel_size = 0.0075; bg.double_sided = true; bg.no_depth_test = true; bg.render_priority = 5; bg.position = Vector3(0, 0.15, 0); bubble.add_child(bg)
	var ic := Sprite3D.new(); ic.texture = load("res://assets/ui/icons/%s.png" % UiStyle.item_icon_id(pid)); ic.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ic.shaded = false; ic.pixel_size = 0.0034; ic.no_depth_test = true; ic.render_priority = 6; ic.position = Vector3(0, 0.3, 0); bubble.add_child(ic)
	if qty > 1 or refused:
		var l := Label3D.new(); l.text = ("×%d" % qty) if not refused else "✕"; l.font = Fonts.get_font(true); l.font_size = 64; l.pixel_size = 0.006
		l.modulate = Color("e94b4b") if refused else Color("0f1f3d"); l.outline_size = 10; l.outline_modulate = Color.WHITE
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true; l.render_priority = 7; l.position = Vector3(0.42, 0.05, 0); bubble.add_child(l)
	bubble.scale = Vector3.ZERO
	var tw := create_tween(); tw.tween_property(bubble, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_order() -> void:
	if bubble != null: bubble.queue_free(); bubble = null

# Something to carry away (a paper bag, a cup).
func give(model: String) -> void:
	drop()
	carried = ShopRoom.food(model); rig.carry_anchor.add_child(carried); carried.position = Vector3(0, -0.15, 0)

func drop() -> void:
	if carried != null: carried.queue_free(); carried = null

func sit(seat_pos: Vector3, yaw: float) -> void:
	position = seat_pos; rotation.y = yaw
	rig.set_pose("sit_drink" if carried != null else "sit")
	if carried != null:
		carried.reparent(self, true); carried.position = Vector3(0, 1.18, -0.55); carried.rotation = Vector3.ZERO
		var c := carried; carried = null; c.set_meta("table", true); set_meta("table_item", c)

func stand_up() -> void:
	rig.set_pose("")
	if has_meta("table_item"):
		var c: Node3D = get_meta("table_item")
		if is_instance_valid(c): c.queue_free()
		remove_meta("table_item")
