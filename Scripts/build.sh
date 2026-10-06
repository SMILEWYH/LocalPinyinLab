#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
for product in LocalPinyin inputsource-tool menu-icon settings-icon PinyinSettings; do
    swift build "${SWIFT_FLAGS[@]}" --product "$product"
done
for product in inputsource-tool menu-icon; do
    cp "$BIN_DIR/$product" "$BUILD_ROOT/$product"
done
STAGING=$(mktemp -d "$BUILD_ROOT/.stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/LocalPinyin.app"
SETTINGS_APP="$STAGING/PinyinSettings.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Worker"
cp Info.plist "$APP/Contents/Info.plist"
ditto Resources "$APP/Contents/Resources"
"$BIN_DIR/menu-icon" "$APP/Contents/Resources/LocalPinyin-menu.tiff"
cp Worker/pinyin.sb "$APP/Contents/Resources/Worker/pinyin.sb"
xcrun clang -target arm64-apple-macos26.0 -fobjc-arc -framework Foundation Worker/main.m -o "$APP/Contents/Resources/Worker/pinyin-worker"
cp "$BIN_DIR/LocalPinyin" "$APP/Contents/MacOS/LocalPinyin"
settings_bundle "$SETTINGS_APP"
ditto --norsrc --noextattr "$SETTINGS_APP" "$APP/Contents/Resources/PinyinSettings.app"
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Resources/Worker/pinyin-worker"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
publish_bundle "$SETTINGS_APP" PinyinSettings.app
publish_bundle "$APP" LocalPinyin.app
echo "Input method and 拼音设置 bundles built and verified; not installed or registered."
