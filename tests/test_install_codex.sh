#!/usr/bin/env bash
# install.sh のCodex版スキル配置と AGENTS.md マーカー更新を一時ディレクトリで検証する。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLAUDE="$TMP/claude"; CODEX="$TMP/codex"; BIN="$TMP/bin"
mkdir -p "$CODEX"
printf '# 既存のCodexルール\n\n- 保持する行\n' > "$CODEX/AGENTS.md"

CLAUDE_CONFIG_DIR="$CLAUDE" CODEX_HOME="$CODEX" BIN_DIR="$BIN" bash "$REPO/install.sh" >/dev/null 2>&1
t "Codex版SKILL.mdを配置" "$(grep -q 'codex-native' "$CODEX/skills/quorum/SKILL.md"; echo $?)"
t "Claude固有のSKILL.mdではない" "$(! grep -q 'model.*opus' "$CODEX/skills/quorum/SKILL.md"; echo $?)"
t "共有referencesを配置" "$([ -f "$CODEX/skills/quorum/references/judge_rubric.md" ]; echo $?)"
t "共有scriptsを配置" "$([ -x "$CODEX/skills/quorum/scripts/detect_panel.sh" ]; echo $?)"
t "外部Claude runnerを配置" "$([ -x "$CODEX/skills/quorum/scripts/run_claude.sh" ]; echo $?)"
t "UIメタデータを配置" "$(grep -q 'default_prompt.*\$quorum' "$CODEX/skills/quorum/agents/openai.yaml"; echo $?)"
t "IMPROVEMENTS.mdは正本へのsymlink" "$([ "$(readlink "$CODEX/skills/quorum/IMPROVEMENTS.md")" = "$REPO/IMPROVEMENTS.md" ]; echo $?)"
t "CodexルールがT1をquorumへ接続" "$(grep -q 'T1.*\$quorum' "$CODEX/AGENTS.md"; echo $?)"
t "既存AGENTS.md記述を保持" "$(grep -q '保持する行' "$CODEX/AGENTS.md"; echo $?)"
t "beginマーカーは1つ" "$([ "$(grep -c 'quorum-triage:begin' "$CODEX/AGENTS.md")" = "1" ]; echo $?)"

CLAUDE_CONFIG_DIR="$CLAUDE" CODEX_HOME="$CODEX" BIN_DIR="$BIN" bash "$REPO/install.sh" >/dev/null 2>&1
t "再インストールでマーカーが増殖しない" "$([ "$(grep -c 'quorum-triage:begin' "$CODEX/AGENTS.md")" = "1" ]; echo $?)"
t "再インストール後もユーザー記述を保持" "$(grep -q '保持する行' "$CODEX/AGENTS.md"; echo $?)"

# --- Codex版の配置を省ける（IMPROVEMENTS 2026-08-15） ---
# パネリストとしての codex CLI と、メインエージェントとしての Codex は別物。前者だけ使うPCで
# 後者の配置を止める口が無く、呼び出し側が後から消す羽目になっていた。
for mode in env flag; do
  C2="$TMP/skip_$mode"; mkdir -p "$C2/codex"
  printf '# 既存\n' > "$C2/codex/AGENTS.md"
  if [ "$mode" = "env" ]; then
    QUORUM_INSTALL_CODEX=0 CLAUDE_CONFIG_DIR="$C2/claude" CODEX_HOME="$C2/codex" BIN_DIR="$C2/bin" \
      bash "$REPO/install.sh" >/dev/null 2>&1
  else
    CLAUDE_CONFIG_DIR="$C2/claude" CODEX_HOME="$C2/codex" BIN_DIR="$C2/bin" \
      bash "$REPO/install.sh" --no-codex >/dev/null 2>&1
  fi
  t "[$mode] Codex版スキルを配置しない" "$([ ! -e "$C2/codex/skills/quorum" ]; echo $?)"
  t "[$mode] AGENTS.md にトリアージブロックを足さない" \
    "$(! grep -q 'quorum-triage:begin' "$C2/codex/AGENTS.md"; echo $?)"
  t "[$mode] AGENTS.md の既存記述に触らない" "$(grep -q '既存' "$C2/codex/AGENTS.md"; echo $?)"
  t "[$mode] Claude側は通常どおり配置する" "$([ -f "$C2/claude/skills/quorum/SKILL.md" ]; echo $?)"
  t "[$mode] コマンドも通常どおり配置する" "$([ -f "$C2/claude/commands/quorum.md" ]; echo $?)"
done

# 既存の配置は自動削除せず、残っていることを知らせる（env 1つでユーザーのファイルを削らない）
C3="$TMP/skip_existing"; mkdir -p "$C3/codex/skills/quorum"
printf 'stale\n' > "$C3/codex/skills/quorum/SKILL.md"
err="$(QUORUM_INSTALL_CODEX=0 CLAUDE_CONFIG_DIR="$C3/claude" CODEX_HOME="$C3/codex" BIN_DIR="$C3/bin" \
  bash "$REPO/install.sh" 2>&1 >/dev/null)"
t "スキップ時も既存のCodex配置を自動削除しない" "$([ -f "$C3/codex/skills/quorum/SKILL.md" ]; echo $?)"
t "残存を知らせ、消し方を示す" "$(printf '%s' "$err" | grep -q 'rm -rf'; echo $?)"

# 不明な引数は弾く
CLAUDE_CONFIG_DIR="$TMP/bad/claude" CODEX_HOME="$TMP/bad/codex" BIN_DIR="$TMP/bad/bin" \
  bash "$REPO/install.sh" --nope >/dev/null 2>&1
t "不明な引数は exit 2" "$([ "$?" = "2" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
