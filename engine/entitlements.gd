extends RefCounted

# Optional cosmetic entitlement IDs supplied by the host. Empty IDs are free.
# Debug grants are isolated under this project's user directory.

var _owned := {}


# own: the ids from --own=. debug: whether those and dev_owned.txt count.
func _init(user_root := "user://", own := [], debug := OS.is_debug_build()) -> void:
	if not debug:
		return
	for id in own:
		grant(id)
	var path := user_root.path_join("dev_owned.txt")
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			if line.strip_edges() != "":
				grant(line.strip_edges())


func owns(extra: String) -> bool:
	return extra == "" or _owned.has(extra)


func grant(extra: String) -> void:
	_owned[extra] = true
