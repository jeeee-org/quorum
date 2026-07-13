# NOTES

## Codex対応の設計判断

- 現行Codex CLI 0.144.1と、このPCの `claude-rules` は `$CODEX_HOME/skills` を利用しているため、初期実装も同じ配置契約に揃える。公式ドキュメント側の `$HOME/.agents/skills` への移行は別判断とする。
- Codexホストの同族補完枠は外部 `codex exec` ではなくネイティブ・サブエージェントにする。外部CLIを再度起動すると、同じユーザースキルやグローバル規則を読んで再帰する可能性があり、ベンダー多様性も増えないため。
- 分類の唯一の正本は `claude-rules/hooks/triage-rubric.txt`。quorum側のCodexルールは分類を再定義せず、T1から `$quorum` への接続だけを担う。
- Claude版の `skills/quorum/` を共有資産の正本として維持し、Codex版はインストール時にCodex専用 `SKILL.md` とUIメタデータを上書きして自己完結した配置物を組み立てる。
- Claudeホストから外部Codexパネリストを呼ぶ経路にも `--ephemeral --ignore-user-config` を付ける。Codex版スキルをグローバル導入した後のユーザー設定再読込とセッション残存を避けるためで、引数はモックテストで固定する。
- Codexホストから外部Claudeを呼ぶ経路は `claude -p --safe-mode --no-session-persistence --tools ""` と空CWDで隔離する。Claudeホストでは同runnerを除外するため再帰しない。`ANTHROPIC_API_KEY` 検出時は、明示許可なしでは無効化して意図しないAPI従量を防ぐ。
- Codex版のnative fan-outからjudgeまでと、Claude版からの外部Codex（`--ephemeral --ignore-user-config` 込み）は2026-07-13に実機E2E済み。検証範囲はREADMEとcheckpointに分けて記録する。
