---
description: 複数モデルに同じ問いを独立並列で投げ、メインセッションの Claude が突き合わせて結論を出す（利用可能なパネルを自動選択）
---

`quorum` スキルを使って、以下の問いを融合パイプライン（独立並列 → judge → fuse）で解いてください。

手順:
1. 引数の先頭/末尾に `--output-format json|text` があれば取り出す（既定 `text`）。残りを「問い」とする。
2. `~/.claude/skills/quorum/scripts/detect_panel.sh` を実行する。出力は**目標数（`QUORUM_PANEL_SIZE` 既定 3）まで独立 opus で補完済みのパネル**（1行=1パネリスト、同名複数行=その回数だけ独立実行）。特定バックエンドの増員・固定は `QUORUM_PANEL="opus,opus,codex,grok"` の明示指定で行う（指定時は検出・補完を飛ばしてそのまま出力）。
3. 出力の各行をそのままパネリストにする（`opus` / `fable` 行は Task で独立 spawn、**model をその名前で明示指定**（セッションモデルを継承させない）、複数なら opus#1/opus#2… と区別。`fable` 行はユーザーの呼びかけ時のみ＝spawn 前に1行宣言し fable_calls.log に追記。それ以外の行は `run_<name>.sh`）。既定パネルは opus/codex/grok の3枠（gemini は `QUORUM_ENABLE_GEMINI=1` でオプトイン、codex は `QUORUM_ENABLE_CODEX` を空文字/`0`/`false` にするとオプトアウト）。欠員は opus→codex→grok の優先順で補完される。行数が目標超の時だけ優先順位でトリムし、落としたものを明示。
4. 各パネリストに**同じ問いをそのまま**渡し、互いにブラインドで独立に答えさせる（非 opus は `~/.claude/skills/quorum/scripts/run_<name>.sh` に stdin で渡す）。成功回答が0件（明示パネルの全滅等）なら fuse せず中断して報告する。
5. `~/.claude/skills/quorum/references/judge_rubric.md` に沿ってメイン（セッションのモデル）が突き合わせ、`--output-format` に応じて出力する（`text`=最終回答＋監査証跡、`json`=`references/output_schema.json` 準拠の単一 JSON ブロック）。

問い（先頭/末尾の `--output-format` 指定は除く）:
$ARGUMENTS
