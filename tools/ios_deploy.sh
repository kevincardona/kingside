#!/usr/bin/env bash
#
# ios_deploy.sh — one command: export from Godot, sign with the RIGHT team, install to your iPhone.
#
# Why this exists:
#   Godot regenerates "Chess.xcodeproj" on every iOS export and bakes in a stale
#   DEVELOPMENT_TEAM that has no signing cert on this Mac. Opening Xcode and re-picking
#   the team by hand every time is the pain this script removes. We override the team at
#   `xcodebuild` time (command-line build settings beat anything in the .pbxproj), let Xcode
#   auto-create the provisioning profile, then push the .app to the device with devicectl.
#
#   Requires export_presets.cfg → application/export_project_only=true (already set), so
#   Godot only emits the .xcodeproj and never tries to build/sign the .ipa itself.
#
# Usage:
#   tools/ios_deploy.sh                 # export from Godot -> build+sign -> install -> launch
#   SKIP_EXPORT=1 tools/ios_deploy.sh   # you already exported from the Godot editor; just sign+install
#   FAST=1 tools/ios_deploy.sh          # incremental build (skip 'clean') — much faster for repeat updates
#   CONFIG=Release tools/ios_deploy.sh  # build the Release config instead of Debug
#   DEVICE_ID=<uuid> tools/ios_deploy.sh  # target a specific device (default: first connected one)
#   NO_LAUNCH=1 tools/ios_deploy.sh     # install but don't auto-launch
#
set -euo pipefail

# ---- config (override any of these via env) ----------------------------------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PRESET="${PRESET:-iOS}"
TEAM_ID="${TEAM_ID:-46UPK9VLSD}"          # your Apple Team ID. NOTE: this is the cert's OU field, NOT the
                                          # parenthetical `security find-identity` prints. Confirm with:
                                          #   security find-certificate -c "Apple Development: Kevin Cardona" -p \
                                          #     | openssl x509 -noout -subject   # -> OU=<TEAM_ID>
BUNDLE_ID="${BUNDLE_ID:-com.kevincardona.chess}"
SCHEME="${SCHEME:-Chess}"
XCODEPROJ="$PROJECT_DIR/Chess.xcodeproj"
CONFIG="${CONFIG:-Debug}"
DERIVED="$PROJECT_DIR/.build/ios"
EXPORT_OUT="$PROJECT_DIR/Chess.ipa"       # Godot's nominal output path; we use the .xcodeproj it emits

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cd "$PROJECT_DIR"

# ---- 1. export the Xcode project from Godot ----------------------------------
if [[ "${SKIP_EXPORT:-0}" != "1" ]]; then
  [[ -x "$GODOT" ]] || die "Godot not found at $GODOT (set GODOT=/path/to/Godot)"
  bold "==> Exporting '$PRESET' from Godot (headless)…"
  # --export-debug emits the Xcode project into the project dir. With export_project_only=true
  # in export_presets.cfg, Godot does NOT try to build/sign the .ipa itself — we do that below.
  "$GODOT" --headless --path "$PROJECT_DIR" --export-debug "$PRESET" "$EXPORT_OUT"
else
  bold "==> SKIP_EXPORT=1 — using the existing Xcode project"
fi
[[ -d "$XCODEPROJ" ]] || die "No Xcode project at $XCODEPROJ — run a Godot iOS export first."

# ---- 1b. restore the MAINTAINED Xcode project (embeds native engine) ----
# Godot's --export regenerates a *stripped* Chess.xcodeproj: it drops the native
# Stockfish xcframework embedding, so the app silently
# falls back to the GDScript engine (games go unrated). The committed project is the
# source of truth (see docs/DISTRIBUTION.md) — it embeds the engine framework and
# keeps the "Kingside" display name. Restore it while KEEPING the pck we just
# exported (latest scripts/assets), then sign + build below.
if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bold "==> Restoring committed Chess.xcodeproj (native engine embedding)"
  git -C "$PROJECT_DIR" checkout -- Chess.xcodeproj/project.pbxproj
else
  echo "  (not a git checkout — using the exported project as-is; native engine may be missing)"
fi

# ---- 2. auto-fix the team Godot baked in (so opening Xcode by hand is clean too) ----
# The global (/g) replace covers the app target.
PBX="$XCODEPROJ/project.pbxproj"
if [[ -f "$PBX" ]]; then
  bold "==> Pinning DEVELOPMENT_TEAM=$TEAM_ID + automatic signing in the project"
  perl -0pi -e "s/DEVELOPMENT_TEAM = [^;]+;/DEVELOPMENT_TEAM = $TEAM_ID;/g; s/CODE_SIGN_STYLE = [^;]+;/CODE_SIGN_STYLE = Automatic;/g" "$PBX"
fi

# ---- 2b. refresh Chess.pck from the CURRENT scripts --------------------------
# The Xcode "Rebuild Chess.pck" phase defaults GODOT_BIN to Godot_mono and, when
# that's absent, silently uses the STALE checked-in Chess.pck — so GDScript edits
# never reach the device. Regenerate the pck here with the same Godot we export
# with, so every deploy actually ships the latest code.
if [[ "${SKIP_EXPORT:-0}" != "1" ]]; then
  bold "==> Refreshing Chess.pck from current scripts…"
  "$GODOT" --headless --path "$PROJECT_DIR" --export-pack "$PRESET" "$PROJECT_DIR/Chess.pck" || {
    [[ -f "$PROJECT_DIR/Chess.pck" ]] || die "export-pack failed and Chess.pck missing"
    echo "  (Godot exited nonzero after writing the pck — continuing)"
  }
fi

# ---- 3. build + sign for a real device ---------------------------------------
# FAST=1 → incremental (skip 'clean'); fine for GDScript/scene/asset changes and much quicker on
# repeat deploys. Use a full build (default) after engine/export-template or signing changes.
# GODOT_BIN → the build phase rebuilds the pck with the real Godot instead of the stale fallback.
BUILD_ACTION="clean build"
[[ "${FAST:-0}" == "1" ]] && BUILD_ACTION="build"
bold "==> Building '$SCHEME' ($CONFIG) for device with forced signing… [${BUILD_ACTION}]"
GODOT_BIN="$GODOT" xcodebuild \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  $BUILD_ACTION
  # Note: no -allowProvisioningUpdates — we sign with the existing local profile, so no Apple
  # account needs to be signed into Xcode. If these profiles ever expire, open the project in
  # Xcode once and build to device to refresh them, then this script keeps working headlessly.

APP="$DERIVED/Build/Products/$CONFIG-iphoneos/$SCHEME.app"
[[ -d "$APP" ]] || die "Build succeeded but no .app at $APP"

# ---- 4. pick a connected device ----------------------------------------------
if [[ -z "${DEVICE_ID:-}" ]]; then
  bold "==> Finding a connected device…"
  TMPJSON="$(mktemp)"
  xcrun devicectl list devices --json-output "$TMPJSON" >/dev/null 2>&1 || true
  DEVICE_ID="$(python3 - "$TMPJSON" <<'PY'
import json, sys
try:
    devs = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devs:
    if d.get("connectionProperties", {}).get("tunnelState") == "connected":
        print(d["identifier"]); break
PY
)"
  rm -f "$TMPJSON"
fi
[[ -n "$DEVICE_ID" ]] || die "No connected device found. Plug in your iPhone/iPad, unlock it, and trust this Mac."

# ---- 5. install (+ launch) ---------------------------------------------------
bold "==> Installing to device $DEVICE_ID…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

if [[ "${NO_LAUNCH:-0}" != "1" ]]; then
  bold "==> Launching $BUNDLE_ID…"
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || \
    echo "  (install OK; auto-launch failed — just tap the app on your phone)"
fi

bold "✅ Done — '$SCHEME' is on your device."
