extends Node
# Minimal host entry point. Game-specific tooling and release routes live in
# the host project, not here. Set adventure/content_provider in project.godot.
const Game = preload("res://engine/game.gd")
const Screen = preload("res://engine/screen.gd")
const Menus = preload("res://engine/menus.gd")
var game
var menus
var screen

func _ready() -> void:
	boot()

func boot(options := {}) -> void:
	screen = Screen.new()
	add_child(screen)
	game = Game.new()
	screen.viewport.add_child(game)
	screen.mouse_exited.connect(game.hover_end)
	var opts := {"screen":screen, "start":null}
	opts.merge(options,true)
	game.setup(opts)
	if game.saves.is_versioned(): get_tree().auto_accept_quit=false
	menus = Menus.new(game)
	screen.viewport.add_child(menus)
	if opts["start"] == null: menus.show_title()
