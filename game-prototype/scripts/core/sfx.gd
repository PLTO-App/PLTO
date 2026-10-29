class_name Sfx
extends Node
# Plays short sound effects from assets/audio. A small pool of players lets sounds overlap (a run of coins).

const POOL := 8
var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _next := 0
var enabled := true

func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new(); add_child(p); _players.append(p)

func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not enabled: return
	if not _cache.has(sound):
		var path := "res://assets/audio/%s.wav" % sound
		_cache[sound] = load(path) if ResourceLoader.exists(path) else null
	if _cache[sound] == null: return
	var p := _players[_next]; _next = (_next + 1) % POOL
	p.stream = _cache[sound]; p.pitch_scale = pitch; p.volume_db = volume_db; p.play()

func set_music(_on: bool) -> void:
	pass
