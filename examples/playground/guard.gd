extends RefCounted
# The check every loop in a visitor's code makes (loops.gd puts it there). The game and the page share
# one browser thread, so a loop that never lets a frame finish would freeze the page too, editor and
# all. A loop may run as long as it likes across frames; inside one frame it gets LIMIT_MS, then it
# and every later loop end and host.gd stops the game and names the loop.
const LIMIT_MS := 2000
static var tripped := false
static var where: Array = []  # [file, line] of the loop that ran too long
static var _frame := -1
static var _since := 0

static func reset() -> void:
	tripped = false
	where = []
	_frame = -1

# True while the loop may go round again.
static func ok(file: String, line: int) -> bool:
	if tripped: return false
	var frame := Engine.get_process_frames()
	var now := Time.get_ticks_msec()
	if frame != _frame:
		_frame = frame
		_since = now
		return true
	if now - _since < LIMIT_MS: return true
	tripped = true
	where = [file, line]
	return false
