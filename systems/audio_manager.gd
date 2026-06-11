extends Node

## Client-only audio layer: a round-robin SFX pool, crossfading music, and a
## single looping ambience track. Registered as the last autoload so every
## other autoload (NetworkMode in particular) is ready before _ready() runs.
##
## _ready() returns early on the dedicated server, mirroring the
## `if NetworkMode.is_server(): return` idiom used by model_view.gd and other
## client-only nodes — the server has no AudioServer output and callers
## (hud.gd, world.gd, etc.) call AudioManager.play_*() unconditionally from
## client-only branches anyway, but a defensive early-return keeps a stray
## server-side call from preloading dozens of streams for nothing.

const SFX_PATHS := {
	&"ui_click": "res://audio/sfx/ui_click.ogg",
	&"sword_swing": "res://audio/sfx/sword_swing.ogg",
	&"spell_cast": "res://audio/sfx/spell_cast.ogg",
	&"spell_learn": "res://audio/sfx/spell_learn.ogg",
	&"item_pickup": "res://audio/sfx/item_pickup.ogg",
	&"enemy_death": "res://audio/sfx/enemy_death.ogg",
	&"footstep_stone": "res://audio/sfx/footstep_stone.ogg",
}
const MUSIC_PATHS := {
	&"dungeon_explore": "res://audio/music/dungeon_explore.ogg",
}
const AMBIENT_PATHS := {
	&"dungeon_ambience": "res://audio/ambient/dungeon_ambience.ogg",
}

const SFX_POOL_SIZE := 8
const CROSSFADE_SECONDS := 1.0

var _streams: Dictionary[StringName, AudioStream] = {}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx_slot := 0

var _music_players: Array[AudioStreamPlayer] = []
var _active_music_slot := 0
var _active_music_key: StringName = &""

var _ambient_player: AudioStreamPlayer
var _active_ambient_key: StringName = &""


func _ready() -> void:
	if NetworkMode.is_server():
		return

	for key: StringName in SFX_PATHS:
		_preload(key, SFX_PATHS[key], false)
	for key: StringName in MUSIC_PATHS:
		_preload(key, MUSIC_PATHS[key], true)
	for key: StringName in AMBIENT_PATHS:
		_preload(key, AMBIENT_PATHS[key], true)

	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_sfx_pool.append(player)

	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.volume_db = -80.0
		add_child(player)
		_music_players.append(player)

	_ambient_player = AudioStreamPlayer.new()
	add_child(_ambient_player)


## Loads `path` into `_streams[key]`, marking it to loop if `should_loop` is
## true. Missing files warn (so a forgotten asset is visible in the log) but
## never crash — every play_*() call below is a no-op for an absent stream.
func _preload(key: StringName, path: String, should_loop: bool) -> void:
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: missing audio file for '%s': %s" % [key, path])
		return
	var stream: AudioStream = load(path)
	if should_loop:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_streams[key] = stream


## Fire-and-forget one-shot, round-robin across SFX_POOL_SIZE players so
## overlapping plays of the same (or different) sound don't cut each other off.
func play_sfx(key: StringName) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var player := _sfx_pool[_next_sfx_slot]
	_next_sfx_slot = (_next_sfx_slot + 1) % _sfx_pool.size()
	player.stream = stream
	player.play()


## Crossfades to `key`'s track over CROSSFADE_SECONDS. No-op if it's already
## the active track.
func play_music(key: StringName) -> void:
	if key == _active_music_key:
		return
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return

	var prev_player := _music_players[_active_music_slot]
	var next_slot := 1 - _active_music_slot
	var next_player := _music_players[next_slot]

	next_player.stream = stream
	next_player.volume_db = -80.0
	next_player.play()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(next_player, "volume_db", 0.0, CROSSFADE_SECONDS)
	if prev_player.playing:
		tween.tween_property(prev_player, "volume_db", -80.0, CROSSFADE_SECONDS)
	tween.chain().tween_callback(prev_player.stop)

	_active_music_slot = next_slot
	_active_music_key = key


## Fades the active music track out and stops it.
func stop_music() -> void:
	if _active_music_key == &"":
		return
	var player := _music_players[_active_music_slot]
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -80.0, CROSSFADE_SECONDS)
	tween.tween_callback(player.stop)
	_active_music_key = &""


## Starts (or restarts) the single looping ambience player. No-op if `key` is
## already playing.
func play_ambient(key: StringName) -> void:
	if key == _active_ambient_key and _ambient_player.playing:
		return
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	_ambient_player.stream = stream
	_ambient_player.play()
	_active_ambient_key = key
