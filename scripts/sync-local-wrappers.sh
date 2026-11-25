#!/usr/bin/env bash
# sync-local-wrappers.sh — replace 7 duplicate source mirrors with 3-line single-source exec wrappers (ITEM-43, REQ-1453)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="write"
case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  -h|--help) echo "Usage: sync-local-wrappers.sh [--check]"; exit 0 ;;
  *) echo "sync-local-wrappers: unknown option '$1' (expected --check)" >&2; exit 2 ;;
esac

PAIRS="
scripts/agent-gate:resources/templates/agent-gate.sh
scripts/eval-cases:resources/templates/eval-cases.sh
scripts/eval-rescore:resources/templates/eval-rescore.sh
scripts/session-gate.sh:resources/templates/session-gate.sh
scripts/stamp-provenance.sh:resources/templates/stamp-provenance.sh
.githooks/pre-commit:resources/templates/pre-commit
tests/audit-docs-consistency.sh:resources/templates/audit-docs-consistency.sh
"

bad=0
while IFS=: read -r loc tpl; do
  [[ -n "$loc" && -n "$tpl" ]] || continue
  expected=$(printf '#!/usr/bin/env bash\n# single-source wrapper -> %s (ITEM-43)\nexec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/%s" "$@"\n' "$tpl" "$tpl")
  dst="$ROOT/$loc"
  if [[ "$MODE" == "check" ]]; then
    if [[ ! -f "$dst" ]] || [[ "$(cat "$dst" 2>/dev/null)" != "$expected" ]]; then
      echo "sync-local-wrappers: mismatch at $loc (-> $tpl)" >&2
      bad=$((bad + 1))
    else
      echo "ok   $loc -> $tpl"
    fi
  else
    mkdir -p "$(dirname "$dst")"
    printf '%s\n' "$expected" > "$dst"
    chmod +x "$dst"
    echo "synced $loc -> $tpl"
  fi
done <<< "$PAIRS"

[[ "$bad" -eq 0 ]]
