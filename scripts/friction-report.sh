#!/usr/bin/env bash
# friction-report.sh — local friction ledger trend analyzer (v4.10.0, CHG-155, ITEM-51)
# Reads .agent-state/gate-friction.tsv (handles both 5-col and legacy 2-col formats).
set -euo pipefail

FILE=""; REPO=""; TOP=10; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) [[ $# -ge 2 && -n "$2" ]] || { echo "friction-report: --file needs a path" >&2; exit 2; }; FILE="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || { echo "friction-report: --repo needs a dir" >&2; exit 2; }; REPO="$2"; shift 2 ;;
    --top)  [[ $# -ge 2 ]] || { echo "friction-report: --top needs a number" >&2; exit 2; }; TOP="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help)
      echo "Usage: friction-report.sh [--file <path>] [--repo <dir>] [--top <N>] [--json]"
      exit 0 ;;
    *) echo "friction-report: unknown option '$1'" >&2; exit 2 ;;
  esac
done

[[ "$TOP" =~ ^[1-9][0-9]*$ ]] || { echo "friction-report: --top must be a positive integer (got '$TOP')" >&2; exit 2; }

if [[ -z "$FILE" ]]; then
  BASE="${REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  FILE="$BASE/.agent-state/gate-friction.tsv"
fi

if [[ ! -s "$FILE" ]]; then
  if [[ "$JSON" -eq 1 ]]; then
    printf '{"total":0,"by_kind":{},"by_code":[],"by_change":[]}\n'
  else
    echo "friction-report: no friction events ($FILE missing or empty)"
  fi
  exit 0
fi

awk -F'\t' -v top="$TOP" -v jmode="$JSON" '
  function jesc(s) {
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\r/, "", s); gsub(/\t/, " ", s)
    return s
  }
  NF >= 2 {
    code = $1; cid = "-"; kind = "DIE"
    if (NF >= 4) { cid = ($3 != "" ? $3 : "-"); kind = ($4 != "" ? $4 : "DIE") }
    tot++
    bc[code]++
    bk[kind]++
    if (cid != "-") bchg[cid]++
  }
  END {
    nc = 0; for (k in bc) { ck[++nc] = k; cv[nc] = bc[k] }
    for (i = 1; i <= nc; i++) for (j = i + 1; j <= nc; j++) {
      if (cv[j] > cv[i] || (cv[j] == cv[i] && ck[j] < ck[i])) {
        t = cv[i]; cv[i] = cv[j]; cv[j] = t; t = ck[i]; ck[i] = ck[j]; ck[j] = t
      }
    }
    ng = 0; for (k in bchg) { gk[++ng] = k; gv[ng] = bchg[k] }
    for (i = 1; i <= ng; i++) for (j = i + 1; j <= ng; j++) {
      if (gv[j] > gv[i] || (gv[j] == gv[i] && gk[j] < gk[i])) {
        t = gv[i]; gv[i] = gv[j]; gv[j] = t; t = gk[i]; gk[i] = gk[j]; gk[j] = t
      }
    }
    if (jmode == 1) {
      printf "{\"total\":%d,\"by_kind\":{", tot+0
      kf = 1
      for (k in bk) {
        if (!kf) printf ","
        printf "\"%s\":%d", jesc(k), bk[k]+0
        kf = 0
      }
      printf "},\"by_code\":["
      lim = (nc < top ? nc : top)
      for (i = 1; i <= lim; i++) {
        if (i > 1) printf ","
        printf "{\"code\":\"%s\",\"count\":%d}", jesc(ck[i]), cv[i]+0
      }
      printf "],\"by_change\":["
      glim = (ng < top ? ng : top)
      for (i = 1; i <= glim; i++) {
        if (i > 1) printf ","
        printf "{\"change_id\":\"%s\",\"count\":%d}", jesc(gk[i]), gv[i]+0
      }
      printf "]}\n"
    } else {
      printf "friction-report: total=%d\n", tot+0
      printf "  by_kind:"
      for (k in bk) printf " %s=%d", k, bk[k]+0
      printf "\n  top_codes:\n"
      lim = (nc < top ? nc : top)
      for (i = 1; i <= lim; i++) printf "    %-14s %d\n", ck[i], cv[i]+0
      if (ng > 0) {
        printf "  top_changes:\n"
        glim = (ng < top ? ng : top)
        for (i = 1; i <= glim; i++) printf "    %-14s %d\n", gk[i], gv[i]+0
      }
    }
  }
' "$FILE"
