class_name UiMoney
extends RefCounted
# Whole shekels as text, shared by the simulation messages and the screens. 1234 -> "1,234 ₪".

static func number(n: int) -> String:
	var s := str(absi(n)); var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0: out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out

static func fmt(n: int) -> String:
	return "%s ₪" % number(n)

# For left-to-right labels (amounts in a column): "-₪15", "+₪290".
static func ltr(n: int, plus := false) -> String:
	return ("-" if n < 0 else ("+" if plus and n > 0 else "")) + "₪" + number(absi(n))
