extends Control
# Puzzles hub + solver.
#
# Hub: daily puzzle, endless tactics, and a 12-level progression journey.
# Solver: shared board UI for all three modes with hints, star scoring,
# mistake feedback, and a success overlay.

enum Mode { LEVEL, DAILY, ENDLESS }


# ── Solver state ──
var _mode: int = Mode.LEVEL
var _level_idx: int = -1
var _puzzle_idx: int = -1
var _puzzle: Dictionary = {}
var _state = null
var _start_state = null
var _solution: Array = []
var _step: int = 0
var _selected_sq: int = -1
var _mistakes: int = 0
var _hints_used: int = 0
var _move_hints: int = 0   # hints used on the CURRENT move (resets each move)
var _solved: bool = false
var _busy: bool = false       # opponent reply / wrong-move revert in flight
var _board: BoardVisual = null
var _feedback_lbl: Label = null
var _feedback_panel: PanelContainer = null
var _pips: Array = []
var _hint_btn: Button = null
var _loading_overlay: Control = null
var _session: int = 0   # bumped on every puzzle change; guards async callbacks

func _ready() -> void:
	PuzzleManager.daily_loaded.connect(_on_daily_loaded)
	PuzzleManager.daily_failed.connect(_on_daily_failed)
	PuzzleManager.next_loaded.connect(_on_next_loaded)
	_build_hub()

func _exit_tree() -> void:
	PuzzleManager.daily_loaded.disconnect(_on_daily_loaded)
	PuzzleManager.daily_failed.disconnect(_on_daily_failed)
	PuzzleManager.next_loaded.disconnect(_on_next_loaded)

func _clear() -> void:
	for child in get_children():
		child.queue_free()

func _wide_layout() -> bool:
	return get_viewport_rect().size.x >= 900

# ══════════════════════════════════════════════════════════════════════════════
#  HUB
# ══════════════════════════════════════════════════════════════════════════════
func _build_hub() -> void:
	_clear()
	_board = null
	_session += 1
	add_child(UITheme.make_page_bg())

	var wide = _wide_layout()
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if wide:
		scroll.offset_left = 92
	else:
		scroll.offset_bottom = -float(80 + UITheme.safe_bottom())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.hide_v_scrollbar(scroll)
	add_child(scroll)

	var outer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(outer)

	var margin = UITheme.page_panel(820, 22)
	outer.add_child(margin)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	col.add_child(UITheme.spacer(UITheme.safe_top()))
	col.add_child(UITheme.make_label("Puzzles", UITheme.FS_H1, UITheme.TEXT))

	col.add_child(_make_stats_row())
	col.add_child(UITheme.spacer(2))
	col.add_child(_make_daily_card())
	col.add_child(_make_endless_card())

	col.add_child(UITheme.spacer(6))
	var journey_row = HBoxContainer.new()
	col.add_child(journey_row)
	journey_row.add_child(UITheme.make_label("Journey", UITheme.FS_H3, UITheme.TEXT))
	var stars_lbl = UITheme.make_label("★ %d / %d" % [PuzzleManager.total_stars(), _max_stars()],
		UITheme.FS_SMALL, UITheme.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	journey_row.add_child(stars_lbl)

	for i in PuzzleManager.levels.size():
		col.add_child(_make_level_card(i))

	col.add_child(UITheme.spacer(10))
	var credit = UITheme.make_label("Puzzles from the Lichess open database (CC0).", UITheme.FS_CAPTION, UITheme.TEXT_MUTED)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(credit)
	col.add_child(UITheme.spacer(UITheme.safe_bottom() + 8))

	add_child(UITheme.make_app_nav("puzzles", wide))

func _max_stars() -> int:
	var n = 0
	for lv in PuzzleManager.levels:
		n += lv["puzzles"].size() * 3
	return n

func _make_stats_row() -> HBoxContainer:
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 10)
	var stats = [
		[str(PuzzleManager.rating), "Puzzle Rating", UITheme.GOLD],
		[str(PuzzleManager.streak), "Streak", UITheme.ACCENT_LT],
		[str(PuzzleManager.total_solved()), "Solved", UITheme.TEXT],
	]
	for s in stats:
		var card = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_MEDIUM)
		card.custom_minimum_size.y = 76
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v = VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(v)
		v.add_child(UITheme.make_label(s[0], UITheme.FS_H3, s[2], HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UITheme.make_label(s[1], UITheme.FS_CAPTION, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		row.add_child(card)
	return row

func _make_daily_card() -> Panel:
	var solved = PuzzleManager.is_daily_solved()
	var panel = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_LARGE, true)
	panel.custom_minimum_size.y = 92
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = panel.get_theme_stylebox("panel").duplicate()
	style.border_width_left = 4
	style.border_color = UITheme.GOLD
	panel.add_theme_stylebox_override("panel", style)

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(m)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var info = VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var title_row = HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_PASS
	title_row.add_theme_constant_override("separation", 8)
	var sun = _PuzzleIcon.new()
	sun.kind = "sun"
	sun.icon_color = UITheme.GOLD
	sun.custom_minimum_size = Vector2(22, 22)
	sun.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(sun)
	title_row.add_child(UITheme.make_label("Daily Puzzle", UITheme.FS_BODY_LG, UITheme.GOLD))
	info.add_child(title_row)
	var sub = "Solved — come back tomorrow!" if solved else "One fresh challenge every day"
	info.add_child(UITheme.make_label(sub, UITheme.FS_CAPTION, UITheme.TEXT_DIM))

	if solved:
		var done = UITheme.make_label("★".repeat(max(1, int(PuzzleManager.daily_cache.get("stars", 1)))),
			UITheme.FS_H3, UITheme.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		done.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(done)
	else:
		var play = UITheme.make_btn("Play", UITheme.GOLD.darkened(0.12), UITheme.FS_SMALL, 46, UITheme.R_SMALL)
		play.custom_minimum_size.x = 92
		play.size_flags_horizontal = Control.SIZE_SHRINK_END
		play.pressed.connect(_start_daily)
		row.add_child(play)
	return panel

func _make_endless_card() -> Panel:
	var panel = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_LARGE, true)
	panel.custom_minimum_size.y = 92
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = panel.get_theme_stylebox("panel").duplicate()
	style.border_width_left = 4
	style.border_color = UITheme.ACCENT
	panel.add_theme_stylebox_override("panel", style)

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(m)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var info = VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	info.add_child(UITheme.make_label("∞ Endless Tactics", UITheme.FS_BODY_LG, UITheme.ACCENT_LT))
	info.add_child(UITheme.make_label("Puzzles matched to your rating", UITheme.FS_CAPTION, UITheme.TEXT_DIM))

	var play = UITheme.make_btn("Play", UITheme.ACCENT_DIM, UITheme.FS_SMALL, 46, UITheme.R_SMALL)
	play.custom_minimum_size.x = 92
	play.size_flags_horizontal = Control.SIZE_SHRINK_END
	play.pressed.connect(_start_endless)
	row.add_child(play)
	return panel

# A level card. Tapping an unlocked card jumps straight into its next unsolved
# puzzle (the journey now has thousands of puzzles, so a per-puzzle chip grid
# doesn't scale — tap-to-play does). Locked cards show the star cost to open.
func _make_level_card(idx: int) -> PanelContainer:
	var lv = PuzzleManager.levels[idx]
	var unlocked = PuzzleManager.is_level_unlocked(idx)
	var solved = PuzzleManager.level_solved(idx)
	var stars = PuzzleManager.level_stars(idx)
	var count = lv["puzzles"].size()
	var complete = solved >= count

	var panel = UITheme.make_panel_container(UITheme.BG_CARD if unlocked else UITheme.BG_CARD.darkened(0.25), UITheme.R_MEDIUM)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(m)

	var v = VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_theme_constant_override("separation", 9)
	m.add_child(v)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)

	# Index / completion badge
	var badge = UITheme.make_panel(UITheme.ACCENT_DIM if complete else (UITheme.BG_CARD3 if unlocked else UITheme.BG_CARD2), 22)
	badge.custom_minimum_size = Vector2(44, 44)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_lbl = UITheme.make_label("✓" if complete else str(idx + 1), UITheme.FS_BODY_LG,
		UITheme.TEXT if unlocked else UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	badge_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(badge_lbl)
	row.add_child(badge)

	var info = VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)
	info.add_child(UITheme.make_label(lv["name"], UITheme.FS_BODY_LG, UITheme.TEXT if unlocked else UITheme.TEXT_MUTED))
	var sub_text = lv["subtitle"] if unlocked else "★ %d more to unlock" % PuzzleManager.stars_to_unlock(idx)
	info.add_child(UITheme.make_label(sub_text, UITheme.FS_CAPTION, UITheme.GOLD if not unlocked else UITheme.TEXT_MUTED))

	# Right: stars earned + solved count (unlocked) or a lock (locked)
	if unlocked:
		var rcol = VBoxContainer.new()
		rcol.mouse_filter = Control.MOUSE_FILTER_PASS
		rcol.alignment = BoxContainer.ALIGNMENT_CENTER
		rcol.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(rcol)
		rcol.add_child(UITheme.make_label("★ %d" % stars, UITheme.FS_SMALL,
			UITheme.GOLD if complete else UITheme.ACCENT_LT, HORIZONTAL_ALIGNMENT_RIGHT))
		rcol.add_child(UITheme.make_label("%d/%d" % [solved, count], UITheme.FS_CAPTION,
			UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	else:
		var lock = _PuzzleIcon.new()
		lock.kind = "lock"
		lock.icon_color = UITheme.TEXT_MUTED
		lock.custom_minimum_size = Vector2(22, 24)
		lock.size_flags_horizontal = Control.SIZE_SHRINK_END
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lock)

	if unlocked:
		var track = UITheme.make_panel(UITheme.BG_PAGE, 3)
		track.custom_minimum_size.y = 6
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(track)
		var fill = UITheme.make_panel(UITheme.GOLD if complete else UITheme.ACCENT, 3)
		fill.anchor_right = float(solved) / float(max(1, count))
		fill.anchor_bottom = 1.0
		track.add_child(fill)

		# Whole-card tap → next unsolved puzzle (no chips beneath to block it).
		var play_btn = Button.new()
		play_btn.set_script(UITheme.ScrollFriendlyButtonScript)
		play_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		play_btn.flat = true
		play_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		play_btn.pressed.connect(func():
			Haptics.selection()
			_start_level_puzzle(idx, PuzzleManager.first_unsolved_in_level(idx)))
		panel.add_child(play_btn)
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	return panel

# ══════════════════════════════════════════════════════════════════════════════
#  STARTING PUZZLES
# ══════════════════════════════════════════════════════════════════════════════
func _start_level_puzzle(level_idx: int, puzzle_idx: int) -> void:
	var puzzle = PuzzleManager.level_puzzle(level_idx, puzzle_idx)
	if puzzle.is_empty():
		return
	_mode = Mode.LEVEL
	_level_idx = level_idx
	_puzzle_idx = puzzle_idx
	_begin(puzzle)

func _start_daily() -> void:
	_mode = Mode.DAILY
	_show_loading("Fetching today's puzzle…")
	PuzzleManager.request_daily()

func _start_endless() -> void:
	_mode = Mode.ENDLESS
	_show_loading("Finding a puzzle…")
	PuzzleManager.request_next()

func _on_daily_loaded(puzzle: Dictionary, _from_network: bool) -> void:
	if _mode != Mode.DAILY: return
	_begin(puzzle)

func _on_daily_failed() -> void:
	if _mode != Mode.DAILY: return
	_build_hub()

func _on_next_loaded(puzzle: Dictionary, _from_network: bool) -> void:
	if _mode != Mode.ENDLESS: return
	if puzzle.is_empty():
		_build_hub()
		return
	_begin(puzzle)

func _show_loading(text: String) -> void:
	if is_instance_valid(_loading_overlay):
		_loading_overlay.queue_free()
	_loading_overlay = ColorRect.new()
	_loading_overlay.color = Color(0, 0, 0, 0.55)
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_loading_overlay)
	var lbl = UITheme.make_label(text, UITheme.FS_BODY_LG, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_overlay.add_child(lbl)

# ══════════════════════════════════════════════════════════════════════════════
#  SOLVER
# ══════════════════════════════════════════════════════════════════════════════
func _begin(puzzle: Dictionary) -> void:
	_session += 1
	_puzzle = puzzle
	_solution = puzzle["solution"].duplicate()
	_step = 0
	_mistakes = 0
	_hints_used = 0
	_move_hints = 0
	_solved = false
	_busy = false
	_selected_sq = -1
	_state = ChessLogic.parse_fen(puzzle["fen"])
	_start_state = _state.copy()
	_build_solver()

func _restart_puzzle() -> void:
	_session += 1
	_state = _start_state.copy()
	_step = 0
	_solved = false
	_busy = false
	_selected_sq = -1
	_board.clear_selection()
	_board.clear_hint()
	_reset_move_hint_ui()
	_board.set_last_move(int(_puzzle.get("last_from", -1)), int(_puzzle.get("last_to", -1)))
	_refresh_board()
	_set_feedback(_objective_text(), UITheme.TEXT_DIM)
	_update_pips()

func _player_color() -> int:
	return _start_state.turn if _start_state else ChessLogic.WHITE

func _objective_text() -> String:
	var side = "White" if _player_color() == ChessLogic.WHITE else "Black"
	if _step == 0:
		return "%s to move — find the best move!" % side
	return "Keep going — find the follow-up."

func _source_title() -> String:
	match _mode:
		Mode.DAILY:   return "Daily Puzzle"
		Mode.ENDLESS: return "Endless Tactics"
		_:
			if _level_idx >= 0:
				return PuzzleManager.levels[_level_idx]["name"]
	return "Puzzle"

func _source_subtitle() -> String:
	match _mode:
		Mode.DAILY:   return "Daily challenge"
		Mode.ENDLESS: return "Matched to your rating"
		_:
			if _level_idx >= 0:
				return "Puzzle %d / %d" % [_puzzle_idx + 1,
					PuzzleManager.levels[_level_idx]["puzzles"].size()]
	return ""

func _build_solver() -> void:
	_clear()
	_loading_overlay = null
	add_child(UITheme.make_page_bg())

	var wide = _wide_layout()
	var root: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if wide:
		root.offset_left = 92
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# ── Top (portrait) / side (wide) column: header + feedback + pips ──
	var panel_col = VBoxContainer.new()
	panel_col.add_theme_constant_override("separation", 10)
	if wide:
		panel_col.custom_minimum_size.x = 340
		panel_col.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var m = MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", UITheme.safe_top() + 10)
	m.add_theme_constant_override("margin_bottom", 4)
	m.add_child(panel_col)

	# Header row: back, title/subtitle, rating chip
	var header = HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	panel_col.add_child(header)

	var back = UITheme.make_btn("‹", UITheme.BG_CARD2, UITheme.FS_H3, 48, UITheme.R_SMALL)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size.x = 52
	back.pressed.connect(_build_hub)
	header.add_child(back)

	var title_col = VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_col.add_theme_constant_override("separation", 1)
	header.add_child(title_col)
	var title_lbl = UITheme.make_label(_source_title(), UITheme.FS_BODY_LG, UITheme.TEXT)
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_col.add_child(title_lbl)
	var subtitle = _source_subtitle()
	if subtitle != "":
		var subtitle_lbl = UITheme.make_label(subtitle, UITheme.FS_CAPTION, UITheme.TEXT_MUTED)
		subtitle_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_col.add_child(subtitle_lbl)

	var rating = int(_puzzle.get("rating", 0))
	if rating > 0:
		var rating_pill = UITheme.make_pill_badge("★ %d" % rating, UITheme.BG_CARD2, UITheme.GOLD, UITheme.FS_CAPTION, 12, 7)
		rating_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
		rating_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(rating_pill)

	# Feedback strip
	_feedback_panel = PanelContainer.new()
	_feedback_panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_CARD, UITheme.R_SMALL))
	panel_col.add_child(_feedback_panel)
	var fm = MarginContainer.new()
	for side in ["left", "right"]:
		fm.add_theme_constant_override("margin_" + side, 14)
	fm.add_theme_constant_override("margin_top", 10)
	fm.add_theme_constant_override("margin_bottom", 10)
	_feedback_panel.add_child(fm)
	var frow = HBoxContainer.new()
	frow.add_theme_constant_override("separation", 10)
	fm.add_child(frow)
	_feedback_lbl = UITheme.make_label("", UITheme.FS_SMALL, UITheme.TEXT_DIM)
	_feedback_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frow.add_child(_feedback_lbl)

	# Progress pips
	var pips_row = HBoxContainer.new()
	pips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pips_row.add_theme_constant_override("separation", 8)
	panel_col.add_child(pips_row)
	_pips = []
	var player_moves = int(ceil(_solution.size() / 2.0))
	for i in player_moves:
		var pip = Panel.new()
		pip.custom_minimum_size = Vector2(26, 8)
		pip.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_CARD2, 4))
		pips_row.add_child(pip)
		_pips.append(pip)

	if wide:
		# Wide: controls live under the pips in the side column.
		panel_col.add_child(_make_solver_controls())
		root.add_child(m)

	# ── Board (inset + centered so it never bleeds to the screen edge) ──
	_board = BoardVisual.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.player_color = _player_color()
	_board.flipped = _player_color() == ChessLogic.BLACK
	_board.square_tapped.connect(_on_square_tapped)
	_board.drag_move.connect(_on_drag_move)
	if wide:
		root.add_child(_board)
	else:
		root.add_child(m)
		var board_wrap = MarginContainer.new()
		board_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		board_wrap.add_theme_constant_override("margin_left", 14)
		board_wrap.add_theme_constant_override("margin_right", 14)
		board_wrap.add_theme_constant_override("margin_top", 6)
		board_wrap.add_theme_constant_override("margin_bottom", 6)
		board_wrap.add_child(_board)
		root.add_child(board_wrap)
		# Bottom control bar — keeps the board centered and fills the screen.
		var controls_margin = MarginContainer.new()
		controls_margin.add_theme_constant_override("margin_left", 16)
		controls_margin.add_theme_constant_override("margin_right", 16)
		controls_margin.add_theme_constant_override("margin_top", 4)
		controls_margin.add_theme_constant_override("margin_bottom", UITheme.safe_bottom() + 14)
		controls_margin.add_child(_make_solver_controls())
		root.add_child(controls_margin)

	_board.set_last_move(int(_puzzle.get("last_from", -1)), int(_puzzle.get("last_to", -1)))
	_refresh_board()
	_set_feedback(_objective_text(), UITheme.TEXT_DIM)
	_update_pips()

# Restart + Hint, shown in a bottom bar (portrait) or under the pips (wide).
func _make_solver_controls() -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var retry = UITheme.make_btn("↺  Restart", UITheme.BG_CARD2, UITheme.FS_SMALL, 56, UITheme.R_MEDIUM)
	retry.tooltip_text = "Restart puzzle"
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.size_flags_stretch_ratio = 0.8
	retry.pressed.connect(func():
		if not _solved and not _busy:
			_restart_puzzle())
	row.add_child(retry)

	_hint_btn = UITheme.make_btn("?  Hint", UITheme.ACCENT_DIM, UITheme.FS_SMALL, 56, UITheme.R_MEDIUM)
	_hint_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_btn.pressed.connect(_on_hint)
	row.add_child(_hint_btn)
	return row

func _set_feedback(text: String, color: Color, bg: Color = UITheme.BG_CARD) -> void:
	if not is_instance_valid(_feedback_lbl): return
	_feedback_lbl.text = text
	_feedback_lbl.add_theme_color_override("font_color", color)
	_feedback_panel.add_theme_stylebox_override("panel", UITheme.panel_style(bg, UITheme.R_SMALL))

func _update_pips() -> void:
	var done = int(ceil(_step / 2.0))
	for i in _pips.size():
		if not is_instance_valid(_pips[i]): continue
		var color = UITheme.ACCENT if i < done else UITheme.BG_CARD2
		_pips[i].add_theme_stylebox_override("panel", UITheme.panel_style(color, 4))

func _refresh_board() -> void:
	if _board:
		_board.player_color = _state.turn
		_board.set_state(_state)

# ── Input ──
func _on_square_tapped(sq: int) -> void:
	if _state == null or _solved or _busy: return
	var own = _state.board[sq] != 0 and ChessLogic.piece_color(_state.board[sq]) == _state.turn
	if _selected_sq < 0:
		if own:
			_selected_sq = sq
			_board.set_selection(sq, ChessLogic.get_legal_moves_from(_state, sq).map(func(mv): return mv["to"]))
		return
	if sq == _selected_sq:
		_selected_sq = -1
		_board.clear_selection()
		return
	var legal = ChessLogic.get_legal_moves_from(_state, _selected_sq)
	var matches = legal.filter(func(mv): return int(mv["to"]) == sq)
	if not matches.is_empty():
		_try_player_move(matches[0])
	elif own:
		_selected_sq = sq
		_board.set_selection(sq, ChessLogic.get_legal_moves_from(_state, sq).map(func(mv): return mv["to"]))
	else:
		_selected_sq = -1
		_board.clear_selection()

func _on_drag_move(from_sq: int, to_sq: int) -> void:
	if _state == null or _solved or _busy: return
	var matches = ChessLogic.get_legal_moves_from(_state, from_sq).filter(func(mv): return int(mv["to"]) == to_sq)
	if not matches.is_empty():
		_try_player_move(matches[0])

# ── Core solving logic ──
func _try_player_move(move: Dictionary) -> void:
	if _step >= _solution.size(): return
	var expected: String = _solution[_step]
	var played = ChessLogic.move_to_uci(move)
	# Promotions: match on from/to, then play the exact expected promotion.
	if played != expected and played.substr(0, 4) == expected.substr(0, 4):
		var exact = ChessLogic.uci_to_move(_state, expected)
		if not exact.is_empty():
			move = exact
			played = expected
	if played == expected or _is_alternate_mate(move):
		_accept_move(move)
	else:
		_reject_move(move)

func _is_alternate_mate(move: Dictionary) -> bool:
	# Lichess convention: any move that delivers immediate checkmate is correct.
	var after = ChessLogic.apply_move(_state, move)
	var st = ChessLogic.get_status(after)
	return str(st.get("reason", "")) == "checkmate"

func _accept_move(move: Dictionary) -> void:
	_apply_move(move)
	_step += 1
	SoundManager.play_move(false)
	Haptics.impact(false)
	_update_pips()
	if _step >= _solution.size() or str(ChessLogic.get_status(_state).get("reason", "")) == "checkmate":
		_on_solved()
		return
	_set_feedback("Best move! Opponent is thinking…", UITheme.ACCENT_LT)
	_busy = true
	var session = _session
	await get_tree().create_timer(0.45).timeout
	if session != _session or _state == null or _solved or not is_instance_valid(_board): return
	if _step < _solution.size():
		var reply = ChessLogic.uci_to_move(_state, _solution[_step])
		if not reply.is_empty():
			_apply_move(reply)
			SoundManager.play_move(false)
		_step += 1
	_busy = false
	_reset_move_hint_ui()
	_set_feedback(_objective_text(), UITheme.TEXT_DIM)
	_update_pips()

func _reject_move(move: Dictionary) -> void:
	_mistakes += 1
	var before = _state
	_apply_move(move)
	Haptics.check()
	_set_feedback("Not quite — take that back and try again.", UITheme.RED_LT, UITheme.RED.darkened(0.55))
	_busy = true
	var session = _session
	await get_tree().create_timer(0.7).timeout
	if session != _session or not is_instance_valid(_board): return
	_state = before
	_board.set_last_move(int(_puzzle.get("last_from", -1)) if _step == 0 else -1, int(_puzzle.get("last_to", -1)) if _step == 0 else -1)
	_busy = false
	_refresh_board()
	_set_feedback(_objective_text(), UITheme.TEXT_DIM)

func _apply_move(move: Dictionary) -> void:
	_selected_sq = -1
	if _board:
		_board.clear_selection()
		_board.clear_hint()
		_board.set_last_move(int(move["from"]), int(move["to"]))
	_state = ChessLogic.apply_move(_state, move)
	_refresh_board()

func _on_hint() -> void:
	if _solved or _busy or _step >= _solution.size(): return
	var move = ChessLogic.uci_to_move(_state, _solution[_step])
	if move.is_empty(): return
	_hints_used += 1
	_move_hints += 1
	if _move_hints == 1:
		_board.set_hint(int(move["from"]), -1, 1)
		_set_feedback("Look at the highlighted piece.", UITheme.TEXT)
		if is_instance_valid(_hint_btn): _hint_btn.text = "💡  Show move"
	else:
		_board.set_hint(int(move["from"]), int(move["to"]), 1)
		_set_feedback("Play the arrow.", UITheme.TEXT)
		if is_instance_valid(_hint_btn): _hint_btn.disabled = true

# Re-arm the hint button for a new move (the piece→arrow progression and the
# disabled state are per-move; _hints_used keeps the total for star scoring).
func _reset_move_hint_ui() -> void:
	_move_hints = 0
	if is_instance_valid(_hint_btn):
		_hint_btn.disabled = false
		_hint_btn.text = "?  Hint"

# ── Completion ──
func _earned_stars() -> int:
	if _mistakes == 0 and _hints_used == 0: return 3
	if _mistakes <= 1 and _hints_used <= 1: return 2
	return 1

func _on_solved() -> void:
	_solved = true
	var stars_earned = _earned_stars()
	var clean = _mistakes == 0 and _hints_used == 0
	var rated = _mode != Mode.LEVEL
	var delta = PuzzleManager.record_result(_puzzle, stars_earned, clean, rated)
	if _mode == Mode.DAILY:
		PuzzleManager.mark_daily_solved(stars_earned)
	SoundManager.play_result(true)
	Haptics.result(true)
	_set_feedback("Solved!", UITheme.GOLD)
	_show_success(stars_earned, delta, rated)

func _show_success(stars_earned: int, delta: int, rated: bool) -> void:
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.6, 0.25)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(min(360, get_viewport_rect().size.x - 48), 0)
	card.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_CARD, UITheme.R_LARGE, true))
	center.add_child(card)

	var cm = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		cm.add_theme_constant_override("margin_" + side, 24)
	card.add_child(cm)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	cm.add_child(v)

	v.add_child(UITheme.make_label("Puzzle Solved!", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var stars_lbl = UITheme.make_label("★★★".substr(0, stars_earned) + "☆☆☆".substr(0, 3 - stars_earned),
		UITheme.FS_DISPLAY, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(stars_lbl)

	# Themes revealed after solving
	var themes: Array = _puzzle.get("themes", [])
	if not themes.is_empty():
		var nice = themes.slice(0, 3).map(func(t): return _humanize_theme(str(t)))
		v.add_child(UITheme.make_label(" · ".join(nice), UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	if rated and delta != 0:
		var sign = "+" if delta > 0 else ""
		var color = UITheme.ACCENT_LT if delta > 0 else UITheme.RED_LT
		v.add_child(UITheme.make_label("Puzzle rating %s%d → %d" % [sign, delta, PuzzleManager.rating],
			UITheme.FS_BODY, color, HORIZONTAL_ALIGNMENT_CENTER))
	if PuzzleManager.streak >= 2:
		v.add_child(UITheme.make_label("🔥 %d streak" % PuzzleManager.streak, UITheme.FS_SMALL, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))

	v.add_child(UITheme.spacer(4))
	var next_btn = UITheme.make_btn(_next_button_label(), UITheme.ACCENT, UITheme.FS_BODY, 58)
	next_btn.pressed.connect(_on_next_pressed)
	v.add_child(next_btn)
	var done_btn = UITheme.make_btn("Back to Puzzles", UITheme.BG_CARD2, UITheme.FS_SMALL, 48)
	done_btn.pressed.connect(_build_hub)
	v.add_child(done_btn)

	# Pop-in once the container has laid out (pivot needs the real size)
	card.scale = Vector2(0.85, 0.85)
	await get_tree().process_frame
	if not is_instance_valid(card): return
	card.pivot_offset = card.size * 0.5
	create_tween().tween_property(card, "scale", Vector2.ONE, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _next_button_label() -> String:
	match _mode:
		Mode.ENDLESS: return "Next Puzzle"
		Mode.DAILY:   return "Play Endless"
		_:
			if _level_idx >= 0 and _puzzle_idx + 1 < PuzzleManager.levels[_level_idx]["puzzles"].size():
				return "Next Puzzle"
			elif _level_idx >= 0 and _level_idx + 1 < PuzzleManager.levels.size() and PuzzleManager.is_level_unlocked(_level_idx + 1):
				return "Next Level"
	return "Back to Puzzles"

func _on_next_pressed() -> void:
	match _mode:
		Mode.ENDLESS:
			_start_endless()
		Mode.DAILY:
			_start_endless()
		_:
			if _level_idx >= 0 and _puzzle_idx + 1 < PuzzleManager.levels[_level_idx]["puzzles"].size():
				_start_level_puzzle(_level_idx, _puzzle_idx + 1)
			elif _level_idx >= 0 and _level_idx + 1 < PuzzleManager.levels.size() and PuzzleManager.is_level_unlocked(_level_idx + 1):
				_start_level_puzzle(_level_idx + 1, PuzzleManager.first_unsolved_in_level(_level_idx + 1))
			else:
				_build_hub()

func _humanize_theme(theme: String) -> String:
	const NAMES = {
		"mateIn1": "Mate in 1", "mateIn2": "Mate in 2", "mateIn3": "Mate in 3",
		"mateIn4": "Mate in 4", "mateIn5": "Mate in 5", "mate": "Checkmate",
		"hangingPiece": "Hanging piece", "discoveredAttack": "Discovered attack",
		"doubleCheck": "Double check", "smotheredMate": "Smothered mate",
		"backRankMate": "Back-rank mate", "queensideAttack": "Queenside attack",
		"kingsideAttack": "Kingside attack", "exposedKing": "Exposed king",
		"trappedPiece": "Trapped piece", "defensiveMove": "Defense",
		"quietMove": "Quiet move", "xRayAttack": "X-ray", "zugzwang": "Zugzwang",
		"capturingDefender": "Remove the defender", "interference": "Interference",
		"intermezzo": "In-between move", "advancedPawn": "Advanced pawn",
		"enPassant": "En passant", "castling": "Castling", "promotion": "Promotion",
		"underPromotion": "Underpromotion", "attackingF2F7": "f2/f7 attack",
		"oneMove": "One move", "short": "Short", "long": "Long", "veryLong": "Very long",
		"crushing": "Crushing", "advantage": "Advantage", "equality": "Equality",
		"opening": "Opening", "middlegame": "Middlegame", "endgame": "Endgame",
		"rookEndgame": "Rook endgame", "pawnEndgame": "Pawn endgame",
		"queenEndgame": "Queen endgame", "bishopEndgame": "Bishop endgame",
		"knightEndgame": "Knight endgame", "queenRookEndgame": "Q+R endgame",
		"master": "Master game", "masterVsMaster": "Master game", "superGM": "Super GM game",
	}
	if NAMES.has(theme): return NAMES[theme]
	# camelCase -> Title case fallback
	var out = ""
	for i in theme.length():
		var c = theme[i]
		if c == c.to_upper() and i > 0: out += " " + c.to_lower()
		else: out += c
	return out.capitalize() if out.length() < 3 else out[0].to_upper() + out.substr(1)


# Custom-drawn icons for the hub — emoji (☀ 🔒) render as blank tofu on iOS, so
# these are drawn as vector shapes that show on every platform.
class _PuzzleIcon extends Control:
	var kind: String = "sun"
	var icon_color: Color = UITheme.GOLD

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s = min(size.x, size.y)
		var c = size * 0.5
		match kind:
			"lock": _draw_lock(c, s)
			_: _draw_sun(c, s)

	func _draw_sun(c: Vector2, s: float) -> void:
		var r = s * 0.24
		draw_circle(c, r, icon_color)
		for i in 8:
			var a = TAU * float(i) / 8.0
			var dir = Vector2(cos(a), sin(a))
			draw_line(c + dir * (r + s * 0.08), c + dir * (r + s * 0.22), icon_color, max(2.0, s * 0.06))

	func _draw_lock(c: Vector2, s: float) -> void:
		# Body
		var bw = s * 0.52
		var bh = s * 0.40
		var body = Rect2(c.x - bw * 0.5, c.y - bh * 0.18, bw, bh)
		var sb := StyleBoxFlat.new()
		sb.bg_color = icon_color
		var rad = int(s * 0.07)
		sb.corner_radius_top_left = rad; sb.corner_radius_top_right = rad
		sb.corner_radius_bottom_left = rad; sb.corner_radius_bottom_right = rad
		draw_style_box(sb, body)
		# Shackle (open arc above the body)
		var sh_r = s * 0.18
		var sh_c = Vector2(c.x, c.y - bh * 0.18)
		draw_arc(sh_c, sh_r, PI, TAU, 16, icon_color, max(2.0, s * 0.07))
