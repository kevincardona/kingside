extends AIEngineBackend
class_name AIScriptBackend
# In-process GDScript alpha-beta searcher. Always available, runs on every
# platform (including HTML5). The actual search lives in AIEngine; this
# backend just identifies itself and provides a stub that AIEngine falls
# back to when bestmove() is called.

func name() -> String:
	return "script"

func is_available() -> bool:
	return true

func start() -> bool:
	return true

func bestmove(fen: String, movetime_ms: int) -> String:
	# The script backend runs synchronously in AIEngine's worker thread;
	# it doesn't go through this stub. Returning "" here means "use the
	# in-process searcher".
	return ""
