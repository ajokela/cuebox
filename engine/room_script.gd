extends "res://engine/script_base.gd"

# Base for a room's script, rooms/<id>/<id>.gd. A fresh instance is made each
# time the room is entered and dropped when it is left.
#
# Handlers are found by name: use_<hotspot id>(who, item) and
# use_<npc id>(who, item). item is "" when nothing is selected. A handler that
# says nothing gets a fallback quip.

var room_id := ""
var geo: Dictionary = {}


# Prop id -> state name, read every frame. "" hides the prop and disables the
# hotspot linked to it. Props not listed show their first state.
func prop_states() -> Dictionary:
	return {}


# Runs when crew arrive (a door, a crew switch, a new game or a load), not
# when a cutscene's cut_to only shows the room.
# Initialize props here. Put foreground speech, walking or room changes in
# cutscene(); this hook itself does not own the player action gate. Start
# conversations from an interaction handler. The content check enforces this
# for direct calls and local helpers, including helpers calling other helpers.
func on_enter() -> void:
	pass


# Runs while the room is shown (from the end of a cutscene, if one is playing
# when the room appears). Use the bg_* helpers and loop `while alive:`.
func background() -> void:
	pass


# Draws effects over the background (z -50), in room coordinates.
func draw_fx(_ci: CanvasItem) -> void:
	pass


# Actor-held props and their labels, above the people (z 500) but below UI.
# Like background effects, these use room coordinates and the same camera.
func draw_front(_ci: CanvasItem) -> void:
	pass


# Named start points that belong to this room.
func starts() -> Dictionary:
	return {}


# This room's conversations are filed under it.
func convo_room() -> String:
	return room_id


func anchor(name) -> Vector2:
	if not geo.get("anchors", {}).has(name):
		push_error("room %s has no anchor %s" % [room_id, name])
		return Vector2.ZERO
	return geo["anchors"][name]
