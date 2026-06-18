# quorum 改善案メモ

quorum スキルを使いながら気づいた、汎用融合ハーネスとしての改善ネタを溜める場所。SKILL.md の「改善案の記録（運用ルール）」に従って追記する。

このファイルが**正本**。install.sh が `~/.claude/skills/quorum/IMPROVEMENTS.md` をここへの symlink にするので、実行時の追記はそのまま git 管理下のこのファイルへ書き込まれ、再インストール（install.sh の `rm -rf`）でも消えない。溜まったら `git add IMPROVEMENTS.md && git commit && git push` で共有し、他PCは `git pull` で受け取る。

- 1件 = 日付＋状況（どの問い / どのパネル構成 / どの出力形式で使った時か）＋気づき（judge/fuse/panel/context-packing/バックエンドのどこが弱いか）＋できれば改善案の方向性（rubric 追加 / 新 backend / 既定値変更 / context-packing 追記 等）。
- 単発のタスク状況や特定 PJ のドメイン知見はここに書かない（前者は PROGRESS.md/checkpoint、後者は PJ の NOTES.md へ）。**汎用融合ハーネスとしての改善ネタだけ**を残す。
- 同種の気づきは新規行を量産せず既存項目に統合する（再発頻度・追加事例を足す）。

---

<!-- ここから下に追記。新しいものを上に積む。 -->
