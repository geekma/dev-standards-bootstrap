#!/usr/bin/env bash
# verify-all.sh — one serial verification entry, one receipt, no polling.
#
#   verify-all.sh                 # release + ledger + audit + suite + gate (serial)
#   verify-all.sh --fresh         # ignore a fresh suite receipt and force the suite
#   verify-all.sh --skip-release  # omit any single step (repeatable: --skip-ledger,
#                                 #   --skip-audit, --skip-suite, --skip-gate); a
#                                 #   skipped step is recorded as "skip", never "pass"
#   verify-all.sh --jobs 4        # suite -j N (alias -j; default 4)
#   verify-all.sh --root DIR      # inspect another checkout (tests/fixtures)
#
# The fifth step is the batch's own headline hard gate, run locally too:
# `ci-summary.sh --check` aligns tests/.suite-baseline with the suite receipt the
# same way CI does, so "the number we committed" and "the number we ran" cannot
# drift apart between CI and the maintainer's laptop (v3.87.0 R4, review #5).
# After a count-changing edit it is meant to go red — that is the generator-sync
# instruction, not a false alarm.
#
# Collect-all: every step runs even after an earlier failure, so one call returns
# the complete red picture instead of N sequential round-trips. The suite is
# skipped when a fresh same-HEAD/same-tree green receipt exists (the exact trust
# rule update-assertion-count.sh uses); --fresh forbids that reuse. Writes
# .agent-state/verify-receipt.json (override: AGENT_GUARD_VERIFY_RECEIPT_PATH)
# and per-step logs under .agent-state/verify-logs/<UTC stamp> (override:
# AGENT_GUARD_VERIFY_LOG_DIR).
#
# The before/after tree fingerprints make "the tree changed while verifying"
# visible instead of silently mixing two code states into one green claim.
# Test seams (fixtures only): AGENT_GUARD_VERIFY_{RELEASE,LEDGER,AUDIT,SUITE,GATE}_CMD.
#
# Source-layer only (NOT shipped with the Skill).
# Zero deps: bash 3.2+, git, sed, tr, date, stat.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FRESH=0
SKIP_RELEASE=0
SKIP_LEDGER=0
SKIP_AUDIT=0
SKIP_SUITE=0
SKIP_GATE=0
JOBS="${AGENT_GUARD_SUITE_JOBS:-4}"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "verify-all: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --fresh) FRESH=1; shift ;;
    --skip-release) SKIP_RELEASE=1; shift ;;
    --skip-ledger) SKIP_LEDGER=1; shift ;;
    --skip-audit) SKIP_AUDIT=1; shift ;;
    --skip-suite) SKIP_SUITE=1; shift ;;
    --skip-gate) SKIP_GATE=1; shift ;;
    # -j is accepted as an alias: the suite it forwards to spells parallelism -j,
    # and a documented "-j 4" that dies as an unknown argument is a trap (v3.87.0 R4).
    --jobs|-j) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "verify-all: --jobs needs a value" >&2; exit 2; }; JOBS="$2"; shift 2 ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; exit 0 ;;
    *) echo "verify-all: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "verify-all: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
case "$JOBS" in ''|*[!0-9]*) JOBS=4 ;; esac
[ "$JOBS" -ge 1 ] || JOBS=4
source "$ROOT/scripts/lib-source-facts.sh"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RECEIPT="${AGENT_GUARD_VERIFY_RECEIPT_PATH:-$ROOT/.agent-state/verify-receipt.json}"
LOG_DIR="${AGENT_GUARD_VERIFY_LOG_DIR:-$ROOT/.agent-state/verify-logs/$STAMP}"
mkdir -p "$LOG_DIR" || { echo "verify-all: cannot create log dir $LOG_DIR" >&2; exit 2; }

HEAD=$(sf_repo_head "$ROOT")
FP_BEFORE=$(sf_tree_fingerprint "$ROOT")
FAILED=0
STEPS_JSON=""
SUITE_REUSED=false
SUITE_PASSED=""
SUITE_FAILED=""
SUITE_WALL=""

emit_step() { # name status rc duration log
  local sep=""
  [ -n "$STEPS_JSON" ] && sep=","
  STEPS_JSON="$STEPS_JSON$sep{\"name\":$(sf_json_str "$1"),\"status\":$(sf_json_str "$2"),\"rc\":$3,\"duration_s\":$4,\"log\":$(sf_json_str "$5")}"
}

run_step() { # name skip-flag command
  local name="$1" skip="$2" cmd="$3" rc=0 out start elapsed log
  if [ "$skip" -eq 1 ]; then
    printf 'SKIP %-7s (disabled)\n' "$name"
    emit_step "$name" skip 0 0 ""
    return 0
  fi
  if [ -z "$cmd" ]; then
    printf 'SKIP %-7s (not present in this checkout)\n' "$name"
    emit_step "$name" skip 0 0 ""
    return 0
  fi
  log="$LOG_DIR/$name.log"
  start=$(date +%s)
  ( cd "$ROOT" && bash -c "$cmd" ) >"$log" 2>&1
  rc=$?
  elapsed=$(( $(date +%s) - start ))
  if [ "$rc" -eq 0 ]; then
    printf 'PASS %-7s %ss\n' "$name" "$elapsed"
  else
    printf 'FAIL %-7s %ss (rc=%s, log: %s)\n' "$name" "$elapsed" "$rc" "$log" >&2
    tail -n 20 "$log" >&2 || true
    FAILED=1
  fi
  emit_step "$name" "$([ "$rc" -eq 0 ] && echo pass || echo fail)" "$rc" "$elapsed" "$log"
  return 0
}

REL_CMD="${AGENT_GUARD_VERIFY_RELEASE_CMD:-}"
if [ -z "$REL_CMD" ] && [ -f "$ROOT/scripts/release.sh" ]; then REL_CMD="bash scripts/release.sh check"; fi
run_step release "$SKIP_RELEASE" "$REL_CMD"

LEDGER_CMD="${AGENT_GUARD_VERIFY_LEDGER_CMD:-}"
if [ -z "$LEDGER_CMD" ] && [ -f "$ROOT/tests/audit-docs-consistency.sh" ]; then LEDGER_CMD="bash tests/audit-docs-consistency.sh"; fi
run_step ledger "$SKIP_LEDGER" "$LEDGER_CMD"

AUDIT_CMD="${AGENT_GUARD_VERIFY_AUDIT_CMD:-}"
if [ -z "$AUDIT_CMD" ] && [ -f "$ROOT/tests/audit-standards-src.sh" ]; then AUDIT_CMD="bash tests/audit-standards-src.sh"; fi
run_step audit "$SKIP_AUDIT" "$AUDIT_CMD"

# --- suite receipt reuse (identical trust rule to update-assertion-count) ---
if [ "$SKIP_SUITE" -eq 0 ] && [ "$FRESH" -eq 0 ] && sf_receipt_fresh "$ROOT" "$FP_BEFORE"; then
  SUITE_REUSED=true
  R=$(sf_suite_receipt_path "$ROOT")
  SUITE_PASSED=$(sf_read_json_num "$R" passed)
  SUITE_FAILED=$(sf_read_json_num "$R" failed)
  SUITE_WALL=$(sf_read_json_num "$R" wall_time_s)
  printf 'PASS suite   reused fresh same-tree receipt (passed=%s, wall=%ss)\n' "$SUITE_PASSED" "$SUITE_WALL"
  emit_step suite pass 0 0 "$R"
elif [ "$SKIP_SUITE" -eq 0 ]; then
  run_step suite 0 "${AGENT_GUARD_VERIFY_SUITE_CMD:-bash tests/run-tests.sh -j $JOBS}"
  SLOG="$LOG_DIR/suite.log"
  if [ -f "$SLOG" ]; then
    SUITE_PASSED=$(sed -nE 's/^([0-9]+) passed, [0-9]+ failed$/\1/p' "$SLOG" | tail -n 1)
    SUITE_FAILED=$(sed -nE 's/^[0-9]+ passed, ([0-9]+) failed$/\1/p' "$SLOG" | tail -n 1)
    SUITE_WALL=$(sed -nE 's/^wall-time: ([0-9]+)s$/\1/p' "$SLOG" | tail -n 1)
  fi
else
  run_step suite 1 ""
fi

# The batch's headline hard gate, locally as well as in CI: baseline == receipt.
GATE_CMD="${AGENT_GUARD_VERIFY_GATE_CMD:-}"
if [ -z "$GATE_CMD" ] && [ -f "$ROOT/scripts/ci-summary.sh" ]; then GATE_CMD="bash scripts/ci-summary.sh --check"; fi
run_step gate "$SKIP_GATE" "$GATE_CMD"

FP_AFTER=$(sf_tree_fingerprint "$ROOT")
TREE_STABLE=true
# Fail closed (v3.87.0 R4, review finding #4): an uncomputable fingerprint is not
# evidence of a stable tree. The fingerprint lib degrades to an empty string on
# any failure (non-git root, read-tree error), and both ends empty would otherwise
# compare equal — reporting "stable" for a run whose inputs were never pinned.
if [ -z "$FP_BEFORE" ] || [ -z "$FP_AFTER" ]; then
  TREE_STABLE=false
  FAILED=1
  echo "FAIL tree    fingerprint unavailable (before='${FP_BEFORE:-none}' after='${FP_AFTER:-none}'); stability cannot be proven" >&2
elif [ "$FP_BEFORE" != "$FP_AFTER" ]; then
  TREE_STABLE=false
  FAILED=1
  echo "FAIL tree    changed during verification ($FP_BEFORE -> $FP_AFTER); results mix two code states" >&2
fi

STATUS=$([ "$FAILED" -eq 0 ] && echo pass || echo fail)
mkdir -p "$(dirname "$RECEIPT")" 2>/dev/null || true
{
  printf '{\n'
  printf '  "schema": 1,\n'
  printf '  "generated_at": %s,\n' "$(sf_json_str "$(sf_now)")"
  printf '  "head": %s,\n' "$(sf_json_str_or_null "$HEAD")"
  printf '  "tree_fingerprint_before": %s,\n' "$(sf_json_str_or_null "$FP_BEFORE")"
  printf '  "tree_fingerprint_after": %s,\n' "$(sf_json_str_or_null "$FP_AFTER")"
  printf '  "tree_stable": %s,\n' "$TREE_STABLE"
  printf '  "status": %s,\n' "$(sf_json_str "$STATUS")"
  printf '  "suite": {"reused": %s, "passed": %s, "failed": %s, "wall_time_s": %s},\n' \
    "$SUITE_REUSED" "$(sf_json_num_or_null "$SUITE_PASSED")" "$(sf_json_num_or_null "$SUITE_FAILED")" "$(sf_json_num_or_null "$SUITE_WALL")"
  printf '  "steps": [%s]\n' "$STEPS_JSON"
  printf '}\n'
} > "$RECEIPT" 2>/dev/null || echo "verify-all: warning: could not write $RECEIPT" >&2

printf '\nverify-all: %s (receipt: %s, logs: %s)\n' "$STATUS" "$RECEIPT" "$LOG_DIR"
[ "$FAILED" -eq 0 ]
