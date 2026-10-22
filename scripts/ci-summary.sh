#!/usr/bin/env bash
# ci-summary.sh — turn the machine receipts into the CI job summary.
#
#   ci-summary.sh              # markdown summary to stdout (+ $GITHUB_STEP_SUMMARY)
#   ci-summary.sh --check      # hard gate: committed baseline == the run's passed count
#   ci-summary.sh --root DIR    # summarize another checkout (tests/fixtures)
#
# Exit codes: --check is a gate (0 clean, 1 findings, 2 usage/bad root). The
# default render is reporting-only: it prints the table, appends it to
# $GITHUB_STEP_SUMMARY and always exits 0, so a problem still shows up as a
# "Baseline/provenance problems: N" line in the job summary instead of turning
# the render step red before the summary is written.
#
# The golden-case job runs the suite exactly once; this script is the single place
# that turns that run into (a) a human-readable summary and (b) the assertion that
# tests/.suite-baseline — the evidence A3 and the READMEs consume — still equals
# the real count. A stale baseline therefore fails CI loudly instead of quietly
# documenting a number nobody ran.
#
# Scope note printed in the summary: CI checks the shipped payload and the source
# audit; the private docs ledger under docs/ is not pushed and is not checked here.
#
# Source-layer only (NOT shipped with the Skill).
# Zero deps: bash 3.2+, git, sed, tr, date.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "ci-summary: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    # help = the leading comment block, printed by shape rather than a hardcoded
    # line range (a range silently truncates every time the header grows)
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; exit 0 ;;
    *) echo "ci-summary: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "ci-summary: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
source "$ROOT/scripts/lib-source-facts.sh"

RECEIPT=$(sf_suite_receipt_path "$ROOT")
HEAD=$(sf_repo_head "$ROOT")
BASELINE=$(sf_baseline_num "$ROOT/tests/.suite-baseline")
AUDIT_BASELINE=$(sf_baseline_num "$ROOT/tests/.audit-baseline")
VERSION=$(sf_ds_version "$ROOT")
R_PASS=""; R_FAIL=""; R_WALL=""; R_HEAD=""; R_GEN=""; R_FP=""
if [ -f "$RECEIPT" ]; then
  R_PASS=$(sf_read_json_num "$RECEIPT" passed)
  R_FAIL=$(sf_read_json_num "$RECEIPT" failed)
  R_WALL=$(sf_read_json_num "$RECEIPT" wall_time_s)
  R_HEAD=$(sf_read_json_str "$RECEIPT" head)
  R_GEN=$(sf_read_json_str "$RECEIPT" generated_at)
  R_FP=$(sf_read_json_str "$RECEIPT" tree_fingerprint)
fi
V_STATUS=""
if [ -f "${AGENT_GUARD_VERIFY_RECEIPT_PATH:-$ROOT/.agent-state/verify-receipt.json}" ]; then
  # Top-level only: a verify receipt repeats "status" inside every step, and the
  # generic reader returns the last match (v3.87.0 R4, same family as the batch
  # ledger bug) — the summary would otherwise print "pass" for a red batch.
  V_STATUS=$(sf_verify_status "${AGENT_GUARD_VERIFY_RECEIPT_PATH:-$ROOT/.agent-state/verify-receipt.json}")
fi

FAILS=0
problem() { printf 'ci-summary: %s\n' "$1" >&2; FAILS=$(( FAILS + 1 )); }

if [ -z "$BASELINE" ]; then problem "tests/.suite-baseline missing or non-numeric"; fi
if [ ! -f "$RECEIPT" ]; then
  problem "no suite receipt at $RECEIPT — the golden-case job must run tests/run-tests.sh once and emit it"
else
  # v3.88.0 (CHG-116, REQ-1198): only a full run may pose as full authority.
  # The receipt kind is the machine boundary — a partial receipt quarantined by
  # -T auto (kind:"partial") and a pre-v3.88 legacy receipt without any kind
  # both fail closed BEFORE any number comparison; kind:"full" is the only
  # value that reaches the baseline check below.
  case "$(grep -o '"kind":"[a-z]*"' "$RECEIPT" | head -1)" in
    '"kind":"full"') : ;;
    '"kind":"partial"') problem "suite receipt is kind:partial — a partial receipt is not full authority (run the full suite)" ;;
    *) problem "suite receipt has no kind field (pre-v3.88 legacy receipt) — rerun the suite" ;;
  esac
  [ "$R_FAIL" = "0" ] || problem "suite receipt reports failed=${R_FAIL:-?} (expected 0)"
  # Same trust rule as the reuse path (v3.87.0 R4, review finding #7): HEAD alone
  # does not pin the inputs — a same-HEAD receipt from a dirty/other tree would
  # otherwise certify a number this tree never produced. sf_receipt_fresh owns that
  # judgement for reuse; here it is reproduced explicitly because CI must name the
  # offending field rather than just say "stale".
  CUR_FP=$(sf_tree_fingerprint "$ROOT")
  if [ -z "$R_FP" ]; then problem "suite receipt has no tree_fingerprint field (pre-v3.79.0 schema) — rerun the suite"
  elif [ -z "$CUR_FP" ]; then problem "current tree fingerprint is uncomputable (not a git checkout?) — the receipt cannot be trusted"
  elif [ "$R_FP" != "$CUR_FP" ]; then problem "suite receipt tree fingerprint $R_FP != current $CUR_FP (the worktree changed since the run)"
  fi
  # Fail closed: an unknown/absent field is a finding, never a skipped comparison.
  if [ -z "$HEAD" ]; then problem "current HEAD is unknown (git rev-parse failed)"
  elif [ -z "$R_HEAD" ]; then problem "suite receipt has no head field"
  elif [ "$R_HEAD" != "$HEAD" ]; then problem "suite receipt HEAD $R_HEAD != current HEAD $HEAD"
  fi
  if [ -n "$BASELINE" ]; then
    case "$R_PASS" in
      ''|*[!0-9]*) problem "suite receipt has no numeric passed field (got '${R_PASS:-<empty>}')" ;;
      *) [ "$R_PASS" = "$BASELINE" ] \
        || problem "tests/.suite-baseline is $BASELINE but the run passed $R_PASS — run scripts/update-assertion-count.sh" ;;
    esac
  fi
fi

if [ "$CHECK" -eq 1 ]; then
  if [ "$FAILS" -eq 0 ]; then
    printf 'ci-summary: check OK (baseline=%s == receipt passed=%s)\n' "$BASELINE" "$R_PASS"
    exit 0
  fi
  printf 'ci-summary: check FAILED (%s problem(s))\n' "$FAILS" >&2
  exit 1
fi

BODY=$(
  printf '## dev-standards-bootstrap — golden-case run\n\n'
  printf '| fact | value |\n| --- | --- |\n'
  printf '| standards version | %s |\n' "${VERSION:-?}"
  printf '| head | %s |\n' "${HEAD:-?}"
  printf '| suite baseline (tests/.suite-baseline) | %s |\n' "${BASELINE:-?}"
  printf '| suite receipt passed / failed | %s / %s |\n' "${R_PASS:-?}" "${R_FAIL:-?}"
  printf '| suite wall time | %ss |\n' "${R_WALL:-?}"
  printf '| suite receipt head / generated_at | %s / %s |\n' "${R_HEAD:-?}" "${R_GEN:-?}"
  printf '| suite receipt tree fingerprint | %s |\n' "${R_FP:-?}"
  printf '| source-audit baseline (tests/.audit-baseline) | %s |\n' "${AUDIT_BASELINE:-?}"
  printf '| verify-all status (if run locally) | %s |\n' "${V_STATUS:-none}"
  printf '\nScope: CI checks the shipped payload and the source audit. The private docs ledger under `docs/` is not pushed and is **not** checked here.\n'
  [ "$FAILS" -eq 0 ] || printf '\n**Baseline/provenance problems: %s (see job log)**\n' "$FAILS"
)
printf '%s\n' "$BODY"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "$BODY" >> "$GITHUB_STEP_SUMMARY" || printf 'ci-summary: warning: cannot append to GITHUB_STEP_SUMMARY\n' >&2
fi
exit 0
