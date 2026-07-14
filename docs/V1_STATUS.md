# v1 Status — what's done and what's left

A single place to see where the app stands for launch. Detail lives in the
sibling docs noted below.

## Done in this pass (in code, verified)

**Launch blockers fixed**
- Removed unused camera + photo-library permission strings (5.1.1 rejection risk).
- Set iOS/macOS export version strings (1.0 / build 1).
- Bundle id → `com.kevincardona.chess` (app + iMessage extension + all presets).
- Encryption-compliance flag already correct (`ITSAppUsesNonExemptEncryption=false`).

**Multiplayer cut to ship pure-offline**
- `feature_flags.multiplayer = false`; Game Center never authenticates on launch.
- Removed the `com.apple.developer.game-center` entitlement (app + extension).
- README de-stale'd (it claimed multiplayer was ON).

**Engine picker** (`docs` inline) — Settings → Chess Engine
- `EngineRegistry` autoload + `assets/engines/engines.json`; merges bundled
  engines with installable **data packs** from `user://` (App Store-compliant —
  packs are nets/config, never executable code). `AIEngine` applies the active
  profile's net/UCI options.

**Rating** — see `docs/RATING_AUDIT.md`
- `human_elo → uci_elo` mapping so bot labels mean chess.com-scale strength.
- `tools/calibrate_bots.tscn` self-play harness to set tier numbers from data.
- Game Review "played like" now shows a **range**, with accuracy as the headline.

**UI**
- Game Review modal: compact + accuracy ring + fits one screen (height cap 84→90%).
- "Analyzing game" loader: padding below Cancel.
- Removed the flip-board button (looked like undo) and the new-game matchup banner.

## Left for you (needs your machine / accounts / decisions)

1. **Name** — lock it; confirm availability on the App Store (`marketing/names.md`).
2. **URLs** — host `docs/PRIVACY_POLICY.md` and add Support + Privacy Policy URLs in App Store Connect.
3. **iPad screenshots** — required (app targets iPhone + iPad); run the screenshot tour.
4. **Calibration run** — `<godot> --headless res://tools/calibrate_bots.tscn`, then I (or you) set the tier numbers / `UCI_OVERSHOOT_ANCHORS`.
5. **Device test** — voice (incl. iPad) + iMessage; rebuild the iOS xcframework first.
6. **Signing** — register the bundle id + provisioning profile + distribution cert; tag `v1.0`.
7. **Run the headless tests** — `test_engines.gd`, `test_chesslogic.gd`, `test_puzzles.tscn`, and the screenshot tour (`test_screens.tscn`) to eyeball the new modal.

## Deferred to a later build

- **Game Center online** — re-enable the flag + entitlement + a 2-device test (v2).

## Optional cleanup

- `_make_play_banner` removal left `_banner_title_lbl` / `_banner_meta_lbl`
  (DifficultyScreen) unused and null-guarded — safe to delete.
- The orphan `WorldMapScreen` / `PlayersScreen` are unreachable (not in nav) —
  the engine picker superseded the latter; delete whenever.

## Doc index

- `docs/V1_LAUNCH_AUDIT.md` — the original launch-readiness audit.
- `docs/RATING_AUDIT.md` — rating system analysis + recommendations.
- `docs/PRIVACY_POLICY.md` — hostable privacy policy.
