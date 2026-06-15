#!/usr/bin/env bash
# 利用可能なパネリスト・バックエンドを1行ずつ出力する。
# opus は Claude Code 内で常に利用可能（このスクリプトの外で Task により spawn）。
set -euo pipefail

echo opus
command -v codex  >/dev/null 2>&1 && echo codex  || true
command -v gemini >/dev/null 2>&1 && echo gemini || true
# grok は xAI API キーと curl があれば利用可能
if [ -n "${XAI_API_KEY:-}" ] && command -v curl >/dev/null 2>&1; then
  echo grok
fi
