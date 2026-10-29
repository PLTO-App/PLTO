class_name UiIcons
extends RefCounted
# Small icons drawn in code (no image files): the coin, the smiley for reputation, the level star.

class CoinIcon extends Control:
	func _draw() -> void:
		var c := size / 2.0; var r := minf(size.x, size.y) / 2.0
		draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.25))
		draw_circle(c, r, UiStyle.GOLD_DEEP); draw_circle(c, r * 0.86, UiStyle.GOLD)
		draw_arc(c, r * 0.66, 0.0, TAU, 28, Color(1, 1, 1, 0.45), 1.6, true)
		var f := UiStyle.bold(); var fs := int(r * 1.15)
		var w := f.get_string_size("₪", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - w.x / 2.0, c.y + fs * 0.36), "₪", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("a8591a"))

class SmileyIcon extends Control:
	func _draw() -> void:
		var c := size / 2.0; var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color("e8a21a")); draw_circle(c, r * 0.9, Color("ffd23f"))
		draw_circle(c + Vector2(-r * 0.32, -r * 0.18), r * 0.11, Color("4a2c10")); draw_circle(c + Vector2(r * 0.32, -r * 0.18), r * 0.11, Color("4a2c10"))
		draw_arc(c + Vector2(0, r * 0.05), r * 0.5, 0.35, PI - 0.35, 16, Color("4a2c10"), maxf(1.5, r * 0.12), true)

class StarBadge extends Control:
	var value := 1: set = _set_value
	func _set_value(v: int) -> void:
		value = v; queue_redraw()
	func _draw() -> void:
		var c := size / 2.0; var r := minf(size.x, size.y) / 2.0
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0; var rr := r if i % 2 == 0 else r * 0.52
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, UiStyle.GOLD_DEEP)
		var inner := PackedVector2Array()
		for p in pts: inner.append(c + (p - c) * 0.84)
		draw_colored_polygon(inner, UiStyle.GOLD)
		var f := UiStyle.bold(); var fs := int(r * 0.95); var s := str(value)
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - w.x / 2.0, c.y + fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("7a3d0c"))

static func coin(px: float) -> Control:
	var c := CoinIcon.new(); c.custom_minimum_size = Vector2(px, px); c.size = Vector2(px, px); c.pivot_offset = Vector2(px, px) / 2.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE; return c

static func smiley(px: float) -> Control:
	var c := SmileyIcon.new(); c.custom_minimum_size = Vector2(px, px); c.size = Vector2(px, px); c.pivot_offset = Vector2(px, px) / 2.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE; return c

static func star(px: float, level: int) -> StarBadge:
	var c := StarBadge.new(); c.custom_minimum_size = Vector2(px, px); c.size = Vector2(px, px); c.pivot_offset = Vector2(px, px) / 2.0
	c.value = level; c.mouse_filter = Control.MOUSE_FILTER_IGNORE; return c
