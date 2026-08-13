#!/usr/bin/env bash
# 回収済みパネリスト回答の軽量検査（監査記録用）。**自動棄却はしない**——判定は judge に委ねる。
#
# 背景: エージェント型CLIは「これから確認します」等の途中報告だけで exit 0・非空を返し得る
# （IMPROVEMENTS 2026-07-13「exit 0・非空でも実質回答なしを成功扱いし得る」）。そのため
# 「exit 0 かつ非空」を成功と見なさず、回収後にこの決定論検査を通して疑いを監査証跡に残す。
# 第1段は監査記録のみ。誤棄却が無いことを運用で確認できたら、run_*.sh 側の
# 最小バイト数ゲート（欠席扱い）へ格上げする。
#
# 使い方: check_answer.sh [--backend <name>] <answer_file> [<stderr_file>]
#         または   ... | check_answer.sh [--backend <name>]
# 出力:   ok                        … 検査通過（exit 0）
#         invalid_response:<理由>   … 実質回答なしの疑い（exit 3）
# 理由:   empty            空・空白のみ（stderr に手掛かりがあれば `empty:<stderr先頭行>`）
#         argv-too-long    空 かつ stderr が単一引数長の上限超過を示している
#         too_short:<N>B   本文が QUORUM_MIN_ANSWER_BYTES（既定 500）バイト未満
#
# --backend を渡すと、その backend の**連続 invalid 回数**を記録し、
# QUORUM_INVALID_WARN（既定 2・0 で無効）回連続したら stderr へ警告する。
# 背景: detect_panel.sh の連続欠席カウンタは `--check` の失敗しか数えないので、
# 「--check は通るのに毎回メタ応答だけ返す」型の恒久故障（IMPROVEMENTS 2026-08-11 / 08-12 の
# grok）は永久に警告されず、パネルが黙って縮退していた。状態は
# $QUORUM_STATE_DIR（既定 ~/.local/share/quorum）/invalid.tsv に `<backend>\t<連続回数>\t<最後にokだった時刻>`。
#
# stderr_file を渡すと、空応答の**原因**まで判別できる。argv 上限超過（run_grok.sh の旧
# argv 経路など）は exit 0 で空応答になり、`empty` としか分からないと .err を人が読むまで
# 原因が特定できなかった（IMPROVEMENTS 2026-07-30 / 08-05）。既知パターン以外でも
# **stderr の先頭行をそのまま理由へ転記する**（IMPROVEMENTS 2026-08-09）——認証切れ・
# レート制限・タイムアウトなどの「無音死」は、checks.txt に `empty` としか残らないと
# judge が「今回は欠席」と記録して終わり、恒久故障が見過ごされてパネルが静かに痩せるため。
# 理由の第1・第2フィールド（`invalid_response:empty`）は変えないので checks_summary.sh の
# 集計はそのまま効く。
set -uo pipefail

MIN="${QUORUM_MIN_ANSWER_BYTES:-500}"
case "$MIN" in
  ''|*[!0-9]*) echo "QUORUM_MIN_ANSWER_BYTES は非負整数を指定してください: $MIN" >&2; exit 2 ;;
esac

BACKEND=""
rest=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --backend)
      [ "$#" -ge 2 ] || { echo "--backend には backend 名が必要です" >&2; exit 2; }
      BACKEND="$2"; shift 2 ;;
    --backend=*) BACKEND="${1#--backend=}"; shift ;;
    *) rest+=("$1"); shift ;;
  esac
done
set -- ${rest[@]+"${rest[@]}"}

# 連続 invalid の記録と警告。判定そのものは変えない（自動棄却しない方針は維持）。
record_verdict() { # record_verdict <verdict>
  local verdict="$1"
  [ -n "$BACKEND" ] || return 0
  local warn_at="${QUORUM_INVALID_WARN:-2}"
  case "$warn_at" in ''|*[!0-9]*) warn_at=2 ;; esac
  [ "$warn_at" -gt 0 ] || return 0

  local state_dir="${QUORUM_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/quorum}"
  local file="$state_dir/invalid.tsv"
  mkdir -p "$state_dir" 2>/dev/null || return 0

  local count=0 last_ok="未記録" n c t
  if [ -r "$file" ]; then
    while IFS=$'\t' read -r n c t; do
      [ "${n:-}" = "$BACKEND" ] || continue
      case "${c:-}" in ''|*[!0-9]*) c=0 ;; esac
      count="$c"; last_ok="${t:-未記録}"
    done < "$file"
  fi

  if [ "$verdict" = "ok" ]; then
    count=0; last_ok="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  else
    count=$((count + 1))
    if [ "$count" -ge "$warn_at" ]; then
      echo "[quorum] 警告: $BACKEND が ${count} 回連続で実質回答なし（$verdict）です（最後に実質回答があったのは ${last_ok}）。**恒久故障の疑い**として監査証跡に明記し、この枠はネイティブ枠で補完してください。--check は通るので detect_panel の連続欠席警告には出ません。" >&2
    fi
  fi

  local tmp; tmp="$(mktemp)" || return 0
  if [ -r "$file" ]; then
    awk -F'\t' -v b="$BACKEND" '$1 != b' "$file" > "$tmp" 2>/dev/null
  fi
  printf '%s\t%s\t%s\n' "$BACKEND" "$count" "$last_ok" >> "$tmp"
  sort -o "$tmp" "$tmp" && mv "$tmp" "$file" 2>/dev/null || rm -f "$tmp"
}

emit() { # emit <verdict> <exit code>
  record_verdict "$1"
  echo "$1"
  exit "$2"
}

if [ "$#" -ge 1 ]; then
  [ -r "$1" ] || { echo "[check_answer] 読めないファイル: $1" >&2; exit 2; }
  CONTENT="$(cat "$1")"
else
  CONTENT="$(cat)"
fi

# 空・空白のみ
if [ -z "$(printf '%s' "$CONTENT" | tr -d '[:space:]')" ]; then
  # stderr が渡されていれば、空になった原因まで名指しする
  if [ "$#" -ge 2 ] && [ -r "$2" ]; then
    if grep -qiE 'argument list too long|argv-too-long' "$2"; then
      emit "invalid_response:argv-too-long" 3
    fi
    # 既知パターン以外は stderr の先頭行を理由へ転記する。checks.txt は
    # `<label>\tab<verdict>` の TSV なので、タブ・改行を潰して1行に畳む。
    CAUSE="$(tr -d '\000' < "$2" | grep -m1 -v '^[[:space:]]*$' || true)"
    CAUSE="$(printf '%s' "$CAUSE" | tr '\t' ' ' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
    if [ -n "$CAUSE" ]; then
      SHORT="${CAUSE:0:100}"
      # 切り出しは C ロケールだとバイト単位になる。末尾に壊れたマルチバイト列を
      # 残さないよう、切った時だけ末尾の1文字分を落とす（IMPROVEMENTS 2026-08-02）。
      [ "$SHORT" = "$CAUSE" ] || SHORT="$(printf '%s' "$SHORT" | LC_ALL=C sed -E 's/[\xC0-\xFF][\x80-\xBF]*$//')"
      emit "invalid_response:empty:${SHORT}" 3
    fi
  fi
  emit "invalid_response:empty" 3
fi

BYTES="$(printf '%s' "$CONTENT" | wc -c | tr -d ' ')"
if [ "$BYTES" -lt "$MIN" ]; then
  emit "invalid_response:too_short:${BYTES}B" 3
fi

emit "ok" 0
