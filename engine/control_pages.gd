extends RefCounted
const Ink=preload("res://engine/reading_ink.gd")
# A presentation adapter for product-owned panels. Focus is ephemeral;
# saved scenes may commit source positions through reading_move_page().
# Only the panel's existing story actions can commit gameplay progress.
const Sheet=preload("res://engine/reading_sheet.gd")
const PixelFont=preload("res://engine/pixel_font.gd")
const I18n=preload("res://engine/i18n.gd")
var panel
var page:=0
var focus:=""
var keyboard:=false
var _layout:={}
var _content:=[]
var _identity:=[]
var _geometry:=[]
var _position:={}
var _shown_page:=-1
var _reflow_frame:=-1
var _resume:={}

func _init(owner) -> void: panel=owner

static func fits(text: String, width: float, lines:=1) -> bool:
	if text.contains("\n"): return false # the original compact drawers have no newline layout
	if lines==1: return PixelFont.text_rect(text,Vector2.ZERO).size.x<=width
	return PixelFont.wrap(text,maxi(1,floori(width/float(PixelFont.ADVANCE)))).size()<=lines

func active() -> bool:
	return Ink.preferred(panel.game) or keyboard or panel.game.speech.text_scale==2 or not panel.compact_fits()

func has_diagram() -> bool:
	return panel.has_method("reading_diagram") and (not panel.has_method("reading_has_diagram") or panel.reading_has_diagram())

func close_label() -> String:
	return panel.reading_close_label() if panel.has_method("reading_close_label") else I18n.t("CLOSE")

func back() -> void:
	if panel.has_method("reading_back"): panel.reading_back()
	else: panel.back()

func view_state() -> Dictionary:
	layout()
	return {"anchor":reading_position().duplicate(true),"locale":TranslationServer.get_locale(),"keyboard":keyboard}

func restore(view: Dictionary) -> void:
	_resume=view.duplicate(true)
	keyboard=view.get("keyboard",false)

func reading_position() -> Dictionary:
	if not _layout.is_empty() and page!=_shown_page:
		_position={"diagram":true} if _layout["pages"][page].has("diagram") else Sheet.anchor(_layout,page)
		_shown_page=page
	return _position

func layout() -> Dictionary:
	var content: Array=[panel.reading_sections(),TranslationServer.get_locale(),has_diagram(),close_label()]
	var identity: Array=[panel.reading_identity(),content[1]] if panel.has_method("reading_identity") else content
	var geometry: Array=[panel.game.view_w(),panel.game.speech.text_scale,Ink.preferred(panel.game)]
	if content!=_content or geometry!=_geometry or not _resume.is_empty():
		var position:=reading_position()
		var old:=not _layout.is_empty()
		var same:=identity==_identity
		_layout=panel.reading_layout(content[0],geometry[0],geometry[1],content[3]) if panel.has_method("reading_layout") else Sheet.make(content[0],geometry[0],geometry[1],content[3])
		if _layout["status"]!="ok": push_error("Puzzle controls leave no content space")
		if content[2]: _layout["pages"].append({"rows":[],"blocks":[],"diagram":true})
		if not _resume.is_empty():
			if _resume.get("locale","")==content[1]: position=_resume.get("anchor",{}); same=true; old=true
			_resume={}
		if old:
			page=(_layout["pages"].size()-1 if position.has("diagram") and content[2] else Sheet.page_for(_layout,position)) if same else 0
			_reflow_frame=Engine.get_process_frames()
		_position=position if old and same else Sheet.anchor(_layout,page)
		_shown_page=page; focus=""; _content=content; _identity=identity; _geometry=geometry
	page=clampi(page,0,_layout["pages"].size()-1)
	reading_position()
	return _layout

func ready_input() -> bool:
	layout()
	return Engine.get_process_frames()!=_reflow_frame and panel.game.consume_reading_input()

func intercept(point: Vector2) -> bool:
	if active(): tap(point); return true
	# Compact artwork uses its original hit areas, with the same one-input
	# and stale-coordinate guards as the paginated alternative.
	return not ready_input()

func draw_if_needed(ci) -> bool:
	layout()
	if not active(): return false
	draw(ci); return true

func tap(point: Vector2) -> void:
	var result:=Sheet.hit(layout(),page,point)
	if result.is_empty() or not ready_input(): return
	focus=""
	if result.has("back"): back(); return
	if result.has("action"): panel.reading_activate(result["action"])
	else: move_page(page+result.get("page",0))
	panel.queue_redraw()

func key(code: int) -> bool:
	if code not in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_PAGEUP,KEY_PAGEDOWN,KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_ESCAPE]: return false
	if not ready_input(): return true
	if code==KEY_ESCAPE: back(); return true
	if not active():
		# The first keyboard press reveals the navigable controls, never an action.
		keyboard=true; panel.queue_redraw(); return true
	if code in [KEY_LEFT,KEY_PAGEUP,KEY_RIGHT,KEY_PAGEDOWN]:
		move_page(page+(-1 if code in [KEY_LEFT,KEY_PAGEUP] else 1))
	else:
		var actions: Array=_layout["pages"][page]["blocks"].filter(func(b): return b["last"] and b["enabled"]).map(func(b): return b["id"])
		var body_actions:=actions.size()
		actions.append("close")
		if code in [KEY_UP,KEY_DOWN]:
			var at:=actions.find(focus)
			focus=actions[(actions.size()-1 if code==KEY_UP else 0) if at<0 else posmod(at+(-1 if code==KEY_UP else 1),actions.size())]
		elif focus=="" and body_actions==0 and page+1<_layout["pages"].size(): move_page(page+1)
		elif not focus in actions: focus=actions[0]
		elif focus=="close": back(); return true
		else:
			var action:=focus; focus=""; panel.reading_activate(action)
	panel.queue_redraw(); return true

func draw(ci) -> void:
	if Ink.route(ci,"control_page",draw): return
	var arranged:=layout()
	if panel.has_method("reading_draw"): panel.reading_draw(ci,arranged,page,focus)
	else: Sheet.draw(ci,arranged,page,Callable(),focus)
	if arranged["pages"][page].has("diagram"): panel.reading_diagram(ci,arranged["bounds"])
	if focus=="close": ci.draw_rect(arranged["nav"][1]["rect"],Sheet.PAPER,false)

# Saved scenes opt into the same source navigation with their own existing
# commit method. An unacknowledged move leaves the previous page authoritative.
func move_page(next_page: int) -> bool:
	var arranged:=layout()
	next_page=clampi(next_page,0,arranged["pages"].size()-1)
	if next_page==page: return false
	if panel.has_method("reading_move_page"):
		var position: Dictionary={"diagram":true} if arranged["pages"][next_page].has("diagram") else Sheet.anchor(arranged,next_page)
		if not panel.reading_move_page(position): return false
		restore({"anchor":position,"locale":TranslationServer.get_locale(),"keyboard":keyboard})
		layout()
	else: page=next_page
	focus=""; panel.queue_redraw()
	return true
