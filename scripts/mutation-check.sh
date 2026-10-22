#!/usr/bin/env bash
# mutation-check.sh — prove the fast checkers actually go red (checker self-test).
#
#   mutation-check.sh                 # control + every fixed mutation
#   mutation-check.sh --list          # enumerate mutation names
#   mutation-check.sh --only NAME     # run one mutation (NAME from --list)
#   mutation-check.sh --root DIR      # mutate a copy of another checkout
#
# Each mutation gets a throwaway copy of the tracked working tree (plus untracked
# source-layer files), is mutated THERE, and the relevant fast checker must exit
# non-zero. Live files are never written: the whole git-visible face is content-
# hashed before and after the sweep, and the un-mutated control run of both
# checkers must stay green before and after (auto re-green).
#
# Fixed mutations: version-drift (DS footer), gate-version-drift (gate template),
# baseline-missing (tests/.suite-baseline), readme-count-drift (README claim).
# TMPDIR is redirected per run so the generator's audit-last scratch file cannot
# leak between copies. Zero deps: bash 3.2+, git, sed, cp, cmp, cksum, cut, diff.
#
# Source-layer only (NOT shipped with the Skill).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ONLY=""
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "mutation-check: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --only) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "mutation-check: --only needs a value" >&2; exit 2; }; ONLY="$2"; shift 2 ;;
    --list) LIST=1; shift ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; exit 0 ;;
    *) echo "mutation-check: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "mutation-check: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
# The header already advertised this file as a lib consumer; make it true. One
# baseline-number parser instead of two (v3.87.0 R4, finding #9).
[ -f "$ROOT/scripts/lib-source-facts.sh" ] \
  || { echo "mutation-check: scripts/lib-source-facts.sh is required under $ROOT" >&2; exit 2; }
source "$ROOT/scripts/lib-source-facts.sh"

NAMES=(version-drift gate-version-drift baseline-missing readme-count-drift)
# the file each mutation is expected to change inside the copy
case "$LIST" in
  1) printf '%s\n' "${NAMES[@]}"; exit 0 ;;
esac

DS_VERSION=$(sed -nE 's/.*规范版本：v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$ROOT/resources/DEVELOPMENT_STANDARDS.md" 2>/dev/null | head -n 1)
[ -n "$DS_VERSION" ] || { echo "mutation-check: cannot read the DS footer version" >&2; exit 2; }
SUITE_N=$(sf_baseline_num "$ROOT/tests/.suite-baseline")
[ -n "$SUITE_N" ] || { echo "mutation-check: tests/.suite-baseline must hold a number" >&2; exit 2; }

WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mutation-check.XXXXXX") || { echo "mutation-check: mktemp failed" >&2; exit 2; }
cleanup() { rm -rf "$WORK_ROOT" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# --- the two fast checkers under test ---
CHECK_RELEASE="bash scripts/release.sh check"
CHECK_BASELINE="bash scripts/update-assertion-count.sh --check --from-baseline"

copy_tree() { # dest
  local dest="$1" paths p
  mkdir -p "$dest" || return 1
  paths=$( { git -C "$ROOT" ls-files 2>/dev/null; git -C "$ROOT" status --porcelain 2>/dev/null | sed -e 's/^...//' -e 's/^.* -> //'; } | sort -u )
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$ROOT/$p" ] || continue
    mkdir -p "$dest/$(dirname "$p")" || return 1
    cp "$ROOT/$p" "$dest/$p" || return 1
  done <<EOF
$paths
EOF
  ( cd "$dest" && git init -q && git config user.email mutation@example.invalid \
      && git config user.name mutation && git add -A >/dev/null 2>&1 \
      && git commit -qm "mutation fixture" >/dev/null 2>&1 ) || return 1
  return 0
}

run_checker() { # dest command -> rc
  local dest="$1" cmd="$2"
  ( cd "$dest" && TMPDIR="$dest/.tmp" bash -c "$cmd" ) >/dev/null 2>&1
  echo $?
}

FAILED=0

# Whole-face live proof (v3.87.0 R4, finding #12): the earlier guard cmp'd five
# hand-picked files, so a mutation leaking into any other live file went
# unreported. Every path git can see — tracked plus untracked-but-not-ignored —
# is hashed by content, so a content change, an added file and a deletion all
# show up. gitignored paths (.agent-state, docs/) are excluded by construction,
# which is what keeps the fixture's own scratch writes out of the comparison.
live_state() {
  local p
  { git -C "$ROOT" ls-files 2>/dev/null; git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null; } \
  | sort -u | while IFS= read -r p; do
      [ -f "$ROOT/$p" ] || continue
      printf '%s %s\n' "$(cksum < "$ROOT/$p" | cut -d' ' -f1,2)" "$p"
    done
}
SNAP_BEFORE="$WORK_ROOT/live-before.lst"
SNAP_AFTER="$WORK_ROOT/live-after.lst"

verify_live_untouched() { # label
  local label="$1"
  live_state > "$SNAP_AFTER" || { printf 'FAIL %s: cannot re-hash the working tree\n' "$label" >&2; return 1; }
  cmp -s "$SNAP_BEFORE" "$SNAP_AFTER" && return 0
  printf 'FAIL %s: the live tree changed during the sweep\n' "$label" >&2
  diff "$SNAP_BEFORE" "$SNAP_AFTER" | head -n 20 >&2
  return 1
}

# --- control: the un-mutated copy must keep both checkers green ---
control_run() { # label
  local label="$1" rc_rel rc_base
  local dest="$WORK_ROOT/$label"
  mkdir -p "$dest/.tmp" || return 1
  copy_tree "$dest" || { echo "FAIL $label: cannot build the fixture copy" >&2; return 1; }
  rc_rel=$(run_checker "$dest" "$CHECK_RELEASE")
  rc_base=$(run_checker "$dest" "$CHECK_BASELINE")
  if [ "$rc_rel" -eq 0 ] && [ "$rc_base" -eq 0 ]; then
    printf 'ok   %-22s control green (release=%s baseline=%s)\n' "$label" "$rc_rel" "$rc_base"
    return 0
  fi
  printf 'FAIL %-22s control is not green (release=%s baseline=%s) — fix the checker before mutating\n' "$label" "$rc_rel" "$rc_base" >&2
  return 1
}

mutate() { # name dest
  local name="$1" dest="$2" f tmp
  case "$name" in
    version-drift)
      f="$dest/resources/DEVELOPMENT_STANDARDS.md"
      tmp="$f.mut"
      printf '规范版本：v0.0.0\n' > "$tmp" && cat "$f" >> "$tmp" && mv "$tmp" "$f"
      ;;
    gate-version-drift)
      f="$dest/resources/templates/agent-gate.sh"
      tmp="$f.mut"
      sed "s/\"gate_version\":\"$DS_VERSION\"/\"gate_version\":\"0.0.0\"/" "$f" > "$tmp" && mv "$tmp" "$f"
      ;;
    baseline-missing)
      rm -f "$dest/tests/.suite-baseline"
      ;;
    readme-count-drift)
      f="$dest/README.md"
      tmp="$f.mut"
      sed "s/($SUITE_N golden-case assertions)/(9999 golden-case assertions)/" "$f" > "$tmp" && mv "$tmp" "$f"
      ;;
    *) echo "mutation-check: unknown mutation '$name'" >&2; return 2 ;;
  esac
}

# which checker each mutation is responsible for
checker_for() { # name
  case "$1" in
    version-drift|gate-version-drift) printf '%s\n' "$CHECK_RELEASE" ;;
    baseline-missing|readme-count-drift) printf '%s\n' "$CHECK_BASELINE" ;;
  esac
}

# the file each mutation is expected to change in the copy
target_for() { # name
  case "$1" in
    version-drift) printf 'resources/DEVELOPMENT_STANDARDS.md\n' ;;
    gate-version-drift) printf 'resources/templates/agent-gate.sh\n' ;;
    baseline-missing) printf 'tests/.suite-baseline\n' ;;
    readme-count-drift) printf 'README.md\n' ;;
  esac
}

# did the mutation actually land in the copy (and only as intended)?
mutation_applied() { # name dest
  local name="$1" dest="$2" target
  target=$(target_for "$name")
  if [ "$name" = "baseline-missing" ]; then
    [ ! -f "$dest/$target" ]
  else
    [ -f "$dest/$target" ] && ! cmp -s "$ROOT/$target" "$dest/$target"
  fi
}

live_state > "$SNAP_BEFORE" || { echo "mutation-check: cannot hash the live tree" >&2; exit 2; }
# An empty listing means git could not see this root at all — comparing two empty
# files would be green without proving anything.
[ -s "$SNAP_BEFORE" ] || { echo "mutation-check: the live tree has no git-visible files to hash: $ROOT" >&2; exit 2; }

control_run control-before || FAILED=1

SELECTED=""
if [ -n "$ONLY" ]; then
  found=0
  for n in "${NAMES[@]}"; do [ "$n" = "$ONLY" ] && found=1; done
  [ "$found" -eq 1 ] || { echo "mutation-check: unknown mutation '$ONLY' (see --list)" >&2; exit 2; }
  SELECTED="$ONLY"
else
  SELECTED="${NAMES[*]}"
fi

for name in $SELECTED; do
  dest="$WORK_ROOT/$name"
  mkdir -p "$dest/.tmp" || { FAILED=1; continue; }
  copy_tree "$dest" || { echo "FAIL $name: cannot build the fixture copy" >&2; FAILED=1; continue; }
  before_rc=$(run_checker "$dest" "$(checker_for "$name")")
  if [ "$before_rc" -ne 0 ]; then
    printf 'FAIL %-22s the checker was already red before mutating — nothing to prove\n' "$name" >&2
    FAILED=1
    continue
  fi
  mutate "$name" "$dest" || { printf 'FAIL %-22s mutation could not be applied\n' "$name" >&2; FAILED=1; continue; }
  if ! mutation_applied "$name" "$dest"; then
    printf 'FAIL %-22s mutation did not change the copy (no-op mutation)\n' "$name" >&2
    FAILED=1
    continue
  fi
  after_rc=$(run_checker "$dest" "$(checker_for "$name")")
  if [ "$after_rc" -eq 0 ]; then
    printf 'FAIL %-22s checker stayed green under the mutation — it cannot catch this drift\n' "$name" >&2
    FAILED=1
  else
    printf 'ok   %-22s caught by the checker (rc=%s)\n' "$name" "$after_rc"
  fi
done

control_run control-after || FAILED=1
verify_live_untouched live-tree || FAILED=1

printf '\nmutation-check: %s\n' "$([ "$FAILED" -eq 0 ] && echo PASS || echo FAIL)"
[ "$FAILED" -eq 0 ]
