extends Control

var _selected_diff: String = GameManager.chosen_difficulty
var _selected_color: int   = GameManager.player_color
var _selected_time: String = GameManager.time_mode
var _selected_opponent: String = "computer"   # "computer" | "local"

var _diff_buttons: Dictionary = {}
var _color_buttons: Dictionary = {}
var _time_buttons:  Dictionary = {}
var _opponent_buttons: Dictionary = {}
var _ai_section: VBoxContainer = null   # hidden in Pass & Play mode
var _difficulty_btn: Button = null
var _difficulty_value: Label = null     # value label inside the Difficulty row
var _time_btn: Button = null
var _time_value: Label = null           # value label inside the Time row
var _start_btn: Button = null

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
	outer.add_theme_constant_override("separation", 0)
	scroll.add_child(outer)

	var margin = UITheme.page_panel(560, 24)
	outer.add_child(margin)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	col.add_child(UITheme.spacer(UITheme.safe_top() + 6))

	# Back on its own row + big title below — same header pattern as Engines.
	var back = UITheme.make_back_btn()
	back.pressed.connect(GameManager.show_main_menu)
	col.add_child(back)
	col.add_child(UITheme.make_label("Play", UITheme.FS_H1, UITheme.TEXT))
	col.add_child(UITheme.spacer(2))

	col.add_child(_section_label("Opponent"))
	var opp_row = HBoxContainer.new()
	opp_row.add_theme_constant_override("separation", 10)
	opp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(opp_row)
	for opt in [["computer", "Computer"], ["local", "Pass & Play"]]:
		var opp_btn = UITheme.make_btn(opt[1], UITheme.BG_CARD2, UITheme.FS_SMALL, 54)
		opp_btn.pressed.connect(_on_opponent_selected.bind(opt[0]))
		opp_row.add_child(opp_btn)
		_opponent_buttons[opt[0]] = opp_btn

	_ai_section = VBoxContainer.new()
	_ai_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_section.add_theme_constant_override("separation", 10)
	col.add_child(_ai_section)

	_ai_section.add_child(_section_label("Play as"))
	var color_row = HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 10)
	color_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_section.add_child(color_row)

	var color_opts = [
		[ChessLogic.WHITE, "White"],
		[ChessLogic.BLACK, "Black"],
		[0,                "Random"],
	]
	for opt in color_opts:
		var btn = UITheme.make_btn(opt[1], UITheme.BG_CARD2, UITheme.FS_SMALL, 50)
		btn.pressed.connect(_on_color_selected.bind(opt[0]))
		color_row.add_child(btn)
		_color_buttons[opt[0]] = btn

	_ai_section.add_child(UITheme.spacer(2))
	_ai_section.add_child(_section_label("Game"))
	var diff_row = _make_setting_row("Difficulty", _show_difficulty_picker)
	_difficulty_btn = diff_row["btn"]
	_difficulty_value = diff_row["value"]
	_ai_section.add_child(_difficulty_btn)

	var time_row = _make_setting_row("Time", _show_time_picker)
	_time_btn = time_row["btn"]
	_time_value = time_row["value"]
	col.add_child(_time_btn)

	col.add_child(UITheme.spacer(6))
	_start_btn = UITheme.make_btn("Start Game", UITheme.ACCENT, UITheme.FS_H3, 72)
	_start_btn.pressed.connect(_on_start)
	col.add_child(_start_btn)

	var info_lbl = UITheme.make_label("", UITheme.FS_SMALL, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	info_lbl.name = "InfoLabel"
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(info_lbl)

	col.add_child(UITheme.spacer(UITheme.safe_bottom() + 8))

	_refresh_selection()

func _clean_time_label(raw: String) -> String:
	# Strip emoji prefixes like "⚡ " "◷ " "♜ " "∞ "
	var parts = raw.split(" ", false)
	if parts.size() > 1:
		return " ".join(parts.slice(1))
	return raw

func _difficulty_label(key: String) -> String:
	if key == "custom":
		return "Custom %d" % GameManager.custom_rating
	if key == "stockfish_max":
		return "Max Stockfish 3200"
	var cfg = AIEngine.DIFFICULTIES.get(key, AIEngine.DIFFICULTIES["medium"])
	return "%s %d" % [cfg["label"], cfg["elo"]]

# Settings-style row: dim title on the left, bright value + chevron on the
# right, the whole row tappable. Returns {btn, value} — update the value label,
# not the button text (the button's own text stays empty).
func _make_setting_row(title: String, on_press: Callable) -> Dictionary:
	var btn = UITheme.make_btn("", UITheme.BG_CARD2, UITheme.FS_BODY, 62)
	btn.pressed.connect(on_press)
	var m = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 16)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(m)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var t = UITheme.make_label(title, UITheme.FS_SMALL, UITheme.TEXT_DIM)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(t)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var v = UITheme.make_label("", UITheme.FS_BODY, UITheme.TEXT)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var chev = UITheme.make_label("›", UITheme.FS_BODY, UITheme.TEXT_MUTED)
	chev.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chev)
	return {"btn": btn, "value": v}

func _section_label(text: String) -> Label:
	return UITheme.make_label(text.to_upper(), UITheme.FS_CAPTION, UITheme.TEXT_MUTED)

func _show_difficulty_picker() -> void:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UITheme.make_label("Difficulty", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(grid)

	_diff_buttons.clear()
	for d in ["beginner","easy","medium","hard","expert","master","stockfish_max","custom"]:
		var label = "Custom" if d == "custom" else AIEngine.DIFFICULTIES[d]["label"]
		var elo = GameManager.custom_rating if d == "custom" else AIEngine.DIFFICULTIES[d]["elo"]
		var btn = _make_diff_btn(d, label, elo)
		btn.pressed.connect(func():
			var o = find_child("DifficultyPicker", true, false)
			if o: o.queue_free())
		grid.add_child(btn)
		_diff_buttons[d] = btn

	# The engine powers these bots, so its picker lives here rather than as a
	# stray row on the Play page. Opens the Engines screen (back returns to Play).
	var engine_name = "Stockfish 18"
	var reg = get_node_or_null("/root/EngineRegistry")
	if reg != null:
		engine_name = String(reg.active_profile().get("name", engine_name))
	var engine_btn = UITheme.make_btn("Engine  ·  %s  ›" % engine_name, UITheme.BG_CARD, UITheme.FS_SMALL, 46)
	engine_btn.clip_text = true
	engine_btn.pressed.connect(func():
		var o = find_child("DifficultyPicker", true, false)
		if o: o.queue_free()
		GameManager.show_engines("play"))
	col.add_child(engine_btn)

	var close = UITheme.make_btn("Close", UITheme.BG_CARD2, UITheme.FS_BODY, 52)
	close.pressed.connect(func():
		var o = find_child("DifficultyPicker", true, false)
		if o: o.queue_free())
	col.add_child(close)

	_show_picker_card("DifficultyPicker", col, 460)
	_refresh_selection()

func _show_time_picker() -> void:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UITheme.make_label("Time", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(grid)

	_time_buttons.clear()
	for mode in ["casual","blitz","rapid","classic"]:
		var cfg = GameManager.TIME_MODES[mode]
		var btn = UITheme.make_btn(_clean_time_label(cfg["label"]), UITheme.BG_CARD2, UITheme.FS_SMALL, 58)
		btn.pressed.connect(_on_time_picker_selected.bind(mode))
		grid.add_child(btn)
		_time_buttons[mode] = btn

	var close = UITheme.make_btn("Close", UITheme.BG_CARD2, UITheme.FS_BODY, 52)
	close.pressed.connect(func():
		var o = find_child("TimePicker", true, false)
		if o: o.queue_free())
	col.add_child(close)

	_show_picker_card("TimePicker", col, 420)
	_refresh_selection()

func _on_time_picker_selected(mode: String) -> void:
	_on_time_selected(mode)
	var o = find_child("TimePicker", true, false)
	if o: o.queue_free()

func _show_picker_card(name_str: String, content: Control, max_width: int) -> void:
	var existing = find_child(name_str, true, false)
	if existing:
		existing.queue_free()
	var ov = ColorRect.new()
	ov.color = Color(0, 0, 0, 0.70)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.name = name_str
	add_child(ov)

	var card = UITheme.make_card(content, 24, UITheme.BG_CARD, UITheme.R_LARGE, true)
	var vp = get_viewport_rect().size
	var w = min(float(max_width), max(300.0, vp.x - 40.0))
	card.anchor_left = 0.0
	card.anchor_right = 0.0
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = (vp.x - w) * 0.5
	card.offset_right = card.offset_left + w
	card.offset_top = -200
	card.offset_bottom = 200
	ov.add_child(card)

	await get_tree().process_frame
	if not is_instance_valid(card): return
	var h = clamp(content.get_combined_minimum_size().y + 48.0, 180.0, vp.y * 0.82)
	card.offset_top = -h * 0.5
	card.offset_bottom = h * 0.5

func _make_diff_btn(key: String, label_text: String, rating: int) -> Button:
	var btn = Button.new()
	btn.set_script(UITheme.ScrollFriendlyButtonScript)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 68
	btn.clip_contents = false
	btn.mouse_filter = Control.MOUSE_FILTER_PASS

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left",   10)
	m.add_theme_constant_override("margin_right",  10)
	m.add_theme_constant_override("margin_top",    8)
	m.add_theme_constant_override("margin_bottom", 8)
	btn.add_child(m)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(vbox)

	var name_lbl = UITheme.make_label(label_text, UITheme.FS_SMALL, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_lbl)

	var rating_lbl = UITheme.make_label(str(rating), UITheme.FS_CAPTION, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(rating_lbl)

	if key == "custom":
		btn.pressed.connect(_on_custom_clicked)
	else:
		btn.pressed.connect(_on_diff_selected.bind(key))
	return btn

func _make_color_btn(label: String, color_val: int, icon: String) -> Button:
	var btn = Button.new()
	btn.set_script(UITheme.ScrollFriendlyButtonScript)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 72
	btn.clip_contents = false
	btn.mouse_filter = Control.MOUSE_FILTER_PASS

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left",   8)
	m.add_theme_constant_override("margin_right",  8)
	m.add_theme_constant_override("margin_top",    8)
	m.add_theme_constant_override("margin_bottom", 8)
	btn.add_child(m)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(vbox)

	# Chess king icon
	var icon_lbl = UITheme.make_label("♔" if color_val == ChessLogic.WHITE else ("♚" if color_val == ChessLogic.BLACK else "?"),
		UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(icon_lbl)

	var name_lbl = UITheme.make_label(label, UITheme.FS_CAPTION, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_lbl)

	btn.pressed.connect(_on_color_selected.bind(color_val))
	return btn

func _on_custom_clicked() -> void:
	_show_custom_rating_modal()

func _show_custom_rating_modal() -> void:
	var ov = ColorRect.new()
	ov.color = Color(0, 0, 0, 0.70)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.name = "CustomModal"
	add_child(ov)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)

	col.add_child(UITheme.make_label("Custom Rating", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UITheme.make_label(
		"Set the opponent's strength.",
		UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var rating_display = UITheme.make_label(
		str(GameManager.custom_rating), UITheme.FS_H1,
		_rating_display_color(GameManager.custom_rating), HORIZONTAL_ALIGNMENT_CENTER)
	rating_display.name = "CustomRatingDisplay"
	col.add_child(rating_display)

	var tier_lbl = UITheme.make_label(
		_rating_tier_label(GameManager.custom_rating),
		UITheme.FS_SMALL, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	tier_lbl.name = "CustomTierLabel"
	col.add_child(tier_lbl)

	var slider = HSlider.new()
	slider.min_value = 250
	slider.max_value = 2800
	slider.step = 50
	slider.value = GameManager.custom_rating
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Per-tick handler is kept deliberately light — it updates only the modal's own
	# labels, each guarded with is_instance_valid() (NOT "obj and is_instance_valid":
	# evaluating a freed `obj` for truthiness reads freed memory and crashes first).
	# The heavier work (walking the difficulty-list button subtree) is deferred to
	# drag_ended so it never runs dozens of times per second during a touch drag —
	# that per-tick tree walk is what was crashing the slider on device.
	slider.value_changed.connect(func(v):
		if not is_inside_tree():
			return
		var r = int(v)
		GameManager.custom_rating = r
		if is_instance_valid(rating_display):
			rating_display.text = str(r)
			rating_display.add_theme_color_override("font_color", _rating_display_color(r))
		if is_instance_valid(tier_lbl):
			tier_lbl.text = _rating_tier_label(r))
	slider.drag_ended.connect(func(_value_changed):
		if is_inside_tree():
			_refresh_custom_btn())
	col.add_child(slider)

	var range_row = HBoxContainer.new()
	range_row.add_child(UITheme.make_label("250", UITheme.FS_CAPTION, UITheme.TEXT_MUTED))
	var sp = Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_row.add_child(sp)
	range_row.add_child(UITheme.make_label("2800", UITheme.FS_CAPTION, UITheme.TEXT_MUTED))
	col.add_child(range_row)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	col.add_child(btn_row)

	var cancel_btn = UITheme.make_btn("Cancel", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	cancel_btn.pressed.connect(func():
		var o = find_child("CustomModal", true, false)
		if o: o.queue_free())
	btn_row.add_child(cancel_btn)

	var confirm_btn = UITheme.make_btn("Set", UITheme.ACCENT, UITheme.FS_BODY, 56)
	confirm_btn.pressed.connect(func():
		var o = find_child("CustomModal", true, false)
		if o: o.queue_free()
		_on_diff_selected("custom"))
	btn_row.add_child(confirm_btn)

	var vp = get_viewport_rect().size
	var pad = 28
	var card_w = min(420.0, max(280.0, vp.x - 40.0))
	var total_w = card_w + pad * 2
	var card = UITheme.make_card(col, pad, UITheme.BG_CARD, UITheme.R_LARGE, true)
	card.anchor_left   = 0.0; card.anchor_right  = 0.0
	card.anchor_top    = 0.5; card.anchor_bottom = 0.5
	card.offset_left   = (vp.x - total_w) * 0.5
	card.offset_right  = card.offset_left + total_w
	card.offset_top    = -240.0
	card.offset_bottom = 240.0
	ov.add_child(card)
	# Adjust height to content after layout
	await get_tree().process_frame
	if not is_instance_valid(card): return
	var min_h = col.get_combined_minimum_size().y + pad * 2
	min_h = clamp(min_h, 200.0, vp.y * 0.80)
	card.offset_top    = -min_h * 0.5
	card.offset_bottom = min_h * 0.5

func _rating_display_color(r: int) -> Color:
	if r >= 2000: return UITheme.RED_LT
	if r >= 1500: return UITheme.GOLD
	if r >= 1000: return UITheme.ACCENT_LT
	return UITheme.TEXT_DIM

func _rating_tier_label(r: int) -> String:
	if r >= 2500: return "Master"
	if r >= 2000: return "Expert"
	if r >= 1600: return "Advanced"
	if r >= 1200: return "Intermediate"
	if r >= 800:  return "Beginner"
	return "Absolute Beginner"

func _refresh_custom_btn() -> void:
	# Check validity BEFORE the cast: "_diff_buttons['custom'] as Button" on a freed
	# button (the difficulty list was rebuilt, leaving a stale reference) throws
	# "Trying to cast a freed object" — and the slider fires this on every drag.
	var raw = _diff_buttons.get("custom")
	if not is_instance_valid(raw):
		if is_instance_valid(_difficulty_btn):
			if is_instance_valid(_difficulty_value): _difficulty_value.text = _difficulty_label(_selected_diff)
		return
	var btn := raw as Button
	var r = GameManager.custom_rating
	var m = btn.get_child(0) if btn.get_child_count() > 0 else null
	if not is_instance_valid(m): return
	var vbox = m.get_child(0) if m.get_child_count() > 0 else null
	if not is_instance_valid(vbox) or vbox.get_child_count() < 2: return
	var rating_lbl = vbox.get_child(1) as Label
	if is_instance_valid(rating_lbl): rating_lbl.text = str(r)
	if is_instance_valid(_difficulty_btn):
		if is_instance_valid(_difficulty_value): _difficulty_value.text = _difficulty_label(_selected_diff)

func _on_opponent_selected(kind: String) -> void:
	_selected_opponent = kind
	_refresh_selection()

func _refresh_selection() -> void:
	for key in _opponent_buttons:
		var obtn: Button = _opponent_buttons[key]
		UITheme.apply_button(obtn, UITheme.ACCENT_DIM if key == _selected_opponent else UITheme.BG_CARD2,
			UITheme.TEXT, UITheme.FS_SMALL)
	if _ai_section:
		_ai_section.visible = _selected_opponent == "computer"

	if _difficulty_btn:
		if is_instance_valid(_difficulty_value): _difficulty_value.text = _difficulty_label(_selected_diff)
		_difficulty_btn.visible = _selected_opponent == "computer"
	if _time_btn:
		if is_instance_valid(_time_value): _time_value.text = _clean_time_label(GameManager.TIME_MODES[_selected_time]["label"])
	if _start_btn:
		_start_btn.text = "Start Pass & Play" if _selected_opponent == "local" else "Start Game"

	for key in _diff_buttons:
		var btn: Button = _diff_buttons[key]
		var active = key == _selected_diff
		UITheme.apply_button(btn, UITheme.ACCENT if active else UITheme.BG_CARD2,
			UITheme.TEXT, UITheme.FS_SMALL)

	for key in _color_buttons:
		var btn: Button = _color_buttons[key]
		var active = key == _selected_color
		UITheme.apply_button(btn, UITheme.ACCENT_DIM if active else UITheme.BG_CARD2,
			UITheme.TEXT, UITheme.FS_BODY)

	for key in _time_buttons:
		var btn: Button = _time_buttons[key]
		var active = key == _selected_time
		UITheme.apply_button(btn, UITheme.ACCENT_DIM if active else UITheme.BG_CARD2,
			UITheme.TEXT, UITheme.FS_SMALL)

	var info_lbl = find_child("InfoLabel", true, false) as Label
	if info_lbl:
		if _selected_opponent == "local":
			info_lbl.text = "Two players, one device. White moves first — games are unrated."
			info_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		else:
			var opp = AIEngine.get_difficulty_elo(_selected_diff)
			var expected = PlayerData.expected_score(PlayerData.elo, opp)
			if AIEngine.can_play_rated(_selected_diff):
				info_lbl.text = "Rated game · Opponent %d · Win odds %d%%" % [opp, int(expected * 100)]
				info_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
			else:
				info_lbl.text = "Stockfish unavailable. Fallback games are unrated."
				info_lbl.add_theme_color_override("font_color", UITheme.GOLD)

func _on_diff_selected(key: String) -> void:
	_selected_diff = key
	GameManager.chosen_difficulty = key
	_refresh_selection()

func _on_color_selected(color_val: int) -> void:
	_selected_color = color_val
	_refresh_selection()

func _on_time_selected(mode: String) -> void:
	_selected_time = mode
	GameManager.time_mode = mode
	_refresh_selection()

func _on_start() -> void:
	GameManager.time_mode = _selected_time
	if _selected_opponent == "local":
		GameManager.show_local_game()
		return
	GameManager.local_two_player = false
	GameManager.chosen_difficulty = _selected_diff
	var c = _selected_color
	if c == 0:
		c = ChessLogic.WHITE if randf() > 0.5 else ChessLogic.BLACK
	GameManager.player_color = c
	if not AIEngine.can_play_rated(_selected_diff):
		_show_unrated_fallback_modal()
		return
	GameManager.current_game_rated = true
	GameManager.allow_unrated_fallback = false
	GameManager.show_game()

func _show_unrated_fallback_modal() -> void:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UITheme.make_label("Stockfish Unavailable", UITheme.FS_H2, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UITheme.make_label(
		"Rated play requires the Stockfish model. You can still play the weaker fallback, but the result will not change your rating.",
		UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var play = UITheme.make_btn("Play Unrated Fallback", UITheme.GOLD.darkened(0.15), UITheme.FS_BODY, 56)
	play.pressed.connect(func():
		var o = find_child("FallbackModal", true, false)
		if o: o.queue_free()
		GameManager.current_game_rated = false
		GameManager.allow_unrated_fallback = true
		GameManager.show_game())
	col.add_child(play)

	var cancel = UITheme.make_btn("Cancel", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	cancel.pressed.connect(func():
		var o = find_child("FallbackModal", true, false)
		if o: o.queue_free())
	col.add_child(cancel)

	var ov = ColorRect.new()
	ov.color = Color(0, 0, 0, 0.70)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.name = "FallbackModal"
	add_child(ov)

	var card = UITheme.make_card(col, 24, UITheme.BG_CARD, UITheme.R_LARGE, true)
	var vp = get_viewport_rect().size
	var w = min(460.0, max(300.0, vp.x - 40.0))
	card.anchor_left = 0.0
	card.anchor_right = 0.0
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = (vp.x - w) * 0.5
	card.offset_right = card.offset_left + w
	card.offset_top = -180
	card.offset_bottom = 180
	ov.add_child(card)
