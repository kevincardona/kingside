extends SceneTree
# Headless unit tests for the ChessLogic engine (pure — no autoloads needed).
#   godot --headless -s res://test_chesslogic.gd

const ChessLogicScript = preload("res://scripts/autoload/ChessLogic.gd")

var fails := 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  ", label)
	else:
		fails += 1
		printerr("FAIL  ", label)

func _init() -> void:
	var cl = ChessLogicScript.new()

	# ── FEN round-trip ──
	var start = cl.new_game()
	check(cl.state_to_fen(start) == ChessLogicScript.STARTING_FEN, "startpos FEN round-trip")
	check(start.turn == ChessLogicScript.WHITE, "white to move at start")

	var mid_fen = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3"
	check(cl.state_to_fen(cl.parse_fen(mid_fen)) == mid_fen, "midgame FEN round-trip")

	# ── Move generation (perft node counts from the start position) ──
	check(cl.get_legal_moves(start).size() == 20, "20 legal moves at start")
	check(_perft(cl, start, 2) == 400, "perft(2) == 400")
	check(_perft(cl, start, 3) == 8902, "perft(3) == 8902")

	# ── Applying a move flips the side and updates the board ──
	var e4 = cl.uci_to_move(start, "e2e4")
	check(not e4.is_empty(), "e2e4 is legal")
	var after = cl.apply_move(start, e4)
	check(after.turn == ChessLogicScript.BLACK, "turn flips to black after e4")
	check(cl.get_legal_moves(after).size() == 20, "20 legal replies to e4")
	check(cl.move_to_uci(e4) == "e2e4", "move_to_uci round-trip")

	# ── Checkmate detection (Fool's mate — white is mated) ──
	var mated = cl.parse_fen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")
	var st = cl.get_status(mated)
	check(st["game_over"] and st["result"] == "0-1", "Fool's mate detected as 0-1")
	check(st.get("in_check", false), "mated side is in check")

	# ── Stalemate detection (not in check, no legal moves -> draw) ──
	var stale = cl.parse_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
	var ss = cl.get_status(stale)
	check(ss["game_over"] and ss["result"] == "1/2-1/2", "stalemate detected as draw")
	check(not ss.get("in_check", true), "stalemated side is NOT in check")

	# ── Promotion moves are generated ──
	var promo = cl.parse_fen("8/P7/8/8/8/8/8/k6K w - - 0 1")
	var promos = cl.get_legal_moves(promo).filter(func(m): return int(m.get("promotion", 0)) != 0)
	check(promos.size() == 4, "four promotion options for a7-a8")

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _perft(cl, state, depth: int) -> int:
	if depth == 0:
		return 1
	var n := 0
	for mv in cl.get_legal_moves(state):
		n += _perft(cl, cl.apply_move(state, mv), depth - 1)
	return n
