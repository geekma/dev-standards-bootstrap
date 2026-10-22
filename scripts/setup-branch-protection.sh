#!/usr/bin/env bash
# setup-branch-protection.sh — one-time remote setting for this repository's
# required check. Source-layer only: it is never shipped and never runs in CI.
#
# Default is a DRY RUN: prints the exact gh api payload and changes nothing.
# Applying requires an admin token and the explicit --apply flag; the script
# does not read, store, or print credentials.
#
#   scripts/setup-branch-protection.sh --repo owner/name
#   scripts/setup-branch-protection.sh --repo owner/name --apply
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: setup-branch-protection.sh --repo <owner>/<name> [--branch <name>]
                                  [--check <context>[,<context>...]] [--apply]

  --repo     GitHub repository (required)
  --branch   protected branch (default: main)
  --check    required status check contexts (default: agent-governance)
  --apply    mutate the remote (default: dry run, prints the payload)
USAGE
}

repo=""
branch="main"
checks="agent-governance"
apply=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 2>/dev/null || shift $# ;;
    --branch) branch="${2:-}"; shift 2 2>/dev/null || shift $# ;;
    --check) checks="${2:-}"; shift 2 2>/dev/null || shift $# ;;
    --apply) apply=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "setup-branch-protection: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "setup-branch-protection: --repo must be owner/name (alnum, dot, underscore, hyphen)" >&2; exit 2; }
case "$branch" in ''|*[!A-Za-z0-9._/-]*) echo "setup-branch-protection: invalid branch name" >&2; exit 2 ;; esac
branch_url=$(printf '%s' "$branch" | sed 's|/|%2F|g')

# Validate every check name: JSON-escape safety is enforced by construction (the
# allowlist below excludes quotes, backslashes and control characters).
ctx_json=$(printf '%s' "$checks" | awk -F',' '
  { for (i=1;i<=NF;i++) {
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",$i)
      if ($i=="") continue
      if ($i !~ /^[A-Za-z0-9 ._\/-]+$/) { print "INVALID"; exit }
      printf "%s\"%s\"", (n++?",":""), $i
    }
  }')
[[ "$ctx_json" == *INVALID* || -z "$ctx_json" ]] && { echo "setup-branch-protection: --check names may contain only alnum, space, dot, underscore, slash, hyphen" >&2; exit 2; }

payload=$(cat <<JSON
{
  "required_status_checks": {"strict": true, "contexts": [$ctx_json]},
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
)

echo "repository: $repo"
echo "branch:     $branch"
echo "checks:     $checks"
echo "payload:"
printf '%s\n' "$payload"

if [[ "$apply" != 1 ]]; then
  echo "dry run: no remote change. Re-run with --apply and an admin token to enforce." >&2
  exit 0
fi

command -v gh >/dev/null 2>&1 || { echo "setup-branch-protection: gh CLI is required for --apply" >&2; exit 2; }
printf '%s\n' "$payload" | gh api --method PUT "repos/$repo/branches/$branch_url/protection" --input - >/dev/null
gh api "repos/$repo/branches/$branch_url/protection" --jq '.required_status_checks.contexts'
