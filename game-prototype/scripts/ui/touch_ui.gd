class_name TouchUi
extends CanvasLayer
# Everything drawn over the 3D world: the top bar (Hud), the objective line, the action button, story cards, the reward effects,
# and the floating joystick. Hebrew text, right to left. Also reads the keyboard so it can be tried on a desktop.

signal action_pressed
signal card_button_pressed
signal card_secondary_pressed

var move_vec := Vector2.ZERO          # what the game reads
var override_vec := Vector2.ZERO      # automated tests set this
var use_override := false
var input_enabled := true

var root := Control.new()
var stick: StickView
var hud: Hud
var fx: RewardFx
var objective_panel: PanelContainer
var objective_label: Label
var action_button: Button
var hint_label: Label
var fps_label: Label
var card_dim: ColorRect
var card_panel: PanelContainer
var card_title: Label
var card_body: Label
var card_lines: Label
var card_bubble: PanelContainer
var card_bubble_label: Label
var card_note: Label
var card_button: Button
var card_secondary: Button
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
	root.theme = UiStyle.theme()      # the engine's default font has no Hebrew, so the game ships DejaVu Sans
	root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(_make_vignette())
	stick = StickView.new(); stick.set_anchors_preset(Control.PRESET_FULL_RECT); stick.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(stick)
	hud = Hud.new(); root.add_child(hud)
	objective_panel = PanelContainer.new(); objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_theme_stylebox_override("panel", UiStyle.panel(Color(1.0, 0.965, 0.918, 0.94), 16, 9))
	objective_label = UiStyle.label("", 16, UiStyle.INK, true); objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_child(objective_label); root.add_child(objective_panel); objective_panel.visible = false
	action_button = UiStyle.pill_button("", 19, UiStyle.TEAL); action_button.visible = false; action_button.custom_minimum_size = Vector2(150, 64)
	action_button.pressed.connect(func(): action_pressed.emit()); root.add_child(action_button)
	hint_label = UiStyle.label("", 15, Color.WHITE, false); hint_label.visible = false; UiStyle.outline(hint_label, Color(0.06, 0.12, 0.24, 0.9), 6); root.add_child(hint_label)
	fps_label = Label.new(); fps_label.add_theme_font_size_override("font_size", 12); fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8)); UiStyle.outline(fps_label, Color(0, 0, 0, 0.6), 4)
	root.add_child(fps_label)
	fx = RewardFx.new(); fx.hud = hud; fx.mouse_filter = Control.MOUSE_FILTER_IGNORE; fx.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(fx)
	_build_card()
	get_viewport().size_changed.connect(_layout); _layout()

func _make_vignette() -> TextureRect:
	var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.08, 0.03, 0.0, 0.3)])
	var tex := GradientTexture2D.new(); tex.gradient = g; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(1.0, 0.5); tex.width = 128; tex.height = 128
	var tr := TextureRect.new(); tr.texture = tex; tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT); tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _build_card() -> void:
	card_dim = ColorRect.new(); card_dim.color = Color(0.06, 0.12, 0.24, 0.55); card_dim.set_anchors_preset(Control.PRESET_FULL_RECT); card_dim.visible = false
	card_dim.mouse_filter = Control.MOUSE_FILTER_STOP; root.add_child(card_dim)
	var center := CenterContainer.new(); center.set_anchors_preset(Control.PRESET_FULL_RECT); center.mouse_filter = Control.MOUSE_FILTER_IGNORE; card_dim.add_child(center)
	card_panel = PanelContainer.new(); card_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.CREAM, 22, 22)); center.add_child(card_panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 12); card_panel.add_child(box)
	card_title = UiStyle.label("", 25, UiStyle.INK, true); box.add_child(card_title)
	card_body = UiStyle.label("", 17, UiStyle.INK); box.add_child(card_body)
	card_lines = UiStyle.label("", 17, UiStyle.INK); box.add_child(card_lines)
	card_bubble = PanelContainer.new(); card_bubble.add_theme_stylebox_override("panel", UiStyle.panel(Color("e7f6f3"), 16, 12)); box.add_child(card_bubble)
	card_bubble_label = UiStyle.label("", 16, UiStyle.INK); card_bubble.add_child(card_bubble_label)
	card_note = UiStyle.label("", 13, UiStyle.MUTED); box.add_child(card_note)
	card_button = UiStyle.pill_button("", 19, UiStyle.TEAL); card_button.custom_minimum_size = Vector2(0, 56)
	card_button.pressed.connect(func(): Game.sfx.play("tap"); card_button_pressed.emit()); box.add_child(card_button)
	card_secondary = Button.new(); card_secondary.flat = true; card_secondary.custom_minimum_size = Vector2(0, 40); card_secondary.text_direction = Control.TEXT_DIRECTION_RTL
	card_secondary.add_theme_font_size_override("font_size", 14); card_secondary.add_theme_color_override("font_color", UiStyle.MUTED)
	card_secondary.pressed.connect(func(): card_secondary_pressed.emit()); box.add_child(card_secondary)

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
	objective_panel.offset_left = -ow / 2.0; objective_panel.offset_right = ow / 2.0; objective_panel.offset_top = 76.0; objective_panel.offset_bottom = 76.0
	fps_label.position = Vector2(10, h - 22)
	action_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT); action_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN; action_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	action_button.offset_right = -20.0; action_button.offset_left = -20.0; action_button.offset_bottom = -28.0; action_button.offset_top = -28.0
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

# spec keys: title, body, lines (Array of String), bubble, note, button, secondary
func show_card(spec: Dictionary) -> void:
	card_title.text = spec.get("title", ""); card_body.text = spec.get("body", ""); card_body.visible = card_body.text != ""
	card_lines.text = "\n".join(spec.get("lines", [])); card_lines.visible = card_lines.text != ""
	card_bubble_label.text = spec.get("bubble", ""); card_bubble.visible = card_bubble_label.text != ""
	card_note.text = spec.get("note", ""); card_note.visible = card_note.text != ""
	card_button.text = spec.get("button", "")
	card_secondary.text = spec.get("secondary", ""); card_secondary.visible = card_secondary.text != ""
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
