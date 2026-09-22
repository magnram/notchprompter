#!/bin/zsh
# Renders the App Store screenshots and window captures into the folder given (default: AppStore/screenshots).
# Uses a Debug build without the sandbox, so the app can write outside its container.
set -e
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/AppStore/screenshots}"
xcodebuild -project NotchPrompter.xcodeproj -scheme NotchPrompter -configuration Debug \
  -derivedDataPath build/Render ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS= CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build -quiet
rm -rf "$OUT"
build/Render/Build/Products/Debug/NotchPrompter.app/Contents/MacOS/NotchPrompter -renderScreens "$OUT"
ls "$OUT"
