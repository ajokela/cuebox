extends Node
# Presentation-only candidate for Screen's final UI.
# Original input owners stay in the game viewport. Selected reading painters
# receive a separate CanvasItem in the root viewport, after Screen's shader.
# Default presentation does not route through this class.

class Surface extends Node2D:
	var source: WeakRef
	var paint: Callable
	var active:=false
	var touched: int=-1
	var order: int=0
	func _init() -> void:
		set_meta("reading_contrast_surface",true)
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		if active and source.get_ref()!=null and paint.is_valid(): paint.call(self)

var screen
var enabled:=false
var layer: CanvasLayer
var placement: Node2D
var clip: Control
var _sources:={}
var _order:=0

func _init(owner) -> void:
	screen=owner

func _ready() -> void:
	layer=CanvasLayer.new()
	layer.layer=1
	layer.custom_viewport=screen.get_viewport()
	add_child(layer)
	placement=Node2D.new(); layer.add_child(placement)
	clip=Control.new()
	clip.clip_contents=true
	clip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip.focus_mode=Control.FOCUS_NONE
	clip.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	placement.add_child(clip)
	refit()

func refit() -> void:
	if placement==null or screen.fitted.is_empty(): return
	var factor:=float(screen.fitted["scale"])
	placement.transform=screen.get_global_transform()*Transform2D(0,Vector2(factor,factor),0,Vector2.ZERO)
	clip.size=Vector2(screen.fitted["view"])

func set_enabled(value: bool) -> void:
	if enabled==value: return
	enabled=value
	_invalidate(screen.viewport)
	for record in _sources.values():
		var source=record["source"].get_ref()
		if source!=null: source.queue_redraw()
		for surface in record["surfaces"].values():
			surface.active=false; surface.visible=false; surface.paint=Callable()

func _invalidate(owner: Node) -> void:
	if owner is CanvasItem: owner.queue_redraw()
	for child in owner.get_children(): _invalidate(child)

# Each painter accepts its target CanvasItem as the first argument. Bound
# arguments retain the same source/layout and never contain an input action.
func stage(source: CanvasItem,key: String,paint: Callable) -> bool:
	if not enabled or not source.is_inside_tree() or source.get_viewport()!=screen.viewport: return false
	var id:=source.get_instance_id()
	if not _sources.has(id):
		_sources[id]={"source":weakref(source),"surfaces":{}}
		# Godot emits draw before the virtual _draw, and may have existing
		# signal painters. Keep painters touched earlier in this same draw;
		# clear old painters so an empty redraw cannot leave stale UI behind.
		source.draw.connect(_source_redraw.bind(id))
		source.tree_exiting.connect(_source_exiting.bind(id),CONNECT_ONE_SHOT)
	var record: Dictionary=_sources[id]
	if not record["surfaces"].has(key):
		var added:=Surface.new(); added.source=weakref(source)
		clip.add_child(added); record["surfaces"][key]=added
	var surface: Surface=record["surfaces"][key]
	surface.paint=paint; surface.active=true
	surface.touched=Engine.get_process_frames(); surface.order=_order; _order+=1
	_refresh(source,surface)
	_sort()
	surface.queue_redraw()
	return true

func _source_redraw(id: int) -> void:
	if not _sources.has(id): return
	for surface in _sources[id]["surfaces"].values():
		if surface.touched!=Engine.get_process_frames():
			surface.active=false; surface.visible=false; surface.paint=Callable()

func _source_exiting(id: int) -> void:
	if not _sources.has(id): return
	for surface in _sources[id]["surfaces"].values():
		surface.visible=false; surface.paint=Callable(); surface.queue_free()
	_sources.erase(id)

func _refresh(source: CanvasItem,surface: Surface) -> void:
	surface.visible=enabled and surface.active and source.is_visible_in_tree()
	surface.transform=source.get_global_transform_with_canvas()
	surface.z_index=_effective_z(source)

func _effective_z(source: CanvasItem) -> int:
	# Match CanvasItem's parent rule through its public GDScript API.
	var parent: CanvasItem=null if source.is_set_as_top_level() else source.get_parent() as CanvasItem
	return clampi(source.z_index+(_effective_z(parent) if source.z_as_relative and parent!=null else 0),RenderingServer.CANVAS_ITEM_Z_MIN,RenderingServer.CANVAS_ITEM_Z_MAX)

func _sort() -> void:
	var surfaces:=[]
	for record in _sources.values(): surfaces.append_array(record["surfaces"].values())
	surfaces.sort_custom(func(a,b):
		var left=a.source.get_ref(); var right=b.source.get_ref()
		if left==right: return a.order<b.order
		return right.is_greater_than(left))
	for i in surfaces.size(): clip.move_child(surfaces[i],i)

func _process(_delta: float) -> void:
	refit()
	for record in _sources.values():
		var source=record["source"].get_ref()
		if source==null: continue
		for surface in record["surfaces"].values(): _refresh(source,surface)
	_sort()

func _exit_tree() -> void:
	for record in _sources.values():
		var source=record["source"].get_ref()
		if source!=null:
			var id: int=source.get_instance_id()
			if source.draw.is_connected(_source_redraw.bind(id)): source.draw.disconnect(_source_redraw.bind(id))
			if source.tree_exiting.is_connected(_source_exiting.bind(id)): source.tree_exiting.disconnect(_source_exiting.bind(id))
	_sources.clear()
