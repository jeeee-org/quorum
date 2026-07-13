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
#   QUORUM_PANEL_SIZE       目標パネル数（既定 4）。distinct な利用可能バックエンドがこれに満たない
#                           分をネイティブ実行で補完。distinct がこれを超える場合は全部出力し、トリムは
#                           SKILL 側の優先順位判断（ドメイン適合 > 多様性 > 同系追加）に委ねる。
#   QUORUM_ENABLE_CODEX=1   codex を候補に含める（既定は除外。run_codex.sh 側のオプトイン）。
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
  claude) NATIVE="opus" ;;
  codex) NATIVE="codex-native" ;;
  *) echo "QUORUM_HOST は claude または codex を指定してください: $HOST" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# 目標に満たない分を独立 native 実行で補完（distinct が目標超なら触らない＝SKILL が優先順位でトリム）
TARGET="${QUORUM_PANEL_SIZE:-4}"
while [ "${#panel[@]}" -lt "$TARGET" ]; do
  panel+=("$NATIVE")
done

printf '%s\n' "${panel[@]}"
