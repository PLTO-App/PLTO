class_name TouchUi
extends CanvasLayer
# Phone interface: floating joystick (drag on the left side), one contextual action button, an objective line,
# story cards and a small FPS counter. Hebrew text, right to left. Also reads the keyboard so it can be tried on a desktop.

signal action_pressed
signal card_button_pressed

const INK := Color("0f1f3d")
const CREAM := Color("fff6ea")
const TEAL := Color("2fb3a2")
const CORAL := Color("ff7a59")
const MUTED := Color("5b6478")

var move_vec := Vector2.ZERO          # what the game reads
var override_vec := Vector2.ZERO      # automated tests set this
var use_override := false
var input_enabled := true

var root := Control.new()
var stick: StickView
var fps_label: Label
var objective_panel: PanelContainer
var objective_label: Label
var action_button: Button
var hint_label: Label
var card_dim: ColorRect
var card_panel: PanelContainer
var card_title: Label
var card_body: Label
var card_bubble: PanelContainer
var card_bubble_label: Label
var card_note: Label
var card_button: Button
var bold_font: Font
var _stick_touch := -1
var _fps_t := 0.0

class StickView extends Control:
	var base_c := Vector2.ZERO
	var knob_c := Vector2.ZERO
	var active := false
	const R := 62.0
	func _draw() -> void:
		if not active: return
		draw_circle(base_c, R, Color(1, 1, 1, 0.16))
		draw_arc(base_c, R, 0, TAU, 40, Color(1, 1, 1, 0.55), 3.0, true)
		draw_circle(knob_c, 28.0, Color(1, 1, 1, 0.7))

func _ready() -> void:
	layer = 5
	# The engine's default font has no Hebrew, so the game ships DejaVu Sans (Hebrew and the shekel sign included).
	var ui_theme := Theme.new(); ui_theme.default_font = load("res://assets/fonts/DejaVuSans.ttf"); ui_theme.default_font_size = 16
	bold_font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	root.theme = ui_theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	stick = StickView.new(); stick.set_anchors_preset(Control.PRESET_FULL_RECT); stick.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(stick)
	# objective (top centre)
	objective_panel = PanelContainer.new(); objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_theme_stylebox_override("panel", _panel_style(Color(1.0, 0.965, 0.918, 0.92), 14, 10))
	objective_label = _label("", 16, INK, true); objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_child(objective_label); root.add_child(objective_panel)
	objective_panel.visible = false
	# action button (bottom right)
	action_button = Button.new(); action_button.visible = false
	action_button.custom_minimum_size = Vector2(190, 64)
	action_button.add_theme_font_override("font", bold_font); action_button.add_theme_font_size_override("font_size", 19)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := _panel_style(TEAL if st != "pressed" else TEAL.darkened(0.2), 32, 12); action_button.add_theme_stylebox_override(st, sb)
	action_button.add_theme_color_override("font_color", Color.WHITE); action_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	action_button.text_direction = Control.TEXT_DIRECTION_RTL
	action_button.pressed.connect(func(): action_pressed.emit())
	root.add_child(action_button)
	# hint (bottom left)
	hint_label = _label("", 15, Color.WHITE, false); hint_label.visible = false
	hint_label.add_theme_color_override("font_outline_color", Color(0.06, 0.12, 0.24, 0.9)); hint_label.add_theme_constant_override("outline_size", 6)
	root.add_child(hint_label)
	# fps
	fps_label = Label.new(); fps_label.add_theme_font_size_override("font_size", 12); fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6)); fps_label.add_theme_constant_override("outline_size", 4)
	root.add_child(fps_label)
	_build_card()
	get_viewport().size_changed.connect(_layout); _layout()

func _label(text: String, size: int, color: Color, bold: bool) -> Label:
	var l := Label.new(); l.text = text; l.text_direction = Control.TEXT_DIRECTION_RTL; l.language = "he"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", color)
	if bold: l.add_theme_font_override("font", bold_font)
	return l

func _panel_style(c: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = c; sb.set_corner_radius_all(radius); sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.25); sb.shadow_size = 6
	return sb

func _build_card() -> void:
	card_dim = ColorRect.new(); card_dim.color = Color(0.06, 0.12, 0.24, 0.55); card_dim.set_anchors_preset(Control.PRESET_FULL_RECT); card_dim.visible = false
	card_dim.mouse_filter = Control.MOUSE_FILTER_STOP; root.add_child(card_dim)
	var center := CenterContainer.new(); center.set_anchors_preset(Control.PRESET_FULL_RECT); center.mouse_filter = Control.MOUSE_FILTER_IGNORE; card_dim.add_child(center)
	card_panel = PanelContainer.new(); card_panel.add_theme_stylebox_override("panel", _panel_style(CREAM, 22, 22)); center.add_child(card_panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 14); card_panel.add_child(box)
	card_title = _label("", 25, INK, true); box.add_child(card_title)
	card_body = _label("", 17, INK, false); box.add_child(card_body)
	card_bubble = PanelContainer.new(); card_bubble.add_theme_stylebox_override("panel", _panel_style(Color("e7f6f3"), 16, 12)); box.add_child(card_bubble)
	card_bubble_label = _label("", 16, INK, false); card_bubble.add_child(card_bubble_label)
	card_note = _label("", 13, MUTED, false); box.add_child(card_note)
	card_button = Button.new(); card_button.custom_minimum_size = Vector2(0, 56)
	card_button.add_theme_font_override("font", bold_font); card_button.add_theme_font_size_override("font_size", 19)
	for st in ["normal", "hover", "pressed", "focus"]:
		card_button.add_theme_stylebox_override(st, _panel_style(TEAL if st != "pressed" else TEAL.darkened(0.2), 28, 10))
	card_button.add_theme_color_override("font_color", Color.WHITE); card_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	card_button.text_direction = Control.TEXT_DIRECTION_RTL
	card_button.pressed.connect(func(): card_button_pressed.emit())
	box.add_child(card_button)

# ---------------------------------------------------------------- layout (safe area, orientation)
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var sc := vp / win if win.x > 0 and win.y > 0 else Vector2.ONE
	var scr := Vector2(DisplayServer.screen_get_size())
	var l := 0.0; var t := 0.0; var r := 0.0; var b := 0.0
	if safe.size.x > 0 and scr.x > 0 and win.x >= scr.x - 1.0:
		l = safe.position.x * sc.x; t = safe.position.y * sc.y
		r = (scr.x - safe.end.x) * sc.x; b = (scr.y - safe.end.y) * sc.y
	root.offset_left = l; root.offset_top = t; root.offset_right = -r; root.offset_bottom = -b
	var w := vp.x - l - r; var h := vp.y - t - b
	var ow := minf(w - 32.0, 360.0)
	objective_label.custom_minimum_size.x = ow - 28.0
	objective_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective_panel.offset_left = -ow / 2.0; objective_panel.offset_right = ow / 2.0; objective_panel.offset_top = 14.0; objective_panel.offset_bottom = 14.0
	fps_label.position = Vector2(10, h - 22)
	action_button.position = Vector2(w - 190.0 - 20.0, h - 64.0 - 28.0)
	action_button.size = Vector2(190, 64)
	hint_label.custom_minimum_size.x = minf(w * 0.5, 240.0); hint_label.size = Vector2(hint_label.custom_minimum_size.x, 0.0)
	hint_label.position = Vector2(18, h - 130.0)
	card_panel.custom_minimum_size.x = minf(w - 40.0, 380.0)

# ---------------------------------------------------------------- public API
func set_objective(text: String) -> void:
	objective_panel.visible = text != ""
	objective_label.text = text
	objective_panel.offset_bottom = objective_panel.offset_top

func set_action(text: String) -> void:
	action_button.visible = text != "" and not card_dim.visible
	if text != "": action_button.text = text

func show_hint(text: String, seconds: float) -> void:
	hint_label.text = text; hint_label.visible = true; hint_label.modulate.a = 1.0
	var tw := create_tween(); tw.tween_interval(seconds); tw.tween_property(hint_label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): hint_label.visible = false)

func show_card(title: String, body: String, button_text: String, bubble := "", note := "") -> void:
	card_title.text = title; card_body.text = body; card_body.visible = body != ""
	card_bubble_label.text = bubble; card_bubble.visible = bubble != ""
	card_note.text = note; card_note.visible = note != ""
	card_button.text = button_text
	card_dim.visible = true; action_button.visible = false; input_enabled = false
	_end_stick()

func hide_card() -> void:
	card_dim.visible = false; input_enabled = true

# ---------------------------------------------------------------- joystick
func _end_stick() -> void:
	_stick_touch = -1; stick.active = false; stick.queue_redraw(); move_vec = Vector2.ZERO

func _blocked(p: Vector2) -> bool:
	if not input_enabled: return true
	if action_button.visible and action_button.get_global_rect().grow(8).has_point(p): return true
	return false

func _stick_start(index: int, p: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	if p.x > vp.x * 0.65 or p.y < vp.y * 0.2 or _blocked(p): return
	_stick_touch = index; stick.active = true; stick.base_c = p; stick.knob_c = p; stick.queue_redraw()

func _stick_move(p: Vector2) -> void:
	var off := p - stick.base_c
	var len := off.length()
	if len > StickView.R: off = off / len * StickView.R
	stick.knob_c = stick.base_c + off; stick.queue_redraw()
	var v := off / StickView.R
	move_vec = Vector2(v.x, -v.y) if v.length() > 0.12 else Vector2.ZERO

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed and _stick_touch == -1: _stick_start(st.index, st.position)
		elif not st.pressed and st.index == _stick_touch: _end_stick()
	elif e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		if sd.index == _stick_touch: _stick_move(sd.position)
	elif not DisplayServer.is_touchscreen_available():
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			if mb.pressed and _stick_touch == -1: _stick_start(0, mb.position)
			elif not mb.pressed and _stick_touch == 0: _end_stick()
		elif e is InputEventMouseMotion and _stick_touch == 0:
			_stick_move((e as InputEventMouseMotion).position)

func current_move() -> Vector2:
	if use_override: return override_vec
	if move_vec != Vector2.ZERO: return move_vec
	if not input_enabled: return Vector2.ZERO
	return Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")

func _process(delta: float) -> void:
	_fps_t += delta
	if _fps_t >= 0.5:
		_fps_t = 0.0; fps_label.text = "FPS %d" % roundi(Engine.get_frames_per_second())
	if input_enabled and Input.is_action_just_pressed("ui_accept") and action_button.visible: action_pressed.emit()
