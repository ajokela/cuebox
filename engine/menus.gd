extends Node2D
const Ink=preload("res://engine/reading_ink.gd")

# The title screen, the pause menu, options, the save and load slots and, in
# debug builds, the dev menu of start points. One page at a time, drawn opaque
# over the game in the pixel font; every item is a full-width row that a tap
# picks and a real mouse lights (touch never does). While a page is up the game
# holds still and takes no input (game.menu_open).
#
# The pause menu opens from MENU on the HUD or with Esc, and the dev menu with
# F1 or three quick taps on the HUD's sentence line, but only when the player
# has control (game.can_save()), so saving and loading from them is always
# safe. In a cutscene Esc still skips it. QUIT TO TITLE autosaves first (see
# game.autosave_now: a new game that hasn't been through a door yet leaves the
# old CONTINUE alone). When the demo ends (game.demo_ended) the thanks screen
# goes up over it, with BACK TO TITLE as its only way on; like the title
# screen itself that doesn't autosave, so CONTINUE stays from before the
# ending. Nothing here sells anything: DISPLAY lists only DEFAULT and the
# modes the player owns, and the demo's thanks screen has no store, price or
# link. Every text is in the player's language (I18n.t()), except each
# language's own name and the dev menu's start points.
#
# In the browser build (game.web) the prologue ends the same way: when the
# game says so (game.prologue_ended) the end card goes up, with VISIT THE
# the configured website (in the same tab) and BACK TO TITLE, and no
# autosave on the way out. Nothing on the web quits the app: a quit there
# would only freeze the page, so back on the title screen does nothing.
#
# Android's back button (or a back swipe) is the game's Esc, not a quit
# (application/config/quit_on_go_back is off): over the game it opens the
# pause menu, or skips a cutscene; on a page it goes back as Esc does; on the
# thanks screen it's BACK TO TITLE; only on the title screen does it leave
# the app. (game.gd writes the autosave as back is pressed.) One press of a
# back key arrives as two notifications a moment apart (the activity's back
# and the key's own), a back gesture as one, so notifications closer together
# than BACK_REPEAT count as one press.

const Feel = preload("res://engine/feel.gd")
const PixelFont = preload("res://engine/pixel_font.gd")
const StartPoints = preload("res://engine/start_points.gd")
const I18n = preload("res://engine/i18n.gd")
const MenuPages = preload("res://engine/menu_pages.gd")

const ROW := 12  # each item's row height: an easy tap scaled up on a phone
const TITLE_ROWS_Y := 84  # where the title screen's rows start
# presentation title_starfield "warp": a fly-through starfield behind the title, stepped like a
# 1990 machine rather than smooth; Reduced Effects keeps the still field.
const WARP_STARS := 90
const WARP_HZ := 12.0       # steps a second
const WARP_SECONDS := 3.5   # a star's trip from the far distance past the edge
const HEADER_Y := 20
const ROWS_Y := 52  # where other pages' rows start
const STATUS_Y := 168
const END_TITLE_Y := 48  # the demo's thanks screen: its heading, its line and its row
const END_NOTE_Y := 74
const END_ROWS_Y := 108
const NOTICE_TIME := 4.0  # how long a notice stays over the game
const TAP_WINDOW := 1.0  # three taps on the sentence line within this many seconds open the dev menu
const SPEEDS := ["normal", "slow", "fast"]
const BACK_REPEAT := 400  # ms: Android's back notifications closer together than this are one press

const C_WHITE := Color("eeeadc")
const C_YELLOW := Color("e4c458")
const C_LGREY := Color("a8acb4")
const C_MGREY := Color("6c707a")
const C_BLUE := Color("7a8ed6")

var game
var is_debug: bool
var page := ""  # "title", "pause", "options", "save", "load", "dev", "demo_end", "prologue_end", or "" with no menu up
var status := ""  # one line at the bottom of the page, such as "SAVED IN SLOT 2."
var pointer = null  # where a real mouse is over a page, in view coordinates, or null
var custom_panel: Node2D  # product-owned page; no private text or data in this engine
var notice := ""  # a line shown over the game for a while after the menu closes

var _context_source:={}
var _context_back:="pause"
var _notice_left := 0.0

var _rows := []  # the page's items: {"text": String, "do": Callable, "on": bool}
var _back := "title"  # where options and load go back to: "title" or "pause"
var _first := 0  # the first start point on the dev page, when they don't all fit
var _taps := []  # game.clock at the latest taps on the sentence line
var _blip := AudioStreamPlayer.new()
var _title_music := AudioStreamPlayer.new()
var _title_music_held := false
var quit_app := func(): get_tree().quit()  # what back does on the title screen (tests count it instead)
var storage_body := ""
var _storage_rows: Array=[]
var _storage_back:=Callable()
var _storage_origin:="title"
var _quit_requested:=false
var _storage_panel: Node2D
var _waiting_action:=""
var open_url := _open_url  # how website action opens the website (tests catch it instead)
var _last_back := -(1 << 62)  # Time.get_ticks_msec() at the last back press acted on (long ago)
var reader


func _init(game_, is_debug_ := OS.is_debug_build()) -> void:
	game = game_
	reader = MenuPages.new(self)
	is_debug = is_debug_
	name = "Menus"
	z_index = 2000  # over the game's HUD and speech
	_blip.stream = game.audio._sound("blip")
	_blip.volume_db = Feel.SFX_DB
	add_child(_blip)
	add_child(_title_music)


func _ready() -> void:
	game.menus = self
	game.hud_tapped.connect(_on_hud_tapped)
	game.demo_ended.connect(_open.bind("demo_end"))
	game.prologue_ended.connect(_open.bind("prologue_end"))
	game.save_problem.connect(_on_save_problem,CONNECT_DEFERRED)
	game.save_finished.connect(_on_save_finished)
	game.audio.levels_changed.connect(_apply_sound_level)
	_apply_sound_level()
	if game.entry_flow!=null: game.entry_flow.menus_ready()


func _apply_sound_level() -> void:
	_blip.volume_db=game.audio.gain_db(game.audio.effects_level,Feel.SFX_DB)
	_title_music.volume_db=game.audio.gain_db(game.audio.music_level,Feel.MUSIC_DB)


# Menus are a sibling of the paused game, so menu music belongs here. A
# product-owned panel may request a cue while its world is paused. Ordinary
# title/options/load pages retain the title cue; closing resumes room music.
func _sync_title_music() -> void:
	var tune: String=game.title_music if game.state==null and page!="" else ""
	var owner: Node2D=custom_panel if is_instance_valid(custom_panel) else _storage_panel
	if page!="" and is_instance_valid(owner) and owner.has_method("menu_music"):
		tune=owner.menu_music()
	if tune=="":
		_title_music.stop()
		return
	var stream=game.audio._tune(tune)
	if stream==null:
		_title_music.stop()
		_title_music.stream=null
		return
	if not _title_music.playing or _title_music.stream!=stream:
		_title_music.stream=stream
		_title_music.play()
	_title_music.stream_paused=_title_music_held


# ------------------------------------------------------------------ pages

# The title screen. A game under way ends first (game.close()).
func show_title() -> void:
	if game.close():
		close()
		_open("title")


# Opens "pause", or "dev" in a debug build, if the player has control. What
# they were on their way to do is dropped.
func open(which: String) -> void:
	if page != "" or not which in ["pause", "dev"] or (which == "dev" and not is_debug) or not game.can_save():
		return
	_context_source=game.hud.context_source()
	if not game.foreground_active(): game.drop_player_action()
	game.hover_end()
	_taps.clear()
	_first = 0
	_open(which)


func close() -> void:
	_title_music.stop()
	if is_instance_valid(_storage_panel): _storage_panel.queue_free()
	_storage_panel=null
	if is_instance_valid(custom_panel):
		custom_panel.queue_free()
	custom_panel = null
	page = ""
	status = ""
	_rows = []
	pointer = null
	reader.reset()
	game.menu_open = false


func show_panel(panel: Node2D) -> void:
	close()
	page = "custom"
	game.menu_open = true
	custom_panel = panel
	add_child(panel)
	_sync_title_music()


# The items' texts on the page shown.
func items() -> Array:
	return _rows.map(func(r): return r["text"])


# Picks the item with this text, as a tap on it does. False if there's no
# such item or it can't be picked (an empty slot to load).
func pick(text: String) -> bool:
	var i := items().find(text)
	if i < 0 or not _rows[i]["on"]:
		return false
	_activate(i)
	return true


# The thanks screen at the end of the demo: what it says over its one row,
# BACK TO TITLE. Nothing to buy and nowhere to go but the title.
func demo_end_texts() -> Array:
	return _texts("demo_end", [I18n.mark("THANKS FOR PLAYING"), I18n.mark("THE END")])


# The web build's end card: what it says over its rows, website action and
# BACK TO TITLE.
func prologue_end_texts() -> Array:
	return _texts("prologue_end", [I18n.mark("THANKS FOR PLAYING"), I18n.mark("THE END")])


func recovery_progress_text(progress) -> String:
	return I18n.t(game.presentation.get("recovery_progress", I18n.mark("PROGRESS: %s"))) % str(progress)


func reading_back_row() -> int:
	var label:=""
	match page:
		"pause": label=I18n.t("RESUME")
		"hud_context": label=I18n.t("BACK")
		"options","options_reading","options_sound","options_effects","options_display","options_language","volume_music","volume_effects","save","load","dev": label=I18n.t("BACK")
		"demo_end","prologue_end": label=I18n.t("BACK TO TITLE")
		"storage":
			# A pending acknowledgement has no Back. Only an existing authored
			# return action may become the always-available footer control.
			if _storage_back.is_valid():
				for i in _rows.size():
					if _rows[i]["on"] and _rows[i]["do"]==_storage_back: return i
	for i in _rows.size():
		if _rows[i]["text"]==label and _rows[i]["on"]: return i
	return -1


func reading_sections() -> Array:
	var titles: Array=_title_texts() if page=="title" else demo_end_texts() if page=="demo_end" else prologue_end_texts() if page=="prologue_end" else [_header()]
	var sections:=[]
	for i in titles.size(): sections.append({"id":"title:"+str(i),"text":titles[i],"role":"title" if i==0 or page=="title" else "source"})
	if page=="pause" and game.story_clock!=null:
		sections.append({"id":"clock","text":game.story_clock.header(game.state),"role":"source"})
	var encounter:=reading_status()
	for i in encounter.size(): sections.append({"id":"encounter:"+str(i),"text":encounter[i],"role":"source"})
	if page=="pause" and game.speech.text_scale==2:
		var context: Array=game.hud.reading_context()
		for i in context.size(): sections.append({"id":"hud:"+str(i),"text":context[i],"role":"source"})
	if page=="hud_context": sections.append_array(game.hud.context_sections(_context_source))
	if page in ["volume_music","volume_effects"]:
		sections.append({"id":"volume","text":I18n.t("VOLUME: %s") % _volume_name(_volume_key()),"role":"source"})
	if page=="storage": sections.append({"id":"storage","text":storage_body})
	if status!="": sections.append({"id":"status","text":status,"role":"source"})
	var back_row:=reading_back_row()
	for i in _rows.size():
		if i!=back_row: sections.append({"id":"row:"+str(i),"text":_rows[i]["text"],"action":str(i),"enabled":_rows[i]["on"]})
	return sections


func reading_status() -> Array:
	if page in ["title","demo_end","prologue_end"] or game.state==null: return []
	if game.interaction_policy!=null and game.interaction_policy.has_method("reading_status"):
		return game.interaction_policy.reading_status()
	return []


func compact_fits() -> bool:
	if page in ["","custom"]: return true
	if page=="title" and _title_texts().size()>2: return false
	if game.speech.text_scale!=1 or page in ["storage","hud_context"] or not reading_status().is_empty(): return false
	for section in reading_sections():
		if "\n" in section["text"] or PixelFont.text_rect(section["text"],Vector2.ZERO).size.x>game.view_w()-24: return false
	for i in _rows.size():
		if compact_row_rect(i).end.y>STATUS_Y-4 or PixelFont.text_rect(_rows[i]["text"],Vector2.ZERO).size.x>game.view_w()-24: return false
	return true


func row_rect(i: int) -> Rect2:
	if reader.active(): return reader.row_rect(i)
	return compact_row_rect(i)


func compact_row_rect(i: int) -> Rect2:
	var top := ROWS_Y
	if page == "title":
		top = TITLE_ROWS_Y
	elif page in ["demo_end", "prologue_end"]:
		top = END_ROWS_Y
	elif page=="storage":
		top=132
	return Rect2(0, top + i * ROW, game.view_w(), ROW)


func row_at(p: Vector2) -> int:
	for i in _rows.size():
		if row_rect(i).has_point(p):
			return i
	return -1


# The row under a real mouse, or -1.
func hovered_row() -> int:
	return -1 if pointer == null else row_at(pointer)


func tap(p: Vector2) -> void:
	if game.reading_input_consumed(): return
	if page == "custom":
		custom_panel.tap(p)
		return
	if page!="": reader.tap(p)


# The languages this build offers: [locale, name]. (The game starts in one,
# game.setup: I18n.start_locale.)
func languages() -> Array:
	return I18n.languages(is_debug)


func _open(which: String) -> void:
	reader.reset()
	page = which
	status = ""
	notice = ""
	game.menu_open = true
	_build()
	reader.layout()
	_sync_title_music()


func _activate(i: int) -> void:
	if _blip.stream != null: _blip.play()
	_rows[i]["do"].call()
	if page != "":
		_build()  # options show their new values
		if page!="custom": reader.layout()


func _row(text: String, action: Callable, on := true) -> void:
	_rows.append({"text": text, "do": action, "on": on})


func _build() -> void:
	_rows = []
	match page:
		"title":
			if game.saves.exists("auto"):
				_row(I18n.t("CONTINUE"), _load.bind("auto"))
			_row(I18n.t("NEW GAME"), _new_game)
			_row(I18n.t("LOAD"), _to.bind("load", "title"))
			_row(I18n.t("OPTIONS"), _to.bind("options", "title"))
		"pause":
			_row(I18n.t("RESUME"), close)
			_row(I18n.t("CONTEXT"),_show_context.bind("pause"))
			if game.reference!=null:
				for entry in game.reference.menu_rows(): _row(entry[0],entry[1])
			_row(I18n.t("SAVE"), _to.bind("save", "pause"))
			_row(I18n.t("LOAD"), _to.bind("load", "pause"))
			_row(I18n.t("OPTIONS"), _to.bind("options", "pause"))
			if game.story_clock!=null: _row(game.story_clock.help_label(),func(): game.story_clock.open_help(game))
			_row(I18n.t("QUIT TO TITLE"), _quit_to_title)
		"hud_context":
			_row(I18n.t("BACK"),_context_return)
		"options":
			_row(I18n.t("READING"),_open.bind("options_reading"))
			_row(I18n.t("SOUND"),_open.bind("options_sound"))
			_row(I18n.t("EFFECTS"),_open.bind("options_effects"))
			_row(I18n.t("DISPLAY"),_open.bind("options_display"))
			_row(I18n.t("LANGUAGE"),_open.bind("options_language"))
			if game.telemetry!=null: _row(game.telemetry.choice_label(),game.telemetry.open_choice)
			if not game.web and not game.demo and game.presentation.get("privacy_url", "") != "":
				_row(I18n.t("PRIVACY POLICY"),func(): open_url.call(game.presentation["privacy_url"]))
			_row(I18n.t("BACK"), _go_back)
		"options_reading":
			_row(I18n.t("TEXT COLOUR: %s") % (I18n.t("HIGH CONTRAST") if game.settings["text_colour"]=="high_contrast" else I18n.t("SPEAKER")), _next_text_colour)
			_row(I18n.t("TEXT SIZE: %s") % (I18n.t("LARGE") if game.settings["text_size"]=="large" else I18n.t("STANDARD")), _next_text_size)
			if game.manual_dialogue_available():
				_row(I18n.t("DIALOGUE: %s") % (I18n.t("TAP TO CONTINUE") if game.settings["dialogue_advance"]=="manual" else I18n.t("AUTOMATIC")), _next_dialogue_mode)
			_row(I18n.t("TEXT SPEED: %s") % _speed_name(), _next_speed)
			_row(I18n.t("TEXT BOXES: %s") % _on_off(game.settings["text_boxes"]), func(): game.change_setting("text_boxes", not game.settings["text_boxes"]))
			_row(I18n.t("SPEAKER NAMES: %s") % _on_off(game.settings["speaker_names"]), func(): game.change_setting("speaker_names", not game.settings["speaker_names"]))
			_row(I18n.t("BACK"), _open.bind("options"))
		"options_sound":
			_row(I18n.t("MUSIC: %s") % _volume_name("music_volume"),_open.bind("volume_music"))
			_row(I18n.t("SOUND EFFECTS: %s") % _volume_name("effects_volume"),_open.bind("volume_effects"))
			_row(I18n.t("BACK"), _open.bind("options"))
		"volume_music", "volume_effects":
			var key:=_volume_key()
			_row(I18n.t("QUIETER"),_adjust_volume.bind(key,-10),game.settings[key]>0)
			_row(I18n.t("LOUDER"),_adjust_volume.bind(key,10),game.settings[key]<100)
			_row(I18n.t("MUTE"),game.change_setting.bind(key,0))
			_row(I18n.t("FULL VOLUME"),game.change_setting.bind(key,100))
			_row(I18n.t("BACK"),_open.bind("options_sound"))
		"options_effects":
			_row(I18n.t("REDUCED EFFECTS: %s") % _on_off(game.reduced_effects()),func(): game.change_setting("reduced_effects",not game.reduced_effects()))
			_row(I18n.t("BACK"),_open.bind("options"))
		"options_display":
			_row(I18n.t("CRT LINES: %s") % _on_off(game.crt), func(): game.change_setting("crt", not game.crt))
			_row(I18n.t("DISPLAY: %s") % (I18n.t("DEFAULT") if game.display_mode == "" else I18n.t(_display_name())), _next_display)
			_row(I18n.t("BACK"), _open.bind("options"))
		"options_language":
			_row(I18n.t("LANGUAGE: %s") % _language_name(), _next_language)
			_row(I18n.t("BACK"), _open.bind("options"))
		"save":
			for e in game.saves.list():
				if e["slot"] != "auto" and e.get("writable",true):
					_row(_slot_text(e), _save.bind(e["slot"]))
			_row(I18n.t("BACK"), _open.bind("pause"))
		"load":
			for e in game.saves.list():
				if e["slot"] != "auto" or e["exists"]:
					_row(_slot_text(e), _load.bind(e["slot"]), e["exists"])
			_row(I18n.t("BACK"), _go_back)
		"dev":
			_dev_rows()
		"demo_end":
			_row(I18n.t("BACK TO TITLE"), show_title)
		"prologue_end":
			if game.presentation.get("website_url", "") != "":
				_row(I18n.t(game.presentation.get("website_label", I18n.mark("WEBSITE"))), func(): open_url.call(game.presentation["website_url"]))
			_row(I18n.t("BACK TO TITLE"), show_title)
		"storage":
			for entry in _storage_rows: _row(entry[0],entry[1])


func _to(which: String, back: String) -> void:
	_back = back
	_open(which)


func _go_back() -> void:
	if is_instance_valid(_storage_panel) and _back!="title":
		_back_from_storage(); return
	_open(_back)


func _escape() -> void:
	match page:
		"hud_context":
			_context_return()
		"custom":
			custom_panel.back()
		"pause", "dev":
			close()
		"options", "load":
			_go_back()
		"options_reading", "options_sound", "options_effects", "options_display", "options_language":
			_open("options")
		"volume_music", "volume_effects":
			_open("options_sound")
		"save":
			_open("pause")
		"storage":
			if _storage_back.is_valid(): _storage_back.call()


# ------------------------------------------------------------------ actions

# On the web the page itself goes to url: a new window opened from the game's
# frame loop (OS.shell_open) is a popup Safari may block, and on a phone on
# its side the page shows no other way back to the website. Elsewhere it opens
# in the browser. (JavaScriptBridge is looked up when it's needed, so no
# other platform's script has to know the name.)
func _open_url(url: String) -> void:
	if game.web and Engine.has_singleton("JavaScriptBridge"):
		Engine.get_singleton("JavaScriptBridge").eval("window.location.assign(%s)" % JSON.stringify(url))
	else:
		OS.shell_open(url)


func _new_game() -> void:
	if game.entry_flow!=null:
		game.entry_flow.new_game()
		return
	if StartPoints.apply(game, "new_game", {}):
		close()
	elif game.saves.is_versioned():
		_storage_failure("new","auto")


# A save that falls back to a new game (it's from a build without its room,
# say) is said so over the fresh game; it never becomes the autosave.
func _load(slot: String) -> void:
	if game.entry_flow!=null:
		game.entry_flow.load_slot(slot)
		return
	if not game.load_game(slot):
		if game.saves.is_versioned():
			_storage_failure("load",slot)
			return
		status = I18n.t("THAT SAVE WON'T LOAD.")
		return
	close()
	if game.state.loaded_with_fallback:
		notice = I18n.t("THAT SAVE IS FROM ANOTHER VERSION. STARTING FRESH.")
		_notice_left = NOTICE_TIME


func _quit_to_title() -> void:
	var needed: bool=game.autosave and game._owns_autosave
	var saved: bool=game.autosave_now()
	if game.saves.is_versioned() and needed and not saved:
		_storage_failure("quit","auto")
		return
	show_title()


func _save(slot: String) -> void:
	if game.save_game(slot):
		_open("pause")
		status = I18n.t("SAVED IN SLOT %s.") % slot
	else:
		if game.saves.is_versioned(): _storage_failure("save",slot)
		else: status = I18n.t("COULDN'T SAVE.")

func _on_save_problem(kind: String, slot: String) -> void:
	if not is_instance_valid(game) or not game.saves.is_versioned(): return
	if game.saves.is_waiting() and kind=="auto": return
	if game.saves.has_pending_commit():
		if page!="storage": _storage_failure(kind,slot)
	elif kind=="transaction":
		if page!="storage": _storage_failure("transaction",slot)

func _on_save_finished(result: Dictionary) -> void:
	var action: String=_waiting_action if _waiting_action!="" else result["kind"]
	_waiting_action=""
	if result["status"]!="ok":
		if action!="auto": _storage_failure(action,result["slot"])
		return
	match action:
		"quit": show_title()
		"quit_app": quit_app.call()
		"save":
			_open("pause")
			status=I18n.t("SAVED IN SLOT %s.") % result["slot"]
		"load","recover","transaction": close()

func _storage_dialog(body: String, choices: Array, back_action:=Callable()) -> void:
	storage_body=body
	_storage_rows=choices
	_storage_back=back_action
	var suspended: Node2D=custom_panel if is_instance_valid(custom_panel) else _storage_panel
	custom_panel=null
	_storage_panel=null
	if is_instance_valid(suspended):
		suspended.hide()
		suspended.process_mode=PROCESS_MODE_DISABLED
	close()
	_storage_panel=suspended
	_open("storage")

func _back_from_storage() -> void:
	if is_instance_valid(_storage_panel):
		var panel:=_storage_panel
		_storage_panel=null
		close()
		custom_panel=panel
		page="custom"
		game.menu_open=true
		panel.show()
		panel.process_mode=PROCESS_MODE_INHERIT
		_sync_title_music()
	else:
		_open(_storage_origin)

func _storage_failure(action: String, slot: String) -> void:
	if page!="storage": _storage_origin=page if page in ["title","save","load","pause","custom"] else "pause"
	var result: Dictionary=game.saves.last_result
	var code: String=result.get("status","write_failed")
	if code=="conversion_failed" and result.get("cause")=="busy": code="busy"
	var body:=I18n.t("COULDN'T SAVE. YOUR PREVIOUS CHECKPOINT HAS BEEN KEPT.")
	var back_action: Callable=_back_from_storage
	var retry: Callable=_load.bind(slot) if action=="load" else _save.bind(slot)
	if action=="new": retry=_new_game
	elif action=="quit": retry=_quit_to_title
	elif action=="quit_app": retry=request_quit
	elif action=="auto": retry=_retry_auto
	elif action=="transaction":
		retry=_retry_transaction
		if game.foreground.handles_retry():
			back_action=func():
				game.foreground.cancel_retry()
				_back_from_storage()
	if game.saves.is_waiting():
		_storage_dialog(I18n.t("LOADING...") if action in ["load","recover"] else I18n.t("SAVING..."),[])
		_waiting_action=action
		return
	if game.saves.has_pending_commit():
		body=I18n.t("THE SAVE HAS NOT BEEN CONFIRMED. RETRY TO FINISH THIS CHECKPOINT.")
		var after: Callable=show_title if action=="quit" else quit_app if action=="quit_app" else close
		_storage_dialog(body,[[I18n.t("RETRY"),_retry_pending.bind(after)],[I18n.t("QUIT WITHOUT SAVING"),quit_app]])
		return
	match code:
		"newer": body=I18n.t("THIS SAVE NEEDS A NEWER VERSION. IT HAS BEEN KEPT.")
		"wrong_scope": body=I18n.t("THIS SAVE BELONGS TO ANOTHER GAME BUILD. IT HAS BEEN KEPT.")
		"unreadable","identity_unreadable": body=I18n.t("THIS SAVE COULDN'T BE READ. IT HAS BEEN KEPT.")
		"unsupported": body=I18n.t("THIS SAVE CAN'T BE LOADED BY THIS VERSION. IT HAS BEEN KEPT.")
		"conversion_failed": body=I18n.t("COULDN'T UPDATE THIS SAVE. THE ORIGINAL IS UNCHANGED.")
		"busy": body=I18n.t("ANOTHER GAME WINDOW IS USING THIS SAVE. CLOSE IT, THEN RETRY.")
		"stale": body=I18n.t("THIS SAVE CHANGED IN ANOTHER WINDOW. LOAD IT BEFORE SAVING.")
		"unavailable": body=I18n.t("STORAGE IS UNAVAILABLE. PLEASE RETRY.")
		"empty": body=I18n.t("THAT SAVE IS NO LONGER AVAILABLE.")
	var choices:=[]
	if action=="load" and result.has("previous") and code in ["unreadable","unsupported"]:
		var labels: Dictionary=game._checkpoint_labels(result["previous"]["envelope"]["state"])
		var product_text: String=game.entry_flow.recovery_text(result["previous"]["envelope"]["state"]) if game.entry_flow!=null else ""
		body+="\n\n"+(product_text if product_text!="" else I18n.t("PREVIOUS SAVE: %s - %s") % [I18n.t(labels.get("room_name","")),I18n.t(labels.get("crew_name",""))])
		if game.saves.has_method("recovery_progress"):
			body+="\n"+recovery_progress_text(game.saves.recovery_progress(result["previous"]["envelope"]["state"]))
		choices.append([I18n.t("USE PREVIOUS SAVE"),_recover.bind(slot,result["token"])])
	elif code=="stale":
		choices.append([I18n.t("LOAD"),_to.bind("load","pause" if game.state!=null else "title")])
	elif code in ["write_failed","conversion_failed","busy","unavailable"]:
		choices.append([I18n.t("RETRY"),retry])
	if action in ["quit","quit_app"]:
		choices.append([I18n.t("KEEP PLAYING"),close])
		choices.append([I18n.t("QUIT WITHOUT SAVING"),quit_app if action=="quit_app" else show_title])
		back_action=close
	else:
		choices.append([I18n.t("BACK"),back_action])
		if code=="stale" and game.state!=null: choices.append([I18n.t("QUIT WITHOUT SAVING"),show_title])
	_storage_dialog(body,choices,back_action)

func _recover(slot: String, token: String) -> void:
	if game.recover_game(slot,token): close()
	else: _storage_failure("load",slot)

func _retry_pending(after:=Callable()) -> void:
	if game.retry_pending_save():
		if after.is_valid(): after.call()
		else: close()
	else:
		_storage_dialog(I18n.t("THE SAVE HAS NOT BEEN CONFIRMED. RETRY TO FINISH THIS CHECKPOINT."),
			[[I18n.t("RETRY"),_retry_pending.bind(after)],[I18n.t("QUIT WITHOUT SAVING"),quit_app]])

func _retry_auto() -> void:
	if game.autosave_now(): close()
	else: _storage_failure("auto","auto")

func _retry_transaction() -> void:
	if game.retry_transaction(): close()
	else: _storage_failure("transaction","auto")

func _storage_lines() -> Array:
	var lines:=[]
	for paragraph in storage_body.split("\n"):
		if paragraph=="": lines.append("")
		else: lines.append_array(PixelFont.wrap(paragraph,int((game.view_w()-24)/PixelFont.ADVANCE)))
	return lines


# A save's names are kept in English, so they show in whatever language is on.
func _slot_text(e: Dictionary) -> String:
	if game.entry_flow!=null:
		var text: String=game.entry_flow.slot_text(e)
		if text!="": return text
	if e["exists"] and e.get("status","ok") not in ["ok","legacy"]:
		return "%s  %s" % [I18n.t("AUTO") if e["slot"]=="auto" else e["slot"],I18n.t("SAVE NEEDS ATTENTION")]
	var what: String = "%s - %s" % [I18n.t(e["room_name"]), I18n.t(e["crew_name"])] if e["exists"] else I18n.t("EMPTY")
	return "%s  %s" % [I18n.t("AUTO") if e["slot"] == "auto" else e["slot"], what]


func _on_off(on: bool) -> String:
	return I18n.t("ON") if on else I18n.t("OFF")


func _volume_key() -> String:
	return "music_volume" if page=="volume_music" else "effects_volume"


func _volume_name(key: String) -> String:
	return I18n.t("MUTE") if game.settings[key]==0 else I18n.t("%s%%") % str(game.settings[key])


func _adjust_volume(key: String, step: int) -> void:
	game.change_setting(key,clampi(game.settings[key]+step,0,100))


func _speed_name() -> String:
	match game.settings["text_speed"]:
		"slow":
			return I18n.t("SLOW")
		"fast":
			return I18n.t("FAST")
	return I18n.t("NORMAL")


func _next_text_colour() -> void:
	game.change_setting("text_colour","speaker" if game.settings["text_colour"]=="high_contrast" else "high_contrast")


func _next_text_size() -> void:
	game.change_setting("text_size","standard" if game.settings["text_size"]=="large" else "large")


func _next_dialogue_mode() -> void:
	game.change_setting("dialogue_advance","automatic" if game.settings["dialogue_advance"]=="manual" else "manual")


func _next_speed() -> void:
	var i := SPEEDS.find(game.settings["text_speed"])
	game.change_setting("text_speed", SPEEDS[(i + 1) % SPEEDS.size()])


# In English, as game.display_choices() names them.
func _display_name() -> String:
	return "DEFAULT" if game.display_mode == "" else game.display_modes[game.display_mode]["name"]


# Steps through game.display_choices(): DEFAULT and the modes the player owns.
func _next_display() -> void:
	var names: Array = game.display_choices()
	var next: String = names[(names.find(_display_name()) + 1) % names.size()]
	var id := ""
	for mode in game.display_modes:
		if game.display_modes[mode]["name"] == next:
			id = mode
	game.change_setting("display_mode", id)


func _language_name() -> String:
	for l in languages():
		if l[0] == game.settings["locale"]:
			return l[1]
	return languages()[0][1]


func _next_language() -> void:
	var list := languages()
	var i: int = list.map(func(l): return l[0]).find(game.settings["locale"])
	var locale: String = list[(i + 1) % list.size()][0]
	game.change_setting("locale", locale)
	TranslationServer.set_locale(locale)


# Every start point, a page at a time if they don't all fit, then BACK. The
# start points are a developer's names, never translated.
func _dev_rows() -> void:
	var names: Array = StartPoints.all(game.rooms, game.world_scripts).keys()
	var fit := (STATUS_Y - 2 - ROWS_Y) / ROW - 1  # rows for start points, less BACK
	var more := names.size() > fit
	if more:
		fit -= 1  # and less MORE
		names = names.slice(_first, _first + fit)
	for n in names:
		_row(n.to_upper().replace("_", " "), _start.bind(n))  # the font has no lower case or _
	if more:
		_row(I18n.t("MORE"), _more.bind(fit))
	_row(I18n.t("BACK"), close)


func _more(step: int) -> void:
	_first += step
	if _first >= StartPoints.all(game.rooms, game.world_scripts).size():
		_first = 0


func _start(start: String) -> void:
	if not game.can_load():
		status = I18n.t("NOT NOW.")
		return
	close()
	StartPoints.apply(game, start, {})


func _show_context(origin: String) -> void:
	_context_back=origin
	_open("hud_context")


func _context_return() -> void:
	if _context_back=="": close()
	else: _open(_context_back)


func _open_hud_context() -> void:
	if page!="" or not game.can_save() or game.foreground_active() or game.in_cutscene: return
	# Snapshot before the normal pause path clears hover/cancels a pending use.
	open("pause")
	if page=="pause": _show_context("")


func _on_hud_tapped(what: String) -> void:
	if what == "menu":
		if game.consume_reading_input(): open("pause")
	elif what=="context" or (what=="label" and game.hud.needs_context()):
		if game.consume_reading_input(): _open_hud_context()
	elif what == "label" and is_debug:
		var now: float = game.clock
		_taps.append(now)
		_taps = _taps.filter(func(t): return now - t < TAP_WINDOW)
		if _taps.size() >= 3:
			if game.consume_reading_input(): open("dev")


# ------------------------------------------------------------------ input

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_pressed(Time.get_ticks_msec())
	elif what==NOTIFICATION_WM_CLOSE_REQUEST and game!=null and game.saves.is_versioned():
		request_quit()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_title_music_held=true
		_title_music.stream_paused=true
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		_title_music_held=false
		_title_music.stream_paused=false

func request_quit() -> void:
	if game.state==null:
		quit_app.call(); return
	if game.saves.has_pending_commit():
		_storage_failure("quit_app","auto"); return
	if not game.can_save():
		_quit_requested=true
		notice=I18n.t("FINISH THIS ACTION TO SAVE BEFORE QUITTING.")
		_notice_left=NOTICE_TIME
		return
	_quit_requested=false
	if game.autosave and game._owns_autosave and not game.autosave_now():
		_storage_failure("quit_app","auto")
	else:
		quit_app.call()


# A back notification at now (ms): acted on unless it's the same press as the last.
func back_pressed(now: int) -> void:
	if now - _last_back < BACK_REPEAT:
		return
	if not game.consume_reading_input(): return
	_last_back = now
	back()


# Android's back: see the top of this file.
func back() -> void:
	match page:
		"":
			if game.can_skip():
				game.skip_cutscene()
			elif not game.in_cutscene:
				open("pause")  # only if the player has control
		"title":
			if not game.web:
				quit_app.call()
		"demo_end", "prologue_end":
			show_title()
		_:
			_escape()


func _unhandled_input(event: InputEvent) -> void:
	if game.reading_input_consumed():
		get_viewport().set_input_as_handled(); return
	if page == "":
		if event is InputEventKey and event.pressed and not event.echo:
			# Esc in a cutscene is left for the game: it skips the scene.
			if event.keycode == KEY_ESCAPE and not game.in_cutscene and game.can_save():
				game.consume_reading_input()
				open("pause")
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_F1 and is_debug and game.can_save():
				game.consume_reading_input()
				open("dev")
				get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()  # a page takes every input
	if game.reading_input_consumed(): return
	if event is InputEventKey and event.pressed and not event.echo and page=="custom" and custom_panel.has_method("key"):
		if custom_panel.key(event.keycode): return
	if event is InputEventKey and event.pressed and not event.echo and page!="custom":
		if reader.key(event.keycode): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap(event.position)
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and not OS.has_feature("mobile"):
			pointer = event.position.floor()
			reader.focus=-1
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_escape()


# ------------------------------------------------------------------ drawing

func world_notice() -> String:
	if page!="": return ""
	if game.interaction_policy!=null:
		if game.interaction_policy.has_method("warning_active") and game.interaction_policy.warning_active(): return ""
		if game.interaction_policy.has_method("speech_reserved") and not game.interaction_policy.speech_reserved().is_empty(): return ""
	return notice if notice!="" else I18n.t("SAVE NOT UPDATED") if game.save_dirty and game.autosave and not game.saves.is_waiting() else ""

func speech_reserved() -> Array:
	var arranged:=world_notice_layout()
	return [] if arranged.is_empty() else [arranged["reserved"]]

var _warp_clock := 0.0

func _process(delta: float) -> void:
	if _quit_requested and game.can_save(): request_quit()
	if page == "title": _warp_clock += delta
	if notice != "" and not world_notice_layout().is_empty():
		_notice_left -= delta
		if _notice_left <= 0.0:
			notice = ""
	queue_redraw()


func _draw() -> void:
	if page == "custom":
		return
	if page == "":
		_draw_world_notice(self)
		return
	var w: int = game.view_w()
	reader.layout()
	if reader.active():
		reader.draw(self); return
	draw_rect(Rect2(0, 0, w, Feel.VIEW_H), Color.BLACK)
	if page == "title":
		if game.presentation.get("title_stars",false):
			var clear := [[20, 62], [TITLE_ROWS_Y - 4, TITLE_ROWS_Y + 4 * ROW + 4]]
			if title_stars_move():
				for star in warp_stars(w, _warp_clock, clear): draw_rect(Rect2(star[0], Vector2i(star[1], star[1])), star[2])
			else:
				_stars(w, clear)
		var titles := _title_texts()
		for i in titles.size(): _big(titles[i], 24+i*20 if titles.size()>1 else 44, w)
	elif page in ["demo_end", "prologue_end"]:
		var texts := demo_end_texts() if page == "demo_end" else prologue_end_texts()
		if game.presentation.get("title_stars",false): _stars(w, [[END_TITLE_Y - 4, END_NOTE_Y + 11], [END_ROWS_Y - 4, END_ROWS_Y + _rows.size() * ROW + 4]])
		_big(texts[0], END_TITLE_Y, w)
		_centred(texts[1], END_NOTE_Y, w, C_WHITE)
	else:
		_big(_header(), HEADER_Y, w)
		if page in ["volume_music","volume_effects"]: _centred(I18n.t("VOLUME: %s") % _volume_name(_volume_key()),42,w,C_WHITE)
		if page=="pause" and game.story_clock!=null: _centred(game.story_clock.header(game.state),40,w,C_YELLOW)
		if page=="storage":
			var lines:=_storage_lines()
			for i in mini(lines.size(),9):
				PixelFont.draw_text(self,lines[i],Vector2(12,48+i*PixelFont.LINE),C_WHITE,false)
	var lit := hovered_row()
	if lit<0: lit=reader.focus
	for i in _rows.size():
		var color := C_MGREY
		if _rows[i]["on"]:
			color = C_WHITE if i == lit else C_LGREY
		_centred(_rows[i]["text"], int(row_rect(i).position.y) + (ROW - 7) / 2, w, color)
		if i==reader.focus and _rows[i]["on"]:
			draw_rect(Rect2(4,row_rect(i).position.y+2,2,ROW-4),C_WHITE)
	if status != "":
		_centred(status, STATUS_Y, w, C_BLUE)


func _header() -> String:
	match page:
		"pause":
			return I18n.t("PAUSED")
		"options":
			return I18n.t("OPTIONS")
		"hud_context": return I18n.t("CONTEXT")
		"options_reading": return I18n.t("READING")
		"options_sound": return I18n.t("SOUND")
		"options_effects": return I18n.t("EFFECTS")
		"options_display": return I18n.t("DISPLAY")
		"options_language": return I18n.t("LANGUAGE")
		"volume_music": return I18n.t("MUSIC")
		"volume_effects": return I18n.t("SOUND EFFECTS")
		"save":
			return I18n.t("SAVE")
		"load":
			return I18n.t("LOAD")
		"storage":
			return I18n.t("SAVE STATUS")
	return I18n.t("START POINTS")


func _centred(text: String, y: int, w: int, color: Color) -> void:
	var tw := text.length() * PixelFont.ADVANCE - 1
	PixelFont.draw_text(self, text, Vector2((w - tw) / 2, y), color, false)


# A heading at twice the size, in yellow; at the normal size, in the middle
# of the same band, if it wouldn't fit (a long translation).
func _big(text: String, y: int, w: int) -> void:
	var tw := text.length() * PixelFont.ADVANCE - 1
	if 2 * tw > w - 4:
		_centred(text, y + 4, w, C_YELLOW)
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(2, 2))
	PixelFont.draw_text(self, text, Vector2((w / 2 - tw) / 2, y / 2), C_YELLOW, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A fixed scatter of stars, clear of the bands [top, bottom] (exclusive) the
# texts are in.
func title_stars_move() -> bool:
	return game.presentation.get("title_stars", false) and game.presentation.get("title_starfield", "") == "warp" \
		and not game.reduced_effects()

# The fly-through stars at a moment: [position, size, colour] each, on screen and outside the clear
# bands. Each star keeps a direction from the centre and comes closer; nearer is brighter and bigger.
func warp_stars(w: int, seconds: float, clear: Array) -> Array:
	var out := []
	var t := floorf(seconds * WARP_HZ) / WARP_HZ
	var centre := Vector2(w / 2.0, Feel.VIEW_H / 2.0)
	var n := 11
	for i in WARP_STARS:
		n = (n * 1103515245 + 12345) & 0x7fffffff
		var dx := float(n % 2001) / 1000.0 - 1.0
		n = (n * 1103515245 + 12345) & 0x7fffffff
		var dy := float(n % 2001) / 1000.0 - 1.0
		n = (n * 1103515245 + 12345) & 0x7fffffff
		var phase := float(n % 1000) / 1000.0
		if absf(dx) < 0.08 and absf(dy) < 0.08: continue   # dead ahead: it would never move
		var z := 1.0 - fposmod(phase + t / WARP_SECONDS, 1.0) * 0.95   # 1 far .. 0.05 passing
		var at := centre + Vector2(dx * w / 2.0, dy * Feel.VIEW_H / 2.0) * (0.12 / z)
		var x := int(at.x)
		var y := int(at.y)
		if x < 0 or y < 0 or x >= w or y >= Feel.VIEW_H: continue
		if clear.any(func(band): return y > band[0] and y < band[1]): continue
		out.append([Vector2i(x, y), 2 if z < 0.2 else 1, C_WHITE if z < 0.35 else (C_LGREY if z < 0.7 else C_MGREY)])
	return out

func _stars(w: int, clear: Array) -> void:
	var n := 7
	for i in 60:
		n = (n * 1103515245 + 12345) & 0x7fffffff
		var x := n % w
		n = (n * 1103515245 + 12345) & 0x7fffffff
		var y := n % Feel.VIEW_H
		if clear.any(func(band): return y > band[0] and y < band[1]):
			continue
		draw_rect(Rect2(x, y, 1, 1), C_WHITE if i % 4 == 0 else C_MGREY)


func _draw_world_notice(ci) -> void:
	if Ink.route(ci,"world_notice",_draw_world_notice): return
	var arranged:=world_notice_layout()
	if arranged.is_empty(): return
	if Ink.active(ci): ci.draw_rect(arranged["bounds"],Color.BLACK)
	PixelFont.draw_lines(ci,arranged["placed"],C_WHITE,true,arranged["scale"])

func world_notice_layout() -> Dictionary:
	var message:=world_notice()
	if message=="": return {}
	var scale: int=game.speech.text_scale
	var columns:=mini(40,maxi(1,floori((game.view_w()-8)/float(PixelFont.ADVANCE*scale))))
	var lines:=PixelFont.wrap(message,columns); var placed:=[]; var bounds:=Rect2()
	for i in lines.size():
		var tw:=PixelFont.text_rect(lines[i],Vector2.ZERO,scale).size.x
		var at:=Vector2((game.view_w()-tw)/2,8+i*PixelFont.LINE*scale)
		placed.append([lines[i],at])
		var rect:=PixelFont.text_rect(lines[i],at,scale).grow(2)
		bounds=rect if i==0 else bounds.merge(rect)
	var reserved:=Rect2(0,0,game.view_w(),11+7*scale+(lines.size()-1)*PixelFont.LINE*scale)
	if not game.speech.can_share_notice(game.room,game.view_w(),[reserved]): return {}
	return {"placed":placed,"scale":scale,"bounds":bounds,"reserved":reserved}


func _texts(key: String, fallback: Array) -> Array:
	return game.presentation.get(key, fallback).map(func(text): return I18n.t(text))

func _title_texts() -> Array:
	return _texts("title", [str(ProjectSettings.get_setting("application/config/name", "ADVENTURE"))])
