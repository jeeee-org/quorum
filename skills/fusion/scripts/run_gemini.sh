#!/usr/bin/env bash
# Gemini パネリスト（Google gemini CLI 経由）。
# プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 認証: gemini に Google アカウントでログイン済みなら無料枠/サブスクで動く。
#       APIキー（GEMINI_API_KEY）でも可（AI Studio に無料枠あり）。
# 検証: gemini-cli 0.46.0 で -p（非対話）を確認。要 Google ログイン or GEMINI_API_KEY。
# モデルは GEMINI_MODEL で上書き可（無料/有料で“同じモデル”を指定すれば精度は同じ）。
set -euo pipefail

MODEL="${GEMINI_MODEL:-gemini-2.5-pro}"
PROMPT="$(cat)"

if ! command -v gemini >/dev/null 2>&1; then
  echo "[run_gemini] gemini CLI が見つかりません" >&2
  exit 127
fi

# -p: 非対話（headless）で最終回答を stdout に出力 / -m: モデル明示
gemini -m "$MODEL" -p "$PROMPT"
