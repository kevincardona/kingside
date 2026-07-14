class_name GameReview
extends Node
# Post-game review for GameScreen: engine analysis request, the stats modal,
# and the full-screen move-by-move review overlay (board + eval graph +
# timeline scrubber). Reads finished-game data from the hosting screen
# (_move_records, _player_color, _local_mode) and renders on top of it.

var screen: Control = null

var _records: Array = []
var _idx: int = 0
var _data: Dictionary = {}
var _cancelled: bool = false
var _show_best: bool = false

var _board: BoardVisual = null
var _title_lbl: Label = null
var _note_lbl: Label = null
var _slider: HSlider = null
var _count_lbl: Label = null
var _graph: UIStockGraph = null
var _badge_container: HBoxContainer = null
var _eval_lbl: Label = null
var _win_bar: Control = null
var _win_lbl: Label = null
var _best_lbl: Label = null
var _loss_lbl: Label = null
var _material_lbl: Label = null

# ── Analysis ──

func start_analysis() -> void:
	_cancelled = false
	_show_loading()
	var on_done = func(result: Dictionary):
		var loading = screen.find_child("ReviewLoading", true, false)
		if loading: loading.queue_free()
		if _cancelled: return
		_data = result
		_records = result.get("moves", [])
		_idx = 0
		show_stats_modal(result, false)
	AIEngine.review_ready.connect(on_done, CONNECT_ONE_SHOT)
	AIEngine.request_review(screen._move_records.duplicate(true), screen._player_color)

func _show_loading() -> ColorRect:
	var ov = GameModals.make_overlay(screen, "ReviewLoading")
	var vp = screen.get_viewport_rect().size
	var card_w = min(340.0, max(280.0, vp.x - 56.0))
	var pad := 26

	# Compact card whose HEIGHT is fitted to its content after the first frame
	# (see _fit_loading_card), so the Cancel button always keeps an even margin
	# from the card edge instead of riding it.
	var card = Panel.new()
	card.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.BG_CARD, UITheme.R_LARGE, true))
	card.anchor_left = 0.5; card.anchor_right = 0.5
	card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -card_w * 0.5; card.offset_right = card_w * 0.5
	card.offset_top = -150.0; card.offset_bottom = 150.0
	ov.add_child(card)

	var m = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, pad)
	card.add_child(m)

	var col = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	m.add_child(col)

	var spinner = GameWidgets.ReviewSpinner.new()
	spinner.custom_minimum_size = Vector2(46, 46)
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(spinner)
	col.add_child(UITheme.make_label("Analyzing game…", UITheme.FS_BODY_LG, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var note = UITheme.make_label("This may take a minute for longer games.", UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = card_w - pad * 2
	col.add_child(note)
	col.add_child(UITheme.spacer(2))
	var cancel = UITheme.make_btn("Cancel", UITheme.BG_CARD2, UITheme.FS_SMALL, 44, UITheme.R_SMALL)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.custom_minimum_size.x = 150
	cancel.pressed.connect(func():
		_cancelled = true
		GameModals.dismiss(screen, "ReviewLoading")
		# A review opened from a completed game has no board underneath, so
		# dismissing the loader would leave an empty screen — go back instead.
		if screen._board == null:
			GameManager.show_profile())
	col.add_child(cancel)

	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(spinner, "phase", TAU, 0.9).from(0.0)
	tween.tween_interval(0.01)

	_fit_loading_card(card, col, pad)
	return ov

# Resize the loader card to hug its content (after one frame, once labels have
# their wrapped height), keeping symmetric top/bottom padding so the Cancel
# button never sits flush against the card edge.
func _fit_loading_card(card: Panel, col: Control, pad: int) -> void:
	await screen.get_tree().process_frame
	if not is_instance_valid(card) or not is_instance_valid(col): return
	var h = clampf(col.get_combined_minimum_size().y + pad * 2, 220.0, 360.0)
	card.offset_top = -h * 0.5
	card.offset_bottom = h * 0.5

# ── Stats modal ──

func show_stats_modal(review_data: Dictionary, on_review_page: bool = false) -> void:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)

	col.add_child(UITheme.make_label("Game Review", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var acc = int(round(review_data.get("accuracy", 0.0)))
	var avg_win_loss = float(review_data.get("avg_win_loss", 0.0))
	var review_moments = int(review_data.get("review_moments", review_data.get("misses", []).size()))
	var sharpest_loss = float(review_data.get("sharpest_loss", 0.0))
	var acc_color = GameFormat.accuracy_color(acc)
	var moment_color = UITheme.ACCENT if review_moments <= 1 else (UITheme.GOLD if review_moments <= 4 else UITheme.RED_LT)

	# Hero scorecard: a prominent accuracy ring (it draws its own % inside) beside
	# the review-moment count, with the win-drop context underneath. One tight
	# card, clear hierarchy — no redundant duplicate number.
	var top_panel = UITheme.make_panel_container(UITheme.BG_CARD2, UITheme.R_MEDIUM)
	top_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top_m = MarginContainer.new()
	for s in ["left","right","top","bottom"]:
		top_m.add_theme_constant_override("margin_"+s, 18)
	top_panel.add_child(top_m)
	var top_vbox = VBoxContainer.new()
	top_vbox.add_theme_constant_override("separation", 12)
	top_m.add_child(top_vbox)
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 8)
	top_vbox.add_child(top_hbox)

	var acc_cell = VBoxContainer.new()
	acc_cell.alignment = BoxContainer.ALIGNMENT_CENTER
	acc_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc_cell.add_theme_constant_override("separation", 6)
	var ring_holder = Control.new()
	ring_holder.custom_minimum_size = Vector2(66, 66)
	ring_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var acc_ring = GameWidgets.AccuracyRing.new()
	acc_ring.accuracy = acc
	acc_ring.ring_color = acc_color
	acc_ring.draw_pct = 1.0
	acc_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring_holder.add_child(acc_ring)
	acc_cell.add_child(ring_holder)
	acc_cell.add_child(UITheme.make_label("Accuracy", UITheme.FS_CAPTION, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	top_hbox.add_child(acc_cell)

	var vdiv = VSeparator.new()
	vdiv.custom_minimum_size = Vector2(1, 60)
	vdiv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vdiv.add_theme_color_override("color", UITheme.BG_CARD3)
	top_hbox.add_child(vdiv)

	var moments_vbox = VBoxContainer.new()
	moments_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	moments_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moments_vbox.add_theme_constant_override("separation", 2)
	moments_vbox.add_child(UITheme.make_label(str(review_moments), UITheme.FS_H1, moment_color, HORIZONTAL_ALIGNMENT_CENTER))
	moments_vbox.add_child(UITheme.make_label("Review Moments", UITheme.FS_CAPTION, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	top_hbox.add_child(moments_vbox)

	var context = UITheme.make_label(
		"Avg win drop %s  ·  sharpest drop %s" % [
			GameFormat.format_pct(avg_win_loss),
			GameFormat.format_pct(sharpest_loss)],
		UITheme.FS_CAPTION, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_vbox.add_child(context)
	col.add_child(top_panel)

	# Move quality comparison table
	var table_panel = UITheme.make_panel_container(UITheme.BG_CARD2, UITheme.R_MEDIUM)
	table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table_m = MarginContainer.new()
	for s in ["left","right","top","bottom"]:
		table_m.add_theme_constant_override("margin_"+s, 12)
	table_panel.add_child(table_m)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	table_m.add_child(grid)

	grid.add_child(UITheme.make_label("Move Quality", UITheme.FS_CAPTION, UITheme.TEXT_MUTED))
	grid.add_child(UITheme.make_label("You", UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	grid.add_child(UITheme.make_label("Bot", UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	# Estimated rating each side played at this game (a fun ballpark — single
	# games are noisy). Highlighted so it stands apart from the quality counts.
	var you_rating = int(review_data.get("player_rating", 0))
	var bot_rating = int(review_data.get("opponent_rating", 0))
	if you_rating > 0 and bot_rating > 0:
		grid.add_child(UITheme.make_label("Played like", UITheme.FS_SMALL, UITheme.GOLD))
		grid.add_child(UITheme.make_label(_rating_range(you_rating), UITheme.FS_SMALL, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(UITheme.make_label(_rating_range(bot_rating), UITheme.FS_SMALL, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))

	var counts = _counts(review_data.get("moves", []))
	var quality_rows = [
		{"name": "Best",       "icon": "✓",  "color": UITheme.ACCENT},
		{"name": "Slight",     "icon": "!",  "color": UITheme.ACCENT_LT},
		{"name": "Inaccuracy", "icon": "?",  "color": UITheme.GOLD},
		{"name": "Mistake",    "icon": "??", "color": UITheme.ORANGE},
		{"name": "Blunder",    "icon": "✕",  "color": UITheme.RED_LT},
	]
	for qr in quality_rows:
		grid.add_child(UITheme.make_label("%s  %s" % [qr["icon"], qr["name"]], UITheme.FS_SMALL, qr["color"]))
		var you = counts["player"].get(qr["name"], 0)
		var bot = counts["bot"].get(qr["name"], 0)
		var you_col: Color = qr["color"] if (you > 0 and qr["name"] != "Best") else (UITheme.ACCENT if you > 0 else UITheme.TEXT_MUTED)
		var bot_col: Color = qr["color"] if (bot > 0 and qr["name"] != "Best") else (UITheme.ACCENT if bot > 0 else UITheme.TEXT_MUTED)
		grid.add_child(UITheme.make_label(str(you), UITheme.FS_BODY, you_col, HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(UITheme.make_label(str(bot), UITheme.FS_BODY, bot_col, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(table_panel)

	col.add_child(UITheme.spacer(4))

	# Action buttons
	if on_review_page:
		var close = UITheme.make_btn("Close", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
		close.pressed.connect(func(): GameModals.dismiss(screen, "StatsModal"))
		col.add_child(close)
	else:
		var review_btn = UITheme.make_btn("Review Moves  →", UITheme.ACCENT, UITheme.FS_BODY, 56)
		review_btn.pressed.connect(func():
			GameModals.dismiss(screen, "StatsModal")
			open_review_page(review_data))
		col.add_child(review_btn)

		var menu_btn = UITheme.make_btn("Main Menu", UITheme.BG_CARD2, UITheme.FS_SMALL, 50)
		menu_btn.pressed.connect(func():
			GameModals.dismiss(screen, "StatsModal")
			GameManager.show_main_menu())
		col.add_child(menu_btn)

	GameModals.show_modal_card(screen, "StatsModal", col, 460)

# Single-game "played like" is noisy, so show a ballpark RANGE (rounded to 50),
# not a false-precise number. The band widens with the estimate.
func _rating_range(center: int) -> String:
	var band = clampi(int(round(float(center) * 0.12 / 50.0)) * 50, 100, 350)
	var lo = int(round(float(maxi(100, center - band)) / 50.0)) * 50
	var hi = int(round(float(center + band) / 50.0)) * 50
	return "~%d–%d" % [lo, hi]

# ── Full review page ──

func open_review_page(review_data: Dictionary) -> void:
	_data = review_data
	_records = review_data.get("moves", [])
	_idx = 0

	var ov = GameModals.make_overlay(screen, "ReviewOverlay")
	ov.color = UITheme.BG_PAGE

	var vp = screen.get_viewport_rect().size
	var landscape = vp.x >= vp.y

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	margin.add_theme_constant_override("margin_top",    UITheme.safe_top() + 10)
	margin.add_theme_constant_override("margin_bottom", UITheme.safe_bottom() + 8)
	ov.add_child(margin)

	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	# ── Header card ──
	var acc = int(round(review_data.get("accuracy", 0.0)))
	var avg_win_loss = float(review_data.get("avg_win_loss", 0.0))
	var review_moments = int(review_data.get("review_moments", review_data.get("misses", []).size()))
	var acc_color = GameFormat.accuracy_color(acc)
	var counts = _counts(review_data.get("moves", []))

	var header_panel = PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.BG_CARD, UITheme.R_MEDIUM, true))
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header_m = MarginContainer.new()
	header_m.add_theme_constant_override("margin_left",   12)
	header_m.add_theme_constant_override("margin_right",  12)
	header_m.add_theme_constant_override("margin_top",    8)
	header_m.add_theme_constant_override("margin_bottom", 8)
	header_panel.add_child(header_m)
	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 4)
	header_m.add_child(header_vbox)

	# Top row: accuracy ring + stats column
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vbox.add_child(top_row)

	# Accuracy ring (custom drawn arc)
	var ring_size = 58
	var ring_container = Control.new()
	ring_container.custom_minimum_size = Vector2(ring_size, ring_size)
	ring_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(ring_container)
	var ring = GameWidgets.AccuracyRing.new()
	ring.accuracy = acc
	ring.ring_color = acc_color
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring_container.add_child(ring)
	# Animate the ring fill
	var ring_tween = create_tween()
	ring_tween.tween_property(ring, "draw_pct", 1.0, 0.6).from(0.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Stats column
	var stats_col = VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 2)
	stats_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(stats_col)

	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	stats_col.add_child(title_row)
	title_row.add_child(UITheme.make_label("Game Review", UITheme.FS_BODY_LG, UITheme.TEXT))

	var stats_line = UITheme.make_label(
		"%d moments  ·  %s avg drop  ·  %d moves" % [
			review_moments,
			GameFormat.format_pct(avg_win_loss),
			_records.size()],
		UITheme.FS_CAPTION, UITheme.TEXT_MUTED)
	stats_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_col.add_child(stats_line)

	# Quality summary row — compact inline badges
	var quality_row = HBoxContainer.new()
	quality_row.add_theme_constant_override("separation", 6)
	stats_col.add_child(quality_row)

	var quality_defs = [
		{"name": "Best", "icon": "✓", "color": UITheme.ACCENT},
		{"name": "Slight", "icon": "!", "color": UITheme.ACCENT_LT},
		{"name": "Inaccuracy", "icon": "?", "color": UITheme.GOLD},
		{"name": "Mistake", "icon": "??", "color": UITheme.ORANGE},
		{"name": "Blunder", "icon": "✕", "color": UITheme.RED_LT},
	]
	for qd in quality_defs:
		var cnt = counts["player"].get(qd["name"], 0)
		if cnt > 0:
			var ql = UITheme.make_label(
				"%s %d" % [qd["icon"], cnt],
				UITheme.FS_CAPTION, qd["color"])
			ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
			quality_row.add_child(ql)

	# Evaluation graph
	var evals: Array = []
	var gcolors: Array[Color] = []
	evals.append(0) # Start at 0
	gcolors.append(Color.TRANSPARENT)
	for rec in _records:
		var analysis = rec.get("analysis", {})
		var ev = analysis.get("played_eval", 0)
		var tag = analysis.get("tag", "Best or good")
		evals.append(clamp(float(ev) / 100.0, -10.0, 10.0))
		gcolors.append(GameFormat.color_for_tag(tag))

	var graph_container = Control.new()
	graph_container.custom_minimum_size.y = 48
	graph_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vbox.add_child(graph_container)

	_graph = UIStockGraph.new()
	_graph.data = evals
	_graph.use_center_line = true
	_graph.use_territory_fill = true
	_graph.auto_range = false
	_graph.point_colors = gcolors
	_graph.min_value = -10.0
	_graph.max_value = 10.0
	_graph.color = UITheme.GOLD
	# The ±10 scale numbers added clutter without much meaning — the centre
	# line already reads as "even", above as White, below as Black.
	_graph.show_y_labels = false
	_graph.y_label_width = 6.0
	_graph.x_padding = 12.0
	_graph.y_padding = 10.0
	_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph_container.add_child(_graph)

	root.add_child(header_panel)

	# ── Body ──
	var body: BoxContainer = HBoxContainer.new() if landscape else VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	root.add_child(body)

	# Board
	_board = BoardVisual.new()
	var safe_v = UITheme.safe_top() + UITheme.safe_bottom()
	# Portrait: give the board a smaller slice so the detail/nav panel below has
	# more room (it was cramped enough to need a scrollbar on iPhone).
	var board_min = min(520.0, vp.y - 190.0 - safe_v) if landscape else min(vp.x - 20.0, (vp.y - safe_v) * 0.39)
	_board.custom_minimum_size  = Vector2(board_min, board_min)
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical   = Control.SIZE_SHRINK_CENTER if not landscape \
											else Control.SIZE_EXPAND_FILL
	_board.flipped        = (screen._player_color == ChessLogic.BLACK)
	_board.player_color   = screen._player_color
	_board.set_board_theme(PlayerData.settings.get("board_theme", 0))
	_board.set_piece_theme(PlayerData.settings.get("piece_theme", 0))
	_board.set_piece_style(PlayerData.settings.get("piece_style", 0))
	body.add_child(_board)

	# ── Side panel ──
	var side_card = Panel.new()
	side_card.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.BG_CARD, UITheme.R_MEDIUM, true))
	side_card.custom_minimum_size.x = 340 if landscape else 0
	side_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_card.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(side_card)

	var side_m = MarginContainer.new()
	side_m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	side_m.add_theme_constant_override("margin_left",   12)
	side_m.add_theme_constant_override("margin_right",  12)
	side_m.add_theme_constant_override("margin_top",    8)
	side_m.add_theme_constant_override("margin_bottom", 8)
	side_card.add_child(side_m)

	var side = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 4)
	side_m.add_child(side)

	var win_row = HBoxContainer.new()
	win_row.add_theme_constant_override("separation", 10)
	win_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_row.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_child(win_row)

	_win_lbl = UITheme.make_label("", UITheme.FS_CAPTION, UITheme.TEXT_DIM)
	_win_lbl.custom_minimum_size.x = 128
	_win_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	win_row.add_child(_win_lbl)

	_win_bar = GameWidgets.WinChanceBar.new()
	_win_bar.custom_minimum_size = Vector2(180, 26)
	_win_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_row.add_child(_win_bar)

	var detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	detail_scroll.custom_minimum_size.y = 96
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(detail_scroll)

	var detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 4)
	detail_scroll.add_child(detail)

	# Move quality badge row (dynamic — updated per move)
	_badge_container = HBoxContainer.new()
	_badge_container.add_theme_constant_override("separation", 6)
	detail.add_child(_badge_container)

	var move_row = HBoxContainer.new()
	move_row.add_theme_constant_override("separation", 8)
	move_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(move_row)

	_title_lbl = UITheme.make_label("", UITheme.FS_BODY_LG, UITheme.TEXT)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_row.add_child(_title_lbl)

	_eval_lbl = UITheme.make_label("", UITheme.FS_CAPTION, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_eval_lbl.custom_minimum_size.x = 60
	_eval_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	move_row.add_child(_eval_lbl)

	_material_lbl = UITheme.make_label("", UITheme.FS_CAPTION, UITheme.TEXT_DIM)
	_material_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_material_lbl)

	# Best move suggestion label
	_best_lbl = UITheme.make_label("", UITheme.FS_SMALL, UITheme.ACCENT_LT)
	_best_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_best_lbl)

	# CP loss label
	_loss_lbl = UITheme.make_label("", UITheme.FS_CAPTION, UITheme.TEXT_MUTED)
	detail.add_child(_loss_lbl)

	# Note label (kept for additional context)
	_note_lbl = UITheme.make_label("", UITheme.FS_CAPTION, UITheme.TEXT_MUTED)
	_note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_note_lbl)

	# ── Timeline scrubber ──
	var timeline = VBoxContainer.new()
	timeline.add_theme_constant_override("separation", 0)
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(timeline)

	_count_lbl = UITheme.make_label("", UITheme.FS_CAPTION,
		UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	timeline.add_child(_count_lbl)

	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = max(0, _records.size() - 1)
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size.y = 34
	_slider.value_changed.connect(func(v): set_index(int(v)))
	timeline.add_child(_slider)

	# ── Navigation row ──
	var nav = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(nav)

	# « / » (guillemets) instead of ⏮ / ⏭ — the media-skip glyphs are
	# emoji-presentation and render as blank/tofu on iOS.
	var first_btn = UITheme.make_icon_btn("«", UITheme.BG_CARD2, 44)
	first_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	first_btn.pressed.connect(func(): set_index(0))
	nav.add_child(first_btn)

	var prev_btn = UITheme.make_icon_btn("‹", UITheme.BG_CARD2, 48)
	prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_btn.pressed.connect(func(): set_index(max(0, _idx - 1)))
	nav.add_child(prev_btn)

	var next_btn = UITheme.make_icon_btn("›", UITheme.BG_CARD2, 48)
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.pressed.connect(func(): set_index(min(_records.size() - 1, _idx + 1)))
	nav.add_child(next_btn)

	var last_btn = UITheme.make_icon_btn("»", UITheme.BG_CARD2, 44)
	last_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	last_btn.pressed.connect(func(): set_index(_records.size() - 1))
	nav.add_child(last_btn)

	var best_btn = UITheme.make_btn("Best", UITheme.ACCENT_DIM, UITheme.FS_SMALL, 48, UITheme.R_SMALL)
	best_btn.pressed.connect(func():
		_show_best = not _show_best
		set_index(_idx))
	nav.add_child(best_btn)

	# ── Action buttons ──
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	side.add_child(actions)

	var stats_btn = UITheme.make_btn("Stats", UITheme.BG_CARD2, UITheme.FS_CAPTION, 42, UITheme.R_SMALL)
	stats_btn.pressed.connect(func(): show_stats_modal(_data, true))
	actions.add_child(stats_btn)

	var rematch_btn = UITheme.make_btn("Rematch", UITheme.ACCENT, UITheme.FS_CAPTION, 42, UITheme.R_SMALL)
	rematch_btn.pressed.connect(GameManager.show_game)
	actions.add_child(rematch_btn)

	var menu_btn = UITheme.make_btn("Menu", UITheme.BG_CARD2, UITheme.FS_CAPTION, 42, UITheme.R_SMALL)
	menu_btn.pressed.connect(GameManager.show_main_menu)
	actions.add_child(menu_btn)

	if not _records.is_empty():
		set_index(0)

# ── Index / detail refresh ──

func set_index(idx: int) -> void:
	if _records.is_empty(): return
	var clamped_idx = clamp(idx, 0, _records.size() - 1)
	var changed = clamped_idx != _idx
	if changed:
		_show_best = false
	_idx = clamped_idx
	var rec = _records[_idx]
	# Defensive: a legacy/corrupt record missing its core keys would crash the
	# raw rec["fen"]/rec["move"] reads below — skip rendering it rather than die.
	if typeof(rec) != TYPE_DICTIONARY or not rec.has("fen") or not rec.has("move"):
		return
	var analysis = rec.get("analysis", {})
	var tag = analysis.get("tag", "Best or good")
	var bucket = GameFormat.review_bucket(tag)
	var tag_color = GameFormat.color_for_tag(tag)
	if tag_color == Color.TRANSPARENT:
		tag_color = UITheme.ACCENT

	# Board
	if _board:
		_board.set_state(ChessLogic.parse_fen(rec["fen"]))
		_board.set_last_move(rec["move"]["from"], rec["move"]["to"])
		call_deferred("_animate_move", rec)
		var arrow = analysis.get("best", rec["move"]) if _show_best else rec["move"]
		if not arrow.is_empty():
			_board.set_hint(arrow["from"], arrow["to"], 1)
			# The auto-shown move arrow fades after a moment so it doesn't
			# clutter the board; the explicit "best move" arrow stays put.
			if not _show_best:
				_board.fade_hint()

	# Quality badge
	if _badge_container:
		for child in _badge_container.get_children():
			child.queue_free()
		var badge_text = "%s %s" % [GameFormat.review_icon(tag), bucket]
		var badge = UITheme.make_pill_badge(badge_text, Color(tag_color, 0.2), tag_color, UITheme.FS_CAPTION)
		_badge_container.add_child(badge)
		# Show side indicator
		var side_color = rec.get("color", ChessLogic.WHITE)
		var side_text = "White" if side_color == ChessLogic.WHITE else "Black"
		var side_pill = UITheme.make_pill_badge(side_text, UITheme.BG_CARD3, UITheme.TEXT_DIM, UITheme.FS_CAPTION, 10, 4)
		_badge_container.add_child(side_pill)

	# Move title
	if _title_lbl:
		_title_lbl.text = "%d. %s" % [rec.get("move_no", 0), rec.get("san", ChessLogic.move_to_uci(rec["move"]))]

	# Eval shift
	if _eval_lbl:
		if not analysis.is_empty():
			var white_win = GameFormat.win_percent_for_white(int(analysis.get("played_eval", 0)))
			var player_win = white_win if screen._player_color == ChessLogic.WHITE else 100.0 - white_win
			var opp_win = 100.0 - player_win
			var win_loss = float(analysis.get("win_loss_pct", 0.0))
			if _win_lbl:
				if screen._local_mode:
					_win_lbl.text = "B %d / W %d" % [int(round(100.0 - white_win)), int(round(white_win))]
				else:
					_win_lbl.text = "Bot %d / You %d" % [int(round(opp_win)), int(round(player_win))]
			_eval_lbl.text = "-%s" % GameFormat.format_pct(win_loss) if win_loss > 0.5 else ""
			var delta_color = UITheme.TEXT_DIM
			if win_loss >= 20.0:
				delta_color = UITheme.RED_LT
			elif win_loss >= 8.0:
				delta_color = UITheme.ORANGE
			elif win_loss >= 3.0:
				delta_color = UITheme.GOLD
			elif win_loss <= 0.5:
				delta_color = UITheme.ACCENT
			_eval_lbl.add_theme_color_override("font_color", delta_color)
		else:
			_eval_lbl.text = ""
			if _win_lbl:
				_win_lbl.text = ""

	if is_instance_valid(_win_bar):
		var white_win = GameFormat.win_percent_for_white(int(analysis.get("played_eval", 0))) if not analysis.is_empty() else 50.0
		_win_bar.left_color = Color("#171A17") if screen._local_mode else UITheme.BG_CARD3
		_win_bar.right_color = Color("#EDE9DA") if screen._local_mode else UITheme.ACCENT
		_win_bar.set_target_pct(white_win if screen._local_mode or screen._player_color == ChessLogic.WHITE else 100.0 - white_win, true)

	if _material_lbl:
		var material_state = ChessLogic.parse_fen(rec.get("after_fen", rec["fen"]))
		var material_text = GameFormat.material_summary_text(material_state)
		_material_lbl.text = material_text
		_material_lbl.visible = material_text != ""

	# Best move suggestion
	if _best_lbl:
		if not analysis.is_empty() and bucket != "Best":
			var best_move = analysis.get("best", {})
			if not best_move.is_empty():
				var best_san = ChessLogic.move_to_san(ChessLogic.parse_fen(rec["fen"]), best_move)
				_best_lbl.text = "Best: %s" % best_san
				_best_lbl.visible = true
			else:
				_best_lbl.text = ""
				_best_lbl.visible = false
		else:
			_best_lbl.text = ""
			_best_lbl.visible = false

	# CP loss
	if _loss_lbl:
		var loss = int(analysis.get("loss_cp", 0))
		if loss > 0:
			_loss_lbl.text = "Engine detail: %d cp behind best" % loss
			_loss_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
			_loss_lbl.visible = true
		else:
			_loss_lbl.text = ""
			_loss_lbl.visible = false

	# Note label (supplementary info)
	if _note_lbl:
		if analysis.is_empty():
			_note_lbl.text = ""
			_note_lbl.visible = false
		elif _show_best and not analysis.get("best", {}).is_empty():
			_note_lbl.text = "Showing engine's best move"
			_note_lbl.visible = true
		else:
			_note_lbl.text = ""
			_note_lbl.visible = false

	if _slider and int(_slider.value) != _idx:
		_slider.set_value_no_signal(_idx)
	if _count_lbl:
		_count_lbl.text = "Move %d of %d" % [_idx + 1, _records.size()]
	if is_instance_valid(_graph):
		_graph.highlight_idx = _idx + 1
	if changed:
		SoundManager.play_move(false)

func _animate_move(rec: Dictionary) -> void:
	if not _board or not is_instance_valid(_board): return
	if not rec.has("after_fen"): return
	_board.set_state(ChessLogic.parse_fen(rec["after_fen"]))

func _counts(records: Array) -> Dictionary:
	var counts = {"player": {}, "bot": {}}
	for side_name in counts.keys():
		for bucket in ["Best", "Slight", "Inaccuracy", "Mistake", "Blunder"]:
			counts[side_name][bucket] = 0
	for rec in records:
		var side_name = "player" if rec.get("color", ChessLogic.WHITE) == screen._player_color else "bot"
		var bucket = GameFormat.review_bucket(rec.get("analysis", {}).get("tag", "Best or good"))
		counts[side_name][bucket] = counts[side_name].get(bucket, 0) + 1
	return counts
