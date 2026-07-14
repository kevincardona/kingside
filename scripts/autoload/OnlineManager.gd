extends Node
# Cross-platform online matches over Firebase (Firestore REST + anonymous
# auth). Works on every export target — macOS, Windows, Linux, Android, iOS —
# because it is plain HTTPS from GDScript; no native code, no game server.
# Hosting is Firebase's free Spark tier: set it up once (see
# docs/ONLINE_SETUP.md) and forget it.
#
# The public surface deliberately mirrors GameCenterManager so GameOnline and
# OnlineScreen can route between the two backends:
#   is_configured / is_authenticated / authenticate / local_player_id
#   create_match / join_match / quick_match / load_matches
#   end_turn / end_match / resign_match / watch / unwatch
# Signals: auth_changed, match_found, turn_received, matches_loaded, net_error
#
# Match document (Firestore collection "matches", doc id = invite code):
#   code, status("open"|"active"|"done"), quick(bool),
#   white_id/white_name/black_id/black_name, turn_uid,
#   payload (JSON string {v, moves:[uci], fen, white_id}),
#   winner_uid, reason, created, updated (unix seconds)

signal auth_changed(ok: bool, player_name: String)
signal match_found(match_id: String, my_turn: bool, data: Dictionary, info: Dictionary)
signal turn_received(match_id: String, my_turn: bool, data: Dictionary, ended: bool, outcome: String, info: Dictionary)
signal matches_loaded(matches: Array)
signal net_error(op: String, message: String)

const CONFIG_PATH   = "res://online_service.cfg"
const IDENTITY_PATH = "user://online_identity.json"
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I
const POLL_INTERVAL = 2.5

var _api_key: String = ""
var _project_id: String = ""

var _uid: String = ""
var _name: String = ""
var _id_token: String = ""
var _refresh_token: String = ""
var _token_expiry: float = 0.0
var _authenticating: bool = false

var _watch_id: String = ""
var _watch_timer: Timer = null
var _watch_updated: String = ""
var _watch_busy: bool = false
var _watch_cache: Dictionary = {}   # last parsed doc of the watched match

func _ready() -> void:
	_load_config()
	_load_identity()
	_watch_timer = Timer.new()
	_watch_timer.wait_time = POLL_INTERVAL
	_watch_timer.timeout.connect(_poll_watched)
	add_child(_watch_timer)

# ── Config / identity ──

func _load_config() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_api_key    = str(cfg.get_value("firebase", "api_key", ""))
	_project_id = str(cfg.get_value("firebase", "project_id", ""))

func is_configured() -> bool:
	return _api_key != "" and _project_id != ""

func is_authenticated() -> bool:
	return _uid != "" and _refresh_token != ""

func local_player_id() -> String:
	return _uid

func player_name() -> String:
	return _name

func _load_identity() -> void:
	if not FileAccess.file_exists(IDENTITY_PATH): return
	var f = FileAccess.open(IDENTITY_PATH, FileAccess.READ)
	if f == null: return
	var json = JSON.new()
	if json.parse(f.get_as_text()) != OK: return
	var d = json.get_data()
	if typeof(d) != TYPE_DICTIONARY: return
	_uid = str(d.get("uid", ""))
	_refresh_token = str(d.get("refresh_token", ""))
	_name = str(d.get("name", ""))

func _save_identity() -> void:
	var f = FileAccess.open(IDENTITY_PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({"uid": _uid, "refresh_token": _refresh_token, "name": _name}))

# ── Auth (Firebase anonymous) ──

func authenticate() -> void:
	await ensure_auth()

# Lazily signs up (first run) or refreshes the short-lived ID token.
func ensure_auth() -> bool:
	if not is_configured(): return false
	if _id_token != "" and Time.get_unix_time_from_system() < _token_expiry - 60.0:
		return true
	if _authenticating:
		# Another caller is already authenticating; wait for it to settle.
		while _authenticating:
			await get_tree().process_frame
		return _id_token != ""
	_authenticating = true
	var ok: bool
	if _refresh_token != "":
		ok = await _refresh_id_token()
		if not ok:
			ok = await _sign_up()
	else:
		ok = await _sign_up()
	_authenticating = false
	auth_changed.emit(ok, _name)
	return ok

func _sign_up() -> bool:
	var res = await _http(HTTPClient.METHOD_POST,
		"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % _api_key,
		{"returnSecureToken": true}, false)
	if res["code"] != 200:
		net_error.emit("sign_in", _err_text(res))
		return false
	var d = res["data"]
	_uid = str(d.get("localId", ""))
	_id_token = str(d.get("idToken", ""))
	_refresh_token = str(d.get("refreshToken", ""))
	_token_expiry = Time.get_unix_time_from_system() + float(str(d.get("expiresIn", "3600")))
	if _name == "":
		_name = "Guest-%s" % _uid.substr(0, 4).to_upper()
	_save_identity()
	return _uid != ""

func _refresh_id_token() -> bool:
	var body = "grant_type=refresh_token&refresh_token=%s" % _refresh_token.uri_encode()
	var res = await _http_raw(HTTPClient.METHOD_POST,
		"https://securetoken.googleapis.com/v1/token?key=%s" % _api_key,
		body, "application/x-www-form-urlencoded")
	if res["code"] != 200:
		return false
	var d = res["data"]
	_uid = str(d.get("user_id", _uid))
	_id_token = str(d.get("id_token", ""))
	_refresh_token = str(d.get("refresh_token", _refresh_token))
	_token_expiry = Time.get_unix_time_from_system() + float(str(d.get("expires_in", "3600")))
	_save_identity()
	return _id_token != ""

# ── Match lifecycle ──

# Create a friend match (visible by invite code) or a quick-queue match.
func create_match(quick: bool = false) -> void:
	if not await ensure_auth():
		net_error.emit("create_match", "Sign-in failed")
		return
	var code = _gen_code()
	var now = int(Time.get_unix_time_from_system())
	var doc = {
		"code": code, "status": "open", "quick": quick,
		"white_id": _uid, "white_name": _name,
		"black_id": "", "black_name": "",
		"turn_uid": _uid, "payload": "",
		"winner_uid": "", "reason": "",
		"created": now, "updated": now,
	}
	var res = await _http(HTTPClient.METHOD_POST,
		"%s/matches?documentId=%s" % [_fs_base(), code],
		{"fields": _fs_fields(doc)})
	if res["code"] != 200:
		net_error.emit("create_match", _err_text(res))
		return
	_watch_cache = _fs_parse(res["data"])
	match_found.emit(code, true, {}, {
		"i_created": true, "opponent": "", "code": code, "backend": "web",
		"waiting": true, "quick": quick,
	})

# Join a friend's match by its invite code.
func join_match(code: String) -> void:
	code = code.strip_edges().to_upper()
	if not await ensure_auth():
		net_error.emit("join_match", "Sign-in failed")
		return
	var res = await _http(HTTPClient.METHOD_GET, "%s/matches/%s" % [_fs_base(), code])
	if res["code"] != 200:
		net_error.emit("join_match", "No match with code %s" % code)
		return
	var doc = _fs_parse(res["data"])
	if str(doc.get("white_id", "")) == _uid:
		# Rejoining my own invite — just open it.
		_emit_open(doc)
		return
	if str(doc.get("status", "")) != "open":
		if str(doc.get("black_id", "")) == _uid:
			_emit_open(doc)   # rejoin a match I'm already seated in
			return
		net_error.emit("join_match", "That match already has two players.")
		return
	var ok = await _claim_seat(doc)
	if not ok:
		net_error.emit("join_match", "Could not join — try again.")

# Join the oldest open quick match, or create one and wait.
func quick_match() -> void:
	if not await ensure_auth():
		net_error.emit("quick_match", "Sign-in failed")
		return
	var query = {
		"structuredQuery": {
			"from": [{"collectionId": "matches"}],
			"where": {"compositeFilter": {"op": "AND", "filters": [
				{"fieldFilter": {"field": {"fieldPath": "status"}, "op": "EQUAL",
					"value": {"stringValue": "open"}}},
				{"fieldFilter": {"field": {"fieldPath": "quick"}, "op": "EQUAL",
					"value": {"booleanValue": true}}},
			]}},
			"orderBy": [{"field": {"fieldPath": "created"}, "direction": "ASCENDING"}],
			"limit": 8,
		}
	}
	var res = await _http(HTTPClient.METHOD_POST, "%s:runQuery" % _fs_base(), query)
	if res["code"] == 200 and typeof(res["data"]) == TYPE_ARRAY:
		for row in res["data"]:
			if typeof(row) != TYPE_DICTIONARY or not row.has("document"): continue
			var doc = _fs_parse(row["document"])
			if str(doc.get("white_id", "")) == _uid: continue
			if await _claim_seat(doc):
				return
	# Nobody waiting (or all claims raced out) — create our own queue entry.
	await create_match(true)

# Atomically take the black seat. The updateTime precondition makes two
# simultaneous joiners race safely: the loser gets a 409 and moves on.
func _claim_seat(doc: Dictionary) -> bool:
	var code = str(doc.get("code", ""))
	# Whose move it is depends on how many moves White already made while
	# waiting: even ply count → White to move, odd → Black (the joiner).
	var played = _payload_of(doc).get("moves", [])
	var ply = played.size() if typeof(played) == TYPE_ARRAY else 0
	var patch = {
		"black_id": _uid, "black_name": _name,
		"status": "active",
		"turn_uid": str(doc.get("white_id", "")) if ply % 2 == 0 else _uid,
		"updated": int(Time.get_unix_time_from_system()),
	}
	var url = "%s/matches/%s?%s&currentDocument.updateTime=%s" % [
		_fs_base(), code, _mask(patch.keys()), str(doc.get("_update_time", "")).uri_encode()]
	var res = await _http(HTTPClient.METHOD_PATCH, url, {"fields": _fs_fields(patch)})
	if res["code"] != 200:
		return false
	var merged = _fs_parse(res["data"])
	_emit_open(merged)
	return true

func _emit_open(doc: Dictionary) -> void:
	_watch_cache = doc
	var code = str(doc.get("code", ""))
	match_found.emit(code, _my_turn(doc), _payload_of(doc), _info_of(doc))

# All my matches (as White or Black), newest first, GC-shaped rows.
func load_matches() -> void:
	if not await ensure_auth():
		matches_loaded.emit([])
		return
	var rows: Array = []
	var seen: Dictionary = {}
	for field in ["white_id", "black_id"]:
		var query = {
			"structuredQuery": {
				"from": [{"collectionId": "matches"}],
				"where": {"fieldFilter": {"field": {"fieldPath": field}, "op": "EQUAL",
					"value": {"stringValue": _uid}}},
				"orderBy": [{"field": {"fieldPath": "updated"}, "direction": "DESCENDING"}],
				"limit": 20,
			}
		}
		var res = await _http(HTTPClient.METHOD_POST, "%s:runQuery" % _fs_base(), query)
		if res["code"] != 200 or typeof(res["data"]) != TYPE_ARRAY: continue
		for row in res["data"]:
			if typeof(row) != TYPE_DICTIONARY or not row.has("document"): continue
			var doc = _fs_parse(row["document"])
			var code = str(doc.get("code", ""))
			if code == "" or seen.has(code): continue
			seen[code] = true
			rows.append({
				"match_id": code,
				"my_turn": _my_turn(doc),
				"opponent": _opp_name(doc),
				# Mirror GKTurnBasedMatchStatus: 2 == ended
				"status": 2 if str(doc.get("status", "")) == "done" else 1,
				"data": str(doc.get("payload", "")),
				"i_created": str(doc.get("white_id", "")) == _uid,
				"backend": "web",
				"code": code,
				"waiting": str(doc.get("status", "")) == "open",
			})
	matches_loaded.emit(rows)

# ── In-match sync (called by GameOnline) ──

func end_turn(match_id: String, payload: Dictionary) -> void:
	await _push_state(match_id, payload, "", "")

func end_match(match_id: String, payload: Dictionary, outcome: String) -> void:
	await _ensure_cache(match_id)
	var winner = ""
	if outcome == "won": winner = _uid
	elif outcome == "lost": winner = _opp_id(_watch_cache)
	await _push_state(match_id, payload, winner, "ended")

func resign_match(match_id: String) -> void:
	await _ensure_cache(match_id)
	var patch = {
		"status": "done",
		"winner_uid": _opp_id(_watch_cache),
		"reason": "resign",
		"updated": int(Time.get_unix_time_from_system()),
	}
	await _patch_match(match_id, patch)

# The opponent uid comes from the cached match doc; refetch it if we are
# acting on a match the poller has not seen yet.
func _ensure_cache(match_id: String) -> void:
	if str(_watch_cache.get("code", "")) == match_id: return
	if not await ensure_auth(): return
	var res = await _http(HTTPClient.METHOD_GET, "%s/matches/%s" % [_fs_base(), match_id])
	if res["code"] == 200:
		_watch_cache = _fs_parse(res["data"])

func _push_state(match_id: String, payload: Dictionary, winner_uid: String, reason: String) -> void:
	if not await ensure_auth(): return
	await _ensure_cache(match_id)
	var done = reason != ""
	var patch = {
		"payload": JSON.stringify(payload),
		"turn_uid": _opp_id(_watch_cache),
		"updated": int(Time.get_unix_time_from_system()),
	}
	if done:
		patch["status"] = "done"
		patch["winner_uid"] = winner_uid
		patch["reason"] = reason
	var res = await _patch_match(match_id, patch)
	if res["code"] != 200:
		net_error.emit("send_move", _err_text(res))

func _patch_match(match_id: String, patch: Dictionary) -> Dictionary:
	if not await ensure_auth(): return {"code": 0, "data": {}}
	var url = "%s/matches/%s?%s" % [_fs_base(), match_id, _mask(patch.keys())]
	var res = await _http(HTTPClient.METHOD_PATCH, url, {"fields": _fs_fields(patch)})
	if res["code"] == 200:
		var doc = _fs_parse(res["data"])
		if str(doc.get("code", "")) == _watch_id or _watch_id == "":
			_watch_cache = doc
		_watch_updated = str(doc.get("_update_time", _watch_updated))
	return res

# ── Polling ──

func watch(match_id: String) -> void:
	_watch_id = match_id
	_watch_updated = ""
	_watch_timer.start()

func unwatch() -> void:
	_watch_id = ""
	_watch_timer.stop()

func _poll_watched() -> void:
	if _watch_id == "" or _watch_busy: return
	_watch_busy = true
	await _poll_once()
	_watch_busy = false

func _poll_once() -> void:
	if not await ensure_auth(): return
	var match_id = _watch_id
	var res = await _http(HTTPClient.METHOD_GET, "%s/matches/%s" % [_fs_base(), match_id])
	if res["code"] != 200 or match_id != _watch_id: return
	var doc = _fs_parse(res["data"])
	_watch_cache = doc
	var stamp = str(doc.get("_update_time", ""))
	if stamp == _watch_updated: return
	var first = _watch_updated == ""
	_watch_updated = stamp
	if first: return   # baseline snapshot, nothing new happened yet
	var ended = str(doc.get("status", "")) == "done"
	var outcome = ""
	if ended:
		var w = str(doc.get("winner_uid", ""))
		outcome = "tied" if w == "" else ("won" if w == _uid else "lost")
	turn_received.emit(match_id, _my_turn(doc), _payload_of(doc), ended, outcome, _info_of(doc))
	if ended:
		unwatch()

# ── Doc helpers ──

func _my_turn(doc: Dictionary) -> bool:
	if str(doc.get("status", "")) == "done": return false
	var turn = str(doc.get("turn_uid", ""))
	if turn == "": return str(doc.get("white_id", "")) == _uid
	return turn == _uid

func _opp_id(doc: Dictionary) -> String:
	if str(doc.get("white_id", "")) == _uid:
		return str(doc.get("black_id", ""))
	return str(doc.get("white_id", ""))

func _opp_name(doc: Dictionary) -> String:
	if str(doc.get("white_id", "")) == _uid:
		return str(doc.get("black_name", ""))
	return str(doc.get("white_name", ""))

func _payload_of(doc: Dictionary) -> Dictionary:
	var raw = str(doc.get("payload", ""))
	if raw.strip_edges() == "":
		# No moves yet — seed the seat assignment from the doc itself.
		return {"v": 1, "moves": [], "white_id": str(doc.get("white_id", ""))}
	var json = JSON.new()
	if json.parse(raw) != OK: return {}
	var d = json.get_data()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _info_of(doc: Dictionary) -> Dictionary:
	return {
		"active": false,
		"i_created": str(doc.get("white_id", "")) == _uid,
		"opponent": _opp_name(doc),
		"code": str(doc.get("code", "")),
		"backend": "web",
		"waiting": str(doc.get("status", "")) == "open",
	}

func _gen_code() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var code = ""
	for i in 6:
		code += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return code

# ── Firestore REST plumbing ──

func _fs_base() -> String:
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents" % _project_id

static func _mask(keys: Array) -> String:
	var parts = PackedStringArray()
	for k in keys:
		parts.append("updateMask.fieldPaths=%s" % str(k))
	return "&".join(parts)

static func _fs_fields(d: Dictionary) -> Dictionary:
	var out = {}
	for k in d:
		out[k] = _fs_value(d[k])
	return out

static func _fs_value(v) -> Dictionary:
	match typeof(v):
		TYPE_BOOL:   return {"booleanValue": v}
		TYPE_INT:    return {"integerValue": str(v)}
		TYPE_FLOAT:  return {"doubleValue": v}
		_:           return {"stringValue": str(v)}

static func _fs_parse(doc: Dictionary) -> Dictionary:
	var out = {}
	var fields = doc.get("fields", {})
	for k in fields:
		var v = fields[k]
		if v.has("stringValue"):    out[k] = v["stringValue"]
		elif v.has("integerValue"): out[k] = int(v["integerValue"])
		elif v.has("doubleValue"):  out[k] = float(v["doubleValue"])
		elif v.has("booleanValue"): out[k] = bool(v["booleanValue"])
		else: out[k] = ""
	out["_update_time"] = str(doc.get("updateTime", ""))
	return out

func _err_text(res: Dictionary) -> String:
	var d = res.get("data", {})
	if typeof(d) == TYPE_DICTIONARY:
		var e = d.get("error", {})
		if typeof(e) == TYPE_DICTIONARY and e.has("message"):
			return str(e["message"])
	return "Network error (%d)" % int(res.get("code", 0))

func _http(method: int, url: String, body = null, auth: bool = true) -> Dictionary:
	var data = "" if body == null else JSON.stringify(body)
	var content_type = "application/json"
	var headers = PackedStringArray(["Content-Type: %s" % content_type])
	if auth and _id_token != "":
		headers.append("Authorization: Bearer %s" % _id_token)
	return await _request(method, url, headers, data)

func _http_raw(method: int, url: String, body: String, content_type: String) -> Dictionary:
	return await _request(method, url, PackedStringArray(["Content-Type: %s" % content_type]), body)

func _request(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var req = HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	var err = req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"code": 0, "data": {}}
	var res = await req.request_completed
	req.queue_free()
	var parsed = {}
	var txt: String = res[3].get_string_from_utf8()
	if txt != "":
		var json = JSON.new()
		if json.parse(txt) == OK:
			parsed = json.get_data()
	return {"code": int(res[1]), "data": parsed}
