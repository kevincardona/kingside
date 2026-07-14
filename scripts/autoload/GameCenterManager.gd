extends Node
# Game Center bridge: authentication, the global rating leaderboard, and
# turn-based online matches. Wraps the native "GameCenter" GDExtension class
# (iOS + macOS); on other platforms is_supported() returns false and the UI
# hides online features.
#
# Setup still required in App Store Connect before this works on device:
#   1. Enable the Game Center capability for the app ID / in Xcode.
#   2. Create a leaderboard with ID matching LEADERBOARD_ELO below.
#   3. Turn-based matches need no extra setup (Apple hosts them).

signal auth_changed(authenticated: bool, player_name: String)
signal match_found(match_id: String, my_turn: bool, data: Dictionary, info: Dictionary)
signal turn_received(match_id: String, my_turn: bool, data: Dictionary, ended: bool, outcome: String, info: Dictionary)
signal matches_loaded(matches: Array)
signal matchmaker_cancelled()
signal gc_error(op: String, message: String)
# Real-time (GKMatch) — both players live at once.
signal realtime_started(opponent: String, my_white: bool)
signal realtime_data(data: Dictionary)
signal realtime_ended(reason: String)
signal realtime_cancelled()

const LEADERBOARD_ELO = "chess.elo.global"

var _gc = null
var _poll_accum: float = 0.0

func _ready() -> void:
	if ClassDB.class_exists("GameCenter"):
		_gc = ClassDB.instantiate("GameCenter")

func _process(delta: float) -> void:
	if _gc == null: return
	_poll_accum += delta
	if _poll_accum < 0.25: return
	_poll_accum = 0.0
	while bool(_gc.call("has_event")):
		_dispatch(_gc.call("poll_event"))

func is_supported() -> bool:
	return _gc != null and bool(_gc.call("is_supported"))

func is_authenticated() -> bool:
	return _gc != null and bool(_gc.call("is_authenticated"))

func player_name() -> String:
	return str(_gc.call("local_player_name")) if _gc != null else ""

func authenticate() -> void:
	if _gc != null: _gc.call("authenticate")

func submit_rating(elo: int) -> void:
	if is_authenticated():
		_gc.call("submit_score", LEADERBOARD_ELO, elo)

func show_leaderboard() -> void:
	if is_authenticated():
		_gc.call("show_leaderboard", LEADERBOARD_ELO)

func local_player_id() -> String:
	return str(_gc.call("local_player_id")) if _gc != null else ""

func find_match() -> void:
	if not is_supported():
		gc_error.emit("find_match", "Game Center is not available in this build.")
		return
	if not is_authenticated():
		gc_error.emit("find_match", "Sign in to Game Center first.")
		return
	_gc.call("find_match")

func show_matchmaker() -> void:
	# Apple's match sheet: invite a Game Center friend (delivered over
	# iMessage) or pick up an existing match.
	if not is_supported():
		gc_error.emit("matchmaker", "Game Center is not available in this build.")
		return
	if not is_authenticated():
		gc_error.emit("matchmaker", "Sign in to Game Center first.")
		return
	_gc.call("show_matchmaker")

func load_matches() -> void:
	if is_authenticated(): _gc.call("load_matches")

func end_turn(match_id: String, state_data: Dictionary) -> void:
	if is_authenticated():
		_gc.call("end_turn", match_id, JSON.stringify(state_data))

func end_match(match_id: String, state_data: Dictionary, outcome: String) -> void:
	if is_authenticated():
		_gc.call("end_match", match_id, JSON.stringify(state_data), outcome)

func resign_match(match_id: String) -> void:
	if is_authenticated(): _gc.call("resign_match", match_id)

# ── Real-time (GKMatch) ──
func find_realtime_match() -> void:
	if not is_supported():
		gc_error.emit("realtime", "Game Center is not available in this build.")
		return
	if not is_authenticated():
		gc_error.emit("realtime", "Sign in to Game Center first.")
		return
	_gc.call("show_realtime_matchmaker")

func send_realtime(data: Dictionary) -> void:
	if _gc != null and is_authenticated():
		_gc.call("send_realtime", JSON.stringify(data))

func leave_realtime() -> void:
	if _gc != null:
		_gc.call("leave_realtime")

func _parse_data(raw: String) -> Dictionary:
	if raw.strip_edges() == "": return {}
	var json = JSON.new()
	if json.parse(raw) != OK: return {}
	var d = json.get_data()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _info(event: Dictionary) -> Dictionary:
	return {
		"active": bool(event.get("active", false)),
		"i_created": bool(event.get("i_created", false)),
		"opponent": str(event.get("opponent", "")),
	}

func _dispatch(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"auth":
			auth_changed.emit(bool(event.get("ok", false)), str(event.get("player", "")))
		"match_found":
			match_found.emit(str(event.get("match_id", "")), bool(event.get("my_turn", false)),
				_parse_data(str(event.get("data", ""))), _info(event))
		"turn":
			turn_received.emit(str(event.get("match_id", "")), bool(event.get("my_turn", false)),
				_parse_data(str(event.get("data", ""))), bool(event.get("ended", false)),
				str(event.get("outcome", "")), _info(event))
		"matches":
			matches_loaded.emit(event.get("matches", []))
		"matchmaker_cancelled":
			matchmaker_cancelled.emit()
		"rt_match_found":
			realtime_started.emit(str(event.get("opponent", "")), bool(event.get("my_white", false)))
		"rt_data":
			realtime_data.emit(_parse_data(str(event.get("data", ""))))
		"rt_state":
			if not bool(event.get("connected", true)):
				realtime_ended.emit("opponent_left")
		"rt_cancelled":
			realtime_cancelled.emit()
		"score":
			if not bool(event.get("ok", false)):
				gc_error.emit("submit_score", str(event.get("error", "")))
		"error":
			gc_error.emit(str(event.get("op", "")), str(event.get("error", "")))
