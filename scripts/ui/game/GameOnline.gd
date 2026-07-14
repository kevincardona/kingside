class_name GameOnline
extends Node
# Remote-match adapter for GameScreen. The opponent is on another device and
# moves sync through a turn-based backend:
#   "gamecenter" — Apple Game Center matches (GameCenterManager, Apple only)
#   "web"        — cross-platform OnlineManager (works everywhere)
# Both managers expose the same surface (local_player_id / end_turn /
# end_match / resign_match + a turn_received signal), so everything below is
# backend-agnostic. Match state travels as JSON: {v, moves:[uci], fen, white_id}.

var screen = null   # GameScreen

var active: bool = false
var realtime: bool = false   # GKMatch live mode: moves send/apply immediately
var backend: String = "gamecenter"
var match_id: String = ""
var opp_name: String = ""
var my_id: String = ""
var white_id: String = ""

func _mgr() -> Node:
	if backend == "web":
		return get_tree().root.get_node("OnlineManager")
	return get_tree().root.get_node("GameCenterManager")

# Called from GameScreen._ready before the layout is built. Configures the
# screen for an online seat and replays any stored moves.
func setup(info: Dictionary) -> void:
	active = true
	realtime = bool(info.get("realtime", false))
	backend = str(info.get("backend", "gamecenter"))
	screen._online_mode    = true
	screen._local_mode     = false
	screen._rated_game     = false
	screen._hints_enabled  = false
	screen._timed_game     = false
	screen._difficulty     = "online"
	match_id = str(info.get("match_id", ""))
	opp_name = str(info.get("opponent", ""))
	my_id    = _mgr().local_player_id()
	screen._state = ChessLogic.new_game()
	screen._record_pos()

	if realtime:
		# A fresh live match: the seat comes from the deterministic my_white flag
		# (both clients computed it from the same id pair), nothing to replay.
		screen._player_color = ChessLogic.WHITE if bool(info.get("my_white", true)) else ChessLogic.BLACK
		white_id = my_id if screen._player_color == ChessLogic.WHITE else ""
		var gc = _mgr()
		gc.realtime_data.connect(_on_realtime_data)
		gc.realtime_ended.connect(_on_realtime_ended)
		return

	var payload = info.get("data", {})
	if typeof(payload) == TYPE_STRING:
		payload = parse_payload(payload)
	white_id = str(payload.get("white_id", ""))
	# Seat: a stored white_id wins; otherwise the match creator plays White.
	if white_id != "":
		screen._player_color = ChessLogic.WHITE if white_id == my_id else ChessLogic.BLACK
	else:
		screen._player_color = ChessLogic.WHITE if bool(info.get("i_created", true)) else ChessLogic.BLACK
		if screen._player_color == ChessLogic.WHITE:
			white_id = my_id
	replay_moves(payload.get("moves", []))
	_mgr().turn_received.connect(_on_turn)
	if backend == "web":
		_mgr().watch(match_id)

func _exit_tree() -> void:
	if not active: return
	var mgr = _mgr()
	if realtime:
		if mgr.realtime_data.is_connected(_on_realtime_data):
			mgr.realtime_data.disconnect(_on_realtime_data)
		if mgr.realtime_ended.is_connected(_on_realtime_ended):
			mgr.realtime_ended.disconnect(_on_realtime_ended)
		mgr.leave_realtime()
		return
	if mgr.turn_received.is_connected(_on_turn):
		mgr.turn_received.disconnect(_on_turn)
	if backend == "web":
		mgr.unwatch()

func parse_payload(raw: String) -> Dictionary:
	if raw.strip_edges() == "": return {}
	var json = JSON.new()
	if json.parse(raw) != OK: return {}
	var d = json.get_data()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func replay_moves(moves) -> void:
	if typeof(moves) != TYPE_ARRAY: return
	for uci in moves:
		var mv = ChessLogic.uci_to_move(screen._state, str(uci))
		if mv.is_empty():
			push_warning("Online match: illegal stored move %s — stopping replay" % str(uci))
			break
		screen._history.append(screen._state.copy())
		screen._record_move(mv, screen._state.turn)
		screen._state = ChessLogic.apply_move(screen._state, mv)
		screen._record_pos()

func _move_list() -> Array:
	var out: Array = []
	for rec in screen._move_records:
		var mv = rec.get("move", {})
		if typeof(mv) == TYPE_DICTIONARY and not mv.is_empty():
			out.append(ChessLogic.move_to_uci(mv))
	return out

# Push the local position to the backend after the player moves (or the game
# ends locally — checkmate/stalemate/resign all land here via send_state).
func send_state() -> void:
	var payload = {
		"v": 1,
		"moves": _move_list(),
		"fen": ChessLogic.state_to_fen(screen._state),
		"white_id": white_id,
	}
	if realtime:
		# Live: just broadcast the new position. The opponent applies it and,
		# if it's mate/stalemate, their own _check_game_over ends their game.
		_mgr().send_realtime(payload)
		if screen._game_over:
			_mgr().leave_realtime()
		return
	if screen._game_over:
		var outcome = "tied"
		var res = str(screen._status.get("result", ""))
		if res == "1-0":
			outcome = "won" if screen._player_color == ChessLogic.WHITE else "lost"
		elif res == "0-1":
			outcome = "won" if screen._player_color == ChessLogic.BLACK else "lost"
		_mgr().end_match(match_id, payload, outcome)
	else:
		_mgr().end_turn(match_id, payload)

func resign() -> void:
	if realtime:
		# Tell the opponent we resigned, then drop the connection.
		_mgr().send_realtime({"v": 1, "moves": _move_list(), "white_id": white_id, "resign": true})
		_mgr().leave_realtime()
		return
	_mgr().resign_match(match_id)

# A live update from the opponent (a move, or a resignation).
func _on_realtime_data(data: Dictionary) -> void:
	if not active or not realtime or screen._game_over:
		return
	_sync(data)
	if bool(data.get("resign", false)) and not screen._game_over:
		screen._game_over = true
		screen._ai_thinking = false
		screen._show_result_overlay("You Win!", "Opponent resigned", 0)

func _on_realtime_ended(_reason: String) -> void:
	if not active or not realtime or screen._game_over:
		return
	screen._game_over = true
	screen._ai_thinking = false
	screen._show_result_overlay("You Win!", "Opponent left", 0)

func _on_turn(turn_match_id: String, _my_turn: bool, data: Dictionary, ended: bool, outcome: String, _info: Dictionary) -> void:
	if not active or turn_match_id != match_id:
		return
	_sync(data)
	if ended and not screen._game_over:
		screen._game_over = true
		screen._ai_thinking = false
		var txt = "Draw"
		if outcome == "won": txt = "You Win!"
		elif outcome == "lost": txt = "You Lose"
		var reason = "Resignation" if outcome == "won" and not screen._status.get("game_over", false) else "Match ended"
		screen._show_result_overlay(txt, reason, 0)

# Apply any moves the opponent made that we have not seen yet.
func _sync(data: Dictionary) -> void:
	var moves = data.get("moves", [])
	if typeof(moves) != TYPE_ARRAY: return
	if moves.size() <= screen._move_records.size(): return
	screen._reset_history_view_to_latest()
	var new_moves = moves.slice(screen._move_records.size())
	var last_mv: Dictionary = {}
	for uci in new_moves:
		var mv = ChessLogic.uci_to_move(screen._state, str(uci))
		if mv.is_empty():
			push_warning("Online match: received illegal move %s" % str(uci))
			return
		screen._history.append(screen._state.copy())
		screen._record_move(mv, screen._state.turn)
		screen._state = ChessLogic.apply_move(screen._state, mv)
		screen._record_pos()
		last_mv = mv
	if not last_mv.is_empty():
		screen._board.set_last_move(int(last_mv.get("from", -1)), int(last_mv.get("to", -1)))
		screen._play_move_sound(last_mv)
	screen._board.set_state(screen._state)
	screen._refresh_ui()
	screen._check_game_over()
