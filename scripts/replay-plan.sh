#!/usr/bin/env bash
# replay-plan.sh — source-layer replay check for the adaptive test-scope resolver.
#
# final-plan §9 says replay is the only correctness proof for the engine:
# "拿历史变更的 diff 跑 plan，比对引擎认为该跑的与当时实际跑了且发现问题的".
# This script implements the measurable half that history actually preserves:
#
#   selected  = what today's resolver (-T auto, same single implementation the
#               gate uses) would choose for that change's recorded diff
#   actual    = governance sections named in that change's 04/05 artifacts
#   missed    = actual - selected  → a FALSE NEGATIVE (a section that was really
#               exercised but today's resolver would not select)
#
# A FULL selection can never miss anything, so those rows are reported as
# `full` and excluded from the recall denominator (honest, not inflated).
#
# Read-only. No writes except stdout. Zero deps: git + bash 3.2+.
# Usage: scripts/replay-plan.sh [--limit N] [--json]
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2

limit=0
json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) limit="${2:-0}"; shift 2 ;;
    --json) json=1; shift ;;
    *) echo "usage: scripts/replay-plan.sh [--limit N] [--json]" >&2; exit 2 ;;
  esac
done

changes_root="$ROOT/docs/changes"
[[ -d "$changes_root" ]] || { echo "replay: no docs/changes (not a governance repo)"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "replay: not a git repository"; exit 2; }

# Section ids the runner knows, so "actual" only counts real sections.
sections=$(bash "$ROOT/tests/run-tests.sh" -l 2>/dev/null | tr '\n' ' ' || true)
[[ -n "$sections" ]] || { echo "replay: cannot list suite sections"; exit 2; }

n_total=0; n_used=0; n_skip=0; n_full=0; n_conc=0; n_fn=0; n_fn_sections=0
rows=""

for d in "$changes_root"/*/; do
  [[ -d "$d" ]] || continue
  # A batch directory holds several ids and SHARES one 05 — its recorded runs
  # cannot be attributed to a single member, so replay would invent false
  # negatives. Batches are counted as skipped, never guessed.
  case "$(basename "$d")" in
    BATCH-*) n_total=$(( n_total + 1 )); n_skip=$(( n_skip + 1 )); continue ;;
  esac
  # A batch directory holds several ids; one id per governance record.
  ids=$(grep -oE '"change_id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9._-]+"' "$d/00-governance.json" 2>/dev/null \
    | sed -E 's/.*"([A-Za-z0-9._-]+)"$/\1/' | sort -u)
  [[ -n "$ids" ]] || continue
  for id in $ids; do
    n_total=$(( n_total + 1 ))
    [[ "$limit" -gt 0 && "$n_used" -ge "$limit" ]] && break 2
    f04="$d/04-test-scripts.md"; f05="$d/05-test-results.md"
    [[ -s "$f04" || -s "$f05" ]] || { n_skip=$(( n_skip + 1 )); continue; }
    # Commits that carry this id (merge/revert excluded by the caller convention).
    commits=$(git log --format='%H' --grep="$id" --fixed-strings 2>/dev/null | tail -20)
    [[ -n "$commits" ]] || { n_skip=$(( n_skip + 1 )); continue; }
    first=$(printf '%s\n' "$commits" | tail -1)
    last=$(printf '%s\n' "$commits" | head -1)
    if git rev-parse -q --verify "$first^" >/dev/null 2>&1; then
      changed=$(git diff --name-only "$first^..$last" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
    else
      changed=$(git diff-tree --root --no-commit-id --name-only -r "$last" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
    fi
    [[ -n "$changed" ]] || { n_skip=$(( n_skip + 1 )); continue; }
    n_used=$(( n_used + 1 ))
    sel=$(AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 AGENT_GUARD_SUITE_AUTO_DIFF="$changed" \
      bash "$ROOT/tests/run-tests.sh" -T auto 2>/dev/null \
      | sed -n 's/^auto-resolve-only:[[:space:]]*//p' | tail -1 || true)
    if [[ "$sel" == "FULL" ]]; then
      n_full=$(( n_full + 1 )); rows="${rows}${id}\tFULL\t-\t-\n"; continue
    fi
    # Actual = sections the evidence artifact says were RUN (`run-tests.sh -T …`).
    # Merely mentioning a section elsewhere in 05 is not evidence of execution —
    # counting it produced false negatives that were really prose noise.
    act=$(grep -oE 'run-tests\.sh[^`|]*' "$f05" 2>/dev/null \
      | grep -oE '\-T[[:space:]]*[A-Za-z0-9,_-]+' | sed -E 's/^-T[[:space:]]*//' | tr ',' '\n' \
      | grep -E '^T[0-9]+[a-z]?$' | sort -u | tr '\n' ' ')
    if [[ -z "$act" ]]; then
      # No targeted run recorded: either a full run or no suite evidence at all.
      # Neither can produce a false negative, so it is not in the recall denominator.
      n_full=$(( n_full + 1 )); rows="${rows}${id}\t${sel:-none}\tno-targeted-run\t-\n"; continue
    fi
    n_conc=$(( n_conc + 1 ))
    miss=""
    for s in $act; do
      case " $sections " in *" $s "*) ;; *) continue ;; esac
      case " $sel " in *" $s "*) ;; *) miss="$miss $s" ;; esac
    done
    [[ -n "$miss" ]] && { n_fn=$(( n_fn + 1 )); n_fn_sections=$(( n_fn_sections + $(printf '%s' "$miss" | wc -w | tr -d ' ') )); }
    rows="${rows}${id}\t${sel:-none}\t${act:-none}\t${miss:-none}\n"
  done
done

printf '%b' "$rows" | while IFS= read -r line; do
  [[ -n "$line" ]] && printf 'replay: %s\n' "$line"
done

den=$(( n_conc > 0 ? n_conc : 1 ))
if [[ "$n_conc" -gt 0 ]]; then recall="$(( (n_conc - n_fn) * 100 / den ))%"; else recall="n/a（无具体选节样本）"; fi
echo "replay: changes=$n_total usable=$n_used skipped=$n_skip full=$n_full concrete=$n_conc"
echo "replay: false-negative changes=$n_fn sections=$n_fn_sections recall=$recall"
echo "replay: NOTE — 'actual' is what 04/05 artifacts name, not a re-execution; FULL rows are excluded from recall."
