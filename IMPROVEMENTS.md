# quorum 改善案メモ

quorum スキルを使いながら気づいた、汎用融合ハーネスとしての改善ネタを溜める場所。SKILL.md の「改善案の記録（運用ルール）」に従って追記する。

このファイルが**正本**。install.sh が `~/.claude/skills/quorum/IMPROVEMENTS.md` をここへの symlink にするので、実行時の追記はそのまま git 管理下のこのファイルへ書き込まれ、再インストール（install.sh の `rm -rf`）でも消えない。溜まったら `git add IMPROVEMENTS.md && git commit && git push` で共有し、他PCは `git pull` で受け取る。

- 1件 = 日付＋状況（どの問い / どのパネル構成 / どの出力形式で使った時か）＋気づき（judge/fuse/panel/context-packing/バックエンドのどこが弱いか）＋できれば改善案の方向性（rubric 追加 / 新 backend / 既定値変更 / context-packing 追記 等）。
- 単発のタスク状況や特定 PJ のドメイン知見はここに書かない（前者は PROGRESS.md/checkpoint、後者は PJ の NOTES.md へ）。**汎用融合ハーネスとしての改善ネタだけ**を残す。
- 同種の気づきは新規行を量産せず既存項目に統合する（再発頻度・追加事例を足す）。

---

<!-- ここから下に追記。新しいものを上に積む。 -->

## 2026-07-06 — Fable 5 時代の再定義と Workflow 移植の方向性
- **状況**: Fable 5 リリース直後のセッションで PJ 全体レビューを実施。Claude Code 公式のマルチエージェント機能（Dynamic Workflows / ultracode、2026-05 発表）との比較も行った。
- **気づき**:
  - 「Fable 級を合成する」という当初の物語（fusion-fable）は、本物の Fable 5 が使える今、役目を終えた。残る価値は (a) **異種ベンダー混合による系統的盲点の相殺**（単一ベンダーの N 体実行では原理的に得られない）と (b) **judge ルーブリック資産**（継ぎ目チェック表・重みづけ規律）。→ README/SKILL/panel.md を「judge=セッション最強モデル・パネル=安価 Claude＋異種ベンダー」の構図に書き換え済み。
  - opus 自己融合（並列 spawn・タイムアウト・構造化回収・resume）は、公式 **Workflow（Dynamic Workflows）機構に乗せた方が決定論的**。器の部分は公式に追いつかれており、自前実装を維持する理由が薄い。
- **改善案**:
  - `/quorum-opus` と opus 補完枠の fan-out を Workflow スクリプト化するハイブリッド構成（外部CLI＝grok 等は従来どおり Bash 経由で並走、judge は最後にメインセッション）。schema 指定で構造化回収でき、失敗時 resume も効く。
  - judge 事前コミット差分（precommit.md → 監査証跡の差分1行）が溜まったら、「フルパネルが単発に勝つ問いの型」を SKILL step 0 の分岐に経験則として反映する。パネルが結論を動かさない実行が続く型は単発へ格下げ。
