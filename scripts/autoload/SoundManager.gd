extends Node

var _player: AudioStreamPlayer
var _clock_player: AudioStreamPlayer

var _move_stream: AudioStream
var _capture_stream: AudioStream
var _check_stream: AudioStream
var _checkmate_stream: AudioStream
var _win_stream: AudioStream
var _lose_stream: AudioStream

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_clock_player = AudioStreamPlayer.new()
	add_child(_clock_player)

	_move_stream      = load("res://sounds/Move.ogg")
	_capture_stream   = load("res://sounds/Capture.ogg")
	_check_stream     = load("res://sounds/Check.ogg")
	_checkmate_stream = load("res://sounds/Checkmate.ogg")
	_win_stream       = load("res://sounds/Victory.ogg")
	_lose_stream      = load("res://sounds/Defeat.ogg")

func play_click() -> void:
	if not PlayerData.settings.get("sound", true): return
	_play(_move_stream, _player, -4.0)

func play_move(capture: bool = false) -> void:
	if not PlayerData.settings.get("sound", true): return
	_play(_capture_stream if capture else _move_stream, _player)

func play_check() -> void:
	if not PlayerData.settings.get("sound", true): return
	_play(_check_stream, _player)

func play_checkmate() -> void:
	if not PlayerData.settings.get("sound", true): return
	_play(_checkmate_stream, _player)

func play_clock_tick() -> void:
	if not PlayerData.settings.get("sound", true): return
	if not PlayerData.settings.get("clock_sound", true): return
	_play(_make_tick(), _clock_player, -6.0)

func play_result(win: bool) -> void:
	if not PlayerData.settings.get("sound", true): return
	_play(_win_stream if win else _lose_stream, _player)

# ── Helpers ─────────────────────────────────────────────────────────────────────

func _play(stream: AudioStream, player: AudioStreamPlayer, db: float = 0.0) -> void:
	if not stream: return
	player.stream = stream
	player.volume_db = db
	player.play()

# Short procedural tick for clock countdown — too tiny to need a file
func _make_tick() -> AudioStreamWAV:
	const SR = 44100
	var frames = int(SR * 0.026)
	var data = PackedByteArray(); data.resize(frames * 2)
	for i in frames:
		var t = float(i) / SR
		var v = int(clamp((sin(TAU * 1080.0 * t) * exp(-t * 280.0) * 0.32) * 32767.0, -32768.0, 32767.0))
		data[i * 2]     = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = data
	return wav
