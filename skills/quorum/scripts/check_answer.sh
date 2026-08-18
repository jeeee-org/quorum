#!/usr/bin/env bash
# 回収済みパネリスト回答の軽量検査（監査記録用）。**自動棄却はしない**——判定は judge に委ねる。
#
# 背景: エージェント型CLIは「これから確認します」等の途中報告だけで exit 0・非空を返し得る
# （IMPROVEMENTS 2026-07-13「exit 0・非空でも実質回答なしを成功扱いし得る」）。そのため
# 「exit 0 かつ非空」を成功と見なさず、回収後にこの決定論検査を通して疑いを監査証跡に残す。
# 第1段は監査記録のみ。誤棄却が無いことを運用で確認できたら、run_*.sh 側の
# 最小バイト数ゲート（欠席扱い）へ格上げする。
#
# 使い方: check_answer.sh [--backend <name>] [--expect <語> ...] <answer_file> [<stderr_file>]
#         または   ... | check_answer.sh [--backend <name>] [--expect <語> ...]
# 出力:   ok                        … 検査通過（exit 0）
#         invalid_response:<理由>   … 実質回答なしの疑い（exit 3）
#         truncated_suspect:<理由>  … 回答はあるが末尾が切れている疑い（exit 4）
# 理由:   empty              空・空白のみ（stderr に手掛かりがあれば `empty:<stderr先頭行>`）
#         argv-too-long      空 かつ stderr が単一引数長の上限超過を示している
#         too_short:<N>B     本文が QUORUM_MIN_ANSWER_BYTES（既定 500）バイト未満
#         missing_expected:<語>  --expect で指定した語が1つも現れない
#         plan_only          構造を持たず全行が作業予告の文（「〜を読み、〜します」だけ）
#         heading/unclosed_fence/midsentence … 末尾切れの疑いの内訳（truncated_suspect）
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
#
# ■ 内容ベースの判定（バイト数では塞がらない穴・IMPROVEMENTS 2026-08-13 / 08-15）
# 「作業予告だけの回答」は 87B〜588B の幅で観測されており、**閾値を超えた予告は `ok` を通り抜ける**
# （588B の予告が実際にすり抜けた）。しかし閾値を上げる対処は採れない——正当な短答（数式の答え等）
# を殺すため。∴ バイト数とは独立に、**中身**で見る2つの判定を足す:
#   1) --expect <語>  … 依頼が求める見出し・分類語を呼び出し側から渡す（決定論・最も確実）
#   2) plan_only      … 構造マーカーが皆無 かつ 全行が「〜を読み、〜します」型の予告文（自動・補助）
# plan_only は誤検知を避けるため QUORUM_PLAN_ONLY_MAX_BYTES（既定 3000）以下にのみ適用する。
# これは too_short の閾値を上げるのとは別物——**予告文と判定できた時だけ**効き、正当な短答は
# 構造か非予告文を持つので当たらない。観測された予告の最大は 588B なので 5 倍の余裕がある。
#
# ■ 末尾切れの検知（truncated_suspect・IMPROVEMENTS 2026-08-18）
# 17KB の実質回答が `## 4. 見落とし` の途中（「書いていないと」）で切れていた事例があり、
# 空・短文しか見ない検査は**長文の途中切れを素通しする**。exit 4 の別系統にするのは、これが
# 「実質回答なし」ではない（回答はある・末尾だけ欠けた）ため——exit 3 にすると SKILL 側の
# 「opus で1回だけ補完」が発火してしまい、有効な回答を捨てる誘導になる。連続 invalid の
# カウンタにも数えない（backend は回答している）。
set -uo pipefail

MIN="${QUORUM_MIN_ANSWER_BYTES:-500}"
case "$MIN" in
  ''|*[!0-9]*) echo "QUORUM_MIN_ANSWER_BYTES は非負整数を指定してください: $MIN" >&2; exit 2 ;;
esac

BACKEND=""
EXPECT=()
rest=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --backend)
      [ "$#" -ge 2 ] || { echo "--backend には backend 名が必要です" >&2; exit 2; }
      BACKEND="$2"; shift 2 ;;
    --backend=*) BACKEND="${1#--backend=}"; shift ;;
    --expect)
      [ "$#" -ge 2 ] || { echo "--expect には期待する語が必要です" >&2; exit 2; }
      EXPECT+=("$2"); shift 2 ;;
    --expect=*) EXPECT+=("${1#--expect=}"); shift ;;
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

  # truncated_suspect は「回答している」側に数える（末尾が欠けただけで実質回答はある）
  case "$verdict" in
    ok|truncated_suspect*)
      count=0; last_ok="$(date -u +%Y-%m-%dT%H:%M:%SZ)" ;;
    *)
      count=$((count + 1))
      if [ "$count" -ge "$warn_at" ]; then
        # **恒久故障と断定しない**——2026-08-18 に、6 run 連続欠席の後で 9.5KB / 17KB の実質回答を
        # 返し、しかも**単独でしか出ない高重大度の指摘を 4 件**出した実例がある。この型の不調は
        # run ごとに揺れるので、連続欠席を根拠にパネルから外すと「効いているパネリスト」を失う。
        # 警告は「今回は補完せよ」であって「次回から外せ」ではない。
        echo "[quorum] 警告: $BACKEND が ${count} 回連続で実質回答なし（$verdict）です（最後に実質回答があったのは ${last_ok}）。この run では枠をネイティブ枠で補完し、縮退した事実を監査証跡に明記してください。--check は通るので detect_panel の連続欠席警告には出ません。※**恒久故障と断定せず、次回もパネルの枠は残すこと**——連続欠席の後に実質回答へ復帰し、その回で単独指摘を出した実績があります（IMPROVEMENTS 2026-08-18）。認証・CLI 版・オプションは点検する価値があります。" >&2
      fi ;;
  esac

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

# --expect: 依頼が求める語が1つも現れないなら実質回答なしとみなす。
# バイト数と独立した決定論の判定——「作業予告を長めに書いた」回答はここで落ちる。
# 1語でも含めば通す（OR）。全語必須にすると、章立てを変えただけの正当な回答を落とすため。
if [ "${#EXPECT[@]}" -gt 0 ]; then
  hit=0
  for word in "${EXPECT[@]}"; do
    [ -n "$word" ] || continue
    if printf '%s' "$CONTENT" | grep -qF -- "$word"; then hit=1; break; fi
  done
  if [ "$hit" = "0" ]; then
    joined="$(printf '%s|' "${EXPECT[@]}")"; joined="${joined%|}"
    emit "invalid_response:missing_expected:${joined}" 3
  fi
fi

# plan_only: 構造マーカーが皆無 かつ 全ての非空行が「作業予告」の文。
# 誤検知を避けるため上限バイト以下にのみ適用する（長文の散文は対象外）。
PLAN_MAX="${QUORUM_PLAN_ONLY_MAX_BYTES:-3000}"
case "$PLAN_MAX" in ''|*[!0-9]*) PLAN_MAX=3000 ;; esac
if [ "$BYTES" -le "$PLAN_MAX" ]; then
  # 見出し・箇条書き・番号付き・コードフェンス・表・引用のいずれかがあれば構造ありとみなす
  if ! printf '%s' "$CONTENT" | grep -qE '^[[:space:]]*(#{1,6}[[:space:]]|[-*+][[:space:]]|[0-9]+[.)][[:space:]]|```|\||>)'; then
    # 非空行のうち「予告文でない行」が1つでもあれば plan_only ではない
    if ! printf '%s\n' "$CONTENT" \
        | grep -v '^[[:space:]]*$' \
        | grep -qvE '(読み|読む|確認|精読|審査|レビュー|検討|追い|追う|揃え|整理|分析|調査|着手|開始|進め|始め|書き|書く|まとめ|報告|把握|洗い出)[^。．]*(ます|ますね|する|していく|ていきます|きます)[。．.]?[[:space:]]*$'; then
      emit "invalid_response:plan_only" 3
    fi
  fi
fi

# truncated_suspect: 実質回答はあるが末尾が切れている疑い（exit 4・invalid には数えない）。
LAST_LINE="$(printf '%s\n' "$CONTENT" | grep -v '^[[:space:]]*$' | tail -n 1)"
FENCES="$(printf '%s\n' "$CONTENT" | grep -cE '^[[:space:]]*```' || true)"
if [ $((FENCES % 2)) -ne 0 ]; then
  emit "truncated_suspect:unclosed_fence" 4
fi
# 見出しだけで終わっている（節を立てて本文が無い）
if printf '%s' "$LAST_LINE" | grep -qE '^[[:space:]]*#{1,6}[[:space:]]'; then
  emit "truncated_suspect:heading" 4
fi
# 文の途中で切れている: 末尾が読点・接続助詞・連用形接続で終わる
# （「…書いていないと」で切れた実例。箇条書きの体言止め「- 出典必須」は当たらない）
if printf '%s' "$LAST_LINE" | grep -qE '(、|，|と|て|で|が|は|を|に|の|へ|や|し|り)[[:space:]]*$'; then
  emit "truncated_suspect:midsentence" 4
fi

emit "ok" 0
