class_name GameModals
extends RefCounted
# Fullscreen overlay + centered modal card helpers for in-game dialogs
# (promotion picker, resign confirm, result overlay, review modals...).
# All functions take the hosting Control so they can be used from GameScreen
# and its component nodes alike.

static func make_overlay(host: Control, name_str: String) -> ColorRect:
	var ov = ColorRect.new()
	ov.color = Color(0, 0, 0, 0.70)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.name = name_str
	host.add_child(ov)
	return ov

static func show_modal_card(host: Control, name_str: String, content: Control, max_width: int = 460) -> void:
	var ov = make_overlay(host, name_str)
	add_centered_card(host, ov, content, max_width)

static func dismiss(host: Control, name_str: String) -> void:
	var ov = host.find_child(name_str, true, false)
	if ov: ov.queue_free()

static func add_centered_card(host: Control, overlay: Control, content: Control, max_width: int) -> void:
	var vp  = host.get_viewport_rect().size
	# Inner padding of the card. Kept modest because the base viewport is only
	# 430px wide — every extra pad point here plus the panels' own margins eat into
	# content width and can push wide content (the review table) off the right edge.
	var pad = 20

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size    = Vector2(0, 120)   # width comes from the card, not a fixed min
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	# The default grey scrollbar rectangle reads as unpolished on a phone modal;
	# hide it while keeping touch/wheel scrolling.
	UITheme.hide_v_scrollbar(scroll)

	var card = Panel.new()
	card.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.BG_CARD, UITheme.R_LARGE, true))
	var m = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, pad)
	card.add_child(m)
	m.add_child(scroll)

	# Anchor the card to the overlay's FULL WIDTH minus a side margin. Anchors are
	# RELATIVE (0=left edge .. 1=right edge of the full-rect overlay), so the card
	# physically cannot exceed the screen no matter what get_viewport_rect() reports
	# — the previous absolute-offset math overflowed off-screen when the reported
	# viewport width didn't match the render space. On wide screens (tablets) pull
	# the sides in so it doesn't stretch past a comfortable max_width.
	var side := 20.0
	if vp.x > float(max_width) + 40.0:
		side = (vp.x - float(max_width)) * 0.5
	# Center vertically within the SAFE area (below the notch, above the home
	# indicator), not the raw screen center — a tall card centered on the full
	# height sits visibly high because the top inset is smaller than the bottom.
	var safe_t: float = float(UITheme.safe_top())
	var safe_b: float = float(UITheme.safe_bottom())
	var center_y: float = safe_t + (float(vp.y) - safe_t - safe_b) * 0.5
	card.anchor_left  = 0.0; card.anchor_right  = 1.0
	card.anchor_top   = 0.0; card.anchor_bottom = 0.0
	card.offset_left  =  side
	card.offset_right = -side
	card.offset_top    = center_y - 80.0
	card.offset_bottom = center_y + 80.0
	overlay.add_child(card)

	# Give the content its true width BEFORE measuring. An autowrap Label reports a
	# huge minimum height until it knows how wide it will be (it assumes the
	# narrowest possible column and wraps into dozens of lines) — measuring before
	# that settles is what ballooned this card toward the 90% cap around just a
	# title and two buttons. Inner width = card width (viewport minus the side
	# margins) minus the MarginContainer padding on both sides.
	var inner_w: float = vp.x - side * 2.0 - float(pad) * 2.0
	content.custom_minimum_size.x = maxf(0.0, inner_w)

	# One frame to lay the content out at that width, a second for the re-wrapped
	# label's new minimum height to propagate back up to the VBox before we read it.
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if not is_instance_valid(scroll): return
	var natural_h = content.get_combined_minimum_size().y + pad * 2
	# Cap to the usable (safe) height so the card never runs under the notch or the
	# home indicator; taller content scrolls inside.
	var final_h   = clamp(natural_h, 160.0, (float(vp.y) - safe_t - safe_b) * 0.94)
	scroll.custom_minimum_size.y = max(120.0, final_h - pad * 2)
	card.offset_top    = center_y - final_h * 0.5
	card.offset_bottom = center_y + final_h * 0.5
