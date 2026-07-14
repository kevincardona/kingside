extends Node2D

const BG_CARD2   = Color("#293128")
const ACCENT_DIM = Color("#5E7F3E")
const TEXT       = Color("#F0F1EC")
const BG_CARD    = Color("#1E241F")

func _draw() -> void:
	var w = 1024.0
	var origin = Vector2.ZERO
	var r = Rect2(origin + Vector2(w * 0.06, w * 0.06), Vector2(w * 0.88, w * 0.88))
	
	# Full-bleed: fill the WHOLE square with the board colour so iOS's rounded
	# (squircle) mask wraps it cleanly. Same exact design as the in-game logo —
	# only the framing changes (the old version drew a darker #111512 border
	# around an inset card, which read as an ugly frame under the icon mask).
	draw_rect(Rect2(0, 0, w, w), BG_CARD2)
	draw_rect(Rect2(r.position + Vector2(w * 0.08, w * 0.08), Vector2(w * 0.36, w * 0.36)), ACCENT_DIM)
	draw_rect(Rect2(r.position + Vector2(w * 0.44, w * 0.44), Vector2(w * 0.36, w * 0.36)), ACCENT_DIM)
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
	draw_colored_polygon(k_pts, TEXT)
	# Eye
	draw_circle(origin + Vector2(w * 0.52, w * 0.42), w * 0.025, BG_CARD)
	# Pedestal
	draw_rect(Rect2(origin + Vector2(w * 0.30, w * 0.82), Vector2(w * 0.40, w * 0.06)), TEXT)
