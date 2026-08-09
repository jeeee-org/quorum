# PROGRESS

## 現在地

Claude Code / Codex 両ホスト対応が完了し、運用フェーズ。Claudeは opus、Codexは codex-native を同族補完枠にし、共通の外部バックエンド・judge rubric・監査証跡を使う。CodexのT1分類は `claude-rules` から `$quorum` へ接続済み。

2026-08-09 に、利用側で溜まっていた改善メモ（2026-07-16〜08-09 の16件）を正本へ取り込み、汎用ハーネスに効くものを一巡して反映し終えた。テストは153件。残タスクは gemini 関連3件と、実運用データ待ちの1件だけ。

- **利用側からの持ち込みは `git pull && ./install.sh` で受ける**。`IMPROVEMENTS.md` は install が張る symlink 経由でしか正本に届かないので、リポを移動したら install を回し直す（切れていると実運用の追記が正本に入らない。NOTES.md 参照）。
- **パネルの健全性は detect_panel.sh の stderr で分かる**。opt-in 済み backend が3回連続で欠席すると警告が出る＝パネルが静かに同族ネイティブ寄りへ退化しているサイン。

## 次にやること

- [ ] 実質回答なし検知の第2段（**データ待ち**）: この clone には checks.txt を持つ run が0件で誤棄却の有無を判断できない。運用が溜まったら `scripts/checks_summary.sh` を実行し、閾値付近に実質回答が無ければ run 側の最小バイト数ゲート（欠席扱い）へ格上げする（IMPROVEMENTS 2026-07-13）
- [ ] gemini/curl経路の実キーE2Eを確認する
- [ ] gemini APIキーをStandard key→Authorization keyへ移行する（Google公式が2026年9月にStandard key全般を拒否予定と告知。`GEMINI_API_KEY`/`GOOGLE_API_KEY`の環境変数名は不変だが保存済みキー種別の確認が必要。quorumの実装調査は2026-07-15）
- [ ] **Gemini 3.5 Pro を quorum で試す（2026-07-17 リリース予定以降）**: 課金アカウントに支出上限を設定 → 課金キーで `GEMINI_MODEL=<3.5-pro の正式ID>` を generativelanguage API で実キーE2E → 精度/コストを見て既定 `gemini-2.5-flash` からの昇格可否を判断。無料枠キーでは 2.5-pro 同様 `limit:0` になる想定（課金必須）。agy 経路は #78/#76 未解決のため引き続き見送り

## 完了

- 2026-08-09: 利用側から届いた改善メモをトリアージ。新規は1件（grok の E2BIG 無音死）で、①prompt 受け渡しは `--prompt-file` 化で解消済み・③pack サイズ注意は取り下げ・**②空応答時に stderr 先頭行を `invalid_response:empty:<先頭行>` へ転記のみ新規実装**（原因の違う無音死を判別可能に。集計キーは不変）。テスト153件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: 残TODO 3件を処理。①codex の collab を `--disable multi_agent` で恒久無効化（機能フラグを実機特定）②opt-in 済み backend の連続欠席を stderr へ警告（`--check` に「2=意図的に不参加」を新設して opt-out と区別）③`checks_summary.sh` で誤棄却レビューを1コマンド化。テスト146件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: 取り込んだ改善メモを rubric/packing へ反映。継ぎ目カテゴリ3件追加（仕様内部の整合性・承認権限の射程・構成要素の必要性）＋judge自身が確かめる節、context-packing に「pack は司書の盲点を継承する」節・材料の版/根拠コード欄、mapping.txt に visibility 列、カテゴリ3重複の drift ガードを追加。テスト125件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: grok の大型pack欠席を解消。CLI経路を argv → `--prompt-file` へ（248KB実機E2E）。旧CLIは上限超過をexit 4で明示、`check_answer.sh` は stderr から `argv-too-long` を判定。run_*.sh規約に「promptをargvに展開しない」を明記。テスト121件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: fable の費用表現を「都度課金」→「サブスク枠の使用量」へ是正（SKILL/rules/README。同一プラン上で走る＝別建て請求なし、ただしAPIキー環境は除く）。あわせて dangling だった IMPROVEMENTS.md の symlink を install 再実行で復旧し、届いていなかった改善メモ15件（2026-07-16〜08-09）を正本へ取り込み → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-07-15: GROK_MODEL既定値`grok-4.5`を確認。2026-07-08発表・07-09 GAの現行フラッグシップで、xAI公式のGrok Build CLI既定とも一致（サードパーティ製grok-cliのgrok-code-fast-1既定と誤認しないよう要注意）。grok-5は未提供（トレーニング中）。既定値の変更不要と判定
- 2026-07-15: IMPROVEMENTS 2件の第1段実装: ①回収後の軽量検査 `check_answer.sh`（invalid_response を checks.txt へ監査記録・自動棄却なし）②パネリスト専用ガード `panelist_guard.txt` を全外部 run_*.sh に固定前置（再帰fan-out/collab/メタ応答対策の共通1施策）。テスト105件パス＋実機grokでガード実効を副次確認 → [checkpoint](docs/checkpoints/2026-07-15.md)
- 2026-07-15: パネル参加を全外部（codex/grok/gemini/外部claude）**既定オフ（opt-in）**へ統一。既定パネルは opus×3（Codex=codex-native×3）、`QUORUM_ENABLE_*=1` で参加。`QUORUM_ENABLE_GROK` 新設、settings-env は3枠"0"化、このPCは codex/grok=1。テスト全91件パス＋実機で opus×3 / opus・codex・grok を確認（判断は NOTES.md） → [checkpoint](docs/checkpoints/2026-07-15.md)
- 2026-07-15: 別PC（push不可）で追記された IMPROVEMENTS 2件を当PCへ取り込み。grok巨大pack失敗は既存の「exit 0・実質回答なし」項へ統合、codex collabハングは新規項として維持 → [checkpoint](docs/checkpoints/2026-07-15.md)
- 2026-07-13: Codex既定3枠を `codex-native/claude/grok` の3ベンダーへ対称化し、安全な外部Claude runner・課金ガード・レビュー残件の文書修正を実装、テスト83件＋実機E2E → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: quorumレビュー推奨修正を適用（`0`/`false`無効化・明示パネル全滅時フロア規定・区切り正規化・サイズ検証）、テスト68件 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: 欠員補完を opus→codex→grok の優先順に一般化＋`QUORUM_NATIVE=fable`（呼びかけ時のみ）を追加、テスト58件。Claude版 `/quorum` も初実走（grok は2回連続実質回答なしで dropped） → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: Codex版 `$quorum` を設計レビューで初実走し、native fan-out・runs保存・judge出力を確認（Grokの実質回答なしをdropped化） → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: 既定パネルを3枠 opus/codex/grok に変更（codex 既定参加へ反転）＋ `QUORUM_PANEL` 明示増員を追加、テスト53件 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: Codex版 `$quorum`、T1連携、再帰防止、両環境インストールと45件のAPI不要テストを実装 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-10: codex パネリストを GPT-5.6 Sol に明示固定（`-m gpt-5.6-sol`）。GPT-5.6 一般公開（07-09）＋codex CLI 0.144.1 更新に追随。config 依存の暗黙 pin（未指定だと 0.144 既定=gpt-5.3-codex に化ける）を排除 → [checkpoint](docs/checkpoints/2026-07-10.md)
- 2026-07-10: 別PC（pull 専用機）作業分2件を再実装（run_grok.sh API 既定 grok-4.5 化／IMPROVEMENTS: codex 連続欠席の検知ギャップ）。取り込み運用は research リポ NOTES.md「pull 専用の別PCからの変更の取り込み」参照
- 2026-07-06: Fable 5 再定義・実走検証・実験（匿名化/文体正規化）・常時トリアージ導入の全面改修 → [checkpoint](docs/checkpoints/2026-07-06.md)

## ブロッカー

なし

> 改善ネタは IMPROVEMENTS.md（使用中に気づいた汎用ハーネスとしての弱点）、進捗はこのファイル＋checkpoint、という分担。
