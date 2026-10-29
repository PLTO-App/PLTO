class_name Hud
extends Control
# The top of the screen: Noa's card with level and experience bar, the cash pill and the reputation pill.
# It shows "shown_*" values. Normally they follow the profile at once. During a reward animation the effects hold
# them back (hold = true) and raise them step by step, so the number rises when the coins land.

var hold := false
var shown_cash := 0: set = _set_cash
var shown_rep := 50: set = _set_rep
var shown_level := 1
var shown_xp := 0
var shown_span := 100

var card: PanelContainer
var cash_pill: PanelContainer
var rep_pill: PanelContainer
var cash_label: Label
var rep_label: Label
var xp_bar: ProgressBar
var xp_label: Label
var star: UiIcons.StarBadge
var coin_icon: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_card(); _build_pills()
	Game.profile.changed.connect(func(): if not hold: sync())
	sync()

func _build_card() -> void:
	card = PanelContainer.new(); card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GLASS, 26, 7)); card.position = Vector2(8, 8)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); card.add_child(row)
	var av := TextureRect.new(); av.texture = load("res://assets/ui/avatar_noa.png")
	av.custom_minimum_size = Vector2(46, 46); av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(av)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 2); row.add_child(col)
	var name_l := UiStyle.label("נועה", 15, Color.WHITE, true); name_l.autowrap_mode = TextServer.AUTOWRAP_OFF; name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; col.add_child(name_l)
	var bar_row := HBoxContainer.new(); bar_row.add_theme_constant_override("separation", -8); col.add_child(bar_row)
	star = UiIcons.star(26, 1); bar_row.add_child(star)
	xp_bar = ProgressBar.new(); xp_bar.custom_minimum_size = Vector2(92, 18); xp_bar.show_percentage = false; xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_bar.add_theme_stylebox_override("background", UiStyle.panel(Color(1, 1, 1, 0.16), 9, 0, false))
	xp_bar.add_theme_stylebox_override("fill", UiStyle.panel(UiStyle.GOLD_DEEP, 9, 0, false))
	bar_row.add_child(xp_bar)
	xp_label = UiStyle.label("", 11, Color.WHITE, true); xp_label.set_anchors_preset(Control.PRESET_FULL_RECT); xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xp_label.autowrap_mode = TextServer.AUTOWRAP_OFF; xp_label.text_direction = Control.TEXT_DIRECTION_LTR; UiStyle.outline(xp_label, Color(0, 0, 0, 0.6), 3); xp_bar.add_child(xp_label)
	add_child(card)

func _build_pills() -> void:
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 4); box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT); box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -8; box.offset_left = -8; box.offset_top = 8; box.offset_bottom = 8
	cash_pill = _pill(); var h1 := cash_pill.get_child(0) as HBoxContainer
	coin_icon = UiIcons.coin(22); h1.add_child(coin_icon)
	cash_label = UiStyle.label("0", 16, Color.WHITE, true); cash_label.autowrap_mode = TextServer.AUTOWRAP_OFF; cash_label.text_direction = Control.TEXT_DIRECTION_LTR; h1.add_child(cash_label)
	rep_pill = _pill(); var h2 := rep_pill.get_child(0) as HBoxContainer
	h2.add_child(UiIcons.smiley(22))
	rep_label = UiStyle.label("50%", 16, Color.WHITE, true); rep_label.autowrap_mode = TextServer.AUTOWRAP_OFF; rep_label.text_direction = Control.TEXT_DIRECTION_LTR; h2.add_child(rep_label)
	box.add_child(cash_pill); box.add_child(rep_pill); add_child(box)

func _pill() -> PanelContainer:
	var p := PanelContainer.new(); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GLASS, 18, 5))
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 5); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(h)
	p.pivot_offset = Vector2(40, 16)
	return p

func _set_cash(v: int) -> void:
	shown_cash = v
	if cash_label: cash_label.text = UiStyle.number(v)

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

func sync() -> void:
	var p := Game.profile
	shown_cash = p.cash; shown_rep = p.reputation
	set_xp_display(p.level, p.xp_in_level(), p.level_span())

func punch(node: Control) -> void:
	var tw := create_tween(); tw.tween_property(node, "scale", Vector2(1.18, 1.18), 0.07); tw.tween_property(node, "scale", Vector2.ONE, 0.12)

func cash_target() -> Vector2:
	return coin_icon.get_global_rect().get_center()
