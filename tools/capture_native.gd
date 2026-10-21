extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var capture_path := OS.get_environment("PONG_CAPTURE_PATH")
	if capture_path.is_empty():
		capture_path = OS.get_environment("GENERIC2D_CAPTURE_PATH")
	if capture_path.is_empty():
		push_error("PONG_CAPTURE_PATH must name an output PNG")
		quit(1)
		return
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	if OS.get_environment("PONG_CAPTURE_LOCALE") == "zh-CN":
		root.get_node("I18n").call("set_locale", "zh-CN")
	if OS.get_environment("PONG_CAPTURE_MODE") != "title":
		main.debug_apply_snapshot({
		"type": "state", "seq": 42, "phase": "live", "role": "left",
		"ball": {"x": 0.58, "y": 0.42},
		"paddles": {"left": {"y": 0.36}, "right": {"y": 0.64}},
		"score": {"left": 4, "right": 3},
		"event": {"seq": 5, "kind": "paddle"},
		})
	for _frame: int in 12:
		await process_frame
	await create_timer(0.2).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png(capture_path)
	print("[capture] %s (%s)" % [capture_path, error_string(error)])
	root.get_node("AudioDirector").call("release_streams")
	await process_frame
	quit(0 if error == OK else 1)
