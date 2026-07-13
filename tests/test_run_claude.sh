#!/usr/bin/env bash
# run_claude.sh の課金ガード・隔離フラグ・stdin入力をモックで検証する。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$REPO/skills/quorum/scripts/run_claude.sh"
PASS=0; FAIL=0

t() {
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MOCK_BIN="$TMP/bin"; mkdir -p "$MOCK_BIN"
ARGS="$TMP/args"; STDIN="$TMP/stdin"; PWD_OUT="$TMP/pwd"

cat > "$MOCK_BIN/claude" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  printf '%s\n' '  --safe-mode' '  --no-session-persistence'
  exit 0
fi
printf '%s\n' "$@" > "$MOCK_ARGS"
cat > "$MOCK_STDIN"
pwd > "$MOCK_PWD"
printf 'mock claude answer\n'
SH
chmod +x "$MOCK_BIN/claude"

env -u QUORUM_ENABLE_CLAUDE -u ANTHROPIC_API_KEY PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check はOAuth想定で既定オン" "$?"
QUORUM_ENABLE_CLAUDE=0 PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は0で無効" "$([ "$?" != "0" ]; echo $?)"
ANTHROPIC_API_KEY=test PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "APIキー環境は明示許可なしで無効" "$([ "$?" != "0" ]; echo $?)"
ANTHROPIC_API_KEY=test QUORUM_ALLOW_CLAUDE_API=1 PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "APIキー環境も明示許可なら有効" "$?"

output="$(printf 'same prompt' | env -u ANTHROPIC_API_KEY PATH="$MOCK_BIN:$PATH" MOCK_ARGS="$ARGS" MOCK_STDIN="$STDIN" MOCK_PWD="$PWD_OUT" bash "$RUN")"
t "最終回答をstdoutへ返す" "$([ "$output" = "mock claude answer" ]; echo $?)"
t "プロンプトをstdinで渡す" "$([ "$(cat "$STDIN")" = "same prompt" ]; echo $?)"
t "safe-modeを指定" "$(grep -qx -- '--safe-mode' "$ARGS"; echo $?)"
t "sessionを保存しない" "$(grep -qx -- '--no-session-persistence' "$ARGS"; echo $?)"
t "モデルをopusに固定" "$(grep -qx -- 'opus' "$ARGS"; echo $?)"
t "ツールを無効化" "$(grep -qx -- '--tools' "$ARGS"; echo $?)"
t "空の一時CWDで実行" "$([ "$(cat "$PWD_OUT")" != "$REPO" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
