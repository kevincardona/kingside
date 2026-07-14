class_name FlameIcon
extends Control
# A small custom-drawn flame (gold/orange, on-theme) with a gentle flicker.
# Used for the days-played streak badge. Scales to min(size.x, size.y).

# Normalized flame silhouettes (tip up, y-down) in a 0..1 box. The outer
# outline has a pinched "waist" near the top then bulges out — the classic
# flame look (concave, so it's drawn triangulated).
const OUTER := [
	Vector2(0.50, 0.00),  # sharp tip
	Vector2(0.61, 0.17),
	Vector2(0.55, 0.31),  # waist in
	Vector2(0.76, 0.52),  # bulge out
	Vector2(0.73, 0.76),
	Vector2(0.50, 0.97),  # rounded base
	Vector2(0.27, 0.76),
	Vector2(0.24, 0.52),  # bulge out (left)
	Vector2(0.45, 0.31),  # waist in (left)
	Vector2(0.39, 0.17),
]
const INNER := [
	Vector2(0.50, 0.36),
	Vector2(0.63, 0.58),
	Vector2(0.57, 0.78),
	Vector2(0.50, 0.86),
	Vector2(0.43, 0.78),
	Vector2(0.37, 0.58),
]

var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var s = min(size.x, size.y)
	if s <= 0.0:
		return
	var o = (size - Vector2(s, s)) * 0.5

	# Flicker: gentle vertical breathing of the tip + brightness pulse.
	var flick = sin(_t * 7.3) * 0.5 + sin(_t * 11.7) * 0.5   # -1..1, irregular
	var tip_lift = flick * 0.025
	var glow = 0.5 + 0.5 * (sin(_t * 9.1) * 0.5 + 0.5)

	# Soft outer glow
	draw_circle(o + Vector2(0.5, 0.62) * s, s * (0.46 + glow * 0.04),
		Color(UITheme.ORANGE, 0.10))

	_flame(OUTER, o, s, tip_lift, UITheme.ORANGE)
	_flame(INNER, o, s, tip_lift * 0.6, UITheme.GOLD)
	# Bright molten core
	draw_circle(o + Vector2(0.5, 0.70) * s, s * (0.11 + glow * 0.015),
		Color(1.0, 0.93, 0.66, 0.92))

func _flame(pts: Array, o: Vector2, s: float, tip_lift: float, col: Color) -> void:
	var p = PackedVector2Array()
	for v in pts:
		# Lift points more the closer they are to the tip (y small) for flicker.
		var lift = tip_lift * (1.0 - v.y)
		p.append(o + Vector2(v.x, v.y - lift) * s)
	# Triangulate so concave flame outlines render correctly.
	var idx = Geometry2D.triangulate_polygon(p)
	if idx.size() < 3:
		draw_colored_polygon(p, col)
		return
	for i in range(0, idx.size(), 3):
		draw_colored_polygon(PackedVector2Array([p[idx[i]], p[idx[i + 1]], p[idx[i + 2]]]), col)
