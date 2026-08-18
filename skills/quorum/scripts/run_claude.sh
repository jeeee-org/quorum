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
  # 既定オフ（opt-in）。Codexホストで外部Claudeをパネルに入れるPCだけ QUORUM_ENABLE_CLAUDE=1 にする。
  case "${QUORUM_ENABLE_CLAUDE:-}" in
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

# --check の exit code 規約: 0=可用 / 2=意図的に不参加 / その他非0=参加したいのに使えない
# APIキー検出による拒否は「意図的に不参加」（課金ガードが効いた状態）なので 2 を返す。
if [ "${1:-}" = "--check" ]; then
  # 「意図的に参加しない」判定（exit 2）を先に済ませる。CLI の有無より前に置くのは、
  # 課金ガードが効いている状態を「CLI が壊れている」と誤って連続欠席に数えさせないため。
  enabled || exit 2
  api_allowed || exit 2
  command -v claude >/dev/null 2>&1 || exit 1
  # 旧CLIを誤って使い、ユーザー設定を再読込しないよう隔離フラグの存在も確認する。
  HELP="$(claude --help 2>&1)" || exit 1
  printf '%s' "$HELP" | grep -q -- '--safe-mode' || exit 1
  printf '%s' "$HELP" | grep -q -- '--no-session-persistence' || exit 1
  exit 0
fi

# バックエンド CLI の版を1行で申告する（規約: run_<name>.sh --version）。detect_panel.sh が
# 記録し、前回から変わっていたら警告する（IMPROVEMENTS 2026-08-15）。
if [ "${1:-}" = "--version" ]; then
  command -v claude >/dev/null 2>&1 || { echo "unavailable"; exit 0; }
  claude --version 2>/dev/null | head -n 1 || echo "unknown"
  exit 0
fi

PROMPT="$(cat)"

# パネリスト専用ガードを固定前置する（再帰 fan-out・collab 呼び出し・メタ応答の系統的
# failure mode への全外部 run_*.sh 共通施策。正本: panelist_guard.txt）。
GUARD_FILE="$(cd "$(dirname "$0")" && pwd)/panelist_guard.txt"
if [ -f "$GUARD_FILE" ]; then
  PROMPT="$(cat "$GUARD_FILE")

$PROMPT"
fi

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
