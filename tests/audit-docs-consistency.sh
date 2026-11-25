#!/usr/bin/env bash
# single-source wrapper -> resources/templates/audit-docs-consistency.sh (ITEM-43)
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/resources/templates/audit-docs-consistency.sh" "$@"
