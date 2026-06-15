#!/usr/bin/env bash
# fusion-forge をローカルの Claude Code 設定に配置する。
#   skills/fusion -> $CLAUDE_CONFIG_DIR/skills/fusion
#   commands/*    -> $CLAUDE_CONFIG_DIR/commands/
# 配置先を変えたい場合: CLAUDE_CONFIG_DIR=/path/.claude ./install.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_CONFIG_DIR/commands"

# スクリプトに実行権限を付与
chmod +x "$SRC_DIR"/skills/fusion/scripts/*.sh

# スキル本体をコピー
rm -rf "$CLAUDE_CONFIG_DIR/skills/fusion"
cp -R "$SRC_DIR/skills/fusion" "$CLAUDE_CONFIG_DIR/skills/fusion"

# スラッシュコマンドをコピー
cp "$SRC_DIR"/commands/*.md "$CLAUDE_CONFIG_DIR/commands/"

echo "✓ インストール完了: $CLAUDE_CONFIG_DIR"
echo "  - skills/fusion"
echo "  - commands/fusion.md, commands/fusion-opus.md"
echo ""
echo "Claude Code を再起動するか /reload-skills を実行してください。"
