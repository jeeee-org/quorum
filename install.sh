#!/usr/bin/env bash
# fusion-forge をローカルの Claude Code 設定に配置する。
#   skills/fusion -> $CLAUDE_CONFIG_DIR/skills/fusion
#   commands/*    -> $CLAUDE_CONFIG_DIR/commands/
#   bin/fusion-shell -> $BIN_DIR/fusion-shell（ランチャー）
# 配置先を変えたい場合: CLAUDE_CONFIG_DIR=/path/.claude BIN_DIR=/path/bin ./install.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_CONFIG_DIR/commands" "$BIN_DIR"

# スクリプトに実行権限を付与
chmod +x "$SRC_DIR"/skills/fusion/scripts/*.sh "$SRC_DIR"/bin/fusion-shell

# スキル本体をコピー
rm -rf "$CLAUDE_CONFIG_DIR/skills/fusion"
cp -R "$SRC_DIR/skills/fusion" "$CLAUDE_CONFIG_DIR/skills/fusion"

# スラッシュコマンドをコピー
cp "$SRC_DIR"/commands/*.md "$CLAUDE_CONFIG_DIR/commands/"

# ランチャーを symlink（リポジトリ更新が即反映される）
ln -sf "$SRC_DIR/bin/fusion-shell" "$BIN_DIR/fusion-shell"

echo "✓ インストール完了: $CLAUDE_CONFIG_DIR"
echo "  - skills/fusion"
echo "  - commands/fusion.md, commands/fusion-opus.md"
echo "  - $BIN_DIR/fusion-shell（ランチャー）"
echo ""
echo "Claude Code を再起動するか /reload-skills を実行してください。"
case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) echo "※ $BIN_DIR が PATH に無いようです。追加してください。" ;; esac
