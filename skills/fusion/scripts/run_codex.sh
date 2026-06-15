#!/usr/bin/env bash
# GPT-5.5 パネリスト（OpenAI codex CLI 経由）。
# プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 認証: codex に ChatGPT アカウントでログイン済みならサブスク枠で動く。
#       APIキー（OPENAI_API_KEY）でも可だがその場合は従量課金。
# 検証: codex-cli 0.130.0 で動作確認。--output-last-message で最終回答のみ取得。
set -euo pipefail

PROMPT="$(cat)"

if ! command -v codex >/dev/null 2>&1; then
  echo "[run_codex] codex CLI が見つかりません" >&2
  exit 127
fi

# コスト/時間ガード: FUSION_TIMEOUT 秒で打ち切り（timeout が無ければ無制限）
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout ${FUSION_TIMEOUT:-300}"

TMP="$(mktemp)"; ERR="$(mktemp)"
trap 'rm -f "$TMP" "$ERR"' EXIT

# --skip-git-repo-check: リポジトリ外でも実行可 / --color never: 整形なし
# -o: 最終メッセージのみをファイルへ（途中のログを混ぜない）
if $TO codex exec --skip-git-repo-check --color never -o "$TMP" "$PROMPT" >/dev/null 2>"$ERR"; then
  cat "$TMP"
else
  echo "[run_codex] codex exec が失敗しました:" >&2
  cat "$ERR" >&2
  exit 1
fi
