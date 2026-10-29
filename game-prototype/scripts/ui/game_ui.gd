class_name GameUi
extends CanvasLayer
# Everything drawn over the 3D world: the top bar, the side buttons (goals, settings), the town's bottom bar with the call to
# action, the management sheet, event cards with the speaker's portrait, the working day's strip and action button, the floating
# joystick, short hints, the reward effects, and a fade for scene changes. Right to left for Hebrew (it follows the language).

signal action_pressed
signal cta_pressed
signal card_choice(index: int)

var move_vec := Vector2.ZERO
var override_vec := Vector2.ZERO
var use_override := false
var input_enabled := true

var root := Control.new()
var hud: Hud
var fx: RewardFx
var sheet: Sheet
var screens: Screens
var stick: StickView
var side: VBoxContainer
var goals_badge: Label
var bottom: PanelContainer
var cta: Button
var nav_buttons := {}
var strip: PanelContainer
var strip_clock: Label
var strip_queue: Label
var strip_box: HBoxContainer
var strip_chips := {}
var objective_panel: PanelContainer
var objective_label: Label
var action_button: Button
var hint_panel: PanelContainer
var hint_label: Label
var card_dim: ColorRect
var card_panel: PanelContainer
var card_portrait: Control
var card_who: Label
var card_title: Label
var card_body: Label
var card_note: Label
var card_choices: VBoxContainer
var fade: ColorRect
var fps_label: Label
var _stick_touch := -1
var _fps_t := 0.0
var _hint_tw: Tween

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
	root.theme = UiStyle.theme(); root.layout_direction = UiStyle.direction()
	root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(_vignette())
	stick = StickView.new(); stick.set_anchors_preset(Control.PRESET_FULL_RECT); stick.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(stick)
	hud = Hud.new(); root.add_child(hud)
	_build_side(); _build_bottom(); _build_strip(); _build_objective(); _build_action(); _build_hint()
	fx = RewardFx.new(); fx.hud = hud; fx.mouse_filter = Control.MOUSE_FILTER_IGNORE; fx.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(fx)
	sheet = Sheet.new(); root.add_child(sheet)
	screens = Screens.new(self)
	_build_card()
	fps_label = Label.new(); fps_label.add_theme_font_size_override("font_size", 11); fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(fps_label)
	fade = ColorRect.new(); fade.color = Color(0.05, 0.08, 0.16, 0.0); fade.set_anchors_preset(Control.PRESET_FULL_RECT); fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	get_viewport().size_changed.connect(_layout); _layout()

func _vignette() -> TextureRect:
	var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.06, 0.03, 0.0, 0.28)])
	var tex := GradientTexture2D.new(); tex.gradient = g; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(1.0, 0.5); tex.width = 128; tex.height = 128
	var tr := TextureRect.new(); tr.texture = tex; tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT); tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _round_button(kind: String, tip: String) -> Button:
	var b := Button.new(); b.custom_minimum_size = Vector2(56, 56); b.focus_mode = Control.FOCUS_NONE; b.tooltip_text = tip
	for st in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(st, UiStyle.panel(UiStyle.GLASS if st != "pressed" else UiStyle.INK, 28, 4))
	var g := UiIcons.glyph(kind, 30, Color.WHITE); g.position = Vector2(13, 13); b.add_child(g)
	return b

func _build_side() -> void:
	side = UiStyle.vbox(8); side.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(side)
	var gb := _round_button("goals", Loc.t("ui.goals")); gb.pressed.connect(func(): _tap(); open_screen("goals")); side.add_child(gb)
	goals_badge = UiStyle.one_line(UiStyle.label("", 12, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER))
	var badge := PanelContainer.new(); badge.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.CORAL, 10, 2, false)); badge.add_child(goals_badge)
	badge.position = Vector2(36, -4); badge.mouse_filter = Control.MOUSE_FILTER_IGNORE; gb.add_child(badge)
	var sb := _round_button("gear", Loc.t("ui.settings")); sb.pressed.connect(func(): _tap(); open_screen("settings")); side.add_child(sb)

func _build_bottom() -> void:
	bottom = PanelContainer.new(); bottom.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.CREAM, 0.96), 24, 8))
	var col := UiStyle.vbox(8); bottom.add_child(col)
	cta = UiStyle.button("", "cta", 19, 56); cta.pressed.connect(func(): _tap(); cta_pressed.emit()); col.add_child(cta)
	var row := UiStyle.hbox(6); col.add_child(row)
	for spec in [["plan", "today", "ui.nav_today"], ["truck", "orders", "ui.nav_orders"], ["people", "staff", "ui.nav_staff"], ["upgrade", "upgrades", "ui.nav_upgrades"], ["bank", "finance", "ui.nav_finance"]]:
		var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size = Vector2(0, 62)
		for st in ["normal", "hover", "pressed", "focus"]:
			var s := UiStyle.panel(Color("ffffff") if st != "pressed" else Color("e8eefc"), 14, 4, false); s.border_color = UiStyle.LINE; s.set_border_width_all(1)
			b.add_theme_stylebox_override(st, s)
		var v := UiStyle.vbox(0); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := UiIcons.glyph(spec[0], 26, UiStyle.ACCENT); g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; v.add_child(g)
		v.add_child(UiStyle.one_line(UiStyle.label(Loc.t(spec[2]), 11, UiStyle.INK, true, HORIZONTAL_ALIGNMENT_CENTER)))
		b.add_child(v)
		var screen: String = spec[1]
		b.pressed.connect(func(): _tap(); open_screen(screen))
		row.add_child(b); nav_buttons[screen] = b
	root.add_child(bottom)

func _build_strip() -> void:
	strip = PanelContainer.new(); strip.mouse_filter = Control.MOUSE_FILTER_IGNORE; strip.visible = false
	strip.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.CREAM, 0.94), 14, 6))
	strip_box = UiStyle.hbox(8); strip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; strip.add_child(strip_box)
	root.add_child(strip)

func setup_strip(bid: String) -> void:
	for c in strip_box.get_children(): c.queue_free()
	strip_chips = {}
	strip_clock = UiStyle.one_line(UiStyle.label("", 13, UiStyle.MUTED, true)); strip_clock.text_direction = Control.TEXT_DIRECTION_LTR; strip_box.add_child(strip_clock)
	strip_box.add_child(UiStyle.spacer())
	var db: Dictionary = Game.co.units[bid].db
	for pid in db["products"]:
		var pr: Dictionary = db["products"][pid]
		if pr.get("made_to_order", false) and pid != "cappuccino": continue
		strip_box.add_child(UiStyle.icon(UiStyle.item_icon_id(pid), 24))
		var l := UiStyle.one_line(UiStyle.label("0", 14, UiStyle.INK, true)); l.text_direction = Control.TEXT_DIRECTION_LTR; strip_box.add_child(l); strip_chips[pid] = l
	strip_box.add_child(UiStyle.spacer())
	strip_queue = UiStyle.one_line(UiStyle.label("", 13, UiStyle.INK, true)); strip_box.add_child(strip_queue)

func set_strip(clock: String, stock: Dictionary, queue_n: int) -> void:
	if strip_clock == null: return
	strip_clock.text = clock; strip_queue.text = Loc.t("ui.in_queue", {"n": queue_n})
	for pid in strip_chips: strip_chips[pid].text = str(stock.get(pid, 0))

func _build_objective() -> void:
	objective_panel = PanelContainer.new(); objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.CREAM, 0.95), 16, 9))
	objective_label = UiStyle.label("", 16, UiStyle.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	objective_panel.add_child(objective_label); root.add_child(objective_panel); objective_panel.visible = false

func _build_action() -> void:
	action_button = UiStyle.button("", "cta", 19, 64); action_button.visible = false; action_button.custom_minimum_size = Vector2(160, 64)
	action_button.pressed.connect(func(): action_pressed.emit()); root.add_child(action_button)

func _build_hint() -> void:
	hint_panel = PanelContainer.new(); hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; hint_panel.visible = false
	hint_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GLASS, 14, 10))
	hint_label = UiStyle.label("", 15, Color.WHITE, false, HORIZONTAL_ALIGNMENT_CENTER); hint_panel.add_child(hint_label)
	root.add_child(hint_panel)

func _build_card() -> void:
	card_dim = ColorRect.new(); card_dim.color = Color(0.04, 0.08, 0.18, 0.55); card_dim.set_anchors_preset(Control.PRESET_FULL_RECT); card_dim.visible = false
	card_dim.mouse_filter = Control.MOUSE_FILTER_STOP; root.add_child(card_dim)
	var center := CenterContainer.new(); center.set_anchors_preset(Control.PRESET_FULL_RECT); center.mouse_filter = Control.MOUSE_FILTER_IGNORE; card_dim.add_child(center)
	card_panel = PanelContainer.new(); card_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.CREAM, 24, 18)); center.add_child(card_panel)
	var box := UiStyle.vbox(10); card_panel.add_child(box)
	var head := UiStyle.hbox(10); box.add_child(head)
	card_portrait = Control.new(); head.add_child(card_portrait)
	var hv := UiStyle.vbox(0); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hv.alignment = BoxContainer.ALIGNMENT_CENTER; head.add_child(hv)
	card_who = UiStyle.label("", 13, UiStyle.ACCENT, true); hv.add_child(card_who)
	card_title = UiStyle.label("", 21, UiStyle.INK, true); hv.add_child(card_title)
	card_body = UiStyle.label("", 16, UiStyle.INK); box.add_child(card_body)
	card_note = UiStyle.label("", 14, UiStyle.MUTED); box.add_child(card_note)
	card_choices = UiStyle.vbox(8); box.add_child(card_choices)

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
	var portrait := h > w
	# side buttons at the end side, under the top bar
	side.position = Vector2(8 if UiStyle.rtl() else w - 64, 158 if strip.visible else 112)
	var bw := w - 16.0 if portrait else minf(560.0, w * 0.6)
	bottom.size = Vector2(bw, 0); bottom.position = Vector2((w - bw) / 2.0, h - 150.0)
	strip.size = Vector2(w - 16.0, 0); strip.position = Vector2(8, 104)
	var ow := minf(w - 32.0, 360.0)
	objective_label.custom_minimum_size.x = ow - 28.0; objective_panel.position = Vector2((w - ow) / 2.0, 150); objective_panel.size = Vector2(ow, 0)
	var aw := minf(w - 40.0, 360.0)
	action_button.custom_minimum_size = Vector2(aw, 64); action_button.size = Vector2(aw, 64); action_button.position = Vector2((w - aw) / 2.0, h - 92.0)
	var hw := minf(w - 40.0, 340.0)
	hint_label.custom_minimum_size.x = hw - 24.0; hint_panel.custom_minimum_size.x = hw; hint_panel.size = Vector2(hw, 0)
	hint_panel.position = Vector2((w - hw) / 2.0, h - (250.0 if bottom.visible else 190.0))
	card_panel.custom_minimum_size.x = minf(w - 36.0, 400.0)
	fps_label.position = Vector2(10, h - 18)

func _tap() -> void:
	Game.sfx.play("tap", 1.0, -6.0)

# ---------------------------------------------------------------- modes
func show_town_bar(on: bool, cta_text := "") -> void:
	bottom.visible = on; cta.text = cta_text
	_layout()

func show_day_ui(on: bool) -> void:
	strip.visible = on
	_layout()
	if not on: set_objective(""); set_action("")

func update_goals_badge() -> void:
	var a := Goals.active(Game.co)
	var ready := 0
	for g in a: if Goals.progress(Game.co, g) >= 100: ready += 1
	goals_badge.text = str(Game.co.goals_done.size())
	goals_badge.get_parent().visible = true

# ---------------------------------------------------------------- screens in the sheet
func open_screen(id: String, opts := {}) -> void:
	var s := screens
	match id:
		"today": sheet.open(Loc.t("today.short"), s.today, {"id": id, "closable": true})
		"orders": sheet.open(Loc.t("orders.title"), s.orders, {"id": id})
		"staff": sheet.open(Loc.t("staff.title"), s.staff, {"id": id})
		"finance": sheet.open(Loc.t("fin.title"), s.finance, {"id": id, "tabs": [Loc.t("fin.tab_status"), Loc.t("fin.tab_loans"), Loc.t("fin.tab_services")], "tab": opts.get("tab", 0)})
		"upgrades":
			var names: Array = []
			for bid in Game.co.units: names.append(s.biz_name(bid))
			sheet.open(Loc.t("upg.title"), s.upgrades, {"id": id, "tabs": names, "tab": opts.get("tab", 0)})
		"goals": sheet.open(Loc.t("ui.goals"), s.goals, {"id": id})
		"settings": sheet.open(Loc.t("set.title"), s.settings, {"id": id})
		"building": sheet.open("", func(sh): s.building(sh, opts["building"]), {"id": id})
		"summary": sheet.open("", func(sh): s.summary(sh, opts["summary"]), {"id": id, "closable": false, "tabs": [Loc.t("sum.tab_day"), Loc.t("sum.tab_pl"), Loc.t("sum.tab_units")]})
		"week": sheet.open("", func(sh): s.week(sh, opts["week"]), {"id": id, "closable": false})

# ---------------------------------------------------------------- event and story cards
# spec: who (person id or ""), who_name, title, body, note, choices: [String]  -> emits card_choice(i)
func show_card(spec: Dictionary) -> void:
	card_portrait.get_parent().remove_child(card_portrait); card_portrait.queue_free()
	var who: String = spec.get("who", "")
	card_portrait = UiStyle.portrait(who, 72) if who != "" else Control.new()
	(card_title.get_parent().get_parent() as HBoxContainer).add_child(card_portrait)
	(card_title.get_parent().get_parent() as HBoxContainer).move_child(card_portrait, 0)
	card_who.text = spec.get("who_name", ""); card_who.visible = card_who.text != ""
	card_title.text = spec.get("title", ""); card_body.text = spec.get("body", ""); card_body.visible = card_body.text != ""
	card_note.text = spec.get("note", ""); card_note.visible = card_note.text != ""
	for c in card_choices.get_children(): c.queue_free()
	var choices: Array = spec.get("choices", [Loc.t("ui.continue")])
	for i in choices.size():
		var b := UiStyle.button(choices[i], "cta" if i == 0 else ("secondary" if choices.size() > 2 or i > 0 else "primary"), 17, 52)
		var idx := i
		b.pressed.connect(func(): _tap(); card_choice.emit(idx))
		card_choices.add_child(b)
	card_dim.visible = true; action_button.visible = false; input_enabled = false
	card_panel.pivot_offset = card_panel.size / 2.0; card_panel.scale = Vector2(0.92, 0.92)
	create_tween().tween_property(card_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_end_stick()

func hide_card() -> void:
	card_dim.visible = false; input_enabled = true

# Shows a card and waits for a choice. Returns the index.
func ask(spec: Dictionary) -> int:
	show_card(spec)
	var i: int = await card_choice
	hide_card()
	return i

# ---------------------------------------------------------------- small messages
func set_objective(text: String) -> void:
	objective_panel.visible = text != ""
	objective_label.text = text

func set_action(text: String) -> void:
	action_button.visible = text != "" and not card_dim.visible and not sheet.visible
	if text != "": action_button.text = text

func show_hint(text: String, seconds := 3.0) -> void:
	hint_label.text = text; hint_panel.visible = true; hint_panel.modulate.a = 1.0
	_layout()
	if _hint_tw != null and _hint_tw.is_valid(): _hint_tw.kill()
	_hint_tw = create_tween(); _hint_tw.tween_interval(seconds); _hint_tw.tween_property(hint_panel, "modulate:a", 0.0, 0.6)
	_hint_tw.tween_callback(func(): hint_panel.visible = false)

func fade_out(t := 0.35) -> void:
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween(); tw.tween_property(fade, "color:a", 1.0, t); await tw.finished

func fade_in(t := 0.4) -> void:
	var tw := create_tween(); tw.tween_property(fade, "color:a", 0.0, t); await tw.finished
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------------------------------------------------------------- joystick
func _end_stick() -> void:
	_stick_touch = -1; stick.active = false; stick.queue_redraw(); move_vec = Vector2.ZERO

func _blocked(p: Vector2) -> bool:
	if not input_enabled or sheet.visible or card_dim.visible: return true
	if action_button.visible and action_button.get_global_rect().grow(8).has_point(p): return true
	if bottom.visible and bottom.get_global_rect().has_point(p): return true
	for c in side.get_children(): if (c as Control).get_global_rect().grow(6).has_point(p): return true
	return false

var stick_enabled := false

func _stick_start(index: int, p: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	if not stick_enabled or p.y < vp.y * 0.18 or _blocked(p): return
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
	if sheet.visible or card_dim.visible: return Vector2.ZERO
	if move_vec != Vector2.ZERO: return move_vec
	if not input_enabled: return Vector2.ZERO
	return Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")

func _process(delta: float) -> void:
	_fps_t += delta
	if _fps_t >= 0.5:
		_fps_t = 0.0; fps_label.text = "FPS %d" % roundi(Engine.get_frames_per_second())
	if input_enabled and Input.is_action_just_pressed("ui_accept") and action_button.visible: action_pressed.emit()
