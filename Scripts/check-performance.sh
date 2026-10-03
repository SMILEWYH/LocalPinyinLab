#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
FLAGS=(-target arm64-apple-macos26.0 -module-cache-path build/module-cache -parse-as-library)
xcrun swiftc "${FLAGS[@]}" Sources/Candidate.swift Sources/PinyinSession.swift Tests/PerformanceTests.swift -o build/performance-tests
build/performance-tests "$PWD/build/LocalPinyin.app/Contents/Resources/Worker"
mkdir -p build/timeout-worker
cp Probes/pinyin.sb build/timeout-worker/pinyin.sb
xcrun clang Tests/UnresponsiveWorker.c -o build/timeout-worker/pinyin-worker
xcrun swiftc "${FLAGS[@]}" Sources/Candidate.swift Sources/PinyinSession.swift Tests/WorkerTimeoutTest.swift -o build/worker-timeout-test
build/worker-timeout-test "$PWD/build/timeout-worker"
