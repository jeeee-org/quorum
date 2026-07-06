#!/usr/bin/env bash
# validate_json.sh のテスト（正常系1・異常系3）。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="$REPO/skills/quorum/scripts/validate_json.sh"
PASS=0; FAIL=0

VALID='{"question":"q","final_answer":"a","panel":{"used":["opus"]},"consensus":[],"contradictions":[],"seam_check":[
{"category":"境界の検証","verdict":"na","note":"x"},
{"category":"境界をまたぐ整合性・原子性","verdict":"na","note":"x"},
{"category":"失敗モード","verdict":"covered","note":"x"},
{"category":"観測・追跡","verdict":"partial","note":"x"},
{"category":"移行の途中状態","verdict":"missing","note":"x"},
{"category":"コスト・撤退","verdict":"na","note":"x"},
{"category":"暗黙の前提","verdict":"covered","note":"x"}]}'

t() { # t <名前> <期待exit> <入力>
  local name="$1" want_rc="$2" input="$3" rc=0
  printf '%s' "$input" | bash "$VALIDATE" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$want_rc" ]; then
    PASS=$((PASS+1)); echo "ok   - $name"
  else
    FAIL=$((FAIL+1)); echo "FAIL - $name (want exit=$want_rc, got $rc)"
  fi
}

t "正常系（素の JSON）" 0 "$VALID"
t "正常系（\`\`\`json フェンス付き）" 0 "$(printf '\x60\x60\x60json\n%s\n\x60\x60\x60' "$VALID")"
t "JSON でない入力は NG" 1 "これは JSON ではない"
t "必須キー欠落は NG" 1 '{"question":"q"}'
t "seam_check カテゴリ欠落・不正 verdict は NG" 1 \
  '{"question":"q","final_answer":"a","panel":{"used":["opus"]},"consensus":[],"contradictions":[],"seam_check":[{"category":"失敗モード","verdict":"yes","note":""}]}'

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
