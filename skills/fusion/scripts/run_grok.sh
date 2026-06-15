#!/usr/bin/env bash
# Grok パネリスト（xAI API 経由・OpenAI 互換エンドポイント）。
# プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 認証: xAI API キー（XAI_API_KEY）が必須。=> 従量課金（消費者サブスクは不可）。
# 依存: curl, python3。
# TODO(build): 最新のモデル名を確認して GROK_MODEL の既定値を更新する。
#              Live Search（Web/X 検索）を使うなら search_parameters を有効化する。
set -euo pipefail

MODEL="${GROK_MODEL:-grok-4}"
PROMPT="$(cat)"

: "${XAI_API_KEY:?XAI_API_KEY が設定されていません}"
command -v curl    >/dev/null 2>&1 || { echo "[run_grok] curl が必要です" >&2; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo "[run_grok] python3 が必要です" >&2; exit 127; }

PAYLOAD="$(PROMPT="$PROMPT" MODEL="$MODEL" python3 - <<'PY'
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
