extends RefCounted

# The rooms' pictures: background, props and the effects layer, the actor
# nodes, and the texture cache. Each room's view is made the first time it's
# shown, and each actor's node the first time it's needed; after that they're
# only hidden or shown, never freed (in 4.7.2 a coroutine awaiting a freed node
# hangs its callers silently). The game calls refresh_props() every frame so
# props follow the room script's prop_states().

const Actor = preload("res://engine/actor.gd")

var _parent: Node2D  # the camera-shifted layer the views live in
var _views := {}  # room id -> node, props, background fx and actor-front effects
var _textures := {}
var _room := ""
var _geo: Dictionary = {}
var _script
var _prop_state := {}  # prop id -> the state applied in the shown room


func _init(parent: Node2D) -> void:
	_parent = parent


# Shows a room (making its view the first time) and hides the rest. Prop
# states are re-applied from scratch on the next refresh_props().
func show(id: String, geo: Dictionary, script) -> void:
	for v in _views:
		_views[v]["node"].visible = false
	_room = id
	_geo = geo
	_script = script
	_prop_state = {}
	_view(id)["node"].visible = true


# Hides every room and lets the shown room's script go (the title screen).
func hide_all() -> void:
	for v in _views:
		_views[v]["node"].visible = false
	_script = null


# Applies prop_states(): a changed state swaps the texture; "" hides the prop.
# Props the script doesn't mention show their first state.
func refresh_props() -> void:
	var want: Dictionary = _script.prop_states()
	var sprites: Dictionary = _views[_room]["props"]
	for p in _geo["props"]:
		var states: Dictionary = p["states"]
		var st = want.get(p["id"], states.keys()[0] if not states.is_empty() else "")
		if _prop_state.has(p["id"]) and _prop_state[p["id"]] == st:
			continue
		_prop_state[p["id"]] = st
		var s: Sprite2D = sprites[p["id"]]
		if st == "":
			s.visible = false
		elif not states.has(st):
			push_error("prop %s has no state %s" % [p["id"], st])
			s.visible = false
		else:
			s.texture = texture(states[st])
			s.visible = s.texture != null


# A hotspot linked to a prop is disabled while that prop's state is "".
func hotspot_enabled(h: Dictionary) -> bool:
	var prop: String = h.get("prop", "")
	return prop == "" or _prop_state.get(prop, null) != ""


# A new actor node in the camera-shifted layer, at data's start. data is a
# crew or NPC entry: "name", "sheet", "color", "height", "start". The game
# makes each one once (crew at setup, an NPC when its room is first shown).
func make_actor(id: String, data: Dictionary) -> Node2D:
	var a: Node2D = Actor.new()
	a.setup(id, data["name"], texture(data["sheet"]), data["color"], data["start"]["room"], data["start"]["pos"], data["height"])
	a.hit_width = data.get("hit_width",16)
	_parent.add_child(a)
	return a


func prop_node(prop_id: String) -> Sprite2D:
	return _views[_room]["props"].get(prop_id)


func redraw_fx() -> void:
	_views[_room]["fx"].queue_redraw()
	_views[_room]["front"].queue_redraw()


func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


func _view(id: String) -> Dictionary:
	if _views.has(id):
		return _views[id]
	var node := Node2D.new()
	node.name = "room_" + id
	_parent.add_child(node)
	var bg := Sprite2D.new()
	bg.centered = false
	bg.z_index = -100
	bg.texture = texture(_geo["bg"])
	node.add_child(bg)
	var props := {}
	for p in _geo["props"]:
		var s := Sprite2D.new()
		s.centered = false
		s.position = p["pos"]
		s.z_index = p["z"]
		s.visible = false
		node.add_child(s)
		props[p["id"]] = s
	var fx := Node2D.new()
	fx.z_index = -50
	node.add_child(fx)  # after the props, so effects draw over a prop at the same z
	fx.draw.connect(_draw_fx.bind(id, fx))
	var front:=Node2D.new()
	front.z_index=500
	node.add_child(front)
	front.draw.connect(_draw_front.bind(id,front))
	_views[id] = {"node": node, "props": props, "fx": fx, "front":front}
	return _views[id]


func _draw_fx(id: String, fx: Node2D) -> void:
	if id == _room and _script != null:
		_script.draw_fx(fx)


func _draw_front(id: String, front: Node2D) -> void:
	if id == _room and _script != null:
		_script.draw_front(front)
