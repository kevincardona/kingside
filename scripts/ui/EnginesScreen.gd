extends Control
# EnginesScreen — pick which engine (and neural net) powers the bots, and add
# new engine packs. New engines/nets arrive as DATA (config + .nnue) that run on
# the bundled Stockfish binary — no app update, App Store-compliant (2.5.2).
# Reached from Settings → "Chess Engine".

var _reg = null
var _catalog_box: VBoxContainer = null
var _check_btn: Button = null

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
	back.pressed.connect(func():
		if GameManager.engines_return_to == "play":
			GameManager.show_difficulty_select()
		else:
			GameManager.show_settings())
	col.add_child(back)

	col.add_child(UITheme.make_label("Engines", UITheme.FS_H1, UITheme.TEXT))
	var intro = UITheme.make_label(
		"Choose the engine that powers the bots. Everything runs on your device — no account, no internet needed.",
		UITheme.FS_SMALL, UITheme.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)

	var reg = get_node_or_null("/root/EngineRegistry")
	if reg == null:
		col.add_child(UITheme.make_label("Engine registry unavailable.", UITheme.FS_BODY, UITheme.RED_LT))
		return
	_reg = reg
	_connect_registry(reg)

	col.add_child(UITheme.make_separator())
	col.add_child(UITheme.make_label("Installed", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	for e in reg.engines():
		col.add_child(_engine_card(e, reg))

	col.add_child(UITheme.spacer(8))
	col.add_child(UITheme.make_separator())
	col.add_child(UITheme.make_label("Add engines", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	col.add_child(_add_engines_card(reg))

	col.add_child(UITheme.spacer(UITheme.safe_bottom() + 24))

func _engine_card(e: Dictionary, reg) -> PanelContainer:
	var id := String(e.get("id", ""))
	var active: bool = reg.is_active(id)
	# PanelContainer (not a bare Panel) so the card sizes to its content — a plain
	# Panel has no min height and collapses, stacking the cards on top of each other.
	var card = UITheme.make_panel_container(UITheme.BG_CARD, UITheme.R_MEDIUM, true)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if active:
		var sb = card.get_theme_stylebox("panel").duplicate()
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = UITheme.ACCENT
		card.add_theme_stylebox_override("panel", sb)

	var m = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	card.add_child(m)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	info.add_child(title_row)
	var name_lbl = UITheme.make_label(String(e.get("name", "Engine")), UITheme.FS_BODY_LG, UITheme.TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title_row.add_child(name_lbl)
	if bool(e.get("bundled", false)):
		title_row.add_child(UITheme.make_pill_badge("Built-in", UITheme.BG_CARD2, UITheme.TEXT_DIM))

	var tagline := String(e.get("tagline", ""))
	if tagline != "":
		var tl = UITheme.make_label(tagline, UITheme.FS_SMALL, UITheme.TEXT_DIM)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(tl)
	var author := String(e.get("author", ""))
	if author != "":
		var al = UITheme.make_label(author, UITheme.FS_CAPTION, UITheme.TEXT_MUTED)
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(al)

	if active:
		var pill = UITheme.make_pill_badge("Active", UITheme.ACCENT, Color.WHITE, UITheme.FS_SMALL)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pill)
	else:
		var btn = UITheme.make_btn("Use", UITheme.ACCENT_DIM, UITheme.FS_SMALL, 48)
		btn.custom_minimum_size.x = 88
		btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(func():
			reg.select(id)
			SoundManager.play_click()
			GameManager.show_engines())
		row.add_child(btn)
	return card

func _add_engines_card(reg) -> PanelContainer:
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	var desc = UITheme.make_label(
		"New engines and neural nets install as data packs that run on the built-in Stockfish, so they download without an app update and work offline once installed.",
		UITheme.FS_SMALL, UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(desc)
	if not reg.has_catalog():
		content.add_child(UITheme.make_label("More engine packs coming soon.", UITheme.FS_BODY, UITheme.TEXT_MUTED))
		return _wrap_card(content)
	_check_btn = UITheme.make_btn("Check for engine packs", UITheme.ACCENT, UITheme.FS_SMALL, 52)
	_check_btn.pressed.connect(_on_check_pressed)
	content.add_child(_check_btn)
	# Populated asynchronously when the catalog loads.
	_catalog_box = VBoxContainer.new()
	_catalog_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_box.add_theme_constant_override("separation", 10)
	content.add_child(_catalog_box)
	# List the packs immediately on open (instant for the bundled catalog; the
	# button remains as a manual refresh, mainly for remote catalogs).
	_on_check_pressed.call_deferred()
	return _wrap_card(content)

# A content-fit card (PanelContainer sizes to its child — a bare Panel would
# collapse to zero height and overlap whatever follows).
func _wrap_card(content: Control, pad: int = 18) -> PanelContainer:
	var card = UITheme.make_panel_container(UITheme.BG_CARD, UITheme.R_MEDIUM, true)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m = MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, pad)
	card.add_child(m)
	m.add_child(content)
	return card

# ── Catalog download flow ──────────────────────────────
func _connect_registry(reg) -> void:
	if not reg.catalog_loaded.is_connected(_on_catalog_loaded):
		reg.catalog_loaded.connect(_on_catalog_loaded)
	if not reg.pack_install_finished.is_connected(_on_install_finished):
		reg.pack_install_finished.connect(_on_install_finished)

func _on_check_pressed() -> void:
	if _reg == null:
		return
	if _check_btn:
		_check_btn.text = "Checking…"
		_check_btn.disabled = true
	_reg.fetch_catalog()

func _on_catalog_loaded(ok: bool, packs: Array, message: String) -> void:
	if not is_inside_tree() or _catalog_box == null:
		return
	if _check_btn:
		_check_btn.text = "Check for engine packs"
		_check_btn.disabled = false
	for c in _catalog_box.get_children():
		c.queue_free()
	if not ok:
		_catalog_box.add_child(_wrapped_note(message, UITheme.GOLD))
		return
	var downloadable := packs.filter(func(p): return not _reg.is_installed(String(p.get("id", ""))))
	if downloadable.is_empty():
		_catalog_box.add_child(_wrapped_note("You already have every available engine pack.", UITheme.TEXT_MUTED))
		return
	for p in downloadable:
		_catalog_box.add_child(_pack_card(p))

func _pack_card(pack: Dictionary) -> PanelContainer:
	var card = UITheme.make_panel_container(UITheme.BG_CARD2, UITheme.R_MEDIUM)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m = MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 16)
	card.add_child(m)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)
	# Autowrap + FILL so a long pack name can't force the card wider than the
	# screen (a non-wrapping label's min-width is its full text width, which was
	# pushing the whole card off the right edge).
	var name_lbl = UITheme.make_label(String(pack.get("name", pack.get("id", ""))), UITheme.FS_BODY, UITheme.TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_horizontal = Control.SIZE_FILL
	info.add_child(name_lbl)
	var desc := String(pack.get("description", pack.get("tagline", "")))
	if desc != "":
		var dl = UITheme.make_label(desc, UITheme.FS_CAPTION, UITheme.TEXT_DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(dl)
	var size_mb := float(pack.get("size_mb", 0.0))
	if size_mb <= 0.0 and int(pack.get("size_bytes", 0)) > 0:
		size_mb = float(int(pack.get("size_bytes", 0))) / 1048576.0
	if size_mb > 0.0:
		info.add_child(UITheme.make_label("%.1f MB" % size_mb, UITheme.FS_CAPTION, UITheme.TEXT_MUTED))
	var dl_btn = UITheme.make_btn("Download", UITheme.ACCENT_DIM, UITheme.FS_SMALL, 48)
	dl_btn.custom_minimum_size.x = 116
	dl_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	dl_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dl_btn.pressed.connect(func():
		dl_btn.text = "Downloading…"
		dl_btn.disabled = true
		_reg.install_catalog_pack(pack))
	row.add_child(dl_btn)
	return card

func _on_install_finished(_id: String, ok: bool, message: String) -> void:
	if not is_inside_tree():
		return
	if ok:
		SoundManager.play_click()
		GameManager.show_engines()   # rebuild — the pack now shows under "Installed"
	elif _catalog_box != null:
		_catalog_box.add_child(_wrapped_note("Couldn't install: %s" % message, UITheme.RED_LT))

# Status notes MUST autowrap: a non-wrapping Label's min-width is its full text
# width, and (with horizontal scroll disabled) the ScrollContainer inherits its
# content's min width — one long label made the whole page wider than the screen.
func _wrapped_note(text: String, color: Color) -> Label:
	var l = UITheme.make_label(text, UITheme.FS_SMALL, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_FILL
	return l
