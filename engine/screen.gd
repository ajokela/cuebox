extends SubViewportContainer

# The game's window onto the screen. The game draws at 180 px tall into
# `viewport`; this container scales that up in whole steps, centred, with
# black bars where it doesn't fill the window. Like the prototype's
# keep_height + integer stretch: wider screens get a wider view, narrower ones
# are letterboxed at 320 wide. Taps and clicks reach the game through it in
# view coordinates; ones in the bars reach nothing.
#
# It also carries the display shader, at device resolution: a display mode's
# palette swap and CRT lines. What is shown, and ownership of modes, is the
# game's business (see game.set_display); this only draws.

const Feel = preload("res://engine/feel.gd")
const Content = preload("res://engine/content.gd")
var display_modes: Dictionary = {}
const SHADER = preload("res://engine/display.gdshader")

const ReadingCompositor=preload("res://engine/reading_compositor.gd")
var reading_compositor

var viewport: SubViewport
var fitted := {}  # the last fit(): scale, view, offset

var _material := ShaderMaterial.new()


# The whole-step scale, view size and position for a window of this size.
static func fit(window: Vector2i) -> Dictionary:
	var s := maxi(1, mini(window.y / Feel.VIEW_H, window.x / Feel.BASE_W))
	var view := Vector2i(maxi(Feel.BASE_W, window.x / s), Feel.VIEW_H)
	return {"scale": s, "view": view, "offset": (window - view * s) / 2}


func _init() -> void:
	name = "Screen"
	viewport = SubViewport.new()
	# A new SubViewport ignores the project's 2D settings: filtering would be
	# LINEAR and nothing would snap. The prototype's crisp pixels need these.
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.snap_2d_transforms_to_pixel = true
	viewport.snap_2d_vertices_to_pixel = true
	add_child(viewport)
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_material.shader = SHADER
	configure(Content.options().get("presentation", {}))


func configure(presentation: Dictionary) -> void:
	display_modes = presentation.get("display_modes", {}).duplicate(true)
	var src := PackedVector3Array()
	for c in presentation.get("palette", []):
		src.append(Vector3(c.r, c.g, c.b))
	_material.set_shader_parameter("src", src)


func _ready() -> void:
	get_tree().root.size_changed.connect(refit)
	refit()


func refit() -> void:
	fitted = fit(get_tree().root.size)
	stretch_shrink = fitted["scale"]
	size = Vector2(fitted["view"] * fitted["scale"])
	position = Vector2(fitted["offset"])
	_material.set_shader_parameter("scale", float(fitted["scale"]))
	_material.set_shader_parameter("offset_y", fitted["offset"].y)


# Shows a display mode by id ("" for the normal palette, which needs no
# shader) with or without CRT lines. The game owns what is shown
# (game.display_mode and game.crt, checked by game.set_display, which calls
# this); the screen keeps no copy, so the two can't drift apart.
func show_display(mode_id: String, crt_lines: bool) -> void:
	if mode_id != "":
		var dst := PackedVector3Array()
		for c in display_modes[mode_id]["colors"]:
			dst.append(Vector3(c.r, c.g, c.b))
		_material.set_shader_parameter("dst", dst)
	_material.set_shader_parameter("use_mode", mode_id != "")
	_material.set_shader_parameter("crt", crt_lines)
	material = _material if mode_id != "" or crt_lines else null


# Free reading preference, independent of cosmetic mode ownership. The root
# layer is created only when requested; default presentation stays unchanged.
func show_reading_contrast(value: bool) -> void:
	if value and reading_compositor==null:
		reading_compositor=ReadingCompositor.new(self)
		add_child(reading_compositor)
		viewport.set_meta("reading_compositor",reading_compositor)
	if reading_compositor!=null: reading_compositor.set_enabled(value)
