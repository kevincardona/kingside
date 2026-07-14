class_name GameFormat
extends RefCounted
# Pure formatting and material-count helpers shared by GameScreen, GameHud
# and GameReview. Everything here is stateless.

static func piece_value(pt: int) -> int:
	match pt:
		ChessLogic.PAWN: return 1
		ChessLogic.KNIGHT: return 3
		ChessLogic.BISHOP: return 3
		ChessLogic.ROOK: return 5
		ChessLogic.QUEEN: return 9
	return 0

static func starting_piece_count(pt: int) -> int:
	match pt:
		ChessLogic.PAWN: return 8
		ChessLogic.KNIGHT: return 2
		ChessLogic.BISHOP: return 2
		ChessLogic.ROOK: return 2
		ChessLogic.QUEEN: return 1
	return 0

static func material_score_for_color(state, color: int) -> int:
	var score = 0
	for piece in state.board:
		if int(piece) == ChessLogic.EMPTY: continue
		if ChessLogic.piece_color(int(piece)) == color:
			score += piece_value(abs(int(piece)))
	return score

static func captured_piece_types_for_color(state, color: int) -> Array[int]:
	var target_color = -color
	var present = {}
	for pt in [ChessLogic.PAWN, ChessLogic.KNIGHT, ChessLogic.BISHOP, ChessLogic.ROOK, ChessLogic.QUEEN]:
		present[pt] = 0
	for piece in state.board:
		var p = int(piece)
		if p == ChessLogic.EMPTY or ChessLogic.piece_color(p) != target_color: continue
		var pt = abs(p)
		if present.has(pt):
			present[pt] += 1
	var captured: Array[int] = []
	for pt in [ChessLogic.QUEEN, ChessLogic.ROOK, ChessLogic.BISHOP, ChessLogic.KNIGHT, ChessLogic.PAWN]:
		var missing = maxi(0, starting_piece_count(pt) - int(present.get(pt, 0)))
		for i in missing:
			captured.append(pt)
	return captured

static func piece_glyph(pt: int) -> String:
	var piece_style_idx = int(PlayerData.settings.get("piece_style", 0))
	var pstyle = BoardVisual.PIECE_STYLES[piece_style_idx % BoardVisual.PIECE_STYLES.size()]
	return pstyle["glyphs"].get(pt, "?")

static func captured_text_for_color(state, color: int) -> String:
	var captured = captured_piece_types_for_color(state, color)
	if captured.is_empty():
		return "-"
	var text = ""
	for pt in captured:
		text += piece_glyph(int(pt))
	return text

static func material_delta_for_color(state, color: int) -> int:
	return material_score_for_color(state, color) - material_score_for_color(state, -color)

static func material_delta_text(delta: int) -> String:
	if delta == 0:
		return "even"
	return "+%d" % delta if delta > 0 else str(delta)

static func material_row_text(state, color: int) -> String:
	var captured = captured_text_for_color(state, color)
	var delta = material_delta_for_color(state, color)
	if captured == "-" and delta <= 0:
		return ""
	var suffix = "  +%d" % delta if delta > 0 else ""
	return "%s%s" % [captured if captured != "-" else "", suffix]

static func material_summary_text(state) -> String:
	var white_delta = material_delta_for_color(state, ChessLogic.WHITE)
	var white_caps = captured_text_for_color(state, ChessLogic.WHITE)
	var black_caps = captured_text_for_color(state, ChessLogic.BLACK)
	if white_delta == 0 and white_caps == "-" and black_caps == "-":
		return ""
	var leader = "Even"
	if white_delta > 0:
		leader = "White +%d" % white_delta
	elif white_delta < 0:
		leader = "Black +%d" % abs(white_delta)
	return "%s  ·  W %s  ·  B %s" % [
		leader,
		white_caps,
		black_caps]

static func win_percent_for_white(eval_cp_white: int) -> float:
	var cp = float(eval_cp_white)
	return 50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * cp)) - 1.0)

static func format_pct(value: float) -> String:
	if value >= 9.95:
		return "%d%%" % int(round(value))
	return "%.1f%%" % value

static func format_clock(seconds: float) -> String:
	var total = int(ceil(seconds))
	var mins = total / 60
	var secs = total % 60
	return "%d:%02d" % [mins, secs]

static func accuracy_color(pct: int) -> Color:
	if pct >= 80: return UITheme.ACCENT
	if pct >= 60: return UITheme.GOLD
	return UITheme.RED_LT

# ── Review move-quality buckets ──

static func review_bucket(tag: String) -> String:
	var t = tag.to_lower()
	if "blunder" in t: return "Blunder"
	if "mistake" in t: return "Mistake"
	if "inaccuracy" in t: return "Inaccuracy"
	if "slight" in t or "miss" in t: return "Slight"
	return "Best"

static func review_icon(tag: String) -> String:
	match review_bucket(tag):
		"Blunder": return "X"
		"Mistake": return "??"
		"Inaccuracy": return "?"
		"Slight": return "!"
		_: return "✓"

static func color_for_tag(tag: String) -> Color:
	match review_bucket(tag):
		"Blunder": return UITheme.RED_LT
		"Mistake": return UITheme.ORANGE
		"Inaccuracy": return UITheme.GOLD
		"Slight": return UITheme.ACCENT_LT
		_: return Color.TRANSPARENT
