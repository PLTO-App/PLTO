class_name Hud
extends Control
# The top of the screen: Noa's card (portrait, level star, experience bar), the cash and reputation pills, and a line with the day,
# weekday, weather and time. It shows "shown_*" values: normally they follow the company at once; during a reward animation the
# effects hold them back (hold = true) and raise them step by step, so the number rises when the coins land.

var hold := false
var shown_cash := 0: set = _set_cash
var shown_rep := 50: set = _set_rep
var shown_level := 1
var shown_xp := 0
var shown_span := 100
var rep_biz := "bakery"

var card: PanelContainer
var cash_pill: PanelContainer
var rep_pill: PanelContainer
var cash_label: Label
var rep_label: Label
var xp_bar: ProgressBar
var xp_label: Label
var star: UiIcons.StarBadge
var coin_icon: Control
var info_label: Label
var info_icon: UiIcons.Glyph
var row: HBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = UiStyle.direction()
	var col := UiStyle.vbox(6); col.position = Vector2(8, 8); col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_TOP_WIDE); col.offset_left = 8; col.offset_right = -8; col.offset_top = 8
	add_child(col)
	row = UiStyle.hbox(8); row.mouse_filter = Control.MOUSE_FILTER_IGNORE; col.add_child(row)
	_build_card(); row.add_child(UiStyle.spacer()); _build_pills()
	var info := PanelContainer.new(); info.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GLASS, 14, 5)); info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ih := UiStyle.hbox(6); info.add_child(ih)
	info_icon = UiIcons.glyph("sun", 18, UiStyle.GOLD) as UiIcons.Glyph; ih.add_child(info_icon)
	info_label = UiStyle.one_line(UiStyle.label("", 13, Color.WHITE, true)); ih.add_child(info_label)
	col.add_child(info)
	Game.profile.changed.connect(func(): if not hold: sync())
	sync()

func _build_card() -> void:
	card = PanelContainer.new(); card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GLASS, 30, 6))
	var h := UiStyle.hbox(8); card.add_child(h)
	h.add_child(UiStyle.portrait("noa", 50))
	var v := UiStyle.vbox(2); h.add_child(v)
	var name_row := UiStyle.hbox(4); v.add_child(name_row)
	name_row.add_child(UiStyle.one_line(UiStyle.label(Loc.t("npc.noa"), 15, Color.WHITE, true)))
	var bar_row := UiStyle.hbox(-6); v.add_child(bar_row)
	star = UiIcons.star(26, 1); bar_row.add_child(star)
	xp_bar = UiStyle.bar(0, 100, UiStyle.GOLD_DEEP, 18); xp_bar.custom_minimum_size = Vector2(96, 18)
	xp_bar.add_theme_stylebox_override("background", UiStyle.panel(Color(1, 1, 1, 0.16), 9, 0, false))
	bar_row.add_child(xp_bar)
	xp_label = UiStyle.one_line(UiStyle.label("", 11, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)); xp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; xp_label.text_direction = Control.TEXT_DIRECTION_LTR; UiStyle.outline(xp_label, Color(0, 0, 0, 0.6), 3)
	xp_bar.add_child(xp_label)
	row.add_child(card)

func _build_pills() -> void:
	var box := UiStyle.vbox(4); box.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(box)
	cash_pill = _pill(); var h1 := cash_pill.get_child(0) as HBoxContainer
	coin_icon = UiIcons.coin(22); h1.add_child(coin_icon)
	cash_label = UiStyle.one_line(UiStyle.label("0", 16, Color.WHITE, true)); cash_label.text_direction = Control.TEXT_DIRECTION_LTR; h1.add_child(cash_label)
	rep_pill = _pill(); var h2 := rep_pill.get_child(0) as HBoxContainer
	h2.add_child(UiIcons.smiley(22))
	rep_label = UiStyle.one_line(UiStyle.label("50%", 16, Color.WHITE, true)); rep_label.text_direction = Control.TEXT_DIRECTION_LTR; h2.add_child(rep_label)
	box.add_child(cash_pill); box.add_child(rep_pill)

func _pill() -> PanelContainer:
	var p := PanelContainer.new(); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GLASS, 18, 5))
	var h := UiStyle.hbox(5); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(h)
	p.pivot_offset = Vector2(40, 16)
	return p

func _set_cash(v: int) -> void:
	shown_cash = v
	if cash_label:
		cash_label.text = Loc.number(v)
		cash_label.add_theme_color_override("font_color", Color.WHITE if v >= 0 else Color("ff9b8f"))

func _set_rep(v: int) -> void:
	shown_rep = v
	if rep_label: rep_label.text = "%d%%" % v

func set_xp_display(level: int, xp_in_level: int, span: int) -> void:
	shown_level = level; shown_xp = xp_in_level; shown_span = span
	star.value = level
	xp_bar.max_value = maxi(1, span); xp_bar.value = xp_in_level if span > 0 else xp_bar.max_value
	xp_label.text = "%d/%d" % [xp_in_level, span] if span > 0 else "MAX"

func set_xp_value(v: float) -> void:
	xp_bar.value = v
	xp_label.text = "%d/%d" % [int(v), shown_span]

func set_info(text: String, weather: String) -> void:
	info_label.text = text
	info_icon.kind = {"sunny": "sun", "hot": "sun", "rain": "rain", "cloudy": "cloud"}.get(weather, "sun")
	info_icon.color = UiStyle.GOLD if info_icon.kind == "sun" else Color("cfe3f2")
	info_icon.queue_redraw()

func sync() -> void:
	var co: Company = Game.co
	shown_cash = co.profile.cash
	shown_rep = co.units[rep_biz].reputation if co.units.has(rep_biz) else 50
	set_xp_display(co.profile.level, co.profile.xp_in_level(), co.profile.level_span())

func punch(node: Control) -> void:
	var tw := create_tween(); tw.tween_property(node, "scale", Vector2(1.18, 1.18), 0.07); tw.tween_property(node, "scale", Vector2.ONE, 0.12)

func cash_target() -> Vector2:
	return coin_icon.get_global_rect().get_center()
