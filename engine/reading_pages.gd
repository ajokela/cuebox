extends RefCounted
const Ink=preload("res://engine/reading_ink.gd")
# Presentation only: source character offsets, never visual page numbers,
# identify a place in the same text after a size/width change. A caller owns
# persistence and must restart at a semantic boundary if the text changes.
const PixelFont=preload("res://engine/pixel_font.gd")
const I18n=preload("res://engine/i18n.gd")
const Feel=preload("res://engine/feel.gd")
const INK:=Color("0c0a12")
const PAPER:=Color("eeeadc")

# Wrapped rows retain the exact source interval, including skipped spaces
# and paragraph boundaries. Display hyphens never alter a saved offset.
static func rows(text: String, columns: int) -> Array:
	columns=maxi(1,columns)
	var out:=[]; var at:=0
	while at<text.length():
		var start:=at
		var stop:=text.find("\n",at)
		if stop<0: stop=text.length()
		while at<stop and text[at] in [" ","\t"]: at+=1
		if at==stop:
			at=mini(stop+1,text.length()); out.append({"text":"","start":start,"end":at}); continue
		var end:=mini(at+columns,stop); var hyphen:=false
		if end<stop and not text[end] in [" ","\t"]:
			var space: int=maxi(text.rfind(" ",end),text.rfind("\t",end))
			if space>at: end=space
			else: end=at+maxi(1,columns-1); hyphen=columns>1
		var shown:=text.substr(at,end-at).strip_edges()+("-" if hyphen else "")
		at=end
		while at<stop and text[at] in [" ","\t"]: at+=1
		if at==stop and stop<text.length(): at+=1
		out.append({"text":shown,"start":start,"end":at})
	if out.is_empty(): out.append({"text":"","start":0,"end":0})
	return out

static func make(text: String, labels: Array, width: int, scale: int=1, reserved: Array=[], action: String="") -> Dictionary:
	scale=2 if scale==2 else 1
	var top:=4
	for rect in reserved: top=maxi(top,ceili(rect.end.y)+4)
	var bounds:=Rect2(4,top,width-8,Feel.ROOM_H-4-top)
	var padding:=4; var pitch:=PixelFont.LINE*scale
	var inner_width: int=int(bounds.size.x)-padding*2
	var columns:=maxi(1,floori((inner_width+scale)/float(PixelFont.ADVANCE*scale)))
	if scale==2 and width<=320: columns=mini(24,columns)
	var header:=[]
	for label in labels:
		if label!="": header.append_array(rows(label,columns).map(func(row): return row["text"]))
	var body:=rows(text,columns)
	# Use an upper bound on the number of pages so the footer has stable
	# space even when the actual page counter changes its number of digits.
	var digits:=str(body.size()).length(); var number:="8".repeat(digits)
	var counter:=counter_text(scale,number,number)
	var counter_rows:=rows(counter,columns)
	var action_rows:=rows(action,columns) if action!="" else []
	var inline_footer: bool=counter_rows.size()==1 and action_rows.size()<=1 and PixelFont.text_rect(counter+"  "+action,Vector2.ZERO,scale).size.x<=inner_width
	var footer_rows: int=counter_rows.size() if inline_footer else counter_rows.size()+action_rows.size()
	var header_h: int=header.size()*pitch+(2*scale if not header.is_empty() else 0)
	var footer_h: int=footer_rows*pitch+2*scale
	var available: int=int(bounds.size.y)-padding*2-header_h-footer_h
	# Content authors must keep translated source/name headers short enough
	# for one body row. Never silently clip or abbreviate a speaker's label.
	if available<pitch: return {"status":"header_overflow","bounds":bounds,"header":header,"scale":scale}
	var capacity:=mini(4 if scale==2 else 8,floori(available/float(pitch)))
	var body_at:=bounds.position+Vector2(padding,padding+header_h)
	var pages:=[]
	for first in range(0,body.size(),capacity):
		var slice: Array=body.slice(first,first+capacity); var placed:=[]
		for i in slice.size(): placed.append([slice[i]["text"],body_at+Vector2(0,i*pitch)])
		pages.append({"start":slice[0]["start"],"end":slice[-1]["end"],"body":placed,"text":" ".join(slice.map(func(row): return row["text"]))})
	var title:=[]
	for i in header.size(): title.append([header[i],bounds.position+Vector2(padding,padding+i*pitch)])
	return {"status":"ok","scale":scale,"bounds":bounds,"header":title,"pages":pages,"columns":columns,
		"footer_at":Vector2(bounds.position.x+padding,bounds.end.y-padding-footer_rows*pitch),"footer_rows":counter_rows.size(),
		"inline_footer":inline_footer,"action":action,"action_rows":action_rows,"inner_width":inner_width}

static func counter_text(scale: int, page, count) -> String:
	return (I18n.t("%s / %s") if scale==2 else I18n.t("PAGE %s OF %s")) % [page,count]

static func page_at(layout: Dictionary, anchor: int) -> int:
	var pages: Array=layout["pages"]
	for i in pages.size():
		if anchor<pages[i]["end"] or i==pages.size()-1: return i
	return 0

static func draw(ci, layout: Dictionary, page: int, color: Color=PAPER) -> void:
	if layout.get("status")!="ok": return
	page=clampi(page,0,layout["pages"].size()-1)
	var scale: int=layout["scale"]; var pitch: int=PixelFont.LINE*scale
	ci.draw_rect(layout["bounds"],Ink.backing(ci,INK))
	PixelFont.draw_lines(ci,layout["header"],PAPER,false,scale)
	PixelFont.draw_lines(ci,layout["pages"][page]["body"],color,false,scale)
	var counter:=counter_text(scale,page+1,layout["pages"].size())
	var counter_rows:=rows(counter,layout["columns"])
	for i in counter_rows.size(): PixelFont.draw_text(ci,counter_rows[i]["text"],layout["footer_at"]+Vector2(0,i*pitch),PAPER,false,scale)
	if layout["action"]=="": return
	if layout["inline_footer"]:
		var x: float=layout["inner_width"]-PixelFont.text_rect(layout["action"],Vector2.ZERO,scale).size.x
		PixelFont.draw_text(ci,layout["action"],layout["footer_at"]+Vector2(x,0),PAPER,false,scale)
	else:
		for i in layout["action_rows"].size(): PixelFont.draw_text(ci,layout["action_rows"][i]["text"],layout["footer_at"]+Vector2(0,(layout["footer_rows"]+i)*pitch),PAPER,false,scale)
