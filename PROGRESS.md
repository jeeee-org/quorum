# PROGRESS

## 現在地

Claude Code / Codex 両ホスト対応が完了し、運用フェーズ。Claudeは opus、Codexは codex-native を同族補完枠にし、共通の外部バックエンド・judge rubric・監査証跡を使う。CodexのT1分類は `claude-rules` から `$quorum` へ接続済み。

2026-08-19 に利用側の改善メモ1件（2巡目レビューの型）を取り込み、`context-packing.md` に「2巡目は『前巡の指摘が閉じたか』を問う形に組む」節を新設した。前日 08-18 には改善メモ9件（08-13〜08-18）を実装済み。テストは230件。grok のメタ応答は**原因が plan mode と特定**され `--no-plan` / `--no-subagents` を渡す（緩和であって決定打ではない）。当PCへは配布済みだが**利用側PCは未配布**（`git pull && ./install.sh` 待ち）。残タスクは gemini 関連3件、データ待ち1件、判断保留の refuter 工程、未着手1件。

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

- 2026-08-19: 利用側の改善メモ1件を取り込み実装。`references/context-packing.md` に **2巡目（再レビュー）pack の組み方**を新設（①指摘は ID つき本文で貼る ②回答は「指摘ごとの判定／新しい欠陥／総合判定」の3分割 ③前巡の judge を渡す枠と渡さない枠を混ぜない＝既定は**指摘リストのみ**でアンカリングを避ける）＋テンプレ欄・両SKILLからの参照・`--expect` への接続。テスト230件 → [checkpoint](docs/checkpoints/2026-08-19.md)
- 2026-08-18: 利用側の改善メモ9件（08-13〜08-18）を取り込み実装。①grok のメタ応答の原因が **plan mode** と判明し `--no-plan` / `--no-subagents` を probe 付きで付与（モデルは CLI 既定に委ね grok-4.6 へ追随、API 経路も更新）②`check_answer.sh` に内容ベース判定（`--expect` / `plan_only`）と `truncated_suspect`（exit 4）③`install.sh --no-codex`④`run_*.sh --version` 規約と `detect_panel.sh` の版変化通知⑤panel.md に「書き込み可否と作業場所」「実読2体は指示を分ける」、context-packing に「壊しうる検査基盤」。grok/codex CLI も更新（1.0.5 / 0.147.0）。テスト230件 → [checkpoint](docs/checkpoints/2026-08-18.md)
- 2026-08-13: 改善メモ3件を取り込み grok のメタ応答対策（閾値未満の投げ直し／連続 invalid 警告／ネイティブ枠での補完と縮退記録）。テスト181件 → [checkpoint](docs/checkpoints/2026-08-13.md)
- 2026-08-09: `IMPROVEMENTS.md` を古い順・末尾追記の規約に揃え、`test_improvements_order.sh` で機械検査（利用側 mirror の全22項目 conflict の原因）。テスト162件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: 利用側メモをトリアージし、空応答時に stderr 先頭行を `invalid_response:empty:<先頭行>` へ転記（無音死の判別）。テスト153件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: codex collab の恒久無効化／opt-in backend の連続欠席警告／`checks_summary.sh` で誤棄却レビューを1コマンド化。テスト146件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: rubric に継ぎ目カテゴリ3件と judge 自身が確かめる節、context-packing に「pack は司書の盲点を継承する」節を追加。テスト125件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: grok の大型pack欠席を解消（argv → `--prompt-file`、248KB 実機E2E）。run_*.sh 規約に「prompt を argv に展開しない」。テスト121件 → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-08-09: fable の費用表現を「都度課金」→「サブスク枠の使用量」へ是正。dangling だった IMPROVEMENTS.md の symlink を復旧し改善メモ15件を取り込み → [checkpoint](docs/checkpoints/2026-08-09.md)
- 2026-07-15: `GROK_MODEL` 既定 `grok-4.5` が現行フラッグシップと一致することを確認し、変更不要と判定
- 2026-07-15: 回収後の軽量検査 `check_answer.sh` とパネリスト専用ガード `panelist_guard.txt` を実装。テスト105件 → [checkpoint](docs/checkpoints/2026-07-15.md)
- 2026-07-15: 外部パネル参加を全て**既定オフ（opt-in）**へ統一。既定は opus×3（Codex は codex-native×3）。テスト91件 → [checkpoint](docs/checkpoints/2026-07-15.md)
- 2026-07-15: 別PC（push不可）の IMPROVEMENTS 2件を当PCへ取り込み → [checkpoint](docs/checkpoints/2026-07-15.md)
- 2026-07-13: Codex 既定3枠を3ベンダーへ対称化＋安全な外部Claude runner・課金ガード。テスト83件 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: レビュー推奨修正を適用（`0`/`false` 無効化・パネル全滅時のフロア規定・サイズ検証）。テスト68件 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: 欠員補完を opus→codex→grok に一般化＋`QUORUM_NATIVE=fable`。Claude版 `/quorum` 初実走。テスト58件 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: Codex版 `$quorum` を初実走し native fan-out・runs保存・judge出力を確認 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: 既定パネルを opus/codex/grok の3枠に変更＋`QUORUM_PANEL` 明示増員。テスト53件 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-13: Codex版 `$quorum`、T1連携、再帰防止、両環境インストールと45件のテストを実装 → [checkpoint](docs/checkpoints/2026-07-13.md)
- 2026-07-10: codex パネリストを GPT-5.6 Sol に明示固定し、config 依存の暗黙 pin を排除 → [checkpoint](docs/checkpoints/2026-07-10.md)
- 2026-07-10: 別PC（pull 専用機）作業分2件を再実装（`run_grok.sh` の API 既定／codex 連続欠席の検知ギャップ）
- 2026-07-06: Fable 5 再定義・実走検証・実験（匿名化/文体正規化）・常時トリアージ導入の全面改修 → [checkpoint](docs/checkpoints/2026-07-06.md)

## ブロッカー

なし

> 改善ネタは IMPROVEMENTS.md（使用中に気づいた汎用ハーネスとしての弱点）、進捗はこのファイル＋checkpoint、という分担。
