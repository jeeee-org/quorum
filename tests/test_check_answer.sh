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
# 題材は「予告文でない」短文にする——short.md（「これから確認します。」）は plan_only の標的
# そのものなので、閾値を下げると too_short ではなく plan_only で落ちる（下でその挙動を検証）。
printf '答えは 42 です。' > "$TMP/short_valid.md"
out="$(QUORUM_MIN_ANSWER_BYTES=5 bash "$CHECK" "$TMP/short_valid.md")"
t "閾値を下げれば同じ短文でも ok" "$([ "$out" = "ok" ]; echo $?)"

out="$(QUORUM_MIN_ANSWER_BYTES=5 bash "$CHECK" "$TMP/short.md")"
t "閾値を下げても作業予告は plan_only で落ちる" "$([ "$out" = "invalid_response:plan_only" ]; echo $?)"

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

# --- 内容ベースの判定（IMPROVEMENTS 2026-08-13 / 08-15） ---
# 背景: バイト数だけの検査は「閾値を超えた作業予告」を素通しする（588B の予告が実際にすり抜けた）。
# 閾値を上げる対処は正当な短答を殺すので採らない ∴ 中身で見る。

# 実際に観測された型（500B 超の作業予告だけ・構造なし）
python3 -c "print('依頼の全文を読み、契約書と突き合わせて確認します。' * 20)" > "$TMP/plan_long.md"
out="$(bash "$CHECK" "$TMP/plan_long.md")"; rc=$?
t "閾値を超えた作業予告は plan_only（byte 検査の穴を塞ぐ）" \
  "$([ "$out" = "invalid_response:plan_only" ] && [ "$rc" = "3" ]; echo $?)"

t "その予告は too_short では拾えない（穴が実在することの確認）" \
  "$([ "$(wc -c < "$TMP/plan_long.md")" -ge 500 ]; echo $?)"

# 構造（見出し・箇条書き等）があれば plan_only にしない
printf '## 判定\n\n- 全文を読み、確認します\n' > "$TMP/structured.md"
out="$(QUORUM_MIN_ANSWER_BYTES=5 bash "$CHECK" "$TMP/structured.md")"
t "構造マーカーがあれば plan_only にしない" "$([ "$out" = "ok" ]; echo $?)"

# 予告文でない行が混じれば plan_only にしない
printf 'まず全文を確認します。\n判定は CONDITIONAL_PASS。\n' > "$TMP/mixed.md"
out="$(QUORUM_MIN_ANSWER_BYTES=5 bash "$CHECK" "$TMP/mixed.md")"
t "実質的な行が1つでもあれば plan_only にしない" "$([ "$out" = "ok" ]; echo $?)"

# 長文の散文は対象外（上限バイトのガード）
out="$(QUORUM_PLAN_ONLY_MAX_BYTES=10 bash "$CHECK" "$TMP/plan_long.md")"
t "QUORUM_PLAN_ONLY_MAX_BYTES を下回らせれば plan_only を適用しない" "$([ "$out" = "ok" ]; echo $?)"

# --- --expect（呼び出し側が求める語） ---
out="$(bash "$CHECK" --expect 回答本文 "$TMP/long.md")"; rc=$?
t "--expect の語が含まれれば ok" "$([ "$out" = "ok" ] && [ "$rc" = "0" ]; echo $?)"

out="$(bash "$CHECK" --expect 欠陥 "$TMP/long.md")"; rc=$?
t "--expect の語が無ければ missing_expected" \
  "$([ "$out" = "invalid_response:missing_expected:欠陥" ] && [ "$rc" = "3" ]; echo $?)"

out="$(bash "$CHECK" --expect 欠陥 --expect 回答本文 "$TMP/long.md")"
t "--expect は OR 判定（1語でも含めば通す）" "$([ "$out" = "ok" ]; echo $?)"

out="$(bash "$CHECK" --expect 欠陥 --expect デグレ "$TMP/long.md")"
t "全語欠落なら候補を | で連ねて報告する" \
  "$([ "$out" = "invalid_response:missing_expected:欠陥|デグレ" ]; echo $?)"

out="$(bash "$CHECK" --expect=回答本文 "$TMP/long.md")"
t "--expect=<語> の形も受ける" "$([ "$out" = "ok" ]; echo $?)"

bash "$CHECK" --expect >/dev/null 2>&1
t "--expect に値が無ければ exit 2" "$([ "$?" = "2" ]; echo $?)"

# --- truncated_suspect（末尾切れ・exit 4。実質回答なしではない） ---
BODY="$(python3 -c "print('## 総評\n\n本文がここに続く。' * 30)")"

printf '%s\n## 4. 見落とし\n\n契約書に書いていないと' "$BODY" > "$TMP/mid.md"
out="$(bash "$CHECK" "$TMP/mid.md")"; rc=$?
t "文の途中で切れた長文は truncated_suspect:midsentence / exit 4" \
  "$([ "$out" = "truncated_suspect:midsentence" ] && [ "$rc" = "4" ]; echo $?)"

printf '%s\n## 5. まとめ\n' "$BODY" > "$TMP/head.md"
out="$(bash "$CHECK" "$TMP/head.md")"
t "見出しだけで終わるなら truncated_suspect:heading" "$([ "$out" = "truncated_suspect:heading" ]; echo $?)"

printf '%s\n```bash\nfoo() {\n' "$BODY" > "$TMP/fence.md"
out="$(bash "$CHECK" "$TMP/fence.md")"
t "コードフェンス未閉じなら truncated_suspect:unclosed_fence" \
  "$([ "$out" = "truncated_suspect:unclosed_fence" ]; echo $?)"

printf '%s\n- 出典必須\n- 各事実に file:line かコマンド名\n' "$BODY" > "$TMP/taigen.md"
out="$(bash "$CHECK" "$TMP/taigen.md")"
t "体言止めの箇条書きで終わるのは誤検知しない" "$([ "$out" = "ok" ]; echo $?)"

t "truncated_suspect は invalid_response と別系統（exit が 3 でない）" \
  "$(out2="$(bash "$CHECK" "$TMP/mid.md")"; case "$out2" in invalid_response:*) false ;; *) true ;; esac; echo $?)"

# truncated_suspect は「回答している」ので連続 invalid カウンタを進めない
ST="$TMP/state_trunc"; rm -rf "$ST"
QUORUM_STATE_DIR="$ST" bash "$CHECK" --backend tb "$TMP/empty.md" >/dev/null 2>&1
QUORUM_STATE_DIR="$ST" bash "$CHECK" --backend tb "$TMP/mid.md" >/dev/null 2>&1
t "truncated_suspect はカウンタを 0 に戻す（回答はしている）" \
  "$([ "$(awk -F'\t' '$1=="tb"{print $2}' "$ST/invalid.tsv")" = "0" ]; echo $?)"

# 警告文は「恒久故障と断定するな」を含む（IMPROVEMENTS 2026-08-18）
ST2="$TMP/state_warn"; rm -rf "$ST2"
QUORUM_STATE_DIR="$ST2" bash "$CHECK" --backend wb "$TMP/empty.md" >/dev/null 2>&1
warn="$(QUORUM_STATE_DIR="$ST2" bash "$CHECK" --backend wb "$TMP/empty.md" 2>&1 >/dev/null)"
t "連続警告は「恒久故障と断定せず枠は残す」を含む" \
  "$(printf '%s' "$warn" | grep -q '恒久故障と断定せず'; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
