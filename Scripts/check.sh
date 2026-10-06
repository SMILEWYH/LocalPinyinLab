#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
for suite in input-checks worker-checks presentation-checks; do
    swift run "${SWIFT_FLAGS[@]}" "$suite"
done
TEST_FLAGS=(--disable-xctest)
TEST_SWIFTC=$(xcrun --find swiftc)
TEST_MACROS="$(dirname "$TEST_SWIFTC")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
# Some Command Line Tools releases omit Testing's macro plugin from SwiftBuild.
if [[ "$TEST_SWIFTC" == */CommandLineTools/* && -f "$TEST_MACROS" ]]; then
    TEST_FLAGS+=(-Xswiftc -load-plugin-library -Xswiftc "$TEST_MACROS")
fi
swift test "${SWIFT_FLAGS[@]}" "${TEST_FLAGS[@]}"
