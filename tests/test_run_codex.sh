#!/usr/bin/env bash
# run_codex.sh が分離フラグとstdin入力を保ったままCodex CLIを呼ぶことをモックで検証する。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$REPO/skills/quorum/scripts/run_codex.sh"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MOCK_BIN="$TMP/bin"; mkdir -p "$MOCK_BIN"
ARGS="$TMP/args"; STDIN="$TMP/stdin"

cat > "$MOCK_BIN/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_ARGS"
cat > "$MOCK_STDIN"
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift; fi
  shift
done
printf 'mock answer\n' > "$out"
SH
chmod +x "$MOCK_BIN/codex"

# --check: 既定オフ（未設定=不参加）・1/true/yes で opt-in
env -u QUORUM_ENABLE_CODEX PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は未設定で非0（既定オフ）" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_CODEX="" PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は空文字で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_CODEX="0" PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は 0 で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_CODEX="false" PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は false で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_CODEX="1" PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は 1 + CLI 可用で成功（opt-in）" "$?"

output="$(printf 'same prompt' | PATH="$MOCK_BIN:$PATH" MOCK_ARGS="$ARGS" MOCK_STDIN="$STDIN" bash "$RUN")"
t "最終回答をstdoutへ返す" "$([ "$output" = "mock answer" ]; echo $?)"
t "パネリスト専用ガードを前置" "$(grep -q '単一の回答者' "$STDIN"; echo $?)"
t "プロンプトをstdinの末尾に保持" "$([ "$(tail -n1 "$STDIN")" = "same prompt" ]; echo $?)"
t "ephemeralを指定" "$(grep -qx -- '--ephemeral' "$ARGS"; echo $?)"
t "user configを無視" "$(grep -qx -- '--ignore-user-config' "$ARGS"; echo $?)"
t "モデルを明示固定" "$(grep -qx -- 'gpt-5.6-sol' "$ARGS"; echo $?)"
t "--disable 非対応CLIには機能フラグを渡さない" "$(! grep -qx -- '--disable' "$ARGS"; echo $?)"

# --disable 対応CLI（0.144.1 以降）では collab 機構を無効化する
# 由来: exec + --ephemeral + 空 WORK_DIR では collab が動かないのにモデルからは使えるように
# 見え、重いタスクで spawn を試みて固まる（IMPROVEMENTS 2026-07-13）。
NEW_BIN="$TMP/bin-new"; mkdir -p "$NEW_BIN"
cat > "$NEW_BIN/codex" <<'SH'
#!/usr/bin/env bash
if [ "${2:-}" = "--help" ]; then
  printf 'Options:\n      --enable <FEATURE>\n      --disable <FEATURE>\n'
  exit 0
fi
printf '%s\n' "$@" > "$MOCK_ARGS"
cat > "$MOCK_STDIN"
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift; fi
  shift
done
printf 'mock answer\n' > "$out"
SH
chmod +x "$NEW_BIN/codex"

output="$(printf 'p' | PATH="$NEW_BIN:$PATH" MOCK_ARGS="$ARGS" MOCK_STDIN="$STDIN" bash "$RUN")"
t "--disable 対応CLIでも回答を返す" "$([ "$output" = "mock answer" ]; echo $?)"
t "multi_agent を --disable で落とす" \
  "$(grep -qx -- '--disable' "$ARGS" && grep -qx 'multi_agent' "$ARGS"; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
