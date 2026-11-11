extends "res://engine/room_script.gd"
func use_stairs(_who: String, _item: String) -> void:
	await go("shack","door")
func use_beacon(who: String, _item: String) -> void:
	if not flag("radio_ready"):
		await say(who,"THE BEACON NEEDS THE RADIO DOWNSTAIRS.")
	else:
		set_flag("signal_sent")
		await say(who,"THE VALLEY CAN HEAR US AGAIN.")
		game.end_game("complete")
func draw_fx(ci: CanvasItem) -> void:
	if flag("signal_sent"): ci.draw_circle(Vector2(240,45),8,Color("e4c458"))
