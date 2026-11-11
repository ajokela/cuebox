extends RefCounted

# Everything that is saved: flags, inventories, where every actor is, who is
# active, the crew the player has, conversation and fork memory, and the rooms
# seen. Arrays are plain Array on purpose (typed arrays across untyped
# references error in 4.7.2).

signal changed

const Walkmap = preload("res://engine/walkmap.gd")

const VERSION := 1
const FIELDS := ["flags", "inventory", "inventory_pages", "actors", "active", "crew", "unavailable", "party", "convo_used", "forks", "visited"]
const FACINGS := ["front", "back", "left", "right"]

var flags := {}
var inventory := {}  # crew id -> Array of item ids
var inventory_pages := {}  # optional presentation preference; old saves start on page zero
var actors := {}  # actor id -> {"room": String, "pos": Vector2, "facing": String}
var active := ""
var crew := []
var unavailable := {}  # actor -> reason; "offstage" also hides their sprite
var party := {}  # product-owned selection/checkpoint data; absent in legacy saves
var convo_used := {}
var forks := {}
var visited := {}
var loaded_with_fallback := false  # from_dict() couldn't place the active crew member: this is a new game


func flag(name: String, default = false):
	return flags.get(name, default)


func set_flag(name: String, value) -> void:
	flags[name] = value
	changed.emit()


# A deep copy of every field, for comparing in tests and for saving.
func snapshot() -> Dictionary:
	return {
		"version": VERSION,
		"flags": flags.duplicate(true),
		"inventory": inventory.duplicate(true),
		"inventory_pages": inventory_pages.duplicate(),
		"actors": actors.duplicate(true),
		"active": active,
		"crew": crew.duplicate(true),
		"unavailable": unavailable.duplicate(),
		"party": party.duplicate(true),
		"convo_used": convo_used.duplicate(true),
		"forks": forks.duplicate(true),
		"visited": visited.duplicate(true),
	}


# The state for a save file. JSON.from_native keeps what plain JSON loses: an
# int stays an int (3, not 3.0, so match and == still work) and a Vector2 a
# Vector2.
func to_dict() -> Dictionary:
	return JSON.from_native(snapshot())


# The state in a save file, forgiving of saves from other builds: unknown keys
# are ignored and missing ones take the value in defaults (a new-game state).
# An actor whose room isn't in rooms goes back to its start; if that's the
# active crew member, or d isn't from to_dict() at all, the result is the new
# game itself, with loaded_with_fallback set. Positions are put back on their
# room's floor, in case its walk boxes have changed since the save.
static func from_dict(d: Dictionary, defaults, rooms: Dictionary):
	var base: Dictionary = defaults.snapshot()
	var raw = JSON.to_native(d) if d.has("type") and d.has("args") else null  # to_native errors on anything else
	if not raw is Dictionary:
		return _fallback(defaults)
	for key in ["flags", "convo_used", "forks", "visited", "unavailable", "party"]:
		if raw.get(key) is Dictionary:
			base[key] = raw[key]
	if raw.get("crew") is Array:
		var known: Array = raw["crew"].filter(func(id): return defaults.inventory.has(id))
		if not known.is_empty():
			base["crew"] = known
	var inv = raw.get("inventory")
	if inv is Dictionary:
		for who in base["inventory"]:
			if inv.get(who) is Array:
				base["inventory"][who] = inv[who].filter(func(item): return item is String)
	var saved = raw.get("actors")
	if raw.get("inventory_pages") is Dictionary:
		for who in base["crew"]:
			var page = raw["inventory_pages"].get(who, 0)
			if raw["inventory_pages"].has(who) and page is int and page >= 0:
				base["inventory_pages"][who] = page
	var sent_home := []
	for id in base["actors"]:
		var a = saved.get(id) if saved is Dictionary else null
		if not a is Dictionary:
			continue  # not in the save: at its start
		if not (a.get("room") is String and rooms.has(a["room"]) and a.get("pos") is Vector2):
			sent_home.append(id)
			continue
		base["actors"][id] = {"room": a["room"], "pos": _on_floor(rooms[a["room"]], a["pos"]), "facing": a["facing"] if a.get("facing") in FACINGS else "front"}
	if raw.get("active") is String and raw["active"] in base["crew"]:
		base["active"] = raw["active"]
	if base["active"] in sent_home or not base["active"] in base["crew"]:
		return _fallback(defaults)
	return _from_snapshot(defaults.get_script(), base)


# pos clamped onto the walk boxes of the room in folder.
static func _on_floor(folder: String, pos: Vector2) -> Vector2:
	var path := folder + "geometry.gd"
	if not ResourceLoader.exists(path):
		return pos
	return Walkmap.clamp_point(load(path).DATA["walk_boxes"], pos)


static func _fallback(defaults):
	var s = _from_snapshot(defaults.get_script(), defaults.snapshot())
	s.loaded_with_fallback = true
	return s


static func _from_snapshot(script, snap: Dictionary):
	var s = script.new()
	for key in FIELDS:
		s.set(key, snap[key])
	return s
