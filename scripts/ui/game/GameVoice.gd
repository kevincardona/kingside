class_name GameVoice
extends Node
# Hands-free voice move input for GameScreen. Owns the listening lifecycle
# (arm / re-arm / dedupe), the on-screen "heard" banner, and the pulsing mic
# button animation. The hosting screen exposes board/state/input methods.
#
# Screen contract (read): _board, _state, _player_color, _game_over,
#   _pending_promo, _ai_thinking, _voice_btn, _last_is_landscape, _is_narrow()
# Screen contract (call): _attempt_move, _process_tap, _process_premove_tap,
#   _on_undo, _on_hint

var screen: Control = null

var listening: bool = false
var banner: Panel = null

# A natural pause this long (seconds) with no new words ends the current
# utterance: iOS streams one ever-growing transcript and only marks it "final"
# when WE end the audio, so without this the banner just piles up forever.
const SILENCE_LIMIT := 1.1

var _strip_lbl: Label = null
var _poll_accum: float = 0.0
var _strip_idle: float = 0.0
var _pulse_t: float = 0.0
var _restart_delay: float = 0.0
var _speech_idle: float = 0.0     # seconds since the transcript last changed
var _arm_grace: float = 0.0       # suppress re-arm checks while native start() is in flight
var _last_commit: String = ""     # dedupe guard: same utterance must not move twice
var _last_command_text: String = ""
var _last_command_name: String = ""
var _command_cooldown: float = 0.0
var _level: float = 0.0
var wave_icon: Control = null   # GameWidgets.VoiceWaveIcon, set by GameHud

func _ready() -> void:
	SpeechManager.transcript_changed.connect(_on_speech_transcript)
	SpeechManager.final_transcript.connect(_on_speech_final)
	SpeechManager.error_changed.connect(_on_speech_error)

func _exit_tree() -> void:
	stop()
	if SpeechManager.transcript_changed.is_connected(_on_speech_transcript):
		SpeechManager.transcript_changed.disconnect(_on_speech_transcript)
	if SpeechManager.final_transcript.is_connected(_on_speech_final):
		SpeechManager.final_transcript.disconnect(_on_speech_final)
	if SpeechManager.error_changed.is_connected(_on_speech_error):
		SpeechManager.error_changed.disconnect(_on_speech_error)

func _process(delta: float) -> void:
	_poll(delta)
	_update_pulse(delta)

# ── Lifecycle ──

func toggle() -> void:
	if screen._game_over or not screen._pending_promo.is_empty(): return
	if listening:
		stop()
		return
	var ok = SpeechManager.start()
	_poll_accum = 0.0
	_strip_idle = 0.0
	_restart_delay = 0.0
	_speech_idle = 0.0
	_last_command_text = ""
	_last_command_name = ""
	if not ok:
		var err = SpeechManager.get_error()
		show_strip(err if err != "" else "Could not start speech recognition.")
		return
	listening = true
	if is_instance_valid(wave_icon):
		wave_icon.listening = true
	_update_btn_style()
	show_strip("Listening…")

func stop() -> void:
	listening = false
	_restart_delay = 0.0
	_command_cooldown = 0.0
	SpeechManager.stop()
	show_strip("")
	if is_instance_valid(wave_icon):
		wave_icon.listening = false
		wave_icon.level = 0.0
	_update_btn_style()

# Recolor the mic button by state — red while listening, normal card when off.
# Touch screens leave Godot buttons stuck in their lighter "hover" style after a
# tap, so the hover shade can't be the on/off signal; the base color can be.
func _update_btn_style() -> void:
	if screen == null or not is_instance_valid(screen._voice_btn):
		return
	var col = UITheme.RED_LT.darkened(0.35) if listening else UITheme.BG_CARD2
	UITheme.apply_button(screen._voice_btn, col, Color.WHITE, UITheme.FS_H2, UITheme.R_MEDIUM)

func _poll(delta: float) -> void:
	if not listening: return
	if _command_cooldown > 0.0:
		_command_cooldown = max(0.0, _command_cooldown - delta)
	if _strip_idle > 0.0:
		_strip_idle = max(0.0, _strip_idle - delta)
		if _strip_idle <= 0.0 and is_instance_valid(screen._board) and screen._board.selected_sq < 0:
			show_strip("")
	if screen._game_over:
		stop()
		return
	if _restart_delay > 0.0:
		_restart_delay -= delta
		if _restart_delay <= 0.0:
			_restart_delay = 0.0
			_rearm()
		return
	if _arm_grace > 0.0:
		_arm_grace = max(0.0, _arm_grace - delta)
	else:
		_speech_idle += delta   # only count silence once the fresh request is live
	_poll_accum += delta
	if _poll_accum < 0.08: return
	_poll_accum = 0.0
	SpeechManager.poll()   # may fire _on_speech_transcript, which resets _speech_idle
	_level = SpeechManager.get_audio_level()
	# Silence segmentation: when the growing partial has gone quiet past a short
	# pause, treat the utterance as finished — run the same parse the native
	# "final" path uses, then re-arm with a fresh request so the next command
	# starts from an empty buffer instead of appending onto the last one.
	if _arm_grace <= 0.0 and _speech_idle >= SILENCE_LIMIT \
			and SpeechManager.get_transcript().strip_edges() != "":
		_speech_idle = 0.0
		_on_speech_final(SpeechManager.get_transcript())
		# Guarantee the buffer resets even if that path didn't queue a re-arm
		# (e.g. it only selected a square) — otherwise it keeps re-triggering.
		if _restart_delay <= 0.0 and listening:
			_rearm()
		return
	# Hands-free: whenever the recognizer finishes an utterance (final result,
	# silence timeout, benign error) the mic stays hot but listening goes false
	# — immediately arm the next utterance.
	if _arm_grace <= 0.0 and not SpeechManager.is_listening():
		_restart_delay = 0.15

func _rearm() -> void:
	SpeechManager.stop()
	SpeechManager.start()
	_arm_grace = 0.8
	_speech_idle = 0.0

# ── Speech events ──

func _on_speech_transcript(text: String) -> void:
	if not listening: return
	_speech_idle = 0.0   # new words arrived — the pause timer restarts
	show_strip(_heard_text(text))
	var command = _command_from_text(text)
	if command != "" and _commit_command(command, text):
		return
	# Commit instantly when the partial transcript is already an unambiguous
	# explicit move like "pawn a2 to a3" — no waiting for the silence timeout.
	if screen._game_over or not screen._pending_promo.is_empty(): return
	var parsed = VoiceMoveParser.parse_strict(text, screen._state, screen._player_color)
	if parsed.get("ok", false):
		_commit_move(parsed.get("move", {}))
	elif _show_ambiguity(parsed):
		return
	elif _handle_square(text, false):
		return

func _on_speech_final(text: String) -> void:
	if not listening: return
	var command = _command_from_text(text)
	if command != "" and _commit_command(command, text):
		return
	if screen._game_over or not screen._pending_promo.is_empty(): return
	var parsed = VoiceMoveParser.parse(text, screen._state, screen._player_color)
	if not parsed.get("ok", false):
		if _show_ambiguity(parsed):
			_restart_delay = 0.4
			return
		if _handle_square(text, true):
			return
		show_strip("Didn't catch that")
		_restart_delay = 0.4
		return
	_commit_move(parsed.get("move", {}))

func _on_speech_error(message: String) -> void:
	if not listening: return
	show_strip(message)
	_restart_delay = 1.5

# ── Commands ──

func _command_from_text(text: String) -> String:
	var command = VoiceMoveParser.parse_command(text)
	if command == "":
		_last_command_text = ""
		_last_command_name = ""
		return ""
	var clean = _normalize_command_text(text)
	if clean == _last_command_text and command == _last_command_name:
		return "__consumed__"
	if not _is_short_command_utterance(clean, command):
		return ""
	return command

func _normalize_command_text(text: String) -> String:
	var clean = text.to_lower().strip_edges().replace("\n", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean

func _is_short_command_utterance(clean: String, command: String) -> bool:
	var words = clean.split(" ", false)
	match command:
		"stop", "undo", "hint", "flip", "show_spaces":
			return words.size() <= 5
	return true

func _commit_command(command: String, source_text: String = "") -> bool:
	if command == "__consumed__":
		return true
	if _command_cooldown > 0.0:
		return true
	_command_cooldown = 0.75
	_last_command_text = _normalize_command_text(source_text)
	_last_command_name = command
	match command:
		"stop":
			show_strip("Voice off")
			stop()
		"undo":
			screen._on_undo()
			show_strip("Undo")
			_rearm()
		"hint":
			screen._on_hint()
			show_strip("Hint")
			_rearm()
		"flip":
			screen._board.flip_board()
			show_strip("Board flipped")
			_rearm()
		"show_spaces":
			screen._board.set_voice_coords_visible(true)
			show_strip("Showing spaces")
			_rearm()
		_:
			return false
	return true

# ── Square selection / moves ──

func _handle_square(text: String, final_result: bool) -> bool:
	if screen._game_over or not screen._pending_promo.is_empty(): return false
	var sq = VoiceMoveParser.parse_single_square(text)
	if sq < 0: return false
	if screen._ai_thinking:
		if screen._board.selected_sq == sq:
			_show_square(sq)
			return true
		screen._process_premove_tap(sq)
		_show_square(sq)
		return true
	if screen._state.turn != screen._player_color: return false
	if screen._board.selected_sq == sq:
		_show_square(sq)
		return true
	var selected_before = screen._board.selected_sq
	var piece = screen._state.board[sq]
	var own_piece = piece != 0 and ChessLogic.piece_color(piece) == screen._player_color
	if selected_before < 0 and not own_piece:
		return false
	screen._process_tap(sq)
	if screen._board.selected_sq >= 0:
		_show_square(screen._board.selected_sq)
	elif final_result:
		_rearm()
	return true

func _show_square(sq: int) -> void:
	var sq_label = ChessLogic.sq_name(sq)
	if PlayerData.settings.get("voice_coords", true) and screen._board.selected_sq >= 0:
		screen._board.set_voice_coords_visible(true)
	else:
		screen._board.set_voice_coords_visible(false)
	show_strip("Selected %s" % sq_label)

func _show_ambiguity(parsed: Dictionary) -> bool:
	var candidates = parsed.get("candidates", [])
	if candidates.is_empty(): return false
	screen._board.set_ambiguity(candidates)
	var labels = PackedStringArray()
	for move in candidates.slice(0, mini(2, candidates.size())):
		labels.append(VoiceMoveParser.describe_move(move))
	var suffix = "" if candidates.size() <= 2 else "..."
	show_strip("Ambiguous: say %s%s" % [", ".join(labels), suffix])
	return true

func _commit_move(move: Dictionary) -> void:
	if move.is_empty(): return
	# A partial commit followed by the final transcript of the same utterance
	# must not fire twice.
	var key = "%s@%d.%d" % [ChessLogic.move_to_uci(move), screen._state.fullmove, screen._state.turn]
	if key == _last_commit: return
	_last_commit = key
	show_strip(VoiceMoveParser.describe_move(move))
	screen._board.set_selection(int(move["from"]), [int(move["to"])])
	screen._attempt_move(int(move["from"]), int(move["to"]), [move])
	# Defer the mic re-arm until after the ~0.18s move animation. _rearm()
	# restarts the audio engine, which briefly blocks the main thread — doing it
	# immediately stutters the gliding piece and snaps it to the target square.
	# The _poll loop fires _rearm() when this countdown elapses.
	_restart_delay = max(_restart_delay, 0.4)

# ── Banner strip ──

func show_strip(text: String) -> void:
	if not is_instance_valid(banner) or not is_instance_valid(_strip_lbl): return
	var clean = _banner_text(text)
	_strip_lbl.text = clean
	banner.visible = clean != ""
	_strip_idle = 2.2 if clean != "" else 0.0

func _heard_text(text: String) -> String:
	var clean = text.strip_edges()
	if clean == "":
		return ""
	var display = VoiceMoveParser.display_text(clean)
	if display == "":
		return "\"%s\"" % clean
	if display != clean.to_lower().strip_edges():
		return "\"%s\" -> %s" % [clean, display]
	return "\"%s\"" % display

func _banner_text(text: String) -> String:
	var clean = text.strip_edges().replace("\n", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() > 42:
		clean = clean.substr(0, 39).strip_edges() + "..."
	return clean

func make_banner_panel() -> Panel:
	banner = Panel.new()
	banner.visible = false
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.z_index = 80
	banner.custom_minimum_size.y = 44
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.16, 0.17, 0.16, 0.88), 14, true))
	banner.clip_contents = true

	var m = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(m)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)

	var status = UITheme.make_label("Listening", UITheme.FS_CAPTION, UITheme.ACCENT_LT)
	status.custom_minimum_size.x = 72
	status.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status)

	_strip_lbl = UITheme.make_label("", UITheme.FS_SMALL, UITheme.TEXT)
	_strip_lbl.custom_minimum_size.y = 24
	_strip_lbl.clip_text = true
	_strip_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_strip_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_strip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_strip_lbl)
	return banner

func add_overlay() -> void:
	# The banner floats over the board (an overlay) in both orientations so
	# showing/hiding it never reflows the layout / nudges the board.
	make_banner_panel()
	var vp = screen.get_viewport_rect().size
	var width: float
	var top_offset: float
	if screen._last_is_landscape:
		width = min(420.0, max(280.0, vp.x * 0.42))
		top_offset = UITheme.safe_top() + 18
	else:
		# Cover the move-history strip (just below the opponent bar) rather than
		# overlapping the board — you don't need the history while dictating.
		width = min(560.0, max(280.0, vp.x - 16.0))
		var opp_h = (116 if screen._is_narrow() else 132) + UITheme.safe_top()
		top_offset = opp_h
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 0.0
	banner.anchor_bottom = 0.0
	banner.offset_left = -width * 0.5
	banner.offset_right = width * 0.5
	banner.offset_top = top_offset
	banner.offset_bottom = top_offset + 44
	screen.add_child(banner)

# ── Mic button pulse ──

# Feed the live mic level + listening state into the waveform icon, which
# animates its bars accordingly.
func _update_pulse(_delta: float) -> void:
	if is_instance_valid(wave_icon):
		wave_icon.listening = listening and _restart_delay <= 0.0
		wave_icon.level = _level
