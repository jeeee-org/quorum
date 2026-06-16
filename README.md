# quorum

複数モデルから1つの良い回答を「鍛造」する、自作の **Claude Code 融合スキル**。
同じ問いを**互いにブラインドで独立並列**に複数の回答者へ投げ、**Opus 4.8 が合意・矛盾・盲点まで突き合わせて**最終回答を書く（fan-out → judge → fuse）。

> [`duolahypercho/fusion-fable`](https://github.com/duolahypercho/fusion-fable) の設計思想を参考に、**一から自作・Grok 対応を追加**したもの。

## いまの状態

構造・ロジックは一通り完成。

- **opus**（自己融合）: 外部CLI不要で動く。追加課金ゼロ。
- **codex（GPT-5.5）**: ✅ 実機検証済み（codex-cli 0.130.0、`--output-last-message` で最終回答のみ取得・end-to-end 動作確認）。
- **gemini**: ✅ スクリプトは動作確認済み（gemini-cli 0.46.0）だが、**既定パネルからは除外**（後述）。`QUORUM_ENABLE_GEMINI=1` でいつでも有効化できる。`run_gemini.sh` は grok と同じ **CLI（無料枠/サブスク）優先・APIキー（`GEMINI_API_KEY`/`GOOGLE_API_KEY`）従量フォールバック**の2方式対応。
- **grok**: Grok Build CLI（`grok` 0.2.51）導入済み。`run_grok.sh` は **CLI（サブスク枠）優先・API フォールバック**の2方式対応。要 `grok login`（OAuth）。

### gemini を既定から外している理由

無料枠（Google ログイン＝Code Assist 個人）で検証したところ：
- `gemini-2.5-pro` は **容量枯渇**で実用にならない（flash は動くが quota がタイト）。
- 無料枠は**データが製品改善＝学習に利用され得る**（Claude/Codex の「学習オフ」方針と不整合）。

→ 常用するなら **有料 API キー（billing 有効化＝学習不使用・容量確保）** を推奨。

> ⚠️ **2026-06-18 に gemini CLI の個人向け無料枠/サブスクは廃止予定**（→ Antigravity 移行、Antigravity 無料枠は 20 req/日と実質不足）。廃止後は CLI の `--check` が落ち、`run_gemini.sh` は自動で **APIキー従量経路にフォールバック**する。∴ gemini を常用するなら今のうちに `GEMINI_API_KEY` を用意しておくのが素直（grok と同じ従量モデルで設計が揃う）。

有効化方法：
```bash
export QUORUM_ENABLE_GEMINI=1          # 既定パネルに gemini を復帰
# 有料キーを使う場合（学習不使用）:
export GEMINI_API_KEY=...              # AI Studio で billing 有効化したキー
# 無料のまま試すなら軽量モデルを既定に:
export GEMINI_MODEL=gemini-2.5-flash
```

## 構成

```
quorum/
├── install.sh                  # ~/.claude へ配置＋ランチャーを symlink
├── bin/
│   └── quorum-shell            # Claude Code ラッパーランチャー
├── skills/quorum/
│   ├── SKILL.md                # 中核の台本（メイン Opus への手順書）
│   ├── scripts/
│   │   ├── detect_panel.sh     # 利用可能なバックエンドを検出
│   │   ├── run_codex.sh        # GPT-5.5（codex CLI）
│   │   ├── run_gemini.sh       # Gemini（gemini CLI=無料枠/サブスク / Gemini API フォールバック）
│   │   └── run_grok.sh         # Grok（grok CLI=サブスク枠 / xAI API フォールバック）
│   └── references/
│       ├── panel.md            # なぜ独立並列か
│       └── judge_rubric.md     # どう突き合わせるか
└── commands/
    ├── quorum.md               # /quorum（自動パネル選択）
    └── quorum-opus.md          # /quorum-opus（Opus 自己融合・追加課金ゼロ）
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
cd ~/Develop/skills/quorum
./install.sh                 # ~/.claude/skills と ~/.claude/commands へ
# 別ディレクトリなら: CLAUDE_CONFIG_DIR=/path/.claude ./install.sh
```
完了後、Claude Code を再起動するか `/reload-skills`。

`install.sh` は **このリポジトリの内容を各マシンの `~/.claude`・`~/.local/bin` に“展開”する**もの。
配置物（`~/.claude/skills/quorum` 等）は生成物なので Git には入れない。ソースは全部このリポにあるので、別PCでも `clone → install.sh` で同じ状態を再生成できる。`git pull` 後は `./install.sh` を再実行すると最新が反映される。

## 別PCでのセットアップ（移植）

このツールは**リポジトリが唯一の真実**。他PCでは:

```bash
# 1) ソースを取得
git clone https://github.com/jeeee-org/quorum && cd quorum
# 2) そのPCに配置（~/.claude と ~/.local/bin に展開）
./install.sh
# 3) ~/.local/bin が PATH に無ければ通す（例: ~/.zshrc）
#    export PATH="$HOME/.local/bin:$PATH"
```

**各PC固有で別途必要なもの**（秘密情報のため Git には入れない・入れてはいけない）:
- 使いたいモデルCLIの導入と**認証**:
  - codex（OpenAI）: `codex login`
  - grok（xAI/SuperGrok）: `curl -fsSL https://x.ai/cli/install.sh | bash` → `grok login`
  - gemini（任意）: `npm i -g @google/gemini-cli` → ログイン（`QUORUM_ENABLE_GEMINI=1` で有効化）
- 確認: `~/.claude/skills/quorum/scripts/detect_panel.sh` で使えるパネルが出るか

opus パネリストは Claude Code に内蔵のため追加導入は不要。**認証トークンはマシンごと**で、リポジトリには含まれない（`.gitignore` 済み）。

## 使い方

- 自然言語: 「quorum で次の問いを解いて: …」
- スラッシュ: `/quorum <問い>`（自動でパネル選択） / `/quorum-opus <問い>`（外部CLI不要）
- 機械可読出力: `/quorum --output-format json <問い>` → `skills/quorum/references/output_schema.json` 準拠の単一 JSON（最終回答＋監査証跡＋継ぎ目チェックを構造化）。既定は `text`（人間向け）。

## ランチャー（quorum-shell）

作業フォルダを選んで Claude Code を起動するラッパー。**Claude Code は起動フォルダの `CLAUDE.md` を自動で読む**ので、ランチャーは「フォルダ選択・CLAUDE.md 確認・そのフォルダで起動」を一手にする。

```bash
quorum-shell                       # 引数なし→最近使ったフォルダから選択
quorum-shell ~/Develop/foo         # そのフォルダで claude を起動
quorum-shell ~/Develop/foo -- --model opus "まず概要を教えて"   # -- 以降は claude へ
```

- `CLAUDE.md` が無ければ「続行 / 雛形作成 / 中止」を選べる。
- 最近使ったフォルダを記録（`~/.local/share/quorum/recent`）。
- そのセッションでは `/quorum` などのスキルもそのまま使える（グローバル導入のため）。
- **注意**: `cd` でそのフォルダが作業ディレクトリ＝コンテキストになるが、ハードな隔離ではない。強く閉じ込めたいときは `-- --permission-mode <mode>` を渡す。
- **課金**: ランチャーは**対話モードの `claude`** を起動する（`claude -p` ではない）ので Pro/Max のサブスク枠で動く。`-- -p` を渡すとヘッドレス扱い（Agent SDK クレジット消費）になるため警告を出す。`ANTHROPIC_API_KEY` を環境に設定していると対話でも API 従量になる点に注意（設定時は警告）。

## パネリストを足す（規約ベース・無改修で拡張）

新しいモデルを足すのに detect も SKILL も触らない。`skills/quorum/scripts/run_<name>.sh` を**この規約で**置くだけ：

1. `run_<name>.sh --check` … 使えるなら exit 0、ダメなら非0（CLI/キーの有無などを自己判定）
2. `run_<name>.sh`（引数なし）… プロンプトを **stdin** で受け、回答全文を **stdout** へ
3. 任意で `QUORUM_TIMEOUT` を尊重（`command -v timeout` があれば `timeout "${QUORUM_TIMEOUT:-300}"` でラップ）

`detect_panel.sh` が `run_*.sh` を自動ディスカバリして `--check` で取捨し、fan-out は `<name>` をそのまま使う。

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
| `QUORUM_MAX_PANELISTS` | 4 | パネリスト数の上限（コスト上限ガード）。超過分は明示して除外（無音切り捨てなし） |
| `QUORUM_TIMEOUT` | 300 | 各外部パネリストの実行時間上限（秒）。run スクリプトに内蔵、超過は欠席扱い |
| `QUORUM_ENABLE_GEMINI` | (未設定) | gemini を既定パネルに復帰させる |
| `GROK_MODEL` / `GEMINI_MODEL` | - | 各モデルIDの明示（公平比較用） |

判定は「合議≠多数決」。judge は**根拠の質・ツール接地・ドメイン適合**で重みづけし、ブランドや声の大きさ・単純多数決には流されない（`references/judge_rubric.md`）。

## ビルド時に固めること（TODO）

- [x] `codex exec` の最終回答のみ取得（`-o/--output-last-message`）→ 検証済み。
- [x] `gemini -p`（非対話）動作確認（gemini-cli 0.46.0）。※無料枠の制約により既定では無効化。
- [~] gemini を有料キーで本運用：`run_gemini.sh` に APIキー従量経路を実装（grok と同型、`GEMINI_API_KEY`/`GOOGLE_API_KEY`）。`--check`・REST 応答解析（成功/エラー/SAFETY/空）はモック検証済み。**実キーでの end-to-end 動作確認は残**（キー発行後）。
- [ ] Grok の最新モデル名（`GROK_MODEL` 既定値）と Live Search の要否（`XAI_API_KEY` 設定後）。
- [ ] 空応答・タイムアウト時のフォールバック挙動の実機確認（gemini/grok）。
- [ ] Claude Code 上で `/quorum-opus` → `/quorum` の実走確認。
