class_name SaleCalc
extends RefCounted
# Turns a product and a few modifiers into the money, experience and reputation of one sale.
# All integer math: a percentage discount uses integer division, never floats.
# The modifiers are where later choices plug in (a discount, a better offer, a mistake).

static func compute(product: Dictionary, ctx: Dictionary, rep_per_sale: int, first_sale: bool, first_sale_xp: int) -> Dictionary:
	var price: int = product["price"]
	var discount_pct := clampi(int(ctx.get("discount_pct", 0)), 0, 100)
	var revenue := price * (100 - discount_pct) / 100
	var cost: int = product["cost"]
	var xp: int = product["xp"] + int(ctx.get("xp_bonus", 0))
	var bonus_xp := first_sale_xp if first_sale else 0
	return {
		"revenue": revenue, "cost": cost, "profit": revenue - cost,
		"xp": xp, "bonus_xp": bonus_xp, "xp_total": xp + bonus_xp,
		"reputation": rep_per_sale + int(ctx.get("reputation_bonus", 0)) - (3 if discount_pct >= 40 else 0),
		"discount_pct": discount_pct, "first_sale": first_sale,
	}
