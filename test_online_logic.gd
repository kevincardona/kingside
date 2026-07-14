extends SceneTree
# Headless checks for OnlineManager's pure logic (no network):
#   godot --headless -s res://test_online_logic.gd

const OnlineManagerScript = preload("res://scripts/autoload/OnlineManager.gd")

var fails := 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  ", label)
	else:
		fails += 1
		printerr("FAIL  ", label)

func _init() -> void:
	var om = OnlineManagerScript.new()
	om._uid = "me123"

	# Firestore field encoding round-trip
	var doc = {"code": "ABC234", "quick": true, "created": 1718000000, "elo": 1200.5}
	var fields = OnlineManagerScript._fs_fields(doc)
	check(fields["code"]["stringValue"] == "ABC234", "string encode")
	check(fields["quick"]["booleanValue"] == true, "bool encode")
	check(fields["created"]["integerValue"] == "1718000000", "int encode (string per REST spec)")
	check(fields["elo"]["doubleValue"] == 1200.5, "float encode")
	var parsed = OnlineManagerScript._fs_parse({"fields": fields, "updateTime": "2026-06-12T00:00:00Z"})
	check(parsed["code"] == "ABC234" and parsed["quick"] == true \
		and parsed["created"] == 1718000000 and parsed["elo"] == 1200.5, "parse round-trip")
	check(parsed["_update_time"] == "2026-06-12T00:00:00Z", "updateTime captured")

	# Update mask
	check(OnlineManagerScript._mask(["a", "b"]) == "updateMask.fieldPaths=a&updateMask.fieldPaths=b", "mask")

	# Invite codes: 6 chars, unambiguous alphabet, distinct
	var codes = {}
	for i in 50:
		var c = om._gen_code()
		check(c.length() == 6, "code length") if i == 0 else null
		for ch in c:
			if not OnlineManagerScript.CODE_ALPHABET.contains(ch):
				check(false, "code alphabet (%s)" % c)
		codes[c] = true
	check(codes.size() > 45, "codes mostly unique")

	# Turn / opponent helpers
	var m_active = {"status": "active", "white_id": "me123", "black_id": "opp9",
		"white_name": "Me", "black_name": "Rival", "turn_uid": "me123"}
	check(om._my_turn(m_active) == true, "my turn when turn_uid is me")
	m_active["turn_uid"] = "opp9"
	check(om._my_turn(m_active) == false, "not my turn")
	check(om._opp_id(m_active) == "opp9" and om._opp_name(m_active) == "Rival", "opponent of white")
	var as_black = {"status": "active", "white_id": "opp9", "black_id": "me123",
		"white_name": "Rival", "black_name": "Me", "turn_uid": ""}
	check(om._my_turn(as_black) == false, "empty turn_uid falls back to white")
	check(om._opp_id(as_black) == "opp9" and om._opp_name(as_black) == "Rival", "opponent of black")
	check(om._my_turn({"status": "done", "turn_uid": "me123"}) == false, "no turn when done")

	# Payload fallback seeds seat from the doc
	var p = om._payload_of({"payload": "", "white_id": "w1"})
	check(p["white_id"] == "w1" and p["moves"].is_empty(), "empty payload seeded")
	p = om._payload_of({"payload": '{"v":1,"moves":["e2e4"],"white_id":"w1"}'})
	check(p["moves"] == ["e2e4"], "payload json parsed")

	om.free()
	print("---- %s" % ("ALL OK" if fails == 0 else "%d FAILURES" % fails))
	quit(0 if fails == 0 else 1)
