extends Node

const PATH := "user://pong_online_settings.cfg"
var _locale := ""

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		var saved := str(config.get_value("ui", "locale", ""))
		if saved in ["en", "zh-CN"]:
			_locale = saved

## Returns the player's saved language, or "" if none was chosen yet (I18n then auto-detects).
func get_locale() -> String:
	return _locale

func set_locale(locale: String) -> void:
	if locale not in ["en", "zh-CN"]:
		return
	_locale = locale
	var config := ConfigFile.new()
	config.set_value("ui", "locale", locale)
	if config.save(PATH) != OK:
		push_warning("Language preference could not be saved; it remains active for this session.")
