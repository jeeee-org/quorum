#!/usr/bin/env bash
# install.sh のグローバル CLAUDE.md マーカー挿入の冪等性テスト。
# temp の CLAUDE_CONFIG_DIR / BIN_DIR に対して実行するので実環境には触れない。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/claude"; BIN="$TMP/bin"

# 既存のユーザー記述がある CLAUDE.md を用意
mkdir -p "$CFG"
printf '# 既存のユーザールール\n\n- 触ってはいけない行\n' > "$CFG/CLAUDE.md"

# 1回目のインストール
CLAUDE_CONFIG_DIR="$CFG" BIN_DIR="$BIN" bash "$REPO/install.sh" >/dev/null 2>&1
t "1回目: begin マーカーが1つ" "$([ "$(grep -c 'quorum-triage:begin' "$CFG/CLAUDE.md")" = "1" ]; echo $?)"
t "1回目: 規則本文が入っている" "$(grep -q 'T2b' "$CFG/CLAUDE.md"; echo $?)"
t "1回目: 既存のユーザー記述が残っている" "$(grep -q '触ってはいけない行' "$CFG/CLAUDE.md"; echo $?)"

# 2回目（冪等性: ブロックが増殖しない）
CLAUDE_CONFIG_DIR="$CFG" BIN_DIR="$BIN" bash "$REPO/install.sh" >/dev/null 2>&1
t "2回目: begin マーカーは1つのまま" "$([ "$(grep -c 'quorum-triage:begin' "$CFG/CLAUDE.md")" = "1" ]; echo $?)"

# 規則ファイルの変更が反映される（rules を一時的に差し替えるのではなく、
# コピーしたリポで検証する）
REPO2="$TMP/repo2"
cp -R "$REPO" "$REPO2"
printf '\n<!-- テスト用の追記マーカー xyz123 -->\n' >> "$REPO2/rules/quorum-triage.md"
CLAUDE_CONFIG_DIR="$CFG" BIN_DIR="$BIN" bash "$REPO2/install.sh" >/dev/null 2>&1
t "3回目: 規則の更新が反映される" "$(grep -q 'xyz123' "$CFG/CLAUDE.md"; echo $?)"
t "3回目: begin マーカーは1つのまま" "$([ "$(grep -c 'quorum-triage:begin' "$CFG/CLAUDE.md")" = "1" ]; echo $?)"
t "3回目: ユーザー記述は無傷" "$(grep -q '触ってはいけない行' "$CFG/CLAUDE.md"; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
