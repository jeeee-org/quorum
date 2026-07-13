#!/usr/bin/env bash
# 利用可能なバックエンドを検出し、ホストのネイティブ・サブエージェントで補完したパネルを出力する。
#
# 規約: scripts/ 配下の `run_<name>.sh` が1バックエンド。
#   - `run_<name>.sh --check` … 使えるなら exit 0、使えないなら非0
#   - `run_<name>.sh`（引数なし）… プロンプトを stdin で受け、回答を stdout へ
# 新しいモデルを足したい時は、この規約に従う run_<name>.sh を置くだけでよい。
# ネイティブ枠はスクリプトではなく、ホストのサブエージェント機構で spawn する。
#   QUORUM_HOST=claude（既定）: opus
#   QUORUM_HOST=codex          : codex-native（外部 run_codex.sh は再帰防止のため除外）
#
# 出力: パネリストを1行ずつ（**multiset**。同じ名前が複数行 = その回数だけ独立実行する）。
#   Claudeホストは opus、Codexホストは codex-native をネイティブ枠にし、使えない枠も同じ
#   ネイティブ実行で補完する。外部バックエンドは --check とオプトイン設定に従う。
#
# 環境変数:
#   QUORUM_PANEL            パネルの明示指定（カンマ/空白区切りの multiset。例 "opus,opus,codex,grok"）。
#                           指定時は検出・--check・補完を全部飛ばしてそのまま出力する（増員・固定用）。
#                           使える名前は native（opus / codex-native）と run_<name>.sh。再帰防止
#                           （Codexホストの外部 codex 禁止）だけは明示指定でも上書きできない。
#   QUORUM_PANEL_SIZE       目標パネル数（既定 3）。distinct な利用可能バックエンドがこれに満たない
#                           分を補完する。補完枠は opus → codex → grok の優先順で可用なものを選ぶ
#                           （現行ホストでは Claude=opus / Codex=codex-native に一致。ネイティブ枠を
#                           fable に差し替えていても補完で fable は増殖させない）。distinct が目標を
#                           超える場合は全部出力し、トリムは SKILL 側の優先順位判断に委ねる。
#   QUORUM_NATIVE           Claudeホストのネイティブ枠の差し替え（opus | fable。既定 opus）。
#                           fable は judge と同格の高コストモデルのため、ユーザーの呼びかけ時のみ使う。
#   QUORUM_ENABLE_CODEX     codex の可用スイッチ（**既定オン**。空文字で無効化。run_codex.sh 側で判定）。
#   QUORUM_ENABLE_GEMINI=1  gemini を候補に含める（既定は除外。run_gemini.sh 側のオプトイン）。
# フラグ:
#   --raw  補完せず「利用可能な distinct バックエンド」だけを出力（デバッグ/テスト用）。
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"

RAW=0
HOST="${QUORUM_HOST:-claude}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw) RAW=1 ;;
    --host)
      [ "$#" -ge 2 ] || { echo "--host には claude または codex が必要です" >&2; exit 2; }
      HOST="$2"
      shift
      ;;
    *) echo "不明な引数: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$HOST" in
  claude)
    NATIVE="${QUORUM_NATIVE:-opus}"
    case "$NATIVE" in
      opus|fable) : ;;
      *) echo "QUORUM_NATIVE は opus または fable を指定してください: $NATIVE" >&2; exit 2 ;;
    esac
    ;;
  codex) NATIVE="codex-native" ;;
  *) echo "QUORUM_HOST は claude または codex を指定してください: $HOST" >&2; exit 2 ;;
esac

# ホストが直接 spawn できるサブエージェント名（QUORUM_PANEL の検証に使う）
is_native_name() {
  case "$HOST:$1" in
    claude:opus|claude:fable|codex:codex-native) return 0 ;;
    *) return 1 ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 明示指定（QUORUM_PANEL）があれば検出・補完を飛ばしてそのまま出力する。
# --check も飛ばす（明示された枠の実行時失敗は SKILL 側が dropped として扱う）。
if [ -n "${QUORUM_PANEL:-}" ]; then
  IFS=', ' read -ra entries <<< "$QUORUM_PANEL"
  panel=()
  for name in "${entries[@]}"; do
    [ -n "$name" ] || continue
    if is_native_name "$name"; then panel+=("$name"); continue; fi
    if [ "$HOST" = "codex" ] && [ "$name" = "codex" ]; then
      echo "QUORUM_PANEL: Codexホストでは外部 codex を指定できません（再帰防止）" >&2; exit 2
    fi
    if [ -e "$SCRIPT_DIR/run_$name.sh" ]; then panel+=("$name"); continue; fi
    echo "QUORUM_PANEL: 不明なバックエンド: $name（native または run_$name.sh のある名前を指定）" >&2; exit 2
  done
  [ "${#panel[@]}" -gt 0 ] || { echo "QUORUM_PANEL が空です" >&2; exit 2; }
  printf '%s\n' "${panel[@]}"
  exit 0
fi

# --check を通った distinct な外部バックエンド
externals=()
for s in "$SCRIPT_DIR"/run_*.sh; do
  [ -e "$s" ] || continue
  name="$(basename "$s")"; name="${name#run_}"; name="${name%.sh}"
  # Codexホストではネイティブ・サブエージェントを使う。外部Codexを再起動しない。
  [ "$HOST" = "codex" ] && [ "$name" = "codex" ] && continue
  if bash "$s" --check >/dev/null 2>&1; then
    externals+=("$name")
  fi
done

# distinct な利用可能パネル = native + externals
panel=("$NATIVE")
if [ "${#externals[@]}" -gt 0 ]; then
  panel+=("${externals[@]}")
fi

if [ "$RAW" = "1" ]; then
  printf '%s\n' "${panel[@]}"
  exit 0
fi

# 欠員の補完枠は opus → codex → grok の優先順で可用なものを選ぶ。
# Claudeホストは opus（常に可用）、Codexホストは opus が無いので codex-native に落ちる。
# どれも決まらない場合のみネイティブ枠（QUORUM_NATIVE=fable でも補完で fable は増殖させない）。
has_external() { local e; for e in ${externals[@]+"${externals[@]}"}; do [ "$e" = "$1" ] && return 0; done; return 1; }
BACKFILL=""
if [ "$HOST" = "claude" ]; then
  BACKFILL="opus"
elif [ "$HOST" = "codex" ]; then
  BACKFILL="codex-native"
elif has_external codex; then
  BACKFILL="codex"
elif has_external grok; then
  BACKFILL="grok"
fi
[ -n "$BACKFILL" ] || BACKFILL="$NATIVE"

# 目標に満たない分を補完（distinct が目標超なら触らない＝SKILL が優先順位でトリム）
TARGET="${QUORUM_PANEL_SIZE:-3}"
while [ "${#panel[@]}" -lt "$TARGET" ]; do
  panel+=("$BACKFILL")
done

printf '%s\n' "${panel[@]}"
