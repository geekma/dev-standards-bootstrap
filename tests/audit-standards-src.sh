#!/usr/bin/env bash
# Standards 文档一致性机器审计（audit-docs-consistency）
#
# 背景：v3.4.0 收敛审计（三轮全维度遍历）发现的不变量，全部固化为机器断言。
# 目的：文档完整性由方法 + 机器保证，不由"再问一轮"保证（教训 6：反应式返工成本指数级）。
#
# 【适用范围分层——防误用】
#   通用层（随 Skill 复制到目标仓库）：resources/templates/agent-gate.sh、tests/run-tests.sh、
#                                     check-standards-compliance.sh——审计"被治理仓库的变更产物"。
#   规范源层（仅本仓库，禁止写入 SKILL 复制清单）：本脚本——审计"规范文本自身"的一致性。
#   目标仓库不需要本脚本：其文档一致性由门禁（gate/compliance）与规范落点保证，不复制规范正文。
#
# 【断言分区——防脚本腐烂】
#   PART A 永久结构不变量：版本链、清单同源、编号体系、防恒真、7+1 对齐、锚点存在性、
#          树↔磁盘、日志排序、关键词落点矩阵——跨规范版本有效，仅随结构变化维护
#          （v3.44.0：原 PART B 手写关键词快照就地转正入本区，脱版本化）。
#   PART B 版本派生不变量（v3.44.0 起取代逐版本手写 pin）：升级日志连续性断言全部由
#          resources/STANDARDS_CHANGELOG.md 派生——行数下限 + 严格降序 + 首版行==页脚版本；
#          规范升级不再手改本区。能力级 A26 pin 随能力落地追加、不随版本退役。
#
# 零依赖：bash 3.2+、grep、awk、diff。修改规范正文 / 模板 / README 后必须先跑通本脚本（SKILL.md 版本同步红线）。
#
# Usage: tests/audit-docs-consistency.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# v3.91.9 (CHG-127): snapshot the docs face BEFORE any fixture runs. A5 used to
# create <docs>/templates in the caller's cwd (bootstrap bug, fixed in the same
# batch), which flipped this flag to "present" mid-run and hard-failed A6a/b/c in
# a fresh checkout. Taking the snapshot first makes the SKIP decision honest.
A6_DOCS_ABSENT=0; [[ -d "$ROOT/docs" ]] || A6_DOCS_ABSENT=1
STD="$ROOT/resources/DEVELOPMENT_STANDARDS.md"
AGENTS="$ROOT/resources/AGENTS.md"
METH="$ROOT/resources/METHODOLOGY.md"
PLAY="$ROOT/resources/STAGE_PLAYBOOK.md"
DEV="$ROOT/resources/methodologies/development.md"
DS="$ROOT/resources/methodologies/data-structures.md"
STA="$ROOT/resources/methodologies/state-trigger-audit.md"
BFLOG="$ROOT/resources/templates/bugfix-log.md"
PIPE="$ROOT/resources/templates/github-artifact-pipeline.yml"
SKILL="$ROOT/SKILL.md"
RM_EN="$ROOT/README.md"
RM_ZH="$ROOT/README.zh-CN.md"
# v3.95.0 (CHG-132, REQ-1323): hoisted from the assertion blocks — read across
# blocks (and by the A10b/A10 tail), which run in separate subshells under
# AGENT_GUARD_AUDIT_PARALLEL=1. Pure path/pattern derivations, no side effects.
SLOG="$ROOT/resources/STANDARDS_CHANGELOG.md"
SLOG_ARCHIVE="$ROOT/resources/STANDARDS_CHANGELOG_ARCHIVE.md"
V=$(grep -oE '规范版本：v[0-9.]+' "$STD" | head -1 | grep -oE '[0-9.]+')
[[ -n "$V" ]] || V="UNKNOWN"
log_head=$(grep -m1 -oE '^\| v[0-9.]+' "$SLOG" 2>/dev/null | grep -oE '[0-9.]+')
GEN="$ROOT/scripts/update-assertion-count.sh"
GATE_TPL="$ROOT/resources/templates/agent-gate.sh"
STAGED_TPL="$ROOT/resources/templates/lib-gate-staged.sh"
COLD_TPL="$ROOT/resources/templates/lib-gate-cold.sh"
JLIB_TPL="$ROOT/resources/templates/lib-json.sh"
GATE_FILES=("$GATE_TPL" "$STAGED_TPL" "$COLD_TPL")
SUITE_FILES=("$ROOT/tests/run-tests.sh" "$ROOT/tests/lib/"*.sh "$ROOT/tests/suites/"*.sh)
GOV_WF="$ROOT/resources/templates/github-agent-governance.yml"
AUDIT_BASELINE="$ROOT/tests/.audit-baseline"
AUDIT_LAST="${TMPDIR:-/tmp}/audit-executed-count"
a17_at_least_1() { [[ "${1:-0}" -ge 1 ]] && echo 1 || echo 0; }
REPO_CHANGES="$ROOT/docs/changes"
REPO_BUGS="$ROOT/docs/bugs"
YML_TPL="$ROOT/resources/templates/agent-governance.yml"
GOV_YML_TPL="$ROOT/resources/templates/agent-governance.yml"
std_bytes=$(wc -c < "$STD" | tr -d ' ')
a56_suite="$ROOT/tests/run-tests.sh"

pass=0
soft_pass=0
fail=0
warn=0
failed_names=()

# CHG-121 (batch 0): assertion-NAME set baseline. A total-only baseline cannot
# tell "152 passed" from "a whole block never executed but the count matched"
# (BUG-004). Every executed assertion appends its name; A10b compares the set.
# Two files on purpose: the run-scoped file is filled while the audit executes,
# the last-complete file is REPLACED only at the end. A3 (early in the run) asks
# the generator to compare names — reading a half-filled run file would report
# drift against a complete baseline on every single run.
AUDIT_NAMES_RUN="${TMPDIR:-/tmp}/audit-run-names.$$"
AUDIT_NAMES_LAST="${TMPDIR:-/tmp}/audit-executed-names.$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
: > "$AUDIT_NAMES_RUN" 2>/dev/null || true
AUDIT_ASSERTIONS_BASELINE="$ROOT/tests/.audit-assertions"

# REQ-965 (v3.45.0): soft bucket — CI mode (AGENT_GUARD_AUDIT_SOFT=1) routes the
# numeric-closure assertions (A3 count / A3c sync / A10 baseline) here: a miss
# prints `warn`, never increments `fail`, and stays out of the A10 denominator.
# Local runs (env unset) keep the hard path. Every report_soft call site must be
# registered in the change 09 (soft-bucket abuse guard, MAINTAINER §5.3).
SOFT="${AGENT_GUARD_AUDIT_SOFT:-}"

report() { # name expected actual
  local name="$1" expected="$2" actual="$3"
  printf '%s\n' "$name" >> "$AUDIT_NAMES_RUN" 2>/dev/null || true
  if [[ "$expected" == "$actual" ]]; then
    pass=$(( pass + 1 ))
    printf 'ok   %s\n' "$name"
  else
    fail=$(( fail + 1 ))
    failed_names+=("$name")
    printf 'FAIL %s (expected %s, got %s)\n' "$name" "$expected" "$actual" >&2
  fi
}

# REQ-965: soft bucket reporter — a pass shares the hard counter but is tracked
# separately so it stays OUT of the A10 denominator (FU-910: A11s pass-path
# used to inflate pass+fail and flip A10 red exactly when DS went BELOW the
# soft threshold — the warn path masked this at v3.58.0 delivery).
report_soft() { # name expected actual
  local name="$1" expected="$2" actual="$3"
  printf '%s\n' "$name" >> "$AUDIT_NAMES_RUN" 2>/dev/null || true
  if [[ "$expected" == "$actual" ]]; then
    pass=$(( pass + 1 ))
    soft_pass=$(( soft_pass + 1 ))
    printf 'ok   %s\n' "$name"
  else
    warn=$(( warn + 1 ))
    printf 'warn %s (soft: expected %s, got %s)\n' "$name" "$expected" "$actual" >&2
  fi
}

# CHG-119: **保持 BRE**（不改方言）。实测：把本 helper 整体切到 ERE 会改变
# `^| GATE-E117 ` 这类「行首或字面」的交替语义（BRE 计数 1 → ERE 计数 227），
# 波及 22 条 at_least_unique 结构性 pin —— 改一处 helper、毁一族断言。
# 因此改为**逐条按需**改写：只把「依赖 GNU BRE 扩展（`\|` / `\(`）」的那几条
# 换成跨实现一致的写法（ERE 交替 / -F 固定串），其余 250+ 条调用语义零变化。
grep_count() { # file pattern -> count（basic grep = BRE）
  grep -c -- "$2" "$1" 2>/dev/null || true
}

# CHG-119: 字面串计数（-F）。当 pattern 的意图是**字面文本**（含 | [ ] 等正则元字符）
# 时，正则表达它是脆弱的：ERE 里 | 是交替、[ 需写成 [[]、字面竖线需写成 [[|]]，
# 而 [[|]] 在 BSD grep 的字符类解析里有歧义 → 同一 pattern 在不同实现下行为不同。
# -F 固定串匹配零方言歧义，三类 grep 行为完全一致。
grep_count_f() { # file literal -> count（fixed string）
  grep -cF -- "$2" "$1" 2>/dev/null || true
}

at_least_f() { # name min file literal（固定串；语义见 grep_count_f）
  local name="$1" min="$2" file="$3" literal="$4"
  local c
  c=$(grep_count_f "$file" "$literal")
  if [[ "$c" -ge "$min" ]]; then
    report "$name" ok ok
  else
    report "$name" ">=${min}" "$c"
  fi
}

# 至少出现一次（关键词落点矩阵用；出现多处于语义无害）
at_least() { # name min file pattern
  local name="$1" min="$2" file="$3" pattern="$4"
  local c
  c=$(grep_count "$file" "$pattern")
  if [[ "$c" -ge "$min" ]]; then
    report "$name" ok ok
  else
    report "$name" ">=${min}" "$c"
  fi
}

# CHG-119: ERE 版「至少出现一次」。**只给确实依赖 GNU BRE 扩展的断言用**——
# BRE 的交替 `\|` 与分组 `\(` 在 busybox/toybox 下不被支持（当字面竖线 → 计数恒 0
# → 假红）；ERE 的 `|` 与 `()` 是 POSIX 语法，三类 grep（GNU / BSD / toybox）行为一致。
# 反面教训：不要把 grep_count 整体切到 ERE —— 那会改变 `^| GATE-E117 ` 这类
# 「行首或字面」交替的语义（BRE 计数 1 → ERE 计数 227），一次改 helper 会毁 22 条
# at_least_unique 结构性 pin。故采用逐条按需改写。
at_least_e() { # name min file pattern（POSIX ERE）
  local name="$1" min="$2" file="$3" pattern="$4"
  local c
  c=$(grep -cE -- "$pattern" "$file" 2>/dev/null || true)
  if [[ "$c" -ge "$min" ]]; then
    report "$name" ok ok
  else
    report "$name" ">=${min}" "$c"
  fi
}

# v3.76.0 (CHG-100, REQ-1121, 候选 8)：结构性 pin 必须钉住**唯一**行。`at_least` 的
# >= 语义对"钉结构行"是恒真陷阱：同一字面若在别处也出现（注释/条件块/兄弟行），删掉
# 真结构行后计数仍 >=1，断言不会变红（CHG-099 实证：A46 曾钉「本次引入|既有存量」
# 字面，而该字面在模板条件注释里本就存在）。结构性 pin（整行锚定）一律用本 helper：
# 计数必须恰好 1——0 = 结构行被删/未落地，>1 = 没钉住具体结构，两者都是红。
at_least_unique() { # name file pattern -> exactly one matching line
  local name="$1" file="$2" pattern="$3" c
  c=$(grep_count "$file" "$pattern")
  report "$name" 1 "$c"
}

grep_count_files() { # pattern file... -> sum
  local pat="$1"; shift
  grep -h -c -- "$pat" "$@" 2>/dev/null | awk '{s+=$1} END{print s+0}'
}

grep_count_f_files() { # literal file... -> sum
  local lit="$1"; shift
  grep -h -cF -- "$lit" "$@" 2>/dev/null | awk '{s+=$1} END{print s+0}'
}

at_least_files() { # name min pattern file...
  local name="$1" min="$2" pat="$3"; shift 3
  local c
  c=$(grep_count_files "$pat" "$@")
  if [[ "$c" -ge "$min" ]]; then report "$name" ok ok; else report "$name" ">=${min}" "$c"; fi
}

at_least_f_files() { # name min literal file...
  local name="$1" min="$2" lit="$3"; shift 3
  local c
  c=$(grep_count_f_files "$lit" "$@")
  if [[ "$c" -ge "$min" ]]; then report "$name" ok ok; else report "$name" ">=${min}" "$c"; fi
}

# E160 note (CHG-158): the gate's numeric-drop check reads the first number on each -/+ line; after the table migration that is the assertion id (A39) vs the expected value 1, a false positive. No expected value was lowered. owner=geek007 expires 2026-12-31: make the check skip assertion ids.
run_audit_rules() {
  local _rf _res _op _exp _name _cnt _suites_spec
  _rf="${TMPDIR:-/tmp}/audit-rules.$$"
  cat > "$_rf"
  _suites_spec=$(printf '%s|' "${SUITE_FILES[@]}")
  _res=$(awk -F'\t' \
    -v p_root="$ROOT" \
    -v p_std="$STD" \
    -v p_agents="$AGENTS" \
    -v p_skill="$SKILL" \
    -v p_meth="$METH" \
    -v p_gate="$GATE_TPL" \
    -v p_staged="$STAGED_TPL" \
    -v p_cold="$COLD_TPL" \
    -v p_audit="$ROOT/resources/templates/audit-docs-consistency.sh" \
    -v p_stamp="$ROOT/resources/templates/stamp-provenance.sh" \
    -v p_hook="$ROOT/resources/templates/install-hook-adapter.sh" \
    -v p_ciadapt="$ROOT/resources/templates/install-ci-adapter.sh" \
    -v p_bs="$ROOT/scripts/bootstrap.sh" \
    -v p_inst="$ROOT/scripts/install.sh" \
    -v p_sg="$ROOT/resources/templates/session-gate.sh" \
    -v p_yml="$YML_TPL" \
    -v p_govwf="$GOV_WF" \
    -v p_cr="$ROOT/resources/CLAUSE_REGISTRY.md" \
    -v p_ri="$ROOT/resources/methodologies/review-intelligence.md" \
    -v p_run="$ROOT/tests/run-tests.sh" \
    -v p_rmen="$RM_EN" \
    -v p_rmzh="$RM_ZH" \
    -v p_slog="$SLOG" \
    -v p_suites="$_suites_spec" \
    -v p_gate_hw="${GATE_TPL}|${STAGED_TPL}" \
    -v p_gate_all="${GATE_TPL}|${STAGED_TPL}|${COLD_TPL}" '
    BEGIN {
      map["@STD"] = p_std; map["@AGENTS"] = p_agents; map["@SKILL"] = p_skill
      map["@METH"] = p_meth; map["@GATE"] = p_gate; map["@STAGED"] = p_staged
      map["@COLD"] = p_cold; map["@AUDIT"] = p_audit; map["@STAMP"] = p_stamp
      map["@HOOK"] = p_hook; map["@CIADAPT"] = p_ciadapt; map["@BS"] = p_bs
      map["@INST"] = p_inst; map["@SG"] = p_sg; map["@YML"] = p_yml
      map["@GOV_WF"] = p_govwf; map["@CR"] = p_cr; map["@RI"] = p_ri
      map["@RUN"] = p_run; map["@RM_EN"] = p_rmen; map["@RM_ZH"] = p_rmzh
      map["@SLOG"] = p_slog; map["@SUITES"] = p_suites
      map["@GATE_HW"] = p_gate_hw; map["@GATE_ALL"] = p_gate_all
      nrules = 0; nfiles = 0
    }
    {
      if ($0 == "" || substr($0, 1, 1) == "#") next
      nrules++
      r_op[nrules] = $2
      r_exp[nrules] = $3
      r_name[nrules] = $4
      r_pat[nrules] = $5
      if ($1 in map) fspec = map[$1]
      else if (substr($1, 1, 6) == "@ROOT/") fspec = p_root "/" substr($1, 7)
      else fspec = $1
      nf = split(fspec, fa, "|")
      for (j = 1; j <= nf; j++) {
        if (fa[j] == "") continue
        f = fa[j]
        if (!(f in f_seen)) { f_seen[f] = 1; nfiles++; files[nfiles] = f }
        fc[f]++
        fr[f, fc[f]] = nrules
      }
    }
    END {
      for (fi = 1; fi <= nfiles; fi++) {
        f = files[fi]
        rc = fc[f]
        while ((getline ln < f) > 0) {
          for (k = 1; k <= rc; k++) {
            ri = fr[f, k]
            op = r_op[ri]
            pat = r_pat[ri]
            if (substr(op, 1, 2) == "F_") {
              if (index(ln, pat) > 0) counts[ri]++
            } else {
              if (ln ~ pat) counts[ri]++
            }
          }
        }
        close(f)
      }
      for (i = 1; i <= nrules; i++) {
        printf "%s\t%s\t%s\t%d\n", r_op[i], r_exp[i], r_name[i], counts[i] + 0
      }
    }
  ' "$_rf")
  rm -f "$_rf"
  while IFS=$'\t' read -r _op _exp _name _cnt; do
    [[ -n "$_name" ]] || continue
    case "$_op" in
      F_GE|E_GE)
        if [[ "$_cnt" -ge "$_exp" ]]; then report "$_name" ok ok
        else report "$_name" ">=${_exp}" "$_cnt"; fi ;;
      F_NZ|E_NZ)
        report "$_name" "$_exp" "$([[ "$_cnt" -ge 1 ]] && echo 1 || echo 0)" ;;
      F_EQ|E_EQ)
        report "$_name" "$_exp" "$_cnt" ;;
    esac
  done <<< "$_res"
}

# ===================== PART A：永久结构不变量（跨版本有效） =====================
# v3.95.0 (CHG-132, REQ-1323): the assertion mass below is wrapped into four
# blocks (audit_block_a..d). Serial mode (default) calls them in order in this
# shell — byte-identical to the pre-split script. AGENT_GUARD_AUDIT_PARALLEL=1
# runs each block as a background subshell with per-block stdout/stderr/counter
# capture; the parent replays captures in ORIGINAL block order (ok → stdout,
# FAIL/warn → stderr) and sums the per-block counters, so green runs stay
# byte-identical (red runs group stderr per block). A10b/A10 stay after the
# blocks in EVERY mode: they compare the FULL executed name set/count.
# report() keeps appending assertion names to AUDIT_NAMES_RUN from the
# subshells (single small appends; the A10b comparison is set-based).
AUDIT_BLOCKS=(a b c d)
audit_parallel() {
  _ap_dir="${TMPDIR:-/tmp}/audit-par.$$"
  mkdir -p "$_ap_dir" 2>/dev/null || return 1
  local _s
  for _s in "${AUDIT_BLOCKS[@]}"; do
    while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "${AGENT_GUARD_AUDIT_JOBS:-4}" ]]; do sleep 0.2; done
    ( "audit_block_$_s" >"$_ap_dir/$_s.out" 2>"$_ap_dir/$_s.err"; \
      printf '%s %s %s %s\n' "$pass" "$fail" "$soft_pass" "$warn" >"$_ap_dir/$_s.stats" ) &
  done
  wait
  for _s in "${AUDIT_BLOCKS[@]}"; do
    cat "$_ap_dir/$_s.out"
    cat "$_ap_dir/$_s.err" >&2
    if [[ -f "$_ap_dir/$_s.stats" ]]; then
      read -r _ap _af _asf _aw < "$_ap_dir/$_s.stats"
      pass=$(( pass + _ap )); fail=$(( fail + _af )); soft_pass=$(( soft_pass + _asf )); warn=$(( warn + _aw ))
    fi
  done
  rm -rf "$_ap_dir"
  return 0
}
audit_block_a() {

# ---------- 版本链（单一权威：规范页脚） ----------
# SLOG/V/log_head hoisted to the setup region (REQ-1323 cross-block reads).

for f in "$AGENTS" "$METH"; do
  report "version footer synced: $(basename "$f")" 1 "$(grep_count "$f" "当前对应规范版本：v${V}_")"
done

# 方法论层页脚：动态遍历 resources/methodologies/*.md，禁止写静态清单。
#   CHG-004 / BUG-002：原实现为静态清单 "$AGENTS" "$METH" "$DEV" "$DS"——**漏了
#   state-trigger-audit.md**（该文件也确实没有页脚，双缺）。根因与 BUG-001 同族：
#   "方法论层版本页脚已同步"的语义覆盖面是"该目录下全部 .md"，而静态清单窄于语义
#   → 新增方法论文件不会自动纳入校验，规范升级时该文件静默滞后。
#   改为动态遍历后新增文件自动纳入；再加一条聚合断言防"遍历集本身漏文件"复发。
for m in $(ls "$ROOT/resources/methodologies" | grep '\.md$' | sort); do
  report "version footer synced: methodologies/$m" 1 \
    "$(grep_count "$ROOT/resources/methodologies/$m" "当前对应规范版本：v${V}_")"
done
# fail-closed：目录为空/文件数异常少时不得静默通过
m_all=$(ls "$ROOT"/resources/methodologies/*.md 2>/dev/null | wc -l | tr -d ' ')
m_ok=$(grep -l "当前对应规范版本：v${V}_" "$ROOT"/resources/methodologies/*.md 2>/dev/null | wc -l | tr -d ' ')
m_min=0; [[ "$m_all" -ge 3 ]] && m_min=1
report "methodology layer file count >= 3 (fail-closed)" 1 "$m_min"
report "methodology layer footer coverage == file count" "$m_all" "$m_ok"

report "version badge zh"            1 "$(grep_count "$RM_ZH" "规范版本-v${V}-")"
report "version badge en"            1 "$(grep_count "$RM_EN" "Standards-v${V}-")"
report "version footer zh"           1 "$(grep_count "$RM_ZH" "规范版本：\*\* v${V}")"
report "version footer en"           1 "$(grep_count "$RM_EN" "Standards Version:\*\* v${V}")"
report "version tree zh"             1 "$(grep_count "$RM_ZH" "完整规范文档 v${V}")"
report "version tree en"             1 "$(grep_count "$RM_EN" "Full standards document v${V}")"
report "skill carried version"       1 "$(grep_count "$SKILL" "当前携带版本 v${V}")"

# SKILL.md 版本可见性三载体（用户需求："在 skill 里就能看到是不是最新版"）。
# 平台事实：SKILL.md frontmatter 无 version 字段、/skills 面板只展示 name + description
# → 只写 frontmatter 用户看不见；只写正文则技能列表里看不见。故版本必须同时落在
# ①frontmatter version ②description 尾注 ③正文顶部横幅。三处任一漂移（升级规范时漏改）
# 即红——与"版本页脚已同步"同族：声称的覆盖面必须等于校验的覆盖面。
report "skill frontmatter version == footer version" "$V" \
  "$(grep -m1 -oE '^version: [0-9.]+' "$SKILL" | grep -oE '[0-9.]+')"
report "skill description carries carried version" 1 "$(grep_count "$SKILL" "携带规范版本 v${V}")"
report "skill body version banner present" 1 "$(grep_count "$SKILL" "当前携带版本：v${V}")"
# CHG-050 勘误：plugin.json/marketplace.json 版本必须与页脚同源（MAINTAINER §1 明文，
# 实测漂移 3.37.1 四个版本无人发现——存在性断言（A24）查不出版本漂移）
report "plugin manifests version == footer version" "$V" \
  "$(grep -m1 -oE '"version": "[0-9.]+"' "$ROOT/.claude-plugin/plugin.json" | grep -oE '[0-9.]+')"
report "marketplace manifest version == footer version" "$V" \
  "$(grep -m1 -oE '"version": "[0-9.]+"' "$ROOT/.claude-plugin/marketplace.json" | grep -oE '[0-9.]+')"

# 升级日志（v3.8.0 起外置 STANDARDS_CHANGELOG.md，CHG-005）：新文件存在、
# 新条目置顶且首行版本 == 页脚版本、规范正文不再内嵌历史日志行
report "standards changelog file exists and non-empty" 1 "$([[ -s "$SLOG" ]] && echo 1 || echo 0)"
report "standards changelog newest row == footer version" "$V" "$log_head"
at_least "standards §2.14 rule points to STANDARDS_CHANGELOG" 1 "$STD" 'STANDARDS_CHANGELOG.md'
std_log_rows=$(grep -cE '^\| v[0-9]+\.[0-9]+\.[0-9]+ \| 20[0-9]{2}-' "$STD")
report "standards body carries no historical upgrade-log rows" 0 "$std_log_rows"

# ===================== PART A（续）：关键词落点矩阵（永久不变量；v3.44.0 由版本快照转正，脱版本化） =====================

# ---------- 关键词矩阵：状态/触发链路审计 + 同族推演（v3.4.0 引入） ----------
for f in "$STD" "$METH" "$STA" "$BFLOG" "$AGENTS" "$RM_ZH"; do
  at_least "keyword 同族推演 in $(basename "$f")" 1 "$f" "同族推演"
done
at_least "keyword same-family scan in README en" 1 "$RM_EN" "same-family"
for f in "$STD" "$METH" "$STA" "$AGENTS"; do
  at_least "keyword 隐式链路三向遍历 in $(basename "$f")" 1 "$f" "隐式链路三向遍历"
done
for f in "$SKILL" "$RM_ZH" "$RM_EN" "$AGENTS" "$PIPE" "$STD" "$METH"; do
  at_least "route state-trigger-audit in $(basename "$f")" 1 "$f" "state-trigger-audit"
done

# ---------- 关键词矩阵：占位符拒绝 + L3 释放授权 + commit-msg 归因闸门（v3.5.0 引入） ----------
for f in "$STD" "$RM_EN" "$RM_ZH"; do
  at_least "keyword release_authorized_by in $(basename "$f")" 1 "$f" "release_authorized_by"
done
for f in "$SKILL" "$RM_EN" "$RM_ZH"; do
  at_least "keyword commit-msg attribution gate in $(basename "$f")" 1 "$f" "commit-msg"
done

# ---------- 关键词矩阵：一次变更一组文档 + 缺陷文档组（v3.6.0 引入） ----------
for f in "$STD" "$RM_EN" "$RM_ZH"; do
  at_least "keyword 一次变更一组文档 in $(basename "$f")" 1 "$f" "一次变更一组文档"
done
for f in "$STD" "$BFLOG" "$SKILL"; do
  at_least "keyword 缺陷文档组 in $(basename "$f")" 1 "$f" "缺陷文档组"
done
TPL="$ROOT/resources/templates"
report "governance-state template declares empty bug_ref" 1 "$(grep_count "$TPL/governance-state.json" '"bug_ref": ""')"
report "agent-gate names missing defect document" 1 "$(grep_count "$STAGED_TPL" "missing defect document")"
tpl6=0
for t in bug-diagnosis.md bug-impact.md bug-test-plan.md bug-matrix.md bug-config.md bug-tasks.md; do
  [[ -s "$TPL/$t" ]] && tpl6=$(( tpl6 + 1 ))
done
report "bug doc-set templates present (6 files)" 6 "$tpl6"

# ---------- 阶段输入契约：交付触发点 / 背景输入 全覆盖（v3.91.6，CHG-127） ----------
# PMP 要求下阶段输入=上阶段产出：模板自带标记，gate 再按阶段机检引用面。
# 聚合断言（总数 == 带标记数）比逐个文件名断言更抗模板增删，且基线数字由生成器同步。
tpl_md_total=$(find "$TPL" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
tpl_md_marked=$(grep -rl '交付触发点：' "$TPL" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')
report "all template md files declare 交付触发点 (CHG-127)" "$tpl_md_total" "$tpl_md_marked"
tpl_bg_total=$(( $(find "$TPL/entry" "$TPL/project" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ') \
  + $(find "$TPL" -maxdepth 1 -name 'bug-*.md' -type f 2>/dev/null | wc -l | tr -d ' ') ))
tpl_bg_marked=$( { grep -rl '背景输入：' "$TPL/entry" "$TPL/project" --include='*.md' 2>/dev/null || true; grep -l '背景输入：' "$TPL"/bug-*.md 2>/dev/null || true; } | wc -l | tr -d ' ')
report "stage/project/bug templates declare 背景输入 (CHG-127)" "$tpl_bg_total" "$tpl_bg_marked"
run_audit_rules <<'EOF'
@STD	F_GE	1	DS carries the stage input contract (CHG-127)	阶段输入契约
@STAGED	F_GE	1	agent-gate enforces the marker contract (CHG-127)	delivery_markers_ok
@STAGED	F_GE	1	scaffold emits delivery markers (CHG-127)	交付触发点：变更立项时
@STD	F_GE	1	keyword 最低文档集八类映射 in DEVELOPMENT_STANDARDS	最低文档集八类映射
@RM_EN	F_GE	1	keyword eight-category in README en	eight-category
@STD	F_GE	1	keyword 六件套 in DEVELOPMENT_STANDARDS	六件套
@SKILL	F_GE	1	keyword 六件套 in SKILL	六件套
@STD	F_GE	1	keyword 04.5-coding-record in DEVELOPMENT_STANDARDS	04.5-coding-record
@RM_ZH	F_GE	1	keyword 04.5-coding-record in README zh	04.5-coding-record
@RM_EN	F_GE	1	keyword 04.5-coding-record in README en	04.5-coding-record
@SKILL	F_GE	1	keyword 04.5-coding-record in SKILL	04.5-coding-record
@STAGED	F_GE	1	keyword 04.5-coding-record in agent-gate	04.5-coding-record
@SUITES	F_GE	1	keyword 04.5-coding-record in run-tests	04.5-coding-record
@SKILL	F_GE	1	keyword bug-matrix.md in SKILL	bug-matrix.md
@SKILL	F_GE	1	keyword coding-record template in SKILL	coding-record.md
@STAGED	F_GE	1	keyword 06-tasks in agent-gate	06-tasks
EOF

}

# ===================== PART A（续） =====================
audit_block_b() {
# ---------- §3 清单唯一性（CHG-005：v3.8.0 起 §3 为唯一权威，§4 只作归档引用） ----------
# 注意：标准全文的 ```markdown fence 数量随结构变化，必须按章节标题锚定，
# 禁止按 fence 序号取（序号法曾取到 §1.2/§2.6.3 两个空清单 → 恒真 IDENTICAL，R-D 轮修正；
# v3.8.0 起 §4 归档节改为"逐字复制 §3"引用式，旧"§3↔§4 标签完全一致"断言会被双清单复活绕过，
# 故反转为三条：§3 提取非空（防恒真）、§3 与 §4 标签集不相等（防重复清单复活）、§4 含引用锚点）。
awk '/^## 3\. 变更执行全流程检查清单/{w=1} w && /^```markdown$/{f=1; w=0; next} f==1{ if(/^```$/){exit} print }' "$STD" | grep -oE '【[^】]+】' | sort > /tmp/audit_s3.$$
awk '/^## 4\. Changelog/{w=1} /^## 5\. /{exit} w{print}' "$STD" | grep -oE '【[^】]+】' | sort > /tmp/audit_s4.$$
n3=$(wc -l < /tmp/audit_s3.$$ | tr -d ' ')
report "section3 checklist extraction non-empty (防恒真空转)" 1 "$([[ "$n3" -gt 0 ]] && echo 1 || echo 0)"
if diff -q /tmp/audit_s3.$$ /tmp/audit_s4.$$ >/dev/null 2>&1; then r=0; else r=1; fi
report "section3 is the sole authority (section4 carries no duplicate checklist)" 1 "$r"
report "section4 archive section references §3 verbatim-copy rule" 1 \
  "$(awk '/^## 4\. Changelog/{w=1} /^## 5\. /{exit} w{print}' "$STD" | grep -cE '逐字复制 §3')"
rm -f /tmp/audit_s3.$$ /tmp/audit_s4.$$

# ---------- 双 README 结构一致性（CHG-005 / P2-6：正文靠手工同步，至少结构须机器互证） ----------
#   ① 二级标题序列一致（EN/ZH 逐条对应）；② "仓库结构"树块逐行一致（文件名与树线同构，
#   语言差异只在注释列）——树块锚定：从 'dev-standards-bootstrap/' 根行到收尾 fence
#   （不能按 fence 序号取：README 还有 bash fence，序号法曾取空 → 防恒真断言拦截）。
tree_block_lines() { # $1 = readme → 树块规范化行数（去注释、去尾空白）
  awk 'f==1{ if(/^```$/){exit} print; next } /^dev-standards-bootstrap\/$/{f=1; print}' "$1" \
    | sed -e 's/#.*$//' -e 's/[[:space:]]*$//' | grep -c .
}
h2_en=$(grep -c '^## ' "$RM_EN")
h2_zh=$(grep -c '^## ' "$RM_ZH")
report "README h2 heading count identical (en vs zh)" "$h2_en" "$h2_zh"
tree_en=$(tree_block_lines "$RM_EN")
tree_zh=$(tree_block_lines "$RM_ZH")
report "README structure-tree line count identical (en vs zh)" "$tree_en" "$tree_zh"
report "README structure-tree extraction non-empty (防恒真空转)" 1 "$([[ "$tree_en" -gt 10 ]] && echo 1 || echo 0)"

# ---------- A7d 阶段验收 A 层命令速查表（CHG-006：命令唯一落点须机器守护） ----------
at_least "stage A-layer command quickref table present" 1 "$STD" '阶段验收 A 层命令速查表'
at_least "quickref carries stage-1 command anchor" 1 "$STD" "grep -c 'REQ-' docs/<feature>/01-spec.md"
at_least "quickref carries stage-6 command anchor" 1 "$STD" 'BUG-\[0-9\]'

# ---------- 编号体系收录（R-C 轮） ----------
declared=$(grep -oE '以下 [0-9]+ 种前缀' "$STD" | grep -oE '[0-9]+')
rows=$(awk '/^### 1.1/,/^### 1.2/' "$STD" | grep -cE '^\| \*\*')
report "1.1 declared prefix count == table rows" "$rows" "$declared"

all10="REQ/DES/TASK/CHG/TC/SC/BUG/CFG/DB/FU"
report "1.2 numbering rule lists all prefixes"      1 "$(grep_count "$STD" "各类编号（${all10}）")"
report "1.2 order checklist row includes SC"        1 "$(grep -cE '^\| SC/BUG/CFG/DB/FU' "$STD")"
report "2.16.4 self-check includes SC"              1 "$(grep_count "$STD" "是否所有编号（${all10}）")"

# ---------- 占位符 vs A 层断言（防恒真统计，R-A 轮） ----------
report "bugfix-log placeholder not matched by ^### BUG-[0-9]" 0 "$(grep -cE '^### BUG-[0-9]' "$BFLOG" 2>/dev/null || true)"

# ---------- 骨架 vs A 层关键词（防空骨架绕过） ----------
report "pipeline 02 skeleton free of A-layer keyword" 0 "$(grep_count "$PIPE" "隐式链路三向遍历")"

# ---------- 00 管线件落点（R-A 轮） ----------
report "2.15 table has 00-intent row"        1 "$(grep_count "$STD" '`00-intent.md`（变更管线入口，§2.17）')"
report "2.15 table has 00-governance row"    1 "$(grep_count "$STD" '`00-governance.json`（§2.17）')"
report "2.16.5 table has pipeline-entry row" 1 "$(grep_count "$STD" '管线入口（§2.17）')"
report "2.17 governance definition present"  1 "$(grep_count "$STD" '管线治理声明')"
at_least "2.17 dual-root convention present" 1 "$STD" '产物目录双轨约定'
report "mainline starts with 00 files+begin" 1 "$(grep_count "$STD" '先落 00-intent.md / 00-governance.json / 00.5-communication.md（§2.17，变更目录）')"

# ---------- bugfix 双登记 9+1 项对齐（R-A 轮；v3.6.0 缺陷文档组 + v3.7.0 矩阵/配置/任务拆分项） ----------
chg_backfill=$(awk '/^#### Bug 修复回填清单/,/^#### [^B]/' "$STD" | grep -cE '^[[:space:]]*[-*][[:space:]]+\[[ x]\]')
report "DS section4 carries no Bug backfill copy (single source in entry/09)" 0 "$chg_backfill"
log_line=$(grep -E '^- \[ \] 01-spec' "$BFLOG" | head -1)
log_items=$(printf '%s' "$log_line" | grep -oE '\[ \]' | wc -l | tr -d ' ')
report "log-side backfill checklist == 9 items" 9 "$log_items"

# ---------- 锚点章节存在性（子代理轮） ----------
for h in '^## 0.5 ' '^## 2.6 ' '^## 2.7 ' '^## 2.8 ' '^## 2.9 ' '^## 2.11 ' '^#### 2.17.1' '^## 4. Changelog'; do
  report "standards heading exists: $h" 1 "$(grep -cE "$h" "$STD")"
done

# ---------- README 树 ↔ 磁盘（子代理轮） ----------
for m in $(ls "$ROOT/resources/methodologies" | grep '\.md$'); do
  at_least "README en mentions methodologies/$m" 1 "$RM_EN" "$m"
  at_least "README zh mentions methodologies/$m" 1 "$RM_ZH" "$m"
done

# ---------- README 树 ↔ 磁盘：resources/templates/（CHG-004 / BUG-002） ----------
#   本脚本头部注释早已声称 PART A 含"树↔磁盘"，但原实现**只校验 methodologies/ 的
#   README 提及、未校验 templates/** → 双 README 的"仓库结构"树对称漏列 7 个模板
#   （bug-diagnosis/impact/test-plan/matrix/config/tasks.md + coding-record.md）而长期
#   无人发现。语义：README 树必须列出该目录下全部文件——检查只覆盖一半 = 又一处
#   "检查的覆盖面窄于它声称的语义"（与 BUG-001 同族）。
#   解析要点：ZH README 用中文顿号「、」并列、EN 用「, 」——两种分隔符都要覆盖
#   （首版脚本只切逗号，误判 ZH 漏 3 个 Git Hook 文件；本轮实测踩过，故此处显式处理）。
tree_names() { # $1 = readme → 输出树中 templates/ 段的文件名（去重排序）
  awk '/└── templates\//{f=1;next} f && /^```/{exit} f{
    line=$0
    sub(/#.*$/,"",line)               # 去注释
    gsub(/[、,]/," ",line)            # 归一化分隔符（逐字节替换，对 ASCII 文件名无害）
    sub(/^[^A-Za-z0-9_.]*/,"",line)   # 去缩进与树线前缀
    n=split(line,a," ")
    for(i=1;i<=n;i++) if(a[i] ~ /^[A-Za-z0-9_.-]+$/) print a[i]
  }' "$1" | sort -u
}
tmpl_disk=$(ls "$ROOT/resources/templates" | sort)
for rmf in "$RM_EN" "$RM_ZH"; do
  t_miss=$(comm -23 <(printf '%s\n' "$tmpl_disk") <(tree_names "$rmf") | tr '\n' ' ')
  t_extra=$(comm -13 <(printf '%s\n' "$tmpl_disk") <(tree_names "$rmf") | tr '\n' ' ')
  [[ -z "$t_miss" ]] || echo "audit: $(basename "$rmf") tree missing templates: $t_miss" >&2
  [[ -z "$t_extra" ]] || echo "audit: $(basename "$rmf") tree lists non-existent templates: $t_extra" >&2
  report "README $(basename "$rmf") tree covers all resources/templates" 0 "$(printf '%s' "$t_miss" | grep -c . || true)"
  report "README $(basename "$rmf") tree has no phantom template" 0 "$(printf '%s' "$t_extra" | grep -c . || true)"
done

# ---------- 06.5 / 06-delivery-summary 模板存在性（CHG-004 / BUG-002） ----------
#   §1.1「最低文档集八类」含 06.5-deployment-config.md；06-delivery-summary.md 是
#   §2.5 阶段 9.5 的必含产物（**不在八类内**，落 §1.1 编号主表「遗留项 (Follow-up)」行）。
#   两者此前都无模板、门禁也不校验 → 目标仓库无处可复制、漏项无人拦。
#   本断言保证"有模板可复制"；"门禁必检"由 agent-gate.sh 的 stop 分支承担。
for t in 06.5-deployment-config.md 06-delivery-summary.md; do
  report "template exists and non-empty: $t" 1 "$([[ -s "$ROOT/resources/templates/$t" ]] && echo 1 || echo 0)"
done

# ---------- 阶段 6/8 专项与 §5 拦截 ----------
report "stage-8 defect-fix special check" 1 "$(grep_count "$STD" '缺陷修复类 CHG 专项')"
# (v3.45.0 REQ-966 退役 "section5 same-family interceptor"：与关键词矩阵同族推演循环
#  同不变量双形状——不变量仍由矩阵循环承载)

# ---------- METHODOLOGY 分级行 ----------
# (v3.45.0 REQ-966 退役 "methodology 3.2 implicit-link row"：与关键词矩阵（隐式链路/
#  同族推演循环）在 METH 落点重叠；3.6/4 行留待 MAINTAINER §5.3 生命周期下一轮评审)
report "methodology 3.6 same-family row"   1 "$(grep_count "$METH" '同族推演（同根因旁路扫描）')"
report "methodology 4 conditional note"    1 "$(grep_count "$METH" '条件命中：涉及状态/触发/事件链路时必须')"

# ---------- STAGE_PLAYBOOK 下沉载体（v3.61.0 FU-911） ----------
# DS §2.5/§2.16.6 叙事细则迁入 playbook（DS 原位留指针）；断言防"树↔磁盘/指针↔载体"漂移
at_least "playbook file carries mirror sections" 1 "$PLAY" '## 2.16.6·防漏红线细则'
at_least "playbook file carries stage-2 mirror"  1 "$PLAY" '## 2.5 阶段 2·三维影响详述'
at_least "DS pointer to playbook present"        1 "$STD"  'resources/STAGE_PLAYBOOK.md'

# ---------- 审计脚本自身接线（本轮） ----------
at_least "SKILL.md wires audit script"  1 "$SKILL" "audit-docs-consistency"
at_least "README en tree lists audit"   1 "$RM_EN" "audit-docs-consistency"
at_least "README zh tree lists audit"   1 "$RM_ZH" "audit-docs-consistency"

# ---------- 通用层防复发断言（源自本项目八轮漏检类别，防同类问题在目标仓库复现） ----------

# A1 管线派发骨架集必须覆盖 gate begin 必检集差集（01/00-* 为管线入口件除外）——
#    防"spec 合入后 begin 因缺骨架必失败"复发（v3.4.0 ⑬：03.5 曾缺失）
GATE_REQ_LINE=$(grep -m1 'required_docs=(' "$ROOT/resources/templates/agent-gate.sh")
pipe_missing=0
for f in 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md; do
  grep -q "$f" <<< "$GATE_REQ_LINE" || { echo "audit: gate required_docs changed, update A1 list" >&2; pipe_missing=$(( pipe_missing + 1 )); continue; }
  grep -q "docs/changes/\$id/$f" "$PIPE" || pipe_missing=$(( pipe_missing + 1 ))
done
report "A1 pipeline scaffolds every gate-required artifact (minus entry files)" 0 "$pipe_missing"

# A2 compliance.sh 与 agent-gate 的"代码扩展名"口径必须一致——
#    防 6-vs-20 种后缀分叉复发（v3.4.0 ⑫：14 种后缀逃过文档检查）
gate_ext=$(grep -E '\\\.\(c\|' "$ROOT/resources/templates/agent-gate.sh" | head -1 | sed -E 's/.*\\\.\(([^)]+)\)\$.*/\1/')
ci_ext=$(grep -E '\\\.\(c\|' "$ROOT/resources/templates/check-standards-compliance.sh" | head -1 | sed -E 's/.*\\\.\(([^)]+)\)\$.*/\1/')
report "A2 code-extension list identical in gate and compliance.sh" "$gate_ext" "$ci_ext"

# A3 README 声称的 golden-case 断言数必须与生成器**同源**（CHG-019：静态调用点计数
# 与运行期实出结构性死锁——同链双调用与循环站点使两口径恒差 3，README 取任一值都有
# 一侧红）。口径唯一权威 = 生成器（运行期实出 `N passed`，红套件拒同步）；本断言只
# 做"声称集合单一一致"与"== 生成器口径"两件事，重算逻辑不在此复制（防第三口径）。
#    防"47→52→55 多处数字漂移"复发（本项目实际发生过）
#
#    CHG-003 收紧取值正则，同时治两个方向的缺陷：
#    ① 漏匹配（危险方向）：旧正则 '[0-9]+ (assertions|项断言|golden-case 断言|Golden-Case 断言)'
#       要求数字后紧跟空格 + 关键词，于是 '107 golden-case assertions'（数字后跟 golden-case）
#       不匹配 → claims 只剩 {118} → A3 误判"单一一致数字"通过。该盲区曾让双 README 同时残留
#       107 与 118、而真值为 125，且这条 FAIL 在 main 上长期无人察觉。
#    ② 假阳性（阻断方向）：若仅放宽为 '[0-9]+[^0-9]{0,20}'，版本号尾数会被卷进来——实测
#       '见 §2.17.4 防恒真断言' 会命中 '4 防恒真断言'。
#    故最终形态：(^|[^0-9A-Za-z.])[0-9]+[^0-9]{0,20}(assertions?|项断言|項斷言|断言)
#       · 前导 '(^|[^0-9A-Za-z.])' 排除"前一个字符是数字、字母或小数点"，避免版本号尾数
#         与**标识符尾数**被当成计数；字母这一档是 v3.21.0 补的——实测
#         'G6 **executed no assertion' 会命中 '6 … assertion'，于是 claims 变成 {268,6}，
#         两个方向同时红（"单一一致数字"与"== 静态调用数"）。`G6`/`T20`/`A22`/`CHG-016`
#         这类标识符在本文档里到处都是，漏掉这一档等于给每个标识符都埋一颗地雷。
#       · 上限 20 覆盖全部已知中英表述（最长 '项 golden-case ' 为 14 字符）并避免跨句误匹配；
#       · 'assertions?' 兼顾单复数。
#    须命中：'107 golden-case assertions' / '118 assertions' / '107 项 golden-case 断言'
#    须不命中：'见 §2.17.4 防恒真断言'（版本号尾数）/ 'G6 executed no assertion'（标识符尾数）
#    已知残余缺口（不阻断，登记 FU-009）：'assertions: 125'（数字在关键词之后）不命中。
claims=$(grep -ohE '(^|[^0-9A-Za-z.])[0-9]+[^0-9]{0,20}(assertions?|项断言|項斷言|断言)' "$RM_EN" "$RM_ZH" | grep -oE '[0-9]+' | sort -u | tr '\n' ',')
# v3.87.0 (CHG-115, REQ-1184/1185): A3 consumes the committed suite baseline
# (tests/.suite-baseline) instead of asking the generator to re-derive a count.
# The old `--check` call fell through to a full run-tests.sh whenever the
# same-tree receipt was stale (30-min TTL): the 620-assertion audit spent
# 300.984s/97.2% of its wall time inside this one line. --from-baseline is a
# pure read/compare path; runtime truth is validated by CI's single full run
# (baseline == receipt.passed). Generator stderr is captured separately and
# surfaced on failure — the old 2>&1 silently swallowed the "embedded full
# run" notice, which is why the slowdown looked unexplained.
gen_rc=0
gen_err=$(mktemp "${TMPDIR:-/tmp}/audit-a3.XXXXXX")
gen_out=$(bash "$GEN" --check --from-baseline 2>"$gen_err") || gen_rc=$?
if [[ "$gen_rc" -ne 0 && -s "$gen_err" ]]; then
  sed 's/^/A3 generator: /' "$gen_err" >&2
fi
rm -f "$gen_err"
gen_n=$(printf '%s\n' "$gen_out" | sed -nE 's/^assertion claims in sync with run-tests \(([0-9]+)\)$/\1/p')
report "A3 README assertion-count claims are a single consistent number" 1 "$(printf '%s' "$claims" | grep -c '^[0-9]*,$')"
if [[ -n "$SOFT" ]]; then
  report_soft "A3 claimed assertion count == generator runtime count (CHG-019; CI soft)" "$gen_n" "${claims%,}"
else
  report "A3 claimed assertion count == generator runtime count (CHG-019)" "$gen_n" "${claims%,}"
fi

# A3c 生成器同步校验（CHG-007 / FU-005+009）：README 声称数必须与生成器 --check 一致——
#    手工改数、漏改、或 run-tests 增删用例后未同步，都在这里红。
if [[ -f "$GEN" ]]; then
  if [[ -n "$SOFT" ]]; then
    report_soft "A3c README assertion claims match generated count (FU-005/009; CI soft)" 0 "$gen_rc"
  else
    report "A3c README assertion claims match generated count (FU-005/009)" 0 "$gen_rc"
  fi
else
  report "A3c assertion generator script exists" 1 0
fi

# A4 基线来源不得硬编码（CHG-002）——主线为 master 的仓库曾因写死 origin/main 直接
#    fatal（不可自愈）；更危险的是为绕过报错补 `|| true`，空 diff 被读成"通过"。
#    故：模板不得回退到字面分支名，且必须保留 fail-closed 拒绝路径。
#    运行时行为由 run-tests T13 守护，本段是源层发布前拦截。
CI_SCRIPT="$ROOT/resources/templates/check-standards-compliance.sh"
report "A4 compliance.sh has no hardcoded origin/* default baseline" 0 "$(grep -c -- ':-origin/' "$CI_SCRIPT" || true)"
report "A4 compliance.sh resolves its baseline dynamically" 1 "$(grep -c '^resolve_base_ref() {' "$CI_SCRIPT" || true)"
report "A4 compliance.sh fails closed on an unknown baseline" 1 "$(grep -c '无法确定基线分支' "$CI_SCRIPT" || true)"
report "A4 governance workflow has no literal branch fallback" 0 "$(grep -cF "|| 'main'" "$GOV_WF" || true)"

# A5 门禁"交付必检文档"必须随 bootstrap --core 下发模板（CHG-004 / FU-012 防复发）——
#    根因：门禁要求某文档存在、而安装清单不提供模板 → 目标仓库无从落笔，只能靠人记；
#    `06.5` 与 `06-delivery-summary` 长期处于此状态（前者属八类、后者属阶段 9.5 必含，
#    两类交付必检文档都无模板），是 CHG-003 差点漏交 06.5 的制度性原因。
#    取值方式刻意用**动态派生**而非静态清单：从 agent-gate.sh 的 check_delivery_doc
#    调用点提取文件名，再**真跑一次 --core 到临时目录**核对落点。
#    为什么不 grep bootstrap.sh 的文本：首版就是这么写的，结果 install_file 写成
#    `for t in ...; do install_file ...; done` 循环即漏判（假 FAIL），而等价改写又会
#    假 PASS——**用文本形态代替行为，本身就是本族根因**。故此处验证产物，不验证写法。
deliver_docs=$(grep -oE 'check_delivery_doc "\$d" [^ ]+' "$STAGED_TPL" | awk '{print $3}' | sort -u)
n_deliver=$(printf '%s\n' $deliver_docs | grep -c . || true)
report "A5 gate delivery-doc extraction non-empty (防恒真空转)" 1 "$([[ "$n_deliver" -ge 2 ]] && echo 1 || echo 0)"
A5_TMP=$(mktemp -d 2>/dev/null) || A5_TMP=""
bs_missing=0
if [[ -n "$A5_TMP" ]]; then
  bash "$ROOT/scripts/bootstrap.sh" --core "$A5_TMP" >/dev/null 2>&1 || true
  for t in $deliver_docs; do
    [[ -s "$A5_TMP/docs/$t" ]] \
      || { echo "audit: bootstrap --core does not ship a template for gate-required doc: $t" >&2; bs_missing=$(( bs_missing + 1 )); }
  done
  rm -rf "$A5_TMP"
else
  bs_missing=1
  echo "audit: mktemp failed, cannot verify bootstrap --core delivery templates" >&2
fi
report "A5 bootstrap --core ships a template for every gate delivery doc" 0 "$bs_missing"

# A5b 交付模板必须自带 TEMPLATE-MARKER 哨兵——门禁靠它区分"已填写的交付物"与
#     "直接复制过来的空模板"。若模板不带哨兵，门禁就只剩"文件非空"这一条弱校验，
#     等于"复制模板即算完成"重新可行。与 run-tests 的分工：模板侧由本断言守护，
#     门禁的哨兵识别行为由 run-tests T5 守护（内联哨兵，与仓库布局无关）。
for t in $deliver_docs; do
  at_least "A5b delivery template carries TEMPLATE-MARKER sentinel: $t" 1 \
    "$ROOT/resources/templates/$t" 'TEMPLATE-MARKER'
done

# ── PART A6: 本仓库自身治理产物审计（FU-013 闭环）──────────────────────────
# 本仓库 dogfood 的治理产物此前无任何机器审计（FU-013）。以下断言校验本仓库
# 自身的 docs/bugfix-log.md 双登记、docs/changes/CHG-*/ 编号连续性、
# docs/bugs/BUG-*/ 六件套齐备——"规范仓库自己也要受规范审计"。
REPO_BFLOG="$ROOT/docs/bugfix-log.md"
# REPO_CHANGES/REPO_BUGS hoisted to the setup region (REQ-1323 cross-block reads).
# v3.86.0 (CHG-113): docs/ is gitignored by source-repo decree (CHG-017), so a fresh
# CI checkout has no private ledger. Treat that as an explicit SKIP, not a soft pass:
# the old SOFT bucket made A6a/b/c warn forever and leaked into A3/A10, which hid real
# numeric drift. Local runs (docs/ present) and target repos stay hard.
# (Flag is snapshotted at the top of this script — see the v3.91.9 note there.)

# A6a bugfix-log.md 存在且含真实 BUG 条目（非占位模板）
# v3.56.1：A6 族断言依赖 docs/ 磁盘态，而源仓裁定 docs/* 忽略（CHG-017/FU-032，
# .gitignore:37 注释）→ CI checkout 永远缺这些文件，A6a/b/c 结构性必红——并入
# REQ-965 soft 桶（CI 降警，本地恒硬），与 A3/A3c/A10 同款。
if [[ "$A6_DOCS_ABSENT" == 1 ]]; then
  echo "SKIP A6a: docs/ absent in a fresh source checkout (CHG-017; not a pass)"
  report "A6a repo bugfix-log has real BUG entries (docs-dependent)" 1 1
elif [[ -f "$REPO_BFLOG" ]]; then
  bug_count=$(grep -cE '^### BUG-[0-9]' "$REPO_BFLOG" || true)
  report "A6a repo bugfix-log has real BUG entries (docs-dependent)" 1 \
    "$([[ "$bug_count" -ge 2 ]] && echo 1 || echo 0)"
else
  report "A6a repo bugfix-log has real BUG entries (docs-dependent)" 1 0
fi

# A6b docs/changes/ 下每个 CHG 目录至少含 00-intent.md（门禁 1 最低要求）
chg_dirs=$(ls -d "$REPO_CHANGES"/CHG-* 2>/dev/null || true)
chg_missing_intent=0
if [[ -n "$chg_dirs" ]]; then
  for d in $chg_dirs; do
    [[ -f "$d/00-intent.md" ]] || { echo "audit: $d missing 00-intent.md" >&2; chg_missing_intent=$(( chg_missing_intent + 1 )); }
  done
else
  chg_missing_intent=1
fi
if [[ "$A6_DOCS_ABSENT" == 1 ]]; then
  echo "SKIP A6b: docs/ absent in a fresh source checkout (CHG-017; not a pass)"
  report "A6b every CHG dir has 00-intent.md (docs-dependent)" 0 0
else
  report "A6b every CHG dir has 00-intent.md (docs-dependent)" 0 "$chg_missing_intent"
fi

# A6c docs/changes/ 下 CHG 编号连续递增（CHG-001, CHG-002, ... 无跳号）
# BUG-004 修复：编号去前缀后保留前导零（008），bash 算术按**八进制**解析 →
# "value too great for base"；实测（bash 3.2）该错误会**中断整个 if 复合块**，
# 而不只是让条件为假 → 下面的 report 从未执行，断言既不会红也不会绿，连断言
# 总数都不计它（A10 基线按缺失它的口径固化，缺陷完全不可见）。
# 修法：复用本仓 shipped 模板 audit-docs-consistency.sh check_seq() 的既有范式——
# 在取值阶段用 awk '%d' 做十进制归一（非数字归一为 0，产生 gap 报错而非静默跳过）。
# v3.43.0（REQ-961 / FU-111 闭合，用户裁定放宽）：编号集 = 独立 CHG-* 目录 ∪
# BATCH-*/ 内 `## CHG-xxx` 锚点成员——批后独立目录不再误报跳号（§1.1 同日语义）。
# v3.67.0（CHG-090）：∪ STANDARDS_CHANGELOG 声明的 CHG 号——同版本收尾类变更
# （CHG-089 前例：产物并入 CHG-088 docset，仅 §7/CHANGELOG 留名）不构成跳号；
# 号在账本声明即被占用，磁盘形态不是占用与否的判据。
chg_nums=$( { basename -s '' $(ls -d "$REPO_CHANGES"/CHG-* 2>/dev/null) 2>/dev/null \
  | sed 's/CHG-//';
  grep -hoE '^##[[:space:]]+CHG-[0-9]+' "$REPO_CHANGES"/BATCH-*/[0-9A-Za-z]*.md 2>/dev/null \
  | sed -E 's/^##[[:space:]]+CHG-//';
  # 号声明面只取「（CHG-xxx」括注形态（版本行的变更号引法），避免把历史行里的
  # 假想示例（如 `## CHG-903`）当真实占用号（v3.19.0 行实测含此类示例）。
  grep -hoE '[（(]CHG-[0-9]+' "$SLOG" "$SLOG_ARCHIVE" 2>/dev/null \
  | grep -oE '[0-9]+'; } \
  | awk '{printf "%d\n", $1}' | sort -nu)
a6c_ran=0
if [[ "$A6_DOCS_ABSENT" == 1 ]]; then
  echo "SKIP A6c: docs/ absent in a fresh source checkout (CHG-017; not a pass)"
  report "A6c CHG numbering continuous (docs-dependent)" 0 0
  a6c_ran=1
elif [[ -n "$chg_nums" ]]; then
  chg_prev=0
  chg_gap=0
  for n in $chg_nums; do
    if [[ "$n" -ne $(( chg_prev + 1 )) ]]; then
      echo "audit: CHG numbering gap: expected $(( chg_prev + 1 )), got $n" >&2
      chg_gap=1
    fi
    chg_prev=$n
  done
  report "A6c CHG numbering continuous (docs-dependent)" 0 "$chg_gap"
  a6c_ran=1
else
  report "A6c CHG numbering continuous (docs-dependent)" 1 0
  a6c_ran=1
fi
# BUG-004 放大器守卫：A10 基线只记**断言总数**、不记**断言名** → 任一断言被"整块
# 跳过"时总数与基线依然一致（基线本就是按缺失它的口径固化的），缺陷完全不可见。
# 本断言专防"复合块被算术错误中断导致 report 未执行"这一失效模式复发。
report "A6c actually executed (BUG-004 guard)" 1 "$a6c_ran"

# A6d docs/bugs/ 下每个 BUG 目录含六件套（01~06）
bug_dirs=$(ls -d "$REPO_BUGS"/BUG-* 2>/dev/null || true)
bug_missing_files=0
if [[ -n "$bug_dirs" ]]; then
  for d in $bug_dirs; do
    for f in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
      [[ -f "$d/$f" ]] || { echo "audit: $d missing $f" >&2; bug_missing_files=$(( bug_missing_files + 1 )); }
    done
  done
else
  # No bug dirs is valid (repo may not have bugs yet)
  bug_missing_files=0
fi
report "A6d every BUG dir has six-file set (v3.7.0)" 0 "$bug_missing_files"

# A6e 已闭合变更目录完整性（BUG-003 防复发）：目录含 09-changelog.md（闭合标志）则
# 必须同时含其余编号产物——防"闭合变更被部分覆盖/破坏"再次静默发生（BUG-003 实际
# 摧毁了 9 件产物而仅凭 A6b 检查 00-intent 无法发现）。
closed_missing=0
for d in $chg_dirs; do
  [[ -f "$d/09-changelog.md" ]] || continue
  for f in 00-intent.md 00-governance.json 01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 04.5-coding-record.md 05-test-results.md 07-review-report.md; do
    [[ -f "$d/$f" ]] || { echo "audit: closed change $d missing $f" >&2; closed_missing=$(( closed_missing + 1 )); }
  done
done
report "A6e closed change dirs are complete (BUG-003 guard)" 0 "$closed_missing"

# A24 quick-start 承诺面必须已入库（CHG-020）：README 宣传的安装命令读取的是**提交里**
# 的文件——文件只在暂存区/工作树时，远端 raw 404（实测缺陷：install.sh 未提交而已提交的
# README 已在宣传 curl 一条命令）。`git ls-files` 匹配=tracked（CI 干净 checkout 下即
# committed）；与"树↔磁盘"断言互补：那条管"README 树=磁盘实际"，本条管"README 命令=提交内容"。
a24_missing=0
for a24f in scripts/install.sh MAINTAINER.md resources/templates/stamp-provenance.sh .claude-plugin/marketplace.json .claude-plugin/plugin.json; do
  git -C "$ROOT" ls-files --error-unmatch "$a24f" >/dev/null 2>&1 \
    || { echo "audit: quick-start surface not committed (untracked): $a24f" >&2; a24_missing=$(( a24_missing + 1 )); }
done
report "A24 quick-start surface is git-tracked (CHG-020)" 0 "$a24_missing"

# ── PART A8: 门禁硬化形态锚点（CHG-007：FU-008/014/015/019 防复发）──────────────────
#   门禁行为已由 run-tests golden case 守护；此处锁"实现形态"，防行为被静默回退成弱检查
#   （BUG-001 同族：检查模式弱于其声称语义）。取值用 grep -F 固定串，防正则元字符歧义。
# v3.76.0 (CHG-100)：验证通道方言声明的唯一权威载体（yml 模板 ci 段注释，A43 单源）。
# YML_TPL hoisted to the setup region (REQ-1323 cross-block reads).
# v3.18.0：FU-015 的闭环判定从"changelog 文件存在"细化为两种形态——独立目录仍看文件，
# 批次目录看**本变更自己的 `## <id>` 小节**（同批共享 changelog，"文件存在"会把后加入的
# 变更一起判为已关闭）。故此处由"恰好 1 处"改为"两种形态各至少 1 处"：恒等断言会把
# 正确的细化判成回退，下界断言才是这条不变量真正想守的东西。
run_audit_rules <<'EOF'
@STAGED	F_GE	2	A8 begin rejects closed change re-entry (FU-015)	already closed
@STAGED	F_EQ	1	A8 RTVM glob covers nested change-dir matrices (FU-019)	"$change_root"/*/01.5-rtvm-matrix.md
@STAGED	F_NZ	1	A8 numbering checks are digit-anchored (FU-008)	REQ-[0-9]+
@STAGED	F_NZ	1	A8 stage-2 impact checks are structure-anchored (FU-008)	业务影响)
@STAGED	F_EQ	1	A8 delivery declarations are line-anchored (FU-014)	[#>-][[:space:]]*)*未命中
EOF

# A9 规范条款存在性锚点（CHG-008 / FU-016）：防条款被静默移除
at_least "A9 change-id occupancy-verification clause present (FU-016)" 1 "$STD" '取号前必须核实占用'

# A11 规范体量上界（CHG-010 引入 / CHG-011、v3.21.2、v3.25.0、v3.43.0、v3.89.0、v3.97.2 重校准）：治理内容演进时上界随之重校准
# （新条款须有 CHANGELOG 条目对应），硬上界只防"无序回弹"。当前上界 180KB（184,320 字节，v3.97.2 +4KiB 步进；CHG-147 重校准 176KB→180KB，FU-1013 R42 勘误 +60B 压线触发）。
# v3.29.0（CHG-028）重校准 132KB → 140KB 的依据：§2.1 九专家行 + §2.2 分阶段专家评审矩阵为
# 新增规范性内容（两轮措辞压缩后仍超 136KB 约 1.6KB），按 KiB 步进 +4KB；STANDARDS_CHANGELOG v3.29.0 行即依据。
# v3.25.0（CHG-025）重校准 128KB → 132KB 的依据（按既有三个条件）：
#   ① **先压缩**：v3.24.0 + v3.25.0 两轮新增条款均经措辞压缩（§2.9.6/§2.5 三轮收字），
#      v3.24.0 收口时余量仅剩 3 字节——上界事实上已失效（同 v3.17.0 的 53 字节、
#      v3.21.2 的 193 字节同型）；v3.25.0 新增为执行侧纪律（写侧并行批量/定向验证/
#      产物最小表达形态），非文字膨胀；
#   ② **有 CHANGELOG 条目对应**：见 `resources/STANDARDS_CHANGELOG.md` 的 v3.25.0 行；
#   ③ 上界按 KiB 步进（+4KB）重设，余量约 3.3KB——**不是**按当前体量贴合。
# v3.21.2（CHG-017 / REQ-089）重校准 124KB → 128KB 的依据（按 §5.1 的两个条件）：
#   ① **先压缩**：本轮新增文字先做了一轮浓缩（删除规范正文里的变更日志式括注、
#      把派生资产的判定口径收成一句），但 v3.21.1 + v3.21.2 两轮的对齐修正
#      （AGENTS 门禁节清单、L3 覆盖率门槛、矩阵落点句澄清等）已把 124KB 上界的
#      余量吃到 **193 字节**——上界事实上再次失效，与 v3.16.0 的 53 字节同型；
#   ② **有 CHANGELOG 条目对应**：见 `resources/STANDARDS_CHANGELOG.md` 的 v3.21.2 行；
#   ③ 上界按 KiB 步进（+4KB）重设，余量 **4,289 字节**——**不是**按当前体量贴合，
#      否则下一次任何实质新增又会立刻撞墙。
# v3.17.0 重校准 120KB → 124KB 的依据（不只是"装不下了"）：
#   ① v3.16.0 的未提交改动已把 120KB 上界的余量吃到 **53 字节**——上界事实上已失效，
#      留着它只会让下一位维护者以为还有空间；
#   ② 本版新增的是**治理要求**（文件溯源 + 不追溯既往），不是文字膨胀；且已先做压缩：
#      合并三条重复条款为一条、并把机制细节下沉到 stamp-provenance.sh 头部注释，
#      净增 1,035 字节（122,827 → 123,862）；
#   ③ 上界按 KiB 步进（+4KB）重设，余量 3,114 字节——**不是**按当前体量贴合。
# v3.35.0 重校准 144KB → 156KB 的依据（不只是"装不下了"）：
#   ① v3.31.0 的 144KB 上界余量已被 §1.3 项目级总册（CHG-035，12 册定义 + 门禁/DoD/
#      主线/落点/回填清单 + 缺陷按天入批 + bug 两条款）吃到负值（153,499 字节）；
#   ② 有 CHANGELOG 条目对应：resources/STANDARDS_CHANGELOG.md 的 v3.35.0 行；
#   ③ 上界按 KiB 步进（+12KB，跨 4KB 档取整）重设为 156KB，余量约 6.2KB——
#      不是按当前体量贴合。
# v3.43.0 重校准 156KB → 164KB 的依据（CHG-053，FU-106④）：
#   ① §2.17.2b 缺陷发现入口（三信号双通道 + 频控 + 自主权）吃到负值（160,160 字节）；
#   ② 有 CHANGELOG 条目对应：resources/STANDARDS_CHANGELOG.md 的 v3.43.0 行；
#   ③ 上界按 KiB 步进（+8KB，跨 4KB 档取整）重设为 164KB，余量约 7.5KB——
#      不是按当前体量贴合。
# v3.68.0 重校准 164KB → 172KB 的依据（CHG-043 同版本收尾，2026-10-12 用户裁定）：
#   ① v3.67.0 UX 体系 + v3.68.0 三维对照门禁族连续两版本族结构扩容吃到负值（170,735 字节，
#      v3.67.0 时余量仅 455B 已压线）；② 有 CHANGELOG 条目对应（v3.68.0 行勘误注）；
#   ③ KiB 步进（+8KB）重设为 172KB——**配对减法纪律**：下次触软警线（171,008B）必须走
#      结构性减法，禁止连续重校准；门禁族稳定后的减法 CHG 另立。
# v3.70.0 回转 172KB → 164KB（CHG-045，2026-10-13，用户"体积要控制"指令 + 配对减法纪律兑现）：
#   CHG-045 存量法下沉实移 ~3.2KB（DS 170,823→167,610——盘点估值 13KB 偏高，可无语义损失
#   移出的形状就这些；软警线 163,840B 常亮=下次结构增长的减法触发器）。A28/MAINTAINER 同步。
# v3.89.0 重校准 164KB → 168KB 的依据（CHG-117，REQ-1199~1203，独立评审批 F5）：
#   ① §2.17.2b 信号③专句 + §2.16.2 阶段门执法点 + §2.17 阶段门/无账门专段（含设计门补齐
#      03.5）把 DS 推到 165,937 字节——旧软警 163,840B 之上、旧硬上界 167,936B 内余 1,999B；
#   ② 有 CHANGELOG 条目对应：resources/STANDARDS_CHANGELOG.md 的 v3.89.0 行；
#   ③ 按 +4KB 步进重设为 168KB（172,032 字节），余量 6,095B——**不是**按当前体量贴合；
#      软警线随上界 −4KiB = 167,936B。独立评审核回+8KB 步进放宽过多，此处兑现 +4KB。
# std_bytes hoisted to the setup region (REQ-1323 cross-block reads).
report "A11 standards body size <= 160KB (ITEM-42; slimmed in v4.9.0 CHG-154)" 1 "$([[ "$std_bytes" -le 163840 ]] && echo 1 || echo 0)"
# A11s 软预警档（v3.58.0 / REQ-1008；v4.9.0 CHG-154 下调随 160KB 收敛）：DS ≥155,648B（152KB）即 soft warn。
report_soft "A11s standards body approaching hard cap (soft warn >= 155,648B)" 0 "$([[ "$std_bytes" -ge 155648 ]] && echo 1 || echo 0)"
at_least "A11 layered reading map present (FU-018)" 1 "$STD" '分层阅读路由'
# A28 §5.1 口径一致性（CHG-057/REQ-974）：MAINTAINER「当前上界」句必须与 A11 断言同源——v3.43.0 重校曾漏同步 144KB 口径（漂移实存），A28 防复发
report "A28 maintainer 5.1 bound sentence matches A11" 1 "$(grep -cF '160 KB / 163,840 字节' "$ROOT/MAINTAINER.md")"
# A29 SKILL 清单枚举面（CHG-057 sweep 防复发）：bootstrap 分发的治理新件必须出现在 SKILL.md 核心/强制层清单——批 1 曾漏列（README 树有、SKILL 无），枚举面漂移实存
report "A29 SKILL core layer lists clause registry" 1 "$(grep -c 'CLAUSE_REGISTRY' "$ROOT/SKILL.md")"
report "A29 SKILL guard layer lists reading-pack generator" 1 "$(grep -c 'generate-reading-pack' "$ROOT/SKILL.md")"
# A30 延伸发现/历史相似检索（CHG-058/REQ-975/976）：DS §2.5 阶段 2/6、§2.12、§2.16.5、七要素⑦ 节与关键词在位
at_least "A30 stage-2 延伸发现 clause" 1 "$STD" '延伸发现（v3.48.0）'
at_least "A30 stage-2 历史相似检索 clause" 1 "$STD" '历史相似检索（v3.48.0）'
at_least "A30 stage-6 dual clause" 1 "$STD" '延伸发现与历史相似检索（v3.48.0）'
at_least "A30 discover-register-now clause" 1 "$STD" '会话内发现即登记'
at_least "A30 erratum cites origin CHG" 1 "$STD" '显式引用原 CHG 号'
at_least "A30 seven-element history field" 1 "$STD" '历史检索命中的 BUG/CHG 号'
# A31 枚举面 pin（CHG-058/REQ-978，CHG-120 改指）：G 组索引唯一权威=AGENTS 锚点表（G10 同步漏更复发防线，A29 同族）；
# 双 README 自 CHG-120 起只留「G1–G16」指针、不再逐组枚举 —— pin 随实现改指唯一索引，同时钉住 README 的指针形态。
at_least "A31 G10 enumerated in the AGENTS index" 1 "$ROOT/resources/AGENTS.md" 'G10'
at_least "A31 EN README points at the single audit-group index" 1 "$ROOT/README.md" 'G1–G16'
at_least "A31 zh README points at the single audit-group index" 1 "$ROOT/README.zh-CN.md" 'G1–G16'
# CHG-118: pin 随实现更新——audit 实际已是 G1–G16（G15/G16 于 v3.84.0/v3.89.0 加入），
# 旧 pin 'G1–G14' 是过期字面量，会在 SKILL 如实更新时误判为回退。
at_least "A31 audit-group enumeration in SKILL (G1-G16)" 1 "$ROOT/SKILL.md" 'G1–G16'
at_least "A31 bugfix-log template history field" 1 "$ROOT/resources/templates/bugfix-log.md" '历史相似'

# A32 版本载体全链清单条款（CHG-061 / REQ-984，对等减法=§2.16.5 标准升级行退役合并）
at_least "A32 carrier full-chain clause present" 1 "$STD" '版本载体全链清单（v3.49.0）'
report "A32 retired 2.16.5 row absent" 0 "$(grep_count "$STD" '标准升级 | 版本 + 影响清单')"

# A33 AGENTS.md 托管标记与合并机制（CHG-062 / REQ-986，安装/升级用户内容保留）
at_least "A33 AGENTS.md carries managed markers" 1 "$ROOT/resources/AGENTS.md" 'dev-standards:managed begin'
at_least "A33 bootstrap ships merge_managed" 1 "$ROOT/scripts/bootstrap.sh" 'merge_managed'

# A34 安装清单用户改动检测（CHG-063 / REQ-987，全文件保留机制）
at_least "A34 bootstrap ships manifest user-modified detection" 1 "$ROOT/scripts/bootstrap.sh" 'manifest_user_modified'
at_least "A34 bootstrap manifest path pinned" 1 "$ROOT/scripts/bootstrap.sh" '.dev-standards-manifest'
# A35 reserved tombstone (v3.58.0, REQ-1008): no assertion ever used this id —
# the gap predates the v3.46 registry and had no tombstone (BATCH-20260926
# review finding). Reserved so the gap stays visible; A36 resumes the
# sequence below. Do not silently renumber A36+.

# A12 Bug 诊断增强锚点（CHG-011 / REQ-057~058，依据 arXiv:2602.02475）
at_least "A12 root-cause classification present (REQ-057)" 1 "$STD" '根因分类'
at_least "A12 change dynamic constraints present (REQ-058)" 1 "$STD" '变更动态约束'

# A13 安装器自动接线锚点（CHG-012）
run_audit_rules <<'EOF'
@BS	F_GE	1	A13 bootstrap auto-wires hooksPath (CHG-012)	auto-wired   git config core.hooksPath
@STAGED	F_GE	1	A13 gate reads yml verification fallback (CHG-012)	agent-governance.yml
@GATE_HW	F_EQ	0	A13 legacy sed channel parser is gone (CHG-100)	s/^[[:space:]]*verification_command:
@STAGED	E_EQ	1	A13 single channel reader is defined once (CHG-100)	^yml_scalar\(\) \{ # <file> <key>
@SUITES	E_GE	8	A13 golden dialect matrix covers the declared dialect (CHG-100)	T61 TC-13[34][0-9]
@BS	F_GE	1	A14 bootstrap upgrade mode present (CHG-013)	--upgrade
@BS	F_GE	1	A15 bootstrap self-update present (CHG-014)	self-update skill repo
@STAGED	F_GE	1	A16 gate anti-tamper guard present (CHG-015)	anti-tamper
@BS	F_GE	1	A16 upgrade blocks on dirty target (CHG-015)	uncommitted changes — commit first, or pass --force
EOF

# A17 路径根可配置锚点（v3.15.0）——防两个反向回退：
#   ① 参数化回退：又变回硬编码（目标仓库换根后门禁按默认根找文件 → 静默错位）；
#   ② 过度参数化：把 AGENTS.md / 15 件产物名 / 六件套名也做成可配 →
#      跨仓逐文件比对与"装一次迁移任意仓库"解体。
#   形态锚点（grep -c）而非行为断言：行为由 run-tests T14 在真仓库里端到端验证。
# GOV_YML_TPL hoisted to the setup region (REQ-1323 cross-block reads).
AUDIT_TPL="$ROOT/resources/templates/audit-docs-consistency.sh"
CI_TPL="$ROOT/resources/templates/check-standards-compliance.sh"
# 计数型断言统一归一到 0/1（本脚本的 at_least 是 4 参形态：name min file pattern，
# 计数型必须走 report + 归一，不能直接喂计数）
# a17_at_least_1 hoisted to the setup region (REQ-1323 cross-block reads).
report "A17 gate resolves path roots from config" 1 "$(a17_at_least_1 "$(grep -c 'cfg_path() {' "$GATE_TPL" || true)")"
report "A17 gate path defaults are the historical values" 1 "$(a17_at_least_1 "$(grep -cE 'cfg_path docs docs|_AG_YML_DOCS:-docs' "$GATE_TPL" || true)")"
report "A17 audit script resolves the docs root from config" 1 "$(a17_at_least_1 "$(grep -c 'cfg_path docs docs' "$AUDIT_TPL" || true)")"
report "A17 compliance script resolves the docs root from config" 1 "$(a17_at_least_1 "$(grep -c 'cfg_path docs docs' "$CI_TPL" || true)")"
report "A17 installer exposes --docs-dir" 1 "$(a17_at_least_1 "$(grep -c -- '--docs-dir' "$ROOT/scripts/bootstrap.sh" || true)")"
report "A17 installer persists non-default roots into the config" 1 "$(a17_at_least_1 "$(grep -c 'rewrite_yml_key' "$ROOT/scripts/bootstrap.sh" || true)")"
report "A17 live-skip keys are logical, not literal paths (D6)" 1 "$(a17_at_least_1 "$(grep -c 'install_file bugfix-log ' "$ROOT/scripts/bootstrap.sh" || true)")"
report "A17 shipped config declares the four configurable roots" 4 "$(grep -cE '^  (docs|scripts|tests|githooks):' "$GOV_YML_TPL" || true)"
report "A17 .github is NOT configurable (platform-fixed location)" 0 "$(grep -cE '^  github:' "$GOV_YML_TPL" || true)"
report "A17 contract names stay out of the configurable block" 0 "$(grep -cE '^  (AGENTS|CLAUDE|agent-gate|00-intent|01-diagnosis)' "$GOV_YML_TPL" || true)"
report "A17 installer substitutes in-template path references" 1 "$(a17_at_least_1 "$(grep -c 'transform_src' "$ROOT/scripts/bootstrap.sh" || true)")"
at_least "A17 standards documents the configurable roots" 1 "$STD" '路径根可配置'
at_least "A17 standards documents the non-configurable set" 1 "$STD" '不可配置项'

# A18 Agent 自进化契约 + 自更新/版本自查锚点（v3.16.0）——防三类反向回退：
#   ① 自更新又变回"静默跳过"（D1 回归：非 git 克隆时用户以为已升级）；
#   ② 升级又去覆盖显式层选择（D4 回归）或派生资产（自进化契约失效）；
#   ③ 派生标记解析退回整文件 grep（SKILL.md 正文的示例代码块会被误判为真实
#      声明——本轮实测踩过：源仓把自己报成了派生 Skill，且写入守卫会误拒
#      向本仓自身的合法安装）。
BOOT="$ROOT/scripts/bootstrap.sh"
report "A18 installer exposes a read-only --check mode" 1 "$(a17_at_least_1 "$(grep -c 'check_mode=true' "$BOOT" || true)")"
report "A18 installer exposes --self-update" 1 "$(a17_at_least_1 "$(grep -c 'self_update=true' "$BOOT" || true)")"
report "A18 installer exposes --derived-report" 1 "$(a17_at_least_1 "$(grep -c 'derived_report=true' "$BOOT" || true)")"
report "A18 upgrade preserves an explicit layer selection (D4)" 1 "$(a17_at_least_1 "$(grep -c 'layers_explicit' "$BOOT" || true)")"
report "A18 derived markers are parsed from frontmatter only" 1 "$(a17_at_least_1 "$(grep -c 'frontmatter() {' "$BOOT" || true)")"
report "A18 installer refuses to install into a derived skill" 1 "$(a17_at_least_1 "$(grep -c 'refusing to install into a derived skill directory' "$BOOT" || true)")"
report "A18 every write path skips derived dirs" 1 "$(a17_at_least_1 "$(grep -c 'derived (skip)' "$BOOT" || true)")"
report "A18 upgrade refuses to clobber local changelog rows (D5)" 1 "$(a17_at_least_1 "$(grep -c 'divergence_guard' "$BOOT" || true)")"
report "A18 installer pins path roots through escaped variables (idempotency)" 3 "$(( $(a17_at_least_1 "$(grep -cF '\1${e_docs} ' "$BOOT" || true)") + $(a17_at_least_1 "$(grep -cF 'e_docs=$(sed_repl_escape' "$BOOT" || true)") + $(a17_at_least_1 "$(grep -cF '$(cfg_path docs $e_docs_q)' "$BOOT" || true)") ))"
at_least "A18 standards documents the changelog ownership" 1 "$STD" '规范升级日志的归属'
at_least "A18 standards documents the self-evolution contract" 1 "$STD" 'Agent 自进化与派生资产'
at_least "A18 SKILL.md declares the derived_from contract" 1 "$SKILL" 'derived_from'
report "A18 changelog template declares skill ownership" 1 "$(a17_at_least_1 "$(grep -c '归 Skill 所有' "$ROOT/resources/STANDARDS_CHANGELOG.md" || true)")"
report "A18 MAINTAINER.md exists (maintainer notes live outside the payload)" 1 "$([[ -s "$ROOT/MAINTAINER.md" ]] && echo 1 || echo 0)"
report "A18 MAINTAINER.md is NOT in the installer copy list" 0 "$(grep -c 'MAINTAINER.md' "$BOOT" || true)"

# A19 文件溯源锚点（v3.17.0）——防五类反向回退：
#   ① 溯源脚本从 payload 消失或未进 guard 层 → 门禁要求它，目标仓库却装不到，
#      每个变更都会卡在"run stamp-provenance.sh"却无脚本可跑（死锁）；
#   ② 门禁不再校验溯源 → 要求形同虚设，手写块畅通；
#   ③ 校验退回"只看块存在" → 占位块与手写块放行（本轮实测的反例形态）；
#   ④ 隐私开关失效 → email 恒明文，`include_email: false` 无声无效；
#   ⑤ 幂等性回退 → 重复运行叠加多个块（门禁按首块校验，叠加即误导）。
# 形态锚点而非行为断言：行为由 run-tests T16 在真仓库里端到端验证（26 断言）。
STAMP_TPL="$ROOT/resources/templates/stamp-provenance.sh"
CR_TPL="$ROOT/resources/templates/coding-record.md"
report "A19 provenance stamper ships in the payload" 1 "$([[ -s "$STAMP_TPL" ]] && echo 1 || echo 0)"
report "A19 installer lands the stamper in the guard layer" 1 "$(a17_at_least_1 "$(grep -c 'install_file - "\$SCRIPTS_DIR/stamp-provenance.sh"' "$BOOT" || true)")"
report "A19 installer substitutes the stamper path in templates" 1 "$(a17_at_least_1 "$(grep -c 'scripts/stamp-provenance' "$BOOT" || true)")"
# §2 联动表：改复制清单必须同步 --help 文本（--help 是文件清单的唯一权威源）
report "A19 installer --help lists the stamper in the guard layer" 1 "$(a17_at_least_1 "$(grep -c 'stamp-provenance.sh (文件溯源盖章' "$BOOT" || true)")"
run_audit_rules <<'EOF'
@STAGED	F_NZ	1	A19 gate extracts the provenance block	provenance_block() {
@STAGED	F_NZ	1	A19 gate rejects a missing block	carries no provenance block
@STAGED	F_NZ	1	A19 gate rejects a placeholder block	provenance block still holds a placeholder
@STAGED	F_NZ	1	A19 gate requires the script as producer	was not produced by scripts/stamp-provenance.sh
@STAGED	F_NZ	1	A19 gate checks the ISO shape of generated_at	is not an ISO-8601 date
@STAGED	F_NZ	1	A19 gate requires the four mandatory fields	for k in author email generated_at generated_by
@STAMP	F_NZ	1	A19 stamper honours the privacy switch	include_email
@STAMP	F_NZ	1	A19 stamper redacts the email when asked	<redacted>
@STAMP	F_NZ	1	A19 privacy switch is env-overridable (CLI > env > yml)	AGENT_GUARD_PROVENANCE_EMAIL
@STAMP	F_NZ	1	A19 stamper replaces the block wholesale (idempotent)	单趟删块+插块
@STAMP	F_NZ	1	A19 stamper never fabricates: unknown fallbacks	unknown
@STAMP	F_NZ	1	A19 stamper gives an actionable next step when the record is absent	write the coding record first
@GATE	F_NZ	1	A19 gate treats the stamper as a governance tool (no install deadlock)	scripts_re}/stamp-provenance
EOF
report "A19 gate validates every artifact's provenance (CHG-026)" 1 "$([[ $(grep -c 'validate_provenance "\$pf"' "$STAGED_TPL" || true) -ge 1 && $(grep -c '"00-governance.json"' "$STAGED_TPL" || true) -ge 1 ]] && echo 1 || echo 0)"
report "A19 shipped config declares the provenance section" 1 "$(a17_at_least_1 "$(grep -c '^provenance:' "$GOV_YML_TPL" || true)")"
report "A19 shipped config defaults include_email to true" 1 "$(a17_at_least_1 "$(grep -c '^  include_email: true' "$GOV_YML_TPL" || true)")"
report "A19 coding-record template carries the placeholder block" 1 "$(a17_at_least_1 "$(grep -c '^<!-- provenance' "$CR_TPL" || true)")"
report "A19 coding-record template placeholder is stamped PENDING" 1 "$(a17_at_least_1 "$(grep -c '^author: PENDING' "$CR_TPL" || true)")"
at_least "A19 standards documents the provenance requirement" 1 "$STD" '文件溯源'
at_least "A19 SKILL.md tells the agent to stamp provenance" 1 "$SKILL" 'stamp-provenance'
# 反向断言（v3.22.0 语义修正）：溯源块只允许出现在**活跃变更**或**已闭合变更**
# （含 09-changelog.md）——交付时盖章是 §1.1 的**强制动作**，原断言"历史目录一律
# 不得盖章"与它直接矛盾（自锁：本仓 17 个变更目录 0 盖章，一盖即红，溯源条款在
# 源仓从未走通过）。修正后仍拦住真正的伪造形态：对**无关的开放目录**随手盖章
# （那才是"把 generated_at 伪造成今天"的入口）；已闭合目录的块是交付时的合法
# 产物（幂等重盖本就无法与首次区分——门禁本就只校验活跃变更，此处不假装更强）。
# 活跃变更从 .git/agent-governance/active-change 读（gate begin 维护；无 gate 环境
# 退化为"已闭合即可"）。
active_id=""
if [[ -s "$ROOT/.git/agent-governance/active-change" ]]; then
  active_id=$(tr -d '[:space:]' < "$ROOT/.git/agent-governance/active-change")
fi
retro_stamped=0
for d in "$ROOT/docs/changes"/*/; do
  [[ -d "$d" ]] || continue
  dname=$(basename "$d")
  # 已闭合的目录级代理：存在 09-changelog.md。批次的"半闭合"（部分成员已写小节）
  # 由门禁的逐成员锚点语义兜底（A20），此处采用目录级代理并如实声明——共享产物的
  # 盖章属于整批交付动作，按成员拆分反而会把合法盖章误判为回填。
  [[ -f "$d/09-changelog.md" ]] && continue
  [[ "$dname" == "$active_id" ]] && continue
  # CHG-106（REQ-1151，DES-1916）：日批成员目录豁免——active 判定原比目录名，
  # BATCH-YYYYMMDD 目录名恒 ≠ 成员 id，首成员 09 未写（closed 代理缺失）时该目录
  # 盖章全数误报（CHG-105 实测 ×7）。与门禁 change_dir 同款锚点解析：BATCH 目录
  # 含 `## <active_id>` 成员锚即视为 active 目录（盖章属整批交付动作，目录级豁免
  # 与上方注释语义一致）。grep -qs：静默容忍无文件/不可读。
  if [[ -n "$active_id" && "$active_id" =~ ^[A-Za-z0-9._-]+$ && "$dname" =~ ^BATCH-[0-9]{8}$ ]] \
    && grep -qsE "^##[[:space:]]+${active_id}([[:space:]]|$)" "$d"*.md 2>/dev/null; then
    continue
  fi
  for f in "$d"*.md; do
    [[ -f "$f" ]] || continue
    grep -q '^<!-- provenance$' "$f" 2>/dev/null || continue
    echo "audit: provenance block on a non-active, non-closed change artifact: ${f#$ROOT/}" >&2
    retro_stamped=$(( retro_stamped + 1 ))
  done
done
report "A19 stamps appear only on the active or closed changes (v3.22.0 semantics)" 0 "$retro_stamped"

# A20 变更批次锚点（v3.18.0）——防五类反向回退：
#   ① 批次解析从门禁消失 → 批次目录里的变更被判"缺产物"，同天合并直接不可用；
#   ② 治理记录退回"取文件里第一个 risk_level" → 批次里读到**兄弟变更的风险与
#      责任人**（最危险的一种：错的风险等级会放行 L2/L3）；
#   ③ 批次失去 L0/L1 上限 → 批次变成绕过角色独立性的暗道；
#   ④ 闭环判定退回"changelog 文件存在" → 同批兄弟的 changelog 把后加入的变更
#      一起判为已关闭（假阳性），或反之永不关闭；
#   ⑤ 审计与门禁对"锚点"的定义分叉 → 审计绿而门禁红（或反过来），最难查。
# 行为由 run-tests T18 在真仓库里端到端验证；此处钉形态，防静默删除。
run_audit_rules <<'EOF'
@STAGED	F_NZ	1	A20 gate resolves batch directories	change_dir() {
@STAGED	F_NZ	1	A20 gate scans BATCH-* directories	$change_root"/BATCH-*/
@STAGED	F_NZ	1	A20 gate honours AGENT_GUARD_CHANGE_DIR	AGENT_GUARD_CHANGE_DIR
@STAGED	F_NZ	1	A20 gate recognises a batch directory by name	is_batch_dir() {
@STAGED	F_NZ	1	A20 gate has ONE definition of a section anchor	anchor_re() {
@STAGED	F_NZ	1	A20 gate extracts anchors with a single sed shape	anchors_in_file() {
@STAGED	F_NZ	1	A20 gate maps a directory to every change it carries	change_ids_in_dir() {
@STAGED	F_NZ	1	A20 governance records are scoped per change (one record per change id)	gov_record() {
@STAGED	F_NZ	1	A20 governance state is scoped to this change's own record	rec=$(gov_record "$file" "$id")
@STAGED	F_NZ	1	A20 batches are L0/L1 only (refused on the record, not on the path)	batches are L0/L1 only
@STAGED	F_NZ	1	A20 batch closure is this change's own anchor, not the shared file	carries a '## $id' section
@COLD	F_NZ	1	A20 metrics emits one row per change, not per directory	change_ids_in_dir "${dir%/}"
@STAGED	F_NZ	1	A20 diff attribution reads a batch file's governance roster	id_list=$(gov_ids "$(dirname "$f")/00-governance.json")
@STAMP	F_NZ	1	A20 stamper resolves the batch directory too	resolve_dir() {
@STAMP	F_NZ	1	A20 stamper attests the batch and lists its members	batch_changes:
@STAMP	F_NZ	1	A20 batch provenance risk is member-independent (max of the batch)	batch_changes" && -f
@AUDIT	F_NZ	1	A20 template audit grew a G7 batch group	G7 变更批次自洽
@AUDIT	F_NZ	1	A20 template audit offers --only-fail with skip-line exemption	only-fail
@AUDIT	F_NZ	1	A20 G7 checks every declared change has an entry section	every batch change has a section in the batch 00-intent.md
@AUDIT	F_NZ	1	A20 G7 checks records are a subset of the anchors	every batch governance record has an anchor
@AUDIT	F_NZ	1	A20 G7 re-checks the L0/L1 ceiling	batch risk levels are L0/L1 only
@AUDIT	F_NZ	1	A20 G7 checks change ids are unique across batches	change ids unique across batches
@STAGED	F_NZ	1	A20 gate has ONE place that reads the batch roster	gov_ids() {
@STAGED	F_NZ	1	A20 batch change set comes from the roster, not from headings	roster=$(gov_ids "$d/00-governance.json")
@AUDIT	F_NZ	1	A20 audit reads the roster as the batch's authoritative id set	权威名单：只从治理记录取变更号
@AUDIT	F_NZ	1	A20 audit documents WHY the reverse direction was dropped	无法区分"变更小节"与"结构小节"
@GATE_HW	E_EQ	0	A20 batch attribution does not fall back to heading scanning first	^ *id_list=\$\(anchors_in_file "\$f"\)$
@AUDIT	F_NZ	1	A20 audit and gate share one anchor shape	同一条 sed 表达式
@STD	F_GE	1	A20 standards documents the change batch	变更批次
@SKILL	F_GE	1	A20 SKILL.md documents the batch layout	变更批次
@AGENTS	F_GE	1	A20 AGENTS.md states the batch rule in the gate steps	BATCH-YYYYMMDD
EOF
report "A20 changelog carries the v3.18.0 entry" 1 "$(a17_at_least_1 "$(cat "$SLOG" "$SLOG_ARCHIVE" 2>/dev/null | grep -c 'v3.18.0' || true)")"
report "A20 gate splits the resolver's local declaration (bash 3.2)" 0 "$(grep_count_f_files 'local id="$1" d=' "$GATE_TPL" "$STAGED_TPL")"
report "A20 stamper splits the resolver's local declaration (bash 3.2)" 0 "$(grep -c 'local id="\$1" d=' "$STAMP_TPL" || true)"

# A21 治理记录的格式无关性锚点（v3.20.0）——防三类反向回退：
#   ① 记录读取退回**行式**（`grep ... | head -1`）→ 多行格式化记录读不到任何字段。
#      这不是假想：v3.18.0 为支持批次正是这么改的（行式对批次是必需的：要按
#      change_id 隔离兄弟记录），它**静默打破了多行记录**，而多行恰是**随包下发的
#      模板** `resources/templates/governance-state.json` 的形状、也是 SKILL.md
#      指示生成 `00-governance.json` 时照抄的形状。实测后果：`begin` 报
#      `must declare risk_level L0, L1, L2, or L3`（字段就在 change_id 下面两行），
#      `metrics` 对每条记录报 `"risk_level":null`；本仓账本 16/16 条全中。
#   ② 有人"反向修"——把模板压成单行来迁就读取器。数据迁就解析器是错的方向：
#      模板是给人看的，读取器必须接受任意合法 JSON。故有下面的反向断言。
#   ③ 批次成员之间串读（本修复最容易引入的回归）——由 run-tests T19 ④ 端到端钉住。
# 形态锚点；行为由 run-tests T19 在真仓库里端到端验证（多行 / 单行 / 多行批次三种形状）。
run_audit_rules <<'EOF'
@STAGED	F_NZ	1	A21 gate flattens a governance record before matching	flat=$(tr -d
@STAGED	F_NZ	1	A21 gate splits sibling records on top-level object boundaries	top-level object boundaries
@STAGED	F_NZ	1	A21 the record reader is documented as no longer line-oriented	no longer a PARSER
@STAGED	F_NZ	1	A21 the batch one-line convention survives as a style rule	style rule, not a load-bearing one
@SUITES	F_NZ	1	A21 golden suite covers a pretty-printed record end-to-end	T19 begin accepts a pretty-printed governance record
@SUITES	F_NZ	1	A21 golden suite pins that a sibling's risk cannot leak	T19 the sibling reads its own risk, not the first record
EOF
# 正向：随包模板仍是多行（这是本缺陷的触发形状，也是文档指示照抄的形状）
report "A21 shipped governance template is the multi-line shape" 1 "$(grep -cE '^  \"change_id\":' "$ROOT/resources/templates/governance-state.json" || true)"
# 反向：模板**不得**被压成单行来迁就解析器（数据迁就解析器是错的方向）
report "A21 the template was NOT collapsed to one line (fix the reader, not the data)" 0 "$(grep -cE '^\{.*\"change_id\".*\}$' "$ROOT/resources/templates/governance-state.json" || true)"
report "A21 changelog carries the v3.20.0 entry" 1 "$(a17_at_least_1 "$(cat "$SLOG" "$SLOG_ARCHIVE" 2>/dev/null | grep -c 'v3.20.0' || true)")"
at_least "A21 SKILL.md documents the format-agnostic record reader" 1 "$SKILL" '格式无关'
at_least "A21 MAINTAINER documents the record-reader coupling" 1 "$ROOT/MAINTAINER.md" 'gov_record'

# A22 审计单元识别 / 空转显式声明 / 编号定义式（v3.21.0）
run_audit_rules <<'EOF'
@AUDIT	F_NZ	1	A22 audit detects units by positive signal	looks_like_audit_dir()
@AUDIT	F_NZ	1	A22 audit declares a G2 vacuous skip instead of skipping silently	G2 VACUOUS SKIP
@AUDIT	F_NZ	1	A22 audit declares the G3/G5/G6 vacuous skip separately from G2	G3/G5/G6 VACUOUS SKIP
@AUDIT	F_NZ	1	A22 numbering counts definition-shaped occurrences only	DEF_RE()
@AUDIT	F_EQ	0	A22 numbering baseline is the file's own min, not 1	$(seq 1 "$max")
@AUDIT	F_NZ	1	A22 G2 covers the change track as well as the feature track	for base in "$DOCS" "$CHANGES"
@AUDIT	F_NZ	1	A22 G3/G5/G6 are scoped to living docs only	g36_dirs
@AUDIT	F_GE	1	A22 the audit header documents the frozen-history scoping	不变量对冻结历史的适用性
@SUITES	F_NZ	1	A22 golden suite pins the change-dir REQ gap end-to-end	T20 audit reds on a REQ gap inside a change dir
@SUITES	F_NZ	1	A22 golden suite pins that in-prose refs do not widen the span	T20 in-prose REQ references do not widen the definition span
EOF
report "A22 changelog carries the v3.21.0 entry" 1 "$(a17_at_least_1 "$(cat "$SLOG" "$SLOG_ARCHIVE" 2>/dev/null | grep -c 'v3.21.0' || true)")"
at_least "A22 MAINTAINER documents the audit-unit scoping" 1 "$ROOT/MAINTAINER.md" 'g36_dirs'

# A22b 源仓台账审计不再空转 / 历史红灯可见（v3.86.0，CHG-113）
run_audit_rules <<'EOF'
@AUDIT	F_GE	1	A22b source repo audits against shipped standards (no blanket SKIP)	AGENT_GUARD_STD_FILE
@AUDIT	F_GE	1	A22b source mode falls back to resources/AGENTS.md pointer target	resources/AGENTS.md
@AUDIT	F_GE	1	A22b G4 newest BUG is selected by registration date	NODATE
@AUDIT	F_GE	1	A22b legacy allowlists stay visible in output	allowlisted legacy
@AUDIT	F_GE	1	A22b G7 excludes the batch container record from members	grep -vx "$bname"
EOF

# A23 一键安装器 + 溯源全量盖章形态锚点（v3.22.0）
INSTALL_SH="$ROOT/scripts/install.sh"
report "A23 install.sh exists in the source layer" 1 "$([[ -s "$INSTALL_SH" ]] && echo 1 || echo 0)"
run_audit_rules <<'EOF'
@INST	F_NZ	1	A23 install.sh stays a thin delegate to bootstrap	scripts/bootstrap.sh
@INST	F_NZ	1	A23 install.sh auto-detects install vs upgrade	mode="auto"
@INST	F_NZ	1	A23 install.sh keeps the offline path (--from)	--from
@INST	F_NZ	1	A23 install.sh never overwrites a dirty skill checkout	never overwrites your checkout
@INST	F_NZ	1	A23 install.sh documents the one-liner	curl -fsSL
@STAMP	F_NZ	1	A23 stamper exposes the --all mode	stamp_all=true
@STAMP	F_NZ	1	A23 stamper --all targets every md artifact	"$CHG_DIR"/*.md
@STAMP	F_NZ	1	A23 stamper documents why the governance JSON is excluded	deliberately NOT stamped
@SUITES	F_NZ	1	A23 golden suite covers --all end-to-end	T17b --all stamps the whole change directory
@SUITES	F_NZ	1	A23 golden suite covers the one-command installer	T21 install.sh --from performs a full offline install
EOF
report "A23 project CHANGELOG.md removed — sole history is STANDARDS_CHANGELOG (CHG-050)" 0 "$([[ -e "$ROOT/CHANGELOG.md" ]] && echo 1 || echo 0)"
at_least "A23 README en points at install.sh" 1 "$RM_EN" 'install.sh'
at_least "A23 README zh points at install.sh" 1 "$RM_ZH" 'install.sh'
at_least "A23 MAINTAINER documents the install.sh role" 1 "$ROOT/MAINTAINER.md" 'install.sh'

# ── PART A25: 项目级总册 + 缺陷按天入批形态锚点（v3.35.0，CHG-035/BUG-005）────
# 防五类反向回退：①总册体系被删（规范/方法论/模板三层任一缺失）；②begin/stop
# 的总册机校被静默移除；③缺陷批次化回退为"刻意不入批"；④stamper/审计丢失批次
# 嵌套形态；⑤golden 负例被删导致机校裸奔。
MASTERS_MD="$ROOT/resources/methodologies/project-masters.md"
report "A25 project-masters methodology file exists" 1 "$([[ -s "$MASTERS_MD" ]] && echo 1 || echo 0)"
at_least "A25 methodology defines the thirteen masters" 1 "$MASTERS_MD" '十三册清单'
at_least "A25 methodology defines review-record shape" 1 "$MASTERS_MD" '评审记录必含章节'
at_least "A25 standards §1.3 defines the master set" 1 "$STD" '项目级总册与评审记录（Project Master Set'
at_least "A25 standards pins every-change backfill" 1 "$STD" '项目总册回填清单'
at_least "A25 standards pins first-change initialization" 1 "$STD" 'AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS'
at_least "A25 standards pins the bug diagnosis master-reading clause" 1 "$STD" '诊断前必读总册'
at_least "A25 standards pins the TC-coverage clause for bug fixes" 1 "$STD" '不可覆盖必须新增防回归 TC'
run_audit_rules <<'EOF'
@STD	F_GE	1	A36 standards pins the staged-review clause (v3.53.0, REQ-993)	分阶段评审留痕（v3.53.0，REQ-993）
@STD	F_GE	1	A36 standards pins stage-8 backfill-check row (v3.53.0)	分阶段评审留痕核对
@STD	F_GE	1	A36 standards pins the bug-track machine checkpoint (FU-902)	缺陷轨机校点=绑定 CHG 的 begin
@AGENTS	F_GE	1	A36 AGENTS carries the staged-review hard directive	禁止"只做阶段 8 终审"的收敛执行
@STAGED	F_GE	1	A37 gate checks history-similarity search (v3.54.0, REQ-998)	GATE-E84
@STAGED	F_GE	1	A38 gate checks review-report signature+task id (v3.56.0, REQ-1005)	GATE-E85
@STD	F_GE	1	A25 standards reverses the v3.22.0 no-batch decision	缺陷六件套自 v3.35.0 起同样按天入批
@STD	F_GE	1	A25 standards flattens the bug batch (v3.36.0)	扁平化
@STD	F_GE	1	A25 standards pins the flat anchor form	## <BUG-xxx>
@STAGED	F_NZ	1	A25 gate resolves defect groups across both layouts	bug_group_dir
@STAGED	F_NZ	1	A25 gate sweeps batched bug groups	BATCH-*/BUG-*/
@STAGED	F_NZ	1	A25 gate sweeps flat anchor batches	anchored in more than one day batch
@STAGED	E_NZ	1	A25 gate enforces the bug day-batch default	must join it into the day batch|move it into the day batch
@STAGED	F_NZ	1	A25 gate begin checks the thirteen masters	validate_project_masters
@STAGED	F_NZ	1	A25 gate stop checks the master backfill rows	validate_master_backfill
@STAMP	F_NZ	1	A25 stamper resolves batched bug groups	defect group not found
@AUDIT	F_NZ	1	A25 audit carries G9 masters checks	G9 project masters
@AUDIT	F_NZ	1	A25 audit sweeps batched bug groups	BATCH-*/BUG-*/
@AUDIT	F_NZ	1	A25 audit sweeps flat anchor batches	扁平批次锚点缺件
EOF
masters_n=0
for mf in P00-project-charter P01-requirements-master P02-architecture-master P03-interface-registry P04-data-dictionary P05-task-plan P06-test-master P07-test-verdicts P08-deployment-master P09-risk-register P10-change-ledger P11-decision-log P12-product-context; do
  [[ -s "$ROOT/resources/templates/project/$mf.md" ]] && masters_n=$((masters_n+1))
done
report "A25 thirteen master templates exist" 13 "$masters_n"
report "A25 review-record template exists" 1 "$([[ -s "$ROOT/resources/templates/project/reviews/_template.review.md" ]] && echo 1 || echo 0)"
report "A25 docs map template exists" 1 "$([[ -s "$ROOT/resources/templates/docs-readme.md" ]] && echo 1 || echo 0)"
report "A25 docs map shipped by bootstrap core" 1 "$(a17_at_least_1 "$(grep -c 'resources/templates/docs-readme.md' "$ROOT/scripts/bootstrap.sh" || true)")"
report "A25 audit sweeps out-of-table feature-dir reviews" 1 "$(a17_at_least_1 "$(grep -c 'G9 feature dirs carry no out-of-table reviews/' "$ROOT/resources/templates/audit-docs-consistency.sh" || true)")"

# ── PART A39: UX 条件门锚点（v3.67.0，CHG-090）────────────────────────────
run_audit_rules <<'EOF'
@STAGED	F_GE	1	A39 gate defines the UX conditional lane	validate_ux_conditions
@STAGED	F_GE	1	A39 gate reads the ui_change declaration	ui_change_true
@STAGED	F_GE	1	A39 gate carries E90 (UJ required)	GATE-E90
@STAGED	F_GE	1	A39 gate carries E96 (usability UAT)	GATE-E96
@STAGED	F_GE	1	A39 gate begin requires the P12 master	P12-product-context.md
@AUDIT	F_GE	1	A39 audit carries the G11 UJ coverage criterion	UI-change requirements carry UJ
@AUDIT	F_GE	1	A39 audit carries the G12 five-party criterion	five-party usability evidence
@STD	F_GE	1	A39 standards pins the bare-key ban	禁止 DB 主键
@STD	F_GE	1	A39 standards pins the usability UAT section	用户可用性验收
EOF
report "A39 03.6-ui-spec template exists" 1 "$([[ -s "$ROOT/resources/templates/entry/03.6-ui-spec.md" ]] && echo 1 || echo 0)"
report "A39 P12 product-context template exists" 1 "$([[ -s "$ROOT/resources/templates/project/P12-product-context.md" ]] && echo 1 || echo 0)"
report "A39 schema registers the UX clauses (R44-R50)" 1 "$(a17_at_least_1 "$(grep -c -E '^[|] R4[4-9] [|]|^[|] R50 [|]' "$ROOT/resources/CLAUSE_REGISTRY.md" || true)")"

# ── PART A40: UX lane conditionality (v3.67.0 erratum CHG-091) ────────────────
run_audit_rules <<'EOF'
@STD	F_GE	1	A40 context-pack trigger face is conditional	项目上下文包：未命中
@STD	F_GE	1	A40 context-pack trigger face names ui_change	触发面=`ui_change: true`
@ROOT/resources/methodologies/project-masters.md	F_GE	1	A40 P12 domain-6 whole-domain N/A allowed	项目无用户界面
@SUITES	F_NZ	1	A25 golden pins the out-of-table reviews sweep	audit rejects out-of-table reviews/ in feature dir
@SUITES	F_NZ	1	A25 golden suite pins the master backfill gate	T23 project-master backfill checklist is enforced at stop
@SUITES	F_NZ	1	A25 golden suite pins begin masters check	T23 begin refuses to start without project masters
@SUITES	F_NZ	1	A25 golden suite pins the bug day-batch default	T18c defect groups join the same-day batch
@SUITES	F_NZ	1	A25 golden suite pins the flat bug batch form	T18d flat bug batch
EOF
at_least "A40 entry template carries the miss declaration form" 1 "$ROOT/resources/templates/entry/01-spec.md" '未命中（理由）'
}

# --- A25 v3.38.0：会话水位门 / 产物体量度量 / 入口脚手架（CHG-038/039/040）---
audit_block_c() {
run_audit_rules <<'EOF'
@STAGED	F_NZ	1	A25 gate begin reads the session water level	session-water.json
@STAGED	F_NZ	1	A25 gate water refusal names the escape hatch	AGENT_GUARD_ALLOW_OVER_WATER
@HOOK	F_NZ	1	A25 adapter counts chat.message turns	chat.message
@SG	F_NZ	1	A25 session-gate maintains the water file	session-water.json
@COLD	F_NZ	1	A25 metrics emits artifact cost fields	artifact_bytes
EOF
report "A25 scaffolder template exists" 1 "$([[ -s "$ROOT/resources/templates/new-change.sh" ]] && echo 1 || echo 0)"
report "A25 scaffolder shipped by bootstrap guard" 1 "$(a17_at_least_1 "$(grep -c 'resources/templates/new-change.sh' "$ROOT/scripts/bootstrap.sh" || true)")"
report "A25 entry templates exist (8 core + conditional 03.6 + shape 4, CHG-045)" 13 "$(ls "$ROOT/resources/templates/entry/"* 2>/dev/null | wc -l | tr -d ' ')"
a25_shape=0
for sf in 01.5-rtvm-matrix.md 05-test-results.md 07-review-report.md 09-changelog.md; do
  [[ -s "$ROOT/resources/templates/entry/$sf" ]] && grep -q "$sf" "$ROOT/scripts/bootstrap.sh" && a25_shape=$(( a25_shape + 1 ))
done
report "A25 shape templates present + bootstrap-registered (4: 01.5/05/07/09)" 4 "$a25_shape"
run_audit_rules <<'EOF'
@BS	F_NZ	1	A25 entry templates shipped by bootstrap core	templates/entry
@SUITES	F_NZ	1	A25 golden pins the water gate	T24 begin names the water level
@SUITES	F_NZ	1	A25 golden pins the scaffolder	T25 filled scaffold passes begin
@SUITES	F_NZ	1	A25 golden pins the artifact cost metrics	metrics emits artifact cost fields
@STAGED	F_NZ	1	A25 gate enforces the review-input field	missing review-input
@ROOT/resources/templates/entry/03.5-tasks.md	F_NZ	1	A25 entry 03.5 template carries the input contract	评审输入
@SG	F_NZ	1	A25 telemetry lives in the session-gate common layer	count tool
@HOOK	F_NZ	1	A25 claude adapter forwards telemetry hooks	UserPromptSubmit
@HOOK	F_NZ	1	A25 opencode plugin is a thin forwarder	session-gate.sh count turn
@SUITES	F_NZ	1	A25 golden pins the telemetry suite	T26 idle carries yellow light
@AGENTS	F_NZ	1	A25 AGENTS discipline 10 long-task wait present (REQ-1100)	长任务等待纪律
@AGENTS	F_NZ	1	A25 AGENTS discipline 11 env-attribution present (REQ-1101)	环境归因续跑
@AGENTS	F_NZ	1	A25 AGENTS discipline 11 carries both attribution criteria (TC-1285)	任务类（方案错/理解错）
@SG	F_NZ	1	A25 session-gate carries the sleep-poll threshold env (REQ-1100)	AGENT_GUARD_SLEEP_POLL_LIMIT
@SG	F_NZ	1	A25 session-gate carries the full-test threshold env (REQ-1102)	AGENT_GUARD_FULL_TEST_LIMIT
@SG	F_NZ	1	A25 session-gate counts sleep_polls	sleep_polls
@SG	F_NZ	1	A25 session-gate counts full_suite	full_suite
@YML	F_NZ	1	A25 governance template declares full_test_patterns (commented default-off)	full_test_patterns
@SUITES	F_NZ	1	A25 golden pins the wait/full-suite telemetry suite	T58 TC-1281 sleep yellow light on status
@ROOT/resources/templates/pre-commit	F_NZ	1	A25 pre-commit stamps provenance automatically	stamp-provenance.sh --all
@STAGED	F_NZ	1	A25 gate resolves the P3 defect channel	bug_p3_lightweight
@STAGED	F_NZ	1	A25 gate begin blocks on unresolved session red	AGENT_GUARD_ALLOW_OVER_RED
@STAGED	E_NZ	1	A25 gate die messages carry error codes	die "GATE-E[0-9][0-9]: 
@AUDIT	F_NZ	1	A25 audit sweeps pointer-less deprecated clauses	废止标记缺版本指向
@SUITES	F_NZ	1	A25 golden pins the auto-stamp suite	T27 pre-commit exits 0
@SUITES	F_NZ	1	A25 golden pins the P3 channel	T28 P3 severity waives
@SUITES	F_NZ	1	A25 golden pins the red gate	T29 fresh RED report blocks begin
@SUITES	F_NZ	1	A25 golden pins the G10 sweep	T31 G10 flags pointer-less
@BS	F_NZ	1	A25 uninstaller ships with bootstrap guard	uninstall-standards
@ROOT/resources/templates/uninstall-standards.sh	F_NZ	1	A25 uninstaller self-removes on real run	self — removed last below
@SUITES	F_NZ	1	A25 golden pins the uninstall suite	T32 backup holds the moved asset
EOF
slog_rows=$(grep -cE '^\| v[0-9]+\.[0-9]+\.[0-9]+ \|' "$SLOG" || true)
report "A25 changelog version rows >= 8 (derived floor, no per-version pins)" 1 "$([[ "$slog_rows" -ge 8 ]] && echo 1 || echo 0)"
slog_vs=$(grep -oE '^\| v[0-9]+\.[0-9]+\.[0-9]+ ' "$SLOG" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
slog_n=$(printf '%s\n' "$slog_vs" | grep -c . || true)
slog_order=$(printf '%s\n' "$slog_vs" | awk -F. 'NR==1{p1=$1;p2=$2;p3=$3;next}{if($1+0>p1+0)bad=1;else if($1+0==p1+0){if($2+0>p2+0)bad=1;else if($2+0==p2+0&&$3+0>=p3+0)bad=1}p1=$1;p2=$2;p3=$3}END{if(bad)print 0;else print 1}')
report "A25 changelog version rows strictly descending (continuity, dups fail)" 1 "$([[ "$slog_n" -ge 1 && "$slog_order" == 1 ]] && echo 1 || echo 0)"

run_audit_rules <<'EOF'
@STAMP	F_GE	2	A26 stamp-provenance implements derive_trace_block (REQ-955)	derive_trace_block
@STAMP	F_GE	1	A26 stamp-provenance wires --trace arg (REQ-955)	stamp_trace=true
@AUDIT	F_GE	1	A26 audit G5 asserts 01.5 REQ subset of 01-spec (REQ-956)	01.5 REQ rows all defined in 01-spec
@SUITES	F_GE	1	A26 golden T33 anchors trace derivation (REQ-955)	T33 --trace derives
@ROOT/resources/templates/bug-autointent.sh	F_GE	2	A26 bug-autointent exists with rate-limit window (REQ-958)	AGENT_GUARD_AUTOBUG_WINDOW
@BS	F_GE	1	A26 bootstrap --guard carries bug-autointent (REQ-958)	templates/bug-autointent.sh
@ROOT/resources/templates/uninstall-standards.sh	F_GE	1	A26 uninstall Tier1 covers bug-autointent (REQ-958)	bug-autointent
@ROOT/resources/templates/github-regression-to-bug.yml	F_GE	1	A26 regression workflow template exists (REQ-958)	workflow_run
@SG	F_GE	1	A26 session-gate emits defect-signal interactive options (REQ-959)	缺陷信号交互三选项
@GATE	F_GE	1	A26 gate die writes friction ledger (REQ-960)	gate-friction.tsv
@STAGED	F_GE	1	A26 gate carries L0 minimal-set carve-out (REQ-962)	L0 minimal-set carve-out
@STAGED	F_GE	1	A26 gate rejects declaration-only stubs off L0 (REQ-962)	GATE-E52
@STD	F_GE	1	A26 standards split L0/L1 non-placeholder sets (REQ-962)	L0 最小不可占位集
@STD	F_GE	1	A26 standards retire 08-supplement into 09 (REQ-963)	「补充说明」节
@STD	F_GE	1	A26 standards declare 15-artifact contract (REQ-963/CHG-064)	15 件
@ROOT/tests/audit-standards-src.sh	F_GE	1	A26 audit derives changelog continuity from SLOG (REQ-964)	strictly descending
@SUITES	F_GE	1	A26 golden T37 anchors L0 minimal-set states (REQ-962)	T37 L0 minimal-set
@CR	F_GE	1	A27 registry schema and authority declaration (REQ-968)	权威关系声明
@BS	F_GE	1	A27 bootstrap core ships registry (REQ-971)	CLAUSE_REGISTRY.md
@BS	F_GE	1	A27 bootstrap guard ships generator (REQ-969)	templates/generate-reading-pack.sh
@ROOT/resources/templates/uninstall-standards.sh	F_GE	1	A27 uninstall covers generator (REQ-969)	generate-reading-pack
@ROOT/resources/templates/uninstall-standards.sh	F_GE	1	A27 uninstall covers registry (REQ-971)	CLAUSE_REGISTRY.md
@GATE	F_GE	1	A27 gate exempts generator from code-path (REQ-969)	generate-reading-pack
@STD	F_GE	1	A27 standards define registry clause (REQ-971)	2.17.2c 条款注册表与阅读包
@AGENTS	F_GE	1	A27 AGENTS routes reading pack (REQ-971)	generate-reading-pack
@SUITES	F_GE	1	A27 golden T39 anchors registry capability (REQ-970)	T39 registry schema header
@SUITES	F_GE	1	A27 golden T40 anchors generator capability (REQ-969)	T40 normal generation exits 0
EOF

# ── A39 CLAUSE_REGISTRY E 码索引 ↔ 模板 die 计数互锁（v3.62.0，CHG-080/REQ-1021）──
reg_e=$(grep -c '^| GATE-E' "$ROOT/resources/CLAUSE_REGISTRY.md" || true)
tpl_e=$(grep -hoE 'die "GATE-E[0-9]+' "$GATE_TPL" "$STAGED_TPL" "$COLD_TPL" | grep -oE 'GATE-E[0-9]+' | LC_ALL=C sort -u | wc -l | tr -d ' ')
report "A39 registry GATE-E rows == template die codes (CHG-080/REQ-1021)" "$tpl_e" "$reg_e"
nc10=$(grep -cF 'NC-E10: scripts/agent-gate not found' "$ROOT/resources/templates/new-change.sh" || true)
nc11=$(grep -cF 'NC-E11: check-confirm failed' "$ROOT/resources/templates/new-change.sh" || true)
report "A40 new-change NC-E10/NC-E11 message single-source (CHG-080/REQ-1022)" "1/1" "${nc10}/${nc11}"

# ── A49 六机制机校承接面（v3.99.1，CHG-141/REQ-1375）──────────────────────
run_audit_rules <<'EOF'
@STAGED	F_EQ	2	A49 E104 word table single-source: die site + hint case (CHG-141)	HTTP|DB|响应体|快照|点击链路|截图|几何断言
@STAGED	F_GE	1	A49 E104 head comment declares the three new marker words (CHG-141)	点击链路|截图|几何断言
@STAGED	F_EQ	1	A49 gate_version write literal matches footer (CHG-141/142/143)	gate_receipt_json "$vc_gver"
@STAGED	F_EQ	1	A49 gate_version read literal matches write (CHG-141/142/143)	vc_r_ver" == "$vc_gver"
@GATE_HW	E_EQ	0	A49 no stale gate_version literal (CHG-141/142/143)	gate_version":"[0-9][0-9.]*"
@STAGED	F_GE	1	A49 E104 head comment declares the v3.99.1 evidence classes (CHG-141)	v3.99.1 扩两类
@STAGED	F_GE	1	A49 E107 self-produced marker die text (CHG-141)	评审会话自产 (session-produced)
@STAGED	F_EQ	1	A49 E157 die site is unique (CHG-141)	GATE-E157:
@STAGED	F_GE	1	A49 E157 判定卡 trigger die site exists (CHG-141)	diff touches 被测核心
@STAGED	F_EQ	1	A49 E158 die site is unique (CHG-141)	GATE-E158:
@STAGED	F_EQ	1	A49 E159 die site is unique (CHG-141)	GATE-E159:
@CR	F_EQ	1	A49 REGISTRY indexes GATE-E157 (CHG-141)	| GATE-E157 
@CR	F_EQ	1	A49 REGISTRY indexes GATE-E158 (CHG-141)	| GATE-E158 
@CR	F_EQ	1	A49 REGISTRY indexes GATE-E159 (CHG-141)	| GATE-E159 
@CR	E_EQ	1	A49 REGISTRY registers R84 三查 clause (CHG-141)	^[|] R84 
@STAGED	F_GE	1	A50 preflight probes the stop content face (CHG-142)	p_run validate_mechanism_stop
@ROOT/scripts/update-assertion-count.sh	F_GE	2	A50 update-assertion-count --from-evidence is wired (CHG-142)	--from-evidence
EOF

# ── PART A10: 审计执行数基线自校验（CHG-009 / FU-022）──────────────────────────
# 语义：audit 的实际执行断言数（pass+fail）必须与基线文件一致。断言增删（含不可达
# 死调用）而未同步基线 → 红；红即提示跑 scripts/update-assertion-count.sh 同步。
# 不采用"静态调用数==执行数"口径：if/else 双分支站点使静态数天然≠执行数。
# 基线文件随本变更入库；/tmp 计数文件为本轮运行现场（供生成器 --check 比对）。
# AUDIT_BASELINE/AUDIT_LAST hoisted to setup (REQ-1323 cross-block reads).
# A41（v3.62.1，CHG-081/REQ-1027）：溯源块后空行残留 canary——旧写入路径每跑净增
# 1 空行（BATCH-20260925 12 文件×73 连续空行实证，跨 73 次盖章累积）。规范形块后
# 连续空行必须 ≤1；残留=写入幂等被破坏的前哨（红向实证见 05 §CHG-081）。
canary_viol=0
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  awk '
    /^<!-- provenance$/ { inblk=1; next }
    inblk && /^-->$/ { inblk=0; drain=1; n=0; next }
    inblk { next }
    drain && /^[[:space:]]*$/ { n++; next }
    drain { if (n > 1) exit 1; drain=0; next }
    END { if (drain && n > 1) exit 1 }
  ' "$f" || canary_viol=$(( canary_viol + 1 ))
done < <(find "$REPO_CHANGES" "$REPO_BUGS" -name '*.md' 2>/dev/null)
report "A41 provenance block-tail blank-run canary (REQ-1027)" 0 "$canary_viol"

# A42 payload 通用性硬门槛（2026-10-12 用户硬指令）：本仓 payload 是公共 skill 分发面，
# 禁止任何单一项目特异性内容——项目名/仓路径/领域表字段与界面元素/外部仓 FU·CHG 编号/
# 领域示例词。命中即红（tripwire 扫描，覆盖 review 盲区）。STANDARDS_CHANGELOG 豁免：
# append-only 历史不改写（§2.15），新条目纪律由评审承载（v2.17.0 即通用化改版记录）。
a42_hits=""
for a42_f in $(git ls-files 'resources/*' 'SKILL.md' 'README.md' 'README.zh-CN.md' 'scripts/bootstrap.sh' '.claude-plugin/*' 2>/dev/null); do
  [[ "$a42_f" == "resources/STANDARDS_CHANGELOG.md" || "$a42_f" == "resources/STANDARDS_CHANGELOG_ARCHIVE.md" ]] && continue
  a42_hit=$(grep -nE '儿童内分泌|newCDSScode|CDSS|候诊|预问诊|ptSwitch|btnDemo|FU-942|FU-935|diagnosis-round|observation\(id|ingest 管线|dev\.sh' "$a42_f" 2>/dev/null | head -1)
  [[ -n "$a42_hit" ]] && a42_hits="$a42_hits${a42_f}: ${a42_hit}"$'\n'
done
report "A42 payload genericity — no single-project markers (user hard gate 2026-10-12)" 0 "$([[ -z "$a42_hits" ]] && echo 0 || { printf 'foreign markers:\n%s' "$a42_hits" >&2; echo 1; })"

# A44 private-face drift tripwire (2026-10-16 user directive, CHG-097/REQ-1103):
# 源仓本地安装副本必须与 shipped 模板一致（byte-identical 或 3 行单源 exec wrapper, ITEM-43）。
a44_bad=""
for a44_p in scripts/agent-gate:resources/templates/agent-gate.sh scripts/stamp-provenance.sh:resources/templates/stamp-provenance.sh scripts/session-gate.sh:resources/templates/session-gate.sh scripts/eval-cases:resources/templates/eval-cases.sh scripts/eval-rescore:resources/templates/eval-rescore.sh .githooks/pre-commit:resources/templates/pre-commit; do
  a44_l="$ROOT/${a44_p%%:*}"; a44_t="$ROOT/${a44_p##*:}"; a44_tr="${a44_p##*:}"
  [[ -f "$a44_t" ]] || { a44_bad="$a44_bad${a44_p}(template-missing) "; continue; }
  [[ -f "$a44_l" ]] || continue
  if ! cmp -s "$a44_l" "$a44_t"; then
    if grep -qF "# single-source wrapper -> $a44_tr" "$a44_l" && grep -qF 'exec bash' "$a44_l"; then
      :
    else
      a44_bad="$a44_bad${a44_p} "
    fi
  fi
done
report "A44 local-copy drift vs template (private face == public face, CHG-097)" 0 "$([[ -z "$a44_bad" ]] && echo 0 || { printf 'drifted: %s\n' "$a44_bad" >&2; echo 1; })"

# A45 发现处置闭环 + 评审轮次收敛（v3.74.0，CHG-098/REQ-1104~1107）：五面互锁——门禁 E 码、
# 07 形状模板、规范正文条款、注册表（E 码行 + R 条款行）、golden 节注册。任一面缺失即红
# （单面绿不得声称能力落地；与 A39 计数互锁同源口径）。
run_audit_rules <<'EOF'
@STAGED	E_GE	2	A45 gate carries the disposition gates (E114/E115, CHG-098)	GATE-E11[45]
@STAGED	F_GE	1	A45 gate carries the round-cap gate (E116, CHG-098)	GATE-E116
@STAGED	F_GE	1	A45 gate derives review rounds from the ledger (CHG-098)	review-rounds.tsv
@STAGED	F_GE	1	A45 gate exposes the round-limit knob (CHG-098)	AGENT_GUARD_REVIEW_ROUND_LIMIT
@COLD	F_GE	1	A45 metrics emits the dismissal rate (CHG-098)	dismissal_rate
@ROOT/resources/templates/entry/07-review-report.md	F_GE	1	A45 07 template carries the disposition section (CHG-098)	发现处置
@ROOT/resources/templates/entry/07-review-report.md	F_GE	1	A45 07 template carries the conditional cap-disposition line (CHG-098)	超限处置
@STD	F_GE	1	A45 standards body carries the disposition clause (CHG-098)	发现处置（v3.74.0
@STD	F_GE	1	A45 standards body carries the convergence clause (CHG-098)	评审收敛（v3.74.0）
@STD	F_GE	1	A45 standards body carries the new metric fields (CHG-098)	dismissal_rate
@CR	E_GE	3	A45 registry indexes the new gate codes (CHG-098)	^[|] GATE-E11[456] 
@CR	E_GE	3	A45 registry registers the new clauses (CHG-098)	^[|] R5[678] 
@SUITES	F_GE	1	A45 golden suite registers the T59 section (CHG-098)	T58 T59
@STAGED	E_GE	1	A45 cap-disposition predicate requires a filled line, not a bare word (CHG-098)	\[\^\[:space:\]<\]|[^[:space:]<]
@COLD	E_GE	1	A45 disposition tally skips template placeholder rows (CHG-098)	\^<\.\*>\$|\^<.*>\$
@ROOT/resources/templates/entry/07-review-report.md	E_GE	1	A45 07 template marks its example row as a placeholder (CHG-098)	^[|] <编号> [|]
@ROOT/resources/templates/eval-cases.sh	F_GE	1	A46 eval-cases script ships (CHG-099)	eval-cases — 评测资产派生视图
@ROOT/resources/templates/eval-cases.sh	F_GE	1	A46 eval-cases declares the --verify contract (CHG-099)	--verify
@ROOT/resources/templates/eval-cases.sh	F_GE	1	A46 eval-cases derives the capture layer (CHG-099)	应捕获层
@ROOT/resources/templates/eval-cases.sh	F_GE	1	A46 eval-cases documents the runtime-only discipline (CHG-099)	禁止入库、禁止手编
@ROOT/resources/templates/eval-rescore.sh	F_GE	1	A46 eval-rescore script ships (CHG-099)	eval-rescore — 评测集重打分
@ROOT/resources/templates/eval-rescore.sh	F_GE	1	A46 eval-rescore binds the governance-face hash (CHG-099)	config_sha
@ROOT/resources/templates/eval-rescore.sh	F_GE	1	A46 eval-rescore keeps the null-score contract (CHG-099)	score = null
@ROOT/resources/templates/eval-rescore.sh	F_GE	1	A46 eval-rescore scopes out approval binding (CHG-099)	不含人工审批/放行结论绑定提交
@ROOT/resources/templates/github-reviewer-rescore.yml	F_GE	1	A46 rescore workflow ships with a schedule (CHG-099)	schedule
@ROOT/resources/templates/github-reviewer-rescore.yml	F_GE	1	A46 rescore workflow calls the local script (CHG-099)	scripts/eval-rescore
@STAGED	F_GE	1	A46 gate carries the provenance gate (E117, CHG-099)	GATE-E117
@STAGED	F_GE	1	A46 gate soft-passes legacy 07 shapes (CHG-099)	发现处置表缺「来源」列
@STAGED	F_GE	1	A46 gate counts finding provenance (CHG-099)	finding_source_counts
@COLD	E_GE	1	A46 metrics emits the finding-provenance fields (CHG-099)	findings_introduced|findings_pre_existing
@ROOT/resources/templates/entry/07-review-report.md	E_GE	1	A46 07 template pins the literal provenance header row (CHG-099)	^[|] 编号 [|] 发现 [|] 严重度 [|] 处置 [|] 证据/理由 [|] 来源 [|]$
@ROOT/resources/templates/bug-diagnosis.md	F_GE	2	A46 bug template requires the capture layer (CHG-099)	应捕获层
@STD	F_GE	1	A46 standards body carries the incident review duty (CHG-099)	复盘义务（v3.75.0
@STD	F_GE	1	A46 standards body carries the eval-asset clause (CHG-099)	评测资产与重打分（v3.75.0
@STD	F_GE	1	A46 standards body carries the written priority order (CHG-099)	真缺陷召回优先于轮次下降
@STD	F_GE	1	A46 standards body carries the provenance column (CHG-099)	v3.75.0 增「来源」列
@AGENTS	F_GE	1	A46 AGENTS carries the per-repo review-focus block (CHG-099)	本仓评审要点
@AGENTS	F_GE	1	A46 AGENTS block forbids a second authority (CHG-099)	禁止**另建按仓评审文件
@CR	E_GE	1	A46 registry indexes the new gate code (CHG-099)	^[|] GATE-E117 
@CR	E_GE	3	A46 registry registers the new clauses (CHG-099)	^[|] R(59|60|61) 
@BS	E_GE	3	A46 bootstrap guard installs the eval layer (CHG-099)	eval-cases|eval-rescore|github-reviewer-rescore
@ROOT/resources/templates/uninstall-standards.sh	E_GE	2	A46 uninstall removes the eval runtime scripts (CHG-099)	eval-cases|eval-rescore
@ROOT/resources/templates/uninstall-standards.sh	F_GE	1	A46 uninstall removes the rescore workflow (CHG-099)	github-reviewer-rescore.yml
@SKILL	F_GE	1	A46 SKILL names the eval layer (CHG-099)	eval-cases
@RM_EN	F_GE	1	A46 README (EN) names the eval layer (CHG-099)	eval-cases
@RM_ZH	F_GE	1	A46 README (zh) names the eval layer (CHG-099)	eval-cases
@RUN	F_GE	1	A46 golden suite registers the T62 section (CHG-101)	T60 T61 T62
EOF

# A47 pin 唯一性 + BRE 语义 tripwire（v3.76.0，CHG-100/REQ-1121，候选 8）：把 CHG-099
# 两条同族教训机校化。①结构性 pin（整行锚定）必须钉住**唯一**行——见 at_least_unique
# （`>=` 语义下删掉真结构行仍可能命中注释/兄弟行，恒真陷阱）。
# ②**BRE 口径**：`at_least`/`at_least_unique`/`grep_count`/`grep -c`（无 `-E`）走 BRE，
# `\|` 是**交替**而非字面管道——交替里任何**空分支**（行首 `^\|` / 双连 `\|\|` /
# 尾随 `\|`）都匹配全文件（恒真复现）；字面管道必须写 `[|]`。
# 注：`grep -c -E`/`grep -cE`（ERE）里 `\|` 是**字面管道**，合法——不扫（独立评审
# F11：扫描面必须与检测器口径同族，否则既漏检又假阳）。
# 扫描面=本脚本非注释代码行里"最后一个单引号段"（=模式实参），跳过本 tripwire 自身。
a47_bre=0
while IFS= read -r a47_l; do
  [[ -n "$a47_l" ]] || continue
  case "$a47_l" in *a47_*) continue ;; esac
  a47_pat="${a47_l%\'*}"; a47_pat="${a47_pat##*\'}"
  [[ "$a47_pat" == *'\|'* ]] || continue
  # 把模式按 `\|` 切成分支：**任一分支为空或只含锚点**（`` / `^` / `$`）即恒真。
  # 穷举式（不是只查首尾）——`a\|^\|b` 中间的空锚分支同样要红（独立评审 F11）。
  a47_rest="$a47_pat"
  while :; do
    a47_br="${a47_rest%%'\|'*}"
    case "$a47_br" in ''|'^'|'$') a47_bre=$(( a47_bre + 1 )); break ;; esac
    [[ "$a47_rest" == *'\|'* ]] || break
    a47_rest="${a47_rest#*'\|'}"
  done
done < <(grep -E 'at_least|grep_count|grep -c' "$ROOT/tests/audit-standards-src.sh" 2>/dev/null \
           | grep -vE 'grep -c[[:space:]]*-E|grep -cE' | grep -v '^[[:space:]]*#' || true)
report "A47 no BRE alternation with an empty branch (CHG-100)" 0 "$a47_bre"
at_least_unique "A47 bootstrap snapshots the yml before the layers (CHG-100)" "$ROOT/scripts/bootstrap.sh" '^YML_PRE_STATE="absent"$'
at_least "A47 bootstrap warns when the channel is paused (CHG-100)" 1 "$ROOT/scripts/bootstrap.sh" 'verification channel paused'
at_least_unique "A47 E118 die site is unique in the gate (CHG-100)" "$STAGED_TPL" '^      die "GATE-E118: cannot finish:'
at_least_unique "A47 channel state writer is defined once (CHG-100)" "$STAGED_TPL" '^write_verify_channel() { # <state> <source> <command> <exit_code-json> <reason>$'
at_least_unique "A47 session-gate channel line is defined once (CHG-100)" "$ROOT/resources/templates/session-gate.sh" '^channel_line() {$'
at_least_unique "A47 yml template declares the dialect block once (CHG-100)" "$YML_TPL" '^  # 方言（v3.76.0）'
at_least_unique "A47 registry indexes the new gate code (CHG-100)" "$ROOT/resources/CLAUSE_REGISTRY.md" '^| GATE-E118 '
at_least_unique "A47 registry registers the new clause row (CHG-100)" "$ROOT/resources/CLAUSE_REGISTRY.md" '^| R62 '
at_least_unique "A47 golden section T62 is registered once (CHG-101)" "$ROOT/tests/run-tests.sh" '^SECTIONS=.*T62 '
at_least "A47 suite clears the red archive on a full green run (CHG-100)" 1 "$ROOT/tests/run-tests.sh" 'rm -f "\$SUITE_RED_PATH"'
at_least "A47 channel probe is exposed as a read-only subcommand (CHG-100)" 1 "$STAGED_TPL" 'verify-channel)'
# 整改面（独立评审 F1~F15）：新不变量各自钉一行，防回退。
at_least_unique "A47 channel evidence writer is defined once (CHG-100)" "$STAGED_TPL" '^append_verify_evidence() {'
at_least "A47 evidence append preserves the 05 mtime (CHG-100)" 1 "$STAGED_TPL" 'touch -r "\$ref" "\$tmp"'
at_least "A47 evidence lines are replaced, not appended unboundedly (CHG-100)" 1 "$STAGED_TPL" 'grep -v -e'
at_least "A47 skipped runs never write the channel state (CHG-100)" 1 "$STAGED_TPL" '\[\[ "\$vstate" == "skipped" \]\] || write_verify_channel'
at_least "A47 channel fingerprint carries the yml digest (CHG-100)" 1 "$STAGED_TPL" 'yml:%s'
at_least "A47 reader/probe carry the misplaced-key detail (CHG-100)" 2 "$STAGED_TPL" 'misplaced'
at_least "A47 the BRE tripwire ignores ERE counts (CHG-100)" 1 "$ROOT/tests/audit-standards-src.sh" 'grep -vE .grep -c\[\[:space:\]\]\*-E'
at_least "A47 standards enumerates the four states correctly (CHG-100)" 1 "$STD" '四态 absent/placeholder/tampered/unparsable'
at_least "A47 stop lane rejects an unparsable channel with rc 2 (CHG-100)" 1 "$ROOT/tests/suites/suite-06-runner.sh" 'TC-1339b stop lane rejects an unparsable channel'
at_least "A47 skip-verify behaviour is pinned (CHG-100)" 1 "$ROOT/tests/suites/suite-06-runner.sh" 'TC-1341b SKIP_VERIFY does not execute'

# A48 治理面口径 + 下发面缺口（v3.78.0，CHG-102/REQ-1129~1141）：本版全部是"声称的覆盖面
# ≠ 实际覆盖面"类静默失效，故每面都**反例与正例成对**——只写"改完形态在位"挡不住回退到
# 改前形态（源仓采样 / 死链路径 / 无限定指针 / 改了必检项名）。反例串一律钉改前形态。
at_least "A48 eval-rescore samples the installed docs face (CHG-102)" 4 "$ROOT/resources/templates/eval-rescore.sh" 'face_add "\$docs_dir/'
at_least "A48 eval-rescore resolves the docs root (CHG-102)" 1 "$ROOT/resources/templates/eval-rescore.sh" 'AGENT_GUARD_DOCS_DIR'
report "A48 eval-rescore never samples the source tree as its primary face (CHG-102)" 0 "$(grep_count "$ROOT/resources/templates/eval-rescore.sh" '^face_add resources/')"
report "A48 eval-rescore source/template byte-identical (CHG-102)" 0 "$([[ ! -f "$ROOT/scripts/eval-rescore" ]] && echo 0 || { cmp -s "$ROOT/scripts/eval-rescore" "$ROOT/resources/templates/eval-rescore.sh" && echo 0 || { grep -qF '# single-source wrapper -> resources/templates/eval-rescore.sh' "$ROOT/scripts/eval-rescore" && grep -qF 'exec bash' "$ROOT/scripts/eval-rescore" && echo 0 || echo 1; }; })"
A48_WF="$ROOT/resources/templates/github-reviewer-rescore.yml"
# paths 块按缩进取段（注释行说明改前形态，不计入）：块内零源仓路径 + 9 条安装落点
a48_paths=$(awk '/^[[:space:]]+paths:/{f=1;next} f && /^[[:space:]]*[[:alnum:]_]/ && !/^[[:space:]]*#/{exit} f{print}' "$A48_WF")
report "A48 rescore workflow push paths carry no source-repo path (CHG-102)" 0 "$(printf '%s\n' "$a48_paths" | grep -v '^[[:space:]]*#' | grep -c 'resources/')"
report "A48 rescore workflow push paths list nine installed anchors (CHG-102)" 9 "$(printf '%s\n' "$a48_paths" | grep -c '^[[:space:]]*- ')"
at_least "A48 pre-push template calls the strict branch gate (CHG-102)" 1 "$ROOT/resources/templates/pre-push" 'agent-gate --stage ci --base'
at_least "A48 commit-msg template forwards the message file (CHG-102)" 1 "$ROOT/resources/templates/commit-msg" 'agent-gate --stage commit-msg "\$1"'
at_least_unique "A48 required-check job name is preserved verbatim (CHG-102)" "$GOV_WF" '^    name: agent-governance$'
at_least_unique "A48 aggregator needs both parallel jobs (CHG-102)" "$GOV_WF" '^    needs: \[governance, verify\]$'
at_least_unique "A48 aggregator runs unconditionally (CHG-102)" "$GOV_WF" '^    if: always()$'
at_least "A48 aggregator fails on any non-success dependency (CHG-102)" 1 "$GOV_WF" 'an upstream job did not succeed'
at_least "A48 verification command stays fail-closed when unset (CHG-102)" 1 "$GOV_WF" 'Set repository variable AGENT_GUARD_VERIFY_COMMAND'
report "A48 only the two working jobs check out (aggregator does no work) (CHG-102)" 2 "$(grep_count "$GOV_WF" 'uses: actions/checkout@v5')"
report "A48 gate help no longer claims the 12-master range (CHG-102)" 0 "$(grep_count "$COLD_TPL" 'P00\.\.P11')"
at_least "A48 gate help names the 13-master range (CHG-102)" 1 "$COLD_TPL" 'P00\.\.P12'
report "A48 gate source/template byte-identical (CHG-102; source-only face absent on fresh clone = SKIP, A44 semantics)" 0 "$([[ ! -f "$ROOT/scripts/agent-gate" ]] && echo 0 || { cmp -s "$ROOT/scripts/agent-gate" "$GATE_TPL" && echo 0 || { grep -qF '# single-source wrapper -> resources/templates/agent-gate.sh' "$ROOT/scripts/agent-gate" && grep -qF 'exec bash' "$ROOT/scripts/agent-gate" && echo 0 || echo 1; }; })"
report "A48 SKILL never names a shipped script with a .sh suffix (CHG-102)" 0 "$(grep_count "$SKILL" 'install-hook-adapter.sh')"
at_least_e "A48 usage lists the guard-layer entry scripts (CHG-102)" 2 "$ROOT/scripts/bootstrap.sh" 'bug-autointent|generate-reading-pack.sh'
at_least "A48 usage lists the regression workflow (CHG-102)" 1 "$ROOT/scripts/bootstrap.sh" 'regression-to-bug.yml'
report "A48 DS carries no authority pointer at a non-shipped file (CHG-102)" 0 "$(grep_count "$STD" 'MAINTAINER §')"
at_least "A48 DS points at the shipped intent template (CHG-102)" 1 "$STD" 'templates/entry/00-intent.md'
report "A48 standards body ratchet (CHG-107; ratcheted v4.9.0 CHG-154)" 1 "$([[ "$std_bytes" -le 163840 ]] && echo 1 || echo 0)"
# v3.80.0 (CHG-107, REQ-1152/1153): scaffold single-sourcing + phase read-set pins.
run_audit_rules <<'EOF'
@STAGED	F_GE	1	A49 gate carries the scaffold generator (CHG-107)	scaffold_change()
@STAGED	F_GE	1	A49 gate usage names --scaffold (CHG-107)	usage: scripts/agent-gate begin <change-id> [--risk L0|L1|L2|L3] [--scaffold]
@AGENTS	F_GE	1	A49 AGENTS carries the phase read-set discipline (CHG-107)	分阶段最小读集（v3.80.0
@CR	E_EQ	1	A49 registry registers R65 (CHG-107)	^[|] R65 
@STD	F_EQ	1	A49 DS carries the read-set pointer (CHG-107)	分阶段最小读集（v3.77.0/v3.80.0，CHG-101/107，REQ-1124/1125/1153）
@CR	E_EQ	1	A48 registry registers R64 (CHG-102)	^[|] R64 
@STD	E_EQ	1	A48 R64 anchor resolves to a single standards line (CHG-102)	^> \*\*冻结树并行派发（REQ-1140）\*\*
@AGENTS	F_GE	1	A48 AGENTS carries the parallel-dispatch discipline (CHG-102)	冻结树并行派发（v3.78.0
@SUITES	E_GE	1	A48 golden suite defines the T63 section (CHG-102)	^section_T63\(\) \{
@RUN	E_EQ	1	A48 golden section T63 is registered once (CHG-102)	^SECTIONS=.*T63 
@SUITES	F_EQ	0	A48 no long-stale version literal survives in a T48 label (CHG-102)	carries v3.75.0
EOF

# v3.81.0 (CHG-108): 文档-实现对账钉（TC-1409）——README 双语失真修复后的防回归面。
# 每条锚点对应 01-spec REQ-1155 的一项修订；README 是 payload，失真即契约失真。
report "A50 README en carries no 12-volume literal (CHG-108)" 0 "$(grep_count "$ROOT/README.md" '12-volume')"
report "A50 README zh carries no 12-volume literal (CHG-108)" 0 "$(grep_count "$ROOT/README.zh-CN.md" '12-volume')"
at_least "A50 README en states the 13-volume master set (CHG-108)" 1 "$ROOT/README.md" '13-volume master set'
at_least "A50 README en positions as AI agent skill (CHG-108)" 1 "$ROOT/README.md" 'is an \*\*AI agent skill\*\*'
at_least "A50 README zh positions as Agent 技能 (CHG-108)" 1 "$ROOT/README.zh-CN.md" '是一个 \*\*Agent 技能\*\*'
at_least "A50 README en documents --self-update (CHG-108)" 1 "$ROOT/README.md" '--self-update'
at_least "A50 README zh documents --self-update (CHG-108)" 1 "$ROOT/README.zh-CN.md" '--self-update'
at_least "A50 README en has a dedicated uninstall section (CHG-108)" 1 "$ROOT/README.md" '^## Uninstalling'
at_least "A50 README zh has a dedicated uninstall section (CHG-108)" 1 "$ROOT/README.zh-CN.md" '^## 卸载'
at_least "A50 README en documents the Tier1 outright-delete semantics (CHG-108)" 1 "$ROOT/README.md" 'Deleted \*\*outright, even if modified\*\*'
at_least "A50 README zh documents the Tier1 outright-delete semantics (CHG-108)" 1 "$ROOT/README.zh-CN.md" '一律直接删除，含被改动者'
at_least "A50 README en upgrade section discloses kept semantics (CHG-108)" 1 "$ROOT/README.md" 'which are kept untouched and reported'
at_least "A50 README zh upgrade section discloses kept semantics (CHG-108)" 1 "$ROOT/README.zh-CN.md" '原样保留并报告'
at_least "A50 README en --as-skill requires the full link path (CHG-108)" 1 "$ROOT/README.md" 'full link path including the skill name'
at_least "A50 README zh --as-skill requires the full link path (CHG-108)" 1 "$ROOT/README.zh-CN.md" '含 skill 名的完整链接路径'
at_least "A50 README en CI section names both jobs (CHG-108)" 1 "$ROOT/README.md" 'no soft mode and no double run'
at_least "A50 README zh CI section names both jobs (CHG-108)" 1 "$ROOT/README.zh-CN.md" '不再软门、不再双跑'

# v3.81.0 (CHG-108): CI 守卫钉（TC-1407）——ci.yml 每job超时 + workflow级并发取消。
at_least "A51 ci.yml bounds each job with timeout-minutes (CHG-108)" 2 "$ROOT/.github/workflows/ci.yml" 'timeout-minutes: 15'
at_least "A51 ci.yml declares a concurrency group (CHG-108)" 1 "$ROOT/.github/workflows/ci.yml" '^concurrency:'
at_least "A51 ci.yml cancels superseded runs (CHG-108)" 1 "$ROOT/.github/workflows/ci.yml" 'cancel-in-progress: true'
at_least "A51 install.sh states staleness on pull failure (CHG-108)" 1 "$ROOT/scripts/install.sh" 'possibly stale'

# v3.82.0 (CHG-109/SC-1859): 秒级形状探针 + 睡眠防护 + 遥测失联兜底钉——目标会话
# 5 轮格式返工 ×16min verify（4 轮可避免）实证驱动的三条反馈回路缩短面。声称面 =
# 校验面：拆分函数/探针接线/caffeinate 包裹/黄灯/自证任一被拆，本组红而非静默退化。
run_audit_rules <<'EOF'
@STAGED	F_GE	2	A52 gate splits delivery into probe-safe front face (CHG-109)	validate_delivery_shape_front
@STAGED	F_GE	2	A52 gate splits delivery into probe-safe back face (CHG-109)	validate_delivery_shape_back
@STAGED	F_GE	1	A52 preflight wires the front shape face (CHG-109)	p_run validate_delivery_shape_front
@STAGED	F_GE	1	A52 preflight wires the back shape face (CHG-109)	p_run validate_delivery_shape_back
@STAGED	F_GE	1	A52 round-ledger write documented stop-lane-only (CHG-109)	round-ledger write stays
@COLD	F_GE	1	A52 preflight usage discloses the widened face (CHG-109)	v3.82.0 adds the delivery shape face
@STAGED	F_GE	1	A52 verify channel wraps in caffeinate when available (CHG-109)	caffeinate -dims bash -lc
@STAGED	F_GE	1	A52 darwin missing-caffeinate warning stays loud (CHG-109)	WARNING: caffeinate unavailable or disabled
@STAGED	F_GE	2	A52 begin carries the telemetry-liveness backstop (CHG-109)	YELLOW liveness
@HOOK	F_GE	2	A52 hook adapter carries the post-wiring self-proof (CHG-109)	self-proof
@AGENTS	F_GE	1	A52 AGENTS entry step discloses the widened probe (CHG-109)	v3.82.0 起并收 stop 侧交付形状面
@ROOT/scripts/lib-suite-tree-fingerprint.sh	F_GE	1	A53 lib takes optional reset claims (CHG-110)	local claims=("$@")
@ROOT/scripts/lib-suite-tree-fingerprint.sh	F_GE	1	A53 lib documents the claim face (CHG-110)	docs/changes) so doc-only edits
@STAGED	F_GE	1	A53 gate sources the fingerprint lib (CHG-110)	lib-suite-tree-fingerprint.sh
@STAGED	F_GE	1	A53 gate fingerprints with the docs/changes claim (CHG-110)	suite_tree_fingerprint "$repo_root" "docs/changes"
@STAGED	F_GE	1	A53 receipt carries the gate version key (CHG-110)	"gate_version":"%s"
@STAGED	F_GE	1	A53 receipt is rc0-only and change-bound (CHG-110)	"rc":0
@STAGED	F_GE	1	A53 TTL is env-tunable with a numeric guard (CHG-110)	AGENT_GUARD_VERIFY_CACHE_TTL
@STAGED	F_GE	2	A53 opt-out env is honored at both read and write (CHG-110)	AGENT_GUARD_VERIFY_CACHE:-1
@STAGED	F_GE	1	A53 cached run surfaces a CACHED line and evidence (CHG-110)	CACHED (receipt match
@STAGED	F_GE	1	A53 non-git repos degrade to always-run (CHG-110)	Non-git repos (empty fingerprint) degrade
@COLD	E_GE	1	A53 usage discloses the opt-out boundary (CHG-110)	external mutable state set AGENT_GUARD_VERIFY_CACHE[=]0
@SUITES	E_GE	1	A53 golden section T66 is defined (CHG-110)	^section_T66\(\) \{
@RUN	E_EQ	1	A53 golden section T67 is registered once (CHG-110 tail; CHG-111 joins)	^SECTIONS=.* T67 
@RUN	E_EQ	1	A53 golden section T68 is registered once (CHG-113 lock joins)	^SECTIONS=.* T68 
@SUITES	E_GE	1	A52 golden section T65 is defined (CHG-109)	^section_T65\(\) \{
@RUN	E_EQ	1	A52 golden section T65 is registered once (CHG-109)	^SECTIONS=.*T65 
EOF

# A54 读集一致性（v3.86.0，CHG-113）：AGENTS 规则 1 曾要求“完整读取 DS”，规则 15
# 又要求“永不整读”——两版并存的直接矛盾会让 Agent 二选一而无法判定合规，且标题
# 计数“十四条”与实际 15 条漂移。声称面=校验面：矛盾句/计数任一回潮，本组红。
a54_rule_count=$(awk '/^## Agent 执行资源纪律/{f=1;next} f&&/^## /{exit} f&&/^[0-9]+\. /{n++} END{print n+0}' "$AGENTS")
report "A54 AGENTS discipline heading count matches numbered items (CHG-113)" 15 "$a54_rule_count"
report "A54 AGENTS carries no full-read directive (CHG-113)" 0 "$(grep -cF '__完整读取__' "$AGENTS" 2>/dev/null || true)"
report "A54 AGENTS states the never-read-full rule (CHG-113)" 1 "$(grep -cF '禁止整读全文' "$AGENTS" 2>/dev/null || true)"
report "A54 README zh states 15 rules (CHG-113)" 1 "$(grep -cF '十五条' "$RM_ZH" 2>/dev/null || true)"
report "A54 README en states 15 rules (CHG-113)" 1 "$(grep -cF '**15-rule**' "$RM_EN" 2>/dev/null || true)"

# A54b 源审计计数的声称面（v3.86.0，CHG-113）：A3 的计数正则刻意不匹配
# "assertions: N" 后置形态（FU-009 已知残余），于是 README 里的源审计执行数
# 长期无人看守（实测 595 vs 基线 612）。这里把两语 README 的数字与基线互锁。
a54b_base=$(tr -d '[:space:]' < "$ROOT/tests/.audit-baseline" 2>/dev/null || true)
a54b_en=$(grep -oE '\(assertions: [0-9]+\)' "$RM_EN" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
a54b_zh=$(grep -oE '（断言：[0-9]+）' "$RM_ZH" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
report "A54b README source-audit counts match the baseline (CHG-113)" 2 \
  "$([[ -n "$a54b_base" && "$a54b_en" == "$a54b_base" && "$a54b_zh" == "$a54b_base" ]] && echo 2 || echo 0)"

# A55 DS §4 ↔ entry/09 单一形状权威（v3.86.1，CHG-114）：§4 曾内嵌 9,224 B 的
# 09 模板副本，与模板双维护；压缩后 §4 只留节名与机校口径。七条断言钉住防回潮：
#   ① §4 抽取非空；② §4 不得再出现任意缩进/样式的代码围栏（```/~~~）或任何勾选行
#      副本（P 行/Bug 行，[ ] 或 [x]；`-`/`*` 均可）；③ §4 必须点名
#   模板为唯一形状权威；④ §4 与模板均含十四节规范标题且逐字一致（名单钉）；
#   ⑤ 模板 P00–P12 十三行且顺序固定；⑥ 模板 Bug 十项；⑦ DS §4 十三行口径不得回退到 P00–P11。
a55_s4=$(awk '/^## 4\. Changelog/{w=1} /^## 5\. /{exit} w{print}' "$STD")
a55_tpl="$ROOT/resources/templates/entry/09-changelog.md"
report "A55 DS section4 extraction non-empty (CHG-114)" 1 "$([[ -n "$a55_s4" ]] && echo 1 || echo 0)"
report "A55 DS section4 carries no inline changelog template copy (CHG-114)" 0 \
  "$(( $(printf '%s\n' "$a55_s4" | grep -cE '^[[:space:]]*(```|~~~)' || true) + $(printf '%s\n' "$a55_s4" | grep -cE '^[[:space:]]*[-*][[:space:]]+\[[ x]\]' || true) ))"
report "A55 DS section4 names entry/09-changelog.md as the sole shape authority (CHG-114)" 1 \
  "$(printf '%s\n' "$a55_s4" | grep -cF '形状唯一权威 = `entry/09-changelog.md` 模板' || true)"
a55_expect_heads=$(printf '%s\n' \
  '#### 追踪矩阵映射 (Traceability)' \
  '#### 现象' \
  '#### 分析' \
  '#### 根因' \
  '#### 方案' \
  '#### 测试脚本与结论' \
  '#### 项目总册回填清单（每次 CHG 必填，§1.3）' \
  '#### Bug 修复回填清单（Bug 修复类必填，§2.5 阶段 6；非缺陷类删除）' \
  '#### 角色签署与独立性（门禁 5）' \
  '#### 执行记录（ReAct，§2.16.2 铁律）' \
  '#### 变更执行检查清单（§3 归档落点；唯一权威在 §3）' \
  '#### 未验证 REQ 清单' \
  '#### 未动项' \
  '#### 重要上下文' \
  '#### 发布与回滚记录（进入发布时必填，§2.7）' | sort)
a55_ds_heads=$(printf '%s\n' "$a55_s4" | grep '^#### ' | sed 's/[[:space:]]*$//' | sort)
a55_tpl_heads=$(grep '^#### ' "$a55_tpl" | sed 's/[[:space:]]*$//' | sort)
report "A55 DS section4 and entry/09 carry the fifteen canonical section headings (CHG-114)" 1 \
  "$([[ "$a55_ds_heads" == "$a55_expect_heads" && "$a55_tpl_heads" == "$a55_expect_heads" ]] && echo 1 || echo 0)"
a55_row_seq=$(sed -nE 's/^- \[ \] (P[0-9]{2}) .*/\1/p' "$a55_tpl" | tr '\n' ' ')
a55_expect_row_seq='P00 P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12 '
report "A55 entry/09 template carries P00-P12 in order (13 master rows) (CHG-114)" 13 \
  "$([[ "$a55_row_seq" == "$a55_expect_row_seq" ]] && echo 13 || echo 0)"
report "A55 entry/09 template carries the ten-item Bug backfill checklist (CHG-114)" 10 \
  "$(awk '/^#### Bug 修复回填清单/,/^#### [^B]/' "$a55_tpl" | grep -cE '^- \[ \]' || true)"
# Two intentional occurrences: the 逐字归档 invariant bullet and the 项目总册回填清单 body.
report "A55 DS section4 states the P00-P12 thirteen-row rule (CHG-114)" 2 \
  "$(printf '%s\n' "$a55_s4" | grep -cF 'P00–P12 十三行' || true)"

# A56 套件基线 + 源层工具链 + 公开/私有边界（v3.87.0，CHG-115，REQ-1184~1193）：
# 本批改的是"谁在什么时候跑全量套件"和"哪些能力属于下发载荷"。十四类钉：
#   ① 七个源层工具在位且可解析；② 每个工具声明 source-layer 边界；③ bootstrap 清单
#   不含任何一个（源层工具一旦被复制进目标仓就成了公开能力）；④ tests/.suite-baseline
#   存在、纯数字、不被忽略，且两份基线与七个工具一律受跟踪（提交式证据：CI 全新检出读得到才算）；
#   ⑤ A3 走 --from-baseline、不再有裸
#   --check 回退；⑥ 生成器两种快速模式都在（基线消费 + 收据强制 fail-closed）；
#   ⑦ 变异目录固定四类；⑧ T69~T73b 六节注册、各自带源层缺失 SKIP 分支，且断言排在
#   SKIP 分支之后（目标仓只拿到 run-tests.sh，守卫前置的断言会让下发的套件变红）；
#   ⑨ CI 有基线硬门与汇总步，且 source-audit 不再排在套件后面；⑩ 双 README 的 B 面列出四个入口工具；
#   ⑪ 私有执行纪律（PD-1~PD-5）落在 .opencode/ 且 ⑫ 从不出现在受跟踪面上
#   （⑫ 的扫描集含未跟踪新文件——未 add 的改动一提交就成了载荷；除机器锚点外还扫
#   中文措辞本身，覆盖受跟踪全集而不只是载荷，因为源层文件同样受跟踪）；
#   ⑬ .opencode/ 目录本身不受跟踪；⑭ 套件收据复用规则被 verify-all 与生成器共享。
a56_self="$ROOT/tests/audit-standards-src.sh"
# a56_suite hoisted to the setup region (REQ-1323 cross-block reads).
a56_gen="$ROOT/scripts/update-assertion-count.sh"
a56_ci="$ROOT/.github/workflows/ci.yml"
a56_tools="lib-source-facts.sh facts.sh verify-all.sh pre-review-check.sh mutation-check.sh ci-summary.sh batch-metrics.sh"
a56_missing=0
for a56_t in $a56_tools; do
  [[ -f "$ROOT/scripts/$a56_t" ]] || { echo "A56: missing source tool scripts/$a56_t" >&2; a56_missing=$(( a56_missing + 1 )); continue; }
  bash -n "$ROOT/scripts/$a56_t" 2>/dev/null || { echo "A56: scripts/$a56_t does not parse" >&2; a56_missing=$(( a56_missing + 1 )); }
done
report "A56 the seven source-layer tools exist and parse (CHG-115)" 0 "$a56_missing"

a56_hdr=0
for a56_t in $a56_tools; do
  grep -qF 'Source-layer only (NOT shipped with the Skill)' "$ROOT/scripts/$a56_t" 2>/dev/null \
    || { echo "A56: scripts/$a56_t lacks the source-layer boundary header" >&2; a56_hdr=$(( a56_hdr + 1 )); }
done
report "A56 every source tool declares the source-layer boundary (CHG-115)" 0 "$a56_hdr"

a56_ship=0
for a56_t in $a56_tools; do
  grep -qF "$a56_t" "$ROOT/scripts/bootstrap.sh" \
    && { echo "A56: bootstrap.sh would ship the source-only tool $a56_t" >&2; a56_ship=$(( a56_ship + 1 )); }
done
report "A56 bootstrap payload list excludes every source-only tool (CHG-115)" 0 "$a56_ship"

a56_base_num=""
[[ -f "$ROOT/tests/.suite-baseline" ]] && a56_base_num=$(tr -d '[:space:]' < "$ROOT/tests/.suite-baseline")
a56_base_ok=0
case "$a56_base_num" in ''|*[!0-9]*) ;; *) a56_base_ok=1 ;; esac
git -C "$ROOT" check-ignore -q tests/.suite-baseline 2>/dev/null && a56_base_ok=0
report "A56 tests/.suite-baseline is numeric and never git-ignored (CHG-115)" 1 "$a56_base_ok"

# Review round 1 finding: "not ignored" is not "committed". The baseline is the
# submitted evidence CI reads, so it must be in the index; the same holds for the
# audit baseline and the seven source tools a fresh checkout needs to exist.
a56_untracked=0
for a56_t in tests/.suite-baseline tests/.audit-baseline; do
  git -C "$ROOT" ls-files --error-unmatch "$a56_t" >/dev/null 2>&1 \
    || { echo "A56: $a56_t is not tracked — CI on a fresh checkout cannot read it" >&2; a56_untracked=$(( a56_untracked + 1 )); }
done
for a56_t in $a56_tools; do
  git -C "$ROOT" ls-files --error-unmatch "scripts/$a56_t" >/dev/null 2>&1 \
    || { echo "A56: scripts/$a56_t is not tracked" >&2; a56_untracked=$(( a56_untracked + 1 )); }
done
report "A56 both count baselines and all seven source tools are tracked (CHG-115)" 0 "$a56_untracked"

report "A56 A3 consumes the baseline and keeps no bare --check fallback (CHG-115)" 1 \
  "$([[ $(grep -cF -- '--check --from-baseline' "$a56_self") -ge 1 ]] && [[ $(grep -cF "\"\$GEN\" --check 2>&1" "$a56_self") -eq 0 ]] && echo 1 || echo 0)"

a56_genmodes=0
grep -qF -- '--from-baseline' "$a56_gen" && a56_genmodes=$(( a56_genmodes + 1 ))
grep -qF -- '--require-receipt' "$a56_gen" && a56_genmodes=$(( a56_genmodes + 1 ))
report "A56 the generator carries both fast evidence modes (CHG-115)" 2 "$a56_genmodes"

# Review round 1, R3: the generator must not keep a second receipt-trust
# implementation — it delegates to sf_receipt_fresh and parses no JSON itself.
a56_delegate=0
grep -qF "lib-source-facts.sh" "$a56_gen" || a56_delegate=$(( a56_delegate + 1 ))
grep -qF "sf_receipt_fresh" "$a56_gen" || a56_delegate=$(( a56_delegate + 1 ))
# v3.93.0 (CHG-130, REQ-1295): the old pattern `grep -qE "s/\.\*"passed""`
# concatenated to `s/\.\*passed` and could never match, so this lane was a
# permanent false green. The violation it means to catch is a hand-rolled JSON
# read of the receipt's passed count — that always spells the quoted key.
grep -qF '"passed"' "$a56_gen" && a56_delegate=$(( a56_delegate + 1 ))
report "A56 the generator delegates receipt trust to the single implementation (CHG-115)" 0 "$a56_delegate"

# v3.93.0 (CHG-130, REQ-1294): is_code_path's exclusion face is replicated in
# three files with a pinned sync duty. A missing entry makes the SAME path code
# in one gate and governance in another (fresh-clone-check.sh was absent twice).
a59_required='agent-gate session-gate.sh install-hook-adapter install-ci-adapter check-standards-compliance.sh stamp-provenance.sh generate-reading-pack.sh behavior-extract.sh lib-suite-tree-fingerprint.sh lib-suite-lock.sh shard-sum.sh evidence-round.sh run-tests.sh audit-docs-consistency.sh fresh-clone-check.sh'
a59_missing=0; a59_seen=0; a59_mutants=0
for a59_f in "$ROOT/resources/templates/agent-gate.sh" "$ROOT/resources/templates/session-gate.sh" "$ROOT/resources/templates/audit-docs-consistency.sh"; do
  [[ -f "$a59_f" ]] || continue
  a59_seen=$(( a59_seen + 1 ))
  # Only the alternation line carries the exclusion face. Searching the whole
  # function body was a false green: the surrounding comments name
  # fresh-clone-check.sh / stamp-provenance.sh, so deleting an entry from the
  # regex still matched. Drop backslashes so `session-gate\.sh` matches the
  # `session-gate.sh` token.
  a59_body=$(grep -m1 -i -E 'githooks_re\}/\|' "$a59_f" 2>/dev/null || true)
  a59_body=${a59_body//\\/}
  for a59_t in $a59_required; do
    [[ "$a59_body" == *"$a59_t"* ]] || a59_missing=$(( a59_missing + 1 ))
  done
  [[ "$a59_f" == *agent-gate.sh ]] || continue
  # Mutation self-test: deleting one required token from the extracted line must
  # make the same token loop report a miss (proves the assertion can fail).
  # Target a token from $a59_required itself: the exclusion face escapes dots
  # (`fresh-clone-check\.sh`), so a literal removal never matches that entry.
  a59_first=${a59_required%% *}
  a59_mut=${a59_body/$a59_first/}
  a59_mut_missing=0
  for a59_t in $a59_required; do
    [[ "$a59_mut" == *"$a59_t"* ]] || a59_mut_missing=$(( a59_mut_missing + 1 ))
  done
  [[ "$a59_mut_missing" -ge 1 ]] && a59_mutants=1
done
if [[ "$a59_seen" -eq 3 ]]; then
  report "A59 is_code_path replicas carry the same tool set (CHG-130 REQ-1294)" 0 "$a59_missing"
  report "A59 mutation of the exclusion face is detectable (CHG-130 REQ-1294)" 1 "$a59_mutants"
else
  report "A59 all three is_code_path replicas exist (CHG-130 REQ-1294)" 3 "$a59_seen"
fi

# v3.93.0 (CHG-130, REQ-1297): a GATE-Exxx code must have exactly one hint arm —
# bash only ever uses the first match, so later duplicates were dead code that
# read like a second, different contract.
a60_dup=$(sed -n '/^gate_hint()/,/^}/p' "$STAGED_TPL" 2>/dev/null | grep -o 'GATE-E[0-9]\+' | sort | uniq -d | wc -l | tr -d ' ')
report "A60 every gate_hint code is defined exactly once (CHG-130 REQ-1297)" 0 "$a60_dup"

# v3.93.0 (CHG-130, REQ-1296): the tests copy is what T26c executes; it must be
# the shipped payload byte for byte (it had drifted to the pre-14-column writer).
a61_p="$ROOT/resources/templates/audit-docs-consistency.sh"
a61_t="$ROOT/tests/audit-docs-consistency.sh"
if [[ -f "$a61_p" && -f "$a61_t" ]]; then
  if cmp -s "$a61_p" "$a61_t" \
    || { grep -qF '# single-source wrapper -> resources/templates/audit-docs-consistency.sh' "$a61_t" && grep -qF 'exec bash' "$a61_t"; }; then
    report "A61 tests audit copy is byte-identical to the payload (CHG-130 REQ-1296)" 0 0
  else
    report "A61 tests audit copy is byte-identical to the payload (CHG-130 REQ-1296)" 0 1
  fi
else
  report "A61 both audit copies exist (CHG-130 REQ-1296)" 1 0
fi

# One baseline-number parser (v3.87.0 R4, finding #9). sf_baseline_num is the
# recipe; a second `tr -d` + digit case is how the empty-string hole reopens.
# Scope: the read-only consumers and CI. The generator keeps its own pre-lib
# validation at update-assertion-count.sh:89 — it runs before the optional
# `source lib-source-facts.sh` (line ~106) and must print the raw content it
# rejected, which sf_baseline_num (empty on any failure) cannot.
a56_parse_bad=0
# The four tools that actually read a count baseline themselves. Naming them beats
# the earlier "does the file mention the baseline path" heuristic: verify-all only
# forwards to ci-summary and facts.sh delegates to this very lib, so the heuristic
# certified the wrong files — it went red on a header comment the first time the
# gate step's documentation mentioned the path (v3.87.0 R4, self-caught).
for a56_f in mutation-check.sh ci-summary.sh batch-metrics.sh pre-review-check.sh; do
  grep -qF 'sf_baseline_num' "$ROOT/scripts/$a56_f" \
    || { echo "A56: scripts/$a56_f reads a count baseline without sf_baseline_num" >&2; a56_parse_bad=$(( a56_parse_bad + 1 )); }
  grep -qF "tr -d '[:space:]' <" "$ROOT/scripts/$a56_f" \
    && { echo "A56: scripts/$a56_f still parses a baseline by hand" >&2; a56_parse_bad=$(( a56_parse_bad + 1 )); }
done
grep -qF 'sf_baseline_num' "$a56_ci" \
  || { echo "A56: CI re-implements the baseline number parse instead of sourcing the lib" >&2; a56_parse_bad=$(( a56_parse_bad + 1 )); }
report "A56 the count baselines are parsed by one recipe everywhere (CHG-115)" 0 "$a56_parse_bad"

report "A56 mutation-check pins the four fixed mutations (CHG-115)" 1 \
  "$(grep -cE 'NAMES=\(version-drift gate-version-drift baseline-missing readme-count-drift\)' "$ROOT/scripts/mutation-check.sh")"

a56_secs="T69 T70 T71 T72 T73 T73b T74 T75 T76"
a56_sec_bad=0
for a56_s in $a56_secs; do
  _a56_sf=$(grep -lE "^section_${a56_s}\(\)" "$ROOT/tests/suites/"*.sh 2>/dev/null | head -1)
  if [[ -z "$_a56_sf" ]]; then
    echo "A56: suites lack section $a56_s" >&2; a56_sec_bad=$(( a56_sec_bad + 1 )); continue
  fi
  grep -qE "SKIP ${a56_s}:" "$_a56_sf" \
    || { echo "A56: section $a56_s has no source-only SKIP branch (target-repo layout)" >&2; a56_sec_bad=$(( a56_sec_bad + 1 )); }
done
report "A56 run-tests sections T69~T76 exist and skip when the tools are absent (CHG-115/116)" 0 "$a56_sec_bad"
at_least_unique "A56 golden section T87 closes the SECTIONS registry (CHG-132 tail; CHG-145 recalibrated T87→T88 E160 golden joins)" "$a56_suite" '^SECTIONS=.* T88)'

a56_order_bad=0
for a56_s in $a56_secs; do
  _a56_sf=$(grep -lE "^section_${a56_s}\(\)" "$ROOT/tests/suites/"*.sh 2>/dev/null | head -1)
  [[ -n "$_a56_sf" ]] || { a56_order_bad=$(( a56_order_bad + 1 )); continue; }
  a56_guard_ln=$(awk -v s="$a56_s" 'index($0, "section_" s "() ") == 1 || index($0, "section_" s "()") == 1 {insec=1; next} /^section_/ && insec {exit} insec && index($0, "SKIP " s ":") {print NR; exit}' "$_a56_sf")
  a56_first_ln=$(awk -v s="$a56_s" 'index($0, "section_" s "() ") == 1 || index($0, "section_" s "()") == 1 {insec=1; next} /^section_/ && insec {exit} insec && index($0, "report \"" s " ") {print NR; exit}' "$_a56_sf")
  if [[ -z "$a56_guard_ln" || -z "$a56_first_ln" || "$a56_guard_ln" -gt "$a56_first_ln" ]]; then
    echo "A56: section $a56_s asserts before its source-only SKIP guard (guard=${a56_guard_ln:-none} first_report=${a56_first_ln:-none})" >&2
    a56_order_bad=$(( a56_order_bad + 1 ))
  fi
done
report "A56 every CHG-115 suite section gates behind its SKIP branch (CHG-115 target-repo green)" 0 "$a56_order_bad"

a56_ci_bad=0
grep -qF 'ci-summary.sh --check' "$a56_ci" || { echo "A56: CI has no ci-summary hard gate" >&2; a56_ci_bad=$(( a56_ci_bad + 1 )); }
grep -qF 'tests/.suite-baseline' "$a56_ci" || { echo "A56: CI does not reference the committed suite baseline" >&2; a56_ci_bad=$(( a56_ci_bad + 1 )); }
# Job-block-scoped pins. A whole-file grep is the wrong shape here: `if: always()`
# legitimately appears twice (the run summary step and the aggregate job), so a
# file-level pin passes no matter which one gets deleted — and a `needs:` written
# as a flow list or with a trailing comment escapes an exact-line regex and the
# reverse pin stops firing in silence. Slice per job block instead.
a56_ci_job_block() { # job name -> that job's yaml lines
  awk -v jn="$1" '/^jobs:[[:space:]]*$/{injobs=1;next}
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{inblock=($0 ~ ("^  " jn ":[[:space:]]*$"))}
    injobs && inblock{print}' "$a56_ci"
}
a56_job_src=$(a56_ci_job_block source-audit)
a56_job_gold=$(a56_ci_job_block golden-case)
a56_job_agg=$(a56_ci_job_block agent-governance)
[[ -n "$a56_job_src" && -n "$a56_job_gold" && -n "$a56_job_agg" ]] \
  || { echo "A56: ci.yml is missing a golden-case / source-audit / agent-governance job block" >&2; a56_ci_bad=$(( a56_ci_bad + 1 )); }
# The audit reads committed baselines, so it must not wait for the suite job:
# serialized, source-audit burned ~4 min of nothing and printed no findings at
# all whenever the suite was red.
grep -qE '^[[:space:]]+needs:' <<< "$a56_job_src" \
  && { echo "A56: source-audit waits on a job again (it only reads committed baselines)" >&2; a56_ci_bad=$(( a56_ci_bad + 1 )); }
# Without if: always() the aggregate is SKIPPED whenever a job fails, so the
# branch-protection check disappears instead of going red.
grep -qE '^[[:space:]]+if:[[:space:]]+always\(\)[[:space:]]*$' <<< "$a56_job_agg" \
  || { echo "A56: the agent-governance aggregate lost its if: always() (a red job would hide the required check)" >&2; a56_ci_bad=$(( a56_ci_bad + 1 )); }
# Both real jobs must be visible to the aggregate, or it is green on half the CI.
a56_needs=$(printf '%s\n' "$a56_job_agg" | grep -E '^[[:space:]]+needs:')
grep -qF 'golden-case' <<< "$a56_needs" \
  && grep -qF 'source-audit' <<< "$a56_needs" \
  || { echo "A56: the aggregate needs-list does not cover both golden-case and source-audit" >&2; a56_ci_bad=$(( a56_ci_bad + 1 )); }
# The run summary must survive a red suite, otherwise CI loses the very receipt
# the baseline gate just refused to trust.
a56_sum=$(printf '%s\n' "$a56_job_gold" | grep -A1 -- '- name: Golden-case run summary')
grep -qE 'if:[[:space:]]+always\(\)' <<< "$a56_sum" \
  || { echo "A56: the ci-summary render step is not if: always() (no summary on a failed run)" >&2; a56_ci_bad=$(( a56_ci_bad + 1 )); }
report "A56 CI carries the baseline gate, a parallel audit job and an un-skippable aggregate/summary (CHG-115)" 0 "$a56_ci_bad"

a56_doc_bad=0
for a56_t in facts.sh verify-all.sh pre-review-check.sh mutation-check.sh; do
  for a56_f in "$RM_EN" "$RM_ZH"; do
    grep -qF "$a56_t" "$a56_f" || { echo "A56: $(basename "$a56_f") does not document scripts/$a56_t" >&2; a56_doc_bad=$(( a56_doc_bad + 1 )); }
  done
done
report "A56 both READMEs document the four source-layer entry tools (CHG-115)" 0 "$a56_doc_bad"

a56_priv_tags="PD-1 PD-2 PD-3 PD-4 PD-5 PD-6"
a56_priv_file="$ROOT/.opencode/AGENTS.md"
if [[ -f "$a56_priv_file" ]]; then
  a56_priv_bad=0
  for a56_p in $a56_priv_tags; do
    grep -qF "$a56_p" "$a56_priv_file" || { echo "A56: private discipline $a56_p is missing from .opencode/AGENTS.md" >&2; a56_priv_bad=$(( a56_priv_bad + 1 )); }
  done
  report "A56 private execution disciplines present on the local-only face (docs/private-dependent)" 0 "$a56_priv_bad"
else
  echo "SKIP A56: private local-only face absent (clean clone, nothing to check)"
  report "A56 private execution disciplines present on the local-only face (docs/private-dependent)" 1 1
fi
# The discipline tags are assembled from parts: a literal copy of a tag inside
# this tracked file would otherwise match itself and report a phantom leak.
a56_leak=0
# Untracked-but-not-ignored files are part of the tracked face the moment they
# are committed, so a commit-less working tree must not be scanned as "clean".
a56_tracked=$( { git -C "$ROOT" -c core.quotePath=false ls-files 2>/dev/null; git -C "$ROOT" -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null; } | sort -u)
a56_leak=0; a56_word_bad=0
_a56_scan=$(printf '%s\n' "$a56_tracked" | awk -v root="$ROOT" '
  BEGIN {
    split("1:no-polling 2:read-output 3:subagent-cap 4:prompt-cache 5:split-batches 6:receipt-buy", pd_raw, " ")
    n_pd = 6
    for (i = 1; i <= n_pd; i++) { split(pd_raw[i], kv, ":"); pd[i] = "PD-" kv[1] " " kv[2] }
    split("禁轮询|子代理上限|缓存布局|拆批|执行成本纪律|读与输出|私有执行纪律|no-polling|read-output|subagent-cap|split-batches|prompt-cache|收据购买批量化|receipt-buy", wd, "|")
    n_wd = 14; leak = 0; word_bad = 0
  }
  {
    rel = $0; if (rel == "") next
    full = root "/" rel
    split("", seen_pd); split("", seen_wd)
    is_self = (rel == "tests/audit-standards-src.sh")
    while ((getline ln < full) > 0) {
      for (i = 1; i <= n_pd; i++) {
        if (!seen_pd[i] && index(ln, pd[i]) > 0) {
          seen_pd[i] = 1; leak++
          printf "ERR\tA56: private discipline leaked into the tracked face: %s\n", rel
        }
      }
      if (!is_self) {
        for (i = 1; i <= n_wd; i++) {
          if (!seen_wd[i] && index(ln, wd[i]) > 0) {
            seen_wd[i] = 1; word_bad++
            printf "ERR\tA56: private session-cost wording reached the tracked face: %s\n", rel
          }
        }
      }
    }
    close(full)
  }
  END { printf "CNT\t%d\t%d\n", leak, word_bad }
')
while IFS=$'\t' read -r _k _a _b; do
  if [[ "$_k" == "ERR" ]]; then
    printf '%s\n' "$_a" >&2
  elif [[ "$_k" == "CNT" ]]; then
    a56_leak="${_a:-0}"; a56_word_bad="${_b:-0}"
  fi
done <<< "$_a56_scan"
report "A56 private execution disciplines never reach the tracked/public face (CHG-115)" 0 "$a56_leak"
report "A56 private session-cost wording reaches no tracked face at all (CHG-115)" 0 "$a56_word_bad"
report "A56 the private workspace .opencode/ stays untracked (CHG-115)" 0 \
  "$(git -C "$ROOT" ls-files .opencode 2>/dev/null | wc -l | tr -d ' ')"

}

# --- A57 (v3.88.0, CHG-116, REQ-1197/1198): -T auto authority boundaries ---
audit_block_d() {
# The mapping is an optimization, never a correctness dependency: the pins below
# keep the authority path (kind:"full" receipt, full-run gating), the partial
# quarantine (separate file, kind:"partial"), the consumer-side rejection
# (ci-summary --check) and the mapping table itself honest. A lying table must
# degrade to FULL, never to a silently smaller run.
a57_bad=0
grep -qF '"kind":"full"' "$a56_suite" || { echo "A57: full receipt writer lacks kind:full" >&2; a57_bad=$((a57_bad+1)); }
grep -qF 'last-suite-partial.json' "$a56_suite" || { echo "A57: partial quarantine path absent from the runner" >&2; a57_bad=$((a57_bad+1)); }
grep -qF '"kind":"partial"' "$a56_suite" || { echo "A57: partial receipt writer lacks kind:partial" >&2; a57_bad=$((a57_bad+1)); }
grep -qE '\[\[ \$\{#WANTED\[@\]\} -eq 0' "$a56_suite" || { echo "A57: full-run gating condition missing from the runner" >&2; a57_bad=$((a57_bad+1)); }
grep -qF 'AGENT_GUARD_SUITE_FAKE_FULL' "$a56_suite" || { echo "A57: self-count test seam absent from the runner" >&2; a57_bad=$((a57_bad+1)); }
grep -qF 'not full authority' "$ROOT/scripts/ci-summary.sh" || { echo "A57: ci-summary does not reject partial receipts" >&2; a57_bad=$((a57_bad+1)); }
grep -qF 'no kind field' "$ROOT/scripts/ci-summary.sh" || { echo "A57: ci-summary does not reject legacy (kind-less) receipts" >&2; a57_bad=$((a57_bad+1)); }
a57_secs_line=$(grep -oE '^SECTIONS=\(.*\)' "$a56_suite")
for a57_s in $(grep -oE "printf 'T[0-9a-z ]*'" "$a56_suite" | grep -oE 'T[0-9a-z]+' | sort -u); do
  case "$a57_secs_line" in *" $a57_s)"*|*" $a57_s "*) ;; *) echo "A57: auto map references unregistered section $a57_s" >&2; a57_bad=$((a57_bad+1)); ;; esac
done
grep -qF '_auto_secs="$_auto_secs T50"' "$a56_suite" || { echo "A57: auto union does not always include the T50 registry pin" >&2; a57_bad=$((a57_bad+1)); }
grep -qF 'runner self-edit' "$a56_suite" || { echo "A57: runner self-edit full-fallback rule missing" >&2; a57_bad=$((a57_bad+1)); }
report "A57 -T auto keeps partial receipts quarantined and the mapping honest (CHG-116)" 0 "$a57_bad"

report "A56 verify-all shares the generator receipt-reuse rule (CHG-115)" 1 \
  "$(grep -qF 'sf_receipt_fresh' "$ROOT/scripts/verify-all.sh" && grep -qF 'sf_receipt_fresh' "$ROOT/scripts/lib-source-facts.sh" && echo 1 || echo 0)"

# v3.79.0 (CHG-103): 通用能力下发面防漂移钉——三能力（token 节省/运行加速/任务并行）
# 的目标仓发现性文本与下发件在位性。声称面 = 校验面：模板指引或 usage 行被改坏时
# 本组断言红，而不是目标仓用户静默拿到串行/无指纹的下发态。
at_least "A48 governance config carries the parallel-runner hint (CHG-102/103)" 1 "$ROOT/resources/templates/agent-governance.yml" 'run-tests\.sh -j 4'
at_least "A48 suite usage line exposes -j (CHG-103)" 1 "$ROOT/tests/run-tests.sh" 'Usage: tests/run-tests\.sh \[-T sec\[,sec\]\] \[-j N\]'
at_least "A48 bootstrap usage exposes the fingerprint lib (CHG-103)" 1 "$ROOT/scripts/bootstrap.sh" 'lib-suite-tree-fingerprint\.sh'
at_least "A48 AGENTS carries the call-batching discipline (CHG-101)" 1 "$AGENTS" '调用批处理（v3.77.0'
at_least "A48 AGENTS carries the tail-incremental-read discipline (CHG-101)" 1 "$AGENTS" '尾部增量读（v3.77.0'
report "A48 fingerprint lib ships and sources cleanly" 1 "$(bash -c 'source scripts/lib-suite-tree-fingerprint.sh 2>/dev/null && command -v suite_tree_fingerprint >/dev/null 2>&1 && echo 1 || echo 0')"
at_least "A48 bootstrap ships the suite-lock lib (CHG-113)" 1 "$ROOT/scripts/bootstrap.sh" 'lib-suite-lock\.sh'
report "A48 suite-lock lib sources cleanly" 1 "$(bash -c 'ROOT=$PWD; source scripts/lib-suite-lock.sh 2>/dev/null && command -v suite_lock_acquire >/dev/null 2>&1 && echo 1 || echo 0')"
report "A48 run-tests honors the receipt path override (CHG-113)" 1 "$([[ $(grep -cF 'AGENT_GUARD_SUITE_RECEIPT_PATH' "$ROOT/tests/run-tests.sh") -ge 1 ]] && echo 1 || echo 0)"
report "A48 update-assertion-count honors the receipt path override (CHG-113)" 1 "$(grep -cF 'AGENT_GUARD_SUITE_RECEIPT_PATH' "$ROOT/scripts/update-assertion-count.sh")"
report "A48 source dogfood entry ships and parses (CHG-113)" 1 "$([[ -f "$ROOT/scripts/selfcheck.sh" ]] && bash -n "$ROOT/scripts/selfcheck.sh" 2>/dev/null && echo 1 || echo 0)"
report "A48 branch-protection helper defaults to dry-run (CHG-113)" 1 "$([[ -f "$ROOT/scripts/setup-branch-protection.sh" ]] && grep -qF 'dry run: no remote change' "$ROOT/scripts/setup-branch-protection.sh" && echo 1 || echo 0)"

# A43 分层单源 tripwire（CHG-044，2026-10-13 用户硬指令）：工具词表/格式细节的唯一权威=
# 工具头注释（behavior-extract.sh / agent-gate）与 entry 模板条件注释块；叙事层
# （DS/playbook/registry/AGENTS）禁止复制工具词表指纹——命中即越层红。指针句必须在位。
a43_bad=0
for a43_f in "$ROOT/resources/DEVELOPMENT_STANDARDS.md" "$ROOT/resources/STAGE_PLAYBOOK.md" "$ROOT/resources/CLAUSE_REGISTRY.md" "$ROOT/resources/AGENTS.md"; do
  a43_n=$(grep -cE 'label\[for\]|hx-trigger|\[contenteditable\]|origin: <文件名>|data-action' "$a43_f" 2>/dev/null || true)
  [[ "$a43_n" -eq 0 ]] || { a43_bad=1; echo "A43 layering: $a43_f carries tool-vocabulary fingerprints ($a43_n hits)" >&2; }
done
a43_ptr=$(grep -cE 'behavior-extract.sh` 头注释|behavior-extract.sh 头注释' "$ROOT/resources/STAGE_PLAYBOOK.md" 2>/dev/null || true)
[[ "$a43_ptr" -ge 1 ]] || { a43_bad=1; echo "A43 layering: playbook lacks the single-source pointer" >&2; }
report "A43 layering single-source — narrative carries no tool vocabulary; pointer present (user hard gate 2026-10-13)" 0 "$a43_bad"

# ── PART A58: 五道交付门承载面（v3.92.0，CHG-128）────────────────────────────
# 门不是"说了就存在"：判定面（4 个 E 码）、证据面（fresh-clone 工具）、文档面
# （DS/AGENTS）、反馈面（pre-push）、版本面（CHANGELOG）必须同时在位。
report "A58a gate carries E150/E151/E152/E153" 4 "$(grep -oE 'GATE-E(150|151|152|153)' "$STAGED_TPL" | sort -u | wc -l | tr -d ' ')"
report "A58b fresh-clone tool emits a receipt" 1 "$(a17_at_least_1 "$(grep -c 'fresh-clone-receipt.json' "$ROOT/tests/fresh-clone-check.sh" 2>/dev/null || true)")"
report "A58c DS documents the environment gate" 1 "$(grep -cE 'fresh-clone|环境等价' "$STD" 2>/dev/null || true)"
report "A58d AGENTS documents the fresh-clone/CI equivalence" 1 "$(grep -c 'fresh clone / 无 CI 仓必须全绿' "$AGENTS" 2>/dev/null || true)"
report "A58e pre-push carries the G-FEED hint" 1 "$(grep -c 'G-FEED tip' "$ROOT/resources/templates/pre-push" 2>/dev/null || true)"
report "A58f CHANGELOG carries the v3.92.0 row" 1 "$(cat "$SLOG" "$SLOG_ARCHIVE" 2>/dev/null | grep -c '| v3\.92\.0 |' || true)"
report "A58g fresh-clone history ledger is declared" 1 "$(a17_at_least_1 "$(grep -c 'fresh-clone-history.tsv' "$ROOT/tests/fresh-clone-check.sh" 2>/dev/null || true)")"
report "A58h unverified-REQ declaration face is shipped" 1 "$([[ $(grep -c 'GATE-E154' "$STAGED_TPL") -ge 1 && $(grep -c '未验证 REQ 清单' "$ROOT/resources/templates/entry/09-changelog.md") -ge 1 ]] && echo 1 || echo 0)"
# v3.92.3 (CHG-128 fix): 只下发门禁、不下发执行件 = E153 永远无法满足。v3.92.0
# 起三个批次都漏装 tests/fresh-clone-check.sh，changelog 却承诺 --upgrade 带走。
# 断言刻意用**行为**（真跑 --guard 到临时仓），不复述安装清单文本——文本形态
# 会被等价改写绕过（A5 同族根因）。
a58_payload_ok=1
A58_TMP=$(mktemp -d 2>/dev/null) || A58_TMP=""
if [[ -n "$A58_TMP" ]]; then
  ( cd "$A58_TMP" && git init -q . ) >/dev/null 2>&1 || true
  bash "$ROOT/scripts/bootstrap.sh" --guard "$A58_TMP" >/dev/null 2>&1 || a58_payload_ok=0
  [[ -x "$A58_TMP/tests/fresh-clone-check.sh" ]] || a58_payload_ok=0
  bash -n "$A58_TMP/tests/fresh-clone-check.sh" 2>/dev/null || a58_payload_ok=0
  rm -rf "$A58_TMP"
else
  a58_payload_ok=0
fi
report "A58i bootstrap --guard installs an executable fresh-clone tool" 0 "$([[ "$a58_payload_ok" -eq 1 ]] && echo 0 || echo 1)"
# v3.92.3: target repos do not receive audit-standards-src.sh, so the tool must
# fall back to the shipped cross-doc audit or the receipt can never be green.
report "A58j fresh-clone tool falls back to the shipped cross-doc audit" 1 "$(a17_at_least_1 "$(grep -c 'audit-docs-consistency.sh' "$ROOT/tests/fresh-clone-check.sh" 2>/dev/null || true)")"
# v3.92.3 fix: profile.tests is scenario metadata ("tests dir present, no test
# command"), NOT a path root. A flat key scan used to retarget the whole install
# into a directory literally named present-no-command. Behaviour assertion:
# a legacy yml with profile.tests and no paths: must install to tests/ and gain
# an explicit paths: block.
a58k_ok=1
A58K=$(mktemp -d 2>/dev/null) || A58K=""
if [[ -n "$A58K" ]]; then
  ( cd "$A58K" && git init -q . && git config user.email t@x.invalid && git config user.name t \
    && mkdir -p tests && printf '#!/bin/sh\necho project-test\n' > tests/project.sh \
    && printf 'profile:\n  schema_version: 1\n  tests: present-no-command\n  assets: tests\n' > .agent-governance.yml \
    && git add -A >/dev/null 2>&1 && git commit -qm legacy >/dev/null 2>&1 ) || a58k_ok=0
  bash "$ROOT/scripts/bootstrap.sh" --upgrade "$A58K" >/dev/null 2>&1 || a58k_ok=0
  [[ -x "$A58K/tests/fresh-clone-check.sh" ]] || a58k_ok=0
  [[ -d "$A58K/present-no-command" ]] && a58k_ok=0
  grep -qE '^paths:' "$A58K/.agent-governance.yml" 2>/dev/null || a58k_ok=0
  grep -qE '^  tests: tests$' "$A58K/.agent-governance.yml" 2>/dev/null || a58k_ok=0
  rm -rf "$A58K"
else a58k_ok=0; fi
report "A58k legacy profile.tests does not hijack the install root" 0 "$([[ "$a58k_ok" -eq 1 ]] && echo 0 || echo 1)"
# v3.92.3 fix: historic `git add -f` on .agent-state kept runtime files tracked.
# Upgrade must untrack them (files stay on disk) so sessions stop dirtying the tree.
a58l_ok=1
A58L=$(mktemp -d 2>/dev/null) || A58L=""
if [[ -n "$A58L" ]]; then
  ( cd "$A58L" && git init -q . && git config user.email t@x.invalid && git config user.name t \
    && mkdir -p .agent-state && printf 'red\n' > .agent-state/session-gate-last.md \
    && git add -f .agent-state >/dev/null 2>&1 && git commit -qm legacy >/dev/null 2>&1 ) || a58l_ok=0
  bash "$ROOT/scripts/bootstrap.sh" --upgrade "$A58L" >/dev/null 2>&1 || a58l_ok=0
  [[ -z "$(git -C "$A58L" ls-files -- .agent-state 2>/dev/null)" ]] || a58l_ok=0
  [[ -f "$A58L/.agent-state/session-gate-last.md" ]] || a58l_ok=0
  rm -rf "$A58L"
else a58l_ok=0; fi
report "A58l tracked .agent-state is untracked, file kept" 0 "$([[ "$a58l_ok" -eq 1 ]] && echo 0 || echo 1)"
# Every shipped path-root reader must carry the paths:-scoped branch; a new
# reader copied from an old template would silently reintroduce the hijack.
a58m_n=0
for a58m_f in scripts/bootstrap.sh scripts/install.sh resources/templates/agent-gate.sh \
  resources/templates/new-change.sh resources/templates/check-standards-compliance.sh \
  resources/templates/stamp-provenance.sh resources/templates/audit-docs-consistency.sh \
  resources/templates/uninstall-standards.sh resources/templates/session-gate.sh \
  resources/templates/eval-rescore.sh; do
  if [[ "$a58m_f" == *"agent-gate.sh" ]]; then
    grep -qF 'if [[ "$sec" == "paths" ]]; then' "$ROOT/$a58m_f" 2>/dev/null && a58m_n=$(( a58m_n + 1 ))
  else
    grep -qF 'paths:[[:space:]]*$/,/^[^[:space:]#]' "$ROOT/$a58m_f" 2>/dev/null && a58m_n=$(( a58m_n + 1 ))
  fi
done
report "A58m every path-root reader scopes to paths:" 10 "$a58m_n"

# A62 派发输入契约 v2 全链（v3.94.0，CHG-131，REQ-1310~1317）：本批失效形态是"契约只写在
# 一份文档里"——主 Agent 照旧一句话派发、模板无承载字段、门禁不校版本、生成器缺失，四者
# 任一回落则契约实际不生效。五面互锁：权威锚点 / 契约表 / 模板承载 / 门禁机校 / 生成器与注册表。
A62_RI="$ROOT/resources/methodologies/review-intelligence.md"
A62_T35="$ROOT/resources/templates/entry/03.5-tasks.md"
A62_T07="$ROOT/resources/templates/entry/07-review-report.md"
A62_GOV="$ROOT/resources/templates/entry/00-governance.json"
A62_NC="$ROOT/resources/templates/new-change.sh"
A62_CR="$ROOT/resources/CLAUSE_REGISTRY.md"
report "A62 DS §2.2 dispatch-contract anchor is unique (CHG-131)" 1 \
  "$(grep_count_f "$STD" '**AI 子代理派发输入契约（v3.94.0，dispatch_contract v2）**')"
report "A62 review-intelligence declares the nine P groups (CHG-131)" 9 \
  "$(grep -cE '^\| \*\*P[0-8] ' "$A62_RI" 2>/dev/null || true)"
a62_stage_rows=$(awk '/^### 2\.1 /{f=1;next} f&&/^## /{exit} f&&/^\| /&&!/^\| 阶段/{n++} END{print n+0}' "$A62_RI")
report "A62 review-intelligence §2.1 carries ten stage skeletons (CHG-131)" 10 "$a62_stage_rows"
# 五标签逐条在位：正例（模板承载）与反例（模板不得只剩旧「评审输入」单字段）成对。
a62_lbl=0
for a62_l in 项目背景 变更上下文 证据包 专业与历史 独立与成本; do
  a62_c=$(grep -cE "^-[[:space:]]*${a62_l}(：|:)" "$A62_T35" 2>/dev/null || true)
  a62_lbl=$(( a62_lbl + ${a62_c:-0} ))
done
report "A62 entry/03.5 carries the five dispatch-input labels (CHG-131)" 5 "$a62_lbl"
report "A62 entry/07 carries the business and test-view rows (CHG-131)" 2 \
  "$(( $(grep_count_f "$A62_T07" '| 功能与业务 |') + $(grep_count_f "$A62_T07" '| 测试视角 |') ))"
report "A62 entry/00-governance carries the dispatch_contract placeholder (CHG-131)" 1 \
  "$(grep_count_f "$A62_GOV" '"dispatch_contract": "__DISPATCH_CONTRACT__"')"
report "A62 new-change stamps dispatch_contract v2 (CHG-131)" 1 \
  "$(grep_count_f "$A62_NC" 's/__DISPATCH_CONTRACT__/v2/g')"
run_audit_rules <<'EOF'
@COLD	F_GE	1	A62 gate assembles the P0-P8 skeleton once (CHG-131)	dispatch_run() { # <stage> <change-id> <text|--json>
@STAGED	F_GE	1	A62 gate wires the dispatch subcommand (CHG-131)	  dispatch)
@STAGED	F_GE	1	A62 gate scaffolds dispatch_contract v2 (CHG-131)	"dispatch_contract": "v2"
@STAGED	F_GE	1	A62 gate emits E155 from one die site (CHG-131)	die "GATE-E155: 
@STAGED	F_GE	4	A62 E155 branches route through the helper (CHG-131)	dispatch_usage "
@STAGED	F_GE	1	A62 E17 v2 strips the label with colon alternation (CHG-131)	${lbl}[[:space:]]*(：|:)
@GATE_HW	F_EQ	0	A62 E17 never strips the label with a multibyte bracket class (CHG-131)	[：:]
@STAGED	F_EQ	1	A62 gate names the five expected labels in one hint (CHG-131)	expected labels: 项目背景 变更上下文 证据包 专业与历史 独立与成本
@AGENTS	F_EQ	1	A62 AGENTS carries the dispatch-contract rule (CHG-131)	**派发契约（v3.94.0，§2.2）**
@ROOT/resources/STAGE_PLAYBOOK.md	F_EQ	1	A62 STAGE_PLAYBOOK points at the sole skeleton authority (CHG-131)	**子代理派发骨架（v3.94.0，CHG-131）**
EOF
at_least_unique "A62 registry updates the dispatch clause (CHG-131)" "$A62_CR" '^| R18 | AI 子代理派发输入契约'
at_least_unique "A62 registry indexes E155 (CHG-131)" "$A62_CR" '^| GATE-E155 |'
at_least_e "A62 suite registers the dispatch section (CHG-131; CHG-145 tail recalibrated to T88)" 1 "$ROOT/tests/run-tests.sh" '^SECTIONS=.* T88\)'

# --- A63 (v3.95.0, CHG-132, REQ-1320~1324): 套件基建五手段的源层接线 ---
run_audit_rules <<'EOF'
@AGENTS	F_GE	1	A63 AGENTS carries the version-chain-first suite rule (CHG-132)	版本链先行（v3.95.0，CHG-132）
@AGENTS	F_GE	1	A63 AGENTS rule names the sync authority (CHG-132)	update-assertion-count.sh
EOF
report "A63 shard-sum.sh is executable" 0 "$([[ -x "$ROOT/scripts/shard-sum.sh" ]] && echo 0 || echo 1)"
run_audit_rules <<'EOF'
@ROOT/scripts/shard-sum.sh	F_GE	1	A63 shard-sum prints the summation total (CHG-132)	total: $total_p passed, $total_f failed
@ROOT/scripts/shard-sum.sh	F_GE	1	A63 shard-sum --write syncs via the generator (CHG-132)	bash "$gen" --from-baseline
@ROOT/scripts/shard-sum.sh	F_GE	1	A63 shard-sum --write refuses without the generator (CHG-132)	target installs are sum-only
@RUN	F_GE	1	A63 --worktree seam is wired in the runner (CHG-132)	WORKTREE=1; shift ;;
@RUN	F_GE	1	A63 worktree recursion guard exists (CHG-132)	AGENT_GUARD_SUITE_IN_WT
@RUN	F_GE	1	A63 section-cache seam is opt-in (CHG-132)	AGENT_GUARD_SECTION_CACHE
@RUN	F_GE	1	A63 section-cache store is fingerprint-keyed (CHG-132)	section-cache.tsv
@RUN	F_GE	1	A63 SERIAL_CHAIN hoisted before dispatch (CHG-132)	SERIAL_CHAIN=(T50 T51 T5 T22a T16)
EOF
report "A63 run-tests.sh never writes .suite-baseline directly (CHG-132)" 0 "$(grep -cE '> *"\$ROOT/tests/\.suite-baseline"' "$ROOT/tests/run-tests.sh" || true)"
run_audit_rules <<'EOF'
@ROOT/tests/audit-standards-src.sh	F_GE	1	A63 audit block-parallel seam exists (CHG-132)	AGENT_GUARD_AUDIT_PARALLEL
@ROOT/tests/audit-standards-src.sh	F_GE	1	A63 audit blocks are registered for dispatch (CHG-132)	AUDIT_BLOCKS=(a b c d)
EOF
report "A63 audit A10b/A10 stay after the parallel blocks (CHG-132)" 0 "$([[ "$(grep -n 'audit_block_d()' "$ROOT/tests/audit-standards-src.sh" | head -1 | cut -d: -f1)" -lt "$(grep -n 'PART A10b' "$ROOT/tests/audit-standards-src.sh" | head -1 | cut -d: -f1)" ]] && echo 0 || echo 1)"

# --- A64 (v3.96.0, CHG-133, REQ-1330/1332/1333/1334/1335): 证据基建与判定面加固 ---
run_audit_rules <<'EOF'
@AGENTS	F_GE	1	A64 AGENTS carries the evidence-round SOP (CHG-133)	证据轮 SOP（v3.96.0，CHG-133）
@AGENTS	F_GE	1	A64 SOP names the default 5 snapshot + 1 live split (CHG-133)	5 快照 + 1 非快照
@AGENTS	F_GE	1	A64 SOP names the round tool (CHG-133)	scripts/evidence-round.sh
EOF
report "A64 evidence-round.sh is executable (CHG-133)" 0 "$([[ -x "$ROOT/scripts/evidence-round.sh" ]] && echo 0 || echo 1)"
run_audit_rules <<'EOF'
@ROOT/scripts/evidence-round.sh	F_GE	1	A64 evidence-round ledger is append-only state (CHG-133)	ledger.tsv
@ROOT/scripts/shard-sum.sh	F_GE	1	A64 shard-sum warns on an all-snapshot round (CHG-133)	logs are worktree snapshots
EOF
report "A64 shard-sum warning carries no frozen totals (CHG-133)" 0 "$(grep -E 'WARN —' "$ROOT/scripts/shard-sum.sh" | grep -cE '[0-9]{3,}' || true)"
run_audit_rules <<'EOF'
@ROOT/scripts/shard-sum.sh	F_GE	1	A64 shard-sum refuses --write on an all-snapshot round (CHG-133)	refusing --write on an all-snapshot round
@ROOT/tests/fresh-clone-check.sh	F_GE	1	A64 fresh-clone passes the audit-parallel default (CHG-133)	AGENT_GUARD_AUDIT_PARALLEL="${AGENT_GUARD_AUDIT_PARALLEL:-1}"
@RUN	F_GE	1	A64 run-tests carries the cost-balanced plan (CHG-133)	SHARD_PLAN_6=(
@SUITES	F_GE	1	A64 TC-1280 attributes the inner section first (CHG-133)	非 T57 责任
@AGENTS	F_GE	1	A65 AGENTS carries the rework-split rule (CHG-134)	返工分治（v3.97.0，CHG-134）
@AGENTS	F_GE	1	A65 the rule names the deferral ledger (CHG-134)	延后补钉登记
@STD	F_GE	1	A65 DS §2.13.4 carries the same rule (CHG-134)	返工分治（v3.97.0，CHG-134）
@ROOT/resources/templates/entry/05-test-results.md	F_GE	1	A65 the 05 template has the deferral section (CHG-134)	## 延后补钉登记
@AGENTS	F_GE	1	A65 AGENTS names the preflight tool (CHG-134)	scripts/pre-round-check.sh
@AGENTS	F_GE	1	A65 AGENTS names the fail-fast and carry switches (CHG-134)	--carry-check
EOF
report "A65 pre-round-check.sh is executable (CHG-134)" 0 "$([[ -x "$ROOT/scripts/pre-round-check.sh" ]] && echo 0 || echo 1)"
report "A65 shard-plan.sh is executable (CHG-134)" 0 "$([[ -x "$ROOT/scripts/shard-plan.sh" ]] && echo 0 || echo 1)"
run_audit_rules <<'EOF'
@ROOT/scripts/evidence-round.sh	F_GE	1	A65 evidence-round refuses to start on a red preflight (CHG-134)	pre-round-check failed
@RUN	F_GE	1	A65 the plan block is machine-written (CHG-134)	# SHARD_PLAN_6_BEGIN
@RUN	F_GE	1	A65 the cache has a path seam (CHG-134)	AGENT_GUARD_SECTION_CACHE_PATH
@RUN	F_GE	1	A65 the cache keeps recent fingerprints (CHG-134)	hist[1]
@AGENTS	F_GE	1	A66 AGENTS carries the freeze rule (CHG-135)	冻结规则（v3.97.1，CHG-135）
@ROOT/scripts/evidence-round.sh	F_GE	1	A66 evidence-round holds a round-scoped lock (CHG-135)	_ER_LOCK="${AGENT_GUARD_EVIDENCE_LOCK_DIR:-$ROOT/.agent-state/evidence-round.lock}"
@ROOT/scripts/evidence-round.sh	F_GE	1	A66 evidence-round re-reads the fingerprint after the shards (CHG-135)	printf 'tree_drift\t%s\n' "$_drift"
@GATE	F_GE	1	A66 agent-gate refuses counted writes in a live round (CHG-135)	die "GATE-E156:
@GATE	F_GE	1	A66 the gate calls the freeze check on every pre-write (CHG-135)	validate_freeze_window "$file"
@ROOT/scripts/evidence-round.sh	F_GE	1	A66 evidence-round re-reads the fingerprint at the end (CHG-135)	_tree_end=$(_tree_sha)
@ROOT/scripts/evidence-round.sh	F_GE	1	A66 evidence-round takes the round lock before any shard (CHG-135)	_er_lock_take || exit 2
@ROOT/scripts/evidence-round.sh	F_GE	1	A66 evidence-round releases the lock on every exit (CHG-135)	trap '_er_lock_release' EXIT
@ROOT/resources/templates/entry/05-test-results.md	F_GE	1	A66 the 05 template marks drifted rounds as void (CHG-135)	tree_drift（必须为 0）
@ROOT/scripts/lib-suite-tree-fingerprint.sh	F_GE	1	A66 the fingerprint excludes runtime state (CHG-135)	tests/.suite-baseline .agent-state "${claims[@]}"
@STAGED	F_GE	1	A67 E160 die site in gate template (CHG-145)	die "GATE-E160: 测试弱化命中
EOF
if [[ -f "$ROOT/scripts/agent-gate" ]]; then
  if grep -qF '# single-source wrapper -> resources/templates/agent-gate.sh' "$ROOT/scripts/agent-gate" && grep -qF 'exec bash' "$ROOT/scripts/agent-gate"; then
    report "A67 E160 die site in source gate (CHG-145)" 1 1
  else
    at_least_f "A67 E160 die site in source gate (CHG-145)" 1 "$ROOT/scripts/agent-gate" 'die "GATE-E160: 测试弱化命中'
  fi
else
  echo "SKIP A67: scripts/agent-gate absent in a fresh source checkout (gitignored mirror; template pin enforces)"
  report "A67 E160 die site in source gate (CHG-145)" 1 1
fi
run_audit_rules <<'EOF'
@STAGED	F_GE	1	A67 E160 staged-chain mount (CHG-145)	validate_test_weakening staged;
EOF
a67_sev_hdr=$(grep_count_f "$A62_RI" '| 严重度 | 阻断交付 | 判定判据 | 处置动作 |')
report "A67 §6 severity table carries the machine-decidable header (CHG-145)" 1 "$a67_sev_hdr"
a67_sev_rows=$(awk '/^\| 严重度 \| 阻断交付/{f=1;next} f&&/^## /{exit} f&&/^\| (严重|中|低) /{n++} END{print n+0}' "$A62_RI")
report "A67 §6 severity table keeps the three-tier rows (CHG-145)" 3 "$a67_sev_rows"
at_least_f "A67 §6 严重 row is delivery-blocking (CHG-145)" 1 "$A62_RI" '| 严重 | 是 |'
at_least_f "A67 §8 five-class line names the E160 enforcement (CHG-145)" 1 "$A62_RI" 'gate E160 执法 A 层 + 评审复核 B 层'

# --- A68 (v4.5.0, CHG-149, REQ-1385~1394): 交付防假绿四门 + 动态适配 + AGENTS 防截断 + 性能/摩擦 ---
a68_agents_bytes=$(wc -c < "$AGENTS" | tr -d '[:space:]')
report "A68 AGENTS.md managed template <= 16384B (no 24KB client truncation, CHG-149)" 1 "$([[ "$a68_agents_bytes" -le 16384 ]] && echo 1 || echo 0)"
run_audit_rules <<'EOF'
@STAGED	F_GE	1	A68 gate carries GATE-E161 outbound exit check (CHG-149)	die "GATE-E161:
@STAGED	F_GE	1	A68 gate carries GATE-E162 entry-owns-exit check (CHG-149)	die "GATE-E162:
@STAGED	F_GE	1	A68 E104 rejects bare HTTP without body or latency (CHG-149)	relies on bare HTTP
@STAGED	F_GE	1	A68 E107 enforces compensation uncovered-gap reconciliation (CHG-149)	工具面缺失补偿存在未覆盖差集非空
@HOOK	F_GE	1	A68 install-hook-adapter supports dynamic --print-contract (CHG-149)	--print-contract)
@HOOK	F_GE	1	A68 install-hook-adapter supports --verify-wiring (CHG-149)	--verify-wiring)
@SG	F_GE	1	A68 session-gate guards empty updated_at overflow (CHG-149)	telemetry uninitialized (no updated_at
@ROOT/tests/fresh-clone-check.sh	F_GE	1	A68 fresh-clone-check records code_face_sha for E153 reuse (CHG-149)	code_face_sha
@BS	F_GE	1	A68 bootstrap profile detects classic asp and server-web UI (CHG-149)	server-web
EOF

# --- A69 (v4.5.1, CHG-150, REQ-1395~1407): P0 回归止血 + CI/Hook 加固 + 文档对齐 ---
a69_rp_fail=0
a69_rp_dir=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/a69rp.$$"); mkdir -p "$a69_rp_dir"
for a69_t in L0-bugfix L1-standards L2-architecture L3-critical universal; do
  ( cd "$ROOT" && bash resources/templates/generate-reading-pack.sh "$a69_t" --verify >/dev/null 2>&1 || : > "$a69_rp_dir/$a69_t.fail" ) &
done
wait
a69_rp_fail=$(ls "$a69_rp_dir" 2>/dev/null | wc -l | tr -d ' ')
rm -rf "$a69_rp_dir"
report "A69 CLAUSE_REGISTRY --verify passes all 5 types (CHG-150)" 0 "$a69_rp_fail"
a69_lss=$(( $(grep_count_f "$ROOT/tests/fresh-clone-check.sh" 'ls-files -s') + $(grep_count_f_files 'ls-files -s' "$GATE_TPL" "$STAGED_TPL") ))
report "A69 fresh-clone-check and agent-gate drop git ls-files -s for code_face_sha (CHG-150)" 0 "$a69_lss"
report "A69 install-hook-adapter supports --print-global-contract and zero-dep JSON fallback (CHG-150)" 2 \
  "$(( $(grep_count_f "$ROOT/resources/templates/install-hook-adapter.sh" '--print-global-contract)') + $(grep_count_f "$ROOT/resources/templates/install-hook-adapter.sh" 'json_sanity_check()') ))"
report "A69 github-artifact-pipeline copies entry templates with no inline skeleton and env-isolated before SHA (CHG-150)" 3 \
  "$(( ($(grep_count_f "$PIPE" '## 业务影响') == 0 ? 1 : 0) + $(a17_at_least_1 "$(grep_count_f "$PIPE" 'templates/entry')") + $(a17_at_least_1 "$(grep_count_f "$PIPE" 'PUSH_BEFORE_SHA: ${{ github.event.before }}')") ))"
a69_bhelp=$(bash "$ROOT/scripts/bootstrap.sh" --help 2>/dev/null || true)
report "A69 bootstrap --help lists 6 methodologies, STAGE_PLAYBOOK, and evidence-round (CHG-150)" 3 \
  "$(( $(printf '%s\n' "$a69_bhelp" | grep -cF 'methodologies/ (6') + $(printf '%s\n' "$a69_bhelp" | grep -cF 'STAGE_PLAYBOOK.md') + $(printf '%s\n' "$a69_bhelp" | grep -cF 'evidence-round.sh') ))"
a69_ag_cnt=0
for a69_f in "$GATE_TPL" "$ROOT/resources/templates/session-gate.sh" "$ROOT/resources/templates/audit-docs-consistency.sh"; do
  grep -qF '\.agents/' "$a69_f" 2>/dev/null && a69_ag_cnt=$(( a69_ag_cnt + 1 ))
done
report "A69 all three is_code_path replicas exempt .agents/ (CHG-150)" 3 "$a69_ag_cnt"

# --- A70 (v4.6.0, CHG-151, REQ-1408~1417): P2 提速包与 FU-15001 收口 ---
at_least_f "A70 install-hook-adapter supports --offline and --reprobe cache (CHG-151)" 1 "$ROOT/resources/templates/install-hook-adapter.sh" 'opencode-arbitration-cache.tsv'
at_least_f "A70 audit-docs-consistency supports --incremental mode (CHG-151)" 1 "$ROOT/resources/templates/audit-docs-consistency.sh" '--incremental'
at_least_f "A70 session-gate start supports --full and defaults to incremental (CHG-151)" 1 "$ROOT/resources/templates/session-gate.sh" 'sg_audit_full'
at_least_f "A70 audit-standards-src defaults to parallel block execution (CHG-151)" 1 "$ROOT/tests/audit-standards-src.sh" 'AGENT_GUARD_AUDIT_PARALLEL:-1'
at_least_f "A70 bootstrap detect_default_branch supports linked git worktrees (CHG-151)" 1 "$ROOT/scripts/bootstrap.sh" 'rev-parse --git-dir'
report "A70 github-artifact-pipeline drops hardcoded resources/methodologies prefix (CHG-151)" 0 "$(grep_count_f "$PIPE" 'resources/methodologies/')"

# --- A71 (v4.7.0, CHG-152, REQ-1418~1425): P1 3A批 8项动态契约与安全门 ---
report "A71 install-ci-adapter.sh exists and is executable (CHG-152)" 0 "$([[ -x "$ROOT/resources/templates/install-ci-adapter.sh" ]]; echo $?)"
at_least_f "A71 install-ci-adapter emits CI and branch-protection contracts (CHG-152)" 1 "$ROOT/resources/templates/install-ci-adapter.sh" '--print-branch-protection-contract'
at_least_f "A71 bootstrap exposes profile contract and verify flags (CHG-152)" 1 "$ROOT/scripts/bootstrap.sh" '--verify-profile'
report "A71 four code-path checkers read dynamic code_extensions (CHG-152)" 4 "$(( $(grep -cF 'code_extensions' "$GATE_TPL" >/dev/null && echo 1 || echo 0) + $(grep -cF 'code_extensions' "$ROOT/resources/templates/session-gate.sh" >/dev/null && echo 1 || echo 0) + $(grep -cF 'code_extensions' "$ROOT/resources/templates/audit-docs-consistency.sh" >/dev/null && echo 1 || echo 0) + $(grep -cF 'code_extensions' "$ROOT/resources/templates/check-standards-compliance.sh" >/dev/null && echo 1 || echo 0) ))"
at_least_f "A71 agent-gate exposes review-models command (CHG-152)" 1 "$COLD_TPL" 'review_models_cmd'
run_audit_rules <<'EOF'
@STAGED	F_GE	1	A71 agent-gate supports extensible test_weakening_patterns (CHG-152)	test_weakening_patterns
@STAGED	F_GE	1	A71 agent-gate supports kv_field structured checks (CHG-152)	kv_field()
@STAGED	F_GE	1	A71 agent-gate enforces GATE-E164 secret scan (CHG-152)	GATE-E164:
@STAGED	F_GE	1	A71 agent-gate emits AI-LAZY soft warn (CHG-152)	AI-LAZY
@STAGED	F_GE	1	A72 agent-gate enforces GATE-E163 causal DAG gate (CHG-153)	GATE-E163:
@STAGED	F_GE	1	A72 agent-gate records stage-gate receipts and mtime check (CHG-153)	record_stage_receipt
@COLD	F_GE	1	A72 agent-gate exposes record-red red-first receipt command (CHG-153)	record_red_cmd
@GATE	F_GE	1	A72 agent-gate records pre-write heartbeat ledger (CHG-153)	prewrite_ledger_append
@COLD	F_GE	1	A72 dispatch review injects process_honesty_summary (CHG-153)	process_honesty_summary
@ROOT/resources/templates/pre-commit	F_GE	1	A72 pre-commit template carries RETROACTIVE_PROBE defense (CHG-153)	RETROACTIVE_PROBE
@COLD	F_GE	4	A72 agent-gate exposes start advance next fix commands (CHG-153)	next_cmd
@STAGED	F_GE	1	A72 agent-gate supports optional single-file change-card mode (CHG-153)	validate_change_card
@GATE	F_GE	1	A72 FU-15202 is_code_path caches extensions (CHG-153)	_AG_EXT_LOADED
@CIADAPT	F_GE	1	A72 FU-15202 install-ci-adapter reports candidates and filters comments (CHG-153)	candidates:
@CR	F_GE	1	A72 CLAUSE_REGISTRY documents GATE-E163 (CHG-153)	GATE-E163
EOF

# --- A73 (v4.9.0, CHG-154, REQ-1438~1443): P3 6项架构收敛与热冷分层 ---
a73_cl_bytes=$(wc -c < "$SLOG" | tr -d ' ')
report "A73 STANDARDS_CHANGELOG slimmed <= 20KB with archive split (CHG-154)" 1 "$([[ "$a73_cl_bytes" -le 20480 && -s "$SLOG_ARCHIVE" ]] && echo 1 || echo 0)"
report "A73 STANDARDS_CHANGELOG_ARCHIVE retains v2.9.0..v4.2.0 history (CHG-154)" 1 "$(a17_at_least_1 "$(grep -c '^| v2\.9\.0 ' "$SLOG_ARCHIVE" || true)")"
report "A73 governance-smoke ships in guard layer (CHG-154)" 1 "$([[ -x "$ROOT/resources/templates/governance-smoke.sh" ]] && grep -cF 'governance-smoke.sh' "$ROOT/scripts/bootstrap.sh" | awk '{print ($1>=1)?1:0}' || echo 0)"
_a73_sw_rc=1
if [[ -x "$ROOT/scripts/sync-local-wrappers.sh" ]]; then
  _a73_sw_tmp=$(mktemp -d)
  mkdir -p "$_a73_sw_tmp/scripts" "$_a73_sw_tmp/.githooks"
  ln -s "$ROOT/resources" "$_a73_sw_tmp/resources"
  cp "$ROOT/scripts/sync-local-wrappers.sh" "$_a73_sw_tmp/scripts/sync-local-wrappers.sh"
  bash "$_a73_sw_tmp/scripts/sync-local-wrappers.sh" >/dev/null 2>&1 && bash "$_a73_sw_tmp/scripts/sync-local-wrappers.sh" --check >/dev/null 2>&1
  _a73_sw_rc=$?
  rm -rf "$_a73_sw_tmp"
  if [[ -f "$ROOT/.githooks/pre-commit" ]]; then
    bash "$ROOT/scripts/sync-local-wrappers.sh" --check >/dev/null 2>&1 || _a73_sw_rc=$?
  fi
fi
report "A73 sync-local-wrappers --check passes in source repo (CHG-154)" 0 "$_a73_sw_rc"
report "A73 lib-json shared by gate, bootstrap, and ci-adapter (CHG-154)" 3 "$(( $(grep -cF 'lib-json.sh' "$GATE_TPL" >/dev/null && echo 1 || echo 0) + $(grep -cF 'lib-json.sh' "$ROOT/scripts/bootstrap.sh" >/dev/null && echo 1 || echo 0) + $(grep -cF 'lib-json.sh' "$ROOT/resources/templates/install-ci-adapter.sh" >/dev/null && echo 1 || echo 0) ))"
at_least_f "A73 lib-gate-cold lazy loader wired in agent-gate (CHG-154)" 1 "$GATE_TPL" 'load_gate_cold()'
report "A73 lib-gate-cold parses cleanly with bash -n (CHG-154)" 0 "$(/bin/bash -n "$COLD_TPL" >/dev/null 2>&1; echo $?)"

# --- A74 (v4.10.0, CHG-155, REQ-1444~1450): P4 7项渐进执法/自诊/校验/MCP收官 ---
report "A74 agent-gate supports enforcement_mode with E164 never downgraded (CHG-155)" 2 "$(( $(grep -cF 'enforcement_mode()' "$GATE_TPL" >/dev/null && echo 1 || echo 0) + $(grep -cF 'GATE-E164) ;;' "$GATE_TPL" >/dev/null && echo 1 || echo 0) ))"
at_least_f "A74 lib-gate-cold provides doctor_cmd diagnostics (CHG-155)" 1 "$COLD_TPL" 'doctor_cmd()'
at_least_f "A74 lib-gate-cold emit_metrics supports --summary aggregation (CHG-155)" 1 "$COLD_TPL" '--summary)'
at_least_f "A74 bootstrap supports --dry-run preview (CHG-155)" 1 "$ROOT/scripts/bootstrap.sh" '--dry-run)'
report "A74 SHA256SUMS checksums --check passes and install supports --verify-sha256 (CHG-155)" 2 "$(( $(bash "$ROOT/scripts/release.sh" checksums --check >/dev/null 2>&1 && echo 1 || echo 0) + $(grep -cF -- '--verify-sha256)' "$ROOT/scripts/install.sh" >/dev/null && echo 1 || echo 0) ))"
report "A74 scripts/friction-report.sh is executable and parses cleanly (CHG-155)" 0 "$([[ -x "$ROOT/scripts/friction-report.sh" ]] && /bin/bash -n "$ROOT/scripts/friction-report.sh" >/dev/null 2>&1; echo $?)"
report "A74 scripts/mcp-governance-server.sh passes --self-test (CHG-155)" 0 "$([[ -x "$ROOT/scripts/mcp-governance-server.sh" ]] && bash "$ROOT/scripts/mcp-governance-server.sh" --self-test >/dev/null 2>&1; echo $?)"

# --- A75 (v4.11.0, CHG-156, REQ-1451~1454): 批 A 文档与细节一致性收口 ---
_a75_docs_ok=1
for _a75_f in "$SKILL" "$RM_EN" "$RM_ZH" "$STD"; do
  for _a75_kw in "enforcement.mode" "doctor" "metrics [--summary]" "verify-sha256" "SHA256SUMS" "friction-report" "mcp-governance-server" "GATE-E163" "GATE-E164" "--dry-run"; do
    grep -qF -- "$_a75_kw" "$_a75_f" 2>/dev/null || { echo "A75 missing '$_a75_kw' in $_a75_f" >&2; _a75_docs_ok=0; }
  done
done
report "A75 SKILL, READMEs and DS document v4.7..v4.10 capabilities (CHG-156)" 1 "$_a75_docs_ok"
report "A75 READMEs no longer claim no checksums published (CHG-156)" 0 "$(( $(grep_count_f "$RM_EN" 'publishes **no** checksums') + $(grep_count_f "$RM_ZH" '不发布**校验和') ))"
_a75_cc_en=0; _a75_cc_zh=0
[[ -f "$ROOT/CAPABILITY-COMPARISON.md" ]] && grep -qF 'Evolution Note (v4.5–v4.10)' "$ROOT/CAPABILITY-COMPARISON.md" && _a75_cc_en=1
[[ -f "$ROOT/能力对比分析.md" ]] && grep -qF '演进说明（v4.5–v4.10）' "$ROOT/能力对比分析.md" && _a75_cc_zh=1
report "A75 CAPABILITY-COMPARISON en/zh include v4.5-v4.10 evolution note (CHG-156)" 2 "$(( _a75_cc_en + _a75_cc_zh ))"
at_least_f "A75 sync-local-wrappers manages tests/audit-docs-consistency.sh (CHG-156)" 1 "$ROOT/scripts/sync-local-wrappers.sh" 'tests/audit-docs-consistency.sh:resources/templates/audit-docs-consistency.sh'
report "A75 release/update-assertion-count/shard-sum enforce 0644 on generated files (CHG-156)" 3 "$(( $(grep -cF 'chmod 0644' "$ROOT/scripts/release.sh" >/dev/null && echo 1 || echo 0) + $(grep -cF 'chmod 0644' "$ROOT/scripts/update-assertion-count.sh" >/dev/null && echo 1 || echo 0) + $(grep -cF 'chmod 0644' "$ROOT/scripts/shard-sum.sh" >/dev/null && echo 1 || echo 0) ))"
at_least_f "A75 .gitignore excludes .screenshots/ (CHG-156)" 1 "$ROOT/.gitignore" '.screenshots/'

# --- A76 (v4.12.0, CHG-157, REQ-1455~1459): Windows Git Bash/WSL2 兼容与 CI 冒烟 ---
report "A76 .gitattributes enforces LF on shell scripts and hooks (CHG-157)" 1 "$([[ -f "$ROOT/.gitattributes" ]] && grep -qF '*.sh text eol=lf' "$ROOT/.gitattributes" && grep -qF '.githooks/* text eol=lf' "$ROOT/.gitattributes" && echo 1 || echo 0)"
_a76_msys_bad=0
for _a76_f in "$ROOT/resources/templates/lib-json.sh" "$GATE_TPL" "$ROOT/scripts/bootstrap.sh" "$ROOT/scripts/install.sh" "$ROOT/resources/templates/session-gate.sh" "$ROOT/resources/templates/audit-docs-consistency.sh" "$ROOT/resources/templates/install-hook-adapter.sh" "$ROOT/resources/templates/install-ci-adapter.sh" "$ROOT/resources/templates/stamp-provenance.sh" "$ROOT/tests/run-tests.sh"; do
  grep -qF 'MSYS_NO_PATHCONV=1' "$_a76_f" 2>/dev/null || { echo "A76 missing MSYS_NO_PATHCONV in $_a76_f" >&2; _a76_msys_bad=$(( _a76_msys_bad + 1 )); }
done
report "A76 lib-json and core entrypoints export MSYS_NO_PATHCONV on Windows shells (CHG-157)" 0 "$_a76_msys_bad"
report "A76 has_real_python3 guards against Windows Store python3 stub (CHG-157)" 4 "$(( $(grep -cF 'has_real_python3' "$ROOT/resources/templates/lib-json.sh" >/dev/null && echo 1 || echo 0) + $(grep -cF 'has_real_python3' "$GATE_TPL" >/dev/null && echo 1 || echo 0) + $(grep -cF 'has_real_python3' "$COLD_TPL" >/dev/null && echo 1 || echo 0) + $(grep -cF 'has_real_python3' "$ROOT/resources/templates/install-hook-adapter.sh" >/dev/null && echo 1 || echo 0) ))"
at_least_f "A76 install.sh --as-skill supports Windows copy-mode fallback (CHG-157)" 1 "$ROOT/scripts/install.sh" '.dev-standards-skill-copy'
report "A76 install-hook-adapter emits windows_note and avoids bare System32 bash (CHG-157)" 2 "$(( $(grep -cF 'windows_note' "$ROOT/resources/templates/install-hook-adapter.sh" >/dev/null && echo 1 || echo 0) + $(grep -cF 'resolve_hook_bash' "$ROOT/resources/templates/install-hook-adapter.sh" >/dev/null && echo 1 || echo 0) ))"
report "A76 ci.yml defines windows-smoke job and READMEs carry Windows support matrix (CHG-157)" 3 "$(( $(grep -cF 'windows-smoke:' "$ROOT/.github/workflows/ci.yml" >/dev/null && echo 1 || echo 0) + $(grep -cF '### Windows Support Matrix' "$RM_EN" >/dev/null && echo 1 || echo 0) + $(grep -cF '### Windows 支持矩阵' "$RM_ZH" >/dev/null && echo 1 || echo 0) ))"

# --- A77 (v4.13.0, CHG-158): 批C 大文件结构化拆解与全链提速 ---
_a77_ag_lines=$(wc -l < "$GATE_TPL" | tr -d '[:space:]')
report "A77 agent-gate hot tier <= 550 lines with lazy load_gate_staged (CHG-158)" 1 \
  "$([[ "$_a77_ag_lines" -le 550 ]] && grep -qF 'load_gate_staged' "$GATE_TPL" && /bin/bash -n "$STAGED_TPL" 2>/dev/null && echo 1 || echo 0)"
report "A77 lib-gate-staged wired in bootstrap, is_code_path, and uninstall (CHG-158)" 3 \
  "$(( $(grep -cF 'lib-gate-staged.sh' "$ROOT/scripts/bootstrap.sh" >/dev/null && echo 1 || echo 0) + $(grep -cF 'lib-gate-staged.sh' "$GATE_TPL" >/dev/null && echo 1 || echo 0) + $(grep -cF 'lib-gate-staged.sh' "$ROOT/resources/templates/uninstall-standards.sh" >/dev/null && echo 1 || echo 0) ))"
_a77_rt_lines=$(wc -l < "$ROOT/tests/run-tests.sh" | tr -d '[:space:]')
_a77_scnt=$(ls "$ROOT/tests/suites/suite-"*.sh 2>/dev/null | wc -l | tr -d '[:space:]')
report "A77 run-tests dispatcher <= 1300 lines with test-harness and 8 domain suites (CHG-158)" 1 \
  "$([[ "$_a77_rt_lines" -le 1300 && "$_a77_scnt" -eq 8 && -s "$ROOT/tests/lib/test-harness.sh" ]] && /bin/bash -n "$ROOT/tests/lib/test-harness.sh" "$ROOT/tests/suites/"*.sh 2>/dev/null && echo 1 || echo 0)"
report "A77 T49 split into T49a/T49b/T49c with CoW new_repo prewarm (CHG-158)" 1 \
  "$(grep -qE '^SECTIONS=.*T49a T49b T49c' "$ROOT/tests/run-tests.sh" && ! grep -qE '^SECTIONS=.* T49 ' "$ROOT/tests/run-tests.sh" && grep -qF 'cp -c -pR' "$ROOT/tests/run-tests.sh" && grep -qF 'cp --reflink=auto' "$ROOT/tests/run-tests.sh" && echo 1 || echo 0)"
report "A77 audit-standards-src defines single-pass awk run_audit_rules engine (CHG-158)" 1 \
  "$([[ $(grep -c '^run_audit_rules()' "$ROOT/tests/audit-standards-src.sh") -ge 1 ]] && echo 1 || echo 0)"
}

if [[ "${AGENT_GUARD_AUDIT_PARALLEL:-1}" == "1" ]] && audit_parallel; then :; else
  for _s in "${AUDIT_BLOCKS[@]}"; do "audit_block_$_s"; done
fi

# ── PART A10b: 断言名集合基线（CHG-121 / batch 0）──────────────────────────────
# 总数相等 ≠ 断言齐备：BUG-004 中 A6c 整块未执行，审计仍报 `152 passed, 0 failed`
# （93 处假绿的同型根因）。只有「断言名集合」相等才能证明该跑的都跑了。
# 位置必须在**全部断言执行完之后、A10 之前**（放前面会与后续断言的集合差 200 条）。
# A10/A10b 自身的名字排除在比较之外（A10 在本块之后才执行）。
if [[ -f "$AUDIT_ASSERTIONS_BASELINE" ]]; then
  # v3.91.9 (CHG-127): docs/private-dependent assertions keep ONE stable name in
  # both environments (the SKIP fact is echoed as its own line), so this set
  # comparison needs no environment-specific normalization.
  a10b_cur=$(grep -vE '^A10b? ' "$AUDIT_NAMES_RUN" 2>/dev/null | sort -u || true)
  a10b_exp=$(grep -vE '^A10b? ' "$AUDIT_ASSERTIONS_BASELINE" 2>/dev/null | sort -u || true)
  a10b_d=$(comm -3 <(printf '%s\n' "$a10b_cur") <(printf '%s\n' "$a10b_exp") 2>/dev/null | wc -l | tr -d ' ')
  report "A10b audit assertion-name set matches baseline (CHG-121)" 0 "$a10b_d"
else
  report "A10b audit assertion-name baseline exists (CHG-121; run update-assertion-count.sh)" 1 0
fi

if [[ -f "$AUDIT_BASELINE" ]]; then
  expected_total=$(cat "$AUDIT_BASELINE" | tr -d '[:space:]')
  # soft (CI) mode: numeric drift warns instead of blocking; warn stays out of
  # this denominator (pass+fail-soft_pass), so the baseline comparison goes soft.
  # +1 = A10 itself (FU-937): the counter snapshot below is taken BEFORE this
  # report increments it, while the baseline (synced from the post-report
  # AUDIT_LAST write below) includes it — the old pre-report write recorded N-1
  # and the committed baseline sat one below the runtime executed count.
  if [[ -n "$SOFT" ]]; then
    report_soft "A10 audit executed-count matches baseline (FU-022; CI soft)" "$expected_total" "$(( pass + fail - soft_pass + 1 ))"
  else
    report "A10 audit executed-count matches baseline (FU-022)" "$expected_total" "$(( pass + fail - soft_pass + 1 ))"
  fi
else
  report "A10 audit baseline exists (FU-022; run scripts/update-assertion-count.sh)" 1 0
fi
# FU-937 (CHG-045): written AFTER the A10 report so the synced number equals the
# runtime executed total (the old pre-report write recorded N-1 → 静态基线恒比
# 运行时少一，正是 audit-baseline 差一的根因).
printf '%s\n' "$(( pass + fail - soft_pass ))" > "$AUDIT_LAST"
# Only a COMPLETED run replaces the name set the generator compares against.
sort -u "$AUDIT_NAMES_RUN" > "$AUDIT_NAMES_LAST.$$" 2>/dev/null && mv "$AUDIT_NAMES_LAST.$$" "$AUDIT_NAMES_LAST" 2>/dev/null || true
rm -f "$AUDIT_NAMES_RUN" 2>/dev/null || true

echo
echo "$pass passed, $fail failed"
if [[ "$warn" -gt 0 ]]; then
  echo "$warn soft warnings (AGENT_GUARD_AUDIT_SOFT; not blocking)"
fi
[[ "$fail" -eq 0 ]]
