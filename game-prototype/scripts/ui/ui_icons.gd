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

# Simple line icons for buttons, drawn in code: plan, truck, people, upgrade, bank, goals, gear, store, close, check, dot.
class Glyph extends Control:
	var kind := "plan"
	var color := Color.WHITE
	func _draw() -> void:
		var s := minf(size.x, size.y); var o := (size - Vector2(s, s)) / 2.0
		var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
		var w := maxf(2.0, s * 0.08)
		match kind:
			"plan":
				draw_rect(Rect2(p.call(0.2, 0.15), Vector2(0.6, 0.75) * s), color, false, w)
				draw_rect(Rect2(p.call(0.35, 0.08), Vector2(0.3, 0.14) * s), color)
				for i in 3: draw_line(p.call(0.32, 0.38 + i * 0.16), p.call(0.68, 0.38 + i * 0.16), color, w * 0.8)
			"truck":
				draw_rect(Rect2(p.call(0.08, 0.3), Vector2(0.52, 0.38) * s), color, false, w)
				draw_polyline(PackedVector2Array([p.call(0.6, 0.4), p.call(0.78, 0.4), p.call(0.92, 0.55), p.call(0.92, 0.68), p.call(0.6, 0.68)]), color, w)
				draw_circle(p.call(0.27, 0.74), s * 0.08, color); draw_circle(p.call(0.75, 0.74), s * 0.08, color)
			"people":
				draw_circle(p.call(0.35, 0.32), s * 0.12, color); draw_circle(p.call(0.68, 0.36), s * 0.1, color)
				draw_arc(p.call(0.35, 0.78), s * 0.22, PI, TAU, 16, color, w); draw_arc(p.call(0.7, 0.78), s * 0.18, PI, TAU, 16, color, w)
			"upgrade":
				draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.12), p.call(0.82, 0.48), p.call(0.62, 0.48), p.call(0.62, 0.85), p.call(0.38, 0.85), p.call(0.38, 0.48), p.call(0.18, 0.48)]), color)
			"bank":
				draw_colored_polygon(PackedVector2Array([p.call(0.1, 0.35), p.call(0.5, 0.1), p.call(0.9, 0.35)]), color)
				for i in 4: draw_rect(Rect2(p.call(0.18 + i * 0.19, 0.4), Vector2(0.08, 0.36) * s), color)
				draw_rect(Rect2(p.call(0.1, 0.8), Vector2(0.8, 0.08) * s), color)
			"goals":
				draw_line(p.call(0.28, 0.1), p.call(0.28, 0.9), color, w)
				draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.12), p.call(0.82, 0.25), p.call(0.3, 0.42)]), color)
			"gear":
				draw_circle(p.call(0.5, 0.5), s * 0.26, color); draw_circle(p.call(0.5, 0.5), s * 0.1, Color(0, 0, 0, 0.35))
				for i in 8:
					var a := i * TAU / 8.0
					draw_line(p.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * s * 0.24, p.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * s * 0.4, color, w * 1.6)
			"store":
				draw_rect(Rect2(p.call(0.15, 0.42), Vector2(0.7, 0.45) * s), color, false, w)
				for i in 4: draw_rect(Rect2(p.call(0.12 + i * 0.19, 0.2), Vector2(0.19, 0.2) * s), color if i % 2 == 0 else Color(color, 0.5))
			"close":
				draw_line(p.call(0.25, 0.25), p.call(0.75, 0.75), color, w * 1.3); draw_line(p.call(0.75, 0.25), p.call(0.25, 0.75), color, w * 1.3)
			"check":
				draw_polyline(PackedVector2Array([p.call(0.2, 0.52), p.call(0.42, 0.74), p.call(0.82, 0.28)]), color, w * 1.4)
			"dot":
				draw_circle(p.call(0.5, 0.5), s * 0.16, color)
			"sun":
				draw_circle(p.call(0.5, 0.5), s * 0.2, color)
				for i in 8:
					var a := i * TAU / 8.0
					draw_line(p.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * s * 0.28, p.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * s * 0.42, color, w)
			"rain":
				draw_circle(p.call(0.4, 0.4), s * 0.18, color); draw_circle(p.call(0.62, 0.42), s * 0.16, color); draw_rect(Rect2(p.call(0.25, 0.42), Vector2(0.52, 0.14) * s), color)
				for i in 3: draw_line(p.call(0.32 + i * 0.16, 0.66), p.call(0.28 + i * 0.16, 0.84), color, w)
			"cloud":
				draw_circle(p.call(0.4, 0.5), s * 0.18, color); draw_circle(p.call(0.62, 0.48), s * 0.2, color); draw_rect(Rect2(p.call(0.22, 0.52), Vector2(0.6, 0.16) * s), color)

static func glyph(kind: String, px: float, color := Color.WHITE) -> Control:
	var g := Glyph.new(); g.kind = kind; g.color = color; g.custom_minimum_size = Vector2(px, px); g.size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g
