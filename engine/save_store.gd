extends RefCounted

# Save files and the settings file, under user_root (user:// in the game,
# user://test/ in tests, so tests never touch the player's own files). Slots
# are "auto" and "1".."3": <user_root>saves/slot_<slot>.json, or
# demo_slot_<slot>.json in the demo, so the demo and the full game never read
# each other's saves. A save file is {"meta": {"room_name", "crew_name"},
# "state": state.to_dict()}. Files are written to a .tmp, checked, and only
# then renamed over the old one, so a game killed mid-write or a full disk
# keeps the previous save.

const State = preload("res://engine/state.gd")
signal operation_finished(result: Dictionary)

const SLOTS := 3
const TEXT_SPEEDS := {"normal": 1.0, "slow": 1.5, "fast": 0.7}  # speech time multipliers
# text_boxes (free, for accessibility) puts a black box behind speech and the
# conversation panel. display_mode is "" or a mode the player owned when it
# was chosen; the game shows it only while they still own it.
const DEFAULT_SETTINGS := {"text_speed": "normal", "text_boxes": false, "crt": false, "display_mode": "", "locale": "en", "speaker_names": true, "music_volume":100, "effects_volume":100, "text_size":"standard", "dialogue_advance":"automatic", "text_colour":"speaker", "reduced_effects":false}
const VOLUMES := ["music_volume","effects_volume"]

var user_root: String
var demo: bool
var rooms := {}  # set by the game: the rooms a loaded save may put actors in
var new_state := Callable()  # set by the game: returns a new-game state, the defaults for loading
var validate := Callable()  # optional product validator, before any forgiving legacy conversion
var last_result := {} # structured result supplied by versioned product stores

func is_versioned() -> bool: return false
func is_waiting() -> bool: return false
func configure_content(_items: Dictionary, _describe: Callable) -> void: pass
func prepare_new_run(_state) -> bool: return true
func end_run() -> void: pass
func has_pending_commit() -> bool: return false
func save_transaction(state, meta := {}) -> bool: return autosave(state, meta)


func _init(user_root_: String, demo_: bool) -> void:
	user_root = user_root_
	demo = demo_


func path(slot: String) -> String:
	return "%ssaves/%sslot_%s.json" % [user_root, "demo_" if demo else "", slot]


func settings_path() -> String:
	return user_root + "settings.json"


func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


# meta is shown in the load and save menus ("ROOM - CHARACTER").
func save(slot: String, state, meta := {}) -> bool:
	return _write(path(slot), {"meta": meta, "state": state.to_dict()})


func autosave(state, meta := {}) -> bool:
	return save("auto", state, meta)


# The state in a slot (see state.from_dict), or null when the slot is empty or
# its file can't be read.
func load_slot(slot: String):
	var d = _read(path(slot))
	if d == null:
		return null
	if not (d is Dictionary and d.get("state") is Dictionary):
		push_error("save %s is unreadable" % path(slot))
		return null
	if validate.is_valid() and not validate.call(d["state"]):
		return null
	return State.from_dict(d["state"], new_state.call(), rooms)


# Every slot, autosave first: [{slot, room_name, crew_name, exists}].
func list() -> Array:
	var out := []
	for slot in ["auto"] + range(1, SLOTS + 1).map(func(i): return str(i)):
		var d = _read(path(slot))
		var meta = d.get("meta") if d is Dictionary else null
		if not meta is Dictionary:
			meta = {}
		out.append({"slot": slot, "room_name": str(meta.get("room_name", "")), "crew_name": str(meta.get("crew_name", "")), "exists": d != null})
	return out


# DEFAULT_SETTINGS with the settings file laid over it; values of the wrong
# type, or a text speed there's no such thing as, are ignored.
const TEXT_SIZES := ["standard", "large"]
const DIALOGUE_MODES := ["automatic", "manual"]
const TEXT_COLOURS := ["speaker", "high_contrast"]

func settings() -> Dictionary:
	var out: Dictionary = DEFAULT_SETTINGS.duplicate()
	var d = _read(settings_path())
	if d is Dictionary:
		for key in out:
			if key in VOLUMES and d.has(key):
				out[key]=volume(d[key])
			elif d.has(key) and typeof(d[key]) == typeof(out[key]):
				out[key] = d[key]
	if not TEXT_SPEEDS.has(out["text_speed"]):
		out["text_speed"] = "normal"
	if not out["text_size"] in TEXT_SIZES: out["text_size"]="standard"
	if not out["dialogue_advance"] in DIALOGUE_MODES: out["dialogue_advance"]="automatic"
	if not out["text_colour"] in TEXT_COLOURS: out["text_colour"]="speaker"
	return out


# JSON numbers load as floats. Booleans, nonfinite values and strings are
# not percentages; old preferences receive the unchanged 100% mix.
static func volume(value) -> int:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)): return 100
	return roundi(clampf(float(value),0.0,100.0))


func save_settings(d: Dictionary) -> bool:
	return _write(settings_path(), d)


func _write(file: String, d: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var tmp := file + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("can't write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	var text := JSON.stringify(d, "\t")
	var ok := _store(f, text)
	f.close()
	if ok:
		ok = FileAccess.get_file_as_bytes(tmp).size() == text.to_utf8_buffer().size()  # all of it reached the disk
	if not ok:
		DirAccess.remove_absolute(tmp)
		push_error("couldn't write %s (is the disk full?); %s is left as it was" % [tmp, file])
		return false
	var err := DirAccess.rename_absolute(tmp, file)
	if err != OK:
		push_error("can't replace %s (error %d)" % [file, err])
		return false
	return true


# Writes text, and says whether all of it went: a full disk fails here.
func _store(f: FileAccess, text: String) -> bool:
	return f.store_string(text) and f.get_error() == OK


# The parsed file, or null if there isn't one; an error if it isn't JSON.
func _read(file: String):
	if not FileAccess.file_exists(file):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK:
		push_error("%s is unreadable" % file)
		return null
	return json.data
