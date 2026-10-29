class_name GameState
extends RefCounted
# What has happened in the story so far. Later scenes will read these flags and numbers (trust, energy, cash)
# to give choices lasting consequences, as in the script. Chapter 1 only records the preparation steps.

var flags := {}
var trust := 50
var energy := 100
var cash := 0   # whole shekels, never a float

func set_flag(name: String, value := true) -> void:
	flags[name] = value

func has_flag(name: String) -> bool:
	return flags.get(name, false)
