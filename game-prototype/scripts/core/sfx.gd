class_name Sfx
extends Node
# Sound: short effects from assets/audio (a small pool of players lets them overlap, a run of coins), a music loop and an
# ambience loop (the street or the shop) that cross-fade when the scene changes. All sounds are synthesised by the project's tools.

const POOL := 8
const MUSIC_DB := -15.0
const AMB_DB := -17.0

var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _next := 0
var enabled := true
var music_on := true
var music: AudioStreamPlayer
var amb: AudioStreamPlayer
var _music_name := ""
var _amb_name := ""

func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new(); add_child(p); _players.append(p)
	music = AudioStreamPlayer.new(); music.volume_db = -80.0; add_child(music)
	amb = AudioStreamPlayer.new(); amb.volume_db = -80.0; add_child(amb)

func _load(name: String, ext: String) -> AudioStream:
	var key := name + "." + ext
	if not _cache.has(key):
		var path := "res://assets/audio/%s.%s" % [name, ext]
		_cache[key] = load(path) if ResourceLoader.exists(path) else null
		if _cache[key] is AudioStreamOggVorbis: (_cache[key] as AudioStreamOggVorbis).loop = true
	return _cache[key]

func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not enabled: return
	var s := _load(sound, "wav")
	if s == null: return
	var p := _players[_next]; _next = (_next + 1) % POOL
	p.stream = s; p.pitch_scale = pitch; p.volume_db = volume_db; p.play()

func set_music(on: bool) -> void:
	music_on = on
	if not on: _fade(music, -80.0, 0.4, true)
	elif _music_name != "": play_music(_music_name, true)

func play_music(name: String, force := false) -> void:
	if name == _music_name and music.playing and not force: return
	_music_name = name
	if not music_on: return
	var s := _load(name, "ogg")
	if s == null: return
	if music.stream != s or not music.playing:
		music.stream = s; music.volume_db = -40.0; music.play()
	_fade(music, MUSIC_DB, 1.5, false)

func play_ambience(name: String) -> void:
	if name == _amb_name and amb.playing: return
	_amb_name = name
	var s := _load(name, "ogg")
	if s == null or not enabled: return
	var tw := create_tween()
	tw.tween_property(amb, "volume_db", -50.0, 0.4)
	tw.tween_callback(func(): amb.stream = s; amb.play())
	tw.tween_property(amb, "volume_db", AMB_DB, 1.0)

func _fade(p: AudioStreamPlayer, to_db: float, t: float, stop_after: bool) -> void:
	var tw := create_tween(); tw.tween_property(p, "volume_db", to_db, t)
	if stop_after: tw.tween_callback(p.stop)
