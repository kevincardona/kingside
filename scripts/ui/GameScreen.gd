extends Control
# The in-game screen: owns the chess state, move application, AI turns,
# clocks, undo/hints/promotion/resign and the game-over flow.
# Everything else lives in focused components under scripts/ui/game/:
#   GameHud     — layout + bars/strips/controls and their refresh
#   GameVoice   — hands-free voice input + mic banner/pulse
#   GameReview  — post-game analysis modal + review overlay
#   GameOnline  — remote-match sync (Game Center / cross-platform web)
#   GameModals  — overlay + centered-card helpers
#   GameFormat  — material/clock/percent formatting (static)
#   GameWidgets — win-chance bar, accuracy ring, spinner

const PROMO_PIECES = [ChessLogic.QUEEN, ChessLogic.ROOK, ChessLogic.BISHOP, ChessLogic.KNIGHT]

var _state
var _board: BoardVisual
var _status: Dictionary  = {}
var _ai_thinking: bool   = false
var _game_over: bool     = false
var _pending_promo: Dictionary = {}
var _history: Array      = []
var _move_records: Array = []
var _pos_hist: Dictionary = {}
var _history_view_ply: int = -1

var _player_color: int
var _difficulty: String
var _hints_enabled: bool = true
var _hint_level: int     = 0
var _hint_move: Dictionary = {}
var _premove: Dictionary = {}
var _white_time: float   = 0.0
var _black_time: float   = 0.0
var _time_increment: int = 0
var _timed_game: bool    = false
var _last_clock_tick_second: int = -1
var _ai_pending_fen: String = ""
var _rated_game: bool = true
var _local_mode: bool = false   # Pass & Play: both colors are human; the
								# "player" seat follows the side to move
var _online_mode: bool = false  # remote opponent; moves sync via GameOnline

var _hint_btn: Button           # created by GameHud
var _voice_btn: Button          # created by GameHud, animated by GameVoice
var _completed_saved: bool = false
var _last_is_landscape: bool = true
var _rebuild_pending: bool = false

# Components
var _hud: GameHud
var _voice: GameVoice
var _review: GameReview
var _online: GameOnline

func _ready() -> void:
	_hud    = GameHud.new();    _hud.name = "Hud";       _hud.screen = self;    add_child(_hud)
	_voice  = GameVoice.new();  _voice.name = "Voice";   _voice.screen = self;  add_child(_voice)
	_review = GameReview.new(); _review.name = "Review"; _review.screen = self; add_child(_review)
	_online = GameOnline.new(); _online.name = "Online"; _online.screen = self; add_child(_online)

	if not GameManager.review_session.is_empty():
		_player_color = GameManager.review_session.get("player_color", ChessLogic.WHITE)
		_difficulty = GameManager.review_session.get("difficulty", "medium")
		_hints_enabled = PlayerData.settings.get("hints", true)
		_state = ChessLogic.new_game()
		add_child(UITheme.make_page_bg())
		_move_records = GameManager.review_session.get("records", [])
		_review.call_deferred("start_analysis")
		return
	if not GameManager.online_match.is_empty():
		_setup_online(GameManager.online_match)
		return
	_player_color  = GameManager.player_color
	_difficulty    = GameManager.chosen_difficulty
	_local_mode    = GameManager.local_two_player or _difficulty == "local"
	_rated_game    = not _local_mode and GameManager.current_game_rated and AIEngine.can_play_rated(_difficulty)
	GameManager.current_game_rated = _rated_game
	GameManager.allow_unrated_fallback = not _rated_game
	_hints_enabled = PlayerData.settings.get("hints", true)
	_init_clock()
	var rs         = GameManager.resume_session
	_state         = ChessLogic.parse_fen(rs["fen"]) if (not rs.is_empty() and rs.has("fen")) \
					 else ChessLogic.new_game()
	_restore_saved_session(rs)
	_record_pos()
	AIEngine.move_ready.connect(_on_ai_move)
	AIEngine.hint_ready.connect(_on_hint_ready)
	_build()
	_refresh_ui()
	_check_ai_turn()
	resized.connect(_on_resized)

func _setup_online(info: Dictionary) -> void:
	_online.setup(info)
	_build()
	if not _move_records.is_empty():
		var last = _move_records[-1].get("move", {})
		if not last.is_empty():
			_board.set_last_move(int(last.get("from", -1)), int(last.get("to", -1)))
	_refresh_ui()
	_check_game_over()
	resized.connect(_on_resized)

func _process(delta: float) -> void:
	if not _timed_game or _game_over or not _pending_promo.is_empty(): return
	if _state.turn == ChessLogic.WHITE:
		_white_time = max(0.0, _white_time - delta)
	else:
		_black_time = max(0.0, _black_time - delta)
	_hud.refresh_clocks()
	_check_clock_warning()
	if _white_time <= 0.0 or _black_time <= 0.0:
		_flag_time_loss()

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE: _auto_save()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_auto_save()

func _exit_tree() -> void:
	if AIEngine.move_ready.is_connected(_on_ai_move):
		AIEngine.move_ready.disconnect(_on_ai_move)
	if AIEngine.hint_ready.is_connected(_on_hint_ready):
		AIEngine.hint_ready.disconnect(_on_hint_ready)

# ──────────────────────────────────────────────
#  Layout (built by GameHud; rebuilt on rotation)
# ──────────────────────────────────────────────
func _build() -> void:
	_clear_layout()
	add_child(UITheme.make_page_bg())
	_hud.build()

func _clear_layout() -> void:
	# Only visual children: the component Nodes (Hud/Voice/Review/Online)
	# stay alive across rotation rebuilds.
	for child in get_children():
		if child is CanvasItem:
			child.queue_free()

func _on_resized() -> void:
	if _rebuild_pending: return
	if not _board: return
	var vp = get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0: return
	var is_landscape = vp.x > vp.y
	if is_landscape == _last_is_landscape: return
	_rebuild_pending = true
	call_deferred("_do_rebuild")

func _do_rebuild() -> void:
	_rebuild_pending = false
	if not is_inside_tree(): return
	_build()
	_refresh_ui()

func _is_narrow() -> bool:
	return get_viewport_rect().size.x < 500

# ──────────────────────────────────────────────
#  Input
# ──────────────────────────────────────────────
func _on_square_tapped(tapped_sq: int) -> void:
	if _game_over or not _pending_promo.is_empty(): return
	if not _is_viewing_latest():
		_on_history_latest()
		return
	_board.set_voice_coords_visible(false)
	if _ai_thinking:
		_process_premove_tap(tapped_sq)
		return
	if _state.turn != _player_color: return
	_process_tap(tapped_sq)

func _on_drag_move(from_sq: int, to_sq: int) -> void:
	if _game_over: return
	if not _is_viewing_latest():
		_on_history_latest()
		return
	_board.set_voice_coords_visible(false)
	if _ai_thinking:
		_queue_premove(from_sq, to_sq)
		return
	if _state.turn != _player_color: return
	if _state.board[from_sq] == 0: return
	if ChessLogic.piece_color(_state.board[from_sq]) != _player_color: return
	var legal = ChessLogic.get_legal_moves_from(_state, from_sq)
	var matches = legal.filter(func(m): return m["to"] == to_sq)
	if not matches.is_empty():
		_board.clear_selection()
		_attempt_move(from_sq, to_sq, matches)

func _process_tap(sq: int) -> void:
	var selected = _board.selected_sq
	var p        = _state.board[sq]
	var own      = p != 0 and ChessLogic.piece_color(p) == _player_color

	if selected < 0:
		if own: _board.set_selection(sq, _legal_targets(sq))
		return

	if sq == selected:
		_board.clear_selection(); return

	var legal   = ChessLogic.get_legal_moves_from(_state, selected)
	var matches = legal.filter(func(m): return m["to"] == sq)
	if not matches.is_empty():
		_attempt_move(selected, sq, matches)
	elif own:
		_board.set_selection(sq, _legal_targets(sq))
	else:
		_board.clear_selection()

func _process_premove_tap(sq: int) -> void:
	if _state.turn == _player_color: return
	var p = _state.board[sq]
	var own = p != 0 and ChessLogic.piece_color(p) == _player_color
	var selected = _board.selected_sq
	if selected < 0:
		if own:
			_premove = {}
			_board.set_selection(sq, [])
			_board.set_premove(sq)
		return
	if sq == selected:
		_clear_premove()
	elif own:
		_premove = {}
		_board.set_selection(sq, [])
		_board.set_premove(sq)
	else:
		_queue_premove(selected, sq)

func _queue_premove(from_sq: int, to_sq: int) -> void:
	if from_sq < 0 or to_sq < 0 or from_sq == to_sq: return
	if _state.board[from_sq] == 0: return
	if ChessLogic.piece_color(_state.board[from_sq]) != _player_color: return
	_premove = {"from": from_sq, "to": to_sq}
	_board.clear_selection()
	_board.set_premove(from_sq, to_sq)
	SoundManager.play_click()

func _clear_premove() -> void:
	_premove = {}
	_board.clear_selection()
	_board.clear_premove()

func _legal_targets(sq: int) -> Array:
	return ChessLogic.get_legal_moves_from(_state, sq).map(func(m): return m["to"])

func _attempt_move(from_sq: int, to_sq: int, matches: Array) -> void:
	_board.clear_selection()
	_board.clear_hint()
	_hint_level = 0; _hint_move = {}
	if matches.size() > 1 and matches[0].get("promotion", 0) != 0:
		_pending_promo = {"from": from_sq, "to": to_sq, "moves": matches}
		_show_promo_dialog()
	else:
		_apply_player_move(matches[0])

# ──────────────────────────────────────────────
#  Move application
# ──────────────────────────────────────────────
func _apply_player_move(move: Dictionary) -> void:
	_reset_history_view_to_latest()
	_clear_premove()
	_history.append(_state.copy())
	_record_move(move, _player_color)
	_board.set_last_move(move["from"], move["to"])
	_state = ChessLogic.apply_move(_state, move)
	_add_increment(_player_color)
	_play_move_sound(move)
	_record_pos(); _board.set_state(_state); _refresh_ui()
	_check_game_over()
	if _online_mode:
		_online.send_state()
	if not _game_over: _check_ai_turn()

func _apply_ai_move(move: Dictionary) -> void:
	if move.is_empty(): return
	_reset_history_view_to_latest()
	_history.append(_state.copy())
	_record_move(move, -_player_color)
	_board.set_last_move(move["from"], move["to"])
	_state = ChessLogic.apply_move(_state, move)
	_add_increment(-_player_color)
	_play_move_sound(move)
	_record_pos(); _board.set_state(_state)
	_ai_thinking = false
	_hud.set_think("")
	_refresh_ui(); _check_game_over()
	if not _game_over:
		_try_apply_premove()

func _check_ai_turn() -> void:
	if _online_mode:
		return   # the opponent is remote; moves arrive via GameOnline
	if _local_mode:
		# Pass & Play: hand the seat to whichever side is to move.
		if not _game_over:
			_player_color = _state.turn
			if _board: _board.player_color = _player_color
		return
	if _state.turn != _player_color and not _game_over:
		_ai_thinking = true
		_hud.set_think("thinking...")
		_ai_pending_fen = ChessLogic.state_to_fen(_state)
		var instant = PlayerData.settings.get("instant_bot", false)
		var delay = 0.0 if instant else randf_range(0.08, 0.22)
		if not instant and randf() < 0.12:
			delay = randf_range(0.38, 0.58)
		get_tree().create_timer(delay).timeout.connect(func():
			if _game_over or _state.turn == _player_color: return
			if _ai_pending_fen != ChessLogic.state_to_fen(_state): return
			AIEngine.request_move(_state, _difficulty))

func _on_ai_move(move: Dictionary) -> void:
	if _game_over: return
	if move.is_empty():
		_ai_thinking = false
		_ai_pending_fen = ""
		_hud.set_think("")
		_show_engine_unavailable()
		return
	if _ai_pending_fen == "" or _ai_pending_fen != ChessLogic.state_to_fen(_state):
		_ai_thinking = false
		_hud.set_think("")
		if _state.turn != _player_color:
			_check_ai_turn()
		return
	var legal = ChessLogic.get_legal_moves(_state)
	var matches = legal.filter(func(m):
		return int(m.get("from", -1)) == int(move.get("from", -2)) \
			and int(m.get("to", -1)) == int(move.get("to", -2)) \
			and int(m.get("promotion", 0)) == int(move.get("promotion", 0)))
	if matches.is_empty():
		_ai_thinking = false
		_ai_pending_fen = ""
		_hud.set_think("")
		_check_ai_turn()
		return
	_ai_pending_fen = ""
	_apply_ai_move(move)

func _try_apply_premove() -> void:
	if _premove.is_empty(): return
	if _state.turn != _player_color:
		_clear_premove()
		return
	var from_sq = int(_premove.get("from", -1))
	var to_sq = int(_premove.get("to", -1))
	var legal = ChessLogic.get_legal_moves_from(_state, from_sq)
	var matches = legal.filter(func(m): return m["to"] == to_sq)
	if matches.is_empty():
		_clear_premove()
		return
	_attempt_move(from_sq, to_sq, matches)

# ──────────────────────────────────────────────
#  Undo
# ──────────────────────────────────────────────
func _on_undo() -> void:
	if _game_over: return
	if _history.is_empty(): return
	_reset_history_view_to_latest()
	_ai_thinking = false
	_ai_pending_fen = ""
	_hud.set_think("")
	# vs AI we revert the AI's reply too; in Pass & Play one ply at a time.
	var steps = min(1 if _local_mode else 2, _history.size())
	var target_idx = max(0, _history.size() - steps)
	var target_state = _history[target_idx].copy()
	# Decrement pos_hist for every position being erased: history entries after
	# target_idx and the current state (which was recorded after the last move).
	_decrement_pos(ChessLogic.position_key(_state))
	for i in range(target_idx + 1, _history.size()):
		_decrement_pos(ChessLogic.position_key(_history[i]))
	_history = _history.slice(0, target_idx) if target_idx > 0 else []
	for i in steps:
		if not _move_records.is_empty(): _move_records.pop_back()
	_state = target_state
	_board.set_last_move(-1,-1); _board.clear_selection()
	_board.clear_premove(); _premove = {}
	_board.clear_hint(); _hint_level=0; _hint_move={}
	if _local_mode:
		_player_color = _state.turn
		_board.player_color = _player_color
	_board.set_state(_state); _refresh_ui()
	SoundManager.play_move(false)
	Haptics.impact(false)

# ──────────────────────────────────────────────
#  Read-only history viewing
# ──────────────────────────────────────────────
func _history_display_ply() -> int:
	var latest = _move_records.size()
	if _history_view_ply < 0:
		return latest
	return int(clamp(_history_view_ply, 0, latest))

func _history_active_move_index() -> int:
	var ply = _history_display_ply()
	return ply - 1 if ply > 0 else -1

func _is_viewing_latest() -> bool:
	return _history_display_ply() >= _move_records.size()

func _reset_history_view_to_latest() -> void:
	_history_view_ply = -1

func _on_history_prev() -> void:
	if _move_records.is_empty(): return
	_set_history_view_ply(_history_display_ply() - 1)

func _on_history_next() -> void:
	if _move_records.is_empty(): return
	_set_history_view_ply(_history_display_ply() + 1)

func _on_history_latest() -> void:
	_set_history_view_ply(_move_records.size())

func _set_history_view_ply(ply: int) -> void:
	var latest = _move_records.size()
	var bounded = int(clamp(ply, 0, latest))
	_history_view_ply = -1 if bounded >= latest else bounded
	_clear_premove()
	_board.clear_selection()
	_board.clear_hint()
	_hint_level = 0
	_hint_move = {}
	_sync_board_to_history_view()
	_hud.refresh()

func _sync_board_to_history_view() -> void:
	if not is_instance_valid(_board):
		return
	var ply = _history_display_ply()
	var last_move = _history_move_for_ply(ply)
	if last_move.is_empty():
		_board.set_last_move(-1, -1)
	else:
		_board.set_last_move(int(last_move.get("from", -1)), int(last_move.get("to", -1)))
	_board.player_color = _player_color if _is_viewing_latest() else 0
	_board.set_state(_state_for_history_ply(ply))

func _history_move_for_ply(ply: int) -> Dictionary:
	if ply <= 0 or _move_records.is_empty():
		return {}
	var idx = min(ply, _move_records.size()) - 1
	var move = _move_records[idx].get("move", {})
	return move if typeof(move) == TYPE_DICTIONARY else {}

func _state_for_history_ply(ply: int):
	var latest = _move_records.size()
	if ply >= latest:
		return _state
	if ply <= 0:
		if not _move_records.is_empty():
			var start_fen = str(_move_records[0].get("fen", ""))
			if start_fen != "":
				return ChessLogic.parse_fen(start_fen)
		if not _history.is_empty():
			return _history[0].copy()
		return ChessLogic.new_game()
	var rec = _move_records[ply - 1]
	var fen = str(rec.get("after_fen", ""))
	if fen != "":
		return ChessLogic.parse_fen(fen)
	if ply < _history.size():
		return _history[ply].copy()
	return _state

func _decrement_pos(key: String) -> void:
	var count = _pos_hist.get(key, 0)
	if count > 1:
		_pos_hist[key] = count - 1
	else:
		_pos_hist.erase(key)

func _restore_saved_session(session: Dictionary) -> void:
	if session.is_empty():
		return
	_history = []
	for fen in session.get("history", []):
		if typeof(fen) == TYPE_STRING and fen != "":
			_history.append(ChessLogic.parse_fen(fen))
	_move_records = session.get("records", []).duplicate(true)
	if session.has("white_time"):
		_white_time = float(session["white_time"])
	if session.has("black_time"):
		_black_time = float(session["black_time"])
	_pos_hist = {}
	for hist_state in _history:
		_record_pos_for_state(hist_state)

# ──────────────────────────────────────────────
#  Hints
# ──────────────────────────────────────────────
func _on_hint() -> void:
	if _ai_thinking or _game_over: return
	if _state.turn != _player_color: return
	if _hint_level == 0:
		# Keep the quick heuristic move only as a fallback — do NOT draw it on
		# the board, or the arrow visibly snaps to a different square the moment
		# the real engine hint arrives (looked like the first hint was fake).
		var quick = AIEngine.quick_hint(_state)
		if not quick.is_empty():
			_hint_move = quick
			_hint_level = 1
		AIEngine.request_hint(_state)
		if _hint_btn:
			_hint_btn.disabled = true   # bulb icon dims while the real hint loads
	elif _hint_level == 1 and not _hint_move.is_empty():
		_hint_level = 2; _board.set_hint(_hint_move["from"], _hint_move["to"], 2)
	else:
		_hint_level=0; _hint_move={}; _board.clear_hint()

func _on_hint_ready(move: Dictionary) -> void:
	if _game_over: return
	_hint_move = move; _hint_level = 1
	if _hint_btn:
		_hint_btn.disabled = false
	if not move.is_empty(): _board.set_hint(move["from"], move["to"], 1)

# ──────────────────────────────────────────────
#  Promotion dialog
# ──────────────────────────────────────────────
func _show_promo_dialog() -> void:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.add_child(UITheme.make_label("Promote to:", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	# Four equal-width buttons that FILL the row, so they always fit the card
	# instead of overflowing off the right edge on a narrow (430px) screen — a
	# fixed 82px square × 4 + gaps was ~388px against a ~350px inner width.
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)

	var chars_w = {ChessLogic.QUEEN:"♛", ChessLogic.ROOK:"♜",
				   ChessLogic.BISHOP:"♝", ChessLogic.KNIGHT:"♞"}
	for pt in PROMO_PIECES:
		var btn = UITheme.make_icon_btn(chars_w[pt], UITheme.BG_CARD2, 76)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 76)   # share width equally; keep the height
		btn.add_theme_font_size_override("font_size", UITheme.FS_H1)
		btn.pressed.connect(_on_promo_picked.bind(pt))
		row.add_child(btn)

	GameModals.show_modal_card(self, "PromoOverlay", col, 420)

func _on_promo_picked(pt: int) -> void:
	GameModals.dismiss(self, "PromoOverlay")
	var moves = _pending_promo.get("moves", [])
	_pending_promo = {}
	for move in moves:
		if move.get("promotion", 0) == pt: _apply_player_move(move); return

# ──────────────────────────────────────────────
#  Resign – with confirmation
# ──────────────────────────────────────────────
func _on_resign_clicked() -> void:
	if _game_over: return
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UITheme.make_label("⚑  Resign?", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UITheme.make_label("You will forfeit this game.", UITheme.FS_BODY, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UITheme.spacer(4))

	var resign = UITheme.make_btn("Yes, Resign", UITheme.RED, UITheme.FS_BODY, 56)
	resign.pressed.connect(func():
		GameModals.dismiss(self, "ResignConfirm")
		_do_resign())
	col.add_child(resign)

	var cancel = UITheme.make_btn("Cancel", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	cancel.pressed.connect(func(): GameModals.dismiss(self, "ResignConfirm"))
	col.add_child(cancel)

	GameModals.show_modal_card(self, "ResignConfirm", col, 380)

func _do_resign() -> void:
	if _online_mode:
		_online.resign()
		_game_over = true
		_show_result_overlay("You Lose", "Resignation", 0)
		return
	if _local_mode:
		# The side to move resigns; the other side wins.
		_game_over = true
		var winner = "Black Wins!" if _state.turn == ChessLogic.WHITE else "White Wins!"
		_show_result_overlay(winner, "Resignation", 0)
		return
	var prev_achievements = PlayerData.achievements.duplicate()
	var delta = _record_game_result(0.0)
	_game_over = true
	_show_result_overlay("You Lose", "Resignation", delta, _newest_unlocked(prev_achievements))

# ──────────────────────────────────────────────
#  Game over
# ──────────────────────────────────────────────
func _check_game_over() -> void:
	_status = ChessLogic.get_status(_state)
	if _pos_hist.get(ChessLogic.position_key(_state), 0) >= 3:
		_status["game_over"] = true; _status["result"] = "1/2-1/2"
		_status["reason"]    = "threefold repetition"
	if not _status["game_over"]: return
	_game_over = true; _ai_thinking = false
	var score: float; var result_txt: String
	var res = _status["result"]
	if res == "1/2-1/2": score=0.5; result_txt="Draw"
	elif (res=="1-0" and _player_color==ChessLogic.WHITE) or \
		 (res=="0-1" and _player_color==ChessLogic.BLACK): score=1.0; result_txt="You Win!"
	else: score=0.0; result_txt="You Lose"
	if _local_mode:
		if res == "1-0": result_txt = "White Wins!"
		elif res == "0-1": result_txt = "Black Wins!"
	var prev_achievements = PlayerData.achievements.duplicate()
	var delta = _record_game_result(score)
	var new_achievement = _newest_unlocked(prev_achievements)
	# Let the final move (e.g. the mating move) land and be seen before the
	# result card covers the board.
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree(): return
	_show_result_overlay(result_txt, _status["reason"].capitalize(), delta, new_achievement)

func _show_result_overlay(result: String, reason: String, delta: int, new_achievement: String = "") -> void:
	# Every game-ending path (checkmate, stalemate, draw, repetition, resign,
	# timeout, online) lands here — so this is the one place that drops the game
	# from the Continue list. Without it a finished game lingers there and would
	# resume to its stale pre-final-move state.
	PlayerData.clear_game_session(_difficulty, _player_color)
	SoundManager.play_result(result == "You Win!")
	Haptics.result(result == "You Win!" or result == "Draw")
	_save_completed_game(result, reason)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	var result_color = UITheme.ACCENT
	var result_glyph = "✓"
	if result == "You Lose":
		result_color = UITheme.RED_LT; result_glyph = "✕"
	elif result == "Draw":
		result_color = UITheme.GOLD;   result_glyph = "="

	# Round result medallion — a rendered glyph in a tinted disc. The old 🏆/💀/🤝
	# emoji don't exist in the UI font, so they rendered as an empty gap.
	col.add_child(UITheme.spacer(2))
	col.add_child(_result_badge(result_glyph, result_color))
	# Result headline
	col.add_child(UITheme.make_label(result, UITheme.FS_H1,
		result_color, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UITheme.make_label("by " + reason, UITheme.FS_BODY,
		UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	# Status block — rating delta + current standing grouped in one subtle card
	# so it reads as a unit instead of loose lines under a divider.
	var status_panel = UITheme.make_panel_container(UITheme.BG_CARD2, UITheme.R_MEDIUM)
	status_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_m = MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		status_m.add_theme_constant_override("margin_" + s, 14)
	status_panel.add_child(status_m)
	var status_col = VBoxContainer.new()
	status_col.add_theme_constant_override("separation", 2)
	status_m.add_child(status_col)
	if _rated_game:
		var dsign = "+" if delta >= 0 else ""
		var dcol  = UITheme.ACCENT if delta >= 0 else UITheme.RED_LT
		status_col.add_child(UITheme.make_label("%s%d rating" % [dsign, delta], UITheme.FS_H2,
			dcol, HORIZONTAL_ALIGNMENT_CENTER))
		status_col.add_child(UITheme.make_label("%d  ·  %s" % [PlayerData.elo, PlayerData.get_title()],
			UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var unrated_title = "Pass & Play" if _local_mode else "Unrated game"
		var unrated_sub = "Local games don't change your rating." if _local_mode \
			else "Fallback results don't change your rating."
		status_col.add_child(UITheme.make_label(unrated_title, UITheme.FS_H3,
			UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		status_col.add_child(UITheme.make_label(unrated_sub,
			UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(status_panel)

	# Achievement — only when one was actually unlocked THIS game (the old code
	# showed achievements[-1], i.e. the most recent ever, which is why "Giant
	# Killer" could appear on a loss). Rendered as a gold pill, not a bare line.
	if new_achievement != "":
		var ach = PlayerData.ACHIEVEMENT_DEFS.get(new_achievement, {})
		if ach and String(ach.get("name", "")) != "":
			var cc = CenterContainer.new()
			cc.add_child(UITheme.make_pill_badge("🏅  " + String(ach.get("name", "")),
				Color(UITheme.GOLD, 0.16), UITheme.GOLD, UITheme.FS_SMALL))
			col.add_child(cc)

	col.add_child(UITheme.spacer(4))

	var review = UITheme.make_btn("Game Review", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	review.pressed.connect(func():
		GameModals.dismiss(self, "ResultOverlay")
		_review.start_analysis())
	col.add_child(review)

	if _online_mode:
		var back_online = UITheme.make_btn("Back to Online", UITheme.ACCENT, UITheme.FS_BODY, 56)
		back_online.pressed.connect(GameManager.show_online)
		col.add_child(back_online)
	else:
		var rematch = UITheme.make_btn("Rematch", UITheme.ACCENT, UITheme.FS_BODY, 56)
		rematch.pressed.connect(GameManager.show_game)
		col.add_child(rematch)

	var menu = UITheme.make_btn("Main Menu", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	menu.pressed.connect(GameManager.show_main_menu)
	col.add_child(menu)

	GameModals.show_modal_card(self, "ResultOverlay", col, 420)

# A circular medallion: a rendered glyph (✓ / ✕ / =) centered in a disc tinted
# by the result colour, with a soft matching border. Used as the result hero.
func _result_badge(glyph: String, tint: Color) -> Control:
	var holder = CenterContainer.new()
	var badge = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_CARD2.lerp(tint, 0.18)
	sb.set_corner_radius_all(39)
	sb.set_border_width_all(2)
	sb.border_color = Color(tint, 0.5)
	badge.add_theme_stylebox_override("panel", sb)
	badge.custom_minimum_size = Vector2(78, 78)
	var g = UITheme.make_label(glyph, UITheme.FS_H1, tint, HORIZONTAL_ALIGNMENT_CENTER)
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	badge.add_child(g)
	holder.add_child(badge)
	return holder

# ──────────────────────────────────────────────
#  Bookkeeping
# ──────────────────────────────────────────────
func _record_pos() -> void:
	_record_pos_for_state(_state)

func _record_pos_for_state(state) -> void:
	var key = ChessLogic.position_key(state)
	_pos_hist[key] = _pos_hist.get(key, 0) + 1

func _record_move(move: Dictionary, color: int) -> void:
	var after = ChessLogic.apply_move(_state, move)
	var is_capture = _state.board[move["to"]] != ChessLogic.EMPTY or move.get("ep", false)
	move["capture"] = is_capture
	var rec = {
		"fen": ChessLogic.state_to_fen(_state),
		"after_fen": ChessLogic.state_to_fen(after),
		"move": move.duplicate(),
		"color": color,
		"move_no": _state.fullmove,
		"san": ChessLogic.move_to_san(_state, move),
		"difficulty": _difficulty,
		"backend": AIEngine.backend_name(),
	}
	if color != _player_color and _difficulty == "stockfish_max" and AIEngine.stockfish_available():
		rec["engine_best"] = true
	_move_records.append(rec)

func _init_clock() -> void:
	var cfg = GameManager.TIME_MODES.get(GameManager.time_mode, GameManager.TIME_MODES["rapid"])
	_white_time = float(cfg.get("seconds", 0))
	_black_time = _white_time
	_time_increment = int(cfg.get("increment", 0))
	_timed_game = _white_time > 0.0

func _add_increment(color: int) -> void:
	if not _timed_game or _time_increment <= 0: return
	if color == ChessLogic.WHITE:
		_white_time += _time_increment
	else:
		_black_time += _time_increment

func _check_clock_warning() -> void:
	if not _timed_game: return
	var active_time = _white_time if _state.turn == ChessLogic.WHITE else _black_time
	var sec = int(ceil(active_time))
	if sec <= 10 and sec > 0 and sec != _last_clock_tick_second:
		_last_clock_tick_second = sec
		SoundManager.play_clock_tick()
		Haptics.tick()

func _play_move_sound(move: Dictionary) -> void:
	var st = ChessLogic.get_status(_state)
	if st["game_over"] and st.get("reason", "") == "checkmate":
		SoundManager.play_checkmate()
		Haptics.checkmate()
	elif st.get("in_check", false):
		SoundManager.play_check()
		Haptics.check()
	else:
		var capture = move.get("capture", false)
		SoundManager.play_move(capture)
		Haptics.impact(capture)

func _flag_time_loss() -> void:
	if _game_over: return
	_game_over = true
	_ai_thinking = false
	if _local_mode:
		var loser_white = _white_time <= 0.0
		_show_result_overlay("Black Wins!" if loser_white else "White Wins!", "time", 0)
		return
	var player_flagged = (_player_color == ChessLogic.WHITE and _white_time <= 0.0) or \
		(_player_color == ChessLogic.BLACK and _black_time <= 0.0)
	var score = 0.0 if player_flagged else 1.0
	var delta = _record_game_result(score)
	_show_result_overlay("You Lose" if player_flagged else "You Win!", "time", delta)

func _save_completed_game(result: String, reason: String) -> void:
	if _completed_saved or _move_records.is_empty(): return
	_completed_saved = true
	PlayerData.save_completed_game({
		"id": int(Time.get_unix_time_from_system()),
		"date": Time.get_datetime_string_from_system(),
		"difficulty": _difficulty,
		"player_color": _player_color,
		"time_mode": GameManager.time_mode,
		"rated": _rated_game,
		"allow_fallback": not _rated_game,
		"result": result,
		"reason": reason,
		"records": _move_records.duplicate(true),
	})

func _refresh_ui() -> void:
	_sync_board_to_history_view()
	_hud.refresh()

# Tapping the in-game ☰ confirms before leaving a live game, and saves NOW (not
# on the deferred _exit_tree) so the main menu immediately shows it under Continue.
func _confirm_leave_to_menu() -> void:
	if _game_over or _online_mode:
		GameManager.show_main_menu()
		return
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UITheme.make_label("Leave game?", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var msg = UITheme.make_label("Your progress is saved — pick it back up from Continue on the menu.",
		UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(msg)
	col.add_child(UITheme.spacer(4))
	var leave = UITheme.make_btn("Leave", UITheme.ACCENT, UITheme.FS_BODY, 56)
	leave.pressed.connect(func():
		GameModals.dismiss(self, "LeaveConfirm")
		_auto_save()
		GameManager.show_main_menu())
	col.add_child(leave)
	var stay = UITheme.make_btn("Keep Playing", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	stay.pressed.connect(func(): GameModals.dismiss(self, "LeaveConfirm"))
	col.add_child(stay)
	GameModals.show_modal_card(self, "LeaveConfirm", col, 380)

func _auto_save() -> void:
	if _online_mode: return   # the backend owns online match state
	# Save as soon as ANY half-move exists. Testing `_state.fullmove <= 1` skipped
	# real games: fullmove only increments after Black's move, so "White played a
	# move and left" (or Black left right after White's reply) was silently not
	# saved — while the leave dialog had just promised "your progress is saved",
	# and the main menu then showed no Continue card.
	if _game_over or _history.is_empty(): return
	var history_fens: Array = []
	for hist_state in _history:
		history_fens.append(ChessLogic.state_to_fen(hist_state))
	PlayerData.save_game_session(ChessLogic.state_to_fen(_state), _difficulty,
								 _player_color, _state.fullmove, GameManager.time_mode,
								 history_fens, _move_records, _white_time, _black_time,
								 _rated_game, not _rated_game)

# The most recent achievement unlocked this game (id), or "" if none — so the
# result modal only celebrates a freshly-earned badge, never a stale one.
func _newest_unlocked(prev: Array) -> String:
	var newest := ""
	for a in PlayerData.achievements:
		if a not in prev:
			newest = String(a)
	return newest

func _record_game_result(score: float) -> int:
	if not _rated_game:
		return 0
	var delta = PlayerData.record_result(AIEngine.get_difficulty_elo(_difficulty), score)
	# Keep the global Game Center leaderboard in sync with the local rating.
	var gc = get_tree().root.get_node_or_null("GameCenterManager")
	if gc != null:
		gc.submit_rating(PlayerData.elo)
	return delta

func _show_engine_unavailable() -> void:
	if _game_over: return
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UITheme.make_label("Engine Unavailable", UITheme.FS_H2, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UITheme.make_label(
		"Stockfish did not return a legal move. Rated play has been stopped so your rating is not affected.",
		UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var menu = UITheme.make_btn("Main Menu", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	menu.pressed.connect(GameManager.show_main_menu)
	col.add_child(menu)
	_game_over = true
	GameModals.show_modal_card(self, "EngineUnavailable", col, 420)
