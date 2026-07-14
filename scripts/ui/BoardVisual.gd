class_name BoardVisual
extends Control

signal square_tapped(sq: int)
signal drag_move(from_sq: int, to_sq: int)

# ── Board themes ───────────────────────────────────────────────────────────────
const BOARD_THEMES = [
	{"name": "Classic",    "light": Color("#F0D9B5"), "dark": Color("#B58863"),
	 "sel": Color(0.25,0.62,1.0,0.42), "last": Color(0.95,0.78,0.18,0.34),
	 "coord_on_light": Color("#B58863"), "coord_on_dark": Color("#F0D9B5")},
	{"name": "Blue Sky",   "light": Color("#DEE3E6"), "dark": Color("#8CA2AD"),
	 "sel": Color(0.12,0.45,0.95,0.44), "last": Color(0.95,0.78,0.18,0.32),
	 "coord_on_light": Color("#8CA2AD"), "coord_on_dark": Color("#DEE3E6")},
	{"name": "Forest",     "light": Color("#FFFFDD"), "dark": Color("#6A8F4E"),
	 "sel": Color(0.12,0.45,0.95,0.42), "last": Color(0.95,0.78,0.18,0.34),
	 "coord_on_light": Color("#6A8F4E"), "coord_on_dark": Color("#FFFFDD")},
	{"name": "Night",      "light": Color("#707080"), "dark": Color("#2E2E40"),
	 "sel": Color(0.25,0.62,1.0,0.46), "last": Color(0.95,0.78,0.18,0.32),
	 "coord_on_light": Color("#2E2E40"), "coord_on_dark": Color("#707080")},
	{"name": "Tournament", "light": Color("#F0EEEC"), "dark": Color("#777788"),
	 "sel": Color(0.20,0.52,1.0,0.44), "last": Color(0.95,0.78,0.18,0.32),
	 "coord_on_light": Color("#777788"), "coord_on_dark": Color("#F0EEEC")},
]

# ── Piece themes ───────────────────────────────────────────────────────────────
# w/b fill colors, w/b outline colors
const PIECE_THEMES = [
	{"name": "Classic",  "w": Color("#F5EDD4"), "b": Color("#1A0E06"),
	 "wo": Color("#5E4C33"), "bo": Color("#E8D7B1")},
	{"name": "Ocean",    "w": Color("#E0EFFF"), "b": Color("#0A1A3A"),
	 "wo": Color("#2F5E81"), "bo": Color("#A9CCFF")},
	{"name": "Wood",     "w": Color("#F2D89C"), "b": Color("#3A2000"),
	 "wo": Color("#6D4819"), "bo": Color("#E7BF75")},
	{"name": "Marble",   "w": Color("#FFF8EA"), "b": Color("#26313A"),
	 "wo": Color("#77654B"), "bo": Color("#CCD7DE")},
	{"name": "Royal",    "w": Color("#F7EFD0"), "b": Color("#251347"),
	 "wo": Color("#7D6331"), "bo": Color("#D9C4FF")},
]

# All entries use FILLED glyphs so neither side appears hollow
const PIECE_STYLES = [
	{"name": "Modern",  "glyphs": {6:"♚", 5:"♛", 4:"♜", 3:"♝", 2:"♞", 1:"♟"}},
	{"name": "Classic", "glyphs": {6:"♔", 5:"♕", 4:"♖", 3:"♗", 2:"♘", 1:"♙"}},
	{"name": "Alpha",   "glyphs": {6:"K", 5:"Q", 4:"R", 3:"B", 2:"N", 1:"P"}},
]

# ── State ──────────────────────────────────────────────────────────────────────
var game_state                = null
var flipped: bool             = false
var player_color: int         = 1        # ChessLogic.WHITE; set by GameScreen

var selected_sq: int          = -1
var legal_targets: Array      = []
var last_move_from: int       = -1
var last_move_to: int         = -1
var check_sq: int             = -1
var hint_from: int            = -1
var hint_to: int              = -1
var hint_level: int           = 0
var hint_piece: int           = 0
var hint_alpha: float         = 1.0:   # game review fades the arrow out
	set(v):
		hint_alpha = v
		queue_redraw()
var _hint_fade_tween: Tween
var premove_from: int         = -1
var premove_to: int           = -1
var voice_coords_visible: bool = false
var ambiguity_sources: Array  = []
var ambiguity_target: int     = -1
var _ambiguity_until_ms: int  = 0

var _drag_from: int           = -1
var _press_sq: int            = -1
var _press_pos: Vector2       = Vector2.ZERO
var _drag_pos: Vector2        = Vector2.ZERO
var _drag_active: bool        = false
var _drag_targets: Array      = []  # legal targets shown during drag
var _drag_hover_sq: int       = -1
var _drag_is_touch: bool      = false
var _last_touch_ms: int       = -10000

var _sq_size: float           = 0.0
var _board_offset: Vector2    = Vector2.ZERO
var _font: SystemFont         # symbol font for piece glyphs
var _coord_font: SystemFont   # plain text font for a-h / 1-8 labels

var _board_theme_idx: int     = 0
var _piece_theme_idx: int     = 0
var _piece_style_idx: int     = 0
var _anim_active: bool        = false
var _anim_from: int           = -1
var _anim_to: int             = -1
var _anim_piece: int          = 0
var _anim_progress: float     = 1.0
var _anim_tween: Tween        = null
var _last_anim_key: String    = ""

# ──────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Segoe UI Symbol","Noto Sans Symbols2",
	                                       "Apple Symbols","DejaVu Sans",""])
	# Plain text font for board coordinates — the symbol font above has no
	# Latin letters/digits, which is why the a-h / 1-8 labels were invisible.
	_coord_font = SystemFont.new()
	_coord_font.font_names = PackedStringArray(["Helvetica Neue","Arial","DejaVu Sans",""])
	_coord_font.font_weight = 700
	_board_theme_idx = PlayerData.settings.get("board_theme", 0)
	_piece_theme_idx = PlayerData.settings.get("piece_theme", 0)
	_piece_style_idx = PlayerData.settings.get("piece_style", 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)

func _process(_delta: float) -> void:
	if _ambiguity_until_ms <= 0:
		set_process(false)
		return
	if Time.get_ticks_msec() >= _ambiguity_until_ms:
		ambiguity_sources = []
		ambiguity_target = -1
		_ambiguity_until_ms = 0
		set_process(false)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recalc()
		queue_redraw()

func _recalc() -> void:
	var bp     = min(size.x, size.y)
	if bp <= 0.0:
		_sq_size = 0.0
		_board_offset = Vector2.ZERO
		return
	_sq_size   = bp / 8.0
	_board_offset = Vector2((size.x - bp) * 0.5, (size.y - bp) * 0.5)

func btheme() -> Dictionary: return BOARD_THEMES[int(_board_theme_idx) % BOARD_THEMES.size()]
func ptheme() -> Dictionary: return PIECE_THEMES[int(_piece_theme_idx) % PIECE_THEMES.size()]

# ──────────────────────────────────────────────────────────────────────────────
#  Drawing
# ──────────────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if _sq_size == 0.0: _recalc()
	if _sq_size <= 0.0: return
	_draw_board_shadow()
	_draw_squares()
	_draw_highlights()
	_draw_premove()
	_draw_hints()
	_draw_pieces()
	_draw_voice_coords()
	_draw_coords()
	_draw_hint_arrow_overlay()
	_draw_drag_piece()
	_draw_anim_piece()

func _sq_rect(sq: int) -> Rect2:
	var f  = ChessLogic.file_of(sq)
	var r  = ChessLogic.rank_of(sq)
	var df = f if not flipped else (7 - f)
	var dr = (7 - r) if not flipped else r
	return Rect2(_board_offset + Vector2(df*_sq_size, dr*_sq_size), Vector2(_sq_size,_sq_size))

func _draw_board_shadow() -> void:
	# Multi-layer shadow for board frame depth
	var bp = _sq_size * 8.0
	var br = Rect2(_board_offset, Vector2(bp, bp))
	draw_rect(Rect2(br.position + Vector2(0,6), br.size), Color(0,0,0,0.20))
	draw_rect(Rect2(br.position + Vector2(0,3), br.size), Color(0,0,0,0.15))
	draw_rect(Rect2(br.position + Vector2(0,1), br.size), Color(0,0,0,0.08))

func _draw_squares() -> void:
	var th = btheme()
	for s in 64:
		var f = ChessLogic.file_of(s); var r = ChessLogic.rank_of(s)
		draw_rect(_sq_rect(s), th["light"] if (f+r)%2==0 else th["dark"])

func _draw_highlights() -> void:
	var th = btheme()
	# Last move
	for s in [last_move_from, last_move_to]:
		if s >= 0:
			var r = _sq_rect(s)
			draw_rect(r.grow(-_sq_size * 0.06), th["last"])
	# Check
	if check_sq >= 0: draw_rect(_sq_rect(check_sq), Color(0.85,0.05,0.05,0.55))
	# Tap selection
	if selected_sq >= 0: draw_rect(_sq_rect(selected_sq), th["sel"])
	elif _drag_from >= 0 and not _drag_active and not _drag_targets.is_empty():
		draw_rect(_sq_rect(_drag_from), th["sel"])

	# Legal targets for tap selection
	_draw_targets(legal_targets)
	_draw_ambiguity()

	# Drag targets (shown while dragging, independent of tap selection)
	if _drag_active:
		if _drag_hover_sq >= 0 and _drag_targets.has(_drag_hover_sq):
			draw_rect(_sq_rect(_drag_hover_sq), Color(0.10, 0.42, 1.0, 0.34))
		_draw_targets(_drag_targets)
	elif _drag_from >= 0 and not _drag_targets.is_empty():
		_draw_targets(_drag_targets)

func _draw_targets(targets: Array) -> void:
	var th = btheme()
	for t in targets:
		var rect = _sq_rect(t)
		var has_piece = game_state and (game_state.board[t] != 0 or t == game_state.ep_square)
		if has_piece:
			# Capture ring: bold ring around capturable pieces
			var b = _sq_size * 0.08
			var f = ChessLogic.file_of(t); var r = ChessLogic.rank_of(t)
			var is_light = (f+r)%2==0
			draw_rect(rect, Color(0.06,0.06,0.06,0.34))
			draw_rect(Rect2(rect.position+Vector2(b,b), rect.size-Vector2(b*2,b*2)),
			          th["light"] if is_light else th["dark"])
		else:
			draw_circle(rect.get_center(), _sq_size * 0.18, Color(0.04, 0.04, 0.04, 0.38))

func _draw_hints() -> void:
	if hint_level >= 1 and hint_from >= 0:
		draw_rect(_sq_rect(hint_from).grow(-_sq_size * 0.08), Color(0.49,0.67,0.30,0.22))
	if hint_level >= 1 and hint_to >= 0:
		draw_rect(_sq_rect(hint_to).grow(-_sq_size * 0.08), Color(0.49,0.67,0.30,0.30))

func _draw_premove() -> void:
	if premove_from < 0: return
	draw_rect(_sq_rect(premove_from), Color(0.90, 0.25, 0.18, 0.28))
	if premove_to >= 0:
		draw_rect(_sq_rect(premove_to), Color(0.90, 0.25, 0.18, 0.36))

func _draw_ambiguity() -> void:
	if ambiguity_sources.is_empty(): return
	var pulse = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.026)
	var source_color = Color(1.0, 0.76, 0.18, 0.30 + pulse * 0.18)
	var target_color = Color(0.20, 0.48, 1.0, 0.24 + pulse * 0.14)
	for sq in ambiguity_sources:
		draw_rect(_sq_rect(int(sq)).grow(-_sq_size * 0.07), source_color)
	if ambiguity_target >= 0:
		draw_rect(_sq_rect(ambiguity_target).grow(-_sq_size * 0.07), target_color)

func _draw_hint_arrow_overlay() -> void:
	if hint_level >= 1 and hint_to >= 0:
		_draw_hint_arrow()

func _draw_hint_arrow() -> void:
	if not game_state or hint_from < 0 or hint_to < 0: return
	var pts = _hint_arrow_points()
	if pts.size() < 2: return
	var tip = pts[pts.size() - 1]
	var dir = (tip - pts[pts.size() - 2]).normalized()
	if dir == Vector2.ZERO: return

	var w = max(7.0, _sq_size * 0.16)        # shaft thickness
	var head_len = w * 2.3
	var head_half = w * 1.45
	# The shaft stops at the base of the head so the two meet as one shape.
	var shaft = pts.duplicate()
	shaft[shaft.size() - 1] = tip - dir * head_len

	var fill = Color(0.49, 0.67, 0.30, 0.95 * hint_alpha)   # themed accent green
	var outline = Color(0.05, 0.08, 0.04, 0.32 * hint_alpha)
	if hint_alpha <= 0.01: return

	# Soft dark outline drawn first (slightly larger), then the fill on top —
	# gives a clean bordered arrow that reads on both light and dark squares.
	_stroke_arrow(shaft, tip, dir, w + 3.0, head_len + 2.2, head_half + 2.2, outline)
	_stroke_arrow(shaft, tip, dir, w, head_len, head_half, fill)

func _stroke_arrow(shaft: PackedVector2Array, tip: Vector2, dir: Vector2,
				   w: float, head_len: float, head_half: float, color: Color) -> void:
	if shaft.size() >= 2:
		draw_polyline(shaft, color, w, true)
		draw_circle(shaft[0], w * 0.5, color)          # rounded tail cap
		if shaft.size() >= 3:
			draw_circle(shaft[1], w * 0.5, color)      # rounded knight elbow
	var side = Vector2(-dir.y, dir.x)
	var base = tip - dir * head_len
	draw_colored_polygon(PackedVector2Array([
		tip, base + side * head_half, base - side * head_half]), color)

func _hint_arrow_points() -> PackedVector2Array:
	var from_center = _sq_rect(hint_from).get_center()
	var to_center = _sq_rect(hint_to).get_center()
	var points = PackedVector2Array()
	if _is_knight_hint():
		var dx = to_center.x - from_center.x
		var dy = to_center.y - from_center.y
		var corner = Vector2(to_center.x, from_center.y) if abs(dx) > abs(dy) else Vector2(from_center.x, to_center.y)
		points.append(from_center.lerp(corner, 0.20))
		points.append(corner)
		points.append(corner.lerp(to_center, 0.82))
		return points
	var start = from_center.lerp(to_center, 0.18)
	var finish = from_center.lerp(to_center, 0.84)
	points.append(start)
	points.append(finish)
	return points

func _is_knight_hint() -> bool:
	if not game_state or hint_from < 0 or hint_to < 0: return false
	var piece = hint_piece if hint_piece != 0 else game_state.board[hint_from]
	if abs(piece) != ChessLogic.KNIGHT: return false
	var df = abs(ChessLogic.file_of(hint_to) - ChessLogic.file_of(hint_from))
	var dr = abs(ChessLogic.rank_of(hint_to) - ChessLogic.rank_of(hint_from))
	return (df == 1 and dr == 2) or (df == 2 and dr == 1)

func _draw_pieces() -> void:
	if not game_state: return
	var fs = int(_sq_size * 0.84)
	for s in 64:
		if s == _drag_from and _drag_active: continue
		if _anim_active and s == _anim_to: continue
		var p = game_state.board[s]
		if p == 0: continue
		_draw_piece_at(s, p, fs)

func _draw_piece_at(sq: int, p: int, fs: int) -> void:
	var rect   = _sq_rect(sq)
	if ambiguity_sources.has(sq):
		var phase = float(Time.get_ticks_msec()) * 0.06 + float(sq)
		rect.position.x += sin(phase) * _sq_size * 0.035
	var center = rect.get_center()
	_draw_glyph(center, p, fs, rect)

func _draw_glyph(center: Vector2, p: int, fs: int, rect: Rect2) -> void:
	var style = PIECE_STYLES[int(_piece_style_idx) % PIECE_STYLES.size()]
	var glyph = style["glyphs"].get(abs(p), "")
	if glyph == "": return
	var pt  = ptheme()
	var w   = p > 0
	var fg  = pt["w"] if w else pt["b"]
	var outline = pt["wo"] if w else pt["bo"]

	# Glyph shadow
	var base = Vector2(rect.position.x, center.y + fs * 0.27)
	var shd  = Color(0,0,0,0.42) if w else Color(1,1,1,0.20)
	
	if _piece_style_idx == 1: # Classic (Outline) - maybe draw a faint circle behind for clarity
		draw_circle(center, fs * 0.45, Color(0,0,0,0.1) if w else Color(1,1,1,0.05))

	for off in [Vector2(-2,0), Vector2(2,0), Vector2(0,-2), Vector2(0,2)]:
		draw_string(_font, base + off, glyph, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs, outline)
	draw_string(_font, base + Vector2(2,3), glyph, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs, shd)
	draw_string(_font, base, glyph, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs, fg)

func _draw_drag_piece() -> void:
	if not _drag_active or _drag_from < 0 or not game_state: return
	var p = game_state.board[_drag_from]
	if p == 0: return
	var drag_size = _sq_size * (1.14 if _drag_is_touch else 1.02)
	var fs  = int(drag_size * 0.88)
	var draw_pos = _drag_pos - Vector2(0, _sq_size * 0.18) if _drag_is_touch else _drag_pos
	var sq_approx = Rect2(draw_pos - Vector2(drag_size*0.5, drag_size*0.5), Vector2(drag_size, drag_size))
	_draw_glyph(draw_pos, p, fs, sq_approx)

func _draw_anim_piece() -> void:
	if not _anim_active or _anim_piece == 0 or _anim_from < 0 or _anim_to < 0: return
	var fs = int(_sq_size * 0.82)
	var from_center = _sq_rect(_anim_from).get_center()
	var to_rect = _sq_rect(_anim_to)
	var center = from_center.lerp(to_rect.get_center(), _ease_out_cubic(_anim_progress))
	var rect = Rect2(center - Vector2(_sq_size * 0.5, _sq_size * 0.5), Vector2(_sq_size, _sq_size))
	_draw_glyph(center, _anim_piece, fs, rect)

func _ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - clamp(t, 0.0, 1.0), 3.0)

func _draw_coords() -> void:
	var th  = btheme()
	var fs  = int(_sq_size * 0.30)
	var pad = _sq_size * 0.07
	for i in 8:
		# Rank number on the left column. Contrast is computed from the actual
		# displayed square colour (dark square -> light ink, and vice-versa).
		# Rank number on the left column. The displayed square at row index `i`
		# is light when i is even (this board makes a1 a light square).
		var rank  = i if not flipped else (7 - i)
		var rect_r = Rect2(_board_offset + Vector2(0, (7 - i) * _sq_size), Vector2(_sq_size, _sq_size))
		var light_sq = i % 2 == 0
		draw_string(_coord_font, rect_r.position + Vector2(pad, fs + pad), str(rank + 1),
		            HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		            th["coord_on_light"] if light_sq else th["coord_on_dark"])
		# File letter on the bottom row (was inverted -> invisible, on the symbol font -> blank).
		var file  = i if not flipped else (7 - i)
		var rect_f = Rect2(_board_offset + Vector2(i * _sq_size, 7 * _sq_size), Vector2(_sq_size, _sq_size))
		draw_string(_coord_font, rect_f.position + Vector2(_sq_size - fs * 0.72 - pad, _sq_size - pad),
		            String.chr(97 + file), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		            th["coord_on_light"] if light_sq else th["coord_on_dark"])

func _draw_voice_coords() -> void:
	if not voice_coords_visible: return
	var th = btheme()
	var fs = int(_sq_size * 0.19)
	var pad = _sq_size * 0.06
	for sq in 64:
		var rect = _sq_rect(sq)
		var f = ChessLogic.file_of(sq)
		var r = ChessLogic.rank_of(sq)
		var is_light = (f + r) % 2 == 0
		var label = ChessLogic.sq_name(sq)
		var bg = Color(0.02, 0.03, 0.04, 0.18)
		var tag_size = Vector2(_sq_size * 0.34, _sq_size * 0.24)
		draw_rect(Rect2(rect.position + Vector2(pad, pad), tag_size), bg)
		draw_string(_coord_font, rect.position + Vector2(pad * 1.55, fs + pad * 1.35),
			label, HORIZONTAL_ALIGNMENT_LEFT, tag_size.x, fs,
			th["coord_on_light"] if is_light else th["coord_on_dark"])

# ──────────────────────────────────────────────────────────────────────────────
#  Input
# ──────────────────────────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_touch_ms = Time.get_ticks_msec()
		if event.pressed: _on_press(event.position, true)
		else:             _on_release(event.position)
	elif event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		_on_move(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_ms < 350: return
		if event.pressed: _on_press(event.position, false)
		else:             _on_release(event.position)
	elif event is InputEventMouseMotion and _drag_from >= 0:
		if Time.get_ticks_msec() - _last_touch_ms < 350: return
		_on_move(event.position)

func _on_press(pos: Vector2, is_touch: bool) -> void:
	var sq = _pos_to_sq(pos)
	if sq < 0: return
	_drag_from   = sq
	_press_sq    = sq
	_press_pos   = pos
	_drag_pos    = pos
	_drag_active = false
	_drag_targets = []
	_drag_hover_sq = -1
	_drag_is_touch = is_touch

	# Immediately calculate and show legal targets for drag feedback
	if game_state and sq >= 0:
		var p = game_state.board[sq]
		if p != 0 and ChessLogic.piece_color(p) == player_color:
			var legal = ChessLogic.get_legal_moves_from(game_state, sq)
			_drag_targets = legal.map(func(m): return m["to"])
			Haptics.selection()
	queue_redraw()

func _on_move(pos: Vector2) -> void:
	if _drag_from < 0: return
	_drag_pos = pos
	_drag_hover_sq = _pos_to_sq(pos)
	if not _drag_active and _press_pos.distance_to(pos) > _sq_size * 0.20:
		_drag_active = true
	queue_redraw()

func _on_release(pos: Vector2) -> void:
	var release_sq = _pos_to_sq(pos)
	_drag_targets = []
	_drag_hover_sq = -1
	if _drag_active and _drag_from >= 0 and release_sq >= 0 and release_sq != _drag_from:
		var from     = _drag_from
		_drag_from   = -1
		_press_sq    = -1
		_drag_active = false
		_drag_is_touch = false
		queue_redraw()
		drag_move.emit(from, release_sq)
	else:
		var tap_sq = _press_sq if _press_sq >= 0 else release_sq
		_drag_active = false
		_drag_from   = -1
		_press_sq    = -1
		_drag_is_touch = false
		queue_redraw()
		if tap_sq >= 0:
			square_tapped.emit(tap_sq)

func _pos_to_sq(local_pos: Vector2) -> int:
	var rel = local_pos - _board_offset
	if rel.x < 0 or rel.y < 0: return -1
	var df = int(rel.x / _sq_size); var dr = int(rel.y / _sq_size)
	if df > 7 or dr > 7: return -1
	var f = df if not flipped else (7-df)
	var r = (7-dr) if not flipped else dr
	return ChessLogic.sq(f, r)

# ──────────────────────────────────────────────────────────────────────────────
#  Public setters
# ──────────────────────────────────────────────────────────────────────────────
func set_state(state) -> void:
	var should_animate = false
	var moving_piece = 0
	if game_state and state and last_move_from >= 0 and last_move_to >= 0:
		var anim_key = str(last_move_from) + ":" + str(last_move_to) + ":" + str(state.fullmove) + ":" + str(state.turn)
		moving_piece = state.board[last_move_to]
		should_animate = moving_piece != 0 and anim_key != _last_anim_key
		if should_animate: _last_anim_key = anim_key
	game_state = state
	check_sq   = -1
	if state:
		var st = ChessLogic.get_status(state)
		if st["in_check"]:
			check_sq = ChessLogic.find_king(state.board, state.turn)
	if should_animate:
		_start_move_anim(last_move_from, last_move_to, moving_piece)
	queue_redraw()

func set_selection(sq: int, targets: Array) -> void:
	clear_ambiguity()
	selected_sq   = sq; legal_targets = targets; queue_redraw()

func clear_selection() -> void:
	clear_ambiguity()
	selected_sq = -1; legal_targets = []; voice_coords_visible = false; queue_redraw()

func set_last_move(from_sq: int, to_sq: int) -> void:
	last_move_from = from_sq; last_move_to = to_sq; queue_redraw()

func set_hint(from_sq: int, to_sq: int, level: int) -> void:
	if _hint_fade_tween and _hint_fade_tween.is_valid():
		_hint_fade_tween.kill()
	hint_alpha = 1.0
	hint_from = from_sq
	hint_to = to_sq
	hint_level = level
	hint_piece = game_state.board[from_sq] if game_state and from_sq >= 0 else 0
	queue_redraw()

# Hold the arrow briefly, then fade it out (used by the game review so the
# board isn't permanently cluttered with the suggested move).
func fade_hint(hold: float = 1.0, dur: float = 0.6) -> void:
	if not is_inside_tree(): return
	if _hint_fade_tween and _hint_fade_tween.is_valid():
		_hint_fade_tween.kill()
	hint_alpha = 1.0
	_hint_fade_tween = create_tween()
	_hint_fade_tween.tween_interval(hold)
	_hint_fade_tween.tween_property(self, "hint_alpha", 0.0, dur)

func clear_hint() -> void:
	if _hint_fade_tween and _hint_fade_tween.is_valid():
		_hint_fade_tween.kill()
	hint_alpha = 1.0
	hint_from=-1; hint_to=-1; hint_level=0; hint_piece=0; queue_redraw()

func set_ambiguity(candidates: Array) -> void:
	ambiguity_sources = []
	ambiguity_target = -1
	var seen = {}
	var common_target = -2
	for move in candidates:
		var from_sq = int(move.get("from", -1))
		var to_sq = int(move.get("to", -1))
		if from_sq >= 0 and not seen.has(from_sq):
			seen[from_sq] = true
			ambiguity_sources.append(from_sq)
		if common_target == -2:
			common_target = to_sq
		elif common_target != to_sq:
			common_target = -1
	ambiguity_target = common_target if common_target >= 0 else -1
	_ambiguity_until_ms = Time.get_ticks_msec() + 1200
	set_process(true)
	queue_redraw()

func clear_ambiguity() -> void:
	if ambiguity_sources.is_empty() and ambiguity_target < 0: return
	ambiguity_sources = []
	ambiguity_target = -1
	_ambiguity_until_ms = 0
	set_process(false)
	queue_redraw()

func set_premove(from_sq: int, to_sq: int = -1) -> void:
	premove_from = from_sq
	premove_to = to_sq
	queue_redraw()

func clear_premove() -> void:
	premove_from = -1
	premove_to = -1
	queue_redraw()

func flip_board() -> void:
	flipped = not flipped; queue_redraw()

func set_board_theme(idx: int) -> void: _board_theme_idx=idx; queue_redraw()
func set_piece_theme(idx: int) -> void: _piece_theme_idx=idx; queue_redraw()
func set_piece_style(idx: int) -> void: _piece_style_idx=idx; queue_redraw()
func set_voice_coords_visible(enabled: bool) -> void: voice_coords_visible = enabled; queue_redraw()

func _start_move_anim(from_sq: int, to_sq: int, piece: int) -> void:
	if _anim_tween: _anim_tween.kill()
	_anim_active = true
	_anim_from = from_sq
	_anim_to = to_sq
	_anim_piece = piece
	_anim_progress = 0.0
	_anim_tween = create_tween()
	_anim_tween.tween_method(func(v: float):
		_anim_progress = v
		queue_redraw(), 0.0, 1.0, 0.18)
	_anim_tween.finished.connect(func():
		_anim_active = false
		_anim_from = -1
		_anim_to = -1
		_anim_piece = 0
		queue_redraw())
