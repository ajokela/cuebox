extends Node
# Try Cuebox: plays a visitor's edited copy of The Last Signal. The cuebox.gd/try/ page supplies the
# files and shows what this reports: lines spoken, rooms entered, flags set, the console's answers, and
# errors with the visitor's file and line. A run compiles every file first and starts the game only
# when all of them compile. Each run is a fresh engine: the page reloads the frame to run again.
#
# Reports are Dictionaries with a "kind": started, stopped, line (a transcript entry), flag (name,
# value), result (input, text) and error (text, and file/line when they're the visitor's).
const Content = preload("res://engine/content.gd")
const SAMPLE := "res://examples/last_signal/"
const PATH_PATTERN := "^[a-z0-9_]+(/[a-z0-9_]+)*\\.gd$"

class Host extends "res://engine/bootstrap.gd":
	func _ready() -> void: pass

# Errors from anywhere: the engine, the visitor's scripts, the console.
class Catch extends Logger:
	var entries: Array = []
	var mutex := Mutex.new()
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, trace: Array[ScriptBacktrace]) -> void:
		if kind == ERROR_TYPE_WARNING: return
		var frames := []
		for backtrace in trace:
			for i in backtrace.get_frame_count(): frames.append([backtrace.get_frame_file(i), backtrace.get_frame_line(i)])
		mutex.lock()
		entries.append({"file": file, "line": line, "text": rationale if rationale != "" else code, "frames": frames})
		mutex.unlock()
	func take() -> Array:
		mutex.lock()
		var out := entries
		entries = []
		mutex.unlock()
		return out

var autostart := true  # off for tests, which call run() themselves
var root := "user://try/"  # the visitor's files go in src/, the game's saves and settings in run/
var reports: Array = []
var sink := Callable()  # also given every report: the page, in a browser
var host
var game
var _catch := Catch.new()
var _seen := 0
var _flags := {}
var _console_callback  # the page's way in; kept so it stays valid

func _enter_tree() -> void:
	OS.add_logger(_catch)

func _exit_tree() -> void:
	OS.remove_logger(_catch)

func _ready() -> void:
	if not autostart: return
	if not OS.has_feature("web"):
		start()   # outside a browser there is no page: the sample as shipped
		return
	sink = _post
	_console_callback = JavaScriptBridge.create_callback(func(args): console(str(args[0]) if args.size() > 0 else ""))
	JavaScriptBridge.get_interface("window").cueboxConsole = _console_callback
	var raw = JavaScriptBridge.eval("(function(){try{return JSON.stringify(parent.cueboxTry.files())}catch(e){return ''}})()", true)
	var files = JSON.parse_string(raw) if raw is String and raw != "" else null
	if files is Dictionary: run(files)
	else: start()

# Writes the files, compiles them, and starts the game with the visitor's rooms. False when it
# didn't start; the reports say why.
func run(files: Dictionary, options := {}) -> bool:
	var src := root + "src/"
	_clear(src)
	_catch.take()   # nothing from before this run
	var pattern := RegEx.create_from_string(PATH_PATTERN)
	var written := []
	for path in files:
		if not (path is String and pattern.search(path) != null and files[path] is String):
			_report({"kind": "error", "text": "%s: only .gd files in plain folders can run here" % str(path)})
			continue
		DirAccess.make_dir_recursive_absolute((src + path).get_base_dir())
		var file := FileAccess.open(src + path, FileAccess.WRITE)
		file.store_string(files[path])
		file.close()
		written.append(path)
	var broken := 0
	for path in written:
		var before := broken
		var script = ResourceLoader.load(src + path, "", ResourceLoader.CACHE_MODE_REPLACE)
		broken += _drain()
		if broken == before and (script == null or not script.can_instantiate()):
			_report({"kind": "error", "file": path, "text": "this file doesn't compile"})
			broken += 1
	if broken > 0: return _stop()
	if not "content.gd" in written:
		_report({"kind": "error", "text": "content.gd is missing"})
		return _stop()
	var provider = load(src + "content.gd")
	var content = provider.options() if provider.has_method("options") else null
	_drain()
	if not (content is Dictionary and content.get("rooms") is Dictionary and content.get("crew") is Dictionary and content.get("roster") is Array):
		_report({"kind": "error", "file": "content.gd", "line": 0, "text": "options() must return a Dictionary with rooms, crew and roster"})
		return _stop()
	# The sample's room folders become the visitor's copies of them; art stays the sample's own.
	var rooms: Dictionary = content["rooms"].duplicate()
	for id in rooms:
		var folder := str(rooms[id])
		if folder.begins_with(SAMPLE) and folder.trim_prefix(SAMPLE) + "geometry.gd" in written:
			rooms[id] = src + folder.trim_prefix(SAMPLE)
	ProjectSettings.set_setting(Content.PROVIDER_SETTING, src + "content.gd")
	var opts := {"rooms": rooms}
	opts.merge(options, true)
	return start(opts)

# Starts the engine straight into a new game, saving nowhere but this run's own folder.
func start(options := {}) -> bool:
	var opts := {"start": "new_game", "user_root": root + "run/", "autosave": false}
	opts.merge(options, true)
	_clear(opts["user_root"])
	DirAccess.make_dir_recursive_absolute(opts["user_root"])
	host = Host.new()
	add_child(host)
	host.boot(opts)
	_drain()
	if host.game == null or host.game.state == null or host.game.room == "":
		_report({"kind": "error", "text": "the game didn't start"})
		return _stop()
	game = host.game
	_seen = game.transcript.size()
	_flags = game.state.flags.duplicate(true)
	_report({"kind": "started", "room": game.room})
	return true

# One line from the console, run against the current room's script: its own functions, say, flag,
# set_flag, go, pick_up and game.
func console(text: String) -> void:
	var line := text.strip_edges()
	if line == "": return
	if game == null or game.room_script == null:
		_report({"kind": "error", "input": line, "text": "the game isn't running: fix the errors and run again"})
		return
	var expression := Expression.new()
	if expression.parse(line) != OK:
		_report({"kind": "error", "input": line, "text": expression.get_error_text()})
		return
	var result = expression.execute([], game.room_script, false)
	if expression.has_execute_failed():
		_catch.take()
		_report({"kind": "error", "input": line, "text": expression.get_error_text()})
		return
	_report({"kind": "result", "input": line, "text": _show(result)})
	_sync()   # what the line did, right after it

func _process(_delta: float) -> void:
	_sync()

# Reports what changed since last time: flags first (a handler usually sets one, then speaks), then
# the transcript's new entries, then errors.
func _sync() -> void:
	if game == null or game.state == null: return
	var flags: Dictionary = game.state.flags
	for name in flags:
		if not _flags.has(name) or _flags[name] != flags[name]: _report({"kind": "flag", "name": name, "value": flags[name]})
	for name in _flags:
		if not flags.has(name): _report({"kind": "flag", "name": name, "value": null})
	_flags = flags.duplicate(true)
	while _seen < game.transcript.size():
		_report({"kind": "line", "text": game.transcript[_seen]})
		_seen += 1
	_drain()

func _stop() -> bool:
	_report({"kind": "stopped"})
	return false

# Reports what the log caught; how many. The file and line are the visitor's when the error is in
# their code or passed through it.
func _drain() -> int:
	var src := root + "src/"
	var count := 0
	for entry in _catch.take():
		if String(entry["text"]).begins_with("Failed to load script"): continue  # its parse error came first
		var out := {"kind": "error", "text": entry["text"]}
		var at = [entry["file"], entry["line"]] if String(entry["file"]).begins_with(src) else null
		if at == null:
			for frame in entry["frames"]:
				if String(frame[0]).begins_with(src):
					at = frame
					break
		if at != null:
			out["file"] = String(at[0]).trim_prefix(src)
			out["line"] = at[1]
		_report(out)
		count += 1
	return count

func _show(value) -> String:
	if value == null: return ""
	if value is Object and value.has_signal("completed"): return ""   # say, go, walk: still going; what they do shows up as it happens
	if value is String: return value
	return var_to_str(value)

func _report(report: Dictionary) -> void:
	reports.append(report)
	if sink.is_valid(): sink.call(report)

func _post(report: Dictionary) -> void:
	JavaScriptBridge.eval("window.parent!==window&&window.parent.postMessage({cuebox:JSON.parse(%s)},location.origin)" % JSON.stringify(JSON.stringify(report)))

static func _clear(folder: String) -> void:
	if not folder.begins_with("user://") or ".." in folder or not DirAccess.dir_exists_absolute(folder): return
	for sub in DirAccess.get_directories_at(folder):
		_clear(folder.path_join(sub) + "/")
		DirAccess.remove_absolute(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(file))
