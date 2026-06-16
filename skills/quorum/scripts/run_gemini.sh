#!/usr/bin/env bash
# Gemini パネリスト。プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 2方式に対応（CLI を優先）:
#   1) Google gemini CLI（`gemini`）= Google ログインの無料枠/サブスク（従量課金なし）
#      事前に `gemini` で一度サインインしておくこと。
#      ⚠️ 個人向け無料枠/サブスクは 2026-06-18 に廃止予定（→ Antigravity 移行）。
#         廃止後は方式2（APIキー従量）に自動フォールバックする。
#   2) Gemini API（`GEMINI_API_KEY` / `GOOGLE_API_KEY`）= 従量課金。CLI が無い時のフォールバック。
#      AI Studio でキー発行。grok と同じ「CLI優先＋APIキー従量」の設計に揃えてある。
#
# モデルは GEMINI_MODEL で上書き可（無料/有料で“同じモデル”を指定すれば精度は同じ）。
#   安価重視なら GEMINI_MODEL=gemini-2.5-flash、品質重視なら gemini-2.5-pro。
# 検証: gemini-cli 0.46.0 で -p（非対話）を確認。
set -euo pipefail

# gemini は既定で除外、QUORUM_ENABLE_GEMINI=1 の時だけ有効（オプトイン）。
gemini_api_key() { printf '%s' "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"; }

# 可用性の自己申告: QUORUM_ENABLE_GEMINI=1 かつ（gemini CLI がある or APIキー+curl）。
if [ "${1:-}" = "--check" ]; then
  [ -n "${QUORUM_ENABLE_GEMINI:-}" ] || exit 1
  command -v gemini >/dev/null 2>&1 && exit 0
  { [ -n "$(gemini_api_key)" ] && command -v curl >/dev/null 2>&1; } && exit 0
  exit 1
fi

MODEL="${GEMINI_MODEL:-gemini-2.5-pro}"
PROMPT="$(cat)"

# コスト/時間ガード: QUORUM_TIMEOUT 秒で打ち切り（timeout が無ければ無制限）
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout ${QUORUM_TIMEOUT:-300}"

# --- 方式1: gemini CLI（無料枠/サブスク。2026-06-18 まで） ---
if command -v gemini >/dev/null 2>&1; then
  # -p: 非対話（headless）で最終回答を stdout に出力 / -m: モデル明示
  $TO gemini -m "$MODEL" -p "$PROMPT"
  exit $?
fi

# --- 方式2: Gemini API（従量課金フォールバック） ---
API_KEY="$(gemini_api_key)"
: "${API_KEY:?gemini CLI も GEMINI_API_KEY/GOOGLE_API_KEY も無し（どちらかが必要）}"
command -v curl    >/dev/null 2>&1 || { echo "[run_gemini] curl が必要です" >&2; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo "[run_gemini] python3 が必要です" >&2; exit 127; }

PAYLOAD="$(PROMPT="$PROMPT" python3 - <<'PY'
import json, os
print(json.dumps({
    "contents": [{"parts": [{"text": os.environ["PROMPT"]}]}],
}))
PY
)"

ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

$TO curl -sS "$ENDPOINT" \
  -H "x-goog-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
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
