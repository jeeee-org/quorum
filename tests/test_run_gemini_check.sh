#!/usr/bin/env bash
# run_gemini.sh --check のオプトイン判定を検証する（API 呼び出しなし・mock CLI）。
# gemini は既定除外のオプトイン。0/false/no/空文字は無効扱い（run_codex.sh と同規約）。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$REPO/skills/quorum/scripts/run_gemini.sh"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MOCK_BIN="$TMP/bin"; mkdir -p "$MOCK_BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK_BIN/gemini"
chmod +x "$MOCK_BIN/gemini"

env -u QUORUM_ENABLE_GEMINI PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は未設定で非0（既定除外）" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GEMINI="" PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は空文字で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GEMINI="0" PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は 0 で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GEMINI="false" PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は false で非0" "$([ "$?" != "0" ]; echo $?)"
QUORUM_ENABLE_GEMINI="1" PATH="$MOCK_BIN:$PATH" bash "$RUN" --check
t "--check は 1 + CLI 可用で成功" "$?"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
