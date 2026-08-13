#!/usr/bin/env bash
# Grok パネリスト。プロンプトを stdin で受け取り、回答全文を stdout に出力する。
#
# 2方式に対応（CLI を優先）:
#   1) Grok Build CLI（`grok`）= SuperGrok / X Premium+ のサブスク枠（OAuth ログイン、従量課金なし）
#      事前に `grok login` で一度サインインしておくこと。
#   2) xAI API（`XAI_API_KEY`）= 従量課金。CLI が無い時のフォールバック。
#
# 学習オフ: grok.com の Settings > Data で「Improve the model」をオフにする（アカウント単位）。
# 検証: grok-cli 0.2.51（-p / --single）、Grok Build CLI の `--prompt-file`（2026-08-09 実機E2E。
#       248KB の pack でも欠落なく通ることを確認）。
#
# プロンプトは argv に載せない（`--prompt-file` を使う）。理由は2つ:
#   1) 単一引数長の上限（Linux の MAX_ARG_STRLEN ≒ 128KB。ARG_MAX 2MB とは別物）を超えると
#      exec 自体が `Argument list too long` で失敗し、grok が**無言で空応答**になる。
#      大型 pack のレビューで4回再発した（IMPROVEMENTS 2026-07-25 ×2 / 07-30 / 08-05）。
#   2) argv は実行中 ps で全文が見える。API 経路がキー・本文とも argv に載せない
#      （curl config / 一時ファイル経由）のと規約を揃える。
#
# メタ応答リトライ: CLI 経路では、正常終了したのに回答が QUORUM_MIN_ANSWER_BYTES（既定 500）
# 未満なら「作業予告だけで終わった」とみなして **1回だけ**投げ直す（QUORUM_GROK_RETRY=0 で無効）。
# 最悪レイテンシは QUORUM_TIMEOUT の2倍になり得る。timeout/argv 上限で落ちた時は投げ直さない。
set -euo pipefail

# 標準のインストール先を PATH に追加（Claude Code の非ログインシェル対策）
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"

# 可用性の自己申告: grok CLI があるか、または XAI_API_KEY+curl があれば可用。
# grok は**既定でオフ**（未設定=不参加。run_codex.sh と対称）。使うPCでは QUORUM_ENABLE_GROK を
# 1/true/yes にして opt-in する。巨大 pack で不安定なPCは 0 のままにして codex だけ参加、も可能。
# --check の exit code 規約: 0=可用 / 2=意図的に不参加 / その他非0=参加したいのに使えない
# （2 を分けることで detect_panel.sh が恒久故障だけを連続欠席として警告できる）
if [ "${1:-}" = "--check" ]; then
  case "${QUORUM_ENABLE_GROK:-}" in
    ''|0|false|no) exit 2 ;;
  esac
  command -v grok >/dev/null 2>&1 && exit 0
  { [ -n "${XAI_API_KEY:-}" ] && command -v curl >/dev/null 2>&1; } && exit 0
  exit 1
fi

MODEL="${GROK_MODEL:-}"
PROMPT="$(cat)"

# パネリスト専用ガードを固定前置する（再帰 fan-out・collab 呼び出し・メタ応答の系統的
# failure mode への全外部 run_*.sh 共通施策。正本: panelist_guard.txt）。
GUARD_FILE="$(cd "$(dirname "$0")" && pwd)/panelist_guard.txt"
if [ -f "$GUARD_FILE" ]; then
  PROMPT="$(cat "$GUARD_FILE")

$PROMPT"
fi

# コスト/時間ガード: QUORUM_TIMEOUT 秒で打ち切り（timeout が無ければ無制限）
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout ${QUORUM_TIMEOUT:-300}"

# メタ応答（「これから確認します」型の作業予告だけで正常終了）への再投入時に足す一文。
# 背景: エージェント型CLIの grok は、重い依頼ほど「作業計画を述べて終わる」挙動に落ちる
# （IMPROVEMENTS 2026-08-11 / 08-12。同一 pack で codex/opus は完走）。panelist_guard.txt に
# 「途中報告・メタ発言禁止」は既にあるが**それでも再発する**ため、プロンプトの文言追加ではなく
# 「短すぎたら1回だけ投げ直す」機械的対策を置く。
RETRY_NOTE='【再投入・重要】直前の応答は作業予告・途中報告だけで、回答本文が含まれていなかったため無効だった。
今回の応答に最終回答そのものを全文書き切ること。「これから読みます」「順に確認します」等の予告や作業計画だけの応答は無効とする。'

# --- 方式1: Grok Build CLI（サブスク枠） ---
if command -v grok >/dev/null 2>&1; then
  # 空の作業ディレクトリで実行する。grok はエージェント型CLIで CWD のファイルを読めるため、
  # 呼び出し元のリポ等を見せない（パネリストに渡すのは $PROMPT のみ、という設計の強制）。
  WORK_DIR="$(mktemp -d)"
  # プロンプトは WORK_DIR の外に置く。CWD に置くと「読めるファイルがある」状態になり、
  # 空 CWD で隔離している意味が薄れるため。--prompt-file は CLI 自身が読むので外でよい。
  PROMPT_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR" "$PROMPT_DIR"' EXIT
  PROMPT_FILE="$PROMPT_DIR/prompt.md"
  OUT_FILE="$PROMPT_DIR/answer.txt"
  BEST_FILE="$PROMPT_DIR/best.txt"
  cd "$WORK_DIR"

  MODEL_ARGS=()
  if [ -n "$MODEL" ]; then MODEL_ARGS=(-m "$MODEL"); fi

  USE_PROMPT_FILE=0
  # 本線: --prompt-file（argv 上限なし・ps に本文が出ない）
  grok --help 2>/dev/null | grep -q -- '--prompt-file' && USE_PROMPT_FILE=1

  MAX_ARGV_BYTES="${QUORUM_MAX_ARGV_BYTES:-120000}"

  attempt() { # attempt <プロンプト本文> — 回答を $OUT_FILE に書き、CLI の exit code を返す
    local body="$1" bytes
    : > "$OUT_FILE"
    if [ "$USE_PROMPT_FILE" = "1" ]; then
      printf '%s' "$body" > "$PROMPT_FILE"
      $TO grok --prompt-file "$PROMPT_FILE" "${MODEL_ARGS[@]}" > "$OUT_FILE"
      return $?
    fi
    # 旧 CLI 向けフォールバック（argv 渡し）。上限超過は「無言の空応答」ではなく明示エラーで
    # 落とす——空応答のまま返すと judge 側で「回答したが中身が無い」と誤読されるため。
    bytes="$(printf '%s' "$body" | wc -c | tr -d ' ')"
    if [ "$bytes" -gt "$MAX_ARGV_BYTES" ]; then
      echo "[run_grok] invalid_response:argv-too-long — プロンプト ${bytes}B が argv 上限 ${MAX_ARGV_BYTES}B を超過。--prompt-file 対応の grok CLI へ更新してください（grok update）" >&2
      return 4
    fi
    $TO grok -p "$body" "${MODEL_ARGS[@]}" > "$OUT_FILE"
    return $?
  }

  rc=0
  attempt "$PROMPT" || rc=$?
  cp "$OUT_FILE" "$BEST_FILE"

  # 実質回答なし（作業予告だけ）の判定は check_answer.sh と同じ閾値を使う。
  # 再投入するのは「CLI 自体は正常終了したのに短い」場合だけ——timeout(124) や
  # argv 上限(4) は投げ直しても同じ結果になり、待ち時間だけが倍になる。
  MIN="${QUORUM_MIN_ANSWER_BYTES:-500}"
  case "$MIN" in ''|*[!0-9]*) MIN=500 ;; esac
  RETRY="${QUORUM_GROK_RETRY:-1}"
  case "$RETRY" in ''|*[!0-9]*) RETRY=1 ;; esac
  BYTES="$(wc -c < "$BEST_FILE" | tr -d ' ')"

  if [ "$rc" = "0" ] && [ "$BYTES" -lt "$MIN" ] && [ "$RETRY" -gt 0 ]; then
    echo "[run_grok] 応答が ${BYTES}B（閾値 ${MIN}B 未満）でした。作業予告だけの応答とみなし、1回だけ再投入します（QUORUM_GROK_RETRY=0 で無効化）" >&2
    rc2=0
    attempt "$PROMPT

$RETRY_NOTE" || rc2=$?
    BYTES2="$(wc -c < "$OUT_FILE" | tr -d ' ')"
    # 長い方を採る（再投入が更に短くなっても初回の内容を失わない）
    if [ "$rc2" = "0" ] && [ "$BYTES2" -gt "$BYTES" ]; then
      cp "$OUT_FILE" "$BEST_FILE"; BYTES="$BYTES2"; rc=0
    fi
    if [ "$BYTES" -lt "$MIN" ]; then
      echo "[run_grok] invalid_response:meta-only — 再投入後も ${BYTES}B（作業予告のみの疑い）。回答はそのまま返すので judge 側で精査してください" >&2
    fi
  fi

  cat "$BEST_FILE"
  exit "$rc"
fi

# --- 方式2: xAI API（従量課金フォールバック） ---
API_MODEL="${GROK_MODEL:-grok-4.5}"
: "${XAI_API_KEY:?grok CLI も XAI_API_KEY も無し（どちらかが必要）}"
command -v curl    >/dev/null 2>&1 || { echo "[run_grok] curl が必要です" >&2; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo "[run_grok] python3 が必要です" >&2; exit 127; }

# 機密を argv に載せない（実行中の ps で見えるため）: キーは curl config、本文は一時ファイル経由
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

PROMPT="$PROMPT" MODEL="$API_MODEL" python3 - >"$TMPD/payload.json" <<'PY'
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "messages": [{"role": "user", "content": os.environ["PROMPT"]}],
    # "search_parameters": {"mode": "auto"},  # Live Search を使うならコメント解除
}))
PY
printf 'header = "Authorization: Bearer %s"\n' "$XAI_API_KEY" > "$TMPD/curl.cfg"

$TO curl -sS --config "$TMPD/curl.cfg" \
  -H "Content-Type: application/json" \
  -d @"$TMPD/payload.json" \
  https://api.x.ai/v1/chat/completions \
| python3 -c 'import sys, json; print(json.load(sys.stdin)["choices"][0]["message"]["content"])'
