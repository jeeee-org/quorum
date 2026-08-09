#!/usr/bin/env bash
# IMPROVEMENTS.md の並び順が規約どおり（古い順・末尾追記）であることを機械検査する。
#
# 背景: 正本の並びは長らく「先頭5項目だけ新しい順・以降は古い順」の混在で、ヘッダの
# コメントは「新しいものを上に積む」のままだった（IMPROVEMENTS 2026-08-09）。規約と実態が
# ずれていると、利用側 clone が良かれと思って整列するたびに**全項目 conflict** を起こし、
# その回の実質的な追記まで巻き込んで失う。人の目では再発するので test で止める。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$REPO/IMPROVEMENTS.md"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

t "IMPROVEMENTS.md がある" "$([ -r "$FILE" ]; echo $?)"

# 見出しは `## YYYY-MM-DD — …` の形
heads="$(grep -n '^## ' "$FILE")"
bad_format="$(printf '%s\n' "$heads" | grep -vE '^[0-9]+:## [0-9]{4}-[0-9]{2}-[0-9]{2} ' || true)"
t "全見出しが '## YYYY-MM-DD ' で始まる" "$([ -z "$bad_format" ] || { printf '  %s\n' "$bad_format"; false; }; echo $?)"

# 日付が昇順（同日は並列可なので「降順が現れないこと」を見る）
dates="$(printf '%s\n' "$heads" | sed -E 's/^[0-9]+:## ([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')"
count="$(printf '%s\n' "$dates" | grep -c . )"
t "項目が2件以上ある（検査が空振りしていない）" "$([ "$count" -ge 2 ]; echo $?)"

prev=""; regressions=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  if [ -n "$prev" ] && [ "$d" \< "$prev" ]; then
    regressions="${regressions}${prev} の後に ${d}"$'\n'
  fi
  prev="$d"
done <<< "$dates"
t "日付が古い順に並んでいる（新しい項目は末尾へ）" \
  "$([ -z "$regressions" ] || { printf '  逆転: %s' "$regressions"; false; }; echo $?)"

# 最後の項目が最も新しい = 末尾追記の運用と一致
newest="$(printf '%s\n' "$dates" | sort | tail -1)"
last="$(printf '%s\n' "$dates" | tail -1)"
t "末尾の項目が最新日付" "$([ "$last" = "$newest" ] || { echo "  末尾=$last 最新=$newest"; false; }; echo $?)"

# ヘッダのコメントが規約と食い違っていない（今回のずれの震源）。
# 検査対象は最初の見出しより上＝規約が書かれている領域だけ（本文には旧規約を
# 引用した項目があるので、ファイル全体を見ると誤検知する）。
header="$(sed -n '1,/^## /p' "$FILE" | sed '$d')"
t "ヘッダのコメントが末尾追記を指示している" \
  "$(printf '%s\n' "$header" | grep -qE '^<!--.*末尾.*-->'; echo $?)"
t "ヘッダに旧規約（新しいものを上に積む）が残っていない" \
  "$(! printf '%s\n' "$header" | grep -q '新しいものを上に積む'; echo $?)"

# 追記するのはスキル実行中のモデルなので、SKILL 側にも規約が要る
t "quorum SKILL に末尾追記の規約がある" \
  "$(grep -q '末尾へ追記' "$REPO/skills/quorum/SKILL.md"; echo $?)"
t "codex-quorum SKILL に末尾追記の規約がある" \
  "$(grep -q '末尾へ追記' "$REPO/skills/codex-quorum/SKILL.md"; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
