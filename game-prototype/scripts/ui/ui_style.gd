class_name UiStyle
extends RefCounted
# The game's own look for the interface: warm cream panels, dark glass pills, teal and gold accents.
# Every screen builds from these helpers, so a new look is a change in one file.

const INK := Color("0f1f3d")
const CREAM := Color("fff6ea")
const TEAL := Color("2fb3a2")
const CORAL := Color("ff7a59")
const GOLD := Color("ffc24d")
const GOLD_DEEP := Color("f0902a")
const MUTED := Color("5b6478")
const GLASS := Color(0.07, 0.12, 0.26, 0.82)

static var _regular: Font
static var _bold: Font

static func regular() -> Font:
	if _regular == null: _regular = load("res://assets/fonts/DejaVuSans.ttf")
	return _regular

static func bold() -> Font:
	if _bold == null: _bold = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	return _bold

static func theme() -> Theme:
	var t := Theme.new(); t.default_font = regular(); t.default_font_size = 16; return t

static func panel(c: Color, radius: int, margin: int, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = c; sb.set_corner_radius_all(radius); sb.set_content_margin_all(margin)
	if shadow: sb.shadow_color = Color(0, 0, 0, 0.25); sb.shadow_size = 6
	return sb

static func label(text: String, size: int, color: Color, is_bold := false) -> Label:
	var l := Label.new(); l.text = text; l.text_direction = Control.TEXT_DIRECTION_RTL; l.language = "he"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", color)
	if is_bold: l.add_theme_font_override("font", bold())
	return l

static func outline(l: Label, color: Color, size: int) -> void:
	l.add_theme_color_override("font_outline_color", color); l.add_theme_constant_override("outline_size", size)

static func pill_button(text: String, size: int, color: Color) -> Button:
	var b := Button.new(); b.text = text; b.text_direction = Control.TEXT_DIRECTION_RTL
	b.add_theme_font_override("font", bold()); b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, panel(color if st != "pressed" else color.darkened(0.2), 32, 12))
	b.add_theme_color_override("font_color", Color.WHITE); b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b

# 1234 -> "1,234"
static func number(n: int) -> String:
	var s := str(absi(n)); var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0: out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out

static func money(n: int) -> String:
	return "%s ₪" % number(n)
