extends SceneTree
# Two-process integration check. Uses only the shipped runtime's public action
# methods and menu rows, under a dedicated test save directory.
class TestBoot:
	extends "res://engine/bootstrap.gd"
	func _ready() -> void: pass
var host
var errors: Array=[]
class ErrorCapture extends Logger:
	var messages: Array=[]
	func _log_error(_function: String,_file: String,_line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array) -> void:
		if kind!=ERROR_TYPE_WARNING: messages.append(rationale if rationale!="" else code)
var capture=ErrorCapture.new()
var root_path: String
var screenshots:=false
func _initialize() -> void:
	OS.add_logger(capture)
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: errors.append(label)
func frame(label: String) -> void:
	if not screenshots: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(root_path+label+".png")
func _run() -> void:
	var args=OS.get_cmdline_user_args()
	root_path=""
	for arg in args:
		if arg.begins_with("--proof-root="): root_path=arg.trim_prefix("--proof-root=")
	screenshots="--capture" in args
	if not root_path.begins_with("user://engine-proof/") or ".." in root_path or not root_path.ends_with("/"):
		printerr("Supply --proof-root=user://engine-proof/<unique-run>/"); quit(2); return
	DirAccess.make_dir_recursive_absolute(root_path)
	root.size=Vector2i(1280,720)
	host=TestBoot.new();root.add_child(host)
	host.boot({"test_mode":true,"test_turbo":true,"user_root":root_path,"autosave":true})
	var game=host.game
	var menus=host.menus
	check(menus._title_texts()==["THE LAST SIGNAL"],"host title")
	check(game.display_modes.is_empty(),"no inherited cosmetic products")
	check(game.telemetry==null,"no analytics")
	await frame("01-title")
	if "--reload" in args:
		check(menus.pick("CONTINUE"),"cold Continue row")
		await process_frame
		check(game.room=="roof" and game.state.flag("radio_ready")==true,"cold room and puzzle state")
		check(game.state.inventory["rae"].is_empty(),"consumed fuse stays consumed")
		await frame("04-cold-roof")
		await game.use("beacon")
		check(game.state.flag("signal_sent")==true,"ending earned")
		check(menus.page=="demo_end" and menus.demo_end_texts()==["SIGNAL RESTORED","THANKS FOR PLAYING"],"custom completion card")
		await frame("05-ending")
		check(menus.pick("BACK TO TITLE"),"ending exit")
	else:
		check(not game.saves.exists("auto"),"fresh isolated run")
		check(menus.pick("NEW GAME"),"New Game row")
		await process_frame
		check(game.room=="shack","new-game room")
		await game.use("radio")
		check(game.state.flag("radio_ready")==false,"requires fuse")
		await game.use("drawer")
		check(game.state.inventory["rae"]==["fuse"],"inventory pickup")
		await frame("02-fuse")
		await game.use("door")
		check(game.room=="roof","named room transition")
		await game.use("beacon")
		check(game.state.flag("signal_sent")==false,"cannot skip radio puzzle")
		await game.use("stairs")
		check(game.room=="shack","return route")
		await game.use("radio","fuse")
		check(game.state.flag("radio_ready")==true and game.state.inventory["rae"].is_empty(),"item use")
		await game.use("door")
		check(game.autosave_now(),"acknowledged autosave")
		await frame("03-roof-ready")
	await process_frame
	errors.append_array(capture.messages)
	var report={"pass":errors.is_empty(),"reload":"--reload" in args,"errors":errors,"room":game.room,"title":menus._title_texts()}
	var file=FileAccess.open(root_path+("reload" if "--reload" in args else "play")+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	OS.remove_logger(capture)
	print(JSON.stringify(report))
	host.queue_free();await process_frame
	quit(0 if errors.is_empty() else 1)
