extends RefCounted
# Public cards wait for the action that requested them to finish. Ending IDs
# are product-owned; no private story or ending table belongs in this adapter.
var game
func _init(game_) -> void: game=game_
func request(id: String) -> bool:
	if game.state==null: return false
	var page: String
	match id:
		"complete": page="demo_end"
		"prologue":
			if not game.web or game.demo or game.state.flag(game.prologue_end_beat)!=true: return false
			page="prologue_end"
		"legacy_demo":
			if not game.demo or game.web or game.entry_flow!=null: return false
			page="demo_end"
		_: return false
	if game.menus!=null and game.menus.page==page: return true
	return game._queue_product_end(page)
