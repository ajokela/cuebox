extends RefCounted
const Ink=preload("res://engine/reading_ink.gd")

# Short choices keep the original HUD strip. Longer replies and larger
# sets use measured reading pages, with every authored answer retained.
# Navigation is presentation only; the director owns answer identities.

const Feel = preload("res://engine/feel.gd")
const PixelFont = preload("res://engine/pixel_font.gd")
const Speech = preload("res://engine/speech.gd")
const I18n = preload("res://engine/i18n.gd")

const LINE := PixelFont.LINE
const MAX_LINES := 4
const TEXT_X := 4

const C_WHITE := Color("eeeadc")
const C_DGREY := Color("3a3c46")


# Line i of n (0 at the top), the full width of the view: an easy tap.
static func line_rect(i: int, n: int, view_w: int) -> Rect2:
	return Rect2(0, Feel.VIEW_H - (n - i) * LINE, view_w, LINE)


# The panel's top edge, where its grey rule is: the HUD's own top, or just
# above the first line when there are more lines than the strip holds.
static func top(n: int) -> int:
	return mini(Feel.ROOM_H, Feel.VIEW_H - n * LINE - 1)


# Which of n lines p is on, or -1.
static func line_at(p: Vector2, n: int, view_w: int) -> int:
	for i in n:
		if line_rect(i, n, view_w).has_point(p):
			return i
	return -1


# Paragraph-aware wrapping also splits a single overlong word without clipping.
static func rows(text: String, columns: int) -> Array:
	var out:=[]
	for paragraph in text.split("\n"):
		if paragraph=="": out.append("")
		else: out.append_array(PixelFont.wrap(paragraph,columns))
	return out

static func layout(texts: Array, view_w: int, clear_top: int=0) -> Dictionary:
	var compact: bool=texts.size()<=MAX_LINES and texts.all(func(text): return not "\n" in text and PixelFont.text_rect(text,Vector2(TEXT_X,0)).end.x<=view_w-TEXT_X)
	if compact:
		var entries:=[]
		for i in texts.size(): entries.append({"option":i,"rows":[texts[i]],"rect":line_rect(i,texts.size(),view_w),"last":true})
		return {"compact":true,"top":top(texts.size()),"pages":[entries],"heading":[],"continuing":[],"nav":[]}
	var heading:=rows(I18n.t("CHOOSE A REPLY"),int((view_w-24)/PixelFont.ADVANCE))
	var continuing:=rows(I18n.t("CONTINUE READING"),int((view_w-24)/PixelFont.ADVANCE))
	var panel_top:=maxi(24,clear_top+4)
	var body_y:=panel_top+maxi(heading.size(),continuing.size())*LINE+7
	# Two rows for navigation leave room for translated labels and accents.
	var footer_y:=Feel.VIEW_H-22
	var capacity:=maxi(1,floori((footer_y-4-body_y)/float(LINE))-1)
	var pages:=[]; var entries:=[]; var used:=0
	for i in texts.size():
		var wrapped:=rows(texts[i],maxi(1,int((view_w-24)/PixelFont.ADVANCE)))
		var at:=0
		while at<wrapped.size():
			var count:=mini(capacity,wrapped.size()-at)
			if used+count+1>capacity+1 and not entries.is_empty():
				pages.append(entries); entries=[]; used=0
			var fragment: Array=wrapped.slice(at,at+count)
			entries.append({"option":i,"rows":fragment,"rect":Rect2(0,body_y+used*LINE,view_w,(count+1)*LINE),"last":at+count==wrapped.size()})
			used+=count+1; at+=count
			if at<wrapped.size(): pages.append(entries); entries=[]; used=0
	if not entries.is_empty(): pages.append(entries)
	var nav:=[]
	for i in 3: nav.append(Rect2(i*view_w/3.0,footer_y,view_w/3.0,22))
	return {"compact":false,"top":panel_top,"pages":pages,"heading":heading,"continuing":continuing,"nav":nav}

static func hit(arranged: Dictionary, page: int, p: Vector2) -> Dictionary:
	for entry in arranged["pages"][page]:
		if entry["rect"].has_point(p): return {"option":entry["option"]} if entry["last"] else {"page":1}
	var nav: Array=arranged["nav"]
	if not nav.is_empty():
		if page>0 and nav[0].has_point(p): return {"page":-1}
		if page+1<arranged["pages"].size() and nav[2].has_point(p): return {"page":1}
	return {}

static func draw_layout(ci, view_w: int, arranged: Dictionary, page: int, color: Color, hovered: int, focused: int=-1, boxed:=false) -> void:
	if Ink.route(ci,"conversation",draw_layout.bind(view_w,arranged,page,color,hovered,focused,boxed)): return
	var pad:=Speech.BOX_PAD if boxed and arranged["compact"] else 0
	var t: int=arranged["top"]
	ci.draw_rect(Rect2(0,t-pad,view_w,Feel.VIEW_H-t+pad),Color.BLACK)
	ci.draw_rect(Rect2(0,t,view_w,1),C_DGREY)
	var heading: Array=arranged["heading"] if arranged["pages"][page].any(func(e): return e["last"]) else arranged["continuing"]
	for i in heading.size(): PixelFont.draw_text(ci,heading[i],Vector2(12,t+3+i*LINE),C_WHITE,false)
	for entry in arranged["pages"][page]:
		var r: Rect2=entry["rect"]
		var chosen: bool=entry["last"] and (entry["option"]==hovered or entry["option"]==focused)
		var x:=TEXT_X if arranged["compact"] else 12
		for i in entry["rows"].size(): PixelFont.draw_text(ci,entry["rows"][i],Vector2(x,r.position.y+1+i*LINE),C_WHITE if chosen else color,false)
		if entry["last"] and (entry["option"]==focused or (Ink.active(ci) and entry["option"]==hovered)): ci.draw_rect(Rect2(0,r.position.y+1,2,r.size.y-2),C_WHITE)
	var nav: Array=arranged["nav"]
	if nav.is_empty(): return
	ci.draw_rect(Rect2(0,nav[0].position.y,view_w,1),C_DGREY)
	var labels: Array=[I18n.t("PREVIOUS") if page>0 else "",I18n.t("PAGE %s OF %s") % [page+1,arranged["pages"].size()],I18n.t("NEXT") if page+1<arranged["pages"].size() else ""]
	for i in 3:
		var lines:=rows(labels[i],maxi(1,int((nav[i].size.x-8)/PixelFont.ADVANCE)))
		for j in lines.size(): PixelFont.draw_text(ci,lines[j],nav[i].position+Vector2(4,3+j*LINE),C_WHITE,false)

static func draw(ci, view_w: int, texts: Array, color: Color, hovered: int, boxed:=false) -> void:
	draw_layout(ci,view_w,layout(texts,view_w),0,color,hovered,-1,boxed)
