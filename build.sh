#!/bin/bash
# Builds Notch.app into ./build. "run" launches it; "install" copies it to /Applications and launches that.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/Notch.app
pkill -f "$PWD/build/Notch.app/" 2>/dev/null || true  # only the build/ copy, never /Applications/Notch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/Notch "$APP/Contents/MacOS/Notch"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
if [[ "${1:-}" == "install" ]]; then
  rm -rf /Applications/Notch.app
  cp -R "$APP" /Applications/Notch.app
  APP=/Applications/Notch.app
  echo "Installed $APP"
fi
if [[ "${1:-}" == "run" || "${1:-}" == "install" ]]; then open "$APP"; fi
