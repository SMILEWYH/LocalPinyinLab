#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/TranslationSetup.app
mkdir -p "$APP/Contents/MacOS" build/module-cache
swiftc -parse-as-library -target arm64-apple-macos26.0 -module-cache-path build/module-cache Probes/TranslationSetup.swift -o "$APP/Contents/MacOS/TranslationSetup"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.pinyinlab.translation-setup</string><key>CFBundleName</key><string>TranslationSetup</string><key>CFBundleExecutable</key><string>TranslationSetup</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>26.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
