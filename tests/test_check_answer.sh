#!/usr/bin/env bash
# check_answer.sh（回収後の軽量検査・監査記録用）の決定論判定を検証する。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO/skills/quorum/scripts/check_answer.sh"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 500B 以上の実質回答 → ok / exit 0
python3 -c "print('回答本文 ' * 200)" > "$TMP/long.md"
out="$(bash "$CHECK" "$TMP/long.md")"; rc=$?
t "十分な長さの回答は ok" "$([ "$out" = "ok" ] && [ "$rc" = "0" ]; echo $?)"

# 空ファイル → invalid_response:empty / exit 3
: > "$TMP/empty.md"
out="$(bash "$CHECK" "$TMP/empty.md")"; rc=$?
t "空ファイルは invalid_response:empty" "$([ "$out" = "invalid_response:empty" ] && [ "$rc" = "3" ]; echo $?)"

# 空白・改行のみ → empty
printf '  \n\t\n  ' > "$TMP/blank.md"
out="$(bash "$CHECK" "$TMP/blank.md")"
t "空白のみは invalid_response:empty" "$([ "$out" = "invalid_response:empty" ]; echo $?)"

# 短文（<500B）→ too_short:<N>B / exit 3
printf 'これから確認します。' > "$TMP/short.md"
out="$(bash "$CHECK" "$TMP/short.md")"; rc=$?
t "短文は invalid_response:too_short" "$(case "$out" in invalid_response:too_short:*B) [ "$rc" = "3" ] ;; *) false ;; esac; echo $?)"

# 閾値は QUORUM_MIN_ANSWER_BYTES で変更可
out="$(QUORUM_MIN_ANSWER_BYTES=5 bash "$CHECK" "$TMP/short.md")"
t "閾値を下げれば同じ短文でも ok" "$([ "$out" = "ok" ]; echo $?)"

# stdin モード
out="$(python3 -c "print('回答 ' * 200)" | bash "$CHECK")"
t "stdin 渡しでも判定できる" "$([ "$out" = "ok" ]; echo $?)"

# 不正な閾値は exit 2
QUORUM_MIN_ANSWER_BYTES=abc bash "$CHECK" "$TMP/long.md" >/dev/null 2>&1
t "非整数の閾値は exit 2" "$([ "$?" = "2" ]; echo $?)"

# 読めないファイルは exit 2
bash "$CHECK" "$TMP/nonexistent.md" >/dev/null 2>&1
t "読めないファイルは exit 2" "$([ "$?" = "2" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
