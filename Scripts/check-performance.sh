#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
run_product performance-tests "$PWD/build/LocalPinyin.app/Contents/Resources/Worker"
mkdir -p build/timeout-worker
cp Worker/pinyin.sb build/timeout-worker/pinyin.sb
xcrun clang -target arm64-apple-macos26.0 Tests/UnresponsiveWorker.c -o build/timeout-worker/pinyin-worker
run_product worker-timeout-test "$PWD/build/timeout-worker"
