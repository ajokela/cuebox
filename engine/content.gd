extends RefCounted
# The host project supplies a provider with static options() through this
# setting. The runtime never guesses a game's resource paths or cast.
const PROVIDER_SETTING := "adventure/content_provider"

static func defaults() -> Dictionary:
	return {"rooms":{}, "crew":{}, "roster":[], "npcs":{}, "items":{},
		"world":[], "room_scripts":{}, "items_script":"res://engine/script_base.gd",
		"common_strings":"", "presentation":{}, "foreground_handlers":[]}

static func options() -> Dictionary:
	var out := defaults()
	var path: String = ProjectSettings.get_setting(PROVIDER_SETTING, "")
	if path != "":
		var provider = load(path)
		if provider == null or not provider.has_method("options"):
			push_error("adventure/content_provider must implement static options()")
			return out
		out.merge(provider.options(), true)
	return out
