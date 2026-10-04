#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
APP=build/TranslationSetup.app
mkdir -p "$APP/Contents/MacOS"
swift build "${SWIFT_FLAGS[@]}" --product TranslationSetup
cp "$BIN_DIR/TranslationSetup" "$APP/Contents/MacOS/TranslationSetup"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.pinyinlab.translation-setup</string><key>CFBundleName</key><string>TranslationSetup</string><key>CFBundleExecutable</key><string>TranslationSetup</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>26.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
