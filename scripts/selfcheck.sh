#!/usr/bin/env bash
# selfcheck.sh — single source-repo dogfood entry (source layer only, never shipped).
#
# v3.87.0 (CHG-115): the four verification faces are ordered, collected and receipt-
# reused by scripts/verify-all.sh (release carriers → private-ledger audit → source
# audit → golden-case suite). The source audit no longer embeds a full suite run: it
# consumes tests/.suite-baseline, so a stale receipt can't turn an 8s read into a
# 300s rerun. Pass-through arguments reach verify-all (e.g. --fresh, --skip-suite).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

rc=0
bash scripts/verify-all.sh "$@" || rc=$?

if [[ -f scripts/eval-cases ]]; then
  echo '== eval cases =='
  bash scripts/eval-cases --verify || rc=$?
fi

exit "$rc"
