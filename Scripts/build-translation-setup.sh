#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
swift build "${SWIFT_FLAGS[@]}" --product TranslationSetup
STAGING=$(mktemp -d "$BUILD_ROOT/.stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/TranslationSetup.app"
translation_setup_bundle "$APP"
publish_bundle "$APP" TranslationSetup.app
