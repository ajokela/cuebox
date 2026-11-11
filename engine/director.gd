extends RefCounted

# Foreground sequences that take the screen away from the player: cutscenes,
# with SKIP, cut_to and captions, and conversation choices. The game keeps
# the gates (busy, scripts_paused) and the tap routing, and hands the rest
# over to this.

const Feel = preload("res://engine/feel.gd")
const ConvoPanel = preload("res://engine/convo_panel.gd")
const I18n = preload("res://engine/i18n.gd")

var game
var in_cutscene := false
var skipping := false  # a skipped cutscene is finishing behind a black screen
var shown := []  # the options on the panel while a choice waits for the player, else empty
var choosing: bool:  # a choice is open: only its options answer a tap
	get:
		return not shown.is_empty()

var _skippable := false  # a cutscene's body is still playing
var _body_owners := []  # the objects whose methods are playing as cutscene bodies
var _held_background = null  # a room script whose background() starts when the cutscene ends
var _picked := ""  # the id the player tapped while choosing
var choice_page:=0
var choice_focus:=-1
var _choice_layout:={}
var _choice_signature:=[]
var _choice_reflow_frame:=-1
var _choice_input_frame:=-1
var _choice_clear_top:=0


func _init(game_) -> void:
	game = game_


# ------------------------------------------------------------------ cutscenes

# Plays body (a Callable, usually a coroutine) as a cutscene. Input is blocked
# except SKIP (or Esc), and background and world scripts hold still; a room
# entered meanwhile starts its background() when the cutscene ends. A skip
# runs the rest of body at once behind a black screen, so the game ends up
# just where watching would have left it. Afterwards the active crew member's
# room is on screen again. A bg_* helper used in body is an error (see
# script_base.gd).
func cutscene(body: Callable) -> void:
	# Holds body's owner for the whole cutscene: a room script whose body cuts
	# away is otherwise freed mid-body, and the body would never return.
	var keep = body.get_object()
	_body_owners.append(keep)
	if in_cutscene:
		await body.call()  # a cutscene inside a cutscene is part of it
		_body_owners.erase(keep)
		return
	if not game.busy:  # started by a background or world script: drop what the player was doing
		game.drop_player_action()
	in_cutscene = true
	_skippable = true
	await body.call()
	_body_owners.erase(keep)
	_skippable = false
	game.fast_forward = false
	var home: String = game.actors[game.state.active].room
	if game.room != home:
		await game.hard_cut(home, false)  # nobody arrives: on_enter doesn't run again
	elif skipping:
		await game.wait(Feel.SWITCH_BLACKOUT)  # a beat of black, as a cut would have
	skipping = false
	in_cutscene = false
	var waiting = _held_background
	_held_background = null
	if waiting != null and waiting == game.room_script:
		waiting.background()


# Starts a room script's background() now, or when the cutscene playing ends.
func start_background(script) -> void:
	if in_cutscene:
		_held_background = script
	else:
		script.background()


# True while obj's method is playing as a cutscene body.
func is_cutscene_body(obj) -> bool:
	return in_cutscene and obj != null and _body_owners.has(obj)


func can_skip() -> bool:
	return in_cutscene and _skippable and not skipping


func skip_cutscene() -> void:
	if not can_skip():
		return
	skipping = true
	game.fast_forward = true


# Inside a cutscene: shows another room without moving any crew. Nobody
# arrives, so its on_enter() doesn't run and it isn't marked visited.
func cut_to(id: String) -> void:
	if not in_cutscene:
		push_error("cut_to(%s) only works inside a cutscene" % id)
		return
	if not game.rooms.has(id):
		push_error("cut_to: no room " + id)
		return
	if id != game.room:
		await game.hard_cut(id, false)


# One centred white line ("MEANWHILE, IN THE HANGAR...") with speech timing.
func caption(text: String) -> void:
	game.record("caption " + text)
	if game.fast_forward:
		return
	var token: int = game.speech.start_caption(text)
	while game.speech.caption_is(token):
		if game.fast_forward:
			game.speech.stop_caption(token)
			break
		await game.get_tree().process_frame
	await game.wait(Feel.SPEECH_GAP)


# ------------------------------------------------------------------ conversations

# Offers the options that show (see script_base.choose) and returns the id
# picked, once the active crew member has said its line. Memory is filed
# under "<room>.<convo>.<id>": every option offered in offered_options, a
# once option picked in state.convo_used. In test mode an answer queued in
# auto_answers is taken at once; otherwise the panel waits for a tap.
# Anything that makes the choice unanswerable is an error and returns "".
func choose(room: String, convo: String, options: Array) -> String:
	var prefix := "%s.%s." % [room, convo]
	if in_cutscene or choosing:
		return await _refuse(convo, "can't run inside a cutscene" if in_cutscene else "another choice is open")
	var visible := []
	for o in options:
		if o["id"] == "":
			push_error("choose(%s): empty option id; that line is left out" % convo)
			continue
		if o["show"] and not (o["once"] and game.state.convo_used.has(prefix + o["id"])):
			visible.append(o)
	if visible.is_empty():
		return await _refuse(convo, "no options to show")
	for o in visible:
		game.offered_options[prefix + o["id"]] = true
	var id: String
	if game.test_mode and not game.auto_answers.is_empty():
		id = game.auto_answers.pop_front()
	else:
		id = await _wait_for_pick(visible)
	var picked := {}
	for o in visible:
		if o["id"] == id:
			picked = o
	if picked.is_empty():
		return await _refuse(convo, "the answer %s isn't offered (%s)" % [id, ", ".join(visible.map(func(o): return o["id"]))])
	if picked["once"]:
		game.state.convo_used[prefix + id] = true
		game.state.changed.emit()
	await game.say(game.state.active,I18n.t(picked["text"]))
	return id


# An error, and "" a frame later: a menu loop that keeps asking spins once a
# frame instead of freezing the game.
func _refuse(convo: String, why: String) -> String:
	push_error("choose(%s): %s" % [convo, why])
	await game.get_tree().process_frame
	return ""


func _wait_for_pick(options: Array) -> String:
	shown = options
	_picked = ""
	choice_page=0; choice_focus=-1; _choice_layout={}; _choice_signature=[]
	_choice_reflow_frame=-1; _choice_input_frame=-1; _choice_clear_top=0
	choice_layout()
	while _picked == "":
		await game.get_tree().process_frame
	shown = []
	return _picked


# Reflow has no answer side effects. A language/width change resets the view,
# and input from that same frame cannot activate an old coordinate.
func choice_layout() -> Dictionary:
	var reserved:=[]
	if game.menus!=null: reserved.append_array(game.menus.speech_reserved())
	if game.interaction_policy!=null and game.interaction_policy.has_method("speech_reserved"): reserved.append_array(game.interaction_policy.speech_reserved())
	var clear_top:=0
	for rect in reserved: clear_top=maxi(clear_top,ceili(rect.end.y))
	# A transient notice expiring must not reset the page being read.
	_choice_clear_top=maxi(_choice_clear_top,clear_top)
	var signature: Array=[game.view_w(),texts(),_choice_clear_top]
	if signature!=_choice_signature:
		if not _choice_signature.is_empty(): _choice_reflow_frame=Engine.get_process_frames()
		_choice_signature=signature; _choice_layout=ConvoPanel.layout(signature[1],signature[0],_choice_clear_top)
		choice_page=0; choice_focus=-1
	return _choice_layout

func _choice_ready() -> bool:
	choice_layout()
	var frame:=Engine.get_process_frames()
	return choosing and _picked=="" and frame!=_choice_reflow_frame and frame!=_choice_input_frame

func turn_choice_page(direction: int) -> void:
	var arranged:=choice_layout()
	choice_page=clampi(choice_page+direction,0,arranged["pages"].size()-1)
	choice_focus=-1

# The first action stands, including page navigation, for this input frame.
func tap(p: Vector2) -> void:
	if not _choice_ready(): return
	var found:=ConvoPanel.hit(_choice_layout,choice_page,p)
	if found.is_empty(): return
	_choice_input_frame=Engine.get_process_frames()
	choice_focus=-1
	if found.has("page"): turn_choice_page(found["page"])
	else: _picked=shown[found["option"]]["id"]

func key(code: int) -> bool:
	if code not in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_PAGEUP,KEY_PAGEDOWN,KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]: return false
	if not _choice_ready(): return true
	_choice_input_frame=Engine.get_process_frames()
	if code in [KEY_LEFT,KEY_PAGEUP]: turn_choice_page(-1); return true
	if code in [KEY_RIGHT,KEY_PAGEDOWN]: turn_choice_page(1); return true
	var visible: Array=_choice_layout["pages"][choice_page].filter(func(e): return e["last"]).map(func(e): return e["option"])
	if visible.is_empty():
		if code in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_DOWN]: turn_choice_page(1)
		return true
	if code in [KEY_UP,KEY_DOWN]:
		var index: int=visible.find(choice_focus)
		choice_focus=visible[(index+(1 if code==KEY_DOWN else -1)+visible.size())%visible.size()] if index>=0 else visible[0 if code==KEY_DOWN else -1]
	elif choice_focus<0: choice_focus=visible[0]
	else: _picked=shown[choice_focus]["id"]
	return true

# Off-page answers have no hit area. Identity remains the original array
# index even when an answer wraps or spans several reading pages.
func option_rect(i: int) -> Rect2:
	var arranged:=choice_layout()
	for entry in arranged["pages"][choice_page]:
		if entry["option"]==i and entry["last"]: return entry["rect"]
	return Rect2()

func hovered_option() -> int:
	if not choosing or game.pointer==null: return -1
	return ConvoPanel.hit(choice_layout(),choice_page,game.pointer).get("option",-1)

func texts() -> Array:
	return shown.map(func(o): return I18n.t(o["text"]))

func draw_panel(ci, view_w: int) -> void:
	ConvoPanel.draw_layout(ci,view_w,choice_layout(),choice_page,game.actors[game.state.active].text_color,hovered_option(),choice_focus,game.speech.boxed)
