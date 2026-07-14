extends Node
# Bot strength calibration harness (round-robin among the bot tiers).
#
# Run headless on a build WITH the native Stockfish extension:
#   <godot> --headless res://tools/calibrate_bots.tscn
#
# It plays every tier against every other, then prints each tier's score vs the
# field and an Elo estimate anchored so ANCHOR_TIER lands on its label. Use the
# output to set the DIFFICULTIES labels (and the UCI_OVERSHOOT_ANCHORS mapping in
# AIEngine) from measured data instead of guesses. Raise GAMES_PER_PAIR for
# tighter numbers (slower).

const TIERS := ["easy", "medium", "hard", "expert", "master"]
const ANCHOR_TIER := "medium"   # this tier's DIFFICULTIES["elo"] anchors the scale
const GAMES_PER_PAIR := 4
const MAX_PLIES := 160

func _ready() -> void:
	await get_tree().process_frame
	if not AIEngine.stockfish_available():
		print("CALIBRATE: native Stockfish unavailable — build the engine extension first.")
		get_tree().quit()
		return

	var score := {}
	var played := {}
	for t in TIERS:
		score[t] = 0.0
		played[t] = 0

	print("CALIBRATE: round-robin, %d games per pairing" % GAMES_PER_PAIR)
	for i in TIERS.size():
		for j in range(i + 1, TIERS.size()):
			var a: String = TIERS[i]
			var b: String = TIERS[j]
			for g in GAMES_PER_PAIR:
				var sa = _play(_cfg(a), _cfg(b), g % 2 == 0)
				score[a] += sa
				score[b] += 1.0 - sa
				played[a] += 1
				played[b] += 1
			print("  %s vs %s done" % [a, b])

	# Anchored Elo from score% vs the field: 400*log10(p/(1-p)), shifted so the
	# anchor tier matches its label.
	var raw := {}
	for t in TIERS:
		var p = clampf(score[t] / float(maxi(1, played[t])), 0.03, 0.97)
		raw[t] = 400.0 * (log(p / (1.0 - p)) / log(10.0))
	var shift = float(AIEngine.DIFFICULTIES[ANCHOR_TIER]["elo"]) - raw[ANCHOR_TIER]

	print("\nCALIBRATE RESULTS (label vs measured):")
	for t in TIERS:
		print("  %-8s label=%-5d  score=%3.0f%%  measured≈%d" % [
			t, int(AIEngine.DIFFICULTIES[t]["elo"]),
			100.0 * score[t] / float(maxi(1, played[t])),
			int(round(raw[t] + shift))])
	get_tree().quit()

func _cfg(tier: String) -> Dictionary:
	var c: Dictionary = AIEngine.DIFFICULTIES[tier].duplicate()
	c["allow_script_fallback"] = true
	c["use_book"] = false
	c["movetime_ms"] = min(int(c.get("movetime_ms", 200)), 250)
	return c

# Play one game; returns A's score (1.0 win / 0.5 draw / 0.0 loss).
func _play(a_cfg: Dictionary, b_cfg: Dictionary, a_white: bool) -> float:
	var state = ChessLogic.new_game()
	var plies := 0
	while plies < MAX_PLIES:
		if ChessLogic.get_legal_moves(state).is_empty():
			var reason = str(ChessLogic.get_status(state).get("reason", ""))
			if reason == "checkmate":
				var loser_is_white = state.turn == ChessLogic.WHITE
				var a_lost = (loser_is_white and a_white) or (not loser_is_white and not a_white)
				return 0.0 if a_lost else 1.0
			return 0.5   # stalemate / no legal moves
		var a_to_move = (state.turn == ChessLogic.WHITE) == a_white
		var mv = AIEngine._pick_move(state, a_cfg if a_to_move else b_cfg)
		if mv.is_empty():
			return 0.5
		state = ChessLogic.apply_move(state, mv)
		plies += 1
	return 0.5
