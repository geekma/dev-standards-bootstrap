#!/usr/bin/env bash
# update-assertion-count.sh — recompute the golden-case assertion count from a
# real run-tests.sh execution (runtime `N passed`) and rewrite the claims in
# both READMEs.
#
#   update-assertion-count.sh          # rewrite READMEs to the real count
#   update-assertion-count.sh --check  # exit 1 if any README would change (CI/audit mode)
#   update-assertion-count.sh --check --from-baseline
#                                      # read tests/.suite-baseline; NEVER run the suite
#   update-assertion-count.sh --check --require-receipt
#                                      # require a fresh same-tree receipt; NEVER run the suite
#
# Evidence sources, in priority order: `--from-baseline` (committed evidence;
# source audit A3 uses this), a fresh same-HEAD/same-tree green receipt
# (v3.66.0/v3.79.0), then the embedded FULL run-tests.sh (FU-907). The default
# write mode updates README claims AND tests/.suite-baseline, so the committed
# baseline always tracks the last real green run (or its same-tree receipt).
# Scope of each source: `--from-baseline` proves the *claim face* equals the
# committed number; it does not prove that number is current. Runtime truth is
# produced only by a real full run — CI's single run plus `ci-summary.sh --check`,
# or locally `verify-all.sh` (which runs or reuses a same-tree receipt).
# Six receipt acceptance conditions: HEAD match, tree fingerprint match, zero
# failed, mtime freshness, valid numbers, fingerprint lib present.
# Never run this script concurrently with a manual run-tests.sh in the same
# workspace: a concurrent green run could overwrite the receipt mid-flight
# (declared weakly consistent; the six acceptance conditions below still
# reject stale / other-HEAD receipts, and the embedded-run fallback is intact).
#
# Source-layer only (NOT shipped with the Skill): READMEs live in this repo.
# Closes FU-005 (hand-maintained numbers drifted 107/118 vs real) and
# compensates the FU-009 A3 regex residual (`assertions: N` form) by making
# every claim site generated. Zero deps: bash + grep + sed + diff.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
check=0
from_baseline=0
require_receipt=0
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    --from-baseline) from_baseline=1 ;;
    --require-receipt) require_receipt=1 ;;
    -h|--help)
      awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"
      exit 0 ;;
    *) echo "update-assertion-count: unknown argument '$arg' (supported: --check --from-baseline --require-receipt)" >&2; exit 2 ;;
  esac
done
if [[ "$from_baseline" -eq 1 && "$require_receipt" -eq 1 ]]; then
  echo "update-assertion-count: --from-baseline and --require-receipt are mutually exclusive evidence sources" >&2
  exit 2
fi
SUITE_BASELINE="$ROOT/tests/.suite-baseline"
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
RECEIPT="${AGENT_GUARD_SUITE_RECEIPT_PATH:-$ROOT/.agent-state/last-suite-receipt.json}"
# --from-baseline: the committed suite baseline is the evidence. Never touch the
# receipt or the suite here — A3 (source audit) depends on this being a pure
# read/compare path, so a stale receipt can no longer turn an 8s audit into a
# 5-minute suite run (CHG-115, REQ-1184/1185).
if [[ "$from_baseline" -eq 1 ]]; then
  if [[ ! -f "$SUITE_BASELINE" ]]; then
    echo "update-assertion-count: --from-baseline requires $SUITE_BASELINE (run a green suite + this script first)" >&2
    exit 2
  fi
  N=$(tr -d '[:space:]' < "$SUITE_BASELINE")
  case "$N" in
    ''|*[!0-9]*)
      echo "update-assertion-count: $SUITE_BASELINE must contain one decimal number (got '${N}')" >&2
      exit 2 ;;
  esac
  F=0
fi
rc_head=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
rc_max="${AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN:-30}"
case "$rc_max" in ''|*[!0-9]*) rc_max=30 ;; esac
rc_fallback="embedded full run"
[[ "$require_receipt" -eq 1 ]] && rc_fallback="--require-receipt will fail closed"
# v3.87.0 (CHG-115, REQ-1185): the receipt-trust decision has exactly one
# implementation — sf_receipt_fresh (head + tree fingerprint + failed=0 + TTL).
# Absence of the lib means absence of the fast path (REJECT, REQ-1143): without
# the recipe we cannot prove the worktree is unchanged.
if [[ -f "$ROOT/scripts/lib-source-facts.sh" ]]; then
  source "$ROOT/scripts/lib-source-facts.sh"
fi
if [[ -z "$N" && -n "$rc_head" && "$rc_max" != "0" && -f "$RECEIPT" ]]; then
  if ! command -v sf_receipt_fresh >/dev/null 2>&1; then
    printf 'update-assertion-count: fingerprint lib missing — receipt fast path disabled, %s\n' "$rc_fallback" >&2
  else
    rc_cur=$(sf_tree_fingerprint "$ROOT")
    if sf_receipt_fresh "$ROOT" "$rc_cur"; then
      r_pass=$(sf_read_json_num "$RECEIPT" passed)
      case "$r_pass" in ''|*[!0-9]*) r_pass="" ;; esac
      if [[ -n "$r_pass" ]]; then
        N="$r_pass"; F=0
        printf 'update-assertion-count: trusting suite receipt for %.12s (passed=%s, tree-match, age<=%smin); embedded full run skipped\n' "$rc_head" "$N" "$rc_max" >&2
      fi
    else
      # Diagnostics only — the accept/reject decision is sf_receipt_fresh's alone.
      r_fp=$(sf_read_json_str "$RECEIPT" tree_fingerprint)
      if [[ -z "$r_fp" || -z "$rc_cur" ]]; then
        printf 'update-assertion-count: receipt tree-fingerprint missing (%s) — %s\n' \
          "$([[ -z "$r_fp" ]] && echo "receipt field (pre-v3.79.0 schema or lib absent at emit)" || echo "worktree fingerprint")" \
          "$rc_fallback" >&2
      else
        printf 'update-assertion-count: receipt tree-fingerprint mismatch (worktree changed since the run) — %s\n' "$rc_fallback" >&2
      fi
    fi
  fi
fi
if [[ -z "$N" || -z "$F" ]]; then
  # --require-receipt is the manual fail-closed switch: no fresh evidence means
  # "run the suite yourself (or verify-all --fresh)", never an implicit rerun.
  if [[ "$require_receipt" -eq 1 ]]; then
    echo "update-assertion-count: --require-receipt found no fresh same-HEAD/same-tree green suite receipt at $RECEIPT (run tests/run-tests.sh or scripts/verify-all.sh --fresh first)" >&2
    exit 2
  fi
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
status=0
# The committed baseline tracks the same evidence the README claims use. Write
# mode updates it; --check reports drift only when the file already exists (a
# pre-baseline repo/fixture keeps its legacy behavior; A3 uses --from-baseline,
# which fails closed on a missing file instead). CHG-115, REQ-1184.
if [[ "$from_baseline" -eq 0 ]]; then
  baseline_cur=""
  [[ -f "$SUITE_BASELINE" ]] && baseline_cur=$(tr -d '[:space:]' < "$SUITE_BASELINE")
  if [[ "$baseline_cur" != "$N" ]]; then
    if [[ "$check" -eq 1 && -f "$SUITE_BASELINE" ]]; then
      echo "drift: tests/.suite-baseline is ${baseline_cur:-missing} (expected ${N}); run scripts/update-assertion-count.sh" >&2
      status=1
    elif [[ "$check" -eq 0 ]]; then
      printf '%s\n' "$N" > "$SUITE_BASELINE"
      echo "updated tests/.suite-baseline -> ${N}"
    fi
  fi
fi
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
# --- audit assertion-NAME set baseline (CHG-121, batch 0) ---
# A total-only baseline silently accepts "a whole block never executed but the
# count matched" (BUG-004). The audit writes every executed assertion name;
# this syncs the sorted set. Drift (names added/dropped without re-sync) → red.
AUDIT_ASSERTIONS="$ROOT/tests/.audit-assertions"
# v3.91.9 (CHG-127): key the completed-run names file by repo root. A bare
# /tmp/audit-executed-names is shared by every checkout on the host, so running
# the audit in one project made another project's A3 report phantom drift.
AUDIT_NAMES_LAST="${TMPDIR:-/tmp}/audit-executed-names.$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
if [[ -f "$AUDIT_NAMES_LAST" ]]; then
  # v3.91.9 (CHG-127): docs/private-dependent assertions now keep one stable
  # name in both environments (the audit echoes SKIP separately), so the set
  # comparison is environment-invariant and needs no normalization here.
  tmp_names=$(mktemp)
  sort -u "$AUDIT_NAMES_LAST" > "$tmp_names" 2>/dev/null || true
  if [[ -f "$AUDIT_ASSERTIONS" ]] && diff -q "$tmp_names" "$AUDIT_ASSERTIONS" >/dev/null 2>&1; then
    rm -f "$tmp_names"
  elif [[ "$check" -eq 1 ]]; then
    echo "drift: tests/.audit-assertions does not match the executed assertion names; run scripts/update-assertion-count.sh" >&2
    status=1
    rm -f "$tmp_names"
  else
    mv "$tmp_names" "$AUDIT_ASSERTIONS"
    echo "updated tests/.audit-assertions -> $(wc -l < "$AUDIT_ASSERTIONS" | tr -d ' ') names"
  fi
fi

# The README API table also pins the audit's executed count in the
# `(assertions: N)` / `（断言：N）` form (audit A54b). Sync it from the baseline
# so a baseline bump can never leave a stale documented number.
if [[ -f "$AUDIT_BASELINE" ]]; then
  audit_n=$(tr -d '[:space:]' < "$AUDIT_BASELINE")
  for f in "$ROOT/README.md" "$ROOT/README.zh-CN.md"; do
    tmp=$(mktemp)
    sed -E \
      -e "s/\(assertions: [0-9]+\)/(assertions: ${audit_n})/g" \
      -e "s/（断言：[0-9]+）/（断言：${audit_n}）/g" \
      "$f" > "$tmp"
    if ! diff -q "$tmp" "$f" >/dev/null 2>&1; then
      if [[ "$check" -eq 1 ]]; then
        echo "drift: $f audit assertion count is stale (expected ${audit_n}); run scripts/update-assertion-count.sh" >&2
        status=1
      else
        mv "$tmp" "$f"
        echo "updated $(basename "$f") audit count -> ${audit_n}"
        continue
      fi
    fi
    rm -f "$tmp"
  done
fi

if [[ "$check" -eq 1 && "$status" -eq 0 ]]; then
  echo "assertion claims in sync with run-tests (${N})"
fi
exit "$status"
