class_name GameHud
extends Node
# Builds and refreshes the in-game chrome around the board for GameScreen:
# player/opponent bars, move-history strip, win-chance strip, control row,
# clocks and captured-material rows. Owns the label/widget references; the
# screen owns the game state this reads.
#
# Screen contract (read): _state, _player_color, _local_mode, _online_mode,
#   _difficulty, _rated_game, _hints_enabled, _move_records, _game_over,
#   _white_time/_black_time/_timed_game, _voice, _online, _board,
#   _last_is_landscape, _is_narrow()
# Screen contract (call): input/action handlers wired to the control row.

var screen: Control = null

var think_lbl: Label
var player_elo_lbl: Label
var opp_material_lbl: Label
var player_material_lbl: Label
var game_win_lbl: Label
var game_win_bar: Control
var move_lbl: Label
var opp_clock_lbl: Label
var player_clock_lbl: Label
var move_history_strip: Control
var move_history_scroll: ScrollContainer
var move_history_row: HBoxContainer
var move_history_prev_btn: Button
var move_history_next_btn: Button
var move_history_latest_btn: Button
var move_history_tokens: Array = []
var _history_scroll_serial: int = 0

# ── Build ──

func build() -> void:
	var vp = screen.get_viewport_rect().size
	screen._last_is_landscape = vp.x > vp.y
	if screen._last_is_landscape:
		_build_landscape()
	else:
		_build_portrait()
	# The voice banner is always a floating overlay so toggling it never
	# reflows the layout / nudges the board down.
	screen._voice.add_overlay()

func portrait_board_side() -> float:
	var vp = screen.get_viewport_rect().size
	var opp_h = (116 if screen._is_narrow() else 132) + UITheme.safe_top()
	var player_h = 96 if screen._is_narrow() else 112
	var controls_h = 68 + UITheme.safe_bottom()
	# opp bar + move-history strip (44) + win-chance strip (42) + player + controls.
	# The voice banner is no longer in the flow (it's a floating overlay).
	var reserved = opp_h + 44 + 42 + player_h + controls_h
	return min(vp.x, max(280.0, vp.y - reserved))

func _build_portrait() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	screen.add_child(vbox)

	vbox.add_child(_make_opp_bar())
	vbox.add_child(_make_move_history_strip())

	var board = _make_board()
	var board_side = portrait_board_side()
	board.custom_minimum_size = Vector2(board_side, board_side)
	# Expand + shrink-center: the board soaks up leftover vertical space and
	# centers in it, so the player bar and controls hug the screen bottom.
	board.size_flags_vertical   = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(board)

	vbox.add_child(_make_win_chance_strip())
	vbox.add_child(_make_player_bar())
	vbox.add_child(_make_controls())

func _build_landscape() -> void:
	var hbox = HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	screen.add_child(hbox)

	var board = _make_board()
	board.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(board)

	var side = VBoxContainer.new()
	side.custom_minimum_size.x = 360
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 0)
	hbox.add_child(side)
	var opp = _make_opp_bar()
	opp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(opp)
	side.add_child(_make_move_history_strip())
	side.add_child(_make_win_chance_strip())
	var player = _make_player_bar()
	player.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(player)
	side.add_child(_make_controls())

func _make_board() -> BoardVisual:
	var board = BoardVisual.new()
	board.flipped        = (screen._player_color == ChessLogic.BLACK)
	board.player_color   = screen._player_color
	board.set_board_theme(PlayerData.settings.get("board_theme", 0))
	board.set_piece_theme(PlayerData.settings.get("piece_theme", 0))
	board.set_piece_style(PlayerData.settings.get("piece_style", 0))
	board.square_tapped.connect(screen._on_square_tapped)
	board.drag_move.connect(screen._on_drag_move)
	screen._board = board
	return board

func _make_opp_bar() -> Control:
	var panel = Panel.new()
	# Tall enough for name + engine line + think line + captured-piece row;
	# must stay in sync with portrait_board_side().
	panel.custom_minimum_size.y = (116 if screen._is_narrow() else 132) + UITheme.safe_top()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_CARD, 0))

	var m = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left",   20)
	m.add_theme_constant_override("margin_right",  20)
	m.add_theme_constant_override("margin_top",    UITheme.safe_top() + (6 if screen._is_narrow() else 8))
	m.add_theme_constant_override("margin_bottom", 10 if screen._is_narrow() else 12)
	panel.add_child(m)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	m.add_child(hbox)

	# Avatar circle (drawn as a colored label). Pass & Play pins Black on top.
	var side_color = ChessLogic.BLACK if screen._local_mode else -screen._player_color
	var avatar = _make_avatar(side_color)
	hbox.add_child(avatar)

	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(info)

	var opp_name = "Black" if screen._local_mode else AIEngine.get_difficulty_label(screen._difficulty)
	if screen._online_mode:
		opp_name = screen._online.opp_name if screen._online.opp_name != "" else "Opponent"
	var name_lbl = UITheme.make_label(opp_name, UITheme.FS_H3, UITheme.TEXT)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(name_lbl)

	if screen._online_mode:
		var net_name = "Game Center" if screen._online.backend == "gamecenter" else "Online Match"
		info.add_child(UITheme.make_label(net_name, UITheme.FS_CAPTION, UITheme.TEXT_MUTED))
	elif screen._local_mode:
		info.add_child(UITheme.make_label("Pass & Play", UITheme.FS_CAPTION, UITheme.TEXT_MUTED))
	else:
		var opp_elo = AIEngine.get_difficulty_elo(screen._difficulty)
		var sub_lbl = UITheme.make_label(
			("Stockfish · %d" % opp_elo) if screen._rated_game else ("Unrated Fallback · %d" % opp_elo),
			UITheme.FS_SMALL,
			UITheme.TEXT_DIM if screen._rated_game else UITheme.GOLD)
		sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(sub_lbl)
	think_lbl = UITheme.make_label("", UITheme.FS_CAPTION, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	# Hidden while empty so it doesn't reserve a blank line between the rating and
	# the captured-pieces row (a container skips invisible children entirely).
	think_lbl.visible = false
	info.add_child(think_lbl)
	opp_material_lbl = _make_material_label(side_color)
	info.add_child(opp_material_lbl)

	var right = VBoxContainer.new()
	right.custom_minimum_size.x = 88
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right)
	opp_clock_lbl = _make_clock_label()
	right.add_child(opp_clock_lbl)

	return panel

func _make_player_bar() -> Control:
	var panel = Panel.new()
	# Tall enough for name + rating line + captured-piece row;
	# must stay in sync with portrait_board_side().
	panel.custom_minimum_size.y = 96 if screen._is_narrow() else 112
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_CARD, 0))

	var m = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left",   20)
	m.add_theme_constant_override("margin_right",  20)
	m.add_theme_constant_override("margin_top",    6 if screen._is_narrow() else 8)
	m.add_theme_constant_override("margin_bottom", 6 if screen._is_narrow() else 8)
	panel.add_child(m)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	m.add_child(hbox)

	hbox.add_child(_make_avatar(ChessLogic.WHITE if screen._local_mode else screen._player_color))

	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(info)

	info.add_child(UITheme.make_label("White" if screen._local_mode else "You", UITheme.FS_H3, UITheme.TEXT))

	player_elo_lbl = UITheme.make_label("", UITheme.FS_SMALL, PlayerData.get_title_color())
	info.add_child(player_elo_lbl)
	player_material_lbl = _make_material_label(ChessLogic.WHITE if screen._local_mode else screen._player_color)
	info.add_child(player_material_lbl)

	var right = VBoxContainer.new()
	right.custom_minimum_size.x = 88
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right)
	player_clock_lbl = _make_clock_label()
	right.add_child(player_clock_lbl)
	move_lbl = UITheme.make_label("", UITheme.FS_CAPTION, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	right.add_child(move_lbl)

	return panel

func _make_clock_label() -> Label:
	var lbl = UITheme.make_label("", UITheme.FS_SMALL, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.custom_minimum_size = Vector2(82, 28)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_color_override("font_color", UITheme.TEXT)
	return lbl

func _make_material_label(_color: int) -> Label:
	# Bigger than caption so the captured pieces are easy to read at a glance.
	var lbl = UITheme.make_label("", UITheme.FS_BODY_LG, UITheme.TEXT_DIM)
	# The default UI font has no chess glyphs on iOS, so captured pieces were
	# invisible there — use the same symbol-font chain as the board. A single
	# light colour keeps both rows readable on the dark bar (the dark piece
	# colour blended into the background).
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI Symbol", "Noto Sans Symbols2",
		"Apple Symbols", "DejaVu Sans", ""])
	lbl.add_theme_font_override("font", sf)
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return lbl

func _make_avatar(color: int) -> Control:
	var outer = Control.new()
	outer.custom_minimum_size = Vector2(52, 52)
	outer.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var disc_color = Color("#F5EDD4") if color == ChessLogic.WHITE else Color("#1A0E06")
	var style = UITheme.panel_style(disc_color, 36, true)
	panel.add_theme_stylebox_override("panel", style)
	outer.add_child(panel)

	var piece_style_idx = int(PlayerData.settings.get("piece_style", 0))
	var pstyle = BoardVisual.PIECE_STYLES[piece_style_idx % BoardVisual.PIECE_STYLES.size()]
	var king_char = pstyle["glyphs"][6]
	var icon = UITheme.make_label(king_char,
								  UITheme.FS_H3,
								  UITheme.BG_CARD if color == ChessLogic.WHITE else UITheme.TEXT,
								  HORIZONTAL_ALIGNMENT_CENTER)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(icon)
	return outer

func _make_win_chance_strip() -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size.y = 42
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_CARD, 0))

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(m)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(row)

	game_win_lbl = UITheme.make_label("", UITheme.FS_CAPTION, UITheme.TEXT_DIM)
	game_win_lbl.custom_minimum_size.x = 128
	game_win_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(game_win_lbl)

	game_win_bar = GameWidgets.WinChanceBar.new()
	game_win_bar.custom_minimum_size = Vector2(150, 20)
	game_win_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(game_win_bar)
	return panel

func _make_move_history_strip() -> Control:
	var panel = PanelContainer.new()
	move_history_strip = panel
	# Always visible: popping in after the first move would shift the board.
	panel.custom_minimum_size.y = 44
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(Color(UITheme.BG_CARD2, 0.86), 0))

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 5)
	m.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(m)

	var outer = HBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(outer)

	move_history_prev_btn = _make_history_nav_btn("‹", "Previous position")
	move_history_prev_btn.pressed.connect(screen._on_history_prev)
	outer.add_child(move_history_prev_btn)

	var scroll = ScrollContainer.new()
	move_history_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	move_history_row = HBoxContainer.new()
	move_history_row.add_theme_constant_override("separation", 8)
	move_history_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(move_history_row)

	move_history_next_btn = _make_history_nav_btn("›", "Next position")
	move_history_next_btn.pressed.connect(screen._on_history_next)
	outer.add_child(move_history_next_btn)

	move_history_latest_btn = _make_history_nav_btn("»", "Latest position")
	move_history_latest_btn.pressed.connect(screen._on_history_latest)
	outer.add_child(move_history_latest_btn)

	refresh_move_history_strip()
	return panel

func _make_history_nav_btn(text: String, tooltip: String) -> Button:
	var btn = UITheme.make_icon_btn(text, UITheme.BG_CARD2, 30)
	btn.tooltip_text = tooltip
	btn.add_theme_font_size_override("font_size", UITheme.FS_SMALL)
	return btn

func _make_controls() -> PanelContainer:
	var pc = PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_CARD, 0))

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left",   10)
	m.add_theme_constant_override("margin_right",  10)
	m.add_theme_constant_override("margin_top",    8)
	m.add_theme_constant_override("margin_bottom", 8 + UITheme.safe_bottom())
	pc.add_child(m)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	m.add_child(vbox)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	hbox.custom_minimum_size.y = 52
	vbox.add_child(hbox)

	var resign = UITheme.make_btn("⚑", UITheme.RED.darkened(0.15), UITheme.FS_H2, 52)
	resign.tooltip_text = "Resign"
	resign.pressed.connect(screen._on_resign_clicked)
	hbox.add_child(resign)

	if not screen._online_mode:
		var undo = UITheme.make_btn("⟲", UITheme.BG_CARD2, UITheme.FS_H2, 52)
		undo.tooltip_text = "Undo"
		undo.pressed.connect(screen._on_undo)
		hbox.add_child(undo)

	if screen._hints_enabled:
		# Custom-drawn bulb (the 💡 emoji doesn't render on iOS).
		screen._hint_btn = UITheme.make_btn("", UITheme.BG_CARD2, UITheme.FS_H2, 52)
		screen._hint_btn.tooltip_text = "Hint"
		screen._hint_btn.pressed.connect(screen._on_hint)
		var hint_icon = GameWidgets.HintIcon.new()
		hint_icon.host = screen._hint_btn
		hint_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen._hint_btn.add_child(hint_icon)
		hbox.add_child(screen._hint_btn)

	# Only offer voice input where the platform actually supports it
	# (macOS/iOS native SpeechInput); on stub platforms the button is hidden.
	if SpeechManager.is_available() and not screen._online_mode:
		# Animated waveform icon (replaces the 🎙 emoji, which fails on iOS).
		screen._voice_btn = UITheme.make_btn("", UITheme.BG_CARD2, UITheme.FS_H2, 52)
		screen._voice_btn.tooltip_text = "Voice move (tap to toggle, hands-free)"
		screen._voice_btn.pressed.connect(screen._voice.toggle)
		var wave = GameWidgets.VoiceWaveIcon.new()
		wave.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen._voice_btn.add_child(wave)
		screen._voice.wave_icon = wave
		hbox.add_child(screen._voice_btn)

	var menu = UITheme.make_btn("☰", UITheme.BG_CARD2, UITheme.FS_H2, 52)
	menu.tooltip_text = "Menu"
	menu.pressed.connect(screen._confirm_leave_to_menu)
	hbox.add_child(menu)

	return pc

# ── Refresh ──

func set_think(text: String) -> void:
	if think_lbl and is_instance_valid(think_lbl):
		think_lbl.text = text
		think_lbl.visible = text != ""

func refresh() -> void:
	if player_elo_lbl:
		if screen._local_mode:
			player_elo_lbl.text = "to move" if screen._state.turn == ChessLogic.WHITE else ""
		else:
			player_elo_lbl.text = "%d  ·  %s" % [PlayerData.elo, PlayerData.get_title()]
			player_elo_lbl.add_theme_color_override("font_color", PlayerData.get_title_color())
	if screen._local_mode and think_lbl:
		think_lbl.text = "to move" if screen._state.turn == ChessLogic.BLACK else ""
		think_lbl.visible = think_lbl.text != ""
	if screen._online_mode and think_lbl:
		think_lbl.text = "their move..." if screen._state.turn != screen._player_color and not screen._game_over else ""
		think_lbl.visible = think_lbl.text != ""
	if move_lbl:
		if screen._is_viewing_latest():
			move_lbl.text = "Move %d" % screen._state.fullmove
		else:
			move_lbl.text = "%d/%d" % [screen._history_display_ply(), screen._move_records.size()]
	refresh_clocks()
	_refresh_material_rows()
	_refresh_game_win_chance()
	refresh_move_history_strip()
	# Voice button uses a drawn waveform icon (no text); GameVoice drives it.

func refresh_clocks() -> void:
	if not screen._timed_game:
		if opp_clock_lbl: opp_clock_lbl.text = "--"
		if player_clock_lbl: player_clock_lbl.text = "--"
		return
	# Pass & Play keeps fixed bars (bottom = White) while the seat rotates.
	var bottom_color = ChessLogic.WHITE if screen._local_mode else screen._player_color
	var player_time = screen._white_time if bottom_color == ChessLogic.WHITE else screen._black_time
	var opp_time = screen._black_time if bottom_color == ChessLogic.WHITE else screen._white_time
	if player_clock_lbl:
		player_clock_lbl.text = GameFormat.format_clock(player_time)
		player_clock_lbl.add_theme_color_override("font_color", UITheme.RED_LT if player_time <= 30.0 else UITheme.TEXT)
	if opp_clock_lbl:
		opp_clock_lbl.text = GameFormat.format_clock(opp_time)
		opp_clock_lbl.add_theme_color_override("font_color", UITheme.RED_LT if opp_time <= 30.0 else UITheme.TEXT)

func _refresh_material_rows() -> void:
	var top_color = ChessLogic.BLACK if screen._local_mode else -screen._player_color
	var bottom_color = ChessLogic.WHITE if screen._local_mode else screen._player_color
	# Keep the labels visible even when empty: the bars reserve a line for
	# them, so the first capture doesn't reflow the layout.
	if opp_material_lbl:
		opp_material_lbl.text = GameFormat.material_row_text(screen._state, top_color)
	if player_material_lbl:
		player_material_lbl.text = GameFormat.material_row_text(screen._state, bottom_color)

func _refresh_game_win_chance() -> void:
	if not is_instance_valid(game_win_bar): return
	var white_win = GameFormat.win_percent_for_white(AIEngine.estimate_eval_cp(screen._state))
	var right_pct = white_win if screen._local_mode or screen._player_color == ChessLogic.WHITE else 100.0 - white_win
	game_win_bar.left_color = Color("#171A17") if screen._local_mode else UITheme.BG_CARD3
	game_win_bar.right_color = Color("#EDE9DA") if screen._local_mode else UITheme.ACCENT
	game_win_bar.set_target_pct(right_pct, true)
	if game_win_lbl:
		if screen._local_mode:
			game_win_lbl.text = "B %d / W %d" % [int(round(100.0 - white_win)), int(round(white_win))]
		else:
			game_win_lbl.text = "Bot %d / You %d" % [int(round(100.0 - right_pct)), int(round(right_pct))]

func refresh_move_history_strip() -> void:
	if not is_instance_valid(move_history_strip) or not is_instance_valid(move_history_row):
		return
	for child in move_history_row.get_children():
		child.queue_free()
	move_history_tokens = []
	_refresh_history_nav_buttons()
	if screen._move_records.is_empty():
		return
	var active_move_idx = screen._history_active_move_index()
	for i in range(screen._move_records.size()):
		var rec = screen._move_records[i]
		var color = int(rec.get("color", ChessLogic.WHITE))
		var move_no = int(rec.get("move_no", 1))
		if color == ChessLogic.WHITE or i == 0:
			var prefix = "%d." % move_no if color == ChessLogic.WHITE else "%d..." % move_no
			move_history_row.add_child(_make_move_history_prefix(prefix))
		var san = str(rec.get("san", ""))
		var move = rec.get("move", {})
		if san == "" and typeof(move) == TYPE_DICTIONARY and not move.is_empty():
			san = ChessLogic.move_to_uci(move)
		if san == "":
			san = "..."
		var token = _make_move_history_token(san, i == active_move_idx)
		move_history_tokens.append(token)
		move_history_row.add_child(token)
	_history_scroll_serial += 1
	if screen._is_viewing_latest():
		call_deferred("_scroll_move_history_end", _history_scroll_serial)
	elif active_move_idx >= 0:
		call_deferred("_scroll_move_history_active", _history_scroll_serial, active_move_idx)

func _refresh_history_nav_buttons() -> void:
	var latest = screen._move_records.size()
	var ply = screen._history_display_ply()
	if is_instance_valid(move_history_prev_btn):
		move_history_prev_btn.disabled = latest <= 0 or ply <= 0
	if is_instance_valid(move_history_next_btn):
		move_history_next_btn.disabled = latest <= 0 or ply >= latest
	if is_instance_valid(move_history_latest_btn):
		move_history_latest_btn.disabled = latest <= 0 or ply >= latest

func _make_move_history_prefix(text: String) -> Label:
	var lbl = UITheme.make_label(text, UITheme.FS_CAPTION, UITheme.TEXT_MUTED)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl

func _make_move_history_token(text: String, active: bool) -> PanelContainer:
	var token = UITheme.make_pill_badge(
		text,
		Color(UITheme.ACCENT_DIM, 0.82) if active else Color(UITheme.BG_CARD3, 0.72),
		UITheme.TEXT if active else UITheme.TEXT_DIM,
		UITheme.FS_CAPTION,
		10,
		4)
	token.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return token

func _scroll_move_history_end(serial: int) -> void:
	if not is_instance_valid(move_history_scroll): return
	var tree = move_history_scroll.get_tree()
	if tree == null: return
	await tree.process_frame
	await tree.process_frame
	if serial != _history_scroll_serial:
		return
	if not is_instance_valid(move_history_scroll): return
	var bar = move_history_scroll.get_h_scroll_bar()
	if bar:
		bar.value = bar.max_value
		move_history_scroll.scroll_horizontal = int(bar.max_value)

func _scroll_move_history_active(serial: int, active_idx: int) -> void:
	if not is_instance_valid(move_history_scroll): return
	var tree = move_history_scroll.get_tree()
	if tree == null: return
	await tree.process_frame
	if serial != _history_scroll_serial:
		return
	if not is_instance_valid(move_history_scroll): return
	if active_idx < 0 or active_idx >= move_history_tokens.size(): return
	var token = move_history_tokens[active_idx]
	if is_instance_valid(token):
		move_history_scroll.ensure_control_visible(token)
