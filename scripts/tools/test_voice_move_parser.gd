extends SceneTree

const Parser = preload("res://scripts/ui/VoiceMoveParser.gd")
const ChessLogicScript = preload("res://scripts/autoload/ChessLogic.gd")
const WHITE = 1

var _logic_node: Node

func _init() -> void:
	_logic_node = ChessLogicScript.new()
	_logic_node.name = "ChessLogic"
	root.add_child(_logic_node)
	var state = _logic().new_game()
	_expect(state, "e two e four", "e2e4")
	_expect(state, "pawn to e4", "e2e4")
	_expect(state, "knight to f3", "g1f3")
	_expect(state, "night to c3", "b1c3")
	_expect(state, "b one to c three", "b1c3")
	_expect(state, "Pawn A2 to A3.", "a2a3")
	_expect(state, "pawn e2 to e4", "e2e4")
	_expect(state, "Porn a2 to a3", "a2a3")       # homophone: porn -> pawn
	_expect(state, "ponda e2 to e3", "e2e3")
	_expect(state, "honda to e3", "e2e3")
	_expect(state, "pond d2 2d3", "d2d3")         # speech often hears "to d3" as "2d3"
	_expect_fail(state, "rock a1")                 # rook cannot move to a1 here
	_expect_fail(state, "knight to e4")
	_expect_fail(state, "six")                     # "x" inside words must not corrupt parsing

	# Strict mode (partial transcripts): explicit from+to only
	_expect_strict(state, "pawn a2 to a3", "a2a3")
	_expect_strict(state, "e2 e4", "e2e4")
	_expect_strict(state, "pond d2 2d3", "d2d3")
	_expect_strict(state, "pawn to e4", "e2e4")    # piece + one legal target is enough
	_expect_strict(state, "ponda e2 to e3", "e2e3")
	_expect_strict(state, "honda to e3", "e2e3")
	_expect_strict(state, "knight f3", "g1f3")
	_expect_strict_fail(state, "castle")           # castle without a side -> wait
	_expect_strict_fail(state, "rook a1")          # piece + single square -> wait

	var bishop_state = _logic().parse_fen("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2")
	_expect(bishop_state, "bishop b5", "f1b5")
	_expect_strict(bishop_state, "bishop b5", "f1b5")

	var capture_state = _logic().parse_fen("4k3/5p2/8/8/2B5/8/8/4K3 w - - 0 1")
	_expect(capture_state, "bishop takes f7", "c4f7")
	_expect_strict(capture_state, "bishop takes f7", "c4f7")
	_expect(capture_state, "bishop takes", "c4f7")
	_expect_strict(capture_state, "bishop takes", "c4f7")

	var ambiguous_capture_state = _logic().parse_fen("4k3/5p2/8/1p6/2B5/8/8/4K3 w - - 0 1")
	_expect_fail(ambiguous_capture_state, "bishop takes")
	_expect_strict_fail(ambiguous_capture_state, "bishop takes")

	var single_target_state = _logic().parse_fen("4k3/8/8/8/4P3/8/8/4K3 w - - 0 1")
	_expect(single_target_state, "e5", "e4e5")
	_expect_strict(single_target_state, "e5", "e4e5")

	var ambiguous_target_state = _logic().parse_fen("4k3/8/8/8/2N1N3/8/8/4K3 w - - 0 1")
	_expect_fail(ambiguous_target_state, "d6")
	_expect_strict_fail(ambiguous_target_state, "d6")

	# Promotion auto-queen
	var promo_state = _logic().parse_fen("8/4P1k1/8/8/8/8/8/4K3 w - - 0 1")
	_expect(promo_state, "e7 to e8", "e7e8q")
	_expect(promo_state, "e7 to e8 promote to knight", "e7e8n")
	_expect_strict(promo_state, "e7 to e8 promote to rook", "e7e8r")

	var compact_state = _logic().parse_fen("4k3/8/8/8/8/8/8/3QK3 w - - 0 1")
	_expect(compact_state, "d12d5", "d1d5")
	_expect_strict(compact_state, "d12d5", "d1d5")

	# Single-square recognition for voice selection.
	_expect_square("d2", "d2")
	_expect_square("dee two", "d2")
	_expect_square("pawn d2", "d2")
	_expect_square("2d3", "d3")
	_expect_square_fail("d2 d4")
	_expect_display("honda to e3", "pawn to e3")
	_expect_display("ponda e2 to e3", "pawn e2 to e3")

	# Commands
	_expect_command("stop listening", "stop")
	_expect_command("please undo that", "undo")
	_expect_command("take back", "undo")
	_expect_command("go back", "undo")
	_expect_command("flip board", "flip")
	_expect_command("rotate board", "flip")
	_expect_command("show hint", "hint")
	_expect_command("best move", "hint")
	_expect_command("show spaces", "show_spaces")
	_expect_command("show coordinates", "show_spaces")
	_expect_command("knight to f3", "")

	print("voice parser tests passed")
	root.remove_child(_logic_node)
	_logic_node.free()
	quit(0)

func _expect_strict(state, text: String, uci: String) -> void:
	var parsed = Parser.parse_strict(text, state, WHITE)
	if not parsed.get("ok", false):
		push_error("Expected strict '%s' to parse as %s: %s" % [text, uci, parsed.get("message", "")])
		quit(1)
		return
	var got = _logic().move_to_uci(parsed["move"])
	if got != uci:
		push_error("Expected strict '%s' to parse as %s, got %s" % [text, uci, got])
		quit(1)

func _expect_strict_fail(state, text: String) -> void:
	var parsed = Parser.parse_strict(text, state, WHITE)
	if parsed.get("ok", false):
		push_error("Expected strict '%s' to fail, got %s" % [text, _logic().move_to_uci(parsed["move"])])
		quit(1)

func _expect_command(text: String, want: String) -> void:
	var got = Parser.parse_command(text)
	if got != want:
		push_error("Expected command '%s' -> '%s', got '%s'" % [text, want, got])
		quit(1)

func _expect_square(text: String, want: String) -> void:
	var got = Parser.parse_single_square(text)
	var want_sq = _logic().sq_from_name(want)
	if got != want_sq:
		push_error("Expected square '%s' -> '%s', got '%s'" % [text, want, _logic().sq_name(got)])
		quit(1)

func _expect_square_fail(text: String) -> void:
	var got = Parser.parse_single_square(text)
	if got >= 0:
		push_error("Expected square '%s' to fail, got '%s'" % [text, _logic().sq_name(got)])
		quit(1)

func _expect_display(text: String, want: String) -> void:
	var got = Parser.display_text(text)
	if got != want:
		push_error("Expected display '%s' -> '%s', got '%s'" % [text, want, got])
		quit(1)

func _expect(state, text: String, uci: String) -> void:
	var parsed = Parser.parse(text, state, WHITE)
	if not parsed.get("ok", false):
		push_error("Expected '%s' to parse as %s: %s" % [text, uci, parsed.get("message", "")])
		quit(1)
		return
	var got = _logic().move_to_uci(parsed["move"])
	if got != uci:
		push_error("Expected '%s' to parse as %s, got %s" % [text, uci, got])
		quit(1)

func _expect_fail(state, text: String) -> void:
	var parsed = Parser.parse(text, state, WHITE)
	if parsed.get("ok", false):
		push_error("Expected '%s' to fail, got %s" % [text, _logic().move_to_uci(parsed["move"])])
		quit(1)

func _logic() -> Node:
	return _logic_node
