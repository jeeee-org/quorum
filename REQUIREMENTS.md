# REQUIREMENTS

## 目的

quorum を Claude Code と Codex の双方から利用可能にし、同じ judge rubric・外部バックエンド・監査証跡を共有する。

## 対象

- `install.sh` から Claude Code と Codex の設定領域へ、それぞれのスキルとトリアージ連携を冪等に配置する。
- Claude Code では Opus サブエージェント、Codex ではCodexネイティブ・サブエージェントを同族補完枠として使う。
- Claude / Codex / Grok / Gemini などの外部バックエンドと references / JSON検証処理は両ホストで共有する。
- 現在ホストと同名の外部runnerはパネルから除外し、ホストCLIのネスト・quorum再帰を防ぐ。Claudeホストは外部 `run_claude.sh`、Codexホストは外部 `run_codex.sh` を呼ばない。
- 外部バックエンド（codex / grok / gemini / 外部claude）は**すべて既定オフ（opt-in）**。何も有効化しなければ目標3枠はホストのネイティブ枠で埋まり、Claudeホストは `opus×3`、Codexホストは `codex-native×3` になる。各PCが `QUORUM_ENABLE_*=1` で有効化した外部だけがパネルに入る。
- codex + grok を有効化したPCでは、利用可能なら Claudeホストで `opus / codex / grok`、Codexホストで `codex-native / claude / grok` の3ベンダー幅になる（これが「フル参加時」の推奨形）。
- `claude-rules` の T0 / T1 / T2a / CADENCE と整合し、T1の実行依頼は `$quorum` へ接続する。
- インストール、パネル検出、マーカー更新、既存ユーザー設定の保持をAPI不要のテストで検証する。

## 対象外

- Codexプラグイン／マーケットプレイスとしての配布。
- Claude CodeのFableエスカレーションをCodex上で再現すること。
- 実キーを使う外部モデルの自動E2E実行。

## 未決事項

- Codexのユーザースキル推奨配置先が将来 `$HOME/.agents/skills` に一本化された場合の移行時期。
- Codexネイティブ補完枠に専用の軽量カスタムエージェントを固定するか。
