#!/usr/bin/env bash
# CHG-128 (v3.92.0, REQ-1278): environment-equivalence check.
# Proves that the TRACKED-ONLY tree (git archive HEAD) passes the source audit
# and the affected suite sections — the same shape as a fresh clone, and the
# same shape as a repo that uses this skill WITHOUT GitHub / WITHOUT CI.
#
# Usage:
#   tests/fresh-clone-check.sh [--sections "T1,T2"] [--check]
#     default sections: AGENT_GUARD_FRESH_CLONE_SECTIONS, else the `-T auto` resolution
#     receipt: .agent-state/fresh-clone-receipt.json (agent-gate E149 consumes it)
#   --check : validate the existing receipt only (no run)
set -uo pipefail
ROOT_DEFAULT=$(cd "$(dirname "$0")/.." && pwd)
opt_root=""
sections="${AGENT_GUARD_FRESH_CLONE_SECTIONS:-}"
check_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sections)
      [[ $# -ge 2 ]] || { echo "fresh-clone-check: --sections needs a value" >&2; exit 2; }
      sections="$2"; shift 2 ;;
    --root)
      [[ $# -ge 2 ]] || { echo "fresh-clone-check: --root needs a value" >&2; exit 2; }
      opt_root="$2"; shift 2 ;;
    --check) check_only=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "fresh-clone-check: unknown option '$1' (supported: --sections --root --check)" >&2; exit 2 ;;
  esac
done
ROOT="${opt_root:-$ROOT_DEFAULT}"
RECEIPT="${AGENT_GUARD_FRESH_CLONE_RECEIPT:-$ROOT/.agent-state/fresh-clone-receipt.json}"

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

head=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || { echo "fresh-clone-check: not a git repo" >&2; exit 2; }
[[ -n "$head" ]] || { echo "fresh-clone-check: no HEAD commit" >&2; exit 2; }

# Section resolution: explicit > env > `-T auto` (mapped from the live diff).
if [[ -z "$sections" ]]; then
  sections=$(AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash "$ROOT/tests/run-tests.sh" -T auto 2>&1 \
    | sed -n 's/^auto-resolve-only: //p' | tail -1 | tr ' ' ',')
fi
[[ -n "$sections" ]] || { echo "fresh-clone-check: cannot resolve sections (pass --sections)" >&2; exit 2; }
case ",$sections," in
  *,FULL,*) echo "fresh-clone-check: auto resolved FULL — pass --sections with the affected list (full runs belong to CI)" >&2; exit 2 ;;
esac

tmp=$(mktemp -d "${TMPDIR:-/tmp}/fresh-clone.XXXXXX") || { echo "fresh-clone-check: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT INT TERM
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
bash "$tmp/tests/audit-standards-src.sh" >"$audit_log" 2>&1; audit_rc=$?
bash "$tmp/tests/run-tests.sh" -T "$sections" -j "$fresh_jobs" >"$suite_log" 2>&1; suite_rc=$?
passed=$(sed -n 's/^\([0-9][0-9]*\) passed,.*/\1/p' "$suite_log" | tail -1); passed=${passed:-0}
failed=$(sed -n 's/^[0-9][0-9]* passed, \([0-9][0-9]*\) failed.*/\1/p' "$suite_log" | tail -1); failed=${failed:-0}
audit_pass=$(sed -n 's/^\([0-9][0-9]*\) passed,.*/\1/p' "$audit_log" | tail -1); audit_pass=${audit_pass:-0}
audit_fail=$(sed -n 's/^[0-9][0-9]* passed, \([0-9][0-9]*\) failed.*/\1/p' "$audit_log" | tail -1); audit_fail=${audit_fail:-0}

mkdir -p "$(dirname "$RECEIPT")"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
printf '{"head":"%s","archive_sha":"%s","tree_sha":"%s","audit_rc":%s,"audit_passed":%s,"audit_failed":%s,"suite_rc":%s,"sections":"%s","passed":%s,"failed":%s,"generated_at":"%s"}\n' \
  "$head" "$archive_sha" "$tree_sha" "$audit_rc" "$audit_pass" "$audit_fail" "$suite_rc" "$sections" "$passed" "$failed" "$now" \
  > "$RECEIPT"

echo "fresh-clone-check: audit ${audit_pass}/${audit_fail} rc=$audit_rc · suite ${passed}/${failed} rc=$suite_rc · sections=$sections"
[[ "$audit_rc" -eq 0 && "$suite_rc" -eq 0 ]]
