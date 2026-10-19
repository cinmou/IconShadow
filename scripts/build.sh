#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -quiet -project IconShadow.xcodeproj -scheme IconShadow \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData build CODE_SIGN_IDENTITY=-
/usr/bin/ditto 'build/DerivedData/Build/Products/Release/Icon Shadow.app' 'build/Icon Shadow.app'
printf 'Built: %s/build/Icon Shadow.app\n' "$PWD"
