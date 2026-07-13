#!/usr/bin/env bash
# Claude Opus パネリスト（Claude Code CLI 経由、Codexホスト専用の外部枠）。
# プロンプトを stdin で受け取り、最終回答を stdout に出力する。
#
# 認証: Claude.ai の Pro/Max 等でログイン済みならプラン利用枠を使う。
#       ANTHROPIC_API_KEY があるとAPI従量になり得るため、既定では拒否する。
#       意図してAPIを使う場合だけ QUORUM_ALLOW_CLAUDE_API=1 を指定する。
# 隔離: --safe-mode + --tools "" + --no-session-persistence + 空CWD により、
#       CLAUDE.md / skills / hooks / MCP / ワークスペースを読ませず再帰を防ぐ。
# 検証: Claude Code 2.1.207、Claude.ai認証、stdin→text経路を2026-07-13にE2E確認済み。
set -euo pipefail

enabled() {
  case "${QUORUM_ENABLE_CLAUDE-1}" in
    ''|0|false|no) return 1 ;;
    *) return 0 ;;
  esac
}

api_allowed() {
  [ -z "${ANTHROPIC_API_KEY:-}" ] && return 0
  case "${QUORUM_ALLOW_CLAUDE_API:-}" in
    1|true|yes) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "${1:-}" = "--check" ]; then
  enabled || exit 1
  command -v claude >/dev/null 2>&1 || exit 1
  api_allowed || exit 1
  # 旧CLIを誤って使い、ユーザー設定を再読込しないよう隔離フラグの存在も確認する。
  HELP="$(claude --help 2>&1)" || exit 1
  printf '%s' "$HELP" | grep -q -- '--safe-mode' || exit 1
  printf '%s' "$HELP" | grep -q -- '--no-session-persistence' || exit 1
  exit 0
fi

PROMPT="$(cat)"

enabled || { echo "[run_claude] QUORUM_ENABLE_CLAUDE で無効化されています" >&2; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "[run_claude] claude CLI が見つかりません" >&2; exit 127; }
api_allowed || {
  echo "[run_claude] ANTHROPIC_API_KEY を検出しました。API従量を意図する場合だけ QUORUM_ALLOW_CLAUDE_API=1 を指定してください" >&2
  exit 1
}

MODEL="${CLAUDE_MODEL:-opus}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

TIMEOUT_CMD=()
command -v timeout >/dev/null 2>&1 && TIMEOUT_CMD=(timeout "${QUORUM_TIMEOUT:-300}")

printf '%s' "$PROMPT" | "${TIMEOUT_CMD[@]}" claude -p \
  --safe-mode \
  --no-session-persistence \
  --model "$MODEL" \
  --tools "" \
  --output-format text
