extends RefCounted
const PixelFont=preload("res://engine/pixel_font.gd")
# Names are optional. Channel/source context and narration headings are not.
# Callers supply already-localized, story-visible labels from their product.
static func rows(name: String,source: String,shown: bool,width: int) -> PackedStringArray:
	var label:=name if shown else ""
	if source!="": label+=(" - " if label!="" else "")+source
	return PixelFont.wrap(label,int((width-24)/6)) if label!="" else PackedStringArray()
static func body_y(header: PackedStringArray) -> int: return 8 if header.is_empty() else 10+header.size()*9
static func draw(ci,header: PackedStringArray,colour: Color) -> void:
	for i in header.size(): PixelFont.draw_text(ci,header[i],Vector2(12,5+i*9),colour,false)
