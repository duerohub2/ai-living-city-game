extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_game")
	var started := Time.get_ticks_msec()
	var role := ""
	var score := ""
	var reconnected := false
	var reconnect_started := false
	var response_ms := -1
	var modal_snapshots := 0
	while Time.get_ticks_msec() - started < 15000:
		await process_frame
		if not main.get("_has_welcome"):
			continue
		var current_role := str(main.get("_role"))
		if current_role not in ["left", "right"]:
			continue
		if role.is_empty():
			if main.get("_phase") != "live":
				continue
			role = current_role
			response_ms = await _check_responsiveness(main, role)
			if response_ms < 0:
				main.call("_leave_room")
				quit(1)
				return
			modal_snapshots = await _check_tweak_apply(main, role)
			if modal_snapshots <= 0:
				main.call("_leave_room")
				quit(1)
				return
			Input.action_press("move_down" if role == "left" else "move_up")
		if reconnect_started:
			reconnected = current_role == role
		var board: Dictionary = main.get("_board").call("get_debug_state")
		var text: String = main.get("_score_label").text
		if board.left > 0.7 and board.right < 0.3 and text != "0   0":
			score = text
			if not reconnect_started:
				main.get("_connection").reconnect()
				reconnect_started = true
			elif reconnected:
				print("PONG_NATIVE_PASS " + JSON.stringify({"role": role, "score": score, "resumed": true, "local_response_ms": response_ms, "modal_snapshot_updates": modal_snapshots}))
				main.call("_leave_room")
				main.queue_free()
				await process_frame
				quit(0)
				return
	push_error("Pong native network timed out: " + str(main.get("_status_label").text))
	quit(1)


func _check_responsiveness(main: Node, role: String) -> int:
	var board = main.get("_board")
	var visual_key := "visual_" + role
	var action := "move_down" if role == "left" else "move_up"
	var reverse := "move_up" if role == "left" else "move_down"
	var direction := 1.0 if role == "left" else -1.0
	main.set("_focused", true)
	var before: float = board.get_debug_state()[visual_key]
	var authority: float = board.get_debug_state()[role]
	var started := Time.get_ticks_msec()
	Input.action_press(action)
	var responded := false
	while Time.get_ticks_msec() - started < 100:
		await process_frame
		if (float(board.get_debug_state()[visual_key]) - before) * direction > 0.004:
			responded = true
			break
	var response_ms := Time.get_ticks_msec() - started
	if not responded or not is_equal_approx(float(board.get_debug_state()[role]), authority):
		push_error("Local paddle did not respond ahead of authority: " + JSON.stringify(board.get_debug_state()))
		return -1
	Input.action_release(action)
	# process_frame is emitted before node processing, so let input run for a full frame.
	await process_frame
	await process_frame
	var stopped: float = board.get_debug_state()[visual_key]
	await process_frame
	if absf(float(board.get_debug_state()[visual_key]) - stopped) > 0.003:
		push_error("Local stop drifted while awaiting acknowledgement")
		return -1
	Input.action_press(reverse)
	await process_frame
	await process_frame
	if (float(board.get_debug_state()[visual_key]) - stopped) * direction >= -0.004:
		push_error("Local reverse waited for authority")
		return -1
	Input.action_release(reverse)
	return response_ms


func _check_tweak_apply(main: Node, _role: String) -> int:
	var store := root.get_node("TuningStore")
	var before := int(main.get("_last_snapshot_seq"))
	if not store.set_values({"audio.music.volume_db": -17.0}, false): return -1
	await create_timer(0.7).timeout
	var after := int(main.get("_last_snapshot_seq"))
	if paused or after <= before or main.get("_phase") != "live" or not main.get("_has_welcome"):
		push_error("Preview tuning interrupted the authoritative connection")
		return -1
	return after - before

