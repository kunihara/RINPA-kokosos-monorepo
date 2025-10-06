#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash scripts/dump_env_file.sh <input_env_file> <output_file>
#
# NOTE: 本スクリプトは gh_set_env_secrets.sh と同じ取り出し・正規化ロジックで
# KEY=VALUE を解析し、正規化済みの KEY=VALUE を <output_file> に書き出します。
# （確認用途。出力ファイルには秘匿情報が含まれるのでコミット禁止）

in_file="${1:-}"
out_file="${2:-}"

if [[ -z "${in_file}" || -z "${out_file}" ]]; then
  echo "Usage: bash scripts/dump_env_file.sh <input_env_file> <output_file>" >&2
  exit 1
fi

if [[ ! -f "${in_file}" ]]; then
  echo "Input file not found: ${in_file}" >&2
  exit 1
fi

tmp_out="${out_file}.tmp"
rm -f "${tmp_out}" 2>/dev/null || true

trim() { local s="$1"; s="${s#${s%%[![:space:]]*}}"; s="${s%${s##*[![:space:]]}}"; printf '%s' "$s"; }

while IFS= read -r raw || [[ -n "$raw" ]]; do
  # CR除去、空行/コメント行スキップ
  line="${raw%$'\r'}"
  [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue

  # 先頭の '=' で分割（値に '=' が含まれてもOK）
  if [[ "$line" != *"="* ]]; then
    continue
  fi
  key="${line%%=*}"; val="${line#*=}"
  key="$(trim "$key")"; val="$(trim "$val")"

  # 値の両端の引用符を除去（"…" または '…'）
  if [[ "$val" == \"*\" && "$val" == *\" ]]; then
    val="${val:1:${#val}-2}"
  elif [[ "$val" == "'"*"'" ]]; then
    val="${val:1:${#val}-2}"
  fi

  # 最終トリム
  val="$(trim "$val")"

  # キー名検証（GitHub Secrets同様）
  if [[ ! "$key" =~ ^[A-Z0-9_]+$ ]]; then
    echo "  ! skip invalid key: $key" >&2
    continue
  fi

  printf '%s=%s\n' "$key" "$val" >> "$tmp_out"
done < "$in_file"

mv "$tmp_out" "$out_file"

echo "Wrote normalized KEY=VALUE pairs from ${in_file} to ${out_file}." >&2
echo "NOTE: ${out_file} includes sensitive values. Do not commit it. Remove after inspection." >&2
