#!/usr/bin/env bash
# shard-sum.sh — sum the per-shard `N passed, M failed` summary lines of a
# sharded suite round into one total, and (source-layer only) sync the claim
# face via the existing generator.
#
#   scripts/shard-sum.sh [--logs DIR] [--write] [--root R]
#
#   default        sum every *.log in DIR (default .agent-state, lexicographic),
#                  print one line per shard + `total: X passed, Y failed`
#                  rc 0 = zero failed · rc 1 = any failed · rc 2 = usage/empty
#   --write        GREEN sums only: write the total to tests/.suite-baseline and
#                  run scripts/update-assertion-count.sh --from-baseline (README×2
#                  + audit claim face). update-assertion-count.sh is source-layer
#                  (READMEs live in this repo) — target installs get sum-only and
#                  --write refuses with a named missing file, never a silent skip.
#   --root R       repo root override (fixture isolation in T87)
#
# The ONLY writers of tests/.suite-baseline remain shard-sum.sh --write and
# update-assertion-count.sh — hand edits are what A63 pins against (CHG-132).
# Zero deps: bash + grep + sort.
set -uo pipefail
logs_dir=".agent-state"
do_write=0
root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --logs) [[ $# -ge 2 ]] || { echo "shard-sum: --logs needs a value" >&2; exit 2; }
      logs_dir="$2"; shift 2 ;;
    --write) do_write=1; shift ;;
    --root) [[ $# -ge 2 ]] || { echo "shard-sum: --root needs a value" >&2; exit 2; }
      root="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "shard-sum: unknown option '$1' (supported: --logs --write --root)" >&2; exit 2 ;;
  esac
done
if [[ -n "$root" ]]; then
  cd "$root" || { echo "shard-sum: --root '$root' is not a directory" >&2; exit 2; }
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root="$PWD"
fi
[[ -d "$logs_dir" ]] || { echo "shard-sum: logs dir '$logs_dir' does not exist" >&2; exit 2; }
# Zero logs must fail: a round that produced nothing may not pose as green
# (same zero-success semantics as stamp-provenance --all, T17b).
shopt -s nullglob
logs=("$logs_dir"/*.log)
shopt -u nullglob
[[ ${#logs[@]} -gt 0 ]] || { echo "shard-sum: no *.log under '$logs_dir'" >&2; exit 2; }
total_p=0; total_f=0; any_bad=0
# numeric-aware order: 1.log 2.log … 10.log (leading number, then lexical)
while IFS= read -r f; do
  p=$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "$f" 2>/dev/null | tail -1 | sed -E 's/^([0-9]+) passed.*/\1/')
  fl=$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "$f" 2>/dev/null | tail -1 | sed -E 's/.*, ([0-9]+) failed$/\1/')
  if [[ ! "$p" =~ ^[0-9]+$ || ! "$fl" =~ ^[0-9]+$ ]]; then
    echo "shard-sum: $f carries no 'N passed, M failed' summary line" >&2
    any_bad=1; continue
  fi
  echo "shard $f: $p passed, $fl failed"
  total_p=$(( total_p + p )); total_f=$(( total_f + fl ))
done < <(printf '%s\n' "${logs[@]}" | awk -F/ '{n=$NF; sub(/[^0-9].*$/,"",n); print (n==""?999999:n)"\t"$0}' | sort -n | cut -f2-)
if [[ "$any_bad" -eq 1 ]]; then exit 2; fi
echo "total: $total_p passed, $total_f failed"
[[ "$total_f" -eq 0 ]] || exit 1
if [[ "$do_write" -eq 1 ]]; then
  gen="$root/scripts/update-assertion-count.sh"
  if [[ ! -f "$gen" ]]; then
    echo "shard-sum: --write needs $gen (source-layer only; target installs are sum-only)" >&2
    exit 2
  fi
  baseline="$root/tests/.suite-baseline"
  [[ -d "$root/tests" ]] || { echo "shard-sum: $root/tests does not exist" >&2; exit 2; }
  printf '%s\n' "$total_p" > "$baseline"
  bash "$gen" --from-baseline
  echo "shard-sum: baseline=$total_p synced via update-assertion-count.sh --from-baseline"
fi
exit 0
