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

# グローバル CLAUDE.md にトリアージ規則ブロックを挿入/更新（マーカー間のみを置換・冪等）。
# ブロック外のユーザー記述には触れない。
GLOBAL_MD="$CLAUDE_CONFIG_DIR/CLAUDE.md"
RULE_SRC="$SRC_DIR/rules/quorum-triage.md"
MARK_BEGIN='<!-- quorum-triage:begin (quorum/install.sh が管理。手動編集しない — 変更はリポの rules/quorum-triage.md へ) -->'
MARK_END='<!-- quorum-triage:end -->'
touch "$GLOBAL_MD"
if grep -qF -- "$MARK_BEGIN" "$GLOBAL_MD"; then
  awk -v begin="$MARK_BEGIN" -v end="$MARK_END" -v rulefile="$RULE_SRC" '
    $0 == begin { print; while ((getline line < rulefile) > 0) print line; close(rulefile); skip = 1; next }
    $0 == end   { skip = 0; print; next }
    !skip       { print }
  ' "$GLOBAL_MD" > "$GLOBAL_MD.tmp" && mv "$GLOBAL_MD.tmp" "$GLOBAL_MD"
else
  { echo ""; echo "$MARK_BEGIN"; cat "$RULE_SRC"; echo "$MARK_END"; } >> "$GLOBAL_MD"
fi

# settings.json の env に既定の環境変数をマージ（正本: rules/settings-env.json）。
# **未設定のキーだけ**追加する——そのPCでユーザーが明示した値（無効化の空文字など）は上書きしない。
# settings.json が壊れた JSON の場合は触らず警告のみ（全設定を道連れにしない）。
SETTINGS_JSON="$CLAUDE_CONFIG_DIR/settings.json"
ENV_SRC="$SRC_DIR/rules/settings-env.json"
python3 - "$SETTINGS_JSON" "$ENV_SRC" <<'PY' || echo "⚠ settings.json への env マージをスキップしました（上の警告参照）" >&2
import json, os, sys

settings_path, env_path = sys.argv[1], sys.argv[2]
with open(env_path) as f:
    desired = json.load(f)

data = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        content = f.read().strip()
    if content:
        try:
            data = json.loads(content)
        except json.JSONDecodeError as e:
            print(f"⚠ {settings_path} が JSON として不正なため env マージを中止: {e}", file=sys.stderr)
            sys.exit(1)

env = data.setdefault("env", {})
changed = False
for key, value in desired.items():
    if key not in env:
        env[key] = value
        changed = True

if changed:
    with open(settings_path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
PY

echo "✓ インストール完了: $CLAUDE_CONFIG_DIR"
echo "  - skills/quorum"
echo "  - skills/quorum/IMPROVEMENTS.md -> $SRC_DIR/IMPROVEMENTS.md (symlink)"
echo "  - commands/quorum.md, commands/quorum-opus.md"
echo "  - $BIN_DIR/quorum-shell（ランチャー）"
echo "  - CLAUDE.md の quorum-triage ブロック（常時トリアージ規則）"
echo "  - settings.json の env マージ（rules/settings-env.json の未設定キーのみ）"
echo ""
echo "Claude Code を再起動するか /reload-skills を実行してください。"
case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) echo "※ $BIN_DIR が PATH に無いようです。追加してください。" ;; esac
