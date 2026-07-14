extends Node
# Puzzle progression, daily puzzle, and endless ("freeform") tactics.
#
# Bundled puzzles come from the Lichess CC0 puzzle database, baked into
# assets/puzzles/bundled.json as raw rows {id, fen, moves, rating, themes}
# where fen is the position BEFORE the opponent's setup move and moves[0]
# is that setup move (Lichess CSV convention).
#
# Online puzzles use the free Lichess API (no auth required):
#   GET https://lichess.org/api/puzzle/daily
#   GET https://lichess.org/api/puzzle/next?difficulty=...
# The API returns fen AFTER the setup move plus lastMove + solution.
#
# Both sources are normalized to:
#   {id, fen, last_from, last_to, solution: [uci...], rating, themes: [String]}
# where fen is the position the player solves (player to move).

signal progress_changed
signal daily_loaded(puzzle: Dictionary, from_network: bool)
signal daily_failed
signal next_loaded(puzzle: Dictionary, from_network: bool)

const BUNDLE_PATH = "res://assets/puzzles/bundled.json"
const SAVE_PATH = "user://puzzle_data.json"
const STARTING_RATING = 1000
const UNLOCK_REQUIRED = 5   # puzzles solved in a level to unlock the next

var levels: Array = []      # [{name, subtitle, unlock_stars, puzzles:[RAW rows]}]
var pool: Array = []        # RAW offline fallback rows; normalized lazily on pick

var stars: Dictionary = {}  # puzzle_id -> best stars earned (1..3)
var rating: int = STARTING_RATING
var solved_count: int = 0
var clean_count: int = 0
var streak: int = 0
var best_streak: int = 0
var rating_history: Array = []
var daily_cache: Dictionary = {}  # {"date": "YYYY-MM-DD", "puzzle": {...}, "solved": bool, "stars": int}

var _seen_pool_ids: Array = []    # avoid repeating offline endless puzzles

func _ready() -> void:
	_load_bundle()
	_load_save()

# ──────────────────────────────────────────────
#  Bundle / persistence
# ──────────────────────────────────────────────
func _load_bundle() -> void:
	var file = FileAccess.open(BUNDLE_PATH, FileAccess.READ)
	if not file:
		push_error("PuzzleManager: bundled puzzles missing at " + BUNDLE_PATH)
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK: return
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY: return
	# Levels (like the pool) keep RAW rows and normalize on demand — the
	# journey now holds thousands of puzzles, so eager normalization would
	# stall startup. Progress queries only need each row's id.
	for lv in data.get("levels", []):
		var rows: Array = []
		for row in lv.get("puzzles", []):
			if typeof(row) == TYPE_DICTIONARY and row.has("id") and row.has("moves"):
				rows.append(row)
		levels.append({
			"name": lv.get("name", "?"), "subtitle": lv.get("subtitle", ""),
			"unlock_stars": int(lv.get("unlock_stars", 0)), "puzzles": rows,
		})
	# Pool rows are kept RAW (id + rating are enough to filter on) and only
	# normalized when one is actually selected, so startup cost stays O(1) in
	# pool size even with thousands of puzzles bundled.
	for row in data.get("pool", []):
		if typeof(row) == TYPE_DICTIONARY and row.has("id") and row.has("moves"):
			pool.append(row)

func _normalize_csv_row(row: Dictionary) -> Dictionary:
	var moves: PackedStringArray = str(row.get("moves", "")).split(" ", false)
	if moves.size() < 2: return {}
	var state = ChessLogic.parse_fen(str(row.get("fen", "")))
	var setup = ChessLogic.uci_to_move(state, moves[0])
	if setup.is_empty(): return {}
	state = ChessLogic.apply_move(state, setup)
	var solution: Array = []
	for i in range(1, moves.size()): solution.append(moves[i])
	return {
		"id": str(row.get("id", "")),
		"fen": ChessLogic.state_to_fen(state),
		"last_from": int(setup["from"]),
		"last_to": int(setup["to"]),
		"solution": solution,
		"rating": int(row.get("rating", 1500)),
		"themes": str(row.get("themes", "")).split(" ", false),
	}

func _normalize_api_puzzle(data: Dictionary) -> Dictionary:
	var pz = data.get("puzzle", {})
	if typeof(pz) != TYPE_DICTIONARY or not pz.has("fen") or not pz.has("solution"): return {}
	var last = str(pz.get("lastMove", ""))
	return {
		"id": str(pz.get("id", "")),
		"fen": str(pz["fen"]),
		"last_from": ChessLogic.sq_from_name(last.substr(0, 2)) if last.length() >= 4 else -1,
		"last_to": ChessLogic.sq_from_name(last.substr(2, 2)) if last.length() >= 4 else -1,
		"solution": Array(pz["solution"]),
		"rating": int(pz.get("rating", 1500)),
		"themes": Array(pz.get("themes", [])).map(func(t): return str(t)),
	}

func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK: return
	var d = json.get_data()
	if typeof(d) != TYPE_DICTIONARY: return
	stars          = d.get("stars", {})
	rating         = int(d.get("rating", STARTING_RATING))
	solved_count   = int(d.get("solved_count", 0))
	clean_count    = int(d.get("clean_count", 0))
	streak         = int(d.get("streak", 0))
	best_streak    = int(d.get("best_streak", 0))
	rating_history = d.get("rating_history", [])
	daily_cache    = d.get("daily_cache", {})
	_seen_pool_ids = d.get("seen_pool_ids", [])

func save() -> void:
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not f: return
	f.store_string(JSON.stringify({
		"stars": stars, "rating": rating,
		"solved_count": solved_count, "clean_count": clean_count,
		"streak": streak, "best_streak": best_streak,
		"rating_history": rating_history,
		"daily_cache": daily_cache, "seen_pool_ids": _seen_pool_ids,
	}))

func reset_all() -> void:
	stars = {}
	rating = STARTING_RATING
	solved_count = 0
	clean_count = 0
	streak = 0
	best_streak = 0
	rating_history = []
	daily_cache = {}
	_seen_pool_ids = []
	save()
	progress_changed.emit()

# ──────────────────────────────────────────────
#  Progression queries
# ──────────────────────────────────────────────
func puzzle_stars(id: String) -> int:
	return int(stars.get(id, 0))

func level_solved(idx: int) -> int:
	if idx < 0 or idx >= levels.size(): return 0
	var n = 0
	for p in levels[idx]["puzzles"]:
		if puzzle_stars(p["id"]) > 0: n += 1
	return n

func level_stars(idx: int) -> int:
	if idx < 0 or idx >= levels.size(): return 0
	var n = 0
	for p in levels[idx]["puzzles"]:
		n += puzzle_stars(p["id"])
	return n

# Star-gated: a level opens once your CUMULATIVE star total reaches its
# threshold — independent of which levels those stars came from.
func is_level_unlocked(idx: int) -> bool:
	if idx <= 0: return true
	if idx >= levels.size(): return false
	return total_stars() >= int(levels[idx].get("unlock_stars", 0))

func level_unlock_stars(idx: int) -> int:
	if idx < 0 or idx >= levels.size(): return 0
	return int(levels[idx].get("unlock_stars", 0))

# Stars still needed to open this level (0 if already unlocked).
func stars_to_unlock(idx: int) -> int:
	return max(0, level_unlock_stars(idx) - total_stars())

# Normalize a level puzzle on demand (rows are stored raw).
func level_puzzle(level_idx: int, puzzle_idx: int) -> Dictionary:
	if level_idx < 0 or level_idx >= levels.size(): return {}
	var puzzles: Array = levels[level_idx]["puzzles"]
	if puzzle_idx < 0 or puzzle_idx >= puzzles.size(): return {}
	return _normalize_csv_row(puzzles[puzzle_idx])

func first_unsolved_in_level(idx: int) -> int:
	if idx < 0 or idx >= levels.size(): return 0
	var puzzles: Array = levels[idx]["puzzles"]
	for i in puzzles.size():
		if puzzle_stars(puzzles[i]["id"]) == 0: return i
	return 0

func total_stars() -> int:
	var n = 0
	for i in levels.size(): n += level_stars(i)
	return n

func total_solved() -> int:
	return solved_count

# ──────────────────────────────────────────────
#  Recording results
# ──────────────────────────────────────────────
# stars_earned: 3 = clean (no mistakes, no hints), 2 = one slip OR hints, 1 = solved eventually
func record_result(puzzle: Dictionary, stars_earned: int, clean: bool, rated: bool) -> int:
	var id = str(puzzle.get("id", ""))
	var delta = 0
	if id != "":
		stars[id] = max(puzzle_stars(id), stars_earned)
	solved_count += 1
	if clean:
		clean_count += 1
		streak += 1
		best_streak = max(best_streak, streak)
	else:
		streak = 0
	if rated:
		var pr = int(puzzle.get("rating", 1500))
		var expected = 1.0 / (1.0 + pow(10.0, (pr - rating) / 400.0))
		var score = 1.0 if clean else 0.0
		delta = int(round(24.0 * (score - expected)))
		rating = max(400, rating + delta)
		rating_history.append(rating)
		if rating_history.size() > 60:
			rating_history = rating_history.slice(rating_history.size() - 60)
	save()
	progress_changed.emit()
	return delta

func mark_daily_solved(stars_earned: int) -> void:
	if daily_cache.get("date", "") == _today():
		daily_cache["solved"] = true
		daily_cache["stars"] = max(int(daily_cache.get("stars", 0)), stars_earned)
		save()
		progress_changed.emit()

func is_daily_solved() -> bool:
	return daily_cache.get("date", "") == _today() and bool(daily_cache.get("solved", false))

func _today() -> String:
	return Time.get_date_string_from_system()

# ──────────────────────────────────────────────
#  Daily puzzle (lichess.org/api/puzzle/daily)
# ──────────────────────────────────────────────
func request_daily() -> void:
	if daily_cache.get("date", "") == _today() and not daily_cache.get("puzzle", {}).is_empty():
		daily_loaded.emit(daily_cache["puzzle"], false)
		return
	var http = HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers, body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var puzzle = _normalize_api_puzzle(json.get_data())
				if not puzzle.is_empty():
					daily_cache = {"date": _today(), "puzzle": puzzle, "solved": false, "stars": 0}
					save()
					daily_loaded.emit(puzzle, true)
					return
		_daily_fallback())
	if http.request("https://lichess.org/api/puzzle/daily") != OK:
		http.queue_free()
		_daily_fallback()

func _daily_fallback() -> void:
	# Deterministic offline daily: pick from the pool by date hash.
	if pool.is_empty():
		daily_failed.emit()
		return
	var idx = abs(_today().hash()) % pool.size()
	var puzzle = _normalize_csv_row(pool[idx])
	if puzzle.is_empty():
		daily_failed.emit()
		return
	daily_cache = {"date": _today(), "puzzle": puzzle, "solved": false, "stars": 0}
	save()
	daily_loaded.emit(puzzle, false)

# ──────────────────────────────────────────────
#  Endless puzzles (lichess.org/api/puzzle/next, offline pool fallback)
# ──────────────────────────────────────────────
func request_next() -> void:
	var http = HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers, body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var puzzle = _normalize_api_puzzle(json.get_data())
				if not puzzle.is_empty():
					next_loaded.emit(puzzle, true)
					return
		next_loaded.emit(_pool_near_rating(), false))
	# Anonymous /next assumes ~1500; nudge with the difficulty parameter.
	var difficulty = "normal"
	if rating < 1100:   difficulty = "easiest"
	elif rating < 1350: difficulty = "easier"
	elif rating > 1900: difficulty = "hardest"
	elif rating > 1650: difficulty = "harder"
	if http.request("https://lichess.org/api/puzzle/next?difficulty=" + difficulty) != OK:
		http.queue_free()
		next_loaded.emit(_pool_near_rating(), false)

func _pool_near_rating() -> Dictionary:
	if pool.is_empty(): return {}
	var candidates = pool.filter(func(p):
		return abs(int(p["rating"]) - rating) <= 200 and not _seen_pool_ids.has(p["id"]))
	if candidates.is_empty():
		candidates = pool.filter(func(p): return not _seen_pool_ids.has(p["id"]))
	if candidates.is_empty():
		_seen_pool_ids = []
		candidates = pool
	var raw = candidates[randi() % candidates.size()]
	_seen_pool_ids.append(raw["id"])
	if _seen_pool_ids.size() > pool.size() - 8:
		_seen_pool_ids = []
	save()
	return _normalize_csv_row(raw)
