#!/usr/bin/env bash
# run_grok.sh の --check 可用スイッチと CLI 実行経路（ガード前置・プロンプト受け渡し）を
# 検証する（実API/CLI 呼び出しなし・mock）。
# grok は既定オフのオプトイン（run_codex.sh / run_gemini.sh と対称）。1/true/yes で参加。
#
# プロンプト受け渡しは2経路:
#   本線     … --prompt-file（argv 上限なし。IMPROVEMENTS 2026-07-25/07-30/08-05 の是正）
#   旧CLI用  … -p argv。上限超過は無言の空応答ではなく明示エラー（exit 4）で落とす
# メタ応答リトライ（IMPROVEMENTS 2026-08-11 / 08-12）は末尾の専用セクションで検証する。
set -uo pipefail

# 受け渡し経路の検証中はリトライを止める（mock の回答は短くリトライ条件に当たるため）。
# リトライ自体は末尾の専用セクションで明示的に有効化して検証する。
export QUORUM_GROK_RETRY=0

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

# --- メタ応答リトライ（IMPROVEMENTS 2026-08-11 / 08-12） ---
# grok は重い依頼ほど「これから読みます」だけ返して exit 0 する。guard の文言では止まらない
# ことが 4 run で確認されたので、run 側で1回だけ投げ直す。
RETRY_BIN="$TMP/bin-retry"; mkdir -p "$RETRY_BIN"
cat > "$RETRY_BIN/grok" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then printf 'Options:\n      --prompt-file <PATH>\n'; exit 0; fi
n=1
[ -s "$MOCK_COUNT" ] && n=$(( $(cat "$MOCK_COUNT") + 1 ))
printf '%s' "$n" > "$MOCK_COUNT"
[ "${1:-}" = "--prompt-file" ] && cp "$2" "$MOCK_SEEN.$n"
case "${MOCK_MODE:-short-then-long}" in
  short-then-long)    [ "$n" = "1" ] && printf 'これから全文を読み、根拠を揃えます。\n' || python3 -c "print('回答本文 ' * 200)" ;;
  always-short)       printf 'これから全文を読み、根拠を揃えます。\n' ;;
  long)               python3 -c "print('回答本文 ' * 200)" ;;
  short-then-shorter) [ "$n" = "1" ] && printf 'AAAAAAAAAAAAAAAAAAAA\n' || printf 'B\n' ;;
esac
SH
chmod +x "$RETRY_BIN/grok"

COUNT="$TMP/count"; SEEN2="$TMP/seen2"
run_retry() { # run_retry <MOCK_MODE> [<QUORUM_GROK_RETRY>]
  : > "$COUNT"; rm -f "$SEEN2".*
  HOME="$TMP" XAI_API_KEY= PATH="$RETRY_BIN:$PATH" MOCK_COUNT="$COUNT" MOCK_SEEN="$SEEN2" \
    MOCK_MODE="$1" QUORUM_GROK_RETRY="${2:-1}" bash "$RUN" 2>"$TMP/retry.err" <<< 'ORIGINAL QUESTION'
}

output="$(run_retry short-then-long)"; rc=$?
t "メタ応答だけなら1回だけ再投入する" "$([ "$(cat "$COUNT")" = "2" ] && [ "$rc" = "0" ]; echo $?)"
t "再投入の回答を最終出力にする" "$(printf '%s' "$output" | grep -q '回答本文'; echo $?)"
t "再投入したことを stderr に残す" "$(grep -q '再投入' "$TMP/retry.err"; echo $?)"
t "再投入プロンプトに元の問いを保持" "$(grep -q 'ORIGINAL QUESTION' "$SEEN2.2"; echo $?)"
t "再投入プロンプトに「予告だけの応答は無効」を足す" "$(grep -q '再投入' "$SEEN2.2"; echo $?)"
t "初回プロンプトには再投入指示を足さない" "$(! grep -q '再投入' "$SEEN2.1"; echo $?)"

output="$(run_retry long)"
t "十分な長さの回答なら再投入しない" "$([ "$(cat "$COUNT")" = "1" ]; echo $?)"

output="$(run_retry short-then-long 0)"
t "QUORUM_GROK_RETRY=0 で再投入を止められる" "$([ "$(cat "$COUNT")" = "1" ]; echo $?)"

output="$(run_retry always-short)"; rc=$?
t "再投入後も短ければ meta-only を stderr へ明示" "$(grep -q 'invalid_response:meta-only' "$TMP/retry.err"; echo $?)"
t "meta-only でも回答は返す（自動棄却しない）" \
  "$([ "$rc" = "0" ] && printf '%s' "$output" | grep -q 'これから'; echo $?)"
verdict="$(printf '%s' "$output" | bash "$REPO/skills/quorum/scripts/check_answer.sh")"
t "meta-only は check_answer が too_short で拾う" \
  "$(case "$verdict" in invalid_response:too_short:*) true ;; *) false ;; esac; echo $?)"

output="$(run_retry short-then-shorter)"
t "再投入が更に短くても初回の回答を失わない" "$(printf '%s' "$output" | grep -q 'AAAAAAAAAA'; echo $?)"

# --- 連続 invalid の警告（check_answer の --backend 連携） ---
STATE="$TMP/state"
short="$TMP/meta.md"; printf 'これから読みます。\n' > "$short"
long2="$TMP/real.md"; python3 -c "print('回答本文 ' * 200)" > "$long2"
CA="$REPO/skills/quorum/scripts/check_answer.sh"

QUORUM_STATE_DIR="$STATE" bash "$CA" --backend grok "$short" >/dev/null 2>"$TMP/w1.err"
t "1回目の invalid では警告しない" "$(! grep -q '連続で実質回答なし' "$TMP/w1.err"; echo $?)"
QUORUM_STATE_DIR="$STATE" bash "$CA" --backend grok "$short" >/dev/null 2>"$TMP/w2.err"
t "2回連続の invalid で警告する（既定 2）" "$(grep -q 'grok が 2 回連続で実質回答なし' "$TMP/w2.err"; echo $?)"
t "警告は stderr（stdout は verdict のみ）" \
  "$([ "$(QUORUM_STATE_DIR="$STATE" bash "$CA" --backend grok "$long2" 2>/dev/null)" = "ok" ]; echo $?)"
QUORUM_STATE_DIR="$STATE" bash "$CA" --backend grok "$short" >/dev/null 2>"$TMP/w3.err"
t "実質回答が返ればカウンタは 0 に戻る" "$(! grep -q '連続で実質回答なし' "$TMP/w3.err"; echo $?)"
QUORUM_STATE_DIR="$STATE" QUORUM_INVALID_WARN=0 bash "$CA" --backend grok "$short" >/dev/null 2>"$TMP/w4.err"
QUORUM_STATE_DIR="$STATE" QUORUM_INVALID_WARN=0 bash "$CA" --backend grok "$short" >/dev/null 2>>"$TMP/w4.err"
t "QUORUM_INVALID_WARN=0 で警告を止められる" "$(! grep -q '連続で実質回答なし' "$TMP/w4.err"; echo $?)"
t "backend ごとに独立して数える" \
  "$(QUORUM_STATE_DIR="$STATE" bash "$CA" --backend codex "$short" >/dev/null 2>"$TMP/w5.err"; ! grep -q '連続で実質回答なし' "$TMP/w5.err"; echo $?)"
t "--backend 無指定なら状態ファイルを作らない" \
  "$(rm -rf "$TMP/state2"; QUORUM_STATE_DIR="$TMP/state2" bash "$CA" "$short" >/dev/null 2>&1; [ ! -e "$TMP/state2/invalid.tsv" ]; echo $?)"

# --- エージェント挙動を CLI 側で落とす（IMPROVEMENTS 2026-08-15） ---
# plan mode が有効だと非対話の単発実行は「計画を述べた時点で正常終了」する。観測された
# メタ応答は plan そのものの形だった。プロンプト側の文言強化は 9 run ぶん効かなかったので
# CLI のオプションで落とす。存在する時だけ渡す（旧 CLI のマシンを壊さない）。
GUARD_BIN="$TMP/bin-guard"; mkdir -p "$GUARD_BIN"
cat > "$GUARD_BIN/grok" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  printf 'Options:\n  -p, --single <PROMPT>\n      --prompt-file <PATH>\n      --no-plan\n          Disable plan mode\n      --no-subagents\n          Disable subagent spawning\n'
  exit 0
fi
[ -n "${MOCK_ARGS:-}" ] && printf '%s\n' "$@" > "$MOCK_ARGS"
printf 'mock grok answer\n'
SH
chmod +x "$GUARD_BIN/grok"

# HOME を temp に振るのは必須——run_grok.sh は $HOME/.local/bin を PATH 先頭に足すので、
# 隔離しないと実 CLI が mock より優先され、テストが実 API を叩いてしまう。
rm -f "$ARGS"
printf 'q' | HOME="$TMP" XAI_API_KEY= PATH="$GUARD_BIN:$PATH" MOCK_ARGS="$ARGS" bash "$RUN" >/dev/null 2>&1
t "--help にあれば --no-plan を渡す" "$(grep -qx -- '--no-plan' "$ARGS"; echo $?)"
t "--help にあれば --no-subagents を渡す" "$(grep -qx -- '--no-subagents' "$ARGS"; echo $?)"
t "ガード追加後も --prompt-file の直後がパスのまま" \
  "$([ "$(sed -n '1p' "$ARGS")" = "--prompt-file" ] \
    && case "$(sed -n '2p' "$ARGS")" in ''|--*) false ;; *) true ;; esac; echo $?)"

rm -f "$ARGS"
printf 'q' | HOME="$TMP" XAI_API_KEY= PATH="$NEW_BIN:$PATH" MOCK_ARGS="$ARGS" bash "$RUN" >/dev/null 2>&1
t "--help に無い旧CLIには渡さない（壊さない）" \
  "$([ -f "$ARGS" ] && ! grep -qx -- '--no-plan' "$ARGS" && ! grep -qx -- '--no-subagents' "$ARGS"; echo $?)"

# --- --version 規約（detect_panel が版の変化を知らせるための申告） ---
cat > "$GUARD_BIN/grok-ver" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "grok 9.9.9 (mock)"; exit 0; }
SH
out="$(HOME="$TMP" PATH="$GUARD_BIN:$PATH" bash "$RUN" --version </dev/null 2>/dev/null)"
t "--version は CLI の版を1行返す" \
  "$([ -n "$out" ] && [ "$(printf '%s\n' "$out" | wc -l)" = "1" ]; echo $?)"

# grok の無い最小 PATH（PATH を空にすると bash 自体が引けないので coreutils は残す）。
# HOME も temp なので run_grok.sh が足す $HOME/.local/bin / $HOME/.grok/bin も空になる。
out="$(HOME="$TMP" PATH="/usr/bin:/bin" bash "$RUN" --version </dev/null 2>/dev/null)"
t "CLI が無ければ unavailable を返す（固まらない）" "$([ "$out" = "unavailable" ]; echo $?)"

t "--version は stdin を消費しない（プロンプトを読みに行かない）" \
  "$(printf 'x' | HOME="$TMP" PATH="$GUARD_BIN:$PATH" timeout 15 bash "$RUN" --version >/dev/null 2>&1; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
