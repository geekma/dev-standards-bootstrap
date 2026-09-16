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

# --- path roots (v3.15.0) ---------------------------------------------------
# Directory ROOTS are configurable; each built-in default IS the historical
# hardcoded value, so a repo without a `paths:` block behaves exactly as before.
# Precedence: AGENT_GUARD_<KEY>_DIR env > .agent-governance.yml > built-in default.
# Only roots are configurable. Contract names (AGENTS.md, the gate filename, the
# twelve change artifacts, the six defect artifacts, the required-check name) are
# deliberately NOT configurable: making them configurable would break cross-repo
# comparison and migration, which is the point of this package.
cfg_path() { # key default
  local k="$1" d="$2" v=""
  if [[ -f ".agent-governance.yml" ]]; then
    v=$(sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" .agent-governance.yml 2>/dev/null \
        | head -n 1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$v" ]] || v="$d"
  printf '%s' "$v"
}
docs_dir="${AGENT_GUARD_DOCS_DIR:-$(cfg_path docs docs)}"
scripts_dir="${AGENT_GUARD_SCRIPTS_DIR:-$(cfg_path scripts scripts)}"
tests_dir="${AGENT_GUARD_TESTS_DIR:-$(cfg_path tests tests)}"
githooks_dir="${AGENT_GUARD_GITHOOKS_DIR:-$(cfg_path githooks .githooks)}"
# `.github/` is deliberately NOT configurable: GitHub only reads workflows from
# .github/workflows and PR templates from .github/ — renaming it silently kills
# the pipeline, so a knob there would be a lie.
# change_root / bugs_root keep their own keys and env vars; their default is
# derived from the docs root, which is what the shipped config documents.
change_root="${AGENT_GUARD_CHANGE_ROOT:-$(cfg_path change_root "$docs_dir/changes")}"
bugs_root="${AGENT_GUARD_BUGS_ROOT:-$(cfg_path bugs_root "$docs_dir/bugs")}"
# regex-safe forms for the path-classification tests below (defaults contain a
# literal dot: .githooks)
re_escape() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
docs_re=$(re_escape "$docs_dir")
scripts_re=$(re_escape "$scripts_dir")
tests_re=$(re_escape "$tests_dir")
githooks_re=$(re_escape "$githooks_dir")
change_root_re=$(re_escape "$change_root")
# 00-intent.md is the pipeline entry point (problem / expected outcome / constraints);
# a change without a recorded intent is treated as undocumented work.
required_docs=(00-intent.md 00-governance.json 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md)
active_file=$(git rev-parse --git-path agent-governance/active-change)

# --- change batches (v3.18.0, standards §1.1) -------------------------------
# Same-day L0/L1 changes MAY share one `<change_root>/BATCH-YYYYMMDD/` directory
# instead of one directory per change. What is deliberately NOT changed is the
# ARTIFACT NAMES: the twelve files keep their exact names, so every "find by
# name" path in the gate, the audit, and the target repo keeps working. Only the
# containing directory differs, and each artifact carries a `## CHG-xxx` section
# anchor that tells the bundled changes apart. That anchor is what makes a batch
# addressable without a JSON/YAML parser.
#
# Resolution order (first hit wins):
#   1. a dedicated `<change_root>/<id>/` directory — the historical layout, and
#      it always wins so existing repos are untouched;
#   2. AGENT_GUARD_CHANGE_DIR — explicit override for tooling/tests;
#   3. a BATCH-*/ directory containing a `## <id>` anchor.
# If nothing matches we return the canonical dedicated path, so error messages
# keep naming the path the user is expected to create.
change_dir() { # <change-id> -> directory
  # NOTE (bash 3.2): `local` expands every word BEFORE assigning any of them, so
  # a second assignment may not reference the first. Keep declarations split.
  local id="$1"
  local d="$change_root/$id" b
  [[ -d "$d" ]] && { printf '%s' "$d"; return 0; }
  if [[ -n "${AGENT_GUARD_CHANGE_DIR:-}" && -d "${AGENT_GUARD_CHANGE_DIR:-}" ]]; then
    printf '%s' "$AGENT_GUARD_CHANGE_DIR"; return 0
  fi
  for b in "$change_root"/BATCH-*/; do
    [[ -d "$b" ]] || continue
    if grep -qE "$(anchor_re "$id")" "$b"/*.md 2>/dev/null; then
      printf '%s' "${b%/}"; return 0
    fi
  done
  printf '%s' "$d"
}

is_batch_dir() { # <dir> -> 0 if it is a BATCH-YYYYMMDD directory
  [[ "$(basename "$1")" =~ ^BATCH-[0-9]{8}$ ]]
}

# Section anchor pattern: `## <change-id>` (optionally followed by more words).
# Requires a separator after the id so a heading like `## 00-intent.md` is not
# mistaken for a change. Shared by change_dir() and anchors_in_file() so the
# resolver and the scanners can never disagree about what an anchor is.
anchor_re() { printf '^##[[:space:]]+%s([[:space:]]|$)' "$1"; }

# The one place that parses anchors out of a file (see anchor_re for the shape).
anchors_in_file() { # <file> -> ids, one per line
  [[ -f "$1" ]] || return 0
  sed -nE 's/^##[[:space:]]+([A-Za-z0-9][A-Za-z0-9_-]*)([[:space:]].*)?$/\1/p' "$1" 2>/dev/null | sort -u
}

# The AUTHORITATIVE roster of a batch: the change ids declared in its
# 00-governance.json, one per line. This — not the set of `## <heading>` lines —
# is what defines "which changes live here".
#
# v3.19.0 fix: the anchor scan used to serve as the roster, but `## <heading>`
# cannot tell a change section from a structural one, and the standards REQUIRE
# structural headings inside the shared artifacts (e.g. `## Observation` in
# 09-changelog.md, §2.16.2). Reading those as change ids produced a phantom
# `{"change_id":"Observation"}` row in `metrics` and made `--stage staged`/`ci`
# reject a perfectly valid batch ("declares no governance record for
# 'Observation'") — a gate that fails on a heading the standards mandate.
gov_ids() { # <governance-file> -> declared change ids, one per line
  [[ -s "$1" ]] || return 0
  grep -oE '"change_id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9._-]+"' "$1" 2>/dev/null \
    | sed -E 's/.*"([A-Za-z0-9._-]+)"$/\1/' | sort -u || true
}

# Which change ids does a directory address? A dedicated <CHG>/ directory names
# exactly one (its basename); a batch names every change its roster declares.
# The diff and metrics scans walk DIRECTORIES rather than starting from an id,
# so they need this direction of the mapping.
# Fallback: with no readable roster there is nothing authoritative to report, so
# the anchors are used as a best effort — that keeps a missing/empty
# 00-governance.json surfacing as a concrete error instead of a silent no-op.
change_ids_in_dir() { # <dir> -> ids, one per line
  local d="$1" f roster
  if is_batch_dir "$d"; then
    roster=$(gov_ids "$d/00-governance.json")
    if [[ -n "$roster" ]]; then
      printf '%s\n' "$roster"
      return 0
    fi
    for f in "$d"/*.md; do
      [[ -f "$f" ]] || continue
      anchors_in_file "$f"
    done | sort -u
  else
    basename "$d"
  fi
}

# Governance records are JSON, and JSON has no meaningful newlines: a
# pretty-printed single object and a one-object-per-line batch carry the SAME
# data. The reader used to be line-oriented (`grep ... | head -1`), which made
# those two shapes behave completely differently — and because the SHIPPED
# template `resources/templates/governance-state.json`, which SKILL.md tells the
# agent to turn into `00-governance.json`, is pretty-printed, following the
# documented workflow produced a record the gate REFUSED with
#   "00-governance.json must declare risk_level L0, L1, L2, or L3"
# while the field sat two lines below the `change_id`. Measured on this repo's
# own ledger: 16 of 16 records (CHG-001..016) are multi-line, so all 16 would
# have been rejected by the gate that ships with them. `metrics` reported
# `"risk_level":null` for every one of them.
#
# v3.20.0 fix: flatten the file, split on top-level object boundaries, then
# select by change_id. Any valid JSON layout now reads identically — the
# one-object-per-line batch convention stays legal (and stays recommended: it
# keeps per-change diffs reviewable), it is simply no longer a PARSER
# requirement. The batch clause in the standards still tells authors to write
# one object per line; that is now a style rule, not a load-bearing one.
#
# Records stay FLAT (no nested objects): `json_field` is still a single-line
# sed, and the L3 release-authorization fields are deliberately flat strings for
# that reason. Flattening does not weaken that contract.
gov_record() { # <governance-file> <change-id> -> that change's JSON object, one line
  local file="$1" id="$2"
  local flat
  [[ -s "$file" ]] || return 0
  # `|| true` is load-bearing: the gate runs under `set -euo pipefail`, so a
  # no-match grep would abort the whole script (exit 1, no message) instead of
  # returning an empty record the caller can turn into a precise diagnostic.
  flat=$(tr -d '\n\r' < "$file" 2>/dev/null) || return 0
  # Split between sibling objects. Both separators must be handled: batches are
  # written as bare consecutive objects (newline-separated, no comma) while a
  # JSON array or a `jq`-formatted file puts a comma between them. The optional
  # `,?` covers both. A `}{` sequence INSIDE a string value would split there
  # too — accepted: records are flat strings and `change_id` is never last, so
  # the worst case is a truncated record, never a sibling's fields.
  printf '%s' "$flat" \
    | sed -E 's/\}[[:space:]]*,?[[:space:]]*\{/}\n{/g' 2>/dev/null \
    | grep -E "\"change_id\"[[:space:]]*:[[:space:]]*\"${id}\"" 2>/dev/null \
    | head -n 1 || true
}

json_field() { # <json-line> <key> -> value
  local line="$1" key="$2"
  printf '%s' "$line" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" 2>/dev/null | head -n 1 || true
}

is_code_path() {
  local path="$1"
  [[ "$path" =~ ^(${docs_re}/|\.github/|\.agent-governance/|README|AGENTS\.md|CLAUDE\.md|GEMINI\.md) ]] && return 1
  # 治理工具自身不是产品代码：安装/升级治理包的提交不需要变更产物（否则新仓库
  # 第一次 commit 即死锁——鸡生蛋）。它们由 §2.17.4 golden-case 回归背书。
  # v3.17.0：**新增治理脚本必须同步加进本清单**——stamp-provenance.sh 漏加时，
  # 全新安装后的第一次 commit 会被判为"源码变更"而拦下（T15 D5 用例实测暴露）。
  [[ "$path" =~ ^(${githooks_re}/|\.claude/|\.cursor/|\.gemini/|\.agent-governance\.yml$|${scripts_re}/agent-gate$|${scripts_re}/install-hook-adapter$|${scripts_re}/check-standards-compliance\.sh$|${scripts_re}/stamp-provenance\.sh$|${tests_re}/run-tests\.sh$|${tests_re}/audit-docs-consistency\.sh$) ]] && return 1
  [[ "$path" =~ \.(c|cc|cpp|cs|go|java|js|jsx|kt|kts|php|py|rb|rs|scala|sh|sql|swift|ts|tsx|vue)$ ]]
}

required_docs_present() {
  local id="$1" doc d
  # FU-023: ids must start alphanumeric, then alnum/_/- only — no dots at all
  # (kills "-foo", "foo.", "a..b"; existing CHG-xxx / BUG-<ts> forms all pass).
  [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "invalid change id '$id' (start with [A-Za-z0-9], then alnum/_/-; no dots)"
  d=$(change_dir "$id")
  for doc in "${required_docs[@]}"; do
    [[ -s "$d/$doc" ]] || die "missing required artifact: $d/$doc"
  done
  validate_artifact_content "$id"
}

# --- A-layer artifact content checks (DEVELOPMENT_STANDARDS §2.5) -----------
# Presence alone is not acceptance: a hollow skeleton with no numbering system
# must not pass as a complete artifact set. These checks are deterministic
# greps; quality judgment (B layer) stays with independent roles.
validate_artifact_content() {
  local id="$1" d
  d=$(change_dir "$id")
  grep -q "预期结果" "$d/00-intent.md" \
    || die "$d/00-intent.md missing expected-outcome section (A-layer acceptance, standards §2.5)"
  grep -q "开放问题" "$d/00-intent.md" \
    || die "$d/00-intent.md missing open-questions section (A-layer acceptance, standards §2.5)"
  grep -qE "REQ-[0-9]+" "$d/01-spec.md" \
    || die "$d/01-spec.md has no REQ- numbering (A-layer acceptance, standards §2.5)"
  grep -qE "DES-[0-9]+" "$d/03-modification-plan.md" \
    || die "$d/03-modification-plan.md has no DES- numbering (A-layer acceptance, standards §2.5)"
  grep -qE "TC-[0-9]+" "$d/04-test-scripts.md" \
    || die "$d/04-test-scripts.md has no TC- numbering (A-layer acceptance, standards §2.5)"
  # v3.3.0 scenario inventory: business scenarios enumerated with SC-
  # numbering and mapped to TCs (standards §2.5 stage 4).
  grep -qE "SC-[0-9]+" "$d/04-test-scripts.md" \
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
  # FU-008: the keyword must sit in a structural position (heading / table row /
  # bold list item), not anywhere in prose — a negated or passing mention like
  # "本变更无业务影响" used to satisfy a bare substring grep.
  grep -qE "^(#{1,6}[[:space:]].*业务影响|\|.*业务影响|[[:space:]]*[-*][[:space:]]+\*\*业务影响)" "$d/02-code-impact-analysis.md" \
    || die "$d/02-code-impact-analysis.md missing business-impact (业务影响) section (A-layer, standards §2.5 stage 2)"
  grep -qE "^(#{1,6}[[:space:]].*风险|\|.*风险|[[:space:]]*[-*][[:space:]]+\*\*风险)" "$d/02-code-impact-analysis.md" \
    || die "$d/02-code-impact-analysis.md missing risk (风险) content (A-layer, standards §2.5 stage 2)"
  grep -qE "^(#{1,6}[[:space:]].*回滚策略|\|.*回滚策略|[[:space:]]*[-*][[:space:]]+\*\*回滚策略)" "$d/02-code-impact-analysis.md" \
    || die "$d/02-code-impact-analysis.md missing rollback (回滚策略) content (A-layer, standards §2.5 stage 2)"
  if ! grep -qE "直接实施|未拆任务" "$d/03.5-tasks.md"; then
    grep -q "依赖" "$d/03.5-tasks.md" \
      || die "$d/03.5-tasks.md missing dependency (依赖) info (A-layer, standards §2.5 stage 3)"
    grep -q "里程碑" "$d/03.5-tasks.md" \
      || die "$d/03.5-tasks.md missing milestone (里程碑) info (A-layer, standards §2.5 stage 3)"
  fi
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

# v3.17.0 file provenance (standards §1.1). The block is written by
# scripts/stamp-provenance.sh from the RUNNING ENVIRONMENT (git identity,
# hostname, platform, UTC time) — values a hand-writer cannot know, which is
# exactly what makes them evidence rather than a claim. What a gate can check is
# therefore: the block exists, its fields are filled, `generated_at` looks like a
# real ISO date, and `generated_by` names the script — a hand-written block
# naming itself something else fails here. Truthfulness of `author` itself is not
# machine-verifiable; the producer requirement is what narrows the gap.
provenance_block() { # file -> block lines, or empty
  sed -n '/^<!-- provenance$/,/^-->$/p' "$1" 2>/dev/null || true
}
validate_provenance() { # file
  local f="$1" blk k norm
  blk=$(provenance_block "$f")
  [[ -n "$blk" ]] || die "cannot finish: $f carries no provenance block — run scripts/stamp-provenance.sh <CHG-id> (standards §1.1)"
  # Placeholder first: an unfilled template should hear "run the script", not a
  # downstream symptom about date formats.
  norm=$(printf '%s' "$blk" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
  case "$norm" in
    *PENDING*|*TODO*|*TBD*|*待定*) die "cannot finish: $f provenance block still holds a placeholder — run scripts/stamp-provenance.sh <CHG-id>" ;;
  esac
  for k in author email generated_at generated_by; do
    printf '%s\n' "$blk" | grep -qE "^${k}:[[:space:]]*[^[:space:]]" \
      || die "cannot finish: $f provenance block is missing '$k' — regenerate with scripts/stamp-provenance.sh"
  done
  printf '%s\n' "$blk" | grep -qE '^generated_at:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    || die "cannot finish: $f provenance 'generated_at' is not an ISO-8601 date — regenerate with scripts/stamp-provenance.sh"
  printf '%s\n' "$blk" | grep -qE '^generated_by:[[:space:]]*stamp-provenance\.sh' \
    || die "cannot finish: $f provenance block was not produced by scripts/stamp-provenance.sh (a hand-written block cannot pass this)"
}

validate_governance_state() {
  local id="$1" file risk implementation test_owner review_owner declared_id d rec
  d=$(change_dir "$id")
  file="$d/00-governance.json"
  [[ -s "$file" ]] || die "missing required artifact: $file"
  # A dedicated <CHG>/ directory holds one record; a batch holds one line per
  # bundled change. Scope to THIS change's line so a sibling's risk/owners can
  # never satisfy our checks (or be misread as ours).
  rec=$(gov_record "$file" "$id")
  [[ -n "$rec" ]] || die "$file declares no governance record for '$id' (expected a JSON line with \"change_id\": \"$id\")"
  declared_id=$(json_field "$rec" change_id)
  [[ "$declared_id" == "$id" ]] || die "$file must declare change_id '$id'"
  risk=$(json_field "$rec" risk_level)
  [[ "$risk" =~ ^L[0-3]$ ]] || die "$file must declare risk_level L0, L1, L2, or L3"
  # v3.18.0 change batches are L0/L1 ONLY (standards §1.1). Bundling weakens the
  # per-change evidence boundary — artifacts of several changes share one file —
  # which is tolerable for low-risk work and not for anything needing role
  # independence or release authorization. Enforced here, on the record, so it
  # cannot be bypassed by simply dropping artifacts into a BATCH-*/ directory.
  if is_batch_dir "$d" && [[ "$risk" != L0 && "$risk" != L1 ]]; then
    die "$d is a change batch but '$id' declares risk_level $risk — batches are L0/L1 only; move '$id' to $change_root/$id/ (standards §1.1)"
  fi
  implementation=$(json_field "$rec" implementation_owner)
  [[ -n "$implementation" ]] || die "$file must declare implementation_owner"
  reject_placeholder_owner "$file" implementation_owner "$implementation"
  if [[ "$risk" == L2 || "$risk" == L3 ]]; then
    test_owner=$(json_field "$rec" test_owner)
    review_owner=$(json_field "$rec" review_owner)
    [[ -n "$test_owner" && -n "$review_owner" ]] || die "$file must declare test_owner and review_owner for $risk"
    reject_placeholder_owner "$file" test_owner "$test_owner"
    reject_placeholder_owner "$file" review_owner "$review_owner"
    [[ "$implementation" != "$test_owner" && "$implementation" != "$review_owner" && "$test_owner" != "$review_owner" ]] || die "$file requires distinct implementation, test, and review owners for $risk"
  fi
  # v3.5.0 L3 release authorization: flat string fields, not a nested object —
  # the record is extracted with a single-line sed, so nested JSON cannot parse.
  if [[ "$risk" == L3 ]]; then
    local auth_by auth_at auth_ev
    auth_by=$(json_field "$rec" release_authorized_by)
    auth_at=$(json_field "$rec" release_authorized_at)
    auth_ev=$(json_field "$rec" release_authorization_evidence)
    [[ -n "$auth_by" ]] || die "$file must declare release_authorized_by for L3"
    reject_placeholder_owner "$file" release_authorized_by "$auth_by"
    [[ -n "$auth_at" ]] || die "$file must declare release_authorized_at for L3"
    [[ -n "$auth_ev" ]] || die "$file must declare release_authorization_evidence for L3"
  fi
  # v3.6.0 bug document set: an optional flat bug_ref binds this change to a
  # defect document group under docs/bugs/<bug_ref>/; when declared, the
  # three-file set must exist and be non-empty (standards §2.5 stage 6).
  local bug_ref
  bug_ref=$(json_field "$rec" bug_ref)
  if [[ -n "$bug_ref" ]]; then
    [[ "$bug_ref" =~ ^[A-Za-z0-9._-]+$ ]] || die "$file field 'bug_ref' has invalid defect id '$bug_ref'"
    for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
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

# CHG-004 / REQ-022: the eight-category minimum doc set (standards §1.1) includes
# 06.5-deployment-config.md and 06-delivery-summary.md. Neither had a template nor
# any machine check, so "no config change" / "no follow-ups" were expressed by
# *omitting the file* — the exact gap that let CHG-003 nearly ship without 06.5.
# Both are delivery-bar items now. "Not hit" must be *declared*, and an unfilled
# template must not pass: templates ship a TEMPLATE-MARKER sentinel line that must
# be deleted once filled (same trick as bugfix-log.md's '### BUG-xxx' placeholder,
# which deliberately fails the '[0-9]' count).
check_delivery_doc() { # change-dir filename content-regex label
  local d="$1" name="$2" pat="$3" label="$4" f="" cand pdir
  # 落点三选一：① 变更目录（常态）② 仓库级 <docs>/（无功能目录的仓库，如本仓库）
  # ③ 功能目录 <docs>/<feature>/（§2.17 产物目录双轨约定）
  for cand in "$d/$name" "$docs_dir/$name"; do
    [[ -f "$cand" ]] && { f="$cand"; break; }
  done
  # ③ 刻意**不用**裸 glob `<docs>/*/`——独立复核实测：那样只要有人在文档根下任意子目录
  #   （如 <docs>/unrelated/）放一个同名占位文件，所有变更的交付门禁就永久放行了。
  #   故此处要求该目录"看起来像功能目录"：须含 01-spec.md 或 01.5-rtvm-matrix.md。
  #   这是本族根因的反向形态——覆盖面过宽比过窄更危险，因为它制造的是假绿。
  if [[ -z "$f" ]]; then
    for cand in "$docs_dir"/*/"$name"; do
      [[ -f "$cand" ]] || continue
      pdir=$(dirname "$cand")
      [[ -f "$pdir/01-spec.md" || -f "$pdir/01.5-rtvm-matrix.md" ]] || continue
      f="$cand"; break
    done
  fi
  [[ -n "$f" ]] || die "cannot finish: missing $label ($name) — standards §1.1 eight-category minimum doc set"
  # Sentinel must be the template's own first-line marker form, anchored to
  # line start — a bare substring match false-positives on prose that merely
  # MENTIONS the marker (live-found when a ledger row describing it tripped).
  if grep -q '^<!-- TEMPLATE-MARKER' "$f"; then
    die "cannot finish: $f is still the unfilled template — delete the TEMPLATE-MARKER line once filled (standards §1.1)"
  fi
  grep -qE "$pat" "$f" \
    || die "cannot finish: $f must declare '未命中，不适用' with evidence, or carry real $label rows (standards §1.1)"
}

# Delivery evidence a change must carry before it may leave the machine: the
# v3.7.0 coding record, test results, a changelog, and the v2.21.0 ReAct
# Observation records in it (standards §2.16.2). Shared by --stage stop and
# branch-mode CI so both enforcement lines hold the same bar. (v3.5.0)
validate_delivery() { # change-id
  local id="$1" d
  d=$(change_dir "$id")
  # v3.7.0: the coding record (changed-file list, CHG-xxx anchors, WHY
  # decisions) is part of the delivery bar (standards §2.5 stage 5).
  [[ -s "$d/04.5-coding-record.md" ]] || die "cannot finish: missing coding record $d/04.5-coding-record.md"
  # v3.17.0: ...and it must carry script-generated provenance (who / where /
  # when). Checked here rather than at `begin` because the coding record is a
  # stage-5 artifact — there is nothing to stamp before coding starts.
  validate_provenance "$d/04.5-coding-record.md"
  [[ -s "$d/05-test-results.md" ]] || die "cannot finish: missing test evidence $d/05-test-results.md"
  [[ -s "$d/09-changelog.md" ]] || die "cannot finish: missing changelog $d/09-changelog.md"
  # Every executed stage must leave an Observation record (verification
  # command + actual output) in the changelog.
  grep -q "Observation" "$d/09-changelog.md" \
    || die "cannot finish: changelog missing ReAct Observation records (standards §2.16.2)"
  # Gate 4 (v3.7.0): every REQ id referenced by the changelog must be backfilled
  # as a row in some docs/<feature>/01.5-rtvm-matrix.md. Changelogs without REQ
  # references (pure fixes / docs changes) are exempt — same semantics as the
  # consistency audit's G5. Updating the changelog alone never closes the loop.
  local req hit
  for req in $(grep -oE 'REQ-[0-9]+' "$d/09-changelog.md" | sort -u); do
    hit=0
    # FU-019: the standards source repo keeps its matrix nested at
    # <change_root>/<CHG>/01.5 (two levels) — a single-level glob would report
    # every REQ as unbackfilled there (fail-closed but unusable).
    for m in "$docs_dir"/*/01.5-rtvm-matrix.md "$change_root"/*/01.5-rtvm-matrix.md; do
      [[ -f "$m" ]] || continue
      grep -qE "^\| \`?${req}\`?" "$m" && { hit=1; break; }
    done
    [[ "$hit" == 1 ]] || die "cannot finish: REQ $req referenced in changelog but not backfilled in $docs_dir/<feature>/01.5-rtvm-matrix.md (gate 4)"
  done
  # CHG-004 / REQ-022: the remaining two of the eight-category minimum doc set.
  check_delivery_doc "$d" 06.5-deployment-config.md '^([#>-][[:space:]]*)*未命中|^[|].*(未命中|(CFG|DB)-[0-9]+)|(CFG|DB)-[0-9]+' 'config/DB record'
  check_delivery_doc "$d" 06-delivery-summary.md '^[|].*FU-[0-9]+|^[-*][[:space:]]+.*FU-[0-9]+|^(#{1,6}[[:space:]]*).*遗留' 'delivery summary / FU ledger'
}

validate_stop() {
  local id
  working_code_changed || return 0
  validate_active_change
  id=$(active_change)
  validate_delivery "$id"
  # CHG-012 / FU: verification command source chain — env (highest) →
  # .agent-governance.yml ci.verification_command (placeholder skipped) → unset
  # (verify skipped; same fail-open semantics as before). Two-phase per design:
  # the file/config is the guard for "is there a command", bash is the assertion.
  local vcmd="${AGENT_GUARD_VERIFY_COMMAND:-}" vsrc="env" yml_tampered=0
  if [[ -z "$vcmd" && -f ".agent-governance.yml" ]]; then
    # CHG-015 anti-tamper: if the yml itself is part of the pending change
    # (modified/untracked), its command must NOT auto-execute — a PR could
    # otherwise inject arbitrary commands into the reviewer's stop/ci hook.
    # Committed versions are trusted (standard repo-trust model).
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
       && [[ -n "$(git status --porcelain -- .agent-governance.yml 2>/dev/null)" ]]; then
      yml_tampered=1
      echo "agent-gate: verification command from .agent-governance.yml skipped — the file is modified in the pending change (anti-tamper, CHG-015); set AGENT_GUARD_VERIFY_COMMAND to run verification"
    else
      vcmd=$(sed -nE 's/^[[:space:]]*verification_command:[[:space:]]*"(.+)".*/\1/p' .agent-governance.yml 2>/dev/null | head -n 1)
      vsrc=".agent-governance.yml"
      case "$vcmd" in ""|*"<replace"*) vcmd=""; vsrc="" ;; esac
    fi
  fi
  if [[ -n "$vcmd" ]]; then
    echo "agent-gate: verification command from $vsrc: $vcmd"
    bash -lc "$vcmd" || die "cannot finish: verification command failed (from $vsrc): $vcmd"
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
    complete=true
    for doc in "${required_docs[@]}"; do
      [[ -s "$dir/$doc" ]] || { complete=false; break; }
    done
    [[ "$complete" == true ]] || continue
    # A dedicated dir names one change; a batch names every change it anchors.
    for id in $(change_ids_in_dir "${dir%/}"); do
      [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
      if ( validate_governance_state "$id" ) >/dev/null 2>&1 \
         && ( validate_artifact_content "$id" ) >/dev/null 2>&1; then
        return 0
      fi
    done
  done
  return 1
}

validate_diff() {
  local mode="$1" base="${2:-}" files code_changed docs_changed f id dir_id seen_ids
  files=$(changed_files "$mode" "$base")
  [[ -n "$files" ]] || exit 0
  code_changed=false
  docs_changed=false
  seen_ids=""
  while IFS= read -r f; do
    is_code_path "$f" && code_changed=true
    if [[ "$f" =~ ^${change_root_re}/([A-Za-z0-9._-]+)/[A-Za-z0-9._-]+$ ]]; then
      docs_changed=true
      dir_id="${BASH_REMATCH[1]}"
      # A batch artifact is SHARED by every bundled change, so a diff to it is
      # attributable to the whole roster. v3.19.0: read the roster from
      # 00-governance.json rather than off the `## <heading>` lines — the latter
      # picks up structural headings the standards require (§2.16.2
      # `## Observation`) and fails the batch over a heading it mandates.
      # `|| true` semantics preserved: an unreadable roster falls back to the
      # anchors, and an empty list must not abort the scan.
      local id_list
      if [[ "$dir_id" == BATCH-* ]]; then
        id_list=$(gov_ids "$(dirname "$f")/00-governance.json")
        [[ -n "$id_list" ]] || id_list=$(anchors_in_file "$f")
      else
        id_list="$dir_id"
      fi
      for id in $id_list; do
        case " $seen_ids " in
          *" $id "*) ;;
          *) seen_ids="$seen_ids $id" ;;
        esac
        # Staged/CI diffs are the only enforcement line for clients without
        # pre-write hooks, so the governance state must be validated here too.
        validate_governance_state "$id"
      done
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
    # One metrics row per CHANGE, not per directory: a batch directory holds
    # several changes and must not collapse into a single `BATCH-*` row with
    # one risk level standing in for all of them.
    for id in $(change_ids_in_dir "${dir%/}"); do
      [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
      if [[ -s "$dir/00-governance.json" ]]; then
        risk=$(json_field "$(gov_record "$dir/00-governance.json" "$id")" risk_level)
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
  done
}

command="${1:-help}"
case "$command" in
  begin)
    id="${2:-}"
    [[ -n "$id" ]] || die "usage: scripts/agent-gate begin <change-id>"
    # FU-015 (BUG-003): a change dir carrying a changelog is a CLOSED change —
    # re-opening it would let a new change write into a read-only artifact set
    # (standards §2.15 rule 4, one change one document set).
    # S1/S2 (independent review): -s misses zero-size and symlinked markers;
    # '.'/'..' would escape the change dir. Both are closed here.
    if [[ "$id" == "." || "$id" == ".." ]]; then
      die "invalid change id '$id'"
    fi
    # In a BATCH the changelog file is SHARED by every bundled change, so "the
    # file exists" cannot mean "this change is closed" — a sibling's changelog
    # would close every change that joins the batch later (false positive).
    # Closure for a batch member is therefore its OWN `## <id>` section in the
    # changelog, which is the same FU-015 semantics read one level finer.
    d=$(change_dir "$id")
    if is_batch_dir "$d"; then
      if [[ -e "$d/09-changelog.md" || -L "$d/09-changelog.md" ]] \
         && grep -qE "$(anchor_re "$id")" "$d/09-changelog.md" 2>/dev/null; then
        die "change $id is already closed ($d/09-changelog.md carries a '## $id' section) — open a new change id (standards §2.15 rule 4, FU-015)"
      fi
    elif [[ -e "$d/09-changelog.md" || -L "$d/09-changelog.md" ]]; then
      die "change $id is already closed ($d/09-changelog.md exists) — open a new change id (standards §2.15 rule 4, FU-015)"
    fi
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

stop and branch-mode CI enforce delivery evidence: 04.5-coding-record.md,
05-test-results.md, and 09-changelog.md carrying ReAct Observation records.
Gate 4 RTVM (v3.7.0): REQ ids referenced by the changelog must be backfilled
as rows in docs/<feature>/01.5-rtvm-matrix.md; changelogs without REQ
references (pure fixes / docs changes) are exempt.

metrics prints one JSON object per change (JSON Lines) with stage timestamps
and intervals derived from git history; pipe it to a CI artifact for trending.

Configuration (v3.15.0): directory ROOTS come from the `paths:` block of
.agent-governance.yml (docs / scripts / tests / githooks), each overridable by
AGENT_GUARD_<KEY>_DIR. Every built-in default is the historical hardcoded value,
so a repo that configures nothing behaves exactly as before.
change_root / bugs_root keep AGENT_GUARD_CHANGE_ROOT / AGENT_GUARD_BUGS_ROOT and
default to <docs>/changes and <docs>/bugs. Not configurable, on purpose:
.github/ (the platform mandates the location) and the contract names (AGENTS.md,
the gate filename, the twelve change artifacts, the six defect artifacts, the
required check name) — they are what makes a repo comparable to every other repo
using this package.
EOF
    ;;
  *) die "unknown command '$command'" ;;
esac
