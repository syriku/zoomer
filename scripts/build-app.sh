#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
CONFIG=${CONFIGURATION:-Release}
VERSION=${VERSION:-1.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
APP="$ROOT/artifacts/app/Zoomer.app"

for ARCH in arm64 x86_64; do
  "$ROOT/scripts/build-native.sh" "$ARCH" "$CONFIG"
  RID=$([[ "$ARCH" == arm64 ]] && echo osx-arm64 || echo osx-x64)
  dotnet publish "$ROOT/src/Zoomer.App/Zoomer.App.csproj" -c "$CONFIG" -f net10.0 -r "$RID" \
    -p:PublishAot=true -p:Version="$VERSION" -p:ApplicationVersion="$BUILD_NUMBER" \
    -o "$ROOT/artifacts/managed/$ARCH/$CONFIG"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
lipo -create "$ROOT/artifacts/managed/arm64/$CONFIG/Zoomer" \
  "$ROOT/artifacts/managed/x86_64/$CONFIG/Zoomer" -output "$APP/Contents/MacOS/Zoomer"
lipo -create "$ROOT/artifacts/native/arm64/$CONFIG/libZoomerNative.dylib" \
  "$ROOT/artifacts/native/x86_64/$CONFIG/libZoomerNative.dylib" \
  -output "$APP/Contents/Frameworks/libZoomerNative.dylib"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Zoomer"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@BUILD_NUMBER@/$BUILD_NUMBER/g" \
  "$ROOT/packaging/Info.plist.in" > "$APP/Contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$APP/Contents/Frameworks/libZoomerNative.dylib"
  codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$APP/Contents/MacOS/Zoomer"
  codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP/Contents/Frameworks/libZoomerNative.dylib"
  codesign --force --sign - "$APP/Contents/MacOS/Zoomer"
  codesign --force --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"
file "$APP/Contents/MacOS/Zoomer"
lipo -info "$APP/Contents/MacOS/Zoomer"
echo "$APP"
