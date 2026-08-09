#!/usr/bin/env bash
# detect_panel.sh の「連続欠席の警告」と `--check` の exit code 規約を検証する。
#
# 背景（IMPROVEMENTS 2026-07-10）: opt-in 済みの backend が認証切れ・CLI 更新で恒久的に
# 落ちていても、毎回「一時的な欠席」として無言でネイティブ補完されるため、パネルが静かに
# 同族寄りへ退化して根本原因が放置される。opt-out（意図的な不参加）と区別して数える必要がある。
#
# exit code 規約: 0=可用 / 2=意図的に不参加 / その他非0=参加したいのに使えない
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$REPO/skills/quorum/scripts/detect_panel.sh"
SCRIPTS="$REPO/skills/quorum/scripts"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mk_env() { # mk_env <dir> [name:check終了コード ...]
  local d="$1"; shift
  mkdir -p "$d"
  cp "$DETECT" "$d/"
  local spec n rc
  for spec in "$@"; do
    n="${spec%%:*}"; rc="${spec##*:}"
    printf '#!/usr/bin/env bash\n[ "${1:-}" = "--check" ] && exit %s\ncat >/dev/null\n' "$rc" > "$d/run_$n.sh"
  done
}

run_detect() { # run_detect <dir> <state_dir> → stderr を stdout に混ぜず別取り
  local d="$1" state="$2"
  QUORUM_STATE_DIR="$state" bash "$d/detect_panel.sh" 2>"$TMP/err" >"$TMP/out"
}

# --- 参加したいのに使えない（exit 1）は数え、閾値で警告する ---
mk_env "$TMP/broken" codex:1
S1="$TMP/state1"
run_detect "$TMP/broken" "$S1"
t "1回目は警告しない" "$(! grep -q '警告' "$TMP/err"; echo $?)"
run_detect "$TMP/broken" "$S1"
t "2回目も警告しない（既定閾値 3）" "$(! grep -q '警告' "$TMP/err"; echo $?)"
run_detect "$TMP/broken" "$S1"
t "3回目で警告する" "$(grep -q 'codex が 3 回連続で欠席' "$TMP/err"; echo $?)"
t "警告は stderr のみ（stdout のパネルを汚さない）" \
  "$([ "$(cat "$TMP/out")" = "$(printf 'opus\nopus\nopus')" ]; echo $?)"

# --- 成功したらカウンタがリセットされる ---
mk_env "$TMP/fixed" codex:0
cp "$S1/absence.tsv" "$TMP/state2_seed" ; mkdir -p "$TMP/state2"; cp "$TMP/state2_seed" "$TMP/state2/absence.tsv"
run_detect "$TMP/fixed" "$TMP/state2"
t "可用に戻ればカウンタが 0 に戻る" \
  "$(awk -F'\t' '$1=="codex"{print $2}' "$TMP/state2/absence.tsv" | grep -qx 0; echo $?)"
t "可用に戻った回は警告しない" "$(! grep -q '警告' "$TMP/err"; echo $?)"

# --- opt-out（exit 2）は故障ではないので数えない ---
mk_env "$TMP/optout" codex:2
S3="$TMP/state3"
for _ in 1 2 3 4 5; do run_detect "$TMP/optout" "$S3"; done
t "opt-out は何回続いても警告しない" "$(! grep -q '警告' "$TMP/err"; echo $?)"
t "opt-out のカウンタは 0 のまま" \
  "$(awk -F'\t' '$1=="codex"{print $2}' "$S3/absence.tsv" | grep -qx 0; echo $?)"

# --- 閾値は環境変数で変更でき、0 で無効化できる ---
mk_env "$TMP/thresh" grok:1
S4="$TMP/state4"
QUORUM_ABSENCE_WARN=1 QUORUM_STATE_DIR="$S4" bash "$TMP/thresh/detect_panel.sh" 2>"$TMP/err" >/dev/null
t "QUORUM_ABSENCE_WARN=1 なら初回から警告" "$(grep -q 'grok が 1 回連続で欠席' "$TMP/err"; echo $?)"
S5="$TMP/state5"
for _ in 1 2 3 4; do
  QUORUM_ABSENCE_WARN=0 QUORUM_STATE_DIR="$S5" bash "$TMP/thresh/detect_panel.sh" 2>"$TMP/err" >/dev/null
done
t "QUORUM_ABSENCE_WARN=0 で無効化できる" "$(! grep -q '警告' "$TMP/err"; echo $?)"
t "無効時は状態ファイルも作らない" "$([ ! -e "$S5/absence.tsv" ]; echo $?)"

# --- 実 run_*.sh が exit 2 規約を守っているか ---
NOBIN="/usr/bin:/bin"   # 対象CLIが1つも無い PATH（bash 等の基本コマンドは残す）
code=0; env -u QUORUM_ENABLE_CODEX bash "$SCRIPTS/run_codex.sh" --check || code=$?
t "run_codex.sh: opt-out は exit 2" "$([ "$code" = "2" ]; echo $?)"
code=0; QUORUM_ENABLE_CODEX=1 HOME="$TMP" PATH="$NOBIN" bash "$SCRIPTS/run_codex.sh" --check || code=$?
t "run_codex.sh: 参加したいのに CLI 無しは exit 1" "$([ "$code" = "1" ]; echo $?)"

code=0; env -u QUORUM_ENABLE_GROK bash "$SCRIPTS/run_grok.sh" --check || code=$?
t "run_grok.sh: opt-out は exit 2" "$([ "$code" = "2" ]; echo $?)"
code=0; QUORUM_ENABLE_GROK=1 XAI_API_KEY= HOME="$TMP" PATH="$NOBIN" bash "$SCRIPTS/run_grok.sh" --check || code=$?
t "run_grok.sh: 参加したいのに CLI/キー無しは exit 1" "$([ "$code" = "1" ]; echo $?)"

code=0; env -u QUORUM_ENABLE_GEMINI bash "$SCRIPTS/run_gemini.sh" --check || code=$?
t "run_gemini.sh: opt-out は exit 2" "$([ "$code" = "2" ]; echo $?)"

code=0; env -u QUORUM_ENABLE_CLAUDE bash "$SCRIPTS/run_claude.sh" --check || code=$?
t "run_claude.sh: opt-out は exit 2" "$([ "$code" = "2" ]; echo $?)"
code=0; QUORUM_ENABLE_CLAUDE=1 ANTHROPIC_API_KEY=sk-dummy HOME="$TMP" PATH="$NOBIN" \
  bash "$SCRIPTS/run_claude.sh" --check || code=$?
t "run_claude.sh: APIキー課金ガードは exit 2（意図的な不参加）" "$([ "$code" = "2" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
