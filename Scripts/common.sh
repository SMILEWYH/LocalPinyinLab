#!/bin/bash
# Shared SwiftPM configuration; source this file from scripts in Scripts/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SWIFT_FLAGS=(--scratch-path build/swift --configuration "${CONFIGURATION:-release}" --arch arm64)
BIN_DIR=$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)
run_product() {
    local product="$1"
    shift
    swift build "${SWIFT_FLAGS[@]}" --product "$product"
    "$BIN_DIR/$product" "$@"
}
