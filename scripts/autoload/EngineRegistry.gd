extends Node
# EngineRegistry — the app's catalogue of chess "engines" the player can run.
#
# WHY THIS EXISTS / THE iOS RULE:
#   A chess engine is executable code. Apple's App Store Guideline 2.5.2 forbids
#   downloading and running NEW executable code, so we never download an engine
#   *binary*. Every entry here runs on a binary that is COMPILED INTO the app at
#   build time (currently Stockfish, via the GDExtension). What an entry may
#   carry — and what we CAN add or download later as plain DATA — is:
#     • a neural-net evaluation file (.nnue)   → applied via the EvalFile UCI option
#     • a set of UCI option overrides (config) → applied via set_option(...)
#   Downloading those is allowed (data, not code). A genuinely different engine
#   means bundling another binary at build time, then adding it here.
#
# Sources, merged (a later source overrides an earlier one on id collision):
#   1. res://assets/engines/engines.json  — engines shipped in the app
#   2. user://engines/*.json              — packs installed at runtime (DATA)

signal engines_changed
signal pack_install_started(id: String)
signal pack_install_finished(id: String, ok: bool, message: String)

const BUNDLED_PATH    := "res://assets/engines/engines.json"
const BUNDLED_CATALOG := "res://assets/engines/catalog.json"
const PACKS_DIR       := "user://engines"
const NETS_DIR        := "user://engines/nets"
const DEFAULT_ID      := "stockfish18"

var _engines: Array = []       # Array[Dictionary]
var _catalog_url: String = ""

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_engines = []
	_load_bundled()
	_load_installed_packs()
	# Guarantee the active id still resolves to something real.
	if get_engine(active_id()).is_empty():
		_set_active_id(DEFAULT_ID)

func _load_bundled() -> void:
	var d = _read_json(BUNDLED_PATH)
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("EngineRegistry: bundled engines.json missing or invalid")
		return
	_catalog_url = String(d.get("catalog_url", ""))
	for e in d.get("engines", []):
		_merge(e, true)

func _load_installed_packs() -> void:
	var dir = DirAccess.open(PACKS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.to_lower().ends_with(".json"):
			_merge(_read_json(PACKS_DIR.path_join(f)), false)
		f = dir.get_next()
	dir.list_dir_end()

func _merge(e, bundled: bool) -> void:
	if typeof(e) != TYPE_DICTIONARY:
		return
	var id := String((e as Dictionary).get("id", ""))
	if id == "":
		return
	var entry: Dictionary = (e as Dictionary).duplicate(true)
	entry["bundled"] = bundled
	for i in _engines.size():
		if String(_engines[i].get("id", "")) == id:
			_engines[i] = entry
			return
	_engines.append(entry)

# ── Query ──────────────────────────────────────────────
func engines() -> Array:
	return _engines.duplicate(true)

func get_engine(id: String) -> Dictionary:
	for e in _engines:
		if String(e.get("id", "")) == id:
			return (e as Dictionary).duplicate(true)
	return {}

func active_id() -> String:
	return String(PlayerData.settings.get("engine_id", DEFAULT_ID))

func active_profile() -> Dictionary:
	var p := get_engine(active_id())
	return p if not p.is_empty() else get_engine(DEFAULT_ID)

func is_active(id: String) -> bool:
	return id == active_id()

func catalog_url() -> String:
	return _catalog_url

# True when ANY pack source exists: a remote catalog URL, or the catalog
# bundled with the app (which needs no hosting at all — its packs point
# straight at public net servers).
func has_catalog() -> bool:
	return _catalog_url != "" or FileAccess.file_exists(BUNDLED_CATALOG)

# ── Selection ──────────────────────────────────────────
func select(id: String) -> bool:
	if get_engine(id).is_empty():
		return false
	_set_active_id(id)
	_invalidate_engine()
	engines_changed.emit()
	return true

func _set_active_id(id: String) -> void:
	PlayerData.settings["engine_id"] = id
	PlayerData.save_data()

func _invalidate_engine() -> void:
	var ai = get_node_or_null("/root/AIEngine")
	if ai != null and ai.has_method("on_engine_profile_changed"):
		ai.on_engine_profile_changed()

# ── Net (DATA) resolution ──────────────────────────────
# Absolute filesystem path for a downloaded net, or "" meaning "use the engine's
# embedded default net". Only user:// nets are resolved here; the bundled net is
# embedded in the binary and handled natively in C++.
func resolve_net_path(net_name: String) -> String:
	if net_name == "":
		return ""
	var p := NETS_DIR.path_join(net_name)
	if FileAccess.file_exists(p):
		return ProjectSettings.globalize_path(p)
	return ""

# ── Install a pack (DATA only) ─────────────────────────
# Downloads a JSON profile and saves it under user://. NEVER downloads
# executable code — packs are config (+ optionally a net) that run on the
# already-bundled engine binary, which is what keeps this 2.5.2-compliant.
func install_pack(url: String) -> void:
	pack_install_started.emit(url.get_file())
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			pack_install_finished.emit("", false, "Download failed (%s)" % str(code))
			return
		var e = JSON.parse_string(body.get_string_from_utf8())
		if typeof(e) != TYPE_DICTIONARY or String((e as Dictionary).get("id", "")) == "":
			pack_install_finished.emit("", false, "Invalid pack")
			return
		_save_pack(e)
		_load_all()
		engines_changed.emit()
		pack_install_finished.emit(String((e as Dictionary).get("id", "")), true, ""))
	if http.request(url) != OK:
		http.queue_free()
		pack_install_finished.emit("", false, "Bad URL")

func _save_pack(e: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACKS_DIR))
	var f = FileAccess.open(PACKS_DIR.path_join(String(e["id"]) + ".json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(e))

func uninstall_pack(id: String) -> bool:
	var e := get_engine(id)
	if e.is_empty() or bool(e.get("bundled", false)):
		return false
	var p := PACKS_DIR.path_join(id + ".json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if active_id() == id:
		_set_active_id(DEFAULT_ID)
	_load_all()
	_invalidate_engine()
	engines_changed.emit()
	return true

# ── Remote catalog (DATA) ──────────────────────────────
# The catalog is a JSON list of downloadable packs:
#   { "version": 1, "packs": [ { "id", "name", "net", "net_url",
#       "size_bytes"?, "sha256"?, "uci"?, "tagline"?, "author"? }, ... ] }
# A pack carries ONLY data — a neural-net file (.nnue) + UCI config — that runs
# on the already-bundled Stockfish binary, so it is App-Store 2.5.2 compliant.
signal catalog_loaded(ok: bool, packs: Array, message: String)

func fetch_catalog() -> void:
	var url := catalog_url()
	if url == "":
		# No remote catalog — serve the one bundled with the app. Its packs point
		# net_url at public net servers, so downloads work with zero hosting.
		var bundled = _read_json(BUNDLED_CATALOG)
		if bundled != null:
			catalog_loaded.emit(true, _extract_packs(bundled), "")
		else:
			catalog_loaded.emit(false, [], "No engine catalog is configured.")
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			catalog_loaded.emit(false, [], "Couldn't reach the engine catalog (%s)." % str(code))
			return
		catalog_loaded.emit(true, _extract_packs(JSON.parse_string(body.get_string_from_utf8())), ""))
	if http.request(url) != OK:
		http.queue_free()
		catalog_loaded.emit(false, [], "The catalog URL is invalid.")

# Pure: pull the valid pack entries out of a parsed catalog document. Skips the
# bundled engine itself and anything already installed is still returned (the UI
# decides how to present an installed pack).
func _extract_packs(d) -> Array:
	var out: Array = []
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for p in (d as Dictionary).get("packs", []):
		if typeof(p) == TYPE_DICTIONARY and String((p as Dictionary).get("id", "")) != "":
			out.append((p as Dictionary).duplicate(true))
	return out

# True when an installed (non-bundled) engine pack with this id is present.
func is_installed(id: String) -> bool:
	var e := get_engine(id)
	return not e.is_empty() and not bool(e.get("bundled", false))

# Download a catalog pack's neural net (DATA), validate it against the declared
# size/checksum, then save the pack profile under user://. The net streams to a
# .part file so a 3 MB+ download never sits in memory, and is only swapped into
# place once validated. UCI-only packs (no net) skip straight to saving.
func install_catalog_pack(pack: Dictionary) -> void:
	var id := String(pack.get("id", ""))
	if id == "":
		pack_install_finished.emit("", false, "Invalid pack.")
		return
	pack_install_started.emit(id)
	var net_name := String(pack.get("net", ""))
	var net_url  := String(pack.get("net_url", ""))
	if net_name == "" or net_url == "" or FileAccess.file_exists(NETS_DIR.path_join(net_name)):
		_finalize_pack(pack)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NETS_DIR))
	var part := NETS_DIR.path_join(net_name + ".part")
	var http := HTTPRequest.new()
	http.download_file = part
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, _body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_remove(part)
			pack_install_finished.emit(id, false, "Download failed (%s)." % str(code))
			return
		var why := _validate_net(part, pack)
		if why != "":
			_remove(part)
			pack_install_finished.emit(id, false, why)
			return
		DirAccess.rename_absolute(ProjectSettings.globalize_path(part),
			ProjectSettings.globalize_path(NETS_DIR.path_join(net_name)))
		_finalize_pack(pack))
	if http.request(net_url) != OK:
		http.queue_free()
		_remove(part)
		pack_install_finished.emit(id, false, "The net URL is invalid.")

# Validate a freshly-downloaded net against the catalog's declared size/sha256.
# Returns "" on success, otherwise a human-readable reason.
func _validate_net(path: String, pack: Dictionary) -> String:
	var size := _file_size(path)
	if size <= 0:
		return "The downloaded net was empty."
	var want_bytes := int(pack.get("size_bytes", 0))
	if want_bytes > 0 and size != want_bytes:
		return "Net size mismatch (got %d, expected %d)." % [size, want_bytes]
	var want_sha := String(pack.get("sha256", "")).to_lower()
	if want_sha != "" and FileAccess.get_sha256(path).to_lower() != want_sha:
		return "Net checksum did not match."
	return ""

func _file_size(path: String) -> int:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := int(f.get_length())
	f.close()
	return n

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# Save a downloaded pack's profile (config only — transport fields stripped) and
# reload so it shows up as an installed, selectable engine.
func _finalize_pack(pack: Dictionary) -> void:
	var profile := pack.duplicate(true)
	for k in ["net_url", "size_mb", "size_bytes", "sha256"]:
		profile.erase(k)
	_save_pack(profile)
	_load_all()
	engines_changed.emit()
	pack_install_finished.emit(String(pack.get("id", "")), true, "")

func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
