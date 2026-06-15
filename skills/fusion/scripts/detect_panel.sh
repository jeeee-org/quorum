#!/usr/bin/env bash
# 利用可能なパネリスト・バックエンドを1行ずつ出力する。
# opus は Claude Code 内で常に利用可能（このスクリプトの外で Task により spawn）。
set -euo pipefail

echo opus
command -v codex >/dev/null 2>&1 && echo codex || true

# gemini は「導入済みだが既定パネルからは除外」。
# 使いたい時だけ FUSION_ENABLE_GEMINI=1 で明示的に有効化する。
# 理由: 無料枠は (1) pro 容量が枯渇しがち (2) データが学習利用され得る。
#       常用するなら有料 API キー（学習不使用・容量確保）を推奨。
if [ -n "${FUSION_ENABLE_GEMINI:-}" ] && command -v gemini >/dev/null 2>&1; then
  echo gemini
fi

# grok は (a) Grok Build CLI（サブスク枠）が入っているか
#         (b) xAI API キー（従量）+ curl があれば利用可能。
export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"
if command -v grok >/dev/null 2>&1 || { [ -n "${XAI_API_KEY:-}" ] && command -v curl >/dev/null 2>&1; }; then
  echo grok
fi
