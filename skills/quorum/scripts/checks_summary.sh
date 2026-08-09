#!/usr/bin/env bash
# 過去 run の checks.txt を横断集計する（軽量検査の誤棄却レビュー用）。
#
# check_answer.sh は「監査記録のみ・自動棄却しない」第1段として入れた。次の段
# （run_*.sh 側の最小バイト数ゲート＝欠席扱い）へ格上げしてよいかは、**誤棄却が
# 出ていないこと**を実データで確認してから決める（IMPROVEMENTS 2026-07-13）。
# その確認を毎回手作業でやらずに済むよう、判断材料を1コマンドで出す。
#
# 使い方: checks_summary.sh [runs_dir]
#   既定の runs_dir は $QUORUM_RUNS_DIR、無ければ
#   ${XDG_DATA_HOME:-$HOME/.local/share}/quorum/runs
#
# 見方: **閾値の近く（バイト数が大きい invalid）から潰す**。閾値をわずかに下回っただけで
#       実質的な回答があったものが1件でもあれば、ハードゲートへの格上げは時期尚早。
#       逆に invalid が「これから確認します」型の途中報告ばかりなら格上げしてよい。
set -uo pipefail

RUNS="${1:-${QUORUM_RUNS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/quorum/runs}}"
MIN="${QUORUM_MIN_ANSWER_BYTES:-500}"

if [ ! -d "$RUNS" ]; then
  echo "runs ディレクトリがありません: $RUNS" >&2
  exit 2
fi

total_runs=0
with_checks=0
total_rows=0

echo "# checks.txt 集計 ($RUNS)"
echo

rows="$(mktemp)"; trap 'rm -f "$rows"' EXIT

for d in "$RUNS"/*/; do
  [ -d "$d" ] || continue
  total_runs=$((total_runs + 1))
  f="$d/checks.txt"
  [ -r "$f" ] || continue
  with_checks=$((with_checks + 1))
  while IFS=$'\t' read -r label verdict; do
    [ -n "${label:-}" ] || continue
    total_rows=$((total_rows + 1))
    answer="$d/answer_${label}.md"
    if [ -r "$answer" ]; then
      bytes="$(wc -c < "$answer" | tr -d ' ')"
      excerpt="$(tr '\n' ' ' < "$answer" | cut -b 1-120)"
    else
      bytes="-"; excerpt="(answer ファイルなし)"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$bytes" "$(basename "$d")" "$label" "${verdict:-}" "$excerpt" >> "$rows"
  done < "$f"
done

echo "run 総数: $total_runs / checks.txt を持つ run: $with_checks / 記録された invalid: $total_rows"
echo "現在の閾値 QUORUM_MIN_ANSWER_BYTES=$MIN"
echo

if [ "$with_checks" -eq 0 ]; then
  cat <<'MSG'
まだ checks.txt が1件もありません。軽量検査を通した run が蓄積されるまで、
ハードゲート（欠席扱い）への格上げは判断できません。判断を急がず運用を続けてください。
MSG
  exit 0
fi

if [ "$total_rows" -eq 0 ]; then
  echo "invalid_response の記録はありません（全パネリストが検査を通過）。"
  exit 0
fi

echo "## 理由別の件数"
awk -F'\t' '{ split($4, a, ":"); print a[1] ":" a[2] }' "$rows" | sort | uniq -c | sort -rn
echo

echo "## 個別（バイト数の大きい順＝閾値に近い＝誤棄却の疑いが濃い順）"
printf '%8s  %-18s  %-8s  %-22s  %s\n' bytes run label verdict 冒頭
sort -t$'\t' -k1,1nr "$rows" | while IFS=$'\t' read -r bytes run label verdict excerpt; do
  printf '%8s  %-18s  %-8s  %-22s  %s\n' "$bytes" "$run" "$label" "$verdict" "$excerpt"
done
echo
echo "上位（閾値に近いもの）に実質的な回答が含まれていないか目視する。"
echo "1件でも含まれていれば格上げは見送り、含まれていなければハードゲートへ進んでよい。"
