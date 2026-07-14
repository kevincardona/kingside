extends Node

# Mobile haptics wrapper. Uses Input.vibrate_handheld on supported platforms
# (iOS/Android) and silently no-ops elsewhere. Honors the "haptics" setting.

const _MIN_GAP := 0.04

var _last_time := 0.0

func _ready() -> void:
	pass

func _enabled() -> bool:
	if not PlayerData.settings.get("haptics", true): return false
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	return false

func _vibrate(duration_ms: int, amplitude: float = 1.0) -> void:
	if not _enabled(): return
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_time < _MIN_GAP: return
	_last_time = now
	# Input.vibrate_handheld supports an optional duration in ms and amplitude (0.0–1.0)
	# in Godot 4. Amplitude is honored on iOS (haptic intensity) and ignored elsewhere.
	if duration_ms <= 0:
		Input.vibrate_handheld(0, amplitude)
	else:
		Input.vibrate_handheld(duration_ms, amplitude)

func selection() -> void:
	_vibrate(8, 0.45)

func impact(capture: bool = false) -> void:
	if capture:
		_vibrate(28, 1.0)
	else:
		_vibrate(14, 0.7)

func check() -> void:
	_vibrate(40, 0.9)

func checkmate() -> void:
	_vibrate(70, 1.0)

func result(win: bool) -> void:
	if win:
		_vibrate(55, 0.85)
	else:
		_vibrate(90, 1.0)

func tick() -> void:
	_vibrate(6, 0.4)
