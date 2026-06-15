#!/usr/bin/env bash
# GPT-5.5 パネリスト（OpenAI codex CLI 経由）。
# プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 認証: codex に ChatGPT アカウントでログイン済みならサブスク枠で動く。
#       APIキー（OPENAI_API_KEY）でも可だがその場合は従量課金。
# TODO(build): 非対話で「最終回答のみ」を吐く正確なフラグを確認する
#              （例: `codex exec --quiet` 等。CLI バージョンで変わる）。
set -euo pipefail

PROMPT="$(cat)"

if ! command -v codex >/dev/null 2>&1; then
  echo "[run_codex] codex CLI が見つかりません" >&2
  exit 127
fi

codex exec "$PROMPT"
