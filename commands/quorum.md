---
description: 複数モデルに同じ問いを独立並列で投げ、Opus 4.8 が突き合わせて結論を出す（利用可能なパネルを自動選択）
---

`quorum` スキルを使って、以下の問いを融合パイプライン（独立並列 → judge → fuse）で解いてください。

手順:
1. 引数の先頭/末尾に `--output-format json|text` があれば取り出す（既定 `text`）。残りを「問い」とする。
2. `~/.claude/skills/quorum/scripts/detect_panel.sh` を実行する。出力は**目標数（`QUORUM_PANEL_SIZE` 既定 4）まで独立 opus で補完済みのパネル**（1行=1パネリスト、同名複数行=その回数だけ独立実行）。
3. 出力の各行をそのままパネリストにする（`opus` 行は Task で独立 spawn、複数なら opus#1/opus#2… と区別。非 opus 行は `run_<name>.sh`）。理想は grok/opus/codex/gemini の4枠、使えない枠は opus で補完される。行数が目標超の時だけ優先順位でトリムし、落としたものを明示。
4. 各パネリストに**同じ問いをそのまま**渡し、互いにブラインドで独立に答えさせる（非 opus は `~/.claude/skills/quorum/scripts/run_<name>.sh` に stdin で渡す）。
5. `~/.claude/skills/quorum/references/judge_rubric.md` に沿って Opus 4.8 が突き合わせ、`--output-format` に応じて出力する（`text`=最終回答＋監査証跡、`json`=`references/output_schema.json` 準拠の単一 JSON ブロック）。

問い（先頭/末尾の `--output-format` 指定は除く）:
$ARGUMENTS
