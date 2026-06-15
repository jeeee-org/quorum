---
description: 複数モデルに同じ問いを独立並列で投げ、Opus 4.8 が突き合わせて結論を出す（利用可能なパネルを自動選択）
---

`fusion` スキルを使って、以下の問いを融合パイプライン（独立並列 → judge → fuse）で解いてください。

手順:
1. `~/.claude/skills/fusion/scripts/detect_panel.sh` を実行して利用可能なバックエンドを検出する。
2. 利用可能なものを**全部**パネリストに使う（最低2回は独立実行。`opus` のみなら Opus 4.8 を2回）。
3. 各パネリストに**同じ問いをそのまま**渡し、互いにブラインドで独立に答えさせる（外部モデルは `~/.claude/skills/fusion/scripts/run_*.sh` に stdin で渡す）。
4. `~/.claude/skills/fusion/references/judge_rubric.md` に沿って Opus 4.8 が突き合わせ、最終回答＋監査証跡を出す。

問い:
$ARGUMENTS
