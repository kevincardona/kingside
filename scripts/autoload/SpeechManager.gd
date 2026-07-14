extends Node

signal transcript_changed(text: String)
signal final_transcript(text: String)
signal error_changed(message: String)

var _input = null
var _last_transcript: String = ""
var _last_error: String = ""

func _ready() -> void:
	if ClassDB.class_exists("SpeechInput"):
		_input = ClassDB.instantiate("SpeechInput")

func is_available() -> bool:
	return _input != null and bool(_input.call("is_available"))

func is_listening() -> bool:
	return _input != null and bool(_input.call("is_listening"))

func get_transcript() -> String:
	return _last_transcript

func get_error() -> String:
	return _last_error

func get_audio_level() -> float:
	return _input.call("get_audio_level") if _input != null else 0.0

func start() -> bool:
	if _input == null:
		_last_error = "Speech recognition is not built for this platform yet."
		error_changed.emit(_last_error)
		return false
	_last_transcript = ""
	_last_error = ""
	_input.call("clear")
	var ok = bool(_input.call("start"))
	if not ok:
		var message = str(_input.call("get_error"))
		_last_error = message if message != "" else "Speech recognition could not start."
		error_changed.emit(_last_error)
	return ok

func stop() -> void:
	if _input != null:
		_input.call("stop")

func clear() -> void:
	_last_transcript = ""
	_last_error = ""
	if _input != null:
		_input.call("clear")

func poll() -> void:
	if _input == null:
		return
	var err = str(_input.call("get_error"))
	if err != "" and err != _last_error:
		_last_error = err
		error_changed.emit(err)
	var text = str(_input.call("get_transcript")).strip_edges()
	if text != "" and text != _last_transcript:
		_last_transcript = text
		transcript_changed.emit(text)
	if bool(_input.call("has_final_transcript")):
		var final_text = str(_input.call("consume_final_transcript")).strip_edges()
		if final_text != "":
			final_transcript.emit(final_text)
