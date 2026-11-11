extends Node
const Ink=preload("res://engine/reading_ink.gd")
# Saved choices share the measured controls used by the other full-game
# readers. A selected answer commits its reply before presentation begins.
const Controls=preload("res://engine/control_pages.gd")
const Convo=preload("res://engine/convo_panel.gd")
const Cursor=preload("res://engine/reading_cursor.gd")
const PixelFont=preload("res://engine/pixel_font.gd")
const I18n=preload("res://engine/i18n.gd")
var game
var runner
var reader
func _init(owner) -> void:
	runner=owner; game=owner.game; reader=Controls.new(self)
	var c: Dictionary=runner.context()
	var anchor:=Cursor.anchor(c["reading"],runner.registry.line(c),source(),TranslationServer.get_locale())
	reader.restore({"anchor":anchor,"locale":TranslationServer.get_locale()})
func options() -> Array: return runner.registry.choices(game,runner.context())
func texts() -> Array: return options().map(func(o): return o["text"])
func compact_fits() -> bool: return Convo.layout(texts(),game.view_w())["compact"]
func reading_sections() -> Array:
	var sections:=[{"id":"title","role":"heading","text":I18n.t("CHOOSE A REPLY")}]
	for option in options(): sections.append({"id":"choice:"+option["id"],"action":option["id"],"text":option["text"]})
	return sections
func source() -> String: return JSON.stringify(reading_sections())
func reading_identity() -> Array: return [runner.registry.line(runner.context()),source()]
func reading_close_label() -> String: return I18n.t("MENU")
func reading_back() -> void: game.menus.open("pause")
func reading_activate(id: String) -> void: runner.select(id)
func reading_move_page(position: Dictionary) -> bool: return runner.commit_reading(position,source())
func queue_redraw() -> void: game._overlay.queue_redraw()
func menu_rect() -> Rect2:
	return Rect2(game.view_w()-game.hud.corner_width(),0,game.hud.corner_width(),20)
func draw(ci) -> void:
	if Ink.route(ci,"foreground_choices",draw): return
	if reader.draw_if_needed(ci): return
	var arranged:=Convo.layout(texts(),game.view_w())
	var hovered:=-1
	if game.pointer!=null: hovered=Convo.hit(arranged,0,game.pointer).get("option",-1)
	Convo.draw_layout(ci,game.view_w(),arranged,0,game.actor(game.state.active).text_color,hovered,-1,game.speech.boxed)
	var rect:=menu_rect(); ci.draw_rect(rect,Color.BLACK)
	PixelFont.draw_text(ci,I18n.t("MENU"),rect.position+Vector2(4,6),Color("eeeadc"),false)
func tap(point: Vector2) -> void:
	if reader.active(): reader.tap(point); return
	if not reader.ready_input(): return
	if menu_rect().has_point(point): reading_back(); return
	var result:=Convo.hit(Convo.layout(texts(),game.view_w()),0,point)
	if result.has("option"): reading_activate(options()[result["option"]]["id"])
func key(code: int) -> bool: return reader.key(code)
