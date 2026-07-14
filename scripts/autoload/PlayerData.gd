extends Node

const SAVE_PATH  = "user://player_data.json"
const GAMES_PATH = "user://saved_games.json"
const STARTING_ELO = 800
const STARTING_RD = 350.0
const K_LOW  = 40   # < 1200
const K_MID  = 20   # 1200–2399
const K_HIGH = 10   # 2400+

signal data_changed

var elo: int            = STARTING_ELO
var rating_deviation: float = STARTING_RD
var games_played: int   = 0
var wins: int           = 0
var losses: int         = 0
var draws: int          = 0
var current_streak: int = 0
var best_streak: int    = 0
var elo_history: Array  = []
var last_rated_at: int  = 0   # unix seconds of the last rated game (RD inactivity decay)

# Consecutive-days-played streak (Duolingo-style), independent of win streak.
var day_streak: int      = 0
var best_day_streak: int = 0
var last_played_date: String = ""   # "YYYY-MM-DD"
var achievements: Array = []

var settings: Dictionary = {
	"sound":       true,
	"clock_sound": true,
	"instant_bot": false,
	"sound_style": "soft",
	"haptics":     true,
	"hints":       true,
	"voice_coords": true,
	"board_theme": 0,
	"piece_theme": 0,
	"piece_style": 0,
	"engine_id":   "stockfish18",
}

# Saved game sessions: Array of {id, fen, difficulty, player_color, date, moves_played, history, records}
var saved_games: Array = []
var completed_games: Array = []

# ──────────────────────────────────────────────
#  Persistence
# ──────────────────────────────────────────────
func _ready() -> void:
	load_data()

func load_data() -> void:
	_load_player()
	_load_games()

func _load_player() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK: return
	var d = json.get_data()
	if typeof(d) != TYPE_DICTIONARY: return
	elo            = d.get("elo", STARTING_ELO)
	rating_deviation = float(d.get("rating_deviation", STARTING_RD))
	games_played   = d.get("games_played", 0)
	wins           = d.get("wins", 0)
	losses         = d.get("losses", 0)
	draws          = d.get("draws", 0)
	current_streak = d.get("current_streak", 0)
	best_streak    = d.get("best_streak", 0)
	last_rated_at  = int(d.get("last_rated_at", 0))
	day_streak       = int(d.get("day_streak", 0))
	best_day_streak  = int(d.get("best_day_streak", 0))
	last_played_date = str(d.get("last_played_date", ""))
	elo_history    = d.get("elo_history", [])
	achievements   = d.get("achievements", [])
	var s          = d.get("settings", {})
	for key in s: settings[key] = s[key]

func _load_games() -> void:
	if not FileAccess.file_exists(GAMES_PATH): return
	var file = FileAccess.open(GAMES_PATH, FileAccess.READ)
	if not file: return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK: return
	var d = json.get_data()
	if typeof(d) == TYPE_ARRAY:
		saved_games = d
	elif typeof(d) == TYPE_DICTIONARY:
		saved_games = d.get("saved", [])
		completed_games = d.get("completed", [])

func save_data() -> void:
	var d = {
		"elo": elo, "games_played": games_played, "wins": wins,
		"rating_deviation": rating_deviation,
		"losses": losses, "draws": draws, "current_streak": current_streak,
		"best_streak": best_streak, "elo_history": elo_history,
		"last_rated_at": last_rated_at,
		"day_streak": day_streak, "best_day_streak": best_day_streak,
		"last_played_date": last_played_date,
		"achievements": achievements, "settings": settings,
	}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

func save_games() -> void:
	var f = FileAccess.open(GAMES_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"saved": saved_games, "completed": completed_games}))

# Call once per app launch. Bumps the consecutive-days-played streak when the
# player returns on the next calendar day; resets it after a missed day.
func touch_daily_streak() -> void:
	var today = _date_string(0)
	if last_played_date == today:
		return
	if last_played_date == _date_string(-1):
		day_streak += 1
	else:
		day_streak = 1
	best_day_streak = max(best_day_streak, day_streak)
	last_played_date = today
	save_data()

func _date_string(day_offset: int) -> String:
	var t = Time.get_unix_time_from_system() + day_offset * 86400
	var d = Time.get_date_dict_from_unix_time(int(t))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func reset_all() -> void:
	elo = STARTING_ELO
	rating_deviation = STARTING_RD
	games_played = 0
	wins = 0
	losses = 0
	draws = 0
	current_streak = 0
	best_streak = 0
	last_rated_at = 0
	day_streak = 0
	best_day_streak = 0
	last_played_date = ""
	elo_history = []
	achievements = []
	saved_games = []
	completed_games = []
	settings = {
		"sound": true,
		"clock_sound": true,
		"instant_bot": false,
		"sound_style": "soft",
		"haptics": true,
		"hints": true,
		"voice_coords": true,
		"board_theme": 0,
		"piece_theme": 0,
		"piece_style": 0,
		"engine_id":   "stockfish18",
	}
	save_data()
	save_games()
	data_changed.emit()

# ──────────────────────────────────────────────
#  Game sessions
# ──────────────────────────────────────────────
func save_game_session(
	fen: String,
	difficulty: String,
	player_color: int,
	moves: int,
	time_mode: String = "rapid",
	history: Array = [],
	records: Array = [],
	white_time: float = -1.0,
	black_time: float = -1.0,
	rated: bool = true,
	allow_fallback: bool = false
) -> void:
	# Keep max 5 saved games, most recent first
	var session = {
		"id": int(Time.get_unix_time_from_system()),
		"fen": fen,
		"difficulty": difficulty,
		"player_color": player_color,
		"time_mode": time_mode,
		"rated": rated,
		"allow_fallback": allow_fallback,
		"moves_played": moves,
		"history": history.duplicate(true),
		"records": records.duplicate(true),
		"date": Time.get_datetime_string_from_system(),
		# Shared data contract: real-world suspend time (so a resume can subtract
		# elapsed time from the clock) and the engine the game was played on.
		# Older saves lack these — every reader must default them safely.
		"saved_at": int(Time.get_unix_time_from_system()),
		"engine_id": String(settings.get("engine_id", "stockfish18")),
	}
	if white_time >= 0.0:
		session["white_time"] = white_time
	if black_time >= 0.0:
		session["black_time"] = black_time
	# Remove any existing session with same difficulty+color (one slot per combo)
	saved_games = saved_games.filter(func(g):
		return not (g["difficulty"] == difficulty and g["player_color"] == player_color))
	saved_games.insert(0, session)
	if saved_games.size() > 5:
		saved_games = saved_games.slice(0, 5)
	save_games()

func delete_game_session(session_id: int) -> void:
	saved_games = saved_games.filter(func(g): return g["id"] != session_id)
	save_games()

# Drop the continuable session for a finished game. Saved sessions are keyed
# one-per (difficulty + color), so a completed game is cleared by that key —
# this is what keeps finished games out of the Continue list.
func clear_game_session(difficulty: String, player_color: int) -> void:
	var before = saved_games.size()
	saved_games = saved_games.filter(func(g):
		return not (g.get("difficulty", "") == difficulty and int(g.get("player_color", 0)) == player_color))
	if saved_games.size() != before:
		save_games()

func has_saved_games() -> bool:
	return saved_games.size() > 0

func save_completed_game(game: Dictionary) -> void:
	if game.is_empty() or game.get("records", []).is_empty(): return
	completed_games.insert(0, game)
	if completed_games.size() > 30:
		completed_games = completed_games.slice(0, 30)
	save_games()

# ──────────────────────────────────────────────
#  ELO
# ──────────────────────────────────────────────
func expected_score(player_elo: int, opponent_elo: int) -> float:
	return 1.0 / (1.0 + pow(10.0, (opponent_elo - player_elo) / 400.0))

func k_factor() -> int:
	if elo < 1200: return K_LOW
	if elo < 2400: return K_MID
	return K_HIGH

# Opponent rating deviation by strength. Weak, handicapped bots are noisy
# (blunder injection), so we trust a single result against them less (higher RD);
# near full-strength bots are consistent (lower RD). 500→110, 2500→45.
func _opponent_rd(opp_elo: int) -> float:
	var t = clampf((float(opp_elo) - 500.0) / 2000.0, 0.0, 1.0)
	return lerp(110.0, 45.0, t)

# Grow the player's RD with days since their last rated game (Glicko inactivity
# decay). c² is chosen so an idle player's RD climbs from the 50 floor back toward
# the 350 ceiling over roughly six months away from rated play.
func _decayed_rd() -> float:
	if last_rated_at <= 0:
		return rating_deviation
	var days = maxf(0.0, (float(Time.get_unix_time_from_system()) - float(last_rated_at)) / 86400.0)
	var c2 = (STARTING_RD * STARTING_RD - 50.0 * 50.0) / 180.0
	return clampf(sqrt(rating_deviation * rating_deviation + c2 * days), 50.0, STARTING_RD)

func record_result(opponent_elo: int, result_score: float) -> int:
	var prev = elo
	# Glicko-style update with two refinements that keep the rating "semi-accurate"
	# without a full Glicko-2 volatility model:
	#  1. Per-opponent RD (_opponent_rd) — handicapped/casual bots play erratically
	#     (deliberate blunders), so a result against them is less informative than
	#     one against a near-full-strength bot ⇒ a smaller, more cautious swing.
	#  2. Inactivity decay (_decayed_rd) — the player's own RD grows with time away
	#     from rated play, so the first game back moves the rating faster.
	var pre_rd = _decayed_rd()
	var opp_rd = _opponent_rd(opponent_elo)
	var q = log(10.0) / 400.0
	var g = 1.0 / sqrt(1.0 + 3.0 * q * q * opp_rd * opp_rd / (PI * PI))
	var exp = 1.0 / (1.0 + pow(10.0, -g * (elo - opponent_elo) / 400.0))
	var d2 = 1.0 / (q * q * g * g * exp * (1.0 - exp))
	var pre_rd2 = pre_rd * pre_rd
	var new_rating = float(elo) + (q / (1.0 / pre_rd2 + 1.0 / d2)) * g * (result_score - exp)
	var new_rd = sqrt(1.0 / (1.0 / pre_rd2 + 1.0 / d2))
	elo = max(100, int(round(new_rating)))
	rating_deviation = clamp(new_rd, 50.0, STARTING_RD)
	last_rated_at = int(Time.get_unix_time_from_system())
	var delta = elo - prev
	games_played += 1
	if result_score == 1.0:
		wins += 1; current_streak += 1; best_streak = max(best_streak, current_streak)
	elif result_score == 0.0:
		losses += 1; current_streak = 0
	else:
		draws += 1; current_streak = 0
	elo_history.append(elo)
	if elo_history.size() > 30: elo_history = elo_history.slice(elo_history.size() - 30)
	_check_achievements(prev, result_score, opponent_elo)
	save_data()
	data_changed.emit()
	return delta

# ──────────────────────────────────────────────
#  Title
# ──────────────────────────────────────────────
func get_title() -> String:
	if elo < 800:  return "Beginner"
	if elo < 1200: return "Novice"
	if elo < 1500: return "Intermediate"
	if elo < 1800: return "Advanced"
	if elo < 2000: return "Expert"
	if elo < 2200: return "Candidate Master"
	return "Master"

func get_title_color() -> Color:
	if elo < 800:  return Color("#9e9e9e")
	if elo < 1200: return Color("#4caf50")
	if elo < 1500: return Color("#2196f3")
	if elo < 1800: return Color("#9c27b0")
	if elo < 2000: return Color("#ff9800")
	return Color("#f6c90e")

func win_rate() -> float:
	if games_played == 0: return 0.0
	return float(wins) / float(games_played)

# ──────────────────────────────────────────────
#  Achievements
# ──────────────────────────────────────────────
const ACHIEVEMENT_DEFS = {
	"first_win":  {"name": "First Blood",      "desc": "Win your first game"},
	"streak_3":   {"name": "On a Roll",         "desc": "Win 3 games in a row"},
	"streak_5":   {"name": "Undefeated Five",   "desc": "Win 5 games in a row"},
	"streak_10":  {"name": "Dominant",          "desc": "Win 10 games in a row"},
	"games_10":   {"name": "Getting Started",   "desc": "Play 10 games"},
	"games_50":   {"name": "Dedicated",         "desc": "Play 50 games"},
	"games_100":  {"name": "Century Club",      "desc": "Play 100 games"},
	"elo_1000":   {"name": "Four Digits",       "desc": "Reach 1000 ELO"},
	"elo_1500":   {"name": "Intermediate",      "desc": "Reach 1500 ELO"},
	"elo_2000":   {"name": "Expert",            "desc": "Reach 2000 ELO"},
	"upset":      {"name": "Giant Killer",      "desc": "Beat an opponent rated 300+ higher"},
	"undo_never": {"name": "No Regrets",        "desc": "Win without using undo"},
}

func has_achievement(id: String) -> bool: return id in achievements
func _unlock(id: String) -> bool:
	if has_achievement(id): return false
	achievements.append(id); return true

func _check_achievements(prev_elo: int, result: float, opp_elo: int) -> void:
	if result == 1.0:
		_unlock("first_win")
		if current_streak >= 3:  _unlock("streak_3")
		if current_streak >= 5:  _unlock("streak_5")
		if current_streak >= 10: _unlock("streak_10")
		if opp_elo - prev_elo >= 300: _unlock("upset")
	if games_played >= 10:  _unlock("games_10")
	if games_played >= 50:  _unlock("games_50")
	if games_played >= 100: _unlock("games_100")
	if elo >= 1000: _unlock("elo_1000")
	if elo >= 1500: _unlock("elo_1500")
	if elo >= 2000: _unlock("elo_2000")
