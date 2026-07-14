extends Control
# Automated screenshot tour. Run windowed:
#   godot res://test_screens.tscn
# Writes PNGs to /tmp/chess_shots/.

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/chess_shots")
	GameManager.start(self)
	await _shot("01_main_menu")
	GameManager.show_puzzles()
	await _shot("02_puzzles_hub")
	var hub = GameManager._current
	hub._start_level_puzzle(0, 0)
	await _shot("04_puzzle_solver")
	hub._on_hint()
	hub._on_hint()
	await _shot("05_puzzle_hint")
	# Wrong move: pick the first legal move that is NOT the solution
	var wrong = null
	for mv in ChessLogic.get_legal_moves(hub._state):
		if ChessLogic.move_to_uci(mv) != hub._solution[0]:
			wrong = mv
			break
	if wrong != null:
		hub._try_player_move(wrong)
		await get_tree().create_timer(0.2).timeout
		var img = get_viewport().get_texture().get_image()
		img.save_png("/tmp/chess_shots/05b_puzzle_wrong.png")
		print("shot 05b_puzzle_wrong")
		await get_tree().create_timer(1.0).timeout
	# Correct move: play the actual solution and let the success card appear
	var right = ChessLogic.uci_to_move(hub._state, hub._solution[0])
	hub._try_player_move(right)
	await _shot("06_puzzle_success")
	GameManager.show_difficulty_select()
	await _shot("07_difficulty")
	var diff = GameManager._current
	diff._on_opponent_selected("local")
	await _shot("07b_difficulty_local")
	GameManager.show_game()
	await _shot("08_game")
	# Pass & Play: white plays e4, seat hands to black
	GameManager.show_local_game()
	await get_tree().create_timer(0.5).timeout
	var game = GameManager._current
	var e4 = ChessLogic.uci_to_move(game._state, "e2e4")
	game._apply_player_move(e4)
	await _shot("08b_local_game_black_to_move")
	print("local seat now: ", "BLACK" if game._player_color == ChessLogic.BLACK else "WHITE",
		" rated=", game._rated_game, " local=", game._local_mode)
	# Capture exchange: d5, exd5 — the bottom bar should show the captured pawn
	game._apply_player_move(ChessLogic.uci_to_move(game._state, "d7d5"))
	await get_tree().create_timer(0.3).timeout
	game._apply_player_move(ChessLogic.uci_to_move(game._state, "e4d5"))
	await _shot("08c_local_game_capture")
	# Game review: stats modal (with "Played like") + the interactive review page
	var rdata = AIEngine.review_game(game._move_records.duplicate(true), game._player_color)
	game._review.show_stats_modal(rdata, false)
	await _shot("11_review_stats")
	GameModals.dismiss(game, "StatsModal")
	game._review.open_review_page(rdata)
	await _shot("12_review_page")
	GameManager.show_profile()
	await _shot("09_profile")
	GameManager.show_online()
	await _shot("10_online")
	get_tree().quit()

func _shot(name: String) -> void:
	await get_tree().create_timer(0.9).timeout
	var img = get_viewport().get_texture().get_image()
	img.save_png("/tmp/chess_shots/%s.png" % name)
	print("shot ", name)
