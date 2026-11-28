#!/usr/bin/env bash
# Golden-case test suite for resources/templates/agent-gate.sh
#
# 对治理配置自身做回归测试（规范 §2.17.4）：在一个临时 Git 仓库里构造
# 合规/违规的暂存区与工作区状态，断言 agent-gate 的退出码与输出。
# 零依赖：bash 3.2+（macOS/Linux 均可）、git。
#
# 双布局自适应：Skill 仓库内直接跑（全量用例）；bootstrap --guard 复制到目标
# 仓库后跑——源路径自动回退到 scripts/agent-gate / tests/audit-docs-consistency.sh，
# Skill 仓库专属用例（T11 安装器、T14b 安装器路径用例、T15 版本自查/自进化、
# 依赖未装层的 T10/T12）自动 SKIP，已装层全部回归。
#
# Usage: tests/run-tests.sh [-T sec[,sec]] [-j N] [-l|--list]
#   AGENT_GUARD_REPEAT_LIMIT=N  warn on stderr when the same HEAD + section set
#   already ran N times within 30 min (default 3; 0 disables the guard entirely)
set -uo pipefail
case "${AGENT_GUARD_FORCE_OS:-$(uname -s 2>/dev/null || echo unknown)}" in
  MINGW*|MSYS*|CYGWIN*) export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# v3.66.0 (CHG-088, REQ-1049): cache the suite HEAD up front — by the time the
# closing receipt block runs, the dispatcher may have left cwd inside a temp repo
# (CHG-087 lesson), so the hash is taken once from a fixed anchor. Empty when
# $ROOT is not a git repo (tarball installs) → the receipt is skipped entirely.
SUITE_HEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
SUITE_KEY=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || true)
# v3.79.0 (CHG-103, REQ-1144): tree-fingerprint source. ONE recipe shared by the
# emitter (closing receipt block below) and scripts/dev/update-assertion-count.sh
# (consumer); the lib degrades to an empty string on ANY failure (non-git repo,
# git error) — an empty fingerprint only makes receipts untrusted (consumer
# falls back to the embedded run), never wrong. Absent lib file = same empty
# behavior (fail-closed in the "slow but correct" direction).
if [[ -f "$ROOT/scripts/lib-suite-tree-fingerprint.sh" ]]; then
  source "$ROOT/scripts/lib-suite-tree-fingerprint.sh"
fi
# 源位置回退：Skill 仓库内为 resources/templates/（原样），bootstrap --core/--guard 落地的
# 目标仓库为 tests/audit-docs-consistency.sh 与 scripts/agent-gate——同一份 run-tests.sh
# 必须在两种布局都可用。
GATE_SRC="$ROOT/resources/templates/agent-gate.sh"
[[ -f "$GATE_SRC" ]] || GATE_SRC="$ROOT/scripts/agent-gate"
BOOT_SRC="$ROOT/scripts/bootstrap.sh"
AUDIT_SRC="$ROOT/resources/templates/audit-docs-consistency.sh"
[[ -f "$AUDIT_SRC" ]] || AUDIT_SRC="$ROOT/tests/audit-docs-consistency.sh"
# hoisted (order-independence for -j; CHG-117 T78/T81 exercise the shipped
# session-gate; skill-repo layout prefers the template, target repo the local copy)
SESSION_GATE_SRC="$ROOT/resources/templates/session-gate.sh"
[[ -f "$SESSION_GATE_SRC" ]] || SESSION_GATE_SRC="$ROOT/scripts/session-gate.sh"
STD_SRC="$ROOT/resources/DEVELOPMENT_STANDARDS.md"
[[ -f "$STD_SRC" ]] || STD_SRC="$ROOT/docs/DEVELOPMENT_STANDARDS.md"
AG_SRC="$ROOT/resources/AGENTS.md"
[[ -f "$AG_SRC" ]] || AG_SRC="$ROOT/AGENTS.md"
# v3.86.0 (CHG-113): version pins resolve from the DS footer (the declared sole
# authority) instead of a literal that every release had to hand-edit in tests.
CURRENT_VERSION=$(sed -nE 's/.*规范版本：v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$STD_SRC" 2>/dev/null | head -1)
# v3.86.0 (CHG-113): receipt/red paths are overridable so self-tests and parallel
# sessions never mutate the real .agent-state ledger (P1-3).
SUITE_RECEIPT_PATH="${AGENT_GUARD_SUITE_RECEIPT_PATH:-$ROOT/.agent-state/last-suite-receipt.json}"
SUITE_RED_PATH="${AGENT_GUARD_SUITE_RED_PATH:-$ROOT/.agent-state/last-suite-red.txt}"
# hoisted to top level (order-independence for -j / -T 单节；was section_T17 局部变量、T18 跨节使用 — v3.72.0 erratum, CHG-095, REQ-1097)
STAMP_SRC="$ROOT/resources/templates/stamp-provenance.sh"
[[ -f "$STAMP_SRC" ]] || STAMP_SRC="$ROOT/scripts/stamp-provenance.sh"
# v3.92.4: payload anchors resolve in BOTH layouts. The skill repo keeps them
# under resources/; an installed target repo keeps the same files under the
# configured docs root, <githooks>/ and the repo root. T55 greps these bytes.
PAYLOAD_DOCS="$ROOT/resources"
[[ -d "$PAYLOAD_DOCS" ]] || { PAYLOAD_DOCS="$ROOT/docs/"; PAYLOAD_DOCS="${PAYLOAD_DOCS%/}"; }
PAYLOAD_HOOKS="$ROOT/resources/templates"
[[ -d "$PAYLOAD_HOOKS" ]] || { PAYLOAD_HOOKS="$ROOT/.githooks/"; PAYLOAD_HOOKS="${PAYLOAD_HOOKS%/}"; }
PAYLOAD_YML="$ROOT/resources/templates/agent-governance.yml"
[[ -f "$PAYLOAD_YML" ]] || PAYLOAD_YML="$ROOT/.agent-governance.yml"
PAYLOAD_AGENTS="$ROOT/resources/AGENTS.md"
[[ -f "$PAYLOAD_AGENTS" ]] || PAYLOAD_AGENTS="$ROOT/AGENTS.md"
# v3.91.9 (CHG-127): a fresh checkout (CI / any non-installed clone) has no
# .agent-state/ — receipt probes and telemetry writes must not die on rd/wr.
mkdir -p "$ROOT/.agent-state" 2>/dev/null || true
# hoisted (order-independence for -j; was a T12 section-local consumed by T13 — v3.72.0 erratum, CHG-095, REQ-1097)
ci_src="$ROOT/resources/templates/check-standards-compliance.sh"
[[ -f "$ci_src" ]] || ci_src="$ROOT/scripts/check-standards-compliance.sh"

pass=0
fail=0
failed_names=()
fail_lines=()  # v3.72.0 erratum (CHG-095, DES-1869): verbatim FAIL lines for the red archive

# ---- v3.90.1 (CHG-123, P0-3/P0-14): cost ledger + per-section timing ------
# One append-only TSV for every measurable action: section / TC / audit / verify.
# Columns: ts kind id suite_key cost_s setup_s cache exit   (8 columns, header once).
# Write failure is a WARN and never changes a verdict.
LEDGER_FILE="${AGENT_GUARD_COST_LEDGER:-$ROOT/.agent-state/cost-ledger.tsv}"
NEW_REPO_SETUP_S=0

# v3.97.1 (CHG-135, REQ-1348): one ledger, several concurrent writers (an
# evidence round launches five snapshot shards plus the live one). Migration and
# retention both rewrite the file (read -> awk -> mv), so an append that lands
# inside that window is lost — measured with six writers: 30 appends kept 12-24
# rows. A mkdir lock (owner = pid + lstart, owner-less reclaim by dir age)
# serializes migration, append and retention. A writer that cannot take the lock
# within ~2.5 s still APPENDS and only skips the rewrite — that path is LOUD,
# because appending while another process replaces the file is the one residual
# way to lose a row.
_LEDGER_LOCK_MINE=0
_ledger_lstart() { # <pid> -> process start stamp (empty when unknown)
  LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
}
# review #2 round 3: `kill -0` answers EPERM for another user's live process, which
# this code would read as "dead" and delete a live lock. ps is ownership-agnostic.
_ledger_alive() { [[ -n "$(_ledger_lstart "$1")" ]]; }
_ledger_write_owner() { # <dir>
  local d="$1"
  printf '%s\n' "$$" > "$d/pid.tmp" 2>/dev/null && mv -f "$d/pid.tmp" "$d/pid" 2>/dev/null
  _ledger_lstart "$$" > "$d/lstart.tmp" 2>/dev/null && mv -f "$d/lstart.tmp" "$d/lstart" 2>/dev/null
}
# review #2 round 3: breaking into an abandoned mutex with rm -rf + mkdir is the
# same TOCTOU one level up. The break-in renames the mutex away (rename is atomic,
# so exactly one breaker can win) and then checks what it actually got: a fresh
# mutex belongs to a LIVE reclaimer and is put back / abandoned. Only a mutex older
# than a minute — i.e. one whose holder died inside the critical section — is
# discarded.
_ledger_mutex_take() { # <mutex> -> 0 when this process holds a fresh mutex
  local r="$1" t i=0 now mt age
  while [[ "$i" -lt 50 ]]; do
    if mkdir "$r" 2>/dev/null; then return 0; fi
    now=$(date +%s 2>/dev/null || echo 0)
    mt=$(stat -c %Y "$r" 2>/dev/null || stat -f %m "$r" 2>/dev/null || echo 0)
    case "$now$mt" in ''|*[!0-9]*) now=0; mt=0 ;; esac
    age=$(( now - mt ))
    if [[ "$mt" -gt 0 && "$age" -gt 60 ]]; then
      t="$r.stale.$$.$i"
      if mv "$r" "$t" 2>/dev/null; then
        mt=$(stat -c %Y "$t" 2>/dev/null || stat -f %m "$t" 2>/dev/null || echo 0)
        case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
        age=$(( now - mt ))
        if [[ "$mt" -gt 0 && "$age" -gt 60 ]]; then
          rm -rf "$t" 2>/dev/null || true
          mkdir "$r" 2>/dev/null && return 0
        else
          mv "$t" "$r" 2>/dev/null || rm -rf "$t" 2>/dev/null
        fi
        return 1
      fi
    fi
    sleep 0.05 2>/dev/null || sleep 1
    i=$((i+1))
  done
  return 1
}
# v3.97.1 (review #2, N1): rm -rf + mkdir was a TOCTOU — two waiters that both
# judged the owner dead could delete and re-create the dir, leaving BOTH holding
# the lock, and the next awk->mv rewrite then dropped the other's append. Same
# shape as the workspace lock (CHG-130): takeovers run under a .reclaim mutex
# and re-verify the owner inside it. The owner predicate is pid + lstart only —
# NOT the repo, because snapshot shards share one ledger from different
# worktrees, so a repo check would read a peer's live lock as a zombie.
_ledger_lock_reclaim() { # <dir> -> 0 when THIS process re-created the lock
  local d="$1" r="$1.reclaim" op ls now mt age
  _ledger_mutex_take "$r" || return 1
  # Re-verify inside the mutex: the stale owner we judged may already have been
  # replaced by a fresh live one while we waited for the mutex.
  op=$(sed -n '1p' "$d/pid" 2>/dev/null || true)
  case "$op" in ''|*[!0-9]*) op="" ;; esac
  if [[ -n "$op" ]] && _ledger_alive "$op"; then
    ls=$(sed -n '1p' "$d/lstart" 2>/dev/null || true)
    if [[ -z "$ls" || "$ls" == "$(_ledger_lstart "$op")" ]]; then
      rmdir "$r" 2>/dev/null || true
      return 1
    fi
  elif [[ -z "$op" ]]; then
    now=$(date +%s 2>/dev/null || echo 0)
    mt=$(stat -c %Y "$d" 2>/dev/null || stat -f %m "$d" 2>/dev/null || echo 0)
    case "$now$mt" in ''|*[!0-9]*) now=0; mt=0 ;; esac
    age=$(( now - mt ))
    if [[ "$mt" -eq 0 || "$age" -le 5 ]]; then
      rmdir "$r" 2>/dev/null || true
      return 1
    fi
  fi
  rm -rf "$d" 2>/dev/null || true
  if mkdir "$d" 2>/dev/null; then
    _ledger_write_owner "$d"
    rmdir "$r" 2>/dev/null || true
    # Observable so a probe can assert the takeover ran exactly once.
    printf 'ledger lock: reclaimed a stale owner (%s)\n' "$d" >&2
    return 0
  fi
  rmdir "$r" 2>/dev/null || true
  return 1
}
_ledger_lock_acquire() { # -> 0 when this process owns the lock
  local d="${LEDGER_FILE}.lock" i=0 op ls now mt age
  while [[ "$i" -lt 50 ]]; do
    if mkdir "$d" 2>/dev/null; then
      _ledger_write_owner "$d"
      _LEDGER_LOCK_MINE=1
      return 0
    fi
    op=$(sed -n '1p' "$d/pid" 2>/dev/null || true)
    case "$op" in ''|*[!0-9]*) op="" ;; esac
    if [[ -n "$op" ]] && _ledger_alive "$op"; then
      ls=$(sed -n '1p' "$d/lstart" 2>/dev/null || true)
      # A live pid with matching start stamp is the real owner: wait it out. A
      # different stamp is PID reuse and falls through to reclaim.
      if [[ -z "$ls" || "$ls" == "$(_ledger_lstart "$op")" ]]; then
        sleep 0.05 2>/dev/null || sleep 1
        i=$((i+1))
        continue
      fi
    elif [[ -z "$op" ]]; then
      # Owner-less lock (crashed between mkdir and the owner write): reclaim on
      # age alone, or a torn lock disables retention forever. The window is
      # microseconds, so a young one is never evidence of a crash.
      now=$(date +%s 2>/dev/null || echo 0)
      mt=$(stat -c %Y "$d" 2>/dev/null || stat -f %m "$d" 2>/dev/null || echo 0)
      case "$now$mt" in ''|*[!0-9]*) now=0; mt=0 ;; esac
      age=$(( now - mt ))
      if [[ "$mt" -eq 0 || "$age" -le 5 ]]; then
        sleep 0.05 2>/dev/null || sleep 1
        i=$((i+1))
        continue
      fi
    fi
    if _ledger_lock_reclaim "$d"; then
      _LEDGER_LOCK_MINE=1
      return 0
    fi
    sleep 0.05 2>/dev/null || sleep 1
    i=$((i+1))
  done
  return 1
}
_ledger_lock_release() { # owner-only release (ownership is process-local)
  local d="${LEDGER_FILE}.lock" op
  [[ "$_LEDGER_LOCK_MINE" == "1" ]] || return 0
  op=$(cat "$d/pid" 2>/dev/null || true)
  [[ -z "$op" || "$op" == "$$" ]] || return 0
  rm -rf "$d" 2>/dev/null || true
  _LEDGER_LOCK_MINE=0
}

# v3.97.1 (CHG-135): T87 early-exits inside a worktree snapshot (1 assertion,
# ~0 s). Now that snapshot shards share the ledger, such a row would sit beside
# the live section's ~40 s row and drag the planner's median down to the 2 s
# floor — the same mispricing this change removes from the other direction.
_sec_row_wanted() { [[ "$1" != "T87" || "${AGENT_GUARD_SUITE_IN_WT:-0}" != "1" ]]; }

ledger_append() { # <kind> <id> <cost_s> <setup_s> <cache> <exit> [asserts] [outcome]
  local rk mid mwin
  mkdir -p "$(dirname "$LEDGER_FILE")" 2>/dev/null || return 0
  local lk=0
  _ledger_lock_acquire && lk=1
  # Loud, not silent: an unlocked append can still land in an inode another
  # writer is about to replace (mv) — visible so a lost row is traceable.
  [[ "$lk" -eq 1 ]] || printf 'warning: ledger lock busy on %s — appended without rotation\n' "$LEDGER_FILE" >&2
  # v3.91.0 (CHG-127, G1): the 13-column schema. The historical 8 columns keep
  # their positions (readers stay compatible); asserts/rc/outcome/repo_key/
  # model_id/ctx_window are appended. Old 8-column rows are migrated in place.
  rk="$(id -un 2>/dev/null || echo user)@$(hostname 2>/dev/null || echo host)/$(basename "$ROOT")"
  if [[ "$lk" -eq 1 && -s "$LEDGER_FILE" ]] && ! grep -q 'asserts' <<< "$(head -1 "$LEDGER_FILE")"; then
    awk -F'\t' -v rk="$rk" 'BEGIN{OFS="\t"}
      NR==1 {print "ts","kind","id","suite_key","cost_s","setup_s","cache","exit","asserts","rc","outcome","repo_key","model_id","ctx_window"; next}
      { o=($8=="0"?"green":"red"); if ($6=="0" && $8=="0") o="wasted"; print $0,"-1",$8,o,rk,"","" }' \
      "$LEDGER_FILE" > "$LEDGER_FILE.mig" 2>/dev/null && mv -f "$LEDGER_FILE.mig" "$LEDGER_FILE"
  fi
  if [[ ! -s "$LEDGER_FILE" ]]; then
    printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\tasserts\trc\toutcome\trepo_key\tmodel_id\tctx_window\n' > "$LEDGER_FILE" 2>/dev/null \
      || { [[ "$lk" -eq 1 ]] && _ledger_lock_release; return 0; }
  fi
  mid=""; mwin=""
  if [[ -s "$ROOT/.agent-state/model-profile.json" ]]; then
    mid=$(sed -n 's/.*"model_id":"\([^"]*\)".*/\1/p' "$ROOT/.agent-state/model-profile.json" | head -1)
    mwin=$(sed -n 's/.*"context_window":\([0-9]*\).*/\1/p' "$ROOT/.agent-state/model-profile.json" | head -1)
  fi
  local a_="${7:--1}" out="${8:-}"
  [[ -n "$out" ]] || { [[ "$6" == "0" ]] && out="green" || out="red"; }
  if [[ "$a_" == "0" && "$6" == "0" ]]; then out="wasted"; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "${SUITE_KEY:-}" "$3" "$4" "$5" "$6" \
    "$a_" "$6" "$out" "$rk" "$mid" "$mwin" \
    >> "$LEDGER_FILE" 2>/dev/null \
    || { printf 'warning: could not append to %s (non-fatal)\n' "$LEDGER_FILE" >&2; [[ "$lk" -eq 1 ]] && _ledger_lock_release; return 0; }
  # v3.91.1 (CHG-127 self-audit, final-plan §2.2): retention — header + last 500
  # rows (or 90 days), whichever comes first, so the ledger cannot grow forever.
  # v3.97.1 (CHG-135, REQ-1348): hysteresis — rotate only above 600 lines, keep
  # the last 500. At a 501 trigger the window and the cap coincide, so EVERY
  # append rewrote the file: one rewrite per row, i.e. the unlocked-append window
  # stayed permanently open and each writer paid an awk pass per row.
  local _ln
  _ln=$(wc -l < "$LEDGER_FILE" 2>/dev/null | tr -d ' ')
  case "$_ln" in ''|*[!0-9]*) _ln=0 ;; esac
  if [[ "$lk" -eq 1 && "$_ln" -gt 600 ]]; then
    # v3.91.2 erratum: keep every `run-full` row. Pruning them silently erased
    # the whole-run p50 (plan fell back to the 300 s prior) — the retention rule
    # must never destroy the cost-learning baseline.
    # v3.97.0 (CHG-134, REQ-1344): also keep the latest `sec` row per section.
    # Heavy sections (T49 fresh-clone, T57 nested chain) run rarely, so a
    # row-count window pruned exactly the rows the shard planner prices from —
    # the planner then modelled them at the 2 s "unseen" default and skewed the
    # plan. Per-id latest rows are bounded by the section count (~97).
    awk 'NR==1 {print; next}
         {a[++m]=$0; ids[m]=$3; lines[m]=NR
          if ($2=="run-full") keep[NR]=1
          if ($2=="sec") last[$3]=NR}
         END {
           for (i=1;i<=m;i++) if (ids[i] in last && lines[i]==last[ids[i]]) keep[lines[i]]=1
           s=(m>500?m-499:1)
           for (i=s;i<=m;i++) keep[lines[i]]=1
           for (i=1;i<=m;i++) if (keep[lines[i]]) print a[i]
         }' \
      "$LEDGER_FILE" > "$LEDGER_FILE.rot" 2>/dev/null && mv -f "$LEDGER_FILE.rot" "$LEDGER_FILE" 2>/dev/null || rm -f "$LEDGER_FILE.rot" 2>/dev/null
  fi
  [[ "$lk" -eq 1 ]] && _ledger_lock_release
}

# v3.90.1 (CHG-123, P0-13): source-vs-target layout predicate. The old proxy was
# "does scripts/dev/facts.sh exist" — a filename, not a capability. Target repos now
# get -T auto and their own runner, so the gate must key on the LAYOUT instead.
is_source_layout() {
  [[ -d "$ROOT/resources/templates" && -f "$ROOT/tests/audit-standards-src.sh" ]]
}

# v3.90.1 (CHG-123, P0-2): liveness snapshot for waiters — status=running is
# written BEFORE the first section and rewritten after each SERIAL section, so a
# poller can tell "still working" from "finished". Parallel runs update at the
# boundaries only (race-free); the per-section `[done]` lines carry live detail.
progress_write() { # <status: running|done|failed>
  local pf tmp mode
  pf="${AGENT_GUARD_SUITE_PROGRESS_PATH:-$ROOT/.agent-state/suite-progress.json}"
  mkdir -p "$(dirname "$pf")" 2>/dev/null || return 0
  tmp="$pf.$$"
  mode="serial"; [[ "${JOBS:-1}" -ge 2 ]] && mode="parallel"
  {
    printf '{"run_id":"%s-%s","status":"%s","head":"%s","mode":"%s","wall_s":%d,"sections":[' \
      "$$" "$(date -u +%s)" "$1" "${SUITE_KEY:-}" "$mode" "$SECONDS"
    _p_first=1
    for _t in ${_TIMINGS[@]+"${_TIMINGS[@]}"}; do
      _tid="${_t%%:*}"; _rest="${_t#*:}"; _tc="${_rest%%:*}"; _ts="${_rest#*:}"
      [[ "$_p_first" == "1" ]] || printf ','
      _p_first=0
      printf '{"id":"%s","cost_s":%s,"setup_s":%s}' "$_tid" "$_tc" "$_ts"
    done
    printf '],"generated_at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$pf" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; printf 'warning: could not write %s (non-fatal)\n' "$pf" >&2; }
}

_new_repo_prewarm() {
  [[ -n "${_NR_TMPL:-}" && -d "$_NR_TMPL" ]] && return 0
  _NR_TMPL=$(mktemp -d "${TMPDIR:-/tmp}/agent-gate-tmpl.XXXXXX") \
    || { echo "FATAL: new_repo could not create template dir — aborting the suite (never touch the source repo)" >&2; exit 1; }
  _NR_STARTED_ISO=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
  (
    cd "$_NR_TMPL" || exit 1
    unset AGENT_GUARD_DOCS_DIR AGENT_GUARD_SCRIPTS_DIR AGENT_GUARD_TESTS_DIR AGENT_GUARD_GITHOOKS_DIR \
          AGENT_GUARD_CHANGE_ROOT AGENT_GUARD_BUGS_ROOT AGENT_GUARD_TEMPLATES_DIR AGENT_GUARD_STD_FILE
    git init -q
    git config user.email test@example.invalid
    git config user.name test
    mkdir -p scripts docs/changes src .agent-state
    seed_project_masters
    cp "$GATE_SRC" scripts/agent-gate
    chmod +x scripts/agent-gate
    for _nr_lib in lib-json.sh lib-gate-staged.sh lib-gate-cold.sh ui-probe.sh; do
      if [[ -f "$ROOT/resources/templates/$_nr_lib" ]]; then
        cp "$ROOT/resources/templates/$_nr_lib" "scripts/$_nr_lib"
        [[ -x "$ROOT/resources/templates/$_nr_lib" ]] && chmod +x "scripts/$_nr_lib"
      elif [[ -f "$ROOT/scripts/$_nr_lib" ]]; then
        cp "$ROOT/scripts/$_nr_lib" "scripts/$_nr_lib"
        [[ -x "$ROOT/scripts/$_nr_lib" ]] && chmod +x "scripts/$_nr_lib"
      fi
    done
    cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" scripts/
    echo init > README.md
    git add README.md scripts
    git commit -qm init
  ) || { rm -rf "$_NR_TMPL" 2>/dev/null || true; _NR_TMPL=""; echo "FATAL: new_repo template init failed" >&2; exit 1; }
}

new_repo() {
  local _nr_t0
  _nr_t0=$(date +%s)
  NEW_REPO_SETUP_S=0
  [[ -n "${_NR_TMPL:-}" && -d "$_NR_TMPL" ]] || _new_repo_prewarm
  REPO=$(mktemp -d "${TMPDIR:-/tmp}/agent-gate-test.XXXXXX") \
    || { echo "FATAL: new_repo could not create a temp dir — aborting the suite (never touch the source repo)" >&2; exit 1; }
  [[ -d "$REPO" ]] \
    || { echo "FATAL: new_repo temp dir '$REPO' is not a directory — aborting" >&2; exit 1; }
  cp -c -pR "$_NR_TMPL/." "$REPO/" 2>/dev/null \
    || cp --reflink=auto -a "$_NR_TMPL/." "$REPO/" 2>/dev/null \
    || cp -a "$_NR_TMPL/." "$REPO/" \
    || { echo "FATAL: new_repo snapshot clone failed — aborting" >&2; exit 1; }
  cd "$REPO" \
    || { echo "FATAL: new_repo could not cd into '$REPO' (refusing to write in $PWD) — aborting" >&2; exit 1; }
  unset AGENT_GUARD_DOCS_DIR AGENT_GUARD_SCRIPTS_DIR AGENT_GUARD_TESTS_DIR AGENT_GUARD_GITHOOKS_DIR \
        AGENT_GUARD_CHANGE_ROOT AGENT_GUARD_BUGS_ROOT AGENT_GUARD_TEMPLATES_DIR AGENT_GUARD_STD_FILE
  export AGENT_GUARD_ALLOW_INDEPENDENT=1
  export AGENT_GUARD_ALLOW_NO_SHIFT=1
  export AGENT_GUARD_ADAPT=0
  printf '{"started_at":"%s"}\n' "${_NR_STARTED_ISO:-$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)}" > .agent-state/session-started.json
  NEW_REPO_SETUP_S=$(( $(date +%s) - _nr_t0 ))
}

# v3.65.0 (CHG-087, REQ-1046~1048): CLI section-filter surface. Sections are
# wrapped into functions below and dispatched in source order at the bottom.
# -T <sec[,sec]>  run only the named sections (original relative order kept)
# -j <N>          section-level parallel dispatch (N>=2 pool; N=1 = the serial
#                 dispatcher byte-identical to the pre--j behavior)
#                 (v3.72.0 erratum, CHG-095, DES-1868)
# -l|--list       print all section keys, one per line
LIST_ONLY=0
JOBS=1
AUTO=0
AUTO_BASE=""
DUAL_RUN=0
SHARD=""
WORKTREE=0
WANTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -T)
      # Same family as the N1 shift guard: a trailing -T with NO operand at all
      # made `shift 2` fail while $# stayed 1, so this loop never advanced — an
      # infinite hang in the file that ships with bootstrap --guard. Note the
      # operand may legitimately be empty: `-T ""` is a FULL run (T68 pins that a
      # full run refuses a held workspace lock with rc2), so only a missing
      # operand is a usage error. v3.88.0 (CHG-116, REQ-1197): the operand may
      # also be `auto` — changeset-driven section selection (see AUTO_RESOLVE
      # below); it is intercepted here and never reaches the section lookup.
      [[ $# -ge 2 ]] || { printf 'invalid -T value: section list required (usage: tests/run-tests.sh [-T sec[,sec|auto]] [-j N] [--base ref] [-l|--list])\n' >&2; exit 2; }
      if [[ "$2" == "auto" ]]; then AUTO=1; else [[ -n "$2" ]] && IFS=',' read -r -a WANTED <<< "$2"; fi
      shift 2 ;;
    --base)
      # v3.88.0 (CHG-116, REQ-1197): diff base for -T auto (default HEAD, i.e.
      # the uncommitted working tree). Trailing-no-value dies rc2 like every
      # other option in this file (CHG-115 R4 arity family).
      [[ $# -ge 2 && -n "$2" ]] || { printf 'invalid --base value: ref required\n' >&2; exit 2; }
      AUTO_BASE="$2"; shift 2 ;;
    -j)
      # v3.72.0 erratum (CHG-095, DES-1868): N must be a positive integer;
      # 1 keeps the serial dispatcher, N>=2 enables the section-level pool.
      [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || { printf 'invalid -j value: %s (usage: tests/run-tests.sh [-T sec[,sec]] [-j N] [-l|--list])\n' "${2:-}" >&2; exit 2; }
      JOBS="$2"; shift 2 ;;
    --shard)
      # v3.91.7 (CHG-127): deterministic partition of SECTIONS. On hosts where a
      # full run is Killed: 9, the honest evidence is N disjoint shards — a
      # hand-built -T list silently misses sections (T18b was missed in v3.91.6).
      [[ "${2:-}" =~ ^[1-9][0-9]*/[1-9][0-9]*$ ]] || { printf 'invalid --shard value: %s (expected i/N, e.g. 1/6)\n' "${2:-}" >&2; exit 2; }
      SHARD="$2"; shift 2 ;;
    --worktree)
      # v3.95.0 (CHG-132, REQ-1321): run from a disposable git worktree snapshot
      # of the current tracked tree (uncommitted changes included via
      # `git stash create`), so concurrent shard invocations never share cwd or
      # .agent-state. Composes with --shard/-T/-j; refuses to nest (T87).
      WORKTREE=1; shift ;;
    -l|--list) LIST_ONLY=1; shift ;;
    --dual-run) DUAL_RUN=1; shift ;;
    *) printf 'unknown option: %s (usage: tests/run-tests.sh [-T sec[,sec]] [-j N] [--shard i/N] [--worktree] [--dual-run] [-l|--list])\n' "$1" >&2; exit 2 ;;
  esac
done
# No -T operand means "all sections". bash 3.2 + set -u forbids expanding an
# empty array unguarded, so WANTED is only expanded behind a ${#WANTED[@]}
# length check (dispatcher below).

SECTIONS=(T1 T1b T2 T3 T4 T5 T22a T16 T6 T6b T7 T7b T8 T9 T10 T11 T12 T13 T14 T15 T17 T17b T18 T18b T19 T20 T21 T22b T18c T18d T18d-E58R T23 T24 T25 T26 T26b T26c T64 T27 T28 T29 T30 T31 T32 T33 T34 T36 T37 T38 T39 T40 T41 T42 T43 T44 T46 T47 T48 T49a T49b T49c T50 T51 T52 T53 T53b T53c T53d T54 T55 T56 T57 T58 T59 T60 T61 T62 T63 T65 T66 T67 T68 T69 T70 T71 T72 T73 T73b T74 T75 T76 T77 T78 T79 T80 T81 T82 T83 T84 T85 T86 T87 T88)

# v3.96.0 (CHG-133, REQ-1332): cost-balanced 6-way partition. LPT over the
# 2026-10-29 medians in .agent-state/cost-ledger.tsv (T49 161.5s, T57 52s,
# T16 35.5s, T14/T55 25s, T83 24s, T53 23s, ...; unseen sections 2s). The
# contiguous 97/6 split cost 111/110/33/215/175/96s — a 6.6x spread and 244s
# wall clock. (Historical: CHG-158 has since split T49 into T49a/T49b/T49c, so it is no
# longer a single-section floor; re-derive the medians from the ledger before re-balancing.)
# SECTIONS order is untouched (full-run and -j replay keep source order) and the
# SERIAL_CHAIN groups are assigned whole. Adding a section to SECTIONS requires
# adding it here: the drift guard below refuses to shard, and T87 pins coverage.
# v3.97.0 (CHG-134, REQ-1344): the marked block is the output of
# `scripts/dev/shard-plan.sh --write` (median costs, LPT, chain atoms) — do not
# hand-edit members. --write also pins the costs it used in
# tests/.shard-plan-costs.tsv, and `--check` recomputes from that pin: the suite
# appends its own `sec` rows, so checking against the live ledger would red the
# plan as a side effect of running it. Drift from the live ledger is a WARN;
# rebalancing is the explicit `--write` in the release ritual.
SHARD_PLAN_6=(
  # SHARD_PLAN_6_BEGIN
  "T1b T3 T8 T17b T20 T36 T50 T51 T53 T56 T68 T69 T80 T84"
  "T2 T6b T10 T19 T18d T18d-E58R T24 T27 T30 T38 T52 T53d T55 T58 T62 T72 T85"
  "T7 T9 T15 T17 T18 T22b T25 T26 T31 T39 T44 T47 T49b T49c T66 T70 T86"
  "T1 T4 T26b T28 T32 T37 T41 T53c T54 T57 T61 T71 T73 T74 T75 T83 T88"
  "T5 T22a T16 T6 T11 T12 T18b T18c T26c T33 T42 T43 T46 T49a T63 T73b T77 T78 T82 T87"
  "T7b T13 T14 T21 T23 T64 T29 T34 T40 T48 T53b T59 T60 T65 T67 T76 T79 T81"
  # SHARD_PLAN_6_END
)

# v3.91.7 (CHG-127): --shard i/N — deterministic partition, reproducible without
# hand-building a 94-key -T list. N=6 uses SHARD_PLAN_6 (cost-balanced); any
# other N falls back to contiguous slices (which keep SERIAL_CHAIN adjacency
# for small N). Both make shard evidence reproducible.
if [[ -n "$SHARD" ]]; then
  [[ "$AUTO" -eq 1 || ${#WANTED[@]} -gt 0 ]] \
    && { printf 'invalid option combination: --shard is exclusive with -T/auto\n' >&2; exit 2; }
  _sh_i="${SHARD%/*}"; _sh_n="${SHARD#*/}"
  [[ "$_sh_i" -le "$_sh_n" ]] || { printf 'invalid --shard value: %s (i must be <= N)\n' "$SHARD" >&2; exit 2; }
  if [[ "$_sh_n" -eq 6 ]]; then
    _plan_flat="${SHARD_PLAN_6[*]}"
    for _sh_s in "${SECTIONS[@]}"; do
      case " $_plan_flat " in
        *" $_sh_s "*) ;;
        *) printf 'shard plan drift: %s is not in SHARD_PLAN_6 (update the plan in tests/run-tests.sh)\n' "$_sh_s" >&2; exit 2 ;;
      esac
    done
    # 反向同样要守：表内成员不在 SECTIONS（改名/删节后留死名）或重复出现，
    # 会让某一节在表中被算两次、而某个真节永远跑不到——单向守卫看不出来。
    for _sh_p in "${SHARD_PLAN_6[@]}"; do
      for _sh_m in $_sh_p; do
        case " ${SECTIONS[*]} " in
          *" $_sh_m "*) ;;
          *) printf 'shard plan drift: %s is in SHARD_PLAN_6 but not in SECTIONS (update the plan)\n' "$_sh_m" >&2; exit 2 ;;
        esac
        _sh_seen=$(printf '%s\n' $_plan_flat | grep -c "^${_sh_m}$")
        [[ "$_sh_seen" -eq 1 ]] || { printf 'shard plan drift: %s appears %s times in SHARD_PLAN_6 (each section exactly once)\n' "$_sh_m" "$_sh_seen" >&2; exit 2; }
      done
    done
    WANTED=( ${SHARD_PLAN_6[$((_sh_i - 1))]:-} )
    # An empty group would otherwise die on ${WANTED[0]} below under `set -u`
    # (rc=1, no named message) instead of the plan-drift refusal.
    [[ ${#WANTED[@]} -gt 0 ]] || { printf 'shard plan drift: shard %s/%s is empty in SHARD_PLAN_6 (each shard needs at least one section)\n' "$_sh_i" "$_sh_n" >&2; exit 2; }
  else
    _sh_total=${#SECTIONS[@]}
    _sh_start=$(( (_sh_i - 1) * _sh_total / _sh_n ))
    _sh_end=$(( _sh_i * _sh_total / _sh_n ))
    WANTED=("${SECTIONS[@]:_sh_start:_sh_end-_sh_start}")
  fi
  printf 'shard %s/%s: %d sections (%s .. %s)\n' "$_sh_i" "$_sh_n" "${#WANTED[@]}" "${WANTED[0]}" "${WANTED[${#WANTED[@]}-1]}"
  if [[ "${AGENT_GUARD_SUITE_SHARD_RESOLVE_ONLY:-0}" == "1" ]]; then
    printf 'shard-resolve-only:%s\n' "$(printf ' %s' "${WANTED[@]}")"; exit 0
  fi
fi

if [[ "${LIST_ONLY}" == 1 ]]; then printf '%s\n' "${SECTIONS[@]}"; exit 0; fi
if [[ ${#WANTED[@]} -gt 0 ]]; then
  for _w in "${WANTED[@]}"; do
    case " ${SECTIONS[*]} " in *" $_w "*) ;; *) printf 'unknown section: %s (available: bash tests/run-tests.sh -l)\n' "$_w" >&2; exit 2 ;; esac
  done
fi
# v3.88.0 (CHG-116, REQ-1197): -T auto — changeset-driven section selection.
# Resolution is a pure decision phase, printable and observable through the
# AGENT_GUARD_SUITE_AUTO_DIFF (file list) and AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY
# (print decision, exit) test seams. The safety default is FULL: any file the
# table cannot map, or the runner editing itself, must never shrink the run —
# the mapping is an optimization, never a correctness dependency. Partial
# results are quarantined to .agent-state/last-suite-partial.json with
# kind:"partial" (REQ-1198): only a full run may write last-suite-receipt.json,
# and ci-summary --check rejects anything else.
_auto_map() { # <file> -> sections on stdout; rc1 = unmapped (caller falls back to FULL); rc2 = suite-irrelevant (no-op)
  case "$1" in
    scripts/dev/lib-source-facts.sh)       printf 'T69 T70 T71 T72 T73b' ;;
    scripts/dev/facts.sh)                  printf 'T70' ;;
    scripts/dev/verify-all.sh)             printf 'T71' ;;
    scripts/dev/pre-review-check.sh)       printf 'T72 T74' ;;
    scripts/dev/mutation-check.sh)         printf 'T73' ;;
    scripts/dev/ci-summary.sh)             printf 'T73b T75' ;;
    scripts/dev/batch-metrics.sh)          printf 'T73b' ;;
    scripts/dev/update-assertion-count.sh) printf 'T69' ;;
    scripts/bootstrap.sh)              printf 'T11 T14 T15 T21 T40 T42 T49a T49b T49c T63 T70 T71 T72 T73 T73b' ;;
    tests/audit-standards-src.sh)      printf 'T69' ;;
    tests/.suite-baseline|tests/.audit-baseline) printf 'T51' ;;
    README.md|README.zh-CN.md)         printf 'T51' ;;
    .github/*)                         printf 'T73b' ;;
    .claude-plugin/*)                  printf 'T48' ;;
    resources/DEVELOPMENT_STANDARDS.md) printf 'T11 T14 T15 T20 T21 T31 T38 T40 T43 T48 T55 T63 T64 T67' ;;
    resources/AGENTS.md)               printf 'T26c T40 T43 T48 T55 T63 T64' ;;
    resources/STANDARDS_CHANGELOG.md|archive/STANDARDS_CHANGELOG_ARCHIVE.md) printf 'T15 T40 T48' ;;
    SKILL.md)                          printf 'T11 T15 T19 T21 T48 T67' ;;
    resources/templates/audit-docs-consistency.sh)  printf 'T10 T79' ;;
    resources/templates/session-gate.sh)            printf 'T24 T26 T26b T29 T49a T49b T49c T78' ;;
    scripts/agent-gate|resources/templates/agent-gate.sh|resources/templates/lib-gate-staged.sh) printf 'T19 T26b T30 T41 T50 T78 T82 T83 T86' ;;
    scripts/session-gate.sh|scripts/lib-suite-lock.sh) printf 'T26 T26b T41 T57' ;;
    tests/.shard-plan-costs.tsv)       printf 'T87' ;;
    tests/suites/suite-01-core.sh)     printf 'T1 T1b T2 T3 T4 T5 T22a T16 T6 T6b T7 T7b T8 T9 T10 T11 T12 T13' ;;
    tests/suites/suite-02-install.sh)  printf 'T14 T15 T17 T17b T18 T18b T19 T20 T21 T22b T18c T18d T18d-E58R T23 T24 T25' ;;
    tests/suites/suite-03-session.sh)  printf 'T26 T26b T26c T64 T27 T28 T29 T30 T31 T32 T33 T34 T36 T37' ;;
    tests/suites/suite-04-gates.sh)    printf 'T38 T39 T40 T41 T42 T43 T44 T46 T47 T48' ;;
    tests/suites/suite-05-adapter.sh)  printf 'T49a T49b T49c' ;;
    tests/suites/suite-06-runner.sh)   printf 'T50 T51 T52 T53 T53b T53c T53d T54 T55 T56 T57 T58 T59 T60 T61 T62' ;;
    tests/suites/suite-07-adapt.sh)    printf 'T63 T65 T66 T67 T68 T69 T70 T71 T72 T73 T73b T74 T75 T76 T77 T78' ;;
    tests/suites/suite-08-infra.sh)    printf 'T79 T80 T81 T82 T83 T84 T85 T86 T87 T88' ;;
    tests/*)                           printf 'T50 T51 T75 T76' ;;
    resources/templates/stamp-provenance.sh)        printf 'T16 T17 T17b' ;;
    resources/templates/install-hook-adapter.sh)    printf 'T49a T49b T49c' ;;
    resources/templates/*.md)          printf 'T7b T18c T18d T43 T46 T86' ;;
    resources/templates/agent-governance.yml|resources/templates/github-*.yml) printf 'T73b' ;;
    resources/METHODOLOGY.md|resources/STAGE_PLAYBOOK.md|resources/methodologies/*|resources/templates/*.md) printf 'T40 T43 T48 T86' ;;
    scripts/shard-sum.sh)              printf 'T87' ;;
    scripts/dev/shard-plan.sh|scripts/dev/pre-round-check.sh|scripts/evidence-round.sh) printf 'T87' ;;
    scripts/*|resources/templates/*.sh) printf 'T19 T30 T41 T86' ;;
    docs/*)                            return 2 ;;  # 变更产物/评审记录：不影响治理工具，无需套件
    MAINTAINER.md)                     return 2 ;;
    # v3.91.2 (CHG-127 self-audit, replay evidence): non-governance repo assets
    # (screenshots, licences, editor config, root docs) cannot change the suite's
    # behaviour. They used to be "unmapped" → FULL, which inflated the fallback
    # rate that final-plan P0-12 caps at 30%.
    screenshots/*|cover-image/*|LICENSE|LICENSE.*|.gitignore|.gitattributes) return 2 ;;
    .vscode/*|.claude/*|.opencode/*|.workbuddy/*|.workbuddy-ai/*) return 2 ;;
    AGENTS.md|CLAUDE.md|GEMINI.md)      return 2 ;;
    *.md)                              return 2 ;;  # root narrative docs (README/SKILL matched above)
    .agent-state/*|.workbuddy-ai/*)    return 2 ;;
    # v3.90.1 (CHG-123, P0-12): unmapped governance-face paths fall back to the
    # same-domain core section triple instead of a FULL run (historical 77%
    # edit->FULL rate). Non-governance unknown paths stay "irrelevant".
    scripts/*|resources/*|tests/*)     printf 'T19 T30 T41' ;;
    *) return 1 ;;
  esac
}
if [[ "$AUTO" -eq 1 ]]; then
  _auto_files=()
  if [[ -n "${AGENT_GUARD_SUITE_AUTO_DIFF:-}" ]]; then
    IFS=',' read -r -a _auto_files <<< "$AGENT_GUARD_SUITE_AUTO_DIFF"
  else
    while IFS= read -r _f; do [[ -n "$_f" ]] && _auto_files+=("$_f"); done \
      < <(git -C "$ROOT" diff --name-only ${AUTO_BASE:+"$AUTO_BASE"} HEAD 2>/dev/null)
  fi
  if [[ ${#_auto_files[@]} -eq 0 ]]; then
    printf 'auto: no tracked changes vs %s — nothing to verify\n' "${AUTO_BASE:-HEAD}"
    exit 0
  fi
  _auto_full=""
  _auto_secs=""
  _auto_skip_n=0
  # v3.90.4 (FU-126-1): AI judgment for test scope. The orchestrator may pass an
  # explicit decision ONLY with evidence; a missing/short basis, a malformed
  # reviewer signature, or an unknown section is rejected and the engine mapping
  # (or FULL fallback) wins. This replaces the hard "runner self-edit => FULL"
  # mono-rule with "AI may override when it can prove the narrower scope".
  _ai_secs="${AGENT_GUARD_SUITE_AI_SECTIONS:-}"
  _ai_basis="${AGENT_GUARD_SUITE_AI_BASIS:-}"
  _ai_reviewer="${AGENT_GUARD_SUITE_AI_REVIEWER:-}"
  _ai_valid=0
  _ai_reject=""
  if [[ -n "$_ai_secs" ]]; then
    if [[ -z "$_ai_basis" || ${#_ai_basis} -lt 20 ]]; then
      _ai_reject="basis missing or shorter than 20 chars"
    elif [[ ! "$_ai_reviewer" =~ ^[^/]+[[:space:]]/[[:space:]][^/]+[[:space:]]/[[:space:]](task-|ses-) ]]; then
      _ai_reject="reviewer must be 'platform / model / task-|ses-…'"
    else
      _ai_valid=1
      for _s in $_ai_secs; do
        case " ${SECTIONS[*]} " in
          *" $_s "*) ;;
          *) _ai_valid=0; _ai_reject="unknown section $_s"; break ;;
        esac
      done
    fi
  fi
  for _f in "${_auto_files[@]}"; do
    if [[ "$_f" == "tests/run-tests.sh" || "$_f" == tests/lib/* ]]; then _auto_full="runner self-edit ($_f)"; break; fi
    _m=$(_auto_map "$_f") && _rc=0 || _rc=$?
    case "$_rc" in
      0) _auto_secs="$_auto_secs $_m" ;;
      2) _auto_skip_n=$(( _auto_skip_n + 1 )) ;;   # suite-irrelevant: docs/artifacts never move the gate
      *) _auto_full="unmapped changed file: $_f"; break ;;
    esac
  done
  if [[ "$_ai_valid" == "1" ]]; then
    _auto_secs="$_ai_secs"
    _auto_full=""
    printf 'auto: AI judgment accepted (%s) — basis: %s\n' "$_ai_reviewer" "$_ai_basis"
  elif [[ -n "$_ai_secs" ]]; then
    printf 'auto: AI judgment rejected (%s) — engine mapping decides\n' "$_ai_reject"
  fi
  # All changed files are suite-irrelevant: there is nothing to verify. Exiting 0 here
  # is the honest answer — running the suite would prove nothing about these files.
  if [[ -z "$_auto_full" && -z "${_auto_secs// /}" ]]; then
    printf 'auto: %d changed file(s) — no suite-relevant changes (%d suite-irrelevant)\n' \
      "${#_auto_files[@]}" "$_auto_skip_n"
    [[ "${AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY:-0}" == "1" ]] && printf 'auto-resolve-only: NONE\n'
    exit 0
  fi
  if [[ -z "$_auto_full" ]]; then
    _auto_secs="$_auto_secs T50"   # registry tail pin always runs (REQ-1197)
    WANTED=()
    for _s in "${SECTIONS[@]}"; do case " $_auto_secs " in *" $_s "*) WANTED+=("$_s") ;; esac; done
    printf 'auto: %d changed file(s) -> sections:%s\n' "${#_auto_files[@]}" "$(printf ' %s' "${WANTED[@]}")"
    if [[ "${AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY:-0}" == "1" ]]; then printf 'auto-resolve-only:%s\n' "$(printf ' %s' "${WANTED[@]}")"; exit 0; fi
  else
    printf 'auto: falling back to FULL run (%s)\n' "$_auto_full"
    WANTED=()
    if [[ "${AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY:-0}" == "1" ]]; then printf 'auto-resolve-only: FULL\n'; exit 0; fi
  fi
fi
# v3.88.0 (CHG-116): test seams must not leak into nested runner invocations —
# T50 spawns filtered children that would otherwise inherit FAKE_FULL and count
# as suite purchases. Capture early, strip from the children's environment.
_fake_full="${AGENT_GUARD_SUITE_FAKE_FULL:-0}"
unset AGENT_GUARD_SUITE_FAKE_FULL 2>/dev/null || true
# v3.86.0 (CHG-113, P1-3): full runs take a workspace lock. Filtered (-T) runs
# never write the receipt and are spawned as children by T51/T57/T61 — locking
# them would deadlock. AGENT_GUARD_SUITE_LOCK_HELD guards re-entry through
# update-assertion-count's embedded run.
if [[ ${#WANTED[@]} -eq 0 && "${AGENT_GUARD_SUITE_LOCK_HELD:-0}" != "1" ]]; then
  _lock_lib="$ROOT/scripts/lib-suite-lock.sh"
  if [[ -f "$_lock_lib" ]]; then
    source "$_lock_lib"
    if command -v suite_lock_acquire >/dev/null 2>&1; then
      if ! suite_lock_acquire; then
        printf 'run-tests: another full suite owns this workspace (or the lock is younger than the grace window). Wait for it or set AGENT_GUARD_SUITE_LOCK_DIR to an isolated path.\n' >&2
        exit 2
      fi
      trap 'suite_lock_release' EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      export AGENT_GUARD_SUITE_LOCK_HELD=1
    fi
  fi
fi
# v3.91.7 (CHG-127): per-host kill marker. A host observed to SIGKILL a full run
# (~10 min, `Killed: 9`) refuses to burn another attempt; the marker lives in the
# gitignored .agent-state and never ships. Shards or CI are the evidence paths.
if [[ ${#WANTED[@]} -eq 0 && "${AGENT_GUARD_FULL_SUITE_FORCE:-0}" != "1" ]]; then
  _ks_dir="${AGENT_GUARD_SUITE_KILL_STATE_DIR:-$ROOT/.agent-state}"
  _ks_marker="$_ks_dir/full-suite-kill.$(hostname -s 2>/dev/null || echo host)"
  if [[ -f "$_ks_marker" ]]; then
    printf 'run-tests: this host is marked full-suite-kill (%s) — refusing another full run.\n' "$(head -1 "$_ks_marker" 2>/dev/null)" >&2
    printf 'run-tests: use tests/run-tests.sh --shard i/N (N disjoint shards) or let CI run the full suite; force with AGENT_GUARD_FULL_SUITE_FORCE=1.\n' >&2
    exit 3
  fi
fi
# v3.92.4 (CHG-129): repeat-run guard. One -T set repeated at the same HEAD is
# the costliest waste we have observed (a 1537 s turn ran one set 5 times and
# burned two fresh-clone receipts). Record one fingerprint row per top-level
# run; once the window already holds AGENT_GUARD_REPEAT_LIMIT runs, say so on
# stderr. Never blocks, never touches stdout (T50 tail / T57 byte-equality).
# Sections spawn run-tests.sh themselves (T50/T57/T61/T70/T75) — that is the
# same logical execution, so the marker exported below silences the children.
_repeat_limit="${AGENT_GUARD_REPEAT_LIMIT:-3}"
case "$_repeat_limit" in ''|*[!0-9]*) _repeat_limit=3 ;; esac
[[ ${#_repeat_limit} -le 9 ]] || _repeat_limit=3
# "08" is octal syntax inside $(( )); normalize before any numeric test so a
# leading zero can never make the guard itself print an arithmetic error.
: "$(( _repeat_limit = 10#$_repeat_limit ))"
if [[ "$_repeat_limit" -gt 0 && "${AGENT_GUARD_SUITE_NESTED:-0}" != "1" ]]; then
  _repeat_sections="FULL"
  if [[ ${#WANTED[@]} -gt 0 ]]; then
    _repeat_sections=$(printf '%s\n' "${WANTED[@]}" | LC_ALL=C sort -u | paste -s -d, -)
  fi
  _repeat_key="${SUITE_KEY:-nogit}|${_repeat_sections}"
  _repeat_state="${AGENT_GUARD_REPEAT_STATE_PATH:-$ROOT/.agent-state/suite-repeats.tsv}"
  _repeat_window=1800
  _repeat_now=$(date +%s)
  _repeat_prior=0
  if [[ -f "$_repeat_state" ]]; then
    # Upper bound too: a row written while the clock was ahead must not stay
    # "in window" forever.
    _repeat_prior=$(awk -F'\t' -v k="$_repeat_key" -v t="$(( _repeat_now - _repeat_window ))" -v nw="$_repeat_now" \
      '$2==k && $1+0>=t && $1+0<=nw {n++} END{print n+0}' "$_repeat_state" 2>/dev/null)
    case "$_repeat_prior" in ''|*[!0-9]*) _repeat_prior=0 ;; esac
    _repeat_rows=$(wc -l < "$_repeat_state" 2>/dev/null | tr -d ' ')
    awk -F'\t' -v t="$(( _repeat_now - _repeat_window ))" '$1+0>=t' "$_repeat_state" \
      > "$_repeat_state.tmp.$$" 2>/dev/null || rm -f "$_repeat_state.tmp.$$" 2>/dev/null
    # Swap in the pruned ledger only when no other run appended meanwhile — a
    # rewrite that drops a concurrent row would undercount (silently, and the
    # guard is warning-only, so a stale row is the cheaper failure).
    if [[ -f "$_repeat_state.tmp.$$" \
       && "$(wc -l < "$_repeat_state" 2>/dev/null | tr -d ' ')" == "$_repeat_rows" ]]; then
      mv -f "$_repeat_state.tmp.$$" "$_repeat_state" 2>/dev/null || rm -f "$_repeat_state.tmp.$$" 2>/dev/null
    else
      rm -f "$_repeat_state.tmp.$$" 2>/dev/null
    fi
  fi
  if [[ "$_repeat_prior" -ge "$_repeat_limit" ]]; then
    printf 'run-tests: repeat guard — section set (%s) already ran %s time(s) in the last %s min; this is run #%s (limit %s).\n' \
      "$_repeat_key" "$_repeat_prior" "$(( _repeat_window / 60 ))" "$(( _repeat_prior + 1 ))" "$_repeat_limit" >&2
    printf 'run-tests: stop re-running — read the previous result (%s; subset runs also record %s) or set AGENT_GUARD_REPEAT_LIMIT=0 to silence.\n' \
      "$SUITE_RECEIPT_PATH" "$ROOT/.agent-state/last-suite-partial.json" >&2
  fi
  mkdir -p "$(dirname "$_repeat_state")" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\t%s\n' "$_repeat_now" "$_repeat_key" "$_repeat_sections" "${JOBS:-1}" "$$" \
    >> "$_repeat_state" 2>/dev/null || true
fi
export AGENT_GUARD_SUITE_NESTED=1
# v3.95.0 (CHG-132, REQ-1321): --worktree — run this suite from a disposable git
# worktree snapshot so concurrent invocations (six shards at once) never share
# cwd, .agent-state, or temp-repo state. The snapshot is a `git stash create`
# commit of the CURRENT tracked working tree — uncommitted changes ride along,
# no ref is mutated, a clean tree falls back to HEAD. Carry is structural, not
# asserted: a snapshot taken at HEAD would lack this change's own sections and
# the `-T T87` self-run below would fail (T87 exists only in the working tree).
# Gitignored runtime (scripts/agent-gate, scripts/session-gate.sh,
# scripts/stamp-provenance.sh) is regenerated from the tracked templates inside
# the snapshot — the same recipe bootstrap applies in target repos. Full runs
# still hit the lock and kill-marker gates ABOVE: --worktree is an isolation
# mechanism, never a bypass.
if [[ "$WORKTREE" -eq 1 ]]; then
  if [[ "${AGENT_GUARD_SUITE_IN_WT:-0}" == "1" ]]; then
    printf 'invalid --worktree: already inside a suite worktree (recursion guard)\n' >&2
    exit 2
  fi
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { printf -- '--worktree requires a git repository (ROOT=%s)\n' "$ROOT" >&2; exit 2; }
  # Snapshot creation is serialized + retried: concurrent `git stash create`
  # invocations contend on git's index locks and 5/6 silently lost in the first
  # 6-way round (the losers fell back to HEAD and tested stale code — a
  # false-green machine). A dirty tracked tree with a persistently failing
  # stash must refuse with a named error instead of falling back to HEAD.
  _wt_lock="$ROOT/.agent-state/wt-snapshot.lock"
  mkdir -p "$ROOT/.agent-state" 2>/dev/null || true
  _wt_held=0
  for _wt_i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
               21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 \
               41 42 43 44 45 46 47 48 49 50; do
    mkdir "$_wt_lock" 2>/dev/null && { _wt_held=1; break; }
    sleep 0.2
  done
  [[ "$_wt_held" -eq 1 ]] \
    || { printf 'worktree: snapshot lock %s busy after 10s (stale lock? remove it and retry)\n' "$_wt_lock" >&2; exit 2; }
  _wt_snap=""
  for _wt_i in 1 2 3; do
    _wt_snap=$(git -C "$ROOT" stash create "suite worktree snapshot" 2>/dev/null) && [[ -n "$_wt_snap" ]] && break
    _wt_snap=""
    sleep 0.5
  done
  if [[ -z "$_wt_snap" ]]; then
    if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
      rmdir "$_wt_lock" 2>/dev/null || true
      printf -- '--worktree: tracked tree carries uncommitted changes but git stash create failed repeatedly — refusing to snapshot a stale HEAD (would test the wrong code)\n' >&2
      exit 2
    fi
    _wt_snap=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || true
    [[ -n "$_wt_snap" ]] || { rmdir "$_wt_lock" 2>/dev/null || true; printf -- '--worktree needs at least one commit (unborn HEAD)\n' >&2; exit 2; }
  fi
  mkdir -p "$ROOT/.agent-state" 2>/dev/null || true
  _wt_dir=$(mktemp -d "$ROOT/.agent-state/wt-shard.XXXXXX" 2>/dev/null) \
    || { rmdir "$_wt_lock" 2>/dev/null || true; printf 'worktree: cannot create a snapshot dir under %s/.agent-state\n' "$ROOT" >&2; exit 2; }
  if ! git -C "$ROOT" worktree add --detach --quiet "$_wt_dir" "$_wt_snap" >/dev/null 2>&1; then
    rm -rf "$_wt_dir"
    rmdir "$_wt_lock" 2>/dev/null || true
    printf 'worktree: git worktree add failed for snapshot %s\n' "$_wt_snap" >&2
    exit 2
  fi
  rmdir "$_wt_lock" 2>/dev/null || true
  for _wt_rt in agent-gate:agent-gate.sh session-gate.sh:session-gate.sh stamp-provenance.sh:stamp-provenance.sh; do
    _wt_dst="$_wt_dir/scripts/${_wt_rt%%:*}"
    _wt_src="$_wt_dir/resources/templates/${_wt_rt##*:}"
    [[ -f "$_wt_dst" || ! -f "$_wt_src" ]] || install -m 755 "$_wt_src" "$_wt_dst"
  done
  _wt_args=()
  if [[ ${#WANTED[@]} -gt 0 ]]; then
    _wt_list=$(IFS=','; printf '%s' "${WANTED[*]}")
    _wt_args+=(-T "$_wt_list")
  fi
  [[ "$JOBS" -ge 2 ]] && _wt_args+=(-j "$JOBS")
  [[ "$DUAL_RUN" -eq 1 ]] && _wt_args+=(--dual-run)
  printf 'worktree: snapshot %s at %s\n' "${_wt_snap:0:12}" "$_wt_dir"
  _wt_rc=0
  ( cd "$_wt_dir" && AGENT_GUARD_SUITE_IN_WT=1 bash tests/run-tests.sh "${_wt_args[@]}" ) || _wt_rc=$?
  git -C "$ROOT" worktree remove --force "$_wt_dir" >/dev/null 2>&1 || rm -rf "$_wt_dir"
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  exit "$_wt_rc"
fi
# v3.95.0 (CHG-132): serial-chain members, hoisted before both dispatch branches —
# the parallel pool collects them separately AND the section cache (below) must
# never store or serve them (their results depend on shared cwd/shell state).
SERIAL_CHAIN=(T50 T51 T5 T22a T16)
# v3.95.0 (CHG-132, REQ-1324): opt-in per-section result cache. Content-addressed
# by the suite tree fingerprint: a row is only served when the tree is
# byte-identical to the tree that produced it. Default OFF; forced off under the
# observational seams (FORCE_RED / DUAL_RUN / resolve-only) and inside worktree
# snapshots (keeps --worktree A/B runs execution-identical). SERIAL_CHAIN members
# are never cached. A hit prints `[cached] <sec> (P passed, F failed)` and skips
# the ledger row (a 0s row would poison the sec-latency p50).
_cache_enabled=0
if [[ "${AGENT_GUARD_SECTION_CACHE:-0}" == "1" \
   && "${AGENT_GUARD_SUITE_FORCE_RED:-0}" != "1" \
   && "${DUAL_RUN:-0}" != "1" \
   && "${AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY:-0}" != "1" \
   && "${AGENT_GUARD_SUITE_SHARD_RESOLVE_ONLY:-0}" != "1" \
   && "${AGENT_GUARD_SUITE_IN_WT:-0}" != "1" ]]; then
  _cache_enabled=1
fi
_cache_fp=""
_cache_hits=0
# v3.97.0 (CHG-134, REQ-1343): the cache file path is overridable so a test can
# drive retention without touching the repo's real cache.
_cache_file="${AGENT_GUARD_SECTION_CACHE_PATH:-$ROOT/.agent-state/section-cache.tsv}"
if [[ "$_cache_enabled" -eq 1 ]] && command -v suite_tree_fingerprint >/dev/null 2>&1; then
  _cache_fp=$(suite_tree_fingerprint "$ROOT")
  [[ -n "$_cache_fp" ]] || _cache_enabled=0
fi
_cache_lookup() { # <section> -> prints "P F" on hit; rc 1 on miss/disabled
  [[ -n "$_cache_fp" && -f "$_cache_file" ]] || return 1
  local _row
  _row=$(awk -F'\t' -v fp="$_cache_fp" -v sec="$1" '$1==fp && $2==sec {print $3, $4; exit}' "$_cache_file" 2>/dev/null) || return 1
  [[ "$_row" =~ ^[0-9]+[[:space:]][0-9]+$ ]] || return 1
  printf '%s\n' "$_row"
}
# v3.97.0 (CHG-134, REQ-1343): retention keeps the current tree's rows plus the
# two most recent historical fingerprints (by row ts), capped at 400 rows with
# current-tree rows always kept. Before this, every code edit wiped the table,
# so the hit rate inside a change cycle was permanently zero — exactly when a
# re-run is most likely.
_cache_store() { # <section> <passed> <failed>
  [[ "$_cache_enabled" -eq 1 && -n "$_cache_fp" ]] || return 0
  local _cf="$_cache_file" _tmp
  mkdir -p "$(dirname "$_cf")" 2>/dev/null || return 0
  _tmp="$_cf.tmp.$$"
  { [[ -f "$_cf" ]] && cat "$_cf"; \
    printf '%s\t%s\t%s\t%s\t%s\n' "$_cache_fp" "$1" "$2" "$3" "$(date +%s)"; } > "$_tmp.raw" 2>/dev/null
  awk -F'\t' -v fp="$_cache_fp" -v cap=400 '
    { rows[NR]=$0; f[NR]=$1; if ($5+0 > last[$1]) last[$1]=$5+0 }
    END {
      n=0
      for (k in last) if (k != fp) hist[++n]=k
      for (i=2;i<=n;i++) { key=hist[i]; q=i-1; while (q>=1 && last[hist[q]] < last[key]) { hist[q+1]=hist[q]; q-- } hist[q+1]=key }
      cn=0; hn=0
      for (i=1;i<=NR;i++) {
        if (f[i] == fp) cur[++cn]=rows[i]
        else if (f[i] == hist[1] || f[i] == hist[2]) hrows[++hn]=rows[i]
      }
      budget=cap-cn; if (budget < 0) budget=0
      start=hn-budget+1; if (start < 1) start=1
      for (i=start;i<=hn;i++) print hrows[i]
      for (i=1;i<=cn;i++) print cur[i]
    }' "$_tmp.raw" > "$_tmp" 2>/dev/null \
    && mv -f "$_tmp" "$_cf" 2>/dev/null || { rm -f "$_tmp" "$_tmp.raw" 2>/dev/null; }
  rm -f "$_tmp.raw" 2>/dev/null
  return 0
}
# v3.72.0 erratum (CHG-095, DES-1868): replay/re-export anchors — defined ONCE
# here; the parallel branch's counter/failed_names re-export shares them with
# the report() wire format (^ok / ^FAIL).
_RE_OK='^ok '
_RE_FAIL='^FAIL '
# v3.90.1 (CHG-123, P0-2): collected per-section timings -> suite-progress.json
_TIMINGS=()
if [[ -f "$ROOT/tests/lib/test-harness.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/tests/lib/test-harness.sh"
fi
_LOADED_SUITES=" "
_suite_file_for_sec() {
  case "$1" in
    T1|T1b|T2|T3|T4|T5|T22a|T16|T6|T6b|T7|T7b|T8|T9|T10|T11|T12|T13) printf 'suite-01-core.sh' ;;
    T14|T15|T17|T17b|T18|T18b|T19|T20|T21|T22b|T18c|T18d|T18d-E58R|T23|T24|T25) printf 'suite-02-install.sh' ;;
    T26|T26b|T26c|T64|T27|T28|T29|T30|T31|T32|T33|T34|T36|T37) printf 'suite-03-session.sh' ;;
    T38|T39|T40|T41|T42|T43|T44|T46|T47|T48) printf 'suite-04-gates.sh' ;;
    T49a|T49b|T49c) printf 'suite-05-adapter.sh' ;;
    T50|T51|T52|T53|T53b|T53c|T53d|T54|T55|T56|T57|T58|T59|T60|T61|T62) printf 'suite-06-runner.sh' ;;
    T63|T65|T66|T67|T68|T69|T70|T71|T72|T73|T73b|T74|T75|T76|T77|T78) printf 'suite-07-adapt.sh' ;;
    T79|T80|T81|T82|T83|T84|T85|T86|T87|T88) printf 'suite-08-infra.sh' ;;
  esac
}
_load_suite_for_sec() {
  local _sf
  _sf=$(_suite_file_for_sec "$1")
  [[ -n "$_sf" ]] || return 0
  case "$_LOADED_SUITES" in *" $_sf "*) return 0 ;; esac
  if [[ -f "$ROOT/tests/suites/$_sf" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT/tests/suites/$_sf"
    _LOADED_SUITES="${_LOADED_SUITES}${_sf} "
  fi
}
if [[ ${#WANTED[@]} -gt 0 ]]; then
  for _ls in "${WANTED[@]}"; do _load_suite_for_sec "$_ls"; done
else
  for _ls in "${SECTIONS[@]}"; do _load_suite_for_sec "$_ls"; done
fi
progress_write running
if [[ "$JOBS" -ge 2 ]]; then
  # ---- parallel branch: section-level pool + source-order replay ----------
  # SERIAL_CHAIN: sections that cannot run in parallel subshells, in THIS
  # execution order — T50/T51 nest the real run-tests.sh and want cwd=$ROOT
  # (so they go first); T5→T22a→T16 form a CHG-500 fixture continuation chain
  # (T22a/T16 evolve T5's temp repo via cwd, deliberately not self-contained —
  # known limitation: `-T T22a` standalone is unsupported, use -T T5,T22a,T16).
  # They run serially (captured, not pooled) before the replay. The chain list
  # itself is hoisted above the dispatch (cache exclusion shares it).
  _ran=(); _pool=(); _serial=()
  _cached_secs=(); _cached_out=()
  for _s in "${SECTIONS[@]}"; do
    if [[ ${#WANTED[@]} -eq 0 ]] || [[ " ${WANTED[*]} " == *" $_s "* ]]; then
      _ran+=("$_s")
      case " ${SERIAL_CHAIN[*]} " in
        *" $_s "*) ;; # chain member: collected below, in chain order
        *)
          _crow=""
          [[ "$_cache_enabled" -eq 1 ]] && _crow=$(_cache_lookup "$_s")
          if [[ -n "$_crow" ]]; then
            _cached_secs+=("$_s"); _cached_out+=("$_crow")
          else
            _pool+=("$_s")
          fi
          ;;
      esac
    fi
  done
  # chain members are collected in SERIAL_CHAIN execution order (the order
  # itself carries the cwd/fixture continuity), same WANTED gate as the pool
  for _s in "${SERIAL_CHAIN[@]}"; do
    if [[ ${#WANTED[@]} -eq 0 ]] || [[ " ${WANTED[*]} " == *" $_s "* ]]; then
      _serial+=("$_s")
    fi
  done
  # pool: N jobs at a time (bash 3.2 has no `wait -n` — poll-reap instead of
  # chunk-wait: before each spawn, idle only while the pool is full, so one
  # slow section no longer pins the whole chunk behind `wait`; 0.3s step is
  # scheduler noise vs section runtimes. Capture files + source-order replay
  # below are untouched.)
  if [[ ${#_pool[@]} -gt 0 ]]; then
    _new_repo_prewarm
    for _s in "${_pool[@]}"; do
      while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]]; do sleep 0.3; done
      ( _ps0=$(date +%s); NEW_REPO_SETUP_S=0; "section_${_s//-/_}"; echo $(( $(date +%s) - _ps0 )) > "${TMPDIR:-/tmp}/suite-${_s}.$$.sec"; echo "${NEW_REPO_SETUP_S:-0}" > "${TMPDIR:-/tmp}/suite-${_s}.$$.setup" ) >"${TMPDIR:-/tmp}/suite-${_s}.$$.out" 2>&1 &
    done
    wait
  fi
  # chain: serial execution inside ONE shared subshell — the members depend on
  # each other's shell state, not just cwd: T50/T51 want cwd=$ROOT, and
  # T5→T22a→T16 continue the CHG-500 fixture repo (cwd) plus the escapes
  # new_repo exports (e.g. AGENT_GUARD_ALLOW_INDEPENDENT, GATE-E86). One
  # subshell reproduces the serial branch's state-continuation semantics
  # exactly; per-section capture shape is unchanged and counters stay
  # subshell-local (the replay re-counts from the captured files).
  if [[ ${#_serial[@]} -gt 0 ]]; then
    (
      for _s in "${_serial[@]}"; do
        _ss0=$(date +%s); NEW_REPO_SETUP_S=0
        "section_${_s//-/_}" >"${TMPDIR:-/tmp}/suite-${_s}.$$.out" 2>&1
        echo $(( $(date +%s) - _ss0 )) > "${TMPDIR:-/tmp}/suite-${_s}.$$.sec"
        echo "${NEW_REPO_SETUP_S:-0}" > "${TMPDIR:-/tmp}/suite-${_s}.$$.setup"
      done
    )
  fi
  # replay in SECTIONS source order: non-FAIL lines → stdout, FAIL lines →
  # stderr; counters and failed_names/fail_lines re-exported from the captured
  # files (subshell-local report() tallies are discarded by design).
  for _s in "${_ran[@]}"; do
    _crow=""
    _ci=0
    while [[ "$_ci" -lt "${#_cached_secs[@]}" ]]; do
      if [[ "${_cached_secs[_ci]}" == "$_s" ]]; then _crow="${_cached_out[_ci]}"; break; fi
      _ci=$(( _ci + 1 ))
    done
    if [[ -n "$_crow" ]]; then
      _cp="${_crow% *}"; _cfail="${_crow#* }"
      pass=$(( pass + _cp )); fail=$(( fail + _cfail ))
      printf '[cached] %s (%s passed, %s failed)\n' "$_s" "$_cp" "$_cfail"
      _cache_hits=$(( _cache_hits + 1 ))
      _TIMINGS+=("${_s}:0:0")
      continue
    fi
    _sf="${TMPDIR:-/tmp}/suite-${_s}.$$.out"
    p=$(grep -cE "$_RE_OK" "$_sf")
    f=$(grep -cE "$_RE_FAIL" "$_sf")
    pass=$(( pass + p ))
    fail=$(( fail + f ))
    case " ${SERIAL_CHAIN[*]} " in
      *" $_s "*) ;;
      *) _cache_store "$_s" "$p" "$f" ;;
    esac
    while IFS= read -r _fl; do fail_lines+=("$_fl"); done < <(grep -hE "$_RE_FAIL" "$_sf")
    while IFS= read -r _fn; do failed_names+=("$_fn"); done < <(grep -hE "$_RE_FAIL" "$_sf" | sed -E 's/^FAIL (.*) \((expected exit|output does not match).*$/\1/')
    grep -vE "$_RE_FAIL" "$_sf"
    grep -E "$_RE_FAIL" "$_sf" >&2
    _se=$(cat "${TMPDIR:-/tmp}/suite-${_s}.$$.sec" 2>/dev/null || echo 0)
    _ss=$(cat "${TMPDIR:-/tmp}/suite-${_s}.$$.setup" 2>/dev/null || echo 0)
    printf '[done] %s %ss\n' "$_s" "$_se"
    if _sec_row_wanted "$_s"; then ledger_append sec "$_s" "$_se" "$_ss" none 0 "$(( p + f ))"; fi
    _TIMINGS+=("${_s}:${_se}:${_ss}")
    rm -f "$_sf" "${TMPDIR:-/tmp}/suite-${_s}.$$.sec" "${TMPDIR:-/tmp}/suite-${_s}.$$.setup"
  done
else
  # ---- serial branch: pre--j dispatcher, byte-identical (JOBS<=1) ---------
  for _s in "${SECTIONS[@]}"; do
    if [[ ${#WANTED[@]} -eq 0 ]] || [[ " ${WANTED[*]} " == *" $_s "* ]]; then
      _crow=""
      case " ${SERIAL_CHAIN[*]} " in
        *" $_s "*) ;;
        *) [[ "$_cache_enabled" -eq 1 ]] && _crow=$(_cache_lookup "$_s") ;;
      esac
      if [[ -n "$_crow" ]]; then
        printf '[cached] %s (%s passed, %s failed)\n' "$_s" "${_crow% *}" "${_crow#* }"
        pass=$(( pass + ${_crow% *} )); fail=$(( fail + ${_crow#* } ))
        _cache_hits=$(( _cache_hits + 1 ))
        _TIMINGS+=("${_s}:0:0")
        progress_write running
        continue
      fi
      # CHG-159 REQ-1471: new_repo exports escape vars into THIS shell; without a reset a
      # later section that never calls new_repo silently inherits them (hidden dependency).
      # SERIAL_CHAIN members keep the leak on purpose: they continue the previous fixture.
      case " ${SERIAL_CHAIN[*]} " in
        *" $_s "*) ;;
        *) unset AGENT_GUARD_ALLOW_INDEPENDENT AGENT_GUARD_ALLOW_NO_SHIFT AGENT_GUARD_ADAPT ;;
      esac
      _t0=$(date +%s); NEW_REPO_SETUP_S=0
      _p0=$pass; _f0=$fail
      "section_${_s//-/_}"
      _p=$(( pass - _p0 )); _f=$(( fail - _f0 ))
      case " ${SERIAL_CHAIN[*]} " in
        *" $_s "*) ;;
        *) _cache_store "$_s" "$_p" "$_f" ;;
      esac
      _el=$(( $(date +%s) - _t0 ))
      printf '[done] %s %ss\n' "$_s" "$_el"
      if _sec_row_wanted "$_s"; then ledger_append sec "$_s" "$_el" "${NEW_REPO_SETUP_S:-0}" none 0 "$(( _p + _f ))"; fi
      _TIMINGS+=("${_s}:${_el}:${NEW_REPO_SETUP_S:-0}")
      progress_write running
    fi
  done
fi

# v3.72.0 erratum (CHG-095, DES-1869): forced-red test seam. Setting
# AGENT_GUARD_SUITE_FORCE_RED=1 injects one guaranteed red case so red-path
# consumers (T57 archive drill, CI drills) can exercise the red path without a
# broken product. Test-only seam — real gate runs never set it.
[[ -n "${_NR_TMPL:-}" ]] && rm -rf "$_NR_TMPL" 2>/dev/null || true
if [[ "${AGENT_GUARD_SUITE_FORCE_RED:-0}" == "1" ]]; then
  report "T0 forced-red seam (AGENT_GUARD_SUITE_FORCE_RED)" 0 1
fi

# v3.95.0 (CHG-132, REQ-1324): cache tally — only the opt-in run prints it, so
# default-off output stays byte-identical for the byte-equality pins (T50 tail).
[[ "${_cache_enabled:-0}" -eq 1 ]] && printf 'section-cache: %d hit(s)\n' "$_cache_hits"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
printf 'wall-time: %ds\n' "$SECONDS"  # v3.65.0 (CHG-087, REQ-1047): constant tail wall-time; summary line format unchanged (update-assertion-count / audit A3 sed anchors)
# v3.90.1 (CHG-123, P0-2): final progress snapshot — status flips to done/failed
# so an external waiter can stop polling instead of blocking on a timeout.
if [[ "$fail" -eq 0 ]]; then progress_write done; else progress_write failed; fi
# Ledger aggregate row. v3.90.3 (CHG-125, FU-964): only an untargeted (full) run
# is tagged `run-full`; `-T` partial runs stay `run` and never feed the p50.
if [[ ${#WANTED[@]} -eq 0 ]]; then
  ledger_append run-full "${JOBS}" "$SECONDS" 0 none "$fail" "$(( pass + fail ))"
else
  ledger_append run "${JOBS}" "$SECONDS" 0 none "$fail" "$(( pass + fail ))"
fi
# v3.90.3 (CHG-125, FU-960): local portability scan (the real dual-implementation
# run happens in the CI OS matrix; this flag proves the assertion surface has no
# un-whitelisted BRE-only dialect left).
if [[ "${DUAL_RUN:-0}" == "1" ]]; then
  _pdial=$(grep -h -c '\\|' "$ROOT/tests/run-tests.sh" "$ROOT/tests/lib/"*.sh "$ROOT/tests/suites/"*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')
  _pwhite=$(sed -n '/^# PORTABILITY-WHITELIST-BEGIN/,/^# PORTABILITY-WHITELIST-END/p' "$ROOT/tests/run-tests.sh" "$ROOT/tests/suites/"*.sh 2>/dev/null | grep -c '\\|' || true)
  printf 'dual-run: dialect occurrences=%s whitelisted=%s unwhitelisted=%s\n' "${_pdial:-0}" "${_pwhite:-0}" "$(( ${_pdial:-0} - ${_pwhite:-0} ))"
fi
# v3.66.0 (CHG-088, REQ-1049): suite receipt. Only a FULL, unfiltered run may
# touch it — filtered (-T) / -l runs are not evidence about the whole suite.
# Green: write .agent-state/last-suite-receipt.json (local, gitignored, same
# trust level as session-started.json). Red: DELETE it — receipt semantics are
# "the most recent full run at this HEAD was green"; without the delete a stale
# green receipt could be trusted inside the freshness window after a red run.
# Best-effort by design: a write failure warns and never blocks the suite (the
# suite's own output remains the primary evidence; the receipt is an
# optimization consumed by update-assertion-count.sh, see REQ-1050).
# v3.79.0 (CHG-103, REQ-1142): the receipt additionally carries a
# "tree_fingerprint" (full-worktree snapshot via a throwaway git index, see
# scripts/lib-suite-tree-fingerprint.sh) — the trust semantics become
# "same HEAD + same tree fingerprint + freshness window" (consumer side,
# REQ-1143): a receipt from a different worktree state must never be trusted
# even at the same HEAD. Empty fingerprint (non-git repo / lib failure) is
# written as-is; the consumer treats empty/mismatched fingerprints as stale.
if [[ ${#WANTED[@]} -eq 0 && -n "$SUITE_HEAD" ]]; then
  if [[ "$fail" -eq 0 ]]; then
    _receipt="$SUITE_RECEIPT_PATH"
    mkdir -p "$(dirname "$SUITE_RECEIPT_PATH")" 2>/dev/null || true
    _tree_fp=""
    command -v suite_tree_fingerprint >/dev/null 2>&1 && _tree_fp=$(suite_tree_fingerprint "$ROOT")
    # v3.88.0 (CHG-116, REQ-1198): the receipt carries kind:"full" — consumers
    # (ci-summary --check) reject receipts without it, so a pre-v3.88 legacy
    # receipt or a quarantined partial receipt can never pose as full authority.
    if ! printf '{"kind":"full","head":"%s","tree_fingerprint":"%s","passed":%d,"failed":%d,"wall_time_s":%d,"generated_at":"%s"}\n' \
      "$SUITE_HEAD" "$_tree_fp" "$pass" "$fail" "$SECONDS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_receipt" 2>/dev/null; then
      printf 'warning: could not write suite receipt %s (non-fatal)\n' "$_receipt" >&2
    fi
  else
    rm -f "$SUITE_RECEIPT_PATH"
  fi
fi
# v3.88.0 (CHG-116, REQ-1197): auto partial runs quarantine their receipt to a
# SEPARATE file — last-suite-receipt.json is only ever written by a full run,
# so no consumer can mistake a subset result for full authority. Symmetric with
# the full receipt: green writes, red deletes. Best-effort, same as above.
if [[ "$AUTO" -eq 1 && ${#WANTED[@]} -gt 0 && -n "$SUITE_HEAD" ]]; then
  _partial="${AGENT_GUARD_SUITE_PARTIAL_PATH:-$ROOT/.agent-state/last-suite-partial.json}"
  if [[ "$fail" -eq 0 ]]; then
    mkdir -p "$(dirname "$_partial")" 2>/dev/null || true
    _tree_fp=""
    command -v suite_tree_fingerprint >/dev/null 2>&1 && _tree_fp=$(suite_tree_fingerprint "$ROOT")
    if ! printf '{"kind":"partial","head":"%s","tree_fingerprint":"%s","sections":"%s","passed":%d,"failed":%d,"wall_time_s":%d,"generated_at":"%s"}\n' \
      "$SUITE_HEAD" "$_tree_fp" "${WANTED[*]}" "$pass" "$fail" "$SECONDS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_partial" 2>/dev/null; then
      printf 'warning: could not write partial receipt %s (non-fatal)\n' "$_partial" >&2
    fi
  else
    rm -f "$_partial"
  fi
fi
# v3.88.0 (CHG-116, REQ-1196): every FULL run self-records full_suite +1 in the
# session stats (gitignored .agent-state; path overridable for tests). Filtered
# runs (including -T auto partials) never count — they are not a suite purchase
# — and neither does a verify-all receipt reuse (no runner invocation at all).
# Best-effort by design: a write failure warns and never changes the verdict.
if [[ ${#WANTED[@]} -eq 0 || "$_fake_full" == "1" ]]; then
  _stats="${AGENT_GUARD_SESSION_STATS_PATH:-$ROOT/.agent-state/session-tool-stats.json}"
  mkdir -p "$(dirname "$_stats")" 2>/dev/null || true
  _sf_n=0
  [[ -s "$_stats" ]] && _sf_n=$(sed -n 's/.*"full_suite":\([0-9]*\).*/\1/p' "$_stats" | tail -1)
  case "$_sf_n" in ''|*[!0-9]*) _sf_n=0 ;; esac
  _sf_tmp="${_stats}.$$"
  if [[ -s "$_stats" ]] && grep -q '"full_suite"' "$_stats" 2>/dev/null; then
    sed "s/\"full_suite\":[0-9]*/\"full_suite\":$((_sf_n + 1))/" "$_stats" > "$_sf_tmp" 2>/dev/null \
      && mv -f "$_sf_tmp" "$_stats" \
      || { rm -f "$_sf_tmp"; printf 'warning: could not update full_suite in %s (non-fatal)\n' "$_stats" >&2; }
  else
    printf '{"full_suite":%d}\n' $((_sf_n + 1)) > "$_sf_tmp" 2>/dev/null \
      && mv -f "$_sf_tmp" "$_stats" \
      || { rm -f "$_sf_tmp"; printf 'warning: could not create %s (non-fatal)\n' "$_stats" >&2; }
  fi
fi
# v3.72.0 erratum (CHG-095, DES-1869) + v3.76.0 (CHG-100, REQ-1122): red-run
# archive. ANY red run (fail > 0, filtered or full) overwrites
# .agent-state/last-suite-red.txt with the failed cases + FAIL lines — and, since
# v3.76.0, a FULL GREEN run DELETES it: the archive's semantics are "the most
# recent run's result", symmetric with the receipt above (which a red run
# deletes). A stale archive used to survive a green run and mislead diagnosis
# (live incident: an archive pinned T39/T50 while the suite was fully green).
# Filtered runs keep the archive untouched, exactly like the receipt (only a
# full run is evidence about the whole suite). Test-seam semantics otherwise
# unchanged: a re-run/CI drill aid, never a product-health signal. Note: the
# condition is intentionally unquoted ($fail) so the T51 TC-1126 pin literal
# stays unique.
if [[ ${#WANTED[@]} -eq 0 && "$fail" -eq 0 && -n "$SUITE_HEAD" ]]; then
  rm -f "$SUITE_RED_PATH"
fi
if [[ $fail -gt 0 ]]; then
  mkdir -p "$(dirname "$SUITE_RED_PATH")" 2>/dev/null || true
  {
    printf '# agent-guard suite red-run archive (test-seam semantics; not a product-health signal)\n'
    printf '# failed cases: %s\n' "${failed_names[*]}"
    if [[ ${#fail_lines[@]} -gt 0 ]]; then printf '%s\n' "${fail_lines[@]}"; fi
  } > "$SUITE_RED_PATH" 2>/dev/null \
    || printf 'warning: could not write red archive %s (non-fatal)\n' "$SUITE_RED_PATH" >&2
fi
if [[ "$fail" -gt 0 ]]; then
  printf 'failed cases: %s\n' "${failed_names[*]}" >&2
  exit 1
fi
exit 0
