extends RefCounted

# Strict runtime boundary for decoded checkpoint data. This does not add cast,
# choose a team, discard an item or turn an invalid location into NEW GAME.
# Product migration must explicitly prepare a complete snapshot first.
const State = preload("res://engine/state.gd")

static func restore(raw: Dictionary, defaults, rooms: Dictionary, items: Dictionary, validator := Callable()):
	if raw.get("version")!=State.VERSION or not raw.get("version") is int: return null
	if raw.size()!=State.FIELDS.size()+1: return null
	for field in State.FIELDS:
		if not raw.has(field): return null
	for field in ["flags","inventory","inventory_pages","actors","unavailable","party","convo_used","forks","visited"]:
		if not raw[field] is Dictionary: return null
	if not raw["crew"] is Array or raw["crew"].is_empty() or not raw["active"] is String or not raw["active"] in raw["crew"]: return null
	var seen := []
	for who in raw["crew"]:
		if not who is String or not defaults.inventory.has(who) or who in seen: return null
		if not raw["inventory"].has(who) or not raw["actors"].has(who): return null
		seen.append(who)
	if raw["actors"].size()!=defaults.actors.size() or raw["inventory"].size()!=defaults.inventory.size(): return null
	for who in raw["actors"]:
		var actor = raw["actors"][who]
		if not defaults.actors.has(who) or not actor is Dictionary or actor.size()!=3: return null
		if not actor.get("room") is String or not rooms.has(actor["room"]): return null
		if not actor.get("pos") is Vector2 or not actor["pos"].is_finite() or not actor.get("facing") in State.FACINGS: return null
	var owned := []
	for who in raw["inventory"]:
		if not defaults.inventory.has(who) or not raw["inventory"][who] is Array: return null
		var held := []
		for item in raw["inventory"][who]:
			if not item is String or not items.has(item) or item in held: return null
			if item in owned and not items[item].get("renewable",false): return null
			held.append(item); owned.append(item)
	for who in raw["inventory_pages"]:
		var page = raw["inventory_pages"][who]
		if not defaults.inventory.has(who) or not page is int or page<0: return null
	for who in raw["unavailable"]:
		if not defaults.actors.has(who) or not raw["unavailable"][who] is String: return null
	if raw["unavailable"].has(raw["active"]): return null
	for room in raw["visited"]:
		if not rooms.has(room) or not raw["visited"][room] is bool: return null
	if validator.is_valid() and not validator.call(JSON.from_native(raw)): return null
	var state := State.new()
	for field in State.FIELDS:
		var value = raw[field]
		state.set(field,value.duplicate(true) if value is Dictionary or value is Array else value)
	return state
