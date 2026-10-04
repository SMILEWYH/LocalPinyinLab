#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT="$PWD/build/LocalPinyin.app/Contents/Resources/Worker"
/usr/bin/sandbox-exec -D "WORKER_ROOT=$ROOT" -f "$ROOT/pinyin.sb" "$ROOT/pinyin-worker" --json nihao 2>/dev/null | /usr/bin/python3 -c 'import json,sys; words=json.load(sys.stdin); assert "你好" in words; print("PASS: synthetic nihao -> 你好")'
if /usr/bin/sandbox-exec -D "WORKER_ROOT=$ROOT" -f "$ROOT/pinyin.sb" "$ROOT/pinyin-worker" --json 'invalid!' >/dev/null 2>&1; then
  echo 'FAIL: invalid input accepted'; exit 1
fi
echo 'PASS: invalid input rejected'
/usr/bin/python3 - "$ROOT" <<'PY'
import json, subprocess, sys
from pathlib import Path
root = Path(sys.argv[1])
cases = {
    "xianzaibeijingshijian": "现在北京时间",
    "xianzaibeijingshijianjidianzhong": "现在北京时间几点钟",
    "xian'zai'bei'jing'shi'jian": "现在北京时间",
}
for query, expected in cases.items():
    result = subprocess.run(
        ["/usr/bin/sandbox-exec", "-D", "WORKER_ROOT=" + str(root), "-f",
         str(root / "pinyin.sb"), str(root / "pinyin-worker"), "--json", query],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    words = json.loads(result.stdout)
    assert expected in words, (query, words)
    assert "现在" in words, "Prefix candidates must remain available for staged selection"
    print("PASS: sentence and prefix candidates: " + query)
PY

run_product composition-tests "$ROOT"
