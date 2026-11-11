extends RefCounted

# Everyone the player doesn't control, offstage: the world scripts that run all
# the time on saved state, NPC scripts, and NPCs moving between rooms. An NPC
# in a room nobody is watching moves by changing the state at once; where the
# player can see it, it walks.

const Walkmap = preload("res://engine/walkmap.gd")

var game
var world_runs := []  # the world scripts running now


func _init(game_) -> void:
	game = game_


# Drops the running world scripts and starts a fresh copy of each. They keep
# their progress in the state, so they carry on where it says.
func restart_world() -> void:
	stop_world()
	for path in game.world_scripts:
		if not ResourceLoader.exists(path):
			push_error("no world script at " + path)
			continue
		var w = load(path).new()
		if not w.has_method("run"):
			push_error("world script %s has no run()" % path)
			continue
		w.game = game
		world_runs.append(w)
	for w in world_runs:
		w.run()


# Stops every world script for good (a stopped one never resumes).
func stop_world() -> void:
	for w in world_runs:
		game.retire_script(w)
	world_runs = []


# A fresh copy of the NPC's own script, or null if it has none.
func npc_script(id: String):
	var path: String = game.npcs[id].get("script", "")
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		push_error("NPC %s has no script at %s" % [id, path])
		return null
	var s = load(path).new()
	s.game = game
	s.npc_id = id
	return s


# Moves an NPC to pos in to_room. Where the player can see it, it walks: across
# the room, in from the nearer end of the floor, or out at the nearer end.
# Anywhere else the state changes at once.
func move_npc(id: String, to_room: String, pos: Vector2, foreground := true) -> void:
	if not game.npcs.has(id):
		push_error("move_npc: no NPC " + id)
		return
	if not game.rooms.has(to_room):
		push_error("move_npc: no room " + to_room)
		return
	if not to_room in game.npcs[id].get("rooms", []):
		push_error("move_npc: %s can't go to %s (not in its rooms)" % [id, to_room])
		return
	var st = game.state
	var shown: String = game.room
	var from: String = st.actors[id]["room"]
	pos = Walkmap.clamp_point(game.room_geo(to_room)["walk_boxes"], pos)
	if from == shown and to_room == shown:
		await game.walk(id, pos, foreground)
	elif to_room == shown:
		place(id, to_room, Walkmap.edge(game.geo["walk_boxes"], pos))
		await game.walk(id, pos, foreground)  # its node appears at the edge if it had none
	elif from == shown:
		await game.walk(id, Walkmap.edge(game.geo["walk_boxes"], game.actor(id).position), foreground)
		if game.state == st:  # a load or start point meanwhile has the last word
			place(id, to_room, pos)
	else:
		place(id, to_room, pos)


# Puts an NPC straight into a room and spot, its node too if it has one.
func place(id: String, to_room: String, pos: Vector2) -> void:
	var s: Dictionary = game.state.actors[id]
	s["room"] = to_room
	s["pos"] = pos
	if game.actors.has(id):
		var a = game.actors[id]
		a.walk_route([])
		a.room = to_room
		a.position = pos
		a.visible = to_room == game.room
