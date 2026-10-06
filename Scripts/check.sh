#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
for suite in input-checks worker-checks presentation-checks; do
    swift run "${SWIFT_FLAGS[@]}" "$suite"
done
