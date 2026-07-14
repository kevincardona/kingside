#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${TARGET:-template_release}"
PLATFORM="${1:-${PLATFORM:-macos}}"
ARCH="${2:-${ARCH:-arm64}}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

case "$PLATFORM" in
  macos|ios|android|linux|windows) ;;
  *)
    echo "Unsupported platform: $PLATFORM" >&2
    exit 2
    ;;
esac

case "$TARGET" in
  editor|template_debug|template_release) ;;
  *)
    echo "Unsupported TARGET: $TARGET" >&2
    exit 2
    ;;
esac

if [[ ! -d "$ROOT/godot-cpp" ]]; then
  echo "Missing $ROOT/godot-cpp" >&2
  exit 1
fi

mkdir -p "$ROOT/bin"

# INCBIN embeds the NNUE directly into the compiled binary, so it must exist
# in stockfish/src/ at compile time. The file is gitignored in the submodule,
# so we look for it in the known locations and copy it if missing.
NNUE_NAME="nn-37f18f62d772.nnue"
NNUE_SRC="$ROOT/stockfish/src/$NNUE_NAME"
NNUE_CANDIDATES=(
  "$ROOT/bin/$NNUE_NAME"
  "$ROOT/data/$NNUE_NAME"
  "$ROOT/../stockfish/$NNUE_NAME"
)
if [[ ! -f "$NNUE_SRC" ]]; then
  for candidate in "${NNUE_CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "Copying NNUE to stockfish/src/ for INCBIN embedding: $candidate"
      cp "$candidate" "$NNUE_SRC"
      break
    fi
  done
fi
if [[ ! -f "$NNUE_SRC" ]]; then
  echo "WARNING: $NNUE_SRC not found. INCBIN embedding will be skipped." >&2
  echo "         Download from: https://tests.stockfishchess.org/api/nn/$NNUE_NAME" >&2
  echo "         and place it at: $NNUE_SRC" >&2
fi

# Cross-compiling Windows binaries from macOS/Linux uses MinGW
# (brew install mingw-w64 / apt install mingw-w64).
GDCPP_EXTRA=()
if [[ "$PLATFORM" == "windows" && "$(uname -s)" != MINGW* && "$(uname -s)" != *NT* ]]; then
  GDCPP_EXTRA+=(use_mingw=yes)
fi

echo "Building godot-cpp: platform=$PLATFORM arch=$ARCH target=$TARGET"
(
  cd "$ROOT/godot-cpp"
  # ${arr[@]+...} guards the empty-array case: macOS bash 3.2 + `set -u` treats
  # expanding an empty array as an unbound variable and aborts the build.
  scons "platform=$PLATFORM" "arch=$ARCH" "target=$TARGET" ${GDCPP_EXTRA[@]+"${GDCPP_EXTRA[@]}"} "-j$JOBS"
)

BUILD_DIR="$ROOT/build-$PLATFORM-$TARGET-$ARCH"
CMAKE_ARGS=(
  -S "$ROOT"
  -B "$BUILD_DIR"
  -DGTARGET="$TARGET"
  -DGPLATFORM="$PLATFORM"
  -DGARCH="$ARCH"
  -DCMAKE_BUILD_TYPE=Release
)

if [[ "$PLATFORM" == "android" ]]; then
  NDK="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
  if [[ -z "$NDK" ]]; then
    echo "Set ANDROID_NDK_ROOT before building Android." >&2
    exit 1
  fi
  case "$ARCH" in
    arm64) ABI="arm64-v8a" ;;
    arm32) ABI="armeabi-v7a" ;;
    x86_64) ABI="x86_64" ;;
    x86_32) ABI="x86" ;;
    *)
      echo "Unsupported Android arch: $ARCH" >&2
      exit 2
      ;;
  esac
  CMAKE_ARGS+=(
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
    -DANDROID_ABI="$ABI"
    -DANDROID_PLATFORM=android-24
  )
fi

if [[ "$PLATFORM" == "windows" && "$(uname -s)" != MINGW* && "$(uname -s)" != *NT* ]]; then
  CMAKE_ARGS+=(
    -DCMAKE_SYSTEM_NAME=Windows
    -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc
    -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++
    -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres
  )
fi

if [[ "$PLATFORM" == "ios" ]]; then
  CMAKE_ARGS+=(
    -G Xcode
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
  )
elif [[ "$PLATFORM" == "macos" && "$ARCH" == "universal" ]]; then
  CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64")
elif [[ "$PLATFORM" == "macos" ]]; then
  CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES="$ARCH")
fi

echo "Configuring extension: platform=$PLATFORM arch=$ARCH target=$TARGET"
cmake "${CMAKE_ARGS[@]}"

echo "Building extension"
cmake --build "$BUILD_DIR" --config Release --parallel "$JOBS"

if [[ "$PLATFORM" == "ios" ]]; then
  FRAMEWORK="$(find "$BUILD_DIR" -name "*chess_engine.ios.$TARGET.$ARCH.framework" -type d | head -n 1)"
  if [[ -z "$FRAMEWORK" ]]; then
    echo "Could not find built iOS framework in $BUILD_DIR" >&2
    exit 1
  fi
  # CRITICAL: the inner framework (and its binary + CFBundleExecutable) must be
  # named exactly the xcframework's basename — libchess_engine.ios.$TARGET — with
  # no arch suffix. At runtime Godot resolves the .gdextension's xcframework path
  # to Frameworks/<basename>.framework/<basename> inside the app bundle and
  # dlopens that; the arch-suffixed name CMake produces is never found, so the
  # engine silently falls back to GDScript ("Stockfish unavailable / unrated").
  NEWNAME="libchess_engine.ios.$TARGET"
  STAGE="$(mktemp -d)"
  mkdir "$STAGE/$NEWNAME.framework"
  BIN="$(basename "$FRAMEWORK" .framework)"
  cp "$FRAMEWORK/$BIN" "$STAGE/$NEWNAME.framework/$NEWNAME"
  cp "$FRAMEWORK/Info.plist" "$STAGE/$NEWNAME.framework/Info.plist"
  plutil -replace CFBundleExecutable -string "$NEWNAME" "$STAGE/$NEWNAME.framework/Info.plist"
  plutil -replace CFBundleName -string "$NEWNAME" "$STAGE/$NEWNAME.framework/Info.plist"
  # Both variants ship embedded in one app, so their CFBundleIdentifiers must
  # differ or iOS rejects the install with "DuplicateIdentifier". (Loading is by
  # path, not bundle id, so a distinct id is harmless to dlopen.)
  BID="com.kevincardona.chess.chess-engine"
  [[ "$TARGET" == "template_release" ]] && BID="$BID-rel"
  plutil -replace CFBundleIdentifier -string "$BID" "$STAGE/$NEWNAME.framework/Info.plist"
  install_name_tool -id "@rpath/$NEWNAME.framework/$NEWNAME" "$STAGE/$NEWNAME.framework/$NEWNAME" 2>/dev/null || true
  codesign --force --sign - "$STAGE/$NEWNAME.framework" >/dev/null 2>&1 || true
  OUT="$ROOT/bin/libchess_engine.ios.$TARGET.xcframework"
  rm -rf "$OUT"
  xcodebuild -create-xcframework -framework "$STAGE/$NEWNAME.framework" -output "$OUT"
  rm -rf "$STAGE"
  echo "Wrote $OUT"
else
  BUILT="$(find "$BUILD_DIR/bin" -maxdepth 1 -type f -name "*chess_engine.$PLATFORM.$TARGET.$ARCH.*" | head -n 1)"
  if [[ -z "$BUILT" ]]; then
    echo "Could not find built extension in $BUILD_DIR/bin" >&2
    exit 1
  fi
  cp "$BUILT" "$ROOT/bin/"
  echo "Wrote $ROOT/bin/$(basename "$BUILT")"
fi

if [[ "$TARGET" == "template_release" && "$PLATFORM" != "ios" ]]; then
  EXT="${BUILT##*.}"
  PREFIX="lib"
  [[ "$PLATFORM" == "windows" ]] && PREFIX=""
  RELEASE="$ROOT/bin/${PREFIX}chess_engine.$PLATFORM.template_release.$ARCH.$EXT"
  ln -sf "$(basename "$RELEASE")" "$ROOT/bin/${PREFIX}chess_engine.$PLATFORM.editor.$ARCH.$EXT"
  ln -sf "$(basename "$RELEASE")" "$ROOT/bin/${PREFIX}chess_engine.$PLATFORM.template_debug.$ARCH.$EXT"
fi
