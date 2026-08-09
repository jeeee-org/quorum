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
# codex は**既定でオフ**（未設定=不参加。何も設定しなければパネルは opus×3）。使うPCでは
# QUORUM_ENABLE_CODEX を 1/true/yes にして opt-in する（settings.json の明示値は
# install.sh のマージで上書きされない＝PCごとの参加設定はそのPCに残る）。
# --check の exit code 規約:
#   0 = 可用 / 2 = **意図的に不参加**（opt-out・未設定） / その他非0 = 参加したいのに使えない
# 2 を分けるのは、恒久的な故障（認証切れ・CLI 未導入）を「毎回の一時的欠席」に埋もれさせ
# ないため。detect_panel.sh は 2 以外の失敗だけを連続欠席として数える（IMPROVEMENTS 2026-07-10）。
if [ "${1:-}" = "--check" ]; then
  case "${QUORUM_ENABLE_CODEX:-}" in
    ''|0|false|no) exit 2 ;;
  esac
  command -v codex >/dev/null 2>&1 && exit 0 || exit 1
fi

PROMPT="$(cat)"

# パネリスト専用ガードを固定前置する（再帰 fan-out・collab 呼び出し・メタ応答の系統的
# failure mode への全外部 run_*.sh 共通施策。正本: panelist_guard.txt）。
GUARD_FILE="$(cd "$(dirname "$0")" && pwd)/panelist_guard.txt"
if [ -f "$GUARD_FILE" ]; then
  PROMPT="$(cat "$GUARD_FILE")

$PROMPT"
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "[run_codex] codex CLI が見つかりません" >&2
  exit 127
fi

# コスト/時間ガード: QUORUM_TIMEOUT 秒で打ち切り（timeout が無ければ無制限）
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout ${QUORUM_TIMEOUT:-300}"

# collab（サブエージェント）機構をフラグで無効化する。exec + --ephemeral + 空 WORK_DIR では
# collab が機能しないのにモデルからは使えるように見え、重いタスクほど「監査を3領域に分割」と
# 宣言して spawn を試み、`collab spawn failed: no thread with id` を繰り返した末に
# タイムアウトする（IMPROVEMENTS 2026-07-13）。codex-cli 0.144.1 では機能フラグ
# `multi_agent`（features list で stable/true）がこれに当たり、`--disable multi_agent` で
# 個別に落とせることを確認した。プロンプト側のパネリスト専用ガードは**残す**——フラグの
# 名前も存在も CLI のバージョン次第で変わるため、二重の歯止めにする。
CODEX_FEATURE_ARGS=()
if codex exec --help 2>/dev/null | grep -q -- '--disable'; then
  CODEX_FEATURE_ARGS=(--disable multi_agent)
fi

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
if printf '%s' "$PROMPT" | $TO codex exec -m gpt-5.6-sol --ephemeral --ignore-user-config --skip-git-repo-check --color never "${CODEX_FEATURE_ARGS[@]}" -o "$TMP" - >/dev/null 2>"$ERR"; then
  cat "$TMP"
else
  echo "[run_codex] codex exec が失敗しました:" >&2
  cat "$ERR" >&2
  exit 1
fi
