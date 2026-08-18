#!/usr/bin/env bash
# 利用可能なバックエンドを検出し、ホストのネイティブ・サブエージェントで補完したパネルを出力する。
#
# 規約: scripts/ 配下の `run_<name>.sh` が1バックエンド。
#   - `run_<name>.sh --check` … 0=可用 / 2=意図的に不参加（opt-out）/ その他非0=参加したいのに使えない
#   - `run_<name>.sh --version` … その backend の CLI 版を1行で申告（任意。未対応でも壊れない）
#   - `run_<name>.sh`（引数なし）… プロンプトを stdin で受け、回答を stdout へ
# 新しいモデルを足したい時は、この規約に従う run_<name>.sh を置くだけでよい。
# ネイティブ枠はスクリプトではなく、ホストのサブエージェント機構で spawn する。
#   QUORUM_HOST=claude（既定）: opus（外部 run_claude.sh は除外）
#   QUORUM_HOST=codex          : codex-native（外部 run_codex.sh は除外）
#
# 出力: パネリストを1行ずつ（**multiset**。同じ名前が複数行 = その回数だけ独立実行する）。
#   Claudeホストは opus、Codexホストは codex-native をネイティブ枠にし、使えない枠も同じ
#   ネイティブ実行で補完する。外部バックエンドは --check とオプトイン設定に従う。
#
# 環境変数:
#   QUORUM_PANEL            パネルの明示指定（カンマ/空白区切りの multiset。タブ・改行も区切りとして
#                           受ける。例 "opus,opus,codex,grok"）。指定時は検出・--check・補完を全部
#                           飛ばしてそのまま出力する（増員・固定用）。使える名前は native
#                           （opus / fable / codex-native）と run_<name>.sh。再帰防止
#                           （現在ホストと同名の外部backend禁止）だけは明示指定でも上書きできない。
#   QUORUM_PANEL_SIZE       目標パネル数（既定 3）。distinct な利用可能バックエンドがこれに満たない
#                           分をホストのネイティブ実行で補完する（Claude=opus / Codex=codex-native）。
#                           QUORUM_NATIVE=fable でも補完で fable は増殖させない。distinct が目標を
#                           超える場合は全部出力し、トリムは SKILL 側の優先順位判断に委ねる。
#   QUORUM_NATIVE           Claudeホストのネイティブ枠の差し替え（opus | fable。既定 opus）。
#                           fable は judge と同格の高コストモデルのため、ユーザーの呼びかけ時のみ使う。
# backend の参加スイッチは**3つとも既定オフ（opt-in）**。何も設定しなければ外部ゼロ →
# ネイティブ枠で埋まり **opus×3**（Codexホストは codex-native×3）になる。使うPCだけ 1 にする。
#   QUORUM_ENABLE_CODEX=1   codex を候補に含める（既定オフ。空文字・0・false・no は無効。run_codex.sh 側で判定）。
#   QUORUM_ENABLE_GROK=1    grok を候補に含める（既定オフ。空文字・0・false・no は無効。run_grok.sh 側で判定）。
#   QUORUM_ENABLE_GEMINI=1  gemini を候補に含める（既定オフ。0・false は無効。run_gemini.sh 側のオプトイン）。
#   QUORUM_ABSENCE_WARN     opt-in 済みなのに --check が通らない状態が何回連続したら stderr へ
#                           警告するか（既定 3。0 で無効）。状態は
#                           $QUORUM_STATE_DIR（既定 ~/.local/share/quorum）/absence.tsv。
#                           opt-out（exit 2）は故障ではないので数えない。
#   QUORUM_VERSION_WATCH    参加する backend の CLI 版を記録し、前回から変わっていたら stderr へ
#                           知らせる（既定 1。0 で無効）。状態は $QUORUM_STATE_DIR/versions.tsv。
# フラグ:
#   --raw  補完せず「利用可能な distinct バックエンド」だけを出力（デバッグ/テスト用）。
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"

RAW=0
HOST="${QUORUM_HOST:-claude}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw) RAW=1 ;;
    --host)
      [ "$#" -ge 2 ] || { echo "--host には claude または codex が必要です" >&2; exit 2; }
      HOST="$2"
      shift
      ;;
    *) echo "不明な引数: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$HOST" in
  claude)
    NATIVE="${QUORUM_NATIVE:-opus}"
    case "$NATIVE" in
      opus|fable) : ;;
      *) echo "QUORUM_NATIVE は opus または fable を指定してください: $NATIVE" >&2; exit 2 ;;
    esac
    ;;
  codex) NATIVE="codex-native" ;;
  *) echo "QUORUM_HOST は claude または codex を指定してください: $HOST" >&2; exit 2 ;;
esac

# ホストが直接 spawn できるサブエージェント名（QUORUM_PANEL の検証に使う）
is_native_name() {
  case "$HOST:$1" in
    claude:opus|claude:fable|codex:codex-native) return 0 ;;
    *) return 1 ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 明示指定（QUORUM_PANEL）があれば検出・補完を飛ばしてそのまま出力する。
# --check も飛ばす（明示された枠の実行時失敗は SKILL 側が dropped として扱う）。
if [ -n "${QUORUM_PANEL:-}" ]; then
  # カンマ・タブ・改行を空白に正規化してから分割（改行入り指定の黙殺を防ぐ。read は1行しか読まない）
  IFS=' ' read -ra entries <<< "$(printf '%s' "$QUORUM_PANEL" | tr ',\t\n' '   ')"
  panel=()
  for name in "${entries[@]}"; do
    [ -n "$name" ] || continue
    if is_native_name "$name"; then panel+=("$name"); continue; fi
    if [ "$name" = "$HOST" ]; then
      echo "QUORUM_PANEL: $HOST ホストでは外部 $name を指定できません（再帰防止）" >&2; exit 2
    fi
    if [ -e "$SCRIPT_DIR/run_$name.sh" ]; then panel+=("$name"); continue; fi
    echo "QUORUM_PANEL: 不明なバックエンド: $name（native または run_$name.sh のある名前を指定）" >&2; exit 2
  done
  [ "${#panel[@]}" -gt 0 ] || { echo "QUORUM_PANEL が空です" >&2; exit 2; }
  printf '%s\n' "${panel[@]}"
  exit 0
fi

# --check を通った distinct な外部バックエンド
# exit code 規約: 0=可用 / 2=意図的に不参加（opt-out） / その他非0=参加したいのに使えない
externals=()
checked_names=()
checked_codes=()
for s in "$SCRIPT_DIR"/run_*.sh; do
  [ -e "$s" ] || continue
  name="$(basename "$s")"; name="${name#run_}"; name="${name%.sh}"
  # 現在ホストと同名の外部CLIは再起動しない。ネイティブ・サブエージェントを使う。
  [ "$name" = "$HOST" ] && continue
  code=0
  bash "$s" --check >/dev/null 2>&1 || code=$?
  checked_names+=("$name")
  checked_codes+=("$code")
  if [ "$code" -eq 0 ]; then
    externals+=("$name")
  fi
done

# 連続欠席の記録と警告（IMPROVEMENTS 2026-07-10）
#
# 単発の欠席は無言で補完してよい。問題は**恒久的な故障**（認証切れ・CLI 更新で壊れた等）が
# 毎回「一時的な欠席」として処理され、パネルが静かに同族ネイティブ寄りへ退化することだった。
# opt-out（exit 2）は故障ではないので数えず、カウンタも 0 に戻す。
# 警告は **stderr** に出す——stdout はパネル multiset で、SKILL が1行=1パネリストとして読むため。
record_absence() {
  local warn_at="${QUORUM_ABSENCE_WARN:-3}"
  case "$warn_at" in
    ''|*[!0-9]*) warn_at=3 ;;
  esac
  [ "$warn_at" -gt 0 ] || return 0
  [ "${#checked_names[@]}" -gt 0 ] || return 0

  local state_dir="${QUORUM_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/quorum}"
  local file="$state_dir/absence.tsv"
  mkdir -p "$state_dir" 2>/dev/null || return 0

  local -A count seen
  if [ -r "$file" ]; then
    local n c t
    while IFS=$'\t' read -r n c t; do
      [ -n "${n:-}" ] || continue
      case "${c:-}" in ''|*[!0-9]*) c=0 ;; esac
      count["$n"]="$c"; seen["$n"]="${t:-未記録}"
    done < "$file"
  fi

  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local i name code
  for i in "${!checked_names[@]}"; do
    name="${checked_names[$i]}"; code="${checked_codes[$i]}"
    case "$code" in
      0) count["$name"]=0; seen["$name"]="$now" ;;
      2) count["$name"]=0 ;;   # 意図的に不参加。故障ではないので数えない
      *)
        count["$name"]=$(( ${count["$name"]:-0} + 1 ))
        if [ "${count[$name]}" -ge "$warn_at" ]; then
          echo "[quorum] 警告: $name が ${count[$name]} 回連続で欠席しています（最後に使えたのは ${seen[$name]:-未記録}）。参加設定は入っているので、CLI の導入・認証（例: \`$name login\`）・APIキーを確認してください。放置するとパネルが静かに同族ネイティブ寄りへ退化します。" >&2
        fi
        ;;
    esac
  done

  local tmp; tmp="$(mktemp)" || return 0
  for name in "${!count[@]}"; do
    printf '%s\t%s\t%s\n' "$name" "${count[$name]}" "${seen[$name]:-未記録}" >> "$tmp"
  done
  sort -o "$tmp" "$tmp" && mv "$tmp" "$file" 2>/dev/null || rm -f "$tmp"
}
record_absence

# バックエンド CLI の版を記録し、変化したら知らせる（IMPROVEMENTS 2026-08-15）
#
# 外部 CLI をパネリストに使うハーネスは、**CLI 自身のバージョンとオプションを定期的に読み直す
# 必要がある**。grok が「作業予告だけ返す」不調に陥った時、原因は plan mode（`--no-plan` で
# 抑止できる）だったのに、9 run ぶんの試行錯誤がすべてプロンプト側で行われ、`--help` を読み
# 直した run が1つも無かった。版が動いたことを知らせれば、その回に `--help` を見直す動機になる。
# 判定は変えない（stdout はパネル multiset のまま）——気づきの機会を stderr に置くだけ。
record_versions() {
  local watch="${QUORUM_VERSION_WATCH:-1}"
  case "$watch" in 0|false|no) return 0 ;; esac
  [ "${#externals[@]}" -gt 0 ] || return 0

  local state_dir="${QUORUM_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/quorum}"
  local file="$state_dir/versions.tsv"
  mkdir -p "$state_dir" 2>/dev/null || return 0

  local -A prev
  if [ -r "$file" ]; then
    local n v
    while IFS=$'\t' read -r n v; do
      [ -n "${n:-}" ] || continue
      prev["$n"]="${v:-}"
    done < "$file"
  fi

  # 版の申告に時間をかける理由はない。timeout が無い環境では素で呼ぶ（</dev/null が主防御）。
  local VERSION_TO=""
  command -v timeout >/dev/null 2>&1 && VERSION_TO="timeout ${QUORUM_VERSION_TIMEOUT:-10}"

  local -A now
  local name ver
  for name in "${externals[@]}"; do
    # `--version` は任意の規約。未対応のスクリプトは引数を無視して stdin を読みに行くので、
    # **必ず </dev/null で塞ぐ**（塞がないと probe がプロンプト待ちで固まる）。
    # timeout があれば更に短く打ち切る——版の申告に時間をかける理由がない。
    ver="$($VERSION_TO bash "$SCRIPT_DIR/run_$name.sh" --version </dev/null 2>/dev/null | head -n 1 | tr '\t' ' ' || true)"
    [ -n "$ver" ] || ver="unknown"
    now["$name"]="$ver"
    # 初回（記録なし）は知らせない。変化した時だけ出す。
    if [ -n "${prev[$name]:-}" ] && [ "${prev[$name]}" != "$ver" ]; then
      echo "[quorum] 注意: $name の CLI 版が変わりました（${prev[$name]} → ${ver}）。挙動が変わっている可能性があります——\`$name --help\` を読み直し、非対話実行に効くオプション（例: plan mode やサブエージェントの無効化）が増減していないか確認してください。監査証跡にこの版を書き残すこと。" >&2
    fi
  done

  # 記録は「今回見た backend」だけ更新し、他の行は残す
  local tmp; tmp="$(mktemp)" || return 0
  if [ -r "$file" ]; then
    local keep=1 n2 v2
    while IFS=$'\t' read -r n2 v2; do
      [ -n "${n2:-}" ] || continue
      [ -n "${now[$n2]:-}" ] && continue
      printf '%s\t%s\n' "$n2" "$v2" >> "$tmp"
    done < "$file"
    : "$keep"
  fi
  for name in "${!now[@]}"; do
    printf '%s\t%s\n' "$name" "${now[$name]}" >> "$tmp"
  done
  sort -o "$tmp" "$tmp" && mv "$tmp" "$file" 2>/dev/null || rm -f "$tmp"
}
record_versions

# distinct な利用可能パネル = native + externals
panel=("$NATIVE")
if [ "${#externals[@]}" -gt 0 ]; then
  panel+=("${externals[@]}")
fi

if [ "$RAW" = "1" ]; then
  printf '%s\n' "${panel[@]}"
  exit 0
fi

# 欠員はホストの安価なネイティブ枠で補完する。
# QUORUM_NATIVE=fable は明示された1枠だけに使い、補完では opus を使う。
case "$HOST" in
  claude) BACKFILL="opus" ;;
  codex) BACKFILL="codex-native" ;;
esac

# 目標に満たない分を補完（distinct が目標超なら触らない＝SKILL が優先順位でトリム）
TARGET="${QUORUM_PANEL_SIZE:-3}"
case "$TARGET" in
  ''|*[!0-9]*|0) echo "QUORUM_PANEL_SIZE は正の整数を指定してください: $TARGET" >&2; exit 2 ;;
esac
while [ "${#panel[@]}" -lt "$TARGET" ]; do
  panel+=("$BACKFILL")
done

printf '%s\n' "${panel[@]}"
