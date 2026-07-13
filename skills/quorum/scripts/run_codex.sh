#!/usr/bin/env bash
# GPT-5.6 Sol パネリスト（OpenAI codex CLI 経由）。モデルは -m で明示固定する。
# プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 認証: codex に ChatGPT アカウントでログイン済みならサブスク枠で動く。
#       APIキー（OPENAI_API_KEY）でも可だがその場合は従量課金。
# 検証: codex-cli 0.144.1、現行の --ephemeral / --ignore-user-config / stdin / -o 経路を
#       2026-07-13のClaude版quorum実走でE2E確認済み。
set -euo pipefail

# 可用性の自己申告（detect_panel.sh から呼ばれる）
# codex は**既定で参加**（未設定=オン）。従量課金を抑えたいPCでは QUORUM_ENABLE_CODEX に
# 空文字か 0/false を置いて無効化する（settings.json の明示値は install.sh のマージで上書きされない）。
if [ "${1:-}" = "--check" ]; then
  case "${QUORUM_ENABLE_CODEX-1}" in
    ''|0|false|no) exit 1 ;;
  esac
  command -v codex >/dev/null 2>&1 && exit 0 || exit 1
fi

PROMPT="$(cat)"

if ! command -v codex >/dev/null 2>&1; then
  echo "[run_codex] codex CLI が見つかりません" >&2
  exit 127
fi

# コスト/時間ガード: QUORUM_TIMEOUT 秒で打ち切り（timeout が無ければ無制限）
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout ${QUORUM_TIMEOUT:-300}"

TMP="$(mktemp)"; ERR="$(mktemp)"
# 空の作業ディレクトリで実行する。codex exec はエージェント型CLIで CWD のファイルを読めるため、
# 呼び出し元のリポ等を見せない（パネリストに渡すのは $PROMPT のみ、という設計の強制）。
WORK_DIR="$(mktemp -d)"
trap 'rm -f "$TMP" "$ERR"; rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

# -m gpt-5.6-sol: パネル構成を全PCで固定（各PCの ~/.codex/config.toml 既定に依存させない）。
#                 config 既定に任せると PC により 5.5 や gpt-5.3-codex に化けるため明示する。
#                 モデルを変える場合は codex CLI で正式な model ID を確認してから差し替える。
# --ephemeral / --ignore-user-config: セッション保存とユーザー設定由来の再帰発動を避ける
# --skip-git-repo-check: リポジトリ外でも実行可 / --color never: 整形なし
# -o: 最終メッセージのみをファイルへ（途中のログを混ぜない）
# 末尾の `-`: プロンプトを stdin から読む（argv に載せると実行中 ps で全文が見えるため）
if printf '%s' "$PROMPT" | $TO codex exec -m gpt-5.6-sol --ephemeral --ignore-user-config --skip-git-repo-check --color never -o "$TMP" - >/dev/null 2>"$ERR"; then
  cat "$TMP"
else
  echo "[run_codex] codex exec が失敗しました:" >&2
  cat "$ERR" >&2
  exit 1
fi
