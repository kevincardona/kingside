class_name VoiceMoveParser

const CHESS_LOGIC_SCRIPT = preload("res://scripts/autoload/ChessLogic.gd")
const PAWN = 1
const KNIGHT = 2
const BISHOP = 3
const ROOK = 4
const QUEEN = 5
const KING = 6

const PIECE_WORDS = {
	"pawn": PAWN,
	"piece": PAWN,
	"knight": KNIGHT,
	"night": KNIGHT,
	"nite": KNIGHT,
	"horse": KNIGHT,
	"bishop": BISHOP,
	"rook": ROOK,
	"castle": ROOK,
	"queen": QUEEN,
	"king": KING,
}

const FILE_WORDS = {
	"a": "a", "ay": "a", "hey": "a",
	"b": "b", "bee": "b", "be": "b",
	"c": "c", "see": "c", "sea": "c",
	"d": "d", "dee": "d",
	"e": "e", "ee": "e",
	"f": "f", "eff": "f",
	"g": "g", "gee": "g",
	"h": "h", "aitch": "h", "eightch": "h",
}

const RANK_WORDS = {
	"1": "1", "one": "1", "won": "1",
	"2": "2", "two": "2", "too": "2", "to": "2",
	"3": "3", "three": "3", "tree": "3",
	"4": "4", "four": "4", "for": "4",
	"5": "5", "five": "5",
	"6": "6", "six": "6",
	"7": "7", "seven": "7",
	"8": "8", "eight": "8", "ate": "8",
}

static var _fallback_logic: Node = null

static func _logic() -> Node:
	var loop = Engine.get_main_loop()
	if loop and loop.root:
		var autoload = loop.root.get_node_or_null("ChessLogic")
		if autoload:
			return autoload
	if _fallback_logic == null:
		_fallback_logic = CHESS_LOGIC_SCRIPT.new()
	return _fallback_logic

static func parse(text: String, state, player_color: int) -> Dictionary:
	var normalized = _normalize(text)
	if normalized == "":
		return _fail("Say a move like knight to f3 or e2 e4.")
	var legal = _logic().get_legal_moves(state)
	if legal.is_empty():
		return _fail("No legal moves are available.")
	if state.turn != player_color:
		return _fail("It is not your turn.")

	var castle = _parse_castle(normalized, legal)
	if castle.get("ok", false):
		return castle

	var tokens = normalized.split(" ", false)
	var piece = _piece_from_tokens(tokens)
	var promo = _promotion_from_tokens(tokens)
	var squares = _extract_squares(tokens)
	var from_sq = _source_square(tokens)

	if squares.size() >= 2:
		from_sq = squares[0]
		return _match_move(state, legal, from_sq, squares[1], piece, promo)
	if squares.size() == 1:
		return _match_move(state, legal, from_sq, squares[0], piece, promo)
	if piece != 0 and _wants_capture(tokens):
		return _match_capture(state, legal, piece, promo)

	var san_move = _parse_san_like(normalized, state, legal)
	if san_move.get("ok", false):
		return san_move
	return _fail("I heard '%s', but could not find a square." % text.strip_edges())

# Strict variant used to commit moves from PARTIAL transcripts the instant
# they become unambiguous ("pawn a2 to a3" moves without waiting for the
# recognizer's silence timeout). Only explicit two-square phrasings or fully
# specified castling are accepted here, so a half-finished sentence can never
# trigger the wrong move; everything else waits for the final transcript.
static func parse_strict(text: String, state, player_color: int) -> Dictionary:
	var normalized = _normalize(text)
	if normalized == "" or state.turn != player_color:
		return _fail("")
	var legal = _logic().get_legal_moves(state)
	if legal.is_empty():
		return _fail("")
	if normalized.contains("castle") or normalized.contains("castling"):
		var has_side = normalized.contains("king") or normalized.contains("short") \
			or normalized.contains("queen") or normalized.contains("long")
		if not has_side:
			return _fail("")
		return _parse_castle(normalized, legal)
	var tokens = normalized.split(" ", false)
	var squares = _extract_squares(tokens)
	var piece = _piece_from_tokens(tokens)
	if squares.size() == 1 and piece != 0:
		var promo = _promotion_from_tokens(tokens)
		return _match_move(state, legal, -1, squares[0], piece, promo)
	if squares.size() == 1:
		return _match_move(state, legal, -1, squares[0], 0, 0)
	if squares.size() < 2:
		if piece != 0 and _wants_capture(tokens):
			var promo = _promotion_from_tokens(tokens)
			return _match_capture(state, legal, piece, promo)
		return _fail("")
	var promo = _promotion_from_tokens(tokens)
	return _match_move(state, legal, squares[0], squares[1], piece, promo)

# Hands-free game commands. Returns "" when the text is not a command.
static func parse_command(text: String) -> String:
	var t = " " + _normalize(text) + " "
	if t.contains("stop listening") or t.contains("stop voice") or t.contains("voice off") \
			or t.contains(" mic off ") or t.contains(" microphone off "):
		return "stop"
	if t.contains("take back") or t.contains("takeback") or t.contains(" undo ") \
			or t.contains(" go back ") or t.contains("back one") or t.contains("back 1"):
		return "undo"
	if t.contains(" hint ") or t.contains("help me") or t.contains(" clue ") \
			or t.contains(" show hint ") or t.contains(" best "):
		return "hint"
	if t.contains("flip board") or t.contains("rotate board"):
		return "flip"
	if t.contains("show spaces") or t.contains("show squares") \
			or t.contains("show coordinates") or t.contains("show coords"):
		return "show_spaces"
	return ""

static func parse_single_square(text: String) -> int:
	var normalized = _normalize(text)
	if normalized == "":
		return -1
	var squares = _extract_squares(normalized.split(" ", false))
	if squares.size() == 1:
		return int(squares[0])
	return -1

static func display_text(text: String) -> String:
	return _normalize(text)

static func describe_move(move: Dictionary) -> String:
	if move.is_empty(): return ""
	var from_name = _logic().sq_name(int(move.get("from", -1)))
	var to_name = _logic().sq_name(int(move.get("to", -1)))
	if int(move.get("promotion", 0)) != 0:
		return "%s to %s, promote to %s" % [from_name, to_name, _piece_name(int(move["promotion"]))]
	return "%s to %s" % [from_name, to_name]

static func _normalize(text: String) -> String:
	var out = text.to_lower().strip_edges()
	var replacements = {
		"-": " ", "_": " ", ".": " ", ",": " ", ":": " ", ";": " ",
		"!": " ", "?": " ", "'s": " ",
		"capture": " takes ", "captures": " takes ",
		"move": " ", "please": " ", "the": " ", "my": " ",
		"promote into": " promote to ", "promotes to": " promote to ",
		"king side": " kingside ", "queen side": " queenside ",
	}
	for key in replacements.keys():
		out = out.replace(key, replacements[key])
	while out.contains("  "):
		out = out.replace("  ", " ")
	# Token-level cleanup: speech recognizers love homophones.
	var fixed = PackedStringArray()
	for token in out.split(" ", false):
		var t: String = _HOMOPHONES.get(token, token)
		# "a three" is often transcribed as the number "83" (the file letter 'a'
		# heard as 'eight'). A bare two-digit token is never a valid square, so
		# remapping 8<rank> -> a<rank> can only rescue an otherwise-dead phrase.
		if t.length() == 2 and t[0] == "8" and t[1] >= "1" and t[1] <= "8":
			t = "a" + t.substr(1, 1)
		fixed.append(t)
	return " ".join(fixed).strip_edges()

# Common mis-hearings from SFSpeechRecognizer for chess vocabulary.
const _HOMOPHONES = {
	"x": "takes", "takes": "takes",
	"porn": "pawn", "pond": "pawn", "ponda": "pawn", "honda": "pawn",
	"prawn": "pawn", "upon": "pawn", "pwn": "pawn", "spawn": "pawn", "born": "pawn",
	"rock": "rook", "brook": "rook", "rookie": "rook", "ruck": "rook",
	"night": "knight", "nite": "knight", "knights": "knight",
	"vichop": "bishop", "bishops": "bishop",
	"clean": "queen", "queens": "queen", "green": "queen",
	"kings": "king",
	"before": "b4", "befour": "b4",
	"ceefor": "c4", "seafour": "c4",
	"defore": "d4",
	"ifor": "e4",
	"hate": "h8", "age": "h",
	"too": "2", "to2": "2",
	"won": "1", "one": "1", "two": "2", "three": "3", "tree": "3",
	"four": "4", "for": "4", "five": "5", "six": "6", "seven": "7",
	"eight": "8", "ate": "8",
}

static func _parse_castle(text: String, legal: Array) -> Dictionary:
	if not (text.contains("castle") or text.contains("castles") or text.contains("castling")):
		return {}
	var want = "kingside"
	if text.contains("queen") or text.contains("long") or text.contains("queenside"):
		want = "queenside"
	for move in legal:
		if str(move.get("castle", "")) == want:
			return _ok(move)
	return _fail("Castling %s is not legal here." % want)

static func _piece_from_tokens(tokens: PackedStringArray) -> int:
	for token in tokens:
		# Piece words after "promote" name the promotion target, not the mover.
		if token in ["promote", "promotion", "promoting"]:
			break
		if PIECE_WORDS.has(token):
			return int(PIECE_WORDS[token])
	return 0

static func _promotion_from_tokens(tokens: PackedStringArray) -> int:
	var promote_next = false
	for token in tokens:
		if token in ["promote", "promotion", "promoting"]:
			promote_next = true
			continue
		if promote_next and PIECE_WORDS.has(token):
			var pt = int(PIECE_WORDS[token])
			return pt if pt in [QUEEN, ROOK, BISHOP, KNIGHT] else 0
	return 0

static func _wants_capture(tokens: PackedStringArray) -> bool:
	for token in tokens:
		if token in ["takes", "take", "capture", "captures"]:
			return true
	return false

static func _extract_squares(tokens: PackedStringArray) -> Array:
	var squares = []
	for i in range(tokens.size()):
		var direct = _direct_square(tokens[i])
		if direct >= 0:
			squares.append(direct)
			continue
		for sq in _compact_squares(tokens[i]):
			squares.append(sq)
		if i + 1 < tokens.size():
			var file = FILE_WORDS.get(tokens[i], "")
			var rank = RANK_WORDS.get(tokens[i + 1], "")
			if file != "" and rank != "":
				squares.append(_logic().sq_from_name(file + rank))
	return _dedupe_valid_squares(squares)

static func _source_square(tokens: PackedStringArray) -> int:
	for i in range(tokens.size()):
		if tokens[i] != "from": continue
		if i + 1 < tokens.size():
			var direct = _direct_square(tokens[i + 1])
			if direct >= 0: return direct
		if i + 2 < tokens.size():
			var file = FILE_WORDS.get(tokens[i + 1], "")
			var rank = RANK_WORDS.get(tokens[i + 2], "")
			if file != "" and rank != "":
				return _logic().sq_from_name(file + rank)
	return -1

static func _direct_square(token: String) -> int:
	if token.length() == 2:
		return _logic().sq_from_name(token)
	if token.length() == 3 and token.begins_with("to"):
		return _logic().sq_from_name(token.substr(1, 2))
	if token.length() == 3 and token.begins_with("2"):
		return _logic().sq_from_name(token.substr(1, 2))
	return -1

static func _compact_squares(token: String) -> Array:
	var out = []
	if token.length() < 4: return out
	for c in token:
		if not ((c >= "a" and c <= "h") or (c >= "1" and c <= "8")):
			return out
	for i in range(token.length() - 1):
		var sq_name = token.substr(i, 2)
		var sq = _logic().sq_from_name(sq_name)
		if sq >= 0:
			out.append(sq)
	return out

static func _dedupe_valid_squares(values: Array) -> Array:
	var out = []
	var seen = {}
	for sq in values:
		if sq < 0 or seen.has(sq): continue
		seen[sq] = true
		out.append(sq)
	return out

static func _match_move(state, legal: Array, from_sq: int, to_sq: int, piece: int, promo: int) -> Dictionary:
	var matches = []
	for move in legal:
		if to_sq >= 0 and int(move.get("to", -1)) != to_sq: continue
		if from_sq >= 0 and int(move.get("from", -1)) != from_sq: continue
		if piece != 0 and abs(state.board[int(move.get("from", -1))]) != piece: continue
		if promo != 0 and int(move.get("promotion", 0)) != promo: continue
		matches.append(move)
	if matches.size() == 1:
		return _ok(matches[0])
	# Promotions: "e7 to e8" without naming a piece defaults to a queen.
	if matches.size() > 1 and promo == 0:
		var same_path = true
		for move in matches:
			if int(move.get("promotion", 0)) == 0 \
				or int(move["from"]) != int(matches[0]["from"]) \
				or int(move["to"]) != int(matches[0]["to"]):
				same_path = false
				break
		if same_path:
			for move in matches:
				if int(move.get("promotion", 0)) == QUEEN:
					return _ok(move)
	if matches.size() > 1:
		var examples = PackedStringArray()
		for move in matches.slice(0, mini(3, matches.size())):
			examples.append(describe_move(move))
		return _fail("That is ambiguous. Try %s." % ", ".join(examples), matches)
	return _fail("That move is not legal.")

static func _match_capture(state, legal: Array, piece: int, promo: int) -> Dictionary:
	var matches = []
	for move in legal:
		var from_sq = int(move.get("from", -1))
		var to_sq = int(move.get("to", -1))
		if from_sq < 0 or to_sq < 0: continue
		if abs(state.board[from_sq]) != piece: continue
		if promo != 0 and int(move.get("promotion", 0)) != promo: continue
		if state.board[to_sq] == 0 and not move.get("ep", false): continue
		matches.append(move)
	if matches.size() == 1:
		return _ok(matches[0])
	if matches.size() > 1:
		var examples = PackedStringArray()
		for move in matches.slice(0, mini(3, matches.size())):
			examples.append(describe_move(move))
		return _fail("That capture is ambiguous. Try %s." % ", ".join(examples), matches)
	return _fail("That capture is not legal.")

static func _parse_san_like(text: String, state, legal: Array) -> Dictionary:
	var compact = text.replace(" ", "")
	if compact.length() < 2:
		return {}
	var target = _logic().sq_from_name(compact.substr(compact.length() - 2, 2))
	if target < 0:
		return {}
	var piece = 0
	match compact.substr(0, 1):
		"n": piece = KNIGHT
		"b": piece = BISHOP
		"r": piece = ROOK
		"q": piece = QUEEN
		"k": piece = KING
	return _match_move(state, legal, -1, target, piece, 0)

static func _piece_name(piece: int) -> String:
	match piece:
		QUEEN: return "queen"
		ROOK: return "rook"
		BISHOP: return "bishop"
		KNIGHT: return "knight"
		KING: return "king"
		_: return "pawn"

static func _ok(move: Dictionary) -> Dictionary:
	return {"ok": true, "move": move}

static func _fail(message: String, candidates: Array = []) -> Dictionary:
	return {"ok": false, "message": message, "candidates": candidates}
