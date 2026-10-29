class_name Loc
extends RefCounted
# Texts and formats for the player's language. Every visible text lives in locale/strings.csv (one column per language) and the code
# refers to it by key. Number, money and direction rules per language are in locale/formats.json, so a new language is a new column
# and a new entry there, not a code change. Hebrew is the default.
#
# Messages that are stored (in the save or a summary) are kept as {"k": key, "p": params} and translated only when shown, so a change
# of language also changes old messages. Param naming: a name ending in _m is money (whole shekels), _k is another translation key,
# _n is a number with digit grouping. Anything else is shown as is.

const DEFAULT := "he"
static var locale := DEFAULT
static var _formats := {}

static func setup(p_locale := DEFAULT) -> void:
	locale = p_locale
	TranslationServer.set_locale(locale)
	if _formats.is_empty():
		var f := FileAccess.open("res://locale/formats.json", FileAccess.READ)
		if f != null: _formats = JSON.parse_string(f.get_as_text())
	if _formats == null: _formats = {}

static func fmt() -> Dictionary:
	if _formats.is_empty(): setup(locale)
	return _formats.get(locale, _formats.get(DEFAULT, {}))

static func is_rtl() -> bool:
	return str(fmt().get("dir", "rtl")) == "rtl"

static func t(key: String, p := {}) -> String:
	var s := String(TranslationServer.translate(key))
	if p.is_empty(): return s
	var q := {}
	for k in p:
		var name := String(k); var v = p[k]
		if name.ends_with("_m"): q[name] = money(int(v))
		elif name.ends_with("_k"): q[name] = String(TranslationServer.translate(str(v)))
		elif name.ends_with("_n"): q[name] = number(int(v))
		else: q[name] = str(v)
	return s.format(q)

static func msg(m) -> String:
	if m is String: return t(m)
	if m is Dictionary: return t(str(m.get("k", "")), m.get("p", {}))
	return str(m)

static func m(key: String, p := {}) -> Dictionary:
	return {"k": key, "p": p}

# 1234 -> "1,234" (grouping from the language format)
static func number(n: int) -> String:
	var s := str(absi(n)); var out := ""; var g := str(fmt().get("group", ","))
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0: out += g
		out += s[i]
	return ("-" if n < 0 else "") + out

# Whole shekels with the currency sign where the language puts it. sign=true adds "+" to positive amounts.
static func money(n: int, sign := false) -> String:
	var f := fmt(); var cur := str(f.get("currency", "₪"))
	var body := number(absi(n))
	var s := (body + " " + cur) if bool(f.get("currency_after", true)) else (cur + body)
	if n < 0: return "-" + s
	return ("+" + s) if sign and n > 0 else s

# A compact amount for tight places (pills, floating numbers): "₪1,234", "+₪290". Always left-to-right.
static func money_short(n: int, sign := false) -> String:
	var cur := str(fmt().get("currency", "₪"))
	return ("-" if n < 0 else ("+" if sign and n > 0 else "")) + cur + number(absi(n))

static func weekday(day: int, keys: Array) -> String:
	return t(str(keys[(day - 1) % keys.size()]))
