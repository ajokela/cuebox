extends "res://engine/room_script.gd"
func use_drawer(who: String, _item: String) -> void:
	if flag("fuse_taken"):
		await say(who,"THE DRAWER IS EMPTY.")
	else:
		set_flag("fuse_taken")
		await pick_up(who,"fuse")
func use_radio(who: String, item: String) -> void:
	if flag("radio_ready"):
		await say(who,"THE RADIO IS READY. THE BEACON ON THE ROOF NEEDS A SIGNAL.")
	elif item=="fuse":
		take(who,item)
		set_flag("radio_ready")
		await say(who,"THAT DID IT. NOW TO THE BEACON ON THE ROOF.")
	else:
		await say(who,"THE RADIO HAS A BLOWN FUSE. THERE MAY BE A SPARE IN THE DRAWER.")
func use_door(_who: String, _item: String) -> void:
	await go("roof","stairs")
