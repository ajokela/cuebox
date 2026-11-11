extends RefCounted

# The lurching camera. It only moves once the walker leaves the middle 30-70%
# of the view, then jumps CAM_STEP pixels per tick until they are roughly
# centred again. All values are whole pixels.

const Feel = preload("res://engine/feel.gd")


# The x the camera is heading for, kept until the walker nears an edge.
static func retarget(cam_target: int, walker_x: int, cam_x: int, view_w: int, room_w: int) -> int:
	var on_screen := walker_x - cam_x
	if on_screen < view_w * Feel.CAM_EDGE_LO or on_screen > view_w * Feel.CAM_EDGE_HI:
		cam_target = snappedi(walker_x - view_w / 2, Feel.CAM_STEP)
	return clampi(cam_target, 0, maxi(0, room_w - view_w))


# One tick: a single jump toward the target, never past it.
static func step(cam_x: int, cam_target: int) -> int:
	if cam_x < cam_target:
		return mini(cam_x + Feel.CAM_STEP, cam_target)
	if cam_x > cam_target:
		return maxi(cam_x - Feel.CAM_STEP, cam_target)
	return cam_x


# Centred on the walker at once (room entry, crew switch).
static func snap(walker_x: int, view_w: int, room_w: int) -> int:
	return clampi(snappedi(walker_x - view_w / 2, Feel.CAM_STEP), 0, maxi(0, room_w - view_w))
