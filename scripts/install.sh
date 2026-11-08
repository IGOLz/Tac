#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
swift build -c release
app="$PWD/build/Tac.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Tac "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --options runtime --sign "Developer ID Application: Alexandru Ciprian Craciun (884UZN5CH3)" "$app"
codesign --verify --strict "$app"
# Stop only the installed Tac before replacing its executable.
pkill -x -f /Applications/Tac.app/Contents/MacOS/Tac || true
ditto "$app" /Applications/Tac.app
open /Applications/Tac.app
