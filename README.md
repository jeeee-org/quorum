# quorum

複数モデルから1つの良い回答を「鍛造」する、自作の **Claude Code / Codex 融合スキル**。
同じ問いを**互いにブラインドで独立並列**に複数の回答者へ投げ、**メインセッションのモデル（judge）が合意・矛盾・盲点まで突き合わせて**最終回答を書く（fan-out → judge → fuse）。

> [`duolahypercho/fusion-fable`](https://github.com/duolahypercho/fusion-fable) の設計思想（複数 LLM の融合で一段上の賢さを合成する）を参考に、**一から自作・Grok 対応を追加**したもの。
>
> **Fable 5 登場後の再定義（2026-07）**：「Fable 級を合成する」という当初の物語は本物の Fable 5 が使える今、役目を終えた。残った——むしろ最初から本体だった——価値は、**単一ベンダーでは原理的に消せない系統的盲点への保険**。同一モデルを N 体走らせても全員が同じ場所で転ぶが、別ベンダーのモデルは訓練データも検索経路も癖も違うため、相関しない誤りを相殺できる。∴ **judge にはセッションで使える最強モデルを座らせ、パネルにはホストの独立サブエージェントと異種ベンダーを並べる**。深さは judge、幅はパネルの分担（`references/panel.md`）。

## いまの状態

Claude Code版の構造・ロジックに加え、Codex版のスキル・T1連携・インストールを実装済み。

- **opus**（自己融合）: 外部CLI不要で動く。追加課金ゼロ。
- **codex-native**（Codex自己融合）: Codexホストの補完枠。Codexのネイティブ・サブエージェントを独立並列で起動する。
- **codex（GPT-5.6 Sol）**: Claude Codeホストから使う外部パネリストとして実機検証済み（codex-cli 0.144.1、`-m gpt-5.6-sol` 固定）。`QUORUM_ENABLE_CODEX=1` で有効化する。**Codexホストでは外部 `run_codex.sh` を除外**し、ネスト・再帰を防ぐ。
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
├── install.sh                  # ~/.claude / $CODEX_HOME へ配置＋ランチャーを symlink
├── bin/
│   └── quorum-shell            # Claude Code ラッパーランチャー
├── skills/quorum/
│   ├── SKILL.md                # Claude Code版の台本＋共有資産の正本
│   ├── scripts/
│   │   ├── detect_panel.sh     # 利用可能なバックエンドを検出
│   │   ├── validate_json.sh    # --output-format json の決定論検証ゲート
│   │   ├── run_codex.sh        # GPT-5.6 Sol（codex CLI）
│   │   ├── run_gemini.sh       # Gemini（Gemini API 本線 / gemini CLI 補助）
│   │   └── run_grok.sh         # Grok（grok CLI=サブスク枠 / xAI API フォールバック）
│   └── references/
│       ├── panel.md            # なぜ独立並列か・judge は最強モデルに
│       ├── judge_rubric.md     # どう突き合わせるか
│       └── context-packing.md  # fan-out 前の「司書」手順（巨大MD/ライブ状態を絞って渡す）
├── skills/codex-quorum/
│   ├── SKILL.md                # Codex版のホスト固有手順
│   └── agents/openai.yaml      # Codex UIメタデータ
├── rules/
│   ├── quorum-triage.md        # Claude Code版トリアージ
│   └── codex-quorum-triage.md  # Codex版 T1 → $quorum 接続
├── tests/
│   └── run_tests.sh            # detect_panel / validate_json の純 bash テスト（API 不要）
└── commands/
    ├── quorum.md               # /quorum（自動パネル選択）
    └── quorum-opus.md          # /quorum-opus（Claude 自己融合・追加課金ゼロ）
```

実行ごとの生入出力（pack 済みプロンプト・各パネリストの回答全文・judge の事前コミット）は
`~/.local/share/quorum/runs/<UTC時刻>/` に保存される。judge の引用の裏取りや、
IMPROVEMENTS.md に書く改善メモの証拠として使える。

## パネリストと課金（重要）

| backend | 実体 | 投げ方 | 認証 / 課金 |
|---|---|---|---|
| `opus` | Claude Opus | Claude Code サブエージェント（**model=opus 明示指定**。judge はセッションのモデル） | **Claude Code のプラン内**（追加課金なし） |
| `codex-native` | Codexネイティブ | Codexサブエージェント（Codexホスト専用） | 親Codexと同じ契約・利用枠 |
| `codex` | GPT-5.6 Sol | `codex exec -m gpt-5.6-sol`（Claude Codeホスト専用） | ChatGPT ログイン=サブスク枠 / APIキー=従量 |
| `gemini` | Gemini | `gemini -p` | Google ログイン=無料枠 / APIキー=従量 |
| `grok` | Grok (xAI) | `grok -p`（CLI）/ xAI API（curl） | **サブスク枠**（SuperGrok/X Premium+・`grok login`）or APIキー=従量 |

- 「sh で叩く＝サブスク不可」は誤り。**codex / gemini / grok はいずれもログイン方式ならサブスク枠で動く**（grok は公式 Grok Build CLI 経由）。
- API キー方式（`OPENAI_API_KEY` / `GEMINI_API_KEY` / `XAI_API_KEY`）にすると従量課金になる。
- コストは概ね単一回答の **N倍**、レイテンシは**最遅パネリストに律速**。高ステークスの問いに限定して使う。

## インストール

```bash
cd ~/Develop/skills/quorum
./install.sh                 # ~/.claude と $CODEX_HOME の両方へ
# 別ディレクトリなら:
# CLAUDE_CONFIG_DIR=/path/.claude CODEX_HOME=/path/.codex ./install.sh
```
完了後、Claude Code は再起動または `/reload-skills`。Codexで反映されない場合は再起動する。

`install.sh` は **このリポジトリの内容を各マシンの `~/.claude`・`$CODEX_HOME`・`~/.local/bin` に展開する**もの。Codex版は共有 scripts/references に専用 `SKILL.md` を重ねて `$CODEX_HOME/skills/quorum` に組み立てる。配置物は生成物なので Git には入れない。

## 別PCでのセットアップ（移植）

このツールは**リポジトリが唯一の真実**。他PCでは:

```bash
# 1) ソースを取得
git clone https://github.com/jeeee-org/quorum && cd quorum
# 2) そのPCに配置（~/.claude / ~/.codex / ~/.local/bin に展開）
./install.sh
# 3) ~/.local/bin が PATH に無ければ通す（例: ~/.zshrc）
#    export PATH="$HOME/.local/bin:$PATH"
```

`install.sh` は skills / commands / ランチャーに加えて、Claude Codeの `~/.claude/CLAUDE.md` へ既存トリアージ規則を、Codexの `$CODEX_HOME/AGENTS.md` へ **T1 → `$quorum` の接続規則だけ**をマーカーブロックとして注入する。Codexの分類正本は `claude-rules` に置き、quorum側では重複定義しない。新PCでは `claude-rules → quorum → cadence` の順で各 `install.sh` を実行するのを推奨する。

さらに **`rules/settings-env.json` の環境変数を各PCの `~/.claude/settings.json` の `env` にマージ**する（現在は `QUORUM_ENABLE_CODEX=1`）。マージは**未設定キーのみ**——そのPCで明示した値は上書きされないので、特定PCで codex を無効にしたければ settings.json で `"QUORUM_ENABLE_CODEX": ""` と空文字を置けばよい（再インストールでも保持される）。codex 未導入のPCでは変数が立っていても `--check` が CLI 不在で弾くため無害。壊れた settings.json には触れない（警告してスキップ）。

**各PC固有で別途必要なもの**（秘密情報のため Git には入れない・入れてはいけない）:
- 使いたいモデルCLIの導入と**認証**:
  - codex（OpenAI）: `codex login`（`QUORUM_ENABLE_CODEX=1` で有効化）
  - grok（xAI/SuperGrok）: `curl -fsSL https://x.ai/cli/install.sh | bash` → `grok login`
  - gemini（任意）: `npm i -g @google/gemini-cli` → ログイン（`QUORUM_ENABLE_GEMINI=1` で有効化）
- 確認: Claude版は `~/.claude/skills/quorum/scripts/detect_panel.sh`、Codex版は `QUORUM_HOST=codex ~/.codex/skills/quorum/scripts/detect_panel.sh` で使えるパネルが出るか

opus / codex-native パネリストは各ホストに内蔵のため追加導入は不要。**認証トークンはマシンごと**で、リポジトリには含まれない（`.gitignore` 済み）。

**更新を取り込む時も同じ**：`git pull` の後に `./install.sh` を再実行する（install.sh は配置先を `rm -rf` して入れ直す）。

**改善メモ（`IMPROVEMENTS.md`）はマシンごとに symlink を張り直す**：正本はリポ root の `IMPROVEMENTS.md`（git 管理）で、install.sh がClaude/Codex両方の配置先から正本へ symlink を張る。実行時の追記は再インストールでも消えず、Gitで他PCと共有できる。

## 常時トリアージ（グローバルルール）

Claude Codeでは `rules/quorum-triage.md` がグローバル `~/.claude/CLAUDE.md` に入り、Fable の都度課金を見据えた段階エスカレーションを行う：

```
T0: セッションモデル（例 Opus）単発          ← 既定。日常の大半
 ├─ 深さ型 × 高ステークス → T2a: Fable サブエージェント単発（quorum は飛ばす）
 └─ 広さ型 × 高ステークス → T1: /quorum（panel=opus+外部、judge=メイン）
                └─ 監査に未解決シグナル → T2b: /quorum-escalate（Fable 再judge・パネル再実行なし）
```

- 設計根拠は 2026-07-06 の実験（IMPROVEMENTS.md）：深さ型では quorum が単発の最強モデルに勝ちにくく、広さ型では panel が効く。T2b は runs/ の成果物を再利用するので追加コストは Fable 1コール分。
- T2b の発動は**観測可能なシグナルのみ**（未解決 Contradictions / 🕳️ 欠落 / 事前コミット不安定）。モデルの「難しい気がする」では発動しない。
- fable 呼び出しは必ず事前宣言＋ `~/.local/share/quorum/fable_calls.log` に記録（課金監査）。ユーザーの明示指定（「単発で」「quorumで」「fableで」）が常に優先。
- 規則本文の変更は**リポの `rules/quorum-triage.md` を編集して `./install.sh`**（各PCの CLAUDE.md を直接編集しない。ブロック外のユーザー記述には触れない設計）。

Codexでは `claude-rules` の T0 / T1 / T2a / CADENCE を正本とする。`rules/codex-quorum-triage.md` は、T1の実行依頼を `$quorum` へ接続するだけで、Fable固有のT2bは持ち込まない。

## 使い方

- 共通の自然言語: 「quorum で次の問いを解いて: …」
- Claude Code: `/quorum <問い>` / `/quorum-opus <問い>` / `/quorum-escalate [run dir]`
- Codex: `$quorum を使って <問い>`（CLI/IDEのスキル選択からも起動可能）
- 機械可読出力: `--output-format json` を付けると `output_schema.json` 準拠の単一JSONになる。既定は `text`。

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
| `QUORUM_PANEL_SIZE` | 4 | 目標パネル数。使えない枠はClaudeホストでは opus、Codexホストでは codex-native で補完。distinct が目標超の時だけトリムし明示 |
| `QUORUM_TIMEOUT` | 300 | 各外部パネリストの実行時間上限（秒）。run スクリプトに内蔵、超過は欠席扱い |
| `QUORUM_ENABLE_CODEX` | **1**（Claude settingsへマージ） | Claude Codeホストで外部codexをパネルに含める。Codexホストでは常に外部codexを除外 |
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
- [ ] プロンプト stdin 化後の実機確認（codex exec `-` / gemini CLI の stdin+`-p ""`）と、API 経路の curl config 方式（キー・本文を argv に載せない）の実キー確認。
