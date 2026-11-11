extends RefCounted
const Ink=preload("res://engine/reading_ink.gd")

# The 28 px strip under the room: the sentence line (with hover names), crew
# portraits, the active crew member's inventory, and at the right edge MENU,
# or SKIP during a cutscene. While a conversation's choice is open, its panel
# is drawn here instead. Drawing and hit-testing only; the game acts.

const Feel = preload("res://engine/feel.gd")
const PixelFont = preload("res://engine/pixel_font.gd")
const I18n = preload("res://engine/i18n.gd")

const C_WHITE := Color("eeeadc")
const C_YELLOW := Color("e4c458")
const C_DGREY := Color("3a3c46")
const C_MGREY := Color("6c707a")
const C_BLACK := Color("0c0a12")

const TEXT_Y := Feel.ROOM_H + 1
const ICON_Y := Feel.ROOM_H + 9
const SKIP_W := 32

var game
var page_message_until := 0


func portrait_rect(i: int) -> Rect2:
	return Rect2(4 + i * 22, ICON_Y, 18, 18)


func slot_rect(i: int) -> Rect2:
	return Rect2(inventory_left() + 22 + i * 20, ICON_Y, 18, 18)


func inventory_left() -> int:
	return 4 + 22 * game.state.crew.size() + 8


func page_rect(direction: int) -> Rect2:
	return Rect2(inventory_left() if direction < 0 else game.view_w() - corner_width() - context_width() - 22, ICON_Y, 18, 18)


func capacity() -> int:
	return maxi(1, floori((game.view_w() - corner_width() - context_width() - 4 - inventory_left() - 42) / 20.0))


func page_count(who: String) -> int:
	return maxi(1, ceili(game.state.inventory.get(who, []).size() / float(capacity())))


func page(who: String) -> int:
	var value: int = clampi(game.state.inventory_pages.get(who, 0), 0, page_count(who) - 1)
	game.state.inventory_pages[who] = value
	return value


func visible_items() -> Array:
	var who: String = game.state.active
	var first := page(who) * capacity()
	return game.state.inventory.get(who, []).slice(first, first + capacity())


func turn_page(direction: int) -> void:
	var who: String = game.state.active
	game.state.inventory_pages[who] = clampi(page(who) + direction, 0, page_count(who) - 1)
	page_message_until = Time.get_ticks_msec() + 2200
	game.state.changed.emit()


func show_new_item(who: String) -> void:
	game.state.inventory_pages[who] = page_count(who) - 1


func page_label(direction := 0) -> String:
	var who: String = game.state.active
	var status := I18n.t("PAGE %s OF %s") % [page(who) + 1, page_count(who)]
	if direction == 0:
		return status
	return (I18n.t("PREVIOUS PAGE") if direction < 0 else I18n.t("NEXT PAGE")) + " - " + status


# The SKIP button: the right end of the HUD, its full height, an easy tap.
func corner_width() -> int:
	# Reserve the larger label for both states so starting a cutscene never
	# shifts the inventory page. Icons keep their original size.
	var scale: int=game.speech.text_scale
	return maxi(SKIP_W,ceili(maxf(PixelFont.text_rect(I18n.t("MENU"),Vector2.ZERO,scale).size.x,
		PixelFont.text_rect(I18n.t("SKIP"),Vector2.ZERO,scale).size.x))+8)


func skip_rect(view_w: int) -> Rect2:
	return Rect2(view_w - corner_width(), Feel.ROOM_H, corner_width(), Feel.HUD_H)


# MENU, in the same place outside cutscenes.
func menu_rect(view_w: int) -> Rect2:
	return skip_rect(view_w)

func foreground_skip_rect(view_w: int) -> Rect2:
	return skip_rect(view_w-corner_width())


# The large reader has its own document icon. Its reservation depends only
# on size, so sentence measurement cannot recurse through inventory hit tests.
func context_width() -> int: return 22 if game.speech.text_scale==2 else 0

func context_rect() -> Rect2:
	return Rect2(game.view_w()-corner_width()-context_width(),ICON_Y,18,18) if context_width()>0 else Rect2()

func sentence_fits() -> bool:
	return PixelFont.text_rect(line(),Vector2.ZERO).size.x<=label_rect(game.view_w()).size.x-8

func compact_label() -> String:
	var full:=line()
	var columns:=maxi(1,floori((label_rect(game.view_w()).size.x-8)/PixelFont.ADVANCE))
	if full.length()<=columns: return full
	# A long room name should still orient the player. Tapping this band
	# retains the complete sentence and location in the existing context sheet.
	if game.selected=="" and _over()=="" and Time.get_ticks_msec()>=page_message_until:
		return full.left(maxi(0,columns-3))+"..."
	return I18n.t("READ")

func needs_context() -> bool: return game.speech.text_scale==2 or not sentence_fits()

func keeps_hover(point: Vector2) -> bool:
	return label_rect(game.view_w()).has_point(point) or menu_rect(game.view_w()).has_point(point) or context_rect().has_point(point)

# A semantic snapshot for the read-only status page. The strings are original
# names, translated only while drawing. No hidden interactions are enumerated.
func context_source() -> Dictionary:
	var who: String=game.state.active
	return {"who":game.crew[who]["name"],"room":game.geo.get("location_name",game.geo["name"]),
		"selected":game.items[game.selected]["name"] if game.selected in game.state.inventory.get(who,[]) else "",
		"over":_over(),"page":page(who)+1,"pages":page_count(who),
		"items":visible_items().map(func(id): return game.items[id]["name"])}

# Translators can put either noun first without changing which item is used.
static func use_sentence(item: String,target: String) -> String:
	return I18n.t("USE {item} WITH {target}").format({"item":item,"target":target})

func context_sections(source: Dictionary) -> Array:
	if source.is_empty(): return []
	var sections:=[{"id":"location","text":I18n.t(source["who"])+" - "+I18n.t(source["room"])}]
	if source["selected"]!="":
		sections.append({"id":"use","text":use_sentence(I18n.t(source["selected"]),I18n.t(source["over"]) if source["over"]!="" else "...")})
	elif source["over"]!="": sections.append({"id":"over","text":I18n.t(source["over"])})
	sections.append({"id":"page","text":I18n.t("PAGE %s OF %s") % [source["page"],source["pages"]]})
	if source["items"].is_empty(): sections.append({"id":"empty","text":I18n.t("NO ITEMS")})
	for i in source["items"].size(): sections.append({"id":"item:"+str(i),"text":I18n.t(source["items"][i])})
	return sections

# The sentence line (character and location) left of MENU. Three quick taps on
# it open the dev menu in debug builds (menus.gd).
func label_rect(view_w: int) -> Rect2:
	return Rect2(0, Feel.ROOM_H, view_w - corner_width(), ICON_Y - 2 - Feel.ROOM_H)


# Persistent context for the large pause page. Reading it does not select,
# transfer, use or page an item, and does not reveal any room's interactions.
func reading_context() -> Array:
	if game.state==null: return []
	var who: String=game.state.active
	var out:=[I18n.t(game.crew[who]["name"])+" - "+I18n.t(game.geo.get("location_name",game.geo["name"]))]
	if game.selected!="" and game.selected in game.state.inventory.get(who,[]):
		out.append(use_sentence(I18n.t(game.items[game.selected]["name"]),"..."))
	return out


# What a HUD tap at p hits: {"menu": true}, {"crew": id}, {"item": id},
# {"label": true} or {}.
func hit(p: Vector2) -> Dictionary:
	var view_w: int = game.view_w()
	if menu_rect(view_w).has_point(p):
		return {"menu": true}
	if context_rect().has_point(p): return {"context":true}
	var crew: Array = game.state.crew
	for i in crew.size():
		if portrait_rect(i).grow(2).has_point(p):
			return {"crew": crew[i]}
	for direction in [-1, 1]:
		if page_rect(direction).has_point(p):
			return {"page": direction}
	var items := visible_items()
	for i in items.size():
		if slot_rect(i).grow(1).has_point(p):
			return {"item": items[i]}
	if label_rect(view_w).has_point(p):
		return {"label": true}
	return {}


# The sentence line: "USE WRENCH WITH TOOLBOX" (or "WITH ...") while an item
# is selected, else the name of what the mouse is over, else who's active and
# where (character and location, in grey). In the player's language.
func line() -> String:
	if not game.in_cutscene and game.pointer != null:
		var under: Dictionary = hit(game.pointer)
		if under.has("page"):
			return page_label(under["page"])
	if not game.in_cutscene and Time.get_ticks_msec() < page_message_until:
		return page_label()
	var over := I18n.t(_over())
	if game.selected != "":
		return use_sentence(I18n.t(game.items[game.selected]["name"]), over if over != "" else "...")
	if over != "":
		return over
	return "%s  -  %s" % [I18n.t(game.actors[game.state.active].display_name), I18n.t(game.geo.get("location_name",game.geo["name"]))]


# The hover name to offer. None in a cutscene: a tap can't use anything then.
func _over() -> String:
	return "" if game.in_cutscene else game.hovered


func draw(ci, view_w: int) -> void:
	var state = game.state
	if game.blackout or game.skipping or game.foreground.blacked_out():
		ci.draw_rect(Rect2(0, 0, view_w, Feel.ROOM_H), Color.BLACK)
	if game.foreground.reading_document():
		game.foreground.document().draw(ci)
		return
	if game.foreground.choosing():
		game.foreground.choices().draw(ci)
		return
	if game.director.choosing:
		game.director.draw_panel(ci, view_w)
		return
	ci.draw_rect(Rect2(0, Feel.ROOM_H, view_w, Feel.HUD_H), Color.BLACK)
	ci.draw_rect(Rect2(0, Feel.ROOM_H, view_w, 1), C_DGREY)

	if Ink.route(ci,"hud",_draw_strip.bind(view_w,false,true)):
		_draw_strip(ci,view_w,true,false)
	else: _draw_strip(ci,view_w,true,true)


# Room art, portraits and item textures stay in Screen's palette pass. The
# same measured labels and controls can be painted onto its final UI layer.
func _draw_strip(ci,view_w: int,art: bool,reading: bool) -> void:
	var state=game.state
	var items:=visible_items()
	if reading:
		if Ink.active(ci): ci.draw_rect(label_rect(view_w),Color.BLACK)
		var quiet: bool = game.selected == "" and _over() == ""
		# The full sentence is available in the read-only context sheet. LARGE
		# does not squeeze its glyphs into this original seven-pixel status band.
		if game.speech.text_scale==1:
			var shown: String=compact_label()
			if PixelFont.text_rect(shown,Vector2.ZERO).size.x<=label_rect(view_w).size.x-8:
				PixelFont.draw_text(ci, shown, Vector2(4, TEXT_Y), C_MGREY if quiet else C_WHITE, false)
			else:
				_document_icon(ci,Rect2(4,TEXT_Y,9,7))
	if art:
		var crew: Array = state.crew
		for i in crew.size():
			var r := portrait_rect(i)
			ci.draw_rect(r, C_YELLOW if crew[i] == state.active else C_DGREY)
			ci.draw_texture(game.texture(game.crew[crew[i]]["portrait"]), r.position + Vector2(1, 1))
			if not game.crew_available(crew[i]):
				ci.draw_rect(r.grow(-1), Color(0, 0, 0, 0.6))

		for i in items.size():
			var r := slot_rect(i)
			ci.draw_rect(r, C_YELLOW if items[i] == game.selected else C_DGREY)
			ci.draw_rect(r.grow(-1), C_BLACK)
			ci.draw_texture(game.texture(game.items[items[i]]["icon"]), r.position + Vector2(3, 3))
	if reading:
		if Ink.active(ci): _selection_marks(ci)
		for direction in [-1, 1]:
			var r := page_rect(direction)
			var enabled: bool = page(state.active) > 0 if direction < 0 else page(state.active) < page_count(state.active) - 1
			ci.draw_rect(r, Ink.backing(ci,C_DGREY if enabled else C_BLACK))
			for y in 7:
				var x: int = 5 + absi(y - 3) if direction < 0 else 10 - absi(y - 3)
				ci.draw_rect(Rect2(r.position + Vector2(x, y + 5), Vector2(2, 1)), C_WHITE if enabled else C_DGREY)
		if items.is_empty():
			var scale: int=game.speech.text_scale
			var at: Vector2=slot_rect(0).position+Vector2(1,5 if scale==1 else 2)
			var box:=Rect2(Vector2(at.x,ICON_Y),Vector2(maxf(0,page_rect(1).position.x-2-at.x),18))
			if box.encloses(PixelFont.text_rect(I18n.t("NO ITEMS"),at,scale)):
				if Ink.active(ci): ci.draw_rect(PixelFont.text_rect(I18n.t("NO ITEMS"),at,scale).grow(1),Color.BLACK)
				PixelFont.draw_text(ci,I18n.t("NO ITEMS"),at,C_MGREY,false,scale)
		if context_width()>0 and not game.foreground_active() and not game.in_cutscene and not game.busy:
			ci.draw_rect(context_rect(),Ink.backing(ci,C_DGREY))
			_document_icon(ci,context_rect().grow(-4))

		if game.foreground_active():
			if game.foreground.can_skip(): _corner(ci,view_w-corner_width(),I18n.t("SKIP"),C_WHITE)
			_corner(ci,view_w,I18n.t("MENU"),C_MGREY)
		elif game.can_skip():
			_corner(ci, view_w, I18n.t("SKIP"), C_WHITE)
		elif not game.in_cutscene:
			var lit: bool = game.pointer != null and menu_rect(view_w).has_point(game.pointer)
			_corner(ci, view_w, I18n.t("MENU"), C_WHITE if lit else C_MGREY)


func _selection_marks(ci) -> void:
	var selected:=[portrait_rect(game.state.crew.find(game.state.active))]
	var items:=visible_items()
	if game.selected in items: selected.append(slot_rect(items.find(game.selected)))
	for rect in selected:
		ci.draw_rect(rect.grow(1),Color.BLACK,false)
		ci.draw_rect(rect,Ink.LIGHT,false)
		# A small corner bracket is a shape cue, as well as a bright border.
		ci.draw_rect(Rect2(rect.position+Vector2(1,1),Vector2(3,1)),Ink.LIGHT)
		ci.draw_rect(Rect2(rect.position+Vector2(1,1),Vector2(1,3)),Ink.LIGHT)


# SKIP or MENU at the right end, on the HUD's own black over any slots beneath.
func _corner(ci, view_w: int, text: String, color: Color) -> void:
	var scale: int=game.speech.text_scale
	var w := PixelFont.text_rect(text,Vector2.ZERO,scale).size.x
	ci.draw_rect(skip_rect(view_w).grow_side(SIDE_TOP, -1), Color.BLACK)
	PixelFont.draw_text(ci, text, Vector2(view_w - 4 - w, floorf(Feel.ROOM_H + (Feel.HUD_H - 7*scale) / 2.0)), color, false,scale)


# A document symbol, not an untranslated text label. CONTEXT in Pause is a
# full-sized named route to the same sheet.
func _document_icon(ci,rect: Rect2) -> void:
	ci.draw_rect(rect,C_WHITE,false)
	for i in 2:
		ci.draw_rect(Rect2(rect.position+Vector2(2,2+i*3),Vector2(maxf(1,rect.size.x-4),1)),C_WHITE)
