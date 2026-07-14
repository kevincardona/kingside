# Kingside — Architecture & internals

Developer notes for the offline chess app. For the overview, features, and build
quick-start, see the [README](../README.md).

- [Architecture](#architecture)
- [The AI & rating system](#the-ai--rating-system) ← "is a 600 here like a 600 on chess.com?"
- [Puzzles & the Journey](#puzzles--the-journey)
- [Game review](#game-review)
- [Voice moves](#voice-moves)
- [Design system](#design-system)
- [Native extensions (GDExtension)](#native-extensions-gdextension)
- [Building](#building)
- [Testing](#testing)

> **Online multiplayer is deferred to v2** and disabled in v1. Game Center
> turn-based code (`GameCenterManager`) and a cross-platform Firebase client
> (`OnlineManager`) exist behind `GameManager.feature_flags.multiplayer = false`,
> so the "Play Online" button never renders and Game Center never authenticates.
> The shipped app is a pure offline experience.

---

## Architecture

A single running scene (`scenes/Main.tscn` → `scripts/Main.gd`) hosts one
**screen** at a time. **Autoload singletons** hold all global state and logic;
**screen scripts** build their UI in code (there are very few `.tscn` layouts —
the UI is constructed imperatively against the design system).

### Autoloads (`scripts/autoload/`)

| Autoload | Responsibility |
|---|---|
| `ChessLogic` | Pure rules engine: board state, legal moves, FEN, status (check/mate/stalemate/draws), perft. No UI. |
| `AIEngine` | Move selection, hints, and game review. Owns the strength model and the native/script backend split. Runs work on threads, emits `move_ready` / `hint_ready` / `review_ready`. |
| `AIEngineBackend` / `AINativeBackend` / `AIScriptBackend` | Backend abstraction. Native = the Stockfish GDExtension; script = a portable GDScript alpha-beta searcher used as a fallback. |
| `GameManager` | Navigation/router (`show_main_menu`, `show_puzzles`, `show_profile`, `show_difficulty_select`, `start`, …), the active session, and `feature_flags`. |
| `PlayerData` | Persistent profile: rating, W/L/D, settings, day-streak, saved/continuable game. Load/save to `user://`. |
| `PuzzleManager` | Loads `assets/puzzles/bundled.json`, the Journey level/unlock logic, the rating pool, and the daily puzzle. Lazy-normalizes rows. |
| `SoundManager` / `Haptics` | Audio + haptic feedback. |
| `SpeechManager` | Wraps the native speech GDExtension; exposes `is_listening`, results, errors. |
| `GameCenterManager` | Game Center auth + leaderboard submit (native GDExtension on Apple, stub elsewhere). Dormant in v1. |
| `OnlineManager` | Firebase Firestore REST + anonymous-auth client for cross-platform online. Dormant until configured. |

### Screens (`scripts/ui/`)

`MainMenuScreen`, `PuzzlesScreen`, `ProfileScreen`, `DifficultyScreen`,
`SettingsScreen`, `AboutScreen`, `EnginesScreen`, `GameScreen`.

### The in-game screen is decomposed

`GameScreen.gd` is a thin **orchestrator**. The heavy lifting lives in child
component nodes under `scripts/ui/game/`, each holding a `screen` back-reference
to the orchestrator:

| Component | Owns |
|---|---|
| `GameHud` | Layout (portrait/landscape), board, player bars, move-history strip, control buttons, captured material. |
| `GameVoice` | The voice listening lifecycle + the floating "Listening" banner overlay. |
| `GameReview` | The post-game review UI: eval graph, accuracy ring, navigation, best-move arrows. |
| `GameOnline` | Online turn plumbing (when enabled). |
| `GameModals` | Shared overlay + centered-card modal helpers (promotion, resign, result, review loader). |
| `GameWidgets` | Custom-drawn widgets: `AccuracyRing`, `WinChanceBar`, `ReviewSpinner`, `VoiceWaveIcon`, `HintIcon`. |
| `GameFormat` | Text/format helpers (move SAN, piece glyphs, review bucket/colour/icon). |

> **Rotation note:** on rotate, the screen rebuilds only its `CanvasItem`
> children and re-runs the component `build()`, so non-visual state survives.

---

## The AI & rating system

This section answers the recurring question: **"Is a 600 in this app like a 600
on chess.com?"**

### How a bot move is chosen (`AIEngine._pick_move`)

1. **Opening book** for the first few moves (except Max Stockfish).
2. **Native Stockfish** (if the GDExtension is up and the tier prefers it):
   - `native_elo >= 1320` → `UCI_LimitStrength` + `UCI_Elo` (Stockfish's own
     calibrated rating model; **1320 is the engine's hard floor**).
   - `native_elo  < 1320` → **Skill Level 0–5** (its intentional-mistake mode).
3. **Human-blunder layer** (low tiers only — see below).
4. **Script searcher** fallback (portable GDScript alpha-beta with a centipawn
   "target loss" for human-like weakening) if native is unavailable.

### Why the low tiers used to feel too strong

Stockfish's **Skill Level 0 still plays roughly 1100–1300 strength** — it never
hangs a piece to a one-move threat and always plays sound openings. So a tier
*labelled* 500 was really playing ~1200. And Stockfish `UCI_Elo` is calibrated
to engine/CCRL scales that **run well above chess.com** (a Stockfish `UCI_Elo
1600` is closer to a chess.com ~1900). Both effects made the numbers optimistic.

### The fix: a human-blunder layer

The low tiers (`beginner`, `easy`, `medium`, lightly `hard`) now carry a
`blunder` probability in `DIFFICULTIES`. On each move, with that probability,
`AIEngine._apply_human_blunder` replaces Stockfish's move with a **deliberately
weak but non-random** one: every legal move is scored a shallow 1 ply and one is
drawn near the tier's target centipawn loss (reusing `_pick_with_loss`). The bot
**drops a pawn or misplaces a piece like a real beginner**; the rest of the time
it plays Stockfish's move, so games stay coherent.

```
Tier       Elo label   blunder   Engine strength under the hood
Beginner   500         0.45      Skill 0 + frequent material drops
Easy       800         0.28      Skill 2 + occasional drops
Medium     1200        0.12      Skill 5 + light drops
Hard       1600        0.04      UCI_Elo 1600
Expert     2000         —        UCI_Elo 2000
Master     2500         —        UCI_Elo 2500
Max        3200         —        Full strength, long think
```

> **These Elo numbers are *target playing strengths*, not raw `UCI_Elo`.**
> Because the bot labelled 600 actually plays like ~600, the player's own
> rating tracks roughly to chess.com's lower/mid bands. **Exact cross-site
> calibration still needs real-game playtesting;** the per-tier `blunder` rates
> are the single knob to turn. If a tier feels too easy/hard, nudge its
> `blunder` value.

### Hints & review always use full strength

`HINT_CONFIG` and the review pass ignore the opponent's handicap — advice and
post-game analysis always come from the strongest available model, never the
weakened one.

---

## Puzzles & the Journey

- **Bundle:** `assets/puzzles/bundled.json`, generated by `tools/bake_puzzles.py`
  from a Lichess puzzle DB. Contains **20 Journey levels** (~2,000 curated
  puzzles, grouped by theme + rating) and a large rating-matched pool.
- **Lazy normalization:** both levels and pool store *raw* Lichess rows
  (`{id, fen, moves, rating, themes}`); `PuzzleManager` only normalizes a row
  when it's actually played, so startup is O(1).
- **Star-gated unlock:** a level unlocks when your total stars reach its
  `unlock_stars` threshold (`PuzzleManager.is_level_unlocked` /
  `stars_to_unlock`). Locked cards show "★ N more to unlock".
- **Daily puzzle** with an offline fallback so it always resolves.

To regenerate the bundle, point `tools/bake_puzzles.py` at a Lichess CSV and run
`tools/bake_puzzles.sh`.

---

## Game review

Built in `scripts/ui/game/GameReview.gd` after a game ends (or from a finished
game in your history). It re-analyzes every move at full engine strength and
shows:

- An **accuracy %** ring (`GameWidgets.AccuracyRing`).
- A **"Played like ~Elo"** estimate for each side — a fun single-game ballpark
  mapped from accuracy, not a verdict (single-game rating estimates are noisy).
- An **eval graph** (`UIStockGraph`) with a centre line (white advantage above,
  black below), territory fill, and only the **notable** moves marked
  (blunders/mistakes/brilliancies) so it doesn't drown in dots.
- Per-move **quality tags** and a **best-move arrow** that fades after a moment
  (toggle "show best move" to pin it).

**Accuracy method** (`AIEngine`): per-move win% and accuracy use Lichess's exact
curves (`Win% = 50 + 50·(2/(1+e^(-0.00368208·cp)) − 1)`;
`Acc% = 103.1668·e^(−0.04354·Δwin%) − 3.1669`). The **game** accuracy is the
**average of a volatility-weighted mean and the harmonic mean** of the per-move
accuracies (also Lichess's method). The harmonic mean is what makes a few
blunders actually cost you — a plain arithmetic mean reads far too high.

---

## Voice moves

`GameVoice` + `SpeechManager` + the native speech extension. Tap the waveform
button, speak a move ("knight f3", "castle kingside", "e4"), and
`VoiceMoveParser` turns it into a legal move with disambiguation help on the
board. The recognizer streams one growing transcript, so `GameVoice` segments
utterances on a short silence — after a pause it finalizes the current command
and re-arms with a fresh request. The "Listening" indicator is a **floating
overlay** (it never reflows the board). Requires on-device speech permission;
iOS/macOS only.

---

## Design system

`scripts/ui/UITheme.gd` is the single source of truth for the look:

- **Palette:** `BG_PAGE`, `BG_CARD/2/3`, `ACCENT`/`ACCENT_DIM`/`ACCENT_LT`,
  `GOLD`, `ORANGE`, `RED`/`RED_LT`, `TEXT`/`TEXT_DIM`/`TEXT_MUTED`.
- **Type scale:** `FS_*` sizes; helpers `make_label`, `make_btn`,
  `make_panel_container`, `panel_style`, `make_pill_badge`.
- **Bottom nav:** `make_app_nav` renders the 3-tab bar (Play / Puzzles /
  Profile) with **custom-drawn vector icons** so they render identically on
  every platform, plus a soft accent pill on the active tab.
- `safe_top()` / `safe_bottom()` for notch/home-indicator insets;
  `hide_v_scrollbar()`.

> **Gotcha:** plain `Panel` does **not** size to its children — use
> `PanelContainer` (or set explicit offsets) or content will sit off-centre.

> **Font gotcha:** the default UI font has **no chess glyphs (or emoji) on iOS**.
> The board and captured-material labels use an explicit symbol-font chain
> (`Segoe UI Symbol`, `Noto Sans Symbols2`, `Apple Symbols`, `DejaVu Sans`);
> board *coordinates* use a separate Latin font because the symbol font has no
> letters/digits.

---

## Native extensions (GDExtension)

C++/Obj-C sources in `gdextension/src/`, built into `gdextension/bin/`:

| Class | Source | Purpose |
|---|---|---|
| `ChessEngine` | `chess_engine.cpp` | Native Stockfish: `bestmove(fen, movetime)`, `set_option(name, value)`. |
| `SpeechInput` | `speech_input_ios.mm` / `_macos.mm` / `_stub.cpp` | On-device speech (AVAudioEngine + SFSpeechRecognizer). |
| `GameCenter` | `game_center_apple.mm` / `_stub.cpp` | Game Center auth + leaderboard (dormant in v1). |

Prebuilt iOS/macOS binaries are committed. Rebuild others with:

```bash
cd gdextension
./build_stockfish_extension.sh linux   x86_64
./build_stockfish_extension.sh windows x86_64
./build_stockfish_extension.sh android arm64
./build_stockfish_extension.sh macos   arm64   # or x86_64
./build_stockfish_extension.sh ios     arm64
```

> **Build gotchas baked into the script:** OBJCXX is only enabled on
> macOS/iOS; macOS builds pin `CMAKE_OSX_ARCHITECTURES` per `$ARCH`; Android
> uses NDK 28; Windows MinGW vs MSVC flags are split (`-static` for MinGW).
> The iPad voice path guards against an invalid (0 Hz) audio input format to
> avoid the `IsFormatSampleRateAndChannelCountValid` crash — **rebuild the iOS
> xcframework and device-test voice after touching `speech_input_ios.mm`.**

---

## Building

**Requirements:** Godot **4.7** with export templates; for native builds,
platform toolchains (Xcode for iOS/macOS, Android SDK + NDK 28, etc.).

```bash
# Desktop: Godot editor → Project → Export → <preset> → Export Project
# Android: Project → Export → Android  (needs SDK + NDK 28)
# iOS/macOS: Project → Export → iOS/macOS  (needs the gdextension/bin/ libs)
```

The iOS app lives in the Xcode project (`Chess.xcodeproj`). `tools/ios_deploy.sh`
exports from Godot, restores the maintained project (which embeds the native
engine xcframework), signs, and installs to a tethered device. See
[`DISTRIBUTION.md`](DISTRIBUTION.md).

App icon: regenerate the full-bleed opaque icon + all AppIcon sizes with
`python3 tools/make_icon.py` (App Store icons must be opaque and full-bleed for
the squircle mask).

---

## Testing

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # adjust to your install

# Rules engine + perft node counts
$GODOT --headless -s res://test_chesslogic.gd
# Voice move parsing
$GODOT --headless -s res://scripts/tools/test_voice_move_parser.gd
# Puzzle bundle: replays every bundled puzzle's solution + offline fallbacks
$GODOT --headless res://test_puzzles.tscn          # prints RESULT: PASS/FAIL
# Native Stockfish smoke test (returns a best move)
$GODOT --headless res://test_load.tscn
# Screenshot tour — captures every screen at 430×932 to /tmp/chess_shots/
$GODOT --path . res://test_screens.tscn
```

The screenshot tour is the fastest way to eyeball UI regressions across all
screens.
