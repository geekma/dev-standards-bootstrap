#!/usr/bin/env bash
# selfcheck.sh — single source-repo dogfood entry (source layer only, never shipped).
#
# Order matters: the source audit embeds a full golden-case run via
# update-assertion-count, and the private-ledger audit reads the real docs/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo '== release carriers =='
bash scripts/release.sh check

echo '== source audit (embeds a full suite run) =='
bash tests/audit-standards-src.sh

if [[ -d docs ]]; then
  echo '== private-ledger audit =='
  bash tests/audit-docs-consistency.sh
else
  echo '== private-ledger audit: SKIP (docs/ absent) =='
fi

if [[ -f scripts/eval-cases ]]; then
  echo '== eval cases =='
  bash scripts/eval-cases --verify
fi

echo 'selfcheck: OK'
