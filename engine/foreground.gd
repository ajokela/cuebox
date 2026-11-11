extends RefCounted
# Explicit product-owned continuation. The caller queues a whole candidate and
# returns before it commits. No paused coroutine owns the remaining action.
const State=preload("res://engine/state.gd")
const Cursor=preload("res://engine/reading_cursor.gd")
const Stage=preload("res://engine/foreground_stage.gd")
const Document=preload("res://engine/foreground_document.gd")
const Choices=preload("res://engine/foreground_choices.gd")
const Walkmap=preload("res://engine/walkmap.gd")
const Feel=preload("res://engine/feel.gd")
var game
var registry
var presentation
var _caption:=false
var pending=null
var manual:=false # Player preference for managed lines; isolated tests may also override it.
var choice_panel=null
var document_panel=null
var _walk_key:=""
var _epoch:=0
var _token:=-1
var _speaker:=""
var _line:=""
var _source:=""
var _locale:=""
var _gap:=-1.0
var _delay_left:=-1.0
var _reset_frame:=-1

func _init(g,path: String) -> void:
	game=g; presentation=Stage.new(self)
	if path!="": registry=load(path)
func context() -> Dictionary:
	return game.state.party.get("foreground",{}) if game.state!=null else {}
func active() -> bool: return not context().is_empty()
func holding() -> bool:
	return active() or pending!=null or (game._retry_transaction_state!=null and game._retry_transaction_state.party.has("foreground"))
func reset(cancel_waiters:=false) -> void:
	stop_presentation(); presentation.reset()
	if cancel_waiters: _epoch+=1
	if is_instance_valid(choice_panel): choice_panel.queue_free()
	if is_instance_valid(document_panel): document_panel.queue_free()
	document_panel=null
	choice_panel=null; _walk_key=""; _caption=false
	pending=null; _token=-1; _speaker=""; _line=""; _source=""; _locale=""; _gap=-1.0; _delay_left=-1.0
	_reset_frame=Engine.get_process_frames()
func queue(id: String,args: Dictionary) -> bool:
	if registry==null or active() or pending!=null or game.in_cutscene or not game.busy: return false
	game.sync_state()
	var candidate=registry.begin(game,id,args)
	if candidate==null: return false
	_epoch+=1; pending=candidate
	# Marks a handled response without inventing a transcript line.
	game._fg_events+=1
	return true
func start_world(id: String,args:={}) -> bool:
	if registry==null or holding() or game.menu_open or game.in_cutscene or not game.can_save(): return false
	game.sync_state()
	var candidate=registry.begin(game,id,args)
	if candidate==null: return false
	_epoch+=1; _commit_action(candidate)
	return true # Retry holds this authored entry, including a failed first write.
func start_pending() -> bool:
	if pending==null: return false
	var candidate=pending; pending=null
	_commit_action(candidate)
	return true # A failed transaction is still handled by the existing Retry menu.
func _commit_action(candidate) -> bool:
	if candidate==null: return false
	var effect: String=registry.sound(candidate.party["foreground"]) if candidate.party.has("foreground") else ""
	var fast: bool=candidate.party.get("foreground",{}).get("fast",false)
	var forks: Dictionary=candidate.forks.duplicate()
	var before: Dictionary=game.state.forks.duplicate()
	var after:=func():
		for fork in forks:
			if forks[fork]!=before.get(fork,""): game.decided_forks[fork+"."+forks[fork]]=true
		if effect!="":
			if fast or skipping(): game.record("sfx "+effect)
			else: game.sfx(effect)
	var retain: bool=not registry.has_method("retain_world") or registry.retain_world(context(),candidate.party.get("foreground",{}))
	var preserve_motion:=retain
	if retain and registry.has_method("places_cast") and registry.places_cast(candidate.party.get("foreground",{})):
		preserve_motion=game._can_preserve_motion(candidate)
	return game.commit_state(candidate,retain,"",after,preserve_motion)
func wait_until_settled() -> void:
	# A load/title abandons the caller's run. Retain this RefCounted owner until
	# its waiter observes cancellation, including when the Game node is freed.
	var owner=self; var epoch:=_epoch; var tree=game.get_tree()
	while is_instance_valid(owner.game) and owner._epoch==epoch and (owner.holding() or owner.game.saves.has_pending_commit()):
		# A product control now owns the continuation. The original use handler
		# has no further mutation and may return, just as a normal panel opener.
		if owner.using_controls() and owner.game.menus!=null:
			var panel=owner.game.menus.custom_panel
			if is_instance_valid(panel) and panel.has_method("foreground_runner") and panel.foreground_runner()==owner and not owner.game.saves.has_pending_commit(): return
		await tree.process_frame
func handles_retry() -> bool:
	return game._transaction_origin==game.state and game._retry_transaction_state!=null and (active() or game._retry_transaction_state.party.has("foreground"))
func cancel_retry() -> void:
	if game.saves.has_pending_commit() or not handles_retry(): return
	game._retry_transaction_state=null; game._transaction_origin=null; game._transaction_motion_origin=null; game._transaction_after=Callable(); game._transaction_context=""
	reset() # Re-present the previous committed passage, or leave its untouched source available.
func restore_presentation(reconstruct:=false) -> void: presentation.present(reconstruct)
func restore_reading() -> void:
	if is_instance_valid(document_panel): document_panel.restore_cursor()
	# A retried page/Skip write belongs to this same displayed line. Keep its
	# token and stage clock; only move to an acknowledged source offset.
	if _token<0 or not _current(): return
	var entry:=_entry(); var anchor:=Cursor.anchor(context()["reading"],_line,_source,_locale)
	var offset: int=anchor.get("offset",0) if anchor.get("id","")=="body" else 0
	if offset!=entry.get("anchor",0):
		entry["anchor"]=offset; entry["layout_key"]=[]; entry.erase("skipped")
		game.speech.configure(game.room,game._world_offset(),game.view_w(),game.speech_reserved(),false)
func blacked_out() -> bool: return presentation.blacked_out()
func stop_presentation() -> void:
	if _caption: game.speech.stop_caption(_token)
	elif _speaker!="": game.speech.stop(_speaker,_token)
func _current() -> bool: return game.speech.caption_is(_token) if _caption else game.speech.is_current(_speaker,_token)
func _entry() -> Dictionary: return game.speech.caption if _caption else game.speech.lines.get(_speaker,{})
func _record_voice(voice: Dictionary) -> void:
	game.record("caption "+voice["text"] if voice.get("caption",false) else "say %s: %s" % [voice["speaker"],voice["text"]])
func _voice() -> Dictionary: return registry.voice(game,context())
func _source_text(voice: Dictionary) -> String: return JSON.stringify([voice["speaker"],voice["text"],voice.get("source",{})])
func _show(record_line:=true) -> void:
	var c:=context(); var voice:=_voice()
	_caption=voice.get("caption",false)
	_speaker=voice["speaker"]; _line=c["reading"]["line"]; _source=_source_text(voice); _locale=TranslationServer.get_locale()
	if record_line: _record_voice(voice)
	var source: Dictionary=voice.get("source",{}).duplicate(true); source["name"]=game.speaker_label(_speaker)
	_token=game.speech.start_caption(voice["text"]) if _caption else game.speech.start(game.actor(_speaker),voice["text"],true,source)
	var entry: Dictionary=_entry()
	entry["managed"]=true
	var anchor:=Cursor.anchor(c["reading"],_line,_source,_locale)
	entry["anchor"]=anchor.get("offset",0) if anchor.get("id","")=="body" else 0
	game.speech.configure(game.room,game._world_offset(),game.view_w(),game.speech_reserved(),false)
	_gap=-1.0
func _page(entry: Dictionary,offset: int) -> bool:
	return commit_reading({"id":"body","offset":offset},_source)
func commit_reading(position: Dictionary,source: String) -> bool:
	var next=State._from_snapshot(game.state.get_script(),game.state.snapshot())
	next.party["foreground"]["reading"]=Cursor.at(registry.line(context()),position,source,TranslationServer.get_locale())
	return game.commit_state(next,true,"foreground")
func _advance(entry: Dictionary) -> void:
	var reading: Dictionary=entry.get("reading",{})
	if not reading.is_empty() and entry["page"]+1<reading["pages"].size():
		var offset: int=reading["pages"][entry["page"]+1]["start"]
		if _page(entry,offset): game.speech._next_page(entry)
		return
	stop_presentation(); _gap=0.0
func using_controls() -> bool:
	return active() and registry!=null and registry.has_method("controls") and registry.controls(context())
func reading_document() -> bool:
	return active() and registry!=null and registry.has_method("document") and not registry.document(game,context()).is_empty()
func document():
	if document_panel==null:
		document_panel=Document.new(self); game.add_child(document_panel)
	return document_panel
func choosing() -> bool:
	return active() and registry!=null and registry.has_method("choices") and not registry.choices(game,context()).is_empty()
func choices():
	if choice_panel==null:
		choice_panel=Choices.new(self); game.add_child(choice_panel)
	return choice_panel
func select(id: String) -> bool:
	if not choosing() or game.menu_open or game.saves.has_pending_commit(): return false
	return _commit_action(registry.select(game,id))
func cinematic() -> bool:
	return active() and registry!=null and registry.has_method("cinematic") and registry.cinematic(context())
func skipping() -> bool: return cinematic() and context().get("fast",false)
func can_skip() -> bool: return cinematic() and not skipping()
func skip() -> void:
	if not can_skip(): return
	game.sync_state()
	var next=State._from_snapshot(game.state.get_script(),game.state.snapshot())
	next.party["foreground"]["fast"]=true
	game.commit_state(next,true,"foreground")
func _next() -> void:
	game.sync_state()
	_commit_action(registry.advance(game))
func _move() -> bool:
	var moves: Array=[]
	if registry.has_method("movements"): moves=registry.movements(context())
	elif registry.has_method("movement"):
		var move: Dictionary=registry.movement(context())
		if not move.is_empty(): moves.append(move)
	if moves.is_empty(): return false
	var moving: Array=moves.map(func(move):return game.actor(move["who"]))
	var key: String=registry.line(context())
	if _walk_key!=key or (skipping() and moving.any(func(actor):return actor.is_walking())):
		_walk_key=key
		for i in moves.size():
			var actor=moving[i]
			actor.walk_route(Walkmap.route(game.room_geo(actor.room)["walk_boxes"],actor.position,moves[i]["target"]),game.test_turbo or skipping())
	# A shared beat arrives only when every real actor reaches its target.
	# Their ordinary positions are saved, so a load resumes the remaining paths.
	if moving.all(func(actor):return not actor.is_walking()): _next()
	return true
func tick(delta: float) -> void:
	if not active() or registry==null or game.menu_open or game.saves.has_pending_commit() or game.busy: return
	if Engine.get_process_frames()<=_reset_frame: return
	presentation.tick(delta)
	if using_controls():
		game.menus.show_panel(registry.control_panel(game,context())); return
	if reading_document(): document(); return
	if choosing():
		choices()
		for option in registry.choices(game,context()): game.offered_options[option["key"]]=true
		if game.test_mode and not game.auto_answers.is_empty():
			var answer: String=game.auto_answers.pop_front()
			if not select(answer): push_error("choose(talk): answer not offered: "+answer)
		return
	if _move(): return
	if skipping() and not registry.silent(context()):
		if _token<0:
			_record_voice(_voice())
		else: stop_presentation()
		_next(); return
	if _gap>=0.0:
		_gap+=delta
		if game.test_turbo or _gap>=Feel.SPEECH_GAP:
			_next()
		return
	if _delay_left<0.0: _delay_left=registry.delay(context())
	if _delay_left>0.0:
		_delay_left=0.0 if game.test_turbo or (skipping() and registry.delay(context())==0.0) else maxf(0.0,_delay_left-delta)
		if _delay_left>0.0: return
	if registry.silent(context()):
		_next(); return
	if _token<0 or not _current(): _show()
	elif _locale!=TranslationServer.get_locale() or _source!=_source_text(_voice()):
		stop_presentation(); _show(false)
	var entry: Dictionary=_entry()
	if not manual: entry["left"]-=delta
	if entry.get("skipped",false) or (not manual and (game.test_turbo or entry["left"]<=0.0)): _advance(entry)
func tap(p: Vector2) -> bool:
	if not active(): return false
	if reading_document(): document().tap(p); return true
	if choosing(): choices().tap(p); return true
	if game.hud.menu_rect(game.view_w()).has_point(p):
		game.hud_tapped.emit("menu") # The menu owns consumption of its opening tap.
	elif can_skip() and game.hud.foreground_skip_rect(game.view_w()).has_point(p):
		if game.consume_reading_input(): skip()
	elif game.consume_reading_input() and _gap<0.0: game.speech.skip()
	return true
func key(code: int) -> bool:
	if not active(): return false
	if reading_document(): return document().key(code)
	if choosing(): return choices().key(code)
	if code==KEY_ESCAPE:
		if game.consume_reading_input():
			if can_skip(): skip()
			elif game.menus!=null: game.menus.open("pause")
		return true
	if code not in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]: return false
	if game.consume_reading_input() and _gap<0.0: game.speech.skip()
	return true
