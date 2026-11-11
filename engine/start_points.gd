extends RefCounted

# Named start points (written in each room script's starts()) and the
# command-line options that lay changes over them. A start point is a
# Dictionary: {"room", "active", "actors": {id: {"room","pos"}},
# "items": {crew: [..]}, "flags", "forks", "convo_used"}. Missing keys take
# new-game values. Everything handed out is a deep copy.


# Every room script's starts(), plus "new_game". rooms maps id -> folder.
static func all(rooms: Dictionary, world := []) -> Dictionary:
	var out := {"new_game": {}}
	for id in rooms:
		var path: String = rooms[id] + id + ".gd"
		if not ResourceLoader.exists(path):
			continue
		var script = load(path).new()
		var found: Dictionary = script.starts()
		for name in found:
			if out.has(name):
				push_error("duplicate start point " + name)
			else:
				out[name] = found[name].duplicate(true)
	for path in world:
		var script = load(path).new()
		if script.has_method("starts"):
			for name in script.starts():
				if out.has(name):
					push_error("duplicate start point " + name)
				else:
					out[name] = script.starts()[name].duplicate(true)
	return out


# The start (a name or a Dictionary) with the overrides laid on top:
# "room", "active", "give" ({crew: [items]}) and "flags".
static func resolve(game, start, overrides: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	if start is String:
		var named := all(game.rooms, game.world_scripts)
		if named.has(start):
			d = named[start]
		else:
			push_error("unknown start point " + start)
	else:
		d = start.duplicate(true)
	if overrides.has("active"):
		d["active"] = overrides["active"]
	if overrides.has("room"):
		d["room"] = overrides["room"]
		var who: String = d.get("active", game.roster[0])
		if d.get("actors", {}).has(who):
			d["actors"][who].erase("room")  # the room override wins over the start's own spot
			d["actors"][who].erase("pos")
	var give: Dictionary = overrides.get("give", {})
	if not give.is_empty():
		if not d.has("items"):
			d["items"] = {}
		for who in give:
			d["items"][who] = d["items"].get(who, []) + give[who]
	if overrides.get("flags", {}).size() > 0:
		if not d.has("flags"):
			d["flags"] = {}
		d["flags"].merge(overrides["flags"], true)
	return d


# Shows the start, as a load does. Refused (an error, and false) unless
# game.can_load(): a handler, conversation, cutscene or door under way would
# carry on into the new state.
static func apply(game, start, overrides: Dictionary) -> bool:
	if not game.can_load():
		push_error("start point %s refused: the game is in the middle of something" % (start if start is String else "(dictionary)"))
		return false
	var candidate=game.start_state(resolve(game,start,overrides))
	if not game.saves.prepare_new_run(candidate): return false
	game._retry_transaction_state=null
	game.apply_state(candidate)
	game.save_dirty=false
	return true


# Understands --start --room --active --give --flag --locale --own --shots
# --nonce --print-state --display --crt --final --user-root --plan-shots; anything else is ignored.
# A bare --flag=name is true; --flag=name=<JSON> is that value, or the text if it isn't JSON.
# --display=<mode id> shows a display mode the player owns; --crt turns on CRT
# lines; --final makes shots capture the whole screen after the display shader.
# --user-root=<dir> (debug builds only, see main.gd) keeps a run away from the real user:// files.
# Returns {start, room, active, give, flags, locale, own, shots, nonce, print_state,
# display, crt, final, user_root}; keys for options not given are absent, except
# give, flags, own and shots (empty) and print_state, crt and final (false).
static func parse_cli(args: PackedStringArray) -> Dictionary:
	var out := {"give": {}, "flags": {}, "own": [], "shots": [], "print_state": false, "crt": false, "final": false}
	for arg in args:
		if arg in ["--print-state", "--crt", "--final", "--plan-shots"]:
			out[arg.substr(2).replace("-", "_")] = true
			continue
		if not arg.begins_with("--"):
			continue
		var eq := arg.find("=")
		var key := arg.substr(2, eq - 2) if eq >= 0 else arg.substr(2)
		var val := arg.substr(eq + 1) if eq >= 0 else ""
		match key:
			"start", "room", "active", "locale", "nonce", "display":
				out[key] = val
			"user-root":
				out["user_root"] = val
			"give":
				var parts := val.split(":", true, 1)
				if parts.size() == 2:
					var list: Array = out["give"].get(parts[0], [])
					list.append_array(Array(parts[1].split(",", false)))
					out["give"][parts[0]] = list
			"flag":
				var kv := val.split("=", true, 1)
				var value = true
				if kv.size() == 2:
					value = JSON.parse_string(kv[1])
					if value == null and kv[1] != "null":
						value = kv[1]  # not JSON: keep the text
					elif value is float and value == floorf(value):
						value = int(value)
				out["flags"][kv[0]] = value
			"own":
				out["own"].append_array(Array(val.split(",", false)))
			"shots":
				out["shots"].append_array(Array(val.split(",", false)))
	return out
