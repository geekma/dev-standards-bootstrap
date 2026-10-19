#!/usr/bin/env bash
# A deterministic guard shared by local hooks, Git hooks, and CI.
# It deliberately validates evidence and execution state; it never trusts an
# agent's natural-language claim that a check has run.
set -euo pipefail

die() {
  echo "agent-gate: $*" >&2
  # v3.43.0 (REQ-960): gate 摩擦事件账（append-only TSV，metrics 侧聚合）。
  # fail-open：缺 .agent-state 或写失败不影响拒绝语义；TSV 而非 JSON——bash 零依赖。
  local _code="${1%%:*}" _re='^GATE-E[0-9]+$'
  if [[ -d ".agent-state" && "$_code" =~ $_re ]]; then
    printf '%s\t%s\n' "$_code" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
      >> ".agent-state/gate-friction.tsv" 2>/dev/null || true
  fi
  exit 2
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "GATE-E01: run inside a Git repository"

gate_epoch() { # <iso8601Z> — GNU then BSD, 0 on failure (v3.63.0 GATE-E89 helper)
  date -u -d "$1" +%s 2>/dev/null || date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || echo 0
}
gate_mtime() { # <file> — GNU then BSD stat, 0 on failure (v3.67.0 erratum CHG-092:
  # BSD-first ordering is unreachable on Linux: GNU stat accepts -f as
  # filesystem-status mode where %m is an unknown directive — it prints '?m'
  # and exits 0 (coreutils stat.c print_statfs default branch), so the GNU
  # fallback never fires. GNU-first works on both: BSD stat has no -c.)
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# --- review convergence & finding disposition (v3.74.0, CHG-098) ------------
# Review rounds are DERIVED from disk, never self-reported: the ledger keeps one
# row per distinct content revision of a change's 07-review-report.md observed
# at gate time, so begin/staged/stop/ci runs on unchanged content add nothing
# (idempotent). A missing .agent-state is fail-open — no counting, no E116;
# E114/E115 depend only on the report text, never on the ledger.
review_round_limit() { # AGENT_GUARD_REVIEW_ROUND_LIMIT, invalid => 3
  local l="${AGENT_GUARD_REVIEW_ROUND_LIMIT:-3}"
  [[ "$l" =~ ^[0-9]+$ ]] || l=3
  printf '%s' "$l"
}

review_round_hash() { # <file> — shasum (macOS) then sha256sum (Linux), cksum last
  if [[ ! -s "$1" ]]; then printf ''; return 0; fi
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else cksum "$1" | awk '{print $1"-"$2}'
  fi
}

review_rounds_of() { # <change-id> — distinct recorded hashes (0 when absent)
  local id="$1"
  [[ -f ".agent-state/review-rounds.tsv" ]] || { printf '0'; return 0; }
  awk -F'\t' -v k="$id" '$1==k && $2!="" {c++} END{print c+0}' \
    .agent-state/review-rounds.tsv 2>/dev/null || printf '0'
}

track_review_round() { # <dir> <change-id> <report-file>
  local d="$1" id="$2" f="$3" hash rounds limit
  [[ -s "$f" ]] || return 0
  hash=$(review_round_hash "$f")
  [[ -n "$hash" ]] || return 0
  if [[ -d ".agent-state" ]]; then
    # grep -F on the id+hash pair: a row for THIS revision already recorded
    # means no new round — the ledger is append-only, never rewritten.
    if ! grep -qF -- "$(printf '%s\t%s' "$id" "$hash")" ".agent-state/review-rounds.tsv" 2>/dev/null; then
      printf '%s\t%s\t%s\n' "$id" "$hash" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
        >> ".agent-state/review-rounds.tsv" 2>/dev/null || true
    fi
  fi
  rounds=$(review_rounds_of "$id")
  limit=$(review_round_limit)
  if [[ "${rounds:-0}" -gt "$limit" ]]; then
    echo "agent-gate: YELLOW: $id review rounds $rounds exceed the cap $limit (standards §2.2 convergence; raise AGENT_GUARD_REVIEW_ROUND_LIMIT only with a recorded reason)" >&2
    # Conditional shape requirement, not a ban on reviewing: past the cap the
    # author must record what "step back and reconsider the approach" produced.
    # The predicate is a FILLED line, not a bare substring: the shape template
    # itself carries the words 「超限处置」 in its guidance comment and in a
    # placeholder line, so a literal grep would be short-circuited by any
    # template-derived report (found in independent review of CHG-098, F3).
    grep -qE '^[[:space:]]*-[[:space:]]*\*\*超限处置\*\*(：|:)[[:space:]]*[^[:space:]<]' "$f" \
      || die "GATE-E116: $d/07-review-report.md exceeded the review-round cap ($rounds > $limit) without a filled 「超限处置」 line — review must converge by re-considering the approach, not by another pass (standards §2.2 review convergence, v3.74.0 CHG-098)"
  fi
  return 0
}

assert_finding_disposition() { # <dir> <report-file>
  local d="$1" f="$2" bad rows dhead ddecl e115
  [[ -s "$f" ]] || return 0
  # Stage 1 — structural guard (E115): the disposition lane is part of the
  # stage-8 review-report shape. Two accepted forms: a 「发现处置」 section
  # carrying at least one REAL finding row, or the single-line declaration
  # (mirrors §1.1) for a review with nothing to dispose of. Angle-bracket
  # placeholder rows and header/separator/short rows are not data rows —
  # otherwise the shape template itself would satisfy the guard (v3.74.0
  # independent review of CHG-098, same short-circuit class as F3).
  dhead='^#{1,6}[[:space:]]*发现处置'
  ddecl='^[[:space:]]*-[[:space:]]*\*\*发现处置\*\*(：|:)[[:space:]]*未命中，不适用（.+）'
  e115=""
  if ! grep -qE "$dhead" "$f" && ! grep -qE "$ddecl" "$f"; then
    e115="missing the 「发现处置」 section (declare 未命中 when there is nothing to dispose of)"
  fi
  rows=$(awk -F'|' '
    /^#{1,6}[[:space:]]*发现处置/ { sec=1; next }
    sec && /^#{1,6}[[:space:]]/ { sec=0 }
    !sec { next }
    /^[[:space:]]*\|/ {
      if (NF < 6) next
      id=$2
      gsub(/<!--[^>]*-->/,"",id); gsub(/[[:space:]]/,"",id)
      if (id == "" || id == "编号" || id ~ /^-+$/ || id ~ /^<.*>$/) next
      n++
    }
    END { print n+0 }' "$f" 2>/dev/null || true)
  if [[ -z "$e115" ]] && grep -qE "$dhead" "$f" && [[ "${rows:-0}" -eq 0 ]] && ! grep -qE "$ddecl" "$f"; then
    e115="「发现处置」 section carries no real finding row and no 未命中 declaration"
  fi
  if [[ -n "$e115" ]]; then
    die "GATE-E115: $d/07-review-report.md $e115 — every finding must be fixed or dismissed with a reason (standards §2.5 stage 8, v3.74.0 CHG-098)"
  fi
  grep -qE "$dhead" "$f" || return 0
  # Stage 2 — assertion (E114) by column position: an empty / 待处置
  # disposition on any real row, or a 严重 row or a security-nature finding
  # marked 「不处理」. HTML comments are stripped first so a leftover
  # `<!-- 待填 -->` cell is read as empty, not as content.
  bad=$(awk -F'|' '
    /^#{1,6}[[:space:]]*发现处置/ { sec=1; next }
    sec && /^#{1,6}[[:space:]]/ { sec=0 }
    !sec { next }
    /^[[:space:]]*\|/ {
      if (NF < 6) next
      id=$2; sev=$4; dis=$5
      gsub(/<!--[^>]*-->/,"",id); gsub(/<!--[^>]*-->/,"",sev); gsub(/<!--[^>]*-->/,"",dis)
      gsub(/[[:space:]]/,"",id); gsub(/[[:space:]]/,"",sev); gsub(/[[:space:]]/,"",dis)
      if (id == "" || id == "编号" || id ~ /^-+$/ || id ~ /^<.*>$/) next
      if (dis == "" || dis ~ /^(待处置|未处置|PENDING|TODO|待定)$/) { print; next }
      if (sev ~ /^严重/ && dis ~ /^不处理/) print
      if ($3 ~ /安全|security/ && dis ~ /^不处理/) print
    }' "$f" 2>/dev/null || true)
  [[ -z "$bad" ]] || die "GATE-E114: $d/07-review-report.md has an undisposed finding — an empty / 待处置 disposition, or a 严重 or security-nature finding marked 「不处理」; fix it or dismiss it with a reason (standards §2.5 stage 8, v3.74.0 CHG-098)"
  return 0
}

finding_source_counts() { # <report-file> — prints "<introduced> <pre_existing> <none>" (none=1 when no 来源 column)
  local f=$1 has col
  has=$(awk -F'|' '
    /^#{1,6}[[:space:]]*发现处置/ { sec=1; next }
    sec && /^#{1,6}[[:space:]]/ { exit }
    !sec { next }
    /^[[:space:]]*\|/ {
      for (i = 1; i <= NF; i++) {
        t = $i; gsub(/<!--[^>]*-->/, "", t); gsub(/[[:space:]]/, "", t)
        if (t == "来源") { print 1; exit }
      }
    }' "$f" 2>/dev/null || true)
  [[ "$has" = 1 ]] || { printf '0 0 1'; return 0; }
  awk -F'|' '
    /^#{1,6}[[:space:]]*发现处置/ { sec=1; next }
    sec && /^#{1,6}[[:space:]]/ { sec=0 }
    !sec { next }
    /^[[:space:]]*\|/ {
      if (NF < 6) next
      id = $2; src = $(NF - 1)
      for (i = 1; i <= NF; i++) gsub(/<!--[^>]*-->/, "", $i)
      id = $2; src = $(NF - 1)
      gsub(/[[:space:]]/, "", id); gsub(/[[:space:]]/, "", src)
      if (id == "" || id == "编号" || id ~ /^-+$/ || id ~ /^<.*>$/) next
      if (src == "本次引入") a++
      else if (src == "既有存量") b++
    } END { printf "%d %d 0", a + 0, b + 0 }' "$f" 2>/dev/null || printf '0 0 0'
}

assert_finding_source() { # <dir> <report-file> — v3.75.0 (CHG-099, REQ-1111, GATE-E117)
  local d=$1 f=$2 counts bad
  [[ -s "$f" ]] || return 0
  grep -qE '^#{1,6}[[:space:]]*发现处置' "$f" || return 0
  counts=$(finding_source_counts "$f")
  if [[ "${counts##* }" = 1 ]]; then
    # Backward-compatible upgrade path (user-adjudicated): pre-v3.75.0 report
    # shapes carry a five-column table — a soft notice, never a hard stop.
    printf 'agent-gate: notice: %s/07-review-report.md 发现处置表缺「来源」列（v3.75.0 CHG-099 新增；存量形状放行，新变更请补列）\n' "$d" >&2
    return 0
  fi
  bad=$(awk -F'|' '
    /^#{1,6}[[:space:]]*发现处置/ { sec=1; next }
    sec && /^#{1,6}[[:space:]]/ { sec=0 }
    !sec { next }
    /^[[:space:]]*\|/ {
      if (NF < 6) next
      id = $2
      for (i = 1; i <= NF; i++) gsub(/<!--[^>]*-->/, "", $i)
      id = $2; src = $(NF - 1)
      gsub(/[[:space:]]/, "", id); gsub(/[[:space:]]/, "", src)
      if (id == "" || id == "编号" || id ~ /^-+$/ || id ~ /^<.*>$/) next
      if (src != "本次引入" && src != "既有存量") print
    }' "$f" 2>/dev/null || true)
  [[ -z "$bad" ]] || die "GATE-E117: $d/07-review-report.md 发现处置表「来源」列取值非法（须为 本次引入 | 既有存量）— 存量问题与本次引入必须可分，否则归责信号失真 (standards §2.5 stage 8, v3.75.0 CHG-099)"
  return 0
}
record_delivery() { # <stage> — v3.63.0 (REQ-1033, DES-1822): delivery marker for begin GATE-E89
  local ac cid
  ac=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  [[ -s "$ac" ]] || return 0
  cid=$(tr -d '[:space:]' < "$ac" 2>/dev/null)
  [[ -n "$cid" ]] || return 0
  mkdir -p "$repo_root/.agent-state" 2>/dev/null || return 0
  printf '{"delivered_at":"%s","change":"%s","stage":"%s","session":""}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cid" "$1" > "$repo_root/.agent-state/last-delivery.json" 2>/dev/null \
    || echo "agent-gate: note — could not write .agent-state/last-delivery.json (shift gate degrades fail-open)" >&2
  return 0
}

# --- v3.71.0 (CHG-046, REQ-1088) + v3.71.0 erratum (CHG-093, REQ-1093/1094): -
# infra/config smoke gate (fail-closed). Trigger face: a changed path matching
# SMOKE_INFRA_RE (overridable via the .agent-governance.yml flat key
# `smoke_paths:` — comma-separated EREs; add startup-script faces like
# `\.sh$` per project). An INVALID ERE dies GATE-E111 immediately with a
# repair hint (fail-closed: a silently-skipped trigger face is worse than a
# block); a legal pattern behaves exactly as before (CHG-093). When the diff
# touches the face the repo MUST declare `smoke_command:` (the project's
# pre-commit smoke script) — undeclared blocks, per the 2026-10-14 ruling:
# fail-closed forces the project to configure. With a command declared, 05
# evidence (a 「冒烟证据」 line) is scanned in THE ACTIVE CHANGE's
# docs/changes/<id>/05-test-results.md ONLY — id read from the git-path
# agent-governance/active-change pointer (same mechanism as record_delivery);
# a line in any historical (non-active) change's 05 never satisfies the gate
# (CHG-093). Window semantics unchanged: file mtime within
# AGENT_GUARD_SMOKE_EVIDENCE_MAX_AGE_H hours, default 24; 0 disables the
# window (presence-level, still limited to the active change). Waiver: a
# 「基建冒烟」：未命中，不适用（理由） line in THAT SAME active-change 05 passes
# with a stderr warning naming the 05 path (the discipline layer records the
# justification in that change's 09). If the pointer is missing/unresolvable
# or its 05 file is absent (non-governed commit), the waiver/evidence scan
# FAILS OPEN with a stderr note (E89 evidence-precedent; the smoke_command
# configuration gate stays fail-closed) and never rescans the history (CHG-093).
SMOKE_INFRA_RE='(^|/)(pom\.xml|build\.gradle[^/]*|settings\.gradle[^/]*|application[^/]*\.(yml|yaml|properties)|\.env[^/]*|Dockerfile[^/]*|docker-compose[^/]*|Makefile)$'
smoke_abort() { # <text> — the only smoke-gate abort call site (T41 code-uniqueness)
  die "GATE-E111: $1 (v3.71.0)"
}
check_smoke_gate() { # <files...> -> dies GATE-E111 on violation; empty input = no-op
  local files="$1" re hit="" f cmd win ev ok=0 waiver now mt rc=0 acid="" target
  [[ -n "$files" ]] || return 0
  re=$(cfg_path smoke_paths "")
  [[ -n "$re" ]] || re="$SMOKE_INFRA_RE"
  local e111=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # v3.71.0 erratum (CHG-093): three-way rc — 0 hit, 1 keep scanning, >=2 an
    # invalid ERE (fail-closed die; a silently-skipped trigger face would
    # defeat the whole gate). The default SMOKE_INFRA_RE is a constant and
    # cannot be invalid; only user-supplied smoke_paths can reach here.
    rc=0
    printf '%s\n' "$f" | grep -qE "$re" || rc=$?
    if [[ $rc -eq 0 ]]; then hit="$f"; break; fi
    if [[ $rc -ge 2 ]]; then
      # T41 die-literal uniqueness: route through the aggregate die below
      # (same GATE-E111 text, single die call site).
      e111="smoke_paths regex invalid — fix the comma-separated EREs in .agent-governance.yml (smoke_paths: ...); invalid pattern: $re (v3.71.0 erratum, CHG-093)"
      break
    fi
  done <<< "$files"
  [[ -z "$e111" ]] || smoke_abort "$e111"
  [[ -n "$hit" ]] || return 0
  # v3.71.0 erratum (CHG-093, REQ-1093/1094): the waiver/evidence scan face is
  # the ACTIVE change's 05 single file (pointer = git-path
  # agent-governance/active-change, record_delivery :33 same mechanism).
  # Pointer missing or its 05 absent -> the SCAN fails open with a stderr note
  # (E89 evidence-precedent) and historical changes never bless new diffs;
  # the smoke_command configuration gate below stays fail-closed regardless.
  local af scan_open=1
  af=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  if [[ -s "$af" ]]; then acid=$(tr -d '[:space:]' < "$af" 2>/dev/null || true); fi
  target="$change_root/$acid/05-test-results.md"
  if [[ -z "$acid" || ! -s "$target" ]]; then
    scan_open=0
    echo "agent-gate: smoke gate fail-open — no active change (or its 05-test-results.md is absent): waiver/evidence scan skipped (infra path: $hit) (v3.71.0 erratum, CHG-093)" >&2
  fi
  if [[ "$scan_open" == 1 ]]; then
    waiver=$(grep -lE '^[[:space:]]*-[[:space:]]*\*\*基建冒烟\*\*(：|:)[[:space:]]*未命中，不适用（.+）' \
      "$target" 2>/dev/null | head -1 || true)
    if [[ -n "$waiver" ]]; then
      echo "agent-gate: smoke gate waived via a 「基建冒烟」 declaration in $target (infra path: $hit) — record the justification in that change's 09 (v3.71.0)" >&2
      return 0
    fi
  fi
  cmd=$(cfg_path smoke_command "")
  if [[ -z "$cmd" ]]; then
    e111="diff touches the infra/config face (e.g. $hit) but no smoke command is declared — add smoke_command: to .agent-governance.yml (fail-closed, standards §2.5 stage 7; waiver: 「基建冒烟」：未命中，不适用（理由） in the active change's 05)"
  elif [[ "$scan_open" == 1 ]]; then
    win=$(cfg_path smoke_evidence_max_age_h 24)
    [[ "$win" =~ ^[0-9]+$ ]] || win=24
    # REQ-1088: the evidence LINE is always required once a command is declared;
    # the window only governs freshness (win=0 = presence-level, yml 注释同义).
    local ev_found=0
    now=$(date -u +%s)
    for ev in "$target"; do
      [[ -s "$ev" ]] || continue
      grep -qE '^[[:space:]]*-[[:space:]]*\*\*冒烟证据\*\*(：|:).+' "$ev" || continue
      ev_found=1
      [[ "$win" == "0" ]] && { ok=1; break; }
      mt=$(gate_mtime "$ev")
      [[ "$mt" -gt 0 ]] || continue
      (( now - mt <= win * 3600 )) && { ok=1; break; }
    done
    [[ "$ev_found" == 1 || -n "$e111" ]] || e111="infra diff (e.g. $hit) without a 「冒烟证据」 line in the active change's 05 ($target) — run the declared smoke command and record a 「冒烟证据」：<命令>：<结果> line in 05"
    [[ "$ev_found" != 1 || "$ok" == 1 || -n "$e111" ]] || e111="infra diff (e.g. $hit): the 「冒烟证据」 line in the active change's 05 ($target) is stale (beyond window ${win}h) — re-run the declared smoke command and refresh the evidence line"
  fi
  [[ -z "$e111" ]] \
    || smoke_abort "$e111"
}
cd "$repo_root"

# --- path roots (v3.15.0) ---------------------------------------------------
# Roots are configurable (env > yml > built-in default == the historical
# hardcoded value: zero regression for repos without `paths:`). Contract names
# and `.github/` are deliberately NOT configurable — rationale lives in DS
# 不可配置项; duplicating it here rotted twice already.
cfg_path() { # key default
  local k="$1" d="$2" v=""
  if [[ -f ".agent-governance.yml" ]]; then
    v=$(sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" .agent-governance.yml 2>/dev/null \
        | head -n 1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$v" ]] || v="$d"
  printf '%s' "$v"
}
docs_dir="${AGENT_GUARD_DOCS_DIR:-$(cfg_path docs docs)}"
scripts_dir="${AGENT_GUARD_SCRIPTS_DIR:-$(cfg_path scripts scripts)}"
tests_dir="${AGENT_GUARD_TESTS_DIR:-$(cfg_path tests tests)}"
githooks_dir="${AGENT_GUARD_GITHOOKS_DIR:-$(cfg_path githooks .githooks)}"
# change_root / bugs_root keep their own keys and env vars (defaults derived
# from the docs root, as the shipped config documents).
change_root="${AGENT_GUARD_CHANGE_ROOT:-$(cfg_path change_root "$docs_dir/changes")}"
bugs_root="${AGENT_GUARD_BUGS_ROOT:-$(cfg_path bugs_root "$docs_dir/bugs")}"
# regex-safe forms for the path-classification tests below (defaults contain a
# literal dot: .githooks)
re_escape() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
docs_re=$(re_escape "$docs_dir")
scripts_re=$(re_escape "$scripts_dir")
tests_re=$(re_escape "$tests_dir")
githooks_re=$(re_escape "$githooks_dir")
change_root_re=$(re_escape "$change_root")
# 00-intent.md is the pipeline entry point (problem / expected outcome / constraints);
# a change without a recorded intent is treated as undocumented work.
# 00.5-communication.md is the communication-first gate artifact (v3.52.0,
# standards §2.17.2d): round-1 communication draft + user overall confirmation
# record; without it no batch doc body nor source edit may happen.
required_docs=(00-intent.md 00-governance.json 00.5-communication.md 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md)
active_file=$(git rev-parse --git-path agent-governance/active-change)

# --- change batches (v3.18.0, standards §1.1) -------------------------------
# Same-day L0/L1 changes MAY share one `<change_root>/BATCH-YYYYMMDD/` dir.
# Artifact names never change (the fifteen files keep them); members are told
# apart by `## <id>` section anchors — batch addressing needs no JSON parser.
# Resolution order (first hit wins): 1. dedicated `<change_root>/<id>/`
# (historical layout, always wins); 2. AGENT_GUARD_CHANGE_DIR; 3. a BATCH-*/
# dir containing the anchor. No match -> canonical dedicated path (error
# messages name the path the user is expected to create). Details: SLOG
# v3.18-v3.21 rows / DS §1.1.
change_dir() { # <change-id> -> directory
  # NOTE (bash 3.2): `local` expands every word BEFORE assigning any of them, so
  # a second assignment may not reference the first. Keep declarations split.
  local id="$1"
  local d="$change_root/$id" b
  [[ -d "$d" ]] && { printf '%s' "$d"; return 0; }
  if [[ -n "${AGENT_GUARD_CHANGE_DIR:-}" && -d "${AGENT_GUARD_CHANGE_DIR:-}" ]]; then
    printf '%s' "$AGENT_GUARD_CHANGE_DIR"; return 0
  fi
  for b in "$change_root"/BATCH-*/; do
    [[ -d "$b" ]] || continue
    if grep -qE "$(anchor_re "$id")" "$b"/*.md 2>/dev/null; then
      printf '%s' "${b%/}"; return 0
    fi
  done
  printf '%s' "$d"
}

is_batch_dir() { # <dir> -> 0 if it is a BATCH-YYYYMMDD directory
  [[ "$(basename "$1")" =~ ^BATCH-[0-9]{8}$ ]]
}

# Section anchor pattern: `## <change-id>` (optionally followed by more words).
# Requires a separator after the id so a heading like `## 00-intent.md` is not
# mistaken for a change. Shared by change_dir() and anchors_in_file() so the
# resolver and the scanners can never disagree about what an anchor is.
anchor_re() { printf '^##[[:space:]]+%s([[:space:]]|$)' "$1"; }

# v3.80.0 (CHG-107, REQ-1152, DES-1917): scaffold — batch-artifact skeleton
# generator. One command emits the eight begin-stage artifacts with every gate
# shape contract baked in (placement declaration, five-element 00.5, expected-
# outcome/open-questions sections, DES/TC/SC/coverage-column hints, fail-closed
# confirmation placeholder). The shape contracts previously lived only in gate
# source + tribal experience; the end-to-end pin (scaffold output passes begin)
# couples generator and gate so they cannot drift apart. Idempotent fail-closed:
# an artifact that already exists is appended to as a batch-member section (or
# refused when it already carries this change's anchor) — existing content is
# never rewritten.
# v3.80.0 (CHG-107, REQ-1152): global next-id cursor computed once per scaffold
# run — REQ/DES/TC/SC continue the ledger max (change dir + STANDARDS_CHANGELOG),
# so scaffolded specs carry REAL numbers and the E06/E07/E08/E09 numbering gates
# pass without hand-grep. Empty ledger → e.g. REQ-1 (never empty string). NOTE:
# next_id must stay invoked inside $() — a bare top-level call under set -e would
# kill the gate on empty ledgers (grep no-match rc=1 absorbed by command subst).
next_id() { # <prefix> -> <prefix>-<max+1>
  local p="$1" m
  m=$( { grep -rhoE "${p}-[0-9]+" "$change_root" "$repo_root/resources/STANDARDS_CHANGELOG.md" 2>/dev/null || true; } \
    | grep -oE '[0-9]+' | sort -n | tail -1)
  printf '%s-%d' "$p" "$(( ${m:-0} + 1 ))"
}

scaffold_body() { # <doc> <id> <risk> <placement>
  local doc="$1" id="$2" risk="$3" placement="$4"
  case "$doc" in
    00-intent.md)
      printf '# %s Intent\n\n- **目录落位**：%s\n- **来源**：<!-- FILL: 一句话来源（用户裁定/事故/评审发现） -->\n- **范围**：① <!-- FILL: 改动面 1 --> ② <!-- FILL: 改动面 2 -->\n- **不做**：<!-- FILL: 显式排除项 -->\n\n### 预期结果\n\n- <!-- FILL: 可验收结果（与 04 的 TC 对应） -->\n\n### 开放问题\n\n- <!-- FILL: 无 或 开放问题清单 -->\n' "$id" "$placement" ;;
    00.5-communication.md)
      printf '# %s Communication（00.5）\n\n### 影响范围\n\n<!-- FILL: 文件 × 层 × 影响 -->\n\n### 风险\n\n<!-- FILL: 行为/回归风险 + 回滚一句话 -->\n\n### 候选方案与取舍\n\n- 方案 A（采纳）：<!-- FILL: 方案与代价 -->\n- 方案 B（否）：<!-- FILL: 为何否 -->\n\n### 测试思路\n\n- <!-- FILL: TC 清单与期望 -->\n\n### 用户整体确认记录\n\n- <!-- FILL: 日期 + 用户整体确认原文/方式 -->\n- 确认状态：待确认\n' "$id" ;;
    00-governance.json)
      printf '{"change_id": "%s", "risk_level": "%s", "spec_author": "FILL-spec-author（人/代理，须≠review_owner）", "implementation_owner": "FILL-implementation-owner", "test_owner": "FILL-test-owner", "review_owner": "FILL-review-owner（须独立，≠spec_author）", "bug_ref": "", "release_authorized_by": "", "release_authorized_at": "", "release_authorization_evidence": ""}\n' "$id" "$risk" ;;
    01-spec.md)
      printf '# %s Spec\n\n## %s <标题：一句话>\n\n- **DES**：%s\n- **规则**：<!-- FILL -->\n- **理由**：<!-- FILL -->\n- **验收**：<!-- FILL: TC 绑定，编号顺延 -->\n' "$id" "$nxt_req" "$nxt_des" ;;
    02-code-impact-analysis.md)
      printf '# %s Code Impact Analysis\n\n### 改动面\n\n| 文件 | 层 | 影响 |\n|---|---|---|\n| <!-- FILL --> | <!-- FILL: payload/源层 --> | <!-- FILL --> |\n\n### 业务影响\n\n<!-- FILL: 目标仓/源仓/治理链 -->\n\n### 历史相似检索\n\n- 检索词：<!-- FILL -->——命中：<!-- FILL -->\n\n### 风险

<!-- FILL: 行为风险/回归风险/等级（L0~L3） -->

### 延伸发现\n\n- <!-- FILL: 无 或 发现 -->\n\n### 回滚策略\n\n- <!-- FILL: revert 面/触发条件/版本链回退 -->\n' "$id" ;;
    03-modification-plan.md)
      printf '# %s Modification Plan\n\n### 改动清单\n\n| # | 文件 | 改动 | REQ |\n|---|---|---|---|\n| 1 | <!-- FILL --> | <!-- FILL --> | %s |\n\n### 设计决策\n\n- **%s <名>**：<!-- FILL -->；备选 <!-- FILL --> 被否——<!-- FILL: 为何 -->\n\n### 顺序\n\n1. <!-- FILL -->\n' "$id" "$nxt_req" "$nxt_des" ;;
    03.5-tasks.md)
      printf '# %s Tasks\n\n依赖：<!-- FILL: 串/并行链 -->。无外部阻塞。\n\n里程碑：M1=<!-- FILL -->。\n\n评审输入：<!-- FILL: 01-spec/02/04 + diff 面 -->\n' "$id" ;;
    04-test-scripts.md)
      printf '# %s Test Scripts\n\n场景：%s <!-- FILL: 场景名 -->。\n\n| 编号 | TC | SC | 覆盖维度 | 命令 | 期望 | REQ | 来源 |\n|---|---|---|---|---|---|---|---|\n| T1 | %s | %s | <!-- FILL --> | <!-- FILL --> | <!-- FILL --> | %s | 本次引入 |\n\n## TC 落点清单（REQ-1091，v3.71.0）\n\n- %s → <!-- FILL: 文件/节 -->\n' "$id" "$nxt_sc" "$nxt_tc" "$nxt_sc" "$nxt_req" "$nxt_tc" ;;
  esac
}

scaffold_change() { # <id> <risk> — generate the eight begin-stage artifacts
  local id="$1" risk="$2" d doc body target anchor
  local nxt_req nxt_des nxt_tc nxt_sc
  nxt_req=$(next_id REQ); nxt_des=$(next_id DES); nxt_tc=$(next_id TC); nxt_sc=$(next_id SC)
  case "$risk" in
    L0|L1) local dd; dd=$(date -u +%Y%m%d); d="$change_root/BATCH-${dd}"; local placement="BATCH-${dd}（L0/L1 首批触发首-of-日日批规则，§1.1）" ;;
    *)     d="$change_root/$id";                local placement="独立目录（$risk 风险档，§1.1 专用目录形态）" ;;
  esac
  if [[ -d "$d" && -n "$(ls -A "$d" 2>/dev/null | head -1)" ]] \
     && ! is_batch_dir "$d"; then
    die "GATE-E120: scaffold refuses non-empty dedicated dir $d — use a fresh change id"
  fi
  mkdir -p "$d"
  local created=0 appended=0
  for doc in 00-intent.md 00-governance.json 00.5-communication.md 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md; do
    target="$d/$doc"
    body=$(scaffold_body "$doc" "$id" "$risk" "$placement")
    t121=""
    if [[ ! -e "$target" ]]; then
      if [[ "$doc" == "00-governance.json" ]]; then
        printf '%s\n' "$body" > "$target"   # JSON 不插锚不盖戳（gov_record 扁平解析 + stamper 豁免）
      else
        { printf '%s\n\n## %s\n\n' "${body%%$'\n'*}" "$id"; printf '%s\n' "${body#*$'\n'}"; } > "$target"
      fi
      created=$(( created + 1 ))
    else
      # E121 防重入（评审 F1）：gov.json 按 change_id 判重（裸对象无锚），md 按成员锚判重；
      # die 站点全 gate 唯一（T41 唯一性钉），消息变量化。
      if [[ "$doc" == "00-governance.json" ]] && grep -qs "\"change_id\": \"$id\"" "$target"; then
        t121="$target already carries change_id $id (id already materialized)"
      elif grep -qsE "$(anchor_re "$id")" "$target" && [[ "$doc" != "00-governance.json" ]]; then
        t121="$target already carries this change's anchor (id already materialized)"
      fi
      [[ -z "$t121" ]] || die "GATE-E121: $t121"
      if [[ "$doc" == "00-governance.json" ]]; then
        printf '%s\n' "$body" >> "$target"   # 裸追对象行：gov_record 扁平解析禁止夹注 markdown 行（new-change batch_put 同款不变量，评审 F1）
      else
        { printf '\n\n## %s\n\n' "$id"; printf '%s\n' "$body"; } >> "$target"
      fi
      appended=$(( appended + 1 ))
    fi
  done
  printf 'agent-gate: scaffolded %s → %s (created %s, member-appended %s); fill every <!-- FILL --> then re-run begin\n' \
    "$id" "$d" "$created" "$appended" >&2
}


# §2.1.7 signature regex head, shared by GATE-E85 (07-review-report) and
# GATE-E82 (专家评审记录): `platform / model / <trailing id>` with spaced
# slashes. Second real use case extracted (CHG-071, CHG-068 single-source
# precedent); the trailing id pattern and the die strings stay per-gate.
sig_head='[A-Za-z0-9][A-Za-z0-9 ._()-]* / [A-Za-z0-9._-]+ / '

# v3.69.0 (CHG-044): 证据行格式（唯一权威）——E103/E104 机校 grep 形态的唯一叙事源；
# STAGE_PLAYBOOK 阶段 7 只留指针（A43 单源纪律：格式细节不入叙事层）。
#   E104 逐 UJ 运行痕迹行（落 05「运行时证据」节，ui_change: true 时强制）：
#     - UJ-001：POST /api/xxx 响应体片段 {…关键字段…} + DB 行 <表>(id=…) + <UTC 时间戳>
#     机校条件：同一行含 UJ-xxx 且含证据词 HTTP|DB|响应体|快照 之一。
#   E103 剧本回放行（落 05，01-spec demo_script: <N> 时强制）：
#     REPLAY: 句N → <结果> → <证据片段>
#     裁判=原始工件（批准者已把正确答案写进工件）。

# The one place that parses anchors out of a file (see anchor_re for the shape).
anchors_in_file() { # <file> -> ids, one per line
  [[ -f "$1" ]] || return 0
  sed -nE 's/^##[[:space:]]+([A-Za-z0-9][A-Za-z0-9_-]*)([[:space:]].*)?$/\1/p' "$1" 2>/dev/null | sort -u
}

# The AUTHORITATIVE roster of a batch: the change ids declared in its
# 00-governance.json — never the `## <heading>` scan (v3.19.0: structural
# headings like `## Observation` would phantom-change ids and reject valid
# batches; details in SLOG v3.19.0 row).
gov_ids() { # <governance-file> -> declared change ids, one per line
  [[ -s "$1" ]] || return 0
  grep -oE '"change_id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9._-]+"' "$1" 2>/dev/null \
    | sed -E 's/.*"([A-Za-z0-9._-]+)"$/\1/' | sort -u || true
}

# Which change ids does a directory address? A dedicated <CHG>/ directory names
# exactly one (its basename); a batch names every change its roster declares.
# The diff and metrics scans walk DIRECTORIES rather than starting from an id,
# so they need this direction of the mapping.
# Fallback: with no readable roster there is nothing authoritative to report, so
# the anchors are used as a best effort — that keeps a missing/empty
# 00-governance.json surfacing as a concrete error instead of a silent no-op.
change_ids_in_dir() { # <dir> -> ids, one per line
  local d="$1" f roster
  if is_batch_dir "$d"; then
    roster=$(gov_ids "$d/00-governance.json")
    if [[ -n "$roster" ]]; then
      printf '%s\n' "$roster"
      return 0
    fi
    for f in "$d"/*.md; do
      [[ -f "$f" ]] || continue
      anchors_in_file "$f"
    done | sort -u
  else
    basename "$d"
  fi
}

# Format-agnostic record reader (v3.20.0): any valid JSON layout reads
# identically — flatten, split on top-level object boundaries, select by
# change_id. One-object-per-line stays the recommended batch style (reviewable
# diffs) but is no longer a PARSER requirement — a
# style rule, not a load-bearing one. Records stay FLAT (no nesting): `json_field` is a
# single-line sed and the L3 release-authorization fields are deliberately flat
# strings. Case study: SLOG v3.20.0 row.
gov_record() { # <governance-file> <change-id> -> that change's JSON object, one line
  local file="$1" id="$2"
  local flat
  [[ -s "$file" ]] || return 0
  # `|| true` is load-bearing: the gate runs under `set -euo pipefail`, so a
  # no-match grep would abort the whole script (exit 1, no message) instead of
  # returning an empty record the caller can turn into a precise diagnostic.
  flat=$(tr -d '\n\r' < "$file" 2>/dev/null) || return 0
  # Split between sibling objects. Both separators must be handled: batches are
  # written as bare consecutive objects (newline-separated, no comma) while a
  # JSON array or a `jq`-formatted file puts a comma between them. The optional
  # `,?` covers both. A `}{` sequence INSIDE a string value would split there
  # too — accepted: records are flat strings and `change_id` is never last, so
  # the worst case is a truncated record, never a sibling's fields.
  printf '%s' "$flat" \
    | sed -E 's/\}[[:space:]]*,?[[:space:]]*\{/}\n{/g' 2>/dev/null \
    | grep -E "\"change_id\"[[:space:]]*:[[:space:]]*\"${id}\"" 2>/dev/null \
    | head -n 1 || true
}

json_field() { # <json-line> <key> -> value
  local line="$1" key="$2"
  printf '%s' "$line" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" 2>/dev/null | head -n 1 || true
}

# v3.28.0 (CHG-071 复盘): bug_ref may be a flat string OR a flat string array —
# the old check extracted only flat strings, so every change declaring an array
# silently skipped the six-piece validation (fail-open). Returns one value per
# line; empty output for a key that is absent. Callers MUST distinguish
# "absent" from "present but unparseable" via a grep on the raw record.
json_field_values() { # <json-line> <key> -> one value per line
  local line="$1" key="$2" flat arr
  flat=$(printf '%s' "$line" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" 2>/dev/null | head -n 1 || true)
  if [[ -n "$flat" ]]; then printf '%s\n' "$flat"; return 0; fi
  # NOTE: the bracket is [^]] (no backslash) ON PURPOSE — BSD sed (macOS) does
  # not match [^]] inside an ERE bracket expression; [^]] is POSIX-portable.
  arr=$(printf '%s' "$line" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\[([^]]*)\].*/\1/p" 2>/dev/null | head -n 1 || true)
  [[ -n "$arr" ]] || return 0
  printf '%s\n' "$arr" | tr ',' '\n' \
    | sed -E 's/^[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' \
    | grep -v '^[[:space:]]*$' || true
}

is_code_path() {
  local path="$1"
  [[ "$path" =~ ^(${docs_re}/|\.github/|\.agent-governance/|README|AGENTS\.md|CLAUDE\.md|GEMINI\.md) ]] && return 1
  # 治理工具自身不是产品代码：安装/升级治理包的提交不需要变更产物（否则新仓库
  # 第一次 commit 即死锁——鸡生蛋）。它们由 §2.17.4 golden-case 回归背书。
  # v3.17.0：**新增治理脚本必须同步加进本清单**——stamp-provenance.sh 漏加时，
  # 全新安装后的第一次 commit 会被判为"源码变更"而拦下（T15 D5 用例实测暴露）。
  [[ "$path" =~ ^(${githooks_re}/|\.claude/|\.cursor/|\.gemini/|\.opencode/|\.agent-state/|\.agent-governance\.yml$|${scripts_re}/agent-gate$|${scripts_re}/session-gate\.sh$|${scripts_re}/install-hook-adapter$|${scripts_re}/check-standards-compliance\.sh$|${scripts_re}/stamp-provenance\.sh$|${scripts_re}/generate-reading-pack\.sh$|${scripts_re}/behavior-extract\.sh$|${scripts_re}/lib-suite-tree-fingerprint\.sh$|${tests_re}/run-tests\.sh$|${tests_re}/audit-docs-consistency\.sh$) ]] && return 1
  [[ "$path" =~ \.(c|cc|cpp|cs|go|java|js|jsx|kt|kts|php|py|rb|rs|scala|sh|sql|swift|ts|tsx|vue)$ ]]
}

# v3.55.0 (CHG-068): single source for the 延伸发现/历史相似检索 check family —
# a section heading (bare substring; declaration lines self-carry it) OR an
# explicit 未命中（…检索…） declaration line. Callers own their die messages.
require_section_or_decl() { # <file> <keyword> [decl_regex]
  local f="$1" kw="$2" decl="${3:-}"
  grep -q "$kw" "$f" 2>/dev/null && return 0
  if [[ -n "$decl" ]]; then grep -qE "$decl" "$f" 2>/dev/null && return 0; fi
  return 1
}

# v3.67.0 (CHG-090, REQ-1056): the UI-change declaration is the switch for the
# whole UX conditional lane (03.6 artifact + E2E threshold + usability UAT).
# Anchored to the value right after the colon so a template comment that merely
# MENTIONS "true" (e.g. `ui_change：false <!-- 改 true -->`) cannot switch it on.
ui_change_true() { # <spec-file> -> 0 when the spec declares ui_change: true
  # v3.67.0 (CHG-090): the switch is the DECLARATION BULLET only —
  # `- **ui_change**: true`. Prose mentions of `ui_change:true` inside REQ
  # text (CHG-090's own 01-spec tripped this), template comments and the
  # documented `true|false` literal form must not arm the lane. HTML comments
  # are stripped first; the value is anchored right after the colon and must
  # end at a word boundary.
  sed 's/<!--[^>]*-->//g' "$1" 2>/dev/null \
    | grep -qE '^[[:space:]]*[-*][[:space:]]*\*\*ui_change\*\*[：:][[:space:]]*`?true`?([[:space:]]|$|）|\))'
}

# v3.68.0 (CHG-043): declaration bullet parser for the G13/G14 lane switches —
# same family as ui_change_true: bullet form only, HTML comments stripped,
# 未命中/未声明 (or absent) disarms the lane. Value may be a path with spaces.
spec_decl() { # <spec-file> <key> -> declared value or "" (lane disarmed)
  local v
  v=$(sed 's/<!--[^>]*-->//g' "$1" 2>/dev/null \
    | grep -m1 -E "^[[:space:]]*[-*][[:space:]]*\*\*$2\*\*[：:]" \
    | sed -E "s/^[[:space:]]*[-*][[:space:]]*\*\*$2\*\*[：:][[:space:]]*//" \
    | tr -d '`' || true)
  case "$v" in 未命中*|未声明*|"") printf '' ;; *) printf '%s' "$v" ;; esac
}

sha256_file() { # <file> -> hex digest or "" (v3.68.0 CHG-043; macOS/Linux portable)
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || true
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}' || true
  else
    printf ''
  fi
}

# v3.68.0 (CHG-043): G13/G14 begin lane — source-dimension gates that must fire
# BEFORE coding (exposure left-shift): inventory presence (E99), artifact hash
# freshness (E100, anchor anti-rot), data-flow spec table completeness (E105),
# negation-test spot-check section (E106). All trigger-gated by 01-spec
# declarations; undeclared changes short-circuit (no cost, no fatigue).
validate_dimensional_begin() { # <change-dir>
  # AGENT_GUARD_DIM_PROBE=1 disables this lane for structural completeness
  # probes (complete_valid_change_exists): the probe answers "artifact set
  # present?", not "anchors fresh?" — E99/E100/E105/E106 belong to the real
  # enforcement points (begin / staged / stop via validate_dimensional_active).
  [[ "${AGENT_GUARD_DIM_PROBE:-}" == "1" ]] && return 0
  local d="$1" spec="$1/01-spec.md" oa cc inv hrec hcur f
  [[ -s "$spec" ]] || return 0
  oa=$(spec_decl "$spec" "origin_artifact")
  cc=$(spec_decl "$spec" "chain_change")
  if [[ -n "$oa" ]]; then
    [[ -f "$oa" ]] \
      || die "GATE-E109: origin_artifact '$oa' not found relative to repo root (standards §2.5 stage 1, v3.68.0)"
    inv="$d/behavior-inventory.json"
    [[ -s "$inv" ]] \
      || die "GATE-E99: origin_artifact declared but $inv missing — run behavior-extract.sh on the artifact during 勘察, before coding (standards §2.5 stage 1, v3.68.0)"
    hrec=$(grep -m1 -o '"artifact_hash": *"[a-f0-9]\{64\}"' "$inv" 2>/dev/null | grep -o '[a-f0-9]\{64\}' || true)
    hcur=$(sha256_file "$oa")
    hfail=""
    if [[ -z "$hrec" || -z "$hcur" ]]; then
      hfail="cannot verify artifact hash — inventory header line or sha256 tool missing"
    elif [[ "$hrec" != "$hcur" ]]; then
      hfail="origin artifact hash mismatch — artifact changed after extraction, anchors rotted; re-run behavior-extract.sh and re-anchor"
    fi
    [[ -z "$hfail" ]] \
      || die "GATE-E100: $hfail (standards §2.5 stage 1, v3.68.0)"
  fi
  if [[ "$cc" == "true" ]]; then
    e105=""
    require_section_or_decl "$spec" "数据流规格表" \
      || require_section_or_decl "$d/03-modification-plan.md" "数据流规格表" 2>/dev/null \
      || e105="chain_change declared but no 数据流规格表 in 01-spec/03 (字段→来源→变换→落点→展示位置 per chain)"
    if [[ -z "$e105" ]]; then
      for f in "$spec" "$d/03-modification-plan.md"; do
        [[ -s "$f" ]] || continue
        if awk '/^#{1,6} /{f=($0 ~ /数据流规格表/); next} f' "$f" | grep -qE '\|[[:space:]]{0,3}\|'; then
          e105="$f 数据流规格表 has blank cell(s) — a blank row is a design gap, back to design"
          break
        fi
      done
    fi
    [[ -z "$e105" ]] \
      || die "GATE-E105: $e105 (standards §2.5 stage 2, v3.68.0)"
    require_section_or_decl "$d/04-test-scripts.md" "否定测试" \
      || die "GATE-E106: chain_change declared but 04 lacks 否定测试 spot-check section — REQ without a regression TC is a test blind spot (standards §2.5 stage 4, v3.68.0)"
  fi
  return 0
}

# v3.68.0 (CHG-043): G13/G14 stop lane — the delivery backstop for the
# reference-corruption incident class (all downstream checks validated against
# a lossy transcription; nobody compared back to the approved origin artifact):
# declared-missing behaviors (E101), three-way reconciliation orphans (E102),
# demo-script replay evidence (E103), per-UJ runtime evidence (E104), review
# journey evidence (E107), waiver transitivity (E108). Prints upstream-error
# counters on success (all-zero is a danger signal — playbook stage 8).
validate_dimensional_stop() { # <change-dir>
  local d="$1" spec="$1/01-spec.md" oa cc inv ids cov orph uj res05 res07 led row bhv n_bhv n_wv
  [[ -s "$spec" ]] || return 0
  oa=$(spec_decl "$spec" "origin_artifact")
  cc=$(spec_decl "$spec" "chain_change")
  res05="$d/05-test-results.md"; res07="$d/07-review-report.md"
  if [[ -n "$oa" ]]; then
    inv="$d/behavior-inventory.json"
    if [[ ! -s "$inv" ]]; then
      # E99 single die point lives in the begin lane (validate_dimensional_active,
      # dispatched right after this at staged/stop/ci) — keep the skip visible.
      echo "agent-gate: G13/G14 stop lane skipped — behavior-inventory.json missing (E99 reported by the begin lane)" >&2
      return 0
    fi
    if grep -qE '"status": *"missing"' "$inv"; then
      die "GATE-E101: behavior inventory contains 遗漏 (missing) entries — close them or waive explicitly via the 拆除/豁免登记簿; stopping (standards §2.5 stage 2, v3.68.0)"
    fi
    ids=$(grep -oE '"id": *"BHV-[0-9]+"' "$inv" 2>/dev/null | grep -oE 'BHV-[0-9]+' | sort -u || true)
    n_bhv=""
    if [[ -n "$ids" ]]; then
      n_bhv=$(printf '%s\n' "$ids" | grep -c . || true)
      cov=$(cat "$d"/*.md 2>/dev/null | grep -oE 'BHV-[0-9]+' | sort -u || true)
      orph=$(comm -23 <(printf '%s\n' "$ids") <(printf '%s\n' "$cov") 2>/dev/null | tr '\n' ' ' || true)
      if [[ -n "$(printf '%s' "$orph" | tr -d '[:space:]')" ]]; then
        die "GATE-E102: orphan behavior(s) never referenced by any change artifact nor waived: $orph (three-way reconciliation 清单↔事件链↔登记簿, standards §2.5 stage 2, v3.68.0)"
      fi
    fi
    case "$(spec_decl "$spec" "demo_script")" in [1-9]*)
      grep -q "REPLAY:" "$res05" 2>/dev/null \
        || die "GATE-E103: demo_script declared but 05 lacks per-sentence REPLAY: runtime evidence — the approver already wrote the correct answers into the artifact (standards §2.5 stage 7, v3.68.0)" ;;
    esac
    n_wv=$(grep -cE '"status": *"waived"' "$inv" 2>/dev/null || true)
  fi
  if ui_change_true "$spec"; then
    ujs=$(grep -oE 'UJ-[0-9]+' "$spec" 2>/dev/null | sort -u || true)
    while IFS= read -r uj; do
      [[ -n "$uj" ]] || continue
      grep -E "$uj.*(HTTP|DB|响应体|快照)" "$res05" >/dev/null 2>&1 \
        || die "GATE-E104: 05 lacks runtime evidence row for $uj (HTTP body/DB row/快照+timestamp, grep-verifiable) — incident-hardened delivery gate (standards §2.5 stage 7, v3.68.0)"
    done <<EOF
$ujs
EOF
    e107=""
    [[ -s "$res07" ]] || e107="ui_change declared but 07-review-report.md missing"
    if [[ -z "$e107" ]]; then
      grep -q "运行时走查" "$res07" \
        || e107="07 lacks 「运行时走查」 journey-evidence section — document-level walkthrough alone is not availability acceptance"
    fi
    if [[ -z "$e107" ]]; then
      grep -qE 'ses-[a-z0-9-]+|task-[a-z0-9-]+' "$res07" \
        || e107="07 运行时走查 lacks a traceable ses-/task- id"
    fi
    [[ -z "$e107" ]] \
      || die "GATE-E107: $e107 (standards §2.5 stage 8, v3.68.0)"
    # v3.71.0 (CHG-046, REQ-1087): restoration-assertion gate — the E92–E98/E104
    # family checks artifact EXISTENCE only (external-project retro: five review rounds
    # all returned "build+unit green ≠ done"); the restoration bar must be
    # machine-checkable. 05 carries 「还原度断言」: either a waiver declaration
    # or a pointer to a real test file (exists + a test-assertion marker).
    local ra ra_file e110=""
    ra=$(grep -E '^[[:space:]]*-[[:space:]]*\*\*还原度断言\*\*(：|:)' "$res05" 2>/dev/null | head -1 || true)
    if [[ -z "$ra" ]]; then
      e110="05 lacks a 「还原度断言」 line — ui_change restoration must be machine-checkable (an assertion test file: section-order/placeholder/section-header DOM assertions) or explicitly waived: 「还原度断言」：未命中，不适用（理由）"
    elif ! printf '%s\n' "$ra" | grep -q '未命中，不适用'; then
      # BSD sed C-locale mangling lesson: multibyte negated classes capture
      # wrong spans — extract with bash parameter expansion (byte-safe).
      ra_file="${ra#*：}"; [[ "$ra_file" == "$ra" ]] && ra_file="${ra#*:}"
      ra_file="${ra_file%%（*}"; ra_file="${ra_file%%(*}"
      ra_file="$(printf '%s' "$ra_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [[ -z "$ra_file" || ! -f "$ra_file" ]]; then
        e110="the 05 还原度断言 line points at '$ra_file' which does not exist — name the real assertion test file"
      elif ! grep -qE 'describe\(|\bit\(|\btest\(|expect\(|assert|def test_|@Test' "$ra_file" 2>/dev/null; then
        e110="$ra_file carries no recognizable test assertion marker — a plan document is not a test"
      fi
    fi
    [[ -z "$e110" ]] \
      || die "GATE-E110: $e110 (standards §2.5 stage 7, v3.71.0)"
  fi
  # v3.71.0 (CHG-046, REQ-1090): stop-lane shift enforcement — closes the GATE-E89
  # blind spot (E89 fires only at begin; same-change long sessions never re-run
  # begin). A re-delivery of a change already delivered IN THIS SESSION, without
  # handoff evidence, is blocked: write docs/changes/<id>/handoff.md, or record
  # - **换挡声明**：未到换挡点（<理由>） in 09, or escape via
  # AGENT_GUARD_ALLOW_NO_SHIFT=1 (same key as E89; the discipline layer still
  # owes the 09 registration). First delivery passes: record_delivery writes
  # the marker AFTER validate_stop, and stale/absent markers fail open (E89
  # semantics).
  local lastd lc l_started l_delivered
  lastd="$repo_root/.agent-state/last-delivery.json"
  if [[ -s "$lastd" && ! -s "$d/handoff.md" ]] \
     && ! grep -qE '^[[:space:]]*-[[:space:]]*\*\*换挡声明\*\*(：|:).+' "$d/09-changelog.md" 2>/dev/null \
     && [[ "${AGENT_GUARD_ALLOW_NO_SHIFT:-}" != "1" ]] \
     && [[ -s "$repo_root/.agent-state/session-started.json" ]]; then
    lc=$(sed -n 's/.*"change"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$lastd" | head -1)
    if [[ "$lc" == "$id" ]]; then
      l_started=$(sed -n 's/.*"started_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$repo_root/.agent-state/session-started.json" | head -1)
      l_delivered=$(sed -n 's/.*"delivered_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$lastd" | head -1)
      if [[ -n "$l_started" && -n "$l_delivered" ]] && [[ "$l_delivered" > "$l_started" ]]; then
        die "GATE-E112: change $id was delivered earlier in this session but has neither handoff.md nor a 09 「换挡声明」 line — shift the session (write handoff), record the declaration, or set AGENT_GUARD_ALLOW_NO_SHIFT=1 with the justification in 09 (standards §2.9.6, v3.71.0)"
      fi
    fi
  fi
  # v3.71.0 (CHG-046, REQ-1091): TC-landing gate — blocks "test planning posing
  # as tests" (external-project retro: 04 promised ~25 test files, zero materialized).
  # Only the 「TC 落点清单」 section is scanned (legacy 04 files without the
  # section keep passing; the discipline layer lands the mapping going forward).
  # 「人工」-typed entries are skipped (manual walkthroughs have no executable
  # file); automated entries must point at an existing file carrying a
  # test-assertion marker.
  if grep -q '^## TC 落点清单' "$d/04-test-scripts.md" 2>/dev/null; then
    local tcl tc_path tc_id
    while IFS= read -r tcl; do
      [[ -n "$tcl" ]] || continue
      case "$tcl" in *"自动化"*) ;; *) continue ;; esac
      tc_id=$(printf '%s\n' "$tcl" | sed -E 's/^[[:space:]]*-[[:space:]]*(TC-[A-Za-z0-9_-]+)[[:space:]]*:[[:space:]].*/\1/')
      tc_path="${tcl#*:}"; tc_path="${tc_path%%（*}"; tc_path="${tc_path%%(*}"
      tc_path="$(printf '%s' "$tc_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      local e113=""
      if [[ -z "$tc_path" || ! -f "$tc_path" ]]; then
        e113="TC landing '$tc_id' points at '$tc_path' which does not exist — every automated TC must land an executable file (standards §2.5 stage 7)"
      elif ! grep -qE 'describe\(|\bit\(|\btest\(|expect\(|assert|def test_|@Test' "$tc_path" 2>/dev/null; then
        e113="'$tc_id' landing '$tc_path' carries no recognizable test assertion marker"
      fi
      [[ -z "$e113" ]] \
        || die "GATE-E113: $e113 (v3.71.0; escape review: 人工-typed rows are skipped)"
    done < <(sed -n '/^## TC 落点清单/,/^## /p' "$d/04-test-scripts.md" | grep -E '^[[:space:]]*-[[:space:]]*TC-')
  else
    echo "agent-gate: TC landing soft warning: $d/04-test-scripts.md has no 「TC 落点清单」 section (legacy shape passes unblocked; new changes must land TC→file mappings, REQ-1091, v3.71.0)" >&2
  fi
  # G14d waiver transitivity (v3.70.0，CHG-045 收窄)：①「行为豁免」表行只允许出现在
  # 01-spec「拆除/豁免登记簿」节内——节外豁免行直接 E108（堵"节外豁免行躲检"）；
  # ②触真实业务链的节内豁免行须行内同时含 00.5 引用与「确认」——静默扩大豁免范围
  # 是本门禁族要杀的语义漂移失效形态。单一 die 点（T41 码唯一性）。
  e108=""
  led=$(awk '/^#{1,6} /{f=($0 ~ /拆除\/豁免登记簿/); next} f' "$spec")
  if awk '/^#{1,6} /{f=($0 ~ /拆除\/豁免登记簿/); next} !f' "$spec" | grep -qE '^\|.*行为豁免'; then
    e108="「行为豁免」表行出现在拆除/豁免登记簿节之外 — waiver rows are only legal inside the ledger section (v3.70.0 CHG-045 收窄)"
  elif [[ -n "$led" ]]; then
    while IFS= read -r row; do
      case "$row" in *行为豁免*) ;; *) continue ;; esac
      bhv=$(printf '%s' "$row" | grep -oE 'BHV-[0-9]+' | head -1 || true)
      [[ -n "$bhv" ]] || continue
      # chain behavior = referenced anywhere in 01-spec OUTSIDE the ledger section
      if awk '/^#{1,6} /{f=($0 ~ /拆除\/豁免登记簿/); next} !f' "$spec" | grep -q "$bhv"; then
        if ! { printf '%s' "$row" | grep -q '00\.5' && printf '%s' "$row" | grep -q '确认'; }; then
          e108="行为豁免 $bhv touches a real business chain but carries no inline 00.5 追加沟通轮确认 reference — waivers must not transit (豁免演示数据≠豁免演示所走真实链路) (standards §2.5 stage 2, v3.68.0; narrowed v3.70.0)"
          break
        fi
      fi
    done <<EOF
$led
EOF
  fi
  [[ -z "$e108" ]] || die "GATE-E108: $e108"
  if [[ -n "$n_bhv" ]]; then
    echo "agent-gate: G13/G14 stop lane clean — behaviors=$n_bhv waived=${n_wv:-0} orphans=0 (upstream-error counters: record nonzero finds in 07; all-zero is a danger signal, playbook stage 8)"
  fi
  return 0
}

# v3.68.0 (CHG-043): resolve the active change and run the G13/G14 BEGIN lane
# at staged/stop as well — begin gates them before coding, this catches
# mid-flight anchor rot (prototype edited after extraction) at commit staging
# and re-verifies at delivery. Dormant without an active change.
validate_dimensional_active() {
  local af id d
  af=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  [[ -n "$af" && -s "$af" ]] || return 0
  id=$(tr -d '[:space:]' < "$af" 2>/dev/null || true)
  [[ -n "$id" ]] || return 0
  d=$(change_dir "$id" 2>/dev/null || true)
  [[ -n "$d" && -d "$d" ]] || return 0
  validate_dimensional_begin "$d"
}

# v3.55.0 (CHG-068): communication-first gate semantics, single source —
# shared by validate_artifact_content (GATE-E83 die) and the check-confirm
# subcommand (exit-code protocol). Sets CONFIRM_REASON ("" = confirmed).
confirmation_gate_reason() { # <id> <dir>
  local id="$1"
  local d="$2"
  CONFIRM_REASON=""
  local comm05="$d/00.5-communication.md" scope05
  if [[ ! -s "$comm05" ]]; then
    CONFIRM_REASON="missing $comm05"
    return 0
  fi
  if grep -qE "^##[[:space:]]+${id}([[:space:]]|\$)" "$d/00-intent.md"; then
    # batch member (§1.1): the shared 00.5 must carry THIS change's own anchor
    # section — a sibling's confirmation never counts (fail-closed). The
    # section runs to the NEXT SIBLING ANCHOR (not the next h2): member
    # sections legitimately contain h2 structural headings. Sibling ids come
    # from the authoritative roster (00-governance.json, v3.19 semantics).
    if grep -qE "^##[[:space:]]+${id}([[:space:]]|\$)" "$comm05"; then
      local others05
      # `|| true` inside the subshell: a single-member batch leaves grep -vx
      # with no output — with pipefail that would abort the whole script
      # (silent exit 1), the exact trap documented at the top of this file.
      others05=$( (change_ids_in_dir "$d" | grep -vx "$id" || true) | sort -u | tr '\n' '|')
      others05="${others05%|}"
      if [[ -n "$others05" ]]; then
        scope05=$(awk -v cur="^##[[:space:]]+${id}([[:space:]]|\$)" -v stop="^##[[:space:]]+(${others05})([[:space:]]|\$)" '$0 ~ cur {f=1; next} f && $0 ~ stop {f=0} f' "$comm05")
      else
        scope05=$(awk -v cur="^##[[:space:]]+${id}([[:space:]]|\$)" '$0 ~ cur {f=1; next} f' "$comm05")
      fi
    else
      # v3.61.1 (FU-916): message no longer presumes batch membership — this
      # branch fires whenever 00-intent carries the anchor, even for a
      # single-member/独立 directory; the roster-accurate wording lives in the
      # roster branch below.
      CONFIRM_REASON="$id declares a ## $id anchor in 00-intent (batch-shaped) but its own ## $id anchor is missing in $comm05 — fail-closed: sibling/absent confirmations never count (§2.17.2d)"
      return 0
    fi
  else
    # v3.61.1 (CHG-078, FU-913 closure): member detection now follows the
    # authoritative roster (same source as GATE-E86) instead of the 00-intent
    # anchor scan — a multi-member batch member without its own 00.5 anchor
    # used to fall back to whole-file scope here (a sibling's confirmation
    # could satisfy this gate). Independent dirs / single-member batches keep
    # the whole-file fallback: the file IS this change's scope.
    local others05b
    others05b=$( (change_ids_in_dir "$d" | grep -vx "$id" || true) | sort -u | tr '\n' '|')
    others05b="${others05b%|}"
    if [[ -n "$others05b" ]] && grep -qE "^##[[:space:]]+${id}([[:space:]]|\$)" "$comm05"; then
      scope05=$(awk -v cur="^##[[:space:]]+${id}([[:space:]]|\$)" -v stop="^##[[:space:]]+(${others05b})([[:space:]]|\$)" '$0 ~ cur {f=1; next} f && $0 ~ stop {f=0} f' "$comm05")
    elif [[ -n "$others05b" ]]; then
      CONFIRM_REASON="batch member $id lacks its own ## $id anchor section in $comm05 (roster: {${others05b}}; fail-closed, aligned with GATE-E86, v3.61.1)"
      return 0
    else
      scope05=$(cat "$comm05")
    fi
  fi
  local rec05 risk05=""
  rec05=$(gov_record "$d/00-governance.json" "$id")
  [[ -n "$rec05" ]] && risk05=$(json_field "$rec05" risk_level)
  if printf '%s\n' "$scope05" | grep -qE '^[[:space:]]*-[[:space:]]*\*\*沟通确认\*\*(：|:)[[:space:]]*未命中，不适用（.+）'; then
    if [[ "$risk05" == "L0" ]]; then
      : # L0 lightweight single-line declaration satisfies the gate (§2.17.2d)
    else
      CONFIRM_REASON="L0-only single-line declaration found in $comm05 but risk_level is ${risk05:-unknown} — the lightweight channel is L0-exclusive (§2.17.2d)"
    fi
  elif ! printf '%s\n' "$scope05" | grep -q "用户整体确认记录"; then
    CONFIRM_REASON="missing 用户整体确认记录 section in $comm05"
  elif ! printf '%s\n' "$scope05" | grep -qE '(确认状态|confirmation)[[:space:]]*(：|:)[[:space:]]*(已整体确认|confirmed)'; then
    CONFIRM_REASON="no user-overall-confirmation marker under 用户整体确认记录 in $comm05"
  fi
  [[ -z "$CONFIRM_REASON" ]] || return 0
  # v3.60.0 (REQ-1009, TC-1065): five-element substance extension — a bare
  # confirmation marker on an otherwise hollow 00.5 must not pass (the
  # round-1 communication carries 需求理解/影响/风险/方案/测试思路 per
  # §2.17.2d). L0 single-line declaration stays exempt (checked above).
  if [[ "$risk05" != "L0" ]]; then
    local a05
    for a05 in 影响范围 风险 候选方案与取舍 测试思路; do
      printf '%s\n' "$scope05" | grep -qE "^(#{1,6}[[:space:]]*$a05([[:space:]]|\$)|[[:space:]]*[-*][[:space:]]+\*\*$a05\*\*)" \
        || { CONFIRM_REASON="00.5 substance: missing '$a05' anchor (five-element round-1, §2.17.2d v3.60.0)"; return 0; }
    done
  fi
  return 0
}

required_docs_present() {
  local id="$1" doc d  # FU-023: ids must start alphanumeric, then alnum/_/- only — no dots at all
  # (kills "-foo", "foo.", "a..b"; existing CHG-xxx / BUG-<ts> forms all pass).
  [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "GATE-E02: invalid change id '$id' (start with [A-Za-z0-9], then alnum/_/-; no dots)"
  d=$(change_dir "$id")
  for doc in "${required_docs[@]}"; do
    if [[ "$doc" == "00.5-communication.md" && "${AGENT_GUARD_ALLOW_UNCONFIRMED:-}" == "1" ]]; then
      # explicit bypass (§2.17.2d) — v3.60.0: append to the friction ledger so
      # bypass use is visible to metrics/review, not silent; 09 justification
      # duty stays (standards §2.17.2d).
      printf 'GATE-E83BYPASS\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
        >> ".agent-state/gate-friction.tsv" 2>/dev/null || true
      continue
    fi
    [[ -s "$d/$doc" ]] || die "GATE-E03: missing required artifact: $d/$doc"
  done
  validate_artifact_content "$id"
}

# --- A-layer artifact content checks (DEVELOPMENT_STANDARDS §2.5) -----------
# Presence alone is not acceptance: a hollow skeleton with no numbering system
# must not pass as a complete artifact set. These checks are deterministic
# greps; quality judgment (B layer) stays with independent roles.
validate_artifact_content() {
  local id="$1" d
  d=$(change_dir "$id")
  grep -q "预期结果" "$d/00-intent.md" \
    || die "GATE-E04: $d/00-intent.md missing expected-outcome section (A-layer acceptance, standards §2.5)"
  grep -q "开放问题" "$d/00-intent.md" \
    || die "GATE-E05: $d/00-intent.md missing open-questions section (A-layer acceptance, standards §2.5)"
  # v3.52.0 communication-first gate (standards §2.17.2d): 00.5 must exist and
  # carry a non-empty user-overall-confirmation record before any batch doc
  # body or source edit. Semantics live in confirmation_gate_reason (single
  # source, shared with the check-confirm subcommand, v3.55.0).
  if [[ "${AGENT_GUARD_ALLOW_UNCONFIRMED:-}" == "1" ]]; then
    : # explicit bypass — register the justification in 09 重要上下文 (§2.17.2d)
  else
    confirmation_gate_reason "$id" "$d"
    [[ -z "$CONFIRM_REASON" ]] \
      || die "GATE-E83: communication-first gate: $CONFIRM_REASON — record the user overall confirmation (standards §2.17.2d; L0 single-line declaration allowed; AGENT_GUARD_ALLOW_UNCONFIRMED=1 is the explicit automation bypass)"
  fi
  grep -qE "REQ-[0-9]+" "$d/01-spec.md" \
    || die "GATE-E06: $d/01-spec.md has no REQ- numbering (A-layer acceptance, standards §2.5)"
  grep -qE "DES-[0-9]+" "$d/03-modification-plan.md" \
    || die "GATE-E07: $d/03-modification-plan.md has no DES- numbering (A-layer acceptance, standards §2.5)"
  grep -qE "TC-[0-9]+" "$d/04-test-scripts.md" \
    || die "GATE-E08: $d/04-test-scripts.md has no TC- numbering (A-layer acceptance, standards §2.5)"
  # v3.3.0 scenario inventory: business scenarios enumerated with SC-
  # numbering and mapped to TCs (standards §2.5 stage 4).
  grep -qE "SC-[0-9]+" "$d/04-test-scripts.md" \
    || die "GATE-E09: $d/04-test-scripts.md has no SC- scenario numbering (A-layer, standards §2.5 stage 4, v3.3.0)"
  # v2.20.0 professional-role markers: option comparison in the plan and a
  # coverage-dimension column in the test matrix (standards §2.5 stages 3-4).
  grep -qE "备选|选型" "$d/03-modification-plan.md" \
    || die "GATE-E10: $d/03-modification-plan.md has no option-comparison (备选/选型) content (A-layer, standards §2.5 stage 3)"
  grep -q "覆盖维度" "$d/04-test-scripts.md" \
    || die "GATE-E11: $d/04-test-scripts.md has no coverage-dimension (覆盖维度) column (A-layer, standards §2.5 stage 4)"
  # Stage 2 is unconditional: "analyze before designing" (standards §2.5
  # stage 2) is a hard gate, not an optional extra. 03.5 may alternatively
  # carry an explicit no-breakdown exemption marker instead of task rows.
  # FU-008: the keyword must sit in a structural position (heading / table row /
  # bold list item), not anywhere in prose — a negated or passing mention like
  # "本变更无业务影响" used to satisfy a bare substring grep.
  grep -qE "^(#{1,6}[[:space:]].*业务影响|\|.*业务影响|[[:space:]]*[-*][[:space:]]+\*\*业务影响)" "$d/02-code-impact-analysis.md" \
    || die "GATE-E12: $d/02-code-impact-analysis.md missing business-impact (业务影响) section (A-layer, standards §2.5 stage 2)"
  grep -qE "^(#{1,6}[[:space:]].*风险|\|.*风险|[[:space:]]*[-*][[:space:]]+\*\*风险)" "$d/02-code-impact-analysis.md" \
    || die "GATE-E13: $d/02-code-impact-analysis.md missing risk (风险) content (A-layer, standards §2.5 stage 2)"
  grep -qE "^(#{1,6}[[:space:]].*回滚策略|\|.*回滚策略|[[:space:]]*[-*][[:space:]]+\*\*回滚策略)" "$d/02-code-impact-analysis.md" \
    || die "GATE-E14: $d/02-code-impact-analysis.md missing rollback (回滚策略) content (A-layer, standards §2.5 stage 2)"
  # v3.48.0 (CHG-058): 延伸发现即时落盘（标题或"未发现"声明行均含关键词）
  require_section_or_decl "$d/02-code-impact-analysis.md" "延伸发现" \
    || die "GATE-E80: $d/02-code-impact-analysis.md missing 延伸发现 section (A-layer, standards §2.5 stage 2, v3.48.0; renumbered from E15 in v3.48.1, CHG-060 — E15/E16 collide with pre-existing stage-3 codes)"
  # v3.54.0 (CHG-067, REQ-998): stage-2 历史相似检索 step machine-checked like
  # its sibling 延伸发现 (E80) — section heading OR an explicit
  # 未命中（<检索词>） declaration line. Single die point keeps T41 uniqueness.
  require_section_or_decl "$d/02-code-impact-analysis.md" "历史相似检索" '未命中（[^）]+）' \
    || die "GATE-E84: $d/02-code-impact-analysis.md missing 历史相似检索 section (or 未命中（检索词） declaration) (A-layer, standards §2.5 stage 2, v3.54.0 CHG-067)"
  if ! grep -qE "直接实施|未拆任务" "$d/03.5-tasks.md"; then
    grep -q "依赖" "$d/03.5-tasks.md" \
      || die "GATE-E15: $d/03.5-tasks.md missing dependency (依赖) info (A-layer, standards §2.5 stage 3)"
    grep -q "里程碑" "$d/03.5-tasks.md" \
      || die "GATE-E16: $d/03.5-tasks.md missing milestone (里程碑) info (A-layer, standards §2.5 stage 3)"
    # v3.39.0 (CHG-041): review/test subagents must receive their evidence pack
    # from the orchestrator, not re-explore the repo for it (standards §2.2
    # input contract). The field must exist on every non-trivial task list;
    # the lightweight one-line channel stays exempt by the branch above.
    grep -q "评审输入" "$d/03.5-tasks.md" \
      || die "GATE-E17: $d/03.5-tasks.md missing review-input (评审输入) field (A-layer, standards §2.2 input contract, v3.39.0)"
  fi
  # v3.67.0 (CHG-090, REQ-1053): requirements carry UX when the change touches a
  # user-visible interface — every REQ block must anchor to a UJ-xxx user task.
  # Block = from a REQ- mention to the next REQ-/top-level section; the anchor
  # may sit on the REQ line itself or on a later line inside the block (template
  # form: `**挂靠 UJ**：UJ-001`). An unfilled `UJ-xxx` placeholder anchor fails.
  # Non-UI changes stay exempt (conditional gate keyed off 01-spec ui_change).
  if [[ -s "$d/01-spec.md" ]] && ui_change_true "$d/01-spec.md"; then
    unanchored=$(awk '
      /REQ-[0-9A-Za-z]+/ { if (pending && !anchored) bad++; pending=1 }
      pending && /UJ-[0-9]+/ { anchored=1 }
      /^## / { if (pending && !anchored) bad++; pending=0 }
      END { if (pending && !anchored) bad++; print bad+0 }
    ' "$d/01-spec.md")
    [[ "$unanchored" == 0 ]] \
      || die "GATE-E90: $d/01-spec.md declares ui_change: true but $unanchored REQ block(s) carry no UJ-xxx anchor (A-layer, standards §2.5 stage 1, v3.67.0)"
  fi
  # v3.69.0 (CHG-044): G13/G14 begin lane — G14e element dimension ships inside
  # the same inventory (kind=element rows; word table = behavior-extract.sh
  # header, single source — A43 forbids copying it into narrative layers).
  validate_dimensional_begin "$d"
}

# v3.67.0 (CHG-090): soft fallback for a MISSED ui_change declaration (the
# declaration is author-written and can be forgotten). A staged diff that
# touches UI-looking paths while the active 01-spec does not declare
# ui_change: true prints a one-line warning (non-fatal — the hard gate stays
# keyed off the explicit declaration; record the justification in 09).
warn_ux_soft() {
  local id d spec af
  af=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  [[ -n "$af" && -s "$af" ]] || return 0
  id=$(tr -d '[:space:]' < "$af" 2>/dev/null || true)
  [[ -n "$id" ]] || return 0
  d=$(change_dir "$id" 2>/dev/null || true)
  [[ -n "$d" && -d "$d" ]] || return 0
  spec="$d/01-spec.md"
  [[ -s "$spec" ]] || return 0
  ui_change_true "$spec" && return 0
  if git diff --cached --name-only 2>/dev/null \
     | grep -Eq '\.(vue|tsx|jsx|html|css|scss|xaml)$|(^|/)(web|frontend|ui|pages|views|components)/'; then
    echo "agent-gate: UX soft warning: staged diff touches UI-looking paths but $spec does not declare ui_change: true — declare it or record the justification in 09「重要上下文」 (standards §2.5 stage 1, v3.67.0)" >&2
  fi
}

# v3.67.0 (CHG-090, REQ-1056..1060): the conditional UX lane. Only fires when
# 01-spec declares ui_change: true, so non-UI changes stay byte-for-byte
# equivalent to pre-upgrade behavior. Runs on stop/staged (03.6/04 already
# exist by then; 07 exists at stop), never at begin (design/test not yet made).
validate_ux_conditions() {
  local id d spec risk n e2e af
  # Read the active-change marker directly: active_change() dies when absent,
  # and this conditional lane must stay dormant on repos with no active change.
  af=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  [[ -n "$af" && -s "$af" ]] || return 0
  id=$(tr -d '[:space:]' < "$af" 2>/dev/null || true)
  [[ -n "$id" ]] || return 0
  d=$(change_dir "$id" 2>/dev/null || true)
  [[ -n "$d" && -d "$d" ]] || return 0
  spec="$d/01-spec.md"
  [[ -s "$spec" ]] || return 0
  ui_change_true "$spec" || return 0
  risk=$(json_field "$(gov_record "$d/00-governance.json" "$id" 2>/dev/null || true)" risk_level 2>/dev/null || true)
  [[ -s "$d/03.6-ui-spec.md" ]] \
    || die "GATE-E92: ui_change: true but $d/03.6-ui-spec.md is missing (conditional artifact, standards §2.5 stage 3, v3.67.0)"
  grep -qE "主键映射|显示名.*主键|主键.*显示名" "$d/03.6-ui-spec.md" \
    || die "GATE-E94: $d/03.6-ui-spec.md missing the 显示名↔主键映射 section — a bare DB key field is not a user interface (standards §2.5 stage 3, v3.67.0)"
  if grep -qE "直接输入[^。]*[A-Za-z_]*[Ii]d([^A-Za-z]|$)" "$d/03.6-ui-spec.md" 2>/dev/null; then
    die "GATE-E97: $d/03.6-ui-spec.md describes a bare primary-key entry as the user's main input — entities must be chosen via list/search/context (standards §2.5 stage 3, v3.67.0)"
  fi
  if [[ ! -s "$d/03.5-tasks.md" ]] \
     || ! sed 's/<!--[^>]*-->//g' "$d/03.5-tasks.md" 2>/dev/null | grep -qE '^\|.*\b(UX|UI)\b'; then
    die "GATE-E93: ui_change: true but $d/03.5-tasks.md is missing or carries no UX/UI task row — UX work was never broken out (standards §2.5 stage 3, v3.67.0)"
  fi
  case "$risk" in L0|L1) n=1 ;; *) n=3 ;; esac
  e2e=$(grep -cE "E2E|用户旅程" "$d/04-test-scripts.md" 2>/dev/null || true)
  [[ "$e2e" -ge "$n" ]] \
    || die "GATE-E95: ui_change: true but $d/04-test-scripts.md has $e2e user-journey E2E case(s), below threshold $n (L0/L1=1, L2/L3=3 or full main flow) (standards §2.5 stage 4, v3.67.0)"
  if [[ -s "$d/07-review-report.md" ]]; then
    grep -q "用户可用性验收" "$d/07-review-report.md" \
      || die "GATE-E96: $d/07-review-report.md missing 「用户可用性验收」 signature section (standards §2.5 stage 8, v3.67.0)"
    grep -q "建议人类走查" "$d/07-review-report.md" \
      || die "GATE-E98: $d/07-review-report.md missing 「建议人类走查（非阻塞）」 line (standards §2.5 stage 8, v3.67.0)"
  fi
}

# Placeholder owner values are governance debt, not a real assignment: an
# owner set to PENDING/TODO/TBD/待定 must fail the gate now instead of
# silently passing role-independence checks later. (v3.5.0)
reject_placeholder_owner() { # file field value
  local file="$1" field="$2" value="$3" norm
  norm=$(printf '%s' "$value" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
  case "$norm" in
    PENDING|TODO|TBD|*待定*) die "GATE-E18: $file field '$field' must name a concrete owner (placeholder '$value' rejected)" ;;
  esac
}

# v3.17.0 file provenance (standards §1.1). The block is written by
# scripts/stamp-provenance.sh from the RUNNING ENVIRONMENT (git identity,
# hostname, platform, UTC time) — values a hand-writer cannot know, which is
# exactly what makes them evidence rather than a claim. What a gate can check is
# therefore: the block exists, its fields are filled, `generated_at` looks like a
# real ISO date, and `generated_by` names the script — a hand-written block
# naming itself something else fails here. Truthfulness of `author` itself is not
# machine-verifiable; the producer requirement is what narrows the gap.
provenance_block() { # file -> block lines, or empty
  # v3.62.2 (CHG-082, REQ-1029): fence-aware extraction. The old sed range
  # grabbed EVERY `<!-- provenance`..`-->` span — a fenced EXAMPLE block in
  # the document body (docs showing what a block looks like) was extracted
  # instead of (or in addition to) the real block. ``` state tracking keeps
  # the real block (never inside a fence: it is written right after the H1)
  # and ignores fenced sample markers; \r is tolerated on read (CRLF files)
  # without rewriting the file.
  awk '
    { sub(/\r$/, "") }
    !inblk && /^[[:space:]]*```/ { infence = !infence; next }
    !inblk && !infence && /^<!-- provenance$/ { inblk = 1; print; next }
    inblk && !infence && /^-->$/ { print; inblk = 0; next }
    inblk { print }
  ' "$1" 2>/dev/null || true
}
validate_provenance() { # file
  local f="$1" blk k norm
  blk=$(provenance_block "$f")
  [[ -n "$blk" ]] || die "GATE-E19: cannot finish: $f carries no provenance block — run scripts/stamp-provenance.sh <CHG-id> (standards §1.1)"
  # Placeholder first: an unfilled template should hear "run the script", not a
  # downstream symptom about date formats.
  norm=$(printf '%s' "$blk" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
  case "$norm" in
    *PENDING*|*TODO*|*TBD*|*待定*) die "GATE-E20: cannot finish: $f provenance block still holds a placeholder — run scripts/stamp-provenance.sh <CHG-id>" ;;
  esac
  for k in author email generated_at generated_by; do
    printf '%s\n' "$blk" | grep -qE "^${k}:[[:space:]]*[^[:space:]]" \
      || die "GATE-E21: cannot finish: $f provenance block is missing '$k' — regenerate with scripts/stamp-provenance.sh"
  done
  printf '%s\n' "$blk" | grep -qE '^generated_at:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    || die "GATE-E22: cannot finish: $f provenance 'generated_at' is not an ISO-8601 date — regenerate with scripts/stamp-provenance.sh"
  printf '%s\n' "$blk" | grep -qE '^generated_by:[[:space:]]*stamp-provenance\.sh' \
    || die "GATE-E23: cannot finish: $f provenance block was not produced by scripts/stamp-provenance.sh (a hand-written block cannot pass this)"
}

validate_governance_state() {
  local id="$1" file risk implementation test_owner review_owner declared_id d rec
  d=$(change_dir "$id")
  file="$d/00-governance.json"
  [[ -s "$file" ]] || die "GATE-E24: missing required artifact: $file"
  # A dedicated <CHG>/ directory holds one record; a batch holds one line per
  # bundled change. Scope to THIS change's line so a sibling's risk/owners can
  # never satisfy our checks (or be misread as ours).
  rec=$(gov_record "$file" "$id")
  [[ -n "$rec" ]] || die "GATE-E25: $file declares no governance record for '$id' (expected a JSON line with \"change_id\": \"$id\")"
  declared_id=$(json_field "$rec" change_id)
  [[ "$declared_id" == "$id" ]] || die "GATE-E26: $file must declare change_id '$id'"
  risk=$(json_field "$rec" risk_level)
  [[ "$risk" =~ ^L[0-3]$ ]] || die "GATE-E27: $file must declare risk_level L0, L1, L2, or L3"
  # v3.18.0 change batches are L0/L1 ONLY (standards §1.1). Bundling weakens the
  # per-change evidence boundary — artifacts of several changes share one file —
  # which is tolerable for low-risk work and not for anything needing role
  # independence or release authorization. Enforced here, on the record, so it
  # cannot be bypassed by simply dropping artifacts into a BATCH-*/ directory.
  if is_batch_dir "$d" && [[ "$risk" != L0 && "$risk" != L1 ]]; then
    die "GATE-E28: $d is a change batch but '$id' declares risk_level $risk — batches are L0/L1 only; move '$id' to $change_root/$id/ (standards §1.1)"
  fi
  # v3.60.0 (REQ-1009, TC-1063/1064): directory-placement declaration
  # (GATE-E86) — the BATCH-vs-independent decision must be recorded in
  # 00-intent (batch members: inside the change's own anchor section) and must
  # agree with the actual directory form and the declared risk (§1.1). Without
  # the declaration the placement choice is unauditable: a compliant choice
  # (e.g. an L2 sibling forcing an L1 change independent) is indistinguishable
  # from a violated default, which read as "feature removed / rule ignored"
  # (CHG-076 incident, 2026-09-26).
  local intent_f="$d/00-intent.md" scope_i decl86 others_i reason86="" scope_resolved=0
  if [[ ! -s "$intent_f" ]]; then
    reason86="missing $intent_f (placement declaration carrier)"
  fi
  if [[ -z "$reason86" ]]; then
  if grep -qE "^##[[:space:]]+${id}([[:space:]]|\$)" "$intent_f"; then
    others_i=$( (change_ids_in_dir "$d" | grep -vx "$id" || true) | sort -u | tr '\n' '|')
    others_i="${others_i%|}"
    if [[ -n "$others_i" ]]; then
      scope_i=$(awk -v cur="^##[[:space:]]+${id}([[:space:]]|\$)" -v stop="^##[[:space:]]+(${others_i})([[:space:]]|\$)" '$0 ~ cur {f=1; next} f && $0 ~ stop {f=0} f' "$intent_f")
    else
      scope_i=$(awk -v cur="^##[[:space:]]+${id}([[:space:]]|\$)" '$0 ~ cur {f=1; next} f' "$intent_f")
    fi
    scope_resolved=1
  else
    # v3.61.0 (FU-912): fail-closed alignment with GATE-E83. A batch member
    # without its own anchor section used to fall back to whole-file scope,
    # letting a sibling's placement declaration satisfy this gate (fail-open
    # asymmetry). Multi-member batch + missing anchor => die; independent dir
    # (or single-member batch) whole-file fallback is the legitimate form and
    # stays (the file IS this change's scope, no ambiguity).
    others_i=$( (change_ids_in_dir "$d" | grep -vx "$id" || true) | sort -u | tr '\n' '|')
    others_i="${others_i%|}"
    if [[ -n "$others_i" ]]; then
      reason86="missing anchor section '## $id' in $intent_f — batch member among {${others_i}} must declare placement in its own section (fail-closed, aligned with GATE-E83)"
    else
      scope_i=$(cat "$intent_f")
      scope_resolved=1
    fi
  fi
  fi
  if [[ "$scope_resolved" == 1 ]]; then
  decl86=$(printf '%s\n' "$scope_i" | awk '/^[[:space:]]*-[[:space:]]*\*\*目录落位\*\*(：|:)/{print; exit}')
  if [[ -z "$decl86" ]]; then
    reason86="missing placement declaration '- **目录落位**：BATCH-YYYYMMDD | 独立目录（<理由>）'"
  elif printf '%s\n' "$decl86" | grep -q 'BATCH-'; then
    is_batch_dir "$d" || reason86="'$id' declares BATCH-YYYYMMDD placement but lives in independent dir $d — declaration and directory disagree"
    [[ -n "$reason86" ]] || [[ "$risk" =~ ^L[01]$ ]] || reason86="'$id' risk $risk cannot declare BATCH placement — batches are L0/L1 only"
  elif printf '%s\n' "$decl86" | grep -q '独立目录'; then
    is_batch_dir "$d" && reason86="'$id' declares 独立目录 placement but lives in batch dir $d — declaration and directory disagree"
    # v3.62.2 (CHG-082, REQ-1028): L0/L1 must never declare independent
    # placement — standards §1.1 first-of-day rule (v3.61.2) makes the day
    # batch the ONLY legal form for L0/L1, both forward (a same-day batch
    # exists and must be joined) and reverse (no batch yet: the FIRST L0/L1
    # of the day creates it). E73 enforces this on directory reality at
    # begin only; this declaration-level check closes the reverse direction
    # and the stop/CI paths (validate_governance_state callers). The CHG-081
    # 立项 interception was the live proof of the gap.
    if [[ -z "$reason86" && "$risk" =~ ^L[01]$ && "${AGENT_GUARD_ALLOW_INDEPENDENT:-}" != "1" ]]; then
      if [[ -d "$change_root/BATCH-$(date -u +%Y%m%d)" ]]; then
        reason86="'$id' risk $risk declares 独立目录 placement while $change_root/BATCH-$(date -u +%Y%m%d) exists — same-day L0/L1 changes must join the batch (standards §1.1); set AGENT_GUARD_ALLOW_INDEPENDENT=1 only with a recorded justification"
      else
        reason86="'$id' risk $risk must declare BATCH-YYYYMMDD placement — the first L0/L1 change of the day creates the day batch (standards §1.1 first-of-day rule); set AGENT_GUARD_ALLOW_INDEPENDENT=1 only with a recorded justification"
      fi
    fi
  else
    reason86="'$id' placement declaration must state BATCH-YYYYMMDD or 独立目录（<理由>）"
  fi
  fi
  [[ -z "$reason86" ]] || die "GATE-E86: $reason86 (standards §1.1, v3.60.0)"
  implementation=$(json_field "$rec" implementation_owner)
  [[ -n "$implementation" ]] || die "GATE-E29: $file must declare implementation_owner"
  reject_placeholder_owner "$file" implementation_owner "$implementation"
  # v3.33.0 (FU-039/FU-041, CHG-033): standards §2.1 rule 10 (one role per
  # subject) enforced on the record — the spec/document author must be
  # declared at every level, differ from the reviewer at the lowest bar, and
  # differ from all three owners for L2/L3 (two-batch separation, §2.2).
  spec_author=$(json_field "$rec" spec_author)
  [[ -n "$spec_author" ]] || die "GATE-E30: $file must declare spec_author (standards §2.1 rule 10: author, implementer, tester, reviewer are distinct subjects)"
  reject_placeholder_owner "$file" spec_author "$spec_author"
  if [[ "$risk" == L2 || "$risk" == L3 ]]; then
    test_owner=$(json_field "$rec" test_owner)
    review_owner=$(json_field "$rec" review_owner)
    [[ -n "$test_owner" && -n "$review_owner" ]] || die "GATE-E31: $file must declare test_owner and review_owner for $risk"
    reject_placeholder_owner "$file" test_owner "$test_owner"
    reject_placeholder_owner "$file" review_owner "$review_owner"
    [[ "$implementation" != "$test_owner" && "$implementation" != "$review_owner" && "$test_owner" != "$review_owner" ]] || die "GATE-E32: $file requires distinct implementation, test, and review owners for $risk"
    [[ "$spec_author" != "$implementation" && "$spec_author" != "$test_owner" && "$spec_author" != "$review_owner" ]] || die "GATE-E33: $file requires spec_author distinct from implementation, test, and review owners for $risk (standards §2.1 rule 10)"
  else
    # v3.61.1 (CHG-078, REQ-1016): lowest-bar closure — DS §0.5.2 requires an
    # independent review subject even at L0/L1 ("评审不可与作者/开发合并"),
    # so an undeclared review_owner used to skip E34/E35 entirely. Declare it
    # mandatory here; the distinctness checks below now always run.
    review_owner=$(json_field "$rec" review_owner)
    [[ -n "$review_owner" ]] || die "GATE-E88: $file must declare review_owner for $risk (lowest bar: the review subject itself is mandatory — review may not merge with author/implementer, standards §0.5.2, v3.61.1)"
    reject_placeholder_owner "$file" review_owner "$review_owner"
    [[ "$spec_author" != "$review_owner" ]] || die "GATE-E34: $file: spec_author must differ from review_owner (lowest bar, standards §2.1 rule 10)"
    [[ "$implementation" != "$review_owner" ]] || die "GATE-E35: $file: review_owner must differ from implementation_owner (reviewer independence at the lowest bar, standards §2.1 rule 10)"
  fi
  # v3.5.0 L3 release authorization: flat string fields, not a nested object —
  # the record is extracted with a single-line sed, so nested JSON cannot parse.
  if [[ "$risk" == L3 ]]; then
    local auth_by auth_at auth_ev
    auth_by=$(json_field "$rec" release_authorized_by)
    auth_at=$(json_field "$rec" release_authorized_at)
    auth_ev=$(json_field "$rec" release_authorization_evidence)
    [[ -n "$auth_by" ]] || die "GATE-E36: $file must declare release_authorized_by for L3"
    reject_placeholder_owner "$file" release_authorized_by "$auth_by"
    [[ -n "$auth_at" ]] || die "GATE-E37: $file must declare release_authorized_at for L3"
    [[ -n "$auth_ev" ]] || die "GATE-E38: $file must declare release_authorization_evidence for L3"
  fi
  # v3.6.0 bug document set: bug_ref binds this change to defect document group(s)
  # under <bugs_root>/<bug_ref>/; when declared, the six-piece set must exist and
  # be non-empty (standards §2.5 stage 6). v3.28.0 (CHG-071 复盘): the check was
  # FAIL-OPEN — it only parsed flat strings, so changes declaring an array
  # ("bug_ref": ["BUG-040", …]) extracted empty and SKIPPED validation entirely.
  # Now both forms parse; a declared-but-unparseable bug_ref dies (fail-closed).
  # Validated refs are exported in bug_refs_current for the stop-stage
  # provenance check (stamp-provenance.sh --bug).
  local bug_ref _r
  bug_refs_current=""
  if printf '%s' "$rec" | grep -q '"bug_ref"'; then
    while IFS= read -r _r; do
      [[ -n "$_r" ]] && bug_refs_current="$bug_refs_current $_r"
    done < <(json_field_values "$rec" bug_ref)
    if [[ -z "${bug_refs_current// /}" ]]; then
      # An EXPLICIT empty value ("bug_ref": "" or []) means "no defect bound" —
      # same semantics as the field being absent (golden: 'begin skips bug_ref
      # validation when empty'). Only a present-but-unparseable value fails.
      if printf '%s' "$rec" | grep -qE "\"bug_ref\"[[:space:]]*:[[:space:]]*(\"\"|\[[[:space:]]*\])"; then
        :
      else
        die "GATE-E39: $file field 'bug_ref' is present but unparseable — use a flat string or a flat JSON string array of defect ids"
      fi
    fi
    for bug_ref in $bug_refs_current; do
      [[ "$bug_ref" =~ ^[A-Za-z0-9._-]+$ ]] || die "GATE-E40: $file field 'bug_ref' has invalid defect id '$bug_ref'"
      local bug_gdir p3_exempt=""
      bug_gdir=$(bug_group_dir "$bug_ref") || die "GATE-E41: $file bug_ref '$bug_ref': defect group not found under $bugs_root (standalone, BATCH-*/<id>, or flat BATCH-*/ anchor — standards §1.1)"
      # v3.40.0 (CHG-045): P3 copy-class groups may omit the three optional
      # pieces; flat batches read severity from the member's own section.
      local re_bid
      re_bid=$(printf '%s' "$bug_ref" | sed 's/[.[\*^$]/\\&/g')
      if [[ "$(basename "$bug_gdir")" =~ ^BATCH- ]] \
        && grep -qE "^##[[:space:]]+${re_bid}([[:space:]]|\$)" "$bug_gdir/01-diagnosis.md" 2>/dev/null; then
        bug_p3_lightweight "$bug_gdir" "$bug_ref" && p3_exempt=" 02-impact.md 05-config.md 06-tasks.md "
      else
        bug_p3_lightweight "$bug_gdir" && p3_exempt=" 02-impact.md 05-config.md 06-tasks.md "
      fi
      for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
        [[ " $p3_exempt " == *" $doc "* ]] && continue
        [[ -s "$bug_gdir/$doc" ]] || die "GATE-E42: $file bug_ref '$bug_ref' is missing defect document: $bug_gdir/$doc"
      done
      # v3.48.0 (CHG-058): BUG 轨延伸发现即时落盘（文件级机校；分节质量由评审 B 层核对）
      # v3.54.0 (CHG-067): same family covers 历史相似检索 (E84 semantics, BUG track)
      require_section_or_decl "$bug_gdir/01-diagnosis.md" "延伸发现" 2>/dev/null \
        && require_section_or_decl "$bug_gdir/01-diagnosis.md" "历史相似检索" '未命中（[^）]+）' 2>/dev/null \
        || die "GATE-E81: $file bug_ref '$bug_ref': 01-diagnosis missing 延伸发现/历史相似检索 section (BUG track, standards §2.5 stage 6, v3.48.0; renumbered from E16 in v3.48.1, CHG-060; 历史相似检索 added v3.54.0 CHG-067)"
    done
  fi
}

active_change() {
  [[ -s "$active_file" ]] || die "GATE-E43: no active change. Create documents, then run: scripts/agent-gate begin CHG-123"
  tr -d '[:space:]' < "$active_file"
}

extract_file_from_hook_input() {
  # Claude Code, Cursor, Gemini CLI, and Copilot place tool arguments under
  # tool_input. This intentionally supports the common path field spellings
  # without adding jq/Python as a dependency.
  local input
  input=$(cat)
  printf '%s' "$input" | sed -nE 's/.*"(file_path|path|filePath|target_file)"[[:space:]]*:[[:space:]]*"([^"\\]+)".*/\2/p' | head -n 1
}

validate_active_change() {
  local id
  id=$(active_change)
  required_docs_present "$id"
  validate_governance_state "$id"
}

working_code_changed() {
  local files f
  files=$( {
    git diff --name-only --diff-filter=ACMR
    git diff --cached --name-only --diff-filter=ACMR
    git ls-files --others --exclude-standard
  } | sort -u)
  while IFS= read -r f; do
    is_code_path "$f" && return 0
  done <<< "$files"
  return 1
}

# CHG-004 / REQ-022: the eight-category minimum doc set (standards §1.1) includes
# 06.5-deployment-config.md and 06-delivery-summary.md. Neither had a template nor
# any machine check, so "no config change" / "no follow-ups" were expressed by
# *omitting the file* — the exact gap that let CHG-003 nearly ship without 06.5.
# Both are delivery-bar items now. "Not hit" must be *declared*, and an unfilled
# template must not pass: templates ship a TEMPLATE-MARKER sentinel line that must
# be deleted once filled (same trick as bugfix-log.md's '### BUG-xxx' placeholder,
# which deliberately fails the '[0-9]' count).
check_delivery_doc() { # change-dir filename content-regex label
  local d="$1" name="$2" pat="$3" label="$4" f="" cand pdir
  # 落点三选一：① 变更目录（常态）② 仓库级 <docs>/（无功能目录的仓库，如本仓库）
  # ③ 功能目录 <docs>/<feature>/（§2.17 产物目录双轨约定）
  for cand in "$d/$name" "$docs_dir/$name"; do
    [[ -f "$cand" ]] && { f="$cand"; break; }
  done
  # ③ 刻意**不用**裸 glob `<docs>/*/`——独立复核实测：那样只要有人在文档根下任意子目录
  #   （如 <docs>/unrelated/）放一个同名占位文件，所有变更的交付门禁就永久放行了。
  #   故此处要求该目录"看起来像功能目录"：须含 01-spec.md 或 01.5-rtvm-matrix.md。
  #   这是本族根因的反向形态——覆盖面过宽比过窄更危险，因为它制造的是假绿。
  if [[ -z "$f" ]]; then
    for cand in "$docs_dir"/*/"$name"; do
      [[ -f "$cand" ]] || continue
      pdir=$(dirname "$cand")
      [[ -f "$pdir/01-spec.md" || -f "$pdir/01.5-rtvm-matrix.md" ]] || continue
      f="$cand"; break
    done
  fi
  [[ -n "$f" ]] || die "GATE-E44: cannot finish: missing $label ($name) — standards §1.1 eight-category minimum doc set"
  # Sentinel must be the template's own first-line marker form, anchored to
  # line start — a bare substring match false-positives on prose that merely
  # MENTIONS the marker (live-found when a ledger row describing it tripped).
  if grep -q '^<!-- TEMPLATE-MARKER' "$f"; then
    die "GATE-E45: cannot finish: $f is still the unfilled template — delete the TEMPLATE-MARKER line once filled (standards §1.1)"
  fi
  grep -qE "$pat" "$f" \
    || die "GATE-E46: cannot finish: $f must declare '未命中，不适用' with evidence, or carry real $label rows (standards §1.1)"
}

# REQ-962 (v3.44.0): a lightweight-channel declaration stub may only carry the
# delivery bar for L0 (standards §1.1 two-tier non-placeholder sets). Off-L0 it
# is the channel escaping its lane → literal GATE-E52 (T30 static Exx check).
# The stub test is deliberately SHAPE-AGNOSTIC (review P1 fix): one content line
# (HTML comment spans stripped — single-line and multi-line, so a `<!-- x -->`
# prefix cannot blind the counter) containing 未命中 in any bracket variant is
# still a stub. L0's own admission stays on the strict §1.1 declaration shape.
stub_guard() { # file risk id
  local f="$1" risk="$2" id="$3" stub
  stub=$(awk '
    { line=$0
      while (1) {
        if (!c) {
          i = index(line, "<!--"); if (!i) break
          pre = substr(line, 1, i - 1); rest = substr(line, i + 4)
          j = index(rest, "-->")
          if (j) { line = pre substr(rest, j + 3) } else { c = 1; line = pre; break }
        } else {
          j = index(line, "-->"); if (!j) { line = ""; break }
          line = substr(line, j + 3); c = 0
        }
      }
      if (line ~ /[^ \t]/) n++
    }
    END { print n + 0 }' "$f")
  if [[ "$stub" -eq 1 ]] && grep -q '未命中' "$f" 2>/dev/null; then
    die "GATE-E52: cannot finish: $f is a declaration-only stub but '$id' declares risk_level ${risk:-unknown} — the L0 minimal-set carve-out (standards §1.1) does not apply"
  fi
  return 0
}

# Delivery evidence a change must carry before it may leave the machine: the
# v3.7.0 coding record, test results, a changelog, and the v2.21.0 ReAct
# Observation records in it (standards §2.16.2). Shared by --stage stop and
# branch-mode CI so both enforcement lines hold the same bar. (v3.5.0)
validate_delivery() { # change-id
  local id="$1" d
  d=$(change_dir "$id")
  # REQ-962 (v3.44.0): L0 minimal-set carve-out — 04.5/05 may be satisfied by a
  # §1.1 lightweight-channel single-line declaration. risk_level comes from the
  # same governance record begin validated; a missing record stays on the hard
  # path (fail-closed: the carve-out is the exception, never the default).
  # Die codes stay LITERAL (T30 static Exx check): the stub rule is factored
  # into stub_guard below, the missing-file dies stay inline.
  local rec risk="" \
    dcl='^[[:space:]]*-[[:space:]]*\*\*.*\*\*(：|:)[[:space:]]*未命中，不适用（.+）'
  rec=$(gov_record "$d/00-governance.json" "$id")
  [[ -n "$rec" ]] && risk=$(json_field "$rec" risk_level)
  if [[ "$risk" == "L0" ]] && grep -qE "$dcl" "$d/04.5-coding-record.md" 2>/dev/null; then
    : # L0 declaration satisfies the coding-record bar (standards §1.1, REQ-962)
  else
    [[ -s "$d/04.5-coding-record.md" ]] || die "GATE-E47: cannot finish: missing coding record $d/04.5-coding-record.md"
    stub_guard "$d/04.5-coding-record.md" "$risk" "$id"
  fi
  if [[ "$risk" == "L0" ]] && grep -qE "$dcl" "$d/05-test-results.md" 2>/dev/null; then
    : # L0 declaration satisfies the test-evidence bar (standards §1.1, REQ-962)
  else
    [[ -s "$d/05-test-results.md" ]] || die "GATE-E48: cannot finish: missing test evidence $d/05-test-results.md"
    stub_guard "$d/05-test-results.md" "$risk" "$id"
  fi
  [[ -s "$d/09-changelog.md" ]] || die "GATE-E49: cannot finish: missing changelog $d/09-changelog.md"
  # v3.56.0 (CHG-069, REQ-1005): when a review report exists it must carry a
  # §2.1.7 signature line whose third token is a traceable subtask id
  # (`task-…` or `ses-…`/`ses_…` session id — DS §2.1 rule 7 allows either).
  # A report without one is a self-review posing as an independent review
  # (BATCH-20260925 execution deviation, closed by the backfill review).
  # Absent report: legitimate at any risk level (not just L0 minimal set).
  # Single die point keeps the die-code domain unique (T41).
  if [[ -e "$d/07-review-report.md" ]] && [[ -s "$d/07-review-report.md" ]]; then
    # Not line-anchored on purpose: signature lines carry CJK prefixes
    # (`- 评审主体：…`), which an ASCII-anchored pattern cannot match. The
    # quote-citation false-positive surface is accepted at the E82 precedent
    # (low risk; B-layer 评审结论 + provenance backstop).
    grep -Eq "${sig_head}(task[-_][A-Za-z0-9_-]+|ses[-_][A-Za-z0-9_-]+)" "$d/07-review-report.md" \
      || die "GATE-E85: $d/07-review-report.md lacks an independent-review signature with a traceable subtask/session id (§2.1.7 'platform / model / task-… or ses-…') — self-reviews posing as reviews are a gate-5 violation (standards §2.5 stage 8, v3.56.0 CHG-069)"
  fi
  # v3.74.0 (CHG-098, REQ-1104/1105): finding disposition (E114/E115) and review
  # convergence (E116). Both are no-ops without a review report; the round
  # ledger stays fail-open when .agent-state is absent.
  if [[ -s "$d/07-review-report.md" ]]; then
    track_review_round "$d" "$id" "$d/07-review-report.md"
    assert_finding_disposition "$d" "$d/07-review-report.md"
    assert_finding_source "$d" "$d/07-review-report.md"
  fi
  # Every executed stage must leave an Observation record (verification
  # command + actual output) in the changelog.
  grep -q "Observation" "$d/09-changelog.md" \
    || die "GATE-E50: cannot finish: changelog missing ReAct Observation records (standards §2.16.2)"
  # Gate 4 (v3.7.0): every REQ id referenced by the changelog must be backfilled
  # as a row in some docs/<feature>/01.5-rtvm-matrix.md. Changelogs without REQ
  # references (pure fixes / docs changes) are exempt — same semantics as the
  # consistency audit's G5. Updating the changelog alone never closes the loop.
  local req hit
  for req in $(grep -oE 'REQ-[0-9]+' "$d/09-changelog.md" | sort -u); do
    hit=0
    # FU-019: the standards source repo keeps its matrix nested at
    # <change_root>/<CHG>/01.5 (two levels) — a single-level glob would report
    # every REQ as unbackfilled there (fail-closed but unusable).
    for m in "$docs_dir"/*/01.5-rtvm-matrix.md "$change_root"/*/01.5-rtvm-matrix.md; do
      [[ -f "$m" ]] || continue
      grep -qE "^\| \`?${req}\`?" "$m" && { hit=1; break; }
    done
    [[ "$hit" == 1 ]] || die "GATE-E51: cannot finish: REQ $req referenced in changelog but not backfilled in $docs_dir/<feature>/01.5-rtvm-matrix.md (gate 4)"
  done
  # CHG-004 / REQ-022: the remaining two of the eight-category minimum doc set.
  check_delivery_doc "$d" 06.5-deployment-config.md '^([#>-][[:space:]]*)*未命中|^[|].*(未命中|(CFG|DB)-[0-9]+)|(CFG|DB)-[0-9]+' 'config/DB record'
  check_delivery_doc "$d" 06-delivery-summary.md '^[|].*FU-[0-9]+|^[-*][[:space:]]+.*FU-[0-9]+|^(#{1,6}[[:space:]]*).*遗留' 'delivery summary / FU ledger'
  # v3.35.0 (standards §1.3): project-master backfill checklist — P00..P12
  # rows present, each [x] or 未命中 with reason.
  validate_master_backfill "$d"
  # v3.17.0 provenance, scope widened v3.26.0 (CHG-026): EVERY *.md artifact in
  # the change dir must carry a script-generated block — the author / committer
  # / host / UTC-time header is the delivery traceability bar, not a
  # coding-record extra. Checked LAST so earlier structural failures name their
  # own check; 00-governance.json stays excluded (HTML comments would break the
  # flat-JSON readers — v3.22.0 decision, unchanged). Run
  # `scripts/stamp-provenance.sh --all <CHG-id>` at delivery time.
  # v3.33.0 (FU-039, CHG-033): an 「专家评审记录」 section (heading-form only —
  # inline mentions in prose must NOT trigger this) in the requirement or plan
  # artifact must carry a §2.1.7-style agent signature (platform/model/task,
  # three slash-separated tokens). A missing section is legitimate N/A
  # (L0/L1 lightweight channel); a section without a signature is a
  # self-signed review and blocks delivery.
  local sigf sigsec
  for sigf in 01-spec.md 03-modification-plan.md; do
    [[ -s "$d/$sigf" ]] || continue
    sigsec=$(awk '/^#{1,6}.*专家评审记录/{flag=1;next} flag && /^#{1,6}[[:space:]]/{flag=0} flag' "$d/$sigf")
    [[ -n "$sigsec" ]] || continue
    # §2.1.7 canonical shape only: `platform / model / task` with spaced
    # slashes — paths (docs/x/y.md), URLs (https://...) and compact a/b/c
    # strings do NOT match (review finding: evidence paths inside the section
    # must not satisfy the signature check).
    echo "$sigsec" | grep -Eq "${sig_head}[A-Za-z0-9_-]+" \
      || die "GATE-E82: $d/$sigf 专家评审记录 section lacks an agent signature (§2.1.7 'platform / model / task') — standards §2.2 two-batch rule; renumbered from E52 in v3.48.1, CHG-060 (E52 stays with the declaration-only stub check, whose code is pinned by T30/T37)"
  done
  local pf
  for pf in "$d"/*.md; do
    [[ "$(basename "$pf")" == "00-governance.json" ]] && continue
    validate_provenance "$pf"
  done
}

# v3.35.0 (BUG-005, standards §1.1): defect doc groups live in a per-day batch;
# v3.36.0 (BUG-006, standards §1.1): the batch is FLAT — six pieces live DIRECTLY
# in <bugs_root>/BATCH-YYYYMMDD/ and same-day members are separated by
# `## <BUG-id>` anchors (isomorphic with the change track). THREE legal layouts
# resolve through THIS function, exactly one must match; two at once is a
# fail-closed defect, not a warning:
#   1. standalone  <bugs_root>/<BUG-id>/            (legacy + single-of-day)
#   2. nested      <bugs_root>/BATCH-*/<BUG-id>/    (v3.35.0 form, legacy-legal)
#   3. flat        <bugs_root>/BATCH-*/ (anchors)   (v3.36.0 default)
bug_group_dir() { # <BUG-id> -> prints the group dir (exit 1 if absent)
  local id="$1" standalone="" nested="" flat="" b
  [[ -d "$bugs_root/$id" ]] && standalone="$bugs_root/$id"
  for b in "$bugs_root"/BATCH-*/; do
    if [[ -d "${b}${id}" ]]; then
      if [[ -n "$nested" ]]; then
        die "GATE-E53: defect group '$id' exists in more than one day batch under $bugs_root — keep one (standards §1.1)"
      fi
      nested="${b%/}/$id"
    fi
    # v3.36.0 (BUG-006): flat member = `## <id>` anchor in the batch's own
    # six pieces. Anchor on 01-diagnosis.md — the group's identity piece.
    if [[ -s "${b}01-diagnosis.md" ]] \
      && grep -qE "^##[[:space:]]+${id}([[:space:]]|\$)" "${b}01-diagnosis.md" 2>/dev/null; then
      if [[ -n "$flat" ]]; then
        die "GATE-E54: defect group '$id' is anchored in more than one day batch under $bugs_root — keep one (standards §1.1)"
      fi
      flat="${b%/}"
    fi
  done
  local hits=0
  [[ -n "$standalone" ]] && hits=$((hits+1))
  [[ -n "$nested" ]] && hits=$((hits+1))
  [[ -n "$flat" ]] && hits=$((hits+1))
  if [[ "$hits" -gt 1 ]]; then
    die "GATE-E55: defect group '$id' exists in more than one legal layout under $bugs_root (standalone=$standalone nested=$nested flat=$flat) — keep exactly one (standards §1.1)"
  fi
  if [[ -n "$standalone" ]]; then printf '%s' "$standalone"; return 0; fi
  if [[ -n "$nested" ]]; then printf '%s' "$nested"; return 0; fi
  if [[ -n "$flat" ]]; then printf '%s' "$flat"; return 0; fi
  return 1
}

# v3.40.0 (CHG-045, FU-106②): P3 lightweight channel for defect doc groups.
# A group whose 01-diagnosis HEAD carries the EXACT line `severity: P3` (copy-class
# defect) may omit 02-impact/05-config/06-tasks entirely. Everything else stays
# fail-closed: no declaration, a different value, a shape mismatch, or a
# severity line outside the first 20 lines → the full six-piece check. The
# mandatory pieces (01-diagnosis/03-test-plan/04-matrix) can never be waived.
# Flat batches must declare severity INSIDE their own `## <BUG-id>` section
# (pass <gid>); for standalone/nested groups the file head is scanned (omit
# <gid>). <gid> is escaped before it is used in a regex (BUG ids may contain '.').
bug_p3_lightweight() { # <group-or-batch-dir> [<BUG-id>] -> 0 if channel applies
  local dir="$1" gid="${2:-}" re
  re=$(printf '%s' "$gid" | sed 's/[.[\*^$]/\\&/g')
  if [[ -n "$gid" ]]; then
    [[ -s "$dir/01-diagnosis.md" ]] || return 1
    awk -v id="$re" '
      $0 ~ ("^##[[:space:]]+" id "([[:space:]]|$)") { on=1; next }
      on && /^##[[:space:]]/ { on=0 }
      on { print }
    ' "$dir/01-diagnosis.md" 2>/dev/null | head -20 | grep -qE '^severity:[[:space:]]*P3[[:space:]]*$'
  else
    head -20 "$dir/01-diagnosis.md" 2>/dev/null | grep -qE '^severity:[[:space:]]*P3[[:space:]]*$'
  fi
}

# v3.28.0 (CHG-071 / BUG-040~055 复盘): defect doc groups are enforced by
# EXISTENCE of <bugs_root>/<BUG-id>/, not only through a change's bug_ref —
# 16 groups shipped with only 01-diagnosis.md (and self-checked "[x] done" in
# the log) because every machine check was scoped to the change track. The
# sweep runs at staged / stop / CI so pure bug-track处置 hits the same bar.
# Escape hatch: <bugs_root>/.gate-allowlist lists legacy incomplete groups,
# one id per line, reason in a trailing comment — listed groups WARN (visible,
# counted by audit G8), unlisted groups die.
validate_bug_groups() {
  local group doc missing allow listed gid
  [[ -d "$bugs_root" ]] || return 0
  allow="$bugs_root/.gate-allowlist"
  # v3.35.0 (BUG-005): sweep BOTH layouts — standalone and day-batched.
  for group in "$bugs_root"/BUG-*/ "$bugs_root"/BATCH-*/BUG-*/; do
    [[ -d "$group" ]] || continue
    [[ -s "$group/01-diagnosis.md" ]] || continue
    missing=""
    # v3.40.0 (CHG-045): P3 copy-class groups may omit the three optional pieces.
    local p3_exempt=""
    bug_p3_lightweight "$group" && p3_exempt=" 02-impact.md 05-config.md 06-tasks.md "
    for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
      [[ " $p3_exempt " == *" $doc "* ]] && continue
      [[ -s "$group/$doc" ]] || missing="$missing $doc"
    done
    [[ -z "$missing" ]] && continue
    gid=$(basename "$group")
    listed=""
    if [[ -f "$allow" ]]; then
      listed=$(grep -vE '^[[:space:]]*(#|$)' "$allow" 2>/dev/null | awk '{print $1}' | grep -Fx "$gid" || true)
    fi
    if [[ -n "$listed" ]]; then
      echo "agent-gate: WARN defect group $gid incomplete (allowlisted):$missing"
    else
      die "GATE-E56: defect group $gid is missing:$missing — complete the six-piece set (standards §2.5 stage 6) or register a reason in $allow"
    fi
  done
  # v3.36.0 (BUG-006): FLAT day-batches — the six pieces live directly in
  # BATCH-YYYYMMDD/ and members are `## <BUG-id>` anchor sections (isomorphic
  # with change batches). Completeness is ANCHOR-based: every id anchored in
  # 01-diagnosis.md must carry its own section in all six pieces. Legacy
  # day-folders that only ever held a merged single file are caught here too —
  # that is the backfill list (§2.14), with the allowlist as the escape hatch.
  for batch in "$bugs_root"/BATCH-*/; do
    [[ -s "${batch}01-diagnosis.md" ]] || continue
    # v3.61.1 (CHG-078, REQ-1015): roster-diff guard. The per-gid loop below
    # only iterates ids anchored in 01-diagnosis.md — a BUG id anchored in a
    # sibling doc but missing from 01-diagnosis escaped both bug_group_dir and
    # E57 entirely. Union across the six docs and die on the diff (T41: this
    # is E87's single die site).
    local diag_ids all_ids stray
    diag_ids=$(sed -nE 's/^##[[:space:]]+(BUG-[A-Za-z0-9._-]+)([[:space:]].*)?$/\1/p' "${batch}01-diagnosis.md" | sort -u)
    all_ids=$( (cat "${batch}01-diagnosis.md" "${batch}02-impact.md" "${batch}03-test-plan.md" "${batch}04-matrix.md" "${batch}05-config.md" "${batch}06-tasks.md" 2>/dev/null || true) | sed -nE 's/^##[[:space:]]+(BUG-[A-Za-z0-9._-]+)([[:space:]].*)?$/\1/p' | sort -u)
    stray=$(comm -13 <(printf '%s\n' "$diag_ids") <(printf '%s\n' "$all_ids"))
    if [[ -n "$stray" ]]; then
      die "GATE-E87: defect group anchor(s)$stray present in sibling docs but missing from ${batch}01-diagnosis.md — the 01-diagnosis anchor set is the authoritative roster (standards §2.5 stage 6, v3.61.1)"
    fi
    for gid in $(sed -nE 's/^##[[:space:]]+(BUG-[A-Za-z0-9._-]+)([[:space:]].*)?$/\1/p' "${batch}01-diagnosis.md" | sort -u); do
      missing=""
      # v3.40.0 (CHG-045): severity must be declared inside the member's own
      ## `## <BUG-id>` section; undeclared members keep the full anchor set.
      p3_exempt=""
      bug_p3_lightweight "$batch" "$gid" && p3_exempt=" 02-impact.md 05-config.md 06-tasks.md "
      local re_gid
      re_gid=$(printf '%s' "$gid" | sed 's/[.[\*^$]/\\&/g')
      for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
        [[ " $p3_exempt " == *" $doc "* ]] && continue
        grep -qE "^##[[:space:]]+${re_gid}([[:space:]]|\$)" "$batch/$doc" 2>/dev/null || missing="$missing $doc"
      done
      [[ -z "$missing" ]] && continue
      listed=""
      if [[ -f "$allow" ]]; then
        listed=$(grep -vE '^[[:space:]]*(#|$)' "$allow" 2>/dev/null | awk '{print $1}' | grep -Fx "$gid" || true)
      fi
      if [[ -n "$listed" ]]; then
        echo "agent-gate: WARN defect group $gid incomplete (allowlisted):$missing"
      else
        die "GATE-E57: defect group $gid is missing:$missing — complete the six-piece anchor set in $batch (standards §2.5 stage 6, v3.36.0 flat form) or register a reason in $allow"
      fi
    done
  done
  # v3.35.0 (BUG-005): the day-batch default is ENFORCED, mirroring the change
  # track (v3.27.0) — a defect group created TODAY outside the day batch must
  # join it. Detection uses the group's provenance block (script-written UTC
  # date; un-stamped groups are skipped here and caught by the delivery-time
  # stamping checks instead).
  # v3.62.2 (CHG-082, REQ-1028): the check now runs BOTH directions,
  # mirroring GATE-E86 on the change track — forward (batch exists: today's
  # standalone groups must join) and reverse (no batch yet: the FIRST L0/L1
  # defect of the day creates the day batch, standards §1.1 first-of-day
  # rule, v3.61.2). The old `|| return 0` silently passed the reverse shape.
  if [[ "${AGENT_GUARD_ALLOW_INDEPENDENT:-}" != "1" ]]; then
    local today pb pdate batch_exists e58_why
    today=$(date -u +%Y-%m-%d)
    batch_exists=0
    [[ -d "$bugs_root/BATCH-$(date -u +%Y%m%d)" ]] && batch_exists=1
    for group in "$bugs_root"/BUG-*/; do
      [[ -d "$group" ]] || continue
      pb="$group/01-diagnosis.md"
      [[ -s "$pb" ]] || continue
      pdate=$(sed -n 's/^generated_at:[[:space:]]*\([0-9-]\{4\}-[0-9-]\{2\}-[0-9-]\{2\}\).*/\1/p' "$pb" | head -1)
      [[ "$pdate" == "$today" ]] || continue
      gid=$(basename "$group")
      listed=""
      [[ -f "$allow" ]] && listed=$(grep -vE '^[[:space:]]*(#|$)' "$allow" 2>/dev/null | awk '{print $1}' | grep -Fx "$gid" || true)
      if [[ -z "$listed" ]]; then
        # single die point (T41 code uniqueness): message branches on direction
        if [[ "$batch_exists" == 1 ]]; then
          e58_why="was created today ($pdate) while $bugs_root/BATCH-$(date -u +%Y%m%d) exists — move it into the day batch (standards §1.1)"
        else
          e58_why="was created today ($pdate) with no $bugs_root/BATCH-$(date -u +%Y%m%d) yet — the first L0/L1 defect of the day creates the day batch (standards §1.1 first-of-day rule)"
        fi
        die "GATE-E58: standalone defect group $gid $e58_why; set AGENT_GUARD_ALLOW_INDEPENDENT=1 only with a recorded justification"
      fi
    done
  fi
}

# v3.28.0: defect groups bound to the active change (bug_ref) must carry the
# provenance header on all six pieces — stamp with
# `scripts/stamp-provenance.sh --bug <BUG-id>` at delivery time. Relies on
# bug_refs_current set by validate_governance_state (stop stage only; begin
# must not demand provenance on freshly created groups).
validate_bug_ref_provenance() {
  local ref doc gdir
  [[ -z "${bug_refs_current// /}" ]] && return 0
  for ref in $bug_refs_current; do
    gdir=$(bug_group_dir "$ref") || gdir="$bugs_root/$ref"
    for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
      validate_provenance "$gdir/$doc"
    done
  done
}

# v3.35.0 (standards §1.3): the changelog of a delivered change must carry the
# project-master backfill checklist — one row per master P00..P12, each either
# `[x]` (backfilled) or explicitly `未命中（理由）`. An unchecked `[ ]` row
# without a reason is an open loop, not a completion.
validate_master_backfill() { # change-dir
  local d="$1" p row
  grep -q "项目总册回填清单" "$d/09-changelog.md" \
    || die "GATE-E59: cannot finish: 09-changelog.md missing 「项目总册回填清单」 section (standards §1.3)"
  for p in P00 P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12; do
    # v3.66.0 (CHG-089): guard grep no-match — under set -euo pipefail a bare
    # `grep | head` assignment exits 1 and set -e kills the script before the
    # GATE-E60 die() below fires (silent death, friction ledger bypassed).
    row=$(grep -m1 -E "^- \[[ x]\] ${p}([^0-9]|$)" "$d/09-changelog.md" || true)
    [[ -n "$row" ]] || die "GATE-E60: cannot finish: 项目总册回填清单 missing row for $p (standards §1.3)"
    echo "$row" | grep -qE "^- \[x\]|未命中" \
      || die "GATE-E61: cannot finish: 项目总册回填清单 row $p is neither '[x]' nor '未命中（理由）' (standards §1.3)"
  done
}

# v3.35.0 (standards §1.3): begin refuses to start work in a repo whose
# project masters are not initialized. Filling the skeletons is the FIRST
# change's job (docs edits precede begin); the gate only demands the thirteen
# files exist. Escape hatch is explicit: AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1
# with the justification recorded in 09 重要上下文 — fail-closed, never silent.
# v3.67.0 (CHG-090, REQ-1054): P12 产品上下文册 joins the set — thirteen files.
validate_project_masters() {
  local f missing=""
  [[ -d "$docs_dir/project" ]] || die "GATE-E62: project masters not initialized: $docs_dir/project/ missing — copy <docs>/templates/project/ (skill resources/templates/project/) first (standards §1.3); set AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 only with a recorded justification"
  for f in P00-project-charter.md P01-requirements-master.md P02-architecture-master.md P03-interface-registry.md P04-data-dictionary.md P05-task-plan.md P06-test-master.md P07-test-verdicts.md P08-deployment-master.md P09-risk-register.md P10-change-ledger.md P11-decision-log.md P12-product-context.md; do
    [[ -s "$docs_dir/project/$f" ]] || missing="$missing $f"
  done
  [[ -z "$missing" ]] || die "GATE-E63: project masters incomplete:$missing — initialize all thirteen under $docs_dir/project/ (standards §1.3; P12 产品上下文册 v3.67.0)"
}

# v3.76.0 (CHG-100, REQ-1115~1116): 验证通道标量读取器——**唯一解析权威**（旧 sed
# 一次性解析已删，禁止回退成第二权威）。方言（越界一律 unparsable，fail-closed，
# 绝不猜）：双引号 "…"（含 \\ \" \n 反转义）；单引号 '…'（'' 转义）；裸标量
# （剥行尾 ` #` 注释与行尾空白）；块标量 | / >（含 - / + 裁剪、块内相对缩进保留、
# 折叠 > 用空行分段）。作用域：只认 `<sect>:` 段内、缩进等于该段首个子键缩进的
# `key:` —— 顶层、其它段内、其它键的块正文里的同名键一律 unparsable（显式，不
# 静默 absent："配了却没跑且无痕"正是要消灭的事故形态）。
# 输出协议（调用端唯一契约）：ok<TAB>值 / absent<TAB> / unparsable<TAB>细节
# 细节 ∈ value-invalid（空值/未闭合引号/非法块标量）| multiline（多行裸标量）
#        | misplaced（不在 <sect>: 段内或层级不对）
yml_dump_block() { # <fold> <chomp> <blk> — 块标量收尾（裁剪 + 折叠收口）
  local fold="$1" chomp="$2" val="$3"
  if [[ "$fold" == 1 ]]; then
    while [[ "$val" == *" " ]]; do val="${val% }"; done
    case "$chomp" in '-'*) : ;; *) val="$val"$'\n' ;; esac
  fi
  case "$chomp" in
    '-') while [[ "$val" == *$'\n' ]]; do val="${val%$'\n'}"; done ;;
    '+') : ;;
    *)   while [[ "$val" == *$'\n'$'\n' ]]; do val="${val%$'\n'}"; done ;;
  esac
  [[ -n "$val" ]] || { printf 'unparsable\tvalue-invalid\n'; return 0; }
  printf 'ok\t%s\n' "$val"
}

yml_scalar() { # <file> <key> [section=ci]
  local f="$1" key="$2" sect="${3:-ci}"
  local _l _r _ind _ki=-1 _st=seek _val _fold=0 _chomp=keep _blk="" _prevblank=0
  local _i _c _n _closed _top="" _sect_ind=-1 _ans=-1 _bi=-1 _misplaced=0
  local _hk _rest _isblk
  [[ -f "$f" ]] || { printf 'absent\t\n'; return 0; }
  while IFS= read -r _l || [[ -n "$_l" ]]; do
    _l="${_l//$'\r'/}"
    _ind=0
    while [[ "${_l:_ind:1}" == " " || "${_l:_ind:1}" == $'\t' ]]; do _ind=$((_ind+1)); done
    _r="${_l:_ind}"
    case "$_st" in
      block)
        # 我们的键的块正文：空行保留；更浅的非空行 = 块结束 → 立即出值（首个命中
        # 即返回，不能因为后面还有同级键/别的段就把已收集的块丢掉，独立评审 F1）。
        if [[ -z "$_r" ]]; then
          if [[ "$_fold" == 1 ]]; then _prevblank=1; else _blk="$_blk"$'\n'; fi
          continue
        fi
        if (( _ind <= _ans )); then
          yml_dump_block "$_fold" "$_chomp" "$_blk"
          return 0
        fi
        (( _bi >= 0 )) || _bi=$_ind
        _r="${_l:_bi}"
        if [[ "$_fold" == 1 ]]; then
          if (( _prevblank == 1 )); then _blk="$_blk"$'\n'"$_r"; else
            [[ -n "$_blk" ]] && _blk="$_blk "
            _blk="$_blk$_r"
          fi
        else
          _blk="$_blk$_r"$'\n'
        fi
        _prevblank=0
        continue
        ;;
      skip)
        # 其它键的块正文：整段跳过（正文里的同名键不得被当成配置）。但正文里出现
        # **同名行**要 fail-closed（misplaced）：它"看起来配了"却永不被解析——正是
        # 本变更要消灭的形态（yml 注释是方言声明唯一权威载体，已声明这类形态
        # "一律 unparsable，不静默忽略"；独立评审 R1 复评收口）。
        [[ -z "$_r" ]] && continue
        if (( _ind > _ans )); then
          case "$_r" in "$key":*) _misplaced=1 ;; esac
          continue
        fi
        _st=seek
        ;;
      scalar)
        # 标量值的续行判定：更深缩进 = 多行裸标量（不支持）→ unparsable（不静默截断）。
        if [[ -n "$_r" ]] && (( _ind > _ki )); then
          printf 'unparsable\tmultiline\n'; return 0
        fi
        printf 'ok\t%s\n' "$_val"; return 0
        ;;
    esac
    [[ -n "$_r" ]] || continue
    case "$_r" in '#'*) continue ;; esac
    if (( _ind == 0 )); then
      # 顶层段：记录当前段名并重置段内子键缩进基准。顶层出现同名键 = 位置非法
      # （旧 sed 会匹配到并执行，新读取器必须显式 reject，不能静默 absent）。
      case "$_r" in *:*) _top="${_r%%:*}" ;; *) _top="" ;; esac
      [[ "$_top" == "$key" ]] && _misplaced=1
      _sect_ind=-1
      continue
    fi
    # 非空子行：拆出键名与值区。
    case "$_r" in
      *:*) _hk="${_r%%:*}" ;;
      *)   _hk="" ;;
    esac
    _rest="${_r#*:}"
    while [[ "$_rest" == " "* || "$_rest" == $'\t'* ]]; do _rest="${_rest:1}"; done
    _isblk=0
    case "$_rest" in
      '|'*|'>'*)
        _n="${_rest:1}"
        case "$_n" in [-+]*) _n="${_n:1}" ;; esac
        while [[ "$_n" == " "* || "$_n" == $'\t'* ]]; do _n="${_n:1}"; done
        [[ -z "$_n" || "$_n" == "#"* ]] && _isblk=1
        ;;
    esac
    if [[ "$_hk" != "$key" ]]; then
      # 段内第一个子键定义缩进基准（`ci: sub:` 之后的更深同名键因此落 misplaced，
      # 而不是被当成真配置——独立评审 F6② 同族）。
      [[ "$_top" == "$sect" ]] && (( _sect_ind < 0 )) && _sect_ind=$_ind
      (( _isblk == 1 )) && { _ans=$_ind; _st=skip; }
      continue
    fi
    if [[ "$_top" == "$sect" ]] && (( _sect_ind < 0 )); then _sect_ind=$_ind; fi
    if [[ "$_top" != "$sect" || "$_ind" != "$_sect_ind" ]]; then _misplaced=1; continue; fi
    _ki=$_ind
    if (( _isblk == 1 )); then
      _ans=$_ind; _bi=-1; _blk=""; _prevblank=0; _st=block
      case "$_rest" in '|'*) _fold=0 ;; *) _fold=1 ;; esac
      _n="${_rest:1}"
      case "$_n" in [-+]*) _chomp="${_n:0:1}" ;; *) _chomp=keep ;; esac
      continue
    fi
    if [[ -z "$_rest" || "$_rest" == "#"* ]]; then printf 'unparsable\tvalue-invalid\n'; return 0; fi
    # `|` / `>` 是保留指示符：不是合法块标量开头就不能当裸标量（`|x` 曾静默成命令）。
    case "$_rest" in '|'*|'>'*) printf 'unparsable\tvalue-invalid\n'; return 0 ;; esac
    case "$_rest" in
      '"'*)
        _val=""; _i=1; _closed=0
        while (( _i < ${#_rest} )); do
          _c="${_rest:_i:1}"
          if [[ "$_c" == '\' ]]; then
            _n="${_rest:_i+1:1}"
            case "$_n" in
              '"') _val="$_val\"" ;;
              '\') _val="$_val\\" ;;
              'n') _val="$_val"$'\n' ;;
              '') _closed=-1; break ;;
              *) _val="$_val\\$_n" ;;
            esac
            _i=$((_i+2))
          elif [[ "$_c" == '"' ]]; then
            _closed=1; _i=$((_i+1)); break
          else
            _val="$_val$_c"; _i=$((_i+1))
          fi
        done
        (( _closed == 1 )) || { printf 'unparsable\tvalue-invalid\n'; return 0; }
        _rest="${_rest:_i}"
        while [[ "$_rest" == " "* || "$_rest" == $'\t'* ]]; do _rest="${_rest:1}"; done
        [[ -z "$_rest" || "$_rest" == "#"* ]] || { printf 'unparsable\tvalue-invalid\n'; return 0; }
        [[ -n "$_val" ]] || { printf 'unparsable\tvalue-invalid\n'; return 0; }
        _st=scalar; continue ;;
      "'"*)
        _val=""; _i=1; _closed=0
        while (( _i < ${#_rest} )); do
          _c="${_rest:_i:1}"
          if [[ "$_c" == "'" ]]; then
            if [[ "${_rest:_i+1:1}" == "'" ]]; then _val="$_val'"; _i=$((_i+2)); continue; fi
            _closed=1; _i=$((_i+1)); break
          fi
          _val="$_val$_c"; _i=$((_i+1))
        done
        (( _closed == 1 )) || { printf 'unparsable\tvalue-invalid\n'; return 0; }
        _rest="${_rest:_i}"
        while [[ "$_rest" == " "* || "$_rest" == $'\t'* ]]; do _rest="${_rest:1}"; done
        [[ -z "$_rest" || "$_rest" == "#"* ]] || { printf 'unparsable\tvalue-invalid\n'; return 0; }
        [[ -n "$_val" ]] || { printf 'unparsable\tvalue-invalid\n'; return 0; }
        _st=scalar; continue ;;
      *)
        _val="$_rest"
        case "$_val" in *[[:space:]]#*) _val="${_val%%[[:space:]]#*}" ;; esac
        while [[ "$_val" == *" " ]]; do _val="${_val% }"; done
        while [[ "$_val" == *$'\t' ]]; do _val="${_val%$'\t'}"; done
        [[ -n "$_val" ]] || { printf 'unparsable\tvalue-invalid\n'; return 0; }
        _st=scalar; continue ;;
    esac
  done < "$f"
  if [[ "$_st" == block ]]; then yml_dump_block "$_fold" "$_chomp" "$_blk"; return 0; fi
  if [[ "$_st" == scalar ]]; then printf 'ok\t%s\n' "$_val"; return 0; fi
  (( _misplaced == 1 )) && { printf 'unparsable\tmisplaced\n'; return 0; }
  printf 'absent\t\n'
}

# v3.76.0 (CHG-100, REQ-1117): 通道状态机器可见——唯一写点，失败 fail-open。
# command 的换行折叠为空格（JSON 单行约束）；exit_code 用 null 表示未执行。
# DES-1890 口径：BASH_VERSION + uname -sm + **yml sha256 前 12 位**（缺第三段则
# 状态档无法回答"这条判定对应哪一版 yml"——排障第一问，独立评审 F15）。
channel_fingerprint() {
  local y="none"
  if [[ -f "$repo_root/.agent-governance.yml" ]]; then
    y=$(sha256_file "$repo_root/.agent-governance.yml" 2>/dev/null) || y=""
    [[ -n "$y" ]] || y="unhashed"
    y="${y:0:12}"
  fi
  printf '%s/%s/yml:%s' "${BASH_VERSION%%(*}" "$(uname -sm 2>/dev/null | tr -d '\n')" "$y"
}

# 换行**折叠为空格**（不是删除——独立评审 F10：删掉会把多行命令粘成
# `bash a.shbash b.sh`，与真实执行值不符）。
json_escape() { printf '%s' "$1" | tr '\t' ' ' | tr '\n' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

write_verify_channel() { # <state> <source> <command> <exit_code-json> <reason>
  local st="$1" src="$2" cmd="$3" ec="$4" reason="$5" out
  out="$repo_root/.agent-state/verify-channel.json"
  mkdir -p "$repo_root/.agent-state" 2>/dev/null || return 0
  printf '{"state":"%s","source":"%s","command":"%s","exit_code":%s,"reason":"%s","env_fingerprint":"%s","generated_at":"%s","head":"%s"}\n' \
    "$(json_escape "$st")" "$(json_escape "$src")" "$(json_escape "$cmd")" "$ec" \
    "$(json_escape "$reason")" "$(json_escape "$(channel_fingerprint)")" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(json_escape "$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo '')")" \
    > "$out" 2>/dev/null \
    || echo "agent-gate: note — 无法写 ${out}（fail-open，不阻断交付）" >&2
  return 0
}

# v3.76.0 (CHG-100, REQ-1118): 通道证据行 → 活跃变更 05。语义 = **单行受控覆盖**
# （最近一次判定），不是无界追加：每行都带 UTC 时间戳，`grep -qF` 永不命中，
# 无界追加会把 05 涨成噪声（独立评审 F5）。同时 **保留 05 的 mtime**——冒烟证据
# 时效窗（GATE-E111）判定的正是 05 的 mtime，通道证据不得把它刷新成"刚冒烟过"
# （独立评审 F4）。无活跃变更指针/无 05 时静默跳过（fail-open，不新建指针）。
append_verify_evidence() { # <line>（单行；调用端负责折叠换行）
  local line="$1" af id dir f ref tmp
  af=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  [[ -n "$af" && -s "$af" ]] || return 0
  id=$(tr -d '[:space:]' < "$af" 2>/dev/null || true)
  [[ -n "$id" ]] || return 0
  dir=$(change_dir "$id" 2>/dev/null || true)
  [[ -n "$dir" && -d "$dir" ]] || return 0
  f="$dir/05-test-results.md"
  [[ -s "$f" ]] || return 0
  ref="$f.time-ref"; tmp="$f.tmp.$$"
  cp -p "$f" "$ref" 2>/dev/null || ref=""
  grep -v -e '- 通道自检证据：' -e '- 通道未验证（' "$f" > "$tmp" 2>/dev/null || cp "$f" "$tmp" 2>/dev/null || return 0
  printf '%s\n' "$line" >> "$tmp" 2>/dev/null || { rm -f "$tmp" "$ref"; return 0; }
  [[ -n "$ref" ]] && touch -r "$ref" "$tmp" 2>/dev/null
  mv "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" "$ref"; return 0; }
  [[ -n "$ref" ]] && rm -f "$ref"
  return 0
}

validate_stop() {
  local id
  working_code_changed || return 0
  validate_active_change
  id=$(active_change)
  validate_delivery "$id"
  # v3.68.0 (CHG-043): G13/G14 stop lane — three-way reconciliation, replay,
  # per-UJ runtime evidence, review journey, waiver transitivity (E101–E108).
  validate_dimensional_stop "$(change_dir "$id")"
  # v3.28.0: repo-wide six-piece sweep + provenance for this change's bound
  # defect groups (stamp-provenance.sh --bug).
  validate_bug_groups
  validate_bug_ref_provenance
  # v3.71.0 (CHG-046, REQ-1088): stop-lane smoke gate over the staged + last
  # commit face (the commit lane is covered in validate_diff).
  check_smoke_gate "$( { changed_files staged 2>/dev/null; git show --name-only --format= HEAD 2>/dev/null; } | sort -u )"
  # CHG-012 / FU: verification command source chain — env (highest) →
  # .agent-governance.yml ci.verification_command → absent. Two-phase per design:
  # the file/config is the guard for "is there a command", bash is the assertion.
  # v3.76.0 (CHG-100, REQ-1115~1119): 通道从"静默可能不生效"改为**四态显式**——
  #   absent（键不存在）/ placeholder（安装占位符）/ tampered（yml 在在途改动中，
  #   CHG-015 anti-tamper）/ unparsable（值无法按声明方言解析，见 yml_scalar 头注释）
  #   前三态跳过并打印显式 reason；unparsable **硬 fail-closed**（GATE-E118）——
  #   "看起来配了实际没跑"不得静默（另一仓事故的规范侧根因，外部编号不入载荷）。
  #   判定结果落 .agent-state/verify-channel.json（session-gate status 读取）；
  #   真实执行/跳过的证据行落活跃变更 05（append_verify_evidence）。
  #   anti-tamper 的合法维护路径：yml 在途时用 AGENT_GUARD_VERIFY_COMMAND + 09
  #   「重要上下文」登记（状态 tampered+env）。
  # v3.28.0: AGENT_GUARD_SKIP_VERIFY=1 short-circuits the command — session-time
  # soft checks (session-gate idle) must not run a full regression (mvn test …)
  # on every turn; the real delivery line (Claude Stop hook / pre-commit / CI)
  # never sets it and keeps the full bar.
  local vcmd="${AGENT_GUARD_VERIFY_COMMAND:-}" vsrc="" vstate="" vreason="" vraw="" vfile=".agent-governance.yml" yml_pending=0 vexit=0
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
     && [[ -n "$(git status --porcelain -- "$vfile" 2>/dev/null)" ]]; then yml_pending=1; fi
  if [[ "${AGENT_GUARD_SKIP_VERIFY:-}" == "1" ]]; then
    vstate="skipped"; vreason="AGENT_GUARD_SKIP_VERIFY=1（会话期软执法；真实交付线不设）"
    # F2（既有存量，当批闭环）：跳过分支持有 env 命令时必须**清空 vcmd**——否则
    # 后面的 `[[ -n "$vcmd" ]]` 仍会执行它，会话期 idle（session-gate 每轮设
    # SKIP_VERIFY=1）就会跑全量回归并在失败时 rc 2，与"软执法不跑"直接矛盾。
    vcmd=""
    echo "agent-gate: verification command skipped (AGENT_GUARD_SKIP_VERIFY=1, session-time soft check) — full bar still enforced at staged/CI"
  elif [[ -n "$vcmd" ]]; then
    vsrc="env"
    if [[ "$yml_pending" == 1 ]]; then
      vstate="tampered+env"
      vreason="在途 yml + env 通道（合法路径，须在 09「重要上下文」登记）"
    else
      vstate="env"
    fi
  elif [[ -f "$vfile" && "$yml_pending" == 1 ]]; then
    # CHG-015 anti-tamper: if the yml itself is part of the pending change
    # (modified/untracked), its command must NOT auto-execute — a PR could
    # otherwise inject arbitrary commands into the reviewer's stop/ci hook.
    # Committed versions are trusted (standard repo-trust model).
    vstate="tampered"
    vreason="$vfile 在途（anti-tamper，CHG-015）：设 AGENT_GUARD_VERIFY_COMMAND 并在 09「重要上下文」登记后重跑"
    echo "agent-gate: verification command from $vfile skipped — the file is modified in the pending change (anti-tamper, CHG-015); set AGENT_GUARD_VERIFY_COMMAND to run verification"
  else
    vraw=$(yml_scalar "$vfile" verification_command)
    case "$vraw" in
      absent*)     vstate="absent";     vreason="$vfile 未声明 ci.verification_command（合法态：本仓库未配置验证通道）" ;;
      unparsable*)
        vstate="unparsable"
        case "${vraw#*$'\t'}" in
          misplaced) vreason="$vfile 的 ci.verification_command 位置非法（必须位于 ci: 段内、与其它 ci 子键同缩进；顶层、其它段或其它键块标量正文里的同名行不被接受）" ;;
          multiline) vreason="$vfile 的 ci.verification_command 是多行裸标量（不支持；请写双引号单行，或用块标量 | / >）" ;;
          *)         vreason="$vfile 的 ci.verification_command 无法按声明方言解析（空值 / 未闭合引号 / 非法块标量）" ;;
        esac ;;
      ok*)         vcmd="${vraw#*$'\t'}"; vsrc="$vfile"
                   case "$vcmd" in
                     *"<replace"*) vcmd=""; vsrc=""; vstate="placeholder"
                                   vreason="$vfile 仍为安装占位符（合法态：等待项目填测试命令）" ;;
                     *) vstate="yml" ;;
                   esac ;;
      *)           vstate="unparsable"; vreason="$vfile 的 ci.verification_command 读取异常" ;;
    esac
    if [[ "$vstate" == "unparsable" ]]; then
      write_verify_channel "$vstate" "" "" "null" "$vreason"
      die "GATE-E118: cannot finish: ${vreason}；修复示例：ci: / verification_command: \"bash tests/run-tests.sh\"（或设 AGENT_GUARD_VERIFY_COMMAND）"
    fi
  fi
  if [[ -n "$vcmd" ]]; then
    echo "agent-gate: verification command from $vsrc: $vcmd"
    bash -lc "$vcmd" || vexit=$?
  fi
  # F8：会话期软执法（skipped）**不落盘**——否则每轮 idle 都用 state=skipped 覆盖
  # 上一次真实判定，`session-gate status` 将长期显示 skipped（REQ-1117 要回答的
  # 正是"到底跑没跑"）。跳过本身仍是显式行为：上面已 echo reason。
  [[ "$vstate" == "skipped" ]] || write_verify_channel "$vstate" "$vsrc" "$vcmd" "$vexit" "$vreason"
  if [[ "$vstate" == "skipped" ]]; then
    : # 会话期软执法不写 05（每轮都会跑到这里，写 05 会刷屏）
  elif [[ -n "$vcmd" ]]; then
    local vcmd1="${vcmd//$'\n'/ }"
    append_verify_evidence "- 通道自检证据：${vcmd1}；退出码 ${vexit}；环境指纹 $(channel_fingerprint)；$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  else
    append_verify_evidence "- 通道未验证（${vstate}：${vreason}）"
  fi
  if [[ "$vexit" != "0" ]]; then
    die "GATE-E64: cannot finish: verification command failed (from $vsrc): $vcmd"
  fi
}

changed_files() {
  local mode="$1" base="${2:-}"
  case "$mode" in
    staged) git diff --cached --name-only --diff-filter=ACMR ;; 
    branch)
      if [[ -n "$base" ]]; then git diff --name-only --diff-filter=ACMR "$base"...HEAD
      else git diff --name-only --diff-filter=ACMR HEAD~1...HEAD; fi ;;
    *) die "GATE-E65: unknown diff mode '$mode'" ;;
  esac
}

complete_valid_change_exists() {
  # True when at least one change directory carries the full required artifact
  # set with a valid governance state. Local staged commits rely on this when
  # code is committed after the artifacts landed in an earlier commit of the
  # same change (the documented workflow: artifacts first, implementation later).
  # KNOWN LIMITATION (narrowed in v3.5.0): staged mode still cannot attribute
  # code to a specific change id — a complete set of ANY change satisfies it.
  # --stage commit-msg now pins per-commit attribution and branch-mode CI
  # (pre-push) enforces delivery evidence per touched change; residual
  # cross-change drift stays a B-layer (review) responsibility.
  local dir id doc complete
  [[ -d "$change_root" ]] || return 1
  for dir in "$change_root"/*/; do
    [[ -d "$dir" ]] || continue
    complete=true
    for doc in "${required_docs[@]}"; do
      # communication-first gate bypass (§2.17.2d): same key as required_docs_present
      [[ "$doc" == "00.5-communication.md" && "${AGENT_GUARD_ALLOW_UNCONFIRMED:-}" == "1" ]] && continue
      [[ -s "$dir/$doc" ]] || { complete=false; break; }
    done
    [[ "$complete" == true ]] || continue
    # A dedicated dir names one change; a batch names every change it anchors.
    # No-dot id rule (FU-023/GATE-E02) — dot ids here would dodge the E02 gate.
    for id in $(change_ids_in_dir "${dir%/}"); do
      [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] || continue
      if ( validate_governance_state "$id" ) >/dev/null 2>&1 \
         && ( AGENT_GUARD_DIM_PROBE=1 validate_artifact_content "$id" ) >/dev/null 2>&1; then
        return 0
      fi
    done
  done
  return 1
}

validate_diff() {
  local mode="$1" base="${2:-}" files code_changed docs_changed f id dir_id seen_ids
  files=$(changed_files "$mode" "$base")
  [[ -n "$files" ]] || exit 0
  code_changed=false
  docs_changed=false
  seen_ids=""
  while IFS= read -r f; do
    is_code_path "$f" && code_changed=true
    if [[ "$f" =~ ^${change_root_re}/([A-Za-z0-9._-]+)/[A-Za-z0-9._-]+$ ]]; then
      docs_changed=true
      dir_id="${BASH_REMATCH[1]}"
      # A batch artifact is SHARED by every bundled change, so a diff to it is
      # attributable to the whole roster. v3.19.0: read the roster from
      # 00-governance.json rather than off the `## <heading>` lines — the latter
      # picks up structural headings the standards require (§2.16.2
      # `## Observation`) and fails the batch over a heading it mandates.
      # `|| true` semantics preserved: an unreadable roster falls back to the
      # anchors, and an empty list must not abort the scan.
      local id_list
      if [[ "$dir_id" == BATCH-* ]]; then
        id_list=$(gov_ids "$(dirname "$f")/00-governance.json")
        [[ -n "$id_list" ]] || id_list=$(anchors_in_file "$f")
      else
        id_list="$dir_id"
      fi
      for id in $id_list; do
        case " $seen_ids " in
          *" $id "*) ;;
          *) seen_ids="$seen_ids $id" ;;
        esac
        # Staged/CI diffs are the only enforcement line for clients without
        # pre-write hooks, so the governance state must be validated here too.
        validate_governance_state "$id"
      done
    fi
  done <<< "$files"

  # v3.28.0: defect doc groups are repo-level evidence — sweep them on every
  # diff-anchored stage (staged commits / branch CI), not only at stop.
  validate_bug_groups

  # v3.71.0 (CHG-046, REQ-1088): infra smoke gate on the commit lane
  # (staged = pre-commit; branch CI keeps a presence-level check).
  check_smoke_gate "$files"

  # v3.5.0: branch-mode CI additionally requires delivery evidence (test
  # results + changelog with ReAct Observation) for every change touched by
  # the diff — the same bar --stage stop holds. Staged stays lenient: it is a
  # local fast signal over repo state; stop/ci close the evidence loop.
  if [[ "$mode" == branch ]]; then
    for id in $seen_ids; do
      validate_delivery "$id"
    done
  fi

  if [[ "$code_changed" == true && "$docs_changed" != true ]]; then
    # Staged is a local hook: repo state is authoritative, so code may follow an
    # earlier artifacts-only commit of the same change. CI keeps the stricter
    # rule: the branch diff itself must carry the artifact changes.
    if [[ "$mode" == staged ]] && complete_valid_change_exists; then
      return 0
    fi
    die "GATE-E66: source changes require change artifacts under $change_root/<change-id>/ (spec, plan, test plan, evidence)"
  fi
}

# Attribution gate (v3.5.0): a code-bearing commit must reference its change
# id so the gate and the pipeline metrics share one definition of ownership.
# Exemption ladder: merge commits (MERGE_HEAD present), reverts, and commits
# touching no code path pass without an id. An id-bearing code commit must
# point at a change that exists with a valid governance state.
validate_commit_msg() { # message-file
  local msgfile="$1" msg f id files code_found=false
  [[ -s "$msgfile" ]] || die "GATE-E67: commit message file is empty"
  msg=$(cat "$msgfile")
  # Ladder written in if-form: a bare `[[ x ]] && return` leaves the whole
  # statement returning 1 on the fall-through path, which a commit-msg hook
  # would read as rejection.
  if [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]]; then return 0; fi
  if [[ "$msg" =~ ^Revert ]]; then return 0; fi
  files=$(git diff --cached --name-only --diff-filter=ACMR)
  while IFS= read -r f; do
    if is_code_path "$f"; then code_found=true; fi
  done <<< "$files"
  if [[ "$code_found" != true ]]; then return 0; fi
  # `|| true` guards the pipefail case: grep exits 1 when the message carries
  # no id, and the assignment must not abort the gate before the die below.
  id=$(printf '%s\n' "$msg" | grep -Eo '[A-Z][A-Z0-9_]*-[0-9]+' | head -n 1 || true)
  if [[ -z "$id" ]]; then
    die "GATE-E68: code commit must reference its change id (e.g. 'feat: CHG-123 implement ...')"
  fi
  required_docs_present "$id"
  validate_governance_state "$id"
}

# --- metrics ---------------------------------------------------------------
# Pipeline metrics derived purely from git history (JSON Lines, one object per
# change). Zero third-party dependencies: timestamps come from git, values are
# either numbers or null. Semantics:
#   *_ts           epoch seconds of the commit that first added the artifact
#   first_code_commit_ts  earliest commit whose message references the change id
#   *_s            stage interval in seconds (null when either endpoint is missing)
first_commit_ts() {
  local out
  out=$(git log --format=%ct --diff-filter=A -- "$1" 2>/dev/null | tail -n 1)
  printf '%s' "$out"
}

first_commit_referencing() {
  local line esc
  # v3.5.0: word-boundary match so id "CUSTOM-1" cannot match a subject
  # mentioning "CUSTOM-10" (prefix collision); the id is regex-escaped first.
  esc=$(printf '%s' "$1" | sed 's/[][\.*^$]/\\&/g')
  line=$(git log --reverse --format='%ct|%s' | grep -E -m1 -- "(^|[^A-Za-z0-9])${esc}([^A-Za-z0-9]|$)" || true)
  [[ -n "$line" ]] && printf '%s' "${line%%|*}"
  # 空匹配时上面 [[ ]] 返回 1；显式 return 0，防止调用方 $( ) 赋值在 set -e 下中断
  # （真实场景：变更产物尚未提交时跑 metrics，T7 golden case 覆盖）。
  return 0
}

ts_or_null() {
  [[ -n "${1:-}" ]] && printf '%s' "$1" || printf 'null'
}

delta_or_null() {
  local newer="${1:-}" older="${2:-}"
  if [[ -n "$newer" && -n "$older" && "$newer" =~ ^[0-9]+$ && "$older" =~ ^[0-9]+$ && "$newer" -ge "$older" ]]; then
    printf '%s' "$(( newer - older ))"
  else
    printf 'null'
  fi
}

delivery_ready() {
  local d="$1"
  if [[ -s "$d/05-test-results.md" && -s "$d/07-review-report.md" && -s "$d/09-changelog.md" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

emit_metrics() {
  local dir id risk t_intent t_gov t_spec t_plan t_test t_chg t_code
  local sigs esess esess_over r_rounds r_limit r_over f_tot f_dis f_rate
  [[ -d "$change_root" ]] || exit 0
  for dir in "$change_root"/*/; do
    [[ -d "$dir" ]] || continue
    # One metrics row per CHANGE, not per directory: a batch directory holds
    # several changes and must not collapse into a single `BATCH-*` row with
    # one risk level standing in for all of them.
    for id in $(change_ids_in_dir "${dir%/}"); do
      [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
      if [[ -s "$dir/00-governance.json" ]]; then
        risk=$(json_field "$(gov_record "$dir/00-governance.json" "$id")" risk_level)
        # Emit a valid JSON string value; null stays unquoted.
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
      # v3.34.0 (CHG-034): observational count of DISTINCT expert-review
      # signature task-ids (§2.1.7 third segment) across 01/03 — makes the
      # L2 ≤3 session guardrail (§2.2) visible WITHOUT enforcing (metrics is
      # read-only by contract).
      sigs=$(cat "$dir/01-spec.md" "$dir/03-modification-plan.md" 2>/dev/null \
        | grep -Eo '[A-Za-z0-9][A-Za-z0-9 ._()-]* / [A-Za-z0-9._-]+ / [A-Za-z0-9_-]+' \
        | awk -F'/' '{gsub(/[[:space:]]/,"",$3); print $3}' | sort -u || true)
      esess=$(printf '%s' "$sigs" | grep -c . || true)
      esess_over=false
      if [[ "$risk" == '"L2"' || "$risk" == '"L3"' ]] && [[ "${esess:-0}" -gt 3 ]]; then esess_over=true; fi
      # v3.38.0 (CHG-040): artifact cost observation — md file count and byte
      # volume of the change's containing directory. In a BATCH the files are
      # SHARED by every member, so each member reports the same directory-wide
      # numbers: they measure the batch, not the individual change — do not
      # sum them across members. Governance JSON is deliberately not counted
      # (machine-read contract, mirrors the stamp exclusion).
      a_files=$(find "$dir" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c . || true)
      # `|| true` keeps an empty directory (no *.md → cat fails under pipefail)
      # from aborting metrics mid-run; wc still prints 0.
      a_bytes=$(cat "$dir"/*.md 2>/dev/null | wc -c | tr -d ' ' || true)
      [[ "$a_bytes" =~ ^[0-9]+$ ]] || a_bytes=0
      # v3.74.0 (CHG-098, REQ-1106): review-quality observation — rounds come
      # from the derived ledger (never self-reported), findings from the
      # report's disposition table. Read-only by contract; the numbers never
      # substitute for the DoD (§2.17.5). dismissed = any disposition that is
      # not 已修复, i.e. the disagreement/noise signal the round cap watches.
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
      # v3.75.0 (CHG-099, REQ-1111): finding provenance (N1) — 本次引入 vs 既有存量.
      # null when the disposition table is absent or predates the 来源 column
      # (upgrade compatibility); never a substitute for the DoD (§2.17.5).
      f_int=null
      f_pre=null
      if [[ -s "$dir/07-review-report.md" ]]; then
        f_counts=$(finding_source_counts "$dir/07-review-report.md")
        if [[ "${f_counts##* }" = 0 ]]; then
          f_int=${f_counts%% *}
          f_pre=${f_counts#* }; f_pre=${f_pre%% *}
        fi
      fi
      printf '{"change_id":"%s","risk_level":%s,"expert_sessions":%s,"expert_sessions_over_guardrail":%s,"artifact_files":%s,"artifact_bytes":%s,"intent_ts":%s,"governance_ts":%s,"spec_ts":%s,"plan_ts":%s,"first_code_commit_ts":%s,"test_evidence_ts":%s,"changelog_ts":%s,"intent_to_spec_s":%s,"spec_to_plan_s":%s,"plan_to_code_s":%s,"code_to_evidence_s":%s,"intent_to_changelog_s":%s,"delivery_ready":%s,"review_rounds":%s,"review_rounds_over_limit":%s,"findings_total":%s,"findings_dismissed":%s,"dismissal_rate":%s,"findings_introduced":%s,"findings_pre_existing":%s}\n' \
        "$id" "$risk" "${esess:-0}" "$esess_over" "${a_files:-0}" "${a_bytes:-0}" \
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
  # v3.43.0 (REQ-960): gate 摩擦聚合——append-only TSV（die 事件账）按错误码聚合计数。
  if [[ -f ".agent-state/gate-friction.tsv" ]]; then
    awk -F'\t' '{ c[$1]++ } END { for (k in c) printf "{\"friction_code\":\"%s\",\"count\":%d}\n", k, c[k] }' \
      .agent-state/gate-friction.tsv 2>/dev/null || true
  fi
}

command="${1:-help}"
# v3.68.0 (CHG-043, review finding 中2): external env must NOT be able to
# disarm the dimensional gates — AGENT_GUARD_DIM_PROBE is an INTERNAL probe
# switch (set only inside complete_valid_change_exists's subshell). Unset it
# at the dispatch entry so an injected env var cannot bypass E99/E100/E105/
# E106/E109 at begin/staged/stop/ci; the subshell-local assignment still works.
unset AGENT_GUARD_DIM_PROBE 2>/dev/null || true
case "$command" in
  begin)
    id=""
    scaffold=0; srisk=""; srisk_pending=0; e69msg=""
    if [[ -n "${2:-}" ]]; then
      for arg in "${@:2}"; do
        case "$arg" in
          --scaffold) scaffold=1 ;;
          --risk) [[ "$srisk_pending" = 0 ]] || { e69msg="--risk needs a value (L0|L1|L2|L3)"; break; }; srisk_pending=1 ;;
          L0|L1|L2|L3) if [[ "$srisk_pending" = 1 ]]; then srisk="$arg"; srisk_pending=0; else [[ -z "$id" ]] || { e69msg="multiple change ids given"; break; }; id="$arg"; fi ;;
          *) [[ -z "$id" ]] || { e69msg="multiple change ids given"; break; }; id="$arg" ;;
        esac
      done
    fi
    # 评审 F2（CHG-107）：悬空/非法/越位 --risk 与多 id fail-closed（不静默回落默认，
    # 用户想 L2 却落日批 = 静默错落位）。E69 die 站点全 gate 唯一（T41 唯一性钉）。
    if [[ -z "$e69msg" && "$srisk_pending" = 1 ]]; then e69msg="--risk needs a value (L0|L1|L2|L3)"; fi
    if [[ -z "$e69msg" && -n "${srisk:-}" && "$scaffold" != 1 ]]; then e69msg="--risk only takes effect with --scaffold"; fi
    if [[ -z "$e69msg" && -z "$id" ]]; then
      if [[ "$scaffold" = 1 ]]; then e69msg="usage: scripts/agent-gate begin <change-id> --scaffold [--risk L0|L1|L2|L3]"
      else e69msg="usage: scripts/agent-gate begin <change-id> [--risk L0|L1|L2|L3] [--scaffold]"; fi
    fi
    [[ -z "$e69msg" ]] || die "GATE-E69: $e69msg"
    if [[ "$scaffold" = 1 ]]; then
      : "${srisk:=L1}"
      scaffold_change "$id" "$srisk"; exit 0
    fi
    # FU-015 (BUG-003): a change dir carrying a changelog is a CLOSED change —
    # re-opening it would let a new change write into a read-only artifact set
    # (standards §2.15 rule 4, one change one document set).
    # S1/S2 (independent review): -s misses zero-size and symlinked markers;
    # '.'/'..' would escape the change dir. Both are closed here.
    if [[ "$id" == "." || "$id" == ".." ]]; then
      die "GATE-E70: invalid change id '$id'"
    fi
    # In a BATCH the changelog file is SHARED by every bundled change, so "the
    # file exists" cannot mean "this change is closed" — a sibling's changelog
    # would close every change that joins the batch later (false positive).
    # Closure for a batch member is therefore its OWN `## <id>` section in the
    # changelog, which is the same FU-015 semantics read one level finer.
    d=$(change_dir "$id")
    if is_batch_dir "$d"; then
      if [[ -e "$d/09-changelog.md" || -L "$d/09-changelog.md" ]] \
         && grep -qE "$(anchor_re "$id")" "$d/09-changelog.md" 2>/dev/null; then
        die "GATE-E71: change $id is already closed ($d/09-changelog.md carries a '## $id' section) — open a new change id (standards §2.15 rule 4, FU-015)"
      fi
    elif [[ -e "$d/09-changelog.md" || -L "$d/09-changelog.md" ]]; then
      die "GATE-E72: change $id is already closed ($d/09-changelog.md exists) — open a new change id (standards §2.15 rule 4, FU-015)"
    fi
    required_docs_present "$id"
    validate_governance_state "$id"
    # v3.27.0 (CHG-027): the same-day batch default is ENFORCED, not advisory —
    # once a BATCH-<today> exists, a new L0/L1 change must join it (standards
    # §1.1, v3.24.0 defaulting). Independent dirs stay valid for L2/L3 and for
    # single-change days (no batch yet). Escape hatch is explicit on purpose:
    # AGENT_GUARD_ALLOW_INDEPENDENT=1 with the justification recorded in the
    # changelog — silent bypasses are the failure mode this closes (the
    # same family as "the standard shipped a speed bump nobody stepped on").
    b_risk=$(json_field "$(gov_record "$d/00-governance.json" "$id")" risk_level)
    if [[ "$b_risk" == L0 || "$b_risk" == L1 ]] && ! is_batch_dir "$d" \
       && [[ -d "$change_root/BATCH-$(date -u +%Y%m%d)" ]] \
       && [[ "${AGENT_GUARD_ALLOW_INDEPENDENT:-}" != "1" ]]; then
      die "GATE-E73: same-day batch exists ($change_root/BATCH-$(date -u +%Y%m%d)) — L0/L1 changes must join it (standards §1.1); set AGENT_GUARD_ALLOW_INDEPENDENT=1 only with a recorded justification"
    fi
    # v3.35.0 (standards §1.3): project masters must be initialized before any
    # change starts — first change initializes them (docs edits precede begin).
    [[ "${AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS:-}" == "1" ]] || validate_project_masters
    # v3.38.0 (CHG-039): session water level (standards §2.9.6). The OpenCode
    # adapter counts user turns into .agent-state/session-water.json; the gate
    # still reads only DISK (never the client runtime), so clients without the
    # hook have no water file and degrade fail-open (§2.17.3.2: semantics
    # unchanged, defense line moves back). Threshold is env-tunable until the
    # metrics cost data (v3.38.0) justifies hardening it.
    # v3.63.0 (REQ-1035, D): threshold comparison unified to `-ge` to match
    # session-gate.sh check (turn == limit blocks on BOTH sides; the old
    # begin-side `-gt` let turn==limit open new changes — 口径不一致修复).
    water_file="$repo_root/.agent-state/session-water.json"
    if [[ -s "$water_file" && "${AGENT_GUARD_ALLOW_OVER_WATER:-}" != "1" ]]; then
      w_turns=$(sed -n 's/.*"turns":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$water_file" | head -1)
      w_limit="${AGENT_GUARD_SESSION_TURN_LIMIT:-50}"
      if [[ "$w_turns" =~ ^[0-9]+$ ]] && [[ "$w_turns" -ge "$w_limit" ]]; then
        die "GATE-E74: session water level ${w_turns} turns reaches the ${w_limit}-turn limit (standards §2.9.6) — handoff to a fresh session (state rebuilds from disk, §2.16.1) and re-begin there, or set AGENT_GUARD_ALLOW_OVER_WATER=1 with the justification recorded in 09「重要上下文」"
      fi
    fi
    # v3.63.0 (REQ-1033, DES-1822): GATE-E89 — post-delivery shift gate (hook-
    # independent; begin is the discipline session's mandatory waypoint). A
    # delivery recorded DURING this session's lifetime (started_at < delivered_at)
    # requires handoff evidence (a handoff*.md newer than the delivery) before
    # opening the next change in the SAME session; sessions started after the
    # delivery pass (fresh-session semantics). Missing/stale markers degrade
    # fail-open. Escape: AGENT_GUARD_ALLOW_NO_SHIFT=1 with justification in 09
    # (GATE-E75 同型豁免先例).
    last_delivery="$repo_root/.agent-state/last-delivery.json"
    if [[ -s "$last_delivery" && "${AGENT_GUARD_ALLOW_NO_SHIFT:-}" != "1" ]]; then
      l_delivered=$(sed -n 's/.*"delivered_at":"\([^"]*\)".*/\1/p' "$last_delivery" | head -1)
      # R07-1 (07-review, BLOCKER): `x=$(sed missing-file 2>/dev/null | head -1)`
      # under `set -euo pipefail` aborts begin SILENTLY (rc 1, no die code) —
      # exactly the hook-only/mid-upgrade repos REQ-1033 targets. Guard the
      # read; a missing marker degrades fail-open per §2.17.3.2.
      l_started=""
      if [[ -s "$repo_root/.agent-state/session-started.json" ]]; then
        l_started=$(sed -n 's/.*"started_at":"\([^"]*\)".*/\1/p' "$repo_root/.agent-state/session-started.json" | head -1)
      fi
      if [[ -n "$l_delivered" && -n "$l_started" ]]; then
        ep_del=$(gate_epoch "$l_delivered"); ep_start=$(gate_epoch "$l_started")
        # R07 closeout: ep_start==0 means the started marker exists but is
        # unparseable (corrupt) — treat like missing (fail-open), not like
        # "session started at epoch 0" (which would arm the gate on garbage).
        if [[ "$ep_del" =~ ^[0-9]+$ && "$ep_start" =~ ^[0-9]+$ && "$ep_start" -gt 0 && "$ep_del" -gt "$ep_start" ]]; then
          l_change=$(sed -n 's/.*"change":"\([^"]*\)".*/\1/p' "$last_delivery" | head -1)
          handoff_ok=0
          # R07-2/R07-10 (07-review, MAJOR/NIT): the glob concatenates onto the
          # dir element — the own-change path needs its trailing slash (it is
          # the PRIMARY remediation path the die message names), and an empty
          # change id must not degrade to scanning docs/changes/ itself.
          e89_dirs=()
          [[ -n "$l_change" ]] && e89_dirs+=("$repo_root/docs/changes/$l_change/")
          e89_dirs+=("$repo_root"/docs/changes/BATCH-*/)
          for hd in "${e89_dirs[@]}"; do
            [[ -d "$hd" ]] || continue
            for hf in "$hd"handoff*.md; do
              [[ -f "$hf" ]] || continue
              hm=$(gate_mtime "$hf")
              if [[ "$hm" =~ ^[0-9]+$ && "$hm" -ge "$ep_del" ]]; then handoff_ok=1; break 2; fi
            done
          done
          if [[ "$handoff_ok" != 1 ]]; then
            die "GATE-E89: last delivery (${l_change:-<change>} @ ${l_delivered}) happened in THIS session without a handoff doc — write the handoff record under docs/changes/${l_change:-<change>}/ (or the active BATCH dir), run /handoff and continue in a fresh session, or set AGENT_GUARD_ALLOW_NO_SHIFT=1 with the justification recorded in 09「重要上下文」 (standards §2.9.6)"
          fi
        fi
      fi
    fi
    # v3.40.0 (CHG-046, FU-106⑤): unresolved session RED blocks new changes.
    # .agent-state/session-gate-last.md is the last start/idle audit report; a
    # `GATE RED` report FRESHER than the newest delivered 09-changelog means the
    # red arose after the last delivery and was never cleared (带病开工). A
    # missing report, or a changelog newer than the report, degrades fail-open —
    # same ladder as the water gate above. No changelog baseline at all → the
    # comparison is meaningless → fail-open. Escape: AGENT_GUARD_ALLOW_OVER_RED=1
    # with the justification recorded in 09「重要上下文」.
    red_report="$repo_root/.agent-state/session-gate-last.md"
    if [[ -s "$red_report" && "${AGENT_GUARD_ALLOW_OVER_RED:-}" != "1" ]] \
       && grep -q "GATE RED" "$red_report" \
       && [[ -n "$(find "$change_root" -mindepth 2 -type f -name 09-changelog.md 2>/dev/null)" ]] \
       && ! find "$change_root" -mindepth 2 -type f -name 09-changelog.md -newer "$red_report" 2>/dev/null | grep -q .; then
      die "GATE-E75: session audit RED unresolved ($red_report is fresher than the last delivered 09-changelog) — clear the red list (§2.14 backfill) before opening a new change, or set AGENT_GUARD_ALLOW_OVER_RED=1 with the justification recorded in 09「重要上下文」"
    fi
    mkdir -p "$(dirname "$active_file")"
    printf '%s\n' "$id" > "$active_file"
    echo "agent-gate: active change is $id"
    ;;
  end)
    rm -f "$active_file"
    echo "agent-gate: active change cleared"
    ;;
  check-confirm)
    # v3.55.0 (CHG-068, REQ-1002): read-only confirmation-gate probe for
    # tooling (new-change wave-2). Exit 0 = confirmed; 1 = not confirmed
    # (reason on stderr); 2 = usage error. Deliberately NOT die-shaped —
    # keeps the GATE-Exx die domain unique (T41).
    id="${2:-}"
    if [[ -z "$id" ]] || [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
      printf 'agent-gate: check-confirm requires a valid change id (FU-023 shape). Probe semantics: "is the confirmation in place" — NOT "would the gate pass" (which also honors AGENT_GUARD_ALLOW_UNCONFIRMED). Reported reasons cover six classes: missing 00.5-communication.md; batch member lacking its own ## <id> anchor in 00.5; L0-exclusive single-line declaration at non-L0 risk; missing 用户整体确认记录 section; missing confirmation marker under that section; missing five-element substance anchor (影响范围/风险/候选方案与取舍/测试思路)\n' >&2
      exit 2
    fi
    d=$(change_dir "$id")
    confirmation_gate_reason "$id" "$d"
    if [[ -z "$CONFIRM_REASON" ]]; then exit 0; fi
    printf 'agent-gate: check-confirm: %s\n' "$CONFIRM_REASON" >&2
    exit 1
    ;;
  verify-channel)
    # v3.76.0 (CHG-100, REQ-1116/1117): read-only 验证通道探针（check-confirm
    # 同族）。**不执行**命令、**不写**状态文件，只报四态判定：exit 0 = 有可用
    # 命令或合法跳过（absent/placeholder/tampered/环境变量）；exit 2 = unparsable
    # （GATE-E118 的干跑形态，供 T61 方言矩阵与人工排查使用）。
    _vc_file=".agent-governance.yml"
    _vc_flag=""
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
       && [[ -n "$(git status --porcelain -- "$_vc_file" 2>/dev/null)" ]]; then _vc_flag="pending"; fi
    if [[ -n "${AGENT_GUARD_VERIFY_COMMAND:-}" ]]; then
      _vc_state="env"
      [[ "$_vc_flag" == "pending" ]] && _vc_state="tampered+env"
      echo "agent-gate: verify-channel state=$_vc_state source=env command=${AGENT_GUARD_VERIFY_COMMAND}"
    elif [[ -f "$_vc_file" && "$_vc_flag" == "pending" ]]; then
      echo "agent-gate: verify-channel state=tampered source=$_vc_file reason=yml-modified-in-pending-change"
    else
      _vc_raw=$(yml_scalar "$_vc_file" verification_command)
      case "$_vc_raw" in
        absent*)     echo "agent-gate: verify-channel state=absent reason=ci.verification_command-not-declared" ;;
        unparsable*) _vc_detail="${_vc_raw#*$'\t'}"
                     case "$_vc_detail" in
                       misplaced) _vc_detail="misplaced-key(must-live-under-ci-at-sibling-indent)" ;;
                       multiline) _vc_detail="multiline-plain-scalar(use-one-quoted-line-or-block-scalar)" ;;
                       *)         _vc_detail="dialect-parse-failed(empty-value/unterminated-quote/invalid-block-indicator)" ;;
                     esac
                     echo "agent-gate: verify-channel state=unparsable reason=$_vc_detail" >&2; exit 2 ;;
        ok*)         _vc_cmd="${_vc_raw#*$'\t'}"
                     case "$_vc_cmd" in
                       *"<replace"*) echo "agent-gate: verify-channel state=placeholder source=$_vc_file" ;;
                       *) echo "agent-gate: verify-channel state=yml source=$_vc_file command=$_vc_cmd" ;;
                     esac ;;
        *)           echo "agent-gate: verify-channel state=unparsable reason=read-failed" >&2; exit 2 ;;
      esac
    fi
    ;;
  check-smoke)
    # v3.71.0 (CHG-046, REQ-1088): read-only smoke-gate probe (check-confirm
    # sibling). Exit 0 = pass; 1 = violation (GATE-E111 reason on stderr);
    # 2 = usage. Deliberately non-die-shaped at this level: the probe re-runs
    # check_smoke_gate in a subshell and maps its die to exit 1.
    sm_files="$( { changed_files staged 2>/dev/null; git show --name-only --format= HEAD 2>/dev/null; } | sort -u )"
    if ( check_smoke_gate "$sm_files" ) 2>&1; then
      exit 0
    fi
    exit 1
    ;;
  preflight)
    # v3.72.0 (CHG-094, REQ-1095): read-only begin-artifact probe (check-smoke
    # sibling). Exit 0 = all artifact gates clean; 1 = violations, each collected
    # GATE-Exx reason prefixed "agent-gate: preflight: " on stderr; 2 = usage.
    # Collect-all, not fail-fast: the begin product-layer validators run in a
    # subshell whose `die` is shadowed by a print-and-continue recorder — the
    # real die call sites stay the single reason source (zero new E-codes, zero
    # new die literals, T41/T30 untouched), and no real die ever runs, so the
    # friction ledger is never touched. Product layer only: the session-state
    # gates (E74 water / E89 shift / E75 red) and the active-change pointer
    # write are NOT part of this probe (zero side effects, zero bypass env).
    id="${2:-}"
    if [[ -z "$id" ]] || [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
      printf 'agent-gate: preflight requires a valid change id (FU-023 shape: start with [A-Za-z0-9], then alnum/_/-; no dots) — usage: scripts/agent-gate preflight <change-id> (exit 0 = all artifact gates clean, 1 = violations listed, 2 = usage)\n' >&2
      exit 2
    fi
    pf_d=$(change_dir "$id")
    p_n=0
    p_seen=""
    p_run() {
      unset AGENT_GUARD_ALLOW_UNCONFIRMED AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS  # probe determinism (v3.72.0 erratum, CHG-095, REQ-1099)
      local out p_line
      out=$( ( die() { printf 'agent-gate: preflight: %s\n' "$*"; }; "$@" ) 2>&1 ) || true
      while IFS= read -r p_line; do
        [[ "$p_line" == *GATE-E[0-9]* ]] || continue
        if [[ -z "$p_seen" || "$p_seen" != *"$p_line"* ]]; then
          p_seen="$p_seen"$'\n'"$p_line"
          printf '%s\n' "$p_line" >&2
          p_n=$((p_n+1))
        fi
      done <<< "$out"
      return 0
    }
    p_run required_docs_present "$id"
    p_run validate_artifact_content "$id"
    p_run validate_governance_state "$id"
    p_run validate_dimensional_begin "$pf_d"
    p_run validate_project_masters
    if [[ "$p_n" -eq 0 ]]; then
      echo "agent-gate: preflight: $id: all artifact gates clean"
      exit 0
    fi
    exit 1
    ;;
  metrics)
    emit_metrics
    ;;
  --stage)
    stage="${2:-}"; shift 2
    case "$stage" in
      pre-write)
        file=""
        if [[ "${1:-}" == "--file" ]]; then file="${2:-}"
        else file=$(extract_file_from_hook_input); fi
        # A hook that cannot identify a path must fail closed: otherwise a
        # client schema change silently turns this policy into a no-op.
        [[ -n "$file" ]] || die "GATE-E76: cannot determine the target file from hook input"
        if is_code_path "$file"; then
          validate_active_change
        fi
        ;;
      staged) validate_diff staged; validate_ux_conditions; validate_dimensional_active; warn_ux_soft; record_delivery staged ;;
      stop) validate_stop; validate_ux_conditions; validate_dimensional_active; warn_ux_soft; record_delivery stop ;;
      ci)
        base=""
        if [[ "${1:-}" == "--base" ]]; then base="${2:-}"; fi
        validate_diff branch "$base"
        validate_ux_conditions
        validate_dimensional_active
        ;;
      commit-msg)
        msgfile="${1:-}"
        if [[ -z "$msgfile" ]]; then
          die "GATE-E77: usage: scripts/agent-gate --stage commit-msg <message-file>"
        fi
        validate_commit_msg "$msgfile"
        ;;
      *) die "GATE-E78: unknown stage '$stage'" ;;
    esac
    ;;
  help|--help|-h)
    cat <<'EOF'
Usage:
  scripts/agent-gate begin <change-id>
  scripts/agent-gate end
  scripts/agent-gate metrics
  scripts/agent-gate --stage pre-write [--file path]
  scripts/agent-gate --stage staged
  scripts/agent-gate --stage stop
  scripts/agent-gate --stage ci [--base ref]
  scripts/agent-gate --stage commit-msg <message-file>
  scripts/agent-gate check-confirm <change-id>   # exit 0/1/2, read-only (v3.55.0)
  scripts/agent-gate verify-channel              # exit 0/2, read-only 通道探针 (v3.76.0)
  scripts/agent-gate check-smoke                 # exit 0/1/2, read-only (v3.71.0)
  scripts/agent-gate preflight <change-id>       # exit 0/1/2, read-only begin-artifact probe, collects all anchor violations in one run (v3.72.0)

begin requires eight non-empty artifacts under the change root:
00-intent.md, 00-governance.json, 00.5-communication.md, 01-spec.md,
02-code-impact-analysis.md, 03-modification-plan.md, 03.5-tasks.md,
04-test-scripts.md. It also enforces
the project masters (v3.35.0, standards §1.3): all thirteen docs/project/ files
must exist (escape hatch AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 with a
recorded justification). It also enforces
A-layer content checks (standards §2.5): 00-intent.md must contain the
expected-outcome and open-questions sections; 00.5-communication.md must
carry a non-empty user-overall-confirmation record (v3.52.0 communication-
first gate, §2.17.2d; L0 single-line declaration allowed); 01-spec.md must use REQ-
numbering; 02 must cover business impact, risk and rollback; 03-modification-
plan.md must use DES- numbering plus option comparison; 03.5-tasks.md must
carry dependencies/milestones plus a review-input (评审输入) field, or an
explicit no-breakdown exemption; 04-test-
scripts.md must use TC- numbering, a coverage-dimension column, and SC-
scenario numbering. Hollow skeletons fail.

commit-msg attribution (v3.5.0): a code-bearing commit message must
reference its change id (e.g. 'feat: CHG-123 implement ...'); the referenced
change must exist with a valid governance state. Merge commits, reverts, and
commits that touch no code path are exempt.

stop and branch-mode CI enforce delivery evidence: 04.5-coding-record.md,
05-test-results.md, and 09-changelog.md carrying ReAct Observation records,
plus the project-master backfill checklist (v3.35.0): a 「项目总册回填清单」
section with one P00..P12 row each, marked [x] or 未命中 with a reason.
Gate 4 RTVM (v3.7.0): REQ ids referenced by the changelog must be backfilled
as rows in docs/<feature>/01.5-rtvm-matrix.md; changelogs without REQ
references (pure fixes / docs changes) are exempt.

defect doc groups (v3.28.0; day-batched since v3.35.0, FLAT since v3.36.0):
every <bugs_root>/BUG-*/ and <bugs_root>/BATCH-*/BUG-*/ group holding a
01-diagnosis.md must contain the complete six-piece set (staged / stop / CI).
v3.36.0 flat batches (<bugs_root>/BATCH-YYYYMMDD/ holding the six pieces
directly) are validated by ANCHOR: every `## <BUG-id>` anchored in the batch
diagnosis must carry its own section in all six pieces.
Once a same-day bugs batch exists, a standalone group created today is
rejected (AGENT_GUARD_ALLOW_INDEPENDENT=1 escapes with a recorded reason).
Groups declared via 00-governance.json 'bug_ref' (flat string or string array —
a declared but unparseable value fails closed) additionally need the
provenance header on all six pieces at stop: stamp with
'scripts/stamp-provenance.sh --bug <BUG-id>'. Legacy incomplete groups can be
allowlisted with a recorded reason in <bugs_root>/.gate-allowlist (one id per
line, trailing comment = reason); allowlisted groups WARN instead of dying.

metrics prints one JSON object per change (JSON Lines) with stage timestamps
and intervals derived from git history; pipe it to a CI artifact for trending.
v3.38.0 adds artifact_files / artifact_bytes (md files in the change's
directory; in a BATCH they measure the shared directory — do not sum across
members). v3.74.0 adds review_rounds / review_rounds_over_limit (derived from
.agent-state/review-rounds.tsv, never self-reported) and findings_total /
findings_dismissed / dismissal_rate (read from the 07 disposition table;
dismissed = any disposition that is not 已修复). v3.75.0 adds
findings_introduced / findings_pre_existing (read from the 07 disposition
table's trailing 「来源」 column: 本次引入 / 既有存量; a missing column
reports null, never 0 — legacy five-column tables stay lawful).

Session water level (v3.38.0, generalized v3.39.0, standards §2.9.6): begin reads
.agent-state/session-water.json, maintained by `session-gate.sh count turn` —
the harness-agnostic telemetry layer that Claude/OpenCode adapters forward
events to. Over AGENT_GUARD_SESSION_TURN_LIMIT (default 50) begin refuses
the new change; AGENT_GUARD_ALLOW_OVER_WATER=1 escapes with a justification
recorded in 09「重要上下文」. No water file (no hook client) = check skipped.

Configuration (v3.15.0): directory ROOTS come from the `paths:` block of
.agent-governance.yml (docs / scripts / tests / githooks), each overridable by
AGENT_GUARD_<KEY>_DIR; change_root / bugs_root keep AGENT_GUARD_CHANGE_ROOT /
AGENT_GUARD_BUGS_ROOT (defaults <docs>/changes and <docs>/bugs). Every built-in
default is the historical hardcoded value. Not configurable, on purpose:
`.github/` and the contract names — rationale lives in DS 不可配置项 (the same
single source cited in the path-roots header comment above).
EOF
    ;;
  *) die "GATE-E79: unknown command '$command'" ;;
esac
