#!/usr/bin/env bash
# CHG-128 (v3.92.0, REQ-1278): environment-equivalence check.
# Proves that the TRACKED-ONLY tree (git archive HEAD) passes the source audit
# and the affected suite sections — the same shape as a fresh clone, and the
# same shape as a repo that uses this skill WITHOUT GitHub / WITHOUT CI.
#
# Usage:
#   tests/fresh-clone-check.sh [--sections "T1,T2"] [--check] [--ledger-check]
#     default sections: AGENT_GUARD_FRESH_CLONE_SECTIONS, else the `-T auto` resolution
#     audit: tests/audit-standards-src.sh in the source repo; falls back to the
#            shipped tests/audit-docs-consistency.sh in a target repo
#     receipt: .agent-state/fresh-clone-receipt.json (agent-gate E153 consumes it)
#   --check : validate the existing receipt only (no run)
#   AGENT_GUARD_REPEAT_LIMIT=N  warn when this change already has N receipts
#                               (default 3; 0 disables the guard)
set -uo pipefail
TOOL_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DEFAULT=$(cd "$(dirname "$0")/.." && pwd)
opt_root=""
sections="${AGENT_GUARD_FRESH_CLONE_SECTIONS:-}"
check_only=0
ledger_check=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sections)
      [[ $# -ge 2 ]] || { echo "fresh-clone-check: --sections needs a value" >&2; exit 2; }
      sections="$2"; shift 2 ;;
    --root)
      [[ $# -ge 2 ]] || { echo "fresh-clone-check: --root needs a value" >&2; exit 2; }
      opt_root="$2"; shift 2 ;;
    --check) check_only=1; shift ;;
    --ledger-check) ledger_check=1; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "fresh-clone-check: unknown option '$1' (supported: --sections --root --check)" >&2; exit 2 ;;
  esac
done
ROOT="${opt_root:-$ROOT_DEFAULT}"
# v3.92.3: the tool is installed at <tests>/ (possibly a non-default root) and
# must call its SIBLING run-tests/audit tools, never a hardcoded tests/ path.
if [[ "$TOOL_DIR" == "$ROOT" ]]; then
  TOOL_REL="."
elif [[ "$TOOL_DIR" == "$ROOT"/* ]]; then
  TOOL_REL="${TOOL_DIR#"$ROOT"/}"
else
  TOOL_REL="tests"
fi
RECEIPT="${AGENT_GUARD_FRESH_CLONE_RECEIPT:-$ROOT/.agent-state/fresh-clone-receipt.json}"
# v3.92.1 (CHG-128 batch 2): receipt history — repeated full-chain verification is
# the costliest waste we have observed. Every generation appends one row; a second
# receipt for the SAME change without a recorded reason is announced (never blocks).
HISTORY="${AGENT_GUARD_FRESH_CLONE_HISTORY:-$ROOT/.agent-state/fresh-clone-history.tsv}"
# v3.92.3: --git-path is relative to the worktree; reading it from the caller's
# cwd made every invocation outside the repo root print a redirection error.
ACTIVE_FILE=$(git -C "$ROOT" rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
case "$ACTIVE_FILE" in
  "") CHANGE="" ;;
  /*) CHANGE=$(tr -d '[:space:]' < "$ACTIVE_FILE" 2>/dev/null || true) ;;
  *)  [[ -f "$ROOT/$ACTIVE_FILE" ]] \
        && CHANGE=$(tr -d '[:space:]' < "$ROOT/$ACTIVE_FILE" 2>/dev/null || true) \
        || CHANGE="" ;;
esac
CHANGE_LOG=""
[[ -n "$CHANGE" ]] && CHANGE_LOG=$(ls -d "$ROOT/docs/changes/$CHANGE" 2>/dev/null | head -1)

ledger_dupes() { # -> count of prior receipts for the same change
  [[ -n "$CHANGE" && -f "$HISTORY" ]] || { echo 0; return 0; }
  awk -F'\t' -v c="$CHANGE" '$2 == c' "$HISTORY" 2>/dev/null | wc -l | tr -d ' '
}
ledger_reason_present() {
  [[ -n "$CHANGE_LOG" ]] && grep -q '^- fresh-clone re-run:' "$CHANGE_LOG/09-changelog.md" 2>/dev/null
}

if [[ "$check_only" -eq 1 ]]; then
  [[ -s "$RECEIPT" ]] || { echo "fresh-clone-check: no receipt at $RECEIPT — run without --check" >&2; exit 1; }
  head=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)
  want_tree=$( cd "$ROOT" && git ls-files -z | xargs -0 cksum 2>/dev/null | cksum | awk '{print $1}' )
  rh=$(sed -n 's/.*"head":"\([^"]*\)".*/\1/p' "$RECEIPT" | head -1)
  rt=$(sed -n 's/.*"tree_sha":"\([^"]*\)".*/\1/p' "$RECEIPT" | head -1)
  ra=$(sed -n 's/.*"audit_rc":\([0-9-]*\).*/\1/p' "$RECEIPT" | head -1)
  rs=$(sed -n 's/.*"suite_rc":\([0-9-]*\).*/\1/p' "$RECEIPT" | head -1)
  if [[ "$rt" != "$want_tree" || "$ra" != "0" || "$rs" != "0" ]]; then
    echo "fresh-clone-check: receipt stale/red (head=$rh tree=$rt want=$want_tree audit_rc=$ra suite_rc=$rs)" >&2
    exit 1
  fi
  echo "fresh-clone-check: receipt green for $head (tree $rt)"
  exit 0
fi

if [[ "$ledger_check" -eq 1 ]]; then
  n=$(ledger_dupes)
  if [[ "$n" -ge 2 ]] && ! ledger_reason_present; then
    echo "fresh-clone-check: WARN — ${CHANGE:-<no active change>} has $n receipts and no '- fresh-clone re-run: <reason>' line in 09 (G-ENV discipline: generate once at close-out; record a reason when re-running)" >&2
    exit 1
  fi
  echo "fresh-clone-check: ledger clean for ${CHANGE:-<no active change>} ($n prior receipts)"
  exit 0
fi

# v3.92.4 (CHG-129): repeat guard. Re-generating the receipt for the same change
# is the costliest re-run we see (a receipt is the whole audit + section set),
# so say it on stderr before the expensive copy. Never blocks, never changes rc.
_fc_limit="${AGENT_GUARD_REPEAT_LIMIT:-3}"
case "$_fc_limit" in ''|*[!0-9]*) _fc_limit=3 ;; esac
[[ ${#_fc_limit} -le 9 ]] || _fc_limit=3
# "08" is octal syntax inside $(( )); normalize before the numeric test.
: "$(( _fc_limit = 10#$_fc_limit ))"
if [[ "$_fc_limit" -gt 0 && -n "$CHANGE" ]]; then
  _fc_prior=$(ledger_dupes)
  if [[ "$_fc_prior" -ge "$_fc_limit" ]]; then
    echo "fresh-clone-check: repeat guard — ${CHANGE} already has ${_fc_prior} receipt(s); this would be #$(( _fc_prior + 1 )) (limit ${_fc_limit}). Generate the receipt once after the content freezes; AGENT_GUARD_REPEAT_LIMIT=0 silences this." >&2
  fi
fi

head=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || { echo "fresh-clone-check: not a git repo" >&2; exit 2; }
[[ -n "$head" ]] || { echo "fresh-clone-check: no HEAD commit" >&2; exit 2; }

# Section resolution: explicit > env > `-T auto` (mapped from the live diff).
if [[ -z "$sections" ]]; then
  sections=$(AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash "$TOOL_DIR/run-tests.sh" -T auto 2>&1 \
    | sed -n 's/^auto-resolve-only: //p' | tail -1 | tr ' ' ',')
fi
[[ -n "$sections" ]] || { echo "fresh-clone-check: cannot resolve sections (pass --sections)" >&2; exit 2; }
case ",$sections," in
  *,FULL,*) echo "fresh-clone-check: auto resolved FULL — pass --sections with the affected list (full runs belong to CI)" >&2; exit 2 ;;
esac

# v3.92.3: audit tool selection. The source repo ships audit-standards-src.sh;
# a target repo only gets audit-docs-consistency.sh (the source audit is
# deliberately NOT shipped). Without this fallback the receipt could never be
# green in a target repo and E153 would be unsatisfiable.
audit_tool=""
if [[ -f "$TOOL_DIR/audit-standards-src.sh" ]]; then
  audit_tool="audit-standards-src.sh"
elif [[ -f "$TOOL_DIR/audit-docs-consistency.sh" ]]; then
  audit_tool="audit-docs-consistency.sh"
else
  echo "fresh-clone-check: no audit tool at $TOOL_DIR (need audit-standards-src.sh in the source repo or audit-docs-consistency.sh in a target repo)" >&2
  exit 2
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/fresh-clone.XXXXXX") || { echo "fresh-clone-check: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT INT TERM
start_s=$(date +%s)
prior=$(ledger_dupes)
# v3.92.0: copy the TRACKED working tree (not `git archive HEAD`) so the check
# covers the pending change before it is committed — same set a clone gets after
# the commit lands. Untracked files stay out (they never reach a clone / CI).
# Only `cp` is used below: this tool must run on macOS and Linux alike.
( cd "$ROOT" && git ls-files | while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    d=$(dirname "$f")
    mkdir -p "$tmp/$d" || exit 1
    cp -p "$f" "$tmp/$f" || exit 1
  done ) || { echo "fresh-clone-check: tracked-copy failed" >&2; exit 2; }
( cd "$tmp" && git init -q . \
  && git config user.email fresh@clone.invalid && git config user.name fresh \
  && git add -A >/dev/null 2>&1 && git commit -qm "fresh clone" >/dev/null 2>&1 ) \
  || { echo "fresh-clone-check: snapshot commit failed" >&2; exit 2; }
archive_sha=$( cd "$ROOT" && git ls-files | while IFS= read -r f; do [[ -f "$f" ]] && cksum "$f"; done | cksum | awk '{print $1}' )
tree_sha=$( cd "$ROOT" && git ls-files -z | xargs -0 cksum 2>/dev/null | cksum | awk '{print $1}' )

audit_log="$tmp/.fresh-audit.log"
suite_log="$tmp/.fresh-suite.log"
# G-ENV proves correctness, not latency: dispatch in parallel so the serial-only
# wall-clock assertion (T82) does not depend on the host's momentary load.
fresh_jobs="${AGENT_GUARD_FRESH_CLONE_JOBS:-4}"
bash "$tmp/$TOOL_REL/$audit_tool" >"$audit_log" 2>&1; audit_rc=$?
bash "$tmp/$TOOL_REL/run-tests.sh" -T "$sections" -j "$fresh_jobs" >"$suite_log" 2>&1; suite_rc=$?
passed=$(sed -n 's/^\([0-9][0-9]*\) passed,.*/\1/p' "$suite_log" | tail -1); passed=${passed:-0}
failed=$(sed -n 's/^[0-9][0-9]* passed, \([0-9][0-9]*\) failed.*/\1/p' "$suite_log" | tail -1); failed=${failed:-0}
audit_pass=$(sed -n 's/^\([0-9][0-9]*\) passed,.*/\1/p' "$audit_log" | tail -1); audit_pass=${audit_pass:-0}
audit_fail=$(sed -n 's/^[0-9][0-9]* passed, \([0-9][0-9]*\) failed.*/\1/p' "$audit_log" | tail -1); audit_fail=${audit_fail:-0}

mkdir -p "$(dirname "$RECEIPT")"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
printf '{"head":"%s","archive_sha":"%s","tree_sha":"%s","audit_tool":"%s","audit_rc":%s,"audit_passed":%s,"audit_failed":%s,"suite_rc":%s,"sections":"%s","passed":%s,"failed":%s,"generated_at":"%s"}\n' \
  "$head" "$archive_sha" "$tree_sha" "$audit_tool" "$audit_rc" "$audit_pass" "$audit_fail" "$suite_rc" "$sections" "$passed" "$failed" "$now" \
  > "$RECEIPT"

echo "fresh-clone-check: audit(${audit_tool}) ${audit_pass}/${audit_fail} rc=$audit_rc · suite ${passed}/${failed} rc=$suite_rc · sections=$sections"
# v3.92.1: one ledger row per generation; repeated use is announced, never blocked.
wall_s=$(( $(date +%s) - start_s ))
rc=0; [[ "$audit_rc" -eq 0 && "$suite_rc" -eq 0 ]] || rc=1
mkdir -p "$(dirname "$HISTORY")" 2>/dev/null || true
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "${CHANGE:-<none>}" "$head" "$tree_sha" "$sections" "$wall_s" "$rc" >> "$HISTORY" 2>/dev/null || true
if [[ "$prior" -ge 1 ]] && ! ledger_reason_present; then
  echo "fresh-clone-check: WARN — ${CHANGE:-<no active change>} already has $prior receipt(s); repeated full-chain verification is the costliest waste — record '- fresh-clone re-run: <reason>' in 09「重要上下文」, or generate once at close-out (AGENTS 纪律 7)" >&2
fi
[[ "$audit_rc" -eq 0 && "$suite_rc" -eq 0 ]]
