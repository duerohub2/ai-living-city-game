extends SceneTree

const BrowserBgmPlayer = preload("res://scripts/manus/browser_bgm_player.gd")
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var track := AudioStreamWAV.new()
	track.format = AudioStreamWAV.FORMAT_16_BITS
	track.mix_rate = 12000
	track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	track.loop_end = 24000
	var bytes := PackedByteArray()
	bytes.resize(48000)
	for index in 24000:
		bytes.encode_s16(index * 2, int(sin(float(index) * TAU * 220.0 / 12000.0) * 4000.0))
	track.data = bytes
	var decoder := track.instantiate_playback()
	decoder.start()
	var pcm := decoder.mix_audio(1.0, 16384)
	_check(pcm.size() == 16384 and pcm.to_byte_array().size() == 16384 * 8, "one-time decoder provides packed float32 stereo frames")
	var energy := 0.0
	for sample in pcm:
		energy += sample.length_squared()
	_check(energy > 0.01, "one-time decoder preserves non-silent runtime PCM soundtrack")
	decoder.stop()
	decoder = null
	var container := Node.new()
	root.add_child(container)
	var music := BrowserBgmPlayer.new()
	music.stream = track
	music.volume_db = -6.0
	music.pitch_scale = 1.08
	container.add_child(music)
	music.play(0.25)
	_check(music.playing and not music.uses_browser_audio(), "native fallback starts the same stream")
	_check(music._native.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "native fallback keeps streaming playback")
	_check(is_equal_approx(music._native.pitch_scale, 1.08), "tempo adjustment reaches fallback")
	_check(is_equal_approx(music._native.volume_db, -6.0), "player volume reaches fallback")
	_check(music._loop_settings().enabled and is_equal_approx(music._loop_settings().end, 2.0), "WAV loop range is expressed in seconds")
	paused = true
	await process_frame
	await process_frame
	_check(music._native.stream_paused, "inherited tree pause freezes fallback audio")
	container.process_mode = Node.PROCESS_MODE_ALWAYS
	await process_frame
	await process_frame
	_check(not music._native.stream_paused, "always-processing music survives gameplay pause")
	music.stream_paused = true
	_check(music._native.stream_paused, "explicit soundtrack pause works in an always-processing owner")
	music.stream_paused = false
	paused = false
	var master := AudioServer.get_bus_index(&"Master")
	var was_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)
	_check(is_zero_approx(music._effective_gain()), "browser control gain includes Master mute")
	_check(music.playing, "gain mute preserves existing music timeline")
	AudioServer.set_bus_mute(master, was_muted)
	music.stop()
	_check(not music.playing, "explicit stop ends native voice")
	music.play()
	music.stream = null
	_check(not music.playing and music._native.stream == null, "stream replacement stops and releases old audio")
	container.queue_free()
	await process_frame
	track = null
	await create_timer(0.3).timeout
	if failures.is_empty():
		print("[browser-bgm-regression] PASS: PCM, fallback, pause, mute, pitch and cleanup")
	quit(0 if failures.is_empty() else 1)
