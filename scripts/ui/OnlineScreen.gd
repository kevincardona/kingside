extends Control
# Online play hub with two backends:
#
#   Cross-platform (OnlineManager, any OS — needs online_service.cfg):
#     - Quick Match          → join the oldest waiting player, else queue up
#     - Create Invite Code   → 6-letter code a friend enters on any device
#     - Join with Code       → enter a friend's code
#
#   Game Center (Apple devices only):
#     - Challenge a Friend   → Apple's matchmaker sheet (iMessage invites)
#     - Random Opponent      → Game Center auto-match
#
# "Your Matches" merges both lists; rows open GameScreen in online mode with
# the right backend tagged in the match info.

var _status_lbl: Label = null
var _matches_box: VBoxContainer = null
var _gc_signin_section: VBoxContainer = null
var _gc_play_section: VBoxContainer = null
var _code_edit: LineEdit = null
var _finding: bool = false
var _gc_matches: Array = []
var _web_matches: Array = []

func _ready() -> void:
	GameCenterManager.auth_changed.connect(_on_gc_auth_changed)
	GameCenterManager.match_found.connect(_on_gc_match_found)
	GameCenterManager.turn_received.connect(_on_gc_turn_received)
	GameCenterManager.matches_loaded.connect(_on_gc_matches_loaded)
	GameCenterManager.matchmaker_cancelled.connect(_on_matchmaker_cancelled)
	GameCenterManager.realtime_cancelled.connect(_on_realtime_cancelled)
	GameCenterManager.gc_error.connect(_on_gc_error)
	OnlineManager.match_found.connect(_on_web_match_found)
	OnlineManager.matches_loaded.connect(_on_web_matches_loaded)
	OnlineManager.net_error.connect(_on_web_error)
	_build()
	_refresh_lists()

func _exit_tree() -> void:
	for conn in [
		["auth_changed", _on_gc_auth_changed],
		["match_found", _on_gc_match_found],
		["turn_received", _on_gc_turn_received],
		["matches_loaded", _on_gc_matches_loaded],
		["matchmaker_cancelled", _on_matchmaker_cancelled],
		["realtime_cancelled", _on_realtime_cancelled],
		["gc_error", _on_gc_error],
	]:
		if GameCenterManager.is_connected(conn[0], conn[1]):
			GameCenterManager.disconnect(conn[0], conn[1])
	for conn in [
		["match_found", _on_web_match_found],
		["matches_loaded", _on_web_matches_loaded],
		["net_error", _on_web_error],
	]:
		if OnlineManager.is_connected(conn[0], conn[1]):
			OnlineManager.disconnect(conn[0], conn[1])

func _refresh_lists() -> void:
	if GameCenterManager.is_supported() and GameCenterManager.is_authenticated():
		GameCenterManager.load_matches()
	if OnlineManager.is_configured():
		OnlineManager.load_matches()

# ── Layout ──

func _build() -> void:
	add_child(UITheme.make_page_bg())

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.hide_v_scrollbar(scroll)
	add_child(scroll)

	var outer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	scroll.add_child(outer)

	var margin = UITheme.page_panel(560, 24)
	outer.add_child(margin)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	col.add_child(UITheme.spacer(UITheme.safe_top() + 6))

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(header)
	var back = UITheme.make_icon_btn("‹", UITheme.BG_CARD2, 52)
	back.tooltip_text = "Back"
	back.pressed.connect(GameManager.show_main_menu)
	header.add_child(back)
	# Left-aligned sub-page title (matches the puzzle solver header), so the
	# back button and title sit together instead of leaving a centered gap.
	var title_lbl = UITheme.make_label("Online", UITheme.FS_H2, UITheme.TEXT)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_lbl)

	_status_lbl = UITheme.make_label("", UITheme.FS_SMALL, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status_lbl)

	var any_backend = OnlineManager.is_configured() or GameCenterManager.is_supported()
	if not any_backend:
		_status_lbl.text = "Online play is not configured for this build. Add Firebase keys to online_service.cfg (see docs/ONLINE_SETUP.md)."
		col.add_child(UITheme.spacer(UITheme.safe_bottom() + 8))
		return

	if OnlineManager.is_configured():
		_build_web_section(col)

	if GameCenterManager.is_supported():
		_build_gc_section(col)

	# ── Your Matches ──
	var matches_header = HBoxContainer.new()
	matches_header.add_theme_constant_override("separation", 10)
	col.add_child(matches_header)
	var matches_title = UITheme.make_label("Your Matches", UITheme.FS_H3, UITheme.TEXT)
	matches_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	matches_header.add_child(matches_title)
	var refresh = UITheme.make_btn("Refresh", UITheme.BG_CARD2, UITheme.FS_CAPTION, 40, UITheme.R_SMALL)
	refresh.size_flags_horizontal = Control.SIZE_SHRINK_END
	refresh.custom_minimum_size.x = 92
	refresh.pressed.connect(_refresh_lists)
	matches_header.add_child(refresh)

	_matches_box = VBoxContainer.new()
	_matches_box.add_theme_constant_override("separation", 8)
	col.add_child(_matches_box)

	col.add_child(UITheme.spacer(UITheme.safe_bottom() + 8))
	_refresh_gc_sections()

func _build_web_section(col: VBoxContainer) -> void:
	col.add_child(UITheme.make_label("PLAY ANYWHERE", UITheme.FS_CAPTION, UITheme.TEXT_MUTED))

	var quick_btn = UITheme.make_btn("Quick Match", UITheme.ACCENT, UITheme.FS_H3, 72)
	quick_btn.pressed.connect(func():
		if _finding: return
		_finding = true
		_set_status("Finding a match…")
		OnlineManager.quick_match())
	col.add_child(quick_btn)
	var quick_hint = UITheme.make_label("Any device — Mac, Windows, Linux, Android, iPhone",
		UITheme.FS_CAPTION, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(quick_hint)

	var invite_btn = UITheme.make_btn("Create Invite Code", UITheme.BG_CARD2, UITheme.FS_BODY, 60)
	invite_btn.pressed.connect(func():
		_set_status("Creating match…")
		OnlineManager.create_match(false))
	col.add_child(invite_btn)

	var join_row = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	col.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Friend's code"
	_code_edit.max_length = 6
	_code_edit.custom_minimum_size.y = 56
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.add_theme_font_size_override("font_size", UITheme.FS_BODY)
	join_row.add_child(_code_edit)
	var join_btn = UITheme.make_btn("Join", UITheme.ACCENT_DIM, UITheme.FS_BODY, 56)
	join_btn.custom_minimum_size.x = 110
	join_btn.pressed.connect(func():
		var code = _code_edit.text.strip_edges()
		if code.length() < 4:
			_set_status("Enter the 6-letter code your friend shared.", UITheme.GOLD)
			return
		_set_status("Joining %s…" % code.to_upper())
		OnlineManager.join_match(code))
	join_row.add_child(join_btn)

func _build_gc_section(col: VBoxContainer) -> void:
	col.add_child(UITheme.spacer(2))
	col.add_child(UITheme.make_label("GAME CENTER", UITheme.FS_CAPTION, UITheme.TEXT_MUTED))

	_gc_signin_section = VBoxContainer.new()
	_gc_signin_section.add_theme_constant_override("separation", 12)
	col.add_child(_gc_signin_section)
	var signin = UITheme.make_btn("Sign in to Game Center", UITheme.BG_CARD2, UITheme.FS_BODY, 60)
	signin.pressed.connect(func():
		_set_status("Signing in…")
		GameCenterManager.authenticate())
	_gc_signin_section.add_child(signin)

	_gc_play_section = VBoxContainer.new()
	_gc_play_section.add_theme_constant_override("separation", 12)
	col.add_child(_gc_play_section)

	# Live (real-time) match — the headline online mode.
	var live_btn = UITheme.make_btn("Play Live", UITheme.ACCENT, UITheme.FS_H3, 68)
	live_btn.pressed.connect(func():
		if _finding: return
		_finding = true
		_set_status("Finding a live opponent…")
		GameCenterManager.find_realtime_match())
	_gc_play_section.add_child(live_btn)
	var live_hint = UITheme.make_label("Real-time game — invite a friend or auto-match",
		UITheme.FS_CAPTION, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_gc_play_section.add_child(live_hint)

	var friend_btn = UITheme.make_btn("Challenge a Friend (turn-based)", UITheme.BG_CARD2, UITheme.FS_BODY, 60)
	friend_btn.pressed.connect(func():
		_set_status("")
		GameCenterManager.show_matchmaker())
	_gc_play_section.add_child(friend_btn)
	var friend_hint = UITheme.make_label("Invites are sent through iMessage", UITheme.FS_CAPTION,
		UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_gc_play_section.add_child(friend_hint)

	var random_btn = UITheme.make_btn("Random Opponent (Game Center)", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	random_btn.pressed.connect(func():
		if _finding: return
		_finding = true
		_set_status("Finding a match…")
		GameCenterManager.find_match())
	_gc_play_section.add_child(random_btn)

	var leaderboard_btn = UITheme.make_btn("Leaderboard", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	leaderboard_btn.pressed.connect(GameCenterManager.show_leaderboard)
	_gc_play_section.add_child(leaderboard_btn)

func _refresh_gc_sections() -> void:
	var authed = GameCenterManager.is_authenticated()
	if _gc_signin_section: _gc_signin_section.visible = not authed
	if _gc_play_section: _gc_play_section.visible = authed

func _set_status(text: String, color: Color = UITheme.TEXT_MUTED) -> void:
	if _status_lbl and is_instance_valid(_status_lbl):
		_status_lbl.text = text
		_status_lbl.add_theme_color_override("font_color", color)

# ── Opening matches ──

func _open_match(match_id: String, my_turn: bool, data, info: Dictionary) -> void:
	GameManager.show_online_game({
		"match_id": match_id,
		"my_turn": my_turn,
		"data": data,
		"i_created": bool(info.get("i_created", false)),
		"opponent": str(info.get("opponent", "")),
		"backend": str(info.get("backend", "gamecenter")),
	})

# Friend invite created: show the code big and clear before play starts.
func _show_invite_code(code: String) -> void:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UITheme.make_label("Invite a Friend", UITheme.FS_H2, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var code_lbl = UITheme.make_label(code, UITheme.FS_H1, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(code_lbl)
	var hint = UITheme.make_label(
		"Share this code. Your friend taps Join with Code on any device — Mac, Windows, Linux, Android or iPhone.",
		UITheme.FS_SMALL, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	col.add_child(UITheme.spacer(4))

	var copy_btn = UITheme.make_btn("Copy Code", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(code)
		copy_btn.text = "Copied!")
	col.add_child(copy_btn)

	var play_btn = UITheme.make_btn("Open the Board", UITheme.ACCENT, UITheme.FS_BODY, 56)
	play_btn.pressed.connect(func():
		GameModals.dismiss(self, "InviteCode")
		_open_match(code, true, {}, {"i_created": true, "opponent": "", "backend": "web"}))
	col.add_child(play_btn)

	var close_btn = UITheme.make_btn("Later", UITheme.BG_CARD2, UITheme.FS_BODY, 56)
	close_btn.pressed.connect(func():
		GameModals.dismiss(self, "InviteCode")
		_refresh_lists())
	col.add_child(close_btn)

	GameModals.show_modal_card(self, "InviteCode", col, 420)

# ── Match list (merged) ──

func _rebuild_match_list() -> void:
	if not is_instance_valid(_matches_box): return
	for child in _matches_box.get_children():
		child.queue_free()
	var rows: Array = []
	for m in _web_matches:
		if int(m.get("status", 0)) != 2:
			rows.append(m)
	for m in _gc_matches:
		# GKTurnBasedMatchStatusEnded == 2: hide finished games from the list
		if int(m.get("status", 0)) != 2:
			rows.append(m)
	rows.sort_custom(func(a, b):
		return bool(a.get("my_turn", false)) and not bool(b.get("my_turn", false)))
	if rows.is_empty():
		var empty = UITheme.make_label("No matches yet — challenge a friend!",
			UITheme.FS_SMALL, UITheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_matches_box.add_child(empty)
		return
	for m in rows:
		_matches_box.add_child(_make_match_row(m))

func _make_match_row(m: Dictionary) -> Control:
	var my_turn = bool(m.get("my_turn", false))
	var waiting = bool(m.get("waiting", false))
	var backend = str(m.get("backend", "gamecenter"))
	var opponent = str(m.get("opponent", ""))
	if opponent == "":
		opponent = ("Code %s — share it" % str(m.get("code", ""))) if waiting else "Waiting for opponent"

	var btn = Button.new()
	btn.set_script(UITheme.ScrollFriendlyButtonScript)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 64
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	UITheme.apply_button(btn, UITheme.BG_CARD2, UITheme.TEXT, UITheme.FS_SMALL)

	var row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	row.add_child(UITheme.spacer(0))

	var m_left = MarginContainer.new()
	m_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m_left.add_theme_constant_override("margin_left", 14)
	m_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(m_left)
	var left_col = VBoxContainer.new()
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	m_left.add_child(left_col)
	var name_lbl = UITheme.make_label(opponent, UITheme.FS_BODY, UITheme.TEXT)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left_col.add_child(name_lbl)
	left_col.add_child(UITheme.make_label(
		"Game Center" if backend == "gamecenter" else "Online",
		UITheme.FS_CAPTION, UITheme.TEXT_MUTED))

	var m_right = MarginContainer.new()
	m_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m_right.add_theme_constant_override("margin_right", 14)
	row.add_child(m_right)
	var turn_text = "Waiting…" if waiting else ("Your turn" if my_turn else "Their turn")
	var turn_lbl = UITheme.make_label(turn_text,
		UITheme.FS_CAPTION, UITheme.ACCENT_LT if my_turn else UITheme.TEXT_MUTED)
	turn_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	turn_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	m_right.add_child(turn_lbl)

	var match_id = str(m.get("match_id", ""))
	var data = str(m.get("data", ""))
	var info = {
		"i_created": bool(m.get("i_created", false)),
		"opponent": str(m.get("opponent", "")),
		"backend": backend,
	}
	btn.pressed.connect(func(): _open_match(match_id, my_turn, data, info))
	return btn

# ── Game Center events ──

func _on_gc_auth_changed(ok: bool, player_name: String) -> void:
	_set_status("Signed in as %s" % player_name if ok else "Game Center sign-in failed.",
		UITheme.TEXT_MUTED if ok else UITheme.GOLD)
	_refresh_gc_sections()
	if ok:
		GameCenterManager.load_matches()

func _on_gc_match_found(match_id: String, my_turn: bool, data: Dictionary, info: Dictionary) -> void:
	_finding = false
	info = info.duplicate(); info["backend"] = "gamecenter"
	_open_match(match_id, my_turn, data, info)

func _on_gc_turn_received(match_id: String, my_turn: bool, data: Dictionary, ended: bool, _outcome: String, info: Dictionary) -> void:
	# Only open matches the player explicitly chose (matchmaker sheet or
	# invite notification); passive turn updates just refresh the list.
	if bool(info.get("active", false)) and not ended:
		info = info.duplicate(); info["backend"] = "gamecenter"
		_open_match(match_id, my_turn, data, info)
	else:
		GameCenterManager.load_matches()

func _on_matchmaker_cancelled() -> void:
	_set_status("")

func _on_realtime_cancelled() -> void:
	_finding = false
	_set_status("")

func _on_gc_error(op: String, message: String) -> void:
	_finding = false
	if op == "find_match" and _is_gc_app_not_recognized(message):
		if OnlineManager.is_configured():
			_finding = true
			_set_status("Game Center is not enabled for this build yet. Using Online quick match…", UITheme.GOLD)
			OnlineManager.quick_match()
		else:
			_set_status("Game Center is not enabled for this app ID yet. Use Play Bots for now, or configure Game Center in App Store Connect.", UITheme.GOLD)
		return
	_set_status("%s failed: %s" % [op.capitalize().replace("_", " "), message], UITheme.GOLD)

func _is_gc_app_not_recognized(message: String) -> bool:
	var clean = message.to_lower()
	return clean.contains("not recognized") or clean.contains("unrecognized") or clean.contains("not recognised")

func _on_gc_matches_loaded(matches: Array) -> void:
	_gc_matches = matches
	_rebuild_match_list()

# ── Cross-platform events ──

func _on_web_match_found(match_id: String, my_turn: bool, data: Dictionary, info: Dictionary) -> void:
	_finding = false
	_set_status("")
	# A fresh friend invite shows its code first; quick matches and joins
	# open the board straight away.
	if bool(info.get("waiting", false)) and not bool(info.get("quick", false)):
		_show_invite_code(match_id)
		return
	_open_match(match_id, my_turn, data, info)

func _on_web_matches_loaded(matches: Array) -> void:
	_web_matches = matches
	_rebuild_match_list()

func _on_web_error(op: String, message: String) -> void:
	_finding = false
	_set_status("%s failed: %s" % [op.capitalize().replace("_", " "), message], UITheme.GOLD)
