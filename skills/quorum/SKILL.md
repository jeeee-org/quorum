---
name: quorum
description: 高難度・高ステークスの問いを「独立並列 → judge → fuse」で解く融合スキル。同じプロンプトを複数の回答者（Opus 4.8 サブエージェント／codex=GPT-5.5／gemini／grok）に互いにブラインドで投げ、Opus 4.8 が合意・矛盾・盲点まで構造的に突き合わせて最終回答を書く。クイック/低リスクな問いには使わない（コストN倍・最遅パネリストに律速）。
---

# Quorum（独立並列 → judge → fuse）

このスキルは **fan-out → judge → fuse** パイプラインで1問の回答品質を上げる。
**メインの Opus 4.8 セッションがオーケストレーター兼 judge を兼ねる**（順序は反転不可：パネリストは judge を spawn できない）。

> 設計思想は `references/panel.md`（なぜ独立か）と `references/judge_rubric.md`（どう統合するか）を参照。
> 巨大MD／ライブ状態を扱う時の入力整形は `references/context-packing.md`（fan-out 前の「司書」手順）。
>
> **スクリプト/参照ファイルの場所**: 既定のインストール先は `~/.claude/skills/quorum/`。
> 以下の `scripts/...` `references/...` は `~/.claude/skills/quorum/` 配下を指す（CWD に依存しない絶対パスで叩くこと）。

## 実行手順

### 0. コスト/ステークス・ガード（fan-out 前に必ず）
- **ステークス判定**: 問いが低リスク／単純なら、**融合せず単一モデルで答える**（または `/quorum-opus` を案内）。融合は高ステークス・複雑な問い限定。コストは概ね**パネリスト数 × トークン**。
- **目標パネル数**: `QUORUM_PANEL_SIZE`（既定 4）。**理想は grok / opus / codex / gemini の4枠**だが、使えない枠（PCに codex が無い・gemini が頼りない等）は**独立 opus 実行で補完**して目標数を満たす（detect_panel.sh が自動でバックフィルした multiset を出力する）。distinct な利用可能バックエンドが目標を**超える**場合のみトリムし、**無音で切り捨てない** — 落としたバックエンドを必ず明示する。トリム優先順位は「設問ドメイン適合 > 多様性（別系統モデル）> 同系の追加実行（=opus 補完分）」。
- **時間上限**: 各外部パネリストは `QUORUM_TIMEOUT` 秒（既定 300）で自動打ち切り（run スクリプトに内蔵）。打ち切られたパネリストは欠席扱いで続行。

### 1. パネルを決める
- 明示指定（例「`opus-grok` で」）があればそれに従う。
- なければ `~/.claude/skills/quorum/scripts/detect_panel.sh` を Bash で実行する。**出力は目標数（`QUORUM_PANEL_SIZE` 既定 4）まで opus で補完済みの multiset**（1行=1パネリスト、同じ名前が複数行=その回数だけ独立実行）。
- **出力の各行をそのままパネリストにする**：`opus` 行は Task で独立サブエージェントを1体ずつ spawn（複数あれば opus#1 / opus#2 … と区別して監査証跡に明示）。非 opus 行は `scripts/run_<name>.sh` を呼ぶ。
- detect の出力行数が `QUORUM_PANEL_SIZE` を超える場合（distinct バックエンドが目標超）だけ、step 0 の優先順位でトリムし**落としたものを明示**する。

**バックエンドは規約ベース（汎用）**。detect_panel.sh は `scripts/run_<name>.sh` を自動ディスカバリし、各スクリプトの `--check`（exit 0=可用）で取捨する。出力された `<name>` ごとに `scripts/run_<name>.sh` を呼べばよい（個別の分岐を SKILL に書かない）。**「使える枠は本物のモデル・足りない枠は opus」**という補完は detect_panel.sh が行うので、SKILL 側は出力を信じて回すだけでよい。

現状検出され得るバックエンド（例）：
| backend | 実体 | 投げ方 |
|---|---|---|
| `opus` | Opus 4.8 | Task でサブエージェントを spawn（web検索・bash 込み）。スクリプトではなく特別扱い |
| `codex` | GPT-5.5 | `scripts/run_codex.sh` に プロンプトを stdin |
| `gemini` | Gemini | `scripts/run_gemini.sh`（既定除外・`QUORUM_ENABLE_GEMINI=1` で可用） |
| `grok` | Grok (xAI) | `scripts/run_grok.sh`（grok CLI=サブスク枠 or `XAI_API_KEY`） |

新しいモデルを足すには、規約に従う `run_<name>.sh`（`--check` で可用判定＋stdin→stdout）を置くだけ。detect も fan-out も無改修で対応する。

### 2. fan-out（独立・並列・ブラインド）
- **問いが巨大MD／複数ファイル／ライブ状態に依存する場合は、fan-out の前に `references/context-packing.md` の「司書」手順で `$PROMPT` を自己完結化する**（パネリスト＝特に外部CLIはリポも `~/.claude` も見えないので、渡すテキストの質が回答の上限になる）。材料が小さい問いはこの手順を飛ばして素の問いを渡す。
- **全パネリストに完全に同じプロンプト（ユーザーの問い／pack 済みなら同一 pack）をそのまま渡す**。言い換え・役割付与（「批評家として」等）はしない。多様性は演出せず独立実行から収穫する。
- `opus` パネリストは Task でサブエージェントとして並列起動。各自に web 検索と bash を使って独立に調べさせる。
- 非 opus の各バックエンド `<name>` は Bash で `scripts/run_<name>.sh` を実行し、標準出力（回答全文）を回収する。プロンプトは stdin で渡す：
  - 例: `printf '%s' "$PROMPT" | bash ~/.claude/skills/quorum/scripts/run_<name>.sh`
- パネリストどうしの中間結果は**互いに見せない**。

### 3. judge（突き合わせ）
回収した全回答を、メイン Opus が `~/.claude/skills/quorum/references/judge_rubric.md` に沿って構造化分析する。最低限：
- **Consensus**（合意点）
- **Contradictions**（食い違い。どちらがより確からしいか根拠つきで判定）
- **Partial coverage**（一部しか触れていない論点）
- **Unique insights**（単独パネリストだけが出した洞察）
- **Blind spots**（全員が見落としている可能性のある点）
- **継ぎ目チェック表**（judge_rubric の全カテゴリを1行も省略せず点検。被覆/部分/欠落/N-A を判定）

各項目には**どのパネリスト由来か**を明示する。

### 4. fuse（最終回答）
上の分析を根拠に、メイン Opus が最終回答を書く。**出力形式は `--output-format` で切替**（既定 `text`）。

**`text`（既定・人間向け）**
1. **最終回答**（本体・トップに置く）
2. **監査証跡（audit trail）**：上記の構造化分析を畳んで添える（どの回答者が何を言ったか追える形で）。
   - **継ぎ目チェック表は常設**（省略不可）。🕳️ 欠落カテゴリがあれば、その補足を最終回答にも反映する。

**`json`（機械可読）**
- `~/.claude/skills/quorum/references/output_schema.json` に**準拠した単一の ```json ブロックだけ**を出力する（前後に散文を付けない）。
- `final_answer` に最終回答（markdown 可）、`seam_check` に継ぎ目カテゴリ全件、`panel.dropped` に除外/timeout したバックエンドを必ず入れる。

## 注意
- コストは概ね単一回答の **N倍トークン**、レイテンシは**最も遅いパネリストに律速**。高ステークスの問いに限定して使う。
- 外部CLIの認証は「アカウント/OAuth ログイン＝サブスク枠」か「APIキー＝従量」かで課金が変わる。`grok` は xAI APIキー（従量）前提。詳細は README 参照。
- パネリストが落ちた／空応答なら、そのパネリストを除いて続行する（最低1回答＋judge は維持）。
