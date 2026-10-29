#!/usr/bin/env bash
# pre-round-check.sh — static, read-only preflight for an evidence round.
#
#   scripts/pre-round-check.sh [--root D] [--strict] [--json]
#
# Source-only tool (never installed): it inspects THIS repo's install manifest,
# gate whitelist, T21 fixture, shard plan and cost ledger. It exists because the
# two most expensive evidence rounds in CHG-133 (203 s + 317 s = 520 s) were
# both "new payload registered in some places but not all" — a class a
# one-second static check can catch before the round starts.
#
# Checks (each prints ok/WARN/FAIL <id> <detail>):
#   R1 manifest sources exist   every install_file src in scripts/bootstrap.sh
#                               resolves on disk (dynamic loop sources check
#                               their static directory prefix)
#   R2 T21 fixture closure      every manifest src under scripts/ or tests/ is
#                               copied into the T21 FAKE_SRC fixture (install
#                               tests run from that copy; a missing copy = red
#                               at runtime)
#   R3 gate whitelist           every installed scripts/ or tests/ entry with a
#                               code extension is in is_code_path(), else the
#                               first commit of a fresh install hits E125
#   R4 template coverage        every resources/templates/*.sh is installed
#                               (none is exempt: an uninstalled template is dead
#                               payload)
#   R5 shard plan               SHARD_PLAN_6 covers SECTIONS exactly once and
#                               keeps the SERIAL_CHAIN atoms in one shard
#                               (asked from the suite itself, not re-parsed)
#   R6 plan drift + balance     SHARD_PLAN_6 must equal its pinned cost model
#                               (FAIL otherwise) and the live model's max shard
#                               must stay <= 1.15 x max(total/6, heaviest atom)
#                               (WARN; a drifted or over-heavy plan is named)
#
# rc: 0 no FAIL (and no WARN under --strict) · 1 FAIL (or WARN with --strict)
#     · 2 usage/environment. --json prints the same result as one object.
set -uo pipefail

ROOT=""; STRICT=0; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || { echo "pre-round-check: --root needs a value" >&2; exit 2; }
      ROOT="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "pre-round-check: unknown option '$1' (supported: --root --strict --json)" >&2; exit 2 ;;
  esac
done
if [[ -z "$ROOT" ]]; then ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "pre-round-check: not a git repository (use --root)" >&2; exit 2; }; fi
[[ -d "$ROOT" ]] || { echo "pre-round-check: root '$ROOT' is not a directory" >&2; exit 2; }
BOOT="$ROOT/scripts/bootstrap.sh"
SUITE="$ROOT/tests/run-tests.sh"
GATE="$ROOT/resources/templates/agent-gate.sh"
[[ -f "$BOOT" && -f "$SUITE" && -f "$GATE" ]] \
  || { echo "pre-round-check: bootstrap.sh / run-tests.sh / agent-gate.sh missing under $ROOT (source layout only)" >&2; exit 2; }

FAILS=0; WARNS=0
ROWS=""
record() { # <id> <ok|warn|fail> <detail>
  case "$2" in fail) FAILS=$(( FAILS + 1 )) ;; warn) WARNS=$(( WARNS + 1 )) ;; esac
  ROWS+="$1"$'\t'"$2"$'\t'"$3"$'\n'
  if [[ "$JSON" -eq 0 ]]; then printf '%s %s %s\n' "$2" "$1" "$3"; fi
}

MANIFEST=$(sed -n 's/^[[:space:]]*install_file[[:space:]]\{1,\}//p' "$BOOT" | awk '{gsub(/"/,""); print $2 "\t" $3}')
[[ -n "$MANIFEST" ]] || { echo "pre-round-check: no install_file lines in $BOOT" >&2; exit 2; }

# R1 — manifest sources exist. Loop sources (`for m in a b c; do install_file …
# "resources/methodologies/$m"; done`) are expanded against the loop's own member
# list: checking only that the directory is non-empty would pass while the
# installer aborts on the missing member (a partial install).
_r1_bad=""
while IFS=$'\t' read -r _dest _src; do
  [[ -n "$_src" ]] || continue
  case "$_src" in
    *'$'*) continue ;;   # loop sources: expanded below
    *) [[ -f "$ROOT/$_src" ]] || _r1_bad+="$_src " ;;
  esac
done <<< "$MANIFEST"
while IFS= read -r _lp; do
  [[ -n "$_lp" ]] && [[ -n "$_lp" && ! -f "$ROOT/$_lp" ]] && _r1_bad+="$_lp "
done <<< "$(awk '
  /^[[:space:]]*for [A-Za-z_][A-Za-z0-9_]* in / {
    v = $2
    rest = $0
    sub(/^[[:space:]]*for [A-Za-z_][A-Za-z0-9_]* in[[:space:]]+/, "", rest)
    sub(/;[[:space:]]*do[[:space:]]*$/, "", rest)
    nm = split(rest, M, /[[:space:]]+/)
    for (i = 1; i <= nm; i++) if (M[i] != "") mem[v, i] = M[i]
    cnt[v] = nm; inloop[v] = 1; next
  }
  /^[[:space:]]*done[[:space:]]*$/ { for (k in inloop) inloop[k] = 0; next }
  /^[[:space:]]*install_file[[:space:]]/ {
    src = $0
    sub(/^[[:space:]]*install_file[[:space:]]+/, "", src)
    gsub(/"/, "", src)
    n = split(src, F, /[[:space:]]+/)
    path = F[3]
    for (k in inloop) {
      if (inloop[k] && index(path, "$" k) > 0) {
        for (i = 1; i <= cnt[k]; i++) {
          p = path; sub("\\$" k, mem[k, i], p); print p
        }
      }
    }
  }' "$BOOT")"
if [[ -n "$_r1_bad" ]]; then record R1 fail "missing manifest sources: $_r1_bad"
else record R1 ok "all install_file sources resolve (loop members expanded)"; fi

# R2 — T21 FAKE_SRC closure for every manifest source the install tests copy
# (scripts/ and tests/: a missing tests/ copy reds the install assertions the
# same way, and a static check costs nothing).
_r2_bad=""
while IFS=$'\t' read -r _dest _src; do
  case "$_src" in scripts/*|tests/*) ;; *) continue ;; esac
  grep -qF "cp \"\$ROOT/$_src\" \"\$FAKE_SRC/$_src\"" "$SUITE" \
    || _r2_bad+="$_src "
done <<< "$MANIFEST"
if [[ -n "$_r2_bad" ]]; then record R2 fail "not copied into the T21 FAKE_SRC fixture: $_r2_bad"
else record R2 ok "every scripts/ and tests/ manifest source is copied by T21"; fi

# R3 — installed scripts/ and tests/ code files appear in is_code_path().
# Non-extension names (agent-gate, new-change, ...) are exempt by construction:
# is_code_path classifies by extension, not by directory.
_r3_bad=""
while IFS=$'\t' read -r _dest _src; do
  case "$_dest" in
    *'$SCRIPTS_DIR/'*) _dir=scripts ;;
    *'$TESTS_DIR/'*) _dir=tests ;;
    *) continue ;;
  esac
  _name="${_dest##*/}"
  case "$_name" in *.sh) ;; *) continue ;; esac
  _re="\${${_dir}_re}/${_name//./\\.}"
  grep -qF "$_re" "$GATE" || _r3_bad+="$_dir/$_name "
done <<< "$MANIFEST"
if [[ -n "$_r3_bad" ]]; then record R3 fail "installed code files missing from is_code_path(): $_r3_bad"
else record R3 ok "every installed code file is whitelisted by the gate"; fi

# R4 — every template shell script is installed. There is no exemption list on
# purpose: an install_file-less template is payload nobody ships.
_r4_bad=""
for _t in "$ROOT"/resources/templates/*.sh; do
  [[ -e "$_t" ]] || continue
  _rel="resources/templates/${_t##*/}"
  case "$MANIFEST" in *"$_rel"*) ;; *) _r4_bad+="$_rel " ;; esac
done
if [[ -n "$_r4_bad" ]]; then record R4 fail "template scripts installed nowhere: $_r4_bad"
else record R4 ok "all template scripts are installed"; fi

# R5 — the plan is a partition and keeps the chain atoms together. The suite
# owns SECTIONS/SERIAL_CHAIN and its own drift guard; ask it via resolve-only.
PLANNER_DECL="$ROOT/scripts/shard-plan.sh"
SECTIONS_STR=$(sed -n 's/^SECTIONS=(\(.*\))$/\1/p' "$SUITE" | head -1)
SERIAL_STR=$(sed -n 's/^SERIAL_CHAIN=(\(.*\))$/\1/p' "$SUITE" | head -1)
[[ -n "$SECTIONS_STR" ]] || { echo "pre-round-check: cannot read SECTIONS from $SUITE" >&2; exit 2; }
_r5_bad=""; declare -a _sh_mem
for _i in 1 2 3 4 5 6; do
  _out=$(AGENT_GUARD_SUITE_SHARD_RESOLVE_ONLY=1 bash "$SUITE" --shard "$_i/6" 2>&1); _rc=$?
  if [[ "$_rc" -ne 0 ]]; then
    _r5_bad+="shard $_i/6 resolve rc=$_rc ($(printf '%s' "$_out" | head -1)); "
    _sh_mem[_i]=""
    continue
  fi
  _line=$(sed -n 's/^shard-resolve-only: //p' <<< "$_out")
  [[ -n "$_line" ]] || _r5_bad+="shard $_i/6 printed no member line; "
  _sh_mem[_i]="$_line"
done
if [[ -z "$_r5_bad" ]]; then
  _want=$(printf '%s\n' $SECTIONS_STR | sort | tr '\n' ' ')
  _got=$(for _i in 1 2 3 4 5 6; do printf '%s\n' ${_sh_mem[_i]}; done | sort | tr '\n' ' ')
  [[ "$_want" == "$_got" ]] || _r5_bad+="plan members differ from SECTIONS (missing or duplicated); "
  # The atoms are the planner's own declaration (scripts/shard-plan.sh ATOMS):
  # copying the list here would let a new chain group go unchecked.
  _atom_line=$(sed -n 's/^ATOMS=(\(.*\))$/\1/p' "$PLANNER_DECL" 2>/dev/null | head -1)
  _atom_line=${_atom_line//\"/}
  declare -a _atoms
  if [[ -n "$_atom_line" ]]; then read -r -a _atoms <<< "$_atom_line"; fi
  for _atom in "${_atoms[@]}"; do
    _hit=0
    for _i in 1 2 3 4 5 6; do
      _all=1
      for _m in $_atom; do case " ${_sh_mem[_i]} " in *" $_m "*) ;; *) _all=0 ;; esac; done
      [[ "$_all" -eq 1 ]] && _hit=1
    done
    [[ "$_hit" -eq 1 ]] || _r5_bad+="atom '$_atom' is split across shards; "
  done
  [[ ${#_atoms[@]} -gt 0 ]] || _r5_bad+="no chain atoms found (scripts/shard-plan.sh ATOMS unreadable); "
fi
if [[ -n "$_r5_bad" ]]; then record R5 fail "$_r5_bad"
else record R5 ok "SHARD_PLAN_6 partitions SECTIONS and keeps both chain atoms whole"; fi

# R6 — plan drift + predicted imbalance (the drift face is a gate, the load face
# is an observation). shard-plan.sh is the one implementation of both; without
# it (or without a ledger) skip.
PLANNER="$ROOT/scripts/shard-plan.sh"
LEDGER="$ROOT/.agent-state/cost-ledger.tsv"
if [[ ! -f "$PLANNER" ]]; then record R6 ok "skip — no scripts/shard-plan.sh (cost model unavailable)"
elif [[ ! -f "$LEDGER" ]]; then record R6 ok "skip — no cost ledger at .agent-state/cost-ledger.tsv"
else
  # The table must equal its pinned model; a mismatch means a hand edit (or a
  # table older than the pin) and the round would run a plan nobody can recompute.
  _chk_out=$(bash "$PLANNER" --root "$ROOT" --check 2>&1); _chk_rc=$?
  if [[ "$_chk_rc" -eq 1 ]]; then
    record R6 fail "SHARD_PLAN_6 does not match its cost model ($(grep -m1 '^shard-plan:' <<< "$_chk_out")) — run scripts/shard-plan.sh --write"
  elif [[ "$_chk_rc" -ne 0 ]]; then
    record R6 fail "shard-plan --check rc=$_chk_rc ($(grep -m1 'shard-plan:' <<< "$_chk_out")) — the plan cannot be verified, so the round must not start"
  else
    # --ledger forces the live model: the planner otherwise reads its pinned
    # costs, which would make this warning constant instead of about today.
    _json=$(bash "$PLANNER" --root "$ROOT" --ledger "$LEDGER" --json 2>/dev/null); _prc=$?
    _max=$(sed -n 's/.*"max":\([0-9.]*\).*/\1/p' <<< "$_json")
    _floor=$(sed -n 's/.*"floor":\([0-9.]*\).*/\1/p' <<< "$_json")
    if [[ "$_prc" -ne 0 || -z "$_max" || -z "$_floor" ]]; then
      record R6 warn "cost model did not produce a plan (shard-plan rc=$_prc)"
    elif grep -q 'WARN cost drift' <<< "$_chk_out"; then
      record R6 warn "cost drift — the ledger now plans differently from the pinned model (observe; --write rebalances)"
    elif awk -v m="$_max" -v f="$_floor" 'BEGIN { exit !(m > f * 1.15) }'; then
      record R6 warn "predicted max shard ${_max}s exceeds 1.15x the packing floor ${_floor}s (observe; not a blocker)"
    else
      record R6 ok "predicted max shard ${_max}s within 1.15x the floor ${_floor}s"
    fi
  fi
fi

_status=ok
[[ "$FAILS" -gt 0 ]] && _status=fail
if [[ "$_status" == "ok" && "$STRICT" -eq 1 && "$WARNS" -gt 0 ]]; then _status=fail; fi

if [[ "$JSON" -eq 1 ]]; then
  _first=1
  printf '{"status":"%s","fails":%s,"warns":%s,"checks":[' "$_status" "$FAILS" "$WARNS"
  while IFS=$'\t' read -r _id _st _detail; do
    [[ -n "$_id" ]] || continue
    _d="${_detail//\\/\\\\}"; _d="${_d//\"/\\\"}"
    (( _first )) || printf ','
    _first=0
    printf '{"id":"%s","status":"%s","detail":"%s"}' "$_id" "$_st" "$_d"
  done <<< "$ROWS"
  printf ']}\n'
fi

[[ "$_status" == "fail" ]] && exit 1
exit 0
