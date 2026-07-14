#!/usr/bin/env bash
#
# ios_archive.sh — produce an App-Store-uploadable .ipa (archive + export), the
# sibling of ios_deploy.sh (which only installs to a tethered device).
#
# What it does:
#   1. Export the Xcode project from Godot with --export-release (App Store config).
#   2. Pin DEVELOPMENT_TEAM in the .pbxproj (Godot bakes in a stale team).
#   3. xcodebuild archive            -> build/Chess.xcarchive
#   4. xcodebuild -exportArchive     -> build/ipa/Chess.ipa  (method: app-store-connect)
#   5. Print the upload step. Optionally upload automatically when an App Store
#      Connect API key is provided via env (see UPLOAD below).
#
# Distribution signing needs either a distribution profile already on this Mac or
# an Apple account signed into Xcode — we pass -allowProvisioningUpdates so Xcode
# can create/refresh the App Store profile. If that fails, open Chess.xcodeproj in Xcode once, Archive by
# hand to create the profiles, then this script works headlessly afterward.
#
# Usage:
#   tools/ios_archive.sh                  # export -> archive -> export .ipa
#   SKIP_EXPORT=1 tools/ios_archive.sh    # reuse the existing Xcode project
#   tools/ios_archive.sh && open build/ipa
#
#   # Optional auto-upload to App Store Connect (App Store Connect API key):
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-... \
#     ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8 UPLOAD=1 tools/ios_archive.sh
#
set -euo pipefail

# ---- config (override via env) -----------------------------------------------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PRESET="${PRESET:-iOS}"
TEAM_ID="${TEAM_ID:-46UPK9VLSD}"          # cert's OU field (same as ios_deploy.sh)
BUNDLE_ID="${BUNDLE_ID:-com.kevincardona.chess}"
SCHEME="${SCHEME:-Chess}"
XCODEPROJ="$PROJECT_DIR/Chess.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE="$BUILD_DIR/Chess.xcarchive"
IPA_DIR="$BUILD_DIR/ipa"
EXPORT_OUT="$PROJECT_DIR/Chess.ipa"       # Godot's nominal output; we use the .xcodeproj it emits

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cd "$PROJECT_DIR"

# ---- 1. export the Xcode project from Godot (RELEASE) -------------------------
if [[ "${SKIP_EXPORT:-0}" != "1" ]]; then
  [[ -x "$GODOT" ]] || die "Godot not found at $GODOT (set GODOT=/path/to/Godot)"
  bold "==> Exporting '$PRESET' (release) from Godot (headless)…"
  # --export-release embeds the template_release GDExtension (the App Store build);
  # export_project_only=true means Godot emits only the .xcodeproj, we archive below.
  "$GODOT" --headless --path "$PROJECT_DIR" --export-release "$PRESET" "$EXPORT_OUT"
else
  bold "==> SKIP_EXPORT=1 — using the existing Xcode project"
fi
[[ -d "$XCODEPROJ" ]] || die "No Xcode project at $XCODEPROJ — run a Godot iOS export first."

# ---- 1b. restore the MAINTAINED Xcode project (embeds native engine) ----
# Godot's --export regenerates a *stripped* Chess.xcodeproj that drops the native
# Stockfish xcframework embedding. The committed project
# is the source of truth (docs/DISTRIBUTION.md); restore it while keeping the pck we
# just exported so the archive actually ships real Stockfish, not the fallback.
if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bold "==> Restoring committed Chess.xcodeproj (native engine embedding)"
  git -C "$PROJECT_DIR" checkout -- Chess.xcodeproj/project.pbxproj
else
  echo "  (not a git checkout — using the exported project as-is; native engine may be missing)"
fi

# ---- 2. pin the signing team Godot baked in ----------------------------------
PBX="$XCODEPROJ/project.pbxproj"
if [[ -f "$PBX" ]]; then
  bold "==> Pinning DEVELOPMENT_TEAM=$TEAM_ID + automatic signing"
  perl -0pi -e "s/DEVELOPMENT_TEAM = [^;]+;/DEVELOPMENT_TEAM = $TEAM_ID;/g; s/CODE_SIGN_STYLE = [^;]+;/CODE_SIGN_STYLE = Automatic;/g" "$PBX"
fi

# ---- 3. archive --------------------------------------------------------------
rm -rf "$ARCHIVE" "$IPA_DIR"
mkdir -p "$BUILD_DIR"
bold "==> Archiving '$SCHEME' (Release)…"
xcodebuild \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  clean archive
[[ -d "$ARCHIVE" ]] || die "Archive failed — no .xcarchive at $ARCHIVE"

# ---- 4. export the .ipa for App Store Connect --------------------------------
OPTS_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$OPTS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

bold "==> Exporting signed .ipa…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTS_PLIST" \
  -exportPath "$IPA_DIR" \
  -allowProvisioningUpdates
IPA="$(find "$IPA_DIR" -maxdepth 1 -name '*.ipa' | head -n 1)"
[[ -n "$IPA" ]] || die "Export succeeded but no .ipa under $IPA_DIR"
bold "✅ Built $IPA"

# ---- 5. upload (optional) ----------------------------------------------------
if [[ "${UPLOAD:-0}" == "1" ]]; then
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]] \
    || die "UPLOAD=1 needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (App Store Connect API key)"
  bold "==> Uploading to App Store Connect via notarytool/altool…"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  bold "✅ Uploaded — check App Store Connect ▸ TestFlight in a few minutes."
else
  echo
  bold "Next: upload $IPA to App Store Connect"
  echo "  • Easiest: open the Transporter app, drag in the .ipa, click Deliver."
  echo "  • Or re-run with an API key:  ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=… UPLOAD=1 tools/ios_archive.sh"
fi
