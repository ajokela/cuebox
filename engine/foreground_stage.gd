extends RefCounted
# Product-owned cutaway presentation. No room or story IDs live here.
const Feel=preload("res://engine/feel.gd")
var _owner: WeakRef
var _key:=""
var _figure=null
var elapsed:=0.0
func _init(runner) -> void: _owner=weakref(runner)
func descriptor() -> Dictionary:
	var runner=_owner.get_ref()
	if runner==null or not is_instance_valid(runner.game) or not runner.active() or runner.registry==null or not runner.registry.has_method("stage"): return {}
	return runner.registry.stage(runner.context())
func reset() -> void:
	if is_instance_valid(_figure) and is_instance_valid(_figure.sprite): _figure.sprite.position.x=0
	_figure=null; _key=""; elapsed=0.0
func blacked_out() -> bool: return descriptor().get("black",false)
func present(reconstruct:=false) -> void:
	var stage:=descriptor()
	if stage.is_empty(): return
	var runner=_owner.get_ref(); var game=runner.game
	var key: String=runner.registry.line(runner.context())
	var changed:=key!=_key
	if changed: reset(); _key=key
	var target: String=stage["room"]
	if game.room!=target:
		game._enter_room(target,not reconstruct,false)
	if changed and stage.get("black",false): game.audio.stop_music()
	# Fast-forward can span storage acknowledgements. Do not let a temporary
	# away-room tune start while a skipped scene is waiting for the next write.
	if changed and runner.skipping() and target!=game.state.actors[game.state.active]["room"]:
		game.audio.stop_music()
	var who: String=stage.get("jiggle","")
	if who!="": _figure=game.actor(who)
func tick(delta: float) -> void:
	present()
	elapsed+=delta
	if not is_instance_valid(_figure): return
	var runner=_owner.get_ref()
	var index:=floori(elapsed/Feel.JIGGLE_STEP)
	_figure.sprite.position.x=0 if runner.game.reduced_effects() or runner.skipping() or index>=Feel.JIGGLE.size() else Feel.JIGGLE[index]
