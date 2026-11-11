extends Node
const Ink=preload("res://engine/reading_ink.gd")
# Product text stays in the registry. Navigation commits source positions;
# closing commits the product's knowledge/result before returning control.
const Controls=preload("res://engine/control_pages.gd")
const Sheet=preload("res://engine/reading_sheet.gd")
const Cursor=preload("res://engine/reading_cursor.gd")
const PixelFont=preload("res://engine/pixel_font.gd")
const I18n=preload("res://engine/i18n.gd")
var game
var runner
var reader
var closed:=false
func _init(owner) -> void:
	runner=owner; game=owner.game; reader=Controls.new(self); restore_cursor()
	var doc: Dictionary=runner.registry.document(game,runner.context())
	if doc.get("record",true): game.record("read "+doc["title"]+": "+doc["body"])
func restore_cursor() -> void:
	var c: Dictionary=runner.context()
	reader.restore({"anchor":Cursor.anchor(c["reading"],runner.registry.line(c),source(),TranslationServer.get_locale()),"locale":TranslationServer.get_locale()})
func compact_fits() -> bool: return false
func reading_sections() -> Array:
	var doc: Dictionary=runner.registry.document(game,runner.context())
	return [{"id":"title","role":"title","text":doc["title"]},{"id":"body","text":doc["body"]}]
func source() -> String: return JSON.stringify(reading_sections())
func reading_identity() -> Array: return [runner.registry.line(runner.context()),source()]
func reading_close_label() -> String: return I18n.t("CLOSE")
func reading_back() -> void:
	if closed or game.menu_open or game.saves.has_pending_commit() or runner.document_panel!=self: return
	runner._next(); closed=runner.document_panel!=self
func reading_move_page(position: Dictionary) -> bool: return runner.commit_reading(position,source())
func menu_rect() -> Rect2:
	var scale: int=game.speech.text_scale
	var width:=minf(game.view_w()-8,PixelFont.text_rect(I18n.t("MENU"),Vector2.ZERO,scale).size.x+12)
	var rows:=Sheet.Reader.rows(I18n.t("MENU"),Sheet.columns(width-12,scale))
	return Rect2(game.view_w()-width-4,4,width,rows.size()*PixelFont.LINE*scale+8)
func reading_layout(sections: Array,width: int,scale: int,close_label: String) -> Dictionary:
	return Sheet.make(sections,width,scale,close_label,{"top":ceili(menu_rect().end.y)+4})
func queue_redraw() -> void: game._overlay.queue_redraw()
func draw(ci) -> void:
	if Ink.route(ci,"foreground_document",draw): return
	reader.draw(ci)
	var rect:=menu_rect(); ci.draw_rect(rect,Ink.paper(ci,Sheet.GREY),false)
	var scale: int=game.speech.text_scale
	var rows:=Sheet.Reader.rows(I18n.t("MENU"),Sheet.columns(rect.size.x-12,scale))
	for i in rows.size(): PixelFont.draw_text(ci,rows[i]["text"],rect.position+Vector2(6,4+i*PixelFont.LINE*scale),Sheet.PAPER,false,scale)
func tap(point: Vector2) -> void:
	if closed or runner.document_panel!=self: return
	if menu_rect().has_point(point):
		if reader.ready_input(): game.menus.open("pause")
	else: reader.tap(point)
func key(code: int) -> bool:
	if closed or runner.document_panel!=self: return false
	if code==KEY_ESCAPE:
		if reader.ready_input(): game.menus.open("pause")
		return true
	return reader.key(code)
