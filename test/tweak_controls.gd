extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
    if not ok: failures.append(message); push_error(message)
func run() -> void:
    var main: Control = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    await process_frame
    var store: Node = root.get_node("TuningStore")
    check(store.get_settings().size() == 7, "Only local presentation controls are exposed")
    for item: Dictionary in store.get_settings():
        check(item.integrity == "COSMETIC", "No client gameplay override")
    check(store.set_values({"audio.music.volume_db": -17.0}, false), "Audio patch accepted")
    check(main._settings_controls["audio.music.volume_db"].value == -17.0, "Ordinary settings remain synchronized")
    main._connection.state = main.ConnectionType.State.RETRY_WAIT
    main._connection._retry_elapsed = 0.0
    main._process(0.1)
    check(main._connection._retry_elapsed > 0, "Network polling continues after tuning")
    check(not paused, "Apply does not pause the game")
    root.get_node("AudioDirector").release_streams()
    main.queue_free()
    await create_timer(0.15).timeout
    print("TUNING_CONTROLS: ", "PASS" if failures.is_empty() else str(failures))
    quit(0 if failures.is_empty() else 1)
