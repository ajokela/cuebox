extends RefCounted

# Every text the player sees goes through t() on its way to the screen. Lines
# are written inline, in English, and that English is the key:
# tools/extract_strings.py gathers them into string tables (i18n/common.csv
# for the engine and data, rooms/<id>/strings.csv for each room, and the same
# in the folder of an NPC's or world script that has one of its own) with a
# catalog of every text next to each table, and Godot imports each table into
# one .translation per language. register() loads the common table and the
# game's own rooms' and scripts' only, so a build without a room (or an NPC,
# or a world script) has none of its text.
#
# Engine code passes text through t() at the point it's shown; a line the
# engine writes itself is spelled I18n.t("THE LINE"), so the extractor finds it.
# In strict mode (tests on the real rooms) a text that's in no loaded catalog
# is an error: someone wrote a line the tables don't have.

const COMMON := "res://i18n/"
const LOCALES := ["en", "en_XA"]  # the string tables' columns
const LANGUAGES := [["en", "ENGLISH"], ["en_XA", "TEST"]]  # what the options offer; the test language only in debug builds

static var _languages: Array = LANGUAGES.duplicate(true)
static var _debug_locales: Array = ["en_XA"]
static var strict := false
static var missing := {}  # texts strict mode has reported (each once)
static var _known := {}  # every text in the loaded catalogs
static var _added := []  # the translations register() gave the TranslationServer


# text in the player's language, or as written if there's no translation.
static func t(text: String) -> String:
	if strict and text != "" and not _known.has(text) and not missing.has(text):
		missing[text] = true
		push_error("text not in any string table (run tools/extract_strings.py, or write it inline): \"%s\"" % text)
	return TranslationServer.translate(text)


# Loads the common strings, those of each room in rooms (id -> folder) and
# those of each script in scripts (NPC and world script paths) that has a
# folder of its own, in place of any registered before. check turns strict
# mode on or off.
static func register(rooms: Dictionary, check := false, scripts := [], common := COMMON + "common", config := {}) -> void:
	_languages = config.get("languages", LANGUAGES).duplicate(true)
	_debug_locales = config.get("debug_locales", ["en_XA"]).duplicate()
	strict = check
	missing.clear()
	for tr in _added:
		TranslationServer.remove_translation(tr)
	_added.clear()
	_known.clear()
	if common != "": _add(common, common + "_catalog.gd")
	for id in rooms:
		_add(rooms[id] + "strings", rooms[id] + "catalog.gd")
	for table in config.get("tables", []): _add(table["table"], table["catalog"])
	var done := {}
	for path in scripts:
		var folder := table_folder(path)
		if folder != "" and not done.has(folder):
			done[folder] = true
			_add(folder + "strings", folder + "catalog.gd")


# The folder whose string table holds an NPC's or world script's lines:
# its own (res://npcs/<id>/, res://world/<name>/), or "" for the common table.
static func table_folder(script_path: String) -> String:
	var dir := script_path.get_base_dir()
	if ResourceLoader.exists(dir + "/catalog.gd") or dir.begins_with("res://npcs/") or dir.begins_with("res://world/"):
		return dir + "/"
	return ""


static func _add(table: String, catalog: String) -> void:
	for language in _languages:
		var locale: String = language[0]
		var path := "%s.%s.translation" % [table, locale]
		if ResourceLoader.exists(path):
			var tr: Translation = load(path)
			TranslationServer.add_translation(tr)
			_added.append(tr)
	if ResourceLoader.exists(catalog):
		_known.merge(load(catalog).KINDS)


# The languages a build offers: [locale, name].
static func languages(debug: bool) -> Array:
	return _languages.filter(func(language): return debug or language[0] not in _debug_locales).duplicate(true)


# The language to start in: forced (--locale) if given, else the player's own
# if this build offers it, else English.
static func start_locale(forced: String, chosen: String, debug: bool) -> String:
	if forced != "":
		return forced
	return chosen if chosen in languages(debug).map(func(l): return l[0]) else str(languages(debug)[0][0])


# Mark a configuration string for extraction without translating it before
# the host catalogs and player language have been registered.
static func mark(text: String) -> String: return text
