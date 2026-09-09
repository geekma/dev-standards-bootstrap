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
# 00-intent.md is the pipeline entry point (problem / expected outcome / constraints);
# a change without a recorded intent is treated as undocumented work.
required_docs=(00-intent.md 00-governance.json 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md)
active_file=$(git rev-parse --git-path agent-governance/active-change)

is_code_path() {
  local path="$1"
  [[ "$path" =~ ^(docs/|\.github/|\.agent-governance/|README|AGENTS\.md|CLAUDE\.md|GEMINI\.md) ]] && return 1
  # 治理工具自身不是产品代码：安装/升级治理包的提交不需要变更产物（否则新仓库
  # 第一次 commit 即死锁——鸡生蛋）。它们由 §2.17.4 golden-case 回归背书。
  [[ "$path" =~ ^(\.githooks/|\.claude/|\.cursor/|\.gemini/|\.agent-governance\.yml$|scripts/agent-gate$|scripts/install-hook-adapter$|scripts/check-standards-compliance\.sh$|tests/run-tests\.sh$|tests/audit-docs-consistency\.sh$) ]] && return 1
  [[ "$path" =~ \.(c|cc|cpp|cs|go|java|js|jsx|kt|kts|php|py|rb|rs|scala|sh|sql|swift|ts|tsx|vue)$ ]]
}

required_docs_present() {
  local id="$1" doc
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid change id '$id'"
  for doc in "${required_docs[@]}"; do
    [[ -s "$change_root/$id/$doc" ]] || die "missing required artifact: $change_root/$id/$doc"
  done
  validate_artifact_content "$id"
}

# --- A-layer artifact content checks (DEVELOPMENT_STANDARDS §2.5) -----------
# Presence alone is not acceptance: a hollow skeleton with no numbering system
# must not pass as a complete artifact set. These checks are deterministic
# greps; quality judgment (B layer) stays with independent roles.
validate_artifact_content() {
  local id="$1" d="$change_root/$id"
  grep -q "预期结果" "$d/00-intent.md" \
    || die "$d/00-intent.md missing expected-outcome section (A-layer acceptance, standards §2.5)"
  grep -q "开放问题" "$d/00-intent.md" \
    || die "$d/00-intent.md missing open-questions section (A-layer acceptance, standards §2.5)"
  grep -q "REQ-" "$d/01-spec.md" \
    || die "$d/01-spec.md has no REQ- numbering (A-layer acceptance, standards §2.5)"
  grep -q "DES-" "$d/03-modification-plan.md" \
    || die "$d/03-modification-plan.md has no DES- numbering (A-layer acceptance, standards §2.5)"
  grep -q "TC-" "$d/04-test-scripts.md" \
    || die "$d/04-test-scripts.md has no TC- numbering (A-layer acceptance, standards §2.5)"
  # v3.3.0 scenario inventory: business scenarios enumerated with SC-
  # numbering and mapped to TCs (standards §2.5 stage 4).
  grep -q "SC-" "$d/04-test-scripts.md" \
    || die "$d/04-test-scripts.md has no SC- scenario numbering (A-layer, standards §2.5 stage 4, v3.3.0)"
  # v2.20.0 professional-role markers: option comparison in the plan and a
  # coverage-dimension column in the test matrix (standards §2.5 stages 3-4).
  grep -qE "备选|选型" "$d/03-modification-plan.md" \
    || die "$d/03-modification-plan.md has no option-comparison (备选/选型) content (A-layer, standards §2.5 stage 3)"
  grep -q "覆盖维度" "$d/04-test-scripts.md" \
    || die "$d/04-test-scripts.md has no coverage-dimension (覆盖维度) column (A-layer, standards §2.5 stage 4)"
  # Stage 2 is unconditional: "analyze before designing" (standards §2.5
  # stage 2) is a hard gate, not an optional extra. 03.5 may alternatively
  # carry an explicit no-breakdown exemption marker instead of task rows.
  grep -q "业务影响" "$d/02-code-impact-analysis.md" \
    || die "$d/02-code-impact-analysis.md missing business-impact (业务影响) section (A-layer, standards §2.5 stage 2)"
  grep -q "风险" "$d/02-code-impact-analysis.md" \
    || die "$d/02-code-impact-analysis.md missing risk (风险) content (A-layer, standards §2.5 stage 2)"
  grep -q "回滚策略" "$d/02-code-impact-analysis.md" \
    || die "$d/02-code-impact-analysis.md missing rollback (回滚策略) content (A-layer, standards §2.5 stage 2)"
  if ! grep -qE "直接实施|未拆任务" "$d/03.5-tasks.md"; then
    grep -q "依赖" "$d/03.5-tasks.md" \
      || die "$d/03.5-tasks.md missing dependency (依赖) info (A-layer, standards §2.5 stage 3)"
    grep -q "里程碑" "$d/03.5-tasks.md" \
      || die "$d/03.5-tasks.md missing milestone (里程碑) info (A-layer, standards §2.5 stage 3)"
  fi
}

json_string() {
  local file="$1" key="$2"
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -n 1
}

# Placeholder owner values are governance debt, not a real assignment: an
# owner set to PENDING/TODO/TBD/待定 must fail the gate now instead of
# silently passing role-independence checks later. (v3.5.0)
reject_placeholder_owner() { # file field value
  local file="$1" field="$2" value="$3" norm
  norm=$(printf '%s' "$value" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
  case "$norm" in
    PENDING|TODO|TBD|*待定*) die "$file field '$field' must name a concrete owner (placeholder '$value' rejected)" ;;
  esac
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
  reject_placeholder_owner "$file" implementation_owner "$implementation"
  if [[ "$risk" == L2 || "$risk" == L3 ]]; then
    test_owner=$(json_string "$file" test_owner)
    review_owner=$(json_string "$file" review_owner)
    [[ -n "$test_owner" && -n "$review_owner" ]] || die "$file must declare test_owner and review_owner for $risk"
    reject_placeholder_owner "$file" test_owner "$test_owner"
    reject_placeholder_owner "$file" review_owner "$review_owner"
    [[ "$implementation" != "$test_owner" && "$implementation" != "$review_owner" && "$test_owner" != "$review_owner" ]] || die "$file requires distinct implementation, test, and review owners for $risk"
  fi
  # v3.5.0 L3 release authorization: flat string fields, not a nested object —
  # json_string extracts with a single-line sed, so nested JSON cannot parse.
  if [[ "$risk" == L3 ]]; then
    local auth_by auth_at auth_ev
    auth_by=$(json_string "$file" release_authorized_by)
    auth_at=$(json_string "$file" release_authorized_at)
    auth_ev=$(json_string "$file" release_authorization_evidence)
    [[ -n "$auth_by" ]] || die "$file must declare release_authorized_by for L3"
    reject_placeholder_owner "$file" release_authorized_by "$auth_by"
    [[ -n "$auth_at" ]] || die "$file must declare release_authorized_at for L3"
    [[ -n "$auth_ev" ]] || die "$file must declare release_authorization_evidence for L3"
  fi
  # v3.6.0 bug document set: an optional flat bug_ref binds this change to a
  # defect document group under docs/bugs/<bug_ref>/; when declared, the
  # three-file set must exist and be non-empty (standards §2.5 stage 6).
  local bug_ref bugs_root
  bug_ref=$(json_string "$file" bug_ref)
  if [[ -n "$bug_ref" ]]; then
    [[ "$bug_ref" =~ ^[A-Za-z0-9._-]+$ ]] || die "$file field 'bug_ref' has invalid defect id '$bug_ref'"
    bugs_root="${AGENT_GUARD_BUGS_ROOT:-docs/bugs}"
    for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md; do
      [[ -s "$bugs_root/$bug_ref/$doc" ]] || die "$file bug_ref '$bug_ref' is missing defect document: $bugs_root/$bug_ref/$doc"
    done
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

# Delivery evidence a change must carry before it may leave the machine:
# test results, a changelog, and the v2.21.0 ReAct Observation records in it
# (standards §2.16.2). Shared by --stage stop and branch-mode CI so both
# enforcement lines hold the same bar. (v3.5.0)
validate_delivery() { # change-id
  local id="$1" d="$change_root/$id"
  [[ -s "$d/05-test-results.md" ]] || die "cannot finish: missing test evidence $d/05-test-results.md"
  [[ -s "$d/09-changelog.md" ]] || die "cannot finish: missing changelog $d/09-changelog.md"
  # Every executed stage must leave an Observation record (verification
  # command + actual output) in the changelog.
  grep -q "Observation" "$d/09-changelog.md" \
    || die "cannot finish: changelog missing ReAct Observation records (standards §2.16.2)"
}

validate_stop() {
  local id
  working_code_changed || return 0
  validate_active_change
  id=$(active_change)
  validate_delivery "$id"
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

complete_valid_change_exists() {
  # True when at least one change directory carries the full required artifact
  # set with a valid governance state. Local staged commits rely on this when
  # code is committed after the artifacts landed in an earlier commit of the
  # same change (the documented workflow: artifacts first, implementation later).
  # KNOWN LIMITATION (narrowed in v3.5.0): staged mode still cannot attribute
  # code to a specific change id — a complete set of ANY change satisfies it.
  # --stage commit-msg now pins per-commit attribution and branch-mode CI
  # (pre-push) enforces delivery evidence per touched change; residual
  # cross-change drift stays a B-layer (review) responsibility.
  local dir id doc complete
  [[ -d "$change_root" ]] || return 1
  for dir in "$change_root"/*/; do
    [[ -d "$dir" ]] || continue
    id=$(basename "$dir")
    [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    complete=true
    for doc in "${required_docs[@]}"; do
      [[ -s "$dir/$doc" ]] || { complete=false; break; }
    done
    if [[ "$complete" == true ]] \
       && ( validate_governance_state "$id" ) >/dev/null 2>&1 \
       && ( validate_artifact_content "$id" ) >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

validate_diff() {
  local mode="$1" base="${2:-}" files code_changed docs_changed f id seen_ids
  files=$(changed_files "$mode" "$base")
  [[ -n "$files" ]] || exit 0
  code_changed=false
  docs_changed=false
  seen_ids=""
  while IFS= read -r f; do
    is_code_path "$f" && code_changed=true
    if [[ "$f" =~ ^${change_root}/([A-Za-z0-9._-]+)/[A-Za-z0-9._-]+$ ]]; then
      docs_changed=true
      id="${BASH_REMATCH[1]}"
      case " $seen_ids " in
        *" $id "*) ;;
        *) seen_ids="$seen_ids $id" ;;
      esac
      # Staged/CI diffs are the only enforcement line for clients without
      # pre-write hooks, so the governance state must be validated here too.
      validate_governance_state "$id"
    fi
  done <<< "$files"

  # v3.5.0: branch-mode CI additionally requires delivery evidence (test
  # results + changelog with ReAct Observation) for every change touched by
  # the diff — the same bar --stage stop holds. Staged stays lenient: it is a
  # local fast signal over repo state; stop/ci close the evidence loop.
  if [[ "$mode" == branch ]]; then
    for id in $seen_ids; do
      validate_delivery "$id"
    done
  fi

  if [[ "$code_changed" == true && "$docs_changed" != true ]]; then
    # Staged is a local hook: repo state is authoritative, so code may follow an
    # earlier artifacts-only commit of the same change. CI keeps the stricter
    # rule: the branch diff itself must carry the artifact changes.
    if [[ "$mode" == staged ]] && complete_valid_change_exists; then
      return 0
    fi
    die "source changes require change artifacts under $change_root/<change-id>/ (spec, plan, test plan, evidence)"
  fi
}

# Attribution gate (v3.5.0): a code-bearing commit must reference its change
# id so the gate and the pipeline metrics share one definition of ownership.
# Exemption ladder: merge commits (MERGE_HEAD present), reverts, and commits
# touching no code path pass without an id. An id-bearing code commit must
# point at a change that exists with a valid governance state.
validate_commit_msg() { # message-file
  local msgfile="$1" msg f id files code_found=false
  [[ -s "$msgfile" ]] || die "commit message file is empty"
  msg=$(cat "$msgfile")
  # Ladder written in if-form: a bare `[[ x ]] && return` leaves the whole
  # statement returning 1 on the fall-through path, which a commit-msg hook
  # would read as rejection.
  if [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]]; then return 0; fi
  if [[ "$msg" =~ ^Revert ]]; then return 0; fi
  files=$(git diff --cached --name-only --diff-filter=ACMR)
  while IFS= read -r f; do
    if is_code_path "$f"; then code_found=true; fi
  done <<< "$files"
  if [[ "$code_found" != true ]]; then return 0; fi
  # `|| true` guards the pipefail case: grep exits 1 when the message carries
  # no id, and the assignment must not abort the gate before the die below.
  id=$(printf '%s\n' "$msg" | grep -Eo '[A-Z][A-Z0-9_]*-[0-9]+' | head -n 1 || true)
  if [[ -z "$id" ]]; then
    die "code commit must reference its change id (e.g. 'feat: CHG-123 implement ...')"
  fi
  required_docs_present "$id"
  validate_governance_state "$id"
}

# --- metrics ---------------------------------------------------------------
# Pipeline metrics derived purely from git history (JSON Lines, one object per
# change). Zero third-party dependencies: timestamps come from git, values are
# either numbers or null. Semantics:
#   *_ts           epoch seconds of the commit that first added the artifact
#   first_code_commit_ts  earliest commit whose message references the change id
#   *_s            stage interval in seconds (null when either endpoint is missing)
first_commit_ts() {
  local out
  out=$(git log --format=%ct --diff-filter=A -- "$1" 2>/dev/null | tail -n 1)
  printf '%s' "$out"
}

first_commit_referencing() {
  local line esc
  # v3.5.0: word-boundary match so id "CUSTOM-1" cannot match a subject
  # mentioning "CUSTOM-10" (prefix collision); the id is regex-escaped first.
  esc=$(printf '%s' "$1" | sed 's/[][\.*^$]/\\&/g')
  line=$(git log --reverse --format='%ct|%s' | grep -E -m1 -- "(^|[^A-Za-z0-9])${esc}([^A-Za-z0-9]|$)" || true)
  [[ -n "$line" ]] && printf '%s' "${line%%|*}"
  # 空匹配时上面 [[ ]] 返回 1；显式 return 0，防止调用方 $( ) 赋值在 set -e 下中断
  # （真实场景：变更产物尚未提交时跑 metrics，T7 golden case 覆盖）。
  return 0
}

ts_or_null() {
  [[ -n "${1:-}" ]] && printf '%s' "$1" || printf 'null'
}

delta_or_null() {
  local newer="${1:-}" older="${2:-}"
  if [[ -n "$newer" && -n "$older" && "$newer" =~ ^[0-9]+$ && "$older" =~ ^[0-9]+$ && "$newer" -ge "$older" ]]; then
    printf '%s' "$(( newer - older ))"
  else
    printf 'null'
  fi
}

delivery_ready() {
  local d="$1"
  if [[ -s "$d/05-test-results.md" && -s "$d/07-review-report.md" && -s "$d/09-changelog.md" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

emit_metrics() {
  local dir id risk t_intent t_gov t_spec t_plan t_test t_chg t_code
  [[ -d "$change_root" ]] || exit 0
  for dir in "$change_root"/*/; do
    [[ -d "$dir" ]] || continue
    id=$(basename "$dir")
    [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    if [[ -s "$dir/00-governance.json" ]]; then
      risk=$(json_string "$dir/00-governance.json" risk_level)
      # Emit a valid JSON string value; null stays unquoted.
      if [[ "$risk" =~ ^L[0-3]$ ]]; then risk="\"$risk\""; else risk=null; fi
    else
      risk=null
    fi
    t_intent=$(first_commit_ts "$dir/00-intent.md")
    t_gov=$(first_commit_ts "$dir/00-governance.json")
    t_spec=$(first_commit_ts "$dir/01-spec.md")
    t_plan=$(first_commit_ts "$dir/03-modification-plan.md")
    t_test=$(first_commit_ts "$dir/05-test-results.md")
    t_chg=$(first_commit_ts "$dir/09-changelog.md")
    t_code=$(first_commit_referencing "$id")
    printf '{"change_id":"%s","risk_level":%s,"intent_ts":%s,"governance_ts":%s,"spec_ts":%s,"plan_ts":%s,"first_code_commit_ts":%s,"test_evidence_ts":%s,"changelog_ts":%s,"intent_to_spec_s":%s,"spec_to_plan_s":%s,"plan_to_code_s":%s,"code_to_evidence_s":%s,"intent_to_changelog_s":%s,"delivery_ready":%s}\n' \
      "$id" "$risk" \
      "$(ts_or_null "$t_intent")" "$(ts_or_null "$t_gov")" "$(ts_or_null "$t_spec")" \
      "$(ts_or_null "$t_plan")" "$(ts_or_null "$t_code")" "$(ts_or_null "$t_test")" \
      "$(ts_or_null "$t_chg")" \
      "$(delta_or_null "$t_spec" "$t_intent")" \
      "$(delta_or_null "$t_plan" "$t_spec")" \
      "$(delta_or_null "$t_code" "$t_plan")" \
      "$(delta_or_null "$t_test" "$t_code")" \
      "$(delta_or_null "$t_chg" "$t_intent")" \
      "$(delivery_ready "$dir")"
  done
}

command="${1:-help}"
case "$command" in
  begin)
    id="${2:-}"
    [[ -n "$id" ]] || die "usage: scripts/agent-gate begin <change-id>"
    required_docs_present "$id"
    validate_governance_state "$id"
    mkdir -p "$(dirname "$active_file")"
    printf '%s\n' "$id" > "$active_file"
    echo "agent-gate: active change is $id"
    ;;
  end)
    rm -f "$active_file"
    echo "agent-gate: active change cleared"
    ;;
  metrics)
    emit_metrics
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
        if is_code_path "$file"; then
          validate_active_change
        fi
        ;;
      staged) validate_diff staged ;;
      stop) validate_stop ;;
      ci)
        base=""
        if [[ "${1:-}" == "--base" ]]; then base="${2:-}"; fi
        validate_diff branch "$base"
        ;;
      commit-msg)
        msgfile="${1:-}"
        if [[ -z "$msgfile" ]]; then
          die "usage: scripts/agent-gate --stage commit-msg <message-file>"
        fi
        validate_commit_msg "$msgfile"
        ;;
      *) die "unknown stage '$stage'" ;;
    esac
    ;;
  help|--help|-h)
    cat <<'EOF'
Usage:
  scripts/agent-gate begin <change-id>
  scripts/agent-gate end
  scripts/agent-gate metrics
  scripts/agent-gate --stage pre-write [--file path]
  scripts/agent-gate --stage staged
  scripts/agent-gate --stage stop
  scripts/agent-gate --stage ci [--base ref]
  scripts/agent-gate --stage commit-msg <message-file>

begin requires seven non-empty artifacts under the change root:
00-intent.md, 00-governance.json, 01-spec.md, 02-code-impact-analysis.md,
03-modification-plan.md, 03.5-tasks.md, 04-test-scripts.md. It also enforces
A-layer content checks (standards §2.5): 00-intent.md must contain the
expected-outcome and open-questions sections; 01-spec.md must use REQ-
numbering; 02 must cover business impact, risk and rollback; 03-modification-
plan.md must use DES- numbering plus option comparison; 03.5-tasks.md must
carry dependencies/milestones or an explicit no-breakdown exemption; 04-test-
scripts.md must use TC- numbering, a coverage-dimension column, and SC-
scenario numbering. Hollow skeletons fail.

commit-msg attribution (v3.5.0): a code-bearing commit message must
reference its change id (e.g. 'feat: CHG-123 implement ...'); the referenced
change must exist with a valid governance state. Merge commits, reverts, and
commits that touch no code path are exempt.

metrics prints one JSON object per change (JSON Lines) with stage timestamps
and intervals derived from git history; pipe it to a CI artifact for trending.

Configuration: set AGENT_GUARD_CHANGE_ROOT to change the default docs/changes root.
EOF
    ;;
  *) die "unknown command '$command'" ;;
esac
