#!/usr/bin/env bash
# evidence-round.sh — run one suite evidence round into an append-only directory.
#
#   scripts/evidence-round.sh --chg <CHG-id> [--round N] [--shards 6]
#                             [--live-shard S] [--no-sum] [--dry-run]
#                             [--state-dir DIR] [--skip-precheck] [--fail-fast]
#   scripts/evidence-round.sh --carry-check [--state-dir DIR]
#   scripts/evidence-round.sh --carry --chg <CHG-id> [--state-dir DIR]
#
#   --chg        change id (also the directory name); required except --carry-check
#   --round N    explicit round number; default = next free number (never reuses)
#   --shards N   shard count, default 6 (min 2)
#   --live-shard S
#                the one shard that runs WITHOUT --worktree (default: the shard
#                that contains T87 — inside a snapshot T87 early-exits, so the
#                live shard is what makes the total comparable to the baseline)
#   --no-sum     skip the shard-sum call at the end
#   --dry-run    print the planned commands and exit; creates nothing
#   --state-dir  root for round dirs and ledger (default .agent-state/evidence).
#                A custom dir INSIDE the repo joins the code face, so --carry
#                never matches itself (the copy moves the fingerprint): keep it
#                outside the repo or gitignored. An in-repo, un-ignored state dir
#                also trips the mid-round drift check — every such round is INVALID.
#   --skip-precheck
#                do not run scripts/pre-round-check.sh before starting
#   --fail-fast  stop the round on the first non-live shard with a non-zero rc:
#                terminate the siblings, record 143 for them, skip the sum
#   --carry-check
#                read-only: is there a green round whose code face (tree minus
#                docs/changes, docs/bugs) equals the current one? rc0 = yes
#   --carry      create a new round by copying that green round's artifacts
#                (no shards run). The source round must have rc=0.
#
# Layout: <state-dir>/<CHG>/round-<N>/{shard-<i>.log,.rc,.mode,meta.tsv,sum.txt}
#         <state-dir>/ledger.tsv  (one row per round; schema is header-driven)
#
# An existing round directory is refused with rc2: evidence rounds are
# append-only so a failed shard's log is never overwritten by the next attempt
# (CHG-133 REQ-1330). rc 0 = every shard green and sum green · 1 = red (all
# artifacts kept) · 2 = usage/environment.
#
# Freeze (v3.97.1, CHG-135 REQ-1350): the round holds
# .agent-state/evidence-round.lock for its whole life; agent-gate --stage
# pre-write refuses edits to fingerprint-counted files while it lives
# (GATE-E156), and an edit that still lands makes the round INVALID —
# rc2, meta tree_drift=1 + tree_sha_end, INVALID banner in sum.txt.
#
# v3.97.0 (CHG-134): preflight (REQ-1340), --fail-fast (REQ-1341) and the
# code-face fingerprint / carry path (REQ-1342). The fingerprint uses the same
# recipe as the suite receipt (scripts/lib-suite-tree-fingerprint.sh). Its claim
# face is the recipe's built-in claims (README.md, README.zh-CN.md,
# tests/.audit-baseline, tests/.suite-baseline — rewritten by the assertion-count
# sync after a green run) plus docs/changes and docs/bugs, so this change's own
# paper trail keeps the code face stable while every code edit moves it.
#
# AGENT_GUARD_EVIDENCE_SUITE overrides the suite path (T87 drives the tool with
# a stub; the real runner would cost a full sharded round). The suite path is
# recorded per round, and --carry only accepts a source round that ran the same
# suite.
set -uo pipefail

STATE_DIR=".agent-state/evidence"
CHG=""; ROUND=""; SHARDS=6; LIVE_SHARD=""; NO_SUM=0; DRY=0
FAIL_FAST=0; CARRY_CHECK=0; CARRY=0; SKIP_PRECHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --chg) [[ $# -ge 2 && -n "$2" ]] || { echo "evidence-round: --chg needs a value" >&2; exit 2; }
      CHG="$2"; shift 2 ;;
    --round) [[ $# -ge 2 && -n "$2" ]] || { echo "evidence-round: --round needs a value" >&2; exit 2; }
      ROUND="$2"; shift 2 ;;
    --shards) [[ $# -ge 2 && -n "$2" ]] || { echo "evidence-round: --shards needs a value" >&2; exit 2; }
      SHARDS="$2"; shift 2 ;;
    --live-shard) [[ $# -ge 2 && -n "$2" ]] || { echo "evidence-round: --live-shard needs a value" >&2; exit 2; }
      LIVE_SHARD="$2"; shift 2 ;;
    --state-dir) [[ $# -ge 2 && -n "$2" ]] || { echo "evidence-round: --state-dir needs a value" >&2; exit 2; }
      STATE_DIR="$2"; shift 2 ;;
    --no-sum) NO_SUM=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --fail-fast) FAIL_FAST=1; shift ;;
    --carry-check) CARRY_CHECK=1; shift ;;
    --carry) CARRY=1; shift ;;
    --skip-precheck) SKIP_PRECHECK=1; shift ;;
    -h|--help) sed -n '2,59p' "$0"; exit 0 ;;
    *) echo "evidence-round: unknown option '$1' (supported: --chg --round --shards --live-shard --no-sum --dry-run --state-dir --skip-precheck --fail-fast --carry-check --carry)" >&2; exit 2 ;;
  esac
done
[[ "$CARRY_CHECK" -eq 1 && "$CARRY" -eq 1 ]] \
  && { echo "evidence-round: --carry-check is read-only and exclusive with --carry" >&2; exit 2; }
[[ -n "$CHG" || "$CARRY_CHECK" -eq 1 ]] \
  || { echo "evidence-round: --chg <CHG-id> is required" >&2; exit 2; }
if [[ -n "$CHG" ]]; then
  [[ "$CHG" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "evidence-round: invalid --chg '$CHG'" >&2; exit 2; }
fi
[[ "$SHARDS" =~ ^[1-9][0-9]*$ && "$SHARDS" -ge 2 ]] \
  || { echo "evidence-round: --shards must be an integer >= 2 (one shard is just a full run)" >&2; exit 2; }
if [[ -n "$LIVE_SHARD" ]]; then
  [[ "$LIVE_SHARD" =~ ^[1-9][0-9]*$ && "$LIVE_SHARD" -le "$SHARDS" ]] \
    || { echo "evidence-round: --live-shard must be 1..$SHARDS" >&2; exit 2; }
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "evidence-round: not a git repository (worktree snapshots need one)" >&2; exit 2; }
cd "$ROOT" || exit 2
SUITE="${AGENT_GUARD_EVIDENCE_SUITE:-$ROOT/tests/run-tests.sh}"
if [[ "$CARRY_CHECK" -eq 0 ]]; then
  [[ -f "$SUITE" ]] || { echo "evidence-round: suite not found at $SUITE" >&2; exit 2; }
fi

_ledger="$STATE_DIR/ledger.tsv"

# v3.97.0 (CHG-134, REQ-1342): the ledger gained code_face_sha + carried_from.
# Migrate the header once, padding old rows with '-', so readers stay
# header-driven and no pre-existing round loses its facts. Migration writes the
# ledger, so it belongs to the append path only — --carry-check is read-only.
_ledger_ensure_schema() {
  [[ -f "$_ledger" ]] || return 0
  head -1 "$_ledger" | grep -q 'code_face_sha' && return 0
  local _tmp
  _tmp="$(mktemp 2>/dev/null)" || return 0
  awk -F'\t' 'BEGIN{OFS="\t"} NR==1{print $0,"code_face_sha","carried_from"; next} {print $0,"-","-"}' \
    "$_ledger" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$_ledger" 2>/dev/null || rm -f "$_tmp" 2>/dev/null
}
_ledger_col() { head -1 "$_ledger" 2>/dev/null | tr '\t' '\n' | awk -v n="$1" '$0==n{print NR; exit}'; }
# A ledger that predates the carry columns cannot prove any carry: say so by
# name instead of reporting "no candidate" (which would read as "code changed").
_ledger_carry_ready() {
  [[ -f "$_ledger" ]] || return 1
  head -1 "$_ledger" | grep -q 'code_face_sha'
}

# The tree the round ran against. Same recipe as the suite receipt (and as
# _code_face) so untracked files count — `git ls-files` alone missed a docs edit
# that had not been staged yet, which made --carry-check refuse a valid pair.
_tree_sha() {
  local _lib="$ROOT/scripts/lib-suite-tree-fingerprint.sh"
  [[ -f "$_lib" ]] || { printf ''; return 0; }
  ( . "$_lib"; suite_tree_fingerprint "$ROOT" )
}

# Claim face = the built-in claims of the fingerprint recipe (README.md,
# README.zh-CN.md, tests/.audit-baseline, tests/.suite-baseline — all rewritten
# by the assertion-count sync AFTER the green run) plus this change's own paper
# trail (docs/changes, docs/bugs).
_code_face() {
  local _lib="$ROOT/scripts/lib-suite-tree-fingerprint.sh"
  [[ -f "$_lib" ]] || { printf ''; return 0; }
  ( . "$_lib"; suite_tree_fingerprint "$ROOT" docs/changes docs/bugs )
}

# _find_carry <code-face> <tree-sha> -> "round<TAB>dir<TAB>tree" (latest match).
# Read-only: no header migration, no writes.
_find_carry() {
  _ledger_carry_ready || return 1
  [[ -f "$_ledger" ]] || return 1
  local _rc _fc _tc _rd _dr _tp
  _rc=$(_ledger_col rc); _fc=$(_ledger_col code_face_sha); _tc=$(_ledger_col tree_sha)
  _rd=$(_ledger_col round); _dr=$(_ledger_col dir); _tp=$(_ledger_col total)
  [[ -n "$_rc" && -n "$_fc" && -n "$_tc" && -n "$_rd" && -n "$_dr" && -n "$_tp" ]] || return 1
  awk -F'\t' -v face="$1" -v tree="$2" -v rc="$_rc" -v fc="$_fc" -v tc="$_tc" \
      -v rd="$_rd" -v dr="$_dr" -v tp="$_tp" '
    $rc=="0" && $fc==face && $tc!=tree && $tp!="-" && $tp!="" { r=$rd; d=$dr; t=$tc }
    END { if (r=="") exit 1; printf "%s\t%s\t%s\n", r, d, t }' "$_ledger"
}

_append_ledger() { # ts chg round head tree shards live total failed rc wall dir face carried
  _ledger_ensure_schema
  if [[ ! -f "$_ledger" ]]; then
    mkdir -p "$(dirname "$_ledger")" 2>/dev/null || return 1
    printf 'ts\tchg\tround\thead\ttree_sha\tshards\tlive_shard\ttotal\tfailed\trc\twall_s\tdir\tcode_face_sha\tcarried_from\n' \
      >> "$_ledger" || return 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$_ledger"
}

# v3.97.0 (CHG-134, REQ-1342): carry is explicit opt-in and read-only until a
# candidate is found; a green round with the same code face is required.
if [[ "$CARRY_CHECK" -eq 1 ]]; then
  _face=$(_code_face)
  [[ -n "$_face" ]] \
    || { echo "carry-check: code-face fingerprint unavailable (scripts/lib-suite-tree-fingerprint.sh missing or not a git tree)" >&2; exit 1; }
  [[ -f "$_ledger" ]] \
    || { echo "carry-check: no ledger at $_ledger — no round has been recorded yet, nothing to carry" >&2; exit 2; }
  _ledger_carry_ready \
    || { echo "carry-check: $_ledger predates the carry columns (no code_face_sha) — run one normal round to migrate it, then re-check" >&2; exit 2; }
  _tree=$(_tree_sha)
  if _row=$(_find_carry "$_face" "$_tree"); then
    IFS=$'\t' read -r _r _d _t <<< "$_row"
    echo "carryable: round $_r (tree $_t, code_face $_face) at $_d"
    exit 0
  fi
  echo "carry-check: no green round with the current code face and a different tree (code changed, or no prior green round)" >&2
  exit 1
fi

if [[ "$CARRY" -eq 1 ]]; then
  [[ -n "$CHG" ]] || { echo "evidence-round: --carry needs --chg" >&2; exit 2; }
  [[ "$DRY" -eq 0 ]] || { echo "evidence-round: --carry does not combine with --dry-run" >&2; exit 2; }
  _face=$(_code_face)
  [[ -n "$_face" ]] \
    || { echo "evidence-round: code-face fingerprint unavailable — refusing to carry without a code-face identity" >&2; exit 2; }
  [[ -f "$_ledger" ]] \
    || { echo "evidence-round: no ledger at $_ledger — no round has been recorded yet, nothing to carry" >&2; exit 2; }
  _ledger_carry_ready \
    || { echo "evidence-round: $_ledger predates the carry columns (no code_face_sha) — run one normal round to migrate it" >&2; exit 2; }
  _tree=$(_tree_sha)
  _row=$(_find_carry "$_face" "$_tree") \
    || { echo "evidence-round: no carryable round (need a green round with the same code face and a different tree)" >&2; exit 2; }
  IFS=$'\t' read -r _src_round _src_dir _src_tree <<< "$_row"
  [[ -d "$_src_dir" ]] \
    || { echo "evidence-round: carry source round directory is gone: $_src_dir" >&2; exit 2; }
  _src_meta="$_src_dir/meta.tsv"
  [[ -f "$_src_meta" ]] || { echo "evidence-round: carry source has no meta.tsv: $_src_dir" >&2; exit 2; }
  _src_total=$(awk -F'\t' '$1=="total_passed"{print $2}' "$_src_meta")
  _src_failed=$(awk -F'\t' '$1=="total_failed"{print $2}' "$_src_meta")
  [[ -n "$_src_total" && "$_src_total" != "-" ]] \
    || { echo "evidence-round: carry source round has no total (it never summed) — refusing to carry a blank result" >&2; exit 2; }
  _src_shards=$(awk -F'\t' '$1=="shards"{print $2}' "$_src_meta")
  _src_live=$(awk -F'\t' '$1=="live_shard"{print $2}' "$_src_meta")
  _src_suite=$(awk -F'\t' '$1=="suite"{print $2}' "$_src_meta")
  # Carry copies a result; it must be a result of THIS suite. A fixture round
  # (AGENT_GUARD_EVIDENCE_SUITE=stub) records its stub path, so it can never be
  # carried as evidence for the real runner.
  [[ "$_src_suite" == "$SUITE" ]] \
    || { echo "evidence-round: carry source round $_src_round ran $_src_suite, not $SUITE — refusing to carry a different suite's result" >&2; exit 2; }
  [[ "${_src_failed:-}" == "0" ]] \
    || { echo "evidence-round: carry source round $_src_round has total_failed='${_src_failed:-}' — refusing to carry a round with failures" >&2; exit 2; }
  # A row written before the ledger columns were fixed can claim rc=0 for a
  # drifted carry; the source round's own meta is the authority.
  _src_drift=$(awk -F'\t' '$1=="tree_drift"{print $2}' "$_src_meta")
  [[ "${_src_drift:-0}" == "0" ]] \
    || { echo "evidence-round: carry source round $_src_round certified a drifted tree (tree_drift=${_src_drift:-?}) — refusing to carry" >&2; exit 2; }
  # A green round can still be short: an all-snapshot round sums without the live
  # shard's full T87 section. A total below the pinned suite baseline is that shape
  # (or a truncated sum), so it is never a carryable full-suite truth.
  if [[ -f "$ROOT/tests/.suite-baseline" ]]; then
    _base=$(tr -d '[:space:]' < "$ROOT/tests/.suite-baseline" 2>/dev/null || true)
    if [[ "$_base" =~ ^[0-9]+$ && "$_src_total" =~ ^[0-9]+$ ]] && (( _src_total < _base )); then
      echo "evidence-round: carry source round $_src_round totals $_src_total, below tests/.suite-baseline ($_base) — that round is short (all-snapshot sum?), refusing to carry it" >&2
      exit 2
    fi
  fi

  if [[ -z "$ROUND" ]]; then
    ROUND=1
    for _d in "$STATE_DIR/$CHG"/round-*; do
      [[ -d "$_d" ]] || continue
      _n="${_d##*/round-}"
      [[ "$_n" =~ ^[0-9]+$ ]] || continue
      [[ "$_n" -ge "$ROUND" ]] && ROUND=$(( _n + 1 ))
    done
  else
    [[ "$ROUND" =~ ^[1-9][0-9]*$ ]] || { echo "evidence-round: --round must be a positive integer" >&2; exit 2; }
  fi
  RDIR="$STATE_DIR/$CHG/round-$ROUND"
  mkdir -p "$STATE_DIR/$CHG" 2>/dev/null || { echo "evidence-round: cannot create $STATE_DIR/$CHG" >&2; exit 2; }
  mkdir "$RDIR" 2>/dev/null || {
    echo "evidence-round: round directory already exists: $RDIR (rounds are append-only; omit --round to take the next free number)" >&2
    exit 2; }
  cp "$_src_dir"/shard-*.log "$RDIR"/ 2>/dev/null
  cp "$_src_dir"/shard-*.rc "$RDIR"/ 2>/dev/null
  cp "$_src_dir"/shard-*.mode "$RDIR"/ 2>/dev/null
  [[ -f "$_src_dir/sum.txt" ]] && cp "$_src_dir/sum.txt" "$RDIR/sum.txt"
  _head=$(git rev-parse HEAD 2>/dev/null || echo none)
  _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
  # A carry copies a result; it must not fabricate "no drift". Fingerprint once
  # before the copy and once after, exactly like a live round — a carry that
  # writes tree_drift 0 without ever looking is the same lie the round lock and
  # the end-of-round re-read exist to prevent.
  _tree_start=$(_tree_sha)
  [[ -n "$_tree_start" ]] \
    || { echo "evidence-round: cannot fingerprint the tree (scripts/lib-suite-tree-fingerprint.sh missing or unreadable) — refusing to carry" >&2; exit 2; }
  [[ "$_tree_start" == "$_tree" ]] \
    || { echo "evidence-round: the tree moved between the carry match and the copy — re-run the carry" >&2; exit 2; }
  _tree_end=$(_tree_sha)
  # Re-derive the code face too: the ledger row must not pair a new tree_sha
  # with the face sampled before the copy.
  _face_end=$(_code_face)
  _drift=0
  [[ -n "$_tree_end" && "$_tree_end" == "$_tree_start" ]] || _drift=1
  [[ -n "$_face_end" && "$_face_end" == "$_face" ]] || _drift=1
  _rc_carry=0
  (( _drift )) && _rc_carry=2
  {
    printf 'key\tvalue\n'
    printf 'chg\t%s\n' "$CHG"
    printf 'round\t%s\n' "$ROUND"
    printf 'head\t%s\n' "$_head"
    printf 'tree_sha\t%s\n' "$_tree_start"
    printf 'tree_drift\t%s\n' "$_drift"
    printf 'tree_sha_end\t%s\n' "${_tree_end:-none}"
    printf 'shards\t%s\n' "${_src_shards:-$SHARDS}"
    printf 'live_shard\t%s\n' "${_src_live:--}"
    printf 'started_at\t%s\n' "$_ts"
    printf 'wall_s\t0\n'
    printf 'total_passed\t%s\n' "$_src_total"
    printf 'total_failed\t%s\n' "$_src_failed"
    printf 'rc\t%s\n' "$_rc_carry"
    printf 'suite\t%s\n' "${_src_suite:-$SUITE}"
    printf 'code_face_sha\t%s\n' "$_face_end"
    printf 'carried_from\t%s\n' "$_src_round"
    printf 'fail-fast\t0\n'
    printf 'killed\t-\n'
  } > "$RDIR/meta.tsv"
  # Preserve the source's per-shard rc facts (they are what was audited then).
  awk -F'\t' '$1 ~ /^shard_[0-9]+_rc$/ {print}' "$_src_meta" >> "$RDIR/meta.tsv"
  if (( _drift )); then
    [[ -f "$RDIR/sum.txt" ]] || : > "$RDIR/sum.txt"
    printf 'INVALID: tree changed during the carry (start %s, end %s)\n' \
      "$_tree_start" "${_tree_end:-none}" >> "$RDIR/sum.txt"
  fi
  _append_ledger "$_ts" "$CHG" "$ROUND" "$_head" "$_tree_start" "${_src_shards:-$SHARDS}" "${_src_live:--}" \
    "${_src_total:--}" "${_src_failed:--}" "$_rc_carry" 0 "$RDIR" "${_face_end:--}" "$_src_round" \
    || { echo "evidence-round: cannot append to ledger at $_ledger — the round would have no trail" >&2; exit 2; }
  if (( _drift )); then
    echo "evidence-round: $CHG round $ROUND carry INVALID — the tree changed while it was copied (start $_tree_start, end ${_tree_end:-none}); not evidence" >&2
    exit 2
  fi
  echo "evidence-round: $CHG round $ROUND carried from round $_src_round · total ${_src_total}/${_src_failed} · rc=0 · 0s"
  exit 0
fi

# The live shard is the one whose sections include T87: a snapshot run there
# early-exits (1 assertion instead of 37) and the sum would sit 36 short.
if [[ -z "$LIVE_SHARD" ]]; then
  for _i in $(seq 1 "$SHARDS"); do
    _res=$(AGENT_GUARD_SUITE_SHARD_RESOLVE_ONLY=1 bash "$SUITE" --shard "$_i/$SHARDS" 2>/dev/null || true)
    case " $_res " in *" T87 "*) LIVE_SHARD="$_i"; break ;; esac
  done
  [[ -n "$LIVE_SHARD" ]] || LIVE_SHARD="$SHARDS"
fi

if [[ -z "$ROUND" ]]; then
  ROUND=1
  for _d in "$STATE_DIR/$CHG"/round-*; do
    [[ -d "$_d" ]] || continue
    _n="${_d##*/round-}"
    [[ "$_n" =~ ^[0-9]+$ ]] || continue
    [[ "$_n" -ge "$ROUND" ]] && ROUND=$(( _n + 1 ))
  done
else
  [[ "$ROUND" =~ ^[1-9][0-9]*$ ]] || { echo "evidence-round: --round must be a positive integer" >&2; exit 2; }
fi
RDIR="$STATE_DIR/$CHG/round-$ROUND"

# v3.97.1 (CHG-135, REQ-1347): a worktree shard runs in a disposable snapshot
# whose .agent-state dies with it, so its section costs never reached the shared
# ledger — five of six shards were invisible to the planner, which then priced
# those sections at its 2 s "unseen" default. Hand every shard the same absolute
# ledger path; an explicit AGENT_GUARD_COST_LEDGER still wins.
_shared_ledger="${AGENT_GUARD_COST_LEDGER:-$ROOT/.agent-state/cost-ledger.tsv}"
# Snapshot shards cd into their own worktree, so a relative override would resolve
# per shard and re-create the isolation this line exists to remove.
case "$_shared_ledger" in /*) ;; *) _shared_ledger="$ROOT/$_shared_ledger" ;; esac

if [[ "$DRY" -eq 1 ]]; then
  echo "evidence-round: $CHG round $ROUND -> $RDIR (live shard $LIVE_SHARD/$SHARDS)"
  for _i in $(seq 1 "$SHARDS"); do
    if [[ "$_i" -eq "$LIVE_SHARD" ]]; then _mode=live; _wt=""; else _mode=worktree; _wt=" --worktree"; fi
    echo "  shard $_i/$SHARDS $_mode: AGENT_GUARD_COST_LEDGER=\"$_shared_ledger\" bash $SUITE --shard $_i/$SHARDS$_wt > $RDIR/shard-$_i.log 2>&1"
  done
  [[ "$NO_SUM" -eq 1 ]] || echo "  sum: bash $ROOT/scripts/shard-sum.sh --logs $RDIR"
  exit 0
fi

# v3.97.0 (CHG-134, REQ-1340): static preflight before any round directory is
# created. Missing tool = skip notice (target repos do not ship it); rc1 =
# refuse to start (a known-missing registration would only burn a full round).
if [[ "$SKIP_PRECHECK" -eq 0 ]]; then
  if [[ -f "$ROOT/scripts/pre-round-check.sh" ]]; then
    bash "$ROOT/scripts/pre-round-check.sh" --root "$ROOT" || {
      _prc=$?
      echo "evidence-round: pre-round-check failed (rc=$_prc) — refusing to start a round that would burn shard time; fix the named item or pass --skip-precheck" >&2
      exit 2
    }
  else
    echo "evidence-round: pre-round-check.sh not present — skipping the static preflight" >&2
  fi
fi

_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
_start_s=$(date +%s)

# v3.97.1 (CHG-135, REQ-1350): a round testifies for exactly one tree, but
# nothing marked the tree as frozen — nine CHG-135 rounds were voided or
# reddened by edits made while or just before a round ran. Hold an owner-stamped
# lock for the round's whole life: the write-time hook (agent-gate --stage
# pre-write, GATE-E156) refuses fingerprint-counted edits while the owner lives,
# and the end-of-round drift check below turns any edit that bypassed the hook
# (raw sed, no hook installed) into an explicitly INVALID round.
# AGENT_GUARD_EVIDENCE_LOCK_DIR is a self-test seam only: tests/run-tests.sh
# drives this tool from inside a live round, whose lock must not block fixtures.
_ER_LOCK="${AGENT_GUARD_EVIDENCE_LOCK_DIR:-$ROOT/.agent-state/evidence-round.lock}"
mkdir -p "$(dirname "$_ER_LOCK")" 2>/dev/null || true
_er_trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
_ER_LSTART=$(LC_ALL=C ps -p $$ -o lstart= 2>/dev/null | _er_trim || true)
_tree=""
_er_age_gt() { # <path> <seconds> -> 0 when the path is older than <seconds>
  local _now _mt
  _now=$(date +%s 2>/dev/null || echo 0)
  _mt=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
  case "$_mt" in ''|*[!0-9]*) _mt=0 ;; esac
  [[ "$_mt" -gt 0 ]] || return 1
  [[ $(( _now - _mt )) -gt "$2" ]]
}
_er_lock_field() { # <file> <key> -> value
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1
}
_er_lock_set() { # <key> <value> — rewrite one field of the lock we own
  local _t
  _t=$(mktemp "$_ER_LOCK.set.XXXXXX" 2>/dev/null) || return 0
  awk -v k="$1" -v v="$2" '
    $0 ~ "^" k "=" { print k "=" v; seen=1; next }
    { print }
    END { if (!seen) print k "=" v }
  ' "$_ER_LOCK" > "$_t" 2>/dev/null && mv "$_t" "$_ER_LOCK" 2>/dev/null \
    || rm -f "$_t" 2>/dev/null || true
}
# A stamped lock is only alive when pid AND lstart match. An empty or torn
# lstart is "unknown", never "alive": treating unknown as alive would make a
# lock whose lstart was cut short unreclaimable forever once the pid is reused.
# LC_ALL=C is not cosmetic: `ps -o lstart=` is locale-formatted ("Fri Oct 30 …"
# vs "五 10月/30 …"), and two processes with different locale settings would
# each judge the other's live lock dead.
_er_owner_alive() { # <pid> <lstart>
  local _out _want
  [[ -n "$1" && -n "$2" ]] || return 1
  _out=$(LC_ALL=C ps -p "$1" -o lstart= 2>/dev/null | _er_trim || true)
  _want=$(printf '%s\n' "$2" | _er_trim)
  [[ -n "$_out" && -n "$_want" && "$_out" == "$_want" ]]
}
# The lock is a FILE published with `ln`: link(2) fails atomically when the
# target exists, so a contender can never overwrite (or nest into) a live
# owner's lock. A directory published with `mv` could not do this: on BSD,
# `mv dir existing-dir` moves INSIDE the target, and rm -rf + mkdir raced
# (CHG-135 review). The staged file is fully stamped before it is published.
_er_lock_stage() {
  local _d
  _d=$(mktemp "$_ER_LOCK.XXXXXX" 2>/dev/null) || return 1
  {
    printf 'pid=%s\n' "$$"
    printf 'lstart=%s\n' "$_ER_LSTART"
    printf 'chg=%s\n' "$CHG"
    printf 'round=%s\n' "$ROUND"
    printf 'tree_sha=%s\n' "${_tree:-}"
  } > "$_d" 2>/dev/null || { rm -f "$_d"; return 1; }
  printf '%s\n' "$_d"
}
# A SIGKILLed attempt leaves its staged file behind; nobody owns it and it is
# excluded from the fingerprint, so sweep the ones old enough to be abandoned.
_er_sweep_stages() {
  local _f
  for _f in "$_ER_LOCK".*; do
    [[ -e "$_f" ]] || continue
    _er_age_gt "$_f" 600 && rm -rf "$_f" 2>/dev/null
  done
  return 0
}
_er_lock_take() {
  local _i _p _l _try _aside
  _er_sweep_stages
  for _i in 1 2 3 4 5; do
    _try=$(_er_lock_stage) \
      || { echo "evidence-round: cannot stage the lock next to $_ER_LOCK" >&2; return 1; }
    if ln "$_try" "$_ER_LOCK" 2>/dev/null; then
      rm -f "$_try" 2>/dev/null || true
      return 0
    fi
    rm -f "$_try" 2>/dev/null || true
    _p=$(_er_lock_field "$_ER_LOCK" pid)
    _l=$(_er_lock_field "$_ER_LOCK" lstart)
    if _er_owner_alive "$_p" "$_l"; then
      echo "evidence-round: $_ER_LOCK is held by a live round (pid $_p) — two rounds on one tree would invalidate each other; wait for it or stop it first" >&2
      return 1
    fi
    # Owner-less or half-stamped lock (crashed taker): grace window, so a lock
    # being stamped right now is not stolen; past the window it is abandoned.
    if [[ -z "$_p" || -z "$_l" ]]; then
      _er_age_gt "$_ER_LOCK" 5 || {
        echo "evidence-round: $_ER_LOCK is being taken (no complete owner stamp yet) — retry in a few seconds" >&2
        return 1; }
    fi
    # Break in by rename, never rm -rf: the file moved aside is exactly the one
    # just judged dead, so a concurrent takeover cannot be deleted mid-flight.
    _aside="$_ER_LOCK.stale.$$"
    rm -f "$_aside" 2>/dev/null || true
    mv "$_ER_LOCK" "$_aside" 2>/dev/null || {
      echo "evidence-round: $_ER_LOCK is stale but another process is reclaiming it" >&2
      return 1; }
    _p=$(_er_lock_field "$_aside" pid)
    _l=$(_er_lock_field "$_aside" lstart)
    if _er_owner_alive "$_p" "$_l"; then
      # Restore with link(2): if a third process published a lock during the
      # gap, `mv` would delete that live lock. EEXIST means somebody else owns
      # the path now; keep theirs, drop ours, and say so.
      if ln "$_aside" "$_ER_LOCK" 2>/dev/null; then
        echo "evidence-round: $_ER_LOCK is held by a live round (pid $_p)" >&2
      else
        echo "evidence-round: $_ER_LOCK was republished during a stale-lock takeover — leaving the new owner in place" >&2
      fi
      rm -f "$_aside" 2>/dev/null || true
      return 1
    fi
    rm -f "$_aside" 2>/dev/null || true
  done
  echo "evidence-round: cannot acquire $_ER_LOCK" >&2
  return 1
}
_er_lock_release() {
  local _p _l
  _p=$(_er_lock_field "$_ER_LOCK" pid)
  [[ "$_p" == "$$" ]] || return 0
  _l=$(_er_lock_field "$_ER_LOCK" lstart)
  [[ -z "$_l" || "$_l" == "$_ER_LSTART" ]] || return 0
  rm -f "$_ER_LOCK" 2>/dev/null || true
}
declare -a _pids
_wt_before=""
# Terminate a whole subtree, deepest first: a bash script waiting on a
# foreground child defers SIGTERM until that child exits, so the wrapper alone
# would let a 30 s stub keep writing into the tree after the abort.
_kill_tree() {
  local _p="$1" _c
  for _c in $(pgrep -P "$_p" 2>/dev/null); do _kill_tree "$_c"; done
  kill -TERM "$_p" 2>/dev/null || true
}
_kill_tree_hard() {
  local _p="$1" _c
  for _c in $(pgrep -P "$_p" 2>/dev/null); do _kill_tree_hard "$_c"; done
  kill -KILL "$_p" 2>/dev/null || true
}
# A shard killed between `worktree add` and its own cleanup leaves a registered
# worktree under .agent-state/wt-shard.* and, if it died inside the 10 s
# snapshot-lock window, a held wt-snapshot.lock directory — the next round's
# snapshot shards would then wait 10 s each and exit 2. Reap children first.
_sweep_worktrees() {
  local _d
  for _d in "$ROOT"/.agent-state/wt-shard.*; do
    [[ -d "$_d" ]] || continue
    case $'\n'"$_wt_before"$'\n' in *$'\n'"$_d"$'\n'*) continue ;; esac
    git -C "$ROOT" worktree remove --force "$_d" >/dev/null 2>&1 || rm -rf "$_d"
  done
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  [[ -d "$ROOT/.agent-state/wt-snapshot.lock" ]] \
    && rmdir "$ROOT/.agent-state/wt-snapshot.lock" 2>/dev/null
}
# TERM every shard subtree, then wait, escalate to KILL, and reap. A fixture (or
# a wedged suite) can ignore TERM; plain `wait` would block and keep letting it
# write into the tree after the freeze window was supposed to close.
_er_stop_shards() {
  local _p _i _alive _n=0
  for _p in ${_pids[@]+"${_pids[@]}"}; do
    _kill_tree "$_p"
    _n=$(( _n + 1 ))
  done
  (( _n )) || return 0
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    _alive=0
    for _p in ${_pids[@]+"${_pids[@]}"}; do kill -0 "$_p" 2>/dev/null && _alive=1; done
    (( _alive )) || break
    sleep 0.2
  done
  for _p in ${_pids[@]+"${_pids[@]}"}; do _kill_tree_hard "$_p"; done
  for _p in ${_pids[@]+"${_pids[@]}"}; do wait "$_p" 2>/dev/null || true; done
}
# A trap that only releases and returns would leave the shards running and the
# round writing a clean-looking meta.tsv after SIGINT/SIGTERM: abort the whole
# round instead (no evidence), then let the EXIT trap clean up.
_er_abort() { # <exit code>
  local _rc="$1"
  _er_stop_shards
  _sweep_worktrees
  echo "evidence-round: interrupted — no evidence was produced; lock released (rc $_rc)" >&2
  # Owner-only release: if this round was wrongly taken over, the lock now
  # belongs to the successor and must not be deleted by the victim.
  _er_lock_release
  exit "$_rc"
}
_er_lock_take || exit 2
trap '_er_lock_release' EXIT
trap '_er_abort 130' INT
trap '_er_abort 143' TERM
trap '_er_abort 129' HUP

# The start fingerprint is sampled only now: the preflight and the live-shard
# resolution above are outside the frozen window, and counting an edit made
# between them and the lock as mid-round drift would void an honest round.
_head=$(git rev-parse HEAD 2>/dev/null || echo none)
_tree=$(_tree_sha)
# Fail closed: with no start fingerprint the end-of-round comparison below would
# be blind and every round would look clean — refuse instead of certifying a
# tree that was never measured.
[[ -n "$_tree" ]] || {
  echo "evidence-round: cannot fingerprint the tree (scripts/lib-suite-tree-fingerprint.sh missing or unreadable) — a round whose drift check cannot run would silently certify mid-round edits; refusing" >&2
  exit 2; }
_er_lock_set tree_sha "$_tree"
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
_start_s=$(date +%s)

# Round dir only after the lock: a refused round must not consume the next free
# round number with an artifact-free directory.
mkdir -p "$STATE_DIR/$CHG" 2>/dev/null || { echo "evidence-round: cannot create $STATE_DIR/$CHG" >&2; exit 2; }
mkdir "$RDIR" 2>/dev/null || {
  echo "evidence-round: round directory already exists: $RDIR (rounds are append-only; omit --round to take the next free number)" >&2
  exit 2; }
_code_face_sha=$(_code_face)
# Snapshot the pre-existing suite worktrees so the fail-fast sweep below never
# touches a worktree owned by another (concurrent) round.
_wt_before=$(ls -d "$ROOT"/.agent-state/wt-shard.* 2>/dev/null || true)
for _i in $(seq 1 "$SHARDS"); do
  if [[ "$_i" -eq "$LIVE_SHARD" ]]; then _mode=live; _args=(--shard "$_i/$SHARDS")
  else _mode=worktree; _args=(--shard "$_i/$SHARDS" --worktree); fi
  printf '%s\n' "$_mode" > "$RDIR/shard-$_i.mode"
  # The .rc lands atomically: the fail-fast watcher treats "file exists, content
  # unreadable" as a red shard, so a torn write would kill its green siblings.
  ( AGENT_GUARD_COST_LEDGER="$_shared_ledger" bash "$SUITE" "${_args[@]}" >"$RDIR/shard-$_i.log" 2>&1
    _c=$?
    printf '%s\n' "$_c" > "$RDIR/shard-$_i.rc.tmp" && mv "$RDIR/shard-$_i.rc.tmp" "$RDIR/shard-$_i.rc" ) &
  _pids[_i]=$!
  echo "evidence-round: started shard $_i/$SHARDS ($_mode)"
done

# v3.97.0 (CHG-134, REQ-1341): --fail-fast watches the non-live shards while
# the round runs. A non-zero rc there already answers the round; the other
# shards' remaining minutes cannot change that answer. (A red LIVE shard is
# not a trigger: the live shard is the only comparable full-suite evidence.)
_killed=""
if [[ "$FAIL_FAST" -eq 1 ]]; then
  while :; do
    _trigger=0
    for _i in $(seq 1 "$SHARDS"); do
      [[ "$_i" -eq "$LIVE_SHARD" ]] && continue
      if [[ -f "$RDIR/shard-$_i.rc" ]]; then
        _r=$(cat "$RDIR/shard-$_i.rc" 2>/dev/null)
        [[ "$_r" == "0" ]] || { _trigger=1; break; }
      fi
    done
    (( _trigger )) && break
    _done=0
    for _i in $(seq 1 "$SHARDS"); do
      [[ -f "$RDIR/shard-$_i.rc" ]] && _done=$(( _done + 1 ))
    done
    (( _done < SHARDS )) || break
    sleep 0.2
  done
  if (( _trigger )); then
    for _i in $(seq 1 "$SHARDS"); do
      [[ -f "$RDIR/shard-$_i.rc" ]] && continue
      _killed+=" $_i"
    done
    _er_stop_shards
    for _i in $_killed; do
      [[ -f "$RDIR/shard-$_i.rc" ]] || printf '143\n' > "$RDIR/shard-$_i.rc"
    done
    # A shard killed between `worktree add` and its own cleanup leaves a
    # registered worktree under .agent-state/wt-shard.* and, if it died inside
    # the 10 s snapshot-lock window, a held wt-snapshot.lock directory — the
    # next round's snapshot shards would then wait 10 s each and exit 2. Every
    # child is reaped above, so no shard can still own either one.
    _sweep_worktrees
  else
    wait
  fi
else
  wait
fi

_fail=0
# v3.97.1 (CHG-135, REQ-1350): re-read the fingerprint now that every shard is
# done. A mismatch means the tracked tree moved while the round ran, so the
# result certifies neither the old tree nor the new one. Say it here, with the
# round, instead of leaving a meta.tsv that looks clean and a --carry-check that
# refuses weeks later with no explanation. (A change made and reverted between
# the two reads is not caught; the check attests the end state.)
_tree_end=$(_tree_sha)
_drift=0
if [[ -z "$_tree_end" || "$_tree_end" != "$_tree" ]]; then _drift=1; fi
for _i in $(seq 1 "$SHARDS"); do
  _rc=$(cat "$RDIR/shard-$_i.rc" 2>/dev/null || echo 2)
  [[ "$_rc" == "0" ]] || { _fail=1; echo "evidence-round: shard $_i/$SHARDS rc=$_rc (log kept: $RDIR/shard-$_i.log)" >&2; }
done

_sum_total="-"; _sum_failed="-"
if [[ -n "$_killed" ]]; then
  printf 'fail-fast: sum not computed (%s shard(s) terminated: %s)\n' \
    "$(printf '%s\n' $_killed | wc -l | tr -d ' ')" "$(printf '%s' "${_killed# }")" > "$RDIR/sum.txt"
  echo "evidence-round: fail-fast stopped the round; sum skipped (terminated:$(printf '%s' "$_killed"))"
elif [[ "$NO_SUM" -eq 0 ]]; then
  bash "$ROOT/scripts/shard-sum.sh" --logs "$RDIR" >"$RDIR/sum.txt" 2>&1; _sum_rc=$?
  cat "$RDIR/sum.txt"
  _sum_total=$(sed -n 's/^total: \([0-9][0-9]*\) passed,.*/\1/p' "$RDIR/sum.txt" | tail -1)
  _sum_failed=$(sed -n 's/^total: [0-9][0-9]* passed, \([0-9][0-9]*\) failed$/\1/p' "$RDIR/sum.txt" | tail -1)
  _sum_total=${_sum_total:--}; _sum_failed=${_sum_failed:--}
  [[ "$_sum_rc" -eq 0 ]] || _fail=1
fi

_wall_s=$(( $(date +%s) - _start_s ))
[[ "$_drift" -eq 1 ]] && _fail=1
_rc_all=0; [[ "$_fail" -eq 0 ]] || _rc_all=1
[[ "$_drift" -eq 1 ]] && _rc_all=2
if [[ "$_drift" -eq 1 ]]; then
  echo "evidence-round: INVALID — the tree changed mid-round (start ${_tree:-none}, end ${_tree_end:-none}); this round certifies neither tree — fix the pending edits and run the round again" >&2
  [[ -f "$RDIR/sum.txt" ]] || : > "$RDIR/sum.txt"
  printf 'INVALID: tree changed mid-round (start %s, end %s)\n' \
    "${_tree:-none}" "${_tree_end:-none}" >> "$RDIR/sum.txt"
fi
{
  printf 'key\tvalue\n'
  printf 'chg\t%s\n' "$CHG"
  printf 'round\t%s\n' "$ROUND"
  printf 'head\t%s\n' "$_head"
  printf 'tree_sha\t%s\n' "$_tree"
  printf 'tree_drift\t%s\n' "$_drift"
  printf 'tree_sha_end\t%s\n' "${_tree_end:-}"
  printf 'shards\t%s\n' "$SHARDS"
  printf 'live_shard\t%s\n' "$LIVE_SHARD"
  printf 'started_at\t%s\n' "$_ts"
  printf 'wall_s\t%s\n' "$_wall_s"
  printf 'total_passed\t%s\n' "$_sum_total"
  printf 'total_failed\t%s\n' "$_sum_failed"
  printf 'rc\t%s\n' "$_rc_all"
  # The suite path can be overridden (fixtures drive a stub); record it so a stub
  # round can never be mistaken for a real one later.
  printf 'suite\t%s\n' "$SUITE"
  printf 'code_face_sha\t%s\n' "$_code_face_sha"
  printf 'carried_from\t-\n'
  printf 'fail-fast\t%s\n' "$FAIL_FAST"
  printf 'killed\t%s\n' "$(printf '%s' "${_killed# }" | sed 's/^$/-/')"
  for (( _m = 1; _m <= SHARDS; _m++ )); do
    _mrc=$(cat "$RDIR/shard-$_m.rc" 2>/dev/null)
    printf 'shard_%s_rc\t%s\n' "$_m" "${_mrc:--}"
  done
} > "$RDIR/meta.tsv"

_append_ledger "$_ts" "$CHG" "$ROUND" "$_head" "$_tree" "$SHARDS" "$LIVE_SHARD" \
  "$_sum_total" "$_sum_failed" "$_rc_all" "$_wall_s" "$RDIR" "$_code_face_sha" "-" \
  || { echo "evidence-round: cannot append to ledger at $_ledger — the round would have no trail" >&2; exit 2; }

_suffix=""; [[ "$_drift" -eq 1 ]] && _suffix=" · INVALID (tree changed mid-round)"
echo "evidence-round: $CHG round $ROUND kept at $RDIR · total ${_sum_total}/${_sum_failed} · rc=$_rc_all · ${_wall_s}s$_suffix"
exit "$_rc_all"
