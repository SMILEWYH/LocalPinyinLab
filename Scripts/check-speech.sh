#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -target arm64-apple-macos26.0 -module-cache-path build/module-cache -parse-as-library Sources/Candidate.swift Sources/EnglishSpeaker.swift Tests/SpeechTests.swift -o build/speech-tests
build/speech-tests
