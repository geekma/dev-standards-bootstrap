#!/usr/bin/env bash
# evidence-round.sh — run one suite evidence round into an append-only directory.
#
#   scripts/evidence-round.sh --chg <CHG-id> [--round N] [--shards 6]
#                             [--live-shard S] [--no-sum] [--dry-run]
#                             [--state-dir DIR]
#
#   --chg        change id (also the directory name); required
#   --round N    explicit round number; default = next free number (never reuses)
#   --shards N   shard count, default 6 (min 2)
#   --live-shard S
#                the one shard that runs WITHOUT --worktree (default: the shard
#                that contains T87 — inside a snapshot T87 early-exits, so the
#                live shard is what makes the total comparable to the baseline)
#   --no-sum     skip the shard-sum call at the end
#   --dry-run    print the planned commands and exit; creates nothing
#   --state-dir  root for round dirs and ledger (default .agent-state/evidence)
#
# Layout: <state-dir>/<CHG>/round-<N>/{shard-<i>.log,.rc,.mode,meta.tsv,sum.txt}
#         <state-dir>/ledger.tsv  (append-only; one row per round)
#
# An existing round directory is refused with rc2: evidence rounds are
# append-only so a failed shard's log is never overwritten by the next attempt
# (CHG-133 REQ-1330). rc 0 = every shard green and sum green · 1 = red (all
# artifacts kept) · 2 = usage/environment.
#
# AGENT_GUARD_EVIDENCE_SUITE overrides the suite path (T87 drives the tool with
# a stub; the real runner would cost a full sharded round).
set -uo pipefail

STATE_DIR=".agent-state/evidence"
CHG=""; ROUND=""; SHARDS=6; LIVE_SHARD=""; NO_SUM=0; DRY=0
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
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "evidence-round: unknown option '$1' (supported: --chg --round --shards --live-shard --no-sum --dry-run --state-dir)" >&2; exit 2 ;;
  esac
done
[[ -n "$CHG" ]] || { echo "evidence-round: --chg <CHG-id> is required" >&2; exit 2; }
[[ "$CHG" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "evidence-round: invalid --chg '$CHG'" >&2; exit 2; }
[[ "$SHARDS" =~ ^[1-9][0-9]*$ && "$SHARDS" -ge 2 ]] \
  || { echo "evidence-round: --shards must be an integer >= 2 (one shard is just a full run)" >&2; exit 2; }
if [[ -n "$LIVE_SHARD" ]]; then
  [[ "$LIVE_SHARD" =~ ^[1-9][0-9]*$ && "$LIVE_SHARD" -le "$SHARDS" ]] \
    || { echo "evidence-round: --live-shard must be 1..$SHARDS" >&2; exit 2; }
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "evidence-round: not a git repository (worktree snapshots need one)" >&2; exit 2; }
cd "$ROOT" || exit 2
SUITE="${AGENT_GUARD_EVIDENCE_SUITE:-$ROOT/tests/run-tests.sh}"
[[ -f "$SUITE" ]] || { echo "evidence-round: suite not found at $SUITE" >&2; exit 2; }

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

if [[ "$DRY" -eq 1 ]]; then
  echo "evidence-round: $CHG round $ROUND -> $RDIR (live shard $LIVE_SHARD/$SHARDS)"
  for _i in $(seq 1 "$SHARDS"); do
    if [[ "$_i" -eq "$LIVE_SHARD" ]]; then _mode=live; _wt=""; else _mode=worktree; _wt=" --worktree"; fi
    echo "  shard $_i/$SHARDS $_mode: bash $SUITE --shard $_i/$SHARDS$_wt > $RDIR/shard-$_i.log 2>&1"
  done
  [[ "$NO_SUM" -eq 1 ]] || echo "  sum: bash $ROOT/scripts/shard-sum.sh --logs $RDIR"
  exit 0
fi

mkdir -p "$STATE_DIR/$CHG" 2>/dev/null || { echo "evidence-round: cannot create $STATE_DIR/$CHG" >&2; exit 2; }
mkdir "$RDIR" 2>/dev/null || {
  echo "evidence-round: round directory already exists: $RDIR (rounds are append-only; omit --round to take the next free number)" >&2
  exit 2; }

_head=$(git rev-parse HEAD 2>/dev/null || echo none)
_tree=$(git ls-files -z | xargs -0 cksum 2>/dev/null | cksum | awk '{print $1}')
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
_start_s=$(date +%s)

for _i in $(seq 1 "$SHARDS"); do
  if [[ "$_i" -eq "$LIVE_SHARD" ]]; then _mode=live; _args=(--shard "$_i/$SHARDS")
  else _mode=worktree; _args=(--shard "$_i/$SHARDS" --worktree); fi
  printf '%s\n' "$_mode" > "$RDIR/shard-$_i.mode"
  ( bash "$SUITE" "${_args[@]}" >"$RDIR/shard-$_i.log" 2>&1; echo "$?" > "$RDIR/shard-$_i.rc" ) &
  echo "evidence-round: started shard $_i/$SHARDS ($_mode)"
done
wait

_fail=0
for _i in $(seq 1 "$SHARDS"); do
  _rc=$(cat "$RDIR/shard-$_i.rc" 2>/dev/null || echo 2)
  [[ "$_rc" == "0" ]] || { _fail=1; echo "evidence-round: shard $_i/$SHARDS rc=$_rc (log kept: $RDIR/shard-$_i.log)" >&2; }
done

_sum_total="-"; _sum_failed="-"
if [[ "$NO_SUM" -eq 0 ]]; then
  bash "$ROOT/scripts/shard-sum.sh" --logs "$RDIR" >"$RDIR/sum.txt" 2>&1; _sum_rc=$?
  cat "$RDIR/sum.txt"
  _sum_total=$(sed -n 's/^total: \([0-9][0-9]*\) passed,.*/\1/p' "$RDIR/sum.txt" | tail -1)
  _sum_failed=$(sed -n 's/^total: [0-9][0-9]* passed, \([0-9][0-9]*\) failed$/\1/p' "$RDIR/sum.txt" | tail -1)
  _sum_total=${_sum_total:--}; _sum_failed=${_sum_failed:--}
  [[ "$_sum_rc" -eq 0 ]] || _fail=1
fi

_wall_s=$(( $(date +%s) - _start_s ))
_rc_all=0; [[ "$_fail" -eq 0 ]] || _rc_all=1
{
  printf 'key\tvalue\n'
  printf 'chg\t%s\n' "$CHG"
  printf 'round\t%s\n' "$ROUND"
  printf 'head\t%s\n' "$_head"
  printf 'tree_sha\t%s\n' "$_tree"
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
  for (( _m = 1; _m <= SHARDS; _m++ )); do
    _mrc=$(cat "$RDIR/shard-$_m.rc" 2>/dev/null)
    printf 'shard_%s_rc\t%s\n' "$_m" "${_mrc:--}"
  done
} > "$RDIR/meta.tsv"

_ledger="$STATE_DIR/ledger.tsv"
if [[ ! -f "$_ledger" ]]; then
  printf 'ts\tchg\tround\thead\ttree_sha\tshards\tlive_shard\ttotal\tfailed\trc\twall_s\tdir\n' >> "$_ledger" \
    || { echo "evidence-round: cannot create ledger at $_ledger — the round would have no trail" >&2; exit 2; }
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$_ts" "$CHG" "$ROUND" "$_head" "$_tree" "$SHARDS" "$LIVE_SHARD" \
  "$_sum_total" "$_sum_failed" "$_rc_all" "$_wall_s" "$RDIR" \
  >> "$_ledger" \
  || { echo "evidence-round: cannot append to ledger at $_ledger — the round would have no trail" >&2; exit 2; }

echo "evidence-round: $CHG round $ROUND kept at $RDIR · total ${_sum_total}/${_sum_failed} · rc=$_rc_all · ${_wall_s}s"
exit "$_rc_all"
