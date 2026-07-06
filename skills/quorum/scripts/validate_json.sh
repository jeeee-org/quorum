#!/usr/bin/env bash
# --output-format json の出力を検証する決定論ゲート。
# stdin に JSON（```json フェンス付きでも可）を受け、output_schema.json の要点を機械チェックする：
#   必須キー / panel.used 非空 / seam_check 7カテゴリ全件 / verdict enum / note 非空
# OK なら "OK" を stdout に出して exit 0。問題は 1行ずつ stderr に出して exit 1。
# 依存は python3 標準ライブラリのみ（jsonschema 不要）。
# 注意: バックエンド規約（run_<name>.sh）とは無関係の補助スクリプト。detect_panel.sh には拾われない。
set -euo pipefail

# ヒアドキュメントが stdin を占有するため、検証対象の JSON は fd3 経由で渡す
exec 3<&0
python3 - <<'PY'
import os, sys, json, re

raw = os.fdopen(3, "r").read()
m = re.search(r'```(?:json)?\s*(.*?)```', raw, re.S)
if m:
    raw = m.group(1)

try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"NG: JSON として parse できない: {e}", file=sys.stderr)
    sys.exit(1)

errs = []

for k in ["question", "final_answer", "panel", "consensus", "contradictions", "seam_check"]:
    if k not in data:
        errs.append(f"必須キー欠落: {k}")

panel = data.get("panel")
if isinstance(panel, dict):
    used = panel.get("used")
    if not isinstance(used, list) or not used:
        errs.append("panel.used が空または配列でない")
elif "panel" in data:
    errs.append("panel がオブジェクトでない")

CATS = ["境界の検証", "境界をまたぐ整合性・原子性", "失敗モード", "観測・追跡",
        "移行の途中状態", "コスト・撤退", "暗黙の前提"]
VERDICTS = {"covered", "partial", "missing", "na"}

sc = data.get("seam_check")
if isinstance(sc, list):
    seen = []
    for row in sc:
        if not isinstance(row, dict):
            errs.append("seam_check の要素がオブジェクトでない")
            continue
        cat = row.get("category")
        seen.append(cat)
        if row.get("verdict") not in VERDICTS:
            errs.append(f"seam_check verdict が不正: {row.get('verdict')!r}（{cat}）")
        if not row.get("note"):
            errs.append(f"seam_check note が空: {cat}")
    for c in CATS:
        if c not in seen:
            errs.append(f"seam_check カテゴリ欠落: {c}")
elif "seam_check" in data:
    errs.append("seam_check が配列でない")

if errs:
    print("\n".join("NG: " + e for e in errs), file=sys.stderr)
    sys.exit(1)

print("OK")
PY
