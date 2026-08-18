#!/usr/bin/env bash
# quorum をローカルの Claude Code / Codex 設定に配置する。
#   skills/quorum -> $CLAUDE_CONFIG_DIR/skills/quorum
#   skills/quorum + Codex差分 -> $CODEX_HOME/skills/quorum
#   commands/*    -> $CLAUDE_CONFIG_DIR/commands/
#   bin/quorum-shell -> $BIN_DIR/quorum-shell（ランチャー）
# 配置先を変えたい場合: CLAUDE_CONFIG_DIR=/path/.claude CODEX_HOME=/path/.codex BIN_DIR=/path/bin ./install.sh
#
# Codex版の配置を丸ごと省く: QUORUM_INSTALL_CODEX=0 ./install.sh（または --no-codex）
#   **パネリストとしての codex CLI**（QUORUM_ENABLE_CODEX=1 / run_codex.sh 経由）と
#   **メインエージェントとしての Codex**（~/.codex/skills/quorum・AGENTS.md のトリアージ）は別物。
#   前者だけ使うPCでは後者が不要なのに、配置を止める口が無く、呼び出し側が後から消す羽目になった
#   （IMPROVEMENTS 2026-08-15）。既定は現状どおり配置する。
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

INSTALL_CODEX="${QUORUM_INSTALL_CODEX:-1}"
for arg in "$@"; do
  case "$arg" in
    --no-codex) INSTALL_CODEX=0 ;;
    *) echo "不明な引数: $arg（使えるのは --no-codex）" >&2; exit 2 ;;
  esac
done
case "$INSTALL_CODEX" in
  0|false|no|'') INSTALL_CODEX=0 ;;
  *) INSTALL_CODEX=1 ;;
esac

mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_CONFIG_DIR/commands" "$BIN_DIR"
if [ "$INSTALL_CODEX" = "1" ]; then
  mkdir -p "$CODEX_HOME/skills"
fi

# スクリプトに実行権限を付与
chmod +x "$SRC_DIR"/skills/quorum/scripts/*.sh "$SRC_DIR"/bin/quorum-shell

# スキル本体をコピー
rm -rf "$CLAUDE_CONFIG_DIR/skills/quorum"
cp -R "$SRC_DIR/skills/quorum" "$CLAUDE_CONFIG_DIR/skills/quorum"

# IMPROVEMENTS.md はリポ root（$SRC_DIR/IMPROVEMENTS.md）を正本にし、install 先は symlink。
# 実行時の追記が git 管理下のリポ側へ書き込まれ、再インストールの rm -rf でも消えない。
ln -sfn "$SRC_DIR/IMPROVEMENTS.md" "$CLAUDE_CONFIG_DIR/skills/quorum/IMPROVEMENTS.md"

# Codex版は共有 scripts/references をコピーし、ホスト固有の SKILL.md / agents を上書きする。
if [ "$INSTALL_CODEX" = "1" ]; then
  rm -rf "$CODEX_HOME/skills/quorum"
  cp -R "$SRC_DIR/skills/quorum" "$CODEX_HOME/skills/quorum"
  cp "$SRC_DIR/skills/codex-quorum/SKILL.md" "$CODEX_HOME/skills/quorum/SKILL.md"
  rm -rf "$CODEX_HOME/skills/quorum/agents"
  cp -R "$SRC_DIR/skills/codex-quorum/agents" "$CODEX_HOME/skills/quorum/agents"
  ln -sfn "$SRC_DIR/IMPROVEMENTS.md" "$CODEX_HOME/skills/quorum/IMPROVEMENTS.md"
fi

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

# Codexグローバル AGENTS.md には分類を複製せず、claude-rules の T1 と $quorum の接続だけを置く。
CODEX_GLOBAL_MD="$CODEX_HOME/AGENTS.md"
CODEX_MARK_BEGIN='<!-- quorum-triage:begin (quorum/install.sh Codex版が管理。手動編集しない — 変更はリポの rules/codex-quorum-triage.md へ) -->'
CODEX_MARK_END='<!-- quorum-triage:end -->'
if [ "$INSTALL_CODEX" = "1" ]; then
  CODEX_RULE_SRC="$SRC_DIR/rules/codex-quorum-triage.md"
  touch "$CODEX_GLOBAL_MD"
  if grep -qF -- "$CODEX_MARK_BEGIN" "$CODEX_GLOBAL_MD"; then
    awk -v begin="$CODEX_MARK_BEGIN" -v end="$CODEX_MARK_END" -v rulefile="$CODEX_RULE_SRC" '
      $0 == begin { print; while ((getline line < rulefile) > 0) print line; close(rulefile); skip = 1; next }
      $0 == end   { skip = 0; print; next }
      !skip       { print }
    ' "$CODEX_GLOBAL_MD" > "$CODEX_GLOBAL_MD.tmp" && mv "$CODEX_GLOBAL_MD.tmp" "$CODEX_GLOBAL_MD"
  else
    { [ -s "$CODEX_GLOBAL_MD" ] && echo ""; echo "$CODEX_MARK_BEGIN"; cat "$CODEX_RULE_SRC"; echo "$CODEX_MARK_END"; } >> "$CODEX_GLOBAL_MD"
  fi
else
  # 既存の配置は**自動で消さない**（env 1つでユーザーのファイルを削るのは危険）。
  # 残っていることと、消す手順だけを知らせる。
  if [ -e "$CODEX_HOME/skills/quorum" ]; then
    echo "※ Codex版はスキップしました。前回の配置が残っています: $CODEX_HOME/skills/quorum" >&2
    echo "   不要なら: rm -rf \"$CODEX_HOME/skills/quorum\"" >&2
  fi
  if [ -f "$CODEX_GLOBAL_MD" ] && grep -qF -- "$CODEX_MARK_BEGIN" "$CODEX_GLOBAL_MD"; then
    echo "※ $CODEX_GLOBAL_MD に quorum-triage ブロックが残っています（マーカー間を手で削除してください）" >&2
  fi
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

# グローバル指示の常時ロード上限を目安チェック（超過してもインストールは継続）。
global_docs=("$GLOBAL_MD")
if [ "$INSTALL_CODEX" = "1" ]; then
  global_docs+=("$CODEX_GLOBAL_MD")
fi
for global_doc in "${global_docs[@]}"; do
  [ -f "$global_doc" ] || continue
  global_size=$(wc -c < "$global_doc")
  if [ "$global_size" -gt 14336 ]; then
    echo "⚠ $global_doc が14KBを超過（${global_size} bytes）。ルール圧縮を検討してください。" >&2
  fi
done

echo "✓ インストール完了: $CLAUDE_CONFIG_DIR"
echo "  - skills/quorum"
echo "  - skills/quorum/IMPROVEMENTS.md -> $SRC_DIR/IMPROVEMENTS.md (symlink)"
if [ "$INSTALL_CODEX" = "1" ]; then
  echo "  - $CODEX_HOME/skills/quorum（Codex版）"
  echo "  - $CODEX_HOME/skills/quorum/IMPROVEMENTS.md -> $SRC_DIR/IMPROVEMENTS.md (symlink)"
fi
echo "  - commands/quorum.md, commands/quorum-opus.md"
echo "  - $BIN_DIR/quorum-shell（ランチャー）"
echo "  - CLAUDE.md の quorum-triage ブロック（常時トリアージ規則）"
if [ "$INSTALL_CODEX" = "1" ]; then
  echo "  - $CODEX_GLOBAL_MD の quorum-triage ブロック（T1 → \$quorum 連携）"
else
  echo "  - Codex版はスキップ（QUORUM_INSTALL_CODEX=0 / --no-codex）"
  echo "    ※ パネリストとしての codex CLI は QUORUM_ENABLE_CODEX=1 で従来どおり使えます"
fi
echo "  - settings.json の env マージ（rules/settings-env.json の未設定キーのみ）"
echo ""
echo "Claude Code を再起動するか /reload-skills を実行してください。Codexで反映されない場合は再起動してください。"
case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) echo "※ $BIN_DIR が PATH に無いようです。追加してください。" ;; esac
