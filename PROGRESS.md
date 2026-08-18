# PROGRESS

## 現在地

Claude Code / Codex 両ホスト対応が完了し、運用フェーズ。Claudeは opus、Codexは codex-native を同族補完枠にし、共通の外部バックエンド・judge rubric・監査証跡を使う。CodexのT1分類は `claude-rules` から `$quorum` へ接続済み。

2026-08-18 に、利用側から届いた改善メモ9件（08-13〜08-18）を取り込み実装まで完了した。テストは230件。grok のメタ応答は**原因が plan mode と特定**され、`--no-plan` / `--no-subagents` を渡すようにした（決定打ではなく緩和）。あわせて check_answer に内容ベース判定、install に `--no-codex`、CLI 版の変化通知を追加。当PCへは配布済み（配置先の実物で新判定の発火まで検証済み）だが、**利用側PCは未配布**（`git pull && ./install.sh` 待ち）。残タスクは gemini 関連3件と、実運用データ待ちの1件、判断保留の refuter 工程、未着手1件。

- **grok を「恒久故障」と断定してパネルから外さない**。6 run 連続欠席の後に復帰し、その回で単独でしか出ない高重大度の指摘を4件出した実績がある。外すのではなく毎回検知して補完する（実害は1体ぶんの待ち時間だけ）。疑うのは backend ではなく認証・CLI 版・オプション。
- **外部CLIの `--help` を定期的に読み直す**。grok の不調の原因は CLI 側（plan mode）だったのに、9 run ぶんの試行錯誤がすべてプロンプト側で行われた。`detect_panel.sh` が版の変化を stderr で知らせるので、出たら `--help` を見る。

- **利用側からの持ち込みは `git pull && ./install.sh` で受ける**。`IMPROVEMENTS.md` は install が張る symlink 経由でしか正本に届かないので、リポを移動したら install を回し直す（切れていると実運用の追記が正本に入らない。NOTES.md 参照）。
- **`IMPROVEMENTS.md` は古い順・末尾追記**。並べ替えると全項目 conflict になり、その回の実質的な追記を巻き込んで失う。規約はヘッダ・箇条書き・両SKILLの3箇所にあり、`test_improvements_order.sh` が昇順を機械検査する。
- **パネルの健全性は detect_panel.sh の stderr で分かる**。opt-in 済み backend が3回連続で欠席すると警告が出る＝パネルが静かに同族ネイティブ寄りへ退化しているサイン。
- **`--check` は通るのにメタ応答しか返さない故障は別系統で見る**。`check_answer.sh --backend <name>` の連続 `invalid_response` 警告（既定2回・`invalid.tsv`）。absence.tsv とは別ファイル——`--check` が通る以上そちらは毎回リセットされる。

## 次にやること

- [ ] **「依頼の型 × backend の適合表」を持つか判断する（未着手）**: 重い依頼（ツール実行を伴うレビュー）で特定 backend の優先度を下げる案。`--no-plan` 投入後の実走で欠席が減るかを先に観測してから決める（IMPROVEMENTS 2026-08-11 の②）
- [ ] 実質回答なし検知の第2段（**データ待ち**）: この clone には checks.txt を持つ run が0件で誤棄却の有無を判断できない。運用が溜まったら `scripts/checks_summary.sh` を実行し、閾値付近に実質回答が無ければ run 側の最小バイト数ゲート（欠席扱い）へ格上げする（IMPROVEMENTS 2026-07-13）
- [ ] **refuter 工程を quorum に新設するか判断する（保留）**: 利用側で mustFix 候補への敵対検証を2体・レンズ分け（データ攻め／論理・規範攻め）で回して効果が出ているが、quorum 側には敵対検証の step が無く（step 5 は fable 再judge）、cadence にも定義が無い。新 step の新設は実走の蓄積を見てから（IMPROVEMENTS 2026-08-11）
- [ ] gemini/curl経路の実キーE2Eを確認する
- [ ] gemini APIキーをStandard key→Authorization keyへ移行する（Google公式が2026年9月にStandard key全般を拒否予定と告知。`GEMINI_API_KEY`/`GOOGLE_API_KEY`の環境変数名は不変だが保存済みキー種別の確認が必要。quorumの実装調査は2026-07-15）
- [ ] **Gemini 3.5 Pro を quorum で試す（2026-07-17 リリース予定以降）**: 課金アカウントに支出上限を設定 → 課金キーで `GEMINI_MODEL=<3.5-pro の正式ID>` を generativelanguage API で実キーE2E → 精度/コストを見て既定 `gemini-2.5-flash` からの昇格可否を判断。無料枠キーでは 2.5-pro 同様 `limit:0` になる想定（課金必須）。agy 経路は #78/#76 未解決のため引き続き見送り

## 完了

- 2026-08-18: 利用側の改善メモ9件（08-13〜08-18）を取り込み実装。①grok のメタ応答の原因が **plan mode** と判明し `--no-plan` / `--no-subagents` を probe 付きで付与（モデルは CLI 既定に委ね grok-4.6 へ追随、API 経路も更新）②`check_answer.sh` に内容ベース判定（`--expect` / `plan_only`）と `truncated_suspect`（exit 4）③`install.sh --no-codex`④`run_*.sh --version` 規約と `detect_panel.sh` の版変化通知⑤panel.md に「書き込み可否と作業場所」「実読2体は指示を分ける」、context-packing に「壊しうる検査基盤」。grok/codex CLI も更新（1.0.5 / 0.147.0）。テスト230件 → [checkpoint](docs/checkpoints/2026-08-18.md)
- 2026-08-13: 利用側の改善メモ3件を取り込み、grok のメタ応答対策を実装。①`run_grok.sh` が閾値未満の正常終了を1回だけ投げ直す（`QUORUM_GROK_RETRY`）②`check_answer.sh --backend` で連続 invalid を警告（`--check` は通る型の恒久故障を検出）③両SKILLに「invalid の枠はネイティブ枠で1回補完・縮退を監査証跡へ」④rubric に「証跡の所在 vs 転記」。テスト181件 → [checkpoint](docs/checkpoints/2026-08-13.md)
- 2026-08-09: `IMPROVEMENTS.md` の並びを規約と一致させた（先頭5項目の反転で全項目を古い順に／ヘッダのコメント・箇条書き・**両SKILL**の3箇所へ「末尾追記」規約を明記／`test_improvements_order.sh` で昇順とヘッダ文言を機械検査）。利用側 mirror の pull で全22項目 conflict が起きた原因。テスト162件 → [checkpoint](docs/checkpoints/2026-08-09.md)
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
