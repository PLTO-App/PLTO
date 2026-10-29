class_name RewardFx
extends Control
# The reward moment of a sale: coins fly from the customer to the cash pill and the number rises as each one lands (with a rising
# "ding"), the reputation pill ticks up, the experience bar fills (and a level-up banner appears if a level is crossed).
# It only plays what the game systems already decided; the money was added to the profile before this started.

var hud: Hud
var _banner: PanelContainer
var _landed := 0

func float_text(text: String, pos: Vector2, color: Color, size := 26) -> void:
	var l := UiStyle.label(text, size, color, true); l.autowrap_mode = TextServer.AUTOWRAP_OFF; UiStyle.outline(l, Color(0.1, 0.07, 0.03, 0.95), 8)
	l.text_direction = Control.TEXT_DIRECTION_LTR; l.size = Vector2(160, size + 10); l.position = pos - Vector2(80, size); l.pivot_offset = Vector2(80, size / 2.0); l.scale = Vector2(0.4, 0.4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 1.3)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tw.chain().tween_callback(l.queue_free)

# `before` = {"level": int, "xp": int} read before the sale was recorded.
func play_sale(result: Dictionary, origin: Vector2, before: Dictionary) -> void:
	hud.hold = true
	hud.shown_cash = before["cash"]; hud.shown_rep = before["rep"]
	var profit: int = result["profit"]
	if profit > 0: float_text("+₪%s" % UiStyle.number(profit), origin + Vector2(0, -34), UiStyle.GOLD, 30)
	await _coins(profit, origin)
	# reputation
	if result["reputation"] != 0:
		hud.shown_rep = Game.profile.reputation; hud.punch(hud.rep_pill)
		float_text("%s%d%%" % ["+" if result["reputation"] > 0 else "-", absi(result["reputation"])], hud.rep_pill.get_global_rect().get_center() + Vector2(0, 46), Color("ffe27a"), 18)
		await get_tree().create_timer(0.25).timeout
	await _xp(result["xp_total"], before)
	hud.hold = false; hud.sync()

func _coins(profit: int, origin: Vector2) -> void:
	if profit <= 0:
		hud.shown_cash = Game.profile.cash; return
	var n := clampi(profit / 12 + 3, 6, 16)
	var base := profit / n; var rest := profit - base * n
	var target := hud.cash_target()
	var start_cash := Game.profile.cash - profit
	_landed = 0
	for i in n:
		var coin := UiIcons.coin(30); add_child(coin)
		var amount := base + (rest if i == n - 1 else 0)
		var p0 := origin + Vector2(randf_range(-16, 16), randf_range(-10, 10))
		var c := (p0 + target) / 2.0 + Vector2(randf_range(-70, 70), -randf_range(60, 130))
		coin.position = p0 - coin.size / 2.0; coin.scale = Vector2(0.2, 0.2)
		var tw := create_tween(); tw.tween_interval(0.05 * i)
		tw.tween_method(_fly.bind(coin, p0, c, target), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(_land.bind(coin, amount))
	await get_tree().create_timer(0.05 * n + 0.75).timeout
	hud.shown_cash = start_cash + profit

func _fly(t: float, coin: Control, p0: Vector2, c: Vector2, target: Vector2) -> void:
	var q := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * c + t * t * target
	coin.position = q - coin.size / 2.0
	coin.scale = Vector2.ONE * lerpf(0.2, 1.0, minf(1.0, t * 3.0)) * lerpf(1.0, 0.7, t)

func _land(coin: Control, amount: int) -> void:
	_landed += 1
	hud.shown_cash += amount
	hud.punch(hud.cash_pill)
	Game.sfx.play("coin", 1.0 + 0.035 * _landed, -3.0)
	coin.queue_free()

func _xp(gain: int, before: Dictionary) -> void:
	var db := Game.content
	var lvl: int = before["level"]; var xp: int = before["xp"]
	var remaining := gain
	hud.set_xp_display(lvl, xp - db.levels[lvl - 1], db.levels[lvl] - db.levels[lvl - 1] if lvl < db.levels.size() else 0)
	float_text("+%d XP" % gain, hud.card.get_global_rect().get_center() + Vector2(10, 52), Color("ffe27a"), 17)
	while remaining > 0 and lvl < db.levels.size():
		var span := db.levels[lvl] - db.levels[lvl - 1]; var in_level := xp - db.levels[lvl - 1]
		var add := mini(remaining, span - in_level)
		hud.shown_span = span
		var tw := create_tween(); tw.tween_method(hud.set_xp_value, float(in_level), float(in_level + add), clampf(0.9 * add / span, 0.3, 0.9))
		await tw.finished
		xp += add; remaining -= add
		if in_level + add >= span:
			lvl += 1
			await _level_up(lvl)
			hud.set_xp_display(lvl, 0, db.levels[lvl] - db.levels[lvl - 1] if lvl < db.levels.size() else 0)
	hud.punch(hud.card)

func _level_up(level: int) -> void:
	Game.sfx.play("levelup")
	if _banner != null: _banner.queue_free()
	_banner = PanelContainer.new(); _banner.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.CREAM, 0.97), 28, 20))
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 6); col.alignment = BoxContainer.ALIGNMENT_CENTER; _banner.add_child(col)
	var st := UiIcons.star(84, level); st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; col.add_child(st)
	var t1 := UiStyle.label("דרגה חדשה", 22, UiStyle.INK, true); t1.autowrap_mode = TextServer.AUTOWRAP_OFF; col.add_child(t1)
	var t2 := UiStyle.label("דרגה %d" % level, 15, UiStyle.MUTED); t2.autowrap_mode = TextServer.AUTOWRAP_OFF; col.add_child(t2)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_banner)
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	_banner.position = (vp - _banner.size) / 2.0 - Vector2(0, 40); _banner.pivot_offset = _banner.size / 2.0; _banner.scale = Vector2(0.3, 0.3); _banner.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.2)
	await get_tree().create_timer(1.7).timeout
	var tw2 := create_tween(); tw2.tween_property(_banner, "modulate:a", 0.0, 0.3)
	await tw2.finished
	_banner.queue_free(); _banner = null
