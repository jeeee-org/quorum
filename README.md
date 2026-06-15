# fusion-forge

複数モデルから1つの良い回答を「鍛造」する、自作の **Claude Code 融合スキル**。
同じ問いを**互いにブラインドで独立並列**に複数の回答者へ投げ、**Opus 4.8 が合意・矛盾・盲点まで突き合わせて**最終回答を書く（fan-out → judge → fuse）。

> [`duolahypercho/fusion-fable`](https://github.com/duolahypercho/fusion-fable) の設計思想を参考に、**一から自作・Grok 対応を追加**したもの。

## いまの状態

構造・ロジックは一通り完成。

- **opus**（自己融合）: 外部CLI不要で動く。追加課金ゼロ。
- **codex（GPT-5.5）**: ✅ 実機検証済み（codex-cli 0.130.0、`--output-last-message` で最終回答のみ取得・end-to-end 動作確認）。
- **gemini**: ✅ スクリプトは動作確認済み（gemini-cli 0.46.0）だが、**既定パネルからは除外**（後述）。`FUSION_ENABLE_GEMINI=1` でいつでも有効化できる。
- **grok**: Grok Build CLI（`grok` 0.2.51）導入済み。`run_grok.sh` は **CLI（サブスク枠）優先・API フォールバック**の2方式対応。要 `grok login`（OAuth）。

### gemini を既定から外している理由

無料枠（Google ログイン＝Code Assist 個人）で検証したところ：
- `gemini-2.5-pro` は **容量枯渇**で実用にならない（flash は動くが quota がタイト）。
- 無料枠は**データが製品改善＝学習に利用され得る**（Claude/Codex の「学習オフ」方針と不整合）。

→ 常用するなら **有料 API キー（billing 有効化＝学習不使用・容量確保）** を推奨。
有効化方法：
```bash
export FUSION_ENABLE_GEMINI=1          # 既定パネルに gemini を復帰
# 有料キーを使う場合（学習不使用）:
export GEMINI_API_KEY=...              # AI Studio で billing 有効化したキー
# 無料のまま試すなら軽量モデルを既定に:
export GEMINI_MODEL=gemini-2.5-flash
```

## 構成

```
fusion-forge/
├── install.sh                  # ~/.claude へ配置
├── skills/fusion/
│   ├── SKILL.md                # 中核の台本（メイン Opus への手順書）
│   ├── scripts/
│   │   ├── detect_panel.sh     # 利用可能なバックエンドを検出
│   │   ├── run_codex.sh        # GPT-5.5（codex CLI）
│   │   ├── run_gemini.sh       # Gemini（gemini CLI）
│   │   └── run_grok.sh         # Grok（grok CLI=サブスク枠 / xAI API フォールバック）
│   └── references/
│       ├── panel.md            # なぜ独立並列か
│       └── judge_rubric.md     # どう突き合わせるか
└── commands/
    ├── fusion.md               # /fusion（自動パネル選択）
    └── fusion-opus.md          # /fusion-opus（Opus 自己融合・追加課金ゼロ）
```

## パネリストと課金（重要）

| backend | 実体 | 投げ方 | 認証 / 課金 |
|---|---|---|---|
| `opus` | Opus 4.8 | Claude Code サブエージェント | **Claude Code のプラン内**（追加課金なし） |
| `codex` | GPT-5.5 | `codex exec` | ChatGPT ログイン=サブスク枠 / APIキー=従量 |
| `gemini` | Gemini | `gemini -p` | Google ログイン=無料枠 / APIキー=従量 |
| `grok` | Grok (xAI) | `grok -p`（CLI）/ xAI API（curl） | **サブスク枠**（SuperGrok/X Premium+・`grok login`）or APIキー=従量 |

- 「sh で叩く＝サブスク不可」は誤り。**codex / gemini / grok はいずれもログイン方式ならサブスク枠で動く**（grok は公式 Grok Build CLI 経由）。
- API キー方式（`OPENAI_API_KEY` / `GEMINI_API_KEY` / `XAI_API_KEY`）にすると従量課金になる。
- コストは概ね単一回答の **N倍**、レイテンシは**最遅パネリストに律速**。高ステークスの問いに限定して使う。

## インストール

```bash
cd ~/Develop/skills/fusion-forge
./install.sh                 # ~/.claude/skills と ~/.claude/commands へ
# 別ディレクトリなら: CLAUDE_CONFIG_DIR=/path/.claude ./install.sh
```
完了後、Claude Code を再起動するか `/reload-skills`。

## 使い方

- 自然言語: 「fusion で次の問いを解いて: …」
- スラッシュ: `/fusion <問い>`（自動でパネル選択） / `/fusion-opus <問い>`（外部CLI不要）

## Grok を使うとき

**推奨：サブスク枠（Grok Build CLI）**
```bash
curl -fsSL https://x.ai/cli/install.sh | bash   # 導入（済）
grok login                                       # ブラウザで SuperGrok/X Premium+ サインイン
# 学習オフ: grok.com の Settings > Data で「Improve the model」をオフ
```

**または API キー（従量課金フォールバック）**
```bash
export XAI_API_KEY=xai-...
export GROK_MODEL=grok-4    # 必要ならモデル上書き（最新を確認）
```
`run_grok.sh` は `grok` CLI があればそちらを優先し、無ければ API を使う。

## チューニング用の環境変数

| 変数 | 既定 | 効果 |
|---|---|---|
| `FUSION_MAX_PANELISTS` | 4 | パネリスト数の上限（コスト上限ガード）。超過分は明示して除外（無音切り捨てなし） |
| `FUSION_TIMEOUT` | 300 | 各外部パネリストの実行時間上限（秒）。run スクリプトに内蔵、超過は欠席扱い |
| `FUSION_ENABLE_GEMINI` | (未設定) | gemini を既定パネルに復帰させる |
| `GROK_MODEL` / `GEMINI_MODEL` | - | 各モデルIDの明示（公平比較用） |

判定は「合議≠多数決」。judge は**根拠の質・ツール接地・ドメイン適合**で重みづけし、ブランドや声の大きさ・単純多数決には流されない（`references/judge_rubric.md`）。

## ビルド時に固めること（TODO）

- [x] `codex exec` の最終回答のみ取得（`-o/--output-last-message`）→ 検証済み。
- [x] `gemini -p`（非対話）動作確認（gemini-cli 0.46.0）。※無料枠の制約により既定では無効化。
- [ ] gemini を有料キーで本運用する場合の動作確認（学習不使用・pro 容量）。
- [ ] Grok の最新モデル名（`GROK_MODEL` 既定値）と Live Search の要否（`XAI_API_KEY` 設定後）。
- [ ] 空応答・タイムアウト時のフォールバック挙動の実機確認（gemini/grok）。
- [ ] Claude Code 上で `/fusion-opus` → `/fusion` の実走確認。
