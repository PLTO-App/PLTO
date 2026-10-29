class_name Fonts
extends RefCounted
# The game's fonts: Noto Sans Hebrew (OFL, from the Ubuntu fonts-noto-core package) with Noto Sans as the fallback for Latin letters
# and digits. Godot's built-in font has no Hebrew. A new language adds its font to the fallback chain here.

static var _cache := {}

static func get_font(bold := false) -> Font:
	var key := "b" if bold else "r"
	if not _cache.has(key):
		var main: FontFile = load("res://assets/fonts/NotoSansHebrew-%s.ttf" % ("Bold" if bold else "Regular"))
		var latin: FontFile = load("res://assets/fonts/NotoSans-%s.ttf" % ("Bold" if bold else "Regular"))
		var f := FontVariation.new(); f.base_font = main; f.fallbacks = [latin]
		_cache[key] = f
	return _cache[key]
