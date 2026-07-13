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
t "UIメタデータを配置" "$(grep -q 'default_prompt.*\$quorum' "$CODEX/skills/quorum/agents/openai.yaml"; echo $?)"
t "IMPROVEMENTS.mdは正本へのsymlink" "$([ "$(readlink "$CODEX/skills/quorum/IMPROVEMENTS.md")" = "$REPO/IMPROVEMENTS.md" ]; echo $?)"
t "CodexルールがT1をquorumへ接続" "$(grep -q 'T1.*\$quorum' "$CODEX/AGENTS.md"; echo $?)"
t "既存AGENTS.md記述を保持" "$(grep -q '保持する行' "$CODEX/AGENTS.md"; echo $?)"
t "beginマーカーは1つ" "$([ "$(grep -c 'quorum-triage:begin' "$CODEX/AGENTS.md")" = "1" ]; echo $?)"

CLAUDE_CONFIG_DIR="$CLAUDE" CODEX_HOME="$CODEX" BIN_DIR="$BIN" bash "$REPO/install.sh" >/dev/null 2>&1
t "再インストールでマーカーが増殖しない" "$([ "$(grep -c 'quorum-triage:begin' "$CODEX/AGENTS.md")" = "1" ]; echo $?)"
t "再インストール後もユーザー記述を保持" "$(grep -q '保持する行' "$CODEX/AGENTS.md"; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
