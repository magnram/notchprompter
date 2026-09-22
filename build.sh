#!/bin/zsh
# Builds the app with Xcode and copies it here, so `./build.sh && open NotchPrompter.app` works.
set -e
cd "$(dirname "$0")"
pkill -x NotchPrompter 2>/dev/null || true
xcodebuild -project NotchPrompter.xcodeproj -scheme NotchPrompter -configuration Debug \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates build -quiet
rm -rf NotchPrompter.app
cp -R build/DerivedData/Build/Products/Debug/NotchPrompter.app .
echo "Built NotchPrompter.app"
