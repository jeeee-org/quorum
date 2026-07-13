# quorum PJ固有ルール

## 目的と最大リスク

- Claude Code / Codex をホストに、異種モデルの独立回答を judge が融合する quorum を配布・保守する。
- 最大のリスクは、ホスト固有のサブエージェント機構を混同すること、外部 `codex exec` の再帰発動、認証情報や従量課金を意図せず扱うこと。

## 記録

- `REQUIREMENTS.md` は Claude/Codex 両ホストの機能要件と配布契約を管理する。
- 汎用ハーネスの改善候補は `IMPROVEMENTS.md`、確定した判断と罠は `NOTES.md`、詳細作業ログは日別 checkpoint に記録する。

## Git

- リモートは `https://github.com/jeeee-org/quorum.git`。低リスクの個人リポとして `main` の直接編集と、作業単位の自動 push を許可する。
- コミットは日本語 subject と説明 body を使い、Claude版/Codex版にまたがる変更でも1つの利用者価値ごとにまとめる。

## 実装・検証

- Bash と Markdown を中心とし、JSON処理は Python 標準ライブラリだけで完結させる。
- Claude版とCodex版で scripts/references を共有し、ホスト固有の指示だけを分離する。
- 変更後は `bash tests/run_tests.sh`、`bash -n install.sh skills/quorum/scripts/*.sh tests/*.sh` を実行する。
- Codex版スキルは skill validator でも検証し、インストール試験は一時ディレクトリだけを使う。
