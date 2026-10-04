#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/return-key-tests
python3 - <<'PY'
from pathlib import Path
text = Path('Sources/InputController.swift').read_text()
assert text.count('import InputMethodKit') == 1
# Only replace the framework base/client boundary. Event and async implementation is unchanged.
text = text.replace('import InputMethodKit', '')
Path('build/return-key-tests/InputController.swift').write_text(text)
PY
xcrun swiftc -target arm64-apple-macos26.0 -module-cache-path build/module-cache -parse-as-library Sources/Candidate.swift Sources/CompositionState.swift Sources/EnglishSpeaker.swift build/return-key-tests/InputController.swift Tests/ReturnKeyTests.swift -o build/return-key-tests/run
build/return-key-tests/run
