#!/usr/bin/env bash
# lib-gate-cold.sh — cold-path subcommand handlers lazy-loaded by agent-gate (ITEM-45)
if [[ "${_LIB_GATE_COLD_LOADED:-0}" != "1" ]]; then
_LIB_GATE_COLD_LOADED=1

process_honesty_summary() { # <chg> -> P3 honesty summary line (ITEM-23)
  local id="$1" d lg rf redf ac_ok="no" docs_ok="no" pw_ok="no" red_ok="no" retries=0
  d=$(change_dir "$id" 2>/dev/null || true)
  rf=$(stage_receipt_file "$id")
  [[ -s "$rf" ]] && grep -qE $'\tbegin\t' "$rf" 2>/dev/null && ac_ok="yes"
  if [[ -n "$d" && -f "$d/00-intent.md" ]]; then
    if git -C "$repo_root" check-ignore -q "$d/00-intent.md" 2>/dev/null; then
      docs_ok="gitignored"
    elif git -C "$repo_root" cat-file -e "HEAD:$d/00-intent.md" 2>/dev/null; then
      docs_ok="yes"
    fi
  fi
  lg="$repo_root/.agent-state/pre-write-ledger.tsv"
  if [[ -s "$lg" ]] && awk -F'\t' -v id="$id" '$2==id && $4=="pass"{f=1;exit} END{exit !f}' "$lg" 2>/dev/null; then
    pw_ok="yes"
  fi
  redf=$(git -C "$repo_root" rev-parse --git-path "agent-governance/red-receipts/${id}.json" 2>/dev/null || true)
  [[ -n "$redf" && "$redf" != /* ]] && redf="$repo_root/$redf"
  [[ -n "$redf" && -s "$redf" ]] && grep -qE '"exit_code":[1-9]' "$redf" 2>/dev/null && red_ok="yes"
  if [[ -s "$repo_root/.agent-state/pre-commit-streak.tsv" ]]; then
    retries=$(awk -F'\t' -v id="$id" '$1==id{print $2; exit}' "$repo_root/.agent-state/pre-commit-streak.tsv" 2>/dev/null || echo 0)
    [[ "$retries" =~ ^[0-9]+$ ]] || retries=0
  fi
  printf '过程诚实度摘要：active_change_before_code=%s | docs_committed_before_code=%s | pre_write_hook_observed=%s | red_receipt_verified=%s | gate_probe_retries_before_pass=%s' \
    "$ac_ok" "$docs_ok" "$pw_ok" "$red_ok" "$retries"
}

_cold_sha256() { # <file>
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else cksum "$1" | awk '{print $1"-"$2}'
  fi
}

_cold_str_sha256() { # <string>
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | awk '{print $1}'
  else printf '%s' "$1" | cksum | awk '{print $1"-"$2}'
  fi
}

_cold_norm_cmd() { # <cmd> -> trimmed single-spaced command
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//;s/[[:space:]]+/ /g'
}

_cold_layer_rank() { # <unit|api|e2e|manual> -> 1|2|3|0
  case "$1" in
    unit) echo 1 ;;
    api)  echo 2 ;;
    e2e|manual) echo 3 ;;
    *) echo 0 ;;
  esac
}

_cold_diag_section() { # <01-diagnosis.md> <bug-id> -> prints relevant section
  local f="$1" bid="$2" re_bid
  [[ -s "$f" ]] || return 0
  re_bid=$(printf '%s' "$bid" | sed 's/[.[\*^$]/\\&/g')
  if [[ "$(basename "$(dirname "$f")")" =~ ^BATCH- ]] && grep -qE "^##[[:space:]]+${re_bid}([[:space:]]|\$)" "$f" 2>/dev/null; then
    awk -v re="^##[[:space:]]+${re_bid}([[:space:]]|$)" '
      $0 ~ re { on=1; print; next }
      on && /^##[[:space:]]/ { exit }
      on { print }
    ' "$f" 2>/dev/null
  else
    cat "$f"
  fi
}

_cold_diag_field() { # <text> <label> -> trimmed cell value
  local txt="$1" lbl="$2"
  printf '%s\n' "$txt" | awk -F'|' -v k="$lbl" '
    /^[[:space:]]*\|/ {
      c2=$2; gsub(/<!--[^>]*-->/,"",c2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",c2)
      if (c2 == k) {
        c3=$3; gsub(/<!--[^>]*-->/,"",c3); gsub(/^[[:space:]]+|[[:space:]]+$/,"",c3)
        print c3; exit
      }
    }' 2>/dev/null || true
}

classify_red_output() { # <rc> <outfile> -> red-assertion | red-error | unclassified
  local rc="$1" outf="$2" custom_re=""
  if [[ -f "$repo_root/.agent-governance.yml" ]]; then
    custom_re=$(sed -nE 's/^[[:space:]]*red_classifier:[[:space:]]*//p' "$repo_root/.agent-governance.yml" 2>/dev/null | head -1 | sed -E 's/[[:space:]]*#.*$//;s/^[[:space:]]+//;s/[[:space:]]+$//;s/^["'\'']//;s/["'\'']$//' || true)
  fi
  if [[ "$rc" -eq 126 || "$rc" -eq 127 ]]; then
    echo "red-error"; return 0
  fi
  if grep -qiE 'command not found|No such file|ModuleNotFoundError|ImportError|SyntaxError|Cannot find module|collected 0 items|no tests ran' "$outf" 2>/dev/null; then
    echo "red-error"; return 0
  fi
  if [[ -n "$custom_re" ]] && grep -qE "$custom_re" "$outf" 2>/dev/null; then
    echo "red-assertion"; return 0
  fi
  if grep -qE 'FAIL|FAILED|AssertionError|expected|not ok|Failures:[[:space:]]*[1-9]|[1-9][0-9]*[[:space:]]+failed' "$outf" 2>/dev/null; then
    echo "red-assertion"; return 0
  fi
  echo "unclassified"
}

record_red_cmd() { # <chg> [--layer L] [--target-tests T] [--accept-unclassified R] -- <cmd...> — ITEM-21 / E-1 / E-4
  local id="" layer="unit" target_tests="" accept_reason="" cmd="" rc=0 rf d ts sha f05
  local tmpout out_sha out_tail cls
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --) shift; break ;;
      --layer)
        [[ -n "${2:-}" ]] || { echo "agent-gate: record-red --layer requires unit|api|e2e|manual" >&2; exit 2; }
        layer="$2"; shift 2 ;;
      --target-tests)
        [[ -n "${2:-}" ]] || { echo "agent-gate: record-red --target-tests requires a value" >&2; exit 2; }
        target_tests="$2"; shift 2 ;;
      --accept-unclassified)
        [[ -n "${2:-}" ]] || { echo "agent-gate: record-red --accept-unclassified requires a reason" >&2; exit 2; }
        accept_reason="$2"; shift 2 ;;
      -*) echo "agent-gate: record-red unknown option '$1'" >&2; exit 2 ;;
      *)
        if [[ -z "$id" ]]; then id="$1"; shift
        else break; fi ;;
    esac
  done
  case "$layer" in unit|api|e2e|manual) ;; *) echo "agent-gate: record-red invalid --layer '$layer' (expected unit|api|e2e|manual)" >&2; exit 2 ;; esac
  cmd="$*"
  if [[ -z "$id" || -z "$cmd" ]] || [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    echo "agent-gate: usage: scripts/agent-gate record-red <change-id> [--layer unit|api|e2e|manual] [--target-tests <spec>] [--accept-unclassified <reason>] -- <failing-test-cmd>" >&2; exit 2
  fi
  d=$(change_dir "$id" 2>/dev/null || true)
  [[ -d "$d" ]] || is_change_card "$id" || { echo "agent-gate: record-red unknown change: $id" >&2; exit 2; }

  # E-4: verify red layer >= bug_ref discovery layer when declared in 01-diagnosis.md
  if [[ -d "$d" && -s "$d/00-governance.json" ]]; then
    local rec brefs bref bgdir diag_txt d_layer_raw d_layer l_rank d_rank
    rec=$(gov_record "$d/00-governance.json" "$id" 2>/dev/null || true)
    if [[ -n "$rec" ]] && grep -q '"bug_ref"' <<< "$rec"; then
      brefs=$(json_field_values "$rec" bug_ref 2>/dev/null || true)
      l_rank=$(_cold_layer_rank "$layer")
      for bref in $brefs; do
        bgdir=$(bug_group_dir "$bref" 2>/dev/null || true)
        [[ -n "$bgdir" && -s "$bgdir/01-diagnosis.md" ]] || continue
        diag_txt=$(_cold_diag_section "$bgdir/01-diagnosis.md" "$bref")
        d_layer_raw=$(_cold_diag_field "$diag_txt" "发现层")
        d_layer=$(printf '%s' "$d_layer_raw" | tr -d '`' | sed -E 's/^[[:space:]]*([A-Za-z0-9_-]+).*/\1/' | tr '[:upper:]' '[:lower:]')
        d_rank=$(_cold_layer_rank "$d_layer")
        if [[ "$d_rank" -gt 0 && "$l_rank" -lt "$d_rank" ]]; then
          echo "agent-gate: record-red refused (E-4) — --layer '$layer' (rank $l_rank) is lower than discovery layer '$d_layer' (rank $d_rank) in $bref" >&2
          exit 2
        fi
      done
    fi
  fi

  tmpout=$(mktemp "${TMPDIR:-/tmp}/ag-red.XXXXXX")
  if [[ $# -eq 1 ]]; then
    bash -lc "$1" >"$tmpout" 2>&1 || rc=$?
  else
    "$@" >"$tmpout" 2>&1 || rc=$?
  fi
  out_sha=$(_cold_sha256 "$tmpout")
  out_tail=$(tail -n 20 "$tmpout" 2>/dev/null | tr '\t\r\n' '   ' | cut -c1-400 || true)
  cls=$(classify_red_output "$rc" "$tmpout")
  rm -f "$tmpout"

  if [[ "$rc" -eq 0 ]]; then
    echo "agent-gate: record-red refused — command exited 0 (a red-first receipt requires a failing test): $cmd" >&2; exit 2
  fi
  if [[ "$cls" == "red-error" ]]; then
    echo "agent-gate: record-red refused (class=red-error, rc=$rc) — infrastructure/syntax/command error is not a test failure: ${out_tail:-$cmd}" >&2; exit 2
  fi
  if [[ "$cls" == "unclassified" && -z "$accept_reason" ]]; then
    echo "agent-gate: record-red refused (class=unclassified, rc=$rc) — output matched no assertion signature; fix test output or pass --accept-unclassified <reason>" >&2; exit 2
  fi
  if [[ "$cls" == "unclassified" ]]; then
    mkdir -p "$repo_root/.agent-state" 2>/dev/null || true
    friction_append RED_UNCLASSIFIED ADVISORY "$id: $accept_reason ($cmd)"
  fi

  rf=$(git -C "$repo_root" rev-parse --git-path "agent-governance/red-receipts/${id}.json" 2>/dev/null || true)
  [[ -n "$rf" ]] || rf="$repo_root/.git/agent-governance/red-receipts/${id}.json"
  [[ "$rf" != /* ]] && rf="$repo_root/$rf"
  mkdir -p "$(dirname "$rf")" 2>/dev/null || { echo "agent-gate: record-red cannot create receipt dir" >&2; exit 2; }
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
  sha=$(tracked_tree_sha 2>/dev/null || echo unknown)
  local ncmd ncmd_sha
  ncmd=$(_cold_norm_cmd "$cmd")
  ncmd_sha=$(_cold_str_sha256 "$ncmd")
  printf '{"change_id":"%s","cmd":"%s","norm_cmd":"%s","norm_cmd_sha":"%s","exit_code":%s,"class":"%s","layer":"%s","target_tests":"%s","output_sha":"%s","output_tail":"%s","unclassified_reason":"%s","recorded_at":"%s","tree_sha":"%s"}\n' \
    "$(json_escape "$id")" "$(json_escape "$cmd")" "$(json_escape "$ncmd")" "$(json_escape "$ncmd_sha")" "$rc" \
    "$(json_escape "$cls")" "$(json_escape "$layer")" "$(json_escape "$target_tests")" \
    "$(json_escape "$out_sha")" "$(json_escape "$out_tail")" "$(json_escape "$accept_reason")" \
    "$ts" "${sha:-unknown}" > "$rf"
  f05="$d/05-test-results.md"
  if [[ -d "$d" && -f "$f05" ]] && ! grep -qE '^[[:space:]]*red_repro:' "$f05" 2>/dev/null; then
    printf '\nred_repro: %s -> FAIL rc=%s (%s/%s) @ %s\n' "$cmd" "$rc" "$cls" "$layer" "$ts" >> "$f05"
  fi
  echo "agent-gate: red receipt recorded ($id rc=$rc class=$cls layer=$layer -> $rf)"
}

record_green_cmd() { # <chg> -- <cmd...> — E-2 green receipt verification
  local id="${1:-}" cmd="" rc=0 rf gf d ts sha f05 red_rec red_cmd red_tree red_cls
  local ncmd red_ncmd red_ncmd_sha ncmd_sha tmpout out_sha
  shift || true
  [[ "${1:-}" == "--" ]] && shift
  cmd="$*"
  if [[ -z "$id" || -z "$cmd" ]] || [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    echo "agent-gate: usage: scripts/agent-gate record-green <change-id> -- <passing-test-cmd>" >&2; exit 2
  fi
  d=$(change_dir "$id" 2>/dev/null || true)
  [[ -d "$d" ]] || is_change_card "$id" || { echo "agent-gate: record-green unknown change: $id" >&2; exit 2; }
  rf=$(git -C "$repo_root" rev-parse --git-path "agent-governance/red-receipts/${id}.json" 2>/dev/null || true)
  [[ -n "$rf" ]] || rf="$repo_root/.git/agent-governance/red-receipts/${id}.json"
  [[ "$rf" != /* ]] && rf="$repo_root/$rf"
  [[ -s "$rf" ]] || { echo "agent-gate: record-green refused — no red receipt found for $id (run record-red first)" >&2; exit 2; }

  red_rec=$(cat "$rf" 2>/dev/null || true)
  red_cmd=$(json_field "$red_rec" cmd)
  red_ncmd_sha=$(json_field "$red_rec" norm_cmd_sha)
  red_tree=$(json_field "$red_rec" tree_sha)
  red_cls=$(json_field "$red_rec" class)
  if [[ "$red_cls" == "red-error" ]]; then
    echo "agent-gate: record-green refused — red receipt class is red-error" >&2; exit 2
  fi
  ncmd=$(_cold_norm_cmd "$cmd")
  ncmd_sha=$(_cold_str_sha256 "$ncmd")
  if [[ -n "$red_ncmd_sha" ]]; then
    if [[ "$ncmd_sha" != "$red_ncmd_sha" ]]; then
      echo "agent-gate: record-green refused — command mismatch (red_sha='$red_ncmd_sha', green_sha='$ncmd_sha')" >&2; exit 2
    fi
  else
    red_ncmd=$(_cold_norm_cmd "$red_cmd")
    if [[ "$ncmd" != "$red_ncmd" ]]; then
      echo "agent-gate: record-green refused — command mismatch (red='$red_ncmd', green='$ncmd')" >&2; exit 2
    fi
  fi

  sha=$(tracked_tree_sha 2>/dev/null || echo unknown)
  if [[ -n "$red_tree" && "$red_tree" != "unknown" && "$sha" == "$red_tree" ]]; then
    echo "agent-gate: record-green refused — tracked_tree_sha ($sha) is unchanged since red receipt (cannot claim green without code/test change)" >&2; exit 2
  fi

  tmpout=$(mktemp "${TMPDIR:-/tmp}/ag-green.XXXXXX")
  if [[ $# -eq 1 ]]; then
    bash -lc "$1" >"$tmpout" 2>&1 || rc=$?
  else
    "$@" >"$tmpout" 2>&1 || rc=$?
  fi
  out_sha=$(_cold_sha256 "$tmpout")
  rm -f "$tmpout"
  if [[ "$rc" -ne 0 ]]; then
    echo "agent-gate: record-green refused — command exited $rc (green receipt requires rc=0): $cmd" >&2; exit 2
  fi

  gf=$(git -C "$repo_root" rev-parse --git-path "agent-governance/green-receipts/${id}.json" 2>/dev/null || true)
  [[ -n "$gf" ]] || gf="$repo_root/.git/agent-governance/green-receipts/${id}.json"
  [[ "$gf" != /* ]] && gf="$repo_root/$gf"
  mkdir -p "$(dirname "$gf")" 2>/dev/null || { echo "agent-gate: record-green cannot create receipt dir" >&2; exit 2; }
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
  printf '{"change_id":"%s","cmd":"%s","norm_cmd":"%s","exit_code":0,"recorded_at":"%s","tree_sha":"%s","red_tree_sha":"%s","output_sha":"%s"}\n' \
    "$(json_escape "$id")" "$(json_escape "$cmd")" "$(json_escape "$ncmd")" "$ts" \
    "${sha:-unknown}" "${red_tree:-unknown}" "$(json_escape "$out_sha")" > "$gf"
  f05="$d/05-test-results.md"
  if [[ -d "$d" && -f "$f05" ]] && ! grep -qE '^[[:space:]]*green_after:' "$f05" 2>/dev/null; then
    printf '\ngreen_after: %s -> PASS rc=0 @ %s\n' "$cmd" "$ts" >> "$f05"
  fi
  echo "agent-gate: green receipt recorded ($id rc=0 -> $gf)"
}

escape_cmd() { # <BUG-id> --should-catch <layer> — E-6 post-claim defect escape registration
  local bug_id="" should_catch="" bgdir diagf sec_txt rel_land reg_ref="" evalf tmpf
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --should-catch)
        [[ -n "${2:-}" ]] || { echo "agent-gate: escape --should-catch requires a layer" >&2; exit 2; }
        should_catch="$2"; shift 2 ;;
      -*) echo "agent-gate: escape unknown option '$1'" >&2; exit 2 ;;
      *)
        [[ -z "$bug_id" ]] || { echo "agent-gate: escape unexpected argument '$1'" >&2; exit 2; }
        bug_id="$1"; shift ;;
    esac
  done
  case "$should_catch" in
    需求|设计|编码前置|测试|门禁|运行监控|无) ;;
    *) echo "agent-gate: usage: scripts/agent-gate escape <BUG-id> --should-catch <需求|设计|编码前置|测试|门禁|运行监控|无>" >&2; exit 2 ;;
  esac
  if [[ -z "$bug_id" ]] || [[ ! "$bug_id" =~ ^BUG-[A-Za-z0-9._-]+$ ]]; then
    echo "agent-gate: escape invalid BUG-id '$bug_id'" >&2; exit 2
  fi
  bgdir=$(bug_group_dir "$bug_id" 2>/dev/null || true)
  [[ -n "$bgdir" && -s "$bgdir/01-diagnosis.md" ]] || { echo "agent-gate: escape defect group not found for $bug_id" >&2; exit 2; }
  diagf="$bgdir/01-diagnosis.md"
  sec_txt=$(_cold_diag_section "$diagf" "$bug_id")
  if ! grep -qE 'escaped_after_claim:[[:space:]]*yes' <<< "$sec_txt" 2>/dev/null; then
    local re_bugid
    re_bugid=$(printf '%s' "$bug_id" | sed 's/[.[\*^$()+?{}|]/\\&/g')
    if [[ "$(basename "$bgdir")" =~ ^BATCH- ]] && grep -qE "^##[[:space:]]+${re_bugid}([[:space:]]|\$)" "$diagf" 2>/dev/null; then
      tmpf=$(mktemp "${TMPDIR:-/tmp}/ag-esc.XXXXXX")
      awk -v bid="$re_bugid" -v sc="$should_catch" '
        $0 ~ ("^##[[:space:]]+" bid "([[:space:]]|$)") { in_sec=1 }
        in_sec && /^##[[:space:]]/ && $0 !~ ("^##[[:space:]]+" bid "([[:space:]]|$)") && !done {
          print "- escaped_after_claim: yes"
          print "- **应捕获层（escape）**：" sc
          done=1; in_sec=0
        }
        { print }
        END {
          if (!done) {
            print "- escaped_after_claim: yes"
            print "- **应捕获层（escape）**：" sc
          }
        }' "$diagf" > "$tmpf" && mv "$tmpf" "$diagf"
    else
      printf '\n- escaped_after_claim: yes\n- **应捕获层（escape）**：%s\n' "$should_catch" >> "$diagf"
    fi
  fi
  if [[ -s "$bgdir/04-matrix.md" ]]; then
    reg_ref=$(_cold_diag_section "$bgdir/04-matrix.md" "$bug_id" | grep -oE 'TC-[A-Za-z0-9_-]+' | head -1 || true)
  fi
  rel_land="${bgdir#"$repo_root"/}"
  evalf="$repo_root/.agent-state/eval-cases.tsv"
  mkdir -p "$(dirname "$evalf")" 2>/dev/null || true
  [[ -s "$evalf" ]] || printf 'case_id\tsource\tbug_id\tcaptured_layer\tlanding\tregression_ref\n' > "$evalf"
  tmpf=$(mktemp "${TMPDIR:-/tmp}/ag-eval.XXXXXX")
  awk -F'\t' -v OFS='\t' -v cid="EC-${bug_id}" -v bid="$bug_id" -v layer="$should_catch" -v land="$rel_land" -v ref="$reg_ref" '
    NR==1 { print; next }
    $1==cid { print cid, "escape", bid, layer, land, ref; seen=1; next }
    { print }
    END { if (!seen) print cid, "escape", bid, layer, land, ref }
  ' "$evalf" > "$tmpf" && mv "$tmpf" "$evalf"
  echo "agent-gate: escape recorded ($bug_id -> should_catch=$should_catch, $evalf)"
}

start_cmd() { # <chg> [--risk L0|L1|L2|L3] — ITEM-25
  local id="" risk="L1" d nc="" _self_bin=""
  _self_bin="${_AG_SELF_BIN:-$_AG_SELF_DIR/agent-gate.sh}"
  [[ -f "$repo_root/$scripts_dir/agent-gate" ]] && _self_bin="$repo_root/$scripts_dir/agent-gate"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --risk)
        [[ -n "${2:-}" ]] || { echo "agent-gate: start --risk needs L0|L1|L2|L3" >&2; exit 2; }
        risk="$2"; shift 2 ;;
      L0|L1|L2|L3) risk="$1"; shift ;;
      -*) echo "agent-gate: start unknown option '$1'" >&2; exit 2 ;;
      *)
        [[ -z "$id" ]] || { echo "agent-gate: start unexpected argument '$1'" >&2; exit 2; }
        id="$1"; shift ;;
    esac
  done
  case "$risk" in L0|L1|L2|L3) ;; *) echo "agent-gate: start invalid risk '$risk'" >&2; exit 2 ;; esac
  if [[ -z "$id" ]] || [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    echo "agent-gate: usage: scripts/agent-gate start <change-id> [--risk L0|L1|L2|L3]" >&2; exit 2
  fi
  d=$(change_dir "$id")
  if [[ ! -d "$d" ]] && ! is_change_card "$id"; then
    for nc in "$repo_root/$scripts_dir/new-change" "$repo_root/scripts/new-change" "$repo_root/scripts/new-change.sh" "$repo_root/resources/templates/new-change.sh"; do
      if [[ -f "$nc" ]]; then
        bash "$nc" "$id" --risk "$risk" || exit $?
        break
      fi
    done
    d=$(change_dir "$id")
    if [[ ! -d "$d" ]] && ! is_change_card "$id"; then
      scaffold_change "$id" "$risk"
    fi
  fi
  bash "$_self_bin" session-start >/dev/null 2>&1 || true
  if bash "$_self_bin" begin "$id" >/dev/null 2>&1; then
    echo "agent-gate: start complete ($id risk=$risk active)"
  else
    echo "agent-gate: start initialized ($id risk=$risk -> $d); fill entry artifacts then run: scripts/agent-gate begin $id"
  fi
}

advance_cmd() { # [chg] — ITEM-26
  local id="${1:-}" rf _self_bin="" cur_ac=""
  _self_bin="${_AG_SELF_BIN:-$_AG_SELF_DIR/agent-gate.sh}"
  [[ -f "$repo_root/$scripts_dir/agent-gate" ]] && _self_bin="$repo_root/$scripts_dir/agent-gate"
  [[ -n "$id" ]] || id=$(active_change_quiet)
  [[ -n "$id" ]] || { echo "agent-gate: advance needs a change id or active change" >&2; exit 2; }
  rf=$(stage_receipt_file "$id")
  cur_ac=$(active_change_quiet)
  if is_change_card "$id"; then
    if [[ "$cur_ac" != "$id" || ! -s "$rf" ]] || ! grep -qE $'\tbegin\t' "$rf" 2>/dev/null; then
      echo "agent-gate: advancing $id -> begin (change-card)"
      bash "$_self_bin" begin "$id"; return $?
    fi
    echo "agent-gate: advancing $id -> preflight (change-card)"
    bash "$_self_bin" preflight "$id"; return $?
  fi
  if [[ "$cur_ac" != "$id" || ! -s "$rf" ]] || ! grep -qE $'\tbegin\t' "$rf" 2>/dev/null; then
    echo "agent-gate: advancing $id -> begin"
    bash "$_self_bin" begin "$id"
  elif ! grep -qE $'\tspec\t' "$rf" 2>/dev/null; then
    echo "agent-gate: advancing $id -> spec"
    bash "$_self_bin" --stage spec
  elif ! grep -qE $'\tdesign\t' "$rf" 2>/dev/null; then
    echo "agent-gate: advancing $id -> design"
    bash "$_self_bin" --stage design
  elif ! grep -qE $'\ttestplan\t' "$rf" 2>/dev/null; then
    echo "agent-gate: advancing $id -> testplan"
    bash "$_self_bin" --stage testplan
  else
    echo "agent-gate: advancing $id -> preflight"
    bash "$_self_bin" preflight "$id"
  fi
}

next_cmd() { # [chg] [--json] — ITEM-27 read-only wizard
  local id="" jmode=0 cur_ac rf cur_stage="none" next_cmd_str="" d _blk_raw="" _ln
  local -a blockers
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) jmode=1 ;;
      -*) echo "agent-gate: next unknown option '$1'" >&2; exit 2 ;;
      *) id="$1" ;;
    esac
    shift
  done
  [[ -n "$id" ]] || id=$(active_change_quiet)
  cur_ac=$(active_change_quiet)
  if [[ -z "$id" ]]; then
    cur_stage="uninitialized"
    next_cmd_str="scripts/agent-gate start CHG-xxx --risk L1"
    blockers+=("no active change pointer")
  elif is_change_card "$id"; then
    rf=$(stage_receipt_file "$id")
    if [[ "$cur_ac" != "$id" || ! -s "$rf" ]] || ! grep -qE $'\tbegin\t' "$rf" 2>/dev/null; then
      cur_stage="entry"
      next_cmd_str="scripts/agent-gate begin $id"
    else
      cur_stage="ready_for_stop"
      next_cmd_str="scripts/agent-gate --stage stop"
    fi
    _blk_raw=$( ( validate_change_card "$id" ) 2>&1 ) || {
      while IFS= read -r _ln; do [[ -n "$_ln" ]] && blockers+=("$_ln"); done <<< "$_blk_raw"
    }
  else
    d=$(change_dir "$id" 2>/dev/null || true)
    if [[ ! -d "$d" ]]; then
      cur_stage="missing"
      next_cmd_str="scripts/agent-gate start $id --risk L1"
      blockers+=("missing change directory $d")
    else
      rf=$(stage_receipt_file "$id")
      if [[ "$cur_ac" != "$id" || ! -s "$rf" ]] || ! grep -qE $'\tbegin\t' "$rf" 2>/dev/null; then
        cur_stage="entry"
        next_cmd_str="scripts/agent-gate begin $id"
      elif ! grep -qE $'\tspec\t' "$rf" 2>/dev/null; then
        cur_stage="spec"
        next_cmd_str="scripts/agent-gate --stage spec"
      elif ! grep -qE $'\tdesign\t' "$rf" 2>/dev/null; then
        cur_stage="design"
        next_cmd_str="scripts/agent-gate --stage design"
      elif ! grep -qE $'\ttestplan\t' "$rf" 2>/dev/null; then
        cur_stage="testplan"
        next_cmd_str="scripts/agent-gate --stage testplan"
      elif [[ ! -s "$d/05-test-results.md" || ! -s "$d/09-changelog.md" ]]; then
        cur_stage="implementation"
        next_cmd_str="scripts/agent-gate --stage staged"
      else
        cur_stage="delivery"
        next_cmd_str="scripts/agent-gate --stage stop"
      fi
      _blk_raw=$( ( die() { printf '%s\n' "$*"; }; required_docs_present "$id" entry; validate_governance_state "$id" ) 2>&1 || true )
      while IFS= read -r _ln; do
        [[ "$_ln" == *GATE-E[0-9]* ]] && blockers+=("$_ln")
      done <<< "$_blk_raw"
    fi
  fi
  if [[ "$jmode" -eq 1 ]]; then
    printf '{"change_id":"%s","current_stage":"%s","next_command":"%s","blockers":%s}\n' \
      "$(json_escape "${id:-none}")" "$(json_escape "$cur_stage")" "$(json_escape "$next_cmd_str")" \
      "$(djson_arr ${blockers[@]+"${blockers[@]}"})"
  else
    echo "next: change=${id:-none} stage=$cur_stage next_command='$next_cmd_str'"
    if [[ -n "${blockers[*]+x}" ]]; then
      local _b
      for _b in "${blockers[@]}"; do echo "  blocker: $_b"; done
    fi
  fi
}

fix_cmd() { # [chg] — ITEM-28 mechanical auto-fix
  local id="${1:-}" d fixed=0 req sp="" p
  [[ -n "$id" ]] || id=$(active_change_quiet)
  [[ -n "$id" ]] || { echo "agent-gate: fix needs a change id or active change" >&2; exit 2; }
  d=$(change_dir "$id" 2>/dev/null || true)
  [[ -d "$d" ]] || { echo "agent-gate: fix unknown change dir for $id" >&2; exit 2; }
  if [[ -s "$d/01-spec.md" && -f "$d/01.5-rtvm-matrix.md" ]]; then
    for req in $(grep -oE 'REQ-[0-9]+' "$d/01-spec.md" 2>/dev/null | sort -u); do
      if ! grep -qE "^\|[[:space:]]*\`?${req}\`?([[:space:]]|\|)" "$d/01.5-rtvm-matrix.md" 2>/dev/null; then
        printf '| %s | 待补充 | TBD | TBD | TBD | %s | TBD | TBD | 待验证 |\n' "$req" "$id" >> "$d/01.5-rtvm-matrix.md"
        fixed=$((fixed + 1))
      fi
    done
  fi
  if [[ -f "$d/09-changelog.md" ]]; then
    if ! grep -q '项目总册回填清单' "$d/09-changelog.md" 2>/dev/null; then
      printf '\n#### 项目总册回填清单\n\n' >> "$d/09-changelog.md"
    fi
    for p in P00 P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12; do
      if ! grep -qE "^[[:space:]]*-[[:space:]]*\[[xX ]\][[:space:]]*${p}" "$d/09-changelog.md" 2>/dev/null; then
        printf -- '- [ ] %s — 未命中（由 agent-gate fix 补齐骨架）\n' "$p" >> "$d/09-changelog.md"
        fixed=$((fixed + 1))
      fi
    done
  fi
  for sp in "$repo_root/$scripts_dir/stamp-provenance.sh" "$repo_root/scripts/stamp-provenance.sh" "$repo_root/resources/templates/stamp-provenance.sh"; do
    if [[ -f "$sp" ]]; then
      bash "$sp" --all "$id" >/dev/null 2>&1 || true
      fixed=$((fixed + 1))
      break
    fi
  done
  echo "agent-gate: fix applied ($id updates=$fixed)"
}

review_models_cmd() { # [--discover | --print-contract | --verify [path]]
  local mode="discover" cfg_arg="" cli clis_json="" raw rt fam cfg_def exists="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --discover) mode="discover" ;;
      --print-contract) mode="contract" ;;
      --verify)
        mode="verify"
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then cfg_arg="$2"; shift; fi
        ;;
      -*) echo "agent-gate: review-models: unknown option '$1' (expected --discover|--print-contract|--verify [path])" >&2; exit 2 ;;
      *) cfg_arg="$1" ;;
    esac
    shift
  done

  cfg_def=$(review_models_file)
  case "$mode" in
    discover)
      for cli in claude codex opencode gemini aider; do
        if command -v "$cli" >/dev/null 2>&1; then
          clis_json="${clis_json:+${clis_json},}\"${cli}\""
        fi
      done
      raw=$(review_runtime_raw)
      rt=$(printf '%s\n' "$raw" | sed -n 's/^  runtime: *\([^ ]*\).*/\1/p' | head -1 || true)
      fam=$(printf '%s\n' "$raw" | sed -n 's/^  runtime: .*(family: *\([^)]*\)).*/\1/p' | head -1 || true)
      [[ -f "$cfg_def" ]] && exists="true"
      cat <<EOF
{"runtime":"$(json_escape "${rt:-unknown}")","family":"$(json_escape "${fam:-unknown}")","detected_clis":[${clis_json}],"config_file":"$(json_escape "${cfg_def}")","config_exists":${exists},"tiers":["fast","standard","deep"],"deep_requires_user_approval":true}
EOF
      ;;
    contract)
      cat <<'EOF'
{
  "schema_version": "1",
  "target_file": ".agent-review-models.json",
  "rules": {
    "models_non_empty": true,
    "tier_enum": ["fast", "standard", "deep"],
    "deep_requires_user_approval": true
  },
  "example_entry": {
    "id": "claude-sonnet",
    "provider": "anthropic",
    "cli": "claude",
    "tier": "standard",
    "requires_user_approval": false,
    "roles": ["code", "architecture"]
  },
  "verify_command": "scripts/agent-gate review-models --verify .agent-review-models.json"
}
EOF
      ;;
    verify)
      local target_cfg="${cfg_arg:-$cfg_def}"
      [[ -s "$target_cfg" ]] || { echo "agent-gate: review-models --verify failed — missing or empty: $target_cfg" >&2; exit 2; }
      if has_real_python3; then
        python3 - "$target_cfg" <<'PY'
import json, sys
p = sys.argv[1]
try:
    with open(p, encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    print(f"agent-gate: review-models --verify failed — invalid JSON ({e})", file=sys.stderr)
    sys.exit(2)
if not isinstance(data, dict) or not isinstance(data.get("models"), list) or len(data["models"]) == 0:
    print("agent-gate: review-models --verify failed — top-level 'models' must be a non-empty array", file=sys.stderr)
    sys.exit(2)
for i, m in enumerate(data["models"]):
    if not isinstance(m, dict) or not str(m.get("id", "")).strip():
        print(f"agent-gate: review-models --verify failed — models[{i}] missing non-empty 'id'", file=sys.stderr)
        sys.exit(2)
    tier = m.get("tier")
    if tier not in ("fast", "standard", "deep"):
        print(f"agent-gate: review-models --verify failed — models[{i}] invalid tier '{tier}' (must be fast|standard|deep)", file=sys.stderr)
        sys.exit(2)
    if tier == "deep" and m.get("requires_user_approval") is not True:
        print(f"agent-gate: review-models --verify failed — deep model '{m.get('id')}' must set requires_user_approval: true", file=sys.stderr)
        sys.exit(2)
PY
      else
        awk '
          BEGIN { raw = "" }
          { raw = raw $0 " " }
          END {
            n = length(raw)
            in_str = 0; esc = 0; br = 0; bk = 0; first = ""; last = ""
            for (i = 1; i <= n; i++) {
              c = substr(raw, i, 1)
              if (c !~ /[ \t\r\n]/ && first == "") first = c
              if (c !~ /[ \t\r\n]/) last = c
              if (in_str) {
                if (esc) { esc = 0; continue }
                if (c == "\\") { esc = 1; continue }
                if (c == "\"") in_str = 0
              } else {
                if (c == "\"") in_str = 1
                else if (c == "{") br++
                else if (c == "}") { br--; if (br < 0) { print "unbalanced }" > "/dev/stderr"; exit 2 } }
                else if (c == "[") bk++
                else if (c == "]") { bk--; if (bk < 0) { print "unbalanced ]" > "/dev/stderr"; exit 2 } }
              }
            }
            if (in_str != 0 || br != 0 || bk != 0 || first != "{" || last != "}") {
              print "agent-gate: review-models --verify failed — malformed JSON" > "/dev/stderr"; exit 2
            }
            if (raw !~ /"models"[ \t]*:[ \t]*\[/ || raw !~ /"id"[ \t]*:[ \t]*"[^"]+"/) {
              print "agent-gate: review-models --verify failed — missing non-empty models[].id" > "/dev/stderr"; exit 2
            }
            sub(/^.*"models"[ \t]*:[ \t]*\[/, "", raw)
            if (raw ~ /^[ \t]*\]/) { print "agent-gate: review-models --verify failed — empty models array" > "/dev/stderr"; exit 2 }
            cnt = split(raw, objs, /\}[ \t]*,[ \t]*\{/)
            for (j = 1; j <= cnt; j++) {
              o = objs[j]
              if (o !~ /"id"[ \t]*:[ \t]*"[^"]+"/) {
                print "agent-gate: review-models --verify failed — missing non-empty models[].id" > "/dev/stderr"; exit 2
              }
              if (o !~ /"tier"[ \t]*:[ \t]*"(fast|standard|deep)"/) {
                print "agent-gate: review-models --verify failed — tier must be fast|standard|deep" > "/dev/stderr"; exit 2
              }
              if (o ~ /"tier"[ \t]*:[ \t]*"deep"/ && o !~ /"requires_user_approval"[ \t]*:[ \t]*true/) {
                print "agent-gate: review-models --verify failed — deep tier requires requires_user_approval: true" > "/dev/stderr"; exit 2
              }
            }
          }
        ' "$target_cfg" || exit 2
      fi
      echo "agent-gate: review-models verified ($target_cfg)"
      ;;
  esac
}

dispatch_role() { # <stage> -> role label
  case "$1" in
    exploration) printf '只读勘探子代理' ;;
    intent)      printf '业务 / 行业专家' ;;
    spec)        printf '需求 Agent' ;;
    impact)      printf '影响分析 Agent' ;;
    design)      printf '架构 / 项管专家' ;;
    testplan)    printf '测试专家' ;;
    code)        printf '开发 Agent' ;;
    test)        printf '测试执行 Agent' ;;
    review)      printf '独立评审子代理' ;;
    delivery)    printf '交付 / 验收 Agent' ;;
  esac
}

dispatch_boundary() { # <stage> -> read/write boundary and done criteria
  case "$1" in
    exploration) printf '只读：不改任何文件｜完成判据：每条事实带 文件:行，未覆盖面显式列出' ;;
    intent)      printf '可写：00-intent.md / 00.5-communication.md；禁改源码｜完成判据：问题陈述 + 未决问题（含状态）+ 风险初判，00.5 待用户确认' ;;
    spec)        printf '可写：01-spec.md / 01.5-rtvm-matrix.md；禁改源码｜完成判据：REQ 编号连续、可判定、逐条挂靠 UJ 或声明无用户面' ;;
    impact)      printf '可写：02-code-impact-analysis.md；禁改源码｜完成判据：业务/技术/风险三维影响 + 回滚策略 + 隐式链路三向遍历（或显式未命中）+ 延伸发现 / 历史相似检索节' ;;
    design)      printf '可写：02 / 03 / 03.5（ui_change 命中时 03.6）；禁改源码｜完成判据：≥2 候选对比 + DES + 任务拆解 + 既有范式关系节' ;;
    testplan)    printf '可写：04-test-scripts.md；禁改源码｜完成判据：十一维覆盖表 + SC 枚举 + TC 矩阵 + TC 落点清单' ;;
    code)        printf '可写：DES 范围内源码 + 04.5-coding-record.md；禁改测试断言迁就实现｜完成判据：每 DES 有落点 + ReAct 三段记录 + 镜像同步' ;;
    test)        printf '可执行测试命令；不改源码与测试断言｜完成判据：真实命令 + rc 证据（含 red→green），未执行项显式列出' ;;
    review)      printf '只读：不改任何文件；发现与结论回给编排者，由编排者落 07｜完成判据：07 五节齐备，每条发现带证据，禁泛评' ;;
    delivery)    printf '可写：06-delivery-summary.md / 09-changelog.md（追加式）；禁改上游产物｜完成判据：DoD 逐条 + RTVM 闭环 + 09 回填清单' ;;
  esac
}

dispatch_needs() { # <stage> -> artifact basenames this stage must read
  case "$1" in
    exploration) printf '%s' '00-intent.md 00-governance.json 00.5-communication.md' ;;
    intent)      printf '%s' '00-intent.md 00-governance.json' ;;
    spec)        printf '%s' '00-intent.md 00.5-communication.md' ;;
    impact)      printf '%s' '00-intent.md 01-spec.md 01.5-rtvm-matrix.md' ;;
    design)      printf '%s' '01-spec.md 01.5-rtvm-matrix.md' ;;
    testplan)    printf '%s' '01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md' ;;
    code)        printf '%s' '01-spec.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md' ;;
    test)        printf '%s' '04-test-scripts.md 04.5-coding-record.md' ;;
    review)      printf '%s' '01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 05-test-results.md' ;;
    delivery)    printf '%s' '05-test-results.md 07-review-report.md' ;;
  esac
}

dispatch_expertise() { # <stage> -> capability profile (review = risk-derived roles)
  case "$1" in
    exploration) printf '系统分析 / 检索纪律 / 证据链' ;;
    intent)      printf '业务领域 / 行业经验 / 风险判断' ;;
    spec)        printf '需求工程 / 可判定性 / UJ 建模' ;;
    impact)      printf '业务建模 / 状态-触发链路审计 / 影响面推理' ;;
    design)      printf '架构设计 / 演进性 / 权衡取舍' ;;
    testplan)    printf '测试设计 / 覆盖推理 / 领域知识' ;;
    code)        printf '实现 / 安全 / 性能 / 最小改动面' ;;
    test)        printf '证据纪律 / 环境排障 / 红测试归因顺序' ;;
    delivery)    printf '追踪矩阵 / DoD / 一致性核对' ;;
    review)      printf '' ;;
  esac
}

dispatch_outputs() { # <stage> -> output contract
  case "$1" in
    exploration) printf '事实清单（文件:行）+ 未覆盖面 + 建议下一步' ;;
    intent)      printf '问题陈述 + 未决问题（含关闭状态）+ 风险初判；00.5 需用户整体确认' ;;
    spec)        printf '01-spec REQ 行（REQ-xxx + 描述 + 验收标准 + 挂靠 UJ/声明）+ 01.5 行' ;;
    impact)      printf '02 业务/技术/风险三维 + 回滚策略 + 隐式链路三向遍历（或显式未命中）+ 延伸发现 / 历史相似检索' ;;
    design)      printf '02 三维 + 回滚；03 选型 + DES + 既有范式关系；03.5 任务表' ;;
    testplan)    printf '04 维度表 + SC-xxx 清单 + TC-xxx 矩阵 + TC 落点清单' ;;
    code)        printf '04.5 ReAct（Thought / Action / Observation）+ 改动清单' ;;
    test)        printf '05 证据（命令 + 过滤后关键输出 + rc）+ 未执行项；禁「测试已通过」式空声明' ;;
    review)      printf '07 五节：输入契约与专业能力 / 模型选择与成本确认 / 独立性声明 / 发现处置 / 评审结论' ;;
    delivery)    printf '06 + 09（DoD 逐条、RTVM 闭环、09 回填清单、重要上下文与未验证 REQ 清单）' ;;
  esac
}

dispatch_lines() { # one line per argument
  local it
  for it in ${1+"$@"}; do printf '%s\n' "$it"; done
}

dispatch_run() { # <stage> <change-id> <text|--json> — print-only, never writes
  local stage="$1" id="$2" mode="${3:-text}"
  local d rec risk ui goal reqs des tcs needs f m mt cnt cap roles
  local -a p0 p1 p2 p3 p4 p5 p6 p7 p8 gaps
  local so io to vo
  d=$(change_dir "$id")
  rec=$(gov_record "$d/00-governance.json" "$id" || true)
  risk=$(json_field "$rec" risk_level); [[ -n "$risk" ]] || risk="未声明"
  if [[ -s "$d/01-spec.md" ]]; then
    if review_ui_change "$d"; then ui=true; else ui=false; fi
  else
    ui="未声明（缺 01-spec.md）"
  fi
  goal=$(awk '/^#{1,6}[[:space:]]*预期结果/{f=1;next} f&&/^[-*][[:space:]]+[^[:space:]]/{sub(/^[-*][[:space:]]+/,"");print;exit}' \
    "$d/00-intent.md" 2>/dev/null || true)
  goal=$(printf '%s' "$goal" | cut -c1-90 | sed -E 's/[[:space:]]+$//')
  reqs=$(grep -E '^#{2,4}[[:space:]]+REQ-[0-9]+|\|[[:space:]]*REQ-[0-9]+[[:space:]]*\|' "$d/01-spec.md" 2>/dev/null | grep -oE 'REQ-[0-9]+' | sort -u | tr '\n' ' ' || true)
  if [[ -z "$reqs" ]]; then
    reqs=$(grep -oE 'REQ-[0-9]+' "$d/01-spec.md" 2>/dev/null | sort -u | tr '\n' ' ' || true)
  fi
  reqs=${reqs% }
  des=$(grep -oE 'DES-[0-9]+' "$d/01.5-rtvm-matrix.md" 2>/dev/null | sort -u | tr '\n' ' ' || true); des=${des% }
  tcs=$(grep -oE 'TC-[0-9]+' "$d/01.5-rtvm-matrix.md" 2>/dev/null | sort -u | tr '\n' ' ' || true); tcs=${tcs% }

  p0+=("角色：$(dispatch_role "$stage")")
  p0+=("阶段：${stage} · 变更：${id}（风险 ${risk} · ui_change ${ui}）")
  p0+=("读写边界与完成判据：$(dispatch_boundary "$stage")")
  p0+=("写法：按本骨架装配 prompt；收到缺项 prompt 时按 P8 声明缺口，只做最小必要读盘")

  for m in P12-product-context.md P01-requirements-master.md P02-architecture-master.md P03-interface-registry.md P04-data-dictionary.md; do
    if [[ -s "$docs_dir/project/$m" ]]; then
      mt=$(grep -m1 -E '^#[[:space:]]+' "$docs_dir/project/$m" 2>/dev/null | sed -E 's/^#[[:space:]]+//' || true)
      p1+=("${m}：${mt:-（无标题）} — $docs_dir/project/$m")
    else
      p1+=("${m}：缺失")
      gaps+=("P1 缺 ${m}（$docs_dir/project/${m}）：项目背景维度未装载")
    fi
  done
  p1+=("仓库入口与约定：$repo_root/AGENTS.md + $docs_dir/DEVELOPMENT_STANDARDS.md")

  p2+=("风险等级：${risk}；ui_change：${ui}")
  p2+=("功能目的：${goal:-（00-intent 未给出预期结果，先补 00-intent）}")
  if [[ -n "$reqs" ]]; then p2+=("受影响 REQ：${reqs}"); else gaps+=("P2 缺 REQ 清单：$d/01-spec.md 无 REQ-xxx"); fi
  p2+=("业务规则 / UJ：见 01-spec「用户任务」；非目标：见 00-intent「非目标」")

  needs=$(dispatch_needs "$stage")
  for f in $needs; do
    if [[ -s "$d/$f" ]]; then
      p3+=("${f}（$(wc -l < "$d/$f" 2>/dev/null | tr -d ' ') 行）— $d/$f")
    else
      p3+=("${f}（未产出）")
      gaps+=("P3 缺 ${f}：${stage} 阶段必带输入（$d/${f}）")
    fi
  done
  [[ -n "$des" || -n "$tcs" ]] && p3+=("DES：${des:-未登记}；TC：${tcs:-未登记}")
  if [[ "$stage" == "review" ]]; then
    p3+=("$(process_honesty_summary "$id")")
  fi
  p3+=("diff 摘要：由编排者贴入 git diff --stat + 关键 hunk（生成器不猜改动面）")

  if [[ -s "$docs_dir/bugfix-log.md" ]]; then
    cnt=$(grep -cE '^#{2,3}[[:space:]]+BUG-' "$docs_dir/bugfix-log.md" 2>/dev/null || true); cnt=${cnt:-0}
    p4+=("bugfix-log：${cnt} 条 BUG 记录 — $docs_dir/bugfix-log.md（先检索同族教训）")
  else
    p4+=("bugfix-log：缺失")
    gaps+=("P4 缺 $docs_dir/bugfix-log.md：同族教训面为空")
  fi
  if [[ -s "$d/06-delivery-summary.md" ]]; then
    cnt=$(grep -oE 'FU-[0-9]+(-[0-9]+)?' "$d/06-delivery-summary.md" 2>/dev/null | sort -u | wc -l | tr -d ' ' || true)
    p4+=("本变更 FU 台账：${cnt:-0} 条 — $d/06-delivery-summary.md")
  fi
  p4+=("既有约定：$docs_dir/project/P11-decision-log.md；既有评审结论：$d/07-review-report.md")

  cap=$(dispatch_expertise "$stage")
  if [[ "$stage" == "review" ]]; then
    roles=$(review_roles_for "$d" "$id" || true)
    cap="评审角色：${roles:-code handoff}（§3 能力矩阵）"
  fi
  p5+=("$cap")
  p5+=("凭什么认为具备：结论里自述经验证据；无法自述＝能力不匹配，视同未评审")

  so=$(json_field "$rec" spec_author); io=$(json_field "$rec" implementation_owner)
  to=$(json_field "$rec" test_owner);  vo=$(json_field "$rec" verification_owner)
  p6+=("生产主体（实现）：${io:-未填}；规格：${so:-未填}；测试：${to:-未填}；验证：${vo:-未填}")
  case "$risk" in
    L2|L3) p6+=("独立性要求：L2/L3 评审须与生产跨主体（会话/模型/厂商分离），禁同会话自评") ;;
    *)     p6+=("独立性要求：四主体互异；同模型独立会话可接受") ;;
  esac
  [[ -z "$io" ]] && gaps+=("P6 未填 implementation_owner：四主体互异无法证明（§2.1 规则 10）")
  if [[ "$stage" == "review" ]]; then
    if [[ -z "$(json_field "$rec" review_owner)" ]]; then
      gaps+=("P6 未填 review_owner：评审签署主体缺失")
    fi
    p6+=("成本：scripts/agent-gate review-plan $id 探测运行时候选；deep/高成本模型须用户确认（AGENT_REVIEW_USER_APPROVED=1）")
  else
    p6+=("成本：沿用会话预算；超预算按 §2.16.6 第 5 条显式声明")
  fi

  p7+=("$(dispatch_outputs "$stage")")

  p8+=("不自签：不得同时生产本环节产物并签署本环节结论")
  p8+=("未跑≠通过：没有真实命令输出与 rc 的证据，不得宣称通过")
  p8+=("超清单读盘须在结论中声明原因；缺依据写「未验证 / 不适用（理由）」，不猜")
  p8+=("不得改写上游已签署产物；发现上游错误走偏差定责（图纸错 / 代码错 / 理解错）")

  if [[ "$mode" == "--json" ]]; then
    printf '{"stage":"%s","change":"%s","role":"%s","contract":"v2","sections":{"p0":%s,"p1":%s,"p2":%s,"p3":%s,"p4":%s,"p5":%s,"p6":%s,"p7":%s,"p8":%s},"gaps":%s}\n' \
      "$stage" "$id" "$(json_escape "$(dispatch_role "$stage")")" \
      "$(djson_arr ${p0[@]+"${p0[@]}"})" "$(djson_arr ${p1[@]+"${p1[@]}"})" \
      "$(djson_arr ${p2[@]+"${p2[@]}"})" "$(djson_arr ${p3[@]+"${p3[@]}"})" \
      "$(djson_arr ${p4[@]+"${p4[@]}"})" "$(djson_arr ${p5[@]+"${p5[@]}"})" \
      "$(djson_arr ${p6[@]+"${p6[@]}"})" "$(djson_arr ${p7[@]+"${p7[@]}"})" \
      "$(djson_arr ${p8[@]+"${p8[@]}"})" "$(djson_arr ${gaps[@]+"${gaps[@]}"})"
    return 0
  fi
  printf '# dispatch %s · stage=%s · contract=v2\n' "$id" "$stage"
  printf '\n## P0 任务\n'; dispatch_lines ${p0[@]+"${p0[@]}"}
  printf '\n## P1 项目背景\n'; dispatch_lines ${p1[@]+"${p1[@]}"}
  printf '\n## P2 变更上下文\n'; dispatch_lines ${p2[@]+"${p2[@]}"}
  printf '\n## P3 证据包\n'; dispatch_lines ${p3[@]+"${p3[@]}"}
  printf '\n## P4 专业与历史\n'; dispatch_lines ${p4[@]+"${p4[@]}"}
  printf '\n## P5 专业能力\n'; dispatch_lines ${p5[@]+"${p5[@]}"}
  printf '\n## P6 独立与成本\n'; dispatch_lines ${p6[@]+"${p6[@]}"}
  printf '\n## P7 输出契约\n'; dispatch_lines ${p7[@]+"${p7[@]}"}
  printf '\n## P8 红线\n'; dispatch_lines ${p8[@]+"${p8[@]}"}
  printf '\n## gaps（缺失项；先补齐，或在 prompt 中按 P8 显式声明）\n'
  if [[ -z "${gaps[*]+x}" ]]; then
    printf -- '- 无（骨架齐备）\n'
  else
    for m in "${gaps[@]}"; do printf -- '- [gap] %s\n' "$m"; done
  fi
  printf '\n> 五标签映射：项目背景=P1 / 变更上下文=P2 / 证据包=P3 / 专业与历史=P4+P5 / 独立与成本=P6（§2.2 契约 v2）\n'
}

baseline_p50() {
  local lg="$repo_root/.agent-state/cost-ledger.tsv" kind="$1" vals
  [[ -s "$lg" ]] || return 0
  vals=$(awk -F'\t' -v k="$kind" '$2==k && $5 ~ /^[0-9]+$/ {print $5}' "$lg" | tail -5 | sort -n)
  [[ -n "$vals" ]] || return 0
  printf '%s' "$(printf '%s\n' "$vals" | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')"
}

baseline_last() {
  local lg="$repo_root/.agent-state/cost-ledger.tsv" kind="$1"
  [[ -s "$lg" ]] || return 0
  awk -F'\t' -v k="$kind" '$2==k && $5 ~ /^[0-9]+$/ {v=$5} END{if (v!="") print v}' "$lg"
}

baseline_count() {
  local lg="$repo_root/.agent-state/cost-ledger.tsv" kind="$1"
  [[ -s "$lg" ]] || { printf '0'; return 0; }
  awk -F'\t' -v k="$kind" '$2==k {n++} END{print n+0}' "$lg"
}

baseline_snapshot() {
  local stop_p50 full_runs audit_p50 assertions wall src
  stop_p50=$(baseline_p50 run-full)
  full_runs=$(baseline_count run-full)
  audit_p50=$(baseline_p50 audit)
  wall=$(baseline_last run-full)
  assertions=""
  if [[ -s "$repo_root/.agent-state/last-suite-receipt.json" ]]; then
    local pa fa
    pa=$(sed -nE 's/.*"passed":[[:space:]]*([0-9]+).*/\1/p' "$repo_root/.agent-state/last-suite-receipt.json" | head -1)
    fa=$(sed -nE 's/.*"failed":[[:space:]]*([0-9]+).*/\1/p' "$repo_root/.agent-state/last-suite-receipt.json" | head -1)
    if [[ -n "$pa" && -n "$fa" ]]; then assertions=$(( pa + fa )); fi
  fi
  if [[ -n "$stop_p50" && -n "$audit_p50" && -n "$assertions" ]]; then src="ledger+receipt"
  elif [[ -n "$stop_p50" || -n "$audit_p50" ]]; then src="ledger"
  elif [[ -n "$assertions" ]]; then src="receipt"
  else src="partial"; fi
  printf '{"measured_at":"%s","source":"%s","stop_p50_s":%s,"full_runs":%s,"audit_p50_s":%s,"full_assertions":%s,"full_wall_s":%s}' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$src" \
    "${stop_p50:-null}" "${full_runs:-0}" "${audit_p50:-null}" "${assertions:-null}" "${wall:-null}"
}

baseline_write() {
  local d="$1" js="$2" f="$1/baseline.json" log="$1/09-changelog.md"
  printf '%s\n' "$js" > "$f" 2>/dev/null || {
    echo "agent-gate: WARN — could not write $f (P0-0)" >&2; return 1; }
  if [[ -s "$log" ]] && ! grep -q '^- \[baseline\]' "$log" 2>/dev/null; then
    printf -- '- [baseline] %s\n' "$js" >> "$log" 2>/dev/null || true
  fi
  echo "agent-gate: baseline recorded at $f"
}

_cold_defect_metrics() { # -> "<bugs> <escaped> <erate> <fps> <reopened> <rrate>"
  local df b_tot=0 b_esc=0 fp_tot=0 fp_re=0 erate="null" rrate="null"
  local _f_list=() _evalf="$repo_root/.agent-state/eval-cases.tsv"
  if [[ -d "$bugs_root" ]]; then
    while IFS= read -r df; do
      [[ -s "$df" ]] && _f_list+=("$df")
    done < <(find "$bugs_root" -name '01-diagnosis.md' -type f 2>/dev/null | LC_ALL=C sort)
  fi
  if [[ ${#_f_list[@]} -gt 0 ]]; then
    read -r b_tot b_esc fp_tot fp_re <<< "$(awk -v evalf="$_evalf" '
      BEGIN {
        if (evalf != "") {
          while ((getline line < evalf) > 0) {
            n = split(line, cols, "\t")
            if (n >= 3 && cols[2] == "escape") esc_id[cols[3]] = 1
          }
          close(evalf)
        }
      }
      function flush_bug(   k) {
        if (cur_id == "") return
        if (!(cur_id in seen_bug)) {
          seen_bug[cur_id] = 1
          bugs++
          if (cur_esc == 1 || (cur_id in esc_id)) escaped++
          if (cur_fp != "" && cur_fp !~ /^</ && cur_fp != "无" && cur_fp != "未命中") {
            fp_cnt[cur_fp]++
          }
        }
      }
      FNR == 1 {
        flush_bug()
        cur_id = ""; cur_esc = 0; cur_fp = ""
        np = split(FILENAME, _p, "/")
        is_batch = (np >= 2 && _p[np - 1] ~ /^BATCH-/)
        if (!is_batch && np >= 2) {
          cur_id = _p[np - 1]
        }
      }
      is_batch && /^##[[:space:]]+BUG-[A-Za-z0-9._-]+/ {
        flush_bug()
        cur_id = $2; sub(/[[:space:]].*$/, "", cur_id)
        cur_esc = 0; cur_fp = ""
        next
      }
      cur_id != "" {
        if ($0 ~ /escaped_after_claim:[[:space:]]*yes/) cur_esc = 1
        if ($0 ~ /^[[:space:]]*\|[[:space:]]*defect_fp[[:space:]]*\|/) {
          split($0, c, "|")
          v = c[3]; gsub(/<!--[^>]*-->/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          if (v != "") cur_fp = v
        }
      }
      END {
        flush_bug()
        for (k in fp_cnt) {
          fps++
          if (fp_cnt[k] >= 2) reop++
        }
        printf "%d %d %d %d\n", bugs+0, escaped+0, fps+0, reop+0
      }
    ' "${_f_list[@]}" 2>/dev/null || echo "0 0 0 0")"
  fi
  [[ "$b_tot" -gt 0 ]] && erate=$(awk -v e="$b_esc" -v t="$b_tot" 'BEGIN{printf "%.2f", e/t}')
  [[ "$fp_tot" -gt 0 ]] && rrate=$(awk -v r="$fp_re" -v t="$fp_tot" 'BEGIN{printf "%.2f", r/t}')
  printf '%s %s %s %s %s %s' "$b_tot" "$b_esc" "$erate" "$fp_tot" "$fp_re" "$rrate"
}

emit_metrics() {
  local sum=0 jmode=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --summary) sum=1 ;;
      --json) jmode=1 ;;
      *) echo "agent-gate: metrics unknown option '$1' (expected --summary [--json])" >&2; exit 2 ;;
    esac
    shift
  done
  if [[ "$jmode" -eq 1 && "$sum" -eq 0 ]]; then
    echo "agent-gate: metrics --json requires --summary" >&2; exit 2
  fi
  if [[ "$sum" -eq 1 ]]; then
    local _raw _dm_bugs _dm_esc _dm_erate _dm_fps _dm_reop _dm_rrate
    _raw=$(_emit_metrics_jsonl)
    read -r _dm_bugs _dm_esc _dm_erate _dm_fps _dm_reop _dm_rrate <<< "$(_cold_defect_metrics)"
    awk -v jmode="$jmode" -v dbugs="$_dm_bugs" -v desc="$_dm_esc" -v derate="$_dm_erate" -v dfps="$_dm_fps" -v dreop="$_dm_reop" -v drrate="$_dm_rrate" '
      function jesc(s) {
        gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/[\t\r\n]/, " ", s)
        return s
      }
      BEGIN {
        c=0; l0=0; l1=0; l2=0; l3=0; ready=0; rr=0; ftot=0; fint=0; fpre=0; fr_tot=0
      }
      /"change_id":/ {
        c++
        if ($0 ~ /"risk_level":"L0"/) l0++
        else if ($0 ~ /"risk_level":"L1"/) l1++
        else if ($0 ~ /"risk_level":"L2"/) l2++
        else if ($0 ~ /"risk_level":"L3"/) l3++
        if ($0 ~ /"delivery_ready":true/) ready++
        if (match($0, /"review_rounds":[0-9]+/)) { rr += substr($0, RSTART+16, RLENGTH-16)+0 }
        if (match($0, /"findings_total":[0-9]+/)) { ftot += substr($0, RSTART+17, RLENGTH-17)+0 }
        if (match($0, /"findings_introduced":[0-9]+/)) { fint += substr($0, RSTART+22, RLENGTH-22)+0 }
        if (match($0, /"findings_pre_existing":[0-9]+/)) { fpre += substr($0, RSTART+24, RLENGTH-24)+0 }
      }
      /"friction_code":/ {
        if (match($0, /"friction_code":"[^"]+"/)) {
          fc = substr($0, RSTART+17, RLENGTH-18)
          if (match($0, /"count":[0-9]+/)) {
            fn = substr($0, RSTART+8, RLENGTH-8)+0
            fr_tot += fn; frc[fc] += fn
          }
        }
      }
      END {
        top_code = "none"; top_n = 0
        for (k in frc) { if (frc[k] > top_n || (frc[k] == top_n && k < top_code)) { top_n = frc[k]; top_code = k } }
        if (jmode == 1) {
          printf "{\"changes\":%d,\"by_risk\":{\"L0\":%d,\"L1\":%d,\"L2\":%d,\"L3\":%d},\"delivery_ready\":%d,\"review_rounds\":%d,\"findings_total\":%d,\"findings_introduced\":%d,\"findings_pre_existing\":%d,\"friction_events\":%d,\"top_friction\":\"%s\",\"bugs_total\":%d,\"escaped_bugs\":%d,\"escape_rate\":%s,\"fingerprints_total\":%d,\"reopened_fingerprints\":%d,\"same_fp_reopen_rate\":%s}\n",
            c, l0, l1, l2, l3, ready, rr, ftot, fint, fpre, fr_tot, jesc(top_code),
            dbugs+0, desc+0, derate, dfps+0, dreop+0, drrate
        } else {
          printf "metrics summary: changes=%d (L0=%d L1=%d L2=%d L3=%d) delivery_ready=%d\n", c, l0, l1, l2, l3, ready
          printf "metrics reviews: rounds=%d findings_total=%d introduced=%d pre_existing=%d\n", rr, ftot, fint, fpre
          printf "metrics friction: events=%d top=%s (%d)\n", fr_tot, top_code, top_n
          printf "metrics defects: bugs=%d escaped=%d escape_rate=%s fingerprints=%d reopened=%d same_fp_reopen_rate=%s\n", dbugs+0, desc+0, derate, dfps+0, dreop+0, drrate
        }
      }
    ' <<< "$_raw"
    return 0
  fi
  _emit_metrics_jsonl
}

_emit_metrics_jsonl() {
  local dir id risk t_intent t_gov t_spec t_plan t_test t_chg t_code
  local ad_total ad_yes ad_no ad_over ad_rate
  local sigs esess r_rounds r_limit r_over f_tot f_dis f_rate
  local g_sec g_wasted g_wrate g_stale g_handshake rev_indep r_owner i_owner
  [[ -d "$change_root" ]] || exit 0
  g_sec=0; g_wasted=0
  if [[ -s "$repo_root/.agent-state/cost-ledger.tsv" ]]; then
    read -r g_sec g_wasted <<< "$(awk -F'\t' '$2=="sec" && NF>=11 {n++; if ($11=="wasted") w++} END{print n+0, w+0}' \
      "$repo_root/.agent-state/cost-ledger.tsv")"
  fi
  g_wrate=null
  [[ "$g_sec" -gt 0 ]] && g_wrate=$(awk -v w="$g_wasted" -v n="$g_sec" 'BEGIN{printf "%.2f", w/n}')
  g_stale=0
  [[ -s "$repo_root/.agent-state/stale-decisions.tsv" ]] \
    && g_stale=$(grep -c . "$repo_root/.agent-state/stale-decisions.tsv" 2>/dev/null || true)
  g_handshake=false
  ls "$repo_root/.agent-state/runtime/"*.json >/dev/null 2>&1 && g_handshake=true
  for dir in "$change_root"/*/; do
    [[ -d "$dir" ]] || continue
    for id in $(change_ids_in_dir "${dir%/}"); do
      [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
      if [[ -s "$dir/00-governance.json" ]]; then
        risk=$(json_field "$(gov_record "$dir/00-governance.json" "$id")" risk_level)
        if [[ "$risk" =~ ^L[0-3]$ ]]; then risk="\"$risk\""; else risk=null; fi
      else
        risk=null
      fi
      t_intent=$(first_commit_ts "$dir/00-intent.md")
      t_gov=$(first_commit_ts "$dir/00-governance.json")
      t_spec=$(first_commit_ts "$dir/01-spec.md")
      t_plan=$(first_commit_ts "$dir/03-modification-plan.md")
      t_test=$(first_commit_ts "$dir/05-test-results.md")
      t_chg=$(first_commit_ts "$dir/09-changelog.md")
      t_code=$(first_commit_referencing "$id")
      sigs=$(cat "$dir/01-spec.md" "$dir/03-modification-plan.md" 2>/dev/null \
        | grep -Eo '[A-Za-z0-9][A-Za-z0-9 ._()-]* / [A-Za-z0-9._-]+ / [A-Za-z0-9_-]+' \
        | awk -F'/' '{gsub(/[[:space:]]/,"",$3); print $3}' | sort -u || true)
      esess=$(printf '%s' "$sigs" | grep -c . || true)
      a_files=$(find "$dir" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c . || true)
      a_bytes=$(cat "$dir"/*.md 2>/dev/null | wc -c | tr -d ' ' || true)
      [[ "$a_bytes" =~ ^[0-9]+$ ]] || a_bytes=0
      r_rounds=$(review_rounds_of "$id")
      [[ "$r_rounds" =~ ^[0-9]+$ ]] || r_rounds=0
      r_limit=$(review_round_limit)
      r_over=false
      if [[ "$r_rounds" -gt "$r_limit" ]]; then r_over=true; fi
      f_tot=0
      f_dis=0
      if [[ -s "$dir/07-review-report.md" ]]; then
        f_tot=$(awk -F'|' '
          /^#{1,6}[[:space:]]*发现处置/ { sec=1; next }
          sec && /^#{1,6}[[:space:]]/ { sec=0 }
          !sec { next }
          /^[[:space:]]*\|/ {
            if (NF < 6) next
            id=$2; gsub(/<!--[^>]*-->/,"",id); gsub(/[[:space:]]/,"",id)
            if (id == "" || id == "编号" || id ~ /^-+$/ || id ~ /^<.*>$/) next
            c++
          } END { print c+0 }' "$dir/07-review-report.md" 2>/dev/null || true)
        f_dis=$(awk -F'|' '
          /^#{1,6}[[:space:]]*发现处置/ { sec=1; next }
          sec && /^#{1,6}[[:space:]]/ { sec=0 }
          !sec { next }
          /^[[:space:]]*\|/ {
            if (NF < 6) next
            id=$2; dis=$5
            gsub(/<!--[^>]*-->/,"",id); gsub(/<!--[^>]*-->/,"",dis)
            gsub(/[[:space:]]/,"",id); gsub(/[[:space:]]/,"",dis)
            if (id == "" || id == "编号" || id ~ /^-+$/ || id ~ /^<.*>$/) next
            if (dis == "" || dis !~ /^已修复/) c++
          } END { print c+0 }' "$dir/07-review-report.md" 2>/dev/null || true)
      fi
      [[ "$f_tot" =~ ^[0-9]+$ ]] || f_tot=0
      [[ "$f_dis" =~ ^[0-9]+$ ]] || f_dis=0
      f_rate=null
      if [[ "$f_tot" -gt 0 ]]; then
        f_rate=$(awk -v t="$f_tot" -v d="$f_dis" 'BEGIN { printf "%.2f", d/t }')
      fi
      f_int=null
      f_pre=null
      if [[ -s "$dir/07-review-report.md" ]]; then
        f_counts=$(finding_source_counts "$dir/07-review-report.md")
        if [[ "${f_counts##* }" = 0 ]]; then
          f_int=${f_counts%% *}
          f_pre=${f_counts#* }; f_pre=${f_pre%% *}
        fi
      fi
      ad_total=0; ad_yes=0; ad_no=0; ad_over=0
      if [[ -s "$repo_root/.agent-state/adapt-decisions.tsv" ]]; then
        read -r ad_total ad_yes ad_no ad_over <<< "$(awk -F'\t' -v id="$id" '
          $2==id {n++; if ($7=="yes") y++; if ($7=="no") o++; if ($4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ && $4+0>$5+0) b++}
          END {print n+0, y+0, o+0, b+0}' "$repo_root/.agent-state/adapt-decisions.tsv")"
      fi
      ad_rate=null
      [[ "$ad_total" -gt 0 ]] && ad_rate=$(( ad_yes * 100 / ad_total ))
      rev_indep=null
      if [[ -s "$dir/00-governance.json" ]]; then
        r_owner=$(json_field "$(gov_record "$dir/00-governance.json" "$id")" review_owner)
        i_owner=$(json_field "$(gov_record "$dir/00-governance.json" "$id")" implementation_owner)
        if [[ -n "$r_owner" && -n "$i_owner" ]]; then
          if [[ "$r_owner" != "$i_owner" ]]; then rev_indep=true; else rev_indep=false; fi
        fi
      fi
      printf '{"change_id":"%s","risk_level":%s,"expert_sessions":%s,"artifact_files":%s,"artifact_bytes":%s,"decisions":%s,"adopted":%s,"overridden":%s,"over_budget":%s,"adoption_rate":%s,"wasted_rate":%s,"stale_decisions":%s,"handshake":%s,"review_independent":%s,"intent_ts":%s,"governance_ts":%s,"spec_ts":%s,"plan_ts":%s,"first_code_commit_ts":%s,"test_evidence_ts":%s,"changelog_ts":%s,"intent_to_spec_s":%s,"spec_to_plan_s":%s,"plan_to_code_s":%s,"code_to_evidence_s":%s,"intent_to_changelog_s":%s,"delivery_ready":%s,"review_rounds":%s,"review_rounds_over_limit":%s,"findings_total":%s,"findings_dismissed":%s,"dismissal_rate":%s,"findings_introduced":%s,"findings_pre_existing":%s}\n' \
        "$id" "$risk" "${esess:-0}" "${a_files:-0}" "${a_bytes:-0}" \
        "$ad_total" "$ad_yes" "$ad_no" "$ad_over" "$ad_rate" \
        "$g_wrate" "$g_stale" "$g_handshake" "$rev_indep" \
        "$(ts_or_null "$t_intent")" "$(ts_or_null "$t_gov")" "$(ts_or_null "$t_spec")" \
        "$(ts_or_null "$t_plan")" "$(ts_or_null "$t_code")" "$(ts_or_null "$t_test")" \
        "$(ts_or_null "$t_chg")" \
        "$(delta_or_null "$t_spec" "$t_intent")" \
        "$(delta_or_null "$t_plan" "$t_spec")" \
        "$(delta_or_null "$t_code" "$t_plan")" \
        "$(delta_or_null "$t_test" "$t_code")" \
        "$(delta_or_null "$t_chg" "$t_intent")" \
        "$(delivery_ready "$dir")" \
        "$r_rounds" "$r_over" "$f_tot" "$f_dis" "$f_rate" "$f_int" "$f_pre"
    done
  done
  if [[ -f ".agent-state/gate-friction.tsv" ]]; then
    awk -F'\t' '{ c[$1]++ } END { for (k in c) printf "{\"friction_code\":\"%s\",\"count\":%d}\n", k, c[k] }' \
      .agent-state/gate-friction.tsv 2>/dev/null || true
  fi
}

doctor_cmd() { # [--json] — ITEM-47 read-only diagnostics
  local jmode=0 pass=0 warn=0 fail=0 checks_json="" first=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) jmode=1 ;;
      -h|--help) echo "Usage: scripts/agent-gate doctor [--json]"; return 0 ;;
      *) echo "agent-gate: doctor unknown option '$1' (expected --json)" >&2; exit 2 ;;
    esac
    shift
  done
  _doc_add() { # <name> <ok|warn|fail> <detail> <fix>
    local n="$1" st="$2" det="$3" fix="$4"
    case "$st" in
      ok)   pass=$((pass + 1)) ;;
      warn) warn=$((warn + 1)) ;;
      fail) fail=$((fail + 1)) ;;
    esac
    if [[ "$jmode" -eq 1 ]]; then
      local entry
      entry=$(printf '{"name":"%s","status":"%s","detail":"%s","fix":"%s"}' \
        "$(json_escape "$n")" "$(json_escape "$st")" "$(json_escape "$det")" "$(json_escape "$fix")")
      if [[ "$first" -eq 1 ]]; then checks_json="$entry"; first=0; else checks_json="$checks_json,$entry"; fi
    else
      printf '%-4s %-18s %s' "${st}" "$n" "$det"
      [[ -n "$fix" && "$st" != "ok" ]] && printf ' | fix: %s' "$fix"
      printf '\n'
    fi
  }
  local hp
  hp=$(git -C "$repo_root" config --get core.hooksPath 2>/dev/null || true)
  if [[ "$hp" == "$githooks_dir" || "$hp" == "$repo_root/$githooks_dir" ]]; then
    _doc_add "git_hooks" "ok" "core.hooksPath=$hp" ""
  else
    _doc_add "git_hooks" "warn" "core.hooksPath='${hp:-unset}' (expected $githooks_dir)" "git config core.hooksPath $githooks_dir"
  fi
  local _cs_ok=1 _cs_bad="" _cs_f _cs_dir="$repo_root/$scripts_dir"
  [[ -f "$_cs_dir/lib-gate-cold.sh" ]] || _cs_dir="$repo_root/resources/templates"
  for _cs_f in lib-json.sh lib-gate-cold.sh; do
    if [[ ! -f "$_cs_dir/$_cs_f" ]] || ! /bin/bash -n "$_cs_dir/$_cs_f" >/dev/null 2>&1; then
      _cs_ok=0; _cs_bad="${_cs_bad:+$_cs_bad }$_cs_f"
    fi
  done
  local _ag_f="$repo_root/$scripts_dir/agent-gate"
  [[ -f "$_ag_f" ]] || _ag_f="$repo_root/resources/templates/agent-gate.sh"
  if [[ ! -f "$_ag_f" ]] || ! /bin/bash -n "$_ag_f" >/dev/null 2>&1; then
    _cs_ok=0; _cs_bad="${_cs_bad:+$_cs_bad }agent-gate"
  fi
  if [[ "$_cs_ok" -eq 1 ]]; then
    _doc_add "core_scripts" "ok" "agent-gate + lib-json + lib-gate-cold present & valid" ""
  else
    _doc_add "core_scripts" "fail" "missing or invalid bash syntax: $_cs_bad" "bash scripts/bootstrap.sh --guard ."
  fi
  if [[ -f "$repo_root/.agent-governance.yml" ]]; then
    if grep -q '<replace-with-project-test-command>' "$repo_root/.agent-governance.yml" 2>/dev/null && [[ -z "${AGENT_GUARD_VERIFY_COMMAND:-}" ]]; then
      _doc_add "verify_channel" "warn" "ci.verification_command is still placeholder" "set ci.verification_command in .agent-governance.yml or AGENT_GUARD_VERIFY_COMMAND"
    else
      _doc_add "verify_channel" "ok" ".agent-governance.yml configured" ""
    fi
  else
    _doc_add "verify_channel" "warn" ".agent-governance.yml not found" "bash scripts/bootstrap.sh --guard ."
  fi
  local _ad_found=""
  for _ad_p in "$repo_root/.agents/hooks.json" "$repo_root/.claude/settings.json" "$repo_root/.cursor/hooks.json" "$repo_root/.gemini/settings.json" "$repo_root/.opencode/plugins"; do
    if [[ -e "$_ad_p" ]]; then _ad_found="$_ad_p"; break; fi
  done
  if [[ -n "$_ad_found" ]]; then
    _doc_add "client_adapter" "ok" "found ${_ad_found#"$repo_root/"}" ""
  else
    _doc_add "client_adapter" "warn" "no client hook adapter detected" "scripts/install-hook-adapter"
  fi
  local _ac_id _ac_ok=0
  _ac_id=$(active_change_quiet)
  if [[ -z "$_ac_id" ]]; then
    _doc_add "active_change" "ok" "none active" ""
  else
    local _ac_dir
    _ac_dir=$(change_dir "$_ac_id" 2>/dev/null || true)
    if [[ -n "$_ac_dir" && -d "$_ac_dir" ]] || is_change_card "$_ac_id"; then _ac_ok=1; fi
    if [[ "$_ac_ok" -eq 1 ]]; then
      _doc_add "active_change" "ok" "active=$_ac_id" ""
    else
      _doc_add "active_change" "fail" "active-change '$_ac_id' points to missing dir/card" "scripts/agent-gate start $_ac_id"
    fi
  fi
  local _em _em_raw="${AGENT_GUARD_ENFORCEMENT_MODE:-}"
  if [[ -z "$_em_raw" && -f "$repo_root/.agent-governance.yml" ]]; then
    _em_raw=$(sed -nE '/^enforcement:[[:space:]]*$/,/^[^[:space:]#]/s/^[[:space:]]+mode:[[:space:]]*([^#]*).*$/\1/p' "$repo_root/.agent-governance.yml" 2>/dev/null \
      | head -n 1 | tr -d "[:space:]\"'" || true)
  fi
  _em=$(enforcement_mode 2>/dev/null || echo strict)
  if [[ -n "$_em_raw" && "$_em_raw" != "strict" && "$_em_raw" != "ratchet" && "$_em_raw" != "advisory" ]]; then
    _doc_add "enforcement_mode" "warn" "invalid mode '$_em_raw' (falling back to strict)" "set strict|ratchet|advisory in .agent-governance.yml"
  else
    _doc_add "enforcement_mode" "ok" "mode=$_em" ""
  fi
  if [[ "$jmode" -eq 1 ]]; then
    printf '{"passed":%d,"warned":%d,"failed":%d,"enforcement_mode":"%s","checks":[%s]}\n' \
      "$pass" "$warn" "$fail" "$(json_escape "$_em")" "$checks_json"
  else
    printf 'doctor: %d ok, %d warn, %d fail (mode=%s)\n' "$pass" "$warn" "$fail" "$_em"
  fi
  [[ "$fail" -eq 0 ]]
}

_cold_run_with_timeout() { # <secs> <dir> <outfile> <cmd> -> rc (124 on timeout)
  local secs="${1:-300}" dir="$2" outf="$3" cmd="$4" pid wpid rc=0 to_flag="${3}.to"
  rm -f "$to_flag"
  ( cd "$dir" && eval "$cmd" ) >"$outf" 2>&1 &
  pid=$!
  (
    sleep "$secs" 2>/dev/null || exit 0
    if kill -0 "$pid" 2>/dev/null; then
      : > "$to_flag"
      pkill -TERM -P "$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1 2>/dev/null || true
      pkill -KILL -P "$pid" 2>/dev/null || true
      kill -KILL "$pid" 2>/dev/null || true
    fi
  ) >/dev/null 2>&1 &
  wpid=$!
  wait "$pid" 2>/dev/null || rc=$?
  pkill -KILL -P "$wpid" 2>/dev/null || true
  kill -KILL "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  if [[ -f "$to_flag" ]]; then
    rm -f "$to_flag"
    return 124
  fi
  return "$rc"
}

_cold_is_test_path() { # <relpath> -> 0 if test file
  local p="$1" tdir=""
  if [[ -f "$repo_root/.agent-governance.yml" ]]; then
    tdir=$(sed -nE '/^paths:[[:space:]]*$/,/^[^[:space:]#]/s/^[[:space:]]+tests:[[:space:]]*([^#]*).*$/\1/p' "$repo_root/.agent-governance.yml" 2>/dev/null | head -1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$tdir" ]] || tdir="tests"
  case "$p" in
    "${tdir}/"*|*/"${tdir}/"*) return 0 ;;
  esac
  [[ "$p" =~ (^|/)(tests?|spec|__tests__|e2e)/|(\.|_)(test|spec)\.|_test\.|(^|/)test_ ]] && return 0
  return 1
}

f2p_replay_run() { # <id> <dir> <risk> [base-override] -> sets _F2P_STATUS, _F2P_DETAIL, _F2P_ELAPSED
  local id="$1" d="$2" risk="$3" base_override="${4:-}" f05="$2/05-test-results.md"
  local raw_cmd="" cmd="" base_sha="" br_file="" setup_cmd="" tmo="${AGENT_GUARD_F2P_TIMEOUT:-300}"
  local norm_cmd cmd_sha tree_fp test_sig cache_key receipt_f hist_f t0 t1
  local tmpd="" wt1="" wt2="" out1 out2 out_s1 out_s2 rc1=0 rc2=0 rcls="" rcls2=""
  local tf f_list="" t_files=""
  _F2P_STATUS="replay-failed"; _F2P_DETAIL=""; _F2P_ELAPSED=0
  [[ "$tmo" =~ ^[0-9]+$ && "$tmo" -gt 0 ]] || tmo=300
  receipt_f="$repo_root/.agent-state/f2p-${id}.json"
  hist_f="$repo_root/.agent-state/f2p-history.tsv"
  mkdir -p "$repo_root/.agent-state" 2>/dev/null || true

  if [[ ! -s "$f05" ]]; then
    _F2P_DETAIL="missing 05-test-results.md"; return 2
  fi
  raw_cmd=$(sed -nE 's/^[[:space:]]*red_repro:[[:space:]]*//p' "$f05" 2>/dev/null | head -1 || true)
  cmd=$(printf '%s' "$raw_cmd" | sed -E 's/[[:space:]]+->[[:space:]]+.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^`+//; s/`+$//')
  if [[ -z "$cmd" ]] || grep -qE 'FILL|待填|<' <<< "$cmd"; then
    _F2P_DETAIL="missing or placeholder red_repro command in $f05"; return 2
  fi

  br_file=$(git -C "$repo_root" rev-parse --git-path "agent-governance/begin-receipts/${id}.json" 2>/dev/null || true)
  [[ -n "$br_file" && "$br_file" != /* ]] && br_file="$repo_root/$br_file"
  if [[ -s "$br_file" ]]; then
    base_sha=$(sed -n 's/.*"begin_sha":"\([^"]*\)".*/\1/p' "$br_file" 2>/dev/null | head -1 || true)
  fi
  if [[ -z "$base_sha" && -n "$base_override" ]] && git -C "$repo_root" cat-file -e "${base_override}^{commit}" 2>/dev/null; then
    base_sha="$base_override"
  fi
  if [[ -z "$base_sha" ]] || ! git -C "$repo_root" cat-file -e "${base_sha}^{commit}" 2>/dev/null; then
    base_sha=$(git -C "$repo_root" rev-parse HEAD~1 2>/dev/null || git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)
  fi
  if [[ -z "$base_sha" ]] || ! git -C "$repo_root" cat-file -e "${base_sha}^{commit}" 2>/dev/null; then
    _F2P_STATUS="unverifiable"; _F2P_DETAIL="cannot resolve valid baseline commit"; return 2
  fi

  norm_cmd=$(_cold_norm_cmd "$cmd")
  cmd_sha=$(_cold_str_sha256 "$norm_cmd")
  local _ign_re="^(\\.agent-state/|${docs_dir}/|${change_root}/|${bugs_root}/)"
  tree_fp=$(cd "$repo_root" && { git diff --name-only "$base_sha" 2>/dev/null; git diff --name-only --cached 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; git ls-files 2>/dev/null | head -n 50; } | awk 'NF' | { grep -vE "$_ign_re" || true; } | sort -u | while IFS= read -r _p; do [[ -f "$repo_root/$_p" ]] && cksum "$repo_root/$_p" 2>/dev/null || printf 'D %s\n' "$_p"; done | cksum | awk '{print $1}')
  cache_key="${base_sha}:${tree_fp}:${cmd_sha}"
  if [[ -s "$receipt_f" ]] && grep -qF "\"cache_key\":\"$cache_key\"" "$receipt_f" 2>/dev/null && grep -qF '"status":"verified"' "$receipt_f" 2>/dev/null; then
    _F2P_STATUS="verified"; _F2P_DETAIL="cached (${cache_key})"
    echo "agent-gate: f2p replay cached (status=verified, cache_key=$cache_key)" >&2
    return 0
  fi

  if [[ -f "$repo_root/.agent-governance.yml" ]]; then
    setup_cmd=$(sed -nE 's/^[[:space:]]*replay_setup_command:[[:space:]]*//p' "$repo_root/.agent-governance.yml" 2>/dev/null | head -1 | sed -E 's/[[:space:]]*#.*$//;s/^[[:space:]]+//;s/[[:space:]]+$//;s/^["'\'']//;s/["'\'']$//' || true)
  fi

  t_files=$(cd "$repo_root" && { git diff --name-only "$base_sha" 2>/dev/null; git diff --name-only --cached 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | awk 'NF' | sort -u)
  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/ag-f2p.XXXXXX")
  wt1="$tmpd/wt1"; wt2="$tmpd/wt2"
  out1="$tmpd/out1.txt"; out2="$tmpd/out2.txt"; out_s1="$tmpd/s1.txt"; out_s2="$tmpd/s2.txt"
  _f2p_cleanup() {
    git -C "$repo_root" worktree remove --force "$wt1" >/dev/null 2>&1 || true
    git -C "$repo_root" worktree remove --force "$wt2" >/dev/null 2>&1 || true
    [[ -n "$tmpd" ]] && rm -rf "$tmpd" 2>/dev/null || true
  }

  t0=$(date +%s 2>/dev/null || echo 0)
  if ! git -C "$repo_root" worktree add --detach "$wt1" "$base_sha" >/dev/null 2>&1; then
    _f2p_cleanup
    _F2P_STATUS="unverifiable"; _F2P_DETAIL="git worktree add failed for base_sha $base_sha"; return 2
  fi
  while IFS= read -r tf; do
    [[ -n "$tf" && -f "$repo_root/$tf" ]] || continue
    _cold_is_test_path "$tf" || continue
    mkdir -p "$wt1/$(dirname "$tf")" 2>/dev/null || true
    cp -p "$repo_root/$tf" "$wt1/$tf" 2>/dev/null || true
  done <<< "$t_files"
  if [[ -n "$setup_cmd" ]]; then
    if ! _cold_run_with_timeout "$tmo" "$wt1" "$out_s1" "$setup_cmd"; then
      _F2P_STATUS="unverifiable"; _F2P_DETAIL="replay_setup_command failed on baseline worktree"
    fi
  fi
  if [[ "$_F2P_STATUS" != "unverifiable" ]]; then
    rc1=0; _cold_run_with_timeout "$tmo" "$wt1" "$out1" "$cmd" || rc1=$?
    if [[ "$rc1" -eq 124 ]]; then
      _F2P_STATUS="unverifiable"; _F2P_DETAIL="baseline+test replay timed out after ${tmo}s"
    elif [[ "$rc1" -eq 0 ]]; then
      _F2P_STATUS="replay-failed"; _F2P_DETAIL="baseline+test unexpectedly passed rc=0 (test does not reproduce bug)"
    else
      rcls=$(classify_red_output "$rc1" "$out1")
      if [[ "$rcls" == "red-error" ]]; then
        _F2P_STATUS="unverifiable"; _F2P_DETAIL="baseline+test hit red-error (rc=$rc1)"
      elif [[ "$rcls" != "red-assertion" ]]; then
        _F2P_STATUS="replay-failed"; _F2P_DETAIL="baseline+test produced $rcls output (requires red-assertion)"
      else
        if ! git -C "$repo_root" worktree add --detach "$wt2" HEAD >/dev/null 2>&1; then
          _F2P_STATUS="unverifiable"; _F2P_DETAIL="git worktree add failed for fixed HEAD"
        else
          local _wf
          while IFS= read -r _wf; do
            [[ -n "$_wf" && "$_wf" != .git/* ]] || continue
            if [[ -f "$repo_root/$_wf" ]]; then
              mkdir -p "$wt2/$(dirname "$_wf")" 2>/dev/null || true
              cp -p "$repo_root/$_wf" "$wt2/$_wf" 2>/dev/null || true
            else
              rm -f "$wt2/$_wf" 2>/dev/null || true
            fi
          done <<< "$(cd "$repo_root" && { git diff --name-only 2>/dev/null; git diff --name-only --cached 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | awk 'NF' | sort -u)"
          if [[ -n "$setup_cmd" ]] && ! _cold_run_with_timeout "$tmo" "$wt2" "$out_s2" "$setup_cmd"; then
            _F2P_STATUS="unverifiable"; _F2P_DETAIL="replay_setup_command failed on fixed worktree"
          else
            rc2=0; _cold_run_with_timeout "$tmo" "$wt2" "$out2" "$cmd" || rc2=$?
            if [[ "$rc2" -eq 124 ]]; then
              _F2P_STATUS="unverifiable"; _F2P_DETAIL="fixed tree replay timed out after ${tmo}s"
            elif [[ "$rc2" -eq 0 ]]; then
              _F2P_STATUS="verified"; _F2P_DETAIL="baseline red-assertion (rc=$rc1) -> fixed rc=0"
            else
              rcls2=$(classify_red_output "$rc2" "$out2")
              if [[ "$rcls2" == "red-error" ]]; then
                _F2P_STATUS="unverifiable"; _F2P_DETAIL="fixed tree hit red-error (rc=$rc2)"
              else
                _F2P_STATUS="replay-failed"; _F2P_DETAIL="fixed tree test still fails (rc=$rc2, class=$rcls2)"
              fi
            fi
          fi
        fi
      fi
    fi
  fi
  t1=$(date +%s 2>/dev/null || echo 0)
  _F2P_ELAPSED=$(( t1 - t0 ))
  [[ "$_F2P_ELAPSED" -ge 0 ]] 2>/dev/null || _F2P_ELAPSED=0
  local sha_r="" sha_g="" ts_now
  [[ -s "$out1" ]] && sha_r=$(_cold_sha256 "$out1")
  [[ -s "$out2" ]] && sha_g=$(_cold_sha256 "$out2")
  ts_now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
  printf '{"change_id":"%s","status":"%s","base_sha":"%s","cache_key":"%s","red_class":"%s","red_sha":"%s","green_sha":"%s","elapsed_s":%d,"detail":"%s","recorded_at":"%s"}\n' \
    "$(json_escape "$id")" "$(json_escape "$_F2P_STATUS")" "$(json_escape "$base_sha")" "$(json_escape "$cache_key")" \
    "$(json_escape "${rcls:-none}")" "$(json_escape "${sha_r:-}")" "$(json_escape "${sha_g:-}")" \
    "$_F2P_ELAPSED" "$(json_escape "$_F2P_DETAIL")" "$(json_escape "$ts_now")" > "$receipt_f"
  printf '%s\t%s\t%s\t%s\n' "$ts_now" "$id" "$_F2P_STATUS" "$_F2P_ELAPSED" >> "$hist_f"
  _f2p_cleanup
  [[ "$_F2P_STATUS" == "verified" ]]
}

mutation_spot_cmd() { # --file <path> --cmd "<cmd>" [--json]
  local file="" cmd="" jmode=0 bak="" outf="" rc0=0 tested=0 killed=0 survived=0 lno kind mut_line
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="${2:-}"; shift 2 ;;
      --cmd)  cmd="${2:-}"; shift 2 ;;
      --json) jmode=1; shift ;;
      *) echo "agent-gate: mutation-spot unknown argument '$1'" >&2; exit 2 ;;
    esac
  done
  [[ -n "$file" && -f "$file" && -n "$cmd" ]] || { echo "agent-gate: usage: scripts/agent-gate mutation-spot --file <path> --cmd \"<cmd>\" [--json]" >&2; exit 2; }
  outf=$(mktemp "${TMPDIR:-/tmp}/ag-mut-out.XXXXXX")
  _cold_run_with_timeout 60 "$repo_root" "$outf" "$cmd" || rc0=$?
  if [[ "$rc0" -ne 0 ]]; then
    rm -f "$outf"
    echo "agent-gate: mutation-spot baseline command failed (rc=$rc0)" >&2
    exit 2
  fi
  bak=$(mktemp "${TMPDIR:-/tmp}/ag-mut-bak.XXXXXX")
  cp -p "$file" "$bak"
  _mut_restore() {
    [[ -n "${bak:-}" && -f "$bak" ]] && cp "$bak" "$file" 2>/dev/null || true
    rm -f "${bak:-}" "${outf:-}" 2>/dev/null || true
  }
  trap '_mut_restore' EXIT INT TERM

  local cands tmp_new
  cands=$(awk '
    /^[[:space:]]*(#|\/\/|\/\*|\*|$)/ { next }
    {
      mkind = ""
      if (!seen["cmp"] && $0 ~ /==/) {
        mkind = "cmp_eq"
      } else if (!seen["cmp"] && $0 ~ /!=/) {
        mkind = "cmp_ne"
      } else if (!seen["cmp"] && $0 ~ / -eq /) {
        mkind = "cmp_dash_eq"
      } else if (!seen["ret"] && $0 ~ /(^|[^A-Za-z0-9_])return 0([^0-9]|$)/) {
        mkind = "ret_0"
      } else if (!seen["ret"] && $0 ~ /(^|[^A-Za-z0-9_])exit 0([^0-9]|$)/) {
        mkind = "ret_exit0"
      } else if (!seen["ret"] && $0 ~ /(^|[^A-Za-z0-9_])return true([^A-Za-z0-9_]|$)/) {
        mkind = "ret_true"
      } else if (!seen["ret"] && $0 ~ /(^|[^A-Za-z0-9_])return True([^A-Za-z0-9_]|$)/) {
        mkind = "ret_True"
      } else if (!seen["bra"] && $0 ~ /(^|[^A-Za-z0-9_])return 1([^0-9]|$)/) {
        mkind = "br_ret1"
      } else if (!seen["bra"] && $0 ~ / -gt /) {
        mkind = "br_gt"
      } else if (!seen["bra"] && $0 ~ / -lt /) {
        mkind = "br_lt"
      }
      if (mkind != "") {
        if (substr(mkind, 1, 2) == "br") seen["bra"] = 1
        else seen[substr(mkind, 1, 3)] = 1
        printf "%d\t%s\n", NR, mkind
        cnt++
        if (cnt >= 3) exit
      }
    }
  ' "$bak" 2>/dev/null || true)

  if [[ -n "$cands" ]]; then
    tmp_new=$(mktemp "${TMPDIR:-/tmp}/ag-mut-new.XXXXXX")
    while IFS=$'\t' read -r lno kind; do
      [[ -n "$lno" && -n "$kind" ]] || continue
      awk -v target="$lno" -v mkind="$kind" '
        NR == target {
          if (mkind == "cmp_eq") sub(/==/, "!=")
          else if (mkind == "cmp_ne") sub(/!=/, "==")
          else if (mkind == "cmp_dash_eq") sub(/ -eq /, " -ne ")
          else if (mkind == "ret_0") sub(/return 0/, "return 1")
          else if (mkind == "ret_exit0") sub(/exit 0/, "exit 1")
          else if (mkind == "ret_true") sub(/return true/, "return false")
          else if (mkind == "ret_True") sub(/return True/, "return False")
          else if (mkind == "br_ret1") sub(/return 1/, "return 0")
          else if (mkind == "br_gt") sub(/ -gt /, " -le ")
          else if (mkind == "br_lt") sub(/ -lt /, " -ge ")
        }
        { print }
      ' "$bak" > "$tmp_new"
      cp "$tmp_new" "$file"
      tested=$(( tested + 1 ))
      local mrc=0
      _cold_run_with_timeout 60 "$repo_root" "$outf" "$cmd" || mrc=$?
      cp "$bak" "$file"
      if [[ "$mrc" -ne 0 ]]; then
        killed=$(( killed + 1 ))
      else
        survived=$(( survived + 1 ))
      fi
    done <<< "$cands"
    rm -f "$tmp_new" 2>/dev/null || true
  fi

  _mut_restore
  trap - EXIT INT TERM
  local status="killed" cmd_sha
  if [[ "$tested" -eq 0 ]]; then status="no_applicable_mutants"
  elif [[ "$killed" -eq 0 ]]; then status="survived"; fi
  cmd_sha=$(_cold_str_sha256 "$cmd")
  mkdir -p "$repo_root/.agent-state" 2>/dev/null || true
  printf '{"file":"%s","cmd_sha":"%s","mutants_tested":%d,"killed":%d,"survived":%d,"status":"%s"}\n' \
    "$(json_escape "$file")" "$(json_escape "$cmd_sha")" "$tested" "$killed" "$survived" "$status" > "$repo_root/.agent-state/mutation-spot.json"
  if [[ "$jmode" -eq 1 ]]; then
    cat "$repo_root/.agent-state/mutation-spot.json"
  else
    printf 'agent-gate: mutation-spot %s: tested=%d killed=%d survived=%d status=%s\n' "$file" "$tested" "$killed" "$survived" "$status"
  fi
  if [[ "$tested" -gt 0 && "$killed" -eq 0 ]]; then
    echo "agent-gate: mutation-spot failed — 0 of $tested injected mutants killed (weak/tautological test)" >&2
    exit 2
  fi
  exit 0
}

print_help_cmd() {
  cat <<'EOF'
Usage:
  scripts/agent-gate begin <change-id>
  scripts/agent-gate end
  scripts/agent-gate metrics [--summary [--json]]
  scripts/agent-gate doctor [--json]               # read-only governance health diagnostics (v4.10.0)
  scripts/agent-gate session-start          # v3.90.2: write the session handshake (runtime/model/window, P0-1)
  scripts/agent-gate plan <change-id> [--dry-run|--explain]  # v3.90.2: read-only test-scope decision (P1-1/P1-2)
  scripts/agent-gate baseline <change-id> [--write]          # v3.90.5: 5-number baseline snapshot (P0-0)
  scripts/agent-gate tc-index <change-id> [--write]          # v3.90.5: three-source TC index cache (P1-2)
  scripts/agent-gate review-plan <change-id> [--json|--write|--approve <model>]  # v3.90.4: runtime-aware review plan; deep/high-cost needs USER consent
  scripts/agent-gate start <change-id> [--risk L0|L1|L2|L3]  # v4.8.0: atomic scaffold + session-start + begin (ITEM-25)
  scripts/agent-gate advance [change-id]                     # v4.8.0: auto-advance next unpassed stage gate (ITEM-26)
  scripts/agent-gate next [change-id] [--json]               # v4.8.0: read-only state-machine wizard (ITEM-27)
  scripts/agent-gate fix [change-id]                         # v4.8.0: mechanical P00-P12 / RTVM / provenance fix (ITEM-28)
  scripts/agent-gate record-red <change-id> [--layer unit|api|e2e|manual] [--target-tests <spec>] [--accept-unclassified <reason>] -- <cmd> # v4.8.0/v4.15.0: record classified red-first receipt
  scripts/agent-gate record-green <change-id> -- <cmd>       # v4.15.0: record matching green receipt after tree change
  scripts/agent-gate escape <BUG-id> --should-catch <layer>  # v4.15.0: register post-claim defect escape + eval case
  scripts/agent-gate mutation-spot --file <path> --cmd "<cmd>" [--json] # v4.15.1: 3-mutant spot check for target repos
  scripts/agent-gate review-models [--discover|--print-contract|--verify [path]] # v4.7.0: zero-dep review model discovery & schema check (ITEM-17)
  scripts/agent-gate dispatch <stage> [CHG] [--json]   # v3.94.0: read-only P0-P8 dispatch-prompt skeleton (never a gate)
  scripts/agent-gate cost-line <change-id>        # v3.90.2: append the execution-cost line to 09 (P0-15)
  scripts/agent-gate --stage pre-write [--file path]
  scripts/agent-gate --stage spec | --stage design | --stage testplan   # v3.89.0: stateless stage gates (CHG-117)
  scripts/agent-gate --stage core   # v3.92.2: stateless E150/E151/E153 (environment + red→green + independence)
  scripts/agent-gate --stage scope  # v3.92.2: stateless E152 (change-scope budget)
  scripts/agent-gate --stage rtvm   # v3.92.2: stateless E154 (unverified RTVM REQs must be declared)
  scripts/agent-gate --stage shift               # v3.91.7: pre-push handoff gate (E112, no suite)
  scripts/agent-gate --stage staged
  scripts/agent-gate --stage stop               # v3.83.0: successful-verify receipt cache (key = version+cmd+tree-fingerprint+change-id, TTL 30min, rc=0 only; repos whose tests read external mutable state set AGENT_GUARD_VERIFY_CACHE=0)
  scripts/agent-gate --stage ci [--base ref]
  scripts/agent-gate --stage commit-msg <message-file>
  scripts/agent-gate check-confirm <change-id>   # exit 0/1/2, read-only (v3.55.0)
  scripts/agent-gate verify-channel              # exit 0/2, read-only channel probe (v3.76.0)
  scripts/agent-gate check-smoke                 # exit 0/1/2, read-only (v3.71.0)
  scripts/agent-gate preflight <change-id> [--json] # exit 0/1/2, read-only probe (v3.72.0; v3.82.0 adds the delivery shape face E85/E114/E115/E117/E46)

metrics prints one JSON object per change (JSON Lines) with stage timestamps and derived review/artifact telemetry.
All projects are governed against 13 project masters (P00..P12) under docs/project/.
EOF
}
fi
