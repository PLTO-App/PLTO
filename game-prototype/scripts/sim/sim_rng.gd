class_name SimRng
extends RefCounted
# Seeded random numbers for the simulation: the same save seed, day and purpose always give the same numbers,
# so a day can be replayed and balance tests are repeatable.

var r := RandomNumberGenerator.new()

func _init(seed_value: int, day: int, purpose: String) -> void:
	r.seed = hash([seed_value, day, purpose])

func int_range(a: int, b: int) -> int:
	return r.randi_range(a, b)

# Index chosen by integer weights.
func weighted(weights: Array) -> int:
	var total := 0
	for w in weights: total += int(w)
	if total <= 0: return 0
	var x := r.randi_range(0, total - 1)
	for i in weights.size():
		x -= int(weights[i])
		if x < 0: return i
	return weights.size() - 1
