#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
for product in PinyinSettings settings-icon; do
    swift build "${SWIFT_FLAGS[@]}" --product "$product"
done
STAGING=$(mktemp -d "$BUILD_ROOT/.stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/PinyinSettings.app"
settings_bundle "$APP"
publish_bundle "$APP" PinyinSettings.app
