#!/bin/bash
set -euo pipefail
echo "The translation preparation tool is now 拼音设置; building PinyinSettings.app."
exec /bin/bash "$(dirname "$0")/build-settings.sh"
