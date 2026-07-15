#!/usr/bin/env bash
# run_grok.sh の --check 可用スイッチと CLI 実行経路（ガード前置）を検証する（実API/CLI 呼び出しなし・mock）。
# grok は既定オフのオプトイン（run_codex.sh / run_gemini.sh と対称）。1/true/yes で参加。
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
MOCK_BIN="$TMP/bin"; mkdir -p "$MOCK_BIN"
ARGS="$TMP/args"
cat > "$MOCK_BIN/grok" <<'SH'
#!/usr/bin/env bash
[ -n "${MOCK_ARGS:-}" ] && printf '%s\n' "$@" > "$MOCK_ARGS"
printf 'mock grok answer\n'
SH
chmod +x "$MOCK_BIN/grok"

# XAI_API_KEY を消して「CLI 経路のみ」を評価対象にする（キー経路の混入を防ぐ）。
env -u QUORUM_ENABLE_GROK -u XAI_API_KEY PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は未設定で非0（既定オフ）" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="" XAI_API_KEY= PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は空文字で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="0" XAI_API_KEY= PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は 0 で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="false" XAI_API_KEY= PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は false で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="no" XAI_API_KEY= PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は no で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GROK="1" XAI_API_KEY= PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は 1 + CLI 可用で成功（opt-in）" "$?"

# CLI 実行経路: ガード前置と -p argv 渡しを検証
# HOME を隔離する（run_grok.sh が $HOME/.local/bin 等を PATH 先頭に足すため、実 grok が
# 入っているPCでは mock より実CLIが勝ってしまう）。
output="$(printf 'same prompt' | HOME="$TMP" XAI_API_KEY= PATH="$MOCK_BIN:$PATH" MOCK_ARGS="$ARGS" bash "$RUN")"
t "最終回答をstdoutへ返す" "$([ "$output" = "mock grok answer" ]; echo $?)"
t "-p でプロンプトを渡す" "$([ "$(head -n1 "$ARGS")" = "-p" ]; echo $?)"
t "パネリスト専用ガードを前置" "$(grep -q '単一の回答者' "$ARGS"; echo $?)"
t "プロンプトを末尾に保持" "$([ "$(tail -n1 "$ARGS")" = "same prompt" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
