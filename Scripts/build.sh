#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
swift build "${SWIFT_FLAGS[@]}"
mkdir -p build
for product in translation-probe candidate-preview inputsource-tool menu-icon libIMKCompileProbe.dylib; do
    cp "$BIN_DIR/$product" "build/$product"
done
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/localpinyin-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/LocalPinyin.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Worker"
cp Info.plist "$APP/Contents/Info.plist"
ditto Resources "$APP/Contents/Resources"
"$BIN_DIR/menu-icon" "$APP/Contents/Resources/LocalPinyin-menu.tiff"
cp Worker/pinyin.sb "$APP/Contents/Resources/Worker/pinyin.sb"
xcrun clang -target arm64-apple-macos26.0 -fobjc-arc -framework Foundation Worker/main.m -o "$APP/Contents/Resources/Worker/pinyin-worker"
cp "$BIN_DIR/LocalPinyin" "$APP/Contents/MacOS/LocalPinyin"
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Resources/Worker/pinyin-worker"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
# Remove the obsolete generated icon when updating an existing build bundle.
rm -f build/LocalPinyin.app/Contents/Resources/LocalPinyin-menu.pdf
ditto --norsrc --noextattr "$APP" build/LocalPinyin.app
# Desktop file providers can attach Finder metadata to the destination bundle.
xattr -cr build/LocalPinyin.app
codesign --verify --deep --strict build/LocalPinyin.app
echo "Experimental input method bundle built and verified; not installed or registered."
