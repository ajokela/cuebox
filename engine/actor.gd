extends Node2D

# A crew member or NPC. Walking is deliberately stiff: the body only moves on
# each animation step, a few pixels at a time, horizontally first and then
# vertically, with no easing on the turns. A background walk holds still,
# standing, while paused says so (the player is busy or watching a cutscene).

signal arrived

const Feel = preload("res://engine/feel.gd")

const ROW_SIDE := 0
const ROW_FRONT := 1
const ROW_BACK := 2
const ROW_TALK := 3

var id := ""
var display_name := ""
var text_color := Color.WHITE
var room := ""
var height := 40
var hit_width := 16
var facing := "front"
var talking := false
var sprite: Sprite2D
var background := false  # the walk under way is a background one
var paused := Callable()  # set by the game: true while background walks hold still

var _path: Array[Vector2] = []
var _walking := false
var _frame := 0
var _clock := 0.0
var _talk_clock := 0.0
var _talk_frame := 0
var _held := false
var _manual_walking := false


# A persistent world controller may advance a discrete step itself. This
# changes only the pose; normal character walking keeps its original timing.
func scripted_step(to: Vector2, moving := true) -> void:
	var d := to-position
	if d.x!=0: facing="right" if d.x>0 else "left"
	elif d.y!=0: facing="front" if d.y>0 else "back"
	position=to
	_manual_walking=moving
	_frame=(_frame+1)%4 if moving else 0
	_refresh()


func setup(id_: String, name_: String, texture: Texture2D, color: Color, room_: String, pos: Vector2, height_: int) -> void:
	id = id_
	display_name = name_
	text_color = color
	room = room_
	position = pos
	height = height_
	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = 4
	sprite.vframes = 4
	sprite.centered = false
	sprite.offset = Vector2(-texture.get_width()/8.0, -texture.get_height()/4.0)
	add_child(sprite)
	_refresh()


func walk_to(target: Vector2) -> void:
	walk_route([target])


# Walks the waypoints in order, each one x first and then y. The array is
# untyped on purpose: typed arrays through untyped references error in 4.7.2.
# instant applies every step at once (cutscene fast-forward) and ends facing
# the way a real walk would.
func walk_route(points: Array, instant := false) -> void:
	_manual_walking = false
	background = false
	_path.clear()
	var cur := position
	for p in points:
		var t: Vector2 = (p as Vector2).round()
		if t.x != cur.x:
			_path.append(Vector2(t.x, cur.y))
		if t.y != cur.y:
			_path.append(t)
		cur = t
	if _path.is_empty():
		_stop()
		arrived.emit.call_deferred()
		return
	_walking = true
	if instant:
		while _walking:
			_step(true)


func is_walking() -> bool:
	return _walking


func face(dir: String) -> void:
	facing = dir
	_refresh()


func _process(delta: float) -> void:
	var held: bool = _walking and background and paused.is_valid() and paused.call()
	if held != _held:
		_held = held
		_refresh()
	if _walking and not held:
		_clock += delta
		while _walking and _clock >= Feel.STEP_TIME:
			_clock -= Feel.STEP_TIME
			_step()
	if talking:
		_talk_clock -= delta
		if _talk_clock <= 0.0:
			_talk_clock = randf_range(Feel.MOUTH_MIN, Feel.MOUTH_MAX)
			_talk_frame = [0, 1, 2, 1][randi() % 4]
			_refresh()
	elif _talk_frame != 0:
		_talk_frame = 0
		_refresh()


func _step(instant := false) -> void:
	var goal: Vector2 = _path[0]
	var d := goal - position
	if d.x != 0:
		facing = "right" if d.x > 0 else "left"
		position.x += clampf(d.x, -Feel.STEP_X, Feel.STEP_X)
	elif d.y != 0:
		facing = "front" if d.y > 0 else "back"
		position.y += clampf(d.y, -Feel.STEP_Y, Feel.STEP_Y)
	_frame = (_frame + 1) % 4
	if position == goal:
		_path.pop_front()
		if _path.is_empty():
			_stop()
			if instant:
				arrived.emit.call_deferred()
			else:
				arrived.emit()
	_refresh()


func _stop() -> void:
	_manual_walking = false
	_walking = false
	background = false
	_frame = 0
	_clock = 0.0
	_refresh()


func _refresh() -> void:
	if sprite == null:
		return
	var moving := (_walking and not _held) or _manual_walking
	var col := _frame if moving else 0
	sprite.flip_h = facing == "left"
	match facing:
		"left", "right":
			sprite.frame = ROW_SIDE * 4 + col
		"back":
			sprite.frame = ROW_BACK * 4 + col
		_:
			if talking and not moving:
				sprite.frame = ROW_TALK * 4 + _talk_frame
			else:
				sprite.frame = ROW_FRONT * 4 + col
