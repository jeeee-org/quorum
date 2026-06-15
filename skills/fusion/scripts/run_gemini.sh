#!/usr/bin/env bash
# Gemini パネリスト（Google gemini CLI 経由）。
# プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 認証: gemini に Google アカウントでログイン済みなら無料枠/サブスクで動く。
#       APIキー（GEMINI_API_KEY / Vertex）でも可だがその場合は従量課金。
# TODO(build): 非対話実行のフラグ・モデル指定を確認する
#              （例: `gemini -p "..."` / `-m <model>`。CLI バージョンで変わる）。
set -euo pipefail

PROMPT="$(cat)"

if ! command -v gemini >/dev/null 2>&1; then
  echo "[run_gemini] gemini CLI が見つかりません" >&2
  exit 127
fi

gemini -p "$PROMPT"
