extends Control
# About / Open Source screen. Kingside links Stockfish (GPLv3), so the whole app
# is GPLv3 — this screen carries the required attribution and a link to the
# complete corresponding source. Reached from Settings.

const SOURCE_URL  := "https://github.com/kevincardona/kingside"
const LICENSE_URL := "https://www.gnu.org/licenses/gpl-3.0.html"

func _ready() -> void:
	_build()

func _build() -> void:
	add_child(UITheme.make_page_bg())

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.hide_v_scrollbar(scroll)
	add_child(scroll)

	var outer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(outer)

	var margin = UITheme.page_panel(640, 28)
	outer.add_child(margin)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	col.add_child(UITheme.spacer(UITheme.safe_top() + 4))
	var back = UITheme.make_back_btn()
	back.pressed.connect(GameManager.show_settings)
	col.add_child(back)

	col.add_child(UITheme.make_label("About", UITheme.FS_H1, UITheme.TEXT))
	col.add_child(UITheme.make_label("Kingside — Offline Chess", UITheme.FS_BODY_LG, UITheme.TEXT))
	col.add_child(_para("A fully-offline chess app: real Stockfish opponents, thousands of puzzles, and a computer review of every game — no account, no ads, no internet.", UITheme.FS_SMALL, UITheme.TEXT_DIM))

	col.add_child(UITheme.spacer(6))
	col.add_child(UITheme.make_separator())
	col.add_child(UITheme.make_label("OPEN SOURCE", UITheme.FS_CAPTION, UITheme.TEXT_MUTED))
	col.add_child(_para("Kingside is free, open-source software licensed under the GNU General Public License, version 3 (GPLv3). The complete source code is available online.", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	col.add_child(_para("It includes the Stockfish chess engine — © the Stockfish developers — also licensed under GPLv3, and is built with the Godot Engine (MIT).", UITheme.FS_SMALL, UITheme.TEXT_DIM))

	col.add_child(UITheme.spacer(4))
	var src = UITheme.make_btn("View Source Code  ↗", UITheme.ACCENT_DIM, UITheme.FS_SMALL, 54)
	src.pressed.connect(func(): OS.shell_open(SOURCE_URL))
	col.add_child(src)
	var lic = UITheme.make_btn("View License (GPLv3)  ↗", UITheme.BG_CARD2, UITheme.FS_SMALL, 54)
	lic.pressed.connect(func(): OS.shell_open(LICENSE_URL))
	col.add_child(lic)

	col.add_child(UITheme.spacer(UITheme.safe_bottom() + 24))

func _para(text: String, fs: int, color: Color) -> Label:
	var l = UITheme.make_label(text, fs, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
