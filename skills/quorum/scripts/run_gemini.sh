#!/usr/bin/env bash
# Gemini パネリスト（Google gemini CLI 経由）。
# プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 認証: gemini に Google アカウントでログイン済みなら無料枠/サブスクで動く。
#       APIキー（GEMINI_API_KEY）でも可（AI Studio に無料枠あり）。
# 検証: gemini-cli 0.46.0 で -p（非対話）を確認。要 Google ログイン or GEMINI_API_KEY。
# モデルは GEMINI_MODEL で上書き可（無料/有料で“同じモデル”を指定すれば精度は同じ）。
set -euo pipefail

# 可用性の自己申告。gemini は既定で除外、QUORUM_ENABLE_GEMINI=1 の時だけ有効。
if [ "${1:-}" = "--check" ]; then
  [ -n "${QUORUM_ENABLE_GEMINI:-}" ] && command -v gemini >/dev/null 2>&1 && exit 0 || exit 1
fi

MODEL="${GEMINI_MODEL:-gemini-2.5-pro}"
PROMPT="$(cat)"

if ! command -v gemini >/dev/null 2>&1; then
  echo "[run_gemini] gemini CLI が見つかりません" >&2
  exit 127
fi

# コスト/時間ガード: QUORUM_TIMEOUT 秒で打ち切り（timeout が無ければ無制限）
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout ${QUORUM_TIMEOUT:-300}"

# -p: 非対話（headless）で最終回答を stdout に出力 / -m: モデル明示
$TO gemini -m "$MODEL" -p "$PROMPT"
