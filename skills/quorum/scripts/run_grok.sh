#!/usr/bin/env bash
# Grok パネリスト。プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 2方式に対応（CLI を優先）:
#   1) Grok Build CLI（`grok`）= SuperGrok / X Premium+ のサブスク枠（OAuth ログイン、従量課金なし）
#      事前に `grok login` で一度サインインしておくこと。
#   2) xAI API（`XAI_API_KEY`）= 従量課金。CLI が無い時のフォールバック。
#
# 学習オフ: grok.com の Settings > Data で「Improve the model」をオフにする（アカウント単位）。
# 検証: grok-cli 0.2.51（-p / --single）。
# ⚠️ CLI 経路はプロンプトを argv（-p）で渡すため、実行中は ps で全文が見える（grok CLI は
#    stdin 渡し未対応）。機密は context-packing の段階でマスク済みであること。API 経路は
#    キー・本文とも argv に載せない（curl config / 一時ファイル経由）。
set -euo pipefail

# 標準のインストール先を PATH に追加（Claude Code の非ログインシェル対策）
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"

# 可用性の自己申告: grok CLI があるか、または XAI_API_KEY+curl があれば可用。
if [ "${1:-}" = "--check" ]; then
  command -v grok >/dev/null 2>&1 && exit 0
  { [ -n "${XAI_API_KEY:-}" ] && command -v curl >/dev/null 2>&1; } && exit 0
  exit 1
fi

MODEL="${GROK_MODEL:-}"
PROMPT="$(cat)"

# コスト/時間ガード: QUORUM_TIMEOUT 秒で打ち切り（timeout が無ければ無制限）
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout ${QUORUM_TIMEOUT:-300}"

# --- 方式1: Grok Build CLI（サブスク枠） ---
if command -v grok >/dev/null 2>&1; then
  if [ -n "$MODEL" ]; then
    $TO grok -p "$PROMPT" -m "$MODEL"
  else
    $TO grok -p "$PROMPT"
  fi
  exit $?
fi

# --- 方式2: xAI API（従量課金フォールバック） ---
API_MODEL="${GROK_MODEL:-grok-4}"
: "${XAI_API_KEY:?grok CLI も XAI_API_KEY も無し（どちらかが必要）}"
command -v curl    >/dev/null 2>&1 || { echo "[run_grok] curl が必要です" >&2; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo "[run_grok] python3 が必要です" >&2; exit 127; }

# 機密を argv に載せない（実行中の ps で見えるため）: キーは curl config、本文は一時ファイル経由
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

PROMPT="$PROMPT" MODEL="$API_MODEL" python3 - >"$TMPD/payload.json" <<'PY'
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "messages": [{"role": "user", "content": os.environ["PROMPT"]}],
    # "search_parameters": {"mode": "auto"},  # Live Search を使うならコメント解除
}))
PY
printf 'header = "Authorization: Bearer %s"\n' "$XAI_API_KEY" > "$TMPD/curl.cfg"

$TO curl -sS --config "$TMPD/curl.cfg" \
  -H "Content-Type: application/json" \
  -d @"$TMPD/payload.json" \
  https://api.x.ai/v1/chat/completions \
| python3 -c 'import sys, json; print(json.load(sys.stdin)["choices"][0]["message"]["content"])'
