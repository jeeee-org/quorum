#!/usr/bin/env bash
# quorum をローカルの Claude Code 設定に配置する。
#   skills/quorum -> $CLAUDE_CONFIG_DIR/skills/quorum
#   commands/*    -> $CLAUDE_CONFIG_DIR/commands/
#   bin/quorum-shell -> $BIN_DIR/quorum-shell（ランチャー）
# 配置先を変えたい場合: CLAUDE_CONFIG_DIR=/path/.claude BIN_DIR=/path/bin ./install.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_CONFIG_DIR/commands" "$BIN_DIR"

# スクリプトに実行権限を付与
chmod +x "$SRC_DIR"/skills/quorum/scripts/*.sh "$SRC_DIR"/bin/quorum-shell

# スキル本体をコピー
rm -rf "$CLAUDE_CONFIG_DIR/skills/quorum"
cp -R "$SRC_DIR/skills/quorum" "$CLAUDE_CONFIG_DIR/skills/quorum"

# IMPROVEMENTS.md はリポ root（$SRC_DIR/IMPROVEMENTS.md）を正本にし、install 先は symlink。
# 実行時の追記が git 管理下のリポ側へ書き込まれ、再インストールの rm -rf でも消えない。
ln -sfn "$SRC_DIR/IMPROVEMENTS.md" "$CLAUDE_CONFIG_DIR/skills/quorum/IMPROVEMENTS.md"

# スラッシュコマンドをコピー
cp "$SRC_DIR"/commands/*.md "$CLAUDE_CONFIG_DIR/commands/"

# ランチャーを symlink（リポジトリ更新が即反映される）
ln -sf "$SRC_DIR/bin/quorum-shell" "$BIN_DIR/quorum-shell"

echo "✓ インストール完了: $CLAUDE_CONFIG_DIR"
echo "  - skills/quorum"
echo "  - skills/quorum/IMPROVEMENTS.md -> $SRC_DIR/IMPROVEMENTS.md (symlink)"
echo "  - commands/quorum.md, commands/quorum-opus.md"
echo "  - $BIN_DIR/quorum-shell（ランチャー）"
echo ""
echo "Claude Code を再起動するか /reload-skills を実行してください。"
case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) echo "※ $BIN_DIR が PATH に無いようです。追加してください。" ;; esac
