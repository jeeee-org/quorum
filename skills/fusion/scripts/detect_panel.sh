#!/usr/bin/env bash
# 利用可能なパネリスト・バックエンドを1行ずつ出力する（汎用ディスカバリ）。
#
# 規約: scripts/ 配下の `run_<name>.sh` が1パネリスト・バックエンド。
#   - `run_<name>.sh --check` … 使えるなら exit 0、使えないなら非0
#   - `run_<name>.sh`（引数なし）… プロンプトを stdin で受け、回答を stdout へ
# 新しいモデルを足したい時は、この規約に従う run_<name>.sh を置くだけでよい
# （detect_panel.sh も SKILL.md も編集不要）。
#
# opus は Claude Code 内で常に利用可能（スクリプトではなく Task で spawn）。
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"

echo opus

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
for s in "$SCRIPT_DIR"/run_*.sh; do
  [ -e "$s" ] || continue
  name="$(basename "$s")"; name="${name#run_}"; name="${name%.sh}"
  if bash "$s" --check >/dev/null 2>&1; then
    echo "$name"
  fi
done
