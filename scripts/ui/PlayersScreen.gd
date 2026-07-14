extends Control

const PLAYERS = [
	{"key": "beginner", "name": "Mira", "style": "Beginner", "note": "Misses tactics and plays quickly."},
	{"key": "easy", "name": "Theo", "style": "Casual", "note": "Simple plans, frequent inaccuracies."},
	{"key": "medium", "name": "Iris", "style": "Club", "note": "Reasonable development and basic tactics."},
	{"key": "hard", "name": "Nadia", "style": "Sharp", "note": "Stockfish-limited tactical player."},
	{"key": "expert", "name": "Viktor", "style": "Positional", "note": "Stronger Stockfish-limited profile."},
	{"key": "master", "name": "Sofia", "style": "Master", "note": "High-strength Stockfish profile."},
	{"key": "stockfish_max", "name": "Stockfish", "style": "Maximum", "note": "Full-strength analysis engine."},
]

func _ready() -> void:
	_build()

func _build() -> void:
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
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(outer)

	var margin = UITheme.page_panel(900, 22)
	outer.add_child(margin)

	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	col.add_child(UITheme.spacer(UITheme.safe_top()))
	col.add_child(UITheme.make_label("Players", UITheme.FS_H1, UITheme.TEXT))
	var subtitle = UITheme.make_label("Installed opponent profiles", UITheme.FS_SMALL, UITheme.TEXT_DIM)
	col.add_child(subtitle)

	var grid = GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.columns = 2 if wide else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)

	for player in PLAYERS:
		grid.add_child(_make_player_card(player))

	var note = UITheme.make_label("Remote player packs should be signed data profiles layered over Stockfish. Native engines should stay bundled with the app.", UITheme.FS_SMALL, UITheme.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)

	add_child(UITheme.make_app_nav("players", wide))

func _make_player_card(player: Dictionary) -> Panel:
	var key = player["key"]
	var elo = AIEngine.get_difficulty_elo(key)
	var panel = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_SMALL)
	panel.custom_minimum_size.y = 132
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(m)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var avatar = UITheme.make_panel(_avatar_color(elo), 32, true)
	avatar.custom_minimum_size = Vector2(54, 54)
	row.add_child(avatar)
	var glyph = UITheme.make_label("♚", UITheme.FS_H3, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_child(glyph)

	var info = VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)
	info.add_child(UITheme.make_label("%s  %d" % [player["name"], elo], UITheme.FS_BODY, UITheme.TEXT))
	info.add_child(UITheme.make_label(player["style"], UITheme.FS_CAPTION, UITheme.ACCENT_LT))
	var note = UITheme.make_label(player["note"], UITheme.FS_CAPTION, UITheme.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(note)

	var choose = UITheme.make_btn("Choose", UITheme.ACCENT_DIM, UITheme.FS_CAPTION, 46)
	choose.custom_minimum_size.x = 96
	choose.size_flags_horizontal = Control.SIZE_SHRINK_END
	choose.pressed.connect(_choose_player.bind(key))
	row.add_child(choose)
	return panel

func _choose_player(key: String) -> void:
	GameManager.chosen_difficulty = key
	GameManager.show_difficulty_select()

func _avatar_color(elo: int) -> Color:
	if elo >= 3000: return UITheme.RED.darkened(0.1)
	if elo >= 2200: return UITheme.GOLD.darkened(0.15)
	if elo >= 1500: return UITheme.ACCENT_DIM
	return UITheme.BG_CARD2

func _wide_layout() -> bool:
	return get_viewport_rect().size.x >= 900
