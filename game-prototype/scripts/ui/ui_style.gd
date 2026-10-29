class_name UiStyle
extends RefCounted
# The game's interface look: navy glass bars, cream panels, a blue accent, a green call to action and gold for rewards.
# Every screen builds from these helpers, so the look is changed in one file. Layout follows the language direction:
# containers are built in reading order and mirror themselves for right-to-left languages.

const INK := Color("0f1f3d")
const CREAM := Color("fff8ee")
const PANEL_2 := Color("f1f5f9")
const ACCENT := Color("2563eb")
const CTA := Color("22a55b")
const GOLD := Color("f5b83d")
const GOLD_DEEP := Color("e8891c")
const CORAL := Color("e94b4b")
const TEAL := Color("1f9e8f")
const MUTED := Color("5b6478")
const LINE := Color("e5ddd0")
const GLASS := Color(0.06, 0.12, 0.24, 0.86)
const GOOD := Color("1e8e4e")
const BAD := Color("c0392b")

static func regular() -> Font: return Fonts.get_font(false)
static func bold() -> Font: return Fonts.get_font(true)

static func theme() -> Theme:
	var t := Theme.new(); t.default_font = regular(); t.default_font_size = 16
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0, 0.12); sb.set_corner_radius_all(4)
	t.set_stylebox("scroll", "VScrollBar", sb); t.set_stylebox("grabber", "VScrollBar", panel(Color(0, 0, 0, 0.25), 4, 0, false))
	return t

static func rtl() -> bool:
	return Loc.is_rtl()

static func direction() -> int:
	return Control.LAYOUT_DIRECTION_RTL if rtl() else Control.LAYOUT_DIRECTION_LTR

# Horizontal alignment for the start / end of a line in the current language.
static func start() -> int:
	return HORIZONTAL_ALIGNMENT_RIGHT if rtl() else HORIZONTAL_ALIGNMENT_LEFT

static func end() -> int:
	return HORIZONTAL_ALIGNMENT_LEFT if rtl() else HORIZONTAL_ALIGNMENT_RIGHT

static func panel(c: Color, radius: int, margin: int, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = c; sb.set_corner_radius_all(radius); sb.set_content_margin_all(margin)
	if shadow: sb.shadow_color = Color(0, 0, 0, 0.22); sb.shadow_size = 6; sb.shadow_offset = Vector2(0, 2)
	return sb

static func label(text: String, size: int, color := INK, is_bold := false, align := -1) -> Label:
	var l := Label.new(); l.text = text
	l.horizontal_alignment = start() if align < 0 else align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", bold() if is_bold else regular())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func one_line(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF; return l

static func outline(l: Label, color: Color, size: int) -> void:
	l.add_theme_color_override("font_outline_color", color); l.add_theme_constant_override("outline_size", size)

# kind: cta (green), primary (blue), gold, secondary (light), ghost (text only), danger
static func button(text: String, kind := "primary", size := 17, min_h := 50) -> Button:
	var b := Button.new(); b.text = text
	b.add_theme_font_override("font", bold()); b.add_theme_font_size_override("font_size", size)
	var bg := {"cta": CTA, "primary": ACCENT, "gold": GOLD_DEEP, "secondary": Color("e8e2d8"), "ghost": Color(0, 0, 0, 0), "danger": CORAL, "navy": INK}.get(kind, ACCENT) as Color
	var fg := INK if kind in ["secondary", "ghost"] else Color.WHITE
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var c := bg
		if st == "pressed": c = bg.darkened(0.18)
		if st == "disabled": c = Color("cfd3da") if kind != "ghost" else Color(0, 0, 0, 0)
		var sb := panel(c, 26, 10, kind in ["cta", "primary", "gold", "danger", "navy"] and st != "disabled")
		if st == "focus": sb.draw_center = true
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", fg); b.add_theme_color_override("font_pressed_color", fg); b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_focus_color", fg); b.add_theme_color_override("font_disabled_color", Color("7b8494"))
	b.custom_minimum_size = Vector2(0, min_h); b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	press_fx(b)
	return b

static func chip(text: String, selected: bool, size := 14) -> Button:
	var b := Button.new(); b.text = text; b.toggle_mode = false
	b.add_theme_font_override("font", bold()); b.add_theme_font_size_override("font_size", size)
	var bg := ACCENT if selected else Color("ffffff")
	var fg := Color.WHITE if selected else INK
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := panel(bg if st != "disabled" else Color("eceae6"), 18, 8, false)
		sb.border_color = ACCENT if selected else LINE; sb.set_border_width_all(2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", fg); b.add_theme_color_override("font_pressed_color", fg); b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_disabled_color", Color("9aa1ad"))
	b.custom_minimum_size = Vector2(0, 44); b.focus_mode = Control.FOCUS_NONE; b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	press_fx(b)
	return b

# A small squeeze while a button is held, and a springy release. Works on any button (the pivot follows its size).
static func press_fx(b: BaseButton) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	b.button_down.connect(func():
		b.create_tween().tween_property(b, "scale", Vector2(0.95, 0.95), 0.06))
	b.button_up.connect(func():
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", sep); return h

static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep); return v

static func card(color := Color(1, 1, 1, 0.92), margin := 10) -> PanelContainer:
	var pc := PanelContainer.new(); var sb := panel(color, 16, margin, false)
	sb.border_color = LINE; sb.set_border_width_all(1)
	pc.add_theme_stylebox_override("panel", sb); return pc

static func spacer() -> Control:
	var c := Control.new(); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.mouse_filter = Control.MOUSE_FILTER_IGNORE; return c

static func bar(value: float, max_value: float, color := ACCENT, h := 12) -> ProgressBar:
	var p := ProgressBar.new(); p.max_value = maxf(1.0, max_value); p.value = value; p.show_percentage = false
	p.custom_minimum_size = Vector2(60, h); p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("background", panel(Color(0, 0, 0, 0.1), h / 2, 0, false))
	p.add_theme_stylebox_override("fill", panel(color, h / 2, 0, false))
	p.fill_mode = ProgressBar.FILL_END_TO_BEGIN if rtl() else ProgressBar.FILL_BEGIN_TO_END
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func tex(path: String, px: float) -> TextureRect:
	var t := TextureRect.new(); t.texture = load(path) if ResourceLoader.exists(path) else null
	t.custom_minimum_size = Vector2(px, px); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func icon(item: String, px := 40.0) -> TextureRect:
	return tex("res://assets/ui/icons/%s.png" % item, px)

# A round portrait of a person (res://assets/ui/portraits/<id>.png) on a coloured disc.
static func portrait(id: String, px := 64.0, ring := GOLD) -> Control:
	var holder := PanelContainer.new(); var sb := panel(Color("fde7c8"), int(px / 2), 0, false); sb.border_color = ring; sb.set_border_width_all(3)
	holder.add_theme_stylebox_override("panel", sb); holder.custom_minimum_size = Vector2(px, px); holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var t := tex("res://assets/ui/portraits/%s.png" % id, px); holder.add_child(t)
	return holder

# Item names: ingredients and products share the icon folder (product ids, or the input ids).
static func item_icon_id(item: String) -> String:
	return {"cappuccino": "cup", "americano": "cup"}.get(item, item)
