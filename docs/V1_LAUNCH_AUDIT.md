# Kingside – Offline Chess — v1 Launch-Readiness Audit

_Prepared June 23, 2026. Scope: deep-dive on the engine-install question, the
multiplayer cut, analytics, and everything required to pass App Store review.
This is the audit; code changes come after you've signed off._

---

## TL;DR — the decisions

| Question | Verdict | Why |
|---|---|---|
| "Install different engines from inside the app, run on iOS" | **Reframe.** You can't download + run engine *binaries* on iOS, but you can ship multiple **engine personalities** (same Stockfish binary, different net/config) and download new **config/net data** over the air. | Apple Guideline 2.5.2 bans downloading/executing code. A net file and UCI options are *data*, not code. |
| Multiplayer in v1 | **Cut it (already 90% done).** | Flag is already `false`; Game Center never signs in on launch. Small cleanup left. Matches the "Offline Chess" name. |
| Analytics | **Not required. Use the free, zero-SDK path for v1.** | App Store Connect + Xcode Organizer give you installs, retention and crashes with no SDK and no privacy cost. |

**Overall:** the app itself is in good shape for a v1. The launch blockers are
mostly **metadata and configuration**, not code.

---

## 1. "Different chess engines" on iOS — what's actually possible

Your instinct — *"isn't an engine just a big config file that tells our system
how to run?"* — is **half right, and the half that's wrong is the important
one.** Here's the precise picture, from your own code.

A chess engine like Stockfish is **two things**:

1. **The program** — Stockfish's search and evaluation, written in C++ and
   **compiled to native machine code**. In your repo this is built into
   `gdextension/bin/libchess_engine.ios.*.xcframework` and exposed to GDScript
   as the `ChessEngine` class (`AINativeBackend.gd`). This is **executable
   code**, not config.
2. **The brain** — the NNUE neural-network weights file
   (`nn-37f18f62d772.nnue`, ~the evaluation "knowledge"). This **is data.** Your
   C++ already supports loading it *either* embedded in the binary *or* from a
   file path (`chess_engine.cpp`: `_get_nnue_path()` / `_set_nnue_file()` →
   sets the `EvalFile` UCI option).

On top of those sit the things that make a bot feel weak/strong/stylistic — the
**UCI options and presets** in `AIEngine.gd` (`DIFFICULTIES`, `set_option`,
Skill Level, `UCI_Elo`, movetime, the opening book, the blunder rates). All of
that is **data/config too.**

### The rule that decides everything: Guideline 2.5.2

> "Apps … may not download, install, or execute code which introduces or
> changes features or functionality of the app."

Apple applies a **functional test**: did downloaded content change what the app
fundamentally *does/runs*? In 2026 they've been actively enforcing this (they
pulled several "vibe-coding" apps that download executable behavior). So:

| You want to… | Is it code or data? | iOS-legal? |
|---|---|---|
| Download a new **Stockfish/Leela binary** and run it | **Code** | ❌ Rejected under 2.5.2 |
| Swap to a **different NNUE net** (file) | Data | ✅ Yes — even downloadable at runtime |
| Add **new difficulty/personality presets** (UCI options, opening book) | Data | ✅ Yes — even downloadable |
| Bundle a **second real engine** (e.g. a different algorithm) | Code, but **compiled in at build time** | ✅ Yes — it ships in the app |

### What this means for "different engines" — the compliant design

You can absolutely give users a screen that **looks** like "pick / install
different engines." You just build it out of the three legal pieces:

- **Personalities over one binary.** Each entry = the bundled Stockfish + a
  named **config preset** (and optionally a different **net file**). "Aggressive
  1600", "Positional 1800", "Endgame trainer", "Maximum" — all the same engine
  code, different *data*. Your `set_option` + `DIFFICULTIES` plumbing already
  does 90% of this.
- **Downloadable engine *packs* (data only).** If you later want an
  "install" button that fetches more opponents over the air, ship **net files +
  config JSON**, not executables. That's data, fully allowed, and doesn't even
  need an app update. (You'd add an integrity check + a bundled fallback.)
- **A genuinely different engine** (say Leela-style) is allowed **only if you
  compile it into the app** and bundle it like Stockfish — then it's just
  another entry in the same picker. It can't be downloaded.

**Recommendation:** build an in-app **"Opponents / Engines" picker** backed by
config presets (+ optional per-entry net), with the architecture leaving room
for downloadable *data* packs in v2. That delivers the experience you're after
and passes review. What we should *not* do is build a binary downloader — it
will get the app rejected.

---

## 2. Multiplayer — cut for v1 (mostly already done)

You're in better shape than you think. The current state in code:

- **The flag is already off.** `GameManager.gd` → `feature_flags["multiplayer"]
  = false`. The "Play Online" button only renders when that's true
  (`MainMenuScreen.gd:71`), so **it's already hidden.**
- **Nothing signs into Game Center on launch.** `GameCenterManager.authenticate()`
  is only ever called from a button inside `OnlineScreen`
  (`OnlineScreen.gd:193`), which is now unreachable. So the "pure offline" claim
  genuinely holds at runtime — no surprise sign-in prompt.
- **The README contradicts the code.** README still says `multiplayer: true` and
  "Game Center online play is ON." That's stale and needs fixing so you don't
  ship docs that promise a cut feature.

### One decision hiding inside "multiplayer": iMessage ≠ Game Center

There are **two different online-ish features**, and they're not the same call:

- **Game Center turn-based** (`OnlineScreen` / `GameCenterManager`) — this is the
  "Play Online" you said "doesn't work great." **Cut it.**
- **iMessage play-a-friend** (`MessagesExtension/`) — separate, **serverless**
  (game state travels in the message), and it's a nice differentiator your
  listing leans on. It's not "online multiplayer" in the fragile sense.

My recommendation: **cut Game Center, keep iMessage.** But note that "keep
iMessage" slightly complicates a *purist* "100% offline" line (it sends
messages). If you want the cleanest possible story, you could defer iMessage too
— your call. I'd keep it.

### To fully land the cut (small)

- Leave `multiplayer: false` (done).
- **Remove the Game Center capability/entitlement** (`ChessMessages.entitlements`
  has `com.apple.developer.game-center = true`; the app target has it too) so a
  reviewer doesn't ask why an "offline" app requests Game Center.
- Fix the README + any "Online" mention in marketing.
- Decide iMessage in or out.

---

## 3. Analytics — optional, and you can get the useful 80% for free

Analytics is **not required for approval**, and you do not need a heavy SDK.

- **Free, zero-SDK, zero-privacy-cost (recommended for v1):** App Store Connect
  gives you impressions, downloads, retention and conversion; Xcode Organizer
  gives you crash reports and energy/perf metrics from real users. No code, no
  privacy-label impact. For a v1 this is genuinely enough to see if the app is
  landing.
- **If you want in-app funnel data** (e.g. "how many finish the puzzle journey"),
  add a **privacy-light** analytics layer — but know it adds another third-party
  SDK declaration to the privacy manifest and shifts your "no data collected"
  label. A third-party analytics SDK is the thing that *breaks* the clean
  privacy story.

**Recommendation:** v1 = built-in App Store Connect + Organizer only. Add in-app
analytics later only if you decide the funnel data is worth the privacy-label
cost.

---

## 4. What else you need to get approved — the checklist

These are the concrete blockers I found in the project. Most are
**metadata/config, not code.**

### Will likely cause a rejection or upload failure

- **Unused permission strings.** `Chess-Info.plist` declares
  `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` "reserved for
  future chess position import features." Requesting access for features that
  don't exist is a classic **Guideline 5.1.1** rejection. **Remove both for v1**
  (keep mic + speech — those are real). Re-add when the import feature ships.
- **iPad screenshots are mandatory.** The project targets iPhone **and** iPad
  (`TARGETED_DEVICE_FAMILY = "1,2"`). Apple requires iPad screenshots when the
  app runs on iPad — your marketing notes treat iPad as "optional," which is
  wrong given this setting. Either (a) generate iPad screenshots, or (b) drop
  iPad by setting the family to `"1"` (also removes iPad from your test matrix).
- **Empty version strings in the iOS export preset.** `export_presets.cfg` has
  `application/short_version=""` and `application/version=""`. Set these
  (CFBundleShortVersionString / CFBundleVersion, e.g. `1.0` / `1`) or the
  App Store Connect upload can be rejected.
- **Privacy Policy URL + Support URL.** Both are "_add before submission_" in
  `marketing/description.md`. A Support URL is required; a Privacy Policy URL is
  required outright if you add analytics, and strongly expected regardless.

### Should fix / confirm before submitting

- **Game Center entitlement** still present while multiplayer is cut — remove it
  (see §2) to avoid reviewer questions and an unused capability.
- **Encryption compliance — already handled.** `ITSAppUsesNonExemptEncryption`
  is present and set to `false` in `Chess-Info.plist`, so Apple won't prompt
  export-compliance on every upload. ✅ Nothing to do.
- **Bundle IDs.** App = `kevincardona.Chess`, iMessage =
  `kevincardona.Chess.MessagesExtension`. They're consistent (good) but not
  conventional reverse-DNS. Make sure both are registered in the Developer
  portal with matching provisioning profiles and a distribution cert. The bundle
  ID stays `com.kevincardona.chess` (already consistent everywhere); the brand is
  carried by the display name "Kingside", not the bundle ID.
- **App privacy "nutrition label"** in App Store Connect must match reality:
  "Data Not Collected" if you stay analytics-free; updated if you don't.
- **Final name.** **Kingside** (locked) — display name set via `config/name`;
  listing *Kingside – Offline Chess*. Reserve the exact string in App Store Connect.
- **README/code drift.** README says multiplayer is ON; code says off. Fix so
  the repo is internally consistent.
- **Orphan screens.** `WorldMapScreen` / `PlayersScreen` aren't in v1 nav (per
  the release checklist) — leave out or remove so they can't be reached.

### Standard submission gates (no blockers found, just confirm)

- App icon opaque + all sizes (you have `tools/make_icon.py`); launch screen set.
- Real-device pass: voice (incl. iPad audio-format guard), iMessage send/receive,
  rebuild the iOS xcframework after the speech crash-guard change.
- Age-rating questionnaire filled (4+), App Review notes (you have draft notes).
- Crash-free launch on a clean device; no placeholder content (Guideline 2.1).

---

## 5. Prioritized v1 punch list

**Before any submission (must):**

- [ ] Remove camera + photo-library usage strings from `Chess-Info.plist`.
- [ ] Set iOS export version strings (`short_version`, `version`).
- [ ] Decide iPad: generate iPad screenshots **or** set device family to iPhone-only.
- [ ] Add Support URL + Privacy Policy URL.
- [ ] Confirm `ITSAppUsesNonExemptEncryption = false`.
- [ ] Register/confirm bundle IDs + provisioning + distribution cert.

**Land the decisions you've made:**

- [ ] Multiplayer: keep flag off, remove Game Center entitlement, fix README, decide iMessage.
- [ ] Engines: build the config-preset "Opponents/Engines" picker (no binary downloader).
- [ ] Analytics: rely on App Store Connect + Organizer for v1.

**Polish:**

- [ ] Remove/seal orphan screens.
- [ ] Playtest bot tiers, tune `blunder` rates.
- [ ] Version bump + tag `v1.0`.

---

## Sources

- [App Review Guidelines — Apple Developer (Guideline 2.5.2)](https://developer.apple.com/app-store/review/guidelines/)
- [Why did Apple reject my app for Guideline 2.5.2? — PTKD Journal](https://ptkd.com/journal/guideline-2-5-2-downloading-scripts-without-review)
- [Apple steps up crackdown on "vibe coding" apps over 2.5.2 — 9to5Mac (2026)](https://9to5mac.com/2026/03/30/apple-steps-up-crackdown-on-vibe-coding-apps-pulls-anything-from-the-app-store/)
- [User Privacy and Data Use — Apple Developer](https://developer.apple.com/app-store/user-privacy-and-data-use/)

_Repo evidence cited inline: `AIEngine.gd`, `AINativeBackend.gd`,
`gdextension/src/chess_engine.cpp`, `GameManager.gd`, `MainMenuScreen.gd`,
`OnlineScreen.gd`, `Chess-Info.plist`, `ChessMessages.entitlements`,
`PrivacyInfo.xcprivacy`, `export_presets.cfg`, `Chess.xcodeproj/project.pbxproj`,
`marketing/description.md`._
