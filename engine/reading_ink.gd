extends RefCounted
# A local CanvasItem marker, never a global font mode.
const LIGHT:=Color("eeeadc")
const DARK:=Color.BLACK

static func preferred(game) -> bool:
	return game.settings.get("text_colour","speaker")=="high_contrast"

static func active(ci) -> bool:
	return ci is Object and ci.get_meta("reading_contrast_surface",false)

static func paper(ci,ordinary: Color) -> Color:
	return LIGHT if active(ci) else ordinary

static func backing(ci,ordinary: Color) -> Color:
	return DARK if active(ci) else ordinary

static func route(ci,key: String,paint: Callable) -> bool:
	if not ci is CanvasItem or active(ci) or not ci.is_inside_tree(): return false
	var viewport: Viewport=ci.get_viewport()
	if not viewport.has_meta("reading_compositor"): return false
	var compositor=viewport.get_meta("reading_compositor")
	return compositor!=null and compositor.stage(ci,key,paint)
