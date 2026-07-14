extends Node

const EMPTY  = 0
const PAWN   = 1
const KNIGHT = 2
const BISHOP = 3
const ROOK   = 4
const QUEEN  = 5
const KING   = 6

const WHITE =  1
const BLACK = -1

const STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

# ──────────────────────────────────────────────
#  GameState
# ──────────────────────────────────────────────
class GameState:
	var board: Array        # 64 ints, board[rank*8+file]
	var turn: int           # WHITE or BLACK
	var castling: Array     # [wk, wq, bk, bq] bools
	var ep_square: int      # -1 or en-passant target square
	var halfmove: int
	var fullmove: int

	func _init() -> void:
		board = []
		board.resize(64)
		board.fill(0)
		turn      = WHITE
		castling  = [true, true, true, true]
		ep_square = -1
		halfmove  = 0
		fullmove  = 1

	func copy() -> GameState:
		var s         = GameState.new()
		s.board       = board.duplicate()
		s.turn        = turn
		s.castling    = castling.duplicate()
		s.ep_square   = ep_square
		s.halfmove    = halfmove
		s.fullmove    = fullmove
		return s

# ──────────────────────────────────────────────
#  Square helpers
# ──────────────────────────────────────────────
func sq(file: int, rank: int) -> int:       return rank * 8 + file
func file_of(s: int) -> int:               return s % 8
func rank_of(s: int) -> int:               return s / 8
func valid_sq(s: int) -> bool:             return s >= 0 and s < 64
func piece_color(p: int) -> int:
	if p > 0: return WHITE
	if p < 0: return BLACK
	return 0

func sq_name(s: int) -> String:
	return String.chr(97 + file_of(s)) + str(rank_of(s) + 1)

func sq_from_name(name: String) -> int:
	if name.length() != 2: return -1
	var f = name.unicode_at(0) - 97
	var r = name.unicode_at(1) - 49
	if f < 0 or f > 7 or r < 0 or r > 7: return -1
	return sq(f, r)

# ──────────────────────────────────────────────
#  FEN
# ──────────────────────────────────────────────
func new_game() -> GameState:
	return parse_fen(STARTING_FEN)

func parse_fen(fen: String) -> GameState:
	var state = GameState.new()
	var parts = fen.split(" ")
	if parts.size() < 4: return state

	var rows = parts[0].split("/")
	var rank  = 7
	for row in rows:
		var file = 0
		for c in row:
			if c >= "1" and c <= "8":
				file += c.to_int()
			else:
				state.board[sq(file, rank)] = _fen_char_to_piece(c)
				file += 1
		rank -= 1

	state.turn        = WHITE if parts[1] == "w" else BLACK
	var cs            = parts[2]
	state.castling    = [cs.contains("K"), cs.contains("Q"), cs.contains("k"), cs.contains("q")]
	state.ep_square   = sq_from_name(parts[3]) if parts[3] != "-" else -1
	if parts.size() > 4: state.halfmove  = parts[4].to_int()
	if parts.size() > 5: state.fullmove  = parts[5].to_int()
	return state

func state_to_fen(state: GameState) -> String:
	var fen = ""
	for rank in range(7, -1, -1):
		var empty = 0
		for file in 8:
			var p = state.board[sq(file, rank)]
			if p == 0:
				empty += 1
			else:
				if empty > 0: fen += str(empty); empty = 0
				fen += _piece_to_fen_char(p)
		if empty > 0: fen += str(empty)
		if rank > 0:  fen += "/"

	fen += " " + ("w" if state.turn == WHITE else "b")
	var c = ("K" if state.castling[0] else "") + ("Q" if state.castling[1] else "") + \
			("k" if state.castling[2] else "") + ("q" if state.castling[3] else "")
	fen += " " + (c if c != "" else "-")
	fen += " " + (sq_name(state.ep_square) if state.ep_square >= 0 else "-")
	fen += " " + str(state.halfmove) + " " + str(state.fullmove)
	return fen

func _fen_char_to_piece(c: String) -> int:
	var table = {
		"P":  PAWN,   "N":  KNIGHT, "B":  BISHOP,
		"R":  ROOK,   "Q":  QUEEN,  "K":  KING,
		"p": -PAWN,   "n": -KNIGHT, "b": -BISHOP,
		"r": -ROOK,   "q": -QUEEN,  "k": -KING,
	}
	return table.get(c, EMPTY)

func _piece_to_fen_char(p: int) -> String:
	var chars = {PAWN: "P", KNIGHT: "N", BISHOP: "B", ROOK: "R", QUEEN: "Q", KING: "K"}
	var c = chars.get(abs(p), "")
	return c if p > 0 else c.to_lower()

# ──────────────────────────────────────────────
#  Move generation
# ──────────────────────────────────────────────
# Move dictionary keys: from, to, promotion(int), ep(bool), castle(String)

func generate_pseudo_legal_moves(state: GameState) -> Array:
	var moves = []
	for from_sq in 64:
		var p = state.board[from_sq]
		if p == 0 or piece_color(p) != state.turn: continue
		match abs(p):
			PAWN:   _gen_pawn(state, from_sq, state.turn, moves)
			KNIGHT: _gen_knight(state, from_sq, state.turn, moves)
			BISHOP: _gen_sliding(state, from_sq, state.turn, [[-1,-1],[-1,1],[1,-1],[1,1]], moves)
			ROOK:   _gen_sliding(state, from_sq, state.turn, [[-1,0],[1,0],[0,-1],[0,1]], moves)
			QUEEN:  _gen_sliding(state, from_sq, state.turn,
					[[-1,-1],[-1,1],[1,-1],[1,1],[-1,0],[1,0],[0,-1],[0,1]], moves)
			KING:   _gen_king(state, from_sq, state.turn, moves)
	return moves

func _gen_pawn(state: GameState, from_sq: int, color: int, moves: Array) -> void:
	var f    = file_of(from_sq)
	var r    = rank_of(from_sq)
	var dir  = color
	var home = 1 if color == WHITE else 6
	var promo_r = 7 if color == WHITE else 0

	var fwd = sq(f, r + dir)
	if valid_sq(fwd) and state.board[fwd] == EMPTY:
		_add_pawn_move(from_sq, fwd, rank_of(fwd) == promo_r, moves)
		if r == home:
			var fwd2 = sq(f, r + dir * 2)
			if state.board[fwd2] == EMPTY:
				moves.append({"from": from_sq, "to": fwd2, "promotion": 0})

	for df in [-1, 1]:
		var cf = f + df
		if cf < 0 or cf > 7: continue
		var cap = sq(cf, r + dir)
		if not valid_sq(cap): continue
		var target = state.board[cap]
		if target != EMPTY and piece_color(target) != color:
			_add_pawn_move(from_sq, cap, rank_of(cap) == promo_r, moves)
		if cap == state.ep_square:
			moves.append({"from": from_sq, "to": cap, "promotion": 0, "ep": true})

func _add_pawn_move(from_sq: int, to_sq: int, is_promo: bool, moves: Array) -> void:
	if is_promo:
		for promo in [QUEEN, ROOK, BISHOP, KNIGHT]:
			moves.append({"from": from_sq, "to": to_sq, "promotion": promo})
	else:
		moves.append({"from": from_sq, "to": to_sq, "promotion": 0})

func _gen_knight(state: GameState, from_sq: int, color: int, moves: Array) -> void:
	var f = file_of(from_sq)
	var r = rank_of(from_sq)
	for off in [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]]:
		var nf = f + off[0]; var nr = r + off[1]
		if nf < 0 or nf > 7 or nr < 0 or nr > 7: continue
		var to_sq = sq(nf, nr)
		if state.board[to_sq] == EMPTY or piece_color(state.board[to_sq]) != color:
			moves.append({"from": from_sq, "to": to_sq, "promotion": 0})

func _gen_sliding(state: GameState, from_sq: int, color: int, dirs: Array, moves: Array) -> void:
	var f = file_of(from_sq); var r = rank_of(from_sq)
	for dir in dirs:
		var cf = f + dir[0]; var cr = r + dir[1]
		while cf >= 0 and cf <= 7 and cr >= 0 and cr <= 7:
			var to_sq = sq(cf, cr)
			var target = state.board[to_sq]
			if target == EMPTY:
				moves.append({"from": from_sq, "to": to_sq, "promotion": 0})
			elif piece_color(target) != color:
				moves.append({"from": from_sq, "to": to_sq, "promotion": 0}); break
			else: break
			cf += dir[0]; cr += dir[1]

func _gen_king(state: GameState, from_sq: int, color: int, moves: Array) -> void:
	var f = file_of(from_sq); var r = rank_of(from_sq)
	for df in [-1, 0, 1]:
		for dr in [-1, 0, 1]:
			if df == 0 and dr == 0: continue
			var nf = f + df; var nr = r + dr
			if nf < 0 or nf > 7 or nr < 0 or nr > 7: continue
			var to_sq = sq(nf, nr)
			if state.board[to_sq] == EMPTY or piece_color(state.board[to_sq]) != color:
				moves.append({"from": from_sq, "to": to_sq, "promotion": 0})

	# Castling
	var back_rank = 0 if color == WHITE else 7
	var king_home = sq(4, back_rank)
	if from_sq != king_home: return
	var ci_k = 0 if color == WHITE else 2  # castling index kingside
	var ci_q = 1 if color == WHITE else 3

	if state.castling[ci_k]:
		if state.board[sq(5, back_rank)] == EMPTY and state.board[sq(6, back_rank)] == EMPTY:
			moves.append({"from": from_sq, "to": sq(6, back_rank), "promotion": 0,
						  "castle": ("wk" if color == WHITE else "bk")})
	if state.castling[ci_q]:
		if state.board[sq(3, back_rank)] == EMPTY and \
		   state.board[sq(2, back_rank)] == EMPTY and \
		   state.board[sq(1, back_rank)] == EMPTY:
			moves.append({"from": from_sq, "to": sq(2, back_rank), "promotion": 0,
						  "castle": ("wq" if color == WHITE else "bq")})

# ──────────────────────────────────────────────
#  Attack detection
# ──────────────────────────────────────────────
func is_attacked(board: Array, target: int, by_color: int) -> bool:
	var f = file_of(target); var r = rank_of(target)

	# Knights
	for off in [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]]:
		var nf = f + off[0]; var nr = r + off[1]
		if nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7:
			if board[sq(nf, nr)] == by_color * KNIGHT: return true

	# Diagonals – bishop/queen
	for dir in [[-1,-1],[-1,1],[1,-1],[1,1]]:
		var cf = f + dir[0]; var cr = r + dir[1]
		while cf >= 0 and cf <= 7 and cr >= 0 and cr <= 7:
			var s = sq(cf, cr)
			if board[s] != EMPTY:
				if board[s] == by_color * BISHOP or board[s] == by_color * QUEEN: return true
				break
			cf += dir[0]; cr += dir[1]

	# Straights – rook/queen
	for dir in [[-1,0],[1,0],[0,-1],[0,1]]:
		var cf = f + dir[0]; var cr = r + dir[1]
		while cf >= 0 and cf <= 7 and cr >= 0 and cr <= 7:
			var s = sq(cf, cr)
			if board[s] != EMPTY:
				if board[s] == by_color * ROOK or board[s] == by_color * QUEEN: return true
				break
			cf += dir[0]; cr += dir[1]

	# King
	for df in [-1, 0, 1]:
		for dr in [-1, 0, 1]:
			if df == 0 and dr == 0: continue
			var nf = f + df; var nr = r + dr
			if nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7:
				if board[sq(nf, nr)] == by_color * KING: return true

	# Pawns – by_color pawn at rank (r - by_color) attacks target
	var pr = r - by_color
	if pr >= 0 and pr <= 7:
		for df in [-1, 1]:
			var pf = f + df
			if pf >= 0 and pf <= 7:
				if board[sq(pf, pr)] == by_color * PAWN: return true

	return false

func find_king(board: Array, color: int) -> int:
	var king = color * KING
	for i in 64:
		if board[i] == king: return i
	return -1

# ──────────────────────────────────────────────
#  Legal move filter
# ──────────────────────────────────────────────
func get_legal_moves(state: GameState) -> Array:
	var pseudo = generate_pseudo_legal_moves(state)
	var legal  = []
	for move in pseudo:
		if move.get("castle", "") != "" and not _castle_valid(state, move): continue
		var after    = apply_move(state, move)
		var king_sq  = find_king(after.board, state.turn)
		if king_sq >= 0 and not is_attacked(after.board, king_sq, -state.turn):
			legal.append(move)
	return legal

func get_legal_moves_from(state: GameState, from_sq: int) -> Array:
	var all = get_legal_moves(state)
	var result = []
	for m in all:
		if m["from"] == from_sq: result.append(m)
	return result

func _castle_valid(state: GameState, move: Dictionary) -> bool:
	var color  = state.turn
	var enemy  = -color
	var king_sq = find_king(state.board, color)
	if is_attacked(state.board, king_sq, enemy): return false

	var castle = move.get("castle", "")
	var back   = 0 if color == WHITE else 7
	var pass_sq = {
		"wk": sq(5, 0), "wq": sq(3, 0),
		"bk": sq(5, 7), "bq": sq(3, 7)
	}
	var s = pass_sq.get(castle, -1)
	if s >= 0 and is_attacked(state.board, s, enemy): return false
	return true

# ──────────────────────────────────────────────
#  Apply move
# ──────────────────────────────────────────────
func apply_move(state: GameState, move: Dictionary) -> GameState:
	var ns      = state.copy()
	var from_sq = move["from"]
	var to_sq   = move["to"]
	var piece   = ns.board[from_sq]
	var color   = piece_color(piece)
	var pt      = abs(piece)

	var is_cap  = ns.board[to_sq] != EMPTY or move.get("ep", false)
	ns.halfmove = 0 if (pt == PAWN or is_cap) else ns.halfmove + 1

	ns.board[to_sq]   = piece
	ns.board[from_sq] = EMPTY

	if move.get("promotion", 0) != 0:
		ns.board[to_sq] = color * move["promotion"]

	if move.get("ep", false):
		ns.board[sq(file_of(to_sq), rank_of(from_sq))] = EMPTY

	var castle = move.get("castle", "")
	if castle == "wk":
		ns.board[sq(5,0)] = WHITE * ROOK; ns.board[sq(7,0)] = EMPTY
	elif castle == "wq":
		ns.board[sq(3,0)] = WHITE * ROOK; ns.board[sq(0,0)] = EMPTY
	elif castle == "bk":
		ns.board[sq(5,7)] = BLACK * ROOK; ns.board[sq(7,7)] = EMPTY
	elif castle == "bq":
		ns.board[sq(3,7)] = BLACK * ROOK; ns.board[sq(0,7)] = EMPTY

	# Update castling rights
	if pt == KING:
		if color == WHITE: ns.castling[0] = false; ns.castling[1] = false
		else:              ns.castling[2] = false; ns.castling[3] = false
	if pt == ROOK:
		if from_sq == sq(7,0): ns.castling[0] = false
		elif from_sq == sq(0,0): ns.castling[1] = false
		elif from_sq == sq(7,7): ns.castling[2] = false
		elif from_sq == sq(0,7): ns.castling[3] = false

	# Update castling rights when rook is captured
	if to_sq == sq(7,0): ns.castling[0] = false
	elif to_sq == sq(0,0): ns.castling[1] = false
	elif to_sq == sq(7,7): ns.castling[2] = false
	elif to_sq == sq(0,7): ns.castling[3] = false

	# En passant square
	ns.ep_square = -1
	if pt == PAWN and abs(rank_of(to_sq) - rank_of(from_sq)) == 2:
		ns.ep_square = sq(file_of(from_sq), (rank_of(from_sq) + rank_of(to_sq)) / 2)

	ns.turn = -color
	if color == BLACK: ns.fullmove += 1
	return ns

# ──────────────────────────────────────────────
#  Game status
# ──────────────────────────────────────────────
func get_status(state: GameState) -> Dictionary:
	var legal   = get_legal_moves(state)
	var king_sq = find_king(state.board, state.turn)
	var in_check = king_sq >= 0 and is_attacked(state.board, king_sq, -state.turn)

	var status = {
		"legal_moves": legal,
		"in_check": in_check,
		"game_over": false,
		"result": "",     # "1-0" | "0-1" | "1/2-1/2"
		"reason": ""      # "checkmate" | "stalemate" | "50-move" | "insufficient"
	}

	if legal.is_empty():
		status["game_over"] = true
		if in_check:
			status["result"] = "0-1" if state.turn == WHITE else "1-0"
			status["reason"] = "checkmate"
		else:
			status["result"] = "1/2-1/2"
			status["reason"] = "stalemate"
	elif state.halfmove >= 100:
		status["game_over"] = true
		status["result"] = "1/2-1/2"
		status["reason"] = "50-move rule"
	elif _insufficient_material(state):
		status["game_over"] = true
		status["result"] = "1/2-1/2"
		status["reason"] = "insufficient material"

	return status

func _insufficient_material(state: GameState) -> bool:
	var wp = []; var bp = []
	for i in 64:
		var p = state.board[i]
		if p == 0 or abs(p) == KING: continue
		if p > 0: wp.append(abs(p))
		else: bp.append(abs(p))
	if wp.is_empty() and bp.is_empty(): return true
	if wp.is_empty() and bp.size() == 1: return bp[0] in [KNIGHT, BISHOP]
	if bp.is_empty() and wp.size() == 1: return wp[0] in [KNIGHT, BISHOP]
	return false

# ──────────────────────────────────────────────
#  UCI helpers
# ──────────────────────────────────────────────
func move_to_uci(move: Dictionary) -> String:
	var uci = sq_name(move["from"]) + sq_name(move["to"])
	var promo_chars = {QUEEN: "q", ROOK: "r", BISHOP: "b", KNIGHT: "n"}
	if move.get("promotion", 0) != 0:
		uci += promo_chars.get(move["promotion"], "q")
	return uci

func uci_to_move(state: GameState, uci: String) -> Dictionary:
	for move in get_legal_moves(state):
		if move_to_uci(move) == uci: return move
	return {}

func move_to_san(state: GameState, move: Dictionary) -> String:
	if move.is_empty(): return ""
	var piece = state.board[move["from"]]
	if piece == 0: return move_to_uci(move)
	var color = piece_color(piece)
	var pt = abs(piece)
	if move.get("castle", "") in ["wk", "bk"]: return "O-O"
	if move.get("castle", "") in ["wq", "bq"]: return "O-O-O"

	var names = {KNIGHT: "N", BISHOP: "B", ROOK: "R", QUEEN: "Q", KING: "K"}
	var san = names.get(pt, "")
	var target = state.board[move["to"]]
	var is_capture = target != EMPTY or move.get("ep", false)

	if pt == PAWN:
		if is_capture:
			san += String.chr(97 + file_of(move["from"]))
	else:
		san += _san_disambiguation(state, move, pt, color)

	if is_capture: san += "x"
	san += sq_name(move["to"])

	if move.get("promotion", 0) != 0:
		san += "=" + names.get(move["promotion"], "Q")

	var after = apply_move(state, move)
	var status = get_status(after)
	if status["game_over"] and status["reason"] == "checkmate":
		san += "#"
	elif status["in_check"]:
		san += "+"
	return san

func _san_disambiguation(state: GameState, move: Dictionary, pt: int, color: int) -> String:
	var same_file = false
	var same_rank = false
	var ambiguous = false
	for other in get_legal_moves(state):
		if other["from"] == move["from"]: continue
		if other["to"] != move["to"]: continue
		var p = state.board[other["from"]]
		if abs(p) != pt or piece_color(p) != color: continue
		ambiguous = true
		if file_of(other["from"]) == file_of(move["from"]): same_file = true
		if rank_of(other["from"]) == rank_of(move["from"]): same_rank = true
	if not ambiguous: return ""
	if not same_file: return String.chr(97 + file_of(move["from"]))
	if not same_rank: return str(rank_of(move["from"]) + 1)
	return sq_name(move["from"])

# position hash for threefold-repetition (simplified Zobrist-free version)
func position_key(state: GameState) -> String:
	var key = ""
	for p in state.board: key += str(p) + ","
	key += str(state.turn) + str(state.castling) + str(state.ep_square)
	return key
