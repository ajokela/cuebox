extends RefCounted
const Ink=preload("res://engine/reading_ink.gd")

# Speech lines, at most one per actor, and one caption: timing, mouth flaps
# and drawing. Foreground lines (handlers, cutscenes) and captions can be
# skipped with a tap; background lines (bg_say) can't. A new line for an actor
# replaces the old one. The player's text speed scales how long text stays up,
# and their text boxes setting puts a black box behind it.

const Feel = preload("res://engine/feel.gd")
const PixelFont = preload("res://engine/pixel_font.gd")
const I18n = preload("res://engine/i18n.gd")
const Reader=preload("res://engine/reading_pages.gd")

const C_WHITE := Color("eeeadc")
const BOX_PAD := 2  # a text box reaches this far past the text

var time_scale := 1.0  # the text speed: 1.0 normal, 1.5 slow, 0.7 fast
var boxed := false  # text boxes: black behind each block of text, for reading over busy art
var names := true # optional speech labels; source/channel tags remain visible
var lines := {}  # actor id -> {"actor": Node2D, "text": PackedStringArray, "left": float, "fg": bool, "token": int}
var caption := {}  # the caption showing, {"text": String, "left": float, "token": int}, or empty
var _next_token := 0
var text_scale:=1 # Exact bitmap size for measured reading surfaces.
var manual:=false # Only managed foreground lines; ambient speech still expires.
var _room:=""
var _offset:=0
var _width:=320
var _reserved:=[]
var _choosing:=false
var _last_skip_frame:=-1
var _notice_fit_key:=[]
var _notice_fits:=true


# Shows text above the actor and returns a token for is_current().
func start(actor: Node2D, text: String, foreground: bool, source := {}) -> int:
	_next_token += 1
	lines[actor.id] = {
		"actor": actor,
		"text": PixelFont.wrap(text, Feel.WRAP_CHARS),
		"raw":text,"anchor":0,"reading":{},"layout_key":[],"clear_top":0,
		"left": _time(text),
		"fg": foreground,
		"token": _next_token,
		"source": source,
	}
	actor.talking = true
	return _next_token


# Shows one centred white line ("MEANWHILE, ...") with speech timing and
# returns a token for caption_is().
func start_caption(text: String) -> int:
	_next_token += 1
	caption = {"text":text,"raw":text,"left":_time(text),"token":_next_token,"anchor":0,"reading":{},"layout_key":[],"clear_top":0}
	return _next_token


func _time(text: String) -> float:
	return (Feel.SPEECH_BASE + Feel.SPEECH_PER_CHAR * text.length()) * time_scale


func caption_is(token: int) -> bool:
	return caption.get("token", -1) == token


func stop_caption(token: int) -> void:
	if caption_is(token):
		caption = {}


func is_current(id: String, token: int) -> bool:
	return lines.has(id) and lines[id]["token"] == token


# Ends a line early if it is still the actor's current one.
func stop(id: String, token: int) -> void:
	if is_current(id, token):
		lines[id]["actor"].talking = false
		lines.erase(id)


func clear() -> void:
	for line in lines.values():
		line["actor"].talking = false
	lines.clear()
	caption = {}
	_last_skip_frame=-1


func tick(delta: float) -> void:
	for id in lines.keys():
		var line: Dictionary = lines[id]
		if line.get("managed",false): continue # Durable foreground runner commits before advancing.
		line["left"] -= delta
		while line["left"]<=0.0:
			var overshoot: float=line["left"]
			if not _next_page(line):
				line["actor"].talking=false; lines.erase(id); break
			if line["fg"]: break # A foreground page gets a complete reading interval.
			line["left"]+=overshoot # Hidden barks catch up and expire, never queue behind foreground text.
	if not caption.is_empty() and not caption.get("managed",false):
		caption["left"] -= delta
		if caption["left"]<=0.0 and not _next_page(caption): caption={}


func _next_page(entry: Dictionary) -> bool:
	var reading: Dictionary=entry.get("reading",{})
	entry["skipped"]=false
	if reading.is_empty() or entry["page"]+1>=reading["pages"].size(): return false
	entry["page"]+=1
	entry["anchor"]=reading["pages"][entry["page"]]["start"]
	entry["left"]=_time(reading["pages"][entry["page"]]["text"])
	return true

# One input ends one page; its token remains live until the final page.
func skip() -> bool:
	var frame:=Engine.get_process_frames()
	if frame==_last_skip_frame: return true
	if not caption.is_empty() and caption["left"]>0.0:
		caption["left"]=0.0; caption["skipped"]=true; _last_skip_frame=frame; return true
	for line in lines.values():
		if line["fg"] and line["left"]>0.0:
			line["left"]=0.0; line["skipped"]=true; _last_skip_frame=frame; return true
	return false

func configure(room: String, offset: int, width: int, reserved: Array=[], choosing:=false) -> void:
	_room=room; _offset=offset; _width=width; _reserved=reserved; _choosing=choosing
	for line in lines.values():
		if not line["fg"]: _prepare(line,false)
	if not caption.is_empty(): _prepare(caption,true); return
	if choosing: return
	for line in visible_lines(): _prepare(line,false)

func reading_active() -> bool:
	if not caption.get("reading",{}).is_empty(): return true
	return visible_lines().any(func(line): return line["fg"] and not line.get("reading",{}).is_empty())

func visible_lines() -> Array:
	var visible:=lines.values().filter(func(line): return line.get("source",{}).get("room",line["actor"].room)==_room)
	var foreground:=visible.filter(func(line): return line["fg"])
	if not foreground.is_empty(): visible=foreground
	visible.sort_custom(func(a,b): return a["token"]<b["token"])
	return visible.slice(0,1)

# Informational notices may wait for a foreground line, while critical encounter
# warnings retain their own priority. Probe the same complete reading layout;
# never shorten either message or consume the notice's display time offscreen.
func can_share_notice(room: String,width: int,reserved: Array) -> bool:
	var entries: Array=[caption] if not caption.is_empty() else lines.values().filter(func(line): return line["fg"] and line.get("source",{}).get("room",line["actor"].room)==room)
	if entries.is_empty(): return true
	entries.sort_custom(func(a,b): return a["token"]<b["token"])
	var entry: Dictionary=entries[0]
	var header: Array=[] if not entry.has("actor") else label_texts(entry)
	var held:=reserved.duplicate()
	if entry.get("clear_top",0)>0: held.append(Rect2(0,0,width,entry["clear_top"]))
	var action: String=I18n.t("CONTINUE") if manual and entry.get("managed",false) else I18n.t("NEXT")
	var key: Array=[entry["raw"],header,width,text_scale,held,action]
	if key!=_notice_fit_key:
		_notice_fit_key=key
		_notice_fits=Reader.make(entry["raw"],header,width,text_scale,held,action)["status"]=="ok"
	return _notice_fits

func _prepare(entry: Dictionary, narration: bool) -> void:
	var clear_top: int=entry.get("clear_top",0)
	for rect in _reserved: clear_top=maxi(clear_top,ceili(rect.end.y))
	entry["clear_top"]=clear_top
	var header: Array=[] if narration else label_texts(entry)
	var manual_line: bool=manual and entry.get("managed",false)
	var key: Array=[_width,text_scale,header,clear_top,manual_line]
	if not narration and entry.get("reading",{}).is_empty():
		key.append(entry.get("source",{}).get("pos",entry["actor"].position-Vector2(0,entry["actor"].height+4)).y)
	if key==entry.get("layout_key",[]): return
	entry["layout_key"]=key
	var held: Array=[] if clear_top==0 else [Rect2(0,0,_width,clear_top)]
	var needs: bool=manual_line or text_scale==2 or "\n" in entry["raw"] or not entry.get("reading",{}).is_empty()
	if narration: needs=needs or PixelFont.text_rect(entry["text"],Vector2.ZERO).size.x>_width-4
	else: needs=needs or not layout(entry,_offset,_width,held)["fits"]
	if not needs: return
	var action:=I18n.t("CONTINUE") if manual_line else I18n.t("NEXT") if narration or entry["fg"] else ""
	var reading:=Reader.make(entry["raw"],header,_width,text_scale,held,action)
	if reading["status"]!="ok":
		push_error("Reading header does not fit the supported view: "+" / ".join(header))
		return # Invalid authored labels are a content error, never silently abbreviated.
	entry["reading"]=reading
	entry["layout_key"]=key.slice(0,5) # Actor motion no longer changes an anchored reading panel.
	entry["page"]=Reader.page_at(reading,entry.get("anchor",0))
	entry["left"]=0.0 if entry.get("skipped",false) else _time(reading["pages"][entry["page"]]["text"])

func label_texts(line: Dictionary) -> Array:
	var source: Dictionary=line.get("source",{})
	var out:=[]
	var name=source.get("name",line["actor"].get("display_name"))
	if names and name is String and name!="": out.append(I18n.t(name))
	if source.has("room"): out.append(I18n.t("INTERCOM"))
	return out

# Lines of actors in the shown room, centred over their heads and kept on
# screen, and the caption in the middle of the room. ci is a CanvasItem (or
# anything with its draw_rect and draw_texture_rect_region, for tests).
func labels(line: Dictionary) -> PackedStringArray:
	var out:=PackedStringArray()
	for text in label_texts(line): out.append_array(PixelFont.wrap(text,Feel.WRAP_CHARS))
	return out

func layout(line: Dictionary, offset: int, view_w: int, reserved: Array=[]) -> Dictionary:
	var a: Node2D=line["actor"]
	var source: Dictionary=line.get("source",{})
	var head: Vector2=source.get("pos",Vector2(a.position.x,a.position.y-a.height-4))+Vector2(offset,0)
	var header:=labels(line)
	var text: PackedStringArray=line["text"]
	var width:=0.0
	for row in header+text: width=maxf(width,row.length()*PixelFont.ADVANCE-1)
	var title:=[]; var body:=[]
	for i in header.size(): title.append([header[i],Vector2(0,i*PixelFont.LINE)])
	var body_y: float=header.size()*PixelFont.LINE+(2 if not header.is_empty() else 0)
	for i in text.size(): body.append([text[i],Vector2(roundf((width-(text[i].length()*PixelFont.ADVANCE-1))/2),body_y+i*PixelFont.LINE)])
	var bounds:=Rect2(); var first:=true
	for group in [title,body]:
		for row in group:
			var rect:=PixelFont.text_rect(row[0],row[1]).grow(BOX_PAD)
			bounds=rect if first else bounds.merge(rect); first=false
	var top:=2.0
	# Patrol notices occupy the top edge; their exact height belongs to the
	# product. Moving the complete speech block preserves the name/body bond.
	for rect in reserved:
		if rect.position.y<=top: top=maxf(top,rect.end.y+2)
	var at:=Vector2(clampf(roundf(head.x-width/2),2-bounds.position.x,view_w-2-bounds.end.x),clampf(head.y-bounds.end.y,top-bounds.position.y,Feel.ROOM_H-2-bounds.end.y))
	for group in [title,body]:
		for row in group: row[1]+=at
	var placed:=Rect2(bounds.position+at,bounds.size)
	var fits:=Rect2(2,top,view_w-4,Feel.ROOM_H-2-top).encloses(placed) and placed.end.y<=head.y
	return {"header":title,"body":body,"bounds":placed,"fits":fits}

func draw(ci, room: String, offset: int, view_w: int, reserved: Array=[], choosing:=false) -> void:
	if Ink.route(ci,"speech",draw.bind(room,offset,view_w,reserved,choosing)): return
	configure(room,offset,view_w,reserved,choosing)
	if not caption.is_empty():
		if not caption.get("reading",{}).is_empty(): Reader.draw(ci,caption["reading"],caption["page"],C_WHITE); return
		var text: String = caption["text"]
		var w := text.length() * PixelFont.ADVANCE - 1
		_block(ci, [[text, Vector2(roundf((view_w - w) / 2.0), (Feel.ROOM_H - 7) / 2)]], C_WHITE)
		return # narration owns the foreground; ambient chatter cannot cover it
	if choosing: return
	# Hidden ambient lines still expire, without waiting for foreground speech.
	for line in visible_lines():
		if not line.get("reading",{}).is_empty():
			Reader.draw(ci,line["reading"],line["page"],line["actor"].text_color); continue
		var a: Node2D = line["actor"]
		var source: Dictionary = line.get("source", {})
		if source.get("room", a.room) != room:
			continue
		var arranged:=layout(line,offset,view_w,reserved)
		for row in arranged["header"]:
			ci.draw_rect(PixelFont.text_rect(row[0],row[1]).grow(BOX_PAD),Color.BLACK)
		PixelFont.draw_lines(ci,arranged["header"],C_WHITE,false)
		_block(ci,arranged["body"],a.text_color)


# One block of text, [[line, pos], ...], with its box first if text boxes are
# on, then every line's outline and then every line's letters.
func _block(ci, placed: Array, color: Color) -> void:
	if boxed or Ink.active(ci):
		var box := Rect2()
		for p in placed:
			var r := PixelFont.text_rect(p[0], p[1])
			box = r if box.size == Vector2.ZERO else box.merge(r)
		ci.draw_rect(box.grow(BOX_PAD), Color.BLACK)
	PixelFont.draw_lines(ci, placed, color)
