#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
bash Scripts/check-input-source.sh
run_product PinyinCoreTests
run_product TranslationServiceTests
run_product InputSessionTests
run_product PinyinInfrastructureTests
run_product PinyinPresentationTests
