#!/usr/bin/env bash
# update-assertion-count.sh — recompute the golden-case assertion count from a
# real run-tests.sh execution (runtime `N passed`) and rewrite the claims in
# both READMEs.
#
#   update-assertion-count.sh          # rewrite READMEs to the real count
#   update-assertion-count.sh --check  # exit 1 if any README would change (CI/audit mode)
#
# NOTE: both modes execute the FULL run-tests.sh (FU-907) — unless a fresh
# same-HEAD-and-tree suite receipt exists (v3.66.0, below), which skips the
# embedded run. Six acceptance conditions: HEAD match, tree fingerprint match,
# zero failed, mtime freshness, valid numbers, fingerprint lib present.
# Never run this script concurrently with a manual run-tests.sh in the same
# workspace: a concurrent green run could overwrite the receipt mid-flight
# (declared weakly consistent; the five acceptance conditions below still
# reject stale / other-HEAD receipts, and the embedded-run fallback is intact).
#
# Source-layer only (NOT shipped with the Skill): READMEs live in this repo.
# Closes FU-005 (hand-maintained numbers drifted 107/118 vs real) and
# compensates the FU-009 A3 regex residual (`assertions: N` form) by making
# every claim site generated. Zero deps: bash + grep + sed + diff.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# N is the RUNTIME passed count — the number a user actually sees. Static
# call-site counting undercounts by construction: same-line conditional chains
# (`grep … && report … || report …`) anchor nowhere at line start (0 sites for
# 1+ runtime calls) and loop-driven sites run k>1 times (CHG-019 review: static
# 288 vs runtime 291 — the same 3-gap already existed at 281/284).
# v3.66.0 (CHG-088, REQ-1050): same-HEAD receipt fast path. A green FULL
# run-tests.sh run writes .agent-state/last-suite-receipt.json. When it exists,
# parses, matches the CURRENT HEAD, reports 0 failed and is fresh (mtime age <=
# AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN minutes; default 30, 0 disables, invalid
# values fall back to the default), trust its count and skip the embedded run.
# v3.79.0 (CHG-103, REQ-1143): the trust condition gains a tree-fingerprint gate
# — "same HEAD + same tree fingerprint + freshness window". The fingerprint is a
# full-worktree snapshot (throwaway git index; see
# scripts/lib-suite-tree-fingerprint.sh, the SAME recipe the emitter uses), so a
# worktree edited after a green run is NOT trusted even at the same HEAD. A
# receipt without the field (pre-v3.79.0 schema) or with an empty/unmatchable
# fingerprint is treated as stale — backward-compatible in the fail-closed
# direction (embedded run re-derives the truth; never fail-open to a wrong
# number).
# Anything else falls through to the legacy embedded run below — fail-open to
# the status quo, never to a wrong number. Local gitignored file, same trust
# level as session-started.json (no signature); the receipt is an optimization,
# the suite's own output stays the primary evidence.
N=""
F=""
RECEIPT="$ROOT/.agent-state/last-suite-receipt.json"
rc_head=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
rc_max="${AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN:-30}"
case "$rc_max" in ''|*[!0-9]*) rc_max=30 ;; esac
# fingerprint recipe must exist for the gate to be meaningful; absence degrades
# to the legacy head+TTL... no — absence degrades to REJECT (REQ-1143): without
# the recipe we cannot prove the worktree is unchanged, so the fast path is off.
if [[ -f "$ROOT/scripts/lib-suite-tree-fingerprint.sh" ]]; then
  source "$ROOT/scripts/lib-suite-tree-fingerprint.sh"
fi
if [[ -n "$rc_head" && "$rc_max" != "0" && -f "$RECEIPT" ]] && ! command -v suite_tree_fingerprint >/dev/null 2>&1; then
  printf 'update-assertion-count: fingerprint lib missing — receipt fast path disabled, embedded full run\n' >&2
fi
if [[ -n "$rc_head" && "$rc_max" != "0" && -f "$RECEIPT" ]] && command -v suite_tree_fingerprint >/dev/null 2>&1; then
  r_head=$(sed -nE 's/.*"head":"([0-9a-f]{7,40})".*/\1/p' "$RECEIPT" | tail -n 1)
  r_fp=$(sed -nE 's/.*"tree_fingerprint":"([0-9a-f]+)".*/\1/p' "$RECEIPT" | tail -n 1)
  r_pass=$(sed -nE 's/.*"passed":([0-9]+).*/\1/p' "$RECEIPT" | tail -n 1)
  r_fail=$(sed -nE 's/.*"failed":([0-9]+).*/\1/p' "$RECEIPT" | tail -n 1)
  if [[ -n "$r_head" && -n "$r_pass" && -n "$r_fail" && "$r_head" == "$rc_head" && "$r_fail" == 0 ]]; then
    # v3.79.0 (CHG-103, REQ-1143): tree-fingerprint gate. Missing receipt field
    # (old schema), empty current fingerprint (non-git/lib failure), or a
    # mismatch (worktree changed since the run) all reject the receipt — the
    # embedded run below re-derives the truth.
    r_cur=$(suite_tree_fingerprint "$ROOT")
    if [[ -z "$r_fp" || -z "$r_cur" ]]; then
      printf 'update-assertion-count: receipt tree-fingerprint missing (%s) — embedded full run\n' \
        "$([[ -z "$r_fp" ]] && echo "receipt field (pre-v3.79.0 schema or lib absent at emit)" || echo "worktree fingerprint")" >&2
    elif [[ "$r_fp" != "$r_cur" ]]; then
      printf 'update-assertion-count: receipt tree-fingerprint mismatch (worktree changed since the run) — embedded full run\n' >&2
    else
    # freshness via mtime (GNU/BSD stat dual form, session-started.json precedent;
    # v3.67.0 erratum CHG-092: GNU-first — GNU stat -f %m prints '?m' rc=0, so the
    # BSD-first form left the GNU fallback unreachable on Linux and every receipt
    # was rejected as stale);
    # negative age (future mtime / clock skew) is treated as fresh — the emitter
    # never writes future stamps and this is a local-trust optimization.
    r_mtime=$(stat -c %Y "$RECEIPT" 2>/dev/null || stat -f %m "$RECEIPT" 2>/dev/null || true)
    case "$r_mtime" in ''|*[!0-9]*) r_mtime="" ;; esac
    if [[ -n "$r_mtime" ]]; then
      r_age=$(( $(date +%s) - r_mtime ))
      if [[ "$r_age" -le $(( rc_max * 60 )) ]]; then
        N="$r_pass"; F="$r_fail"
        printf 'update-assertion-count: trusting suite receipt for %.12s (passed=%s, tree-match, age<=%smin); embedded full run skipped\n' "$rc_head" "$N" "$rc_max" >&2
      fi
    fi
    fi
  fi
fi
if [[ -z "$N" || -z "$F" ]]; then
  # v3.78.0（CHG-102，REQ-1136）：内嵌全跑改节级并行——收口/源层审计的内嵌整跑是纯断言语义，
  # 节级池只改墙钟不改判定（SERIAL_CHAIN 恒串行，池先 wait 收口；CHG-095 实测 807s→227s）。
  # 并发数按机器可调：AGENT_GUARD_SUITE_JOBS（默认 4；非数字或 <1 回落 4，`-j 1` 是合法串行请求）。
  suite_jobs="${AGENT_GUARD_SUITE_JOBS:-4}"
  case "$suite_jobs" in ''|*[!0-9]*) suite_jobs=4 ;; esac
  [[ "$suite_jobs" -ge 1 ]] || suite_jobs=4
  run_out=$(bash "$ROOT/tests/run-tests.sh" -j "$suite_jobs" 2>&1) || true
  # v3.65.0 (CHG-087, REQ-1048): run-tests now appends a constant `wall-time: Ns`
  # line AFTER the summary — take the LAST matching line instead of the last raw
  # line. Both sed anchors stay byte-identical (audit A3 shares them).
  N=$(printf '%s\n' "$run_out" | sed -nE 's/^([0-9]+) passed, [0-9]+ failed$/\1/p' | tail -n 1)
  F=$(printf '%s\n' "$run_out" | sed -nE 's/^[0-9]+ passed, ([0-9]+) failed$/\1/p' | tail -n 1)
fi
[[ -n "$N" && -n "$F" ]] || { echo "cannot determine assertion count from run-tests output: ${run_out:-<empty>}" >&2; exit 2; }
[[ "$F" == 0 ]] || { echo "run-tests reported ${F} failed — refusing to sync claims off a red suite" >&2; exit 2; }
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
    -e "s/[0-9]+ 条 golden-case 断言/${N} 条 golden-case 断言/g" \
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
