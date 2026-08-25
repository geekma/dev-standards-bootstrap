#!/usr/bin/env bash
# A deterministic guard shared by local hooks, Git hooks, and CI.
# It deliberately validates evidence and execution state; it never trusts an
# agent's natural-language claim that a check has run.
set -euo pipefail

die() {
  echo "agent-gate: $*" >&2
  exit 2
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run inside a Git repository"
cd "$repo_root"

change_root="${AGENT_GUARD_CHANGE_ROOT:-docs/changes}"
required_docs=(00-governance.json 01-spec.md 03-modification-plan.md 04-test-scripts.md)
active_file=$(git rev-parse --git-path agent-governance/active-change)

is_code_path() {
  local path="$1"
  [[ "$path" =~ ^(docs/|\.github/|\.agent-governance/|README|AGENTS\.md|CLAUDE\.md|GEMINI\.md) ]] && return 1
  [[ "$path" =~ \.(c|cc|cpp|cs|go|java|js|jsx|kt|kts|php|py|rb|rs|scala|sh|sql|swift|ts|tsx|vue)$ ]]
}

required_docs_present() {
  local id="$1" doc
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid change id '$id'"
  for doc in "${required_docs[@]}"; do
    [[ -s "$change_root/$id/$doc" ]] || die "missing required artifact: $change_root/$id/$doc"
  done
}

json_string() {
  local file="$1" key="$2"
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -n 1
}

validate_governance_state() {
  local id="$1" file risk implementation test_owner review_owner declared_id
  file="$change_root/$id/00-governance.json"
  [[ -s "$file" ]] || die "missing required artifact: $file"
  declared_id=$(json_string "$file" change_id)
  [[ "$declared_id" == "$id" ]] || die "$file must declare change_id '$id'"
  risk=$(json_string "$file" risk_level)
  [[ "$risk" =~ ^L[0-3]$ ]] || die "$file must declare risk_level L0, L1, L2, or L3"
  implementation=$(json_string "$file" implementation_owner)
  [[ -n "$implementation" ]] || die "$file must declare implementation_owner"
  if [[ "$risk" == L2 || "$risk" == L3 ]]; then
    test_owner=$(json_string "$file" test_owner)
    review_owner=$(json_string "$file" review_owner)
    [[ -n "$test_owner" && -n "$review_owner" ]] || die "$file must declare test_owner and review_owner for $risk"
    [[ "$implementation" != "$test_owner" && "$implementation" != "$review_owner" && "$test_owner" != "$review_owner" ]] || die "$file requires distinct implementation, test, and review owners for $risk"
  fi
}

active_change() {
  [[ -s "$active_file" ]] || die "no active change. Create documents, then run: scripts/agent-gate begin CHG-123"
  tr -d '[:space:]' < "$active_file"
}

extract_file_from_hook_input() {
  # Claude Code, Cursor, Gemini CLI, and Copilot place tool arguments under
  # tool_input. This intentionally supports the common path field spellings
  # without adding jq/Python as a dependency.
  local input
  input=$(cat)
  printf '%s' "$input" | sed -nE 's/.*"(file_path|path|filePath|target_file)"[[:space:]]*:[[:space:]]*"([^"\\]+)".*/\2/p' | head -n 1
}

validate_active_change() {
  local id
  id=$(active_change)
  required_docs_present "$id"
  validate_governance_state "$id"
}

working_code_changed() {
  local files f
  files=$( {
    git diff --name-only --diff-filter=ACMR
    git diff --cached --name-only --diff-filter=ACMR
    git ls-files --others --exclude-standard
  } | sort -u)
  while IFS= read -r f; do
    is_code_path "$f" && return 0
  done <<< "$files"
  return 1
}

validate_stop() {
  local id
  working_code_changed || return 0
  validate_active_change
  id=$(active_change)
  [[ -s "$change_root/$id/05-test-results.md" ]] || die "cannot finish: missing test evidence $change_root/$id/05-test-results.md"
  [[ -s "$change_root/$id/09-changelog.md" ]] || die "cannot finish: missing changelog $change_root/$id/09-changelog.md"
  if [[ -n "${AGENT_GUARD_VERIFY_COMMAND:-}" ]]; then
    bash -lc "$AGENT_GUARD_VERIFY_COMMAND" || die "cannot finish: AGENT_GUARD_VERIFY_COMMAND failed"
  fi
}

changed_files() {
  local mode="$1" base="${2:-}"
  case "$mode" in
    staged) git diff --cached --name-only --diff-filter=ACMR ;; 
    branch)
      if [[ -n "$base" ]]; then git diff --name-only --diff-filter=ACMR "$base"...HEAD
      else git diff --name-only --diff-filter=ACMR HEAD~1...HEAD; fi ;;
    *) die "unknown diff mode '$mode'" ;;
  esac
}

validate_diff() {
  local mode="$1" base="${2:-}" files code_changed docs_changed f
  files=$(changed_files "$mode" "$base")
  [[ -n "$files" ]] || exit 0
  code_changed=false
  docs_changed=false
  while IFS= read -r f; do
    is_code_path "$f" && code_changed=true
    if [[ "$f" =~ ^${change_root}/([A-Za-z0-9._-]+)/[A-Za-z0-9._-]+$ ]]; then
      docs_changed=true
      # Staged/CI diffs are the only enforcement line for clients without
      # pre-write hooks, so the governance state must be validated here too.
      validate_governance_state "${BASH_REMATCH[1]}"
    fi
  done <<< "$files"

  if [[ "$code_changed" == true && "$docs_changed" != true ]]; then
    die "source changes require change artifacts under $change_root/<change-id>/ (spec, plan, test plan, evidence)"
  fi
}

command="${1:-help}"
case "$command" in
  begin)
    id="${2:-}"
    [[ -n "$id" ]] || die "usage: scripts/agent-gate begin <change-id>"
    required_docs_present "$id"
    mkdir -p "$(dirname "$active_file")"
    printf '%s\n' "$id" > "$active_file"
    echo "agent-gate: active change is $id"
    ;;
  end)
    rm -f "$active_file"
    echo "agent-gate: active change cleared"
    ;;
  --stage)
    stage="${2:-}"; shift 2
    case "$stage" in
      pre-write)
        file=""
        if [[ "${1:-}" == "--file" ]]; then file="${2:-}"
        else file=$(extract_file_from_hook_input); fi
        # A hook that cannot identify a path must fail closed: otherwise a
        # client schema change silently turns this policy into a no-op.
        [[ -n "$file" ]] || die "cannot determine the target file from hook input"
        is_code_path "$file" && validate_active_change
        ;;
      staged) validate_diff staged ;;
      stop) validate_stop ;;
      ci)
        base=""
        [[ "${1:-}" == "--base" ]] && base="${2:-}"
        validate_diff branch "$base"
        ;;
      *) die "unknown stage '$stage'" ;;
    esac
    ;;
  help|--help|-h)
    cat <<'EOF'
Usage:
  scripts/agent-gate begin <change-id>
  scripts/agent-gate end
  scripts/agent-gate --stage pre-write [--file path]
  scripts/agent-gate --stage staged
  scripts/agent-gate --stage stop
  scripts/agent-gate --stage ci [--base ref]

Configuration: set AGENT_GUARD_CHANGE_ROOT to change the default docs/changes root.
EOF
    ;;
  *) die "unknown command '$command'" ;;
esac
