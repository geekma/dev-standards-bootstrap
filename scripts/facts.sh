#!/usr/bin/env bash
# facts.sh — one cheap, machine-readable snapshot of the source repo.
#
#   facts.sh                    # JSON to stdout (<1s; never runs the suite)
#   facts.sh --write            # also write .agent-state/facts.json
#   facts.sh --root DIR         # inspect another checkout (tests/fixtures)
#   facts.sh --path FILE        # override the --write destination
#
# Fields: head/branch/version/tree_fingerprint/dirty/changed_files,
# active_change, audit_baseline, suite_baseline, and the suite receipt with a
# computed `fresh` flag. The point is to stop paying an LLM round-trip (or a
# suite run) for facts a local read can produce deterministically.
#
# Source-layer only (NOT shipped with the Skill).
# Zero deps: bash 3.2+, git, sed, tr, date, stat.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WRITE=0
DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "facts: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --write) WRITE=1; shift ;;
    --path) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "facts: --path needs a value" >&2; exit 2; }; DEST="$2"; shift 2 ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; exit 0 ;;
    *) echo "facts: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "facts: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
source "$ROOT/scripts/lib-source-facts.sh"
OUT=$(sf_emit_facts "$ROOT") || { echo "facts: failed to collect facts" >&2; exit 2; }
if [ "$WRITE" -eq 1 ]; then
  [ -n "$DEST" ] || DEST="${AGENT_GUARD_FACTS_PATH:-$ROOT/.agent-state/facts.json}"
  mkdir -p "$(dirname "$DEST")" || { echo "facts: cannot create $(dirname "$DEST")" >&2; exit 2; }
  tmp="${DEST}.$$"
  printf '%s\n' "$OUT" > "$tmp" || { echo "facts: cannot write $tmp" >&2; rm -f "$tmp"; exit 2; }
  mv -f "$tmp" "$DEST" || { echo "facts: cannot replace $DEST" >&2; rm -f "$tmp"; exit 2; }
  printf 'facts: wrote %s\n' "$DEST" >&2
fi
printf '%s\n' "$OUT"
