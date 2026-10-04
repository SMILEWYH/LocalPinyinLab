#!/bin/bash
# Shared SwiftPM configuration; source this file from scripts in Scripts/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SWIFT_FLAGS=(--scratch-path build/swift --configuration "${CONFIGURATION:-release}" --arch arm64)
BIN_DIR=$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)
