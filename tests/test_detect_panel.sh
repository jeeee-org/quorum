#!/usr/bin/env bash
# detect_panel.sh の純ロジックテスト（API 呼び出しなし）。
# モックの run_<name>.sh を temp dir に置き、バックフィル・除外・--raw・目標数の挙動を検証する。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$REPO/skills/quorum/scripts/detect_panel.sh"
PASS=0; FAIL=0

t() { # t <名前> <期待(改行区切り)> <実際>
  local name="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    PASS=$((PASS+1)); echo "ok   - $name"
  else
    FAIL=$((FAIL+1)); echo "FAIL - $name"
    echo "  want: $(printf '%s' "$want" | tr '\n' ' ')"
    echo "  got : $(printf '%s' "$got" | tr '\n' ' ')"
  fi
}

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

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mk_env "$TMP/none"
t "外部なし → opus×4 にバックフィル" \
  "$(printf 'opus\nopus\nopus\nopus')" \
  "$(bash "$TMP/none/detect_panel.sh")"

mk_env "$TMP/one" grok:0
t "grok 可用 → opus+grok+opus 補完で4枠" \
  "$(printf 'opus\ngrok\nopus\nopus')" \
  "$(bash "$TMP/one/detect_panel.sh")"

mk_env "$TMP/ng" grok:1
t "--check 非0 のバックエンドは除外" \
  "$(printf 'opus\nopus\nopus\nopus')" \
  "$(bash "$TMP/ng/detect_panel.sh")"

mk_env "$TMP/raw" codex:0 grok:0
t "--raw は distinct のみ（バックフィルなし）" \
  "$(printf 'opus\ncodex\ngrok')" \
  "$(bash "$TMP/raw/detect_panel.sh" --raw)"

mk_env "$TMP/codex" codex:0 grok:0
t "Codexホストは外部codexを除外" \
  "$(printf 'codex-native\ngrok')" \
  "$(QUORUM_HOST=codex bash "$TMP/codex/detect_panel.sh" --raw)"

mk_env "$TMP/codex-fill"
t "Codexホストはcodex-nativeで4枠に補完" \
  "$(printf 'codex-native\ncodex-native\ncodex-native\ncodex-native')" \
  "$(bash "$TMP/codex-fill/detect_panel.sh" --host codex)"

QUORUM_HOST=invalid bash "$TMP/codex-fill/detect_panel.sh" >/dev/null 2>&1
t "不明なホストはexit 2" "2" "$?"

mk_env "$TMP/size"
t "QUORUM_PANEL_SIZE=6 で opus×6" \
  "$(printf 'opus\nopus\nopus\nopus\nopus\nopus')" \
  "$(QUORUM_PANEL_SIZE=6 bash "$TMP/size/detect_panel.sh")"

mk_env "$TMP/over" aa:0 bb:0 cc:0
t "distinct が目標超でもトリムせず全出力（トリムは SKILL 側）" \
  "$(printf 'opus\naa\nbb\ncc')" \
  "$(QUORUM_PANEL_SIZE=2 bash "$TMP/over/detect_panel.sh")"

# 規約外のファイル名（validate_json.sh 等）はバックエンドとして拾われないこと
mk_env "$TMP/misc"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/misc/validate_json.sh"
t "run_*.sh 以外のスクリプトは無視される" \
  "$(printf 'opus\nopus\nopus\nopus')" \
  "$(bash "$TMP/misc/detect_panel.sh")"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
