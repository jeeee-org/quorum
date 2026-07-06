#!/usr/bin/env bash
# install.sh の settings.json env マージのテスト（temp ディレクトリ・実環境に触れない）。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

jget() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d$2)" "$1" 2>/dev/null; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1) settings.json が無い → 作成され env が入る
CFG1="$TMP/cfg1"; mkdir -p "$CFG1"
CLAUDE_CONFIG_DIR="$CFG1" BIN_DIR="$TMP/bin" bash "$REPO/install.sh" >/dev/null 2>&1
t "settings.json 新規作成で env が入る" "$([ "$(jget "$CFG1/settings.json" '["env"]["QUORUM_ENABLE_CODEX"]')" = "1" ]; echo $?)"

# 2) 既存の設定キーが保持される
CFG2="$TMP/cfg2"; mkdir -p "$CFG2"
printf '{\n  "model": "opus",\n  "effortLevel": "high"\n}\n' > "$CFG2/settings.json"
CLAUDE_CONFIG_DIR="$CFG2" BIN_DIR="$TMP/bin" bash "$REPO/install.sh" >/dev/null 2>&1
t "既存キー model が保持される" "$([ "$(jget "$CFG2/settings.json" '["model"]')" = "opus" ]; echo $?)"
t "env が追加される" "$([ "$(jget "$CFG2/settings.json" '["env"]["QUORUM_ENABLE_CODEX"]')" = "1" ]; echo $?)"

# 3) ユーザーが明示した値（無効化の空文字）は上書きしない
CFG3="$TMP/cfg3"; mkdir -p "$CFG3"
printf '{\n  "env": { "QUORUM_ENABLE_CODEX": "" }\n}\n' > "$CFG3/settings.json"
CLAUDE_CONFIG_DIR="$CFG3" BIN_DIR="$TMP/bin" bash "$REPO/install.sh" >/dev/null 2>&1
t "既存の空文字（無効化）を上書きしない" "$([ "$(jget "$CFG3/settings.json" '["env"]["QUORUM_ENABLE_CODEX"]')" = "" ]; echo $?)"

# 4) 冪等性: 2回目で内容が変わらない
before="$(cat "$CFG1/settings.json")"
CLAUDE_CONFIG_DIR="$CFG1" BIN_DIR="$TMP/bin" bash "$REPO/install.sh" >/dev/null 2>&1
t "2回目で settings.json が変化しない" "$([ "$before" = "$(cat "$CFG1/settings.json")" ]; echo $?)"

# 5) 壊れた JSON は触らない（install 自体は成功する）
CFG5="$TMP/cfg5"; mkdir -p "$CFG5"
printf '{ broken json' > "$CFG5/settings.json"
CLAUDE_CONFIG_DIR="$CFG5" BIN_DIR="$TMP/bin" bash "$REPO/install.sh" >/dev/null 2>&1
rc=$?
t "壊れた JSON でも install は成功する" "$rc"
t "壊れた JSON は書き換えられていない" "$([ "$(cat "$CFG5/settings.json")" = "{ broken json" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
