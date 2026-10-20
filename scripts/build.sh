#!/usr/bin/env bash
# Generates the Xcode project and builds Gondar.app; prints the app's path.
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
xcodegen generate --quiet
xcodebuild -project Gondar.xcodeproj -scheme Gondar -configuration "$configuration" \
  -derivedDataPath build/DerivedData -quiet build
echo "build/DerivedData/Build/Products/$configuration/Gondar.app"
