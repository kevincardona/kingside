extends Node
# Headless smoke test for PuzzleManager. Run with:
#   godot --headless res://test_puzzles.tscn

func _ready() -> void:
	var failures = 0
	print("levels=", PuzzleManager.levels.size(), " pool=", PuzzleManager.pool.size())
	if PuzzleManager.levels.size() < 12: failures += 1; print("FAIL: expected >= 12 levels")
	if PuzzleManager.pool.size() < 200: failures += 1; print("FAIL: pool too small")

	# Replay every bundled puzzle's full solution through ChessLogic.
	# Levels and pool are both raw rows now; normalize each (also exercises the
	# lazy normalization path the game uses at play time).
	var raw_rows = []
	for lv in PuzzleManager.levels: raw_rows += lv["puzzles"]
	raw_rows += PuzzleManager.pool
	var all = []
	for raw in raw_rows:
		var norm = PuzzleManager._normalize_csv_row(raw)
		if norm.is_empty():
			failures += 1
			print("FAIL: row failed to normalize ", raw.get("id", "?"))
		else:
			all.append(norm)
	for p in all:
		var state = ChessLogic.parse_fen(p["fen"])
		for uci in p["solution"]:
			var mv = ChessLogic.uci_to_move(state, uci)
			if mv.is_empty():
				failures += 1
				print("FAIL: illegal solution move ", uci, " in puzzle ", p["id"])
				break
			state = ChessLogic.apply_move(state, mv)
	print("replayed ", all.size(), " puzzles")

	# Progression gates (star-based): level 0 is always open; a later level with
	# a positive star threshold must be locked at zero total stars.
	if not PuzzleManager.is_level_unlocked(0): failures += 1; print("FAIL: level 0 locked")
	var gated = -1
	for i in PuzzleManager.levels.size():
		if PuzzleManager.level_unlock_stars(i) > 0: gated = i; break
	if gated >= 0 and PuzzleManager.total_stars() == 0 and PuzzleManager.is_level_unlocked(gated):
		failures += 1; print("FAIL: star-gated level %d should be locked at 0 stars" % gated)

	# Offline fallbacks
	var near = PuzzleManager._pool_near_rating()
	if near.is_empty(): failures += 1; print("FAIL: pool_near_rating empty")
	PuzzleManager._daily_fallback()
	if PuzzleManager.daily_cache.get("puzzle", {}).is_empty(): failures += 1; print("FAIL: daily fallback empty")

	# Online daily (best effort — passes either way, just reports)
	PuzzleManager.daily_cache = {}
	PuzzleManager.daily_loaded.connect(func(p2, net): print("daily_loaded from_network=", net, " id=", p2.get("id")))
	PuzzleManager.request_daily()
	await get_tree().create_timer(6.0).timeout

	print("RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
