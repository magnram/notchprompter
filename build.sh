#!/bin/zsh
# Builds the app with Xcode and copies it here, so `./build.sh && open NotchPrompter.app` works.
#
# Without a signing certificate (or with --local), the app is signed for this Mac only and
# iCloud sync is left out, since that needs the project's Apple team. Everything else works.
set -e
cd "$(dirname "$0")"

local_build=false
if [[ "$1" == "--local" ]] || security find-identity -v -p codesigning | grep -q '^ *0 valid identities'; then
  local_build=true
fi

pkill -x NotchPrompter 2>/dev/null || true

if $local_build; then
  echo "Building for this Mac only, without iCloud sync"
  mkdir -p build
  cp Config/NotchPrompter.entitlements build/local.entitlements
  /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.ubiquity-kvstore-identifier' build/local.entitlements
  xcodebuild -project NotchPrompter.xcodeproj -scheme NotchPrompter -configuration Debug \
    -derivedDataPath build/DerivedData build -quiet \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
    CODE_SIGN_ENTITLEMENTS="$PWD/build/local.entitlements"
else
  if ! xcodebuild -project NotchPrompter.xcodeproj -scheme NotchPrompter -configuration Debug \
    -derivedDataPath build/DerivedData -allowProvisioningUpdates build -quiet; then
    echo "Build failed. Not on the project's Apple team? Run: ./build.sh --local" >&2
    exit 1
  fi
fi

rm -rf NotchPrompter.app
cp -R build/DerivedData/Build/Products/Debug/NotchPrompter.app .
echo "Built NotchPrompter.app"
