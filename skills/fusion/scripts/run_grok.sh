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
set -euo pipefail

# 標準のインストール先を PATH に追加（Claude Code の非ログインシェル対策）
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"

MODEL="${GROK_MODEL:-}"
PROMPT="$(cat)"

# --- 方式1: Grok Build CLI（サブスク枠） ---
if command -v grok >/dev/null 2>&1; then
  if [ -n "$MODEL" ]; then
    grok -p "$PROMPT" -m "$MODEL"
  else
    grok -p "$PROMPT"
  fi
  exit $?
fi

# --- 方式2: xAI API（従量課金フォールバック） ---
API_MODEL="${GROK_MODEL:-grok-4}"
: "${XAI_API_KEY:?grok CLI も XAI_API_KEY も無し（どちらかが必要）}"
command -v curl    >/dev/null 2>&1 || { echo "[run_grok] curl が必要です" >&2; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo "[run_grok] python3 が必要です" >&2; exit 127; }

PAYLOAD="$(PROMPT="$PROMPT" MODEL="$API_MODEL" python3 - <<'PY'
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "messages": [{"role": "user", "content": os.environ["PROMPT"]}],
    # "search_parameters": {"mode": "auto"},  # Live Search を使うならコメント解除
}))
PY
)"

curl -sS https://api.x.ai/v1/chat/completions \
  -H "Authorization: Bearer ${XAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
| python3 -c 'import sys, json; print(json.load(sys.stdin)["choices"][0]["message"]["content"])'
