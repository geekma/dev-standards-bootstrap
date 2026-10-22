#!/usr/bin/env bash
# pre-review-check.sh — the mechanical half of "ready for review".
#
#   pre-review-check.sh [--change CHG-123|BATCH-YYYYMMDD] [--root DIR]
#                       [--skip-release] [--skip-audit] [--strict]
#
# --change matches a directory under docs/changes by name first, then falls back
# to the change_id recorded in each 00-governance.json (a batch dir carries its
# own name and an inner CHG id; both must resolve).
#
# Checks (read-only): the full artifact set exists and is non-empty; no FILL
# placeholders remain; 00.5 carries the confirmation marker; 05 carries real
# execution evidence; 00-governance owners are filled and independent; 07 carries
# a signature line; every markdown artifact is provenance-stamped; version
# carriers agree (release.sh check, including the gate mirror cmp); README counts
# match tests/.suite-baseline and tests/.audit-baseline; changed shell files carry
# no empty-glob trap (an ls -d pattern ending in a slash makes a missing glob
# match the literal path and silently defeats 2>/dev/null).
#
# --skip-release skips release.sh check; --skip-audit skips the source audit.
# --strict promotes warnings to failures. Output is a check list plus a summary;
# exit 0 clean, 1 findings, 2 usage.
#
# Source-layer only (NOT shipped with the Skill).
# Zero deps: bash 3.2+, git, grep, sed, tr, date, stat.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHANGE=""
SKIP_RELEASE=0
SKIP_AUDIT=0
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "pre-review-check: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --change) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "pre-review-check: --change needs a value" >&2; exit 2; }; CHANGE="$2"; shift 2 ;;
    --skip-release) SKIP_RELEASE=1; shift ;;
    --skip-audit) SKIP_AUDIT=1; shift ;;
    --strict) STRICT=1; shift ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; exit 0 ;;
    *) echo "pre-review-check: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "pre-review-check: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
source "$ROOT/scripts/lib-source-facts.sh"

FAILS=0
WARNS=0
ok()   { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; FAILS=$(( FAILS + 1 )); }
warn() { printf 'WARN %s\n' "$1"; WARNS=$(( WARNS + 1 )); }
note() { printf 'skip %s\n' "$1"; }

# --- locate the change directory ---
[ -n "$CHANGE" ] || CHANGE=$(sf_active_change "$ROOT")
CHANGE_DIR=""
# Resolve a literal batch directory before scanning governance ids: this repo
# addresses a batch by its own name (docs/changes/BATCH-20261022 carries
# change_id CHG-115), and matching only the inner id made that argument silently
# drop every artifact check. Traversal forms are excluded so `..` cannot turn the
# change dir into docs/ itself.
case "$CHANGE" in
  */*|.|..) ;;
  *) [ -z "$CHANGE" ] || [ ! -d "$ROOT/docs/changes/$CHANGE" ] || CHANGE_DIR="$ROOT/docs/changes/$CHANGE" ;;
esac
if [ -z "$CHANGE_DIR" ] && [ -d "$ROOT/docs/changes" ]; then
  while IFS= read -r gov; do
    [ -f "$gov" ] || continue
    if [ -n "$CHANGE" ]; then
      id=$(sf_read_json_str "$gov" change_id)
      [ "$id" = "$CHANGE" ] && { CHANGE_DIR=$(dirname "$gov"); break; }
    else
      CHANGE_DIR=$(dirname "$gov"); CHANGE=$(sf_read_json_str "$gov" change_id); break
    fi
  done < <(ls -t "$ROOT"/docs/changes/*/00-governance.json 2>/dev/null)
fi
if [ -z "$CHANGE_DIR" ]; then
  bad "no change matches '${CHANGE:-<none>}': neither a directory under docs/changes nor a 00-governance.json change_id"
else
  ok "change directory: $CHANGE_DIR"
fi

if [ -n "$CHANGE_DIR" ]; then
  REQUIRED="00-governance.json 00-intent.md 00.5-communication.md 01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 04.5-coding-record.md 05-test-results.md 06-delivery-summary.md 06.5-deployment-config.md 07-review-report.md 09-changelog.md handoff.md"
  missing=""
  for f in $REQUIRED; do
    [ -s "$CHANGE_DIR/$f" ] || missing="$missing $f"
  done
  [ -z "$missing" ] && ok "all 16 artifacts present and non-empty" || bad "missing/empty artifacts:$missing"

  fill=$(grep -rnF '<!-- FILL' "$CHANGE_DIR" 2>/dev/null | wc -l | tr -d ' ')
  fill2=$(grep -rnE 'FILL-(spec|implementation|test|review)' "$CHANGE_DIR" 2>/dev/null | wc -l | tr -d ' ')
  [ "$fill" -eq 0 ] && [ "$fill2" -eq 0 ] && ok "no FILL placeholders remain" \
    || bad "placeholders remain ($fill comment, $fill2 owner fields)"

  if [ -f "$CHANGE_DIR/00.5-communication.md" ]; then
    # E83 canonical marker is a bullet line; L0 "**沟通确认**" declaration is its documented equivalent.
    grep -qE '^[-*[:space:]]*(\*\*)?(确认状态|沟通确认)(\*\*)?(：|:)' "$CHANGE_DIR/00.5-communication.md" \
      && ok "00.5 confirmation marker present" || bad "00.5 missing a 确认状态 line"
  fi

  if [ -f "$CHANGE_DIR/05-test-results.md" ]; then
    if grep -qE '([0-9]+ passed, [0-9]+ failed|[0-9]+ (项|条)?通过|failed(：|:)[[:space:]]*0|冒烟证据)' "$CHANGE_DIR/05-test-results.md"; then
      ok "05 carries execution evidence"
    else
      bad "05 carries no recognizable execution evidence (passed/failed line)"
    fi
  fi

  gov="$CHANGE_DIR/00-governance.json"
  if [ -f "$gov" ]; then
    spec_owner=$(sf_read_json_str "$gov" spec_author)
    impl_owner=$(sf_read_json_str "$gov" implementation_owner)
    test_owner=$(sf_read_json_str "$gov" test_owner)
    review_owner=$(sf_read_json_str "$gov" review_owner)
    [ -n "$spec_owner" ] && [ -n "$impl_owner" ] && [ -n "$test_owner" ] && [ -n "$review_owner" ] \
      && ok "governance owners are filled" || bad "governance owners incomplete"
    [ -n "$review_owner" ] && [ "$review_owner" != "$spec_owner" ] \
      && ok "review owner is independent of the spec author" || bad "review owner equals/misses spec author"
    if [ -f "$CHANGE_DIR/07-review-report.md" ]; then
      grep -qF "$review_owner" "$CHANGE_DIR/07-review-report.md" \
        && ok "07 names the review owner" || bad "07 does not name review_owner '$review_owner'"
      grep -qE '评审结论|复核结论|Review verdict' "$CHANGE_DIR/07-review-report.md" \
        && ok "07 carries a review verdict" || bad "07 carries no review verdict section"
    fi
  fi

  unstamped=""
  for f in "$CHANGE_DIR"/*.md; do
    [ -f "$f" ] || continue
    grep -qF '<!-- provenance' "$f" || unstamped="$unstamped $(basename "$f")"
  done
  [ -z "$unstamped" ] && ok "all markdown artifacts carry provenance" || bad "unstamped artifacts:$unstamped"
fi

# --- version carriers + gate mirror ---
if [ "$SKIP_RELEASE" -eq 1 ]; then
  note "release carrier check (--skip-release)"
elif [ -f "$ROOT/scripts/release.sh" ]; then
  rel_out=$( cd "$ROOT" && bash scripts/release.sh check 2>&1 ); rel_rc=$?
  if [ "$rel_rc" -eq 0 ]; then
    ok "version carriers agree (release.sh check)"
  else
    bad "version carriers drift (release.sh check rc=$rel_rc)"
    printf '%s\n' "$rel_out" | grep '^FAIL' | head -n 10
  fi
else
  warn "release.sh absent — carrier check skipped"
fi
if [ -f "$ROOT/scripts/agent-gate" ] && [ -f "$ROOT/resources/templates/agent-gate.sh" ]; then
  cmp -s "$ROOT/scripts/agent-gate" "$ROOT/resources/templates/agent-gate.sh" \
    && ok "gate mirror is byte-identical" || bad "gate mirror differs from resources/templates/agent-gate.sh"
fi

# --- claimed numbers vs committed baselines ---
suite_base=$(sf_baseline_num "$ROOT/tests/.suite-baseline")
audit_base=$(sf_baseline_num "$ROOT/tests/.audit-baseline")
if [ -n "$suite_base" ]; then
  en=$(grep -oE '\([0-9]+ golden-case assertions\)' "$ROOT/README.md" 2>/dev/null | grep -oE '[0-9]+' | head -n 1)
  zh=$(grep -oE '[0-9]+ (项|条) golden-case 断言' "$ROOT/README.zh-CN.md" 2>/dev/null | grep -oE '[0-9]+' | head -n 1)
  [ "$en" = "$suite_base" ] && [ "$zh" = "$suite_base" ] \
    && ok "README suite counts match tests/.suite-baseline ($suite_base)" \
    || bad "README suite counts drift from tests/.suite-baseline ($suite_base): en=${en:-?} zh=${zh:-?}"
else
  bad "tests/.suite-baseline missing or non-numeric"
fi
if [ -n "$audit_base" ]; then
  en=$(grep -oE '\(assertions: [0-9]+\)' "$ROOT/README.md" 2>/dev/null | grep -oE '[0-9]+' | head -n 1)
  zh=$(grep -oE '（断言：[0-9]+）' "$ROOT/README.zh-CN.md" 2>/dev/null | grep -oE '[0-9]+' | head -n 1)
  [ "$en" = "$audit_base" ] && [ "$zh" = "$audit_base" ] \
    && ok "README audit counts match tests/.audit-baseline ($audit_base)" \
    || bad "README audit counts drift from tests/.audit-baseline ($audit_base): en=${en:-?} zh=${zh:-?}"
else
  bad "tests/.audit-baseline missing or non-numeric"
fi

# --- empty-glob trap in changed shell files ---
trap_hits=""
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r f; do
    case "$f" in *.sh) ;; *) continue ;; esac
    [ -f "$ROOT/$f" ] || continue
    hit=$(grep -nE 'ls -d[^|;]*/[[:space:]]*(2>|$|\|)' "$ROOT/$f" 2>/dev/null | head -n 3 || true)
    [ -n "$hit" ] && trap_hits="$trap_hits
$f: $hit"
  done <<EOF
$(git -C "$ROOT" status --porcelain 2>/dev/null | sed -e 's/^...//')
EOF
fi
if [ -n "$trap_hits" ]; then
  warn "ls -d pattern ending in a slash can match a missing glob and defeat 2>/dev/null:$trap_hits"
else
  ok "changed shell files carry no trailing-slash ls -d empty-glob trap"
fi

# --- claims chain (v3.88.0, CHG-116, REQ-1194) ---
# Docs claims must equal the machine face in BOTH directions: a TC the runner
# reports but no doc registers (the TC-1465 incident) is as bad as a TC the
# docs claim with no report line behind it. Scoping: machine ids at or above
# the claims face's minimum must all be registered — smaller ids belong to
# older batches' docs (T50/T51 still report TC-1120-era pins); phantom checks
# need no range. 01.5 anchors of the form `file:line（token）` are verified
# against the live file — a moved line or a dangling file is exactly the N6
# drift family. Objects live in gitignored docs/, so this check exists only
# here (CI's not-checked-here boundary stays).
if [ -n "$CHANGE_DIR" ] && [ -f "$ROOT/tests/run-tests.sh" ]; then
  _m_tc=$(grep -oE '^ *report "[^"]*"' "$ROOT/tests/run-tests.sh" | grep -oE 'TC-[0-9]+' | sort -u | tr '\n' ' ')
  _c_tc=$(cat "$CHANGE_DIR/04-test-scripts.md" "$CHANGE_DIR/01.5-rtvm-matrix.md" 2>/dev/null | grep -ohE 'TC-[0-9]+' | sort -u | tr '\n' ' ')
  _c_min=$(printf '%s' "$_c_tc" | tr ' ' '\n' | sed -n 's/TC-//p' | sort -n | head -1)
  _unreg=""
  for _t in $_m_tc; do
    _n=${_t#TC-}
    case "$_n" in ''|*[!0-9]*) continue ;; esac
    [ -n "$_c_min" ] && [ "$_n" -lt "$_c_min" ] && continue
    case " $_c_tc " in *" $_t "*) ;; *) _unreg="$_unreg $_t" ;; esac
  done
  [ -z "$_unreg" ] || bad "claims chain: unregistered TC (reported by run-tests, absent from 04/01.5):$_unreg"
  _phantom=""
  for _t in $_c_tc; do case " $_m_tc " in *" $_t "*) ;; *) _phantom="$_phantom $_t" ;; esac; done
  [ -z "$_phantom" ] || bad "claims chain: phantom TC (in 04/01.5, no report line):$_phantom"
  _anc_bad=""
  _anc_n=0
  # N4 family (CHG-115 R1): a for-loop over $(grep) word-splits on the spaces
  # inside tokens like（`--from-baseline` 解析）— iterate lines instead.
  while IFS= read -r _a; do
    [ -n "$_a" ] || continue
    _anc_n=$(( _anc_n + 1 ))
    _af="${_a%%:*}"
    _rest="${_a#*:}"
    _ln="${_rest%%（*}"
    _ln="${_ln%\`}"   # 01.5 writes `file:line`（token）— the closing backtick sits between the line number and （
    _tk="${_rest#*（}"
    _tk="${_tk%）}"
    _tk="${_tk//\`/}"   # markdown code spans are formatting, not token content
    if [ ! -f "$ROOT/$_af" ]; then
      _anc_bad="$_anc_bad $_a(dangling)"
    elif ! sed -n "${_ln}p" "$ROOT/$_af" 2>/dev/null | grep -qF "$_tk"; then
      _anc_bad="$_anc_bad $_a"
    fi
  done < <(grep -ohE '[A-Za-z0-9_./-]+:[0-9]+`?（[^）]+）' "$CHANGE_DIR/01.5-rtvm-matrix.md" 2>/dev/null)
  [ -z "$_anc_bad" ] || bad "claims chain: anchor drift/dangling:$_anc_bad"
  if [ -z "$_unreg" ] && [ -z "$_phantom" ] && [ -z "$_anc_bad" ]; then
    ok "claims chain: $(printf '%s' "$_m_tc" | wc -w | tr -d ' ') machine TC ids, $_c_min+ registered, $_anc_n anchors verified"
  fi
elif [ -n "$CHANGE_DIR" ]; then
  warn "claims chain skipped: no tests/run-tests.sh in this repo"
fi

# --- source audit (optional) ---
if [ "$SKIP_AUDIT" -eq 1 ]; then
  note "source audit (--skip-audit)"
elif [ -f "$ROOT/tests/audit-standards-src.sh" ]; then
  audit_out=$( cd "$ROOT" && bash tests/audit-standards-src.sh 2>&1 ); audit_rc=$?
  if [ "$audit_rc" -eq 0 ]; then
    ok "source audit green"
  else
    bad "source audit red (rc=$audit_rc)"
    printf '%s\n' "$audit_out" | grep '^FAIL\|^A[0-9].*:' | head -n 15
  fi
else
  warn "tests/audit-standards-src.sh absent — audit skipped"
fi

if [ "$STRICT" -eq 1 ] && [ "$WARNS" -gt 0 ]; then
  FAILS=$(( FAILS + WARNS ))
  printf '\npre-review-check: --strict promoted %s warning(s) to failures\n' "$WARNS"
fi
printf '\npre-review-check: %s (%s failure(s), %s warning(s))\n' \
  "$([ "$FAILS" -eq 0 ] && echo PASS || echo FAIL)" "$FAILS" "$WARNS"
[ "$FAILS" -eq 0 ]
