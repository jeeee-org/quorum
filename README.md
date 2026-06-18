# quorum

複数モデルから1つの良い回答を「鍛造」する、自作の **Claude Code 融合スキル**。
同じ問いを**互いにブラインドで独立並列**に複数の回答者へ投げ、**Opus 4.8 が合意・矛盾・盲点まで突き合わせて**最終回答を書く（fan-out → judge → fuse）。

> [`duolahypercho/fusion-fable`](https://github.com/duolahypercho/fusion-fable) の設計思想を参考に、**一から自作・Grok 対応を追加**したもの。

## いまの状態

構造・ロジックは一通り完成。

- **opus**（自己融合）: 外部CLI不要で動く。追加課金ゼロ。
- **codex（GPT-5.5）**: ✅ 実機検証済み（codex-cli 0.130.0、`--output-last-message` で最終回答のみ取得・end-to-end 動作確認）。ただし**既定パネルからは除外**（コスト抑制のため）。`QUORUM_ENABLE_CODEX=1` でいつでも有効化できる。
- **gemini**: ✅ APIキー経路を実キー E2E 済（2026-06-17、flash）だが、**既定パネルからは除外**（後述）。`QUORUM_ENABLE_GEMINI=1` でいつでも有効化できる。`run_gemini.sh` は **API キー（`GEMINI_API_KEY`/`GOOGLE_API_KEY`）を本線・gemini CLI は補助**の2方式（grok の CLI 優先とは逆。理由は下記）。
- **grok**: Grok Build CLI（`grok` 0.2.51）導入済み。`run_grok.sh` は **CLI（サブスク枠）優先・API フォールバック**の2方式対応。要 `grok login`（OAuth）。

### gemini を既定から外している理由

無料枠（Google ログイン＝Code Assist 個人 / AI Studio APIキー無料枠）で検証したところ：
- `gemini-2.5-pro` は **無料枠では実用にならない**。AI Studio APIキー無料枠では `gemini-2.5-pro` が `limit: 0`（=構造的に不可。「retry in 30s」表示は誤解を招くが、待っても無料では通らない。要・課金アカウント紐付け）。**flash は無料枠で動作**（2026-06-17 実キー E2E 確認済）。∴ **無料枠キーの既定は `gemini-2.5-flash`**（`run_gemini.sh` の既定もこれに合わせた）。
- 無料枠は**データが製品改善＝学習に利用され得る**（Claude/Codex の「学習オフ」方針と不整合）。

→ 常用するなら **有料 API キー（billing 有効化＝学習不使用・容量確保）** を推奨。

> ⚠️ **2026-06-18 に gemini CLI の個人向け（無料/Pro/Ultra）は廃止 → Antigravity CLI `agy`（Go・クローズド）へ**。本スクリプトが grok と逆に **API キーを本線**にしているのはこのため：
> - 素の **モデル API（API キー）は別系統で影響を受けない**（公式明言）。`agy` の登場・gemini CLI の廃止に左右されない。
> - 後継 `agy` は **headless 未成熟**で、いまパネリストに使えない：`agy -p` が非TTY（パイプ/サブプロセス）で stdout を取りこぼす（[#76](https://github.com/google-antigravity/antigravity-cli/issues/76)）／APIキー認証が未対応で基本ブラウザログイン（[#78](https://github.com/google-antigravity/antigravity-cli/issues/78)）。quorum はパネリストをサブプロセス起動するので両方を踏む。
> - ∴ `agy` は **#76/#78 が解消したら**「サブスク枠で叩くコストゼロCLI」として再評価（その時は grok と対称になる）。それまでは API キー従量が本線。
> - 📌 **将来やるかも（低優先）**：headless 以外の経路＝**pty/対話駆動**（`expect`/`pexpect` で TTY を噛ませて応答を抜く、または agy の transcript ファイルを読む）。サブスク枠を使い倒したい強い動機が出た時の選択肢。エージェントTUIの出力整形・完了判定・初回ウィザード対応で**脆くなる前提**。当面は採用しない。

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
│       ├── judge_rubric.md     # どう突き合わせるか
│       └── context-packing.md  # fan-out 前の「司書」手順（巨大MD/ライブ状態を絞って渡す）
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
  - codex（OpenAI）: `codex login`（`QUORUM_ENABLE_CODEX=1` で有効化）
  - grok（xAI/SuperGrok）: `curl -fsSL https://x.ai/cli/install.sh | bash` → `grok login`
  - gemini（任意）: `npm i -g @google/gemini-cli` → ログイン（`QUORUM_ENABLE_GEMINI=1` で有効化）
- 確認: `~/.claude/skills/quorum/scripts/detect_panel.sh` で使えるパネルが出るか

opus パネリストは Claude Code に内蔵のため追加導入は不要。**認証トークンはマシンごと**で、リポジトリには含まれない（`.gitignore` 済み）。

**更新を取り込む時も同じ**：`git pull` の後に `./install.sh` を再実行する（install.sh は配置先を `rm -rf` して入れ直す）。

**改善メモ（`IMPROVEMENTS.md`）はマシンごとに symlink を張り直す**：正本はリポ root の `IMPROVEMENTS.md`（git 管理）で、install.sh が `~/.claude/skills/quorum/IMPROVEMENTS.md` をそのマシンのリポパスへの symlink にする。だから SKILL の「改善案の記録」運用で追記したメモは git 管理下の正本へ書き込まれ、再インストールの `rm -rf` でも消えない。symlink 自体はリポの絶対パスを指すマシン固有のものなので、**コミットには含まれず、各PCで install.sh が張り直す**。溜まったメモは `git add IMPROVEMENTS.md && git commit && git push` で共有し、他PCは `git pull` で受け取る。

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
| `QUORUM_PANEL_SIZE` | 4 | **目標パネル数**。既定パネルは grok/opus + opus 補完の4枠（**codex・gemini は既定で外し opus 補完**、入れるのは `QUORUM_ENABLE_CODEX=1` / `QUORUM_ENABLE_GEMINI=1` 時のみ）。使えない枠も**独立 opus 実行で補完**（detect_panel.sh が自動バックフィル）。distinct が目標超の時だけトリムし明示（無音切り捨てなし） |
| `QUORUM_TIMEOUT` | 300 | 各外部パネリストの実行時間上限（秒）。run スクリプトに内蔵、超過は欠席扱い |
| `QUORUM_ENABLE_CODEX` | (未設定) | codex を既定パネルに復帰させる（既定は除外、独立 opus 実行で補完） |
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
