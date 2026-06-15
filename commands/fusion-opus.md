---
description: Opus 4.8 のみで自己融合（外部CLI不要・追加課金ゼロ）。同じ問いを2回独立実行して Opus が統合する
---

`fusion` スキルを **opus 自己融合モード** で使ってください（外部モデルは使わない）。

手順:
1. **Opus 4.8 のサブエージェントを2つ並列に spawn** し、各自に web 検索・bash を使って独立に同じ問いを解かせる（互いの結果は見せない）。
2. `~/.claude/skills/fusion/references/judge_rubric.md` に沿って、メイン Opus が2つの回答を突き合わせる。
3. 最終回答＋監査証跡（合意・矛盾・盲点）を出す。

> このモードは Claude Code のプラン内で動き、追加の従量課金は発生しない。

問い:
$ARGUMENTS
