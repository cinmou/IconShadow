#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/validation
swiftc Sources/IconShadowCore/IconRenderer.swift Sources/IconShadowCore/IconExporter.swift \
  scripts/calibration/main.swift -o build/calibrate
build/calibrate "$@"
