---
name: quorum
description: 高難度・高ステークスの問いを「独立並列 → judge → fuse」で解く融合スキル。同じプロンプトを複数の回答者（Claude Opus サブエージェント／codex=GPT-5.6 Sol／gemini／grok）に互いにブラインドで投げ、メインセッションのモデル（judge）が合意・矛盾・盲点まで構造的に突き合わせて最終回答を書く。クイック/低リスクな問いには使わない（コストN倍・最遅パネリストに律速）。
---

# Quorum（独立並列 → judge → fuse）

このスキルは **fan-out → judge → fuse** パイプラインで1問の回答品質を上げる。
**メインセッションのモデルがオーケストレーター兼 judge を兼ねる**（順序は反転不可：パネリストは judge を spawn できない）。
融合の品質上限は judge の突き合わせ能力で決まるので、**judge にはセッションで使える最も賢いモデル（例: Fable 5）を座らせる**のが最も効率が良い。パネル（幅）は安価なモデルで、突き合わせ（深さ）は最強モデルで（`references/panel.md`）。

> 設計思想は `references/panel.md`（なぜ独立か）と `references/judge_rubric.md`（どう統合するか）を参照。
> 巨大MD／ライブ状態を扱う時の入力整形は `references/context-packing.md`（fan-out 前の「司書」手順）。
>
> **スクリプト/参照ファイルの場所**: 既定のインストール先は `~/.claude/skills/quorum/`。
> 以下の `scripts/...` `references/...` は `~/.claude/skills/quorum/` 配下を指す（CWD に依存しない絶対パスで叩くこと）。

## 実行手順

### 0. コスト/ステークス・ガード（fan-out 前に必ず）
- **ステークス判定**: 問いが低リスク／単純なら、**融合せず単一モデルで答える**（または `/quorum-opus` を案内）。融合は高ステークス・複雑な問い限定。コストは概ね**パネリスト数 × トークン**。
- **問いの型で使い分ける**: **推論の深さ**が支配的な問い（数学・設計の一貫性・単一文書の精読）は、フルパネルよりセッションモデル単発（または `/quorum-opus`）が有利なことが多い——深さは judge 側のモデルが既に持っている。フルパネルが効くのは**事実の争い・情報の広さ・盲点リスク**が支配的な問い（技術選定・障害の根因・相場観・「全員が同じ場所で転ぶ」のが怖い判断）。迷ったら「異種ベンダーの視点が結論を動かし得るか？」で判定する。
- **目標パネル数**: `QUORUM_PANEL_SIZE`（既定 3）。**既定パネルは opus / codex / grok の3枠**（gemini は既定で外し、入れるのは `QUORUM_ENABLE_GEMINI=1` のオプトイン時のみ。codex は既定参加で、外すのは `QUORUM_ENABLE_CODEX` に空文字か `0`/`false` を置いた時のみ）。欠員は **opus → codex → grok の優先順で可用な補完枠**が埋めて目標数を満たす（Claude Code ホストでは opus が常に可用なので実質 opus 補完。detect_panel.sh が自動でバックフィルした multiset を出力する）。distinct な利用可能バックエンドが目標を**超える**場合のみトリムし、**無音で切り捨てない** — 落としたバックエンドを必ず明示する。トリム優先順位は「設問ドメイン適合 > 多様性（別系統モデル）> 同系の追加実行（=補完分）」。
- **時間上限**: 各外部パネリストは `QUORUM_TIMEOUT` 秒（既定 300）で自動打ち切り（run スクリプトに内蔵）。打ち切られたパネリストは欠席扱いで続行。

### 1. パネルを決める
- 明示指定があればそれに従う。会話での指定（例「`opus-grok` で」「grok 2体で」「codex をもう1体足して」）は multiset として解釈してそのまま fan-out する。スクリプト経由で固定・増員したい時は `QUORUM_PANEL="opus,opus,codex,grok"`（カンマ/空白区切り）を detect_panel.sh に渡す——指定時は検出・`--check`・補完を全部飛ばしてそのまま出力される。**明示パネルは `--check` とネイティブ枠の床の両方を外すため、成功回答が0件になったら fuse せず中断して報告し**、自動検出パネルでの再実行を提案する（quorum の体裁で単発回答を出さない）。
- **fable 枠（呼びかけ時のみ）**: ユーザーが「fable をパネルに」「opus 枠を fable で」等と明示した時だけ、opus 枠を `fable` に差し替える（`QUORUM_NATIVE=fable` を detect_panel.sh に渡すか、`QUORUM_PANEL` / 会話指定に `fable` を含める）。fable は judge と同格の高コストモデルなので**自動選択では使わない**し、欠員補完で fable を増殖もさせない（補完は常に opus→codex→grok）。fable 行を spawn する前に**1行宣言し、`~/.local/share/quorum/fable_calls.log` に「日時<TAB>panel<TAB>用途一言」を追記する**（グローバル規則の都度課金監査に合わせる）。
- なければ `~/.claude/skills/quorum/scripts/detect_panel.sh` を Bash で実行する。**出力は目標数（`QUORUM_PANEL_SIZE` 既定 3）まで opus で補完済みの multiset**（1行=1パネリスト、同じ名前が複数行=その回数だけ独立実行）。
- **出力の各行をそのままパネリストにする**：`opus` 行は Task で独立サブエージェントを1体ずつ spawn（複数あれば opus#1 / opus#2 … と区別して監査証跡に明示）。**spawn 時に model を `opus` と明示指定する**——セッションモデルを継承させると judge と同一の高コストモデルが走り、監査証跡の帰属も嘘になる（幅はパネルの安いモデル、深さは judge の役割分担）。非 opus 行は `scripts/run_<name>.sh` を呼ぶ。
- detect の出力行数が `QUORUM_PANEL_SIZE` を超える場合（distinct バックエンドが目標超）だけ、step 0 の優先順位でトリムし**落としたものを明示**する。

**バックエンドは規約ベース（汎用）**。detect_panel.sh は `scripts/run_<name>.sh` を自動ディスカバリし、各スクリプトの `--check`（exit 0=可用）で取捨する。出力された `<name>` ごとに `scripts/run_<name>.sh` を呼べばよい（個別の分岐を SKILL に書かない）。**「使える枠は本物のモデル・足りない枠は opus」**という補完は detect_panel.sh が行うので、SKILL 側は出力を信じて回すだけでよい。

現状検出され得るバックエンド（例）：
| backend | 実体 | 投げ方 |
|---|---|---|
| `opus` | Claude Opus | Task でサブエージェントを spawn（**model=opus 明示指定**・web検索・bash 込み）。スクリプトではなく特別扱い |
| `fable` | Claude Fable | opus と同じく Task で spawn（**model=fable 明示指定**）。**ユーザーの呼びかけ時のみ**・宣言＋fable_calls.log 追記が必須 |
| `codex` | GPT-5.6 Sol | `scripts/run_codex.sh` に プロンプトを stdin（`-m gpt-5.6-sol` 固定・既定参加。`QUORUM_ENABLE_CODEX` を空文字/`0`/`false` にすると除外） |
| `gemini` | Gemini | `scripts/run_gemini.sh`（既定除外・`QUORUM_ENABLE_GEMINI=1` で可用） |
| `grok` | Grok (xAI) | `scripts/run_grok.sh`（grok CLI=サブスク枠 or `XAI_API_KEY`） |

新しいモデルを足すには、規約に従う `run_<name>.sh`（`--check` で可用判定＋stdin→stdout）を置くだけ。detect も fan-out も無改修で対応する。

### 2. fan-out（独立・並列・ブラインド）
- **問いが巨大MD／複数ファイル／ライブ状態に依存する場合は、fan-out の前に `references/context-packing.md` の「司書」手順で `$PROMPT` を自己完結化する**（パネリスト＝特に外部CLIはリポも `~/.claude` も見えないので、渡すテキストの質が回答の上限になる）。材料が小さい問いはこの手順を飛ばして素の問いを渡す。
- **run ディレクトリを作り、生の入出力をファイルに残す**：`RUN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quorum/runs/$(date -u +%Y%m%dT%H%M%SZ)"` を作成し、投げたプロンプトを `$RUN_DIR/prompt.md` に保存する。各パネリストの回答全文もここに保存する——外部CLIは `... | tee "$RUN_DIR/answer_<label>.md"`、opus サブエージェントの回答はメインが Write で保存。ラベルと backend の対応は `$RUN_DIR/mapping.txt`（`<label>\t<backend>` 1行ずつ）に書く（ラベルは step 3 の匿名化で使う）。judge の引用を後から検証でき、一部パネリストが落ちても成功分を失わない。
- **judge の事前コミット**：fan-out を投げた直後・**どのパネリスト回答も読む前に**、メインは自分の暫定回答（結論と主根拠を数行）を `$RUN_DIR/precommit.md` に書き留める。fuse 後、暫定からの差分（パネルが結論を動かしたか・何を足したか）を監査証跡に1行で書く。**パネルが結論を全く動かさない実行が続くなら、その問いの型は単発で足りるサイン**——IMPROVEMENTS.md に記録する（step 0 の分岐を経験的に更新する材料）。
- **全パネリストに完全に同じプロンプト（ユーザーの問い／pack 済みなら同一 pack）をそのまま渡す**。言い換え・役割付与（「批評家として」等）はしない。多様性は演出せず独立実行から収穫する。
- `opus` / `fable` パネリストは Task でサブエージェントとして並列起動（model をその名前で明示指定）。各自に web 検索と bash を使って独立に調べさせる。fable 行は spawn 前の宣言と fable_calls.log 追記を忘れない（step 1）。
- 非 opus の各バックエンド `<name>` は Bash で `scripts/run_<name>.sh` を実行し、標準出力（回答全文）を回収する。プロンプトは stdin で渡す：
  - 例: `printf '%s' "$PROMPT" | bash ~/.claude/skills/quorum/scripts/run_<name>.sh | tee "$RUN_DIR/answer_<label>.md"`
- パネリストどうしの中間結果は**互いに見せない**。

### 3. judge（突き合わせ）
- **匿名化してから突き合わせる**：回収した回答を（回収順と無関係な順で）**回答A / 回答B / … の匿名ラベル**で扱い、分析はラベルだけで書く。ラベル→backend の対応は `$RUN_DIR/mapping.txt` にあり、**監査証跡を書く段階で初めて実名に戻す**。実名復元は**必ず mapping.txt を読み直して**行い、記憶で帰属しない（誤帰属防止。対応表が正）。メイン自身が fan-out したので完全なブラインドにはならないが、「ブランドで重みづけしない」規律（judge_rubric）を機械的に支える。判定が拮抗していて帰属バイアスが怖い時は、`$RUN_DIR/answer_*.md`（匿名ファイル名のまま）だけを渡した判定サブエージェントに rubric 分析を委ね、メインはその結果を使って fuse する。
  - **文体正規化（回答の中立文体への書き直し）は行わない**。2026-07-06 の実験では、文体指紋は正規化前から弱く（文体のみの識別率≒偶然）、真の識別ベクトルは「同族 N-1 体の内容収束による消去法」で正規化では消えない。正規化は追加1パスのコストと情報落ち（偽の手がかり生成）の害の方が大きい。匿名化はラベル遮断の規律として維持すれば足りる。

- **load-bearing な出典を spot-check する（research 型の問い）**：結論の重みづけを左右する引用・出典が回答に含まれる場合、**上位1〜2件は judge が WebFetch 等で実在・内容を確認してから**重みにする。未検証のまま採用した出典は監査証跡に「未検証」と明記する（出典風の記述を無検証で加点するのは rubric が警告する authority bias そのもの）。

回収した全回答を、メイン（セッションのモデル）が `~/.claude/skills/quorum/references/judge_rubric.md` に沿って構造化分析する。最低限：
- **Consensus**（合意点）
- **Contradictions**（食い違い。どちらがより確からしいか根拠つきで判定）
- **Partial coverage**（一部しか触れていない論点）
- **Unique insights**（単独パネリストだけが出した洞察）
- **Blind spots**（全員が見落としている可能性のある点）
- **継ぎ目チェック表**（judge_rubric の全カテゴリを1行も省略せず点検。被覆/部分/欠落/N-A を判定）

各項目には**どのパネリスト由来か**を明示する。

### 4. fuse（最終回答）
上の分析を根拠に、メイン（セッションのモデル）が最終回答を書く。**出力形式は `--output-format` で切替**（既定 `text`）。

**`text`（既定・人間向け）**
1. **最終回答**（本体・トップに置く）
2. **監査証跡（audit trail）**：上記の構造化分析を畳んで添える（どの回答者が何を言ったか追える形で）。
   - **継ぎ目チェック表は常設**（省略不可）。🕳️ 欠落カテゴリがあれば、その補足を最終回答にも反映する。
   - **事前コミット差分を1行常設**：judge の暫定回答（step 2 の precommit.md）からパネルが何を動かしたか（動かさなかったならその旨と理由）。
   - **監査証跡を `$RUN_DIR/judge.md` にも保存する**（step 5 の escalate の入力になる。会話にしか残さない運用をしない）。

**`json`（機械可読）**
- `~/.claude/skills/quorum/references/output_schema.json` に**準拠した単一の ```json ブロックだけ**を出力する（前後に散文を付けない）。
- `final_answer` に最終回答（markdown 可）、`seam_check` に継ぎ目カテゴリ全件、`panel.dropped` に除外/timeout したバックエンドを必ず入れる。
- **出力する前に検証ゲートを通す**：組んだ JSON を `~/.claude/skills/quorum/scripts/validate_json.sh` に stdin で渡し（`printf '%s' "$JSON" | bash .../validate_json.sh`）、NG が出たら直して再検証してから出力する。準拠をモデルの善意に頼らない。

### 5. escalate（任意・T2b: Fable 再judge）

judge/fuse の結果に**次の観測可能なシグナル**が出た時だけ使う（グローバルのトリアージ規則 T2b。感覚では発動しない）：
- Contradictions を根拠つきで裁定できず両論併記に逃げた
- 継ぎ目チェックに 🕳️ 欠落があり judge の補足が薄い
- 事前コミット差分が大きいのに結論が安定しない

手順：
1. **パネルは再実行しない**。`$RUN_DIR` の prompt.md／answer_*.md（匿名のまま）／judge.md を入力として、**model=fable のサブエージェント**に judge_rubric 準拠の再判定＋最終回答の書き直しを委ねる（対応表 mapping.txt は渡さない＝blind 維持）。
2. 呼び出す前に1行宣言し、`~/.local/share/quorum/fable_calls.log` に「日時<TAB>T2b<TAB>用途一言」を追記する。
3. 出力には「**opus judge から何が変わったか**」を1段落で明示する。変わらなければそれも記録する（次回以降 T2b を渋る材料。IMPROVEMENTS.md に集約）。
4. fable が使えない環境なら escalate を中止し、監査証跡に「escalate 不可（環境）」と残す。

## 注意
- コストは概ね単一回答の **N倍トークン**、レイテンシは**最も遅いパネリストに律速**。高ステークスの問いに限定して使う。
- 外部CLIの認証は「アカウント/OAuth ログイン＝サブスク枠」か「APIキー＝従量」かで課金が変わる。`grok` は xAI APIキー（従量）前提。詳細は README 参照。
- パネリストが落ちた／空応答なら、そのパネリストを除いて続行する（最低1回答＋judge は維持）。**成功回答が0件になった場合（特に明示パネルの全滅）は fuse せず中断して報告する**——監査証跡つきの単発回答を quorum の結果として出さない。

## 改善案の記録（運用ルール）

このスキルは**ユーザー自作の汎用融合ハーネス**。使いながら「judge ルーブリックのこの観点が抜けがち」「context-packing がこの形式に弱い」「パネル選定のこの分岐が欲しい」「新しいバックエンドを足したい」などに気づいたら、その場で `IMPROVEMENTS.md` にメモを残す。後で別セッションのユーザー自身が改善作業に入る時の入力になる。

- **追記先**: `~/.claude/skills/quorum/IMPROVEMENTS.md`。これは **install.sh がリポ root の `IMPROVEMENTS.md`（git 管理の正本）へ張った symlink**なので、追記はそのまま正本へ書き込まれ、再インストール（`rm -rf`）でも消えず `git push`/`pull` で他PCと共有される。symlink が未作成のマシンでは `./install.sh` を一度回す（無ければファイル実体に直接書いてもよいが、その場合は repo root の正本へ）。
- **タイミング**: 気づいた**そのターン中**に追記する。「あとで」にしない（次セッションでは忘れる）。
- **何を書くか**: 1件 = 日付＋状況（どの問いで使った時か・どのバックエンド構成だったか）＋気づき（judge/fuse/panel/context-packing/バックエンドのどこが弱いか）＋できれば**改善案の方向性**（rubric 追加？ scripts 追加？ 既定値の見直し？）。
- **何を書かないか**: 単発のタスク状況（それは PROGRESS.md/checkpoint へ）、特定 PJ のドメイン知見（それは PJ の NOTES.md へ）。**汎用融合ハーネスとしての改善ネタだけ**を残す。
- **書式（推奨）**:
  ```
  ## YYYY-MM-DD — <短い要約>
  - **状況**: どんな問い / どのパネル構成 / どの出力形式で使った時か
  - **気づき**: judge/fuse/panel/context-packing/バックエンドのどこに不足があったか
  - **改善案**: rubric 追加 / 新 backend (`run_<name>.sh`) / 既定値変更 / context-packing 追記 / etc.（仮でよい）
  ```
- **既存項目との重複は統合する**：同種の気づきが既にあれば 1 件にマージし、再発頻度や追加事例を足す（新規行を量産しない）。
