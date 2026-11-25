#!/usr/bin/env bash
# A deterministic guard shared by local hooks, Git hooks, and CI (hot entry tier, v4.13.0 CHG-158).
# Warm handlers live in lib-gate-staged.sh; cold handlers live in lib-gate-cold.sh.
set -euo pipefail
case "${AGENT_GUARD_FORCE_OS:-${OSTYPE:-$(uname -s 2>/dev/null || echo unknown)}}" in
  msys*|mingw*|cygwin*|MINGW*|MSYS*|CYGWIN*) export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' ;;
esac

if [[ "${BASH_SOURCE[0]}" == */* ]]; then
  _AG_SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
else
  _AG_SELF_DIR="$PWD"
fi
_AG_SELF_BIN="${BASH_SOURCE[0]}"
for _ag_jlib in "$_AG_SELF_DIR/lib-json.sh" "$_AG_SELF_DIR/../resources/templates/lib-json.sh"; do
  if [[ -f "$_ag_jlib" ]]; then
    # shellcheck source=/dev/null
    . "$_ag_jlib"
    break
  fi
done
if ! command -v has_real_python3 >/dev/null 2>&1; then
  has_real_python3() { command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; }
fi
if ! command -v json_escape >/dev/null 2>&1; then
  json_escape() { printf '%s' "$1" | tr '\t' ' ' | tr '\n' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
fi

friction_cid() { # current change id, "-" when unknown
  local c=""
  [[ -n "${AGENT_GUARD_CHANGE:-}" ]] && { printf '%s' "$AGENT_GUARD_CHANGE"; return 0; }
  if [[ -n "${active_file:-}" && -f "$active_file" ]]; then
    IFS= read -r c < "$active_file" || true
    c="${c//[[:space:]]/}"
  fi
  printf '%s' "${c:--}"
}
friction_sanitize() { # <text> -> one TSV-safe cell (no tabs/newlines, <=160 chars)
  local s="${1//$'\t'/ }"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  printf '%.160s' "$s"
}
friction_append() { # <code> <kind: DIE|BYPASS> <reason>
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
    "$(friction_cid)" "$2" "$(friction_sanitize "$3")" \
    >> ".agent-state/gate-friction.tsv" 2>/dev/null || true
}

load_gate_staged() {
  [[ "${_LIB_GATE_STAGED_LOADED:-0}" == "1" ]] && return 0
  local _quiet=0 _s
  [[ "${1:-}" == "--quiet" ]] && _quiet=1
  for _s in "$_AG_SELF_DIR/lib-gate-staged.sh" "$_AG_SELF_DIR/../resources/templates/lib-gate-staged.sh" "${repo_root:-.}/${scripts_dir:-scripts}/lib-gate-staged.sh" "${repo_root:-.}/resources/templates/lib-gate-staged.sh"; do
    if [[ -f "$_s" ]]; then
      # shellcheck source=/dev/null
      . "$_s"
      return 0
    fi
  done
  [[ "$_quiet" -eq 1 ]] && return 1
  echo "agent-gate: cannot locate lib-gate-staged.sh (expected alongside agent-gate or in resources/templates/)" >&2
  exit 2
}

load_gate_cold() {
  local _bare=0 _c
  if [[ "${1:-}" == "--bare" ]]; then _bare=1; fi
  [[ "$_bare" -eq 1 ]] || load_gate_staged
  [[ "${_LIB_GATE_COLD_LOADED:-0}" == "1" ]] && return 0
  for _c in "$_AG_SELF_DIR/lib-gate-cold.sh" "$_AG_SELF_DIR/../resources/templates/lib-gate-cold.sh" "${repo_root:-.}/${scripts_dir:-scripts}/lib-gate-cold.sh" "${repo_root:-.}/resources/templates/lib-gate-cold.sh"; do
    if [[ -f "$_c" ]]; then
      # shellcheck source=/dev/null
      . "$_c"
      return 0
    fi
  done
  echo "agent-gate: cannot locate lib-gate-cold.sh (expected alongside agent-gate or in resources/templates/)" >&2
  exit 2
}

_AG_CURRENT_STAGE=""
die() {
  local _code4="${1%%:*}" _code="${1%%:*}" _re='^GATE-E[0-9]+$'
  if [[ -n "${_AG_CURRENT_STAGE:-}" && "$_code4" =~ $_re ]]; then
    case "$_code4" in
      GATE-E01|GATE-E76|GATE-E77|GATE-E78|GATE-E79|GATE-E132|GATE-E149|GATE-E155|GATE-E164) ;;
      *)
        local _eff_mode="strict"
        if command -v enforcement_mode >/dev/null 2>&1; then
          _eff_mode=$(enforcement_mode || echo strict)
        fi
        if [[ "$_eff_mode" == "ratchet" ]]; then
          load_gate_staged --quiet || true
          if command -v ratchet_is_legacy >/dev/null 2>&1 && ratchet_is_legacy; then
            _eff_mode="advisory"
          else
            _eff_mode="strict"
          fi
        fi
        if [[ "$_eff_mode" == "advisory" ]]; then
          echo "agent-gate: ADVISORY [downgraded from $_code4] $*" >&2
          if [[ -d ".agent-state" ]]; then
            friction_append "$_code" ADVISORY "$*"
          fi
          exit 0
        fi
        ;;
    esac
  fi
  echo "agent-gate: $*" >&2
  case "$_code4" in
    GATE-E[0-9]*)
      case "$*" in
        *expected:*) : ;;
        *)
          load_gate_staged --quiet || true
          if command -v gate_hint >/dev/null 2>&1; then
            gate_hint "$_code4" >&2
          fi
          ;;
      esac
      ;;
  esac
  if [[ -d ".agent-state" && "$_code" =~ $_re ]]; then
    friction_append "$_code" DIE "$*"
  fi
  exit 2
}

_ag_git_info=$(git rev-parse --show-toplevel --git-path agent-governance/active-change 2>/dev/null) || die "GATE-E01: run inside a Git repository"
repo_root="${_ag_git_info%%$'\n'*}"
active_file="${_ag_git_info#*$'\n'}"
cd "$repo_root"
[[ "$active_file" == /* ]] || active_file="$repo_root/$active_file"

_AG_YML_DOCS="" _AG_YML_SCRIPTS="" _AG_YML_TESTS="" _AG_YML_GITHOOKS=""
_AG_YML_CHANGE_ROOT="" _AG_YML_BUGS_ROOT="" _AG_YML_EXT=""
_AG_YML_ENF_MODE="" _AG_YML_RATCHET_SINCE="" _AG_YML_LOADED=0

_ag_clean_yml_val() {
  local s="$1"
  s="${s%%#*}"
  s="${s// /}"
  s="${s//$'\t'/}"
  s="${s//$'\r'/}"
  s="${s//\"/}"
  s="${s//\'/}"
  _AG_YML_CLEAN="$s"
}

_load_gov_yml() {
  local yf="" line sec="" k v
  _AG_YML_LOADED=1
  if [[ -f ".agent-governance.yml" ]]; then yf=".agent-governance.yml"
  elif [[ -f "$repo_root/.agent-governance.yml" ]]; then yf="$repo_root/.agent-governance.yml"
  else return 0; fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      paths:*)
        k="${line#paths:}"; _ag_clean_yml_val "$k"
        if [[ -z "$_AG_YML_CLEAN" ]]; then sec="paths"; else sec=""; fi
        continue ;;
      enforcement:*)
        k="${line#enforcement:}"; _ag_clean_yml_val "$k"
        if [[ -z "$_AG_YML_CLEAN" ]]; then sec="enforcement"; else sec=""; fi
        continue ;;
      ''|'#'*|' '*|$'\t'*) ;;
      *) sec="" ;;
    esac
    case "$line" in
      *:*) ;;
      *) continue ;;
    esac
    k="${line%%:*}"
    k="${k// /}"; k="${k//$'\t'/}"
    v="${line#*:}"
    if [[ "$sec" == "paths" ]]; then
      case "$k" in
        docs) [[ -z "$_AG_YML_DOCS" ]] && { _ag_clean_yml_val "$v"; _AG_YML_DOCS="$_AG_YML_CLEAN"; } ;;
        scripts) [[ -z "$_AG_YML_SCRIPTS" ]] && { _ag_clean_yml_val "$v"; _AG_YML_SCRIPTS="$_AG_YML_CLEAN"; } ;;
        tests) [[ -z "$_AG_YML_TESTS" ]] && { _ag_clean_yml_val "$v"; _AG_YML_TESTS="$_AG_YML_CLEAN"; } ;;
        githooks) [[ -z "$_AG_YML_GITHOOKS" ]] && { _ag_clean_yml_val "$v"; _AG_YML_GITHOOKS="$_AG_YML_CLEAN"; } ;;
      esac
    elif [[ "$sec" == "enforcement" ]]; then
      case "$k" in
        mode) [[ -z "$_AG_YML_ENF_MODE" ]] && { _ag_clean_yml_val "$v"; _AG_YML_ENF_MODE="$_AG_YML_CLEAN"; } ;;
        ratchet_since) [[ -z "$_AG_YML_RATCHET_SINCE" ]] && { _ag_clean_yml_val "$v"; _AG_YML_RATCHET_SINCE="$_AG_YML_CLEAN"; } ;;
      esac
    fi
    case "$k" in
      change_root) [[ -z "$_AG_YML_CHANGE_ROOT" ]] && { _ag_clean_yml_val "$v"; _AG_YML_CHANGE_ROOT="$_AG_YML_CLEAN"; } ;;
      bugs_root) [[ -z "$_AG_YML_BUGS_ROOT" ]] && { _ag_clean_yml_val "$v"; _AG_YML_BUGS_ROOT="$_AG_YML_CLEAN"; } ;;
      code_extensions) [[ -z "$_AG_YML_EXT" ]] && { _ag_clean_yml_val "$v"; _AG_YML_EXT="$_AG_YML_CLEAN"; } ;;
    esac
  done < "$yf"
}

cfg_path() { # key default
  local k="$1" d="$2" v="" line line_k
  [[ "$_AG_YML_LOADED" -eq 1 ]] || _load_gov_yml
  case "$k" in
    docs) v="$_AG_YML_DOCS" ;;
    scripts) v="$_AG_YML_SCRIPTS" ;;
    tests) v="$_AG_YML_TESTS" ;;
    githooks) v="$_AG_YML_GITHOOKS" ;;
    change_root) v="$_AG_YML_CHANGE_ROOT" ;;
    bugs_root) v="$_AG_YML_BUGS_ROOT" ;;
    code_extensions) v="$_AG_YML_EXT" ;;
    *)
      if [[ -f ".agent-governance.yml" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
          case "$line" in *:*) ;; *) continue ;; esac
          line_k="${line%%:*}"; line_k="${line_k// /}"; line_k="${line_k//$'\t'/}"
          if [[ "$line_k" == "$k" ]]; then
            _ag_clean_yml_val "${line#*:}"
            v="$_AG_YML_CLEAN"
            break
          fi
        done < ".agent-governance.yml"
      fi
      ;;
  esac
  [[ -n "$v" ]] || v="$d"
  printf '%s' "$v"
}

_load_gov_yml
docs_dir="${AGENT_GUARD_DOCS_DIR:-${_AG_YML_DOCS:-docs}}"
scripts_dir="${AGENT_GUARD_SCRIPTS_DIR:-${_AG_YML_SCRIPTS:-scripts}}"
tests_dir="${AGENT_GUARD_TESTS_DIR:-${_AG_YML_TESTS:-tests}}"
githooks_dir="${AGENT_GUARD_GITHOOKS_DIR:-${_AG_YML_GITHOOKS:-.githooks}}"
change_root="${AGENT_GUARD_CHANGE_ROOT:-${_AG_YML_CHANGE_ROOT:-$docs_dir/changes}}"
bugs_root="${AGENT_GUARD_BUGS_ROOT:-${_AG_YML_BUGS_ROOT:-$docs_dir/bugs}}"

_re_escape_var() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//./\\.}"
  s="${s//[/\\[}"
  s="${s//\*/\\*}"
  s="${s//^/\\^}"
  s="${s//$/\\$}"
  _RE_ESC_VAL="$s"
}
re_escape() { _re_escape_var "$1"; printf '%s' "$_RE_ESC_VAL"; }
_re_escape_var "$docs_dir"; docs_re="$_RE_ESC_VAL"
_re_escape_var "$scripts_dir"; scripts_re="$_RE_ESC_VAL"
_re_escape_var "$tests_dir"; tests_re="$_RE_ESC_VAL"
_re_escape_var "$githooks_dir"; githooks_re="$_RE_ESC_VAL"
_re_escape_var "$change_root"; change_root_re="$_RE_ESC_VAL"

enforcement_mode() {
  local m="${AGENT_GUARD_ENFORCEMENT_MODE:-${_AG_YML_ENF_MODE:-}}"
  case "${m:-strict}" in
    strict|ratchet|advisory) printf '%s' "${m:-strict}" ;;
    *) echo "agent-gate: WARN invalid enforcement.mode '$m' — falling back to strict" >&2; printf 'strict' ;;
  esac
}

required_docs=(00-intent.md 00-governance.json 00.5-communication.md 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md)

is_code_path() {
  local path="$1"
  [[ "$path" =~ ^(${docs_re}/|\.github/|\.agent-governance/|README|AGENTS\.md|CLAUDE\.md|GEMINI\.md) ]] && return 1
  [[ "$path" =~ ^(${githooks_re}/|\.agents/|\.claude/|\.cursor/|\.gemini/|\.opencode/|\.agent-state/|\.agent-governance\.yml$|${scripts_re}/agent-gate$|${scripts_re}/lib-json\.sh$|${scripts_re}/lib-gate-staged\.sh$|${scripts_re}/lib-gate-cold\.sh$|${scripts_re}/session-gate\.sh$|${scripts_re}/install-hook-adapter$|${scripts_re}/install-ci-adapter$|${scripts_re}/check-standards-compliance\.sh$|${scripts_re}/stamp-provenance\.sh$|${scripts_re}/generate-reading-pack\.sh$|${scripts_re}/behavior-extract\.sh$|${scripts_re}/lib-suite-tree-fingerprint\.sh$|${scripts_re}/lib-suite-lock\.sh$|${scripts_re}/shard-sum\.sh$|${scripts_re}/evidence-round\.sh$|${tests_re}/run-tests\.sh$|${tests_re}/governance-smoke\.sh$|${tests_re}/audit-docs-consistency\.sh$|${tests_re}/fresh-clone-check\.sh$|${tests_re}/lib/test-harness\.sh$|${tests_re}/suites/suite-01-core\.sh$|${tests_re}/suites/suite-02-install\.sh$|${tests_re}/suites/suite-03-session\.sh$|${tests_re}/suites/suite-04-gates\.sh$|${tests_re}/suites/suite-05-adapter\.sh$|${tests_re}/suites/suite-06-runner\.sh$|${tests_re}/suites/suite-07-adapt\.sh$|${tests_re}/suites/suite-08-infra\.sh$) ]] && return 1
  [[ "$path" =~ \.(c|cc|cpp|cs|go|java|js|jsx|kt|kts|php|py|rb|rs|scala|sh|sql|swift|ts|tsx|vue)$ ]] && return 0
  if [[ "${_AG_EXT_LOADED:-0}" != "1" ]]; then
    local _ag_ext="${_AG_YML_EXT:-}"
    _AG_EXT_RE=""
    if [[ -n "$_ag_ext" && "$_ag_ext" =~ ^[A-Za-z0-9_+]+(,[A-Za-z0-9_+]+)*$ ]]; then
      _AG_EXT_RE="${_ag_ext//,/|}"
      _AG_EXT_RE="${_AG_EXT_RE//+/\\+}"
    fi
    _AG_EXT_LOADED=1
  fi
  if [[ -n "${_AG_EXT_RE:-}" ]] && [[ "$path" =~ \.(${_AG_EXT_RE})$ ]]; then
    return 0
  fi
  return 1
}

prewrite_ledger_append() { # <chg> <file>
  local lg="$repo_root/.agent-state/pre-write-ledger.tsv"
  mkdir -p "$repo_root/.agent-state" 2>/dev/null || return 0
  printf '%s\t%s\t%s\tpass\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$1" "$2" >> "$lg" 2>/dev/null || true
}

active_change() {
  local c=""
  [[ -s "$active_file" ]] && { IFS= read -r c < "$active_file" || true; }
  c="${c//[[:space:]]/}"
  [[ -n "$c" ]] || die "GATE-E43: no active change. Create documents, then run: scripts/agent-gate begin CHG-123"
  printf '%s' "$c"
}

active_change_quiet() {
  [[ -s "$active_file" ]] || return 0
  local c=""
  IFS= read -r c < "$active_file" || true
  printf '%s' "${c//[[:space:]]/}"
}

extract_file_from_hook_input() {
  local input=""
  IFS= read -r -d '' input || true
  if [[ "$input" =~ \"(file_path|path|filePath|target_file)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    local val="${BASH_REMATCH[2]}"
    if [[ "$val" != *\\* ]]; then
      printf '%s\n' "$val"
      return 0
    fi
  fi
  printf '%s' "$input" | sed -nE 's/.*"(file_path|path|filePath|target_file)"[[:space:]]*:[[:space:]]*"([^"\\]+)".*/\2/p' | head -n 1
}

_freeze_abs() { # <path> -> absolute physical path
  local p="$1" tail="" anc
  case "$p" in
    /*) ;;
    *) p="$(pwd -P 2>/dev/null || pwd)/$p" ;;
  esac
  while :; do
    if anc=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P); then
      printf '%s/%s%s\n' "$anc" "$(basename "$p")" "$tail"
      return 0
    fi
    tail="/$(basename "$p")$tail"
    p=$(dirname "$p")
    if [[ "$p" == "/" || -z "$p" ]]; then printf '/%s\n' "${tail#/}"; return 0; fi
  done
}

_freeze_norm() { # <absolute path> -> normalized absolute path
  local _p="$1" _out="" _seg
  local IFS=/
  for _seg in $_p; do
    case "$_seg" in
      ''|.) continue ;;
      ..) [[ -n "$_out" ]] && _out="${_out%/*}"; continue ;;
    esac
    _out="$_out/$_seg"
  done
  printf '%s\n' "${_out:-/}"
}

validate_freeze_window() {
  local lock="$repo_root/.agent-state/evidence-round.lock"
  [[ -e "$lock" && -f "$lock" ]] || return 0
  local f="$1" rel pid lstart cur _chg _round _round_tree
  rel=$(_freeze_norm "$(_freeze_abs "$f")")
  case "$rel" in
    "$repo_root"/*) rel="${rel#"$repo_root"/}" ;;
    /*) return 0 ;;
  esac
  case "$rel" in
    README.md|README.zh-CN.md|tests/.audit-baseline|tests/.suite-baseline) return 0 ;;
    .agent-state|.agent-state/*) return 0 ;;
  esac
  git -C "$repo_root" check-ignore -q -- "$rel" 2>/dev/null && return 0
  pid=$(sed -n 's/^pid=//p' "$lock" 2>/dev/null | head -1)
  lstart=$(sed -n 's/^lstart=//p' "$lock" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [[ -n "$pid" ]] || return 0
  cur=$(LC_ALL=C ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
  [[ -n "$cur" ]] || return 0
  { [[ -z "$lstart" ]] || [[ "$cur" == "$lstart" ]]; } || return 0
  if [[ "${AGENT_GUARD_ALLOW_FREEZE_WRITE:-0}" == "1" ]]; then
    echo "agent-gate: WARN — GATE-E156 bypassed (AGENT_GUARD_ALLOW_FREEZE_WRITE=1): $rel lands in a running round; that round will report itself INVALID" >&2
    return 0
  fi
  _chg=$(sed -n 's/^chg=//p' "$lock" 2>/dev/null | head -1)
  _round=$(sed -n 's/^round=//p' "$lock" 2>/dev/null | head -1)
  _round_tree=$(sed -n 's/^tree_sha=//p' "$lock" 2>/dev/null | head -1)
  die "GATE-E156: evidence round ${_chg:-?} round ${_round:-?} is running (pid $pid, tree ${_round_tree:-?}) — writing $rel would void it; expected: finish the round first, then edit, or stop the round; allowed: AGENT_GUARD_ALLOW_FREEZE_WRITE=1 records the round as INVALID instead of blocking; fix: wait for the round to finish, re-run it after the edit; ref: CHG-135 REQ-1350 / §2.13.5"
}

runtime_status() {
  local jmode=0 adapter="" out rt="unknown" fam="unknown" layers="" enforce="handshake" hand="missing" mid mwin ac_st="" emode="strict" c
  if [[ "${1:-}" == "--json" ]]; then
    jmode=1
    emode=$(enforcement_mode 2>/dev/null || echo strict)
  else
    emode=$(enforcement_mode || echo strict)
  fi
  for c in "$repo_root/scripts/install-hook-adapter" "$repo_root/scripts/install-hook-adapter.sh"; do
    [[ -x "$c" ]] && adapter="$c" && break
  done
  if [[ -n "$adapter" ]]; then
    out=$( cd "$repo_root" && "$adapter" --detect 2>/dev/null || true )
    rt=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*runtime:[[:space:]]*\([^ ]*\).*/\1/p' | head -1)
    fam=$(printf '%s\n' "$out" | sed -n 's/.*family:[[:space:]]*\([^)]*\)).*/\1/p' | head -1)
    layers=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*effective layers:[[:space:]]*//p' | head -1)
  fi
  [[ -n "$rt" ]] || rt="${AGENT_RUNTIME:-unknown}"
  [[ -n "$fam" ]] || fam="unknown"
  [[ "$rt" != "unknown" && -n "$layers" ]] && enforce="hook"
  if ls "$repo_root/.agent-state/runtime/"*.json >/dev/null 2>&1; then hand="present"; fi
  mid="unknown"; mwin=""
  if [[ -s "$repo_root/.agent-state/model-profile.json" ]]; then
    mid=$(sed -n 's/.*"model_id":"\([^"]*\)".*/\1/p' "$repo_root/.agent-state/model-profile.json" | head -1)
    mwin=$(sed -n 's/.*"context_window":\([0-9]*\).*/\1/p' "$repo_root/.agent-state/model-profile.json" | head -1)
  fi
  if [[ "$jmode" -eq 1 ]]; then
    ac_st=$(active_change_quiet)
    printf '{"runtime":"%s","family":"%s","enforcement":"%s","enforcement_mode":"%s","layers":"%s","handshake":"%s","model":"%s","window":"%s","active_change":"%s"}\n' \
      "$(json_escape "$rt")" "$(json_escape "$fam")" "$(json_escape "$enforce")" "$(json_escape "$emode")" "$(json_escape "${layers:-none}")" \
      "$(json_escape "$hand")" "$(json_escape "${mid:-unknown}")" "$(json_escape "${mwin:-unknown}")" "$(json_escape "${ac_st:-}")"
    return 0
  fi
  echo "status: runtime=$rt family=$fam enforcement=$enforce enforcement_mode=$emode layers=${layers:-none}"
  echo "status: handshake=$hand model=${mid:-unknown} window=${mwin:-unknown}"
}

command="${1:-help}"
unset AGENT_GUARD_DIM_PROBE 2>/dev/null || true
case "$command" in
  end)           rm -f "$active_file"; echo "agent-gate: active change cleared" ;;
  status)        runtime_status "${2:-}" ;;
  help|--help|-h) load_gate_cold --bare; print_help_cmd ;;
  review-models) shift; load_gate_cold; review_models_cmd "$@" ;;
  record-red)    shift; load_gate_cold; record_red_cmd "$@" ;;
  start)         shift; load_gate_cold; start_cmd "$@" ;;
  advance)       shift; load_gate_cold; advance_cmd "$@" ;;
  next)          shift; load_gate_cold; next_cmd "$@" ;;
  fix)           shift; load_gate_cold; fix_cmd "$@" ;;
  metrics)       shift; load_gate_cold; emit_metrics "$@" ;;
  doctor)        shift; load_gate_cold; doctor_cmd "$@" ;;
  --stage)
    [[ $# -ge 2 && -n "${2:-}" ]] || { load_gate_staged; unknown_stage "${2:-}"; }
    if [[ "$2" == "pre-write" ]]; then
      shift 2; _AG_CURRENT_STAGE="pre-write"; file=""
      if [[ "${1:-}" == "--file" ]]; then file="${2:-}"; else file=$(extract_file_from_hook_input); fi
      [[ -n "$file" ]] || die "GATE-E76: cannot determine the target file from hook input"
      validate_freeze_window "$file"
      if is_code_path "$file"; then
        active_change >/dev/null
        load_gate_staged
        validate_active_change
        prewrite_ledger_append "$(active_change_quiet)" "$file"
      fi
    else
      load_gate_staged
      gate_staged_dispatch --stage "${@:2}"
    fi ;;
  *) load_gate_staged; gate_staged_dispatch "$@" ;;
esac
