#!/usr/bin/env bash
# batch-metrics.sh — per-batch cost/throughput record, so "did this change speed
# anything up" is answerable from a file instead of from chat memory.
#
#   batch-metrics.sh record [--batch BATCH-YYYYMMDD]   # upsert one row
#   batch-metrics.sh report [--batch ID] [--limit N]   # read the ledger back
#   batch-metrics.sh --root DIR
#
# record collects, read-only: the batch's change ids and artifact completeness,
# the committed baselines, the last suite receipt's count/wall time, the verify-all
# status, and the session counters the execution disciplines are actually about
# (turns, edits, sleep_polls, full_suite runs). The TSV at
# .agent-state/batch-metrics.tsv is the canonical ledger; the JSON mirror at
# .agent-state/batch-metrics.json is regenerated from it on every record, so the
# two can never disagree. Override: AGENT_GUARD_BATCH_METRICS_PATH sets the JSON
# mirror and the TSV follows it (%.json → %.tsv); AGENT_GUARD_BATCH_METRICS_TSV_PATH
# overrides the TSV alone.
#
# Nothing here is shipped with the Skill: the metrics describe this repo's own
# governance overhead, not the payload a target repo receives.
#
# Source-layer only (NOT shipped with the Skill).
# Zero deps: bash 3.2+, git, sed, tr, date, grep, awk, find.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BATCH=""
BATCH_GIVEN=0
LIMIT=0
ACTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    record|report) ACTION="$1"; shift ;;
    --batch) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "batch-metrics: --batch needs a value" >&2; exit 2; }; BATCH="$2"; BATCH_GIVEN=1; shift 2 ;;
    --limit) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "batch-metrics: --limit needs a value" >&2; exit 2; }; LIMIT="$2"; shift 2 ;;
    --root) { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "batch-metrics: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; exit 0 ;;
    *) echo "batch-metrics: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$ACTION" ] || { echo "batch-metrics: usage: batch-metrics.sh record|report [options]" >&2; exit 2; }
case "$LIMIT" in ''|*[!0-9]*) LIMIT=0 ;; esac
[ -d "$ROOT" ] || { echo "batch-metrics: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
source "$ROOT/scripts/lib-source-facts.sh"

JSON_PATH="${AGENT_GUARD_BATCH_METRICS_PATH:-$ROOT/.agent-state/batch-metrics.json}"
TSV_PATH="${AGENT_GUARD_BATCH_METRICS_TSV_PATH:-${JSON_PATH%.json}.tsv}"
HEADER="recorded_at|batch|risk|change_ids|artifacts|fill_files|audit_baseline|suite_baseline|suite_passed|suite_failed|suite_wall_s|turns|edits|sleep_polls|full_suite|verify_status"
ART_TOTAL=16
REQUIRED="00-governance.json 00-intent.md 00.5-communication.md 01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 04.5-coding-record.md 05-test-results.md 06-delivery-summary.md 06.5-deployment-config.md 07-review-report.md 09-changelog.md handoff.md"

[ "$BATCH_GIVEN" -eq 1 ] || BATCH=$(find "$ROOT/docs/changes" -maxdepth 1 -type d -name 'BATCH-*' 2>/dev/null | sort | tail -n 1 | sed 's#.*/##')
[ -n "$BATCH" ] || { echo "batch-metrics: no batch given and none found under docs/changes" >&2; exit 2; }

cell() { # value -> single-line tab-free cell
  local v="${1-}"
  [ -n "$v" ] || v="-"
  printf '%s' "$v" | tr -d '\t\n'
}

collect_row() { # batch -> TSV row
  local batch="$1" dir="$ROOT/docs/changes/$1"
  local present=0 f ids="" risk="" fill="0" ab sb sp sf sw vs turns edits polls full
  if [ -d "$dir" ]; then
    for f in $REQUIRED; do [ -s "$dir/$f" ] && present=$(( present + 1 )); done
    ids=$(sed -nE 's/.*"change_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$dir/00-governance.json" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    risk=$(sed -nE 's/.*"risk_level"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$dir/00-governance.json" 2>/dev/null | head -n 1)
    fill=$(grep -rlE 'FILL-|<!-- FILL' "$dir" 2>/dev/null | wc -l | tr -d ' ')
  fi
  ab=$(sf_baseline_num "$ROOT/tests/.audit-baseline")
  sb=$(sf_baseline_num "$ROOT/tests/.suite-baseline")
  sp=$(sf_read_json_num "$(sf_suite_receipt_path "$ROOT")" passed)
  sf=$(sf_read_json_num "$(sf_suite_receipt_path "$ROOT")" failed)
  sw=$(sf_read_json_num "$(sf_suite_receipt_path "$ROOT")" wall_time_s)
  vs=$(sf_verify_status "${AGENT_GUARD_VERIFY_RECEIPT_PATH:-$ROOT/.agent-state/verify-receipt.json}")
  turns=$(sf_read_json_num "$ROOT/.agent-state/session-tool-stats.json" turns)
  edits=$(sf_read_json_num "$ROOT/.agent-state/session-tool-stats.json" edits)
  polls=$(sf_read_json_num "$ROOT/.agent-state/session-tool-stats.json" sleep_polls)
  full=$(sf_read_json_num "$ROOT/.agent-state/session-tool-stats.json" full_suite)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(cell "$(sf_now)")" "$(cell "$batch")" "$(cell "$risk")" "$(cell "$ids")" \
    "$(cell "$present/$ART_TOTAL")" "$(cell "$fill")" "$(cell "$ab")" "$(cell "$sb")" \
    "$(cell "$sp")" "$(cell "$sf")" "$(cell "$sw")" "$(cell "$turns")" "$(cell "$edits")" \
    "$(cell "$polls")" "$(cell "$full")" "$(cell "${vs:-none}")"
}

json_from_tsv() { # tsv file -> json mirror on stdout
  awk -F '\t' -v now="$(sf_now)" '
    NR==1 { for (i=1;i<=NF;i++) h[i]=$i; next }
    { rows[++n]=$0 }
    END {
      printf "{\"schema\":1,\"updated_at\":\"%s\",\"batches\":{\n", now
      for (r=1; r<=n; r++) {
        split(rows[r], c, "\t")
        bk=c[2]; gsub(/[\\"]/, "\\\\&", bk)
        printf "  \"%s\": {", bk
        sep=""
        for (i=1; i<=16; i++) {
          if (i==2) continue
          v=c[i]; gsub(/[\\"]/, "\\\\&", v)
          if (i==5) { split(v, p, "/"); printf "%s\"artifacts_present\":%s,\"artifacts_required\":%s", sep, p[1], p[2]; sep=","; continue }
          if (v ~ /^-?[0-9]+$/) printf "%s\"%s\":%s", sep, h[i], v
          else printf "%s\"%s\":\"%s\"", sep, h[i], v
          sep=","
        }
        printf " }%s\n", (r<n ? "," : "")
      }
      printf "}\n}\n"
    }
  ' "$1"
}

pretty_tsv() { # tsv file (or stdin) -> aligned columns on stdout
  awk -F '\t' '{ for (i=1;i<=NF;i++) printf "%s%s", (i>1 ? " | " : ""), $i; print "" }' "$@"
}

if [ "$ACTION" = "report" ]; then
  [ -f "$TSV_PATH" ] || { echo "batch-metrics: no ledger at $TSV_PATH yet" >&2; exit 1; }
  if [ "$BATCH_GIVEN" -eq 1 ]; then
    awk -F '\t' -v b="$BATCH" 'NR==1 || $2==b' "$TSV_PATH" | pretty_tsv
  else
    if [ "$LIMIT" -gt 0 ]; then
      { head -n 1 "$TSV_PATH"; tail -n +2 "$TSV_PATH" | tail -n "$LIMIT"; } | pretty_tsv
    else
      pretty_tsv "$TSV_PATH"
    fi
  fi
  printf '\ncanonical ledger: %s\njson mirror: %s\n' "$TSV_PATH" "$JSON_PATH"
  exit 0
fi

# --- record ---
mkdir -p "$(dirname "$TSV_PATH")" || { echo "batch-metrics: cannot create $(dirname "$TSV_PATH")" >&2; exit 1; }
ROW=$(collect_row "$BATCH") || { echo "batch-metrics: collection failed" >&2; exit 1; }
if [ -f "$TSV_PATH" ]; then
  awk -F '\t' -v drop="$BATCH" 'NR==1 || $2!=drop' "$TSV_PATH" > "$TSV_PATH.new" || exit 1
else
  printf '%s\n' "$HEADER" | tr '|' '\t' > "$TSV_PATH.new" || exit 1
fi
printf '%s\n' "$ROW" >> "$TSV_PATH.new" || exit 1
mv "$TSV_PATH.new" "$TSV_PATH" || exit 1
json_from_tsv "$TSV_PATH" > "$JSON_PATH" || { echo "batch-metrics: json mirror rewrite failed" >&2; exit 1; }
printf 'batch-metrics: recorded %s\n' "$BATCH"
printf '  tsv : %s\n  json: %s\n' "$TSV_PATH" "$JSON_PATH"
