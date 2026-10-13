#!/bin/sh
set -eu
EXAMPLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-Debug}
# Ad-hoc signed ("-") so the sandbox and microphone entitlements are embedded; no team required.
xcodebuild -project "$EXAMPLE_DIR/BusymateSDKExample.xcodeproj" -scheme BusymateSDKExample \
  -configuration "$CONFIGURATION" -destination 'generic/platform=macOS' \
  -derivedDataPath "$EXAMPLE_DIR/.derived-data" -jobs 1 build
APP="$EXAMPLE_DIR/.derived-data/Build/Products/$CONFIGURATION/BusymateSDKExample.app"
/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$APP/Contents/Info.plist"
codesign -d --entitlements - "$APP" 2>/dev/null > "$EXAMPLE_DIR/.derived-data/entitlements.txt" || true
for key in com.apple.security.app-sandbox com.apple.security.device.audio-input com.apple.security.network.client; do
  grep -q "$key" "$EXAMPLE_DIR/.derived-data/entitlements.txt" || { echo "missing entitlement $key" >&2; exit 1; }
done
echo "verified entitlements and NSMicrophoneUsageDescription in $APP"
