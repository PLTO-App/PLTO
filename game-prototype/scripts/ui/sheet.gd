class_name Sheet
extends Control
# The management sheet: a panel over the lower part of a portrait screen (or the side of a landscape one), so the world stays
# visible. It has a title, optional tabs, a scrolling body, a line for notes and errors, and footer buttons. A screen fills it by
# passing a builder function; refresh() rebuilds the body in place (after a +/- tap) and keeps the scroll position.

signal closed

var panel: PanelContainer
var title_l: Label
var sub_l: Label
var tabs_box: HBoxContainer
var scroll: ScrollContainer
var body: VBoxContainer
var note_l: Label
var foot: HBoxContainer
var close_b: Button
var dim: ColorRect
var builder: Callable
var tab := 0
var tabs: Array = []
var closable := true
var tall := false
var screen_id := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = UiStyle.direction()
	dim = ColorRect.new(); dim.color = Color(0.04, 0.08, 0.18, 0.35); dim.set_anchors_preset(Control.PRESET_FULL_RECT); dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	panel = PanelContainer.new()
	var sb := UiStyle.panel(Color(UiStyle.CREAM, 0.985), 26, 14); sb.shadow_size = 12
	panel.add_theme_stylebox_override("panel", sb); add_child(panel)
	var col := UiStyle.vbox(8); panel.add_child(col)
	var head := UiStyle.hbox(8); col.add_child(head)
	var tv := UiStyle.vbox(0); tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(tv)
	title_l = UiStyle.label("", 21, UiStyle.INK, true); tv.add_child(title_l)
	sub_l = UiStyle.label("", 13, UiStyle.MUTED); tv.add_child(sub_l)
	close_b = Button.new(); close_b.flat = true; close_b.custom_minimum_size = Vector2(44, 44); close_b.focus_mode = Control.FOCUS_NONE
	var g := UiIcons.glyph("close", 22, UiStyle.MUTED); g.set_anchors_preset(Control.PRESET_CENTER); g.position = Vector2(11, 11); close_b.add_child(g)
	close_b.pressed.connect(func(): Game.sfx.play("tap", 1.0, -6.0); close())
	head.add_child(close_b)
	tabs_box = UiStyle.hbox(6); col.add_child(tabs_box)
	scroll = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	body = UiStyle.vbox(8); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(body)
	note_l = UiStyle.label("", 13, UiStyle.BAD); col.add_child(note_l)
	foot = UiStyle.hbox(10); col.add_child(foot)
	get_viewport().size_changed.connect(_layout)
	visible = false

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.y > vp.x:
		var h := vp.y * (0.86 if tall else 0.64)
		panel.position = Vector2(6, vp.y - h - 6); panel.size = Vector2(vp.x - 12, h)
	else:
		# landscape: the sheet takes the end side, so the profile card at the start side stays visible
		var w := vp.x * 0.56
		panel.position = Vector2(6.0 if UiStyle.rtl() else vp.x - w - 6.0, 6.0); panel.size = Vector2(w, vp.y - 12.0)
	dim.visible = vp.y > vp.x and tall

# opts: tabs (Array of names), tab (int), closable (bool), tall (bool), sub (String), id (String)
func open(title: String, p_builder: Callable, opts := {}) -> void:
	builder = p_builder; tabs = opts.get("tabs", []); tab = int(opts.get("tab", 0)); closable = opts.get("closable", true)
	tall = opts.get("tall", false); screen_id = opts.get("id", "")
	title_l.text = title; sub_l.text = opts.get("sub", ""); sub_l.visible = sub_l.text != ""
	close_b.visible = closable
	visible = true; _layout()
	_build(true)
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.15)

func refresh() -> void:
	if not visible: return
	var keep := scroll.scroll_vertical
	_build(false)
	await get_tree().process_frame
	scroll.scroll_vertical = keep

func _build(reset_scroll: bool) -> void:
	for c in body.get_children(): c.queue_free()
	for c in foot.get_children(): c.queue_free()
	for c in tabs_box.get_children(): c.queue_free()
	tabs_box.visible = not tabs.is_empty()
	for i in tabs.size():
		var b := UiStyle.chip(tabs[i], i == tab, 14); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): Game.sfx.play("tap", 1.0, -8.0); tab = i; refresh())
		tabs_box.add_child(b)
	note_l.text = ""
	if builder.is_valid(): builder.call(self)
	if reset_scroll: scroll.scroll_vertical = 0

func set_title(t: String, sub := "") -> void:
	title_l.text = t; sub_l.text = sub; sub_l.visible = sub != ""

func note(text: String, good := false) -> void:
	note_l.text = text; note_l.add_theme_color_override("font_color", UiStyle.GOOD if good else UiStyle.BAD)

func add_footer(text: String, kind: String, cb: Callable, expand := true) -> Button:
	var b := UiStyle.button(text, kind, 17, 52)
	if expand: b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): Game.sfx.play("tap", 1.0, -6.0); cb.call())
	foot.add_child(b)
	return b

func close() -> void:
	if not visible: return
	visible = false; screen_id = ""
	closed.emit()

# ---------------------------------------------------------------- building blocks for screens
func line(text: String, size := 15, color := UiStyle.INK, is_bold := false) -> Label:
	var l := UiStyle.label(text, size, color, is_bold); body.add_child(l); return l

func heading(text: String) -> Label:
	var l := UiStyle.label(text, 16, UiStyle.INK, true); l.add_theme_constant_override("line_spacing", 0); body.add_child(l); return l

func card(parent: Control = null) -> VBoxContainer:
	var pc := UiStyle.card(); (parent if parent != null else body).add_child(pc)
	var v := UiStyle.vbox(6); pc.add_child(v); return v

func row(parent: Control) -> HBoxContainer:
	var h := UiStyle.hbox(8); parent.add_child(h); return h

# A row with an icon, a title and a subtitle, a value and +/- buttons. Returns the buttons so a screen can disable them.
func stepper(parent: Control, icon_id: String, title: String, subtitle: String, value: String, on_minus: Callable, on_plus: Callable) -> Dictionary:
	var h := row(parent)
	if icon_id != "": h.add_child(UiStyle.icon(icon_id, 40))
	var v := UiStyle.vbox(0); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
	v.add_child(UiStyle.label(title, 15, UiStyle.INK, true))
	if subtitle != "": v.add_child(UiStyle.label(subtitle, 12, UiStyle.MUTED))
	var minus := _round("−"); minus.pressed.connect(func(): Game.sfx.play("tap", 1.1, -10.0); on_minus.call())
	var val := UiStyle.one_line(UiStyle.label(value, 17, UiStyle.INK, true, HORIZONTAL_ALIGNMENT_CENTER)); val.custom_minimum_size = Vector2(48, 0)
	val.text_direction = Control.TEXT_DIRECTION_LTR
	var plus := _round("+"); plus.pressed.connect(func(): Game.sfx.play("tap", 1.2, -10.0); on_plus.call())
	h.add_child(minus); h.add_child(val); h.add_child(plus)
	return {"minus": minus, "plus": plus, "value": val}

func _round(text: String) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size = Vector2(44, 44); b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiStyle.bold()); b.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var c := UiStyle.ACCENT if st != "pressed" else UiStyle.ACCENT.darkened(0.2)
		if st == "disabled": c = Color("cfd3da")
		b.add_theme_stylebox_override(st, UiStyle.panel(c, 22, 2, false))
	b.add_theme_color_override("font_color", Color.WHITE); b.add_theme_color_override("font_pressed_color", Color.WHITE); b.add_theme_color_override("font_disabled_color", Color("f4f4f4"))
	return b

# "label .......... value" in one line (value at the end side, numbers left-to-right).
func kv(parent: Control, label: String, value: String, is_bold := false, value_color := UiStyle.INK) -> HBoxContainer:
	var h := row(parent)
	var a := UiStyle.label(label, 15 if not is_bold else 16, UiStyle.INK, is_bold); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(a)
	var b := UiStyle.one_line(UiStyle.label(value, 15 if not is_bold else 16, value_color, is_bold, UiStyle.end())); b.text_direction = Control.TEXT_DIRECTION_LTR
	h.add_child(b)
	return h

func meter(parent: Control, label: String, value: int, max_value: int, color: Color) -> void:
	var h := row(parent)
	var a := UiStyle.label(label, 14, UiStyle.INK, true); a.custom_minimum_size = Vector2(92, 0); h.add_child(a)
	var b := UiStyle.bar(value, max_value, color, 14); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(b)
	var t := UiStyle.one_line(UiStyle.label("%d" % value, 13, UiStyle.MUTED, true)); t.custom_minimum_size = Vector2(30, 0); h.add_child(t)
