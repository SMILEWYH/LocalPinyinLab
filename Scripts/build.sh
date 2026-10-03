#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
SDK="$(xcrun --show-sdk-path)"
FLAGS=(-sdk "$SDK" -target arm64-apple-macos26.0 -module-cache-path "$CLANG_MODULE_CACHE_PATH")
swiftc "${FLAGS[@]}" -parse-as-library Sources/AppleTranslator.swift Probes/TranslationProbe.swift -o build/translation-probe
swiftc "${FLAGS[@]}" -parse-as-library -emit-library Sources/Candidate.swift Probes/IMKCompileProbe.swift -o build/libIMKCompileProbe.dylib
swiftc "${FLAGS[@]}" Sources/Candidate.swift Sources/CandidateView.swift Probes/Preview.swift -o build/candidate-preview
swiftc "${FLAGS[@]}" Probes/InputSourceTool.swift -o build/inputsource-tool
echo "Build complete. No input method installed or registered."
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/localpinyin-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/LocalPinyin.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Worker"
cp Info.plist "$APP/Contents/Info.plist"
ditto Resources "$APP/Contents/Resources"
swiftc "${FLAGS[@]}" Probes/MenuIcon.swift -o build/menu-icon
build/menu-icon "$APP/Contents/Resources/LocalPinyin-menu.pdf"
cp Probes/pinyin.sb "$APP/Contents/Resources/Worker/pinyin.sb"
xcrun clang -fobjc-arc -framework Foundation Probes/PinyinProbe.m -o "$APP/Contents/Resources/Worker/pinyin-worker"
swiftc "${FLAGS[@]}" -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/LocalPinyin"
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Resources/Worker/pinyin-worker"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto --norsrc --noextattr "$APP" build/LocalPinyin.app
echo "Experimental input method bundle built, not installed."
