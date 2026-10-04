#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Check the source plist, or pass the installed bundle's Info.plist to verify it.
# This does not register, enable, select, or change any system input source.
python3 - "${1:-Info.plist}" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    info = plistlib.load(stream)

source_id = "local.pinyinlab.inputmethod"
mode_id = source_id + ".Hans"
mode = info.get("ComponentInputModeDict", {}).get("tsInputModeListKey", {}).get(mode_id, {})
checks = {
    "bundle input source ID": info.get("TISInputSourceID") == source_id,
    "bundle language": info.get("TISIntendedLanguage") == "zh-Hans",
    "bundle Chinese repertoire": info.get("tsInputMethodCharacterRepertoireKey") == ["Hans"],
    "Caps Lock handled inside input method": info.get("TICapsLockLanguageSwitchCapable") is False,
    "mode input source ID": mode.get("TISInputSourceID") == mode_id,
    "mode language": mode.get("TISIntendedLanguage") == "zh-Hans",
    "mode Chinese repertoire": mode.get("tsInputModeCharacterRepertoireKey") == ["Hans"],
    "mode Chinese script": mode.get("tsInputModeScriptKey") == "smSimpChinese",
    "mode does not replace the script's primary input source": mode.get("tsInputModePrimaryInScriptKey") is False,
}
failures = [name for name, passed in checks.items() if not passed]
for name in failures:
    print("FAIL: " + name, file=sys.stderr)
if failures:
    sys.exit(1)
print("PASS: input source metadata constraints (9)")
PY
