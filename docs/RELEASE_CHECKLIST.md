# Release checklist — work down in order

Everything that could be done in code/docs is done and statically verified
(indentation, brackets, and every cross-file call resolves). The steps below are
the ones that need **your Mac, your accounts, or a decision**. Set `GODOT` to
your editor binary first:

```bash
GODOT=/Applications/Godot_mono.app/Contents/MacOS/Godot   # adjust to your install
```

## Phase 0 — Prove it runs (do this first)

- [ ] **Open the project in Godot once** and let it import. Fix or send me any
      parse/script errors (I verified statically but couldn't run Godot here).
- [ ] **Headless tests** (each prints `RESULT: PASS` or `RESULT: PASS/FAIL`):
  ```bash
  $GODOT --headless -s res://test_chesslogic.gd
  $GODOT --headless -s res://test_engines.gd
  $GODOT --headless res://test_puzzles.tscn
  ```
- [ ] **Screenshot tour** — eyeball every screen, especially the redesigned Game
      Review modal (should fit without scrolling) and the new-game screen (no
      matchup banner, no flip button):
  ```bash
  $GODOT --path . res://test_screens.tscn   # writes to /tmp/chess_shots/
  ```

## Phase 1 — Calibrate the bots (quality)

- [ ] Run the self-play harness on a build with native Stockfish:
  ```bash
  $GODOT --headless res://tools/calibrate_bots.tscn
  ```
- [ ] Send me the `CALIBRATE RESULTS` block → I'll set the final tier numbers and
      the `UCI_OVERSHOOT_ANCHORS` mapping in `AIEngine.gd`.

## Phase 2 — Decisions & assets

- [x] **App name locked: Kingside.** Display name set via `config/name`; listing
      `Kingside – Offline Chess` (see `marketing/names.md`). Still reserve the exact
      string in App Store Connect to confirm uniqueness before submitting.
- [ ] **iPad:** generate an iPad screenshot set (the app targets iPhone + iPad),
      **or** tell me to switch `TARGETED_DEVICE_FAMILY` to iPhone-only and skip it.
- [ ] **App icon** is generated (`tools/make_icon.py`) — confirm it looks right.

## Phase 3 — App Store Connect setup

- [ ] Register the bundle id **`com.kevincardona.chess`** + the iMessage
      extension id `com.kevincardona.chess.MessagesExtension` in the Developer portal.
- [ ] Create the App ID, provisioning profile, and **distribution certificate**.
- [ ] Host `docs/PRIVACY_POLICY.md` and add the **Privacy Policy URL** + a
      **Support URL** in App Store Connect.
- [ ] Set the **privacy "nutrition label"** to *Data Not Collected* (true for the
      offline v1).
- [ ] Fill the **age rating** questionnaire (4+) and the App Review notes
      (draft is in `marketing/description.md`).
- [ ] Upload screenshots (6.7" iPhone + iPad).

## Phase 4 — Build & submit

- [ ] Rebuild the iOS xcframework (the speech crash-guard change) and export iOS
      from Godot / the committed `Chess.xcodeproj`.
- [ ] **Real-device pass:** voice moves (incl. iPad audio), iMessage send/receive.
- [ ] Archive in Xcode → upload to App Store Connect → submit for review.
- [ ] Tag the release: `git tag v1.0 && git push --tags`.

## Deferred to a later build

- [ ] **Game Center online** — re-enable the flag + entitlement + a 2-device test (v2).

## Optional cleanup

- The orphan `WorldMapScreen` / `PlayersScreen` are unreachable (the engine
  picker replaced the latter's purpose) — delete whenever you like.
