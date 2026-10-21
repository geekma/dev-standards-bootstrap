#!/usr/bin/env bash
# lib-suite-tree-fingerprint.sh — suite receipt tree fingerprint (v3.79.0, CHG-103,
# REQ-1144). Ships with the Skill alongside tests/run-tests.sh (bootstrap --guard):
# the receipt emitter (run-tests.sh closing block) sources it from
# "$ROOT/scripts/lib-suite-tree-fingerprint.sh", and any local tool that wants to
# trust a suite receipt (same HEAD + same tree fingerprint + freshness window)
# sources the SAME recipe — one implementation, no drift. In the upstream repo the
# consumer is scripts/update-assertion-count.sh; a target repo may wire its own.
#
# Recipe: full-tree snapshot via a THROWAWAY index.
#   GIT_INDEX_FILE=<mktemp> git read-tree HEAD
#   GIT_INDEX_FILE=<mktemp> git add -A --
#   GIT_INDEX_FILE=<mktemp> git reset -q HEAD -- <claim files>
#   GIT_INDEX_FILE=<mktemp> git write-tree
# → tree OID (hex). Covers tracked modifications/deletions AND untracked
# file contents (porcelain only lists paths — that blind spot is exactly the
# hole this fingerprint closes). gitignored files (.agent-state) are excluded
# by `git add -A` semantics. A clean tree fingerprints as HEAD^{tree}, so the
# value is deterministic and stable across no-op re-computes.
#
# Claim-file exclusion (v3.79.0, live-incident-driven): the upstream assertion
# sync tool REWRITES README.md / README.zh-CN.md / tests/.audit-baseline AFTER
# the green run it consumes (count sync). Those files are the suite's OUTPUT
# claims, not suite inputs — including them would shift the fingerprint on every
# sync and permanently defeat the fast path this receipt exists for. The `git
# reset` restores their index entries to HEAD inside the throwaway index only;
# unmatched pathspecs are a no-op (rc=0), so a target repo without these files
# uses the same recipe unchanged. Everything else (tests/, scripts/, docs/,
# untracked files) still counts.
#
# Failure semantics (DES-1909): ANY failure (non-git repo, read-tree/add/write
# error) prints an empty string and exits 0 — the fingerprint is an
# optimization, never a gate; callers degrade to the legacy embedded run.
# Zero side effects on the real index: GIT_INDEX_FILE isolates every index
# operation in a mktemp file (pinned by suite golden TC-1383).

# suite_tree_fingerprint <repo> [reset-claim...] — print tree OID, or empty
# string on any failure. v3.83.0 (CHG-110, REQ-1161): optional extra reset-claim
# pathspecs are appended to the built-in claim reset INSIDE the throwaway index
# only — a verify-receipt consumer excludes its non-code face (e.g.
# docs/changes) so doc-only edits don't invalidate the cache. Backward
# compatible: existing two-arg callers keep byte-identical behavior.
suite_tree_fingerprint() {
  local repo="$1"; shift
  local claims=("$@") tmpdir out
  tmpdir=$(mktemp -d 2>/dev/null) || { printf ''; return 0; }
  out=$( cd "$repo" 2>/dev/null || exit 1
         git rev-parse -q --verify HEAD >/dev/null 2>&1 || exit 1
         export GIT_INDEX_FILE="$tmpdir/idx"
         git read-tree HEAD 2>/dev/null || exit 1
         git add -A -- 2>/dev/null || exit 1
         if (( ${#claims[@]} )); then
           git reset -q HEAD -- README.md README.zh-CN.md tests/.audit-baseline "${claims[@]}" 2>/dev/null || true
         else
           git reset -q HEAD -- README.md README.zh-CN.md tests/.audit-baseline 2>/dev/null || true
         fi
         git write-tree 2>/dev/null || exit 1 ) || {
    rm -rf "$tmpdir" 2>/dev/null || true
    printf ''
    return 0
  }
  rm -rf "$tmpdir" 2>/dev/null || true
  case "$out" in
    ''|*[!0-9a-f]*) printf '' ;;   # empty/non-hex output degrades to "no fingerprint"
    *) printf '%s\n' "$out" ;;
  esac
  return 0
}
