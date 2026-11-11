extends Node

# Music and sound effects. Music cuts dead at a door and the new tune starts
# at the chosen volume after a beat of silence. Effects round-robin over three
# players, so overlapping sounds clip each other the way the prototype did.
# In a browser the tune holds still while the page is away (hold_music).

const Feel = preload("res://engine/feel.gd")
signal levels_changed

var music: AudioStreamPlayer
var players := []
var _next := 0
var _sounds := {}
var _music_token := 0
var audio_root := "res://audio/"
var sounds: Dictionary = {}
var _held := false  # hold_music(true): the tune holds still, and a new one starts held
var music_level := 100
var effects_level := 100


# Percentages attenuate the original mix; zero is exact silence. Changing
# gain never restarts a stream, alters its hold state, or skips a game action.
static func gain_db(percent: int, baseline: float) -> float:
	return -INF if percent<=0 else baseline+linear_to_db(clampi(percent,0,100)/100.0)


func set_levels(music_percent: int, effects_percent: int) -> void:
	music_level=clampi(music_percent,0,100)
	effects_level=clampi(effects_percent,0,100)
	music.volume_db=gain_db(music_level,Feel.MUSIC_DB)
	for player in players: player.volume_db=gain_db(effects_level,Feel.SFX_DB)
	levels_changed.emit()


func _init() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = Feel.MUSIC_DB
	add_child(music)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.volume_db = Feel.SFX_DB
		add_child(p)
		players.append(p)


func play(name: String) -> void:
	var p: AudioStreamPlayer = players[_next]
	_next = (_next + 1) % players.size()
	p.stream = _sound(name)
	if p.stream != null: p.play()


# Holds the tune still where it is, or lets it play on. A menu holds it too
# (the game's process mode pauses the player), so letting go under a menu
# leaves it to the menu. A tune that starts while held waits as well: a
# player's pause only lasts as long as the tune it paused.
func hold_music(held: bool) -> void:
	_held = held
	music.stream_paused = held or not music.can_process()


func stop_music() -> void:
	_music_token += 1
	music.stop()


# Swaps the tune. With cut, waits MUSIC_SILENCE first; a later change wins.
func start_music(name: String, cut: bool) -> void:
	stop_music()
	var token := _music_token
	music.stream = _tune(name) if name != "" else null
	if cut:
		await get_tree().create_timer(Feel.MUSIC_SILENCE).timeout
	if token == _music_token and music.stream != null and not music.playing:
		music.play()
		if _held:
			music.stream_paused = true


func _sound(name: String) -> AudioStream:
	if not _sounds.has(name):
		var path: String = sounds.get(name, audio_root.path_join(name+".wav"))
		_sounds[name] = load(path) if path != "" and ResourceLoader.exists(path) else null
	return _sounds[name]


# Tunes loop forward over the whole file, unsmoothed, so the loop clicks.
func _tune(name: String) -> AudioStream:
	var tune: AudioStream = _sound(name)
	if not tune is AudioStreamWAV: return tune
	if tune.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		tune.loop_mode = AudioStreamWAV.LOOP_FORWARD
		tune.loop_begin = 0
		tune.loop_end = int(round(tune.get_length() * tune.mix_rate))
	return tune

func configure(root: String, paths: Dictionary) -> void:
	audio_root = root
	sounds = paths.duplicate()
	_sounds.clear()
