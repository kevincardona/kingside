extends SceneTree

func _init() -> void:
	print("native_class=", ClassDB.class_exists("ChessEngine"))
	if not ClassDB.class_exists("ChessEngine"):
		quit(1)
		return
	print("speech_class=", ClassDB.class_exists("SpeechInput"))
	if not ClassDB.class_exists("SpeechInput"):
		quit(1)
		return
	var speech = ClassDB.instantiate("SpeechInput")
	print("speech_available=", bool(speech.call("is_available")))

	var engine = ClassDB.instantiate("ChessEngine")
	print("instantiated=", engine != null)
	if engine == null:
		quit(1)
		return

	var started = bool(engine.call("start"))
	print("started=", started)
	if not started:
		quit(1)
		return

	if not engine.has_method("set_option"):
		print("set_option=false")
		engine.call("shutdown")
		quit(1)
		return
	print("set_option=", bool(engine.call("set_option", "UCI_LimitStrength", "false")))

	var move = str(engine.call(
		"bestmove",
		"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		300
	))
	print("bestmove=", move)
	engine.call("shutdown")
	quit(0 if move != "" else 1)
