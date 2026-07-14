extends Node

var _root: Control    = null
var _current: Control = null

var chosen_difficulty: String  = "medium"
var custom_rating: int         = 1200
var player_color: int          = ChessLogic.WHITE
var local_two_player: bool     = false   # Pass & Play: two humans, one device
var time_mode: String          = "rapid"
var current_game_rated: bool   = true
var allow_unrated_fallback: bool = false
var resume_session: Dictionary = {}   # populated when resuming a saved game
var review_session: Dictionary = {}
var engines_return_to: String = "settings"   # where the Engines screen's back button goes
var online_match: Dictionary   = {}   # Game Center match opened from OnlineScreen:
									  # {match_id, my_turn, data, i_created, opponent}
var feature_flags: Dictionary  = {
	# Game Center turn-based online play + leaderboard. The match flow is
	# turn-based (you stay in-app and moves auto-send via GKTurnBasedMatch —
	# no manual "send" like iMessage), but NOT real-time simultaneous.
	# Needs the Game Center capability + a real-device test before shipping.
	"multiplayer": false,
	"campaign": false,
}
const TIME_MODES = {
	"casual":  {"label": "∞ Casual", "seconds": 0,   "increment": 0},
	"blitz":   {"label": "⚡ Blitz 5 min",     "seconds": 300, "increment": 0},
	"rapid":   {"label": "◷ Rapid 10 min",    "seconds": 600, "increment": 0},
	"classic": {"label": "♜ Classical 15 min", "seconds": 900, "increment": 10},
}

func _ready() -> void:
	# A live (GKMatch) match can begin from anywhere — the matchmaker sheet or an
	# accepted invite — so open the board globally when one starts.
	var gc = get_node_or_null("/root/GameCenterManager")
	if gc != null and gc.has_signal("realtime_started"):
		gc.realtime_started.connect(_on_realtime_started)

func _on_realtime_started(opponent: String, my_white: bool) -> void:
	show_online_game({
		"realtime": true,
		"backend": "gamecenter",
		"my_white": my_white,
		"opponent": opponent,
	})

func start(root: Control) -> void:
	_root = root
	PlayerData.touch_daily_streak()
	show_main_menu()

func _show(screen: Control) -> void:
	if _current and is_instance_valid(_current):
		_current.queue_free()
	_current = screen
	_root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Gentle cross-screen fade
	screen.modulate.a = 0.0
	var tween = screen.create_tween()
	tween.tween_property(screen, "modulate:a", 1.0, 0.18)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func show_main_menu() -> void:
	resume_session = {}
	review_session = {}
	online_match = {}
	current_game_rated = true
	allow_unrated_fallback = false
	local_two_player = false
	_show(load("res://scripts/ui/MainMenuScreen.gd").new())

func show_difficulty_select() -> void:
	_show(load("res://scripts/ui/DifficultyScreen.gd").new())

func show_game() -> void:
	review_session = {}
	online_match = {}
	_show(load("res://scripts/ui/GameScreen.gd").new())

func show_online() -> void:
	_show(load("res://scripts/ui/OnlineScreen.gd").new())

func show_online_game(match_info: Dictionary) -> void:
	review_session = {}
	resume_session = {}
	local_two_player = false
	current_game_rated = false
	online_match = match_info
	_show(load("res://scripts/ui/GameScreen.gd").new())

func show_local_game() -> void:
	local_two_player = true
	chosen_difficulty = "local"
	player_color = ChessLogic.WHITE
	current_game_rated = false
	allow_unrated_fallback = true
	show_game()

func resume_game(session: Dictionary) -> void:
	# Guard against a corrupt/empty saved game: without a valid FEN the board
	# would silently reset to the start, which feels like lost progress. Bail
	# gracefully instead of resuming into a broken state.
	if session.is_empty() or String(session.get("fen", "")).strip_edges() == "":
		push_warning("GameManager.resume_game: saved game has no valid position — ignoring")
		return
	resume_session = session
	chosen_difficulty = session.get("difficulty", "medium")
	local_two_player  = chosen_difficulty == "local"
	player_color      = session.get("player_color", ChessLogic.WHITE)
	time_mode         = session.get("time_mode", "rapid")
	current_game_rated = bool(session.get("rated", true)) and not local_two_player
	allow_unrated_fallback = bool(session.get("allow_fallback", not current_game_rated))
	_show(load("res://scripts/ui/GameScreen.gd").new())

func show_profile() -> void:
	_show(load("res://scripts/ui/ProfileScreen.gd").new())

func show_puzzles() -> void:
	_show(load("res://scripts/ui/PuzzlesScreen.gd").new())

func show_players() -> void:
	_show(load("res://scripts/ui/PlayersScreen.gd").new())

func show_settings() -> void:
	_show(load("res://scripts/ui/SettingsScreen.gd").new())

func show_about() -> void:
	_show(load("res://scripts/ui/AboutScreen.gd").new())

func show_engines(return_to: String = "") -> void:
	# External entry points pass where Back should go ("settings" / "play"); the
	# screen's own re-shows (after select/install) pass "" to keep the current one.
	if return_to != "":
		engines_return_to = return_to
	_show(load("res://scripts/ui/EnginesScreen.gd").new())

func show_completed_review(game: Dictionary) -> void:
	review_session = game
	resume_session = {}
	_show(load("res://scripts/ui/GameScreen.gd").new())
