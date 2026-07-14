extends Control

var _hint_check: CheckButton
var _preview: _BoardPreview
var _board_buttons: Array = []
var _piece_buttons: Array = []
var _style_buttons: Array = []

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(UITheme.make_page_bg())

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.hide_v_scrollbar(scroll)
	add_child(scroll)

	var outer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(outer)

	var margin = UITheme.page_panel(720, 28)
	outer.add_child(margin)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	col.add_child(UITheme.spacer(UITheme.safe_top() + 4))

	var back = UITheme.make_back_btn()
	back.pressed.connect(GameManager.show_main_menu)
	col.add_child(back)

	col.add_child(UITheme.make_label("Settings", UITheme.FS_H1, UITheme.TEXT))
	_preview = _BoardPreview.new()
	_preview.custom_minimum_size = Vector2(0, 180)
	_preview.board_theme_idx = PlayerData.settings.get("board_theme", 0)
	_preview.piece_theme_idx = PlayerData.settings.get("piece_theme", 0)
	_preview.piece_style_idx = PlayerData.settings.get("piece_style", 0)
	col.add_child(_preview)
	col.add_child(UITheme.make_label("Board", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	col.add_child(_make_board_grid())
	col.add_child(UITheme.make_label("Pieces", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	col.add_child(_make_piece_grid())
	col.add_child(UITheme.make_label("Style", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	col.add_child(_make_style_grid())
	col.add_child(UITheme.make_separator())
	col.add_child(UITheme.make_label("Engine", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	col.add_child(_make_engine_row())
	col.add_child(UITheme.make_separator())
	col.add_child(_make_toggle_row())
	col.add_child(_make_sound_row())
	col.add_child(_make_sound_style_row())
	col.add_child(_make_clock_sound_row())
	col.add_child(_make_haptics_row())
	col.add_child(_make_voice_coords_row())
	col.add_child(_make_instant_bot_row())
	col.add_child(UITheme.make_separator())
	var about_btn = UITheme.make_btn("About & Open Source  ›", UITheme.BG_CARD2, UITheme.FS_SMALL, 54)
	about_btn.pressed.connect(GameManager.show_about)
	col.add_child(about_btn)
	col.add_child(_make_reset_row())

func _make_board_grid() -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_board_buttons = []
	for i in BoardVisual.BOARD_THEMES.size():
		var th = BoardVisual.BOARD_THEMES[i]
		var btn = UITheme.make_btn(th["name"], UITheme.BG_CARD2, UITheme.FS_CAPTION, 54)
		if i == PlayerData.settings.get("board_theme", 0):
			UITheme.apply_button(btn, UITheme.ACCENT, Color.WHITE, UITheme.FS_CAPTION)
		btn.pressed.connect(_set_board_theme.bind(i))
		grid.add_child(btn)
		_board_buttons.append(btn)
	return grid

func _make_piece_grid() -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_piece_buttons = []
	for i in BoardVisual.PIECE_THEMES.size():
		var th = BoardVisual.PIECE_THEMES[i]
		var btn = UITheme.make_btn(th["name"], UITheme.BG_CARD2, UITheme.FS_CAPTION, 54)
		if i == PlayerData.settings.get("piece_theme", 0):
			UITheme.apply_button(btn, UITheme.ACCENT, Color.WHITE, UITheme.FS_CAPTION)
		btn.pressed.connect(_set_piece_theme.bind(i))
		grid.add_child(btn)
		_piece_buttons.append(btn)
	return grid

func _make_style_grid() -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 16)
	_style_buttons = []
	for i in BoardVisual.PIECE_STYLES.size():
		var st = BoardVisual.PIECE_STYLES[i]
		var btn = UITheme.make_btn(st["name"], UITheme.BG_CARD2, UITheme.FS_CAPTION, 54)
		if i == PlayerData.settings.get("piece_style", 0):
			UITheme.apply_button(btn, UITheme.ACCENT, Color.WHITE, UITheme.FS_CAPTION)
		btn.pressed.connect(_set_piece_style.bind(i))
		grid.add_child(btn)
		_style_buttons.append(btn)
	return grid

func _make_toggle_row() -> Panel:
	return _make_setting_toggle("Hints", "hints")

func _make_sound_row() -> Panel:
	return _make_setting_toggle("Sounds", "sound")

func _make_clock_sound_row() -> Panel:
	return _make_setting_toggle("Clock Warning", "clock_sound")

func _make_haptics_row() -> Panel:
	return _make_setting_toggle("Haptics", "haptics")

func _make_voice_coords_row() -> Panel:
	return _make_setting_toggle("Voice Coordinates", "voice_coords")

func _make_instant_bot_row() -> Panel:
	return _make_setting_toggle("Instant Bot Moves", "instant_bot")

func _make_sound_style_row() -> Panel:
	var panel = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_SMALL)
	panel.custom_minimum_size.y = 78
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(m)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	m.add_child(row)

	row.add_child(UITheme.make_label("Sound Style", UITheme.FS_BODY, UITheme.TEXT))
	var soft = UITheme.make_btn("Soft", UITheme.BG_CARD2, UITheme.FS_SMALL, 48)
	var crisp = UITheme.make_btn("Crisp", UITheme.BG_CARD2, UITheme.FS_SMALL, 48)
	soft.custom_minimum_size.x = 92
	crisp.custom_minimum_size.x = 92
	soft.pressed.connect(func(): _set_sound_style("soft", soft, crisp))
	crisp.pressed.connect(func(): _set_sound_style("crisp", soft, crisp))
	row.add_child(soft)
	row.add_child(crisp)
	_set_sound_style_buttons(soft, crisp)
	return panel

func _make_setting_toggle(label: String, key: String) -> Panel:
	var panel = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_SMALL)
	panel.custom_minimum_size.y = 72
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(m)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	m.add_child(row)

	row.add_child(UITheme.make_label(label, UITheme.FS_BODY, UITheme.TEXT))
	var toggle = UITheme.make_btn("On" if PlayerData.settings.get(key, true) else "Off",
		UITheme.ACCENT if PlayerData.settings.get(key, true) else UITheme.BG_CARD2,
		UITheme.FS_SMALL, 48)
	toggle.custom_minimum_size.x = 110
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle.pressed.connect(func():
		var on = not PlayerData.settings.get(key, true)
		PlayerData.settings[key] = on
		PlayerData.save_data()
		toggle.text = "On" if on else "Off"
		UITheme.apply_button(toggle, UITheme.ACCENT if on else UITheme.BG_CARD2, UITheme.TEXT, UITheme.FS_SMALL)
		if key == "sound" and on: SoundManager.play_click()
		if key == "haptics" and on: Haptics.impact(false))
	row.add_child(toggle)
	return panel

func _make_reset_row() -> Panel:
	var panel = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_SMALL)
	panel.custom_minimum_size.y = 78
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		m.add_theme_constant_override("margin_"+side, 16)
	panel.add_child(m)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	m.add_child(row)
	row.add_child(UITheme.make_label("Reset App Data", UITheme.FS_BODY, UITheme.TEXT))
	var btn = UITheme.make_btn("Reset", UITheme.RED.darkened(0.25), UITheme.FS_SMALL, 48)
	btn.custom_minimum_size.x = 110
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.pressed.connect(_confirm_reset)
	row.add_child(btn)
	return panel

func _make_engine_row() -> Panel:
	var panel = UITheme.make_panel(UITheme.BG_CARD, UITheme.R_SMALL)
	panel.custom_minimum_size.y = 78
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(m)
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	m.add_child(row)
	var label = UITheme.make_label("Chess Engine", UITheme.FS_BODY, UITheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var ename := "Stockfish 18"
	var reg = get_node_or_null("/root/EngineRegistry")
	if reg != null:
		ename = String(reg.active_profile().get("name", ename))
	var btn = UITheme.make_btn(ename + "  ›", UITheme.BG_CARD2, UITheme.FS_SMALL, 48)
	# Needs a real min width: SHRINK_END next to the EXPAND_FILL label, a min of 0
	# collapsed it to nothing (the whole engine button disappeared). 150px fits the
	# name; clip_text guards a very long one. The label clips first, so no overflow.
	btn.custom_minimum_size.x = 150
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.pressed.connect(GameManager.show_engines.bind("settings"))
	row.add_child(btn)
	return panel

func _set_board_theme(idx: int) -> void:
	PlayerData.settings["board_theme"] = idx
	PlayerData.save_data()
	_preview.board_theme_idx = idx
	_preview.queue_redraw()
	for i in _board_buttons.size():
		UITheme.apply_button(_board_buttons[i], UITheme.ACCENT if i == idx else UITheme.BG_CARD2,
			UITheme.TEXT, UITheme.FS_CAPTION)

func _set_piece_theme(idx: int) -> void:
	PlayerData.settings["piece_theme"] = idx
	PlayerData.save_data()
	_preview.piece_theme_idx = idx
	_preview.queue_redraw()
	for i in _piece_buttons.size():
		UITheme.apply_button(_piece_buttons[i], UITheme.ACCENT if i == idx else UITheme.BG_CARD2,
			UITheme.TEXT, UITheme.FS_CAPTION)

func _set_piece_style(idx: int) -> void:
	PlayerData.settings["piece_style"] = idx
	PlayerData.save_data()
	_preview.piece_style_idx = idx
	_preview.queue_redraw()
	for i in _style_buttons.size():
		UITheme.apply_button(_style_buttons[i], UITheme.ACCENT if i == idx else UITheme.BG_CARD2,
			UITheme.TEXT, UITheme.FS_CAPTION)

func _set_sound_style(style: String, soft: Button, crisp: Button) -> void:
	PlayerData.settings["sound_style"] = style
	PlayerData.save_data()
	_set_sound_style_buttons(soft, crisp)
	SoundManager.play_move(false)

func _set_sound_style_buttons(soft: Button, crisp: Button) -> void:
	var style = PlayerData.settings.get("sound_style", "soft")
	UITheme.apply_button(soft, UITheme.ACCENT if style == "soft" else UITheme.BG_CARD2,
		UITheme.TEXT, UITheme.FS_SMALL)
	UITheme.apply_button(crisp, UITheme.ACCENT if style == "crisp" else UITheme.BG_CARD2,
		UITheme.TEXT, UITheme.FS_SMALL)

func _confirm_reset() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "Reset App Data"
	dialog.dialog_text = "Reset rating, stats, achievements, puzzle progress, and saved games?"
	dialog.confirmed.connect(func():
		PlayerData.reset_all()
		PuzzleManager.reset_all()
		GameManager.show_main_menu())
	add_child(dialog)
	dialog.popup_centered()

class _BoardPreview extends Control:
	var board_theme_idx: int = 0
	var piece_theme_idx: int = 0
	var piece_style_idx: int = 0
	var _font := SystemFont.new()

	func _init() -> void:
		_font.font_names = PackedStringArray(["Segoe UI Symbol","Noto Sans Symbols2",
			"Apple Symbols","DejaVu Sans",""])

	func _draw() -> void:
		var board_size = min(size.x, size.y)
		if board_size <= 0: return
		var origin = Vector2((size.x - board_size) * 0.5, 0)
		var sq = board_size / 4.0
		var th = BoardVisual.BOARD_THEMES[board_theme_idx % BoardVisual.BOARD_THEMES.size()]
		for r in 4:
			for f in 4:
				draw_rect(Rect2(origin + Vector2(f * sq, r * sq), Vector2(sq, sq)),
					th["light"] if (f + r) % 2 == 0 else th["dark"])
		var pt = BoardVisual.PIECE_THEMES[piece_theme_idx % BoardVisual.PIECE_THEMES.size()]
		var style = BoardVisual.PIECE_STYLES[piece_style_idx % BoardVisual.PIECE_STYLES.size()]
		var pieces = [
			[style["glyphs"][4], pt["b"], pt["bo"], Vector2(0, 0)],
			[style["glyphs"][2], pt["b"], pt["bo"], Vector2(2, 0)],
			[style["glyphs"][1], pt["w"], pt["wo"], Vector2(1, 2)],
			[style["glyphs"][6], pt["w"], pt["wo"], Vector2(3, 3)],
		]
		for p in pieces:
			var rect = Rect2(origin + Vector2(p[3].x * sq, p[3].y * sq), Vector2(sq, sq))
			var center = rect.get_center()
			var font_size = int(sq * 0.80)
			var pos = Vector2(rect.position.x, center.y + font_size * 0.27)
			var shadow = Color(0,0,0,0.35)
			
			if piece_style_idx == 1: # Classic
				draw_circle(center, font_size * 0.45, Color(0,0,0,0.1) if p[1] == pt["b"] else Color(1,1,1,0.05))

			for off in [Vector2(-1,0), Vector2(1,0), Vector2(0,-1), Vector2(0,1)]:
				draw_string(_font, pos + off, p[0], HORIZONTAL_ALIGNMENT_CENTER, sq, font_size, p[2])
			draw_string(_font, pos + Vector2(1,2), p[0], HORIZONTAL_ALIGNMENT_CENTER, sq, font_size, shadow)
			draw_string(_font, pos, p[0], HORIZONTAL_ALIGNMENT_CENTER, sq, font_size, p[1])
