#!/bin/sh
# Builds NotchPrompter.app next to this script.
set -e
cd "$(dirname "$0")"
APP=NotchPrompter.app
pkill -x NotchPrompter 2>/dev/null || true   # quit the running copy so the new build opens
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O NotchPrompter.swift -o "$APP/Contents/MacOS/NotchPrompter"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NotchPrompter</string>
  <key>CFBundleIdentifier</key><string>local.notchprompter</string>
  <key>CFBundleExecutable</key><string>NotchPrompter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>NotchPrompter listens to you read so the script can follow your voice.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>NotchPrompter turns your speech into words to find your place in the script.</string>
</dict></plist>
EOF
codesign -s - --force "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
