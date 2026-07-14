# Building & distributing to every platform

The game runs on **macOS, Windows, Linux, Android and iOS** from one Godot
project. Native Stockfish ships wherever a GDExtension library has been
built; any platform without one silently falls back to the built-in GDScript
engine (weaker AI, everything else identical). Online multiplayer works on
all platforms via Firebase (see [ONLINE_SETUP.md](ONLINE_SETUP.md)).

## Quick reference

| Platform | Export preset | Native Stockfish | How to ship |
|----------|--------------|------------------|-------------|
| iOS      | `iOS`        | ✅ committed (`bin/libchess_engine.ios.*.xcframework`) | Xcode project in repo (also carries the iMessage extension) → TestFlight/App Store |
| Android  | `Android`    | ✅ arm64 committed (`bin/libchess_engine.android.*.so`) | `--export-release Android` → APK/AAB → Play Store or sideload |
| macOS    | `macOS`      | ✅ arm64 + x86_64 committed | `--export-release macOS` → DMG (notarize for distribution) |
| Windows  | `Windows`    | via CI or local mingw build | `--export-release Windows` → single exe (pck embedded) |
| Linux    | `Linux`      | via CI | `--export-release Linux` → single x86_64 binary |

## Exporting locally

```bash
GODOT=/Applications/Godot_mono.app/Contents/MacOS/Godot

# Always run first: enables only the native libs that actually exist, so
# exports never fail on a missing dll/so.
python3 tools/sync_gdextension_manifest.py

$GODOT --headless --path . --export-release "macOS"   ~/Desktop/Chess.dmg
$GODOT --headless --path . --export-release "Windows" ~/Desktop/Chess-Windows/Chess.exe
$GODOT --headless --path . --export-release "Linux"   ~/Desktop/Chess-Linux/Chess.x86_64
$GODOT --headless --path . --export-release "Android" ~/Desktop/Chess.apk
```

iOS: export once from Godot (or use the committed `Chess.xcodeproj`), then
build/sign in Xcode as usual. The iMessage extension target is added by
`ruby tools/add_messages_extension.rb` (idempotent).

Android signing: the preset uses the debug keystore by default; for Play
Store set a release keystore in the preset or `EDITOR_SETTINGS`.

## Building native Stockfish libs

```bash
cd gdextension
./build_stockfish_extension.sh macos arm64      # Apple Silicon
./build_stockfish_extension.sh macos x86_64     # Intel Macs
./build_stockfish_extension.sh windows x86_64   # cross-compiles via mingw-w64 (brew install mingw-w64)
ANDROID_NDK_ROOT=$HOME/Library/Android/sdk/ndk/28.1.13356709 \
  ./build_stockfish_extension.sh android arm64
./build_stockfish_extension.sh ios              # produces the xcframework
# linux: build on a Linux box or let CI do it
```

After building, run `python3 tools/sync_gdextension_manifest.py` to flip the
new lib on in `chess_engine.gdextension`.

## CI (set it and forget it)

`.github/workflows/build-release.yml` builds the Linux/Windows/Android libs
on GitHub runners and exports Linux/Windows/macOS binaries as artifacts.
Trigger it by pushing a tag (`git tag v1.0.0 && git push --tags`) or manually
from the Actions tab.

The Stockfish sources are **not** a fetchable submodule — CI clones upstream
at the pinned ref and applies `gdextension/patches/stockfish-18-single-nnue.patch`
(the single-NNUE modifications). If you ever touch the local
`gdextension/stockfish` checkout, regenerate the patch:

```bash
git -C gdextension/stockfish diff > gdextension/patches/stockfish-18-single-nnue.patch
```

Pinned refs (update in the workflow env if you bump either):
- Stockfish `cb3d4ee9b47d0c5aae855b12379378ea1439675c` (Stockfish 18)
- godot-cpp `3a7edf0ea34fac0623ef3013d60362e9d01654d2`

## Platform notes

- **Voice input** is macOS/iOS only (native SFSpeechRecognizer); the mic
  button hides itself elsewhere.
- **Game Center** (leaderboard, iMessage friend invites) is Apple-only and
  appears alongside the cross-platform online play on those devices.
- The **Android preset ships arm64 only** — that covers practically every
  phone from ~2017 on. Enable armeabi-v7a only if you also build that lib.
- The committed `build/` Xcode products and `Chess.xcodeproj` are the iOS
  pipeline; don't delete them when cleaning.
