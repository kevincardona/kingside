extends Control

# Main menu. When the multiplayer flag is on, a "Play Online" button routes to
# OnlineScreen (Game Center turn-based matches + leaderboard). Cross-platform
# (Firebase) online stays dormant unless online_service.cfg is filled in.

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(UITheme.make_page_bg())

	var wide = _wide_layout()
	# No scroll — the whole menu fits on one screen. A full-rect VBox centers
	# the content vertically in the space above the bottom nav.
	var outer = VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if wide:
		outer.offset_left = 92
	else:
		outer.offset_bottom = -float(72 + UITheme.safe_bottom())
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(outer)

	var margin = UITheme.page_panel(720, 18)
	outer.add_child(margin)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	# Safe area top spacer
	col.add_child(UITheme.spacer(UITheme.safe_top()))

	var logo = _HomeLogo.new()
	logo.custom_minimum_size = Vector2(100, 100)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(logo)

	var title = UITheme.make_label("Kingside", UITheme.FS_H1, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(title)

	# Rating badge
	col.add_child(_make_rating_badge())
	# Days-played streak badge (flame)
	if PlayerData.day_streak >= 1:
		col.add_child(UITheme.spacer(2))
		col.add_child(_make_streak_badge())
	col.add_child(UITheme.spacer(8))

	# Play button
	var play_btn = UITheme.make_btn("New Game", UITheme.ACCENT, UITheme.FS_H3, 64)
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.pressed.connect(_on_play)
	col.add_child(play_btn)

	if PlayerData.has_saved_games():
		col.add_child(UITheme.make_label("Continue", UITheme.FS_SMALL, UITheme.TEXT_DIM))
		# Only the most recent game inline so the menu stays compact (the full list
		# used to push the stats row behind the bottom nav). The rest live behind
		# "View all games".
		col.add_child(_make_session_card(PlayerData.saved_games[0]))
		var more = PlayerData.saved_games.size() - 1
		if more > 0:
			var all_btn = UITheme.make_btn("View all games  (%d more)" % more,
				UITheme.BG_CARD2, UITheme.FS_SMALL, 46)
			all_btn.pressed.connect(_show_all_games_modal)
			col.add_child(all_btn)

	# (Puzzles lives in the bottom nav, so no separate button here.)

	# Online play (Game Center turn-based matches + leaderboard) lives behind the
	# multiplayer flag. The Online screen handles sign-in, matchmaking and the
	# leaderboard; the menu just needs one entry point.
	if GameManager.feature_flags.get("multiplayer", false):
		var online_btn = UITheme.make_btn("Play Online", UITheme.ACCENT_DIM, UITheme.FS_BODY, 56)
		online_btn.pressed.connect(GameManager.show_online)
		col.add_child(online_btn)

	col.add_child(UITheme.spacer(12))
	col.add_child(_make_stats_row())
	col.add_child(UITheme.spacer(UITheme.safe_bottom() + 8))
	add_child(UITheme.make_app_nav("play", wide))

func _make_rating_badge() -> Control:
	var cc = CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_PASS
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var badge = UITheme.make_panel(UITheme.BG_CARD, 42)
	badge.custom_minimum_size = Vector2(220, 46)
	cc.add_child(badge)

	var inner = HBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 12)
	badge.add_child(inner)

	# Shrink-center every part so "1066 · Novice" packs into one tight,
	# truly-centered group (expanding the halves left the title offset).
	var rating = UITheme.make_label(str(PlayerData.elo), UITheme.FS_H3, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	rating.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(rating)
	var dot = UITheme.make_label("·", UITheme.FS_BODY, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(dot)
	var title = UITheme.make_label(PlayerData.get_title(), UITheme.FS_BODY, PlayerData.get_title_color(), HORIZONTAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(title)
	return cc

func _make_streak_badge() -> Control:
	var cc = CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_PASS
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# PanelContainer (NOT plain Panel) so the pill sizes to its content and the
	# CenterContainer can center it. Content padding + border live on the style.
	var pill = PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = UITheme.panel_style(Color(UITheme.ORANGE, 0.15), 22)
	style.content_margin_left = 16
	style.content_margin_right = 20
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(UITheme.ORANGE, 0.40)
	pill.add_theme_stylebox_override("panel", style)
	cc.add_child(pill)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 9)
	pill.add_child(row)

	var flame = FlameIcon.new()
	flame.custom_minimum_size = Vector2(26, 30)
	flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(flame)

	var count = UITheme.make_label(str(PlayerData.day_streak), UITheme.FS_H3, UITheme.GOLD)
	count.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(count)

	var unit = "day" if PlayerData.day_streak == 1 else "days"
	var label = UITheme.make_label("%s streak" % unit, UITheme.FS_SMALL, UITheme.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return cc

# Fun persona names so each bot tier has an identity that's easy to remember.
const BOT_NAMES = {
	"beginner": "Pip", "easy": "Casey", "medium": "Morgan", "hard": "Dexter",
	"expert": "Vera", "master": "Capa", "stockfish_max": "Apex", "local": "Pass & Play",
}

func _bot_name(difficulty: String) -> String:
	return BOT_NAMES.get(difficulty, "Stockfish")

func _time_mode_label(mode: String) -> String:
	match mode:
		"blitz":   return "Blitz"
		"rapid":   return "Rapid"
		"classic": return "Classical"
		"casual":  return "Casual"
	return ""

# A single-line, click-through (mouse-ignore) label that ellipsises rather than
# forcing the row wider.
func _clip_label(text: String, font_size: int, color: Color) -> Label:
	var l = UITheme.make_label(text, font_size, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l

func _make_session_card(session: Dictionary) -> Control:
	var is_black = int(session.get("player_color", ChessLogic.WHITE)) == ChessLogic.BLACK
	var card = UITheme.make_panel_container(UITheme.BG_CARD2, UITheme.R_MEDIUM)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	card.add_child(hbox)

	# The whole left area is one big tap-to-resume target — a separate Resume
	# button would eat ~90px on a narrow modal and force the info to truncate. A
	# "›" chevron hints it's tappable. (Flat Button + a real min height so it
	# doesn't collapse; ScrollFriendly so dragging still scrolls the list.)
	var resume := Button.new()
	resume.set_script(UITheme.ScrollFriendlyButtonScript)
	resume.focus_mode = Control.FOCUS_NONE
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Tall enough for three text lines + padding (a Button doesn't grow to fit a
	# FULL_RECT child, so too small clips the bottom "Move / when" line).
	resume.custom_minimum_size.y = 86
	resume.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	resume.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	resume.add_theme_stylebox_override("hover", UITheme.panel_style(Color(UITheme.TEXT, 0.05), UITheme.R_MEDIUM))
	resume.add_theme_stylebox_override("pressed", UITheme.panel_style(Color(UITheme.TEXT, 0.09), UITheme.R_MEDIUM))
	resume.pressed.connect(_on_resume.bind(session))
	hbox.add_child(resume)

	var rm := MarginContainer.new()
	rm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rm.add_theme_constant_override("margin_left", 12)
	rm.add_theme_constant_override("margin_right", 8)
	rm.add_theme_constant_override("margin_top", 10)
	rm.add_theme_constant_override("margin_bottom", 10)
	resume.add_child(rm)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	rm.add_child(row)

	# Mini board thumbnail of the saved position, so a game is easy to recognise.
	var thumb := _MiniBoard.new()
	thumb.custom_minimum_size = Vector2(46, 46)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.set_fen(String(session.get("fen", "")), is_black)
	row.add_child(thumb)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.custom_minimum_size.x = 0
	info.clip_contents = true
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	var diff = String(session.get("difficulty", "medium"))
	if diff == "":
		diff = "medium"
	var diff_label = AIEngine.get_difficulty_label(diff)
	var elo = AIEngine.get_difficulty_elo(diff)
	var side_txt = "Black" if is_black else "White"
	var moves = int(session.get("moves_played", 0))
	var time_label = _time_mode_label(String(session.get("time_mode", "")))

	# Three short lines: name, difficulty + Elo (+ time control), then side/clock/when.
	info.add_child(_clip_label(_bot_name(diff), UITheme.FS_SMALL, UITheme.TEXT))
	var line2 = "%s  ·  %d" % [diff_label, elo]
	if time_label != "":
		line2 += "  ·  " + time_label
	info.add_child(_clip_label(line2, UITheme.FS_CAPTION, UITheme.TEXT_DIM))
	var sub = "%s  ·  Move %d" % [side_txt, moves]
	var ago = _time_ago(int(session.get("saved_at", 0)))
	if ago != "":
		sub += "  ·  " + ago
	info.add_child(_clip_label(sub, UITheme.FS_CAPTION, UITheme.TEXT_MUTED))

	var chev := UITheme.make_label("›", UITheme.FS_H3, UITheme.TEXT_MUTED)
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chev.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(chev)

	var del_btn = UITheme.make_btn("X", UITheme.RED.darkened(0.25), UITheme.FS_CAPTION, 0, UITheme.R_SMALL)
	del_btn.custom_minimum_size.x = 44
	del_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	del_btn.size_flags_vertical = Control.SIZE_FILL
	del_btn.pressed.connect(_on_delete_session.bind(session["id"], card))
	hbox.add_child(del_btn)

	return card

# Modal listing every saved game (the menu only shows the most recent inline).
# Fixed title + Close, with ONLY the list scrolling, so a long list scrolls
# cleanly and the actions never drift off-screen.
func _show_all_games_modal() -> void:
	var ov = GameModals.make_overlay(self, "AllGames")
	var vp = get_viewport_rect().size
	var card_w = min(440.0, vp.x - 28.0)
	# Hug the content for a few games, cap + scroll for many.
	var est = 160.0 + float(PlayerData.saved_games.size()) * 74.0
	var card_h = clampf(est, 220.0, min(vp.y - 90.0, 580.0))

	var card = Panel.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_CARD, UITheme.R_LARGE, true))
	card.anchor_left = 0.5; card.anchor_right = 0.5
	card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -card_w * 0.5; card.offset_right = card_w * 0.5
	card.offset_top = -card_h * 0.5; card.offset_bottom = card_h * 0.5
	ov.add_child(card)

	var m = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 18)
	card.add_child(m)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	m.add_child(col)

	col.add_child(UITheme.make_label("Your games", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.hide_v_scrollbar(scroll)
	col.add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for session in PlayerData.saved_games:
		list.add_child(_make_session_card(session))

	var close = UITheme.make_btn("Close", UITheme.BG_CARD2, UITheme.FS_BODY, 50)
	close.pressed.connect(func(): GameModals.dismiss(self, "AllGames"))
	col.add_child(close)

# Compact, iOS-safe position thumbnail: an 8x8 grid with a coloured disc per
# piece (sized by piece type), drawn straight from the FEN. No glyph fonts (which
# can render as tofu on iOS), so it works everywhere.
class _MiniBoard extends Control:
	var _rows: Array = []
	var _flipped := false
	const _RAD = {"p": 0.30, "n": 0.36, "b": 0.36, "r": 0.40, "q": 0.46, "k": 0.44}

	func set_fen(fen: String, flipped: bool = false) -> void:
		_flipped = flipped
		_rows = []
		var placement = fen.split(" ")[0] if fen != "" else ""
		for part in placement.split("/"):
			var r = ""
			for c in part:
				r += ".".repeat(int(c)) if c.is_valid_int() else c
			while r.length() < 8:
				r += "."
			_rows.append(r.substr(0, 8))
		queue_redraw()

	func _draw() -> void:
		var s = min(size.x, size.y)
		var cell = s / 8.0
		# Board-like squares that contrast with the card; drawn even when the FEN is
		# missing/invalid so a malformed save still shows a board, not a blank gap.
		var light = Color(0.36, 0.40, 0.30)
		var dark = Color(0.23, 0.26, 0.20)
		for r in 8:
			for f in 8:
				draw_rect(Rect2(f * cell, r * cell, cell, cell), light if (r + f) % 2 == 0 else dark)
		if _rows.size() < 8:
			return
		for r in 8:
			var rr = (7 - r) if _flipped else r
			for f in 8:
				var ff = (7 - f) if _flipped else f
				var ch = _rows[rr][ff]
				if ch == ".":
					continue
				var is_white = ch == ch.to_upper()
				var rad = cell * float(_RAD.get(ch.to_lower(), 0.34))
				var center = Vector2((f + 0.5) * cell, (r + 0.5) * cell)
				draw_circle(center, rad, Color(0.95, 0.95, 0.91) if is_white else Color(0.12, 0.12, 0.12))
				draw_arc(center, rad, 0, TAU, 12,
					Color(0, 0, 0, 0.4) if is_white else Color(1, 1, 1, 0.22), 1.0)

# Human "time ago" from a unix timestamp (0/absent → "" so legacy saves show
# nothing). Coarse buckets are plenty for a Continue list.
func _time_ago(unix: int) -> String:
	if unix <= 0:
		return ""
	var secs = int(Time.get_unix_time_from_system()) - unix
	if secs < 60:    return "just now"
	if secs < 3600:  return "%dm ago" % (secs / 60)
	if secs < 86400: return "%dh ago" % (secs / 3600)
	var days = secs / 86400
	if days == 1:    return "yesterday"
	if days < 7:     return "%dd ago" % days
	return "%dw ago" % (days / 7)

func _make_stats_row() -> HBoxContainer:
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 32)

	for stat in [[str(PlayerData.wins), "Wins"],
	             [str(PlayerData.games_played), "Games"],
	             [str(PlayerData.best_streak), "Streak"]]:
		var col = VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_PASS
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(UITheme.make_label(stat[0], UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(UITheme.make_label(stat[1], UITheme.FS_CAPTION, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		row.add_child(col)

	return row

func _on_play() -> void:    GameManager.show_difficulty_select()
func _on_resume(session: Dictionary) -> void: GameManager.resume_game(session)

func _on_delete_session(session_id: int, _card: Control = null) -> void:
	# Confirm first — deleting a continuable game can't be undone.
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UITheme.make_label("Delete this game?", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var msg = UITheme.make_label("It will be removed from Continue. This can't be undone.",
		UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(msg)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cancel = UITheme.make_btn("Cancel", UITheme.BG_CARD2, UITheme.FS_BODY, 50)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func(): GameModals.dismiss(self, "ConfirmDeleteSession"))
	var del = UITheme.make_btn("Delete", UITheme.RED.darkened(0.1), UITheme.FS_BODY, 50)
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del.pressed.connect(func():
		GameModals.dismiss(self, "ConfirmDeleteSession")
		PlayerData.delete_game_session(session_id)
		_rebuild())   # rebuild so the Continue header/section also clears when empty
	row.add_child(cancel)
	row.add_child(del)
	col.add_child(row)
	GameModals.show_modal_card(self, "ConfirmDeleteSession", col, 360)

func _rebuild() -> void:
	if not is_inside_tree(): return
	for child in get_children():
		child.queue_free()
	_build()

func _wide_layout() -> bool:
	return get_viewport_rect().size.x >= 900

class _HomeLogo extends Control:
	func _draw() -> void:
		var w = min(size.x, size.y)
		var origin = (size - Vector2(w, w)) * 0.5
		var r = Rect2(origin + Vector2(w * 0.06, w * 0.06), Vector2(w * 0.88, w * 0.88))
		draw_rect(r, UITheme.BG_CARD2)
		draw_rect(Rect2(r.position + Vector2(w * 0.08, w * 0.08), Vector2(w * 0.36, w * 0.36)), UITheme.ACCENT_DIM)
		draw_rect(Rect2(r.position + Vector2(w * 0.44, w * 0.44), Vector2(w * 0.36, w * 0.36)), UITheme.ACCENT_DIM)
		# Knight Piece Silhouette
		var k_pts = PackedVector2Array([
			origin + Vector2(w * 0.35, w * 0.80), # Base Bottom Left
			origin + Vector2(w * 0.65, w * 0.80), # Base Bottom Right
			origin + Vector2(w * 0.62, w * 0.70), # Base Top Right
			origin + Vector2(w * 0.55, w * 0.65), # Neck Back
			origin + Vector2(w * 0.65, w * 0.50), # Head Back
			origin + Vector2(w * 0.60, w * 0.30), # Top Head
			origin + Vector2(w * 0.45, w * 0.35), # Nose Top
			origin + Vector2(w * 0.30, w * 0.45), # Nose Tip
			origin + Vector2(w * 0.35, w * 0.55), # Jaw
			origin + Vector2(w * 0.45, w * 0.50), # Neck Front
			origin + Vector2(w * 0.38, w * 0.70), # Base Top Left
		])
		draw_colored_polygon(k_pts, UITheme.TEXT)
		# Eye
		draw_circle(origin + Vector2(w * 0.52, w * 0.42), w * 0.025, UITheme.BG_CARD)
		# Pedestal
		draw_rect(Rect2(origin + Vector2(w * 0.30, w * 0.82), Vector2(w * 0.40, w * 0.06)), UITheme.TEXT)
