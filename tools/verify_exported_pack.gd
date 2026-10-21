extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "Multiplayer Paddle Game", "exported identity")
	for path: String in [
		"res://scenes/main.tscn",
		"res://scripts/main.gd",
		"res://scripts/game/pong_board.gd",
		"res://scripts/game/local_paddle.gd",
		"res://scripts/net/protocol.gd",
	]:
		_check(ResourceLoader.exists(path), "pack resource: " + path)
	for path: String in [
		"res://assets/template/environment/backdrop.png",
		"res://assets/template/characters/runner.png",
		"res://assets/template/powerups/energy.png",
		"res://assets/template/ui/title_glass.png",
		"res://test/test_suite.tscn",
		"res://tools/capture_native.gd",
		"res://server/authoritative_server.mjs",
	]:
		_check(not ResourceLoader.exists(path), "excluded resource: " + path)
	# The isolated pack has no saved language, so pin English before asserting English copy.
	root.get_node("I18n").call("set_locale", "en")
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "exported main scene")
	if packed != null:
		var main := packed.instantiate()
		root.add_child(main)
		await process_frame
		main.debug_apply_snapshot({
			"type": "state", "seq": 9, "phase": "live", "role": "right",
			"ball": {"x": 0.4, "y": 0.6},
			"paddles": {"left": {"y": 0.3}, "right": {"y": 0.7}},
			"score": {"left": 2, "right": 5},
			"event": {"seq": 3, "kind": "score"},
		})
		await process_frame
		_check((main.get("_score_label") as Label).text == "2   5", "authoritative score renders")
		_check("LIVE" in (main.get("_status_label") as Label).text, "connection state renders")
		var board_state: Dictionary = (main.get("_board") as PongBoard).get_debug_state()
		_check(board_state.ball == Vector2(0.4, 0.6), "server ball renders")
		var audio := root.get_node("AudioDirector")
		audio.call("unlock_audio")
		_check(bool(audio.call("play_music", "music.gameplay")), "procedural BGM available")
		_check(bool(audio.call("play_cue", "score.reward")), "procedural SFX available")
		audio.call("release_streams")
		main.queue_free()
		await process_frame
	if _failures.is_empty():
		print("[exported-pack] PASS: Pong identity, authority snapshot, procedural audio, exclusions")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[exported-pack] " + failure)
		quit(1)


func _check(condition: bool, context: String) -> void:
	if not condition and context not in _failures:
		_failures.append(context)
