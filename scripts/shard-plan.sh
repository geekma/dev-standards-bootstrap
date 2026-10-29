#!/usr/bin/env bash
# shard-plan.sh — deterministic 6-way shard planner for tests/run-tests.sh.
#
#   scripts/shard-plan.sh [--shards 6] [--ledger P] [--root D]
#                         [--check | --write | --json]
#
# Source-only tool (never installed into a target repo): it reads this repo's
# suite and cost ledger. The plan is *static* — the same ledger always yields
# the same partition, so a shard round stays reproducible and reviewable.
# Runtime bin-packing was rejected in CHG-133; this tool only replaces
# hand-tuning of SHARD_PLAN_6.
#
# Model: per-section cost = median of the last <=6 `sec` rows in the cost
# ledger (columns located by header name, never by index — the CHG-133 lesson
# where cost_s/setup_s were confused), quantized to whole seconds with a 2 s
# floor (sub-second medians are noise; the suite appends its own `sec` rows, so
# unquantized costs re-shuffled equal-cost atoms and tripped --check by itself);
# unseen sections cost 2 s. SERIAL_CHAIN
# groups are atoms (their members must stay in one shard). Atoms are packed LPT
# (cost desc, ties by atom name) onto the least-loaded shard (ties to the lower
# index); members within a shard follow SECTIONS order.
#
# Input pinning (v3.97.0): the ledger is both the model's input AND the suite's
# own output, so a plan computed from it goes stale the moment the suite runs —
# a gate that reds itself is not a gate. `--write` therefore also records the
# cost model it used in tests/.shard-plan-costs.tsv, and `--check` recomputes
# from that pinned file: rc1 then means the table and its inputs disagree (a
# hand edit), not that the machine is busy. Drift between the pinned model and
# the live ledger is reported on stderr as a WARN (no rc change) and is fixed
# by an explicit `--write`.
#
#   --check   recompute from the pinned costs (or --ledger when given) and
#             compare with the whole SHARD_PLAN_6 block between the BEGIN/END
#             markers; rc1 on any difference. Without a ledger it prints a skip
#             notice and rc0 — the check is an optimization, never a gate for
#             repos without a ledger.
#   --write   rewrite the marked block in place and re-pin the cost model
#             (N=6 only; the suite file keeps its permission bits).
#   --json    machine-readable plan (predicted loads, max and packing floor).
#
# rc: 0 ok · 1 --check mismatch · 2 usage/environment.
set -uo pipefail

ROOT=""; LEDGER=""; SHARDS=6; MODE=print
while [[ $# -gt 0 ]]; do
  case "$1" in
    --shards) [[ $# -ge 2 ]] || { echo "shard-plan: --shards needs a value" >&2; exit 2; }
      SHARDS="$2"; shift 2 ;;
    --ledger) [[ $# -ge 2 ]] || { echo "shard-plan: --ledger needs a value" >&2; exit 2; }
      LEDGER="$2"; shift 2 ;;
    --root) [[ $# -ge 2 ]] || { echo "shard-plan: --root needs a value" >&2; exit 2; }
      ROOT="$2"; shift 2 ;;
    --check) MODE=check; shift ;;
    --write) MODE=write; shift ;;
    --json) MODE=json; shift ;;
    -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
    *) echo "shard-plan: unknown option '$1' (supported: --shards --ledger --root --check --write --json)" >&2; exit 2 ;;
  esac
done
[[ "$SHARDS" =~ ^[1-9][0-9]*$ ]] || { echo "shard-plan: --shards must be a positive integer" >&2; exit 2; }
[[ "$MODE" == "json" && "$SHARDS" -ne 6 ]] \
  && { echo "shard-plan: --json is N=6 only (other N has no cost model to report)" >&2; exit 2; }
if [[ -z "$ROOT" ]]; then ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "shard-plan: not a git repository (use --root)" >&2; exit 2; }; fi
SUITE="$ROOT/tests/run-tests.sh"
[[ -f "$SUITE" ]] || { echo "shard-plan: suite not found at $SUITE" >&2; exit 2; }
PIN="$ROOT/tests/.shard-plan-costs.tsv"
_LEDGER_GIVEN=0; [[ -n "$LEDGER" ]] && _LEDGER_GIVEN=1
[[ -n "$LEDGER" ]] || LEDGER="$ROOT/.agent-state/cost-ledger.tsv"

SECTIONS_STR=$(sed -n 's/^SECTIONS=(\(.*\))$/\1/p' "$SUITE" | head -1)
[[ -n "$SECTIONS_STR" ]] || { echo "shard-plan: cannot read SECTIONS from $SUITE" >&2; exit 2; }
read -r -a SECTIONS <<< "$SECTIONS_STR"

if [[ "$SHARDS" -ne 6 ]]; then
  [[ "$MODE" == "check" || "$MODE" == "write" ]] \
    && { echo "shard-plan: --check/--write are N=6 only (the suite falls back to contiguous slices for other N)" >&2; exit 2; }
  total=${#SECTIONS[@]}
  for (( i = 1; i <= SHARDS; i++ )); do
    start=$(( (i - 1) * total / SHARDS )); end=$(( i * total / SHARDS ))
    printf 'shard %s: %s\n' "$i" "${SECTIONS[*]:start:end-start}"
  done
  echo "note: N!=6 uses the suite's contiguous fallback; no cost model applies" >&2
  exit 0
fi

# The two chain atoms mirror the SERIAL_CHAIN contract pinned by T87. Every
# SERIAL_CHAIN member must be covered or this tool refuses: a new chain section
# must not silently become a free-floating atom.
SERIAL_STR=$(sed -n 's/^SERIAL_CHAIN=(\(.*\))$/\1/p' "$SUITE" | head -1)
read -r -a SERIAL <<< "$SERIAL_STR"
ATOMS=("T50 T51" "T5 T22a T16")
ATOMS_STR="T50 T51|T5 T22a T16"

in_sections() { case " $SECTIONS_STR " in *" $1 "*) return 0 ;; esac; return 1; }
for _a in "${ATOMS[@]}"; do
  for _m in $_a; do
    in_sections "$_m" || { echo "shard-plan: atom member '$_m' is not in SECTIONS" >&2; exit 2; }
  done
done
for _m in "${SERIAL[@]}"; do
  _covered=0
  for _a in "${ATOMS[@]}"; do case " $_a " in *" $_m "*) _covered=1 ;; esac; done
  [[ "$_covered" -eq 1 ]] || { echo "shard-plan: SERIAL_CHAIN member '$_m' is not covered by a planner atom (update ATOMS in shard-plan.sh)" >&2; exit 2; }
done

# The model's input: the pinned costs written by --write, or the live ledger.
# --write always rebalances against the live ledger (that is its whole job);
# --check/json/print read the pin so a busy machine cannot red the gate, and
# fall back to the ledger when no pin exists yet.
_SRC=ledger
if [[ "$MODE" != "write" && "$_LEDGER_GIVEN" -eq 0 && -f "$PIN" ]]; then _SRC=pin; fi

if [[ "$_SRC" == "ledger" && ! -f "$LEDGER" ]]; then
  [[ "$MODE" == "write" ]] \
    && { echo "shard-plan: --write needs a cost ledger to model (none at $LEDGER)" >&2; exit 2; }
  echo "shard-plan: skip — no cost ledger at $LEDGER (nothing to model; rc0)" >&2
  exit 0
fi

TMPD=$(mktemp -d 2>/dev/null) || { echo "shard-plan: cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# Median cost per section (tenths of a second) from the last <=6 `sec` rows.
# Columns are located by header name: a future column insert must not silently
# read setup_s instead of cost_s (CHG-133).
_medians_from_ledger() { # <ledger> <out>
  local _cc _kc _ic
  _cost_col=$(head -1 "$1" | tr '\t' '\n' | awk '$0=="cost_s"{print NR}')
  _kind_col=$(head -1 "$1" | tr '\t' '\n' | awk '$0=="kind"{print NR}')
  _id_col=$(head -1 "$1" | tr '\t' '\n' | awk '$0=="id"{print NR}')
  [[ -n "$_cost_col" && -n "$_kind_col" && -n "$_id_col" ]] \
    || { echo "shard-plan: ledger header lacks kind/id/cost_s" >&2; return 2; }
  awk -F'\t' -v kc="$_kind_col" -v ic="$_id_col" -v cc="$_cost_col" '
    $kc == "sec" { id = $ic; if (!(id in cnt)) cnt[id] = 0; cnt[id]++; v[id, cnt[id]] = $cc + 0 }
    END {
      for (id in cnt) {
        c = cnt[id] + 0; m = 0
        start = c - 6; if (start < 1) start = 1
        for (j = start; j <= c; j++) { m++; a[m] = v[id, j] }
        for (p = 2; p <= m; p++) { key = a[p]; q = p - 1; while (q >= 1 && a[q] > key) { a[q+1] = a[q]; q-- } a[q+1] = key }
        if (m % 2 == 1) med = a[(m+1)/2]; else med = (a[m/2] + a[m/2+1]) / 2
        # Quantize to whole seconds with the same 2 s floor as an unseen section.
        # Sub-second medians are run-to-run noise, and letting them decide the
        # packing made the frozen plan flip on ties with no real cost change --
        # the suite appends its own `sec` rows while T87 runs.
        c = int(med + 0.5); if (c < 2) c = 2
        printf "%s\t%d\n", id, c * 10
      }
    }' "$1" > "$2" || { echo "shard-plan: cannot read $1" >&2; return 2; }
}

_medians_from_pin() { # <pin> <out>
  awk -F'\t' 'NR==1 { if ($1!="id" || $2!="cost_s") exit 3; next }
              { if ($2 !~ /^[0-9]+$/) exit 3; printf "%s\t%d\n", $1, $2 * 10 }' "$1" > "$2" \
    || { echo "shard-plan: pinned costs at $1 are malformed (want id<TAB>cost_s)" >&2; return 2; }
  [[ -s "$2" ]] || { echo "shard-plan: pinned costs at $1 are empty" >&2; return 2; }
}

# One awk pass builds atoms, packs them, orders members and reports loads.
# (bash 3.2 has no associative arrays, so all keyed state stays in awk.)
_pack() { # <medians> <planf> <metaf>
awk -F'\t' -v secs="$SECTIONS_STR" -v atoms="$ATOMS_STR" -v n="$SHARDS" \
    -v planf="$2" -v metaf="$3" '
  BEGIN {
    ns = split(secs, S, " "); for (i = 1; i <= ns; i++) ord[S[i]] = i
    na = split(atoms, A, "|"); a = 0
    for (i = 1; i <= na; i++) { a++; atom[a] = A[i] }
    for (i = 1; i <= ns; i++) {
      s = S[i]; chain = 0
      for (j = 1; j <= na; j++) { m = split(A[j], T, " "); for (k = 1; k <= m; k++) if (T[k] == s) chain = 1 }
      if (!chain) { a++; atom[a] = s }
    }
  }
  { med[$1] = $2 }
  END {
    heaviest = 0
    for (i = 1; i <= a; i++) {
      m = split(atom[i], T, " "); c = 0
      for (k = 1; k <= m; k++) c += (T[k] in med ? med[T[k]] : 20)
      ac[i] = c
      if (c > heaviest) heaviest = c
    }
    for (i = 1; i <= a; i++) idx[i] = i
    for (i = 1; i < a; i++) {
      best = i
      for (j = i + 1; j <= a; j++)
        if (ac[idx[j]] > ac[idx[best]] || (ac[idx[j]] == ac[idx[best]] && atom[idx[j]] < atom[idx[best]])) best = j
      t = idx[i]; idx[i] = idx[best]; idx[best] = t
    }
    for (i = 1; i <= n; i++) { load[i] = 0; mem[i] = "" }
    for (i = 1; i <= a; i++) {
      ai = idx[i]; best = 1
      for (j = 2; j <= n; j++) if (load[j] < load[best]) best = j
      load[best] += ac[ai]; mem[best] = mem[best] " " atom[ai]
    }
    maxl = 0; tot = 0
    for (i = 1; i <= n; i++) {
      m = split(mem[i], MM, " ")
      for (p = 2; p <= m; p++) { key = MM[p]; q = p - 1; while (q >= 1 && ord[MM[q]] > ord[key]) { MM[q+1] = MM[q]; q-- } MM[q+1] = key }
      line = "shard " i ":"
      for (p = 1; p <= m; p++) line = line " " MM[p]
      print line > planf
      if (load[i] > maxl) maxl = load[i]
      tot += load[i]
    }
    floor = int((tot + n - 1) / n)
    if (heaviest > floor) floor = heaviest
    printf "max %d.%d floor %d.%d\n", int(maxl/10), maxl%10, int(floor/10), floor%10 > metaf
  }' "$1" || { echo "shard-plan: cannot compute the plan" >&2; return 2; }
}

if [[ "$_SRC" == "pin" ]]; then
  _medians_from_pin "$PIN" "$TMPD/medians.tsv" || exit 2
else
  _medians_from_ledger "$LEDGER" "$TMPD/medians.tsv" || exit 2
fi
_pack "$TMPD/medians.tsv" "$TMPD/plan" "$TMPD/meta" || exit 2

read -r _max_s _maxv _floor_s _floorv < "$TMPD/meta"
[[ -n "${_maxv:-}" && -n "${_floorv:-}" ]] || { echo "shard-plan: empty plan (no sec rows to model)" >&2; exit 2; }
PLAN_LINES=$(cat "$TMPD/plan")
MAXV="$_maxv"; FLOORV="$_floorv"

# Cost drift is an observation, not a verdict: the pinned model is what the
# table must match, but a plan that no longer reflects the machine is worth a
# named WARN so the next rebalance is a decision rather than an accident.
if [[ "$_SRC" == "pin" && -f "$LEDGER" ]]; then
  if _medians_from_ledger "$LEDGER" "$TMPD/live-med.tsv" 2>/dev/null \
     && _pack "$TMPD/live-med.tsv" "$TMPD/live-plan" "$TMPD/live-meta" 2>/dev/null; then
    if ! diff -q "$TMPD/plan" "$TMPD/live-plan" >/dev/null 2>&1; then
      echo "shard-plan: WARN cost drift — the ledger now plans differently from the pinned model in ${PIN#"$ROOT"/}; table unchanged, run --write to rebalance" >&2
    fi
  fi
fi

case "$MODE" in
  json)
    printf '{"shards":%s,"sections":%s,"max":%s,"floor":%s,"plan":[' "$SHARDS" "${#SECTIONS[@]}" "$MAXV" "$FLOORV"
    _first=1
    while IFS= read -r _line; do
      [[ -n "$_line" ]] || continue
      (( _first )) || printf ','
      _first=0
      _i="${_line#shard }"; _i="${_i%%:*}"
      _m="${_line#*: }"
      printf '{"shard":%s,"members":"%s"}' "$_i" "$_m"
    done <<< "$PLAN_LINES"
    printf ']}\n'
    ;;
  check)
    _block=$(sed -n '/^  # SHARD_PLAN_6_BEGIN$/,/^  # SHARD_PLAN_6_END$/p' "$SUITE" \
      | sed '1d;$d' | sed -n 's/^  "\(.*\)"$/\1/p')
    [[ -n "$_block" ]] \
      || { echo "shard-plan: no SHARD_PLAN_6_BEGIN/END block in $SUITE (add the markers first)" >&2; exit 2; }
    # Compare the whole block, not the first N lines: a stray extra group inside
    # the markers is a plan change too (the suite would shard one section twice).
    _nblock=$(printf '%s\n' "$_block" | grep -c .)
    _rc=0
    if [[ "$_nblock" -ne "$SHARDS" ]]; then
      printf 'shard-plan: the block has %s group(s), the plan has %s\n' "$_nblock" "$SHARDS" >&2
      _rc=1
    fi
    while IFS= read -r _line; do
      [[ -n "$_line" ]] || continue
      _i="${_line#shard }"; _i="${_i%%:*}"
      _want="${_line#*: }"
      _cur=$(printf '%s\n' "$_block" | sed -n "${_i}p")
      if [[ "$_cur" != "$_want" ]]; then
        printf 'shard-plan: shard %s differs\n  table:   %s\n  planned: %s\n' "$_i" "$_cur" "$_want" >&2
        _rc=1
      fi
    done <<< "$PLAN_LINES"
    [[ "$_rc" -eq 0 ]] && echo "shard-plan: SHARD_PLAN_6 matches the pinned cost model (max ${MAXV}s vs floor ${FLOORV}s)"
    exit "$_rc"
    ;;
  write)
    grep -q '^  # SHARD_PLAN_6_BEGIN$' "$SUITE" && grep -q '^  # SHARD_PLAN_6_END$' "$SUITE" \
      || { echo "shard-plan: --write needs the SHARD_PLAN_6_BEGIN/END markers inside the array" >&2; exit 2; }
    _tmp=$(mktemp "${TMPDIR:-/tmp}/shard-plan.XXXXXX") || exit 2
    awk -v planf="$TMPD/plan" '
      BEGIN { n = 0; while ((getline line < planf) > 0) plan[++n] = line }
      /^  # SHARD_PLAN_6_BEGIN$/ { print; for (i = 1; i <= n; i++) if (plan[i] != "") printf "  \"%s\"\n", substr(plan[i], index(plan[i], ": ") + 2); skip = 1; next }
      /^  # SHARD_PLAN_6_END$/   { skip = 0 }
      skip != 1 { print }
    ' "$SUITE" > "$_tmp" || { rm -f "$_tmp"; exit 2; }
    # mktemp creates 0600; a bare mv would strip the suite's permission bits
    # (and its +x) for good.
    _perm=$(stat -f '%Lp' "$SUITE" 2>/dev/null || stat -c '%a' "$SUITE" 2>/dev/null)
    [[ -n "$_perm" ]] && chmod "$_perm" "$_tmp"
    mv "$_tmp" "$SUITE" || exit 2
    # Pin the model the table was built from, in SECTIONS order, including the
    # 2 s default for sections the ledger has never seen.
    _pin_tmp=$(mktemp "${TMPDIR:-/tmp}/shard-plan-costs.XXXXXX") || exit 2
    awk -F'\t' -v secs="$SECTIONS_STR" '
      BEGIN { n = split(secs, S, " "); print "id\tcost_s" }
      { c[$1] = $2 }
      END { for (i = 1; i <= n; i++) printf "%s\t%d\n", S[i], (S[i] in c ? c[S[i]] / 10 : 2) }
    ' "$TMPD/medians.tsv" > "$_pin_tmp" || { rm -f "$_pin_tmp"; exit 2; }
    chmod 644 "$_pin_tmp" 2>/dev/null
    mv "$_pin_tmp" "$PIN" || { rm -f "$_pin_tmp"; exit 2; }
    echo "shard-plan: rewrote SHARD_PLAN_6 (max ${MAXV}s vs floor ${FLOORV}s) and pinned ${#SECTIONS[@]} section costs in ${PIN#"$ROOT"/}"
    ;;
  *)
    printf '%s\n' "$PLAN_LINES"
    echo "max ${MAXV}s · floor ${FLOORV}s · model ${_SRC} ($([[ "$_SRC" == "pin" ]] && echo "$PIN" || echo "$LEDGER"))"
    ;;
esac
