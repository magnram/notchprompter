#!/bin/zsh
# Builds the app with Xcode and copies it here, so `./build.sh && open NotchPrompter.app` works.
#
# Without a signing certificate (or with --local), the app is signed for this Mac only and
# iCloud sync is left out, since that needs the project's Apple team. Everything else works.
set -e
cd "$(dirname "$0")"

local_build=false
case "$*" in
  ("") ;;
  (--local) local_build=true ;;
  (*) echo "Usage: ./build.sh [--local]" >&2; exit 2 ;;
esac
if security find-identity -v -p codesigning | grep -q '^ *0 valid identities'; then
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
  # The output also goes to a log, so a signing error can point at --local.
  mkdir -p build
  setopt pipefail
  if ! xcodebuild -project NotchPrompter.xcodeproj -scheme NotchPrompter -configuration Debug \
    -derivedDataPath build/DerivedData -allowProvisioningUpdates build -quiet 2>&1 | tee build/xcodebuild.log; then
    if grep -qE "No Accounts|No profiles for|No signing certificate|requires a development team|provisioning profile" build/xcodebuild.log; then
      echo "Not on the project's Apple team? Run: ./build.sh --local" >&2
    fi
    exit 1
  fi
fi

rm -rf NotchPrompter.app
cp -R build/DerivedData/Build/Products/Debug/NotchPrompter.app .
echo "Built NotchPrompter.app"
