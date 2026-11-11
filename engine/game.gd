extends Node2D

# The runtime: state, rooms, actors (crew and NPCs), input, interactions,
# doors and crew switching, with room scripts and world scripts running on
# top; cutscenes and conversations are the director's (director.gd).
# Everything draws into a view 152 px of room plus a 28 px HUD. All data comes
# in through setup(opts), so tests can inject fixture rooms, crew, NPCs and
# world scripts. Saves, the autosave and the player's settings are here too;
# the menus (menus.gd) sit on top and call in.
#
# Lifetime rule: actor nodes, props and room views are created once and then
# only hidden or shown, never freed while the game runs. A coroutine awaiting
# a freed object hangs its callers silently in 4.7.2. Crew nodes are made at
# setup; an NPC's node the first time its room is shown, so an NPC whose rooms
# aren't in this game never loads its art.

const Feel = preload("res://engine/feel.gd")
const Walkmap = preload("res://engine/walkmap.gd")
const Camera = preload("res://engine/camera.gd")
const State = preload("res://engine/state.gd")
const Speech = preload("res://engine/speech.gd")
const Hud = preload("res://engine/hud.gd")
const Audio = preload("res://engine/audio.gd")
const RoomScript = preload("res://engine/room_script.gd")
const RoomView = preload("res://engine/room_view.gd")
const StartPoints = preload("res://engine/start_points.gd")
const Cast = preload("res://engine/cast.gd")
const Director = preload("res://engine/director.gd")
const Entitlements = preload("res://engine/entitlements.gd")
const SaveStore = preload("res://engine/save_store.gd")
const I18n = preload("res://engine/i18n.gd")
const Content = preload("res://engine/content.gd")
const Foreground = preload("res://engine/foreground.gd")

signal hud_tapped(what: String)  # "menu" (MENU) or "label" (the sentence line), when a tap there would count
signal demo_ended  # the demo's last scene has played (end_game): the menus put up the thanks screen
signal prologue_ended  # the web build's prologue is over (end_game): the menus put up the end card
signal save_problem(kind: String, slot: String)
signal save_finished(result: Dictionary)

var state
var crew
var roster
var initial_crew
var room_scripts := {}
var foreground
var crew_dialogue # optional product-owned conversations with fixed, off-duty NPC crew
var interaction_policy # optional product-owned input and world rules
var manual_dialogue_supported:=false
var story_clock # optional product-owned progress display; no story data in the engine
var reference # optional product-owned belongings/notebook/help menus
var entry_flow # optional product-owned pending selection and entry presentation
var completion # product-owned ending dispatch; presentation intent is never saved
var telemetry # optional product-owned service; no telemetry in public products or tests
var title_music := "" # optional product-owned menu tune; never part of a save
var menus  # attached by Menus; world scripts can offer product-specific panels
var npcs
var items
var rooms
var demo := false
var web := false  # browser behavior: end card, no quitting, music held while away
var test_mode := false
var test_turbo := false # test harness only; never changes the player's movement constants
var fast_forward := false
var auto_answers := []
var transcript := []
var offered_options := {}
var decided_forks := {}  # "<fork>.<choice>" for every fork a script of this game decided (the tests' fork_coverage)
var room := ""
var busy: bool:  # the player can't act: an action, a conversation or a cutscene is playing
	get:
		return _busy or director.in_cutscene or director.choosing
	set(value):
		_busy = value
		if not value:
			_end_if_due()  # a handler that called end_game() or ended the prologue has just finished
var in_cutscene: bool:
	get:
		return director.in_cutscene or (foreground!=null and foreground.cinematic())
var skipping: bool:  # a skipped cutscene is finishing behind a black screen
	get:
		return director.skipping or (foreground!=null and foreground.skipping())

var user_root := "user://"
var autosave := false
var items_script_path := ""
var world_scripts := []  # paths
var world_options := {} # product-owned world-controller options, also injectable in tests
var view := Vector2i.ZERO  # a fixed view size; ZERO follows the viewport
var actors := {}  # actor id -> actor node
var selected := ""
var blackout := false
var hovered := ""  # the name of what a real mouse is over; never set by touch
var _hover_room := "" # Retained context labels cannot cross a room change.
var pointer = null  # where a real mouse is over the game, in view coordinates, or null
var entitlements  # which extras the player owns
var screen  # the Screen the game is shown through (null in most tests)
var display_mode := ""  # the display mode shown, "" for the normal palette; the screen only draws it
var crt := false  # CRT lines shown
var saves  # SaveStore: save slots and the settings file under user_root
var save_dirty := false
var _retry_transaction_state
var _transaction_after := Callable() # temporary presentation intent; never serialized
var _transaction_origin # Failed foreground-to-scene transitions can be cancelled without preserving actor positions.
var _transaction_motion_origin # Same live world only; a real load still reconstructs it.
var _transaction_context:="" # Retain foreground reading/Skip intent across a failed write.
var settings := {}  # the player's settings (save_store.gd), as shown
var menu_open := false:  # a menu is over the game: it holds still and takes no input
	set(value):
		menu_open = value
		process_mode = PROCESS_MODE_DISABLED if value else PROCESS_MODE_INHERIT
var clock := 0.0  # game time since setup, for effects
var exploration_clock := 0.0 # controllable seconds, for product-owned timers; never the story clock
var geo: Dictionary = {}  # the shown room's geometry
var room_script
var room_view
var cast  # world scripts, NPC scripts, NPC movement
var director  # cutscenes and conversations
var hud
var speech
var audio

var _reading_input_frame:=-1
var _busy := false
var _world: Node2D
var _overlay: Node2D
var _geometry := {}
var _quips := {}  # crew id -> what's left of the shuffled quip list
var _last_quip := {}
var _rng := RandomNumberGenerator.new()  # quip shuffles, repeatable in test mode
var _action_id := 0
var _actor_approach := {} # ephemeral click intent; never part of a checkpoint
var _fg_events := 0
var _cam_x := 0
var _cam_target := 0
var _cam_clock := 0.0
var _fg_running := 0  # a script's foreground say, walk, wait or jiggle under way
var _autosave_due := false  # the crew arrived somewhere: autosave once the player has control
var _owns_autosave := false  # this game may replace the autosave (see autosave_now)
var _product_end_due := "" # a public card requested through end_game(), waiting for idle
var _prologue_beat_was_complete := false
var prologue_end_beat := ""
var presentation: Dictionary = {}
var display_modes: Dictionary = {}
var foreground_handlers: Array = []


# Call once the game is in the tree. Every key is optional. "start" (a start
# point name or Dictionary, default "new_game") with "overrides" (as from
# StartPoints.parse_cli) is the room the game opens in; a null start opens no
# game at all, for the title screen. "locale" (from --locale) overrides the
# player's language; "strict_strings" makes text missing from the string
# tables an error (tests).
func setup(opts: Dictionary) -> void:
	if not is_inside_tree():
		push_error("add the game to the tree before calling setup()")
		return
	test_mode = opts.get("test_mode", false)
	test_turbo = test_mode and opts.get("test_turbo",false)
	demo = opts.get("demo", OS.has_feature("demo"))
	web = opts.get("web", OS.has_feature("web"))
	user_root = opts.get("user_root", "user://")
	autosave = opts.get("autosave", not test_mode)
	view = opts.get("view", Vector2i.ZERO)
	var content := Content.options()
	content.merge(opts, true)
	presentation = content.get("presentation", {}).duplicate(true)
	display_modes = presentation.get("display_modes", {}).duplicate(true)
	foreground_handlers = content.get("foreground_handlers", []).duplicate(true)
	title_music = content.get("title_music", "")
	manual_dialogue_supported=content.get("manual_dialogue",not web and not demo)
	rooms = content["rooms"].duplicate()
	crew = content["crew"].duplicate(true)
	roster = content["roster"].duplicate()
	initial_crew = opts.get("initial_crew", opts.get("roster", content.get("initial_crew", roster))).duplicate()
	room_scripts = content.get("room_scripts", {}).duplicate()
	foreground=Foreground.new(self,content.get("foreground", ""))
	if content.get("crew_dialogue","")!="": crew_dialogue=load(content["crew_dialogue"])
	npcs = content["npcs"].duplicate(true)
	items = content["items"].duplicate(true)
	items_script_path = content["items_script"]
	world_scripts = content["world"].duplicate()
	world_options = content.get("world_options",{}).duplicate(true)
	if content.get("entry_flow","")!="": entry_flow=load(content["entry_flow"]).new(self)
	completion=load(content.get("completion","res://engine/completion.gd")).new(self)
	if content.get("interaction_policy", "") != "":
		interaction_policy = load(content["interaction_policy"]).new(self, content.get("policy_options",{}))
	if content.get("story_clock", "") != "": story_clock=load(content["story_clock"]).new()
	if content.get("reference", "") != "": reference=load(content["reference"]).new(self)
	prologue_end_beat = content.get("prologue_end_beat", "")
	var scripts: Array = world_scripts.duplicate()
	if content.get("interaction_policy","")!="": scripts.append(content["interaction_policy"])
	if content.get("entry_flow","")!="": scripts.append(content["entry_flow"])
	if content.get("story_clock", "") != "": scripts.append(content["story_clock"])
	if content.get("reference", "") != "": scripts.append(content["reference"])
	if content.get("telemetry", "") != "": scripts.append(content["telemetry"])
	if content.get("foreground", "") != "": scripts.append(content["foreground"])
	scripts.append_array(room_scripts.values())
	if content.get("crew_dialogue","")!="": scripts.append(content["crew_dialogue"])
	for id in npcs:
		if String(npcs[id].get("script", "")) != "":
			scripts.append(npcs[id]["script"])
	I18n.register(rooms, opts.get("strict_strings", false), scripts, content["common_strings"], content.get("localization", {}))
	entitlements = Entitlements.new(user_root, opts.get("own", []))
	var store_path: String=content.get("save_store","")
	saves = SaveStore.new(user_root,demo) if store_path=="" else load(store_path).new(user_root,demo)
	saves.rooms = rooms
	saves.new_state = new_game_state
	if content.get("save_validator", "") != "":
		var validator = load(content["save_validator"])
		saves.validate = func(raw): return validator.valid_save(raw, new_game_state(), rooms, items)
	saves.configure_content(items,_checkpoint_labels)
	saves.operation_finished.connect(_on_save_finished,CONNECT_DEFERRED)
	screen = opts.get("screen", null)
	if screen != null: screen.configure(presentation)
	if test_mode:
		_rng.seed = 1  # exact transcripts stay exact when a quip turns up
	else:
		_rng.randomize()

	audio = Audio.new()
	audio.configure(content.get("audio_root", "res://audio/"), content.get("sounds", {}))
	add_child(audio)
	_world = Node2D.new()
	add_child(_world)
	room_view = RoomView.new(_world)
	cast = Cast.new(self)
	director = Director.new(self)
	_overlay = Node2D.new()
	_overlay.z_index = 1000
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	speech = Speech.new()
	hud = Hud.new()
	hud.game = self
	if entry_flow==null:
		for id in roster:
			_add_actor(id, room_view.make_actor(id, crew[id]))
	load_settings()
	# Before the first room: its first words are already in the player's language.
	TranslationServer.set_locale(I18n.start_locale(opts.get("locale", ""), settings["locale"], OS.is_debug_build()))

	var start = opts.get("start", "new_game")
	if start != null:
		var candidate=start_state(StartPoints.resolve(self,start,opts.get("overrides",{})))
		if saves.prepare_new_run(candidate): apply_state(candidate)
	if not test_mode and content.get("telemetry_enabled",false) and content.get("telemetry","")!="":
		telemetry=load(content["telemetry"]).new(self)
		add_child(telemetry)

func _exit_tree() -> void:
	if foreground!=null: foreground.reset(true)
	if saves!=null: saves.end_run()


# Every crew member and NPC at their start, the crew empty-handed, the first
# of the roster active.
func new_game_state():
	if entry_flow!=null: return entry_flow.initial_state()
	var s = State.new()
	s.crew = initial_crew.duplicate()
	for id in roster:
		var start: Dictionary = crew[id]["start"]
		s.actors[id] = {"room": start["room"], "pos": start["pos"], "facing": "front"}
		s.inventory[id] = []
		if not id in initial_crew:
			s.unavailable[id] = "offstage"
	for id in npcs:
		var start: Dictionary = npcs[id]["start"]
		s.actors[id] = {"room": start["room"], "pos": start["pos"], "facing": "front"}
		if npcs[id].get("offstage", false):
			s.unavailable[id] = "offstage"
	s.active = initial_crew[0]
	if story_clock!=null: story_clock.normalize(s)
	return s


# A start point name ("new_game" or one from a room script), or a Dictionary laid over a new game: "actors",
# "items", "flags", "forks", "convo_used", "active", and "room" (moves the
# active crew member there unless "actors" already places them).
func start_state(start):
	if entry_flow!=null: return entry_flow.start_state(start)
	var s = new_game_state()
	if start is String:
		var named: Dictionary = StartPoints.all(rooms, world_scripts)
		if not named.has(start):
			push_error("unknown start point " + start)
			return s
		start = named[start]
	var d: Dictionary = start.duplicate(true)
	if d.has("crew"):
		var chosen = d["crew"]
		if not chosen is Array or chosen.is_empty() or chosen.any(func(id): return not id in roster) or chosen.size() != _unique(chosen).size():
			push_error("start point has an invalid crew")
			return s
		s.crew = chosen.duplicate()
		s.active = s.crew[0]
		for id in roster:
			if id in s.crew:
				s.unavailable.erase(id)
			else:
				s.unavailable[id] = "offstage"
	s.party = d.get("party", {}).duplicate(true)
	if d.has("unavailable"):
		s.unavailable = d["unavailable"].duplicate()
		# A developer scene's availability map predates future hidden NPCs.
		# Only explicitly staging one makes it visible at that start point.
		for id in npcs:
			if npcs[id].get("offstage",false) and not d.get("actors",{}).has(id) and not s.unavailable.has(id):
				s.unavailable[id]="offstage"
	for id in d.get("actors", {}):
		if s.actors.has(id):
			s.actors[id].merge(d["actors"][id], true)
		else:
			push_error("start point places unknown actor " + id)
	for id in d.get("items", {}):
		s.inventory[id] = d["items"][id].duplicate()
	s.flags.merge(d.get("flags", {}), true)
	s.forks.merge(d.get("forks", {}), true)
	s.convo_used.merge(d.get("convo_used", {}), true)
	if d.get("active", "") in s.crew:
		s.active = d["active"]
	elif d.has("active"):
		push_error("start point makes unknown crew %s active" % d["active"])
	if d.has("room") and not d.get("actors", {}).get(s.active, {}).has("room"):
		var a: Dictionary = s.actors[s.active]
		a["room"] = d["room"]
		a["pos"] = Walkmap.clamp_point(room_geo(d["room"])["walk_boxes"], a["pos"])
	return s


static func _unique(ids: Array) -> Array:
	var out := []
	for id in ids:
		if not id in out:
			out.append(id)
	return out


# Persist a complete next state before showing it. A failed write leaves the
# live state and the previous CONTINUE alone. Debug start points never write.
func commit_state(next, retain_room := false, background_context := "", after := Callable(), preserve_motion := false) -> bool:
	if not can_save():
		return false
	if story_clock!=null: story_clock.normalize(next)
	# A presentation controller may commit only its own party context.
	# It must not reset a click-to-walk action, selection, camera or actor pose.
	if background_context!="":
		if not next.party.has(background_context): return false
		var before: Dictionary=state.snapshot()
		var candidate: Dictionary=next.snapshot()
		before["party"].erase(background_context); candidate["party"].erase(background_context)
		if before!=candidate: return false
	if saves.validate.is_valid() and not saves.validate.call(next.to_dict()):
		return false
	if preserve_motion and not _can_preserve_motion(next): return false
	_transaction_origin=state
	_transaction_motion_origin=state if preserve_motion or background_context=="foreground" else null
	_transaction_after=after
	_transaction_context=background_context
	var a: Dictionary = next.actors[next.active]
	var meta := {"room_name": room_geo(a["room"])["name"], "crew_name": crew[next.active]["name"]}
	if autosave:
		if not saves.save_transaction(next,meta):
			if saves.is_versioned():
				_retry_transaction_state=State._from_snapshot(next.get_script(),next.snapshot())
				save_problem.emit("transaction","auto")
			return false
		save_dirty=false
	_retry_transaction_state=null
	if background_context!="":
		state.party[background_context]=next.party[background_context].duplicate(true)
		room_view.refresh_props()
	else: _apply_transaction_state(next,retain_room)
	_owns_autosave = autosave
	_transaction_origin=null; _transaction_motion_origin=null
	_transaction_context=""
	_transaction_after=Callable()
	if after.is_valid(): _after_transaction.call_deferred(state,after)
	return true

func _can_preserve_motion(next) -> bool:
	if state==null or next.active!=state.active or next.crew!=state.crew or next.unavailable!=state.unavailable or next.actors.size()!=state.actors.size(): return false
	for id in state.actors:
		if not next.actors.has(id) or next.actors[id]["room"]!=state.actors[id]["room"] or next.actors[id]["pos"]!=state.actors[id]["pos"]: return false
	return true

func _apply_transaction_state(next,retain_room:=false) -> void:
	if _transaction_context=="foreground" and _transaction_motion_origin==state:
		var before: Dictionary=state.snapshot(); var candidate: Dictionary=next.snapshot()
		before["party"].erase("foreground"); candidate["party"].erase("foreground")
		if before==candidate and next.party.has("foreground"):
			state.party["foreground"]=next.party["foreground"].duplicate(true)
			foreground.restore_reading(); room_view.refresh_props()
			_transaction_origin=null; _transaction_motion_origin=null; _transaction_context=""
			return
	if _transaction_motion_origin!=state or not _can_preserve_motion(next):
		apply_state(next,retain_room,next.party.has("foreground")); return
	# Ordinary action transactions change ownership/text while every live walk
	# holds. Keep actor nodes, routes, clocks, ambient scripts and room audio.
	foreground.reset()
	for id in actors:
		if actors[id].facing!=next.actors[id]["facing"]: actors[id].face(next.actors[id]["facing"])
	state=next; _watch_prologue()
	_action_id+=1; selected=""; _autosave_due=false
	room_view.refresh_props()
	foreground.restore_presentation()
	_transaction_origin=null; _transaction_motion_origin=null
	_transaction_context=""

func _after_transaction(expected, after: Callable) -> void:
	# Menus finish closing their Retry dialog before a new presentation opens.
	# A load, new run or title screen cancels a callback already in flight.
	if state!=null and state==expected and after.is_valid(): after.call()


func crew_available(id: String) -> bool:
	return state != null and id in state.crew and not state.unavailable.has(id)


# Content must document a recovery when it removes access to a character.
func set_crew_available(id: String, available: bool, reason := "busy") -> void:
	if not id in roster:
		push_error("unknown crew " + id)
		return
	var others: Array = state.crew.filter(func(who): return who != id and crew_available(who))
	if not available and id == state.active and others.is_empty():
		push_error("can't make the last available character unavailable")
		return
	if available:
		state.unavailable.erase(id)
	else:
		state.unavailable[id] = reason
	state.changed.emit()
	if not available and id == state.active:
		await _switch(others[0])


func actor_visible(id: String) -> bool:
	return actors[id].room == room and state.unavailable.get(id) != "offstage"


# Shows a whole new state (setup, start points, loading): every actor moves to
# its stored room and spot, the active crew member's room is entered, and the
# world scripts start afresh from the state.
# Safe mid-game: walks stop, lines vanish, and a use on its way drops out.
# A handler that is already running is not stopped, so loads and start points
# go through can_load() first (load_game, StartPoints.apply).
func apply_state(s, retain_room := false, foreground_transition:=false) -> void:
	if entry_flow!=null and entry_flow.pending_state(s):
		if close(false): entry_flow.present_pending(s)
		return
	_transaction_after=Callable()
	_transaction_origin=null; _transaction_motion_origin=null
	_transaction_context=""
	foreground.reset(not foreground_transition)
	hud.page_message_until = 0
	_action_id += 1
	_autosave_due = false
	_product_end_due = ""
	_owns_autosave = false  # load_game gives it back to a real load
	busy = false
	blackout = false
	selected = ""
	speech.clear()
	state = s
	if entry_flow!=null: _sync_entry_cast(state.actors)
	if story_clock!=null: story_clock.normalize(state)
	_watch_prologue()
	for id in actors:
		var stored: Dictionary = state.actors[id]
		actors[id].walk_route([])  # stops a walk under way
		actors[id].room = stored["room"]
		actors[id].position = stored["pos"]
		actors[id].face(stored["facing"])
	var destination: String = state.actors[state.active]["room"]
	if foreground_transition and retain_room and not foreground.presentation.descriptor().is_empty(): destination=room
	if retain_room and room == destination:
		# A committed scene may bring a previously unseen NPC into the room
		# already on screen. Give it the same live body as an ordinary arrival.
		for id in npcs:
			if state.actors.get(id,{}).get("room")==room: actor(id)
		for id in actors: actors[id].visible = actor_visible(id)
		room_view.refresh_props()
		sync_state()
	else:
		_enter_room(destination, false)
		cast.restart_world()
	foreground.restore_presentation(not foreground_transition)
	if entry_flow!=null: entry_flow.after_apply()


# A product may offer a selection roster larger than its actual saved cast.
# Other products retain their original persistent actor nodes.
func _sync_entry_cast(saved: Dictionary) -> void:
	for id in actors.keys():
		if not saved.has(id):
			actors[id].hide();actors[id].queue_free();actors.erase(id)
	for id in saved:
		if crew.has(id) and not actors.has(id):
			_add_actor(id,room_view.make_actor(id,crew[id]))


# Copies where every actor node is into state. Runs every frame, after a
# teleport and when a walk ends, so a snapshot is never a frame behind.
func sync_state() -> void:
	if state == null:
		return
	if story_clock!=null: story_clock.normalize(state)
	for id in actors:
		var a = actors[id]
		var s: Dictionary = state.actors[id]
		s["room"] = a.room
		s["pos"] = a.position
		s["facing"] = a.facing


func is_demo() -> bool:
	return demo


# The only completion entry point. The selected product owns its identifiers,
# completion checkpoint and Continue behavior. Invalid requests change nothing.
func end_game(id: String) -> bool:
	return completion!=null and completion.request(id)


# Shared public/legacy cards retain the preceding autosave. Wait until the
# requesting handler is idle so the card cannot freeze a suspended action.
func _queue_product_end(page: String) -> bool:
	if state==null or page not in ["demo_end","prologue_end"]: return false
	_owns_autosave=false; _autosave_due=false
	_product_end_due=page
	_end_if_due()
	return true


func _end_if_due() -> void:
	if _product_end_due=="" or not can_save() or in_cutscene or menu_open: return
	var page:=_product_end_due
	_product_end_due=""
	if page=="demo_end": demo_ended.emit()
	else: prologue_ended.emit()


# On the web the prologue ends when its named completion beat is recorded in
# play. A host script records the beat; the product chooses whether it ends here. Native builds
# continue normally. A state that already has it (a start point, a
# load) isn't a new ending.
func _watch_prologue() -> void:
	_prologue_beat_was_complete = state.flag(prologue_end_beat) == true
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	if state!=null and story_clock!=null: story_clock.normalize(state)
	var done: bool = state != null and state.flag(prologue_end_beat) == true
	if web and done and not _prologue_beat_was_complete:
		end_game("prologue")
	_prologue_beat_was_complete = done
	# In a browser, leaving with the Back button, a phone's back gesture or
	# Cmd/Ctrl+W can give the game no frame once the page is going, and Godot
	# copies files to the browser's storage only on a frame. So on the web
	# progress writes the autosave on the next frame the player has control,
	# and Godot copies it out on the frame after, while the page is still in
	# front. Only for a game that owns the autosave (see autosave_now), so
	# never after the prologue's end card (end_prologue gives it up above).
	# Native versioned runs also checkpoint semantic background transitions
	# (encounter warnings and progress credit), once this run owns Continue.
	# Busy foreground handlers still finish before the queued write can run.
	if (web or saves.is_versioned()) and autosave and _owns_autosave:
		_autosave_due = true


# Background and world scripts hold still while this is true: during an
# action, a conversation, a cutscene or a blackout, and under a menu.
func scripts_paused() -> bool:
	return busy or (foreground!=null and foreground.holding()) or in_cutscene or blackout or menu_open or (saves!=null and saves.has_pending_commit())

func foreground_active() -> bool: return foreground!=null and foreground.active()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if reading_input_consumed():
		get_viewport().set_input_as_handled(); return
	if state == null:
		return
	# Touch arrives as an emulated left click too, so ScreenTouch is ignored
	# or every tap would fire twice. Hover names come only from a real mouse:
	# never from motion emulated from touch, and never on phones.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap(event.position)
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and not OS.has_feature("mobile"):
			hover(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if foreground.key(event.keycode): get_viewport().set_input_as_handled()
		elif director.choosing and director.key(event.keycode): get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE] and speech.reading_active():
			speech.skip(); get_viewport().set_input_as_handled()
		elif event.keycode==KEY_ESCAPE: skip_cutscene()


# A tap at p in view coordinates. In a cutscene a tap only skips: the line
# showing, or with SKIP the whole cutscene. While a conversation's choice is
# open only its options answer.
func reading_input_consumed() -> bool:
	return _reading_input_frame==Engine.get_process_frames()

func consume_reading_input() -> bool:
	if reading_input_consumed(): return false
	_reading_input_frame=Engine.get_process_frames(); return true

func tap(p: Vector2) -> void:
	if reading_input_consumed(): return
	if saves.has_pending_commit(): return
	p = p.floor()
	if _product_end_due!="":
		return  # the demo or the prologue is over: its last screen is on its way
	if foreground.tap(p): return
	if in_cutscene:
		if hud.skip_rect(view_w()).has_point(p):
			skip_cutscene()
		else:
			speech.skip()
		return
	if speech.skip():
		return  # tapping skips the current line
	if director.choosing:
		director.tap(p)
		return
	if busy or blackout:
		return
	if p.y >= Feel.ROOM_H:
		var h: Dictionary = hud.hit(p)
		if h.has("menu"):
			hud_tapped.emit("menu")
		elif h.has("context"):
			hud_tapped.emit("context")
		elif h.has("label"):
			hud_tapped.emit("label")
		elif h.has("crew"):
			_switch(h["crew"])
		elif h.has("page"):
			hud.turn_page(h["page"])
		elif h.has("item"):
			_tap_item(h["item"])
		return
	if interaction_policy!=null and interaction_policy.has_method("exit_hint_at") and not interaction_policy.exit_hint_at(p).is_empty(): selected=""
	if interaction_policy!=null and interaction_policy.has_method("choose_item_target") and interaction_policy.choose_item_target(p): return
	var thing := _thing_at(p)
	if thing.has("actor"):
		_use_actor(thing["actor"])
	elif thing.has("hotspot"):
		_use_hotspot(thing["hotspot"])
	else:
		if interaction_policy != null and not interaction_policy.allow_action("walk", ""): return
		_action_id += 1
		selected = ""
		_start_walk(actors[state.active], Vector2(p.x - _world_offset(), p.y))


# The mouse is at p in view coordinates. What's under it is looked at again
# every frame, so the name stays right as the camera and actors move.
func hover(p: Vector2) -> void:
	pointer = p.floor()
	if _hover_room not in ["",room] or not hud.keeps_hover(pointer): hovered = _name_at(pointer)
	_hover_room=room


# The mouse has left the game.
func hover_end() -> void:
	pointer = null
	hovered = ""
	_hover_room = ""


# The name to show for p: a hotspot, an actor, a portrait or an item. Nothing
# while the room is drawn black. With an item selected, only what it can be
# used with: not itself, and not a portrait (a tap there switches crew).
func _name_at(p: Vector2) -> String:
	if state == null or blackout or skipping:
		return ""
	if p.y >= Feel.ROOM_H:
		var h: Dictionary = hud.hit(p)
		if h.has("crew") and selected == "":
			return crew[h["crew"]]["name"]
		if h.has("item") and h["item"] != selected:
			return items[h["item"]]["name"]
		return ""
	var thing := _thing_at(p)
	if thing.has("actor"):
		return actors[thing["actor"]].display_name
	if thing.has("hotspot"):
		return thing["hotspot"]["name"]
	return ""


# What's under p in the room: {"actor": id}, {"hotspot": dict} or {}.
func _thing_at(p: Vector2) -> Dictionary:
	if interaction_policy!=null and interaction_policy.has_method("exit_hint_at"):
		var exit_hint: Dictionary=interaction_policy.exit_hint_at(p)
		if not exit_hint.is_empty(): return {"hotspot":exit_hint}
	var wp := Vector2(p.x - _world_offset(), p.y)
	for id in actors:
		var a = actors[id]
		if id != state.active and a.visible and _actor_rect(a).has_point(wp):
			return {"actor": id}
	for h in geo["hotspots"]:
		if room_view.hotspot_enabled(h) and h["rect"].has_point(wp):
			return {"hotspot": h}
	return {}


func _actor_rect(a) -> Rect2:
	return Rect2(a.position.x - a.hit_width/2.0, a.position.y - a.height, a.hit_width, a.height)


# With nothing selected a tap selects the item; on the selected item it puts
# it away; on another item it combines the two.
func _tap_item(item: String) -> void:
	sfx("blip")
	if selected == "" or selected == item:
		selected = "" if selected == item else item
		return
	await _combine(selected, item)


# Runs the items script's combine_<a>_with_<b>(who), the two ids in
# alphabetical order, as the active crew member. Without a handler, or if it
# neither speaks, plays a sound nor changes room, who says a quip.
func _combine(a: String, b: String) -> void:
	if interaction_policy != null and not interaction_policy.allow_action("combine", ""): return
	var progress_before: Dictionary=_progress_snapshot()
	_action_id += 1  # a walk that was going to use the first item is off
	actors[state.active].walk_route([])
	var who: String = state.active
	var ids := [a, b]
	ids.sort()
	var method := "combine_%s_with_%s" % ids
	busy = true
	var script = null  # kept alive while its handler runs
	if ResourceLoader.exists(items_script_path):
		script = load(items_script_path).new()
		script.game = self
	else:
		push_error("no items script at " + items_script_path)
	var before := _fg_events
	if script != null and script.has_method(method):
		await script.call(method, who)
	if _fg_events == before:
		await _fallback_quip(who, "combine", "", ids)
	selected = ""
	busy = false
	if foreground.start_pending(): await foreground.wait_until_settled()
	else: _checkpoint_action(progress_before)


# ------------------------------------------------------------------ display

# What the options menu offers under DISPLAY: "DEFAULT" plus the name of each
# mode the player owns. CRT lines aren't a mode: they're free, always offered.
func display_choices() -> Array:
	var out := ["DEFAULT"]
	for id in display_modes:
		if entitlements.owns(display_modes[id].get("extra", "")):
			out.append(display_modes[id]["name"])
	return out


# Shows a display mode by id ("" for the normal palette) and CRT lines on or
# off. A mode the player doesn't own is quietly refused: the normal palette shows.
func set_display(mode: String, crt_lines: bool) -> void:
	if mode != "" and not display_modes.has(mode):
		push_error("no display mode " + mode)
		mode = ""
	if mode != "" and not entitlements.owns(display_modes[mode].get("extra", "")):
		mode = ""
	display_mode = mode
	crt = crt_lines
	if screen != null:
		screen.show_display(mode, crt_lines)


# ------------------------------------------------------------------ settings

# Reads the settings file and shows it (setup does this).
func load_settings() -> void:
	settings = saves.settings()
	_apply_settings(["text_size","dialogue_advance"])


# The options menu's way in: changes one setting, shows it and writes the
# settings file. The locale is only kept here; setup starts in it and menus.gd
# switches the language.
func change_setting(key: String, value) -> void:
	var known: Dictionary = SaveStore.DEFAULT_SETTINGS
	if key in SaveStore.VOLUMES: value=SaveStore.volume(value)
	if not known.has(key) or typeof(value) != typeof(known[key]) or (key == "text_speed" and not SaveStore.TEXT_SPEEDS.has(value)):
		push_error("no setting %s = %s" % [key, value])
		return
	if (key=="text_size" and not value in SaveStore.TEXT_SIZES) or (key=="dialogue_advance" and not value in SaveStore.DIALOGUE_MODES) or (key=="text_colour" and not value in SaveStore.TEXT_COLOURS):
		push_error("no setting %s = %s" % [key,value]); return
	settings[key] = value
	_apply_settings([key])
	saves.save_settings(settings)


# Text speed and boxes go to the speech. The display goes through set_display,
# so a paid mode the player no longer owns quietly shows the default, and is
# forgotten the next time settings are written.
func reduced_effects() -> bool:
	return settings.get("reduced_effects",false)


func manual_dialogue_available() -> bool:
	return not web and manual_dialogue_supported and foreground!=null and foreground.registry!=null


func _apply_settings(changed: Array=[]) -> void:
	if "reduced_effects" in changed: _cam_clock=0.0
	# Developer previews may set size/manual directly. Changing an unrelated
	# option must not reset those isolated presentation choices.
	if "text_size" in changed: speech.text_scale=2 if settings["text_size"]=="large" else 1
	if "dialogue_advance" in changed:
		foreground.manual=manual_dialogue_available() and settings["dialogue_advance"]=="manual"
		speech.manual=foreground.manual
	speech.time_scale = SaveStore.TEXT_SPEEDS[settings["text_speed"]]
	speech.boxed = settings["text_boxes"]
	speech.names = settings["speaker_names"]
	audio.set_levels(settings["music_volume"],settings["effects_volume"])
	var mode: String = settings["display_mode"]
	set_display(mode if display_modes.has(mode) else "", settings["crt"])
	settings["display_mode"] = display_mode
	if screen!=null: screen.show_reading_contrast(settings["text_colour"]=="high_contrast")


# ------------------------------------------------------------------ saving

# True when the player has control: nothing busy (no action, conversation or
# cutscene), no door under way and no script's foreground line, walk, wait or
# jiggle playing. Running coroutines can't be saved, so saves wait for this.
func can_save() -> bool:
	return state != null and not busy and not blackout and _fg_running == 0 and not saves.has_pending_commit()


# Loads and start points need the same, or no game at all (the title screen):
# a handler under way would carry on into the loaded game.
func can_load() -> bool:
	return not saves.has_pending_commit() and (state == null or can_save())


# Saves to a slot, "1".."3" or "auto". Refused, with an error, unless can_save().
func save_game(slot: String) -> bool:
	if not can_save():
		push_error("save_game(%s) refused: %s" % [slot, "there is no game" if state == null else "the game is in the middle of something"])
		return false
	sync_state()
	var saved: bool=saves.save(slot,state,_save_meta())
	if saved: save_dirty=false
	return saved


# Loads a slot and shows it. False if the slot is empty or unreadable;
# refused, with an error, unless can_load(). Items this build doesn't have are
# left out.
func load_game(slot: String) -> bool:
	if not can_load():
		push_error("load_game(%s) refused: the game is in the middle of something" % slot)
		return false
	_retry_transaction_state=null
	_transaction_origin=null; _transaction_motion_origin=null
	_transaction_context=""
	var s = saves.load_slot(slot)
	if s == null:
		return false
	if not saves.is_versioned():
		for who in s.inventory:
			s.inventory[who] = s.inventory[who].filter(func(item): return items.has(item))
	apply_state(s)
	if telemetry!=null: telemetry.loaded("continue" if slot=="auto" else "manual")
	save_dirty=false
	if state==null: return true # pending selection is owned by the entry flow
	_owns_autosave = not s.loaded_with_fallback  # carrying on a saved game; a fresh one has to earn it
	_resume_loaded_ending()
	return true

func _resume_loaded_ending() -> void:
	if web and saves.is_versioned() and state!=null and state.flag(prologue_end_beat): end_game("prologue")

# Browser operations finish after IndexedDB's transaction acknowledgement.
# Input/world scripts were held at the original safe boundary meanwhile.
func _on_save_finished(result: Dictionary) -> void:
	var after:=_transaction_after
	if result["status"]=="ok":
		if result.has("state"):
			_apply_transaction_state(result["state"])
			_owns_autosave=true
			_resume_loaded_ending()
		_retry_transaction_state=null
		save_dirty=false
	elif result["kind"] in ["auto","save"]:
		save_dirty=true
	save_finished.emit(result)
	if result["status"]=="ok" and result["kind"]=="transaction":
		_transaction_after=Callable()
		if after.is_valid(): _after_transaction.call_deferred(state,after)

func recover_game(slot: String, token: String) -> bool:
	if not can_load() or not saves.is_versioned(): return false
	_retry_transaction_state=null
	_transaction_origin=null; _transaction_motion_origin=null
	_transaction_context=""
	var candidate=saves.recover_slot(slot,token)
	if candidate==null: return false
	apply_state(candidate)
	_owns_autosave=true
	if telemetry!=null: telemetry.loaded("recovered")
	save_dirty=false
	return true

func retry_pending_save() -> bool:
	if not saves.has_pending_commit(): return false
	var after:=_transaction_after
	var result: Dictionary=saves.retry_pending()
	if result["status"]!="ok": return false
	if result.has("state"):
		# The original panel's callback already returned on failure. Resume like
		# a real load so scene-owned panels/world continuations are recreated.
		_apply_transaction_state(result["state"])
		_owns_autosave=autosave
	_retry_transaction_state=null
	save_dirty=false
	_transaction_after=Callable()
	if result.has("state") and after.is_valid(): _after_transaction.call_deferred(state,after)
	return true

func retry_transaction() -> bool:
	if _retry_transaction_state==null or not can_save(): return false
	var reading_retry: bool=_transaction_context=="foreground" and _transaction_motion_origin==state
	var committed:=commit_state(_retry_transaction_state,false,_transaction_context,_transaction_after,_transaction_motion_origin==state)
	if committed and reading_retry: foreground.restore_reading()
	return committed


# Ends the game, for the title screen: nothing shown, nothing running, no
# state and so nothing to save. Refused, with an error, unless can_load().
func close(end_session := true) -> bool:
	if not can_load():
		push_error("close() refused: the game is in the middle of something")
		return false
	_transaction_after=Callable()
	_transaction_origin=null; _transaction_motion_origin=null
	_transaction_context=""
	foreground.reset(true)
	if entry_flow!=null and end_session: entry_flow.closed()
	if state == null:
		if entry_flow!=null: _sync_entry_cast({})
		if end_session: saves.end_run()
		return true
	_action_id += 1
	_autosave_due = false
	_owns_autosave = false
	_product_end_due = ""
	selected = ""
	speech.clear()
	audio.stop_music()
	cast.stop_world()
	if room_script != null:
		retire_script(room_script)
		room_script = null
	room_view.hide_all()
	for id in actors:
		actors[id].walk_route([])
		actors[id].visible = false
	hover_end()
	state = null
	if entry_flow!=null: _sync_entry_cast({})
	_retry_transaction_state=null
	save_dirty=false
	if end_session: saves.end_run()
	room = ""
	_overlay.queue_redraw()
	return true


# What the load and save menus show for a save.
func _save_meta() -> Dictionary:
	return {"room_name": room_geo(state.actors[state.active]["room"])["name"], "crew_name": crew[state.active]["name"]}

func _checkpoint_labels(raw: Dictionary) -> Dictionary:
	var who: String=raw.get("active","")
	var where: String=raw.get("actors",{}).get(who,{}).get("room","")
	if not crew.has(who) or not rooms.has(where): return {}
	return {"room_name":room_geo(where)["name"],"crew_name":crew[who]["name"]}


# Writes the autosave (CONTINUE on the title screen) now, if autosave is on,
# the player has control and this game owns the autosave: it was loaded from a
# save, or has been through a door or a crew switch since it began. So a new
# game, a start point or a save that fell back to a new game never replaces
# the CONTINUE point by just being started. True if it wrote.
func autosave_now() -> bool:
	if not (autosave and _owns_autosave and can_save()):
		return false
	_autosave_due = false
	sync_state()
	var saved: bool=saves.autosave(state,_save_meta())
	if saves.is_versioned():
		save_dirty=not saved
		if not saved: save_problem.emit("auto","auto")
	return saved


# The crew went through a door, or a switch cut to another crew member's room:
# progress of this game's own. It owns the autosave from now on and writes it
# once the player has control.
func _arrived() -> void:
	_owns_autosave = true
	_autosave_due = autosave


# The app going to the background (phones), the window being closed
# (desktop) or Android's back button may be the last we hear of it. (Back
# doesn't quit the game: application/config/quit_on_go_back is off and the
# menus treat it as Esc, see menus.gd. But a press is often the player on
# their way out, and the autosave is cheap.)
# A browser says neither. A hidden tab or a click outside the game arrives
# as a loss of focus (the canvas's blur), so on the web that writes the
# autosave too (the shell, game/web/shell.html, gives a hidden page the
# frames it needs to copy it to the browser's storage), and the music holds
# still until the page is back. Leaving the page may not even give a frame
# after the blur, which is why on the web progress writes the autosave as it
# happens as well (_on_state_changed).
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and saves!=null and saves.is_versioned(): return # menus own the explicit quit/retry flow
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST]:
		autosave_now()
	elif web and audio != null and what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		autosave_now()
		audio.hold_music(true)
	elif web and audio != null and what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		audio.hold_music(false)


# ------------------------------------------------------------------ test drivers
# Each does what the matching tap does, and is ignored (with an error) when a
# tap would be.

# Uses item if given, otherwise whatever is selected.
func use(hotspot_id: String, item := "") -> void:
	if _refused("use"):
		return
	var h := _hotspot(hotspot_id)
	if h.is_empty() or not _select_for_use(item):
		return
	await _use_hotspot(h)


func use_actor(id: String, item := "") -> void:
	if _refused("use_actor"):
		return
	if not actors.has(id) or id == state.active or not actor_visible(id):
		push_error("use_actor: %s isn't another actor in %s" % [id, room])
		return
	if not _select_for_use(item):
		return
	await _use_actor(id)


func select_item(item: String) -> void:
	if _refused("select_item"):
		return
	if not item in state.inventory.get(state.active, []):
		push_error("select_item: %s doesn't have %s" % [state.active, item])
		return
	await _tap_item(item)


func switch_to(id: String) -> void:
	if _refused("switch_to"):
		return
	if not crew_available(id):
		push_error("switch_to: %s isn't in the crew" % id)
		return
	await _switch(id)


func _refused(what: String) -> bool:
	if busy or foreground_active() or blackout or saves.has_pending_commit():
		push_error("%s() ignored: the game is busy, as a tap would be" % what)
		return true
	return false


func _select_for_use(item: String) -> bool:
	if item == "":
		return true
	if not item in state.inventory.get(state.active, []):
		push_error("%s doesn't have %s" % [state.active, item])
		return false
	selected = item
	return true


func _hotspot(id: String) -> Dictionary:
	for h in geo["hotspots"]:
		if h["id"] == id:
			if room_view.hotspot_enabled(h):
				return h
			push_error("hotspot %s is disabled by its prop" % id)
			return {}
	push_error("no hotspot %s in %s" % [id, room])
	return {}


# ------------------------------------------------------------------ actions

func _use_hotspot(h: Dictionary) -> void:
	var progress_before: Dictionary=_progress_snapshot()
	if interaction_policy != null and not interaction_policy.allow_action("hotspot", h["id"]): return
	_action_id += 1
	var my_id := _action_id
	var who: String = state.active
	var item := selected
	var a = actors[who]
	_start_walk(a, h["walk"])
	await _arrival(a)
	if my_id != _action_id:
		return  # the player changed their mind on the way
	a.face(h["face"])
	busy = true
	await _sleep(Feel.USE_PAUSE)
	await _run_handler("use_" + h["id"], who, item)
	selected = ""
	busy = false
	if foreground.start_pending(): await foreground.wait_until_settled()
	else: _checkpoint_action(progress_before)


# Walks over beside another actor. An NPC is used like a hotspot (the room's
# use_<npc>, else the NPC's own script). Crew on crew: with an item selected
# it's handed over, otherwise a poke.
func _use_actor(id: String) -> void:
	var progress_before: Dictionary=_progress_snapshot()
	if interaction_policy != null and not interaction_policy.allow_action("actor", id): return
	var off_duty: bool=crew_dialogue!=null and crew_dialogue.available(state,id) and (selected=="" or not crew_available(id))
	if crew.has(id) and not crew_available(id) and not off_duty:
		busy = true
		if not foreground.queue("crew.busy",{"who":state.active,"recipient":id,"item":selected}):
			await say(state.active, I18n.t("THEY'RE BUSY RIGHT NOW."))
		selected = ""
		busy = false
		if foreground.start_pending(): await foreground.wait_until_settled()
		return
	_action_id += 1
	var my_id := _action_id
	_actor_approach={"action":my_id,"target":id}
	var who: String = state.active
	var item := selected
	var a = actors[who]
	var other = actors[id]
	var side := -Feel.GIVE_SIDE if a.position.x < other.position.x else Feel.GIVE_SIDE
	if not npcs.get(id,{}).get("use_from_here",false):
		_start_walk(a, other.position + Vector2(side, 0))
		await _arrival(a)
	else: a.walk_route([]) # a call from here cancels any earlier approach intent
	if my_id != _action_id:
		return
	a.face("right" if other.position.x > a.position.x else "left")
	busy = true
	if npcs.has(id):
		await _sleep(Feel.USE_PAUSE)
		await _run_handler("use_" + id, who, item, id)
	elif off_duty:
		var conversation=crew_dialogue.new(); conversation.game=self
		await conversation.talk(who,id,item)
	elif item != "" and item in state.inventory.get(id, []):
		if not foreground.queue("crew.duplicate",{"who":who,"recipient":id,"item":item}):
			await say(id, I18n.t("I ALREADY HAVE SOME. KEEP THAT BATCH."))
	elif item != "":
		if not foreground.queue("handover.item",{"who":who,"recipient":id,"item":item}):
			remove_item(who, item)
			add_item(id, item)
			sfx("pickup")
			await say(id, I18n.t("THANKS. I GUESS."))
	else:
		if not foreground.queue("crew.poke",{"who":who,"recipient":id,"item":""}):
			await say(id, I18n.t(crew[id]["poke"]))
	selected = ""
	busy = false
	_actor_approach={}
	if foreground.start_pending(): await foreground.wait_until_settled()
	else: _checkpoint_action(progress_before)

func approaching_actor(id: String) -> bool:
	return _actor_approach.get("action",-1)==_action_id and _actor_approach.get("target","")==id

func _progress_snapshot() -> Dictionary:
	if not saves.is_versioned() or state==null: return {}
	# Position changes and ambient motion aren't the first progress boundary.
	return {"inventory":state.inventory.duplicate(true),"flags":state.flags.duplicate(true),
		"forks":state.forks.duplicate(true),"convo_used":state.convo_used.duplicate(true)}

func _checkpoint_action(before: Dictionary) -> void:
	if web and state!=null and state.flag(prologue_end_beat): return # the end card retains the pre-engines Continue
	if saves.is_versioned() and state!=null and not before.is_empty() and before!=_progress_snapshot():
		_owns_autosave=true
		save_dirty=true
		_autosave_due=autosave


# Runs a room handler, or for an NPC without one in this room the NPC's own
# script's use(); if that neither speaks, plays a sound nor changes room, who
# says a quip instead.
func _run_handler(method: String, who: String, item: String, npc := "") -> void:
	if npc=="" and method.begins_with("use_"):
		for action in foreground_handlers:
			if action.get("requires_handler",true) and (room_script==null or not room_script.has_method(method)): continue
			if foreground.queue(action["id"],{"who":who,"target":method.trim_prefix("use_"),"item":item}): return
	var script = room_script  # keeps the script alive while its handler runs, even through a door
	var before := _fg_events
	if script != null and script.has_method(method):
		await script.call(method, who, item)
	elif npc != "":
		var own = cast.npc_script(npc)  # a fresh one per use, kept alive here
		if own != null and own.has_method("use"):
			await own.use(who, item)
	# An opened menu is the handler's response. A fallback line would pause
	# behind that menu and keep the original interaction busy indefinitely.
	if _fg_events == before and not menu_open:
		await _fallback_quip(who, "actor" if npc!="" else "object", npc if npc!="" else method.trim_prefix("use_"), [item] if item!="" else [])


func _fallback_quip(who: String,kind: String,target: String,used: Array) -> void:
	var spoken:=next_quip(who)
	if not foreground.queue("quip."+kind,{"who":who,"target":target,"items":used,"spoken":spoken}):
		await say(who,I18n.t(spoken))


func _switch(id: String) -> void:
	if id == state.active or not crew_available(id):
		return
	sfx("blip")
	_action_id += 1
	selected = ""
	state.active = id
	state.changed.emit()
	if actors[id].room != room:
		await hard_cut(actors[id].room)
	else:
		_snap_camera()
	if interaction_policy!=null and interaction_policy.has_method("after_switch"): interaction_policy.after_switch(id)


func _start_walk(a, target: Vector2) -> void:
	a.walk_route(Walkmap.route(room_geo(a.room)["walk_boxes"], a.position, target),test_turbo)


# Waits for the walk to end. arrived can come from an earlier walk that was
# stopped (it's emitted deferred), so it only counts once the walker stands still.
func _arrival(a) -> void:
	await a.arrived
	while a.is_walking():
		await a.arrived


# Cycles through a shuffled copy of who's quips, never the same twice running.
func next_quip(who: String) -> String:
	var all: Array = crew[who].get("quips", [])
	if all.is_empty():
		push_error("%s has no quips" % who)
		return "HMM."
	var bag: Array = _quips.get(who, [])
	if bag.is_empty():
		bag = all.duplicate()
		for i in range(bag.size() - 1, 0, -1):  # Fisher-Yates on our own generator
			var j := _rng.randi_range(0, i)
			var t = bag[i]
			bag[i] = bag[j]
			bag[j] = t
		if bag.size() > 1 and bag[0] == _last_quip.get(who, ""):
			bag.push_back(bag.pop_front())
		_quips[who] = bag
	var line: String = bag.pop_front()
	_last_quip[who] = line
	return line


func add_item(who: String, item: String) -> void:
	if not items.has(item):
		push_error("no item " + item)
		return
	if not state.inventory.has(who):
		state.inventory[who] = []
	state.inventory[who].append(item)
	hud.show_new_item(who)
	state.changed.emit()


func remove_item(who: String, item: String) -> void:
	var inv: Array = state.inventory.get(who, [])
	if not item in inv:
		push_error("%s has no %s to take" % [who, item])
		return
	inv.erase(item)
	hud.page(who)  # clamp after the last item on a page has gone
	if who == state.active and selected == item and not item in inv:
		selected = ""
	state.changed.emit()


# ------------------------------------------------------------------ script primitives
# Foreground unless told otherwise: recorded in the transcript and finished at
# once under fast_forward. Background calls are neither. Text arrives here
# translated (script_base.gd's helpers and the engine's own lines use I18n.t()).

func speaker_label(who: String) -> String:
	# Only names supplied by this product, and only after a hidden actor is
	# physically introduced. Never derive a display name from a resource ID.
	if state!=null and state.unavailable.get(who)=="offstage": return ""
	var data: Dictionary=crew.get(who,npcs.get(who,{}))
	return data.get("name","")

func say(who: String, text: String, foreground := true, source := {}) -> void:
	var a = actor(who)
	if a == null:
		return
	a.face("front")  # everyone turns to the camera to talk
	if foreground:
		record("say %s: %s" % [who, text])
		if fast_forward or test_turbo:
			return
		_fg_running += 1
	var labelled: Dictionary=source.duplicate(true)
	labelled["name"]=speaker_label(who)
	var token: int = speech.start(a, text, foreground, labelled)
	while speech.is_current(who, token):
		if foreground and fast_forward:
			speech.stop(who, token)
			break
		await get_tree().process_frame
	await _sleep(Feel.SPEECH_GAP, foreground)
	if foreground:
		_fg_running -= 1


# Checked every frame, so a fast_forward that starts mid-walk finishes it at once.
# A background walk holds still while scripts are paused.
func walk(who: String, to: Vector2, foreground := true) -> void:
	var a = actor(who)
	if a == null:
		return
	var boxes: Array = room_geo(a.room)["walk_boxes"]
	a.walk_route(Walkmap.route(boxes, a.position, to), foreground and (fast_forward or test_turbo))
	a.background = not foreground and a.is_walking()
	if foreground:
		_fg_running += 1
	while a.is_walking():
		await get_tree().process_frame
		if foreground and fast_forward and a.is_walking():
			a.walk_route(Walkmap.route(boxes, a.position, to), true)
	sync_state()
	if foreground:
		_fg_running -= 1


func wait(seconds: float) -> void:
	_fg_running += 1
	await _sleep(seconds)
	_fg_running -= 1


# The actor's sideways shake, step by step so fast_forward can cut it short.
func jiggle(who: String) -> void:
	var a = actor(who)
	if a == null:
		return
	var sprite: Sprite2D = a.sprite
	_fg_running += 1
	for dx in Feel.JIGGLE:
		if fast_forward:
			break
		sprite.position.x = 0 if reduced_effects() else dx
		await _sleep(Feel.JIGGLE_STEP)
	sprite.position.x = 0  # square again, even when cut short
	_fg_running -= 1


func sfx(name: String) -> void:
	record("sfx " + name)
	if not fast_forward:
		audio.play(name)


# The active crew member goes through a door into target at entry.
func go(target: String, entry) -> void:
	if not rooms.has(target):
		push_error("go: no room " + target)
		return
	var a = actors[state.active]
	var st = state
	var from: String = a.room
	if entry is String or entry is StringName:
		var entries = room_geo(target).get("entries", {})
		var named = entries.get(String(entry), null) if entries is Dictionary else null
		if not named is Dictionary or not named.get("pos") is Vector2 or not named.get("room") is String:
			push_error("go: invalid entrance %s in %s" % [entry,target])
			return
		if named["room"] != from:
			push_error("go: entrance %s in %s is from %s, not %s" % [entry,target,named["room"],from])
			return
		if not Walkmap.walkable(room_geo(target)["walk_boxes"], named["pos"]):
			push_error("go: entrance %s in %s is off the walk boxes" % [entry,target])
			return
		entry = named["pos"]
	elif not entry is Vector2 and not entry is Vector2i:
		push_error("go: entry must be a named entrance or Vector2")
		return
	# Resolve before a policy reserves a threshold; policies still receive positions.
	var position := Vector2(entry)
	if interaction_policy != null:
		var arrival: Dictionary = interaction_policy.before_exit(state.active, from, target, position)
		target = arrival["room"]
		position = arrival["pos"]
	audio.stop_music()  # the tune cuts dead at the door
	sfx("door")
	blackout = true
	await _sleep(Feel.DOOR_BLACKOUT)
	if state != st:
		return  # a load or start point meanwhile has the last word
	a.room = target
	a.position = position
	a.face("front")
	_enter_room(target)
	_arrived()
	await _sleep(Feel.DOOR_SETTLE)
	blackout = false
	if interaction_policy != null: interaction_policy.after_exit(state.active, from, target)


# Moves an NPC to pos in to_room (see cast.gd): it walks where the player can
# see it, and changes room at once anywhere else.
func move_npc(id: String, to_room: String, pos: Vector2, foreground := true) -> void:
	await cast.move_npc(id, to_room, pos, foreground)


# A foreground event: it goes in the transcript, and a handler that has one
# has answered (no fallback quip).
func record(entry: String) -> void:
	_fg_events += 1
	transcript.append(entry)


# Drops what the player was doing: a use on its way drops out and their own
# walk stops (a background walk carries on).
func drop_player_action() -> void:
	_action_id += 1
	var a = actors[state.active]
	if a.is_walking() and not a.background:
		a.walk_route([])


# A hard cut: the music stops, a beat of black, then the room. arrive as in
# _enter_room.
func hard_cut(id: String, arrive := true) -> void:
	var st = state
	audio.stop_music()
	blackout = true
	await _sleep(Feel.SWITCH_BLACKOUT)
	if state != st:
		return  # a load or start point meanwhile showed its own room
	_enter_room(id, true, arrive)
	if arrive:
		_arrived()  # a crew switch (a cutscene's cuts don't arrive)
	blackout = false


# Game time, counted in frames; fast_forward ends it unless it's background.
func _sleep(seconds: float, skippable := true) -> void:
	var left := seconds
	while left > 0.0:
		if skippable and (fast_forward or test_turbo):
			return
		await get_tree().process_frame
		left -= get_process_delta_time()


# ------------------------------------------------------------------ cutscenes and conversations (director.gd)

func cutscene(body: Callable) -> void:
	await director.cutscene(body)


func is_cutscene_body(obj) -> bool:
	return director.is_cutscene_body(obj)


func can_skip() -> bool:
	return foreground.can_skip() or director.can_skip()


func skip_cutscene() -> void:
	if foreground.can_skip(): foreground.skip()
	else: director.skip_cutscene()


func cut_to(id: String) -> void:
	await director.cut_to(id)


func caption(text: String) -> void:
	await director.caption(text)


func choose(convo_room: String, convo: String, options: Array) -> String:
	return await director.choose(convo_room, convo, options)


# ------------------------------------------------------------------ rooms

# Shows a room with a fresh script. arrive is false when nobody actually came
# in (a cutscene's cut_to, and its cut back): then on_enter() doesn't run and
# the room isn't marked visited. During a cutscene the room's background()
# waits for it to end.
func _enter_room(id: String, cut := true, arrive := true) -> void:
	if not rooms.has(id):
		push_error("no room " + id)
		return
	if room_script != null:
		retire_script(room_script)
	room = id
	geo = room_geo(id)
	room_script = _make_script(id)
	room_view.show(id, geo, room_script)
	for nid in npcs:
		if state.actors.get(nid, {}).get("room") == id:
			actor(nid)  # appears at its stored spot, made the first time
	for aid in actors:
		actors[aid].visible = actor_visible(aid)
	_snap_camera()
	record("room " + id)
	audio.start_music(geo.get("music", ""), cut)
	var script = room_script
	if arrive:
		script.on_enter()
		state.visited[id] = true
	room_view.refresh_props()
	sync_state()
	if script != room_script:
		return  # on_enter has already left
	director.start_background(script)


# A room's geometry (walk boxes, hotspots, props, anchors), loaded once.
func room_geo(id: String) -> Dictionary:
	if not _geometry.has(id):
		_geometry[id] = load(rooms[id] + "geometry.gd").DATA.duplicate(true)
		if room_scripts.has(id):
			var extension = load(room_scripts[id]).new()
			if extension.has_method("extend_geometry"):
				extension.extend_geometry(_geometry[id])
	return _geometry[id]


# The node of a crew member or NPC. An NPC's is made the first time it's
# needed, normally when its room is first shown, at its stored spot.
func actor(id: String) -> Node2D:
	if actors.has(id):
		return actors[id]
	if not npcs.has(id):
		push_error("no actor " + id)
		return null
	var s: Dictionary = state.actors[id]
	if not rooms.has(s["room"]):
		push_error("%s is in %s, which this game doesn't have" % [id, s["room"]])
		return null
	var a: Node2D = room_view.make_actor(id, npcs[id])
	a.room = s["room"]
	a.position = s["pos"]
	a.face(s["facing"])
	a.visible = a.room == room and state.unavailable.get(id) != "offstage"
	_add_actor(id, a)
	return a


func _add_actor(id: String, a: Node2D) -> void:
	a.arrived.connect(sync_state)
	a.paused = scripts_paused
	actors[id] = a


func _make_script(id: String):
	var path: String = room_scripts.get(id, rooms[id] + id + ".gd")
	var s
	if ResourceLoader.exists(path):
		s = load(path).new()
	else:
		push_error("room %s has no script at %s" % [id, path])
		s = RoomScript.new()
	s.game = self
	s.room_id = id
	s.geo = geo
	return s


# Keep a stopped background's owner alive until its helpers have observed
# cancellation and parked. A speech gap or a walk can take several frames;
# releasing the RefCounted script first invalidates the pending await.
func retire_script(script) -> void:
	script.alive = false
	while script.background_pending > 0:
		await get_tree().process_frame
	# The argument retains the script until every helper has parked.


func prop_node(prop_id: String) -> Sprite2D:
	return room_view.prop_node(prop_id)


func texture(path: String) -> Texture2D:
	return room_view.texture(path)


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if state == null or room == "":
		return
	clock += delta
	if can_save() and not foreground_active() and not in_cutscene and not menu_open: exploration_clock += delta
	speech.configure(room,_world_offset(),view_w(),speech_reserved(),director.choosing or foreground.choosing())
	speech.tick(delta)
	foreground.tick(delta)
	room_view.refresh_props()
	for id in actors:
		actors[id].z_index = int(actors[id].position.y)
		actors[id].visible = actor_visible(id)
	sync_state()
	if _autosave_due and can_save():
		autosave_now()
	if _product_end_due!="":
		_end_if_due()
	_update_camera(delta)
	if pointer != null:
		if _hover_room not in ["",room] or not hud.keeps_hover(pointer): hovered = _name_at(pointer)
		_hover_room=room
	room_view.redraw_fx()
	_overlay.queue_redraw()


func view_w() -> int:
	return view.x if view.x > 0 else int(get_viewport_rect().size.x)


func _world_offset() -> int:
	var room_w: int = geo["width"]
	if room_w <= view_w():
		return (view_w() - room_w) / 2
	return -_cam_x


# The camera follows the active crew member. In a room they aren't in (a
# cutscene's cut_to) it rests on the middle.
func _focus_x() -> int:
	var a = actors[state.active]
	return int(a.position.x) if a.room == room else int(geo["width"]) / 2


func _snap_camera() -> void:
	_cam_x = Camera.snap(_focus_x(), view_w(), geo["width"])
	_cam_target = _cam_x
	_world.position.x = _world_offset()


func _update_camera(delta: float) -> void:
	_cam_target = Camera.retarget(_cam_target, _focus_x(), _cam_x, view_w(), geo["width"])
	_cam_clock += delta
	# Optional finer camera steps keep its original speed and dead zone.
	# Actor pathfinding, walking cadence and all world timers stay unchanged.
	var tick: float=Feel.CAM_TICK/Feel.CAM_STEP if reduced_effects() else Feel.CAM_TICK
	while _cam_clock >= tick:
		_cam_clock -= tick
		_cam_x = int(move_toward(_cam_x,_cam_target,1)) if reduced_effects() else Camera.step(_cam_x, _cam_target)
	_world.position.x = _world_offset()


# ------------------------------------------------------------------ drawing

func speech_reserved() -> Array:
	var reserved: Array=[]
	if interaction_policy!=null and interaction_policy.has_method("speech_reserved"): reserved=interaction_policy.speech_reserved()
	if menus!=null: reserved.append_array(menus.speech_reserved())
	return reserved

func _draw_overlay() -> void:
	if state == null:
		return  # no game: the title screen is up
	hud.draw(_overlay, view_w())
	if foreground.reading_document(): return
	speech.draw(_overlay,room,_world_offset(),view_w(),speech_reserved(),director.choosing or foreground.choosing())
	if interaction_policy != null: interaction_policy.draw(_overlay)
