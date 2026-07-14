extends RefCounted
class_name AIEngineBackend
# Abstract interface for an engine backend. Subclasses implement start(),
# bestmove() and shutdown().

func name() -> String:
	return "abstract"

func is_available() -> bool:
	return false

func start() -> bool:
	return false

func bestmove(fen: String, movetime_ms: int) -> String:
	# Returns a UCI move like "e2e4" or "" / "(none)" on failure.
	return ""

func shutdown() -> void:
	pass
