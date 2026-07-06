#!/usr/bin/env bash
# 全テストを実行する。API 呼び出し・外部CLIは一切不要（純 bash + python3 stdlib）。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for f in "$DIR"/test_*.sh; do
  echo "== $(basename "$f") =="
  bash "$f" || rc=1
  echo
done
[ "$rc" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$rc"
