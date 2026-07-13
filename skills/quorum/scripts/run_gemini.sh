#!/usr/bin/env bash
# Gemini パネリスト。プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 2方式に対応（**API キーを優先**。CLI は補助）:
#   1) Gemini API（`GEMINI_API_KEY` / `GOOGLE_API_KEY`）= 本線。AI Studio でキー発行。
#      generativelanguage / Vertex の素の API。Google の CLI 再編（下記）と別系統で影響を受けない。
#   2) gemini CLI（`gemini`）= 補助。API キーが無い時だけ使う（Google ログインの無料枠/サブスク）。
#      ⚠️ 個人向け `gemini` は 2026-06-18 に廃止（→ Antigravity CLI `agy` へ）。後継 `agy` は
#         headless 未成熟（`agy -p` が非TTYで stdout 脱落 #76 / APIキー認証 未対応 #78＝基本ブラウザ
#         ログイン）で、サブプロセス起動のパネリスト用途には当面使えない。∴ ここでは agy を採用せず、
#         API キー経路を本線に置く。agy が #76/#78 を直したら「サブスク枠のコストゼロCLI」として再評価。
#
# モデルは GEMINI_MODEL で上書き可（無料/有料で“同じモデル”を指定すれば精度は同じ）。
#   既定は gemini-2.5-flash（APIキー無料枠で動く最小構成）。品質重視は GEMINI_MODEL=gemini-2.5-pro。
#   ⚠️ APIキー無料枠では gemini-2.5-pro は limit:0（構造的に不可、レート待ちでは解消しない）。
#      pro を使うには課金アカウント紐付けが必要。無料枠キーは flash を使うこと。
# 検証: APIキー経路は実キーE2E済（2026-06-17、flash 成功 / pro は無料枠 limit:0 を確認）。
set -euo pipefail

# gemini は既定で除外、QUORUM_ENABLE_GEMINI=1 の時だけ有効（オプトイン）。
gemini_api_key() { printf '%s' "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"; }

# 可用性の自己申告: QUORUM_ENABLE_GEMINI=1 かつ（APIキー+curl or gemini CLI）。
# 0/false/no は空文字・未設定と同じく無効扱い（課金スイッチの驚き防止。run_codex.sh と同規約）。
if [ "${1:-}" = "--check" ]; then
  case "${QUORUM_ENABLE_GEMINI:-}" in
    ''|0|false|no) exit 1 ;;
  esac
  { [ -n "$(gemini_api_key)" ] && command -v curl >/dev/null 2>&1; } && exit 0
  command -v gemini >/dev/null 2>&1 && exit 0
  exit 1
fi

MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
PROMPT="$(cat)"

# コスト/時間ガード: QUORUM_TIMEOUT 秒で打ち切り（timeout が無ければ無制限）
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout ${QUORUM_TIMEOUT:-300}"

# --- 方式1: Gemini API（本線。API キーがあればこちらを使う） ---
API_KEY="$(gemini_api_key)"
if [ -n "$API_KEY" ]; then
  command -v curl    >/dev/null 2>&1 || { echo "[run_gemini] curl が必要です" >&2; exit 127; }
  command -v python3 >/dev/null 2>&1 || { echo "[run_gemini] python3 が必要です" >&2; exit 127; }

  # 機密を argv に載せない（実行中の ps で見えるため）: キーは curl config、本文は一時ファイル経由
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT

  PROMPT="$PROMPT" python3 - >"$TMPD/payload.json" <<'PY'
import json, os
print(json.dumps({
    "contents": [{"parts": [{"text": os.environ["PROMPT"]}]}],
}))
PY
  printf 'header = "x-goog-api-key: %s"\n' "$API_KEY" > "$TMPD/curl.cfg"

  ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

  $TO curl -sS --config "$TMPD/curl.cfg" \
    -H "Content-Type: application/json" \
    -d @"$TMPD/payload.json" \
    "$ENDPOINT" \
  | python3 -c '
import sys, json
data = json.load(sys.stdin)
if "error" in data:
    sys.stderr.write("[run_gemini] API エラー: %s\n" % data["error"].get("message", data["error"]))
    sys.exit(1)
cands = data.get("candidates") or []
if not cands:
    sys.stderr.write("[run_gemini] 応答に candidates がありません: %s\n" % json.dumps(data)[:500])
    sys.exit(1)
parts = cands[0].get("content", {}).get("parts", [])
text = "".join(p.get("text", "") for p in parts)
if not text:
    sys.stderr.write("[run_gemini] 空応答（finishReason=%s）\n" % cands[0].get("finishReason"))
    sys.exit(1)
print(text)
'
  exit $?
fi

# --- 方式2: gemini CLI（補助。API キーが無い時だけ） ---
# ⚠️ 個人向け gemini は 2026-06-18 廃止。後継 agy は headless 未成熟ゆえここでは使わない（冒頭コメント参照）。
if command -v gemini >/dev/null 2>&1; then
  # 空の作業ディレクトリで実行する。gemini CLI はエージェント型で CWD のファイルを読めるため、
  # 呼び出し元のリポ等を見せない（パネリストに渡すのは $PROMPT のみ、という設計の強制）。
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  cd "$WORK_DIR"
  # -p: 非対話（headless）モード。プロンプト本文は stdin で渡す（-p は stdin 入力への追記仕様。
  # argv に載せると実行中 ps で全文が見えるため空にする）/ -m: モデル明示
  printf '%s' "$PROMPT" | $TO gemini -m "$MODEL" -p ""
  exit $?
fi

echo "[run_gemini] GEMINI_API_KEY/GOOGLE_API_KEY も gemini CLI も無し（どちらかが必要）" >&2
exit 1
