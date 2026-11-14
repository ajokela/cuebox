extends SceneTree
# Try Cuebox (examples/playground): the host the cuebox.gd/try/ page drives, given files the way
# the page gives them. One case per process (--case=), as the page runs each Run in a fresh engine.
const PlaygroundHost = preload("res://examples/playground/host.gd")
const Guard = preload("res://examples/playground/guard.gd")
const FILES := ["content.gd", "rooms/shack/geometry.gd", "rooms/shack/shack.gd", "rooms/roof/geometry.gd", "rooms/roof/roof.gd"]
const QUICK := {"test_mode": true, "test_turbo": true}
var errors: Array = []
var host
var root_path: String

func check(value: bool, label: String) -> void:
	if not value: errors.append(label)

# The sample's files, as the page sends them before any edit.
func sample() -> Dictionary:
	var out := {}
	for path in FILES: out[path] = FileAccess.get_file_as_string("res://examples/last_signal/" + path)
	return out

func reports(kind: String) -> Array:
	return host.reports.filter(func(r): return r["kind"] == kind)

func frames(n: int) -> void:
	for i in n: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var case := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--proof-root="): root_path = arg.trim_prefix("--proof-root=")
		if arg.begins_with("--case="): case = arg.trim_prefix("--case=")
	if not root_path.begins_with("user://engine-proof/") or ".." in root_path or not root_path.ends_with("/"):
		printerr("Supply --proof-root=user://engine-proof/<unique-run>/"); quit(2); return
	root.size = Vector2i(1280, 720)
	host = PlaygroundHost.new()
	host.autostart = false
	host.root = root_path
	root.add_child(host)
	match case:
		"edited": await edited()
		"console": await console()
		"parse_error": await parse_error()
		"runtime_error": await runtime_error()
		"bad_content": await bad_content()
		"bad_paths": await bad_paths()
		"loop_transform": loop_transform()
		"endless_loop": await endless_loop('func use_drawer(who: String, _item: String) -> void:\n\twhile true:\n\t\tpass\n', 3)
		"endless_inline": await endless_loop('func use_drawer(who: String, _item: String) -> void:\n\tvar n := 0\n\twhile true: n += 1\n', 4)
		"endless_for": await endless_loop('func use_drawer(who: String, _item: String) -> void:\n\tfor i: int in 1000000000000:\n\t\tpass\n', 3)
		"waiting_loop": await waiting_loop()
		_: errors.append("unknown case " + case)
	print(JSON.stringify({"pass": errors.is_empty(), "case": case, "errors": errors, "reports": host.reports}))
	host.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)

# An edited line is the one spoken, and the page hears it and sees the flags change.
func edited() -> void:
	var files := sample()
	files["rooms/shack/shack.gd"] = files["rooms/shack/shack.gd"].replace("THE DRAWER IS EMPTY.", "ONLY DUST NOW.")
	check(host.run(files, QUICK), "an edited sample runs")
	var game = host.game
	check(game != null and game.room == "shack", "it starts in the shack, with no title screen")
	check(reports("started").size() == 1, "the page hears it started")
	check(game != null and String(game.rooms["shack"]).begins_with(root_path + "src/"), "the shack is the visitor's copy")
	check(game != null and String(game.rooms["roof"]).begins_with(root_path + "src/"), "so is the roof")
	if game == null: return
	await game.use("drawer")
	await game.use("drawer")
	await frames(2)
	check("say rae: ONLY DUST NOW." in game.transcript, "the edited line is spoken")
	check(reports("line").any(func(r): return r["text"] == "say rae: ONLY DUST NOW."), "the page hears the line")
	check(reports("flag").any(func(r): return r["name"] == "fuse_taken" and r["value"] == true), "the page sees fuse_taken set")
	check(reports("error").is_empty(), "no errors: " + str(reports("error")))

# A line typed in the console runs against the current room's script.
func console() -> void:
	check(host.run(sample(), QUICK), "the sample runs")
	var game = host.game
	if game == null: return
	host.console('flag("radio_ready")')
	check(reports("result").back()["text"] == "false", "the console reads a flag: " + str(reports("result")))
	# Two lines in the same frame (typed fast, or pasted): each one's effects show right after it.
	var at: int = host.reports.size()
	host.console('set_flag("radio_ready")')
	host.console('flag("radio_ready")')
	check(game.state.flag("radio_ready") == true, "the console sets a flag")
	check(host.reports.slice(at).map(func(r): return [r["kind"], r.get("input", r.get("name", ""))]) == [["result", 'set_flag("radio_ready")'], ["flag", "radio_ready"], ["result", 'flag("radio_ready")']], "each line, then what it did: " + str(host.reports.slice(at)))
	check(reports("result").back()["text"] == "true", "and the next line reads it")
	host.console('use_radio("rae", "")')
	for i in 300:
		if "say rae: THE RADIO IS READY. THE BEACON ON THE ROOF NEEDS A SIGNAL." in game.transcript: break
		await process_frame
	check("say rae: THE RADIO IS READY. THE BEACON ON THE ROOF NEEDS A SIGNAL." in game.transcript, "the console calls the room's own functions")
	var before: int = reports("error").size()
	host.console("nope()")
	check(reports("error").size() == before + 1 and "nope" in reports("error").back()["text"], "an unknown call is one error naming it")
	host.console("1 +")
	check(reports("error").size() == before + 2 and reports("error").back().get("input") == "1 +", "a line that doesn't parse is one error")
	host.console("   ")
	check(reports("error").size() == before + 2, "a blank line is nothing")

# A file that doesn't compile stops the run, and the error names its file and line, once.
func parse_error() -> void:
	var files := sample()
	files["rooms/shack/shack.gd"] = files["rooms/shack/shack.gd"].replace('if flag("fuse_taken"):', 'if flag("fuse_taken")')
	check(not host.run(files, QUICK), "a run with a broken file doesn't start")
	check(host.game == null, "no game")
	var found: Array = reports("error")
	check(found.size() == 1, "one error: " + str(found))
	check(not found.is_empty() and found[0].get("file") == "rooms/shack/shack.gd" and found[0].get("line") == 3, "it names the file and line: " + str(found))
	check(reports("stopped").size() == 1, "the page hears the run stopped")
	host.console('flag("x")')
	check(reports("error").size() == 2 and not reports("error").back().has("file"), "the console says the game isn't running")

# An error while playing names the visitor's file and line; the game carries on.
func runtime_error() -> void:
	var files := sample()
	files["rooms/roof/roof.gd"] = files["rooms/roof/roof.gd"].replace('set_flag("signal_sent")', 'set_flag("signal_sent")\n\t\tvar lamp = null\n\t\tlamp.light()')
	check(host.run(files, QUICK), "the edited sample runs")
	var game = host.game
	if game == null: return
	host.console('set_flag("radio_ready")')
	await game.use("door")
	await game.use("beacon")
	await frames(2)
	var found: Array = reports("error").filter(func(r): return "light" in r["text"])
	check(found.size() == 1 and found[0].get("file") == "rooms/roof/roof.gd" and found[0].get("line") == 10, "the error names roof.gd line 10: " + str(reports("error")))
	check(game.room == "roof", "the game is still running")

# A content.gd without rooms is an error about content.gd, not a crash.
func bad_content() -> void:
	var files := sample()
	files["content.gd"] = 'extends RefCounted\nstatic func options() -> Dictionary:\n\treturn {"crew": {}}\n'
	check(not host.run(files, QUICK), "content without rooms doesn't start")
	check(reports("error").any(func(r): return r.get("file") == "content.gd" and "rooms" in r["text"]), "the error is about content.gd's rooms: " + str(reports("error")))
	check(host.game == null, "no game")

# Only .gd files in plain folders are written; nothing lands outside the run's own folder.
func bad_paths() -> void:
	var files := sample()
	files["../escape.gd"] = "extends RefCounted\n"
	files["rooms/shack/notes.txt"] = "hello"
	files["/abs.gd"] = "extends RefCounted\n"
	check(host.run(files, QUICK), "the good files still run")
	check(reports("error").size() == 3, "each bad name is an error: " + str(reports("error")))
	check(not FileAccess.file_exists(root_path + "escape.gd"), "nothing written above the source folder")
	check(not FileAccess.file_exists(root_path + "src/rooms/shack/notes.txt"), "nothing but .gd files written")

# Loops get a check the visitor never sees: their text, their line numbers.
func loop_transform() -> void:
	var Loops = load("res://examples/playground/loops.gd")
	var source := "extends RefCounted\nfunc f(items: Array) -> int:\n\tvar n := 0\n\t# a comment\n\twhile n < 3:\n\n\t\t# inside\n\t\tn += 1\n\tfor i: int in range(2):\n\t\tn += i\n\twhile items.any(func(x): return x > n): n += 1\n\tfor k in {\"a\": 1}:\n\t\tn += 1\n\tvar s := \"while true: not a loop\"\n\twhile (n < 10 and\n\t\t\tn != 7):\n\t\tn += 1\n\treturn n\n"
	var out: Dictionary = Loops.guard(source, "rooms/x/x.gd")
	var text: String = out["text"]
	var lines: Array = Array(text.split("\n"))
	var guards := lines.filter(func(l): return "guard.gd" in l)
	check(guards.size() == 5, "five loops, five checks: " + text)
	check(lines.filter(func(l): return "not a loop" in l).size() == 1 and not "guard.gd" in lines[lines.find(lines.filter(func(l): return "not a loop" in l)[0]) + 1], "a string that says while is not a loop: " + text)
	var script := GDScript.new()
	script.source_code = text
	check(script.reload() == OK, "it still compiles: " + text)
	if script.reload() == OK: check(script.new().f([]) == 7, "and does what it did")
	var map: Array = out["lines"]
	check(map.size() == lines.size(), "every line has its original number")
	for i in lines.size():
		if "n != 7" in lines[i]: check(map[i] == 16, "a continued condition keeps its line: %s" % str(map))
		if lines[i].strip_edges() == "return n": check(map[i] == 18, "the last line keeps its number: %s" % str(map))
	check(out["text"] == Loops.guard(source, "rooms/x/x.gd")["text"], "the same every time")
	check(Loops.guard("extends RefCounted\n", "a.gd")["text"] == "extends RefCounted\n", "no loops, no change")

# A loop that never lets a frame finish is stopped after a moment, named by the visitor's file and
# line; the page stays responsive and the game stops.
func endless_loop(handler: String, line: int) -> void:
	var files := sample()
	files["rooms/shack/shack.gd"] = files["rooms/shack/shack.gd"].replace('func use_drawer(who: String, _item: String) -> void:\n', handler + 'func use_drawer_was(who: String, _item: String) -> void:\n')
	check(host.run(files, QUICK), "the sample with a loop runs: " + str(host.reports))
	if host.game == null: return
	var started := Time.get_ticks_msec()
	host.console('use_drawer("rae", "")')
	var waited := Time.get_ticks_msec() - started
	await frames(3)
	check(waited < 6000, "the loop was stopped (%d ms)" % waited)
	var found: Array = reports("error").filter(func(r): return r.get("file") == "rooms/shack/shack.gd")
	check(found.size() == 1 and found[0].get("line") == line and "loop" in found[0]["text"], "the error names the loop's line %d: %s" % [line, str(reports("error"))])
	check(reports("stopped").size() == 1, "the page hears the game stopped")
	host.console('flag("x")')
	check(reports("error").back().get("input") == 'flag("x")' and "isn't running" in reports("error").back()["text"], "the console says it stopped")

# A loop that waits a frame each time round is not stuck, however long it runs; and errors after a
# guarded loop still name the visitor's own line.
func waiting_loop() -> void:
	var files := sample()
	var handler := 'func use_drawer(who: String, _item: String) -> void:\n\tvar n := 0\n\twhile n < 400:\n\t\tn += 1\n\t\tawait game.get_tree().process_frame\n\tvar lamp = null\n\tlamp.light()\n'
	files["rooms/shack/shack.gd"] = files["rooms/shack/shack.gd"].replace('func use_drawer(who: String, _item: String) -> void:\n', handler + 'func use_drawer_was(who: String, _item: String) -> void:\n')
	check(host.run(files, QUICK), "the sample with a waiting loop runs")
	if host.game == null: return
	host.console('use_drawer("rae", "")')
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9000 and reports("error").is_empty():
		await process_frame
		OS.delay_msec(8)
	check(reports("stopped").is_empty(), "a loop that waits each frame isn't stopped: " + str(reports("error")))
	var found: Array = reports("error")
	check(Time.get_ticks_msec() - started > Guard.LIMIT_MS, "the loop ran longer than one frame may")
	check(found.size() == 1 and found[0].get("line") == 8 and "light" in found[0]["text"], "the error after the loop is on the visitor's line 8: " + str(found))
