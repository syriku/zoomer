#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
APP=${1:-"$ROOT/artifacts/app/Zoomer.app"}
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
ZIP="$ROOT/artifacts/Zoomer-notarization.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
ditto -c -k --keepParent "$APP" "$ROOT/artifacts/Zoomer.zip"

