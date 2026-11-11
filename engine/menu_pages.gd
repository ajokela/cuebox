extends RefCounted
const Ink=preload("res://engine/reading_ink.gd")
# Presentation state for ordinary menus. Row identities continue to select
# the menu's original callbacks; neither reading pages nor focus are saves.
const Sheet=preload("res://engine/reading_sheet.gd")
var menus
var page:=0
var focus:=-1
var _layout:={}
var _content:=[]
var _geometry:=[]
var _position:={}
var _shown_page:=-1
var _reflow_frame:=-1
var _back_row:=-1

func _init(owner) -> void: menus=owner

func reset() -> void:
	page=0; focus=-1; _layout={}; _content=[]; _geometry=[]
	_position={}; _shown_page=-1; _back_row=-1; _reflow_frame=-1

func reading_position() -> Dictionary:
	if not _layout.is_empty() and page!=_shown_page:
		_position=Sheet.anchor(_layout,page); _shown_page=page
	return _position

func layout() -> Dictionary:
	var sections: Array=menus.reading_sections()
	var back_row: int=menus.reading_back_row()
	var content: Array=[menus.page,sections,back_row,TranslationServer.get_locale()]
	var geometry: Array=[menus.game.view_w(),menus.game.speech.text_scale,Ink.preferred(menus.game)]
	if content!=_content or geometry!=_geometry:
		var position:=reading_position()
		var old:=not _layout.is_empty()
		var same:=content==_content
		var close: String=menus._rows[back_row]["text"] if back_row>=0 else ""
		_layout=Sheet.make(sections,geometry[0],geometry[1],close)
		if _layout["status"]!="ok": push_error("Menu controls leave no content space")
		if old:
			page=Sheet.page_for(_layout,position) if same else 0
			_reflow_frame=Engine.get_process_frames()
		_position=position if old and same else Sheet.anchor(_layout,page)
		_shown_page=page; focus=-1; menus.pointer=null
		_content=content; _geometry=geometry; _back_row=back_row
	page=clampi(page,0,_layout["pages"].size()-1)
	reading_position()
	return _layout

func active() -> bool:
	return menus.page not in ["","custom"] and (Ink.preferred(menus.game) or not menus.compact_fits())

func ready_input() -> bool:
	layout()
	return Engine.get_process_frames()!=_reflow_frame and menus.game.consume_reading_input()

func row_rect(index: int) -> Rect2:
	var arranged:=layout()
	if index==_back_row: return arranged["nav"][1]["rect"]
	for block in arranged["pages"][page]["blocks"]:
		if block["id"]==str(index) and block["last"]: return block["rect"]
	return Rect2()

func tap(point: Vector2) -> void:
	if active():
		var result:=Sheet.hit(layout(),page,point)
		if result.is_empty() or not ready_input(): return
		focus=-1
		if result.has("action"): menus._activate(int(result["action"]))
		elif result.has("back") and _back_row>=0: menus._activate(_back_row)
		else: page+=result.get("page",0)
	else:
		layout() # track geometry before accepting coordinates on the compact menu too
		var index: int=menus.row_at(point)
		if index>=0 and menus._rows[index]["on"] and ready_input():
			focus=-1; menus._activate(index)
	menus.queue_redraw()

func key(code: int) -> bool:
	if code not in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_PAGEUP,KEY_PAGEDOWN,KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_ESCAPE]: return false
	if not ready_input(): return true
	menus.pointer=null
	if code==KEY_ESCAPE: menus._escape(); return true
	var paged:=active()
	if code in [KEY_LEFT,KEY_PAGEUP,KEY_RIGHT,KEY_PAGEDOWN]:
		if paged:
			page=clampi(page+(-1 if code in [KEY_LEFT,KEY_PAGEUP] else 1),0,_layout["pages"].size()-1)
			focus=-1
	else:
		var actions:=[]
		var body_actions:=0
		if paged:
			for block in _layout["pages"][page]["blocks"]:
				if block["last"] and block["enabled"]: actions.append(int(block["id"]))
			body_actions=actions.size()
			if _back_row>=0: actions.append(_back_row)
		else:
			for i in menus._rows.size():
				if menus._rows[i]["on"]: actions.append(i)
		if code in [KEY_UP,KEY_DOWN]:
			if not actions.is_empty():
				var at:=actions.find(focus)
				focus=actions[(actions.size()-1 if code==KEY_UP else 0) if at<0 else posmod(at+(-1 if code==KEY_UP else 1),actions.size())]
		elif paged and focus<0 and body_actions==0 and page+1<_layout["pages"].size():
			page+=1 # read the rest before offering the footer as the default action
		elif not actions.is_empty():
			if not focus in actions: focus=actions[0]
			else: menus._activate(focus); return true
		elif paged and page+1<_layout["pages"].size(): page+=1
	menus.queue_redraw(); return true

func draw(ci) -> void:
	if Ink.route(ci,"menu_page",draw): return
	var arranged:=layout()
	var hovered: int=menus.hovered_row()
	var lit:=hovered if hovered>=0 else focus
	Sheet.draw(ci,arranged,page,Callable(),str(lit))
	if lit==_back_row and _back_row>=0:
		ci.draw_rect(arranged["nav"][1]["rect"],Sheet.PAPER,false)
