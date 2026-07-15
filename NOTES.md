# NOTES

## Codex対応の設計判断

- 現行Codex CLI 0.144.1と、このPCの `claude-rules` は `$CODEX_HOME/skills` を利用しているため、初期実装も同じ配置契約に揃える。公式ドキュメント側の `$HOME/.agents/skills` への移行は別判断とする。
- Codexホストの同族補完枠は外部 `codex exec` ではなくネイティブ・サブエージェントにする。外部CLIを再度起動すると、同じユーザースキルやグローバル規則を読んで再帰する可能性があり、ベンダー多様性も増えないため。
- 分類の唯一の正本は `claude-rules/hooks/triage-rubric.txt`。quorum側のCodexルールは分類を再定義せず、T1から `$quorum` への接続だけを担う。
- Claude版の `skills/quorum/` を共有資産の正本として維持し、Codex版はインストール時にCodex専用 `SKILL.md` とUIメタデータを上書きして自己完結した配置物を組み立てる。
- Claudeホストから外部Codexパネリストを呼ぶ経路にも `--ephemeral --ignore-user-config` を付ける。Codex版スキルをグローバル導入した後のユーザー設定再読込とセッション残存を避けるためで、引数はモックテストで固定する。
- Codexホストから外部Claudeを呼ぶ経路は `claude -p --safe-mode --no-session-persistence --tools ""` と空CWDで隔離する。Claudeホストでは同runnerを除外するため再帰しない。`ANTHROPIC_API_KEY` 検出時は、明示許可なしでは無効化して意図しないAPI従量を防ぐ。
- Codex版のnative fan-outからjudgeまでと、Claude版からの外部Codex（`--ephemeral --ignore-user-config` 込み）は2026-07-13に実機E2E済み。検証範囲はREADMEとcheckpointに分けて記録する。

## パネル参加の既定オフ（opt-in）化（2026-07-15）

- **判断**: 外部バックエンド（codex / grok / gemini / Codexホストの外部claude）を**すべて既定オフ**にし、`QUORUM_ENABLE_*=1` を立てたPCだけが参加する opt-in 方式へ統一した。何も設定しなければ既定パネルは Claude=`opus×3` / Codex=`codex-native×3`。
- **なぜ**: (1) 共有正本の既定は「外部依存ゼロ・追加課金ゼロ・驚きなし」であるべき。新PC/CI/未認証環境が clone しただけで opus×3 として無害に動く。(2) 参加は各PCの能力（CLI導入・認証・課金許容）に強く依存するローカル事情なので、コード既定ではなくPCローカル設定（`~/.claude/settings.json`）に置くのが筋。(3) codex だけ既定オンだった非対称を解消し、全外部を同一規約（`${VAR:-}` で未設定=不参加、`1/true/yes` で参加）に揃えた。grok は従来スイッチ自体が無く、`QUORUM_ENABLE_GROK` を新設。
- **各PCの opt-in 先**: `rules/settings-env.json` は3枠とも `"0"`（可視ノブの既定）をマージし、install は**未設定キーのみ**書くので、PCで `"1"` に上書きした参加設定は再インストールで保たれる。grok だけ落として codex は残す等の粒度も可能（巨大 pack で grok が不安定な問題への即応にも使える → IMPROVEMENTS 2026-07-13 の grok 項）。
- **代替案（不採用）**: 単一の `QUORUM_NATIVE_ONLY` で一括 opus-only にする案。per-backend スイッチの方が「grok だけ除外」等の合成が効き、backend が少数固定の本リポでは実利が上と判断した。
