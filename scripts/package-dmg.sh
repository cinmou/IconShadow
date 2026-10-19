#!/bin/zsh
# Developer ID distribution. Credentials are read from Keychain, never embedded.
# SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
# NOTARY_KEYCHAIN_PROFILE='your-notary-profile' ./scripts/package-dmg.sh
set -euo pipefail
cd "${0:A:h:h}"
PROJECT_ROOT="$PWD"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to a Developer ID Application identity}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool Keychain profile}"
if [[ "$SIGN_IDENTITY" != 'Developer ID Application:'* ]]; then
  print -u2 'A Developer ID Application identity is required.'
  exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
ARTIFACT_DIR="$PROJECT_ROOT/build/release/$VERSION"
DERIVED_DATA="$PROJECT_ROOT/build/ReleaseDerivedData"
APP_NAME='Icon Shadow.app'
DMG_NAME="IconShadow-$VERSION.dmg"
DMG_PATH="$ARTIFACT_DIR/$DMG_NAME"
command -v create-dmg >/dev/null || { print -u2 'Install create-dmg: brew install create-dmg'; exit 1; }
[[ ! -e "$DMG_PATH" ]] || { print -u2 "Already exists: $DMG_PATH"; exit 1; }
mkdir -p "$ARTIFACT_DIR/logs"
WORK_DIR=$(mktemp -d "$PROJECT_ROOT/build/package.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
APP_PATH="$WORK_DIR/$APP_NAME"

notarize() {
  local payload="$1" label="$2" submission_id notarization_status
  xcrun notarytool submit "$payload" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --output-format json > "$ARTIFACT_DIR/logs/$label-submission.json"
  submission_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$ARTIFACT_DIR/logs/$label-submission.json")
  print "Notarization $label: $submission_id"
  xcrun notarytool wait "$submission_id" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --timeout 30m --output-format json > "$ARTIFACT_DIR/logs/$label-result.json"
  notarization_status=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$ARTIFACT_DIR/logs/$label-result.json")
  xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    "$ARTIFACT_DIR/logs/$label-notarization.json"
  [[ "$notarization_status" == Accepted ]] || { print -u2 "Notarization failed: $notarization_status"; return 1; }
}

print "Building Icon Shadow $VERSION (universal Release)"
xcodebuild -quiet -project IconShadow.xcodeproj -scheme IconShadow \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- build
/usr/bin/ditto "$DERIVED_DATA/Build/Products/Release/$APP_NAME" "$APP_PATH"
[[ "$(lipo -archs "$APP_PATH/Contents/MacOS/Icon Shadow")" == *arm64* ]] || exit 1
[[ "$(lipo -archs "$APP_PATH/Contents/MacOS/Icon Shadow")" == *x86_64* ]] || exit 1
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvvv "$APP_PATH" 2> "$ARTIFACT_DIR/logs/app-signature.txt"

# Staple the app too, so it retains an offline ticket after being copied out of the DMG.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$WORK_DIR/notarization.zip"
notarize "$WORK_DIR/notarization.zip" app
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

mkdir "$WORK_DIR/dmg-stage"
/usr/bin/ditto "$APP_PATH" "$WORK_DIR/dmg-stage/$APP_NAME"
swift scripts/make-dmg-background.swift "$WORK_DIR/background.png" "$VERSION"
# As in MicaGo, Finder coordinates are points, not Retina pixels.
DMG_BACKGROUND_PATH="$WORK_DIR/background.png"
DMG_WINDOW_WIDTH=$(sips -g pixelWidth -g dpiWidth "$DMG_BACKGROUND_PATH" | awk '/pixelWidth/ {pixels=$2} /dpiWidth/ {dpi=$2} END {printf "%.0f", pixels * 72 / dpi}')
DMG_WINDOW_HEIGHT=$(sips -g pixelHeight -g dpiHeight "$DMG_BACKGROUND_PATH" | awk '/pixelHeight/ {pixels=$2} /dpiHeight/ {dpi=$2} END {printf "%.0f", pixels * 72 / dpi}')
APP_ICON_X=$((DMG_WINDOW_WIDTH * 180 / 660))
APP_ICON_Y=$((DMG_WINDOW_HEIGHT * 216 / 420))
APPLICATIONS_ICON_X=$((DMG_WINDOW_WIDTH * 480 / 660))
print "Finder layout: ${DMG_WINDOW_WIDTH}x${DMG_WINDOW_HEIGHT} points; icons at ${APP_ICON_X},${APP_ICON_Y} and ${APPLICATIONS_ICON_X},${APP_ICON_Y}"
print 'Creating disk image'
create-dmg --volname 'Icon Shadow' \
  --volicon "$APP_PATH/Contents/Resources/IconShadow.icns" \
  --background "$DMG_BACKGROUND_PATH" --window-pos 100 100 \
  --window-size "$DMG_WINDOW_WIDTH" "$DMG_WINDOW_HEIGHT" \
  --text-size 13 --icon-size 96 --icon "$APP_NAME" "$APP_ICON_X" "$APP_ICON_Y" \
  --hide-extension "$APP_NAME" --app-drop-link "$APPLICATIONS_ICON_X" "$APP_ICON_Y" \
  --no-internet-enable --hdiutil-quiet "$DMG_PATH" "$WORK_DIR/dmg-stage"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
notarize "$DMG_PATH" dmg
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
/usr/bin/ditto "$APP_PATH" "$ARTIFACT_DIR/$APP_NAME"
(cd "$ARTIFACT_DIR" && shasum -a 256 "$DMG_NAME" > SHA256SUMS.txt)
print "Release ready: $DMG_PATH"
