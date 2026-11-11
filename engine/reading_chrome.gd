extends RefCounted
# Shared existing foreground-panel MENU chrome.
const Ink=preload("res://engine/reading_ink.gd")
const Sheet=preload("res://engine/reading_sheet.gd")
const PixelFont=preload("res://engine/pixel_font.gd")

static func menu(ci,rect: Rect2,label: String,scale: int) -> void:
	if Ink.route(ci,"reading_menu",menu.bind(rect,label,scale)): return
	ci.draw_rect(rect,Ink.paper(ci,Sheet.GREY),false)
	var rows:=Sheet.Reader.rows(label,Sheet.columns(rect.size.x-12,scale))
	for i in rows.size():
		PixelFont.draw_text(ci,rows[i]["text"],rect.position+Vector2(6,4+i*PixelFont.LINE*scale),Sheet.PAPER,false,scale)
