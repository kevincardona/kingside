extends Node
# AIEngine – dispatches move requests to a backend that can run on every platform.
#
# Backends (preferred order):
#   1. NativeBackend  – a Stockfish instance compiled into the app via GDExtension.
#                       Works on iOS / Android / macOS / Windows / Linux.
#   2. ScriptBackend  – a pure GDScript alpha-beta searcher that runs on any
#                       platform (including HTML5). Slower but always available.
#
# Public API (callers must not depend on the backend):
#   request_move(state, difficulty)
#   request_hint(state)
#   request_review(records, player_color)
#   quick_hint(state) -> Dictionary
#   stockfish_available() -> bool        # true when NativeBackend is healthy
#   can_play_rated(name) -> bool         # true when a rated game can use Stockfish
#   get_difficulty_elo(name) -> int
#   get_difficulty_label(name) -> String
#   backend_name() -> String             # "native" | "script"

signal move_ready(move: Dictionary)
signal hint_ready(move: Dictionary)
signal review_ready(result: Dictionary)

# Strength model:
#  - native_elo >= 1320  → Stockfish UCI_LimitStrength + UCI_Elo (its real
#    calibrated rating model; 1320 is the engine's floor).
#  - native_elo  < 1320  → Skill Level 0-5 (Stockfish's intentional-mistake
#    model). On its own Skill Level 0 still plays ~1100-1300, far above the
#    label, so the low tiers ALSO get `blunder`: a per-move chance to play a
#    deliberately weak (but not random) move, which is what actually drags the
#    effective strength down to the labelled number. See _apply_human_blunder.
#
# Calibration note: these Elo numbers are TARGET PLAYING STRENGTHS, not raw
# Stockfish UCI_Elo (which runs well above chess.com). With the blunder layer a
# "600" hangs material like a real ~600, so the player's own rating — earned
# against these honest labels — tracks roughly to chess.com's lower/mid bands.
# Exact cross-site calibration still wants real-game playtesting; the `blunder`
# rates below are the single knob to tune per tier.
const DIFFICULTIES = {
	"beginner": {"label": "Beginner", "elo":  500, "movetime_ms":  120, "script_depth": 1, "loss_cp": 900, "prefer_native": true, "native_elo":  500,  "blunder": 0.45},
	"easy":     {"label": "Easy",     "elo":  800, "movetime_ms":  160, "script_depth": 2, "loss_cp": 520, "prefer_native": true, "native_elo":  800,  "blunder": 0.28},
	"medium":   {"label": "Medium",   "elo": 1200, "movetime_ms":  250, "script_depth": 3, "loss_cp": 220, "prefer_native": true, "native_elo": 1200, "blunder": 0.12},
	"hard":     {"label": "Hard",     "elo": 1600, "movetime_ms":  350, "script_depth": 4, "loss_cp":  80, "prefer_native": true, "native_elo": 1600, "blunder": 0.04},
	"expert":   {"label": "Expert",   "elo": 2000, "movetime_ms":  500, "script_depth": 5, "loss_cp":  25, "prefer_native": true, "native_elo": 2000},
	"master":   {"label": "Master",   "elo": 2500, "movetime_ms":  800, "script_depth": 6, "loss_cp":   0, "prefer_native": true, "native_elo": 2500},
	"stockfish_max": {"label": "Max Stockfish", "elo": 3200, "movetime_ms": 3000, "script_depth": 6, "loss_cp": 0, "use_book": false, "prefer_native": true, "native_elo": 3200, "mobile_movetime_ms": 1500},
}

# Hints and review always use FULL engine strength — advice must come from the
# strongest model available, not the current opponent's handicapped one.
const HINT_CONFIG  = {"movetime_ms": 600, "script_depth": 4, "loss_cp": 0, "native_elo": 3200, "use_book": false}
const REVIEW_DEPTH = 6
const REVIEW_MOVETIME_MS = 300
# Game review aims for accurate centipawn loss without hanging on long games:
# every position (best move AND played move) is searched with the SAME per-move
# budget, and that budget scales so the whole review stays under a total cap.
const REVIEW_TOTAL_BUDGET_MS = 14000
const REVIEW_MIN_MOVETIME_MS = 220
const REVIEW_MAX_MOVETIME_MS = 900

const OPENING_BOOK = {
	"start": ["e2e4", "d2d4", "g1f3", "c2c4"],
	"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -": ["c7c5", "e7e5", "e7e6", "c7c6"],
	"rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq -": ["g8f6", "d7d5", "e7e6"],
	"rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq -": ["d7d5", "g8f6", "c7c5"],
	"rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq -": ["g8f6", "e7e5", "c7c5"],
}

# Move + material values (centipawns). King is irrelevant.
const MAT = {1: 100, 2: 320, 3: 330, 4: 500, 5: 900, 6: 0}
const PIECE_GLYPH = {1:"♙", 2:"♘", 3:"♗", 4:"♖", 5:"♕", 6:"♔"}

const PST_PAWN = [
	  0,  0,  0,  0,  0,  0,  0,  0,
	  5, 10, 10,-20,-20, 10, 10,  5,
	  5, -5,-10,  0,  0,-10, -5,  5,
	  0,  0,  0, 20, 20,  0,  0,  0,
	  5,  5, 10, 25, 25, 10,  5,  5,
	 10, 10, 20, 30, 30, 20, 10, 10,
	 50, 50, 50, 50, 50, 50, 50, 50,
	  0,  0,  0,  0,  0,  0,  0,  0,
]
const PST_KNIGHT = [
	-50,-40,-30,-30,-30,-30,-40,-50,
	-40,-20,  0,  0,  0,  0,-20,-40,
	-30,  0, 10, 15, 15, 10,  0,-30,
	-30,  5, 15, 20, 20, 15,  5,-30,
	-30,  0, 15, 20, 20, 15,  0,-30,
	-30,  5, 10, 15, 15, 10,  5,-30,
	-40,-20,  0,  5,  5,  0,-20,-40,
	-50,-40,-30,-30,-30,-30,-40,-50,
]
const PST_BISHOP = [
	-20,-10,-10,-10,-10,-10,-10,-20,
	-10,  0,  0,  0,  0,  0,  0,-10,
	-10,  0,  5, 10, 10,  5,  0,-10,
	-10,  5,  5, 10, 10,  5,  5,-10,
	-10,  0, 10, 10, 10, 10,  0,-10,
	-10, 10, 10, 10, 10, 10, 10,-10,
	-10,  5,  0,  0,  0,  0,  5,-10,
	-20,-10,-10,-10,-10,-10,-10,-20,
]
const PST_ROOK = [
	  0,  0,  0,  0,  0,  0,  0,  0,
	  5, 10, 10, 10, 10, 10, 10,  5,
	 -5,  0,  0,  0,  0,  0,  0, -5,
	 -5,  0,  0,  0,  0,  0,  0, -5,
	 -5,  0,  0,  0,  0,  0,  0, -5,
	 -5,  0,  0,  0,  0,  0,  0, -5,
	 -5,  0,  0,  0,  0,  0,  0, -5,
	  0,  0,  0,  5,  5,  0,  0,  0,
]
const PST_QUEEN = [
	-20,-10,-10, -5, -5,-10,-10,-20,
	-10,  0,  0,  0,  0,  0,  0,-10,
	-10,  0,  5,  5,  5,  5,  0,-10,
	 -5,  0,  5,  5,  5,  5,  0, -5,
	  0,  0,  5,  5,  5,  5,  0, -5,
	-10,  5,  5,  5,  5,  5,  0,-10,
	-10,  0,  5,  0,  0,  0,  0,-10,
	-20,-10,-10, -5, -5,-10,-10,-20,
]
const PST_KING = [
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-20,-30,-30,-40,-40,-30,-30,-20,
	-10,-20,-20,-20,-20,-20,-20,-10,
	 20, 20,  0,  0,  0,  0, 20, 20,
	 20, 30, 10,  0,  0, 10, 30, 20,
]

var _move_thread: Thread        = null
var _hint_thread: Thread        = null
var _review_thread: Thread      = null

# Backend is selected on _ready and stays for the lifetime of the autoload.
var _backend: AIEngineBackend = null

# ──────────────────────────────────────────────
#  Lifecycle
# ──────────────────────────────────────────────
# Active engine profile (from EngineRegistry) mirrored onto the native backend.
# Re-applied only when the selection changes, so per-move overhead stays zero.
var _applied_engine_id: String = ""
var _applied_net_path: String = ""

# Per-move review search budget (ms), recomputed at the start of each review_game
# from the game length so best-vs-played evals are compared at equal depth.
var _review_movetime_ms: int = REVIEW_MOVETIME_MS

func _ready() -> void:
	_backend = _pick_backend()
	print("AIEngine: using ", _backend.name(), " backend")
	_dump_engine_status()
	_configure_native_performance()

# Persist which backend loaded to user://engine_status.json at startup. On iOS
# neither stdout nor Godot's file logger is reachable from the host, so this small
# file — pullable via `devicectl device copy from` — is the ground truth for
# whether native Stockfish actually loaded on a real device.
func _dump_engine_status() -> void:
	var f = FileAccess.open("user://engine_status.json", FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({
		"backend": _backend.name() if _backend != null else "none",
		"native_ready": is_native_ready(),
		"os": OS.get_name(),
		"written_at": Time.get_datetime_string_from_system(),
	}))
	f.close()

# One-time engine performance setup. Threads/Hash scale with the device so
# searches finish well inside their movetime budget.
func _configure_native_performance() -> void:
	if _backend == null or _backend.name() != "native": return
	if not _backend.has_method("set_option"): return
	var mobile = OS.get_name() in ["iOS", "Android"]
	var threads = 2 if mobile else clampi(OS.get_processor_count() / 2, 1, 4)
	_backend.set_option("Threads", str(threads))
	# 64MB is plenty for these short-movetime casual bots; keeps the app's memory
	# footprint modest (mobile stays at 32MB).
	_backend.set_option("Hash", "32" if mobile else "64")
	print("AIEngine: native engine configured — threads=", threads, " hash=", "32MB" if mobile else "64MB")

func _pick_backend() -> AIEngineBackend:
	var native = AINativeBackend.new()
	if native.prepare() and native.start():
		return native
	native.shutdown()
	# The native Stockfish library is compiled into the iOS / Android / macOS /
	# Windows builds, so a fallback here means the GDExtension failed to load and
	# play is running on the much weaker GDScript searcher. Surface it loudly
	# (push_warning shows in the editor + device logs) so it never goes unnoticed.
	push_warning("AIEngine: native Stockfish unavailable on %s — falling back to the GDScript engine" % OS.get_name())
	var sb = AIScriptBackend.new()
	sb.start()
	return sb

func backend_name() -> String:
	return _backend.name() if _backend else "none"

# Contract accessor: which engine is actually answering moves/reviews right now
# ("native" = real Stockfish, "script" = GDScript fallback, "none" = unset).
func active_engine_source() -> String:
	return backend_name()

# True when the real Stockfish (native GDExtension) is loaded and healthy. UI can
# read this to badge games as genuine Stockfish; defaults safely if unavailable.
func is_native_ready() -> bool:
	return stockfish_available()

func stockfish_available() -> bool:
	return _backend != null and _backend.name() == "native" and _backend.is_available()

func can_play_rated(_difficulty: String = "") -> bool:
	return stockfish_available()

# ──────────────────────────────────────────────
#  Public API
# ──────────────────────────────────────────────
func request_move(state, difficulty: String) -> void:
	if _move_thread and _move_thread.is_started(): return
	var cfg: Dictionary
	if difficulty == "custom":
		var r = GameManager.custom_rating
		cfg = {"label": "Custom", "elo": r,
				"movetime_ms": _movetime_for(r),
				"script_depth": _depth_for(r),
				"loss_cp": _loss_cp_for(r),
				"prefer_native": true,
				# Mirror the fixed-difficulty strength model. Ratings below the
				# UCI_Elo floor (1320) MUST use the Skill-Level + blunder path —
				# clamping them up to 1320 (the old behaviour) made a "custom 600"
				# play like ~1700. The blunder rate is what drags it back down.
				"native_elo": r,
				"blunder": _blunder_for(r)}
	else:
		cfg = DIFFICULTIES.get(difficulty, DIFFICULTIES["medium"]).duplicate()
	cfg["allow_script_fallback"] = GameManager.allow_unrated_fallback or not GameManager.current_game_rated
	_move_thread = Thread.new()
	_move_thread.start(_thread_move.bind(state.copy(), cfg))

func request_hint(state) -> void:
	if _hint_thread and _hint_thread.is_started(): return
	_hint_thread = Thread.new()
	_hint_thread.start(_thread_hint.bind(state.copy()))

func request_review(records: Array, player_color: int) -> void:
	if _review_thread and _review_thread.is_started(): return
	_review_thread = Thread.new()
	_review_thread.start(_thread_review.bind(records, player_color))

func get_difficulty_elo(difficulty: String) -> int:
	if difficulty == "custom":
		return GameManager.custom_rating
	return DIFFICULTIES.get(difficulty, DIFFICULTIES["medium"])["elo"]

func get_difficulty_label(difficulty: String) -> String:
	if difficulty == "custom":
		return "Custom"
	return DIFFICULTIES.get(difficulty, DIFFICULTIES["medium"])["label"]

func quick_hint(state) -> Dictionary:
	# A fast move for the in-game "💡" button while the deeper search runs.
	var legal = ChessLogic.get_legal_moves(state)
	if legal.is_empty(): return {}
	return _script_quick_hint(state, legal)

func estimate_eval_cp(state) -> int:
	return _evaluate(state)

# ──────────────────────────────────────────────
#  Thread workers
# ──────────────────────────────────────────────
func _thread_move(state, cfg: Dictionary) -> void:
	var move = _pick_move(state, cfg)
	call_deferred("_emit_move", move)

func _thread_hint(state) -> void:
	var move = _pick_move(state, HINT_CONFIG)
	call_deferred("_emit_hint", move)

func _thread_review(records: Array, player_color: int) -> void:
	var result = review_game(records, player_color)
	call_deferred("_emit_review", result)

func _emit_move(move: Dictionary) -> void:
	if _move_thread:
		_move_thread.wait_to_finish()
		_move_thread = null
	move_ready.emit(move)

func _emit_hint(move: Dictionary) -> void:
	if _hint_thread:
		_hint_thread.wait_to_finish()
		_hint_thread = null
	hint_ready.emit(move)

func _emit_review(result: Dictionary) -> void:
	if _review_thread:
		_review_thread.wait_to_finish()
		_review_thread = null
	review_ready.emit(result)

# ──────────────────────────────────────────────
#  Move selection
# ──────────────────────────────────────────────
func _pick_move(state, cfg: Dictionary) -> Dictionary:
	var legal = ChessLogic.get_legal_moves(state)
	if legal.is_empty(): return {}

	# 1. Try the opening book, except for Max Stockfish where every move should
	# come from the engine when the native backend is available.
	if bool(cfg.get("use_book", true)):
		var book = _book_move(state)
		if not book.is_empty(): return book

	# 2. If the native backend is up and this rating should use it, ask
	# Stockfish with explicit strength settings.
	if _backend.name() == "native" and bool(cfg.get("prefer_native", true)):
		if _configure_native_strength(cfg):
			var mt = _platform_movetime(int(cfg.get("movetime_ms", 500)), cfg)
			var uci = _backend.bestmove(ChessLogic.state_to_fen(state), mt)
			if uci != "" and uci != "(none)":
				var native_move = ChessLogic.uci_to_move(state, uci)
				if not native_move.is_empty():
					# Skill Level alone leaves the low tiers too strong; mix in
					# occasional human-like errors to hit the labelled strength.
					return _apply_human_blunder(state, legal, native_move, cfg)
				push_warning("AIEngine: native backend returned illegal move '%s'" % uci)
			else:
				push_warning("AIEngine: native backend returned no move")
			if not bool(cfg.get("allow_script_fallback", false)):
				return {}
			push_warning("AIEngine: using unrated script fallback after native failure")

	# 3. Script searcher: iterative deepening with movetime cap.
	if not bool(cfg.get("allow_script_fallback", false)):
		push_warning("AIEngine: Stockfish unavailable and script fallback is disabled for rated play")
		return {}
	if not bool(cfg.get("use_book", true)) and (_backend.name() != "native" or not bool(cfg.get("prefer_native", true))):
		push_warning("AIEngine: Max Stockfish is using unrated fallback script search because native Stockfish is unavailable")
	var depth = int(cfg.get("script_depth", 3))
	var mt    = _platform_movetime(int(cfg.get("movetime_ms", 500)), cfg)
	var loss  = int(cfg.get("loss_cp", 0))
	return _script_search(state, legal, depth, mt, loss)

# Cap think time on mobile. Keep it high enough that Stockfish still plays strongly.
func _platform_movetime(mt: int, cfg: Dictionary = {}) -> int:
	if OS.get_name() in ["iOS", "Android"]:
		return mini(mt, int(cfg.get("mobile_movetime_ms", 4000)))
	return mt

func _configure_native_strength(cfg: Dictionary) -> bool:
	if _backend.name() != "native": return false
	if not _backend.has_method("set_option"):
		push_warning("AIEngine: native strength options unavailable; using script search for rated opponent")
		return false
	_apply_engine_profile()
	var elo = int(cfg.get("native_elo", cfg.get("elo", 2000)))
	var ok: bool
	if elo >= 3000:
		# Full strength.
		ok = _backend.set_option("UCI_LimitStrength", "false")
		ok = _backend.set_option("Skill Level", "20") and ok
	elif elo >= 1320:
		# Stockfish's UCI_Elo runs above human scales, so request the MAPPED value
		# (see _human_to_uci_elo); the label stays the human target. UCI_Elo floor
		# is 1320, and Skill Level is ignored while UCI_LimitStrength is true.
		ok = _backend.set_option("UCI_LimitStrength", "true")
		ok = _backend.set_option("UCI_Elo", str(clampi(_human_to_uci_elo(elo), 1320, 3190))) and ok
	else:
		# Below the UCI_Elo floor: Skill Level 0-5 makes deliberate, human-like
		# mistakes. 500→0, 800→2, 1200→5.
		var skill = clampi(int(round((float(elo) - 450.0) / 150.0)), 0, 5)
		ok = _backend.set_option("UCI_LimitStrength", "false")
		ok = _backend.set_option("Skill Level", str(skill)) and ok
	if not ok:
		push_warning("AIEngine: native strength options failed; using script search for rated opponent")
	return ok

# Mirror the active EngineRegistry profile (optional NNUE net + UCI option
# overrides — both DATA) onto the native backend. Strength options (UCI_Elo /
# Skill Level / UCI_LimitStrength) belong to _configure_native_strength and must
# NOT be set by a profile. Re-applies only when the selection changes.
func on_engine_profile_changed() -> void:
	_applied_engine_id = ""
	_applied_net_path = ""

func _apply_engine_profile() -> void:
	if _backend == null or _backend.name() != "native":
		return
	if not _backend.has_method("set_option"):
		return
	var reg = get_node_or_null("/root/EngineRegistry")
	if reg == null:
		return
	var prof: Dictionary = reg.active_profile()
	if prof.is_empty():
		return
	var pid := String(prof.get("id", ""))
	if pid == _applied_engine_id:
		return
	_applied_engine_id = pid
	var net_name := String(prof.get("net", ""))
	var net_path := ""
	if net_name != "":
		net_path = String(reg.resolve_net_path(net_name))
	if net_path != _applied_net_path:
		_applied_net_path = net_path
		if net_path != "":
			_backend.set_option("EvalFile", net_path)
			_backend.set_option("EvalFileSmall", net_path)
	var uci = prof.get("uci", {})
	if typeof(uci) == TYPE_DICTIONARY:
		for k in uci:
			_backend.set_option(String(k), str(uci[k]))

func _book_move(state) -> Dictionary:
	if state.fullmove > 4: return {}
	var fen   = ChessLogic.state_to_fen(state)
	var head  = ChessLogic.STARTING_FEN.substr(0, ChessLogic.STARTING_FEN.find(" "))
	var key   = "start" if fen.begins_with(head) else _book_key(fen)
	if not OPENING_BOOK.has(key): return {}
	var candidates: Array = (OPENING_BOOK[key] as Array).duplicate()
	candidates.shuffle()
	for uci in candidates:
		var move = ChessLogic.uci_to_move(state, uci)
		if not move.is_empty():
			if not _is_awful_opening_pawn_push(state, move): return move
	return {}

func _book_key(fen: String) -> String:
	var parts = fen.split(" ")
	if parts.size() < 4: return ""
	return "%s %s %s %s" % [parts[0], parts[1], parts[2], parts[3]]

func _is_awful_opening_pawn_push(state, move: Dictionary) -> bool:
	if state.fullmove > 2: return false
	var uci = ChessLogic.move_to_uci(move)
	return uci in ["a2a3", "h2h3", "a7a6", "h7h6"]

# ──────────────────────────────────────────────
#  Script searcher (portable)
# ──────────────────────────────────────────────
func _script_quick_hint(state, legal: Array) -> Dictionary:
	# Pick a non-blunder in <1 ms. Just run a 1-ply capture-preferring eval.
	var best  = legal[0]
	var best_v = -999999 if state.turn == ChessLogic.WHITE else 999999
	for m in legal:
		var after = ChessLogic.apply_move(state, m)
		var v = _evaluate(after)
		if state.turn == ChessLogic.WHITE:
			if v > best_v: best_v = v; best = m
		else:
			if v < best_v: best_v = v; best = m
	return best

func _script_search(state, legal: Array, max_depth: int, movetime_ms: int, target_loss: int) -> Dictionary:
	# Iterative deepening: do 1-ply, 2-ply, ... up to max_depth or until the
	# time budget is gone. Always return the deepest complete result so the UI
	# is never empty.
	var started = Time.get_ticks_msec()
	var deadline = started + maxi(20, movetime_ms)
	var scored: Array = []
	var best_move = legal[0]
	var maximizing = state.turn == ChessLogic.WHITE

	for depth in range(1, max_depth + 1):
		if Time.get_ticks_msec() >= deadline: break
		var line: Array = []
		for m in _order_moves(state, legal):
			var child = ChessLogic.apply_move(state, m)
			var sc = -_minimax(child, depth - 1, -999999, 999999, deadline)
			line.append({"move": m, "score": sc})
		if line.is_empty(): break
		line.sort_custom(func(a, b): return a.score > b.score if maximizing else a.score < b.score)
		scored = line
		best_move = scored[0]["move"]
		# If we found a mate, no need to search deeper.
		if abs(scored[0]["score"]) > 90000: break

	# Add a controlled amount of "humanness" at the lower difficulties.
	if target_loss > 0 and not scored.is_empty():
		return _pick_with_loss(scored, best_move, target_loss, maximizing)
	return best_move

func _pick_with_loss(scored: Array, best_move: Dictionary, target_loss: int, maximizing: bool) -> Dictionary:
	var best_score = scored[0]["score"]
	var candidates: Array = []
	for item in scored:
		var loss = best_score - item["score"] if maximizing else item["score"] - best_score
		loss = maxi(0, int(loss))
		if loss <= target_loss * 2:
			var dist = abs(float(loss) - float(target_loss) * randf())
			var w = 1.0 / (1.0 + dist / maxi(60.0, float(target_loss)))
			candidates.append({"move": item["move"], "weight": w})
	if candidates.is_empty(): return best_move
	var total = 0.0
	for c in candidates: total += c["weight"]
	var roll = randf() * total
	for c in candidates:
		roll -= c["weight"]
		if roll <= 0.0: return c["move"]
	return candidates[0]["move"]

# Occasionally replace the engine's move with a human-like mistake so the low
# tiers actually play at their labelled strength (Stockfish Skill Level 0 alone
# is ~1100-1300). The replacement is NOT random — every legal move is scored a
# shallow 1 ply and one is drawn near the tier's target centipawn loss, so the
# bot drops a pawn or misplaces a piece like a real beginner rather than playing
# nonsense. Keeps Stockfish's move the rest of the time, so play stays coherent.
func _apply_human_blunder(state, legal: Array, engine_move: Dictionary, cfg: Dictionary) -> Dictionary:
	var chance = float(cfg.get("blunder", 0.0))
	if chance <= 0.0 or legal.size() <= 1: return engine_move
	if randf() > chance: return engine_move
	var scored = _shallow_scored(state, legal)
	if scored.size() <= 1: return engine_move
	var loss = maxi(120, int(cfg.get("loss_cp", 200)))
	return _pick_with_loss(scored, scored[0]["move"], loss, state.turn == ChessLogic.WHITE)

# Score every legal move with a 1-ply static eval, sorted best-first from the
# side-to-move's perspective (compatible with _pick_with_loss).
func _shallow_scored(state, legal: Array) -> Array:
	var maximizing = state.turn == ChessLogic.WHITE
	var out: Array = []
	for m in legal:
		out.append({"move": m, "score": _evaluate(ChessLogic.apply_move(state, m))})
	out.sort_custom(func(a, b): return a.score > b.score if maximizing else a.score < b.score)
	return out

func _minimax(state, depth: int, alpha: int, beta: int, deadline: int) -> int:
	if Time.get_ticks_msec() >= deadline: return _evaluate(state)
	var status = ChessLogic.get_status(state)
	if status["game_over"]:
		match status["result"]:
			"1-0":  return  99000 + depth
			"0-1":  return -99000 - depth
			_:      return 0
	if depth == 0: return _evaluate(state)
	var maximizing = state.turn == ChessLogic.WHITE
	if maximizing:
		var v = -999999
		for m in _order_moves(state, status["legal_moves"]):
			v = maxi(v, -_minimax(ChessLogic.apply_move(state, m), depth - 1, -beta, -alpha, deadline))
			alpha = maxi(alpha, v)
			if alpha >= beta: break
		return v
	var v = 999999
	for m in _order_moves(state, status["legal_moves"]):
		v = mini(v, -_minimax(ChessLogic.apply_move(state, m), depth - 1, -beta, -alpha, deadline))
		beta = mini(beta, v)
		if alpha >= beta: break
	return v

func _order_moves(state, moves: Array) -> Array:
	var scored: Array = []
	for m in moves:
		var s = 0
		var target = state.board[m["to"]]
		var piece  = state.board[m["from"]]
		if target != 0: s += MAT.get(abs(target), 0) * 10 - MAT.get(abs(piece), 0)
		if m.get("promotion", 0) == ChessLogic.QUEEN: s += 900
		var f = ChessLogic.file_of(m["to"]); var r = ChessLogic.rank_of(m["to"])
		if f in [3, 4] and r in [3, 4]: s += 45
		if abs(piece) in [ChessLogic.KNIGHT, ChessLogic.BISHOP] and state.fullmove <= 8: s += 35
		if abs(piece) == ChessLogic.PAWN and ChessLogic.file_of(m["from"]) in [0, 7] and state.fullmove <= 6: s -= 80
		var after = ChessLogic.apply_move(state, m)
		var st = ChessLogic.get_status(after)
		if st["in_check"]: s += 120
		if st["game_over"] and st["reason"] == "checkmate": s += 50000
		scored.append([s, m])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for x in scored: out.append(x[1])
	return out

func _evaluate(state) -> int:
	var score = 0
	for i in 64:
		var p = state.board[i]
		if p == 0: continue
		var c = ChessLogic.piece_color(p)
		var pt = abs(p)
		var f = ChessLogic.file_of(i); var r = ChessLogic.rank_of(i)
		var pr = r if c == ChessLogic.WHITE else (7 - r)
		score += c * (MAT.get(pt, 0) + _pst(pt, pr * 8 + f))
	return score

func _pst(pt: int, idx: int) -> int:
	match pt:
		ChessLogic.PAWN:   return PST_PAWN[idx]
		ChessLogic.KNIGHT: return PST_KNIGHT[idx]
		ChessLogic.BISHOP: return PST_BISHOP[idx]
		ChessLogic.ROOK:   return PST_ROOK[idx]
		ChessLogic.QUEEN:  return PST_QUEEN[idx]
		ChessLogic.KING:   return PST_KING[idx]
	return 0

# ──────────────────────────────────────────────
#  Difficulty helpers
# ──────────────────────────────────────────────
func _movetime_for(rating: int) -> int:
	# Clamp to a sane budget so a 2800-rated opponent doesn't make the UI hang.
	return clamp(int(round(pow(max(0.0, float(rating) - 250.0) / 2550.0, 1.4) * 2000.0)) + 80, 80, 3500)

func _depth_for(rating: int) -> int:
	if rating <  800: return 1
	if rating < 1400: return 2
	if rating < 2000: return 3
	if rating < 2400: return 4
	return 5

func _loss_cp_for(rating: int) -> int:
	var pts = [[250, 800], [500, 650], [800, 420], [1200, 260],
			   [1600, 120], [2000, 55], [2500, 10], [2800, 0]]
	for i in pts.size() - 1:
		var r0 = pts[i][0];   var c0 = pts[i][1]
		var r1 = pts[i+1][0]; var c1 = pts[i+1][1]
		if rating <= r1:
			var t = float(rating - r0) / float(r1 - r0)
			return int(lerp(float(c0), float(c1), t))
	return 0

# Per-move chance of a deliberate human-like error for a CUSTOM rating,
# interpolated to match the fixed-difficulty `blunder` rates so a custom opponent
# plays like the nearest preset tier. Above ~2000 the engine plays it straight.
func _blunder_for(rating: int) -> float:
	var pts = [[250, 0.55], [500, 0.45], [800, 0.28], [1200, 0.12],
			   [1320, 0.06], [1600, 0.04], [2000, 0.0]]
	if rating <= int(pts[0][0]):  return float(pts[0][1])
	if rating >= int(pts[-1][0]): return float(pts[-1][1])
	for i in pts.size() - 1:
		var r0 = pts[i][0]; var b0 = pts[i][1]
		var r1 = pts[i+1][0]; var b1 = pts[i+1][1]
		if rating <= r1:
			var t = float(rating - r0) / float(r1 - r0)
			return clampf(lerp(float(b0), float(b1), t), 0.0, 0.6)
	return 0.0

# ──────────────────────────────────────────────
#  Move analysis (for review and hint classification)
# ──────────────────────────────────────────────
func analyze_move(state, move: Dictionary, depth: int = 2) -> Dictionary:
	var legal = ChessLogic.get_legal_moves(state)
	if legal.is_empty() or move.is_empty(): return {}
	var scored = _score_moves(state, legal, depth)
	if scored.is_empty(): return {}
	var best = scored[0]
	var move_uci = ChessLogic.move_to_uci(move)
	var played = best
	for item in scored:
		if ChessLogic.move_to_uci(item["move"]) == move_uci:
			played = item
			break
	var color = state.turn
	var loss = best["score"] - played["score"] if color == ChessLogic.WHITE else played["score"] - best["score"]
	loss = maxi(0, int(loss))
	return {
		"best": best["move"],
		"best_eval_cp": best["score"],
		"played_eval_cp": played["score"],
		"loss_cp": loss,
		"tag": _classify_loss(loss),
	}

func review_game(records: Array, player_color: int) -> Dictionary:
	# Force maximum engine strength for the entire review session
	if _backend and _backend.name() == "native":
		_configure_native_strength({"native_elo": 3200})

	# Scale the per-move search budget to the game length: short games get the
	# deepest look, long games shrink toward the floor so the whole review stays
	# under REVIEW_TOTAL_BUDGET_MS. The same value is reused for the best move and
	# the played move so their centipawn-loss comparison is unbiased.
	_review_movetime_ms = clampi(
		int(float(REVIEW_TOTAL_BUDGET_MS) / float(maxi(1, records.size()))),
		REVIEW_MIN_MOVETIME_MS, REVIEW_MAX_MOVETIME_MS)

	# Per-side accumulators. Every move is analysed (for the graph anyway), so
	# computing both colours' stats — and a per-side performance rating — is free.
	var side = {
		ChessLogic.WHITE: {"accs": [], "idxs": [], "loss": 0, "n": 0, "winloss": 0.0, "sharp": 0.0, "misses": []},
		ChessLogic.BLACK: {"accs": [], "idxs": [], "loss": 0, "n": 0, "winloss": 0.0, "sharp": 0.0, "misses": []},
	}
	var win_white_timeline: Array = []   # white-POV win% after each ply

	for i in records.size():
		var record = records[i]
		var state = ChessLogic.parse_fen(record["fen"])
		var analysis = _analyze_move_high_quality(state, record["move"])
		record["analysis"] = analysis

		var win_white = win_white_timeline[-1] if not win_white_timeline.is_empty() else 50.0
		if not analysis.is_empty():
			win_white = _win_percent_for_color(int(analysis.get("played_eval", 0)), ChessLogic.WHITE)
			var col = int(record.get("color", ChessLogic.WHITE))
			var s = side.get(col, side[ChessLogic.WHITE])
			s["accs"].append(float(analysis.get("move_accuracy", 100.0)))
			s["idxs"].append(i)
			s["loss"] += int(analysis["loss_cp"])
			s["n"] += 1
			s["winloss"] += float(analysis.get("win_loss_pct", 0.0))
			s["sharp"] = max(s["sharp"], float(analysis.get("win_loss_pct", 0.0)))
			if String(analysis.get("tag", "")) in ["Inaccuracy", "Mistake", "Blunder"]:
				s["misses"].append(record)
		win_white_timeline.append(win_white)

	var w = side[ChessLogic.WHITE]
	var b = side[ChessLogic.BLACK]
	var white_acc = _aggregate_accuracy(w["accs"], w["idxs"], win_white_timeline)
	var black_acc = _aggregate_accuracy(b["accs"], b["idxs"], win_white_timeline)
	var white_acpl = float(w["loss"]) / float(maxi(1, w["n"]))
	var black_acpl = float(b["loss"]) / float(maxi(1, b["n"]))
	var white_rating = _performance_rating(white_acc)
	var black_rating = _performance_rating(black_acc)

	var ps = side.get(player_color, w)
	return {
		"accuracy": white_acc if player_color == ChessLogic.WHITE else black_acc,
		"avg_loss": float(ps["loss"]) / float(maxi(1, ps["n"])),
		"avg_win_loss": ps["winloss"] / float(maxi(1, ps["n"])),
		"sharpest_loss": ps["sharp"],
		"review_moments": ps["misses"].size(),
		"misses": ps["misses"],
		"moves": records,
		# Per-side stats + estimated "played like" rating.
		"player_color": player_color,
		"white_accuracy": white_acc, "black_accuracy": black_acc,
		"white_acpl": white_acpl, "black_acpl": black_acpl,
		"white_rating": white_rating, "black_rating": black_rating,
		"player_rating": white_rating if player_color == ChessLogic.WHITE else black_rating,
		"opponent_rating": black_rating if player_color == ChessLogic.WHITE else white_rating,
	}

# Game accuracy = the plain mean of the per-move accuracies.
#
# We previously blended in a volatility-weighted mean and a harmonic mean
# (Lichess-style). Both were removed because they let a SINGLE catastrophic move
# dominate: the harmonic mean is governed by the smallest value, so a bot with
# one huge injected blunder scored far below a player with several smaller
# mistakes — inverting the order shown right above it in the move-quality
# breakdown. A straight mean tracks that breakdown faithfully (more best moves /
# fewer errors ⇒ higher accuracy), and each blunder still pulls the average down
# ~6-7 points via the per-move accuracy curve, so blunders do hurt — just not
# non-linearly enough to flip who played better.
func _aggregate_accuracy(accs: Array, _idxs: Array, _win_white_timeline: Array) -> float:
	if accs.is_empty(): return 100.0
	var total = 0.0
	for a in accs:
		total += float(a)
	return clampf(total / float(accs.size()), 0.0, 100.0)

# Estimate the rating a side "played at" this game from its accuracy. Single-game
# estimates are noisy (research puts R² ~0.05-0.5), so this is a fun ballpark,
# not a verdict — anchors are calibrated to the harmonic-blended accuracy scale.
# Map a desired HUMAN/chess.com strength to the Stockfish UCI_Elo to request.
# Stockfish's UCI_Elo runs ABOVE human scales (UCI_Elo 1600 ≈ chess.com ~1900),
# so we subtract a level-dependent "overshoot". These anchors are a sensible
# STARTING point — run tools/calibrate_bots.tscn to measure and refine them.
const UCI_OVERSHOOT_ANCHORS = [[1320, 150], [1600, 250], [1900, 300], [2200, 360], [2600, 440], [3000, 500]]

func _interp_anchor(anchors: Array, x: float) -> float:
	if x <= float(anchors[0][0]): return float(anchors[0][1])
	if x >= float(anchors[-1][0]): return float(anchors[-1][1])
	for i in range(anchors.size() - 1):
		var lo = anchors[i]
		var hi = anchors[i + 1]
		if x >= float(lo[0]) and x <= float(hi[0]):
			var t = (x - float(lo[0])) / maxf(0.001, float(hi[0]) - float(lo[0]))
			return lerp(float(lo[1]), float(hi[1]), t)
	return float(anchors[-1][1])

func _human_to_uci_elo(human: int) -> int:
	return int(round(float(human) - _interp_anchor(UCI_OVERSHOOT_ANCHORS, float(human))))

const PERF_RATING_ANCHORS = [
	[35.0, 300], [45.0, 500], [55.0, 750], [65.0, 1000], [72.0, 1250],
	[78.0, 1500], [83.0, 1750], [88.0, 2050], [92.0, 2350], [96.0, 2650], [99.0, 2850],
]
func _performance_rating(accuracy: float) -> int:
	var a = clampf(accuracy, 0.0, 100.0)
	var anchors = PERF_RATING_ANCHORS
	if a <= float(anchors[0][0]): return int(anchors[0][1])
	if a >= float(anchors[-1][0]): return int(anchors[-1][1])
	for i in range(anchors.size() - 1):
		var lo = anchors[i]
		var hi = anchors[i + 1]
		if a >= float(lo[0]) and a <= float(hi[0]):
			var t = (a - float(lo[0])) / maxf(0.001, float(hi[0]) - float(lo[0]))
			return int(round(lerp(float(lo[1]), float(hi[1]), t)))
	return 1200

func _analyze_move_high_quality(state, move: Dictionary) -> Dictionary:
	var legal = ChessLogic.get_legal_moves(state)
	if legal.is_empty() or move.is_empty(): return {}
	
	var best_move: Dictionary
	var best_eval_cp: int
	var played_eval_cp: int
	var maximizing = state.turn == ChessLogic.WHITE
	
	if _backend and _backend.name() == "native":
		# 1. Get the absolute best move and its evaluation from Stockfish
		var fen = ChessLogic.state_to_fen(state)
		var best_uci = _backend.bestmove(fen, _review_movetime_ms)
		best_move = ChessLogic.uci_to_move(state, best_uci)
		# Use last_eval_cp which Stockfish updates during bestmove search
		# Convert to side-to-move POV for calculation
		var eval_pov = _backend.call("last_eval_cp")
		best_eval_cp = eval_pov if maximizing else -eval_pov
		
		# 2. Get the evaluation of the move that was actually played
		var played_uci = ChessLogic.move_to_uci(move)
		if played_uci == best_uci:
			played_eval_cp = best_eval_cp
		else:
			# briefly check the evaluation after the played move
			played_eval_cp = _evaluate_after_move_deep(state, move)
	else:
		# Script fallback: deeper search
		var scored = _score_moves(state, legal, REVIEW_DEPTH)
		if scored.is_empty(): return {}
		best_move = scored[0]["move"]
		best_eval_cp = scored[0]["score"]
		
		var move_uci = ChessLogic.move_to_uci(move)
		played_eval_cp = best_eval_cp # default if not found (shouldn't happen)
		for item in scored:
			if ChessLogic.move_to_uci(item["move"]) == move_uci:
				played_eval_cp = item["score"]
				break
	
	var loss = best_eval_cp - played_eval_cp if maximizing else played_eval_cp - best_eval_cp
	loss = maxi(0, int(loss))
	var move_color = state.turn
	var best_win = _win_percent_for_color(best_eval_cp, move_color)
	var played_win = _win_percent_for_color(played_eval_cp, move_color)
	var win_loss = max(0.0, best_win - played_win)
	var move_accuracy = _accuracy_from_win_loss(win_loss)
	
	return {
		"best": best_move,
		"best_eval": best_eval_cp,
		"played_eval": played_eval_cp,
		"loss_cp": loss,
		"best_win_pct": best_win,
		"played_win_pct": played_win,
		"win_loss_pct": win_loss,
		"move_accuracy": move_accuracy,
		"tag": _classify_winloss(win_loss),
		"loss_cp_tag": _classify_loss(loss),
	}

func _win_percent_for_color(eval_cp_white: int, color: int) -> float:
	var cp = float(eval_cp_white if color == ChessLogic.WHITE else -eval_cp_white)
	return 50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * cp)) - 1.0)

func _accuracy_from_win_loss(win_loss_pct: float) -> float:
	return clamp(103.1668 * exp(-0.04354 * win_loss_pct) - 3.1669, 0.0, 100.0)

func _evaluate_after_move_deep(state, move: Dictionary) -> int:
	var after = ChessLogic.apply_move(state, move)
	if _backend and _backend.name() == "native":
		# Briefly search from the new position to get an accurate evaluation
		_backend.bestmove(ChessLogic.state_to_fen(after), _review_movetime_ms)
		var eval_pov = _backend.call("last_eval_cp")
		# Convert from after-move POV to white POV
		return eval_pov if after.turn == ChessLogic.WHITE else -eval_pov
	else:
		var deadline = Time.get_ticks_msec() + 100
		return -_minimax(after, REVIEW_DEPTH - 1, -999999, 999999, deadline)

func _score_moves(state, legal: Array, depth: int) -> Array:
	var scored: Array = []
	var deadline = Time.get_ticks_msec() + (REVIEW_MOVETIME_MS if depth > 2 else 100)
	for m in _order_moves(state, legal):
		var ev = -_minimax(ChessLogic.apply_move(state, m), depth - 1, -999999, 999999, deadline)
		scored.append({"move": m, "score": ev})
	var white_to_move = state.turn == ChessLogic.WHITE
	scored.sort_custom(func(a, b): return a["score"] > b["score"] if white_to_move else a["score"] < b["score"])
	return scored

func _classify_loss(loss: int) -> String:
	if loss >= 300: return "Blunder"
	if loss >= 160: return "Mistake"
	if loss >=  80: return "Inaccuracy"
	if loss >=  25: return "Slight miss"
	return "Best or good"

# Review classification by win-probability lost (Lichess-style), which is far more
# faithful than a flat centipawn threshold: shedding two pawns while already +9 is
# not a blunder, but a small eval swing in a balanced game can be decisive. Maps
# to the same labels the review UI already understands.
func _classify_winloss(win_loss_pct: float) -> String:
	if win_loss_pct >= 20.0: return "Blunder"
	if win_loss_pct >= 10.0: return "Mistake"
	if win_loss_pct >=  5.0: return "Inaccuracy"
	if win_loss_pct >=  2.0: return "Slight miss"
	return "Best or good"
