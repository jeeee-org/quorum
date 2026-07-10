# PROGRESS

## 現在地

Fable 5 時代の再定義が完了し、運用フェーズ。judge=セッション最強モデル・パネル=opus＋異種ベンダー（codex/grok 有効）の構成で、常時トリアージ（T0/T1/T2a/T2b）が全PCのグローバル CLAUDE.md 経由で効く状態。

## 次にやること

- [ ] T2a/T2b の初発動時に fable サブエージェントの課金実態を小さく確認（fable_calls.log と請求の突き合わせ）
- [ ] 高ステークス実走のたびに盲/実名判定の差分を観測（フリップが出たら blind 委譲を既定化）
- [ ] README「ビルド時に固めること」の実機確認残（codex/gemini stdin 経路 E2E・curl config 実キー・GROK_MODEL 既定値）
- [ ] （方向性）opus fan-out の Workflow 移植を検討（IMPROVEMENTS.md 2026-07-06 参照）
- [ ] codex 連続欠席の警告実装（N回連続欠席で監査証跡冒頭に表示。IMPROVEMENTS 2026-07-10 参照）

## 完了

- 2026-07-10: 別PC（pull 専用機）作業分2件を再実装（run_grok.sh API 既定 grok-4.5 化／IMPROVEMENTS: codex 連続欠席の検知ギャップ）。取り込み運用は research リポ NOTES.md「pull 専用の別PCからの変更の取り込み」参照
- 2026-07-06: Fable 5 再定義・実走検証・実験（匿名化/文体正規化）・常時トリアージ導入の全面改修 → [checkpoint](docs/checkpoints/2026-07-06.md)

## ブロッカー

なし

> 改善ネタは IMPROVEMENTS.md（使用中に気づいた汎用ハーネスとしての弱点）、進捗はこのファイル＋checkpoint、という分担。
