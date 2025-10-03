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

while IFS= read -r raw || [[ -n "$raw" ]]; do
  # Trim CR and spaces
  line="${raw%$'\r'}"
  # Skip comments/blank
  [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
  # Split at first '='
  key="${line%%=*}"
  val="${line#*=}"
  key="${key## }"; key="${key%% }"
  if [[ -z "${key}" ]]; then continue; fi
  printf '%s' "${val}" | gh secret set "${key}" --env "${env_name}" -R "${repo}" --body - >/dev/null
  echo "  ✓ ${key}" >&2
done < "${file_path}"

echo "Done. You can verify with: gh secret list --env ${env_name} -R ${repo}" >&2

