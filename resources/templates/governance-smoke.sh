#!/usr/bin/env bash
# governance-smoke.sh — shipped lightweight target-repo smoke check (ITEM-41)
set -uo pipefail

REPO_ARG=""; SKIP_DOCS=0; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || { echo "governance-smoke: --repo needs a dir" >&2; exit 2; }; REPO_ARG="$2"; shift 2 ;;
    --skip-docs) SKIP_DOCS=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help)
      echo "Usage: governance-smoke.sh [--repo <dir>] [--skip-docs] [--json]"
      exit 0 ;;
    *) echo "governance-smoke: unknown option '$1'" >&2; exit 2 ;;
  esac
done

ROOT="${REPO_ARG:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || { echo "governance-smoke: cannot enter $ROOT" >&2; exit 2; }

yml_root() { # <key> <default>
  local k="$1" d="$2" v=""
  [[ -f .agent-governance.yml ]] && v=$(sed -nE "/^paths:[[:space:]]*$/,/^[^[:space:]#]/s/^[[:space:]]+${k}:[[:space:]]*([^#]*).*$/\1/p" .agent-governance.yml 2>/dev/null | head -n 1 | tr -d "[:space:]\"'" || true)
  printf '%s' "${v:-$d}"
}

DOCS_DIR=$(yml_root docs docs)
SCRIPTS_DIR=$(yml_root scripts scripts)
TESTS_DIR=$(yml_root tests tests)

PASS=0; FAIL=0; LAST_MSG=""
chk() {
  local name="$1" rc="$2" detail="${3:-}"
  if [[ "$rc" -eq 0 ]]; then
    PASS=$((PASS + 1))
    [[ "$JSON" -eq 0 ]] && printf 'ok   governance-smoke: %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    LAST_MSG="$name${detail:+ ($detail)}"
    [[ "$JSON" -eq 0 ]] && printf 'FAIL governance-smoke: %s%s\n' "$name" "${detail:+ — $detail}" >&2
  fi
}

chk "AGENTS.md exists" "$([[ -s AGENTS.md ]] && echo 0 || echo 1)"
chk "$DOCS_DIR/DEVELOPMENT_STANDARDS.md exists" "$([[ -s "$DOCS_DIR/DEVELOPMENT_STANDARDS.md" ]] && echo 0 || echo 1)"

v_ag=$(grep -oE '当前对应规范版本：v[0-9]+\.[0-9]+\.[0-9]+' AGENTS.md 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1 || true)
[[ -n "$v_ag" ]] || v_ag=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' AGENTS.md 2>/dev/null | tail -n 1 || true)
v_ds=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$DOCS_DIR/DEVELOPMENT_STANDARDS.md" 2>/dev/null | tail -n 1 || true)
chk "AGENTS & DEVELOPMENT_STANDARDS footer versions match (${v_ds:-?})" "$([[ -n "$v_ag" && "$v_ag" == "$v_ds" ]] && echo 0 || echo 1)" "$v_ag vs $v_ds"

for req_s in "$SCRIPTS_DIR/agent-gate" "$SCRIPTS_DIR/lib-json.sh" "$SCRIPTS_DIR/lib-gate-cold.sh"; do
  chk "$req_s present and parses" "$([[ -f "$req_s" ]] && /bin/bash -n "$req_s" 2>/dev/null && echo 0 || echo 1)"
done
for opt_s in "$SCRIPTS_DIR/session-gate.sh" "$TESTS_DIR/audit-docs-consistency.sh"; do
  [[ -f "$opt_s" ]] && chk "$opt_s parses" "$(/bin/bash -n "$opt_s" 2>/dev/null && echo 0 || echo 1)"
done

st_out=$(bash "$SCRIPTS_DIR/agent-gate" status --json 2>&1 || true)
chk "agent-gate status --json returns JSON" "$([[ "$st_out" == \{*\} ]] && echo 0 || echo 1)"
nx_out=$(bash "$SCRIPTS_DIR/agent-gate" next --json 2>&1 || true)
chk "agent-gate next --json returns JSON" "$([[ "$nx_out" == \{*\} ]] && echo 0 || echo 1)"

if [[ "$SKIP_DOCS" -eq 0 && -f "$TESTS_DIR/audit-docs-consistency.sh" ]]; then
  bash "$TESTS_DIR/audit-docs-consistency.sh" --only-fail >/dev/null 2>&1
  chk "audit-docs-consistency.sh --only-fail passes" "$?"
fi

if [[ "$JSON" -eq 1 ]]; then
  _gsm_err=$(printf '%s' "$LAST_MSG" | tr '\t\n\r' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '{"passed":%d,"failed":%d,"version":"%s","last_error":"%s"}\n' "$PASS" "$FAIL" "${v_ds:-unknown}" "$_gsm_err"
else
  printf 'governance-smoke: %d passed, %d failed\n' "$PASS" "$FAIL"
fi
[[ "$FAIL" -eq 0 ]]
