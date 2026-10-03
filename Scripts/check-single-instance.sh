#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -target arm64-apple-macos26.0 -module-cache-path build/module-cache -parse-as-library Sources/SingleInstanceLock.swift Tests/SingleInstanceTests.swift -o build/single-instance-tests
build/single-instance-tests
