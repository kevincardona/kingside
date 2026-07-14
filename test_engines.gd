extends SceneTree
# Headless tests for EngineRegistry:
#   godot --headless -s res://test_engines.gd   → prints RESULT: PASS/FAIL
#
# Covers the bundled-catalogue load, unknown-id handling, net resolution, the
# install-a-pack (DATA) merge, the remote-catalog parse + net validation, and the
# self-consistency of the hosted docs/engines/catalog.json.
#
# The work runs in _process (not _init) and load()s EngineRegistry at runtime,
# because the script references the PlayerData autoload — its global name only
# resolves once the project's autoloads have been registered (after boot). A
# const preload here would try to compile EngineRegistry too early and fail.

var fails := 0
var _done := false

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  ", label)
	else:
		fails += 1
		printerr("FAIL  ", label)

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	var EngineRegistryScript = load("res://scripts/autoload/EngineRegistry.gd")
	var reg = EngineRegistryScript.new()

	# ── Bundled catalogue ──
	reg._load_bundled()
	check(reg.engines().size() >= 1, "bundled engines load")
	check(not reg.get_engine("stockfish18").is_empty(), "default engine resolves")
	check(reg.get_engine("does_not_exist").is_empty(), "unknown id returns empty")
	check(reg.get_engine("stockfish18").get("bundled", false) == true, "bundled flag set")

	# ── Net (DATA) resolution ──
	check(reg.resolve_net_path("") == "", "empty net → embedded default")
	check(reg.resolve_net_path("missing.nnue") == "", "missing net file → embedded default")

	# ── Install a DATA-only pack and confirm it merges in ──
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://engines"))
	var f = FileAccess.open("user://engines/test_pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"id": "test_pack", "name": "Test Pack", "engine": "stockfish", "net": "", "uci": {}}))
	f.close()
	reg._load_installed_packs()
	check(not reg.get_engine("test_pack").is_empty(), "installed pack merges in")
	check(reg.get_engine("test_pack").get("bundled", true) == false, "installed pack marked not bundled")

	# ── Catalog parsing (_extract_packs) ──
	var cat = {"version": 1, "packs": [
		{"id": "p1", "name": "P1", "net": "a.nnue", "net_url": "http://x/a.nnue"},
		{"id": "", "name": "no id"},     # skipped
		"not a dict",                    # skipped
	]}
	var packs = reg._extract_packs(cat)
	check(packs.size() == 1, "catalog extracts only valid packs")
	check(packs.size() == 1 and packs[0]["id"] == "p1", "extracted pack id correct")
	check(reg._extract_packs("garbage").is_empty(), "non-dict catalog → empty")

	# ── Net validation (_validate_net) ──
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://engines/nets"))
	var nf = FileAccess.open("user://engines/nets/probe.nnue", FileAccess.WRITE)
	nf.store_string("hello-net-bytes")
	nf.close()
	var sz = FileAccess.open("user://engines/nets/probe.nnue", FileAccess.READ).get_length()
	check(reg._validate_net("user://engines/nets/probe.nnue", {}) == "", "net with no expectations passes")
	check(reg._validate_net("user://engines/nets/probe.nnue", {"size_bytes": sz}) == "", "correct size passes")
	check(reg._validate_net("user://engines/nets/probe.nnue", {"size_bytes": sz + 1}) != "", "wrong size rejected")
	check(reg._validate_net("user://engines/nets/missing.nnue", {}) != "", "missing/empty net rejected")
	var real_sha = FileAccess.get_sha256("user://engines/nets/probe.nnue")
	check(reg._validate_net("user://engines/nets/probe.nnue", {"sha256": real_sha}) == "", "correct sha256 passes")
	check(reg._validate_net("user://engines/nets/probe.nnue", {"sha256": "deadbeef"}) != "", "wrong sha256 rejected")

	# ── Installed net resolves to a path ──
	var pf = FileAccess.open("user://engines/probe_pack.json", FileAccess.WRITE)
	pf.store_string(JSON.stringify({"id": "probe_pack", "name": "Probe", "engine": "stockfish", "net": "probe.nnue", "uci": {}}))
	pf.close()
	reg._load_installed_packs()
	check(not reg.get_engine("probe_pack").is_empty(), "net pack merges in")
	check(reg.resolve_net_path("probe.nnue") != "", "installed net resolves to a path")
	check(reg.resolve_net_path("nope.nnue") == "", "missing net stays embedded default")

	# ── Hosted catalog is valid + self-consistent ──
	var cf = FileAccess.open("res://docs/engines/catalog.json", FileAccess.READ)
	check(cf != null, "docs/engines/catalog.json exists")
	if cf != null:
		var hosted = reg._extract_packs(JSON.parse_string(cf.get_as_text()))
		check(hosted.size() >= 1, "hosted catalog has at least one pack")
		for p in hosted:
			var net_name = String(p.get("net", ""))
			check(net_name != "" and FileAccess.file_exists("res://docs/engines/nets/" + net_name),
				"hosted net file present: " + net_name)

	# ── Bundled catalog (served when no remote catalog_url is configured) ──
	check(reg.has_catalog(), "has_catalog() true (bundled catalog present)")
	var bundled_cat = reg._read_json(reg.BUNDLED_CATALOG)
	check(bundled_cat != null, "bundled catalog parses")
	var bundled_packs: Array = reg._extract_packs(bundled_cat)
	check(bundled_packs.size() >= 1, "bundled catalog has at least one pack")
	for p in bundled_packs:
		var pid := String(p.get("id", ""))
		check(String(p.get("net", "")).ends_with(".nnue"), "pack %s names a .nnue net" % pid)
		check(String(p.get("net_url", "")).begins_with("https://"), "pack %s net_url is https" % pid)
		check(String(p.get("sha256", "")).length() == 64, "pack %s pins a sha256" % pid)
		check(int(p.get("size_bytes", 0)) > 100000, "pack %s declares size_bytes" % pid)
	# fetch_catalog() with an empty URL must emit the bundled packs synchronously.
	# (Mutate `got` — GDScript lambdas capture by value, so assignment wouldn't stick.)
	var got: Array = []
	var cb := func(ok: bool, packs: Array, _msg: String):
		if ok: got.append_array(packs)
	reg.catalog_loaded.connect(cb)
	reg._catalog_url = ""
	reg.fetch_catalog()
	reg.catalog_loaded.disconnect(cb)
	check(got.size() == bundled_packs.size(), "fetch_catalog(empty url) serves the bundled packs")

	# ── Cleanup ──
	for path in ["user://engines/test_pack.json", "user://engines/probe_pack.json", "user://engines/nets/probe.nnue"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d failed)" % fails)
	quit()
	return true
