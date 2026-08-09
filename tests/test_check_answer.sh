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

# --- stderr を渡すと空応答の原因まで名指しできる（IMPROVEMENTS 2026-07-30 / 08-05） ---
printf '/usr/bin/timeout: Argument list too long\n' > "$TMP/argv.err"
out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/argv.err")"; rc=$?
t "空＋stderrが引数長超過なら argv-too-long" "$([ "$out" = "invalid_response:argv-too-long" ] && [ "$rc" = "3" ]; echo $?)"

printf '[run_grok] invalid_response:argv-too-long — ...\n' > "$TMP/argv2.err"
out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/argv2.err")"
t "run側の明示エラーでも argv-too-long" "$([ "$out" = "invalid_response:argv-too-long" ]; echo $?)"

out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/nonexistent.err")"
t "stderr が無くても empty で判定を続ける" "$([ "$out" = "invalid_response:empty" ]; echo $?)"

# --- 既知パターン以外の stderr は先頭行を理由へ転記する（IMPROVEMENTS 2026-08-09） ---
printf 'authentication failed: token expired\n' > "$TMP/other.err"
out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/other.err")"; rc=$?
t "未知の stderr は empty:<先頭行> として転記される" \
  "$([ "$out" = "invalid_response:empty:authentication failed: token expired" ] && [ "$rc" = "3" ]; echo $?)"

t "転記しても集計キー（第1・第2フィールド）は empty のまま" \
  "$([ "$(printf '%s' "$out" | awk -F: '{print $1 ":" $2}')" = "invalid_response:empty" ]; echo $?)"

printf '\n\n   \nrate limit exceeded\nsecond line\n' > "$TMP/blank_head.err"
out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/blank_head.err")"
t "先頭の空行は飛ばして最初の非空行を採る" \
  "$([ "$out" = "invalid_response:empty:rate limit exceeded" ]; echo $?)"

printf 'col1\tcol2  \t multi   space\n' > "$TMP/tab.err"
out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/tab.err")"
t "タブと連続空白は潰して1行に畳む（checks.txt が TSV のため）" \
  "$([ "$out" = "invalid_response:empty:col1 col2 multi space" ]; echo $?)"

printf '   \n\t\n' > "$TMP/blank_only.err"
out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/blank_only.err")"
t "stderr が空白のみなら従来どおり empty" "$([ "$out" = "invalid_response:empty" ]; echo $?)"

python3 -c "print('E' * 300)" > "$TMP/long.err"
out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/long.err")"
t "長い stderr は 100 文字で切る" \
  "$([ "${#out}" = "123" ] && case "$out" in invalid_response:empty:EEE*) true ;; *) false ;; esac; echo $?)"

# 日本語 stderr を切っても不正バイト列を残さない（IMPROVEMENTS 2026-08-02）
python3 -c "print('日本語のエラー' * 40)" > "$TMP/ja.err"
out="$(bash "$CHECK" "$TMP/empty.md" "$TMP/ja.err")"
printf '%s' "$out" | python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")' 2>/dev/null
t "日本語 stderr を切っても UTF-8 として妥当" "$?"

out="$(LC_ALL=C bash "$CHECK" "$TMP/empty.md" "$TMP/ja.err")"
printf '%s' "$out" | python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")' 2>/dev/null
t "C ロケールでも壊れたマルチバイト列を残さない" "$?"

out="$(bash "$CHECK" "$TMP/long.md" "$TMP/argv.err")"
t "本文があれば stderr に関係なく ok" "$([ "$out" = "ok" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
