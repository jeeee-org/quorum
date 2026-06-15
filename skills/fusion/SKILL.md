---
name: fusion
description: 高難度・高ステークスの問いを「独立並列 → judge → fuse」で解く融合スキル。同じプロンプトを複数の回答者（Opus 4.8 サブエージェント／codex=GPT-5.5／gemini／grok）に互いにブラインドで投げ、Opus 4.8 が合意・矛盾・盲点まで構造的に突き合わせて最終回答を書く。クイック/低リスクな問いには使わない（コストN倍・最遅パネリストに律速）。
---

# Fusion（独立並列 → judge → fuse）

このスキルは **fan-out → judge → fuse** パイプラインで1問の回答品質を上げる。
**メインの Opus 4.8 セッションがオーケストレーター兼 judge を兼ねる**（順序は反転不可：パネリストは judge を spawn できない）。

> 設計思想は `references/panel.md`（なぜ独立か）と `references/judge_rubric.md`（どう統合するか）を参照。
>
> **スクリプト/参照ファイルの場所**: 既定のインストール先は `~/.claude/skills/fusion/`。
> 以下の `scripts/...` `references/...` は `~/.claude/skills/fusion/` 配下を指す（CWD に依存しない絶対パスで叩くこと）。

## 実行手順

### 1. パネルを決める
- 明示指定（例「`opus-grok` で」）があればそれに従う。
- なければ `~/.claude/skills/fusion/scripts/detect_panel.sh` を Bash で実行し、**利用可能なバックエンドを全部**パネリストに使う。
- **最低2パネリスト**にする。`opus` しか無い場合は **Opus 4.8 を2回独立実行**する（同一モデルの2回でも統合すれば単発を上回る、が本スキルの前提）。

検出される可能性のあるバックエンド：
| backend | 実体 | 投げ方 |
|---|---|---|
| `opus` | Opus 4.8 | Task でサブエージェントを spawn（web検索・bash 込み） |
| `codex` | GPT-5.5 | `scripts/run_codex.sh` に プロンプトを stdin で渡す |
| `gemini` | Gemini | `scripts/run_gemini.sh` に プロンプトを stdin で渡す |
| `grok` | Grok (xAI) | `scripts/run_grok.sh` に プロンプトを stdin で渡す（要 `XAI_API_KEY`） |

### 2. fan-out（独立・並列・ブラインド）
- **全パネリストに完全に同じプロンプト（ユーザーの問い）をそのまま渡す**。言い換え・役割付与（「批評家として」等）はしない。多様性は演出せず独立実行から収穫する。
- `opus` パネリストは Task でサブエージェントとして並列起動。各自に web 検索と bash を使って独立に調べさせる。
- 外部モデル（`codex`/`gemini`/`grok`）は Bash で対応スクリプトを実行し、標準出力（回答全文）を回収する。プロンプトは stdin で渡す：
  - 例: `printf '%s' "$PROMPT" | bash ~/.claude/skills/fusion/scripts/run_grok.sh`
- パネリストどうしの中間結果は**互いに見せない**。

### 3. judge（突き合わせ）
回収した全回答を、メイン Opus が `~/.claude/skills/fusion/references/judge_rubric.md` に沿って構造化分析する。最低限：
- **Consensus**（合意点）
- **Contradictions**（食い違い。どちらがより確からしいか根拠つきで判定）
- **Partial coverage**（一部しか触れていない論点）
- **Unique insights**（単独パネリストだけが出した洞察）
- **Blind spots**（全員が見落としている可能性のある点）

各項目には**どのパネリスト由来か**を明示する。

### 4. fuse（最終回答）
上の分析を根拠に、メイン Opus が最終回答を書く。出力形式：

1. **最終回答**（本体・トップに置く）
2. **監査証跡（audit trail）**：上記の構造化分析を畳んで添える（どの回答者が何を言ったか追える形で）

## 注意
- コストは概ね単一回答の **N倍トークン**、レイテンシは**最も遅いパネリストに律速**。高ステークスの問いに限定して使う。
- 外部CLIの認証は「アカウント/OAuth ログイン＝サブスク枠」か「APIキー＝従量」かで課金が変わる。`grok` は xAI APIキー（従量）前提。詳細は README 参照。
- パネリストが落ちた／空応答なら、そのパネリストを除いて続行する（最低1回答＋judge は維持）。
