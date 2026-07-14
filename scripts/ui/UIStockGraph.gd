class_name UIStockGraph
extends Control

# Data and styling
var data: Array = []:
	set(v):
		data = v
		_hover_idx = -1
		queue_redraw()
var point_colors: Array[Color] = []:
	set(v):
		point_colors = v
		queue_redraw()
var color: Color = UITheme.ACCENT
var use_fill: bool = true
var use_smooth_curves: bool = true
var use_center_line: bool = false
var use_territory_fill: bool = false  # White/black territory shading
var min_value: float = 0.0
var max_value: float = 100.0
var auto_range: bool = true
var label_format: String = "%d"
var show_y_labels: bool = true
var y_label_width: float = 40.0
var x_padding: float = 20.0
var y_padding: float = 20.0

var highlight_idx: int = -1:
	set(v):
		highlight_idx = v
		queue_redraw()

var _hover_idx: int = -1
var _font: Font = SystemFont.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process_input(true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		_update_hover(event.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_idx = -1
		queue_redraw()

func _update_hover(pos: Vector2) -> void:
	if data.size() < 2: return
	var w = size.x - y_label_width - x_padding * 2
	var idx = int(round(clamp((pos.x - y_label_width - x_padding) / w, 0.0, 1.0) * float(data.size() - 1)))
	if idx != _hover_idx:
		_hover_idx = idx
		queue_redraw()

func _draw() -> void:
	if data.size() < 2:
		draw_string(_font, size * 0.5, "Not enough data", HORIZONTAL_ALIGNMENT_CENTER, -1, UITheme.FS_SMALL, UITheme.TEXT_MUTED)
		return

	var actual_min = min_value
	var actual_max = max_value
	if auto_range:
		actual_min = data.min()
		actual_max = data.max()
		# Add some padding to the range
		var range_diff = actual_max - actual_min
		if range_diff == 0: range_diff = 1.0
		actual_min -= range_diff * 0.1
		actual_max += range_diff * 0.1

	if use_center_line:
		var abs_max = max(abs(actual_min), abs(actual_max))
		actual_min = -abs_max
		actual_max = abs_max

	var w = size.x - y_label_width - x_padding * 2
	var h = size.y - y_padding * 2
	var rect_w = w
	var rect_h = h
	var origin_x = y_label_width + x_padding
	var origin_y = y_padding

	# Draw background grid/lines
	var grid_color = UITheme.BG_CARD3
	grid_color.a = 0.3
	
	# Horizontal lines (Y axis)
	var steps = 4
	for i in range(steps + 1):
		var y = origin_y + h - (float(i) / steps) * h
		draw_line(Vector2(origin_x, y), Vector2(origin_x + w, y), grid_color, 1.0)
		if show_y_labels:
			var val = actual_min + (float(i) / steps) * (actual_max - actual_min)
			draw_string(_font, Vector2(5, y + 5), label_format % val, HORIZONTAL_ALIGNMENT_LEFT, y_label_width, UITheme.FS_CAPTION, UITheme.TEXT_MUTED)

	var y_zero_line = origin_y + h * 0.5
	if use_center_line:
		y_zero_line = origin_y + h * (actual_max / (actual_max - actual_min))
		# Territory background fill — white advantage above, black below
		if use_territory_fill:
			var white_rect = Rect2(origin_x, origin_y, w, y_zero_line - origin_y)
			var black_rect = Rect2(origin_x, y_zero_line, w, origin_y + h - y_zero_line)
			draw_rect(white_rect, Color(1.0, 1.0, 1.0, 0.04), true)
			draw_rect(black_rect, Color(0.0, 0.0, 0.0, 0.12), true)
		draw_line(Vector2(origin_x, y_zero_line), Vector2(origin_x + w, y_zero_line), Color(UITheme.TEXT_MUTED, 0.6), 1.0)

	# Calculate points
	var raw_pts = PackedVector2Array()
	for i in data.size():
		var x = origin_x + (float(i) / float(data.size() - 1)) * w
		var val = clamp(data[i], actual_min, actual_max)
		var y = origin_y + h - ((val - actual_min) / (actual_max - actual_min)) * h
		raw_pts.append(Vector2(x, y))

	var pts = raw_pts
	if use_smooth_curves and data.size() > 2:
		var curve = Curve2D.new()
		for p in raw_pts:
			curve.add_point(p)
		# Tweak curvature
		for i in curve.point_count:
			var prev = curve.get_point_position(max(0, i - 1))
			var next = curve.get_point_position(min(curve.point_count - 1, i + 1))
			var dist = (next - prev).length()
			curve.set_point_in(i, Vector2(-dist * 0.25, 0))
			curve.set_point_out(i, Vector2(dist * 0.25, 0))
		pts = curve.tessellate(5)

	# Draw fill
	if use_fill:
		var fill_pts = pts.duplicate()
		var y_base = origin_y + h
		if use_center_line:
			y_base = y_zero_line
		
		fill_pts.append(Vector2(pts[-1].x, y_base))
		fill_pts.append(Vector2(pts[0].x, y_base))
		
		var fill_color = color
		fill_color.a = 0.15
		draw_polygon(fill_pts, [fill_color])

	# Draw line
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i+1], color, 2.5, true)

	# Only mark notable moves (blunders / mistakes / brilliancies). A dot at
	# every ply overlapped into noise — the line itself carries the rest.
	if data.size() < 150:
		for i in raw_pts.size():
			if i < point_colors.size() and point_colors[i] != Color.TRANSPARENT:
				var p = raw_pts[i]
				var p_col = point_colors[i]
				draw_circle(p, 5.0, p_col)
				draw_circle(p, 6.5, Color(p_col, 0.3))

	# Draw highlight
	if highlight_idx >= 0 and highlight_idx < raw_pts.size():
		var p = raw_pts[highlight_idx]
		draw_line(Vector2(p.x, origin_y), Vector2(p.x, origin_y + h), Color(UITheme.ACCENT_LT, 0.4), 1.5)
		draw_circle(p, 6.0, UITheme.ACCENT_LT)
		draw_circle(p, 8.0, Color(UITheme.ACCENT_LT, 0.3))

	# Draw hover
	if _hover_idx >= 0 and _hover_idx < raw_pts.size():
		var p = raw_pts[_hover_idx]
		draw_line(Vector2(p.x, origin_y), Vector2(p.x, origin_y + h), Color(UITheme.TEXT, 0.3), 1.0)
		draw_circle(p, 5.0, UITheme.GOLD)
		
		var val = data[_hover_idx]
		var sign_str = "+" if val >= 0 else ""
		var val_str = label_format % val
		var tip_text = "Move %d: %s%s" % [_hover_idx, sign_str, val_str]
		var tip_size = _font.get_string_size(tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_CAPTION)
		var tip_rect = Rect2(p.x - tip_size.x * 0.5 - 10, origin_y - 35, tip_size.x + 20, 25)
		
		# Keep tooltip inside bounds
		if tip_rect.position.x < 0: tip_rect.position.x = 5
		if tip_rect.end.x > size.x: tip_rect.position.x = size.x - tip_rect.size.x - 5
		
		# Rounded tooltip background
		var tip_style = StyleBoxFlat.new()
		tip_style.bg_color = UITheme.BG_CARD2
		tip_style.corner_radius_top_left = 4
		tip_style.corner_radius_top_right = 4
		tip_style.corner_radius_bottom_left = 4
		tip_style.corner_radius_bottom_right = 4
		draw_style_box(tip_style, tip_rect)
		draw_string(_font, tip_rect.position + Vector2(10, 18), tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_CAPTION, UITheme.TEXT)
