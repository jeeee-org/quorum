## Codex版 quorum 連携

- `claude-rules` の分類で **T1** となり、ユーザーが実行まで求めている場合は、利用可能な `$quorum` を使う。提案だけで作業を止めない。
- ユーザーが「quorumで」「$quorum」と明示した場合は分類より優先して `$quorum` を使う。
- T0 / T2a / CADENCE では quorum を自動使用しない。T2a はメインCodexによる単独の深い検証、CADENCE は対応フローへ渡す。
- 分類基準はここで再定義しない。正本は `claude-rules` が配置する `triage-rubric.txt` とする。
