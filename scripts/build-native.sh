#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
ARCH=${1:-$(uname -m)}
CONFIG=${2:-Debug}
OUT="$ROOT/artifacts/native/$ARCH/$CONFIG"
MIN_VERSION=14.0
mkdir -p "$OUT"

xcrun clang -fobjc-arc -dynamiclib -arch "$ARCH" -mmacosx-version-min="$MIN_VERSION" \
  -install_name @rpath/libZoomerNative.dylib \
  -framework AppKit -framework ScreenCaptureKit -framework Carbon \
  -framework QuartzCore -framework CoreGraphics \
  "$ROOT/native/Zoomer.Native/ZoomerNative.m" \
  -o "$OUT/libZoomerNative.dylib"

echo "$OUT/libZoomerNative.dylib"

