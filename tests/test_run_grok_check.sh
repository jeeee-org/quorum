#!/usr/bin/env bash
# run_grok.sh の --check 可用スイッチと CLI 実行経路（ガード前置・プロンプト受け渡し）を
# 検証する（実API/CLI 呼び出しなし・mock）。
# grok は既定オフのオプトイン（run_codex.sh / run_gemini.sh と対称）。1/true/yes で参加。
#
# プロンプト受け渡しは2経路:
#   本線     … --prompt-file（argv 上限なし。IMPROVEMENTS 2026-07-25/07-30/08-05 の是正）
#   旧CLI用  … -p argv。上限超過は無言の空応答ではなく明示エラー（exit 4）で落とす
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$REPO/skills/quorum/scripts/run_grok.sh"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ARGS="$TMP/args"
SEEN="$TMP/seen_prompt"

# --prompt-file 対応の現行 CLI を模した mock
NEW_BIN="$TMP/bin-new"; mkdir -p "$NEW_BIN"
cat > "$NEW_BIN/grok" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  printf 'Options:\n  -p, --single <PROMPT>\n      --prompt-file <PATH>\n'
  exit 0
fi
[ -n "${MOCK_ARGS:-}" ] && printf '%s\n' "$@" > "$MOCK_ARGS"
if [ "${1:-}" = "--prompt-file" ] && [ -n "${MOCK_SEEN:-}" ]; then cp "$2" "$MOCK_SEEN"; fi
printf 'mock grok answer\n'
SH
chmod +x "$NEW_BIN/grok"

# --prompt-file 非対応の旧 CLI を模した mock
OLD_BIN="$TMP/bin-old"; mkdir -p "$OLD_BIN"
cat > "$OLD_BIN/grok" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  printf 'Options:\n  -p, --single <PROMPT>\n'
  exit 0
fi
[ -n "${MOCK_ARGS:-}" ] && printf '%s\n' "$@" > "$MOCK_ARGS"
printf 'mock grok answer\n'
SH
chmod +x "$OLD_BIN/grok"

# XAI_API_KEY を消して「CLI 経路のみ」を評価対象にする（キー経路の混入を防ぐ）。
env -u QUORUM_ENABLE_GROK -u XAI_API_KEY PATH="$NEW_BIN:$PATH" bash "$RUN" --check
t "--check は未設定で非0（既定オフ）" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="" XAI_API_KEY= PATH="$NEW_BIN:$PATH" bash "$RUN" --check
t "--check は空文字で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="0" XAI_API_KEY= PATH="$NEW_BIN:$PATH" bash "$RUN" --check
t "--check は 0 で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="false" XAI_API_KEY= PATH="$NEW_BIN:$PATH" bash "$RUN" --check
t "--check は false で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="no" XAI_API_KEY= PATH="$NEW_BIN:$PATH" bash "$RUN" --check
t "--check は no で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="1" XAI_API_KEY= PATH="$NEW_BIN:$PATH" bash "$RUN" --check
t "--check は 1 + CLI 可用で成功（opt-in）" "$?"

# --- 本線: --prompt-file 経路 ---
# HOME を隔離する（run_grok.sh が $HOME/.local/bin 等を PATH 先頭に足すため、実 grok が
# 入っているPCでは mock より実CLIが勝ってしまう）。
output="$(printf 'same prompt' | HOME="$TMP" XAI_API_KEY= PATH="$NEW_BIN:$PATH" \
  MOCK_ARGS="$ARGS" MOCK_SEEN="$SEEN" bash "$RUN")"
t "最終回答をstdoutへ返す" "$([ "$output" = "mock grok answer" ]; echo $?)"
t "--prompt-file でプロンプトを渡す" "$([ "$(head -n1 "$ARGS")" = "--prompt-file" ]; echo $?)"
t "プロンプト本文を argv に載せない" "$(! grep -q 'same prompt' "$ARGS"; echo $?)"
t "パネリスト専用ガードを前置" "$(grep -q '単一の回答者' "$SEEN"; echo $?)"
t "プロンプトを末尾に保持" "$([ "$(tail -n1 "$SEEN")" = "same prompt" ]; echo $?)"

# モデル指定は --prompt-file と併用できる
printf 'p' | HOME="$TMP" XAI_API_KEY= GROK_MODEL=grok-9 PATH="$NEW_BIN:$PATH" \
  MOCK_ARGS="$ARGS" bash "$RUN" >/dev/null
t "GROK_MODEL を -m で渡す" "$(grep -qx -- '-m' "$ARGS" && grep -qx 'grok-9' "$ARGS"; echo $?)"

# 大型 pack（argv 上限超）でも --prompt-file なら通る
python3 -c "import sys; sys.stdout.write('あ' * 90000)" > "$TMP/big.txt"   # 約 270KB
output="$(HOME="$TMP" XAI_API_KEY= PATH="$NEW_BIN:$PATH" MOCK_ARGS="$ARGS" MOCK_SEEN="$SEEN" \
  bash "$RUN" < "$TMP/big.txt")"
t "270KB の pack でも --prompt-file なら成功" "$([ "$output" = "mock grok answer" ]; echo $?)"
t "270KB のプロンプト本文がファイルに全量届く" \
  "$([ "$(wc -c < "$SEEN")" -gt 270000 ]; echo $?)"

# --- 旧 CLI 向けフォールバック: -p argv 経路 ---
output="$(printf 'same prompt' | HOME="$TMP" XAI_API_KEY= PATH="$OLD_BIN:$PATH" \
  MOCK_ARGS="$ARGS" bash "$RUN")"
t "--prompt-file 非対応なら -p にフォールバック" \
  "$([ "$(head -n1 "$ARGS")" = "-p" ] && [ "$output" = "mock grok answer" ]; echo $?)"
t "フォールバックでもガードを前置" "$(grep -q '単一の回答者' "$ARGS"; echo $?)"

# 上限超過は「無言の空応答」ではなく明示エラーで落とす
err="$TMP/argv.err"
output="$(HOME="$TMP" XAI_API_KEY= PATH="$OLD_BIN:$PATH" bash "$RUN" < "$TMP/big.txt" 2>"$err")"; rc=$?
t "フォールバックの上限超過は exit 4" "$([ "$rc" = "4" ]; echo $?)"
t "上限超過は stdout を汚さない" "$([ -z "$output" ]; echo $?)"
t "上限超過の理由を stderr に明示" "$(grep -q 'argv-too-long' "$err"; echo $?)"
# check_answer.sh がその stderr から原因を名指しできること（連携の確認）
: > "$TMP/empty.md"
verdict="$(bash "$REPO/skills/quorum/scripts/check_answer.sh" "$TMP/empty.md" "$err")"
t "check_answer が argv-too-long を判定できる" \
  "$([ "$verdict" = "invalid_response:argv-too-long" ]; echo $?)"

# 閾値は QUORUM_MAX_ARGV_BYTES で調整できる
output="$(printf 'same prompt' | HOME="$TMP" XAI_API_KEY= QUORUM_MAX_ARGV_BYTES=5 \
  PATH="$OLD_BIN:$PATH" bash "$RUN" 2>/dev/null)"; rc=$?
t "QUORUM_MAX_ARGV_BYTES で閾値を下げられる" "$([ "$rc" = "4" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
