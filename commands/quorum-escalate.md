---
description: 直近の quorum 実行を Fable で再judge する（パネル再実行なし・T2b エスカレーション）
---

`quorum` スキルの **escalate 手順**（SKILL.md「5. escalate」）を実行してください。

1. 引数に run ディレクトリの指定があればそれを、なければ `~/.local/share/quorum/runs/` の**最新**を対象にする（`ls -1 | tail -1`）。
2. 対象 `$RUN_DIR` の prompt.md・answer_*.md（匿名のまま。mapping.txt は渡さない）・judge.md（あれば）を、**model=fable のサブエージェント**に渡し、`~/.claude/skills/quorum/references/judge_rubric.md` 準拠で再判定＋最終回答を書かせる。
3. 呼び出し前に1行宣言し、`~/.local/share/quorum/fable_calls.log` に「日時<TAB>T2b<TAB>用途一言」を追記する。
4. 最終回答＋「opus judge から何が変わったか」1段落を提示し、fable の再判定結果を `$RUN_DIR/judge_fable.md` に保存する。
5. fable が使えない環境ならその旨を報告して中止する。

引数（任意: run ディレクトリ）: $ARGUMENTS
