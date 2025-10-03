#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash scripts/gh_set_env_secrets.sh <environment> <secrets_env_file> [<owner/repo>]
#
# Example:
#   bash scripts/gh_set_env_secrets.sh stage .github/env/stage.secrets kunihara/RINPA-kokosos-monorepo
#   bash scripts/gh_set_env_secrets.sh prod  .github/env/prod.secrets   # repo auto-detected (requires gh auth)
#
# The secrets_env_file format is simple KEY=VALUE lines. Lines starting with '#' or blank lines are ignored.

env_name="${1:-}"
file_path="${2:-}"
repo="${3:-}"

if [[ -z "${env_name}" || -z "${file_path}" ]]; then
  echo "Usage: bash scripts/gh_set_env_secrets.sh <environment> <secrets_env_file> [<owner/repo>]" >&2
  exit 1
fi

if [[ -z "${repo}" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is required. Install: https://cli.github.com/" >&2
    exit 1
  fi
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
fi

if [[ ! -f "${file_path}" ]]; then
  echo "Secrets file not found: ${file_path}" >&2
  exit 1
fi

echo "Setting secrets for ${repo} environment '${env_name}' from ${file_path}..." >&2

trim() { local s="$1"; s="${s#${s%%[![:space:]]*}}"; s="${s%${s##*[![:space:]]}}"; printf '%s' "$s"; }

while IFS= read -r raw || [[ -n "$raw" ]]; do
  # Normalize line endings (remove CR) and skip blanks/comments
  line="${raw%$'\r'}"
  [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue

  # Split at the first '=' only
  if [[ "$line" != *=""* && "$line" != *"="* ]]; then
    # Ensure there is an '=' present
    [[ "$line" != *"="* ]] && continue
  fi
  key="${line%%=*}"; val="${line#*=}"
  key="$(trim "$key")"; val="$(trim "$val")"

  # Strip surrounding single/double quotes from value if present
  if [[ "$val" == \"*\" && "$val" == *\" ]]; then
    val="${val:1:${#val}-2}"
  elif [[ "$val" == "'*'" || ( "$val" == "'"*"'" ) ]]; then
    # Generic single-quote stripper
    [[ ${#val} -ge 2 ]] && val="${val:1:${#val}-2}"
  fi

  # Safety: trim again after stripping quotes
  val="$(trim "$val")"

  # Basic key validation (GitHub secret naming): uppercase, digits, underscore
  if [[ ! "$key" =~ ^[A-Z0-9_]+$ ]]; then
    echo "  ! skip invalid key: $key" >&2
    continue
  fi

  printf '%s' "$val" | gh secret set "$key" --env "$env_name" -R "$repo" --body - >/dev/null
  # Masked preview
  if [[ ${#val} -gt 8 ]]; then
    echo "  ✓ $key (len=${#val})" >&2
  else
    echo "  ✓ $key" >&2
  fi
done < "$file_path"

echo "Done. You can verify with: gh secret list --env ${env_name} -R ${repo}" >&2
