extends RefCounted

# The helpers every content script uses (room scripts, NPC scripts, world
# scripts). All of them are safe to await.
#
# Foreground helpers are for handlers, conversations and cutscenes; they show
# in the transcript and fast_forward (cutscene skip) finishes them at once.
# Background helpers (bg_*) are for a room's background() and world scripts:
# they wait while the game is busy or in a cutscene (a background walk holds
# still mid-step), ignore fast_forward, can't be skipped and are never
# recorded. Background loops are written `while alive:`. Inside a cutscene
# body a bg_* helper is an error: it falls back to its foreground helper so the
# scene still plays.

signal _halted  # never emitted: a dead script's background parks here until it is freed

const Feel = preload("res://engine/feel.gd")
const I18n = preload("res://engine/i18n.gd")

var game
var alive := true
var npc_id := ""  # set on an NPC's own script: its conversations are filed under it
var background_pending := 0  # running helpers, until cancellation reaches their parked gate


# ------------------------------------------------------------------ foreground
# Lines are typed inline, in English, as string literals: tools/extract_strings.py
# collects every say(), bg_say(), caption() and opt() text for translation,
# and these helpers show it in the player's language.

func say(who: String, text: String) -> void:
	await game.say(who, I18n.t(text))


# A remote speaker keeps their own position; speech comes from an intercom
# or another visible source in this room, using that speaker's colour.
func say_from(who: String, text: String, room: String, at: Vector2) -> void:
	await game.say(who, I18n.t(text), true, {"room": room, "pos": at})


# Localized ownership/readout sentences retain their literal source template.
func say_format(who: String, text: String, values: Array) -> void:
	await game.say(who, I18n.t(text) % values)


func walk(who: String, to: Vector2) -> void:
	await game.walk(who, to)


func face(who: String, dir: String) -> void:
	var a = game.actor(who)
	if a != null:
		a.face(dir)


func wait(seconds: float) -> void:
	await game.wait(seconds)


func jiggle(who: String) -> void:
	await game.jiggle(who)


func sfx(name: String) -> void:
	game.sfx(name)


func flag(name: String, default = false):
	return game.state.flag(name, default)


func set_flag(name: String, value = true) -> void:
	game.state.set_flag(name, value)


func has(who: String, item: String) -> bool:
	return item in game.state.inventory.get(who, [])


# The item goes into who's inventory with a sound, then who says its hint.
func pick_up(who: String, item: String, hint := true, sound := "pickup") -> void:
	game.add_item(who, item)
	if sound != "":
		sfx(sound)
	if hint:
		await say(who, game.items[item]["hint"])


func give(who: String, item: String) -> void:
	game.add_item(who, item)


func take(who: String, item: String) -> void:
	game.remove_item(who, item)


func can(who: String, ability: String) -> bool:
	return ability in game.crew[who].get("abilities", [])


# Content calls must explain how the character becomes available again.
func set_crew_available(who: String, available: bool, reason := "busy") -> void:
	await game.set_crew_available(who, available, reason)


# The active crew member goes through a door: the music cuts, the screen
# blacks out, and the room changes.
# entry is a named destination entrance, or a Vector2 for legacy/scene callers.
func go(room: String, entry) -> void:
	await game.go(room, entry)


func quip(who: String) -> void:
	await say(who, game.next_quip(who))


# An NPC goes to pos in room: walking where the player can see it (in or out
# at the nearer end of the floor), at once anywhere else.
func move_npc(npc: String, room: String, pos: Vector2) -> void:
	await game.move_npc(npc, room, pos)


# Plays body (usually one of this script's methods) as a skippable cutscene.
# A skip ends in the same state as watching; then the active crew member's
# room is shown again.
func cutscene(body: Callable) -> void:
	await game.cutscene(body)


# Inside a cutscene only: shows another room without moving any crew.
func cut_to(room: String) -> void:
	await game.cut_to(room)


# One centred white line, such as "MEANWHILE, IN THE HANGAR...".
func caption(text: String) -> void:
	await game.caption(I18n.t(text))


# ------------------------------------------------------------------ conversations
# A conversation is a loop over choose(): handle the answer, and loop back for
# the menu again or return to end it. A submenu is another function with its
# own loop. Not inside a cutscene: nobody could answer.

# One line the player can pick. show false hides it, so put the condition
# there (a pilot's line: can(who, "pilot")); a once line goes for good after
# it's been picked.
func opt(id: String, text: String, show := true, once := false) -> Dictionary:
	if id == "":
		push_error("opt(): empty option id (\"\" can never be picked)")
	return {"id": id, "text": text, "show": show, "once": once}


# Puts every visible option on the panel in place of the HUD, wrapping and
# paging longer replies without dropping answers,
# and waits for the player to pick one. The active crew member says its line,
# then its id comes back. If nothing can be asked (no option shows, an empty id,
# a cutscene, another choice open) it's an error and "" comes back after a
# frame, so a menu loop must treat "" as the end of the conversation.
func choose(convo: String, options: Array) -> String:
	return await game.choose(convo_room(), convo, options)


# What a conversation's memory is filed under: an NPC's own script files it
# under the NPC, a room script under its room (room_script.gd), and a world
# script under the room on screen.
func convo_room() -> String:
	return npc_id if npc_id != "" else game.room


# A real fork's outcome, "" while it's undecided.
func fork(name: String) -> String:
	return game.state.forks.get(name, "")


# Settles a real fork for good: the other side is closed from now on. A fork
# is decided once; deciding it again is an error and changes nothing.
func decide(name: String, choice: String) -> void:
	if choice == "":
		push_error("decide(%s): a fork can't be decided as \"\"" % name)
		return
	if game.state.forks.has(name):
		push_error("fork %s is already decided (%s)" % [name, game.state.forks[name]])
		return
	game.state.forks[name] = choice
	game.decided_forks["%s.%s" % [name, choice]] = true
	game.state.changed.emit()


# ------------------------------------------------------------------ background

# Every background helper lets at least one frame go by before it returns,
# even with nothing to do (a walk to where the actor already stands, a wait of
# no time), so a `while alive:` loop of them can never spin inside one frame
# and freeze the game.

func bg_say(who: String, text: String) -> void:
	background_pending += 1
	var frame := Engine.get_process_frames()
	if _misused("bg_say", "say"):
		await say(who, text)
		await _a_frame_since(frame, false)
		background_pending -= 1
		return
	await _bg_gate()
	await game.say(who, I18n.t(text), false)
	await _bg_gate()
	await _a_frame_since(frame)
	background_pending -= 1


func bg_sfx(name: String) -> void:
	background_pending += 1
	var frame := Engine.get_process_frames()
	if _misused("bg_sfx", "sfx"):
		sfx(name)
		await _a_frame_since(frame, false)
		background_pending -= 1
		return
	await _bg_gate()
	game.audio.play(name)
	await _bg_gate()
	await _a_frame_since(frame)
	background_pending -= 1


# Counts down only while scripts aren't paused, so a waiting loop freezes
# while the player is busy.
func bg_wait(seconds: float) -> void:
	background_pending += 1
	var frame := Engine.get_process_frames()
	if _misused("bg_wait", "wait"):
		await wait(seconds)
		await _a_frame_since(frame, false)
		background_pending -= 1
		return
	await _bg_gate()
	var left := seconds
	while left > 0.0:
		await game.get_tree().process_frame
		if not alive:
			background_pending -= 1
			await _halted
		if not game.scripts_paused():
			left -= game.get_process_delta_time()
	await _bg_gate()
	await _a_frame_since(frame)
	background_pending -= 1


func bg_walk(who: String, to: Vector2) -> void:
	background_pending += 1
	var frame := Engine.get_process_frames()
	if _misused("bg_walk", "walk"):
		await walk(who, to)
		await _a_frame_since(frame, false)
		background_pending -= 1
		return
	await _bg_gate()
	await game.walk(who, to, false)
	await _bg_gate()
	await _a_frame_since(frame)
	background_pending -= 1


func bg_move_npc(npc: String, room: String, pos: Vector2) -> void:
	background_pending += 1
	var frame := Engine.get_process_frames()
	if _misused("bg_move_npc", "move_npc"):
		await move_npc(npc, room, pos)
		await _a_frame_since(frame, false)
		background_pending -= 1
		return
	await _bg_gate()
	await game.move_npc(npc, room, pos, false)
	await _bg_gate()
	await _a_frame_since(frame)
	background_pending -= 1


# A bg_* helper in this script's cutscene body would wait for the cutscene to
# end, which never comes. (This script's own background loops are parked in a
# helper's gate all through its cutscenes, so they never get here.)
func _misused(helper: String, instead: String) -> bool:
	if not game.is_cutscene_body(self):
		return false
	push_error("%s used inside a cutscene body: use %s() there" % [helper, instead])
	return true


# Waits while scripts are paused. Once the script is dead it never returns.
func _bg_gate() -> void:
	while alive and game.scripts_paused():
		await game.get_tree().process_frame
	if not alive:
		background_pending -= 1
		await _halted


# Waits for the next frame if none has gone by since frame. Then, in a
# background loop (park), a dead script never returns; a cutscene body that
# misused a bg_* helper carries on, dead or not, so its cutscene can end.
func _a_frame_since(frame: int, park := true) -> void:
	if Engine.get_process_frames() == frame:
		await game.get_tree().process_frame
	# A foreground action may have started during the minimum-frame yield.
	# Recheck before returning control to the background loop: its next helper
	# must not be mistaken for a bg_* call inside that new cutscene's body.
	if park:
		await _bg_gate()
