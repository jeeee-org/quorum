#!/usr/bin/env bash
# 回収済みパネリスト回答の軽量検査（監査記録用）。**自動棄却はしない**——判定は judge に委ねる。
#
# 背景: エージェント型CLIは「これから確認します」等の途中報告だけで exit 0・非空を返し得る
# （IMPROVEMENTS 2026-07-13「exit 0・非空でも実質回答なしを成功扱いし得る」）。そのため
# 「exit 0 かつ非空」を成功と見なさず、回収後にこの決定論検査を通して疑いを監査証跡に残す。
# 第1段は監査記録のみ。誤棄却が無いことを運用で確認できたら、run_*.sh 側の
# 最小バイト数ゲート（欠席扱い）へ格上げする。
#
# 使い方: check_answer.sh <answer_file> [<stderr_file>]   または   ... | check_answer.sh
# 出力:   ok                        … 検査通過（exit 0）
#         invalid_response:<理由>   … 実質回答なしの疑い（exit 3）
# 理由:   empty            空・空白のみ
#         argv-too-long    空 かつ stderr が単一引数長の上限超過を示している
#         too_short:<N>B   本文が QUORUM_MIN_ANSWER_BYTES（既定 500）バイト未満
#
# stderr_file を渡すと、空応答の**原因**まで判別できる。argv 上限超過（run_grok.sh の旧
# argv 経路など）は exit 0 で空応答になり、`empty` としか分からないと .err を人が読むまで
# 原因が特定できなかった（IMPROVEMENTS 2026-07-30 / 08-05）。
set -uo pipefail

MIN="${QUORUM_MIN_ANSWER_BYTES:-500}"
case "$MIN" in
  ''|*[!0-9]*) echo "QUORUM_MIN_ANSWER_BYTES は非負整数を指定してください: $MIN" >&2; exit 2 ;;
esac

if [ "$#" -ge 1 ]; then
  [ -r "$1" ] || { echo "[check_answer] 読めないファイル: $1" >&2; exit 2; }
  CONTENT="$(cat "$1")"
else
  CONTENT="$(cat)"
fi

# 空・空白のみ
if [ -z "$(printf '%s' "$CONTENT" | tr -d '[:space:]')" ]; then
  # stderr が渡されていれば、空になった原因まで名指しする
  if [ "$#" -ge 2 ] && [ -r "$2" ] \
     && grep -qiE 'argument list too long|argv-too-long' "$2"; then
    echo "invalid_response:argv-too-long"
    exit 3
  fi
  echo "invalid_response:empty"
  exit 3
fi

BYTES="$(printf '%s' "$CONTENT" | wc -c | tr -d ' ')"
if [ "$BYTES" -lt "$MIN" ]; then
  echo "invalid_response:too_short:${BYTES}B"
  exit 3
fi

echo "ok"
