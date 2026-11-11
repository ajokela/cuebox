extends RefCounted
const Ink=preload("res://engine/reading_ink.gd")
# Full-screen documents and lists. Headings flow with the content instead
# of consuming a fixed header area or losing their translated continuation.
# Offsets identify a source section, never a visual row or page number.
const Reader=preload("res://engine/reading_pages.gd")
const PixelFont=preload("res://engine/pixel_font.gd")
const I18n=preload("res://engine/i18n.gd")
const INK:=Color("0c0a12")
const PAPER:=Color("eeeadc")
const GOLD:=Color("e4c458")
const GREY:=Color("6c707a")

static func columns(width: float, scale: int) -> int:
	var count:=maxi(1,floori((width+scale)/float(PixelFont.ADVANCE*scale)))
	return mini(24,count) if scale==2 and width<=296 else count

static func make(sections: Array, width: int, scale: int, close_label: String, controls: Dictionary={}) -> Dictionary:
	scale=2 if scale==2 else 1
	var pitch:=PixelFont.LINE*scale
	var labels: Array=[controls.get("prev",I18n.t("PREV")),close_label,controls.get("next",I18n.t("NEXT"))]
	var nav:=[]; var footer_h:=22
	for label in labels:
		var rows:=Reader.rows(label,columns((width-8)/3.0-8,scale))
		footer_h=maxi(footer_h,rows.size()*pitch+6)
		nav.append({"rows":rows})
	for i in nav.size(): nav[i]["rect"]=Rect2(4+i*(width-8)/3.0,180-footer_h,(width-8)/3.0,footer_h)
	var template: String=controls.get("counter",I18n.t("%s / %s") if scale==2 else I18n.t("PAGE %s OF %s"))
	var total:=0
	for section in sections: total+=section["text"].length()+1
	# An exact-font body can share this navigation while laying out its own
	# rows. Reserve the counter from that body's full source length too.
	total=maxi(total,controls.get("source_length",0))
	var number:="8".repeat(str(maxi(1,total)).length())
	var counter_rows:=Reader.rows(template % [number,number],columns(width-24,scale))
	var counter_top:=180-footer_h-counter_rows.size()*pitch-6
	var bottom:=counter_top-4
	var top: int=maxi(8,controls.get("top",8))
	var pages:=[{"rows":[],"blocks":[]}]; var y:=top
	# An action needs its whole hit target and padding even when only one
	# line fits. Reject impossible controls before trying to paginate it.
	var minimum:=maxi(20,pitch+6) if sections.any(func(section): return section.has("action")) else pitch
	if bottom-top<minimum: return {"status":"controls_overflow","pages":pages}
	for section in sections:
		var clickable: bool=section.has("action")
		var x:=34 if section.has("icon") else 12
		var wrapped:=Reader.rows(section["text"],columns(width-x-12,scale))
		var full_h:=maxi(20,wrapped.size()*pitch+6) if clickable else wrapped.size()*pitch
		if clickable and full_h<=bottom-top and y+full_h>bottom and not pages[-1]["rows"].is_empty():
			pages.append({"rows":[],"blocks":[]}); y=top
		var at:=0
		while at<wrapped.size():
			var count:=floori((bottom-y-(6 if clickable else 0))/float(pitch))
			if count<=0 or (clickable and bottom-y<20):
				pages.append({"rows":[],"blocks":[]}); y=top; continue
			count=mini(count,wrapped.size()-at)
			var height:=maxi(20,count*pitch+6) if clickable else count*pitch
			for i in count:
				var row: Dictionary=wrapped[at+i]
				pages[-1]["rows"].append({"id":section["id"],"role":section.get("role","body"),"text":row["text"],
					"enabled":section.get("enabled",true),"start":row["start"],"end":row["end"],"pos":Vector2(x,y+i*pitch+(3 if clickable else 0))})
			if clickable:
				pages[-1]["blocks"].append({"id":section["action"],"section":section["id"],"last":at+count==wrapped.size(),
					"enabled":section.get("enabled",true),"rect":Rect2(6,y,width-12,height),"icon":section.get("icon","") if at==0 else ""})
			y+=height; at+=count
			if at<wrapped.size(): pages.append({"rows":[],"blocks":[]}); y=top
		y+=4
	return {"status":"ok","pages":pages,"scale":scale,"width":width,"nav":nav,"back_enabled":close_label!="","counter_template":template,
		"counter_at":Vector2(12,counter_top+3),"bounds":Rect2(4,top-4,width-8,bottom-top+4)}

static func anchor(layout: Dictionary, page: int) -> Dictionary:
	if layout.is_empty(): return {}
	var rows: Array=layout["pages"][clampi(page,0,layout["pages"].size()-1)]["rows"]
	return {"id":rows[0]["id"],"offset":rows[0]["start"]} if not rows.is_empty() else {}

static func page_for(layout: Dictionary, position: Dictionary) -> int:
	for i in layout["pages"].size():
		for row in layout["pages"][i]["rows"]:
			if row["id"]==position.get("id","") and (row["end"]>position.get("offset",0) or row["start"]==position.get("offset",0)):
				return i
	return 0

static func hit(layout: Dictionary, page: int, p: Vector2) -> Dictionary:
	if layout.get("status")!="ok": return {}
	for block in layout["pages"][page]["blocks"]:
		if block["rect"].has_point(p):
			if not block["last"]: return {"page":1}
			return {"action":block["id"]} if block["enabled"] else {}
	for i in 3:
		if not layout["nav"][i]["rect"].has_point(p): continue
		if i==1 and layout["back_enabled"]: return {"back":true}
		if i==0 and page>0: return {"page":-1}
		if i==2 and page+1<layout["pages"].size(): return {"page":1}
	return {}

static func draw(ci, layout: Dictionary, page: int, textures: Callable=Callable(), focus:="") -> void:
	if layout.get("status")!="ok": return
	var width: int=layout["width"]; var scale: int=layout["scale"]; var pitch:=PixelFont.LINE*scale
	page=clampi(page,0,layout["pages"].size()-1)
	ci.draw_rect(Rect2(0,0,width,180),Ink.backing(ci,INK))
	for block in layout["pages"][page]["blocks"]:
		ci.draw_rect(block["rect"],Ink.paper(ci,GOLD if block["id"]==focus and block["enabled"] else GREY),false)
		if block["id"]==focus and block["enabled"]:
			var rect: Rect2=block["rect"]
			ci.draw_rect(Rect2(rect.position+Vector2(1,2),Vector2(2,rect.size.y-4)),PAPER)
		if block["icon"]!="" and textures.is_valid(): ci.draw_texture(textures.call(block["icon"]),block["rect"].position+Vector2(4,3))
	for row in layout["pages"][page]["rows"]:
		var color:=GOLD if row["role"] in ["title","action"] else PAPER
		if not row["enabled"]: color=GREY
		PixelFont.draw_text(ci,row["text"],row["pos"],color,false,scale)
	var counter: String=layout["counter_template"] % [page+1,layout["pages"].size()]
	var counter_rows:=Reader.rows(counter,columns(width-24,scale))
	for i in counter_rows.size(): PixelFont.draw_text(ci,counter_rows[i]["text"],layout["counter_at"]+Vector2(0,i*pitch),GREY,false,scale)
	for i in 3:
		if (i==0 and page==0) or (i==1 and not layout["back_enabled"]) or (i==2 and page+1==layout["pages"].size()): continue
		var nav: Dictionary=layout["nav"][i]
		for j in nav["rows"].size():
			var text: String=nav["rows"][j]["text"]
			var x: float=(nav["rect"].size.x-PixelFont.text_rect(text,Vector2.ZERO,scale).size.x)/2.0
			PixelFont.draw_text(ci,text,nav["rect"].position+Vector2(floorf(x),3+j*pitch),PAPER if i==1 else GOLD,false,scale)
