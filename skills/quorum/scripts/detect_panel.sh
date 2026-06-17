#!/usr/bin/env bash
# 利用可能なバックエンドを検出し、目標パネルサイズに合わせて独立 opus で補完したパネルを出力する。
#
# 規約: scripts/ 配下の `run_<name>.sh` が1バックエンド。
#   - `run_<name>.sh --check` … 使えるなら exit 0、使えないなら非0
#   - `run_<name>.sh`（引数なし）… プロンプトを stdin で受け、回答を stdout へ
# 新しいモデルを足したい時は、この規約に従う run_<name>.sh を置くだけでよい。
# opus は Claude Code 内で常に利用可能（スクリプトではなく Task で spawn）。
#
# 出力: パネリストを1行ずつ（**multiset**。同じ名前が複数行 = その回数だけ独立実行する）。
#   理想パネルは grok / opus / codex / gemini の4枠。**使えない枠は独立 opus 実行で補完**する
#   （同一モデルの複数独立実行でも、統合すれば単発を上回る＝panel.md）。
#
# 環境変数:
#   QUORUM_PANEL_SIZE       目標パネル数（既定 4）。distinct な利用可能バックエンドがこれに満たない
#                           分を opus で補完。distinct がこれを超える場合は全部出力し、トリムは
#                           SKILL 側の優先順位判断（ドメイン適合 > 多様性 > 同系追加）に委ねる。
#   QUORUM_ENABLE_GEMINI=1  gemini を候補に含める（既定は除外。run_gemini.sh 側のオプトイン）。
# フラグ:
#   --raw  補完せず「利用可能な distinct バックエンド」だけを出力（デバッグ/テスト用）。
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"

RAW=0
[ "${1:-}" = "--raw" ] && RAW=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --check を通った distinct な外部バックエンド
externals=()
for s in "$SCRIPT_DIR"/run_*.sh; do
  [ -e "$s" ] || continue
  name="$(basename "$s")"; name="${name#run_}"; name="${name%.sh}"
  if bash "$s" --check >/dev/null 2>&1; then
    externals+=("$name")
  fi
done

# distinct な利用可能パネル = opus + externals
panel=(opus)
if [ "${#externals[@]}" -gt 0 ]; then
  panel+=("${externals[@]}")
fi

if [ "$RAW" = "1" ]; then
  printf '%s\n' "${panel[@]}"
  exit 0
fi

# 目標に満たない分を独立 opus で補完（distinct が目標超なら触らない＝SKILL が優先順位でトリム）
TARGET="${QUORUM_PANEL_SIZE:-4}"
while [ "${#panel[@]}" -lt "$TARGET" ]; do
  panel+=("opus")
done

printf '%s\n' "${panel[@]}"
