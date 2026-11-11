extends RefCounted

# Walk boxes: a room's floor is a set of Rect2i. A point is walkable if some
# box contains it. Boxes connect only when they overlap by at least 1 px on
# both axes (Rect2i.intersects); boxes that merely touch stay separate.


static func walkable(boxes: Array, p: Vector2) -> bool:
	var q := Vector2i(p.round())
	for b: Rect2i in boxes:
		if b.has_point(q):
			return true
	return false


# The nearest integer point inside one box (right and bottom edges excluded).
static func _clamp_into(b: Rect2i, p: Vector2) -> Vector2:
	var e := b.end
	return Vector2(clampi(int(p.x), b.position.x, e.x - 1), clampi(int(p.y), b.position.y, e.y - 1))


static func _nearest_index(boxes: Array, p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in boxes.size():
		var d := p.distance_squared_to(_clamp_into(boxes[i], p))
		if d < best_d:
			best_d = d
			best = i
	return best


static func _containing_index(boxes: Array, p: Vector2) -> int:
	var q := Vector2i(p.round())
	for i in boxes.size():
		if (boxes[i] as Rect2i).has_point(q):
			return i
	return -1


# Indices of the boxes connected (directly or not) to the box holding p, in
# ascending order. Off the floor, the nearest box stands in.
static func _component_indices(boxes: Array, p: Vector2) -> Array:
	if boxes.is_empty():
		return []
	p = p.round()
	var start := _containing_index(boxes, p)
	if start < 0:
		start = _nearest_index(boxes, p)
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j in boxes.size():
			if not seen.has(j) and (boxes[i] as Rect2i).intersects(boxes[j]):
				seen[j] = true
				queue.append(j)
	var out := seen.keys()
	out.sort()
	return out


static func component(boxes: Array, p: Vector2) -> Array:
	var out := []
	for i in _component_indices(boxes, p):
		out.append(boxes[i])
	return out


static func clamp_point(boxes: Array, p: Vector2) -> Vector2:
	p = p.round()
	if boxes.is_empty():
		return p
	if walkable(boxes, p):
		return p
	return _clamp_into(boxes[_nearest_index(boxes, p)], p)


# The far left or far right of the floor connected to near, whichever is
# nearer to it (the left on a tie), at near's height and clamped onto the
# floor. NPCs walk in and out of a watched room there.
static func edge(boxes: Array, near: Vector2) -> Vector2:
	var comp := component(boxes, near)
	if comp.is_empty():
		return near.round()
	var lo: int = comp[0].position.x
	var hi: int = comp[0].end.x - 1
	for b: Rect2i in comp:
		lo = mini(lo, b.position.x)
		hi = maxi(hi, b.end.x - 1)
	var x := lo if near.x - lo <= hi - near.x else hi
	return clamp_point(comp, Vector2(x, near.y))


static func route(boxes: Array, from: Vector2, to: Vector2) -> Array:
	from = from.round()
	var comp := component(boxes, from)
	if comp.is_empty():
		return [to.round()]
	var goal := clamp_point(comp, to)
	for b: Rect2i in comp:
		if b.has_point(Vector2i(from)) and b.has_point(Vector2i(goal)):
			return [goal]
	var start := _containing_index(comp, from)
	if start < 0:
		start = _nearest_index(comp, from)
	var finish := _containing_index(comp, goal)
	if start == finish:
		return [goal]
	# Breadth-first search over connections; lowest index first keeps it stable.
	var prev := {start: -1}
	var queue := [start]
	while not queue.is_empty() and not prev.has(finish):
		var i: int = queue.pop_front()
		for j in comp.size():
			if not prev.has(j) and (comp[i] as Rect2i).intersects(comp[j]):
				prev[j] = i
				queue.append(j)
	var chain := []
	var k := finish
	while k != -1:
		chain.push_front(k)
		k = prev[k]
	var points := []
	var cur := from
	for n in range(1, chain.size()):
		var overlap: Rect2i = (comp[chain[n - 1]] as Rect2i).intersection(comp[chain[n]])
		cur = _clamp_into(overlap, cur)
		points.append(cur)
	points.append(goal)
	return points
