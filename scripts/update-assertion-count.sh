#!/usr/bin/env bash
# update-assertion-count.sh — recompute the golden-case assertion count from
# tests/run-tests.sh static call sites and rewrite the claims in both READMEs.
#
#   update-assertion-count.sh          # rewrite READMEs to the real count
#   update-assertion-count.sh --check  # exit 1 if any README would change (CI/audit mode)
#
# Source-layer only (NOT shipped with the Skill): READMEs live in this repo.
# Closes FU-005 (hand-maintained numbers drifted 107/118 vs real) and
# compensates the FU-009 A3 regex residual (`assertions: N` form) by making
# every claim site generated. Zero deps: bash + grep + sed + diff.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
N=$(grep -cE '^[[:space:]]*(report|check_output) ' "$ROOT/tests/run-tests.sh")
[[ "$N" =~ ^[0-9]+$ && "$N" -gt 0 ]] || { echo "cannot determine assertion count" >&2; exit 2; }
check=0
[[ "${1:-}" == "--check" ]] && check=1
status=0
for f in "$ROOT/README.md" "$ROOT/README.zh-CN.md"; do
  tmp=$(mktemp)
  # Four claim shapes, each anchored to an assertion keyword (never version
  # numbers or unrelated counts). BSD sed + GNU sed compatible.
  sed -E \
    -e "s/[0-9]+ golden-case assertions/${N} golden-case assertions/g" \
    -e "s/[(][0-9]+ assertions/(${N} assertions/g" \
    -e "s/[0-9]+ 项 golden-case 断言/${N} 项 golden-case 断言/g" \
    -e "s/[0-9]+ 项断言/${N} 项断言/g" \
    "$f" > "$tmp"
  if ! diff -q "$tmp" "$f" >/dev/null 2>&1; then
    if [[ "$check" -eq 1 ]]; then
      echo "drift: $f claims a stale assertion count (expected ${N}); run scripts/update-assertion-count.sh" >&2
      status=1
    else
      mv "$tmp" "$f"
      echo "updated $(basename "$f") -> ${N}"
      continue
    fi
  fi
  rm -f "$tmp"
done
# --- audit executed-count baseline (CHG-009 / FU-022) ---
# audit writes its executed count to $AUDIT_LAST each run; this script syncs
# the committed baseline. Drift (audit assertions changed without re-sync) → --check red.
AUDIT_BASELINE="$ROOT/tests/.audit-baseline"
AUDIT_LAST="${TMPDIR:-/tmp}/audit-executed-count"
if [[ ! -f "$AUDIT_BASELINE" && -f "$AUDIT_LAST" ]]; then
  # first-time bootstrap of the baseline (chicken-and-egg: audit cannot pass
  # until the baseline exists; AUDIT_LAST comes from the audit run just made)
  if [[ "$check" -eq 1 ]]; then
    echo "drift: tests/.audit-baseline missing (audit executed $(cat "$AUDIT_LAST")); run scripts/update-assertion-count.sh" >&2
    status=1
  else
    cp "$AUDIT_LAST" "$AUDIT_BASELINE"
    echo "created tests/.audit-baseline -> $(cat "$AUDIT_BASELINE")"
  fi
elif [[ -f "$AUDIT_BASELINE" && -f "$AUDIT_LAST" ]]; then
  if ! diff -q "$AUDIT_BASELINE" "$AUDIT_LAST" >/dev/null 2>&1; then
    if [[ "$check" -eq 1 ]]; then
      echo "drift: audit executed count changed ($(cat "$AUDIT_LAST")); run scripts/update-assertion-count.sh" >&2
      status=1
    else
      cp "$AUDIT_LAST" "$AUDIT_BASELINE"
      echo "updated tests/.audit-baseline -> $(cat "$AUDIT_BASELINE")"
    fi
  fi
fi

if [[ "$check" -eq 1 && "$status" -eq 0 ]]; then
  echo "assertion claims in sync with run-tests (${N})"
fi
exit "$status"
