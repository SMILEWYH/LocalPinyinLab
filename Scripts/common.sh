#!/bin/bash
# Shared SwiftPM configuration; source this file from scripts in Scripts/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# Keep signed bundles outside Desktop/iCloud file providers, which can reattach
# Finder metadata after xattr cleanup and invalidate an otherwise valid bundle.
BUILD_ROOT="${LOCALPINYIN_BUILD_ROOT:-$HOME/Library/Caches/LocalPinyinLab/build}"
if [[ "$BUILD_ROOT" != /* || "$BUILD_ROOT" == / ]]; then
    echo "LOCALPINYIN_BUILD_ROOT must be an absolute build directory, not /." >&2
    exit 1
fi
mkdir -p "$BUILD_ROOT"
SWIFT_FLAGS=(--scratch-path "$BUILD_ROOT/swift" --configuration "${CONFIGURATION:-release}" --arch arm64)
BIN_DIR=$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)

settings_bundle() {
    local bundle="$1"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
    cp "$BIN_DIR/PinyinSettings" "$bundle/Contents/MacOS/PinyinSettings"
    "$BIN_DIR/settings-icon" "$bundle/Contents/Resources/PinyinSettings.icns"
    cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.pinyinlab.settings</string>
<key>CFBundleName</key><string>拼音设置</string>
<key>CFBundleDisplayName</key><string>拼音设置</string>
<key>CFBundleExecutable</key><string>PinyinSettings</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>9</string>
<key>CFBundleShortVersionString</key><string>1.3.5</string>
<key>CFBundleIconFile</key><string>PinyinSettings.icns</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
    xattr -cr "$bundle"
    codesign --force --sign - "$bundle"
    codesign --verify --deep --strict "$bundle"
}

# Publish a complete verified bundle. Never merge into an old output, which
# would retain removed resources. Keep the previous output until verification.
publish_bundle() (
    local staged="$1" name="$2" destination backup committed=false
    case "$name" in
        LocalPinyin.app|PinyinSettings.app) ;;
        *) echo "Unexpected generated bundle: $name" >&2; return 1 ;;
    esac
    destination="$BUILD_ROOT/$name"
    codesign --verify --deep --strict "$staged"
    backup=$(mktemp -d "$BUILD_ROOT/.previous.XXXXXX")
    restore_previous() {
        local status=$?
        trap - EXIT INT TERM HUP
        if [[ "$committed" != true ]]; then
            if [[ -e "$backup/$name" ]]; then
                rm -rf "$destination"
                if ! mv "$backup/$name" "$destination"; then
                    printf 'Previous bundle retained for recovery: %s\n' "$backup/$name" >&2
                    exit 1
                fi
            elif [[ ! -e "$staged" && -e "$destination" ]]; then
                rm -rf "$destination"
            fi
        fi
        rm -rf "$backup"
        exit "$status"
    }
    trap restore_previous EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    if [[ -e "$destination" ]]; then
        mv "$destination" "$backup/$name" || return 1
    fi
    mv "$staged" "$destination" || return 1
    codesign --verify --deep --strict "$destination" || return 1
    committed=true
    printf 'Built and verified: %s\n' "$destination"
)
