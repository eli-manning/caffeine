#!/bin/bash
# Builds Caffeine.app via an Xcode project (xcodegen + xcodebuild) so the app gets
# a real code signature. On macOS 26, ad-hoc-signed apps get silently denied a real
# menu bar status-item slot even though they launch and run fine.
# Pass --install to copy the result into /Applications.
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null; then
	echo "xcodegen is required: brew install xcodegen" >&2
	exit 1
fi

DERIVED_DATA=".build/xcode"
APP="$DERIVED_DATA/Build/Products/Release/Caffeine.app"

xcodegen generate
xcodebuild -project Caffeine.xcodeproj -scheme Caffeine -configuration Release -derivedDataPath "$DERIVED_DATA" build

# xcodegen doesn't wire up a Copy Bundle Resources phase for these, so add them
# manually and re-sign (any change to a signed bundle invalidates its signature).
mkdir -p "$APP/Contents/Resources"
if [ -f Resources/AppIcon.icns ]; then
	cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep -m1 'Apple Development' | sed -E 's/^[[:space:]]*[0-9]+\) ([A-F0-9]+) .*/\1/')"
ENTITLEMENTS="$DERIVED_DATA/Build/Intermediates.noindex/Caffeine.build/Release/Caffeine.build/Caffeine.app.xcent"
if [ -n "$SIGN_IDENTITY" ] && [ -f "$ENTITLEMENTS" ]; then
	codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
else
	codesign --force --sign - "$APP"
	echo "Warning: no Apple Development identity found; ad-hoc signing may not get a menu bar icon on macOS 26+." >&2
fi

echo "Built $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
	rm -rf /Applications/Caffeine.app
	cp -R "$APP" /Applications/Caffeine.app

	# Ensure no custom Finder icon override exists
	swift - <<'EOF'
import AppKit
let appPath = "/Applications/Caffeine.app"
_ = NSWorkspace.shared.setIcon(nil, forFile: appPath, options: [])
EOF

	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Caffeine.app
	touch /Applications/Caffeine.app

	echo "Installed /Applications/Caffeine.app"
fi
