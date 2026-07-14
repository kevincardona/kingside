extends AIEngineBackend
class_name AINativeBackend
# Talks to the Stockfish GDExtension compiled into the app. The extension
# exposes a native "ChessEngine" class with start(), bestmove(fen,
# movetime_ms), and shutdown(). When the extension isn't loaded, is_available()
# returns false and AIEngine falls back to the script backend.

const NATIVE_CLASS := "ChessEngine"

var _started := false
var _failed := false
var _engine: Object = null

func name() -> String:
	return "native"

func prepare() -> bool:
	if _engine != null: return true
	var class_ok = ClassDB.class_exists(NATIVE_CLASS)
	print("AINativeBackend.prepare: class_exists=", class_ok, " _failed=", _failed)
	if _failed or not class_ok: return false
	_engine = ClassDB.instantiate(NATIVE_CLASS)
	_failed = _engine == null
	print("AINativeBackend.prepare: instantiate ok=", not _failed)
	return not _failed

func is_available() -> bool:
	return not _failed and (_engine != null or ClassDB.class_exists(NATIVE_CLASS))

func start() -> bool:
	if _started: return true
	if not is_available():
		print("AINativeBackend.start: not available")
		return false
	if _engine == null and not prepare(): return false
	print("AINativeBackend.start: calling engine.start()...")
	var ok = _engine.call("start")
	_started = bool(ok)
	_failed = not _started
	print("AINativeBackend.start: result=", ok)
	return bool(ok)

func bestmove(fen: String, movetime_ms: int) -> String:
	if not is_available(): return ""
	if not start(): return ""
	var out = _engine.call("bestmove", fen, int(movetime_ms))
	return str(out) if out != null else ""

# Centipawn score (side-to-move POV) of the most recent bestmove() search.
func last_eval_cp() -> int:
	if _engine == null or not _engine.has_method("last_eval_cp"): return 0
	return int(_engine.call("last_eval_cp"))

func set_option(name: String, value: String) -> bool:
	if not is_available(): return false
	if not start(): return false
	if not _engine.has_method("set_option"): return false
	return bool(_engine.call("set_option", name, value))

func shutdown() -> void:
	if _engine != null:
		_engine.call("shutdown")
	_started = false
	_engine = null
