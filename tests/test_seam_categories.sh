#!/usr/bin/env bash
# 継ぎ目カテゴリの正本一致テスト（drift ガード）。
#
# 継ぎ目カテゴリは3箇所に重複している:
#   1) references/judge_rubric.md の「継ぎ目チェック表」  … 人間・judge が読む正本
#   2) references/output_schema.json の category enum      … --output-format json の契約
#   3) scripts/validate_json.sh の CATS                    … 決定論の検証ゲート
# カテゴリを増減した時にどれか1つを直し忘れると、rubric では点検させているのに JSON では
# 弾かれる（逆もある）という不整合になる。2026-08-09 に3件追加した際に実際に3箇所とも
# 手で直す必要があったので、機械で照合する。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t() { # t <名前> <条件式の結果(0/非0)>
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "ok   - $name"
  else FAIL=$((FAIL+1)); echo "FAIL - $name"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

REPO="$REPO" python3 - > "$TMP/report" <<'PY'
import json, os, re, sys

repo = os.environ["REPO"]

def rubric_cats():
    """judge_rubric.md の継ぎ目チェック表（空欄 2 列のテンプレ行）からカテゴリを拾う。"""
    text = open(f"{repo}/skills/quorum/references/judge_rubric.md", encoding="utf-8").read()
    head = text.index("| 継ぎ目カテゴリ | 判定 |")
    cats = []
    for line in text[head:].splitlines()[2:]:      # ヘッダ行と区切り行を飛ばす
        m = re.match(r"^\|\s*(.+?)\s*\|\s*\|\s*\|\s*$", line)
        if not m:
            break
        cats.append(m.group(1))
    return cats

def schema_cats():
    schema = json.load(open(f"{repo}/skills/quorum/references/output_schema.json", encoding="utf-8"))
    return schema["properties"]["seam_check"]["items"]["properties"]["category"]["enum"]

def validator_cats():
    """validate_json.sh に埋め込まれた python の CATS = [...] を読む。"""
    text = open(f"{repo}/skills/quorum/scripts/validate_json.sh", encoding="utf-8").read()
    m = re.search(r"^CATS = (\[.*?\])$", text, re.S | re.M)
    return json.loads(m.group(1).replace("'", '"'))

r, s, v = rubric_cats(), schema_cats(), validator_cats()
print("rubric_count", len(r))
print("rubric_eq_schema", int(r == s))
print("rubric_eq_validator", int(r == v))
if r != s or r != v:
    print("--- 不一致 ---", file=sys.stderr)
    print("rubric   :", r, file=sys.stderr)
    print("schema   :", s, file=sys.stderr)
    print("validator:", v, file=sys.stderr)
PY

get() { grep -E "^$1 " "$TMP/report" | awk '{print $2}'; }

t "rubric の継ぎ目チェック表を抽出できる" "$([ "$(get rubric_count)" -ge 7 ]; echo $?)"
t "rubric と output_schema.json の enum が一致（順序込み）" "$([ "$(get rubric_eq_schema)" = "1" ]; echo $?)"
t "rubric と validate_json.sh の CATS が一致（順序込み）" "$([ "$(get rubric_eq_validator)" = "1" ]; echo $?)"

# 旧7カテゴリだけの JSON は「カテゴリ欠落」で弾かれること（増やしたカテゴリが効いている証拠）
OLD7='{"question":"q","final_answer":"a","panel":{"used":["opus"]},"consensus":[],"contradictions":[],"seam_check":[
{"category":"境界の検証","verdict":"na","note":"x"},
{"category":"境界をまたぐ整合性・原子性","verdict":"na","note":"x"},
{"category":"失敗モード","verdict":"covered","note":"x"},
{"category":"観測・追跡","verdict":"partial","note":"x"},
{"category":"移行の途中状態","verdict":"missing","note":"x"},
{"category":"コスト・撤退","verdict":"na","note":"x"},
{"category":"暗黙の前提","verdict":"covered","note":"x"}]}'
printf '%s' "$OLD7" | bash "$REPO/skills/quorum/scripts/validate_json.sh" >/dev/null 2>&1
t "旧7カテゴリだけの出力は NG（追加分が必須になっている）" "$([ "$?" != "0" ]; echo $?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
