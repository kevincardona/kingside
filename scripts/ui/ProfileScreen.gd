extends Control

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(UITheme.make_page_bg())

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var wide = _wide_layout()
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

	var margin = UITheme.page_panel(920, 20)
	outer.add_child(margin)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	# Header
	col.add_child(UITheme.spacer(UITheme.safe_top() + 4))

	col.add_child(UITheme.make_label("Profile", UITheme.FS_H1, UITheme.TEXT))

	var settings_btn = UITheme.make_btn("Settings", UITheme.BG_CARD2, UITheme.FS_BODY, 52)
	settings_btn.pressed.connect(GameManager.show_settings)
	col.add_child(settings_btn)

	# --- Rating card ---
	col.add_child(_make_rating_card())

	# --- ELO history mini-chart ---
	if PlayerData.elo_history.size() > 1:
		col.add_child(_make_elo_chart())

	# --- Stats grid ---
	col.add_child(UITheme.make_label("Stats", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	col.add_child(_make_stats_grid())

	if not PlayerData.completed_games.is_empty():
		col.add_child(UITheme.make_label("Recent Games", UITheme.FS_SMALL, UITheme.TEXT_DIM))
		col.add_child(_make_recent_games())

	# --- Achievements ---
	var ach_header = HBoxContainer.new()
	ach_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ach_title = UITheme.make_label("Achievements", UITheme.FS_SMALL, UITheme.TEXT_DIM)
	ach_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ach_header.add_child(ach_title)
	var unlocked_count := 0
	for aid in PlayerData.ACHIEVEMENT_DEFS.keys():
		if PlayerData.has_achievement(aid): unlocked_count += 1
	ach_header.add_child(UITheme.make_label("%d / %d" % [unlocked_count, PlayerData.ACHIEVEMENT_DEFS.size()],
		UITheme.FS_SMALL, UITheme.GOLD))
	col.add_child(ach_header)
	col.add_child(_make_achievements())
	add_child(UITheme.make_app_nav("profile", wide))

func _wide_layout() -> bool:
	return get_viewport_rect().size.x >= 900

func _make_rating_card() -> PanelContainer:
	# PanelContainer so the card grows to fit its labels instead of clipping.
	var panel = UITheme.make_panel_container(UITheme.BG_CARD, UITheme.R_MEDIUM)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var inner = VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 8)

	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left",  40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top",   18)
	margin.add_theme_constant_override("margin_bottom",18)
	panel.add_child(margin)
	margin.add_child(inner)

	inner.add_child(UITheme.make_label(str(PlayerData.elo), UITheme.FS_H2, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	inner.add_child(UITheme.make_label(PlayerData.get_title(), UITheme.FS_BODY, PlayerData.get_title_color(), HORIZONTAL_ALIGNMENT_CENTER))

	var wr = int(PlayerData.win_rate() * 100)
	inner.add_child(UITheme.make_label("%d%% win rate" % wr, UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	return panel

func _make_elo_chart() -> Control:
	var chart_container = UITheme.make_panel(UITheme.BG_CARD, 16)
	chart_container.custom_minimum_size = Vector2(0, 140)
	chart_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var graph = UIStockGraph.new()
	graph.data = PlayerData.elo_history
	graph.color = UITheme.GOLD
	graph.label_format = "%d"
	graph.mouse_filter = Control.MOUSE_FILTER_PASS
	graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chart_container.add_child(graph)

	return chart_container

func _make_stats_grid() -> GridContainer:
	var grid = GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)

	var stats = [
		[str(PlayerData.games_played), "Games"],
		[str(PlayerData.wins),         "Wins"],
		[str(PlayerData.losses),       "Losses"],
		[str(PlayerData.draws),        "Draws"],
		[str(PlayerData.best_streak),  "Best Streak"],
		[str(PlayerData.current_streak), "Current Streak"],
	]

	for s in stats:
		var cell = UITheme.make_panel(UITheme.BG_CARD, 14)
		cell.custom_minimum_size.y = 80
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var m = MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_PASS
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		m.add_theme_constant_override("margin_left",   8)
		m.add_theme_constant_override("margin_right",  8)
		m.add_theme_constant_override("margin_top",    8)
		m.add_theme_constant_override("margin_bottom", 8)
		cell.add_child(m)

		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		m.add_child(vbox)

		var val_lbl = UITheme.make_label(s[0], UITheme.FS_H3, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		val_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vbox.add_child(val_lbl)
		var key_lbl = UITheme.make_label(s[1], UITheme.FS_CAPTION, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		key_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vbox.add_child(key_lbl)

		grid.add_child(cell)

	return grid

func _make_recent_games() -> VBoxContainer:
	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	for game in PlayerData.completed_games.slice(0, min(8, PlayerData.completed_games.size())):
		var row = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_SMALL)
		row.custom_minimum_size.y = 58
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m = MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_PASS
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left","right","top","bottom"]:
			m.add_theme_constant_override("margin_"+side, 10)
		row.add_child(m)
		var h = HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 10)
		m.add_child(h)
		var info = UITheme.make_label("%s  ·  %s  ·  %d moves" % [
			game.get("result", "Game"),
			AIEngine.get_difficulty_label(game.get("difficulty", "medium")),
			game.get("records", []).size()
		], UITheme.FS_CAPTION, UITheme.TEXT)
		info.clip_text = true
		h.add_child(info)
		var btn = UITheme.make_btn("Review", UITheme.ACCENT_DIM, UITheme.FS_CAPTION, 38)
		btn.custom_minimum_size.x = 92
		btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		btn.pressed.connect(GameManager.show_completed_review.bind(game))
		h.add_child(btn)
		col.add_child(row)
	return col

# Single-column list. Unlocked achievements get a gold "medal" badge + a warm
# tinted card so they pop; locked ones recede (flat card, dim badge, dim text).
func _make_achievements() -> VBoxContainer:
	var list = VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)

	for id in PlayerData.ACHIEVEMENT_DEFS.keys():
		var def      = PlayerData.ACHIEVEMENT_DEFS[id]
		var unlocked = PlayerData.has_achievement(id)

		var bg = UITheme.BG_CARD.lerp(UITheme.GOLD, 0.12) if unlocked else UITheme.BG_CARD
		var card = UITheme.make_panel_container(bg, UITheme.R_MEDIUM, false)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var m = MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_PASS
		m.add_theme_constant_override("margin_left", 12)
		m.add_theme_constant_override("margin_right", 14)
		m.add_theme_constant_override("margin_top", 11)
		m.add_theme_constant_override("margin_bottom", 11)
		card.add_child(m)

		var hbox = HBoxContainer.new()
		hbox.mouse_filter = Control.MOUSE_FILTER_PASS
		hbox.add_theme_constant_override("separation", 13)
		m.add_child(hbox)

		hbox.add_child(_ach_badge(unlocked))

		var info = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_theme_constant_override("separation", 1)
		hbox.add_child(info)

		info.add_child(UITheme.make_label(def["name"], UITheme.FS_BODY,
			UITheme.TEXT if unlocked else UITheme.TEXT_DIM))
		var desc = UITheme.make_label(def["desc"], UITheme.FS_CAPTION,
			UITheme.TEXT_DIM if unlocked else UITheme.TEXT_MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)

		list.add_child(card)
	return list

# A round medal badge: solid gold with a dark star when unlocked, dim disc with
# a muted star when locked.
func _ach_badge(unlocked: bool) -> PanelContainer:
	var badge = PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(38, 38)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb = StyleBoxFlat.new()
	sb.bg_color = UITheme.GOLD if unlocked else UITheme.BG_CARD3
	sb.corner_radius_top_left = 19
	sb.corner_radius_top_right = 19
	sb.corner_radius_bottom_left = 19
	sb.corner_radius_bottom_right = 19
	badge.add_theme_stylebox_override("panel", sb)
	var star = UITheme.make_label("★", UITheme.FS_SMALL,
		UITheme.BG_PAGE if unlocked else UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(star)
	return badge

