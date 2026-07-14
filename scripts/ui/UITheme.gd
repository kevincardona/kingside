class_name UITheme

# ── Palette ────────────────────────────────────────────────────────────────────
const BG_PAGE    = Color("#111512")
const BG_CARD    = Color("#1E241F")
const BG_CARD2   = Color("#293128")
const BG_CARD3   = Color("#353F32")
const ACCENT     = Color("#7FA650")
const ACCENT_LT  = Color("#95B96A")
const ACCENT_DIM = Color("#5E7F3E")
const GOLD       = Color("#E9B949")
const ORANGE     = Color("#D4823A")
const RED        = Color("#B9473D")
const RED_LT     = Color("#D65A4E")
const TEXT       = Color("#F0F1EC")
const TEXT_DIM   = Color("#B7BBAF")
const TEXT_MUTED = Color("#7E8478")

const FS_DISPLAY = 72
const FS_H1      = 46
const FS_H2      = 34
const FS_H3      = 26
const FS_BODY_LG = 22
const FS_BODY    = 20
const FS_SMALL   = 17
const FS_CAPTION = 14

# Radii
const R_LARGE  = 16
const R_MEDIUM = 12
const R_SMALL  = 8

# ── Safe area (Dynamic Island / home indicator) ────────────────────────────────
static func safe_top() -> int:
	var rect = DisplayServer.get_display_safe_area()
	if rect.position.y <= 0:
		return 0
	var win_h = DisplayServer.window_get_size().y
	if win_h <= 0:
		return 0
	var vp_h = int(ProjectSettings.get_setting("display/window/size/viewport_height", 932))
	return int(rect.position.y * float(vp_h) / float(win_h))

static func safe_bottom() -> int:
	var rect = DisplayServer.get_display_safe_area()
	var win_h = DisplayServer.window_get_size().y
	if win_h <= 0:
		return 0
	var phys_bottom = win_h - (rect.position.y + rect.size.y)
	if phys_bottom <= 0:
		return 0
	var vp_h = int(ProjectSettings.get_setting("display/window/size/viewport_height", 932))
	return int(phys_bottom * float(vp_h) / float(win_h))

# ──────────────────────────────────────────────────────────────────────────────
#  Page background — soft vertical gradient instead of a flat fill
# ──────────────────────────────────────────────────────────────────────────────
static func make_page_bg() -> Control:
	var grad = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors  = PackedColorArray([Color("#182019"), BG_PAGE, Color("#0C0F0C")])
	var tex = GradientTexture2D.new()
	tex.gradient  = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to   = Vector2(0, 1)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

# ──────────────────────────────────────────────────────────────────────────────
#  StyleBox builders
# ──────────────────────────────────────────────────────────────────────────────
static func _flat(color: Color, radius: int, shadow: bool = false) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left     = radius
	s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left  = radius
	s.corner_radius_bottom_right = radius
	if shadow:
		s.shadow_color  = Color(0, 0, 0, 0.40)
		s.shadow_size   = 6
		s.shadow_offset = Vector2i(0, 3)
	return s

static func panel_style(color: Color = BG_CARD, radius: int = R_MEDIUM,
                        shadow: bool = false) -> StyleBoxFlat:
	return _flat(color, radius, shadow)

static func make_panel(color: Color = BG_CARD, radius: int = R_MEDIUM, shadow: bool = false) -> Panel:
	var p = Panel.new()
	p.add_theme_stylebox_override("panel", panel_style(color, radius, shadow))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p

static func make_panel_container(color: Color = BG_CARD, radius: int = R_MEDIUM, shadow: bool = false) -> PanelContainer:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(color, radius, shadow))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p

# ──────────────────────────────────────────────────────────────────────────────
#  Button helpers
# ──────────────────────────────────────────────────────────────────────────────
static var ScrollFriendlyButtonScript = preload("res://scripts/ui/ScrollFriendlyButton.gd")

static func apply_button(btn: Button, color: Color = ACCENT,
                         text_color: Color = Color.WHITE,
                         font_size: int = FS_BODY, radius: int = R_MEDIUM) -> void:
	btn.set_script(ScrollFriendlyButtonScript)
	var n = _flat(color, radius, true)
	n.border_width_bottom = 3
	n.border_color = color.darkened(0.30)
	var h = _flat(color.lightened(0.10), radius, true)
	h.border_width_bottom = 3
	h.border_color = color.darkened(0.25)
	var p = _flat(color.darkened(0.15), radius, false)
	p.content_margin_top = 2.0
	btn.add_theme_stylebox_override("normal",   n)
	btn.add_theme_stylebox_override("hover",    h)
	btn.add_theme_stylebox_override("pressed",  p)
	btn.add_theme_stylebox_override("disabled", _flat(Color(color, 0.45), radius, false))
	btn.add_theme_stylebox_override("focus",    StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color",          text_color)
	btn.add_theme_color_override("font_hover_color",    text_color)
	btn.add_theme_color_override("font_pressed_color",  text_color)
	btn.add_theme_color_override("font_disabled_color", Color(text_color, 0.45))
	btn.add_theme_font_size_override("font_size", font_size)

static func make_btn(text: String, color: Color = ACCENT,
                     font_size: int = FS_BODY, min_h: int = 68,
                     radius: int = R_MEDIUM) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size.y = min_h
	btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	apply_button(btn, color, Color.WHITE, font_size, radius)
	btn.pressed.connect(func(): Haptics.selection())
	return btn

static func make_icon_btn(icon: String, color: Color = BG_CARD2,
                          size: int = 60) -> Button:
	var btn = Button.new()
	btn.text = icon
	btn.custom_minimum_size = Vector2(size, size)
	btn.size_flags_horizontal  = Control.SIZE_SHRINK_CENTER
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	apply_button(btn, color, TEXT, FS_H3, R_SMALL)
	btn.pressed.connect(func(): Haptics.selection())
	return btn

# ──────────────────────────────────────────────────────────────────────────────
#  Label helpers
# ──────────────────────────────────────────────────────────────────────────────
static func make_label(text: String, font_size: int = FS_BODY,
                       color: Color = TEXT,
                       align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = align
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

static func make_back_btn(label: String = "< Back") -> Button:
	var btn = make_btn(label, BG_CARD2, FS_BODY, 52, R_SMALL)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.custom_minimum_size.x = 120
	return btn

# Hide a ScrollContainer's vertical scrollbar while keeping wheel/touch
# scrolling. The default bar is a hard grey rectangle that reads as unpolished
# on a phone; this makes it invisible without disabling the scroll itself.
static func hide_v_scrollbar(scroll: ScrollContainer) -> void:
	var bar = scroll.get_v_scroll_bar()
	if bar == null:
		return
	var empty = StyleBoxEmpty.new()
	for s in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(s, empty)
	bar.custom_minimum_size.x = 0

static func make_separator() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_color_override("color", BG_CARD2)
	sep.add_theme_constant_override("separation", 2)
	return sep

static func spacer(h: int = 20) -> Control:
	var c = Control.new()
	c.custom_minimum_size.y = h
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func make_pill_badge(text: String, bg_color: Color, text_color: Color = Color.WHITE,
							font_size: int = FS_CAPTION, h_pad: int = 14, v_pad: int = 6) -> PanelContainer:
	var pill = PanelContainer.new()
	var style = _flat(bg_color, 20)
	style.content_margin_left   = h_pad
	style.content_margin_right  = h_pad
	style.content_margin_top    = v_pad
	style.content_margin_bottom = v_pad
	pill.add_theme_stylebox_override("panel", style)
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", text_color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pill

# ──────────────────────────────────────────────────────────────────────────────
#  Card / panel wrappers
# ──────────────────────────────────────────────────────────────────────────────
static func make_card(content: Control, padding: int = 32,
                      color: Color = BG_CARD, radius: int = R_MEDIUM,
                      shadow: bool = true) -> Panel:
	var card = make_panel(color, radius, shadow)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left",   padding)
	m.add_theme_constant_override("margin_right",  padding)
	m.add_theme_constant_override("margin_top",    padding)
	m.add_theme_constant_override("margin_bottom", padding)
	card.add_child(m)
	m.add_child(content)
	return card

# ──────────────────────────────────────────────────────────────────────────────
#  Margin containers
# ──────────────────────────────────────────────────────────────────────────────
static func h_margin(control: Control, h: int = 20) -> MarginContainer:
	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left",  h)
	m.add_theme_constant_override("margin_right", h)
	m.add_child(control)
	return m

static func page_margin(control: Control) -> MarginContainer:
	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left",   24)
	m.add_theme_constant_override("margin_right",  24)
	m.add_theme_constant_override("margin_top",    24)
	m.add_theme_constant_override("margin_bottom", 24)
	m.add_child(control)
	return m

static func page_panel(max_width: int = 720, margin_size: int = 24) -> MarginContainer:
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   margin_size)
	margin.add_theme_constant_override("margin_right",  margin_size)
	margin.add_theme_constant_override("margin_top",    margin_size)
	margin.add_theme_constant_override("margin_bottom", margin_size)
	return margin

static func make_app_nav(active: String, wide: bool = false) -> Panel:
	var panel = make_panel(BG_CARD, 0)
	var bar = panel.get_theme_stylebox("panel").duplicate()
	if wide:
		bar.border_width_right = 1
	else:
		bar.border_width_top = 1
	bar.border_color = Color(1, 1, 1, 0.06)
	panel.add_theme_stylebox_override("panel", bar)
	if wide:
		panel.custom_minimum_size.x = 92
		panel.anchor_left = 0.0
		panel.anchor_right = 0.0
		panel.anchor_top = 0.0
		panel.anchor_bottom = 1.0
		panel.offset_left = 0.0
		panel.offset_right = 92.0
		panel.offset_top = 0.0
		panel.offset_bottom = 0.0
	else:
		panel.custom_minimum_size.y = 72 + safe_bottom()
		panel.anchor_left = 0.0
		panel.anchor_right = 1.0
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_left = 0.0
		panel.offset_right = 0.0
		panel.offset_top = -float(72 + safe_bottom())
		panel.offset_bottom = 0.0

	var m = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 12 + (safe_top() if wide else 0))
	m.add_theme_constant_override("margin_bottom", 12 + (0 if wide else safe_bottom()))
	panel.add_child(m)

	var box: BoxContainer = VBoxContainer.new() if wide else HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	m.add_child(box)

	# Players is deferred (it was meant for downloading other engines/NNUEs —
	# revisit later, likely from the difficulty screen). 3-tab nav for v1.
	var items = [
		{"id": "play", "label": "Play", "fn": GameManager.show_main_menu},
		{"id": "puzzles", "label": "Puzzles", "fn": GameManager.show_puzzles},
		{"id": "profile", "label": "Profile", "fn": GameManager.show_profile},
	]
	for item in items:
		var selected = item["id"] == active
		var btn = Button.new()
		btn.set_script(ScrollFriendlyButtonScript)
		btn.custom_minimum_size = Vector2(76, 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not wide else Control.SIZE_SHRINK_CENTER
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL if wide else Control.SIZE_SHRINK_CENTER
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.text = ""
		# Flat tab styling: no borders/shadows. The active tab gets a soft
		# accent pill; others are transparent with a faint hover.
		var empty := StyleBoxEmpty.new()
		btn.add_theme_stylebox_override("focus", empty)
		btn.add_theme_stylebox_override("pressed", empty)
		if selected:
			var pill = panel_style(Color(ACCENT, 0.16), R_MEDIUM)
			btn.add_theme_stylebox_override("normal", pill)
			btn.add_theme_stylebox_override("hover", pill)
		else:
			btn.add_theme_stylebox_override("normal", empty)
			btn.add_theme_stylebox_override("hover", panel_style(Color(TEXT, 0.05), R_MEDIUM))

		var btn_vbox = VBoxContainer.new()
		btn_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_vbox.add_theme_constant_override("separation", 3)
		btn_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(btn_vbox)

		var icon = NavIcon.new()
		icon.kind = item["id"]
		icon.icon_color = ACCENT if selected else TEXT_MUTED
		icon.custom_minimum_size = Vector2(26, 26)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn_vbox.add_child(icon)

		var text_lbl = make_label(item["label"], FS_CAPTION - 1, ACCENT if selected else TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_vbox.add_child(text_lbl)

		btn.pressed.connect(item["fn"])
		box.add_child(btn)

	return panel

# Custom-drawn tab-bar icons (clean vector shapes that render identically on
# every platform — the old ◈◆◉ glyphs looked cheap and risked not rendering).
class NavIcon extends Control:
	var kind: String = "play"
	var icon_color: Color = UITheme.TEXT_MUTED

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s = min(size.x, size.y)
		var o = (size - Vector2(s, s)) * 0.5
		match kind:
			"puzzles": _draw_puzzle(o, s)
			"profile": _draw_person(o, s)
			_: _draw_pawn(o, s)

	func _at(o: Vector2, s: float, x: float, y: float) -> Vector2:
		return o + Vector2(x, y) * s

	# Play -> a chess pawn
	func _draw_pawn(o: Vector2, s: float) -> void:
		draw_circle(_at(o, s, 0.5, 0.27), s * 0.155, icon_color)
		draw_colored_polygon(PackedVector2Array([
			_at(o, s, 0.41, 0.42), _at(o, s, 0.59, 0.42),
			_at(o, s, 0.68, 0.70), _at(o, s, 0.32, 0.70)]), icon_color)
		_round_rect(Rect2(_at(o, s, 0.26, 0.70), Vector2(s * 0.48, s * 0.13)), s * 0.03)

	# Puzzles -> a puzzle piece (body square + two tabs)
	func _draw_puzzle(o: Vector2, s: float) -> void:
		_round_rect(Rect2(_at(o, s, 0.27, 0.36), Vector2(s * 0.40, s * 0.38)), s * 0.04)
		draw_circle(_at(o, s, 0.47, 0.31), s * 0.115, icon_color)
		draw_circle(_at(o, s, 0.71, 0.52), s * 0.115, icon_color)

	# Profile -> head + shoulders
	func _draw_person(o: Vector2, s: float) -> void:
		draw_circle(_at(o, s, 0.5, 0.31), s * 0.155, icon_color)
		var pts := PackedVector2Array()
		for i in 19:
			var a = PI + PI * float(i) / 18.0
			pts.append(_at(o, s, 0.5 + cos(a) * 0.31, 0.92 + sin(a) * 0.34))
		draw_colored_polygon(pts, icon_color)

	func _round_rect(r: Rect2, radius: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = icon_color
		sb.corner_radius_top_left = int(radius)
		sb.corner_radius_top_right = int(radius)
		sb.corner_radius_bottom_left = int(radius)
		sb.corner_radius_bottom_right = int(radius)
		draw_style_box(sb, r)

static func make_bottom_nav(active: String) -> Panel:
	return make_app_nav(active, false)
