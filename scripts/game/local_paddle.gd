# Local presentation only: one anticipated position, one snapshot, no input replay.
extends RefCounted

const MAX_EXTRAPOLATION := 0.15
const STALE_AFTER := 0.5
const CORRECTION_TIME := 0.10
const SNAP_DISTANCE := 0.20
const DEAD_ZONE := 0.002

var y := 0.5
var speed := 0.74
var min_y := 0.11
var max_y := 0.89
var active := false
var initialized := false
var axis := 0.0
var _server_y := 0.5
var _server_vy := 0.0
var _age := 0.0
var _one_way := 0.0
var _ack := 0
var _change_seq := 0
var _pending_age := 0.0
var _last_seq := -1
var _rtt_ack := 0


func configure(movement: Dictionary) -> void:
	speed = float(movement.speed)
	min_y = float(movement.min_y)
	max_y = float(movement.max_y)
	reset()


func reset() -> void:
	active = false
	initialized = false
	axis = 0.0
	_age = 0.0
	_one_way = 0.0
	_ack = 0
	_change_seq = 0
	_pending_age = 0.0
	_last_seq = -1
	_rtt_ack = 0


func set_input(value: float, next_seq: int) -> void:
	if value != axis:
		axis = value
		# Older snapshots must not undo a direction change that has not reached the server.
		if _ack >= _change_seq:
			_pending_age = 0.0
		_change_seq = next_seq


func accept(paddle: Dictionary, live: bool, seq: int, now_ms: int) -> void:
	if seq <= _last_seq:
		return
	_last_seq = seq
	_server_y = clampf(float(paddle.y), min_y, max_y)
	_server_vy = float(paddle.vy) if live else 0.0
	_ack = int(paddle.ack_seq)
	var sent_ms := int(paddle.sent_msec)
	if _ack > _rtt_ack and sent_ms >= 0 and sent_ms <= now_ms:
		var sample := clampf(float(now_ms - sent_ms) / 2000.0, 0.0, MAX_EXTRAPOLATION)
		_one_way = sample if _rtt_ack == 0 else lerpf(_one_way, sample, 0.2)
		_rtt_ack = _ack
	_age = 0.0
	if not initialized or not active or not live:
		y = _server_y
	initialized = true
	active = live


func advance(delta: float) -> float:
	if not initialized or not active:
		return y
	_age += maxf(delta, 0.0)
	_pending_age += maxf(delta, 0.0)
	if _age > STALE_AFTER:
		active = false
		y = _server_y
		return y
	# Avoid a tab-resume frame simulating seconds of local input at once.
	var dt := clampf(delta, 0.0, 0.05)
	y = clampf(y + axis * speed * dt, min_y, max_y)
	if _ack >= _change_seq:
		_pending_age = 0.0
	if _ack < _change_seq and _pending_age < STALE_AFTER:
		return y
	var target := clampf(_server_y + _server_vy * minf(_one_way + _age, MAX_EXTRAPOLATION), min_y, max_y)
	var error := target - y
	if absf(error) > SNAP_DISTANCE:
		y = target
	elif absf(error) > DEAD_ZONE:
		y += error * (1.0 - exp(-dt / CORRECTION_TIME))
	return y
