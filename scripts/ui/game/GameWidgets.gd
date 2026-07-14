class_name GameWidgets
extends RefCounted
# Custom-drawn widgets shared by the in-game HUD (GameHud) and the review
# overlay (GameReview): win-chance bar, accuracy ring, loading spinner.

class WinChanceBar extends Control:
	var right_pct: float = 50.0:
		set(v):
			right_pct = clamp(v, 0.0, 100.0)
			queue_redraw()
	var left_color: Color = UITheme.BG_CARD3:
		set(v):
			left_color = v
			queue_redraw()
	var right_color: Color = UITheme.ACCENT:
		set(v):
			right_color = v
			queue_redraw()
	var pulse: float = 0.0:
		set(v):
			pulse = v
			queue_redraw()

	var _pct_tween: Tween
	var _pulse_tween: Tween

	func set_target_pct(value: float, animated: bool = true) -> void:
		var target = clamp(value, 0.0, 100.0)
		if not animated or not is_inside_tree():
			right_pct = target
			pulse = 0.0
			return
		if _pct_tween != null and _pct_tween.is_valid():
			_pct_tween.kill()
		_pct_tween = create_tween()
		_pct_tween.tween_property(self, "right_pct", target, 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		if _pulse_tween != null and _pulse_tween.is_valid():
			_pulse_tween.kill()
		_pulse_tween = create_tween()
		_pulse_tween.tween_property(self, "pulse", 1.0, 0.18).from(0.0)
		_pulse_tween.tween_property(self, "pulse", 0.0, 0.34).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var bar_h = 10.0
		var y = 5.0
		var rect = Rect2(Vector2(0, y), Vector2(size.x, bar_h))
		var split_x = rect.position.x + rect.size.x * (1.0 - right_pct / 100.0)
		var left_rect = Rect2(rect.position, Vector2(max(0.0, split_x - rect.position.x), bar_h))
		var right_rect = Rect2(Vector2(split_x, y), Vector2(max(0.0, rect.end.x - split_x), bar_h))

		var bg = StyleBoxFlat.new()
		bg.bg_color = UITheme.BG_CARD3
		bg.corner_radius_top_left = 5
		bg.corner_radius_top_right = 5
		bg.corner_radius_bottom_left = 5
		bg.corner_radius_bottom_right = 5
		draw_style_box(bg, rect)
		if left_rect.size.x > 0.0:
			draw_rect(left_rect, left_color, true)
		if right_rect.size.x > 0.0:
			draw_rect(right_rect, right_color, true)
		draw_rect(rect, Color(UITheme.TEXT, 0.18), false, 1.0)

		var glow = Color(UITheme.GOLD, 0.20 + pulse * 0.34)
		draw_circle(Vector2(split_x, y + bar_h * 0.5), 8.0 + pulse * 5.0, glow)
		draw_line(Vector2(split_x, y - 2.0), Vector2(split_x, y + bar_h + 2.0), UITheme.GOLD, 2.0 + pulse * 1.2, true)

class AccuracyRing extends Control:
	var accuracy: int = 0
	var ring_color: Color = UITheme.ACCENT
	var draw_pct: float = 1.0:
		set(v):
			draw_pct = v
			queue_redraw()

	var _font: Font = SystemFont.new()

	func _draw() -> void:
		var center = size * 0.5
		var radius = min(size.x, size.y) * 0.5 - 4.0
		var bg_color = UITheme.BG_CARD3
		bg_color.a = 0.5

		# Background ring
		draw_arc(center, radius, 0, TAU, 64, bg_color, 5.0, true)

		# Foreground arc (animated via draw_pct)
		var sweep = (float(accuracy) / 100.0) * TAU * draw_pct
		if sweep > 0.01:
			draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + sweep, 64, ring_color, 5.0, true)

		# Center text — anchored on the true baseline so it sits dead-centre
		# in the ring (the old offset left it riding low).
		var fs = UITheme.FS_SMALL
		var text = "%d%%" % accuracy
		var tw = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var baseline_y = center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
		draw_string(_font, Vector2(center.x - tw * 0.5, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ring_color)

class ReviewSpinner extends Control:
	var phase: float = 0.0:
		set(v):
			phase = v
			queue_redraw()

	func _draw() -> void:
		var center = size * 0.5
		var radius = min(size.x, size.y) * 0.5 - 5.0
		draw_arc(center, radius, 0.0, TAU, 64, Color(UITheme.BG_CARD3, 0.65), 5.0, true)
		draw_arc(center, radius, phase, phase + TAU * 0.72, 64, UITheme.ACCENT_LT, 5.0, true)

# Animated voice waveform — vertical bars that react to the mic level while
# listening, idle/flat when off. Driven by GameVoice (sets level + listening).
class VoiceWaveIcon extends Control:
	var level: float = 0.0
	# Setter redraws on change: _process only animates WHILE listening, so
	# without this the icon froze on its last red frame when voice turned off —
	# making on and off look identical.
	var listening: bool = false:
		set(v):
			if listening != v:
				listening = v
				queue_redraw()
	var _t: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if listening:
			queue_redraw()

	func _draw() -> void:
		var n := 5
		var s = min(size.x, size.y)
		var gap = s * 0.10
		var bar_w = (s * 0.62 - gap * float(n - 1)) / float(n)
		var x0 = size.x * 0.5 - (bar_w * n + gap * (n - 1)) * 0.5
		var cy = size.y * 0.5
		var col = UITheme.RED_LT if listening else UITheme.TEXT_DIM
		# Heights per bar: a centred bell shape, animated by level + a little
		# per-bar wobble so it "dances" to the voice.
		var shape = [0.45, 0.75, 1.0, 0.75, 0.45]
		for i in n:
			var h: float
			if listening:
				var wob = 0.5 + 0.5 * sin(_t * 9.0 + float(i) * 1.3)
				var amp = clamp(0.18 + level * 4.0, 0.0, 1.0)
				h = s * (0.20 + shape[i] * (0.18 + amp * 0.52 * wob))
			else:
				h = s * (0.16 + shape[i] * 0.18)   # static idle bars
			var x = x0 + float(i) * (bar_w + gap)
			var r = Rect2(x, cy - h * 0.5, bar_w, h)
			var sb = StyleBoxFlat.new()
			sb.bg_color = col
			var rad = bar_w * 0.5
			sb.corner_radius_top_left = rad
			sb.corner_radius_top_right = rad
			sb.corner_radius_bottom_left = rad
			sb.corner_radius_bottom_right = rad
			draw_style_box(sb, r)

# Custom-drawn lightbulb for the Hint button (the 💡 emoji doesn't render on
# iOS). Dims when its host button is disabled.
class HintIcon extends Control:
	var host: Button = null   # dim the icon while a hint is loading/disabled
	var _font: Font = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_font = SystemFont.new()
		_font.font_weight = 700   # bold "?" reads clearly at button size
		set_process(true)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		# A simple, universally-recognised "?" for hints. Plain ASCII so it
		# renders in any system font (the old drawn bulb was fine too, but the
		# user wanted a question mark).
		var s = min(size.x, size.y)
		var c = size * 0.5
		var on = host == null or not host.disabled
		var col = UITheme.GOLD if on else UITheme.TEXT_MUTED
		var fs = int(s * 0.62)   # leave breathing room inside the button
		var tw = _font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var baseline = c.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
		draw_string(_font, Vector2(c.x - tw * 0.5, baseline), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
