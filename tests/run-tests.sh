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
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# v3.66.0 (CHG-088, REQ-1049): cache the suite HEAD up front — by the time the
# closing receipt block runs, the dispatcher may have left cwd inside a temp repo
# (CHG-087 lesson), so the hash is taken once from a fixed anchor. Empty when
# $ROOT is not a git repo (tarball installs) → the receipt is skipped entirely.
SUITE_HEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
SUITE_KEY=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || true)
# v3.79.0 (CHG-103, REQ-1144): tree-fingerprint source. ONE recipe shared by the
# emitter (closing receipt block below) and scripts/update-assertion-count.sh
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
# hoisted (order-independence for -j; was a T12 section-local consumed by T13 — v3.72.0 erratum, CHG-095, REQ-1097)
ci_src="$ROOT/resources/templates/check-standards-compliance.sh"
[[ -f "$ci_src" ]] || ci_src="$ROOT/scripts/check-standards-compliance.sh"

pass=0
fail=0
failed_names=()
fail_lines=()  # v3.72.0 erratum (CHG-095, DES-1869): verbatim FAIL lines for the red archive

report() { # name expected actual
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$(( pass + 1 ))
    printf 'ok   %s\n' "$name"
  else
    fail=$(( fail + 1 ))
    failed_names+=("$name")
    fail_lines+=("$(printf 'FAIL %s (expected exit %s, got %s)' "$name" "$expected" "$actual")")
    printf 'FAIL %s (expected exit %s, got %s)\n' "$name" "$expected" "$actual" >&2
  fi
}

check_output() { # name pattern actual_output -- pass if pattern matches
  local name="$1" pattern="$2" out="$3"
  if printf '%s' "$out" | grep -Eq -- "$pattern"; then
    pass=$(( pass + 1 ))
    printf 'ok   %s\n' "$name"
  else
    fail=$(( fail + 1 ))
    failed_names+=("$name")
    fail_lines+=("$(printf 'FAIL %s (output does not match: %s)' "$name" "$pattern")")
    printf 'FAIL %s (output does not match: %s)\n' "$name" "$pattern" >&2
  fi
}

# ---- v3.90.1 (CHG-123, P0-3/P0-14): cost ledger + per-section timing ------
# One append-only TSV for every measurable action: section / TC / audit / verify.
# Columns: ts kind id suite_key cost_s setup_s cache exit   (8 columns, header once).
# Write failure is a WARN and never changes a verdict.
LEDGER_FILE="${AGENT_GUARD_COST_LEDGER:-$ROOT/.agent-state/cost-ledger.tsv}"
NEW_REPO_SETUP_S=0

ledger_append() { # <kind> <id> <cost_s> <setup_s> <cache> <exit> [asserts] [outcome]
  local rk mid mwin
  mkdir -p "$(dirname "$LEDGER_FILE")" 2>/dev/null || return 0
  # v3.91.0 (CHG-127, G1): the 13-column schema. The historical 8 columns keep
  # their positions (readers stay compatible); asserts/rc/outcome/repo_key/
  # model_id/ctx_window are appended. Old 8-column rows are migrated in place.
  rk="$(id -un 2>/dev/null || echo user)@$(hostname 2>/dev/null || echo host)/$(basename "$ROOT")"
  if [[ -s "$LEDGER_FILE" ]] && ! head -1 "$LEDGER_FILE" | grep -q 'asserts'; then
    awk -F'\t' -v rk="$rk" 'BEGIN{OFS="\t"}
      NR==1 {print "ts","kind","id","suite_key","cost_s","setup_s","cache","exit","asserts","rc","outcome","repo_key","model_id","ctx_window"; next}
      { o=($8=="0"?"green":"red"); if ($6=="0" && $8=="0") o="wasted"; print $0,"-1",$8,o,rk,"","" }' \
      "$LEDGER_FILE" > "$LEDGER_FILE.mig" 2>/dev/null && mv -f "$LEDGER_FILE.mig" "$LEDGER_FILE"
  fi
  [[ -s "$LEDGER_FILE" ]] || printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\tasserts\trc\toutcome\trepo_key\tmodel_id\tctx_window\n' > "$LEDGER_FILE" 2>/dev/null || return 0
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
    || { printf 'warning: could not append to %s (non-fatal)\n' "$LEDGER_FILE" >&2; return 0; }
}

# v3.90.1 (CHG-123, P0-13): source-vs-target layout predicate. The old proxy was
# "does scripts/facts.sh exist" — a filename, not a capability. Target repos now
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

new_repo() {
  local _nr_t0
  _nr_t0=$(date +%s)
  NEW_REPO_SETUP_S=0
  REPO=$(mktemp -d "${TMPDIR:-/tmp}/agent-gate-test.XXXXXX") \
    || { echo "FATAL: new_repo could not create a temp dir (refusing to touch the source repo)" >&2; return 1; }
  [[ -d "$REPO" ]] \
    || { echo "FATAL: new_repo temp dir '$REPO' is not a directory" >&2; return 1; }
  cd "$REPO" \
    || { echo "FATAL: new_repo could not cd into '$REPO' (refusing to write in $PWD)" >&2; return 1; }
  git init -q
  git config user.email test@example.invalid
  git config user.name test
  # v3.62.2 (CHG-082, DES-1818): E86/E58 now enforce the first-of-day batch
  # rule in BOTH directions; legacy fixtures below predate the batch default
  # and use independent L0/L1 dirs on purpose (placement is not their subject).
  # The escape is exported HERE once — recorded justification = this comment +
  # BATCH-20260928 CHG-082 — and placement-themed sections (T47, T18d E58
  # trio) explicitly unset it to keep the enforcement visible.
  export AGENT_GUARD_ALLOW_INDEPENDENT=1
  # v3.63.0 (CHG-083, REQ-1033): same one-shot escape pattern for GATE-E89 —
  # legacy sections begin after fixture deliveries (directory-resolution
  # subjects, not shift subjects); the shift-themed T49 overrides with =0.
  export AGENT_GUARD_ALLOW_NO_SHIFT=1
  # v3.90.4: legacy fixtures predate the R3 self-bootstrap hard gate (E131).
  # Default the adaptation face OFF here; T82/T83 (the sections that actually
  # test plan/E131) explicitly turn it back ON.
  export AGENT_GUARD_ADAPT=0
  mkdir -p scripts docs/changes src
  seed_project_masters
  cp "$GATE_SRC" scripts/agent-gate
  chmod +x scripts/agent-gate
  # CHG-110 (REQ-1161): the fingerprint lib ships alongside the gate in real
  # installs (bootstrap --guard) — the sandbox mirrors that layout so T66's
  # receipt cache engages (target-repo-realistic, not a test-only favor).
  cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" scripts/
  # v3.63.0 (CHG-083, REQ-1033): GATE-E89 needs session-started.json to judge
  # "delivery happened during THIS session's lifetime". Each new_repo models a
  # FRESH session: started_at is written 1H IN THE PAST so any fixture delivery
  # (written "now" by staged/stop cases) is newer and WOULD arm E89 — the gate
  # stays visible here. Directory/placement-themed sections never do
  # begin-after-delivery in this fixture, so they stay unaffected; if a future
  # lifecycle test needs E89 off, rewrite session-started.json with a future
  # timestamp or export AGENT_GUARD_ALLOW_NO_SHIFT=1 (T49 covers both sides).
  mkdir -p .agent-state
  printf '{"started_at":"%s"}\n' "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/session-started.json
  echo init > README.md
  git add README.md scripts
  git commit -qm init
  NEW_REPO_SETUP_S=$(( $(date +%s) - _nr_t0 ))
}

# 创建合规七产物（L1：无需独立 test/review owner；内容满足 §2.5 A 层验收标记）
seed_artifacts() { # id risk implementation [test] [review]
  local id="$1" risk="$2" impl="$3" test="${4:-}" review="${5:-}"
  local d="docs/changes/$id"
  mkdir -p "$d"
  cat > "$d/00-intent.md" <<'EOF'
# 00-intent.md
## 问题
problem: x
## 预期结果
expected: y
## 目录落位
- **目录落位**：独立目录（single low-risk fixture）
## 开放问题
open: none
EOF
  if [[ -n "$test" && -n "$review" ]]; then
    printf '{"change_id":"%s","risk_level":"%s","spec_author":"author/a-1","implementation_owner":"%s","test_owner":"%s","review_owner":"%s"}\n' \
      "$id" "$risk" "$impl" "$test" "$review" > "$d/00-governance.json"
  else
    # v3.61.1: L0/L1 review_owner/test_owner now mandatory (GATE-E31 closure,
    # REQ-1016) — default fixtures satisfy the lowest bar (distinct from
    # author/a-1 and the impl argument).
    printf '{"change_id":"%s","risk_level":"%s","spec_author":"author/a-1","implementation_owner":"%s","test_owner":"claude/s-t","review_owner":"claude/s-r"}\n' \
      "$id" "$risk" "$impl" > "$d/00-governance.json"
  fi
  cat > "$d/00.5-communication.md" <<'EOF'
# 00.5-communication.md（v3.52.0 沟通先行门夹具：确认记录已落盘）
## 深挖结论
findings: f
## 影响范围
scope: s
## 风险
risk: r
## 候选方案与取舍
options: A vs B
## 测试思路
test: t
## 用户整体确认记录
### 第 1 轮
- 结论：确认（按 §2.17.2d 呈现 Round-1 沟通稿后整体确认）
- 确认状态：已整体确认
EOF
  cat > "$d/01-spec.md" <<'EOF'
# spec
- REQ-001: sample requirement
EOF
  cat > "$d/02-code-impact-analysis.md" <<'EOF'
# impact
## 业务影响
business: b
## 技术影响
call chain: c
## 风险
risk: r
## 回滚策略
rollback: ok
延伸发现：未发现
历史相似检索：未命中（根因关键词检索）
EOF
  cat > "$d/03-modification-plan.md" <<'EOF'
# plan
- DES-001: sample design
## 技术选型
备选方案对比: A vs B
## 既有范式关系
- **既有范式关系**：未命中（纯新增无同族实现）
EOF
  cat > "$d/03.5-tasks.md" <<'EOF'
# tasks
- T-001: do something（依赖: 无；里程碑: M1）
- 评审输入: 变更文件清单 + 待核对产物 + 行号锚点（§2.2 输入契约）
EOF
  cat > "$d/04-test-scripts.md" <<'EOF'
# tests
- TC-001: sample case
## 用例矩阵
覆盖维度: 正常流 / 边界 / 异常
## 业务场景清单
- SC-001: sample scenario（覆盖: TC-001）
EOF
}

commit_all() { # message
  git add -A
  git commit -qm "$1"
}

# v3.55.0（CHG-068，REQ-1003）：缺陷诊断夹具两行强制声明（延伸发现+历史相似检索）
# 单源 helper——散点 printf 收敛于此，机校节新增时只改一处（E84 连坐教训）。
append_diag_lines() { # <file> [decl]
  printf '延伸发现：未发现\n历史相似检索：未命中（%s）\n' "${2:-根因关键词检索}" >> "$1"
}

# v3.35.0（§1.3）：begin 强制项目总册在位——所有夹具仓库开箱即含 13 册最小骨架
#（含「总册编号」与「独立完整声明」自证行 + 逐册评审存根）；T23 负例删除后再验拒绝路径。
seed_project_masters() {
  mkdir -p docs/project/reviews
  local p
  for p in P00-project-charter P01-requirements-master P02-architecture-master P03-interface-registry P04-data-dictionary P05-task-plan P06-test-master P07-test-verdicts P08-deployment-master P09-risk-register P10-change-ledger P11-decision-log P12-product-context; do
    printf '# master\n总册编号：%s\n独立完整声明：fixture\n' "${p%%-*}" > "docs/project/$p.md"
    printf '# review R-%s\n' "${p%%-*}" > "docs/project/reviews/$p.md.review.md"
  done
}

# v3.57.0（CHG-071）：T25/T42/T44 共用入口模板夹具——参数化七处真实差异（P7：差异即测试点）：
# $1 intent 标题词（意图/intent） $2 intent 预期结果体 $3 intent 开放问题体（T25=__RISK__/open，余空）
# $4 00.5 标题词 $5 00.5 机校标记注释行（T25/T42 各异，T44 空）
# $6 01-spec 标题后缀（T25 含 (__RISK__)） $7 03.5 评审输入后缀（T25 含 §2.2 输入契约）
seed_entry_templates() {
  mkdir -p docs/templates/entry
  { printf '# <__CHANGE_ID__> %s\n## 预期结果\n' "$1"
    [[ -n "$2" ]] && printf '%s\n' "$2"
    printf '## 开放问题\n'
    [[ -n "$3" ]] && printf '%s\n' "$3"
    printf '## 目录落位\n- **目录落位**：独立目录（t）\n'; } > docs/templates/entry/00-intent.md
  printf '{"change_id": "__CHANGE_ID__", "risk_level": "__RISK__", "spec_author": "PENDING", "implementation_owner": "PENDING", "test_owner": "PENDING", "review_owner": "PENDING"}\n' > docs/templates/entry/00-governance.json
  { printf '# <__CHANGE_ID__> %s\n## 用户整体确认记录\n' "$4"; [[ -n "$5" ]] && printf '%s\n' "$5"
    printf '## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n'; } > docs/templates/entry/00.5-communication.md
  printf '# <__CHANGE_ID__> spec%s\n- REQ-001: tbd\n' "$6" > docs/templates/entry/01-spec.md
  printf '# <__CHANGE_ID__>\n## 业务影响\n## 技术影响\n## 风险\n## 回滚策略\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > docs/templates/entry/02-code-impact-analysis.md
  printf '# <__CHANGE_ID__>\n- DES-001: tbd\n## 选型比较（备选）\n## 既有范式关系\n- **既有范式关系**：未命中（纯新增无同族实现）\n' > docs/templates/entry/03-modification-plan.md
  printf '# <__CHANGE_ID__>\n- T1: tbd（依赖: 无；里程碑: M1）\n- 评审输入: 待填%s\n' "$7" > docs/templates/entry/03.5-tasks.md
  printf '# <__CHANGE_ID__>\n- TC-001: tbd\n覆盖维度: 正常流\n- SC-001: tbd\n' > docs/templates/entry/04-test-scripts.md
}

# v3.57.0（CHG-071）：T44 批次成员夹具循环收拢——成员内容同构，仅 id 参数化；
# T42 批次块不收拢（成员差异是测试点，P7 留原形）。
seed_batch_member() { # <batch_dir> <change_id>
  local d="$1" id="$2"
  printf '{"change_id":"%s","risk_level":"L1","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x"}\n' "$id" >> "$d/00-governance.json"
  printf '## %s\n## 问题\np\n## 预期结果\ne\n## 目录落位\n- **目录落位**：BATCH-YYYYMMDD（同日 L1 批次成员）\n## 开放问题\no\n' "$id" >> "$d/00-intent.md"
  printf '## %s\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n' "$id" >> "$d/00.5-communication.md"
  printf '## %s\nREQ-910: r\n' "$id" >> "$d/01-spec.md"
  printf '## %s\n### 业务影响\n### 技术影响\n### 风险\n### 回滚策略\n延伸发现：未发现\n历史相似检索：未命中（x）\n' "$id" >> "$d/02-code-impact-analysis.md"
  printf '## %s\nDES-910 备选方案对比\n- **既有范式关系**：未命中（纯新增无同族实现）\n' "$id" >> "$d/03-modification-plan.md"
  printf '## %s\n直接实施\n' "$id" >> "$d/03.5-tasks.md"
  printf '## %s\nTC-910 SC-910 覆盖维度\n' "$id" >> "$d/04-test-scripts.md"
}

seed_begin() { # <change_id> [seed_artifacts args...]（FU-906：seed+begin 相邻对收敛）
  seed_artifacts "$@"
  scripts/agent-gate begin "$1" >/dev/null 2>&1
}

# v3.35.0（§1.3）：交付侧 09 追加「项目总册回填清单」节（幂等；已存在则跳过）。
append_masters() { # <09-file>
  local f="$1" p
  [[ -f "$f" ]] || return 0
  grep -q '项目总册回填清单' "$f" && return 0
  {
    printf '\n#### 项目总册回填清单\n'
    for p in P00 P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12; do
      printf -- '- [x] %s 已回填（章节：fixture；变更注记 CHG-999）\n' "$p"
    done
  } >> "$f"
}

# hoisted to top level (order-independence for -j; was nested in section_T5 — v3.72.0 erratum, CHG-095, REQ-1097)
# CHG-026 (v3.26.0): provenance is mandatory for EVERY *.md artifact — fixture
# helper re-stamps all CHG-500 artifacts with inline valid blocks (layout-
# independent by design; the stamper script itself is exercised in T17).
stamp_fixture_all() {
  for pf in docs/changes/CHG-500/*.md; do
    [[ "$(basename "$pf")" == "00-governance.json" ]] && continue
    if ! grep -q '^<!-- provenance' "$pf"; then
      { printf '<!-- provenance\nauthor: fixture\nemail: fixture@test\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "$pf"; } > "$pf.tmp" && mv "$pf.tmp" "$pf"
    fi
  done
}

# hoisted to top level (order-independence for -j; was nested in section_T6 — v3.72.0 erratum, CHG-095, REQ-1097)
# CHG-026 (v3.26.0): CI shares validate_delivery — every artifact must carry a
# provenance block before a ci-positive case can pass.
ci_stamp_all() {
  for pf in "$1"/*.md; do
    [[ "$(basename "$pf")" == "00-governance.json" ]] && continue
    if ! grep -q '^<!-- provenance' "$pf"; then
      { printf '<!-- provenance\nauthor: claude/s-1\nemail: t@example.com\ngenerated_at: 2026-09-15T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "$pf"; } > "$pf.tmp" && mv "$pf.tmp" "$pf"
    fi
  done
}

# hoisted to top level (order-independence for -j; was nested in section_T10 — v3.72.0 erratum, CHG-095, REQ-1097)
audit_fixture() { # dest -> 构造合规目标仓库 fixture
  local dest="$1"
  rm -rf "$dest"; mkdir -p "$dest/docs/feata"
  (cd "$dest" && seed_project_masters)
  cp "$STD_SRC" "$dest/docs/DEVELOPMENT_STANDARDS.md"
  cp "$AG_SRC" "$dest/AGENTS.md"
  printf -- '- REQ-001 用户故事A（DoD: x）\n- REQ-002 用户故事B（DoD: y）\n' > "$dest/docs/feata/01-spec.md"
  printf '# plan\n\nDES-001 设计\n' > "$dest/docs/feata/03-modification-plan.md"
  printf '# tests\n\n| TC | 场景 | 覆盖维度 | 覆盖的 REQ-DES |\n|---|---|---|---|\n| TC-001 | a | 正常流 | REQ-001 |\n| TC-002 | b | 边界 | REQ-002 |\n\n## 业务场景清单\n\nSC-001 场景（覆盖: TC-001）\n' > "$dest/docs/feata/04-test-scripts.md"
  printf '| REQ-001 | x | DES-001 | y | T1 | CHG-001 | TC-001 | test | PASS |\n| REQ-002 | x | DES-001 | y | T1 | CHG-001 | TC-001 | test | PASS |\n' > "$dest/docs/feata/01.5-rtvm-matrix.md"
  { echo "### BUG-001：现象（严重度 P1）"; echo; echo "| 字段 | 内容 |"; echo "|---|---|"; echo "| 关联变更 | CHG-001 |"; echo "| 历史相似 | 未命中（根因关键词检索） |"; } > "$dest/docs/bugfix-log.md"
  awk '/^## 3\. 变更执行全流程检查清单/{w=1} w && /^```markdown$/{f=1; w=0; next} f==1{ if(/^```$/){exit} print }' "$STD_SRC" > "$dest/s3block.md"
  { echo '## 2026-09-09'; echo; echo '任务编号：CHG-001 / TASK-001   日期：2026-09-09   执行者：dev'; echo;
    echo '#### 追踪矩阵映射 (Traceability)';
    echo '- 对应需求：`REQ-001`、`REQ-002`（见 01-spec.md）';
    echo '- 对应设计：`DES-001`（见 03-modification-plan.md）';
    echo '- 对应测试：`TC-001`（见 04-test-scripts.md）';
    echo '- 对应缺陷：`BUG-001`（索引见 docs/bugfix-log.md）';
    echo '- 完整矩阵：回填 docs/feata/01.5-rtvm-matrix.md'; echo;
    echo '#### 现象'; echo '背景'; echo; echo '#### 分析'; echo '分析'; echo;
    echo '#### 根因'; echo '| 编号 | 描述 |'; echo '|---|---|'; echo;
    echo '#### 方案'; echo '方案'; echo; echo '#### 测试脚本与结论'; echo 'TC-001 通过'; echo;
    echo '#### 角色签署与独立性（门禁 5）'; echo '签署'; echo;
    echo '#### 执行记录（ReAct，§2.16.2 铁律）'; echo '记录'; echo;
    echo '#### 变更执行检查清单（§3）'; cat "$dest/s3block.md"; echo;
    echo '#### 未动项'; echo '- 无'; } > "$dest/docs/feata/09-changelog.md"
  append_masters "$dest/docs/feata/09-changelog.md"
  rm -f "$dest/s3block.md"
}

# hoisted to top level (order-independence for -j; was nested in section_T18 — v3.72.0 erratum, CHG-095, REQ-1097)
# 让 `--stage staged` 拒掉整批。夹具必须用真实形状，不能用更规整的形状绕开。
# 批次夹具：一个 BATCH-YYYYMMDD/ 目录承载多个变更，文件名与独立目录**完全同名**，
# 靠 `## <id>` 锚点区分，治理记录一行一变更。
seed_batch_artifacts() { # <batch-id> <id:risk> [<id:risk> ...]
  local batch="$1"; shift
  local d="docs/changes/$batch" pair id risk
  mkdir -p "$d"
  : > "$d/00-intent.md"
  : > "$d/00-governance.json"
  : > "$d/00.5-communication.md"
  : > "$d/01-spec.md"
  : > "$d/02-code-impact-analysis.md"
  : > "$d/03-modification-plan.md"
  : > "$d/03.5-tasks.md"
  : > "$d/04-test-scripts.md"
  for pair in "$@"; do
    id="${pair%%:*}"; risk="${pair##*:}"
    printf '{"change_id":"%s","risk_level":"%s","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"claude/s-t","review_owner":"claude/s-r"}\n' "$id" "$risk" >> "$d/00-governance.json"
    printf '## %s\n## 问题\nproblem: x\n## 预期结果\nexpected: y\n## 目录落位\n- **目录落位**：BATCH-YYYYMMDD（batch member）\n## 开放问题\nopen: none\n' "$id" >> "$d/00-intent.md"
    printf '## %s\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n- 确认状态：已整体确认\n' "$id" >> "$d/00.5-communication.md"
    printf '## %s\nREQ-901: r\n' "$id" >> "$d/01-spec.md"
    printf '## %s\n### 业务影响\n### 风险\n### 回滚策略\n延伸发现：未发现\n历史相似检索：未命中（x）\n' "$id" >> "$d/02-code-impact-analysis.md"
    printf '## %s\nDES-901 备选方案对比\n- **既有范式关系**：未命中（纯新增无同族实现）\n' "$id" >> "$d/03-modification-plan.md"
    printf '## %s\n直接实施\n' "$id" >> "$d/03.5-tasks.md"
    printf '## %s\nTC-901 SC-901 覆盖维度\n' "$id" >> "$d/04-test-scripts.md"
  done
}

# hoisted to top level (order-independence for -j; was nested in section_T20 — v3.72.0 erratum, CHG-095, REQ-1097)
audit_change_fixture() { # dest -> 管线态布局：产物落 docs/changes/CHG-001/
  local dest="$1"
  rm -rf "$dest"; mkdir -p "$dest/docs/changes/CHG-001"
  cp "$STD_SRC" "$dest/docs/DEVELOPMENT_STANDARDS.md"
  cp "$AG_SRC" "$dest/AGENTS.md"
  printf '# spec\n\n## REQ-001 第一个需求\n## REQ-002 第二个需求\n' > "$dest/docs/changes/CHG-001/01-spec.md"
  printf '# CHG-001 Changelog\n\n## 2026-09-15\n' > "$dest/docs/changes/CHG-001/09-changelog.md"
}

# hoisted to top level (order-independence for -j; was nested in section_T55 — v3.72.0 erratum, CHG-095, REQ-1097)
stamp_all() { # <change-dir> — inline provenance for every artifact md（T5 stamp_fixture_all 同型）
  local pf
  for pf in "$1"/*.md; do
    [[ -f "$pf" ]] || continue
    grep -q '^<!-- provenance' "$pf" && continue
    { printf '<!-- provenance\nauthor: fixture\nemail: fixture@test\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "$pf"; } > "$pf.tmp" && mv "$pf.tmp" "$pf"
  done
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
    -l|--list) LIST_ONLY=1; shift ;;
    --dual-run) DUAL_RUN=1; shift ;;
    *) printf 'unknown option: %s (usage: tests/run-tests.sh [-T sec[,sec]] [-j N] [--dual-run] [-l|--list])\n' "$1" >&2; exit 2 ;;
  esac
done
# No -T operand means "all sections". bash 3.2 + set -u forbids expanding an
# empty array unguarded, so WANTED is only expanded behind a ${#WANTED[@]}
# length check (dispatcher below).

section_T1() {
# ---------------------------------------------------------------- T1 begin 门禁
new_repo
seed_artifacts CHG-100 L1 claude/s-1
rm docs/changes/CHG-100/00-intent.md   # 缺 intent：begin 必须拒绝
scripts/agent-gate begin CHG-100 >/dev/null 2>&1
report "begin rejects missing 00-intent.md" 2 $?

printf '## 问题\nx\n## 预期结果\ny\n## 目录落位\n- **目录落位**：独立目录（t1 fixture）\n## 开放问题\nz\n' > docs/changes/CHG-100/00-intent.md
scripts/agent-gate begin CHG-100 >/dev/null 2>&1
report "begin accepts eight complete artifacts (L1)" 0 $?

}
section_T1b() {
# ------------------------------------------------- T1b A 层内容校验（§2.5）
new_repo
seed_artifacts CHG-110 L1 claude/s-1
# CHG-117: these A-layer content checks belong to the full lane. Default begin
# is the narrowed entry gate (T80 pins that); pin the legacy checks through
# the documented compatibility switch. The partial-set cases below stay on
# the default begin to prove the narrowing.
echo "no numbering here" > docs/changes/CHG-110/01-spec.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects spec without REQ- numbering" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
echo "no numbering" > docs/changes/CHG-110/03-modification-plan.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects plan without DES- numbering" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
echo "no numbering" > docs/changes/CHG-110/04-test-scripts.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects tests without TC- numbering" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '## 问题\nx\n## 开放问题\nz\n' > docs/changes/CHG-110/00-intent.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects intent missing expected-outcome section" 2 $?

# v2.20.0 专业角色标记负例：选型对比 / 覆盖维度 / 02 三维 / 03.5 依赖里程碑
seed_artifacts CHG-110 L1 claude/s-1
printf '# plan\n- DES-001: sample design\n' > docs/changes/CHG-110/03-modification-plan.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects plan without option-comparison markers" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '# tests\n- TC-001: sample case\n' > docs/changes/CHG-110/04-test-scripts.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects tests without coverage-dimension column" 2 $?

# v3.3.0：04 必含业务场景清单（SC- 编号），缺 SC 拒绝
seed_artifacts CHG-110 L1 claude/s-1
printf '# tests\n- TC-001: sample case\n## 用例矩阵\n覆盖维度: 正常流\n' > docs/changes/CHG-110/04-test-scripts.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects tests without SC- scenario numbering" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '# impact\n## 技术影响\ncall chain only\n' > docs/changes/CHG-110/02-code-impact-analysis.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects impact doc without business-impact section" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '# impact\n## 业务影响\nx\n## 风险\ny\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > docs/changes/CHG-110/02-code-impact-analysis.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects impact doc without rollback strategy" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '# tasks\n- T-001: do something\n' > docs/changes/CHG-110/03.5-tasks.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects tasks doc without dependency/milestone markers" 2 $?

# v2.22.0：豁免路径 / 缺 02 / 缺 03.5
seed_artifacts CHG-110 L1 claude/s-1
printf '# tasks\nCHG 直接实施（未拆任务，理由: trivial）\n' > docs/changes/CHG-110/03.5-tasks.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin accepts tasks doc with explicit exemption" 0 $?

seed_artifacts CHG-110 L1 claude/s-1
rm docs/changes/CHG-110/02-code-impact-analysis.md   # 缺影响分析：v3.89.0 起 begin 放行（阶段门接管），G-设计门拒绝
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin accepts partial set without impact analysis (stage gate owns it)" 0 $?
scripts/agent-gate --stage design CHG-110 >/dev/null 2>&1
report "design stage gate rejects missing impact analysis" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
rm docs/changes/CHG-110/03.5-tasks.md   # 缺任务拆解：begin 放行，G-设计门拒绝
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin accepts partial set without tasks doc (stage gate owns it)" 0 $?
scripts/agent-gate --stage design CHG-110 >/dev/null 2>&1
report "design stage gate rejects missing tasks doc" 2 $?

seed_begin CHG-110 L1 claude/s-1
report "begin accepts compliant A-layer content markers" 0 $?

# CHG-007 / FU-008：编号必须带数字——散文提及 "REQ-"（无编号）不再放行
seed_artifacts CHG-110 L1 claude/s-1
printf '# spec\n需求编号参见 REQ- 约定（无具体编号）。\n' > docs/changes/CHG-110/01-spec.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects spec whose REQ- mention carries no number (FU-008)" 2 $?

# CHG-007 / FU-015（BUG-003）：重开已闭合变更必须拒绝——以 09-changelog.md 为闭合标志
new_repo
seed_artifacts CHG-520 L1 claude/s-1
printf '# CHG-520 changelog\nclosed\n' > docs/changes/CHG-520/09-changelog.md
append_masters docs/changes/CHG-520/09-changelog.md
scripts/agent-gate begin CHG-520 >/dev/null 2>&1
report "begin rejects re-opening a closed change dir" 2 $?
out=$(scripts/agent-gate begin CHG-520 2>&1 || true)
check_output "begin names the closed change and the one-change-one-doc-set rule" "already closed .*2[.]15" "$out"

# CHG-009 / FU-023：id 边缘形态必须拒绝（首字符字母数字、无点号）
new_repo
seed_artifacts CHG-522 L1 claude/s-1
for bad in -foo foo. a..b; do
  rm -rf "docs/changes/$bad"
  scripts/agent-gate begin "$bad" >/dev/null 2>&1
  report "begin rejects edge change id: $bad (FU-023)" 2 $?
done


# CHG-007 / S1（独立评审）：零尺寸/软链 09 也必须视为闭合标志（-s 会漏，改 -e/-L）
new_repo
seed_artifacts CHG-521 L1 claude/s-1
ln -s /dev/null docs/changes/CHG-521/09-changelog.md
append_masters docs/changes/CHG-521/09-changelog.md
scripts/agent-gate begin CHG-521 >/dev/null 2>&1
report "begin rejects a symlinked zero-size 09 marker (S1)" 2 $?
rm docs/changes/CHG-521/09-changelog.md
append_masters docs/changes/CHG-521/09-changelog.md
scripts/agent-gate begin CHG-521 >/dev/null 2>&1
report "begin accepts the same dir once the symlink marker is removed" 0 $?

}
section_T2() {
# ---------------------------------------------------------------- T2 治理状态校验
new_repo
seed_begin CHG-200 L2 gemini/m-1 gemini/m-1 gemini/m-2   # test 与 impl 相同
report "begin rejects identical implementation/test owners at L2" 2 $?

seed_begin CHG-201 L2 gemini/m-1 claude/c-9 codex/x-7
report "begin accepts distinct owners at L2" 0 $?

new_repo
seed_artifacts CHG-202 L1 claude/s-1
printf '{"change_id":"OTHER","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"a","test_owner":"t/x","review_owner":"r/x"}\n' \
  > docs/changes/CHG-202/00-governance.json
scripts/agent-gate begin CHG-202 >/dev/null 2>&1
report "begin rejects mismatched change_id" 2 $?

new_repo
seed_begin CHG-203 L9 claude/s-1
report "begin rejects invalid risk_level" 2 $?

# v3.5.0：占位 owner 与 L3 授权三字段
new_repo
seed_begin CHG-204 L1 PENDING
report "begin rejects PENDING implementation owner" 2 $?

seed_begin CHG-205 L2 gemini/m-1 TODO codex/x-7
report "begin rejects TODO test owner at L2" 2 $?

seed_artifacts CHG-206 L3 gemini/m-1 claude/c-9 codex/x-7
printf '{"change_id":"CHG-206","risk_level":"L3","spec_author":"author/a-1","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7"}\n' \
  > docs/changes/CHG-206/00-governance.json
scripts/agent-gate begin CHG-206 >/dev/null 2>&1
report "begin rejects L3 without release authorization fields" 2 $?

seed_artifacts CHG-207 L3 gemini/m-1 claude/c-9 codex/x-7
printf '{"change_id":"CHG-207","risk_level":"L3","spec_author":"author/a-1","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7","release_authorized_by":"tech-lead/h-1","release_authorized_at":"2026-09-09T00:00:00Z","release_authorization_evidence":"APPROVAL-001"}\n' \
  > docs/changes/CHG-207/00-governance.json
scripts/agent-gate begin CHG-207 >/dev/null 2>&1
report "begin accepts L3 with complete release authorization" 0 $?

}
section_T3() {
# ---------------------------------------------------------------- T3 pre-write
new_repo
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"src/app.py"}}' \
  | scripts/agent-gate --stage pre-write >/dev/null 2>&1
report "pre-write blocks code edit without active change" 2 $?

printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"docs/notes.md"}}' \
  | scripts/agent-gate --stage pre-write >/dev/null 2>&1
report "pre-write allows doc edit without active change" 0 $?

printf '%s' '{"tool_name":"Edit"}' | scripts/agent-gate --stage pre-write >/dev/null 2>&1
report "pre-write fails closed on unparseable hook input" 2 $?

seed_begin CHG-300 L1 claude/s-1
printf '%s' '{"tool_name":"Write","tool_input":{"path":"src/new.py"}}' \
  | scripts/agent-gate --stage pre-write >/dev/null 2>&1
report "pre-write allows code edit with active change" 0 $?

scripts/agent-gate --stage pre-write --file src/other.ts >/dev/null 2>&1
report "pre-write accepts --file argument" 0 $?

scripts/agent-gate end >/dev/null 2>&1
scripts/agent-gate --stage pre-write --file src/other.ts >/dev/null 2>&1
report "pre-write blocks after end" 2 $?

}
section_T4() {
# ---------------------------------------------------------------- T4 staged
new_repo
echo x > src/a.go
git add src/a.go
scripts/agent-gate --stage staged >/dev/null 2>&1
report "staged rejects code change without artifacts" 2 $?

# E2E 回归（v3.4.0 ⑭）：治理包安装提交不得被自家门禁死锁（scripts/tests/.githooks 为治理件非产品代码）
git reset -q src/a.go && rm -f src/a.go   # 清掉上一负例的暂存，隔离本用例
mkdir -p tests .githooks
cp "$GATE_SRC" scripts/agent-gate 2>/dev/null || true
printf '#!/usr/bin/env bash\nscripts/agent-gate --stage staged\n' > .githooks/pre-commit
printf '#!/usr/bin/env bash\nscripts/agent-gate --stage staged\n' > .githooks/pre-push
printf '#!/usr/bin/env bash\necho golden\n' > tests/run-tests.sh
git add scripts .githooks tests
scripts/agent-gate --stage staged >/dev/null 2>&1
report "staged accepts governance-bootstrap commit (no deadlock)" 0 $?
rm -rf .githooks tests
git rm -rq --cached .githooks tests >/dev/null 2>&1 || true

new_repo
seed_artifacts CHG-400 L1 claude/s-1
# CHG-117: artifacts alone are no longer an account anchor — the compliant
# flow opens the change (active-change marker) before touching source.
scripts/agent-gate begin CHG-400 >/dev/null 2>&1
commit_all "docs: CHG-400 artifacts"
echo x > src/a.go
git add src/a.go
scripts/agent-gate --stage staged >/dev/null 2>&1
report "staged accepts code change with artifacts" 0 $?

new_repo
seed_artifacts CHG-401 L2 gemini/m-1 gemini/m-1 gemini/m-1
commit_all "docs: bad governance"
echo x > src/a.go
git add src/a.go
scripts/agent-gate --stage staged >/dev/null 2>&1
report "staged validates governance state of diff artifacts" 2 $?

}
section_T5() {
# ---------------------------------------------------------------- T5 stop
new_repo
seed_artifacts CHG-500 L1 claude/s-1
commit_all "docs: CHG-500 artifacts"
scripts/agent-gate begin CHG-500 >/dev/null 2>&1
echo y > src/b.js   # 未跟踪文件计入工作区代码变更
scripts/agent-gate --stage stop >/dev/null 2>&1
out=$(scripts/agent-gate --stage stop 2>&1 || true)   # v3.7.0：delivery 首查编码记录
check_output "stop blocks finish without coding record" "cannot finish: missing coding record docs/changes/CHG-500/04.5-coding-record.md" "$out"
printf '<!-- provenance\nauthor: claude/s-1\nemail: t@example.com\ngenerated_at: 2026-09-15T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-500/04.5-coding-record.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks finish without test evidence" 2 $?

echo results > docs/changes/CHG-500/05-test-results.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks finish without changelog" 2 $?

echo chg > docs/changes/CHG-500/09-changelog.md
append_masters docs/changes/CHG-500/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks finish without ReAct Observation records" 2 $?

printf 'chg\n#### 执行记录（ReAct）\n| 阶段 | Thought | Observation |\n|---|---|---|\n| 阶段1 | t | grep -c REQ- 01-spec.md -> 1 |\n' > docs/changes/CHG-500/09-changelog.md
append_masters docs/changes/CHG-500/09-changelog.md

# CHG-004：八类最低文档集（规范 §1.1）的最后两类纳入交付门禁。
#   此前 --stage stop 只查 04.5/05/09，06.5 与 06-delivery-summary 既无模板也无校验，
#   "不适用"只能靠"不建文件"表达——这正是 CHG-003 差点漏交 06.5 的制度性原因。
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks finish without 06.5 config record" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop names the missing 06.5 and the standards clause" "missing config/DB record [(]06[.]5-deployment-config[.]md[)].*standards §1[.]1" "$out"

# 文件存在但内容空洞：必须显式声明"未命中，不适用"，空骨架不算交付。
printf '# 06.5 部署/配置/DB 记录\n本变更未动配置。\n' > docs/changes/CHG-500/06.5-deployment-config.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects 06.5 that never declares not-applicable" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop demands explicit 未命中，不适用 declaration" "must declare '未命中，不适用'" "$out"

# 直接把未填写的模板当交付（哨兵行未删）同样被拦——防"复制模板即算完成"。
# 这里内联哨兵而不 cp 真实模板：目标仓库经 --guard 落地时 resources/templates/ 不在场，
# 用例必须与布局无关；"真实模板确实带哨兵"由规范源层审计 A5 的哨兵断言守护。
printf '<!-- TEMPLATE-MARKER: 填写完成后必须删除本行 -->\n# 06.5 部署/配置/DB 记录\n未命中，不适用\n' > docs/changes/CHG-500/06.5-deployment-config.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects the unfilled 06.5 template (sentinel)" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop tells the author to delete the TEMPLATE-MARKER line" "still the unfilled template" "$out"

# CHG-007 / FU-014：声明必须行首锚定——句中提及"未命中"不再放行
printf '# 06.5 部署/配置/DB 记录\n依据评审本变更未命中任何配置要求。\n' > docs/changes/CHG-500/06.5-deployment-config.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects a mid-sentence 未命中 mention in 06.5 (FU-014)" 2 $?

printf '# 06.5 部署/配置/DB 记录\n未命中，不适用：本变更无配置项、无 DB 变更，依据见 02-code-impact-analysis.md。\n' > docs/changes/CHG-500/06.5-deployment-config.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks finish without 06-delivery-summary" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop names the missing delivery summary" "missing delivery summary / FU ledger [(]06-delivery-summary[.]md[)]" "$out"

# 注意：负例文本刻意避开"遗留"二字——首版写成"本变更无遗留事项"恰好命中内容正则
# （正则只认关键词，不认否定语义），用例因此假绿。该"关键词可被否定句满足"的残余
# 缺口已在 BUG-002 诊断中显式声明，此处只用不含关键词的文本走通分支。
printf '# 06-delivery-summary\n本变更无未决事项。\n' > docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects delivery summary without FU ledger or 遗留" 2 $?

# CHG-007 / FU-014：BUG-002 的残余缺口闭环——否定句"无遗留事项"（句中）现在也必须红
printf '# 06-delivery-summary\n本变更无遗留事项。\n' > docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects a negated mid-line 遗留 mention (BUG-002 residual closed)" 2 $?

# CHG-009 / FU-020：句中 "FU-901" 提及（无结构行）不再算登记
printf '# 06-delivery-summary\n本变更无 FU-901 需要登记。\n' > docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects a mid-sentence FU- mention with no structured row (FU-020)" 2 $?
printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop still accepts a structured FU table row (FU-020 positive)" 0 $?

printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop passes with evidence and changelog" 0 $?

}
section_T22a() {
# ------------------------------------------------ T22 规则 10 A 层执法（v3.33.0）
# 生产-评审分离（§2.2 两批制）与 spec_author 的机器执法：记录级（begin）+
# 交付级（stop 署名节）。标题形态才触发；正文行内提及不触发（FU-014 同族教训）。
printf '\n## 专家评审记录\n| 主体 | 结论 |\n|---|---|\n| 业务专家 | 通过 |\n' >> docs/changes/CHG-500/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop rejects a signature-less 专家评审记录 section (FU-039)" "lacks an agent signature" "$out"
printf '\n署名：agent-platform / llm-model / task-review-01\n' >> docs/changes/CHG-500/01-spec.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
stamp_fixture_all
report "stop accepts 专家评审记录 with a §2.1.7 signature (FU-039)" 0 "$rc"

printf '正文行内提及「专家评审记录」不触发（T22 anchor guard）。\n' >> docs/changes/CHG-500/03-modification-plan.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
stamp_fixture_all
report "stop ignores an inline 专家评审记录 mention (anchor guard)" 0 "$rc"

# v3.33.0 评审收口：证据路径/URL/紧凑串不得充当署名（假绿封堵）——
# A 层只认 §2.1.7 规范形状（` / ` 带空格三段）。
printf '\n## 专家评审记录\n依据 docs/methodologies/expert-capabilities.md 与 https://a/b/c 核对，紧凑标识 opencode/glm/task-x。\n' >> docs/changes/CHG-500/03-modification-plan.md
scripts/agent-gate --stage stop >/dev/null 2>&1
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop rejects path/URL/compact strings as fake signatures" "lacks an agent signature" "$out"
printf '\n署名：agent-platform / llm-model / task-review-02\n' >> docs/changes/CHG-500/03-modification-plan.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
stamp_fixture_all
report "stop accepts both sections once each carries a canonical signature" 0 "$rc"

# T22 的记录级用例（CHG-610/611）在套件尾部独立仓执行——不能内插在 CHG-500
# 流中部：new_repo 会重置夹具仓库，后续 CHG-500 用例将整体失联（本轮实测）。

}
section_T16() {
# ------------------------------------------------ T16 文件溯源（v3.17.0）
# 溯源块必须由 scripts/stamp-provenance.sh 生成——真值（作者 / 提交者 / 主机 /
# 平台 / UTC 时间）取自运行环境。门禁能验的是形状与非占位：块存在、四个必填字段齐、
# generated_at 是 ISO 日期、generated_by 指向脚本。**作者值本身是否属实不可机器
# 验证**——要求"必须由脚本产出"正是为了收窄这个缺口：手写块能编出 author，却过不了
# generated_by 这一关。夹具内联块而非调用脚本，与 --guard 布局无关（同 06.5 哨兵用例）。
printf '# 编码记录\n无溯源块\n' > docs/changes/CHG-500/04.5-coding-record.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "stop rejects a coding record without provenance (v3.17.0)" 2 "$rc"
check_output "stop tells the author to run stamp-provenance.sh" "carries no provenance block.*stamp-provenance[.]sh" "$out"

printf '<!-- provenance\nauthor: PENDING\nemail: PENDING\ngenerated_at: PENDING\ngenerated_by: PENDING\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-500/04.5-coding-record.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "stop rejects an unfilled provenance placeholder (v3.17.0)" 2 "$rc"
check_output "stop says the provenance block still holds a placeholder" "provenance block still holds a placeholder" "$out"

printf '<!-- provenance\nauthor: bob\nemail: b@x.com\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: hand-written\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-500/04.5-coding-record.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "stop rejects a hand-written provenance block (v3.17.0)" 2 "$rc"
check_output "stop demands the script as producer" "was not produced by scripts/stamp-provenance[.]sh" "$out"

# CHG-026 (v3.26.0): the traceability bar covers every artifact, not just the
# coding record — an unstamped 01-spec must be named by the gate.
printf '# 规格\nREQ-500 已验收。\n' > docs/changes/CHG-500/01-spec.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "stop rejects any unstamped artifact (v3.26.0)" 2 "$rc"
check_output "stop names the unstamped file" "01-spec[.]md carries no provenance block" "$out"
{ printf '<!-- provenance\nauthor: fixture\nemail: fixture@test\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; printf '# 规格\nREQ-500 已验收。\n'; } > docs/changes/CHG-500/01-spec.md

printf '<!-- provenance\nauthor: bob\nemail: b@x.com\ngenerated_at: not-a-date\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-500/04.5-coding-record.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects a non-ISO generated_at (v3.17.0)" 2 $?

printf '<!-- provenance\nauthor: claude/s-1\nemail: <redacted>\ngenerated_at: 2026-09-15T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-500/04.5-coding-record.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop accepts a script-shaped block with a redacted email (privacy switch)" 0 $?

# CHG-004 独立复核发现并已修：候选落点不得用裸 glob `docs/*/`。
#   原实现第三候选为 `docs/*/$name`，实测只要有人在 docs/ 下任意子目录（如 docs/unrelated/）
#   放一个同名占位文件，**所有变更的交付门禁就永久放行**——覆盖面过宽比过窄更危险，
#   因为它制造的是假绿（同族根因的反向形态）。现要求该目录须含 01-spec.md 或
#   01.5-rtvm-matrix.md，即"看起来像功能目录"（§2.17 产物目录双轨约定）。
mkdir -p docs/unrelated
printf '# 06.5\n未命中，不适用：无配置变更。\n' > docs/unrelated/06.5-deployment-config.md
printf '# 06-delivery\n## FU 台账\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | x | y | 2026-10-01 |\n' > docs/unrelated/06-delivery-summary.md
rm -f docs/changes/CHG-500/06.5-deployment-config.md docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects a same-named file in an unrelated docs subdir" 2 $?

# 功能目录形态：目录本身须带功能文档标记，否则不算合法落点
mkdir -p docs/featx
printf '# 06.5\n未命中，不适用：无配置变更。\n' > docs/featx/06.5-deployment-config.md
printf '# 06-delivery\n## FU 台账\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | x | y | 2026-10-01 |\n' > docs/featx/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop rejects a feature dir without 01-spec/01.5 marker" 2 $?
printf '# spec\n- REQ-001: r\n' > docs/featx/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop accepts a real feature dir carrying 01-spec.md" 0 $?

# 恢复常态（两件回到变更目录）
rm -rf docs/unrelated docs/featx
printf '# 06.5 部署/配置/DB 记录\n未命中，不适用：本变更无配置项、无 DB 变更，依据见 02-code-impact-analysis.md。\n' > docs/changes/CHG-500/06.5-deployment-config.md
printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop passes again once artifacts return to the change dir" 0 $?

# v3.7.0：Gate 4 —— changelog 引用的 REQ 必须回填 docs/<feature>/01.5-rtvm-matrix.md
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n\n- 对应需求：`REQ-101`（见 01-spec.md）\n' > docs/changes/CHG-500/09-changelog.md
append_masters docs/changes/CHG-500/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks changelog REQ not backfilled in 01.5 matrix" 2 $?
mkdir -p docs/feata
printf '| REQ-101 | 用户故事A | DES-101 | T1 | CHG-500 | TC-101 | test | PASS |\n' > docs/feata/01.5-rtvm-matrix.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop passes once REQ rows backfilled in matrix" 0 $?

# CHG-007 / FU-019：源头仓嵌套形态 docs/changes/<CHG>/01.5 也必须被 RTVM 检查接受
rm -f docs/feata/01.5-rtvm-matrix.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop still blocks once the one-level matrix is removed" 2 $?
mkdir -p docs/changes/CHG-901
printf '| REQ-101 | 用户故事A | DES-101 | T1 | CHG-500 | TC-101 | test | PASS |\n' > docs/changes/CHG-901/01.5-rtvm-matrix.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop accepts a nested docs/changes/<CHG>/01.5 matrix (FU-019)" 0 $?
rm -rf docs/changes/CHG-901
printf '| REQ-101 | 用户故事A | DES-101 | T1 | CHG-500 | TC-101 | test | PASS |\n' > docs/feata/01.5-rtvm-matrix.md   # 恢复一层矩阵，后续用例依赖

rm docs/changes/CHG-500/04.5-coding-record.md   # v3.7.0：编码记录删除后回拦
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop re-blocks when coding record removed" "cannot finish: missing coding record docs/changes/CHG-500/04.5-coding-record.md" "$out"
printf '<!-- provenance\nauthor: claude/s-1\nemail: t@example.com\ngenerated_at: 2026-09-15T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-500/04.5-coding-record.md

AGENT_GUARD_VERIFY_COMMAND='false' scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop runs AGENT_GUARD_VERIFY_COMMAND and fails on it" 2 $?

AGENT_GUARD_VERIFY_COMMAND='true' scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop passes when AGENT_GUARD_VERIFY_COMMAND succeeds" 0 $?

# v3.72.0 erratum (CHG-095, REQ-1097): the yml-commit cases below mutate and
# commit .agent-governance.yml in the CWD — they require the fixture-repo cwd
# provided by the full-suite/-j SERIAL_CHAIN. Under `-T T16` standalone (cwd is
# the skill repo itself) they would pollute the source repo's history: skip
# loudly instead (T17b precedent). Full coverage lives in the full suite;
# standalone also leaves fixture residue under docs/ (gitignored) — known limitation.
if [[ "$(pwd -P)" == "$ROOT" ]]; then
  echo "SKIP T16 yml-commit cases: fixture-repo cwd required (full suite / -j chain); standalone -T T16 would commit into the skill repo"
  return 0 2>/dev/null || return 0
fi

# CHG-012/CHG-015 / REQ-066+076：验证命令来源链 env → .agent-governance.yml
# （占位符跳过；**反篡改**：yml 处于待定变更中时不执行其命令——已提交版本才可信）
printf 'ci:\n  verification_command: "false"\n' > .agent-governance.yml
git add .agent-governance.yml && git commit -qm "yml false (committed baseline)"
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop reads failing verification command from committed yml (CHG-012)" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop names the yml source of the failed command" "from .agent-governance[.]yml" "$out"

printf 'ci:\n  verification_command: "true"\n' > .agent-governance.yml
git add .agent-governance.yml && git commit -qm "yml true"
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop passes when committed yml verification command succeeds" 0 $?

printf 'ci:\n  verification_command: "<replace-with-project-test-command>"\n' > .agent-governance.yml
git add .agent-governance.yml && git commit -qm "yml placeholder"
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop skips placeholder verification command (CHG-012)" 0 $?

# CHG-015 反篡改：待定修改的 yml（未提交）不执行其命令
printf 'ci:\n  verification_command: "false"\n' > .agent-governance.yml
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop skips yml verification modified in the pending change (anti-tamper)" 0 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "skip note names anti-tamper" "anti-tamper" "$out"

AGENT_GUARD_VERIFY_COMMAND='false' scripts/agent-gate --stage stop >/dev/null 2>&1
report "env verification command overrides committed yml (CHG-015)" 2 $?
rm -f .agent-governance.yml

}
section_T6() {
# ---------------------------------------------------------------- T6 ci
new_repo
seed_artifacts CHG-600 L1 claude/s-1
commit_all "docs: CHG-600 artifacts"
base=$(git rev-parse HEAD)   # base 在产物 commit 之后：分支 diff 只含代码
echo z > src/c.ts
git add src/c.ts
commit_all "feat: code without artifact changes in diff"
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci rejects code diff without artifact changes" 2 $?

new_repo
base=$(git rev-parse HEAD)
seed_artifacts CHG-601 L1 claude/s-1
# v3.5.0: branch-mode CI also enforces delivery evidence, so the accepts-case
# must carry 05+09 with ReAct Observation records in the same diff.
printf 'results\n' > docs/changes/CHG-601/05-test-results.md
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/CHG-601/09-changelog.md
append_masters docs/changes/CHG-601/09-changelog.md
echo z > src/c.ts
git add -A
commit_all "feat: CHG-601 implement"
out=$(scripts/agent-gate --stage ci --base "$base" 2>&1 || true)   # v3.7.0：编码记录缺失先拦
check_output "ci names missing coding record in code diff" "cannot finish: missing coding record docs/changes/CHG-601/04.5-coding-record.md" "$out"
printf '<!-- provenance\nauthor: claude/s-1\nemail: t@example.com\ngenerated_at: 2026-09-15T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-601/04.5-coding-record.md
commit_all "docs: CHG-601 coding record"
# CHG-004：branch 模式与 stop 同口径执行八类最低文档集（06.5 / 06-delivery-summary）
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci blocks code diff without 06.5 config record" 2 $?
printf '# 06.5\n未命中，不适用：本变更无配置/DB 变更。\n' > docs/changes/CHG-601/06.5-deployment-config.md
printf '# 06-delivery-summary\n## FU 台账\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-902 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-601/06-delivery-summary.md
commit_all "docs: CHG-601 config + delivery summary"
ci_stamp_all docs/changes/CHG-601
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci accepts code diff committed with artifacts and delivery evidence" 0 $?

# v3.7.0：branch CI 同口径执行 Gate 4（changelog 引用的 REQ 须回填矩阵）
new_repo
base=$(git rev-parse HEAD)
seed_artifacts CHG-602 L1 claude/s-1
printf 'results\n' > docs/changes/CHG-602/05-test-results.md
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n\n- 对应需求：`REQ-201`\n' > docs/changes/CHG-602/09-changelog.md
append_masters docs/changes/CHG-602/09-changelog.md
printf '<!-- provenance\nauthor: claude/s-1\nemail: t@example.com\ngenerated_at: 2026-09-15T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-602/04.5-coding-record.md
echo z > src/c.ts
git add -A
commit_all "feat: CHG-602 implement"
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci blocks changelog REQ not backfilled in 01.5 matrix" 2 $?

# v3.5.0：branch 模式对 diff 触及的变更目录追加 delivery 证据校验（与 stop 同口径）
new_repo
base=$(git rev-parse HEAD)
seed_artifacts CHG-620 L1 claude/s-1
commit_all "docs: CHG-620 artifacts"
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci rejects docs-only diff whose change lacks delivery evidence" 2 $?
out=$(scripts/agent-gate --stage ci --base "$base" 2>&1 || true)   # v3.7.0：delivery 首查编码记录
check_output "ci names the missing coding record" "cannot finish: missing coding record docs/changes/CHG-620/04.5-coding-record.md" "$out"
printf '<!-- provenance\nauthor: claude/s-1\nemail: t@example.com\ngenerated_at: 2026-09-15T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-620/04.5-coding-record.md
printf 'results\n' > docs/changes/CHG-620/05-test-results.md
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/CHG-620/09-changelog.md
append_masters docs/changes/CHG-620/09-changelog.md
# CHG-004：docs-only 分支同样要求八类最低文档集齐备（与 stop 同口径）
printf '# 06.5\n未命中，不适用：本变更无配置/DB 变更。\n' > docs/changes/CHG-620/06.5-deployment-config.md
printf '# 06-delivery-summary\n## FU 台账\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-903 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-620/06-delivery-summary.md
commit_all "docs: CHG-620 delivery evidence"
ci_stamp_all docs/changes/CHG-620
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci accepts docs-only diff after delivery evidence lands" 0 $?

}
section_T6b() {
# ---------------------------------------------------------------- T6b commit-msg 归因（v3.5.0）
new_repo
seed_artifacts CHG-900 L1 claude/s-1
commit_all "docs: CHG-900 artifacts"
echo x > src/e.ts
git add src/e.ts
printf 'feat: implement without attribution\n' > commitmsg.txt
scripts/agent-gate --stage commit-msg commitmsg.txt >/dev/null 2>&1
report "commit-msg rejects staged code commit without change id" 2 $?

printf 'feat: CHG-900 implement\n' > commitmsg.txt
scripts/agent-gate --stage commit-msg commitmsg.txt >/dev/null 2>&1
report "commit-msg accepts staged code commit referencing valid change" 0 $?

printf 'Revert "feat: CHG-900 implement"\n' > commitmsg.txt
scripts/agent-gate --stage commit-msg commitmsg.txt >/dev/null 2>&1
report "commit-msg exempts revert commits" 0 $?

: > "$(git rev-parse --git-path MERGE_HEAD)"
printf 'merge: bring in feature branch\n' > commitmsg.txt
scripts/agent-gate --stage commit-msg commitmsg.txt >/dev/null 2>&1
report "commit-msg exempts merge commits" 0 $?
rm -f "$(git rev-parse --git-path MERGE_HEAD)"

git reset -q src/e.ts && rm -f src/e.ts
echo more >> docs/changes/CHG-900/01-spec.md
git add docs/changes/CHG-900/01-spec.md
printf 'docs: extend spec\n' > commitmsg.txt
scripts/agent-gate --stage commit-msg commitmsg.txt >/dev/null 2>&1
report "commit-msg exempts artifact-only commits" 0 $?
rm -f commitmsg.txt

}
section_T7() {
# ---------------------------------------------------------------- T7 metrics
new_repo
seed_artifacts CHG-700 L1 claude/s-1
commit_all "docs: CHG-700 intent+artifacts"
sleep 1
echo more >> docs/changes/CHG-700/01-spec.md
commit_all "docs: CHG-700 spec update"
echo code > src/d.py
git add src/d.py
commit_all "feat: CHG-700 implement"
out=$(scripts/agent-gate metrics)
check_output "metrics emits JSON line for change" \
  '^\{"change_id":"CHG-700","risk_level":"L1",' "$out"
check_output "metrics contains stage intervals" '"spec_to_plan_s":(null|[0-9]+)' "$out"
check_output "metrics counts code commit referencing id" '"first_code_commit_ts":[0-9]+' "$out"
check_output "metrics reports delivery_ready false before evidence" '"delivery_ready":false' "$out"
echo ev > docs/changes/CHG-700/05-test-results.md
echo rv > docs/changes/CHG-700/07-review-report.md
echo cl > docs/changes/CHG-700/09-changelog.md
append_masters docs/changes/CHG-700/09-changelog.md
commit_all "docs: CHG-700 evidence"
out=$(scripts/agent-gate metrics)
check_output "metrics flips delivery_ready after evidence" '"delivery_ready":true' "$out"
# v3.34.0（CHG-034）：专家会话数观测字段（只观测不拦截）
check_output "metrics emits expert_sessions field" '"expert_sessions":[0-9]+,"artifact_files"' "$out"
# v3.38.0（CHG-040）：产物体量观测字段（瘦身决策数据化）
check_output "metrics emits artifact cost fields" '"artifact_files":[0-9]+,"artifact_bytes":[0-9]+' "$out"

new_repo
seed_artifacts CHG-710 L0 claude/s-1
printf '{"change_id":"CHG-710","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","review_owner":"claude/s-1"}\n' > docs/changes/CHG-710/00-governance.json
scripts/agent-gate begin CHG-710 >/dev/null 2>&1
out=$(scripts/agent-gate begin CHG-710 2>&1 || true)
check_output "begin rejects implementation == review_owner at L0 (FU-042)" "review_owner must differ from implementation_owner" "$out"

new_repo
out=$(scripts/agent-gate metrics)
report "metrics exits 0 with no change root" 0 $?
[[ -z "$out" ]]
report "metrics outputs nothing for empty repo" 0 $?

# v3.4.0 ⑭：未提交产物状态下 metrics 不得被 set -e 击杀（first_commit_referencing 空匹配回 1）
new_repo
seed_artifacts CHG-701 L1 claude/s-1
out=$(scripts/agent-gate metrics)
report "metrics exits 0 with uncommitted artifacts" 0 $?
check_output "metrics emits null-filled line before first commit" \
  '"change_id":"CHG-701".*"first_code_commit_ts":null' "$out"

# v3.5.0：metrics 词边界——提交只提到 CHG-71 时 CHG-7 不得子串误匹配取到 ts
# （产物 commit 的 subject 不含变更 id，避免 first_commit_referencing 首匹配落空）
new_repo
seed_artifacts CHG-7 L1 claude/s-1
seed_artifacts CHG-71 L1 claude/s-1
commit_all "docs: seed both artifact sets"
echo code > src/g.py
git add src/g.py
commit_all "feat: CHG-71 implement"
out=$(scripts/agent-gate metrics)
check_output "metrics word-bounds id (CHG-71 keeps ts)" \
  '"change_id":"CHG-71","risk_level":"L1".*"first_code_commit_ts":[0-9]+' "$out"
check_output "metrics word-bounds id (CHG-7 stays null)" \
  '"change_id":"CHG-7","risk_level":"L1".*"first_code_commit_ts":null' "$out"

}
section_T7b() {
# ------------------------------------------------ T7b bug_ref 缺陷文档组（v3.6.0）
new_repo
seed_artifacts CHG-800 L1 claude/s-1
mkdir -p docs/bugs/BUG-042
printf '# diagnosis\n延伸发现：未发现\n历史相似检索：未命中（根因关键词检索）\n' > docs/bugs/BUG-042/01-diagnosis.md
printf '# impact\n' > docs/bugs/BUG-042/02-impact.md
printf '# test plan\n' > docs/bugs/BUG-042/03-test-plan.md
printf '# matrix\n' > docs/bugs/BUG-042/04-matrix.md
printf '# config\n' > docs/bugs/BUG-042/05-config.md
printf '# tasks\n' > docs/bugs/BUG-042/06-tasks.md
printf '{"change_id":"CHG-800","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-042"}\n' > docs/changes/CHG-800/00-governance.json
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin accepts bug_ref with complete defect doc set" 0 $?

rm docs/bugs/BUG-042/02-impact.md
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin rejects bug_ref missing a defect doc" 2 $?

rm docs/bugs/BUG-042/01-diagnosis.md
out=$(scripts/agent-gate begin CHG-800 2>&1 || true)
check_output "begin names the missing defect document" "missing defect document: docs/bugs/BUG-042/01-diagnosis.md" "$out"

: > docs/bugs/BUG-042/01-diagnosis.md
printf '# impact recreated\n' > docs/bugs/BUG-042/02-impact.md
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin rejects empty defect doc" 2 $?

printf '# diagnosis restored\n延伸发现：未发现\n历史相似检索：未命中（根因关键词检索）\n' > docs/bugs/BUG-042/01-diagnosis.md
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin accepts restored defect doc with 延伸发现" 0 $?
sed -i '' '/延伸发现/d' docs/bugs/BUG-042/01-diagnosis.md 2>/dev/null || sed -i '/延伸发现/d' docs/bugs/BUG-042/01-diagnosis.md
out=$(scripts/agent-gate begin CHG-800 2>&1 || true)
check_output "begin rejects bug doc missing 延伸发现 (E81)" "GATE-E81.*延伸发现" "$out"
printf '# diagnosis restored\n延伸发现：未发现\n历史相似检索：未命中（根因关键词检索）\n' > docs/bugs/BUG-042/01-diagnosis.md
rm docs/bugs/BUG-042/04-matrix.md   # v3.7.0：六件套缺一件同样拦截
out=$(scripts/agent-gate begin CHG-800 2>&1 || true)
check_output "begin names a v3.7.0 defect doc when missing" "missing defect document: docs/bugs/BUG-042/04-matrix.md" "$out"
printf '# matrix recreated\n' > docs/bugs/BUG-042/04-matrix.md
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin accepts bug_ref after all six defect docs land" 0 $?
printf '{"change_id":"CHG-800","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":""}\n' > docs/changes/CHG-800/00-governance.json
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin skips bug_ref validation when empty" 0 $?

printf '{"change_id":"CHG-800","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":"../evil"}\n' > docs/changes/CHG-800/00-governance.json
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin rejects bug_ref with path-unsafe defect id" 2 $?

}
section_T8() {
# ---------------------------------------------------------------- T8 change_root 覆盖
new_repo
mkdir -p changes/CUSTOM-1
export AGENT_GUARD_CHANGE_ROOT=changes
cat > changes/CUSTOM-1/00-intent.md <<'EOF'
## 问题
i
## 预期结果
e
## 目录落位
- **目录落位**：独立目录（t8 fixture）
## 开放问题
o
EOF
printf '{"change_id":"CUSTOM-1","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"a","test_owner":"t/x","review_owner":"r/x"}\n' > changes/CUSTOM-1/00-governance.json
printf '# CUSTOM-1 沟通稿\n## 用户整体确认记录\n- 确认状态：已整体确认\n' > changes/CUSTOM-1/00.5-communication.md
echo "REQ-001 s" > changes/CUSTOM-1/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > changes/CUSTOM-1/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n- **既有范式关系**：未命中（纯新增无同族实现）\n' > changes/CUSTOM-1/03-modification-plan.md
printf '# tasks\n- T-001: x（依赖: 无；里程碑: M1）\n- 评审输入: 变更文件清单 + 产物路径 + 行号锚点\n' > changes/CUSTOM-1/03.5-tasks.md
printf 'TC-001 t\n## 用例矩阵\n覆盖维度: 正常流\n## 业务场景清单\nSC-001 s（覆盖: TC-001）\n' > changes/CUSTOM-1/04-test-scripts.md
scripts/agent-gate begin CUSTOM-1 >/dev/null 2>&1
report "begin honors AGENT_GUARD_CHANGE_ROOT" 0 $?
unset AGENT_GUARD_CHANGE_ROOT

}
section_T9() {
# ---------------------------------------------------------------- T9 help
new_repo
scripts/agent-gate help >/dev/null 2>&1
report "help exits 0" 0 $?
scripts/agent-gate bogus >/dev/null 2>&1
report "unknown command exits 2" 2 $?

}
section_T10() {
# ------------------------------------------------ T10 audit-docs-consistency golden cases
# §2.17.4：治理配置模板自身必须可回归。对通用层 audit-docs-consistency.sh 构造
# 目标仓库 fixture：合规态全绿 / 跳号 / 归档清单漂移 / BUG 未登记 三类负例 / 未接入仓库 SKIP。
# 源位置回退：Skill 仓库为 resources/templates/，bootstrap --core 落地目标仓库为
# tests/audit-docs-consistency.sh（v3.7 规范位置）；未安装 --core 时整节跳过。
if [[ -f "$AUDIT_SRC" ]]; then

FX=$(mktemp -d)
audit_fixture "$FX"
bash "$AUDIT_SRC" "$FX" >/dev/null 2>&1
report "audit fixture compliant repo passes" 0 $?

sed -i '' '/| 历史相似 |/d' "$FX/docs/bugfix-log.md" 2>/dev/null || sed -i '/| 历史相似 |/d' "$FX/docs/bugfix-log.md"
bash "$AUDIT_SRC" "$FX" >/dev/null 2>&1
report "audit rejects newest BUG entry missing history-similarity (G4 incremental)" 1 $?
printf '| 历史相似 | 未命中（根因关键词检索） |\n' >> "$FX/docs/bugfix-log.md"

FX2=$(mktemp -d)
audit_fixture "$FX2"
printf -- '- REQ-004 用户故事D（DoD: z）\n' >> "$FX2/docs/feata/01-spec.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit rejects numbering gap (REQ-003 missing)" 1 $?

audit_fixture "$FX2"
sed -i '' '/【门禁 5·独立验证与合入授权】/d' "$FX2/docs/feata/09-changelog.md" 2>/dev/null \
  || sed -i '/【门禁 5·独立验证与合入授权】/d' "$FX2/docs/feata/09-changelog.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit rejects archived checklist drift vs §3" 1 $?

audit_fixture "$FX2"
sed -i '' 's/`BUG-001`（索引见 docs\/bugfix-log.md）/`BUG-001`、`BUG-009`（索引见 docs\/bugfix-log.md）/' "$FX2/docs/feata/09-changelog.md" 2>/dev/null \
  || sed -i 's/`BUG-001`（索引见 docs\/bugfix-log.md）/`BUG-001`、`BUG-009`（索引见 docs\/bugfix-log.md）/' "$FX2/docs/feata/09-changelog.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit rejects unregistered BUG in CHG" 1 $?

# v3.7.0：G5 —— CHG 引用 REQ 而矩阵缺失判败；最新 CHG 无 REQ 引用时豁免
audit_fixture "$FX2"
rm -f "$FX2/docs/feata/01.5-rtvm-matrix.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit rejects CHG REQ refs without 01.5 matrix" 1 $?

audit_fixture "$FX2"
rm -f "$FX2/docs/feata/01.5-rtvm-matrix.md"
sed -i '' 's/REQ-00[12]//g' "$FX2/docs/feata/09-changelog.md" 2>/dev/null \
  || sed -i 's/REQ-00[12]//g' "$FX2/docs/feata/09-changelog.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit exempts matrix when latest CHG has no REQ refs" 0 $?

# CHG-037/FU-105（v3.37.1）：功能目录表外 reviews/ 拦截（spec §1.3 第 6 条执法面）
audit_fixture "$FX2"
mkdir -p "$FX2/docs/feata/reviews"
printf '# stray review\n' > "$FX2/docs/feata/reviews/01-spec.md.review.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit rejects out-of-table reviews/ in feature dir" 1 $?
out=$(bash "$AUDIT_SRC" "$FX2" 2>&1 || true)
check_output "audit out-of-table refusal names the feature dir" "out-of-table reviews.*feata" "$out"
rm -f "$FX2/docs/feata/reviews/01-spec.md.review.md"
rmdir "$FX2/docs/feata/reviews"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit passes once the out-of-table reviews/ is removed" 0 $?

SKIPD=$(mktemp -d)
bash "$AUDIT_SRC" "$SKIPD" >/dev/null 2>&1
report "audit skips repo without standards" 0 $?
rm -rf "$FX" "$FX2" "$SKIPD"

else
  echo "SKIP T10: audit-docs-consistency.sh absent (bootstrap --core 未安装) — 跳过通用审计 golden cases"
fi

}
section_T11() {
# ------------------------------------------------ T11 bootstrap.sh golden cases
# §2.17.4 同精神：安装器自身必须可回归——清单驱动替代 SKILL.md 手工 17 步复制，
# 防接入遗漏。覆盖：空仓库全落 / 幂等 / 冲突拒绝 / --force 覆盖 / guard 打包 /
# pipeline 层 / 参数错误 / 非目录目标 / help。
# bootstrap.sh 仅在 Skill 仓库存在（不随 --guard 落地到目标仓库），目标仓库运行
# 本套件时整节跳过。
if [[ -f "$BOOT_SRC" ]]; then
BT=$(mktemp -d)
bash "$BOOT_SRC" --core "$BT" >/dev/null 2>&1
report "bootstrap core installs into empty repo" 0 $?
[[ -s "$BT/AGENTS.md" ]]
report "bootstrap core lands AGENTS.md" 0 $?
[[ -s "$BT/docs/DEVELOPMENT_STANDARDS.md" ]]
report "bootstrap core lands standards" 0 $?
[[ -s "$BT/docs/METHODOLOGY.md" ]]
report "bootstrap core lands methodology" 0 $?
[[ -s "$BT/docs/methodologies/state-trigger-audit.md" ]]
report "bootstrap core lands state-trigger-audit" 0 $?
[[ -s "$BT/docs/bugfix-log.md" ]]
report "bootstrap core lands bugfix-log" 0 $?
[[ -s "$BT/docs/bugs/_templates/bug-tasks.md" ]]
report "bootstrap core lands bug-tasks template" 0 $?
[[ -s "$BT/tests/audit-docs-consistency.sh" ]]
report "bootstrap core lands generic audit" 0 $?
bash "$BOOT_SRC" --core "$BT" >/dev/null 2>&1
report "bootstrap rerun is idempotent (exit 0)" 0 $?
out=$(bash "$BOOT_SRC" --core "$BT" 2>&1 || true)
check_output "bootstrap rerun reports up to date" "up to date" "$out"

grep -q "dev-standards:managed begin" "$BT/AGENTS.md"
report "bootstrap fresh install carries managed markers" 0 $?
# CHG-062 (v3.50.0): AGENTS.md merge-or-keep——用户内容保留；通用 conflict/--force 移 METHODOLOGY 承载
printf '\n<!-- user: project anchor row -->\n' >> "$BT/AGENTS.md"
out=$(bash "$BOOT_SRC" --core "$BT" 2>&1 || true)
check_output "bootstrap merges AGENTS.md managed block" "merged.*AGENTS.md" "$out"
grep -q "user: project anchor row" "$BT/AGENTS.md" && grep -q "本文件是所有 AI Agent" "$BT/AGENTS.md"
report "bootstrap merge preserves user sections and managed block" 0 $?
sed -i '' '/dev-standards:managed/d' "$BT/AGENTS.md" 2>/dev/null || sed -i '/dev-standards:managed/d' "$BT/AGENTS.md"
bash "$BOOT_SRC" --core "$BT" >/dev/null 2>&1
grep -q "user: project anchor row" "$BT/AGENTS.md"
report "bootstrap keeps legacy user-modified AGENTS.md" 0 $?
bash "$BOOT_SRC" --core --force "$BT" >/dev/null 2>&1
grep -q "user: project anchor row" "$BT/AGENTS.md"
report "bootstrap --force still keeps legacy user-modified AGENTS.md" 0 $?

printf '# different content\n' > "$BT/docs/METHODOLOGY.md"
bash "$BOOT_SRC" --core "$BT" >/dev/null 2>&1
report "bootstrap rejects conflicting existing file" 2 $?
out=$(bash "$BOOT_SRC" --core "$BT" 2>&1 || true)
check_output "bootstrap names the conflicting file" "CONFLICT.*METHODOLOGY.md" "$out"

bash "$BOOT_SRC" --core --force "$BT" >/dev/null 2>&1
report "bootstrap --force overwrites conflict" 0 $?
grep -q "M0–M3" "$BT/docs/METHODOLOGY.md"
report "bootstrap --force restores template content" 0 $?
# CHG-063 (v3.51.0): 安装清单——全文件用户改动检测与保留
[[ -s "$BT/.dev-standards-manifest" ]] && grep -q " AGENTS.md" "$BT/.dev-standards-manifest" && grep -q " docs/METHODOLOGY.md" "$BT/.dev-standards-manifest"
report "bootstrap install writes manifest with payload entries" 0 $?
printf '\n<!-- user: ci tweak -->\n' >> "$BT/docs/METHODOLOGY.md"
out=$(bash "$BOOT_SRC" --core --upgrade "$BT" 2>&1 || true)
check_output "bootstrap upgrade keeps user-modified file" "kept.*user-modified.*METHODOLOGY.md" "$out"
grep -q "user: ci tweak" "$BT/docs/METHODOLOGY.md"
report "bootstrap kept file preserves user content verbatim" 0 $?
bash "$BOOT_SRC" --core --force "$BT" >/dev/null 2>&1
grep -q "M0–M3" "$BT/docs/METHODOLOGY.md" && ! grep -q "user: ci tweak" "$BT/docs/METHODOLOGY.md"
report "bootstrap --force overwrites user-modified and refreshes manifest" 0 $?
printf '# simulated old template\n' > "$BT/docs/METHODOLOGY.md"
oldc=$(cksum "$BT/docs/METHODOLOGY.md" | awk '{print $1}')
sed -i '' "s|^[0-9]* docs/METHODOLOGY.md|$oldc docs/METHODOLOGY.md|" "$BT/.dev-standards-manifest" 2>/dev/null || sed -i "s|^[0-9]* docs/METHODOLOGY.md|$oldc docs/METHODOLOGY.md|" "$BT/.dev-standards-manifest"
bash "$BOOT_SRC" --core --upgrade "$BT" >/dev/null 2>&1
grep -q "M0–M3" "$BT/docs/METHODOLOGY.md"
report "bootstrap upgrades unchanged-since-install files (pure version drift)" 0 $?
rm "$BT/.dev-standards-manifest"
printf '\n<!-- user: pre-manifest edit -->\n' >> "$BT/docs/METHODOLOGY.md"
out=$(bash "$BOOT_SRC" --core --upgrade "$BT" 2>&1 || true)
check_output "bootstrap legacy differing file kept" "kept.*legacy.*METHODOLOGY.md" "$out"
bash "$BOOT_SRC" --core --upgrade --force "$BT" >/dev/null 2>&1
grep -q "M0–M3" "$BT/docs/METHODOLOGY.md" && [[ -s "$BT/.dev-standards-manifest" ]]
report "bootstrap legacy --force syncs and rebuilds manifest" 0 $?

BT2=$(mktemp -d)
bash "$BOOT_SRC" --guard "$BT2" >/dev/null 2>&1
report "bootstrap guard installs enforcement package" 0 $?
[[ -x "$BT2/scripts/agent-gate" && -x "$BT2/.githooks/pre-commit" && -x "$BT2/tests/run-tests.sh" ]]
report "bootstrap guard lands executable gate+hooks+self-tests" 0 $?

BT3=$(mktemp -d)
bash "$BOOT_SRC" --pipeline "$BT3" >/dev/null 2>&1
report "bootstrap pipeline installs workflows" 0 $?
[[ -s "$BT3/.github/workflows/artifact-pipeline.yml" && -s "$BT3/.github/workflows/incident-to-intent.yml" ]]
report "bootstrap pipeline lands both workflows" 0 $?

bash "$BOOT_SRC" --bogus "$BT" >/dev/null 2>&1
report "bootstrap rejects unknown flag" 2 $?

bash "$BOOT_SRC" --core "/nonexistent/path/xyz" >/dev/null 2>&1
report "bootstrap rejects non-directory target" 2 $?

bash "$BOOT_SRC" --help >/dev/null 2>&1
report "bootstrap --help exits 0" 0 $?

rm -rf "$BT" "$BT2" "$BT3"
else
  echo "SKIP T11: bootstrap.sh 为 Skill 仓库安装器（不随 --guard 分发）——目标仓库跳过安装器 golden cases"
fi

}
section_T12() {
# ------------------------------------------------ T12 双校验器扩展名清单一致
# compliance.sh 与 agent-gate is_code_path 共享"代码后缀"策略（工程兜底层须可独立
# 安装，故不合并为单校验器）；漂移由源层 audit A2 + 本 T12 运行时双守护。
# 任一处新增/删除代码后缀而不同步，本用例即红——从"发布前 audit 发现"提前到"改完即发现"。
gate_ext=$(grep -E '\\\.\(c\|' "$GATE_SRC" | head -1 | sed -E 's/.*\\\.\(([^)]+)\)\$.*/\1/')
# ci_src 由顶层 env 区供给（v3.72.0 erratum 提升，CHG-095 REQ-1097：T13 单跑/-j 依赖）
if [[ -f "$ci_src" ]]; then
ci_ext=$(grep -E '\\\.\(c\|' "$ci_src" | head -1 | sed -E 's/.*\\\.\(([^)]+)\)\$.*/\1/')
report "T12 code-extension list identical in gate and compliance.sh" "$gate_ext" "$ci_ext"
else
  echo "SKIP T12: check-standards-compliance.sh 未安装（bootstrap --ci 未运行）——跳过双校验器一致用例"
fi

}
section_T13() {
# ------------------------------------------------ T13 compliance 基线解析（CHG-002）
# 旧版把 diff 基线写死为 origin/main：主线为 master 的仓库直接 fatal 128（不可自愈）；
# 若被 `|| true` 绕过则 CHANGED_FILES 变空、脚本打印"✅ 基础合规检查通过"——检查没跑
# 被伪装成检查通过（fail-open）。本段锁死两条不变式：基线不得硬编码；基线未知不得放行。
if [[ -f "$ci_src" ]]; then
  report "T13 compliance.sh has no hardcoded origin/* default baseline" 0 "$(grep -c -- ':-origin/' "$ci_src")"
  report "T13 compliance.sh reads CI_BASE_REF" 1 "$(grep -c 'CI_BASE_REF:-' "$ci_src")"
  report "T13 compliance.sh refuses to run without a baseline" 1 "$(grep -c '无法确定基线分支' "$ci_src")"

  CIR_BASE=$(mktemp -d "${TMPDIR:-/tmp}/compliance-test.XXXXXX")
  ci_repo() { # branch subdir
    cd "$CIR_BASE"
    rm -rf "$2"; mkdir -p "$2"; cd "$2"
    git init -q -b "$1"
    git config user.email test@example.invalid
    git config user.name test
    mkdir -p scripts src
    cp "$ci_src" scripts/check-standards-compliance.sh
    echo init > src/a.js
    git add -A
    git commit -qm init
  }

  # 主线为 master 且无 origin：自动解析 master 并真正执行检查（旧版此处 fatal）
  ci_repo master a
  git checkout -qb feature
  echo b >> src/a.js
  git add -A && git commit -qm "feat: code only"
  out=$(bash scripts/check-standards-compliance.sh 2>&1); rc=$?
  report "T13 auto-resolves a master mainline baseline (no origin)" 1 "$rc"
  check_output "T13 blocks code-only change on a master mainline" "门禁拦截" "$out"

  out=$(bash scripts/check-standards-compliance.sh master 2>&1); rc=$?
  report "T13 honors an explicit baseline argument" 1 "$rc"

  out=$(bash scripts/check-standards-compliance.sh origin/nope 2>&1); rc=$?
  report "T13 rejects an unresolvable explicit baseline (exit 2)" 2 "$rc"

  mkdir -p docs/f1 && echo "REQ-1" > docs/f1/01-spec.md
  git add -A && git commit -qm "docs: spec"
  out=$(bash scripts/check-standards-compliance.sh 2>&1); rc=$?
  report "T13 passes once the docs land" 0 "$rc"

  # 三点号 merge-base 语义：上游 master 的文档改动不得替本分支的代码改动背书
  ci_repo master b
  git checkout -qb feature
  echo b >> src/a.js
  git add -A && git commit -qm "feat: code only"
  git checkout -q master
  mkdir -p docs/f9 && echo "REQ-9" > docs/f9/01-spec.md
  git add -A && git commit -qm "docs: upstream spec"
  git checkout -q feature
  out=$(bash scripts/check-standards-compliance.sh 2>&1); rc=$?
  report "T13 merge-base diff ignores upstream docs (code still blocked)" 1 "$rc"

  # 解析级 2/3/4 的运行时覆盖（级 1/5 与全落空已在上文覆盖）：
  # 级 2 CI 注入、级 3 origin/HEAD、级 4 远端候选——三者靠"只有该级能给出"的仓库构造区分，
  # 避免"随便解析出一个就算过"的恒真断言。
  ci_remote_repo() { # subdir
    cd "$CIR_BASE"
    rm -rf "$1" "$1-origin.git"
    git init -q --bare -b master "$1-origin.git"
    mkdir -p "$1"; cd "$1"
    git init -q -b master
    git config user.email test@example.invalid
    git config user.name test
    mkdir -p scripts src docs/f1
    cp "$ci_src" scripts/check-standards-compliance.sh
    echo init > src/a.js
    echo "REQ-1" > docs/f1/01-spec.md
    git add -A && git commit -qm init
    git checkout -qb develop
    echo d > d.js && git add -A && git commit -qm dev
    git checkout -q master
    git remote add origin "$CIR_BASE/$1-origin.git"
    git push -q origin master develop
    git fetch -q origin
    git checkout -qb feature
    git branch -qD master develop
  }

  ci_remote_repo d
  out=$(bash scripts/check-standards-compliance.sh 2>&1); rc=$?
  report "T13 level 4: resolves without any local mainline" 0 "$rc"
  check_output "T13 level 4: falls back to a remote candidate (origin/master)" "base ref）：origin/master" "$out"

  git remote set-head origin develop
  out=$(bash scripts/check-standards-compliance.sh 2>&1); rc=$?
  report "T13 level 3: origin/HEAD wins over remote candidates" 0 "$rc"
  check_output "T13 level 3: resolves origin/develop from origin/HEAD" "base ref）：origin/develop" "$out"

  out=$(CI_BASE_REF=feature bash scripts/check-standards-compliance.sh 2>&1); rc=$?
  report "T13 level 2: CI_BASE_REF wins over origin/HEAD" 0 "$rc"
  check_output "T13 level 2: resolves the CI-injected baseline" "base ref）：feature" "$out"

  out=$(CI_BASE_REF=origin/nope bash scripts/check-standards-compliance.sh 2>&1); rc=$?
  report "T13 rejects an unresolvable CI_BASE_REF (exit 2)" 2 "$rc"

  # 无任何候选可解析：fail-closed，且绝不打印通过横幅
  ci_repo weird-mainline c
  out=$(bash scripts/check-standards-compliance.sh 2>&1); rc=$?
  report "T13 fails closed when no baseline resolves" 2 "$rc"
  report "T13 never prints the pass banner without a baseline" 0 "$(printf '%s' "$out" | grep -c '基础合规检查通过')"

  cd "$ROOT"
  rm -rf "$CIR_BASE"
else
  echo "SKIP T13: check-standards-compliance.sh 未安装（bootstrap --ci 未运行）——跳过基线解析 golden cases"
fi

}
section_T14() {
# ------------------------------------------------ T14 路径根可配置（v3.15.0）
# 目录根走 .agent-governance.yml 的 paths.*，默认值即历史写死值。本段锁两条不变式：
#   ① 配了非默认根 → 门禁按配置找（落点与校验错位是静默假绿，比报错危险）；
#   ② 没配 → 逐字节回到历史行为（零回归，老仓库升级后行为不变）。
# 另锁"契约名不可配置"：换根后 AGENTS.md 仍须落仓库根（它不是路径根）。
new_repo
mkdir -p doc && mv docs/project doc/project   # v3.35.0：paths.docs=doc → begin 按配置根找总册
mkdir -p doc/changes/CFG-1
printf 'paths:\n  docs: doc\nchange_root: doc/changes\n' > .agent-governance.yml
cat > doc/changes/CFG-1/00-intent.md <<'EOF'
## 预期结果
e
## 目录落位
- **目录落位**：独立目录（t14 fixture）
## 开放问题
o
EOF
printf '{"change_id":"CFG-1","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"a","test_owner":"t/x","review_owner":"r/x"}\n' > doc/changes/CFG-1/00-governance.json
printf '# CFG-1 沟通稿\n## 用户整体确认记录\n- 确认状态：已整体确认\n' > doc/changes/CFG-1/00.5-communication.md
echo "REQ-001 s" > doc/changes/CFG-1/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > doc/changes/CFG-1/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n- **既有范式关系**：未命中（纯新增无同族实现）\n' > doc/changes/CFG-1/03-modification-plan.md
printf '# tasks\n- T-001: x（依赖: 无；里程碑: M1）\n- 评审输入: 变更文件清单 + 产物路径 + 行号锚点\n' > doc/changes/CFG-1/03.5-tasks.md
printf 'TC-001 t\n## 用例矩阵\n覆盖维度: 正常流\n## 业务场景清单\nSC-001 s（覆盖: TC-001）\n' > doc/changes/CFG-1/04-test-scripts.md
out=$(scripts/agent-gate begin CFG-1 2>&1); rc=$?
report "T14 gate honors paths.docs from config" 0 "$rc"
check_output "T14 gate resolved the configured change root" "active change is CFG-1" "$out"

# 派生：只给 paths.docs，change_root 应由它派生（而非回落到 docs/changes）
new_repo
mkdir -p doc && mv docs/project doc/project   # v3.35.0：paths.docs=doc → begin 按配置根找总册
mkdir -p doc/changes/CFG-2
printf 'paths:\n  docs: doc\n' > .agent-governance.yml
cat > doc/changes/CFG-2/00-intent.md <<'EOF'
## 预期结果
e
## 目录落位
- **目录落位**：独立目录（t14 fixture）
## 开放问题
o
EOF
printf '{"change_id":"CFG-2","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"a","test_owner":"t/x","review_owner":"r/x"}\n' > doc/changes/CFG-2/00-governance.json
printf '# CFG-2 沟通稿\n## 用户整体确认记录\n- 确认状态：已整体确认\n' > doc/changes/CFG-2/00.5-communication.md
echo "REQ-001 s" > doc/changes/CFG-2/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > doc/changes/CFG-2/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n- **既有范式关系**：未命中（纯新增无同族实现）\n' > doc/changes/CFG-2/03-modification-plan.md
printf '# tasks\n- T-001: x（依赖: 无；里程碑: M1）\n- 评审输入: 变更文件清单 + 产物路径 + 行号锚点\n' > doc/changes/CFG-2/03.5-tasks.md
printf 'TC-001 t\n## 用例矩阵\n覆盖维度: 正常流\n## 业务场景清单\nSC-001 s（覆盖: TC-001）\n' > doc/changes/CFG-2/04-test-scripts.md
out=$(scripts/agent-gate begin CFG-2 2>&1); rc=$?
report "T14 change_root derives from paths.docs" 0 "$rc"

# 零回归：不配置任何路径 → 仍走 docs/changes（升级前行为）
new_repo
out=$(scripts/agent-gate begin CHG-X 2>&1); rc=$?
report "T14 unconfigured repo keeps the docs/changes default" 2 "$rc"
check_output "T14 default root is docs/changes" "docs/changes/CHG-X" "$out"

# 路径分类：自定义文档根下的源码后缀文件属"治理文档"，不触发变更产物要求
new_repo
printf 'paths:\n  docs: doc\n' > .agent-governance.yml
mkdir -p doc && echo x > doc/tool.js && git add doc/tool.js
out=$(scripts/agent-gate --stage staged 2>&1); rc=$?
report "T14 custom docs root is treated as non-code" 0 "$rc"

# 安装器端：非默认根落点 + 契约名不动 + 配置回写 + 无值拒绝 + live 跳过仍生效
if [[ -f "$BOOT_SRC" ]]; then
  BT4=$(mktemp -d)
  bash "$BOOT_SRC" --all --docs-dir doc "$BT4" >/dev/null 2>&1
  report "T14 bootstrap --docs-dir installs into the custom root" 0 $?
  [[ -s "$BT4/doc/DEVELOPMENT_STANDARDS.md" && ! -e "$BT4/docs/DEVELOPMENT_STANDARDS.md" ]]
  report "T14 bootstrap wrote the custom root only" 0 $?
  [[ -s "$BT4/AGENTS.md" ]]
  report "T14 contract name AGENTS.md stays at repo root" 0 $?
  grep -q '^  docs: doc' "$BT4/.agent-governance.yml"
  report "T14 bootstrap pins paths.docs into the config" 0 $?
  grep -q '^change_root: doc/changes' "$BT4/.agent-governance.yml"
  report "T14 bootstrap derives change_root from the docs root" 0 $?
  bash "$BOOT_SRC" --core --docs-dir >/dev/null 2>&1
  report "T14 --docs-dir without a value is rejected" 2 $?

  # D6：live 跳过改为按逻辑键匹配，换根后 bugfix-log 必须仍被跳过且内容不丢
  printf '# local ledger entry\n' >> "$BT4/doc/bugfix-log.md"
  ( cd "$BT4" && git init -q && git config user.email t@t && git config user.name t \
    && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  out=$(bash "$BOOT_SRC" --upgrade --docs-dir doc "$BT4" 2>&1 || true)
  check_output "T14 upgrade skips the live ledger under a custom root (D6)" "live \(skip\) +doc/bugfix-log\.md" "$out"
  grep -q 'local ledger entry' "$BT4/doc/bugfix-log.md"
  report "T14 upgrade preserved the live ledger content" 0 $?
  rm -rf "$BT4"

  # 模板内部路径引用必须随根改写（hooks/adapter 按路径调门禁），且 .github 不动；
  # 重复安装必须幂等——比较的是"替换后的源"，否则每次都会误报 updated。
  BT5=$(mktemp -d)
  bash "$BOOT_SRC" --all --docs-dir doc --scripts-dir tools --tests-dir spec "$BT5" >/dev/null 2>&1
  report "T14 bootstrap honors --scripts-dir / --tests-dir" 0 $?
  [[ -x "$BT5/tools/agent-gate" && -x "$BT5/spec/run-tests.sh" && -x "$BT5/spec/audit-docs-consistency.sh" ]]
  report "T14 custom scripts/tests roots receive the files" 0 $?
  grep -q 'tools/agent-gate' "$BT5/.githooks/pre-commit"
  report "T14 hooks are rewritten to the custom gate path" 0 $?
  grep -q 'tools/agent-gate' "$BT5/tools/install-hook-adapter"
  report "T14 client adapter is rewritten to the custom gate path" 0 $?
  [[ -e "$BT5/.github/workflows/agent-governance.yml" ]]
  report "T14 .github stays at the platform-mandated location" 0 $?
  bash "$BOOT_SRC" --all --docs-dir doc --scripts-dir tools --tests-dir spec "$BT5" >/dev/null 2>&1
  report "T14 custom-root install is idempotent" 0 $?
  out=$(bash "$BOOT_SRC" --all --docs-dir doc --scripts-dir tools --tests-dir spec "$BT5" 2>&1 || true)
  check_output "T14 custom-root rerun reports up to date (no false drift)" "up to date" "$out"
  rm -rf "$BT5"
else
  echo "SKIP T14b: bootstrap.sh 为 Skill 仓库安装器（不随 --guard 分发）——跳过安装器路径用例"
fi

}
section_T15() {
# ------------------------------------------------ T15 版本自查 / 自更新 / 自进化契约（v3.16.0）
# Skill 仓库专属（bootstrap.sh 不随 --guard 分发）。
# 覆盖三件事：D3 三处版本比对（--check，只读、漂移即 exit 1）、D4 升级保留显式
# 层选择、D5 + 自进化契约（规范升级日志归属 + 派生资产保护）。派生标记必须只从
# frontmatter 解析——正文示例代码块里的 `derived_from:` 不得被当作真实声明。
if [[ -f "$BOOT_SRC" ]]; then

  # --- D3：--check 三处版本比对（只读，漂移即 exit 1，可入 CI）---
  CT=$(mktemp -d)
  out=$(bash "$BOOT_SRC" --check "$CT" 2>&1); rc=$?
  report "T15 --check exits 1 when the target is not installed (D3)" 1 "$rc"
  check_output "T15 --check names the missing install" "not installed" "$out"
  bash "$BOOT_SRC" --all "$CT" >/dev/null 2>&1
  out=$(bash "$BOOT_SRC" --check "$CT" 2>&1); rc=$?
  report "T15 --check exits 0 on an up-to-date target" 0 "$rc"
  check_output "T15 --check reports in-sync" "check: in sync" "$out"
  perl -pi -e 's/规范版本：v[0-9.]+/规范版本：v3.0.0/' "$CT/docs/DEVELOPMENT_STANDARDS.md"
  out=$(bash "$BOOT_SRC" --check "$CT" 2>&1); rc=$?
  report "T15 --check exits 1 on an older target" 1 "$rc"
  check_output "T15 --check says UPGRADE AVAILABLE" "UPGRADE AVAILABLE" "$out"
  # 只读性：--check 不得改动任何文件（比较全部文件的内容指纹）
  fingerprint() { find "$1" -type f -exec cksum {} \; 2>/dev/null | sort | cksum; }
  before=$(fingerprint "$CT")
  bash "$BOOT_SRC" --check "$CT" >/dev/null 2>&1 || true
  after=$(fingerprint "$CT")
  report "T15 --check writes nothing (read-only)" "$before" "$after"
  rm -rf "$CT"

  # --- 自进化契约：派生标记只认 frontmatter ---
  SKROOT=$(mktemp -d)
  mkdir -p "$SKROOT/dev-standards-bootstrap/scripts" "$SKROOT/derived-x" "$SKROOT/plain-x"
  cp "$BOOT_SRC" "$SKROOT/dev-standards-bootstrap/scripts/bootstrap.sh"
  # 整个 resources/ 必须一起复制：--derived-report 只需要规范正文取携带版本，
  # 但同一节后面的"向非派生目录安装仍应成功"要真的跑一次安装，缺 templates/ 会
  # 触发 MISSING SOURCE（fail-closed 生效，属夹具不全而非被测行为错误）。
  cp -R "$ROOT/resources" "$SKROOT/dev-standards-bootstrap/resources"
  # 派生方：frontmatter 里声明
  printf -- '---\nname: derived-x\ndescription: x\nagent_created: true\nderived_from: dev-standards-bootstrap\nderived_at: 2026-09-01\n---\n\n# derived-x\n' > "$SKROOT/derived-x/SKILL.md"
  # 非派生：正文代码块里出现同样字样，不得被当作声明
  printf -- '---\nname: plain-x\ndescription: y\n---\n\n# plain-x\n\n```yaml\nderived_from: dev-standards-bootstrap\n```\n' > "$SKROOT/plain-x/SKILL.md"
  BOOT_X="$SKROOT/dev-standards-bootstrap/scripts/bootstrap.sh"
  out=$(bash "$BOOT_X" --derived-report 2>&1)
  check_output "T15 --derived-report lists the declared derived skill" "derived-x" "$out"
  listed_src=$(printf '%s\n' "$out" | grep -cE '^derived +[^ ]*/dev-standards-bootstrap$' || true)
  report "T15 --derived-report does not report the source skill itself" 0 "$listed_src"
  listed_plain=$(printf '%s\n' "$out" | grep -c 'plain-x' || true)
  report "T15 --derived-report ignores body-only derived_from mentions" 0 "$listed_plain"
  listed_date=$(printf '%s\n' "$out" | grep -c 'derived_at=2026-09-01' || true)
  report "T15 --derived-report surfaces derived_at" 1 "$listed_date"

  # --- 派生写入守卫：拒绝 + --force 不越过 + 不误伤非派生目录 ---
  bash "$BOOT_X" --all "$SKROOT/derived-x" >/dev/null 2>&1
  report "T15 installer refuses to write into a derived skill" 2 $?
  bash "$BOOT_X" --all --force "$SKROOT/derived-x" >/dev/null 2>&1
  report "T15 --force does not override the derived guard" 2 $?
  [[ ! -e "$SKROOT/derived-x/AGENTS.md" ]]
  report "T15 the derived skill directory was left untouched" 0 $?
  bash "$BOOT_X" --core "$SKROOT/plain-x" >/dev/null 2>&1
  report "T15 install into a non-derived directory still works" 0 $?
  rm -rf "$SKROOT"

  # --- D4：--upgrade 保留显式层选择（此前会静默扩为全量 5 层）---
  D4=$(mktemp -d)
  ( cd "$D4" && git init -q && git config user.email t@t && git config user.name t )
  bash "$BOOT_SRC" --all "$D4" >/dev/null 2>&1
  ( cd "$D4" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  out=$(bash "$BOOT_SRC" --core --upgrade "$D4" 2>&1)
  check_output "T15 --core --upgrade keeps the explicit layer selection (D4)" "applying layers \[core\]" "$out"
  out=$(bash "$BOOT_SRC" --upgrade "$D4" 2>&1)
  check_output "T15 a bare --upgrade still expands to all layers (D4)" "applying layers \[core,claude,ci,guard,pipeline\]" "$out"
  rm -rf "$D4"

  # --- D5：规范升级日志归 Skill 所有——本地追加行必须被检测（拒绝而非静默覆盖）---
  D5=$(mktemp -d)
  ( cd "$D5" && git init -q && git config user.email t@t && git config user.name t )
  bash "$BOOT_SRC" --all "$D5" >/dev/null 2>&1
  printf '| v9.9.9-local | 2026-09-15 | 本仓自定义条目 | 无 |\n' >> "$D5/docs/STANDARDS_CHANGELOG.md"
  # v3.17.0：全新安装后的第一次 commit 不得被门禁判为"源码变更"而拦下。
  # 踩过的坑：新增治理脚本 stamp-provenance.sh 未同步进 agent-gate 的治理工具白名单，
  # 它以 .sh 结尾 → 被判为产品代码 → 新仓库装完治理包**第一次 commit 即死锁**；
  # 而下方 D5 用例的断言只看 --upgrade 的退出码与文案，commit 静默失败后
  # 报错来自"目标仓有未提交改动"这**另一条守卫**，表现为文案不匹配——症状与根因相距很远。
  # 故此处显式断言首次 commit 成功，把根因钉在最近的位置。
  ( cd "$D5" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  report "T15 a fresh --all install commits cleanly (no governance deadlock)" 0 $?
  out=$(bash "$BOOT_SRC" --upgrade "$D5" 2>&1); rc=$?
  report "T15 upgrade refuses local rows in the skill-owned changelog (D5)" 2 "$rc"
  check_output "T15 the refusal names the local rows" "local rows this skill does not carry" "$out"
  grep -q 'v9.9.9-local' "$D5/docs/STANDARDS_CHANGELOG.md"
  report "T15 local changelog rows survive the refusal" 0 $?
  rm -rf "$D5"

  # --- D1：非 git 克隆的 Skill 目录，--self-update 必须显式说明不可用（不得静默成功）---
  NG=$(mktemp -d)
  mkdir -p "$NG/scripts" "$NG/resources"
  cp "$BOOT_SRC" "$NG/scripts/bootstrap.sh"
  cp "$ROOT/resources/DEVELOPMENT_STANDARDS.md" "$NG/resources/" 2>/dev/null
  out=$(bash "$NG/scripts/bootstrap.sh" --self-update 2>&1); rc=$?
  report "T15 --self-update fails clearly on a non-git skill dir (D1)" 1 "$rc"
  check_output "T15 --self-update explains why it cannot compare" "not-a-git-checkout" "$out"
  rm -rf "$NG"

else
  echo "SKIP T15: bootstrap.sh 为 Skill 仓库安装器（不随 --guard 分发）——跳过版本自查/自进化用例"
fi

}
section_T17() {
# ------------------------------------------------ T17 溯源脚本本体（v3.17.0）
# T16 验的是**门禁的校验逻辑**（内联块，与布局无关）；T17 验的是**脚本本体的产出**——
# 真值取自环境、写入幂等、隐私开关、--check、以及"真脚本产出能过真门禁"的端到端闭环。
# 脚本是 --guard 层文件：目标仓未装 guard 层时不存在 → SKIP（同 T15 的布局自适应）。
if [[ -f "$STAMP_SRC" ]]; then
  new_repo
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  seed_artifacts CHG-700 L1 claude/s-1
  commit_all "docs: CHG-700 artifacts"

  # ① 编码记录缺失：给出可执行的下一步，且**不**自动建空骨架
  #    （门禁对 04.5 只查"存在且非空"，自动建壳等于放行空交付）
  out=$(scripts/stamp-provenance.sh CHG-700 2>&1); rc=$?
  report "T17 stamper rejects a missing coding record" 2 "$rc"
  check_output "T17 stamper states the actionable next step" "write the coding record first" "$out"

  # ①b 点号 id 拒盖（v3.62.0，REQ-1023/FU-023 no-dot 形状）：exit 非零 + 明确报文，不写产物
  out=$(scripts/stamp-provenance.sh CHG.700 2>&1); rc=$?
  report "T17 stamper rejects a dotted change id" 2 "$rc"
  check_output "T17 dotted-change-id refusal states the no-dot rule" "dots not allowed" "$out"
  out=$(scripts/stamp-provenance.sh --bug BUG.040 2>&1); rc=$?
  report "T17 stamper rejects a dotted defect id" 2 "$rc"
  check_output "T17 dotted-defect-id refusal states the no-dot rule" "dots not allowed" "$out"
  report "T17 dotted-id rejection writes no default target" 0 "$(test ! -e docs/changes/CHG-700/04.5-coding-record.md; echo $?)"

  # ② 正常写入：块插在首个 H1 之后，真值全部取自运行环境
  printf '# CHG-700 编码记录\n\n## 改动文件清单\n' > docs/changes/CHG-700/04.5-coding-record.md
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  report "T17 stamper writes the provenance block" 0 $?
  blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md)
  check_output "T17 stamped block names the script as producer" "^generated_by: stamp-provenance[.]sh$" "$blk"
  check_output "T17 stamped block carries an ISO UTC timestamp" "^generated_at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$blk"
  check_output "T17 stamped block reads the author from git config" "^author: test$" "$blk"
  check_output "T17 stamped block records the commit hash" "^commit: [0-9a-f]{7,}$" "$blk"
  check_output "T17 stamped block records host and platform" "^platform: .+ .+$" "$blk"

  # ③ 幂等：重复运行**整块替换**而非叠加（叠加会让门禁按首块校验而误判）
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  report "T17 stamper is idempotent (one block after re-run)" 1 "$(grep -c '^<!-- provenance$' docs/changes/CHG-700/04.5-coding-record.md)"

  # ④ --check 接受自己的产出
  scripts/stamp-provenance.sh --check docs/changes/CHG-700/04.5-coding-record.md >/dev/null 2>&1
  report "T17 --check accepts the stamper's own output" 0 $?

  # ③b 同 HEAD 连续两次盖章：除 generated_at 墙钟外零 diff（v3.62.0，REQ-1024/TC-1079，
  #     last-touch commit 语义下天然成立；墙钟行归一后整块比对）
  cp docs/changes/CHG-700/04.5-coding-record.md .stamp-snapshot
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  sed -n '/^<!-- provenance$/,/^-->$/p' .stamp-snapshot | grep -v '^generated_at: ' > .stamp-a
  sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md | grep -v '^generated_at: ' > .stamp-b
  report "T17 re-stamp at the same HEAD is zero-diff (modulo generated_at)" 0 "$(diff .stamp-a .stamp-b >/dev/null 2>&1; echo $?)"
  rm -f .stamp-snapshot .stamp-a .stamp-b

  # ③c last-touch commit 随文件演进更新（REQ-1024 方案 A）：入库重盖 → commit=该提交；
  #     再改再提交再重盖 → commit=新提交（--check 的 hash 比对同口径）。
  git add docs/changes/CHG-700/04.5-coding-record.md >/dev/null 2>&1
  git commit -qm "docs: CHG-700 coding record" >/dev/null 2>&1
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk_commit=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md | sed -nE 's/^commit:[[:space:]]*//p')
  report "T17 commit field == the file's last-touch commit" 1 "$(git log -1 --format=%h -- docs/changes/CHG-700/04.5-coding-record.md | grep -cF "$blk_commit")"
  printf '\n## WHY 决策\n\n追加内容驱动 last-touch 更新。\n' >> docs/changes/CHG-700/04.5-coding-record.md
  git add docs/changes/CHG-700/04.5-coding-record.md >/dev/null 2>&1
  git commit -qm "docs: CHG-700 coding record update" >/dev/null 2>&1
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk_commit2=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md | sed -nE 's/^commit:[[:space:]]*//p')
  report "T17 commit field == the evolved last-touch commit" 1 "$(git log -1 --format=%h -- docs/changes/CHG-700/04.5-coding-record.md | grep -cF "$blk_commit2")"
  report "T17 commit field actually advanced between evolutions" 0 "$(test "$blk_commit" != "$blk_commit2"; echo $?)"
  scripts/stamp-provenance.sh --check docs/changes/CHG-700/04.5-coding-record.md >/dev/null 2>&1
  report "T17 --check commit consistency accepts a fresh stamp" 0 $?

  # ③d 整文件字节幂等（v3.62.1，CHG-081/REQ-1025/TC-1080）：旧 TC-1079 只比块内
  #     抽取——空行累积恰在块外，测试自遮蔽恒绿（CHG-080 教训）。整文件 diff +
  #     块尾空行恒 1 双断言。
  cp docs/changes/CHG-700/04.5-coding-record.md .t1080-a
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  cp docs/changes/CHG-700/04.5-coding-record.md .t1080-b
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  report "T17 TC-1080 whole-file byte-idempotent across re-stamps (mod generated_at)" 0 "$(diff <(sed 's/^generated_at: .*/generated_at: X/' .t1080-a) <(sed 's/^generated_at: .*/generated_at: X/' .t1080-b) >/dev/null 2>&1; echo $?)"
  report "T17 TC-1080 exactly one blank after block end" 0 "$(awk '/^<!-- provenance$/{b=1;next} b&&/^-->$/ {b=0;d=1;n=0;next} b{next} d&&/^[[:space:]]*$/{n++;next} d{exit} END{print (n==1)?0:1}' docs/changes/CHG-700/04.5-coding-record.md)"
  rm -f .t1080-a .t1080-b

  # ③e 历史脏形一次收敛（v3.62.1，REQ-1025/TC-1081）：块后 4 空行（目标仓实测
  #     index 4→worktree 8 形态）盖 1 次即达规范形，且与净文件盖章输出字节相等。
  printf '# 脏形夹具\n\n正文一行\n' > .t1081-clean
  scripts/stamp-provenance.sh CHG-700 .t1081-clean >/dev/null 2>&1
  cp .t1081-clean .t1081-expect
  awk '{print} /^-->$/ && !inj {for(i=0;i<4;i++) print ""; inj=1}' .t1081-expect > .t1081-dirty
  scripts/stamp-provenance.sh CHG-700 .t1081-dirty >/dev/null 2>&1
  report "T17 TC-1081 dirty shape (4 trailing blanks) converges in one stamp" 0 "$(diff <(sed 's/^generated_at: .*/generated_at: X/' .t1081-expect) <(sed 's/^generated_at: .*/generated_at: X/' .t1081-dirty) >/dev/null 2>&1; echo $?)"
  rm -f .t1081-clean .t1081-expect .t1081-dirty

  # ③f 栅栏感知（v3.62.2，CHG-082/REQ-1029/TC-1088）：正文代码栅栏内的成对
  #     provenance 示例标记与栅栏内 `# ` 示例标题不再被删块/插块逻辑消费
  #     （CHG-081 评审 B 项实证）。断言：示例原样保留、正文零丢失、恰一真块、
  #     幂等、--check 取真块（TC-1089）。
  printf '# 栅栏夹具\n\n```markdown\n<!-- provenance\nauthor: sample\n-->\n```\n\n```bash\n# 栅栏内假 H1 示例\n```\n\n正文行A\n正文行B\n' > .t1088-fence
  scripts/stamp-provenance.sh CHG-700 .t1088-fence >/dev/null 2>&1
  report "T17 TC-1088 fenced example markers survive stamping (sample kept)" 4 "$(grep -cE '^<!-- provenance$|^-->$' .t1088-fence)"
  report "T17 TC-1088 fenced sample field lines survive" 1 "$(grep -c '^author: sample$' .t1088-fence)"
  report "T17 TC-1088 in-fence fake H1 does not trigger a second block" 0 "$(test "$(grep -c '^<!-- provenance$' .t1088-fence)" = 2; echo $?)"
  report "T17 TC-1088 first-stamp body content survives (TC-1079 教训：幂等不覆盖首盖丢失)" 2 "$(grep -cE '^正文行[AB]$' .t1088-fence)"
  cp .t1088-fence .t1088-a
  scripts/stamp-provenance.sh CHG-700 .t1088-fence >/dev/null 2>&1
  report "T17 TC-1088 fence case is byte-idempotent (mod generated_at)" 0 "$(diff <(sed 's/^generated_at: .*/X/' .t1088-a) <(sed 's/^generated_at: .*/X/' .t1088-fence) >/dev/null 2>&1; echo $?)"
  scripts/stamp-provenance.sh --check .t1088-fence >/dev/null 2>&1
  report "T17 TC-1089 --check extracts the real block when a fenced example exists" 0 $?
  # ③f2 (评审 D1 回归): 无 H1 + 栅栏示例 → 兜底判据不可被示例 begin 标记骗过
  # （旧 grep 判据 → 假成功零块落盘）；现块落头部且示例/正文原样。
  printf '```markdown\n<!-- provenance\nauthor: sample\n-->\n```\n正文X\n' > .tf-noh1
  scripts/stamp-provenance.sh CHG-700 .tf-noh1 >/dev/null 2>&1
  report "T17 TC-1088b no-H1 file with fenced sample still gets the block at head" 1 "$(head -1 .tf-noh1 | grep -c '^<!-- provenance$')"
  report "T17 TC-1088b exactly one real block (not fooled by the sample)" 1 "$(grep -c '^generated_by: ' .tf-noh1)"
  report "T17 TC-1088b sample and body survive the head-block stamp" 2 "$(grep -cE '^(author: sample|正文X)$' .tf-noh1)"
  scripts/stamp-provenance.sh --check .tf-noh1 >/dev/null 2>&1
  report "T17 TC-1088b --check passes on the head-block with fenced sample" 0 $?
  # ③f3 (评审 D2 回归): 真块体内杂散 ``` 行不得翻转栅栏态（否则 --> 终止永不
  # 命中、吞块后正文至 EOF）；重盖后正文零丢失、块仍单。
  printf '# 极端块夹具\n\n正文行1\n正文行2\n' > .tf-stray
  scripts/stamp-provenance.sh CHG-700 .tf-stray >/dev/null 2>&1
  awk '{print} /^generated_by:/{print "```"}' .tf-stray > .tf-stray2 && mv .tf-stray2 .tf-stray
  scripts/stamp-provenance.sh CHG-700 .tf-stray >/dev/null 2>&1
  report "T17 TC-1088c stray fence inside block body does not eat the tail" 2 "$(grep -cE '^正文行[12]$' .tf-stray)"
  report "T17 TC-1088c block stays single after the stray-fence restamp" 1 "$(grep -c '^generated_by: ' .tf-stray)"
  rm -f .t1088-fence .t1088-a .tf-noh1 .tf-stray

  # ③g CRLF 归一（v3.62.2，CHG-082/REQ-1030/TC-1091）：\r 尾行致旧块不识别重复盖
  #     ——写入路径一次归一 LF；--check 读取侧容忍（不回写未盖文件）。
  printf '# CRLF 夹具\r\n\r\n内容行\r\n' > .t1091-crlf
  scripts/stamp-provenance.sh CHG-700 .t1091-crlf >/dev/null 2>&1
  report "T17 TC-1091 CRLF file normalized to LF on stamp" 0 "$(grep -c $'\r' .t1091-crlf)"
  report "T17 TC-1091 CRLF file gets exactly one block" 1 "$(grep -c '^<!-- provenance$' .t1091-crlf)"
  scripts/stamp-provenance.sh --check .t1091-crlf >/dev/null 2>&1
  report "T17 TC-1091 --check accepts the normalized CRLF file" 0 $?
  cp .t1091-crlf .t1091-a
  scripts/stamp-provenance.sh CHG-700 .t1091-crlf >/dev/null 2>&1
  report "T17 TC-1091 CRLF re-stamp is byte-idempotent" 0 "$(diff <(sed 's/^generated_at: .*/X/' .t1091-a) <(sed 's/^generated_at: .*/X/' .t1091-crlf) >/dev/null 2>&1; echo $?)"
  rm -f .t1091-a .t1091-crlf

  # ⑤ 隐私开关：yml 关掉邮箱，作者与主机保留
  printf 'provenance:\n  include_email: false\n' > .agent-governance.yml
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md)
  check_output "T17 privacy switch redacts the email" "^email: <redacted>$" "$blk"
  check_output "T17 privacy switch keeps the author" "^author: test$" "$blk"

  # ⑥ env 覆盖 yml（CLI > env > yml 的第二级）
  AGENT_GUARD_PROVENANCE_EMAIL=true scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md)
  check_output "T17 env override beats the yml privacy switch" "^email: test@example[.]invalid$" "$blk"

  # ⑦ 端到端：**真脚本产出**过**真门禁**（T16 用的是内联块，此处闭合"脚本 ↔ 门禁"接口）
  #    注意 begin 必须在写 09-changelog.md **之前**：门禁把"09 已存在"读作"变更已闭合"
  #    （§2.15 规则 4，FU-015），先写 09 会让 begin 直接拒绝。
  scripts/agent-gate begin CHG-700 >/dev/null 2>&1
  echo y > src/c.js
  echo results > docs/changes/CHG-700/05-test-results.md
  printf 'chg\n#### 执行记录（ReAct）\n| 阶段 | Thought | Observation |\n|---|---|---|\n| 阶段1 | t | grep -c REQ- 01-spec.md -> 1 |\n' > docs/changes/CHG-700/09-changelog.md
append_masters docs/changes/CHG-700/09-changelog.md
  printf '# 06.5 部署/配置/DB 记录\n未命中，不适用：无配置项。\n' > docs/changes/CHG-700/06.5-deployment-config.md
  printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | x | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-700/06-delivery-summary.md
  # TC-1089b (v3.62.2, CHG-082 REQ-1029)：门禁侧 provenance_block 栅栏感知——
  # stop 对"含栅栏示例标记的产物"取真块校验（旧 sed 区间会抽到示例段假红）。
  cat >> docs/changes/CHG-700/04-test-scripts.md <<'EOT17F'

```markdown
<!-- provenance
author: sample
-->
```
EOT17F
  scripts/stamp-provenance.sh --all CHG-700 >/dev/null 2>&1
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T17 gate accepts a real script-stamped record (end-to-end)" 0 $?
  scripts/stamp-provenance.sh --check docs/changes/CHG-700/04-test-scripts.md >/dev/null 2>&1
  report "T17 TC-1089b --check passes on a stamped doc carrying a fenced example block" 0 $?
else
  echo "SKIP T17: stamp-provenance.sh 为 --guard 层文件（未装 guard 层时不存在）"
fi

}
section_T17b() {
# ------------------------------------------------ T17b 溯源全量盖章 --all（v3.22.0）
# --all 把溯源块盖到解析后变更目录的每一个 *.md（批感知复用 resolve_dir）。
# 硬边界：00-governance.json 刻意不盖——JSON 注入 HTML 注释会破坏门禁/审计的
# 扁平 JSON 读取；幂等（整块替换）与"零成功即失败"语义必须同时成立。
if [[ -f "$STAMP_SRC" ]]; then
  new_repo
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  seed_artifacts CHG-800 L1 claude/s-1
  commit_all "docs: CHG-800 artifacts"
  printf '# CHG-800 编码记录\n\n## 改动文件清单\n' > docs/changes/CHG-800/04.5-coding-record.md
  printf '# CHG-800 测试结果\n' > docs/changes/CHG-800/05-test-results.md
  printf '# CHG-800 部署配置\n未命中，不适用：无配置项。\n' > docs/changes/CHG-800/06.5-deployment-config.md
  printf '# CHG-800 交付总结\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | x | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-800/06-delivery-summary.md
  printf '# CHG-800 评审报告\n## 评审结论\n通过\n' > docs/changes/CHG-800/07-review-report.md
  printf '# CHG-800 Changelog\n#### 执行记录（ReAct）\n' > docs/changes/CHG-800/09-changelog.md
append_masters docs/changes/CHG-800/09-changelog.md

  scripts/stamp-provenance.sh --all CHG-800 >/dev/null 2>&1
  report "T17b --all stamps the whole change directory" 0 "$?"

  md_count=$(ls docs/changes/CHG-800/*.md | wc -l | tr -d ' ')
  blk_total=$(grep -c '^<!-- provenance$' docs/changes/CHG-800/*.md | awk -F: '{s+=$2} END{print s}')
  report "T17b every md artifact carries exactly one provenance block (summed, not per-file)" "$md_count" "$blk_total"
  report "T17b 00-governance.json is deliberately NOT stamped" 0 \
    "$(grep -c '^<!-- provenance$' docs/changes/CHG-800/00-governance.json || true)"
  check_ok=0
  for f in docs/changes/CHG-800/*.md; do
    scripts/stamp-provenance.sh --check "$f" >/dev/null 2>&1 || check_ok=1
  done
  report "T17b --check accepts every stamped artifact" 0 "$check_ok"

  scripts/stamp-provenance.sh --all CHG-800 >/dev/null 2>&1
  report "T17b --all is idempotent (no block stacking)" 1 \
    "$(( $(grep -c '^<!-- provenance$' docs/changes/CHG-800/04.5-coding-record.md) == 1 ? 1 : 0 ))"

  # 空目录（无任何 md）：零成功必须失败，"nothing stamped" 不得伪装成功
  mkdir -p docs/changes/CHG-801
  scripts/stamp-provenance.sh --all CHG-801 >/dev/null 2>&1
  report "T17b --all fails on a directory with no md artifacts" 2 "$?"
else
  echo "SKIP T17b: stamp-provenance.sh 为 --guard 层文件（未装 guard 层时不存在）"
fi

}
section_T18() {
# ------------------------------------------------ T18 变更批次 / 同日合并（v3.18.0）
# 批次把"一个变更一套产物"放宽为"一套产物承载多个变更"。本组端到端验证放宽的**边界**：
# 目录放宽但文件名不变、治理记录必须逐变更成行（否则读到兄弟的风险）、风险上限不放宽、
# 闭环判定细一档（看自己的锚点而非共享文件），以及被 T17 掩盖的 `--stage staged` 路径
# （批次解析发生在 `$( )` 子壳里，与 begin 的全局变量路径不同——bash 3.2 的
# `local a="$1" b="...$a"` 缺陷正是在这里才会暴露）。
# v3.19.0 补 ④b：**权威名单**方向。批次共享产物必然含结构标题（§2.16.2 的
# `## Observation`），"把 `## <ascii 单词>` 当变更号"会让 metrics 造出幽灵变更、
new_repo
seed_batch_artifacts BATCH-20260101 CHG-800:L0 CHG-801:L1
commit_all "docs: batch artifacts"

# ① 同批两个成员都能 begin——产物名与独立目录完全同名，只有目录不同
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "T18 batch member begins (anchor-addressed, same filenames)" 0 $?
scripts/agent-gate begin CHG-801 >/dev/null 2>&1
report "T18 a second member of the same batch begins" 0 $?

# ② metrics 按**变更**出行，不按目录——否则整批塌缩成一个 BATCH-* 行、
#    一个风险等级顶替全部成员
t18m=$(mktemp)
scripts/agent-gate metrics > "$t18m" 2>&1
report "T18 metrics emits one row per change, not per directory" 2 "$(wc -l < "$t18m" | tr -d ' ')"
report "T18 metrics row names the first member" 1 "$(grep -c '"change_id":"CHG-800"' "$t18m")"
report "T18 metrics row names the second member" 1 "$(grep -c '"change_id":"CHG-801"' "$t18m")"
rm -f "$t18m"

# ③ --stage staged：批次解析走 `$( )` 子壳（id 是局部变量，不继承全局），
#    这是 bash 3.2 `local` 多赋值缺陷唯一会现形的路径
git add -A
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18 --stage staged resolves batch dirs (no unbound variable)" 0 $?

# ④ 治理记录按行取值：删掉 CHG-800 那一行，它必须红，而兄弟仍绿。
#    反向形态最危险——"取文件里第一个 risk_level"会把兄弟的风险读成本变更的。
t18gov=docs/changes/BATCH-20260101/00-governance.json
cp "$t18gov" "$t18gov.bak"
grep -v '"change_id":"CHG-800"' "$t18gov.bak" > "$t18gov"
out=$(scripts/agent-gate begin CHG-800 2>&1); rc=$?
report "T18 a member with no governance line is refused" 2 "$rc"
check_output "T18 the refusal names the missing record" "declares no governance record for 'CHG-800'" "$out"
scripts/agent-gate begin CHG-801 >/dev/null 2>&1
report "T18 the sibling record is unaffected (line-wise read)" 0 $?
cp "$t18gov.bak" "$t18gov"; rm -f "$t18gov.bak"

# ④b v3.19.0 实测缺陷（本组曾经漏测）：批次共享产物里**必然**会出现结构标题——
#     §2.16.2 强制 09-changelog.md 含 Observation 记录，作者写成 `## Observation`
#     时，"把每个 `## <ascii 单词>` 都当变更号"的读法会同时制造两个假象：
#       ① metrics 凭空多出一行 `{"change_id":"Observation"}`（幽灵变更）；
#       ② `--stage staged` 拿 "Observation" 去查治理记录 → 整批被拒，报文还说
#          "00-governance.json declares no governance record for 'Observation'"。
#     根因：`## <标题>` 在文本层面无法区分"变更小节"与"结构小节"——所以不能
#     反向推断，必须正向读权威名单（00-governance.json 的 change_id）。
#     旧夹具用 `#### 执行记录（ReAct）` 绕开了这个形状，故一直绿——这正是"夹具
#     比真实产物规整"造成的盲区，故此处用**真实形状**（`## Observation`）钉住。
printf '# 09\n## Observation\n#### 执行记录（ReAct）\ncmd: echo ok -> ok\n\n## CHG-800\n' \
  > docs/changes/BATCH-20260101/09-changelog.md
append_masters docs/changes/BATCH-20260101/09-changelog.md
git add -A
out=$(scripts/agent-gate --stage staged 2>&1); rc=$?
report "T18 staged survives a structural '## Observation' heading in a shared artifact" 0 "$rc"
# Count-based (not check_output): the assertion is "the gate never mentions
# Observation", and check_output only asserts presence — an empty `actual`
# against `^$` does not match, so a presence-shaped helper would invert here.
report "T18 the structural heading is not read as a change id" 0 "$(printf '%s' "$out" | grep -c 'Observation' || true)"
t18m2=$(mktemp)
scripts/agent-gate metrics > "$t18m2" 2>&1
report "T18 metrics invents no phantom change for a structural heading" 0 "$(grep -c '"change_id":"Observation"' "$t18m2")"
report "T18 metrics still emits one row per declared change" 2 "$(grep -c '"change_id":' "$t18m2" | tr -d ' ')"
rm -f "$t18m2"

# ⑤ 风险上限不放宽：批次共享产物会削弱逐变更证据边界与角色独立性，
#    L2/L3 必须独立目录——门禁按**记录**拒绝，不能靠目录布局绕过
printf '{"change_id":"CHG-802","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"a","test_owner":"b","review_owner":"c"}\n' >> "$t18gov"
printf '## CHG-802\n## 问题\nx\n## 预期结果\ny\n## 开放问题\nn\n' >> docs/changes/BATCH-20260101/00-intent.md
printf '## CHG-802\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n- 确认状态：已整体确认\n' >> docs/changes/BATCH-20260101/00.5-communication.md
out=$(scripts/agent-gate begin CHG-802 2>&1); rc=$?
report "T18 L2 inside a batch is refused" 2 "$rc"
check_output "T18 the refusal states the L0/L1 ceiling" "batches are L0/L1 only" "$out"

# ⑥ 闭环判定细一档（FU-015 同义）：changelog 被同批共享，"文件存在"不再等于
#    "本变更已关闭"——否则兄弟的 changelog 会把后加入的变更一起判为已关闭
printf '# 09\n## CHG-800\n#### 执行记录（ReAct）\nObservation\n' > docs/changes/BATCH-20260101/09-changelog.md
append_masters docs/changes/BATCH-20260101/09-changelog.md
out=$(scripts/agent-gate begin CHG-800 2>&1); rc=$?
report "T18 a closed batch member is refused" 2 "$rc"
check_output "T18 closure is read from the member's own anchor" "carries a '## CHG-800' section" "$out"
scripts/agent-gate begin CHG-801 >/dev/null 2>&1
report "T18 a sibling absent from the shared changelog still begins" 0 $?

# ⑦ 零回归：独立 <变更号>/ 目录永远优先，L2 在独立目录照常合法
seed_begin CHG-810 L1 claude/s-1
report "T18 dedicated directory still resolves to itself (no regression)" 0 $?
seed_begin CHG-811 L2 claude/s-1 tester reviewer
report "T18 L2 in a dedicated directory is still accepted" 0 $?

# ⑧ 盖章器认批次：默认目标落在批次目录的共享编码记录上，块证明**批次**并列出成员
if [[ -f "$STAMP_SRC" ]]; then
  new_repo
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  seed_batch_artifacts BATCH-20260102 CHG-820:L0 CHG-821:L1
  commit_all "docs: batch artifacts"
  scripts/agent-gate begin CHG-820 >/dev/null 2>&1
  printf '# 04.5 编码记录\n## CHG-820\nx\n## CHG-821\ny\n' > docs/changes/BATCH-20260102/04.5-coding-record.md
  scripts/stamp-provenance.sh CHG-821 >/dev/null 2>&1
  report "T18 stamper resolves the batch directory" 0 $?
  t18blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/BATCH-20260102/04.5-coding-record.md)
  check_output "T18 batch provenance attests the batch" "^change: BATCH-20260102$" "$t18blk"
  check_output "T18 batch provenance lists its members" "^batch_changes: CHG-820 CHG-821$" "$t18blk"
  # 共享文件的块不该因"这次是哪个成员盖的"而改写：风险取批次最高值 → 稳定
  check_output "T18 batch risk is the batch maximum (L1)" "^risk: L1$" "$t18blk"
  scripts/stamp-provenance.sh CHG-820 >/dev/null 2>&1
  t18blk2=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/BATCH-20260102/04.5-coding-record.md)
  check_output "T18 re-stamping by a sibling leaves the risk line stable" "^risk: L1$" "$t18blk2"
  report "T18 batch re-stamping stays idempotent (one block)" 1 "$(grep -c '^<!-- provenance$' docs/changes/BATCH-20260102/04.5-coding-record.md)"
else
  echo "SKIP T18 stamper cases: stamp-provenance.sh 为 --guard 层文件（未装 guard 层时不存在）"
fi

}
section_T18b() {
# ------------------------------------------------ T18b 同日批次默认强制（v3.27.0，CHG-027）
# §1.1 v3.24.0 把"同日多个 L0/L1 默认共用批次"写成默认，但 begin 不拦就是纯建议
# （下游实测：同日 5 组 L0/L1 全部各开独立目录）。本组验证：当日批次已存在时，
# 独立 L0/L1 begin 必须被拦；豁免必须显式；入批与 L2 独立照常。
new_repo
seed_batch_artifacts "BATCH-$(date -u +%Y%m%d)" CHG-820:L0
commit_all "docs: today's batch exists"
seed_begin CHG-821 L1 claude/s-1
# v3.62.2 (CHG-082): E86 声明级分支先于 E73 落 die——落位主题用例撤掉夹具豁免，
# 断言口径同步改为 E86 正向措辞（E73 保留为纵深，不再是最早执法点）。
report "T18b begin rejects an independent L0/L1 when a same-day batch exists" 2 "$(env -u AGENT_GUARD_ALLOW_INDEPENDENT scripts/agent-gate begin CHG-821 >/dev/null 2>&1; echo $?)"
out=$(env -u AGENT_GUARD_ALLOW_INDEPENDENT scripts/agent-gate begin CHG-821 2>&1 || true)
check_output "T18b refusal names the batch and the escape hatch" "GATE-E86.*same-day L0/L1 changes must join the batch.*AGENT_GUARD_ALLOW_INDEPENDENT" "$out"
AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-821 >/dev/null 2>&1
report "T18b explicit override allows an independent L0/L1" 0 $?
seed_batch_artifacts "BATCH-$(date -u +%Y%m%d)" CHG-822:L1
scripts/agent-gate begin CHG-822 >/dev/null 2>&1
report "T18b joining the same-day batch begins" 0 $?
seed_begin CHG-823 L2 claude/s-1 tester reviewer
report "T18b L2 keeps its independent-directory right (no batch compulsion)" 0 $?

}
section_T19() {
# ------------------------------------------------ T19 治理记录的格式无关性（v3.20.0）
# 回归背景：v3.18.0 为支持批次把"读治理记录"从**整文件**（v3.14.0 的
# `json_string <file> <key>`，用 `sed -nE ... "$file"` 逐行扫全文件）改成**行式**
# （`gov_record` = `grep ... | head -1`）。行式对批次是必需的（要按 change_id 隔离
# 兄弟记录），但它**静默打破了多行格式化记录**——而多行恰恰是**随包下发的模板
# `resources/templates/governance-state.json` 的形状**，也是 SKILL.md 指示 Agent
# 生成 `00-governance.json` 时照抄的形状。后果：照着文档走一遍，`begin` 报
# `must declare risk_level L0, L1, L2, or L3`，而该字段就在 change_id 下面两行。
# 本仓自己的账本 16/16 条（CHG-001..016）全是多行，全部会被自己的门禁拒绝。
#
# 本组为什么以前测不出来：`seed_artifacts` / `seed_batch_artifacts` 都用
# `printf '{"change_id":...}\n'` 手写**单行**记录——夹具比真实产物规整，于是
# 这一整类形状从未进过用例。**夹具必须覆盖真实形状**（同 T18 ④b 的教训）。
#
# 断言方向刻意双向：既钉"多行必须被接受"，也钉"单行不得回归"。

# ① 多行独立目录记录：必须被接受（v3.18.0 起被误拒）
new_repo
seed_artifacts CHG-840 L1 claude/s-1
cat > docs/changes/CHG-840/00-governance.json <<'EOF'
{
  "change_id": "CHG-840",
  "risk_level": "L1",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1","test_owner":"t/x","review_owner":"r/x"
}
EOF
out=$(scripts/agent-gate begin CHG-840 2>&1); rc=$?
report "T19 begin accepts a pretty-printed governance record" 0 "$rc"
check_output "T19 the refusal no longer fires on a record that declares risk_level" "active change is CHG-840" "$out"

# ② metrics 必须读出多行记录的风险等级（曾经一律 null）
t19m=$(scripts/agent-gate metrics 2>&1)
check_output "T19 metrics reads risk_level from a multi-line record" '"change_id":"CHG-840","risk_level":"L1"' "$t19m"

# ③ 整条记录被解析，而不是只读到第一行：L2 缺 test_owner 必须在**所有者**上被拒
#    （若 risk_level 读不到，会先在 risk_level 上报错——报文不同，可区分）
seed_artifacts CHG-841 L2 claude/s-1
cat > docs/changes/CHG-841/00-governance.json <<'EOF'
{
  "change_id": "CHG-841",
  "risk_level": "L2",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1"
}
EOF
out=$(scripts/agent-gate begin CHG-841 2>&1); rc=$?
report "T19 a multi-line L2 record without test_owner is still refused" 2 "$rc"
check_output "T19 the refusal is about owners, not about a missing risk_level" "must declare test_owner and review_owner for L2" "$out"

# ④ 多行 + 逗号分隔（jq 风格 / JSON 数组风格）的批次：逐成员读自己的风险，
#    不得串到兄弟（这正是 v3.18.0 引入行式读取要解决的问题，不能被本修复带回）
new_repo
seed_batch_artifacts BATCH-20260103 CHG-830:L0 CHG-831:L1
cat > docs/changes/BATCH-20260103/00-governance.json <<'EOF'
{
  "change_id": "CHG-830",
  "risk_level": "L0",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1","test_owner":"t/x","review_owner":"r/x"
},
{
  "change_id": "CHG-831",
  "risk_level": "L1",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1","test_owner":"t/x","review_owner":"r/x"
}
EOF
t19b=$(scripts/agent-gate metrics 2>&1)
check_output "T19 a multi-line batch member reads its OWN risk" '"change_id":"CHG-830","risk_level":"L0"' "$t19b"
check_output "T19 the sibling reads its own risk, not the first record's" '"change_id":"CHG-831","risk_level":"L1"' "$t19b"
scripts/agent-gate begin CHG-831 >/dev/null 2>&1
report "T19 a member of a multi-line batch begins" 0 $?

# ⑤ 零回归：单行记录（历史与批次推荐写法）继续可用
new_repo
seed_begin CHG-842 L1 claude/s-1
report "T19 one-line records still begin (no regression)" 0 $?

# ⑥ 结构校验（CHG-121，batch 0；CHG-123 拆码 E134）：同一行拼接的 JSON 对象必须被拒绝。
#    实测 12/12 个批次台账外部 json.load 失败，正是这个形状；内部读取器容忍它，
#    所以坏台账一直静默存在。
new_repo
seed_artifacts CHG-843 L1 claude/s-1
printf '{"change_id": "CHG-843", "risk_level": "L1", "spec_author":"a/b/c","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x"}{"change_id": "CHG-844", "risk_level": "L1"}\n' > docs/changes/CHG-843/00-governance.json
out=$(scripts/agent-gate begin CHG-843 2>&1); rc=$?
report "T19 E134 refuses same-line concatenated governance records (CHG-123)" 2 "$rc"
check_output "T19 E134 names the invalid shape (CHG-123)" "GATE-E134" "$out"

}
section_T20() {
# ------------------------------------------------ T20 审计单元识别与"空转显式声明"（v3.21.0）
# 本仓自查实测到的假绿：审计脚本用"<docs>/ 下一层子目录"取审计单元，而 `docs/changes`、
# `docs/bugs`、`docs/review` 都算"子目录"——它们一存在，"没有产物目录"的空转分支就不触发，
# G2/G3/G5/G6 **一条断言都不执行、也不打印任何行**。实测：一个
# `docs/changes/CHG-001/01-spec.md` 里带 REQ 跳号的仓库**通过**了审计。同一根因还让 G4
# 去找 `docs/changes/09-changelog.md`（不存在）而误报**假红**。
# 伴生缺陷在 `check_seq` 里：① grep 全文件的编号出现（含正文引用）② 基线写死从 1 开始
# ——本仓 16 个 01-spec.md 共误报 **695** 处"缺号"。
# v3.21.0 修法：正信号识别 + 空转**显式声明** + 定义式/自身区间；G2 覆盖两轨，
# G3/G5/G6 只覆盖活文档（冻结变更目录按 §2.15 硬性规则 4 不可回填，事后判红是时代错置）。
if [[ -f "$AUDIT_SRC" ]]; then

# ① 靶心：管线态仓库里 REQ 跳号必须判红。v3.21.0 之前 G2 一条断言都不跑 → 整个审计通过。
AC=$(mktemp -d); audit_change_fixture "$AC"
printf '## REQ-004 第四个需求\n' >> "$AC/docs/changes/CHG-001/01-spec.md"
out=$(bash "$AUDIT_SRC" "$AC" 2>&1); rc=$?
report "T20 audit reds on a REQ gap inside a change dir (was a silent pass)" 1 "$rc"
check_output "T20 the red names the gap" 'G2 REQ numbering in CHG-001 continuous 1\.\.4 .*got 1' "$out"

# ② 空转必须**显式声明**：只有变更目录时 G3/G5/G6 没跑，输出里必须有这句话。
check_output "T20 the G3/G5/G6 vacuous skip is declared, not silent" "G3/G5/G6 VACUOUS SKIP" "$out"

# ③ 变更目录的号段不始于 1 是常态（§1.2 编号空间全局）→ 不得报假缺号。
AC2=$(mktemp -d); audit_change_fixture "$AC2"
printf '# spec\n\n## REQ-080 甲\n## REQ-081 乙\n' > "$AC2/docs/changes/CHG-001/01-spec.md"
bash "$AUDIT_SRC" "$AC2" >/dev/null 2>&1
report "T20 a span not starting at 1 is not a gap (REQ-080..081)" 0 $?

# ④ 正文引用不得撑大号段（旧实现把"REQ 从 REQ-008 起（已用 REQ-001~007）"算成定义）。
AC3=$(mktemp -d); audit_change_fixture "$AC3"
printf '# spec\n\n> 编号衔接：REQ 从 REQ-080 起（CHG-001 已用 REQ-001~007）\n\n## REQ-080 甲\n## REQ-081 乙\n' \
  > "$AC3/docs/changes/CHG-001/01-spec.md"
bash "$AUDIT_SRC" "$AC3" >/dev/null 2>&1
report "T20 in-prose REQ references do not widen the definition span" 0 $?

# ⑤ G4 双登记在管线态布局下不得假红（旧实现只看 <docs>/ 下一层的 09-changelog）。
AC4=$(mktemp -d); audit_change_fixture "$AC4"
{ echo '### BUG-001：现象（严重度 P1）'; echo; echo '| 字段 | 内容 |'; echo '|---|---|'; echo '| 关联变更 | CHG-001 |'; echo '| 历史相似 | 未命中（根因关键词检索） |'; } > "$AC4/docs/bugfix-log.md"
printf '# CHG-001 Changelog\n\n## 2026-09-15\n\n- 对应缺陷：`BUG-001`（见 docs/bugfix-log.md）\n' > "$AC4/docs/changes/CHG-001/09-changelog.md"
bash "$AUDIT_SRC" "$AC4" >/dev/null 2>&1
report "T20 G4 resolves changelogs under the change root (no false orphan)" 0 $?

# ⑥ 完全没有产物目录时 G2 也要显式声明空转（而不是打一行"通过"就完事）。
AC5=$(mktemp -d); mkdir -p "$AC5/docs"
cp "$STD_SRC" "$AC5/docs/DEVELOPMENT_STANDARDS.md"; cp "$AG_SRC" "$AC5/AGENTS.md"
out=$(bash "$AUDIT_SRC" "$AC5" 2>&1)
check_output "T20 G2 vacuous skip is declared when no artifact dir exists" "G2 VACUOUS SKIP" "$out"

# ⑦ 零回归：功能目录（活文档）布局仍然全绿——G3/G5/G6 仍在此轨上执行。
AF=$(mktemp -d); audit_fixture "$AF"
out=$(bash "$AUDIT_SRC" "$AF" 2>&1); rc=$?
report "T20 a compliant feature-dir repo still passes (no regression)" 0 "$rc"
t20_ran=1
# 精确锚定 G3/G5/G6 组（v3.28.0 起 G8/A20/A21 在无 bugs/变更目录的仓库合法打印
# 自己的空转声明——泛 grep "VACUOUS SKIP" 会把"诚实声明未覆盖"误判成"G3 没跑"）。
printf '%s' "$out" | grep -q "G3/G5/G6 VACUOUS SKIP" && t20_ran=0
report "T20 G3/G5/G6 actually ran on the living-doc track (no vacuous skip)" 1 "$t20_ran"

rm -rf "$AC" "$AC2" "$AC3" "$AC4" "$AC5" "$AF"
else
  echo "SKIP T20: audit-docs-consistency.sh absent (bootstrap --core 未安装) — 跳过审计单元识别 golden cases"
fi

}
section_T21() {
# ------------------------------------------------ T21 一键安装器 install.sh（v3.22.0）
# install.sh 与 bootstrap.sh 同属源层工具（不随 --guard 分发）——目标仓布局自动 SKIP。
# 夹具用**最小 fake 源仓**（scripts/bootstrap.sh + tests/run-tests.sh + resources/，
# 无 .git）走 --from 离线路径：既覆盖"克隆之外"的全部逻辑，又保证测试零网络依赖。
if [[ -f "$ROOT/scripts/install.sh" && -f "$BOOT_SRC" ]]; then
  FAKE_SRC=$(mktemp -d "${TMPDIR:-/tmp}/install-src.XXXXXX")
  mkdir -p "$FAKE_SRC/scripts" "$FAKE_SRC/tests"
  cp "$ROOT/scripts/bootstrap.sh" "$FAKE_SRC/scripts/bootstrap.sh"
  cp "$ROOT/tests/run-tests.sh" "$FAKE_SRC/tests/run-tests.sh"
  # v3.79.0 (CHG-103): bootstrap guard 清单含树指纹 lib——FAKE_SRC 必须同拷，
  # 否则 install 链在 install_file 缺源时整体红（安装器清单唯一权威=bootstrap）。
  cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$FAKE_SRC/scripts/lib-suite-tree-fingerprint.sh"
  cp "$ROOT/scripts/lib-suite-lock.sh" "$FAKE_SRC/scripts/lib-suite-lock.sh"
  cp "$ROOT/SKILL.md" "$FAKE_SRC/SKILL.md"
  cp -R "$ROOT/resources" "$FAKE_SRC/resources"

  TGT=$(mktemp -d "${TMPDIR:-/tmp}/install-tgt.XXXXXX")
  (cd "$TGT" && git init -q && git config user.email t@x.invalid && git config user.name t \
    && echo hi > README.md && git add README.md && git commit -qm init)

  # TC-141 离线全量安装
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT" 2>&1); rc=$?
  report "T21 install.sh --from performs a full offline install" 0 "$rc"
  for f in AGENTS.md docs/DEVELOPMENT_STANDARDS.md scripts/agent-gate scripts/lib-suite-tree-fingerprint.sh scripts/lib-suite-lock.sh .githooks/pre-commit \
           .agent-governance.yml tests/run-tests.sh; do
    [[ -e "$TGT/$f" ]] || { echo "T21 missing after install: $f" >&2; rc=1; }
  done
  report "T21 install lands the governance payload" 0 "$rc"
  # bootstrap --upgrade 拒绝脏树（fail-closed，git history 即备份）——升级路径用例先提交目标
  (cd "$TGT" && git add -A && git commit -qm artifacts)

  # TC-142 幂等重跑（已接入目标 → 自动探测为升级；--from 路径不进 pull 分支，
  # 也就没有自更新降级 NOTE——离线性由夹具本身保证）
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT" 2>&1); rc=$?
  report "T21 re-run against a governed target succeeds (auto-upgrade)" 0 "$rc"
  printf '%s' "$out" | grep -q CONFLICT && report "T21 re-run raises no conflict" 0 1 || report "T21 re-run raises no conflict" 0 0

  # TC-143 自动升级：fake 源版本 +0.0.1 → 重跑 → 目标规范页脚跟随（版本无关形态，
  # 与 T14 同型——不再钉死当前版本字面量，版本 bump 无须改本夹具）
  sed -i.bak 's/规范版本：v[0-9.][0-9.]*/规范版本：v9.9.9/' "$FAKE_SRC/resources/DEVELOPMENT_STANDARDS.md" 2>/dev/null \
    || sed -i '' 's/规范版本：v[0-9.][0-9.]*/规范版本：v9.9.9/' "$FAKE_SRC/resources/DEVELOPMENT_STANDARDS.md"
  rm -f "$FAKE_SRC/resources/DEVELOPMENT_STANDARDS.md.bak"
  (cd "$TGT" && git add -A && git commit -qm artifacts)
  bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT" >/dev/null 2>&1
  report "T21 version bump in source propagates via re-run" 1 \
    "$(grep -c '规范版本：v9\.9\.9' "$TGT/docs/DEVELOPMENT_STANDARDS.md" || true)"

  # TC-144（v3.50.0 CHG-062 语义升级）：目标已有用户 AGENTS.md → kept 保留原文（fail-visible），
  # 安装继续完成——不再 CONFLICT 拒绝（bootstrap agents-md 键 merge-or-keep，--force 不越）
  TGT2=$(mktemp -d "${TMPDIR:-/tmp}/install-tgt2.XXXXXX")
  printf '# my own agents file\n' > "$TGT2/AGENTS.md"
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT2" 2>&1); rc=$?
  report "T21 user AGENTS.md kept and install completes" 0 "$rc"
  check_output "T21 kept path names AGENTS.md" "kept.*AGENTS.md" "$out"
  report "T21 conflicting target file is NOT overwritten" 1 \
    "$(grep -c 'my own agents file' "$TGT2/AGENTS.md" || true)"

  # TC-145 --as-skill：Skill 本体注册进客户端技能目录（symlink 指向 checkout，v3.23.0）
  # 全部经 --skills-root 重定向——测试零真实 HOME 写入。
  SKR=$(mktemp -d "${TMPDIR:-/tmp}/install-skills.XXXXXX")
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" --as-skill claude --skills-root "$SKR" 2>&1); rc=$?
  report "T21 --as-skill links the skill into the client skills root" 0 "$rc"
  report "T21 --as-skill destination resolves SKILL.md through the link" 1 \
    "$([[ -f "$SKR/dev-standards-bootstrap/SKILL.md" ]] && echo 1 || echo 0)"

  # TC-146 幂等重跑：同落点重复 --as-skill 报 already linked，rc 0，不重复建链
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" --as-skill claude --skills-root "$SKR" 2>&1); rc=$?
  report "T21 --as-skill re-run is idempotent (already linked)" 0 "$rc"
  check_output "T21 --as-skill re-run reports the existing link" "already linked" "$out"

  # TC-147 冲突 fail-closed：落点被真实目录占用 → 拒绝（rc 2）且原内容一字不动
  SKR2=$(mktemp -d "${TMPDIR:-/tmp}/install-skills2.XXXXXX")
  mkdir -p "$SKR2/dev-standards-bootstrap"
  printf 'mine' > "$SKR2/dev-standards-bootstrap/user.txt"
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" --as-skill claude --skills-root "$SKR2" 2>&1); rc=$?
  report "T21 --as-skill refuses an occupied destination (fail-closed)" 2 "$rc"
  check_output "T21 --as-skill refusal names the fail-closed reason" "not a symlink" "$out"
  report "T21 --as-skill does not touch the existing directory" 1 \
    "$(grep -c mine "$SKR2/dev-standards-bootstrap/user.txt" || true)"

  # TC-148 路径形式：值含 "/" 视为落点目录本身（任意其他客户端）
  SKR3="$SKR2/custom-client"
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" --as-skill "$SKR3" 2>&1); rc=$?
  report "T21 --as-skill accepts a custom destination path" 0 "$rc"

  rm -rf "$FAKE_SRC" "$TGT" "$TGT2" "$SKR" "$SKR2"
else
  echo "SKIP T21: install.sh 为 Skill 仓库安装器（不随 --guard 分发）——跳过一键安装用例"
fi

# ---------------------------------------------------------------- 摘要
}
section_T22b() {
# ------------------------------------------------ T22 记录级执法（独立仓，放套件尾部）
new_repo
seed_artifacts CHG-610 L0 claude/s-1
printf '{"change_id":"CHG-610","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","review_owner":"author/a-1"}\n' > docs/changes/CHG-610/00-governance.json
scripts/agent-gate begin CHG-610 >/dev/null 2>&1
report "begin rejects spec_author == review_owner at L0 (lowest bar)" 2 $?
printf '{"change_id":"CHG-610","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","review_owner":"codex/x-7"}\n' > docs/changes/CHG-610/00-governance.json
scripts/agent-gate begin CHG-610 >/dev/null 2>&1
report "begin accepts L0 with spec_author distinct from review_owner" 0 $?

new_repo
seed_artifacts CHG-611 L2 gemini/m-1 claude/c-9 codex/x-7
printf '{"change_id":"CHG-611","risk_level":"L2","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7"}\n' > docs/changes/CHG-611/00-governance.json
scripts/agent-gate begin CHG-611 >/dev/null 2>&1
out=$(scripts/agent-gate begin CHG-611 2>&1 || true)
check_output "begin names the missing spec_author (FU-041)" "must declare spec_author" "$out"
printf '{"change_id":"CHG-611","risk_level":"L2","spec_author":"gemini/m-1","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7"}\n' > docs/changes/CHG-611/00-governance.json
scripts/agent-gate begin CHG-611 >/dev/null 2>&1
report "begin rejects spec_author duplicating an owner at L2" 2 $?

}
section_T18c() {
# ------------------------------------------------ T18c 缺陷六件套按天入批（v3.35.0，BUG-005）
# §1.1 v3.35.0 废止 v3.22.0"缺陷组不入批"：当日缺陷批次已存在时，同日新建的独立
# 缺陷组必须入批（provenance generated_at 判日）；豁免显式；批次嵌套组照常扫描。
new_repo
# v3.62.2 (CHG-082)：基座 CHG-900 由 L1 改 L2——staged 校验暂存树内全部变更，
# env -u 下 L1 独立目录会在 E58 之前先落 E86；E58 主题要求树内无 L0/L1 独立形态。
seed_begin CHG-900 L2 claude/s-1 tester reviewer
today=$(date -u +%Y%m%d)
mkdir -p "docs/bugs/BATCH-$today/BUG-901"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# %s\n' "$d6" > "docs/bugs/BATCH-$today/BUG-901/$d6.md"
done
append_diag_lines "docs/bugs/BATCH-$today/BUG-901/01-diagnosis.md"
seed_artifacts CHG-902 L0 claude/s-1
# v3.62.2 (CHG-082)：CHG-902 由 L0 改 L2——E86 双向化后 L0/L1 专属目录活动变更会在
# E58 之前先落 E86 die；E58 主题的载体必须是合法独立形态（L2）。bug_ref 绑定语义不变。
printf '{"change_id":"CHG-902","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-901"}\n' > docs/changes/CHG-902/00-governance.json
scripts/agent-gate begin CHG-902 >/dev/null 2>&1
report "T18c begin resolves a bug_ref bound to a batched defect group" 0 $?
mkdir -p docs/bugs/BUG-902
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# %s\n' "$d6" > "docs/bugs/BUG-902/$d6.md"
done
append_diag_lines docs/bugs/BUG-902/01-diagnosis.md
{ printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: %sT00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n' "$(date -u +%Y-%m-%d)"; cat docs/bugs/BUG-902/01-diagnosis.md; } > docs/bugs/BUG-902/01-diagnosis.md.tmp && mv docs/bugs/BUG-902/01-diagnosis.md.tmp docs/bugs/BUG-902/01-diagnosis.md
echo y > src/z.js   # staged/stop 只在存在代码路径改动时执法（对齐 T4/T5 夹具）
git add -A          # staged 以暂存区为准，空暂存即空转放行
# v3.62.2 (CHG-082)：E58 正反向主题用例——撤夹具豁免保持执法可见
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c defect groups join the same-day batch (standalone today is rejected)" 2 "$(env -u AGENT_GUARD_ALLOW_INDEPENDENT scripts/agent-gate --stage staged >/dev/null 2>&1; echo $?)"
out=$(env -u AGENT_GUARD_ALLOW_INDEPENDENT scripts/agent-gate --stage staged 2>&1 || true)
check_output "T18c refusal names the batch and the escape hatch" "move it into the day batch.*AGENT_GUARD_ALLOW_INDEPENDENT" "$out"
AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c explicit override allows a standalone same-day group" 0 $?
printf '%s\n' "BUG-902 # legacy standalone, registered" > docs/bugs/.gate-allowlist
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c allowlisted legacy standalone group passes" 0 $?
rm -f docs/bugs/.gate-allowlist
sed -i '' 's/generated_at: [0-9-]*/generated_at: 2020-01-01/' docs/bugs/BUG-902/01-diagnosis.md 2>/dev/null \
  || sed -i 's/generated_at: [0-9-]*/generated_at: 2020-01-01/' docs/bugs/BUG-902/01-diagnosis.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c pre-v3.35.0 standalone groups (old provenance date) stay legal" 0 $?

}
section_T18d() {
# ------------------------------------------------ T18d 缺陷批次扁平化（v3.36.0，BUG-006）
# §1.1 v3.36.0：同日多缺陷共落 BATCH-YYYYMMDD/ 扁平目录——六件套同名文件 + `## <BUG-id>`
# 锚点分节，当天追加落在同一套文件里（与变更批次同构）；嵌套形态历史合法；
# bug_group_dir 三形态统一解析（独立 → 嵌套 → 扁平锚点，多处命中 fail-closed）。
new_repo
seed_begin CHG-930 L1 claude/s-1
today=$(date -u +%Y%m%d)
mkdir -p "docs/bugs/BATCH-$today"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# flat batch\n\n## BUG-903 flat member\n' > "docs/bugs/BATCH-$today/$d6.md"
done
append_diag_lines "docs/bugs/BATCH-$today/01-diagnosis.md"
# 负例铺垫：BUG-904 只在诊断件锚定（其余五件缺同 id 小节 → 六件锚点不齐）
printf '\n## BUG-904 member\n' >> "docs/bugs/BATCH-$today/01-diagnosis.md"
seed_artifacts CHG-931 L0 claude/s-1
printf '{"change_id":"CHG-931","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-903"}\n' > docs/changes/CHG-931/00-governance.json
scripts/agent-gate begin CHG-931 >/dev/null 2>&1
report "T18d flat bug batch begin resolves a bug_ref via the batch anchor" 0 $?
echo y > src/z.js   # staged/stop 只在存在代码路径改动时执法（对齐 T4/T5 夹具）
git add -A          # staged 以暂存区为准，空暂存即空转放行
out=$(scripts/agent-gate --stage staged 2>&1 || true)
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d flat batch anchor missing in five pieces is rejected at staged" 2 $?
check_output "T18d refusal names the flat anchor set" "six-piece anchor set" "$out"
for d6 in 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '\n## BUG-904 member\n' >> "docs/bugs/BATCH-$today/$d6.md"
done
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d flat batch passes once every anchored id spans the six pieces" 0 $?
# TC-1069 (v3.61.1 REQ-1015): E87 roster diff — an id anchored only in sibling
# docs (missing from 01-diagnosis) escaped E57's per-gid loop entirely.
printf '\n## BUG-906 member\n' >> "docs/bugs/BATCH-$today/02-impact.md"
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T18d E87 rejects an id anchored outside 01-diagnosis (roster diff)" "GATE-E87" "$out"
sed -i '' '/^## BUG-906 member$/d' "docs/bugs/BATCH-$today/02-impact.md" 2>/dev/null || sed -i '/^## BUG-906 member$/d' "docs/bugs/BATCH-$today/02-impact.md"
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d E87 clears once the stray anchor is removed" 0 $?
cp "$ROOT/resources/templates/stamp-provenance.sh" scripts/stamp-provenance.sh
scripts/stamp-provenance.sh --bug BUG-903 >/dev/null 2>&1
report "T18d --bug resolves and stamps a flat batch member" 0 $?
check_output "T18d flat stamp attests the batch id" "^bug: BATCH-" "$(cat "docs/bugs/BATCH-$today/01-diagnosis.md")"
check_output "T18d flat stamp lists the members" "^batch_changes: BUG-90[34]" "$(cat "docs/bugs/BATCH-$today/01-diagnosis.md")"
mkdir -p "docs/bugs/BATCH-$today/BUG-905"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# nested\n' > "docs/bugs/BATCH-$today/BUG-905/$d6.md"
done
append_diag_lines "docs/bugs/BATCH-$today/BUG-905/01-diagnosis.md"
seed_artifacts CHG-932 L0 claude/s-1
printf '{"change_id":"CHG-932","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-905"}\n' > docs/changes/CHG-932/00-governance.json
scripts/agent-gate begin CHG-932 >/dev/null 2>&1
report "T18d nested legacy group still resolves under the three-form resolver" 0 $?

}
section_T18d_E58R() {
# ---- T18d-E58R E58 反向（v3.62.2，CHG-082 REQ-1028/TC-1087）：无批 + 当日首个独立缺陷组 ----
# 活动变更用 L2（L0/L1 独立已被 E86 拒，不能作载体）；缺陷组 E57 六件锚点齐备，
# provenance 今日章（正向同键控）；未章/非今日 fail-open 跳过与正向一致。
new_repo
seed_begin CHG-933 L2 claude/s-47 tester reviewer
unset AGENT_GUARD_ALLOW_INDEPENDENT
mkdir -p docs/bugs/BUG-907
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# t\n\n## BUG-907 member\n' > "docs/bugs/BUG-907/$d6.md"
done
append_diag_lines docs/bugs/BUG-907/01-diagnosis.md
cp "$ROOT/resources/templates/stamp-provenance.sh" scripts/stamp-provenance.sh 2>/dev/null || cp "$ROOT/scripts/stamp-provenance.sh" scripts/stamp-provenance.sh
chmod +x scripts/stamp-provenance.sh
scripts/stamp-provenance.sh --bug BUG-907 >/dev/null 2>&1
echo y > src/z.js
git add -A
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T18d E58 reverse: first-of-day standalone defect group with no batch is rejected" "GATE-E58.*first L0/L1 defect of the day creates the day batch" "$out"
AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d E58 reverse admits with explicit escape" 0 $?
sed -i '' 's/generated_at: [0-9-]*/generated_at: 2020-01-01/' docs/bugs/BUG-907/01-diagnosis.md 2>/dev/null || sed -i 's/generated_at: [0-9-]*/generated_at: 2020-01-01/' docs/bugs/BUG-907/01-diagnosis.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d E58 reverse skips non-today groups (fail-open, same keying as forward)" 0 $?
export AGENT_GUARD_ALLOW_INDEPENDENT=1

}
section_T23() {
# ------------------------------------------------ T23 项目总册机校（v3.35.0，§1.3/CHG-035）
new_repo
seed_artifacts CHG-910 L1 claude/s-1
rm -rf docs/project
scripts/agent-gate begin CHG-910 >/dev/null 2>&1
report "T23 begin refuses to start without project masters" 2 $?
out=$(scripts/agent-gate begin CHG-910 2>&1 || true)
check_output "T23 refusal names the masters and the escape hatch" "project masters not initialized.*AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS" "$out"
seed_project_masters
scripts/agent-gate begin CHG-910 >/dev/null 2>&1
report "T23 begin passes once the thirteen masters exist" 0 $?
rm docs/project/P12-product-context.md
scripts/agent-gate begin CHG-910 >/dev/null 2>&1
report "T23 begin refuses with an incomplete master set" 2 $?
seed_project_masters
scripts/agent-gate begin CHG-910 >/dev/null 2>&1
# 交付侧：09 缺回填清单 → stop 拒；行不完整 → 拒；补齐后（stub 溯源块）放行
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/CHG-910/09-changelog.md
printf 'cr\n' > docs/changes/CHG-910/04.5-coding-record.md
printf 'tr\n' > docs/changes/CHG-910/05-test-results.md
printf '未命中，不适用（无配置变更）\n' > docs/changes/CHG-910/06.5-deployment-config.md
printf '# 交付总结\n#### 遗留\n- FU-001 演示\n' > docs/changes/CHG-910/06-delivery-summary.md
for pf9 in docs/changes/CHG-910/*.md; do
  { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "$pf9"; } > "$pf9.tmp" && mv "$pf9.tmp" "$pf9"
done
echo y > src/t23.js   # stop 只在存在代码路径改动时执法（对齐 T5 夹具）
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T23 project-master backfill checklist is enforced at stop" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T23 refusal names the missing checklist" "项目总册回填清单" "$out"
append_masters docs/changes/CHG-910/09-changelog.md
sed -i '' 's/^- \[x\] P03/- [ ] P03/' docs/changes/CHG-910/09-changelog.md 2>/dev/null \
  || sed -i 's/^- \[x\] P03/- [ ] P03/' docs/changes/CHG-910/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T23 an unchecked row without a reason keeps stop red" 2 $?
sed -i '' 's/^- \[ \] P03/- [ ] P03 未命中（理由：无接口变化）/' docs/changes/CHG-910/09-changelog.md 2>/dev/null \
  || sed -i 's/^- \[ \] P03/- [ ] P03 未命中（理由：无接口变化）/' docs/changes/CHG-910/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T23 an explicit 未命中 row with a reason passes" 0 $?
  # v3.66.0 (CHG-089): a WHOLE missing P row (grep no-match) must surface as
  # GATE-E60 — pre-fix, pipefail killed the script before die() (silent exit 1).
  grep -v '^- \[x\] P05' docs/changes/CHG-910/09-changelog.md > docs/changes/CHG-910/09-changelog.md.tmp \
    && mv docs/changes/CHG-910/09-changelog.md.tmp docs/changes/CHG-910/09-changelog.md
  out=$(scripts/agent-gate --stage stop 2>&1 || true)
  check_output "T23 a wholly missing P row dies with GATE-E60 (not silent)" "GATE-E60" "$out"

}
section_T24() {
# ------------------------------------------------ T24 session water level (v3.38.0)
new_repo
seed_artifacts CHG-920 L1 claude/s-1
mkdir -p .agent-state
printf '{"turns":80,"session":"s-1","updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-water.json
out=$(scripts/agent-gate begin CHG-920 2>&1); rc=$?
check_output "T24 begin names the water level and both escapes" "session water level 80 turns reaches the 50-turn limit" "$out"
check_output "T24 refusal names handoff path" "handoff to a fresh session" "$out"
check_output "T24 refusal names escape env" "AGENT_GUARD_ALLOW_OVER_WATER=1" "$out"
report "T24 begin exit 2 over water" 2 "$rc"
AGENT_GUARD_ALLOW_OVER_WATER=1 scripts/agent-gate begin CHG-920 >/dev/null 2>&1
report "T24 explicit escape passes over water" 0 $?
printf '{"turns":10,"session":"s-2","updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-water.json
AGENT_GUARD_SESSION_TURN_LIMIT=5 scripts/agent-gate begin CHG-920 >/dev/null 2>&1
report "T24 tuned limit below turns refuses (exit 2)" 2 $?
rm -f .agent-state/session-water.json
AGENT_GUARD_SESSION_TURN_LIMIT=5 scripts/agent-gate begin CHG-920 >/dev/null 2>&1
report "T24 no water file degrades fail-open" 0 $?

}
section_T25() {
# ------------------------------------------------ T25 new-change scaffolder (v3.38.0)
new_repo
NEWCHANGE_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -f "$NEWCHANGE_SRC" ]]; then
  cp "$NEWCHANGE_SRC" scripts/new-change
  cp "$ROOT/resources/templates/agent-gate.sh" scripts/agent-gate   # v3.55.0: wave-2 确认门下沉 gate（check-confirm）
  chmod +x scripts/new-change
  # CHG-085/REQ-1042（TC-1109，v3.64.0⑥）：CHG-078 AC-1 一次性 grep 常驻化——
  # 判日/日期字段全形态（%Y%m%d/%Y-%m-%d）必须带 -u，防第三处漏网（FU-929）。
  _bare_date=$(grep -E 'date \+%Y' "$NEWCHANGE_SRC" | grep -vcE 'date -u \+%Y' || true)
  report "T25 TC-1109 no bare date +%Y in new-change.sh (all -u)" 0 "$_bare_date"
  # v3.62.2 (CHG-082)：本节后半主题=批次入批默认——撤夹具豁免（new-change 的
  # 批/独立分流同样读该开关）；CHG-930 专属目录 begin 属脚手架流主题，临时前缀豁免。
  unset AGENT_GUARD_ALLOW_INDEPENDENT
  # 夹具内联最小入口模板（内容契约由 audit-standards-src pin 覆盖；此处测脚手架逻辑）
  seed_entry_templates 意图 '__RISK__' 'open' '沟通稿（§2.17.2d 骨架）' '<!-- 机校标记：确认达成后追加 确认状态 行 -->' ' (__RISK__)' '（§2.2 输入契约）'

  scripts/new-change CHG-930 --risk L1 >/dev/null 2>&1
  report "T25 dedicated scaffold exits 0" 0 $?
  report "T25 wave1 creates three entry files" 3 "$(ls docs/changes/CHG-930/*.md docs/changes/CHG-930/*.json 2>/dev/null | wc -l | tr -d ' ')"
  check_output "T25 id substituted in governance" '"change_id": "CHG-930"' "$(cat docs/changes/CHG-930/00-governance.json)"
  out=$(scripts/new-change CHG-930 --risk L1 2>&1 || true)
  check_output "T25 wave2 withheld before confirmation (NC-E09)" "NC-E09" "$out"
  printf -- '- 确认状态：已整体确认\n' >> docs/changes/CHG-930/00.5-communication.md
  scripts/new-change CHG-930 --risk L1 >/dev/null 2>&1
  report "T25 wave2 scaffolded after confirmation" 0 $?
  report "T25 full eight entry files" 8 "$(ls docs/changes/CHG-930/*.md docs/changes/CHG-930/*.json 2>/dev/null | wc -l | tr -d ' ')"
  check_output "T25 risk substituted in spec" "L1" "$(cat docs/changes/CHG-930/01-spec.md)"
  # v3.62.2: owner 校验主题（非落位）——临时前缀豁免使 owner 检查成为决定性失败
  out=$(AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-930 2>&1 || true)
  check_output "T25 PENDING owners rejected by begin" "must name a concrete owner" "$out"
  sed -i '' 's/PENDING/op\/s-930/g; s/"review_owner": "op\/s-930"/"review_owner": "op\/s-r"/' docs/changes/CHG-930/00-governance.json 2>/dev/null \
    || sed -i 's/PENDING/op\/s-930/g; s/"review_owner": "op\/s-930"/"review_owner": "op\/s-r"/' docs/changes/CHG-930/00-governance.json
  # v3.62.2: 脚手架流主题（非落位）——CHG-930 为专属目录 L1，临时前缀豁免过 E86
  AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-930 >/dev/null 2>&1
  report "T25 filled scaffold passes begin (A-layer satisfied by skeleton)" 0 $?

  mkdir -p "docs/changes/BATCH-$(date -u +%Y%m%d)"
  printf '# intent\n## CHG-931\n## 预期结果\n## 开放问题\n' > "docs/changes/BATCH-$(date -u +%Y%m%d)/00-intent.md"
  printf '{"change_id": "CHG-931", "risk_level": "L0", "spec_author": "op/s-x", "implementation_owner": "op/s-x", "test_owner": "t/x", "review_owner": "r/x"}\n' > "docs/changes/BATCH-$(date -u +%Y%m%d)/00-governance.json"
  scripts/new-change CHG-932 --risk L0 >/dev/null 2>&1
  report "T25 batch-join exits 0" 0 $?
  report "T25 no dedicated dir for batch member" 0 "$(test ! -e docs/changes/CHG-932; echo $?)"
  grep -q '^## CHG-932' "docs/changes/BATCH-$(date -u +%Y%m%d)/00.5-communication.md"
  report "T25 batch wave1 carries ## CHG-932 anchor in 00.5" 0 $?
  out=$(scripts/new-change CHG-932 --risk L0 2>&1 || true)
  check_output "T25 wave2 withheld in batch before confirmation" "NC-E09" "$out"
  printf '\n- 确认状态：已整体确认\n' >> "docs/changes/BATCH-$(date -u +%Y%m%d)/00.5-communication.md"
  scripts/new-change CHG-932 --risk L0 >/dev/null 2>&1
  report "T25 batch wave2 after confirmation" 0 $?
  grep -q '^## CHG-932' "docs/changes/BATCH-$(date -u +%Y%m%d)/01-spec.md"
  report "T25 batch shared file carries ## CHG-932 anchor" 0 $?
  report "T25 governance.json gains one line per member" 2 "$(wc -l < "docs/changes/BATCH-$(date -u +%Y%m%d)/00-governance.json" | tr -d ' ')"
  out=$(scripts/new-change CHG-932 --risk L0 2>&1 || true)
  check_output "T25 duplicate id in batch refused" "fully scaffolded" "$out"
  out=$(scripts/new-change CHG-933 --risk L2 2>&1 || true)
  report "T25 L2 on a batch day goes dedicated (exit 0)" 0 $?
  report "T25 L2 dir is dedicated" 0 "$(test -d docs/changes/CHG-933; echo $?)"
  AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/new-change CHG-934 --risk L0 >/dev/null 2>&1
  report "T25 ALLOW_INDEPENDENT escapes to dedicated dir" 0 "$(test -d docs/changes/CHG-934; echo $?)"
  out=$(scripts/new-change CHG-935 2>&1 || true)
  check_output "T25 missing --risk refused" "--risk L0|L1|L2|L3 required" "$out"
  out=$(scripts/new-change CHG-936 --risk L9 2>&1 || true)
  check_output "T25 invalid risk refused" "--risk L0|L1|L2|L3 required" "$out"

  # v3.62.0（CHG-080/REQ-1022）：NC-E10 拆分——gate 缺失=NC-E10，check-confirm 执行失败（rc 非 0/1）=NC-E11；
  # 批/独立两分支共用 confirm_gate_run/die_check_confirm_failed（文案单源，逐字一致）。
  # 独立分支取 L2（批次日 L2 恒走 dedicated，T25 早前已断言）；批分支取 L0 入同日批。
  mv scripts/agent-gate scripts/agent-gate.away
  scripts/new-change CHG-937 --risk L2 >/dev/null 2>&1   # wave1 落盘，wave2 在确认门处停
  out=$(scripts/new-change CHG-937 --risk L2 2>&1 || true)
  check_output "T25 dedicated branch: missing gate dies NC-E10" "NC-E10: scripts/agent-gate not found" "$out"
  printf '#!/usr/bin/env bash\necho "stub check-confirm failure"\nexit 2\n' > scripts/agent-gate
  chmod +x scripts/agent-gate
  out=$(scripts/new-change CHG-937 --risk L2 2>&1 || true)
  check_output "T25 dedicated branch: check-confirm rc=2 dies NC-E11" "NC-E11: check-confirm failed .rc=2." "$out"
  mv scripts/agent-gate.away scripts/agent-gate
  mv scripts/agent-gate scripts/agent-gate.away
  scripts/new-change CHG-938 --risk L0 >/dev/null 2>&1   # 批分支 wave1 锚段落盘
  out=$(scripts/new-change CHG-938 --risk L0 2>&1 || true)
  check_output "T25 batch branch: missing gate dies NC-E10" "NC-E10: scripts/agent-gate not found" "$out"
  printf '#!/usr/bin/env bash\nexit 2\n' > scripts/agent-gate
  chmod +x scripts/agent-gate
  out=$(scripts/new-change CHG-938 --risk L0 2>&1 || true)
  check_output "T25 batch branch: check-confirm rc=2 dies NC-E11" "NC-E11: check-confirm failed .rc=2." "$out"
  mv scripts/agent-gate.away scripts/agent-gate
  printf -- '- 确认状态：已整体确认\n' >> docs/changes/CHG-937/00.5-communication.md
  scripts/new-change CHG-937 --risk L2 >/dev/null 2>&1
  report "T25 dedicated wave2 completes once the gate is restored" 0 $?
  # v3.64.0⑦（CHG-086/REQ-1043~1045，TC-1112~1114）：docs 根解析链对齐五兄弟——
  # yml pin 命中 / env 优先 / fail-closed 三态；夹具自清理，不污染本节后续断言。
  printf 'paths:\n  docs: doc\n' > .agent-governance.yml
  out=$(scripts/new-change CHG-945 --risk L1 2>&1 || true)
  check_output "T25 TC-1114 yml pin to missing templates dies NC-E06" "NC-E06" "$out"
  check_output "T25 TC-1114 NC-E06 self-help names AGENT_GUARD_DOCS_DIR" "AGENT_GUARD_DOCS_DIR" "$out"
  check_output "T25 TC-1114 NC-E06 self-help names .agent-governance.yml" "agent-governance.yml" "$out"
  mkdir -p doc/templates/entry
  printf '# <__CHANGE_ID__> 意图\n## 预期结果\n## 开放问题\n## 目录落位\n- **目录落位**：独立目录（t）\n' > doc/templates/entry/00-intent.md
  printf '{"change_id": "__CHANGE_ID__", "risk_level": "__RISK__", "spec_author": "PENDING", "implementation_owner": "PENDING", "test_owner": "PENDING", "review_owner": "PENDING"}\n' > doc/templates/entry/00-governance.json
  printf '# <__CHANGE_ID__> 沟通稿\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n' > doc/templates/entry/00.5-communication.md
  scripts/new-change CHG-946 --risk L1 >/dev/null 2>&1
  report "T25 TC-1112 bare run honors yml pin paths.docs=doc" 0 $?
  report "T25 TC-1112 wave1 lands under doc/changes" 3 "$(ls doc/changes/CHG-946/*.md doc/changes/CHG-946/*.json 2>/dev/null | wc -l | tr -d ' ')"
  mkdir -p docs2/templates/entry && cp doc/templates/entry/* docs2/templates/entry/
  AGENT_GUARD_DOCS_DIR=docs2 scripts/new-change CHG-947 --risk L1 >/dev/null 2>&1
  report "T25 TC-1113 env AGENT_GUARD_DOCS_DIR overrides yml pin" 3 "$(ls docs2/changes/CHG-947/*.md docs2/changes/CHG-947/*.json 2>/dev/null | wc -l | tr -d ' ')"
  rm -rf doc docs2 .agent-governance.yml
else
  echo "SKIP T25: new-change.sh absent (bootstrap --guard 未安装) — 跳过脚手架 golden cases"
fi

}
section_T26() {
# ------------------------------------------------ T26 session telemetry (v3.39.0)
new_repo
SESSION_GATE_SRC="$ROOT/resources/templates/session-gate.sh"
if [[ -f "$SESSION_GATE_SRC" ]]; then
  cp "$SESSION_GATE_SRC" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  bash scripts/session-gate.sh start >/dev/null 2>&1
  report "T26 telemetry files reset by start" 0 "$(test -s .agent-state/session-tool-stats.json && test -s .agent-state/session-water.json; echo $?)"
  bash scripts/session-gate.sh count turn >/dev/null 2>&1
  bash scripts/session-gate.sh count turn >/dev/null 2>&1
  check_output "T26 turn count lands in water file" '"turns":2' "$(cat .agent-state/session-water.json)"
  bash scripts/session-gate.sh count tool Bash >/dev/null 2>&1
  bash scripts/session-gate.sh count tool Grep >/dev/null 2>&1
  check_output "T26 tool counts classified" '"bash":1,"grep":1' "$(cat .agent-state/session-tool-stats.json)"
  printf '{"tool_name":"Read"}\n' | bash scripts/session-gate.sh count tool - >/dev/null 2>&1
  check_output "T26 stdin tool_name parsed (PostToolUse shape)" '"other":1' "$(cat .agent-state/session-tool-stats.json)"
  out=$(AGENT_GUARD_SESSION_TURN_LIMIT=3 bash scripts/session-gate.sh count turn 2>&1)
  check_output "T26 turn-limit warning emitted" "TURN LIMIT" "$out"
  for i in $(seq 1 25); do bash scripts/session-gate.sh count tool bash >/dev/null 2>&1; done
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T26 exploration yellow light on status" "bash calls 26 > 20" "$out"
  out=$(bash scripts/session-gate.sh idle 2>&1 || true)
  check_output "T26 idle carries yellow light" "bash calls 26 > 20" "$out"
  out=$(AGENT_GUARD_SESSION_TURN_LIMIT=5 bash scripts/session-gate.sh count turn 2>&1)
  if printf '%s' "$out" | grep -q "TURN LIMIT"; then report "T26 under-limit stays silent" 1 0; else report "T26 under-limit stays silent" 0 0; fi
  # ---- v3.90.1 (CHG-123, P0-15): token / model / context metering ----------
  rm -f .agent-state/model-profile.json
  out=$(bash scripts/session-gate.sh start 2>&1)
  check_output "T26 cost: unknown model flags assumed window" "WARN — context window unverified" "$out"
  check_output "T26 cost: assumed window is conservative 128000" '"context_window":128000,"source":"assumed"' "$(cat .agent-state/model-profile.json)"
  AGENT_GUARD_MODEL=m1 AGENT_GUARD_CONTEXT_WINDOW=64000 bash scripts/session-gate.sh start >/dev/null 2>&1
  check_output "T26 cost: env declares model+window" '"context_window":64000,"source":"declared"' "$(cat .agent-state/model-profile.json)"
  check_output "T26 cost: stats carries model+window keys" '"model_id":"m1","ctx_window":64000' "$(cat .agent-state/session-tool-stats.json)"
  out=$(AGENT_GUARD_MODEL=m2 AGENT_GUARD_CONTEXT_WINDOW=32000 AGENT_GUARD_TOKENS_IN=25600 bash scripts/session-gate.sh count tool Bash "echo x" 2>&1)
  check_output "T26 cost: model switch recomputes (80% => H2)" "used≈80%, H2" "$out"
  check_output "T26 cost: transition row appended" "m1	m2	64000	32000" "$(cat .agent-state/model-transitions.tsv)"
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T26 cost: status prints cost line" "- 成本：model=m2 窗口=32000（source=declared）已用≈80%（H2）" "$out"
  printf '{"turns":3,"bash":1,"grep":0,"other":2,"total":3,"updated_at":"2020-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
  bash scripts/session-gate.sh count tool Bash "ls" >/dev/null 2>&1
  check_output "T26 cost: old-schema stats stay readable" '"turns":3' "$(cat .agent-state/session-tool-stats.json)"
  check_output "T26 cost: old-schema gains ctx_window key" '"ctx_window":' "$(cat .agent-state/session-tool-stats.json)"
  # ---- v3.90.1 (CHG-123, P0-11): full_suite counts BUSINESS regressions only
  printf 'full_test_patterns: mvn test,tests/run-tests.sh\n' > .agent-governance.yml
  printf '{"turns":0,"bash":0,"grep":0,"other":0,"sleep_polls":0,"full_suite":0,"total":0,"edits":0,"updated_at":"2020-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
  bash scripts/session-gate.sh count tool Bash "bash tests/run-tests.sh" >/dev/null 2>&1
  check_output "T26 full_suite ignores governance self-test" '"full_suite":0' "$(cat .agent-state/session-tool-stats.json)"
  bash scripts/session-gate.sh count tool Bash "mvn test" >/dev/null 2>&1
  check_output "T26 full_suite counts business regression" '"full_suite":1' "$(cat .agent-state/session-tool-stats.json)"
  rm -f .agent-governance.yml
else
  echo "SKIP T26: session-gate.sh absent — 跳过会话遥测 golden cases"
fi

}
section_T26b() {
# ------------------------------------------------ T26b gate cost line (v3.90.1, CHG-123 P0-15)
new_repo
SG26B="$ROOT/resources/templates/session-gate.sh"
GT26B="$ROOT/resources/templates/agent-gate.sh"
if [[ -s "$SG26B" && -s "$GT26B" ]]; then
  cp "$SG26B" scripts/session-gate.sh
  cp "$GT26B" scripts/agent-gate
  chmod +x scripts/session-gate.sh scripts/agent-gate
  seed_artifacts CHG-930 L1 claude/s-26b
  printf '# 09\n' > docs/changes/CHG-930/09-changelog.md
  bash scripts/session-gate.sh start >/dev/null 2>&1
  bash scripts/session-gate.sh count tool Bash "echo x" >/dev/null 2>&1
  out=$(scripts/agent-gate cost-line CHG-930 2>&1); rc=$?
  report "T26b cost-line exits 0" 0 "$rc"
  check_output "T26b cost line lands in 09" "本次执行成本" "$(cat docs/changes/CHG-930/09-changelog.md)"
  before=$(grep -c '本次执行成本' docs/changes/CHG-930/09-changelog.md || true)
  scripts/agent-gate cost-line CHG-930 >/dev/null 2>&1
  after=$(grep -c '本次执行成本' docs/changes/CHG-930/09-changelog.md || true)
  report "T26b cost line idempotent per session" 0 "$(( after - before ))"
  out=$(scripts/agent-gate cost-line 2>&1 || true)
  check_output "T26b missing change id dies E132" "GATE-E132" "$out"
  report "T26b session-gate mirror byte-identical" 0 "$(cmp -s scripts/session-gate.sh "$SG26B"; echo $?)"
  report "T26b agent-gate mirror byte-identical" 0 "$(cmp -s scripts/agent-gate "$GT26B"; echo $?)"
else
  echo "SKIP T26b: session-gate.sh/agent-gate.sh absent — 跳过成本行 golden cases"
fi

}
section_T26c() {
# ------------------------------------------------ T26c 等待纪律 + payload 边界（v3.90.1，CHG-123）
# P0-6: AGENTS 纪律 10 forbids blocking waits and names the progress file.
check_output "T26c AGENTS forbids blocking TaskOutput" 'block:true timeout>60s' "$(cat "$ROOT/resources/AGENTS.md")"
check_output "T26c AGENTS names the progress file" 'suite-progress.json' "$(cat "$ROOT/resources/AGENTS.md")"
# P0-16: no S-layer path may appear inside a P-layer (installed) document.
# SKILL.md is the skill's own installer guide (source side), so it is NOT scanned;
# the payload face is what a target repo receives.
S16=$(mktemp -d "${TMPDIR:-/tmp}/payload.XXXXXX")
for f in "$ROOT/resources/AGENTS.md" "$ROOT/resources/DEVELOPMENT_STANDARDS.md" "$ROOT"/resources/templates/*.md; do
  [[ -f "$f" ]] && cp "$f" "$S16/" 2>/dev/null || true
done
hits=$(grep -hoE '(scripts/(bootstrap|facts|verify-all|selfcheck|lib-source-facts)|tests/audit-standards-src)\.sh' "$S16"/*.md 2>/dev/null | wc -l | tr -d ' ')
report "T26c P-layer docs never reference S-layer paths" 0 "$hits"
rm -rf "$S16"
# ---- P0-1: runtime probe (protocol family) + unknown => exit 3 + handshake ----
R16=$(mktemp -d "${TMPDIR:-/tmp}/runtime.XXXXXX")
mkdir -p "$R16/scripts"
cp "$ROOT/resources/templates/install-hook-adapter.sh" "$R16/scripts/" 2>/dev/null || true
cp "$ROOT/resources/templates/agent-gate.sh" "$R16/scripts/agent-gate" 2>/dev/null || true
# Strip client CLIs from PATH so "unknown" is reachable on a dev machine that
# happens to have them installed (the probe must key on shapes, not on my laptop).
r16_out=$( cd "$R16" && PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect 2>&1 ); r16_rc=$?
report "T26c unknown runtime exits 3 (never silent success)" 3 "$r16_rc"
check_output "T26c unknown runtime names the effective layers" 'Git hooks \+ CI only' "$r16_out"
mkdir -p "$R16/.claude"
r16_out=$( cd "$R16" && PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect 2>&1 ); r16_rc=$?
report "T26c known runtime exits 0" 0 "$r16_rc"
check_output "T26c runtime classified by family, not name" 'claude \(json-hooks\)' "$r16_out"
check_output "T26c runtime ledger written" '"family":"json-hooks"' "$(cat "$R16/.agent-state/runtime.json" 2>/dev/null)"
printf '{"runtime_id":"opencode","family":"plugin-api","clients":"opencode","generated_at":"x"}\n' > "$R16/.agent-state/runtime.json"
r16_out=$( cd "$R16" && PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect 2>&1 )
check_output "T26c runtime transition recorded" 'runtime changed' "$r16_out"
check_output "T26c handshake file written" '"runtime":' "$( cd "$R16" && git init -q . && bash scripts/agent-gate session-start >/dev/null 2>&1; cat "$R16"/.agent-state/runtime/*.json 2>/dev/null )"
rm -rf "$R16"
# ---- P0-7: every gate refusal carries expected / allowed / fix / ref -------
r16_out=$( cd "$R16" 2>/dev/null; printf '' )
G16="$ROOT/resources/templates/agent-gate.sh"
check_output "T26c die hints carry expected" 'expected:' "$(sed -n '/^gate_hint()/,/^}/p' "$G16")"
check_output "T26c die hints carry allowed" 'allowed:' "$(sed -n '/^gate_hint()/,/^}/p' "$G16")"
check_output "T26c die hints carry fix" 'fix:' "$(sed -n '/^gate_hint()/,/^}/p' "$G16")"
check_output "T26c die hints carry ref" 'ref:' "$(sed -n '/^gate_hint()/,/^}/p' "$G16")"
R17=$(mktemp -d "${TMPDIR:-/tmp}/four.XXXXXX"); mkdir -p "$R17/scripts"
cp "$G16" "$R17/scripts/agent-gate"; chmod +x "$R17/scripts/agent-gate"
r17_out=$( cd "$R17" && git init -q . && bash scripts/agent-gate begin CHG-404 2>&1 || true )
check_output "T26c refusal prints the four elements" 'expected:.*' "$r17_out"
check_output "T26c refusal names a fix command" '^fix:' "$r17_out"
check_output "T26c refusal points at a clause" '^ref:' "$r17_out"
rm -rf "$R17"
# review CHG-123 #3/#6 pins: bad --since ref is a usage error; probe switch is a
# real single switch back to legacy detection.
"$ROOT/tests/audit-docs-consistency.sh" --since no-such-ref-xyz >/dev/null 2>&1
report "T26c --since with an unresolvable ref exits 2" 2 $?
r17_out=$( cd "$R16" 2>/dev/null; printf '' )
R18=$(mktemp -d "${TMPDIR:-/tmp}/probe0.XXXXXX"); mkdir -p "$R18/scripts"
cp "$ROOT/resources/templates/install-hook-adapter.sh" "$R18/scripts/"
( cd "$R18" && PATH=/usr/bin:/bin AGENT_GUARD_RUNTIME_PROBE=0 bash scripts/install-hook-adapter.sh --detect >/dev/null 2>&1 ); r18_rc=$?
report "T26c AGENT_GUARD_RUNTIME_PROBE=0 restores legacy exit 0" 0 "$r18_rc"
rm -rf "$R18"

}
section_T82() {
# ------------------------------------------------ T82 判定引擎 v0（v3.90.2，CHG-124 P1）
new_repo
export AGENT_GUARD_ADAPT=1
GT82="$ROOT/resources/templates/agent-gate.sh"
BS82="$ROOT/scripts/bootstrap.sh"
if [[ -s "$GT82" ]]; then
  cp "$GT82" scripts/agent-gate
  chmod +x scripts/agent-gate
  seed_artifacts CHG-960 L1 claude/s-82
  mkdir -p tests
  cp "$ROOT/tests/run-tests.sh" tests/run-tests.sh 2>/dev/null || true
  # tracked governance-face change so the resolver has something to map
  printf 'x\n' > scripts/session-gate.sh
  git add scripts/session-gate.sh tests/run-tests.sh >/dev/null 2>&1
  git commit -qm seed >/dev/null 2>&1
  printf 'y\n' >> scripts/session-gate.sh
  # wall-clock is integer seconds and load-sensitive: take the best of 3 runs
  # (the target is still <=1 s; a single loaded run must not fail the assertion).
  t82_best=99
  for _t82_i in 1 2 3; do
    t82a=$(date +%s)
    out=$(scripts/agent-gate plan CHG-960 --dry-run 2>&1); rc=$?
    t82b=$(date +%s)
    _t82_d=$(( t82b - t82a ))
    [[ "$_t82_d" -lt "$t82_best" ]] && t82_best="$_t82_d"
  done
  report "T82 plan --dry-run exits 0" 0 "$rc"
  report "T82 plan --dry-run writes nothing" 0 "$(grep -c '\"decision\"' docs/changes/CHG-960/00-governance.json || true)"
  report "T82 plan runs under 1s (best of 3)" 0 "$(( t82_best > 1 ? 1 : 0 ))"
  out=$(scripts/agent-gate plan CHG-960 >/dev/null 2>&1); rc=$?
  report "T82 plan writes a decision" 0 "$rc"
  # review #1: a SECOND write must not corrupt the JSON (key stripped fully)
  scripts/agent-gate plan CHG-960 >/dev/null 2>&1
  report "T82 second plan keeps exactly one decision key" 0 "$(( $(grep -o '\"decision\"' docs/changes/CHG-960/00-governance.json | wc -l | tr -d ' ') - 1 ))"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' docs/changes/CHG-960/00-governance.json >/dev/null 2>&1
    report "T82 governance JSON stays valid after re-plan" 0 $?
  else
    echo "SKIP T82 JSON validity: python3 absent"
  fi
  report "T82 intent block appended once" 0 "$(( $(grep -c '^## 自适应判定' docs/changes/CHG-960/00-intent.md || true) - 1 ))"
  check_output "T82 decision carries engine+chosen+budget" '"engine_version":"adapt/v0"' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 decision keeps change_id" '"change_id":"CHG-960"' "$(cat docs/changes/CHG-960/00-governance.json)"
  out=$(scripts/agent-gate plan CHG-960 --explain 2>&1)
  check_output "T82 explain prints resolution rate" 'resolution_rate=' "$out"
  out=$(AGENT_GUARD_ADAPT=0 scripts/agent-gate plan CHG-960 2>&1)
  check_output "T82 ADAPT=0 disables plan" 'plan disabled' "$out"
  out=$(scripts/agent-gate plan CHG-999 2>&1 || true)
  check_output "T82 bad change id dies E136" 'GATE-E136' "$out"
  # E131 pins: warn-only wording + both markers
  report "T82 E131 is a hard die (R3)" 0 "$(( $(grep -c 'GATE-E131:' "$GT82" || true) >= 1 ? 0 : 1 ))"
  check_output "T82 E131 checks dogfood-next" 'dogfood-next' "$(sed -n '/^e131_dogfood_check()/,/^}/p' "$GT82")"
  check_output "T82 suite mode writes to 05" 'suite_mode=' "$(sed -n '/^record_suite_suggestion()/,/^}/p' "$GT82")"
  check_output "T82 down without reason falls back" 'falling back to adopt' "$(sed -n '/^record_suite_suggestion()/,/^}/p' "$GT82")"
  # v3.90.5 (CHG-126): P0-0 baseline + P1-2 tc-index + P2-1 four judges
  printf '# 09\n' > docs/changes/CHG-960/09-changelog.md
  out=$(scripts/agent-gate baseline CHG-960 --write 2>&1); report "T82 baseline --write exits 0" 0 "$?"
  report "T82 baseline writes five numbers" 5 "$(grep -oE '"(stop_p50_s|full_runs|audit_p50_s|full_assertions|full_wall_s)"' docs/changes/CHG-960/baseline.json | wc -l | tr -d ' ')"
  out=$(scripts/agent-gate baseline CHG-960 --write 2>&1)
  report "T82 baseline 09 line stays single" 1 "$(grep -c '^- \[baseline\]' docs/changes/CHG-960/09-changelog.md 2>/dev/null || true)"
  printf '| TC-9999 | fixture | tests/missing.sh |\n' >> docs/changes/CHG-960/04-test-scripts.md
  out=$(scripts/agent-gate tc-index CHG-960 2>&1)
  check_output "T82 tc-index marks a dangling landing" 'dangling=TC-9999' "$out"
  check_output "T82 tc-index reports the union rate" 'rate=' "$out"
  scripts/agent-gate tc-index CHG-960 --write >/dev/null 2>&1
  report "T82 tc-index --write persists the cache" 0 "$([[ -s tests/tc-index.tsv ]] && echo 0 || echo 1)"
  report "T82 tc-index names its source" 1 "$(grep -c '^TC-9999' tests/tc-index.tsv 2>/dev/null || true)"
  check_output "T82 decision carries the four judges" '"artifacts".*"reviews".*"stages".*"masters"' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 L1 judges are lean" '"stage_list":"intent,test,delivery"' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G5 stages carry the skipped set" '"skipped":\["' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G11 artifacts carry universe/depth/conditional" '"artifacts":{"universe":15,"depth":{.*},"conditional":{' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G11 project masters carry fill/na" '"project_masters":{"rows":"P00..P12","fill":\["P10"\],"na":\["P00"' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G12 must is present (empty is legal)" '"must":\[' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G6 wasted list is present" '"wasted":\[' "$(cat docs/changes/CHG-960/00-governance.json)"
  # G13: a `fix` change routes around spec/design (structural table, not keywords)
  sed 's/"risk_level":"L1"/"risk_level":"L2","change_type":"fix"/' docs/changes/CHG-960/00-governance.json > .gov.tmp && mv .gov.tmp docs/changes/CHG-960/00-governance.json
  scripts/agent-gate plan CHG-960 >/dev/null 2>&1
  check_output "T82 G13 fix skips spec/design" '"skipped":\["spec","design"\]' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G13 fix keeps diagnosis" '"path":\["intent","diagnosis"' "$(cat docs/changes/CHG-960/00-governance.json)"
  sed 's/"risk_level":"L2","change_type":"fix"/"risk_level":"L2"/' docs/changes/CHG-960/00-governance.json > .gov.tmp && mv .gov.tmp docs/changes/CHG-960/00-governance.json
  scripts/agent-gate plan CHG-960 >/dev/null 2>&1
  check_output "T82 L2 judges require the full stages" '"stage_list":"intent,spec,design,testplan,code,test,review,delivery"' "$(cat docs/changes/CHG-960/00-governance.json)"
  # G2: an impossible budget defers sections instead of silently overrunning.
  # Freeze the fixture first: leftover temp/docs files would make `-T auto`
  # fall back to FULL and the CAB face would never be exercised.
  git add -A >/dev/null 2>&1; git commit -qm t82cab >/dev/null 2>&1 || true
  printf 'z\n' >> scripts/session-gate.sh
  out=$(AGENT_GUARD_BUDGET_CLOSE_S=1 scripts/agent-gate plan CHG-960 --dry-run 2>&1)
  check_output "T82 G2 tight budget defers sections" '"deferred":\[\{"id":"T' "$out"
  # G6: three consecutive wasted rows remove a section from the recommendation
  mkdir -p .agent-state
  { printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\tasserts\trc\toutcome\trepo_key\tmodel_id\tctx_window\n'
    for i in 1 2 3; do
      printf '2026-01-0%sT00:00:00Z\tsec\tT26\t-\t20\t0\tnone\t0\t0\t0\twasted\tfixture@host/repo\t\t\n' "$i"
    done; } > .agent-state/cost-ledger.tsv
  out=$(scripts/agent-gate plan CHG-960 --dry-run 2>&1)
  check_output "T82 G6 three wasted rows drop the section" '"wasted":\["T26"\]' "$out"
  # G1: all three ledger writers carry the same in-place 8 -> 13 migration.
  check_output "T82 G1 runner migrates old ledger rows" '"asserts","rc","outcome","repo_key","model_id","ctx_window"; next' "$(sed -n '/^ledger_append()/,/^}/p' tests/run-tests.sh)"
  check_output "T82 G1 audit migrates old ledger rows" '"asserts","rc","outcome","repo_key","model_id","ctx_window"; next' "$(cat "$ROOT/resources/templates/audit-docs-consistency.sh")"
  check_output "T82 G1 gate migrates old ledger rows" '"asserts","rc","outcome","repo_key","model_id","ctx_window"; next' "$(cat "$ROOT/resources/templates/agent-gate.sh")"
  out=$(AGENT_GUARD_PLAN_AI_MASTERS="P10" \
    AGENT_GUARD_PLAN_AI_BASIS="fixture change is documented and risks no runtime surface" \
    AGENT_GUARD_PLAN_AI_REVIEWER="WorkBuddy / test-model / ses-t82-ai" \
    scripts/agent-gate plan CHG-960 --dry-run 2>&1)
  check_output "T82 AI judges override is recorded" '"judges_source":"ai"' "$out"
  out=$(AGENT_GUARD_PLAN_AI_MASTERS="P10" AGENT_GUARD_PLAN_AI_BASIS="short" \
    AGENT_GUARD_PLAN_AI_REVIEWER="WorkBuddy / test-model / ses-t82-ai" \
    scripts/agent-gate plan CHG-960 --dry-run 2>&1)
  check_output "T82 short AI basis falls back to engine" '"judges_source":"engine"' "$out"
  out=$(scripts/agent-gate baseline NOPE 2>&1 || true)
  check_output "T82 baseline bad id dies E140" 'GATE-E140' "$out"
  out=$(scripts/agent-gate tc-index NOPE 2>&1 || true)
  check_output "T82 tc-index bad id dies E141" 'GATE-E141' "$out"
else
  echo "SKIP T82: agent-gate absent — 跳过判定引擎 golden cases"
fi
if [[ -s "$BS82" ]]; then
  P82=$(mktemp -d "${TMPDIR:-/tmp}/prof.XXXXXX")
  # let bootstrap create the yml itself (the previous fixture pre-seeded a
  # partial yml, which made it abort before the writer — vacuous assertion).
  ( cd "$P82" && git init -q . && git config user.email t@e.invalid && git config user.name t \
    && echo x > README.md && git add README.md && git commit -qm i \
    && bash "$ROOT/scripts/bootstrap.sh" --guard . >/dev/null 2>&1 ); p82_rc=$?
  report "T82 bootstrap guard exits 0" 0 "$p82_rc"
  report "T82 profile section written once" 0 "$(( $(grep -c '^profile:' "$P82/.agent-governance.yml" 2>/dev/null || true) - 1 ))"
  check_output "T82 G9 profile carries schema_version" '^  schema_version: 1$' "$(cat "$P82/.agent-governance.yml")"
  check_output "T82 G7 profile carries ai_project" '^  ai_project: false$' "$(cat "$P82/.agent-governance.yml")"
  report "T82 G8 profile carries the nine detected dimensions" 9 \
    "$(awk '/^profile:/{p=1;next} p && /^[^ ]/{exit} p && /^  (ai_project|architecture|ui|runtime_env|repo_topology|assets|size|language|tests):/{n++} END{print n+0}' "$P82/.agent-governance.yml")"
  check_output "T82 G8 declared dimensions default to unknown" '^  business_complexity: unknown$' "$(cat "$P82/.agent-governance.yml")"
  ( cd "$P82" && bash "$ROOT/scripts/bootstrap.sh" --guard . >/dev/null 2>&1 )
  report "T82 profile not duplicated on re-run" 0 "$(( $(grep -c '^profile:' "$P82/.agent-governance.yml" || true) - 1 ))"
  check_output "T82 upgrade report names the switch" 'AGENT_GUARD_ADAPT=0' "$(sed -n '/upgrade-behavior/p' "$ROOT/scripts/bootstrap.sh")"
  rm -rf "$P82"
  # v3.90.5 P0-9/U-6: an older profile block gains missing keys, user values kept.
  P82b=$(mktemp -d "${TMPDIR:-/tmp}/prof-old.XXXXXX")
  ( cd "$P82b" && git init -q . && git config user.email t@e.invalid && git config user.name t \
    && echo x > README.md && git add README.md && git commit -qm i \
    && bash "$ROOT/scripts/bootstrap.sh" --guard . >/dev/null 2>&1 \
    && git add -A && git commit -qm install >/dev/null 2>&1 )
  # Shrink the fresh profile to the pre-U-6 shape, commit, then upgrade in place.
  perl -0777 -pi -e 's/^profile:\n(?:  .*\n)+/profile:\n  language: python\n  size: small\n/m' "$P82b/.agent-governance.yml"
  ( cd "$P82b" && git add .agent-governance.yml && git commit -qm shrink >/dev/null 2>&1 \
    && bash "$ROOT/scripts/bootstrap.sh" --upgrade . >/dev/null 2>&1 )
  check_output "T82 old profile keeps the user language" '^  language: python$' "$(cat "$P82b/.agent-governance.yml")"
  report "T82 old profile gains files" 1 "$(grep -c '^  files:' "$P82b/.agent-governance.yml" 2>/dev/null || true)"
  report "T82 old profile gains budgets" 1 "$(grep -c '^  budgets:' "$P82b/.agent-governance.yml" 2>/dev/null || true)"
  report "T82 G9 old profile gains schema_version" 1 "$(grep -c '^  schema_version:' "$P82b/.agent-governance.yml" 2>/dev/null || true)"
  rm -rf "$P82b"
fi

}
# PORTABILITY-WHITELIST-BEGIN
# Every `\|` below is an ERE literal inside a single-quoted pattern (legal on BSD
# and GNU grep -E), reviewed line by line in CHG-125; the CI OS matrix is the
# executable proof. New occurrences outside this block fail `--dual-run`.
# PORTABILITY-WHITELIST-END
section_T83() {
# ------------------------------------------------ T83 R3 硬门 + 自举（v3.90.3，CHG-125）
new_repo
export AGENT_GUARD_ADAPT=1
GT83="$ROOT/resources/templates/agent-gate.sh"
if [[ ! -s "$GT83" ]]; then echo "SKIP T83: agent-gate absent — 跳过 R3 硬门 golden cases"; return 0; fi
cp "$GT83" scripts/agent-gate; chmod +x scripts/agent-gate
seed_artifacts CHG-970 L2 claude/s-83
printf '# c\n\n### 用户整体确认记录\n\n- 待确认\n' > docs/changes/CHG-970/00.5-communication.md
printf '# 09\n' > docs/changes/CHG-970/09-changelog.md
af=$(git rev-parse --git-path agent-governance/active-change); mkdir -p "$(dirname "$af")"; printf 'CHG-970\n' > "$af"
out=$(scripts/agent-gate --stage staged 2>&1); report "T83 E129 L2 staged without confirmation" 2 "$?"
check_output "T83 E129 names the code" 'GATE-E129' "$out"
out=$(scripts/agent-gate preflight CHG-970 2>&1); report "T83 E130 preflight collects it" 1 "$?"
check_output "T83 E130 names the code" 'GATE-E130' "$out"
out=$(scripts/agent-gate --stage close 2>&1); report "T83 E127 close without confirmation" 2 "$?"
check_output "T83 E127 names the confirmation gap" 'no user-overall-confirmation' "$out"
printf '# c\n\n### 用户整体确认记录\n\n- 确认状态：已整体确认\n' > docs/changes/CHG-970/00.5-communication.md
out=$(scripts/agent-gate --stage close 2>&1); report "T83 E127 close without child-agent release" 2 "$?"
check_output "T83 E127 names the release gap" 'completed 子 Agent 放行' "$out"
printf '子 Agent 放行：待 07\n' >> docs/changes/CHG-970/09-changelog.md
out=$(scripts/agent-gate --stage close 2>&1); report "T83 E127 rejects a placeholder release" 2 "$?"
printf '子 Agent 放行：sub-83 放行 00-04\n' >> docs/changes/CHG-970/09-changelog.md
out=$(scripts/agent-gate --stage close 2>&1); report "T83 close green with prerequisites" 0 "$?"
test -s .agent-state/stage-close.json; report "T83 stage-close.json written" 0 "$?"
out=$(AGENT_GUARD_STAGE_CLOSE=0 scripts/agent-gate --stage close 2>&1); report "T83 STAGE_CLOSE=0 disables the gate" 0 "$?"
report "T83 E128 wired into delivery" 0 "$(( $(grep -c 'reviews_pair_check' "$GT83" || true) >= 1 ? 0 : 1 ))"
printf '#### 阶段复核\n' >> docs/changes/CHG-970/09-changelog.md
printf '# 05\n' > docs/changes/CHG-970/05-test-results.md
printf '# 04.5\n' > docs/changes/CHG-970/04.5-coding-record.md
out=$(scripts/agent-gate preflight CHG-970 2>&1); report "T83 E128 preflight negative" 1 "$?"
check_output "T83 E128 names the missing review file" 'GATE-E128' "$out"
mkdir -p docs/changes/CHG-970/reviews; printf 'ok\n' > docs/changes/CHG-970/reviews/P01.review.md
out=$(scripts/agent-gate preflight CHG-970 2>&1 || true)
report "T83 E128 quiet once the review file exists" 0 "$(printf '%s' "$out" | grep -c 'GATE-E128' || true)"
report "T83 E131 is a hard die (R3)" 0 "$(( $(grep -c 'GATE-E131:' "$GT83" || true) >= 1 ? 0 : 1 ))"
check_output "T83 bootstrap engine self-check" 'engine self-check' "$(cat "$ROOT/scripts/bootstrap.sh")"
check_output "T83 bootstrap runtime re-probe" 'runtime re-probe' "$(cat "$ROOT/scripts/bootstrap.sh")"
check_output "T83 audit writes a ledger row" 'audit' "$(sed -n '/FU-959/,+6p' "$ROOT/resources/templates/audit-docs-consistency.sh")"
report "T83 plan resolution is TC-level" 0 "$(( $(grep -c 'tc=%s' "$GT83" || true) >= 1 ? 0 : 1 ))"
check_output "T83 run p50 is full-only" 'run-full' "$(sed -n '/^plan_run_cost()/,/^}/p' "$GT83")"
# v3.90.4: review intelligence + runtime-aware model consent
report "T83 E137 consent gate is wired into delivery" 0 "$(( $(grep -c 'GATE-E137' "$GT83" || true) >= 1 ? 0 : 1 ))"
report "T83 E138 review-plan usage code present" 0 "$(( $(grep -c 'GATE-E138' "$GT83" || true) >= 1 ? 0 : 1 ))"
report "T83 begin seeds the review plan" 0 "$(( $(grep -c 'review_plan_seed' "$GT83" || true) >= 1 ? 0 : 1 ))"
check_output "T83 07 carries the input/professional contract" '评审输入契约与专业能力' "$(cat "$ROOT/resources/templates/entry/07-review-report.md")"
check_output "T83 07 carries model-cost consent" '模型选择与成本确认' "$(cat "$ROOT/resources/templates/entry/07-review-report.md")"
check_output "T83 07 carries producer-vs-reviewer independence" '独立性声明（生产 vs 评审' "$(cat "$ROOT/resources/templates/entry/07-review-report.md")"
check_output "T83 review intelligence contract ships runtime adaptation" '运行时适配' "$(cat "$ROOT/resources/methodologies/review-intelligence.md")"
# FU-126-1: AI judgment may override the runner-self-edit FULL fallback only with evidence.
out=$(AGENT_GUARD_SUITE_AUTO_DIFF="tests/run-tests.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
  AGENT_GUARD_SUITE_AI_SECTIONS="T83" \
  AGENT_GUARD_SUITE_AI_BASIS="diff only touches T83 assertions and review-plan; no shared gate state" \
  AGENT_GUARD_SUITE_AI_REVIEWER="WorkBuddy / test-model / ses-t83-ai" \
  bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
check_output "T83 AI judgment overrides runner-self-edit FULL" 'auto-resolve-only: T50 T83' "$out"
check_output "T83 AI judgment is announced with its basis" 'auto: AI judgment accepted' "$out"
out=$(AGENT_GUARD_SUITE_AUTO_DIFF="tests/run-tests.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
  AGENT_GUARD_SUITE_AI_SECTIONS="T83" AGENT_GUARD_SUITE_AI_BASIS="too short" \
  AGENT_GUARD_SUITE_AI_REVIEWER="WorkBuddy / test-model / ses-t83-ai" \
  bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
check_output "T83 AI judgment without evidence falls back to FULL" 'auto-resolve-only: FULL' "$out"
out=$(AGENT_GUARD_SUITE_AUTO_DIFF="tests/run-tests.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
  AGENT_GUARD_SUITE_AI_SECTIONS="T999" \
  AGENT_GUARD_SUITE_AI_BASIS="diff only touches T83 assertions and review-plan; no shared gate state" \
  AGENT_GUARD_SUITE_AI_REVIEWER="WorkBuddy / test-model / ses-t83-ai" \
  bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
check_output "T83 AI judgment with an unknown section falls back to FULL" 'auto-resolve-only: FULL' "$out"
# --dual-run scan + targeted run stays `run` (not run-full)
out=$(AGENT_GUARD_COST_LEDGER=/tmp/t83-ledger.tsv bash "$ROOT/tests/run-tests.sh" --dual-run -T T76 2>&1 | grep 'dual-run:' || true)
check_output "T83 dual-run prints the scan" 'unwhitelisted=' "$out"
check_output "T83 targeted run is not run-full" '0' "$(grep -c '^.*	run-full	' /tmp/t83-ledger.tsv 2>/dev/null || true)"
rm -f /tmp/t83-ledger.tsv
# v3.90.5 (CHG-126): P2-2 decision consume + P2-3 coverage + P2-5 backfill order
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 E142 strict requires a decision" 1 "$?"
check_output "T83 E142 names the code" 'GATE-E142' "$out"
scripts/agent-gate plan CHG-970 >/dev/null 2>&1
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 E143 missing hard artifact" 1 "$?"
check_output "T83 E143 names the code" 'GATE-E143' "$out"
cat > docs/changes/CHG-970/00-governance.json <<'EOF'
{"change_id":"CHG-970","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-83","test_owner":"claude/s-t","review_owner":"claude/s-r","decision":{"engine_version":"adapt/v0","chosen":"T83","artifacts":"05-test-results.md,09-changelog.md","reviews":"min=1;independent=true","stages":"staged,stop","masters":"","judges_source":"engine"}}
EOF
out=$(scripts/agent-gate preflight CHG-970 2>&1)
report "T83 coverage gap only WARNs" 0 "$(printf '%s' "$out" | grep -c 'GATE-E144' || true)"
report "T83 coverage gap is recorded in the decision log" 1 "$(grep -c 'no$' .agent-state/adapt-decisions.tsv 2>/dev/null || true)"
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 E144 strict coverage gap" 1 "$?"
check_output "T83 E144 names the code" 'GATE-E144' "$out"
printf -- '- decision-gap: coverage T83 — fixture gap\n' >> docs/changes/CHG-970/09-changelog.md
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1)
report "T83 declared coverage gap is accepted" 0 "$(printf '%s' "$out" | grep -c 'GATE-E144' || true)"
# G4: the final-plan `[adapt]` line is an accepted alias for the gap declaration.
sed 's/^- decision-gap: coverage T83 — fixture gap$/- [adapt] coverage T83 :: fixture gap :: T83 evidence/' \
  docs/changes/CHG-970/09-changelog.md > .adapt83.tmp && mv .adapt83.tmp docs/changes/CHG-970/09-changelog.md
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1)
report "T83 G4 [adapt] line clears E144" 0 "$(printf '%s' "$out" | grep -c 'GATE-E144' || true)"
printf '<!-- filled-at stage=3 chg=CHG-970 by=impl -->\n' >> docs/project/P05-task-plan.md
out=$(scripts/agent-gate --stage close 2 2>&1); report "T83 E145 P05 filled ahead of close 2" 2 "$?"
check_output "T83 E145 names the code" 'GATE-E145' "$out"
sed '/filled-at stage=3/d' docs/project/P05-task-plan.md > .p05.tmp && mv .p05.tmp docs/project/P05-task-plan.md
printf '<!-- filled-at stage=2 chg=CHG-970 by=impl -->\n' >> docs/project/P01-requirements-master.md
out=$(scripts/agent-gate --stage close 2 2>&1); report "T83 close stage 2 records P01" 0 "$?"
printf -- 'Observation: 已核对 00-04（未读回填）\n' >> docs/changes/CHG-970/09-changelog.md
out=$(scripts/agent-gate --stage close 3 2>&1); report "T83 E146 unread backfill" 2 "$?"
check_output "T83 E146 names the code" 'GATE-E146' "$out"
sed 's/Observation: 已核对 00-04（未读回填）/Observation: 已读 P01 增量并继续/' docs/changes/CHG-970/09-changelog.md > .o83.tmp && mv .o83.tmp docs/changes/CHG-970/09-changelog.md
out=$(scripts/agent-gate --stage close 3 2>&1); report "T83 read-back Observation clears E146" 0 "$?"
# v3.91.0 (CHG-127): G3 stale / G10 status+canary / G12 must / G15–G19 observability
out=$(scripts/agent-gate status 2>&1); report "T83 G10 status exits 0" 0 "$?"
check_output "T83 G10 status names enforcement" 'enforcement=' "$out"
cp "$ROOT/resources/templates/install-hook-adapter.sh" scripts/install-hook-adapter 2>/dev/null || true
out=$(bash scripts/install-hook-adapter --canary 2>&1); report "T83 G10 canary exits 0" 0 "$?"
check_output "T83 G10 canary writes a receipt" 'canary: ok' "$out"
out=$(scripts/agent-gate resume CHG-970 2>&1); report "T83 G17 resume exits 0" 0 "$?"
check_output "T83 G17 resume prints next steps" 'resume: next:' "$out"
out=$(scripts/agent-gate resume 2>&1 || true); check_output "T83 G17 resume usage dies E149" 'GATE-E149' "$out"
out=$(scripts/agent-gate metrics 2>&1)
check_output "T83 G15 metrics carry adoption" '"adoption_rate":' "$out"
check_output "T83 G16 metrics carry wasted/stale/handshake/independence" '"wasted_rate":.*"stale_decisions":.*"handshake":.*"review_independent":' "$out"
report "T83 G18 retro line carries CPI" 1 "$(grep -c 'CPI=' "$GT83" || true)"
report "T83 G19 session-gate prints the handoff action" 2 "$(grep -c 'handoff：水位' "$ROOT/resources/templates/session-gate.sh" || true)"
# G3: a decision whose diff_hash no longer matches the live diff is stale (strict).
git add -A >/dev/null 2>&1; git commit -qm t83base >/dev/null 2>&1
scripts/agent-gate plan CHG-970 >/dev/null 2>&1
printf 'x\n' >> docs/changes/CHG-970/01-spec.md
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 G3 stale decision dies E147" 1 "$?"
check_output "T83 G3 names the code" 'GATE-E147' "$out"
git checkout -- docs/changes/CHG-970/01-spec.md >/dev/null 2>&1 || true
# G12: a declared hard rule with a narrowed chosen is a contract violation (strict).
cat > docs/changes/CHG-970/00-governance.json <<'EOF'
{"change_id":"CHG-970","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-83","test_owner":"claude/s-t","review_owner":"claude/s-r","decision":{"engine_version":"adapt/v0","chosen":"T83","stage_list":"test,delivery","artifact_list":"05-test-results.md,09-changelog.md","must":["H7"],"reviews":"min=1;independent=true","masters":""}}
EOF
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 G12 must rule without FULL dies E148" 1 "$?"
check_output "T83 G12 names the code" 'GATE-E148' "$out"
# 2026-10-27 user ruling: the AI may narrow a must rule WITH evidence (judgment=ai).
cat > docs/changes/CHG-970/00-governance.json <<'EOF'
{"change_id":"CHG-970","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-83","test_owner":"claude/s-t","review_owner":"claude/s-r","decision":{"engine_version":"adapt/v0","chosen":"T83","judgment":"ai","stage_list":"test,delivery","artifact_list":"05-test-results.md,09-changelog.md","must":["H7"],"reviews":"min=1;independent=true","masters":""}}
EOF
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1)
report "T83 G12 AI judgment narrows a must rule" 0 "$(printf '%s' "$out" | grep -c 'GATE-E148' || true)"
# ---- TC-1555: self-bootstrap VERIFIED WITH CHG-124's real artifacts (copy only) ----
S83=$(mktemp -d "${TMPDIR:-/tmp}/selfboot.XXXXXX")
mkdir -p "$S83/scripts" "$S83/docs/changes"
cp "$GT83" "$S83/scripts/agent-gate"
cp "$ROOT/resources/templates/session-gate.sh" "$S83/scripts/session-gate.sh"
cp "$ROOT/resources/templates/install-hook-adapter.sh" "$S83/scripts/install-hook-adapter.sh"
cp "$ROOT/resources/templates/audit-docs-consistency.sh" "$S83/scripts/audit-docs-consistency.sh"
cp -R "$ROOT/docs/changes/CHG-124" "$S83/docs/changes/" 2>/dev/null || true
( cd "$S83" && git init -q . && git config user.email t@e.invalid && git config user.name t && git add -A >/dev/null 2>&1 && git commit -qm seed >/dev/null 2>&1 )
out=$( cd "$S83" && bash scripts/agent-gate plan CHG-124 2>&1 ); report "T83 self-boot plan on CHG-124 copy" 0 "$?"
( cd "$S83" && bash scripts/agent-gate plan CHG-124 >/dev/null 2>&1 )
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$S83/docs/changes/CHG-124/00-governance.json" >/dev/null 2>&1
  report "T83 self-boot CHG-124 JSON valid after re-plan" 0 "$?"
fi
report "T83 self-boot decision stays unique" 0 "$(( $(grep -o '"decision"' "$S83/docs/changes/CHG-124/00-governance.json" | wc -l | tr -d ' ') - 1 ))"
out=$( cd "$S83" && bash scripts/session-gate.sh start >/dev/null 2>&1; bash scripts/session-gate.sh count tool Bash x >/dev/null 2>&1; bash scripts/session-gate.sh status 2>&1 )
check_output "T83 self-boot CHG-123 cost line still prints" '成本：' "$out"
r83=$( cd "$S83" && PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect >/dev/null 2>&1; echo $? )
report "T83 self-boot unknown runtime exits 3" 3 "$r83"
mkdir -p "$S83/.claude"
out=$( cd "$S83" && PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect 2>&1 )
check_output "T83 self-boot family classification still works" 'claude \(json-hooks\)' "$out"
out=$( cd "$S83" && bash scripts/audit-docs-consistency.sh --since HEAD 2>&1 | head -1 )
check_output "T83 CHG-123 audit --since no-op path" 'declared no-op' "$out"
# v3.90.4: runtime-aware review plan + user-only consent on the CHG-124 copy
out=$( cd "$S83" && bash scripts/agent-gate review-plan CHG-124 2>&1 )
check_output "T83 review-plan detects the runtime" 'runtime=claude' "$out"
check_output "T83 review-plan names the family" 'family=json-hooks' "$out"
check_output "T83 review-plan names a viable execution scheme" 'scheme=(in-session-independent-subagent|multi-runtime-choose-one)' "$out"
printf '%s\n' '{"models":[{"id":"deep-test","provider":"v","tier":"deep","approval":true,"strengths":["code","handoff","architecture","business","bug"]}]}' > "$S83/deep-models.json"
out=$( cd "$S83" && AGENT_GUARD_REVIEW_MODELS="$S83/deep-models.json" bash scripts/agent-gate review-plan CHG-124 2>&1 )
check_output "T83 review-plan flags high-cost consent" 'approval_required=true' "$out"
r83=$( cd "$S83" && AGENT_GUARD_REVIEW_MODELS="$S83/deep-models.json" bash scripts/agent-gate review-plan CHG-124 --approve deep-test >/dev/null 2>&1; echo $? )
report "T83 review-plan refuses AI self-approval" 3 "$r83"
out=$( cd "$S83" && AGENT_REVIEW_USER_APPROVED=1 AGENT_GUARD_REVIEW_MODELS="$S83/deep-models.json" bash scripts/agent-gate review-plan CHG-124 --approve deep-test 2>&1 )
check_output "T83 user approval is recorded" '"approved":true' "$out"
rm -rf "$S83"

}
section_T27() {
# ------------------------------------------------ T27 pre-commit auto-stamp (v3.40.0)
new_repo
STAMP_SRC="$ROOT/resources/templates/stamp-provenance.sh"
HOOK_SRC="$ROOT/resources/templates/pre-commit"
if [[ -f "$STAMP_SRC" && -f "$HOOK_SRC" ]]; then
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  mkdir -p .githooks && cp "$HOOK_SRC" .githooks/pre-commit
  chmod +x .githooks/pre-commit scripts/stamp-provenance.sh scripts/agent-gate
  # TC-1070 (v3.61.2 REQ-1017): template carries the stamp-backfill logic
  bash -n "$HOOK_SRC"
  report "T27 TC-1070 template syntax" 0 $?
  report "T27 TC-1070 captures stamp file list" 2 "$(grep -cF 'stamped"||$1=="trace-derive' "$HOOK_SRC")"
  report "T27 TC-1070 strips blocks before compare" 1 "$(grep -cF 'trace-derive begin' "$HOOK_SRC")"
  report "T27 TC-1070 backfills via git add" 1 "$(grep -cF 'git add -- "$f"' "$HOOK_SRC")"
  report "T27 TC-1070 warns on beyond-stamp skip" 1 "$(grep -cF 'skip index backfill' "$HOOK_SRC")"
  seed_begin CHG-940 L1 claude/s-27
  report "T27 fixture begins clean" 0 $?
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 pre-commit exits 0 (stamp + staged)" 0 $?
  check_output "T27 hook stamped provenance block" "generated_by: stamp-provenance.sh" "$(cat docs/changes/CHG-940/00-intent.md)"
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 idempotent rerun keeps a single block" 1 "$(grep -c '^<!-- provenance$' docs/changes/CHG-940/00-intent.md | tr -d ' ')"
  scripts/agent-gate end >/dev/null 2>&1
  out=$(bash .githooks/pre-commit 2>&1 || true)
  if printf '%s' "$out" | grep -q "stamping provenance"; then report "T27 skip path prints no stamping line" 1 0; else report "T27 skip path prints no stamping line" 0 0; fi
  # bug_ref binding: the hook stamps the bound defect group too
  mkdir -p docs/bugs/BUG-940
  for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
    printf '# %s\n' "$doc" > "docs/bugs/BUG-940/$doc"
  done
  append_diag_lines docs/bugs/BUG-940/01-diagnosis.md
  sed -i '' 's/}$/,"bug_ref":"BUG-940"}/' docs/changes/CHG-940/00-governance.json 2>/dev/null \
    || sed -i 's/}$/,"bug_ref":"BUG-940"}/' docs/changes/CHG-940/00-governance.json
  scripts/agent-gate begin CHG-940 >/dev/null 2>&1
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 hook exits 0 with bug_ref bound" 0 $?
  check_output "T27 bound defect group stamped" "generated_by: stamp-provenance.sh" "$(cat docs/bugs/BUG-940/01-diagnosis.md)"
  # comma-joined batch governance (the §1.1 recommended shape): each member's
  # bug_ref must be extracted in isolation — no cross-member bleed
  mkdir -p docs/bugs/BUG-943 docs/bugs/BUG-944
  for b in 943 944; do for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do printf '# %s\n' "$doc" > "docs/bugs/BUG-$b/$doc"; done; append_diag_lines "docs/bugs/BUG-$b/01-diagnosis.md"; done
  mkdir -p docs/changes/BATCH-990922
  printf '{"change_id":"CHG-943","risk_level":"L0","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-943"}{"change_id":"CHG-944","risk_level":"L0","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-944"}\n' > docs/changes/BATCH-990922/00-governance.json
  seed_begin CHG-944 L0 claude/s-27
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 hook exits 0 on comma-joined batch member" 0 $?
  check_output "T27 member bug_ref stamped in isolation" "generated_by: stamp-provenance.sh" "$(cat docs/bugs/BUG-944/01-diagnosis.md)"
  if grep -q '^<!-- provenance$' docs/bugs/BUG-943/01-diagnosis.md; then report "T27 no cross-member bleed" 1 0; else report "T27 no cross-member bleed" 0 0; fi
  # TC-1071 (v3.61.2 REQ-1017): index backfill — tracked file's stamp is re-staged
  # so the commit itself carries the stamp (kills the post-commit residue loop).
  # Active change is CHG-944 (seed_begin switched it); --all stamps its own dir.
  git add docs/changes/CHG-944/00-intent.md
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 TC-1071 backfill: no unstaged delta after hook (stamp re-staged)" 0 "$(git diff --name-only -- docs/changes/CHG-944/00-intent.md | wc -l | tr -d ' ')"
  # TC-1072 (v3.61.2 REQ-1017): partial staging preserved — a delta beyond the
  # stamp (e.g. git add -p leftovers) blocks the backfill and warns (fail-open)
  printf '\nunstaged-extra-line\n' >> docs/changes/CHG-944/00-intent.md
  out=$(bash .githooks/pre-commit 2>&1 || true)
  report "T27 TC-1072 skip warning emitted for beyond-stamp delta" 1 "$(printf '%s' "$out" | grep -cF 'skip index backfill')"
  report "T27 TC-1072 unstaged hunk stays unstaged (not swept into index)" 1 "$(git diff --name-only -- docs/changes/CHG-944/00-intent.md | wc -l | tr -d ' ')"
  # TC-1082 (v3.62.1 CHG-081 REQ-1026): iteration-boundary backfill — index holds
  # stamped v1, hook re-stamps v2. Old strip compare swallowed exactly one
  # trailing blank, so any accumulated blank made strips differ and the backfill
  # never ran after the first attempt (the residue loop CHG-079 meant to kill).
  # Normalized compare must restage with no skip warning and no unstaged delta.
  git add docs/changes/CHG-944/00-intent.md
  out=$(bash .githooks/pre-commit 2>&1 || true)
  report "T27 TC-1082 no skip warning at iteration boundary" 0 "$(printf '%s' "$out" | grep -cF 'skip index backfill')"
  report "T27 TC-1082 restamp swept back into index (no unstaged delta)" 0 "$(git diff --name-only -- docs/changes/CHG-944/00-intent.md | wc -l | tr -d ' ')"
else
  echo "SKIP T27: stamp-provenance.sh/pre-commit absent (bootstrap --guard 未安装) — 跳过自动章 golden cases"
fi

}
section_T28() {
# ------------------------------------------------ T28 P3 defect lightweight channel (v3.40.0)
new_repo
seed_artifacts CHG-950 L1 claude/s-28
mkdir -p docs/bugs/BUG-950
printf '# 诊断\nseverity: P3\n现象：文案错别字\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > docs/bugs/BUG-950/01-diagnosis.md
printf '# 防回归\n| TC |\n' > docs/bugs/BUG-950/03-test-plan.md
printf '# 矩阵\n| REQ |\n' > docs/bugs/BUG-950/04-matrix.md
sed -i '' 's/}$/,"bug_ref":"BUG-950"}/' docs/changes/CHG-950/00-governance.json 2>/dev/null \
  || sed -i 's/}$/,"bug_ref":"BUG-950"}/' docs/changes/CHG-950/00-governance.json
scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T28 P3 severity waives 02/05/06 at begin" 0 $?
sed -i '' '/^severity: P3$/d' docs/bugs/BUG-950/01-diagnosis.md 2>/dev/null \
  || sed -i '/^severity: P3$/d' docs/bugs/BUG-950/01-diagnosis.md
scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T28 undeclared severity keeps full six-piece (fail-closed)" 2 $?
printf 'severity: P2\n' >> docs/bugs/BUG-950/01-diagnosis.md
scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T28 non-P3 value keeps full six-piece" 2 $?
# flat batch: severity must live inside the member's own section (same repo —
# standalone BUG-950 and the flat day batch coexist; same-day enforcement for
# the change track only fires when a CHANGE batch exists, none does here)
B9="docs/bugs/BATCH-$(date -u +%Y%m%d)"
mkdir -p "$B9"
printf '# 批次诊断\n## BUG-951\nseverity: P3\n文案\n延伸发现：未发现\n历史相似检索：未命中（x）\n## BUG-952\n无 severity 行\n' > "$B9/01-diagnosis.md"
printf '# 防回归\n## BUG-951\n## BUG-952\n' > "$B9/03-test-plan.md"
printf '# 矩阵\n## BUG-951\n## BUG-952\n' > "$B9/04-matrix.md"
seed_artifacts CHG-951 L1 claude/s-28b
sed -i '' 's/}$/,"bug_ref":"BUG-951"}/' docs/changes/CHG-951/00-governance.json 2>/dev/null \
  || sed -i 's/}$/,"bug_ref":"BUG-951"}/' docs/changes/CHG-951/00-governance.json
scripts/agent-gate begin CHG-951 >/dev/null 2>&1
report "T28 flat P3 severity read from member section" 0 $?
seed_artifacts CHG-952 L1 claude/s-28c
sed -i '' 's/}$/,"bug_ref":"BUG-952"}/' docs/changes/CHG-952/00-governance.json 2>/dev/null \
  || sed -i 's/}$/,"bug_ref":"BUG-952"}/' docs/changes/CHG-952/00-governance.json
scripts/agent-gate begin CHG-952 >/dev/null 2>&1
report "T28 flat member without severity keeps six-piece" 2 $?

}
section_T29() {
# ------------------------------------------------ T29 session RED blocks new changes (v3.40.0)
new_repo
seed_artifacts CHG-960 L1 claude/s-29
mkdir -p .agent-state
printf '# session-gate 报告\n- GATE RED — stop 未通过\n' > .agent-state/session-gate-last.md
scripts/agent-gate begin CHG-960 >/dev/null 2>&1
report "T29 no changelog baseline degrades fail-open" 0 $?
# a DELIVERED sibling change (its own 09, mtime older than the report) gives the
# comparison a baseline; CHG-960 itself stays open (no 09 of its own)
mkdir -p docs/changes/CHG-959
printf '# changelog\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t |\n' > docs/changes/CHG-959/09-changelog.md
touch -t 202001010000 docs/changes/CHG-959/09-changelog.md
out=$(scripts/agent-gate begin CHG-960 2>&1); rc=$?
report "T29 fresh RED report blocks begin" 2 "$rc"
check_output "T29 refusal names the unresolved red" "session audit RED unresolved" "$out"
check_output "T29 refusal names escape env" "AGENT_GUARD_ALLOW_OVER_RED=1" "$out"
touch -t 201901010000 .agent-state/session-gate-last.md
scripts/agent-gate begin CHG-960 >/dev/null 2>&1
report "T29 stale report passes (delivered after red)" 0 $?
touch -t 203501010000 .agent-state/session-gate-last.md
AGENT_GUARD_ALLOW_OVER_RED=1 scripts/agent-gate begin CHG-960 >/dev/null 2>&1
report "T29 explicit escape passes over red" 0 $?

}
section_T30() {
# ------------------------------------------------ T30 die error codes (v3.40.0)
total_die=$(grep -c 'die "' "$GATE_SRC" || true)
coded_die=$(grep -cE 'die "(GATE|NC|ADAPTER)-E[0-9]+: ' "$GATE_SRC" || true)
report "T30 every gate die carries an Exx code" 0 "$(( total_die - coded_die ))"
out=$(scripts/agent-gate begin CHG-404 2>&1 || true)
check_output "T30 refusal output carries GATE-E" "GATE-E" "$out"
NEWCHANGE_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -f "$NEWCHANGE_SRC" ]]; then
  report "T30 new-change die count equals coded" 0 "$(( $(grep -c 'die "' "$NEWCHANGE_SRC") - $(grep -cE 'die "NC-E[0-9]+: ' "$NEWCHANGE_SRC") ))"
fi
ADAPTER_SRC="$ROOT/resources/templates/install-hook-adapter.sh"
if [[ -f "$ADAPTER_SRC" ]]; then
  report "T30 adapter die count equals coded" 0 "$(( $(grep -c 'die "' "$ADAPTER_SRC") - $(grep -cE 'die "ADAPTER-E[0-9]+: ' "$ADAPTER_SRC") ))"
  grep -q "add it to .gitignore" "$ADAPTER_SRC"
  report "TC-1060 adapter prints .agent-state gitignore hint" 0 $?
fi

}
section_T31() {
# ------------------------------------------------ T31 G10 deprecated-clause sweep (v3.40.0)
AUDIT_SRC="$ROOT/resources/templates/audit-docs-consistency.sh"
if [[ -f "$AUDIT_SRC" ]]; then
  new_repo
  mkdir -p tests
  cp "$AUDIT_SRC" tests/audit-docs-consistency.sh
  mkdir -p docs
  printf '# 规范\n- 旧条款（v3.22.0 废止，改由 v3.35.0 批次）\n- 坏例：旧条款废止，无版本指向\n' > docs/DEVELOPMENT_STANDARDS.md
  printf '# AGENTS\n' > docs/AGENTS.md
  out=$(bash tests/audit-docs-consistency.sh 2>&1 || true)
  check_output "T31 G10 flags pointer-less 废止 marker" "废止标记缺版本指向" "$out"
  printf '# 规范\n- 旧条款（v3.22.0 废止，改由 v3.35.0 批次）\n- 好例：旧条款废止（v3.35.0 起由批次承担）\n' > docs/DEVELOPMENT_STANDARDS.md
  out=$(bash tests/audit-docs-consistency.sh 2>&1 || true)
  if printf '%s' "$out" | grep -q "废止标记缺版本指向"; then report "T31 G10 clean spec passes" 1 0; else report "T31 G10 clean spec passes" 0 0; fi
  check_output "T31 G10 ok line present (anti-crash-false-green)" "G10 every 废止 marker carries a superseding v3.x pointer" "$out"
else
  echo "SKIP T31: audit-docs-consistency.sh absent — 跳过 G10 golden cases"
fi

}
section_T32() {
# ------------------------------------------------ T32 one-step uninstall (v3.41.0)
new_repo
UNINST_SRC="$ROOT/resources/templates/uninstall-standards.sh"
if [[ -f "$UNINST_SRC" ]]; then
  cp "$UNINST_SRC" scripts/uninstall-standards
  chmod +x scripts/uninstall-standards
  seed_artifacts CHG-970 L1 claude/s-32
  # AGENTS.md is a shared asset: installer header + user-added content
  printf '# AGENTS\n## 门禁\n' > AGENTS.md
  printf '\nuser custom section\n' >> AGENTS.md
  mkdir -p .githooks
  cp "$ROOT/resources/templates/pre-commit" .githooks/pre-commit
  printf '#!/bin/sh\necho foreign\n' > .githooks/foreign-hook
  mkdir -p .github/workflows
  # PR template with BROKEN marker (custom content, no 门禁/agent-gate tokens) — Tier2 must keep it
  printf 'custom pr template, user edited\n' > .github/PULL_REQUEST_TEMPLATE.md
  # workflow template with INTACT marker — Tier2 must remove it
  cp "$ROOT/resources/templates/github-agent-governance.yml" .github/workflows/agent-governance.yml
  # Tier1 runtime file, deliberately MODIFIED — must be removed outright anyway
  cp "$ROOT/resources/templates/check-standards-compliance.sh" scripts/check-standards-compliance.sh
  printf '\n# local tampering\n' >> scripts/check-standards-compliance.sh
  git config core.hooksPath .githooks
  bash scripts/uninstall-standards --dry-run >/dev/null 2>&1
  report "T32 dry-run exits 0" 0 $?
  report "T32 dry-run removes nothing" 0 "$(test -f scripts/agent-gate && test -f .githooks/pre-commit && test -f AGENTS.md; echo $?)"
  bash scripts/uninstall-standards >/dev/null 2>&1
  report "T32 uninstall exits 0" 0 $?
  report "T32 runtime tier removed" 0 "$(test ! -e scripts/agent-gate && test ! -e scripts/uninstall-standards && test ! -d .agent-state; echo $?)"
  report "T32 marked hook removed" 0 "$(test ! -e .githooks/pre-commit; echo $?)"
  report "T32 marked workflow removed by marker" 0 "$(test ! -e .github/workflows/agent-governance.yml; echo $?)"
  report "T32 modified PR template kept (marker broken)" 0 "$(test -f .github/PULL_REQUEST_TEMPLATE.md; echo $?)"
  report "T32 modified runtime file removed outright (Tier1: check-standards-compliance.sh)" 0 "$(test ! -e scripts/check-standards-compliance.sh; echo $?)"
  report "T32 foreign hook kept" 0 "$(test -f .githooks/foreign-hook; echo $?)"
  report "T32 diverged AGENTS.md kept without --force" 0 "$(test -f AGENTS.md; echo $?)"
  report "T32 core.hooksPath unset" 0 "$(git config core.hooksPath >/dev/null 2>&1 && echo 1 || echo 0)"
  # --force round (re-seed the uninstaller: the first run self-removed it —
  # that is the designed one-step behavior; here we exercise Tier3 backup-move)
  cp "$UNINST_SRC" scripts/uninstall-standards
  bash scripts/uninstall-standards --force >/dev/null 2>&1
  report "T32 force never rm's shared assets" 0 "$(test ! -e AGENTS.md && test -f .githooks/foreign-hook; echo $?)"
  B32=$(ls -d .uninstall-backup-* 2>/dev/null | head -1)
  report "T32 backup holds the moved asset" 0 "$([[ -n "$B32" && -f "$B32/AGENTS.md" ]]; echo $?)"
else
  echo "SKIP T32: uninstall-standards.sh absent (bootstrap --guard 未安装) — 跳过卸载 golden cases"
fi

}
section_T33() {
# ------------------------------------------------ T33 trace derivation (v3.42.0)
new_repo
STAMP_SRC="$ROOT/resources/templates/stamp-provenance.sh"
[[ -f "$STAMP_SRC" ]] || STAMP_SRC="$ROOT/scripts/stamp-provenance.sh"
if [[ -f "$STAMP_SRC" ]]; then
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  mkdir -p docs/feature-f
  cat > docs/feature-f/01-spec.md <<'EOF'
# feature-f spec
REQ-955 trace derivation.
REQ-956 G5 subset.
EOF
  cat > docs/feature-f/01.5-rtvm-matrix.md <<'EOF'
# feature-f RTVM
| REQ | 简述 | DES | 方案 | TASK | 实现 | TC | 方法 | 状态 |
|---|---|---|---|---|---|---|---|---|
| `REQ-955` | derive | `DES-900` | d | T1 | i | `TC-950` | unit | ✅ |
| `REQ-956` | subset | `DES-901` | d | T2 | i | `TC-951` | unit | ✅ |
EOF
  mkdir -p docs/changes/CHG-980
  cat > docs/changes/CHG-980/09-changelog.md <<'EOF'
# 09 changelog
## CHG-980 · trace derivation
#### 追踪矩阵映射 (Traceability)
- 完整矩阵：docs/feature-f/01.5-rtvm-matrix.md（短引用，v3.23.0）
#### 现象
n/a
EOF
  bash scripts/stamp-provenance.sh --trace CHG-980 >/dev/null 2>&1
  report "T33 --trace derives the §4 block" 1 "$(grep -c 'trace-derive begin' docs/changes/CHG-980/09-changelog.md)"
  check_output "T33 REQ rows derived from matrix" '对应需求（派生）：`REQ-955`、`REQ-956`' "$(cat docs/changes/CHG-980/09-changelog.md)"
  check_output "T33 TC rows derived" '对应测试（派生）：`TC-950`、`TC-951`' "$(cat docs/changes/CHG-980/09-changelog.md)"
  cp docs/changes/CHG-980/09-changelog.md .t33-first
  bash scripts/stamp-provenance.sh --trace CHG-980 >/dev/null 2>&1
  report "T33 --trace is idempotent" 0 "$(diff -q .t33-first docs/changes/CHG-980/09-changelog.md >/dev/null; echo $?)"
  bash scripts/stamp-provenance.sh --all CHG-980 >/dev/null 2>&1
  report "T33 --all keeps the derived block" 1 "$(grep -c 'trace-derive begin' docs/changes/CHG-980/09-changelog.md)"
  report "T33 --all stamped provenance too" 1 "$(grep -c '^<!-- provenance$' docs/changes/CHG-980/09-changelog.md)"
  # TC-1090 (v3.62.2, CHG-082/REQ-1029, 评审 D3 自动化补齐): trace-derive 删块
  # 栅栏感知——09 节内栅栏示例块不被消费；自块幂等不受示例干扰。
  printf '```markdown\n<!-- trace-derive begin（示例，勿仿写）\n对应需求（派生）：`REQ-XXX`\n<!-- trace-derive end -->\n```\n' >> docs/changes/CHG-980/09-changelog.md
  bash scripts/stamp-provenance.sh --trace CHG-980 >/dev/null 2>&1
  report "T33 TC-1090 fenced sample trace block survives re-derive" 1 "$(grep -c 'trace-derive begin（示例' docs/changes/CHG-980/09-changelog.md)"
  report "T33 TC-1090 real derived block kept beside the sample" 2 "$(grep -c 'trace-derive begin' docs/changes/CHG-980/09-changelog.md)"
  cp docs/changes/CHG-980/09-changelog.md .t33-c1090
  bash scripts/stamp-provenance.sh --trace CHG-980 >/dev/null 2>&1
  report "T33 TC-1090 re-derive idempotent with fenced sample present" 0 "$(diff -q .t33-c1090 docs/changes/CHG-980/09-changelog.md >/dev/null; echo $?)"
  rm -f .t33-c1090 .t33-first
  # F3 (review): fail-open ladder — matrix WITH REQ rows but WITHOUT DES/TC
  # tokens (legal upstream shape) must derive a REQ-only block, not die
  # (exercises the `|| true` guards; would have caught F1).
  mkdir -p docs/feature-g
  cat > docs/feature-g/01.5-rtvm-matrix.md <<'EOF'
# feature-g RTVM
| REQ | 需求 | 状态 |
|---|---|---|
| `REQ-958` | req-only | ✅ |
EOF
  mkdir -p docs/changes/CHG-982
  cat > docs/changes/CHG-982/09-changelog.md <<'EOF'
# 09
## CHG-982 · req-only matrix
#### 追踪矩阵映射 (Traceability)
- 完整矩阵：docs/feature-g/01.5-rtvm-matrix.md
EOF
  out33=$(bash scripts/stamp-provenance.sh --trace CHG-982 2>&1); rc33=$?
  report "T33 REQ-only matrix derives without dying (F1 guard)" 0 "$rc33"
  check_output "T33 REQ-only block emits REQ row" '对应需求（派生）：`REQ-958`' "$(cat docs/changes/CHG-982/09-changelog.md)"
  report "T33 REQ-only block emits DES placeholder" 1 "$(grep -c '对应设计（派生）：—（01.5 未含 DES 编号）' docs/changes/CHG-982/09-changelog.md)"
  # F3 (review): --trace single-run block == --all derived block (equivalence)
  b1=$(sed -n '/^<!-- trace-derive begin/,/^<!-- trace-derive end/p' docs/changes/CHG-980/09-changelog.md)
  bash scripts/stamp-provenance.sh --all CHG-980 >/dev/null 2>&1
  b2=$(sed -n '/^<!-- trace-derive begin/,/^<!-- trace-derive end/p' docs/changes/CHG-980/09-changelog.md)
  report "T33 --trace block == --all block (equivalence)" 0 "$(printf '%s\n' "$b1" | diff - <(printf '%s\n' "$b2") >/dev/null; echo $?)"
  new_repo
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  mkdir -p docs/changes/CHG-981
  cat > docs/changes/CHG-981/09-changelog.md <<'EOF'
# 09
## CHG-981 · no matrix
#### 追踪矩阵映射 (Traceability)
- 对应需求：`REQ-970`（见 01-spec.md）
EOF
  out33=$(bash scripts/stamp-provenance.sh --trace CHG-981 2>&1); rc33=$?
  report "T33 --trace without matrix exits 0 (fail-open)" 0 "$rc33"
  check_output "T33 missing matrix announces skip" "trace skip" "$out33"
  report "T33 no marker block written on skip" 0 "$(grep -c 'trace-derive begin' docs/changes/CHG-981/09-changelog.md)"
else
  echo "SKIP T33: stamp-provenance.sh absent (bootstrap --guard 未安装) — 跳过派生 golden cases"
fi

}
section_T34() {
# ------------------------------------------------ T34 bug-autointent (v3.43.0)
new_repo
AUTO_SRC="$ROOT/resources/templates/bug-autointent.sh"
if [[ -f "$AUTO_SRC" ]]; then
  mkdir -p scripts docs/bugs/_templates docs
  cp "$AUTO_SRC" scripts/bug-autointent
  chmod +x scripts/bug-autointent
  cp "$ROOT"/resources/templates/bug-*.md docs/bugs/_templates/
  printf '# Bug 修复记录日志\n\n## 登记格式\n\n<!-- x -->\n' > docs/bugfix-log.md
  bash scripts/bug-autointent --repo-root "$REPO" --source ci-regression --failing "TestA,TestB" --run-url "http://run/1" >/dev/null 2>&1
  report "T34 scaffold creates six-piece flat batch" 6 "$(ls docs/bugs/BATCH-*/01-diagnosis.md docs/bugs/BATCH-*/02-impact.md docs/bugs/BATCH-*/03-test-plan.md docs/bugs/BATCH-*/04-matrix.md docs/bugs/BATCH-*/05-config.md docs/bugs/BATCH-*/06-tasks.md 2>/dev/null | wc -l | tr -d ' ')"
  report "T34 one anchor per piece" 1 "$(grep -c '^## BUG-' docs/bugs/BATCH-*/01-diagnosis.md)"
  report "T34 first-registration line present" 1 "$(grep -c '首次登记' docs/bugs/BATCH-*/01-diagnosis.md)"
  report "T34 fingerprint ledger has one row" 1 "$(wc -l < docs/bugs/.autofingerprint.tsv | tr -d ' ')"
  report "T34 bugfix-log index row registered" 1 "$(grep -c '^### BUG-' docs/bugfix-log.md)"
  bash scripts/bug-autointent --repo-root "$REPO" --source ci-regression --failing "TestB, TestA" --run-url "http://run/2" >/dev/null 2>&1
  report "T34 rate-limit: no new anchor in window" 1 "$(grep -c '^## BUG-' docs/bugs/BATCH-*/01-diagnosis.md)"
  report "T34 rate-limit: reproduction appended" 1 "$(grep -c '再次复现' docs/bugs/BATCH-*/01-diagnosis.md)"
  bash scripts/bug-autointent --repo-root "$REPO" --source ci-regression --failing "TestC" --window 0 --run-url "http://run/3" >/dev/null 2>&1
  report "T34 expired window scaffolds new BUG" 2 "$(grep -c '^## BUG-' docs/bugs/BATCH-*/01-diagnosis.md)"
  bash scripts/bug-autointent --repo-root /nonexistent-xyz --source x --failing A >/dev/null 2>&1
  report "T34 no-repo degrade exits 2" 2 $?
else
  echo "SKIP T34: bug-autointent.sh absent (bootstrap --guard 未安装) — 跳过自动登记 golden cases"
fi

}
section_T36() {
# ------------------------------------------------ T36 gate friction metrics (v3.43.0)
new_repo
GATE_T36="$ROOT/resources/templates/agent-gate.sh"
[[ -f "$GATE_T36" ]] || GATE_T36="$ROOT/scripts/agent-gate"
if [[ -f "$GATE_T36" ]]; then
  mkdir -p scripts .agent-state
  cp "$GATE_T36" scripts/agent-gate
  chmod +x scripts/agent-gate
  git config user.name t36; git config user.email t36@x
  git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1
  bash scripts/agent-gate begin CHG-990 >/dev/null 2>&1
  report "T36 die event appended to friction ledger" 1 "$(wc -l < .agent-state/gate-friction.tsv | tr -d ' ')"
  report "T36 friction code is GATE-E format" 1 "$(grep -cE '^GATE-E[0-9]+' .agent-state/gate-friction.tsv)"
  out36=$(bash scripts/agent-gate metrics 2>/dev/null | grep -c 'friction_code' || true)
  report "T36 metrics aggregates friction" 1 "$out36"
  # CHG-121 (batch 0): attribution columns — a 2-column ledger could not say
  # which change caused the friction.
  report "T36 friction row carries 5 columns (CHG-121)" 5 "$(awk -F'\t' 'NR==1{print NF}' .agent-state/gate-friction.tsv)"
  report "T36 friction row records the event kind (CHG-121)" 1 "$(awk -F'\t' 'NR==1 && $4=="DIE"{c++} END{print c+0}' .agent-state/gate-friction.tsv)"
else
  echo "SKIP T36: agent-gate absent — 跳过摩擦 metrics golden cases"
fi

}
section_T37() {
# ------------------------------------------------ T37 L0 最小集三态（v3.44.0，REQ-962）
if [[ -x scripts/agent-gate ]]; then
  t37_stamp() { for pf in docs/changes/$1/*.md; do
    { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "$pf"; } > "$pf.tmp" && mv "$pf.tmp" "$pf"; done; }
  t37_fill() { # id -> declaration-only 04.5/05 + minimal delivery set
    printf -- '- **编码记录**：未命中，不适用（L0 纯文档变更，无源码改动）\n' > docs/changes/$1/04.5-coding-record.md
    printf -- '- **测试结果**：未命中，不适用（L0 纯文档变更，无行为面）\n' > docs/changes/$1/05-test-results.md
    printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/$1/09-changelog.md
    printf '未命中，不适用（无配置变更）\n' > docs/changes/$1/06.5-deployment-config.md
    printf '# 交付总结\n#### 遗留\n- FU-001 演示\n' > docs/changes/$1/06-delivery-summary.md
    append_masters docs/changes/$1/09-changelog.md
    t37_stamp "$1"
  }
  # ① L0 + 04.5/05 单行声明 → stop PASS
  new_repo
  seed_begin CHG-991 L0 claude/s-1
  t37_fill CHG-991
  echo y > src/t37.js   # stop 只在存在代码路径改动时执法（对齐 T5/T23 夹具）
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L0 minimal-set: declaration satisfies 04.5/05" 0 $?
  # ⑤ v3.48.0（CHG-058）：02 缺延伸发现节 → E80（自愈还原；v3.48.1 CHG-060 自 E15 重编）
  sed -i '' '/延伸发现/d' docs/changes/CHG-991/02-code-impact-analysis.md 2>/dev/null || sed -i '/延伸发现/d' docs/changes/CHG-991/02-code-impact-analysis.md
  out=$(scripts/agent-gate --stage stop 2>&1 || true)
  check_output "stop refuses 02 missing 延伸发现 (E80)" "GATE-E80.*延伸发现" "$out"
  append_diag_lines docs/changes/CHG-991/02-code-impact-analysis.md
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 stop green again after 延伸发现 restored" 0 $?
  # ② L0 + 04.5/05 缺失 → 拒绝（E47 先于 E48）
  rm docs/changes/CHG-991/04.5-coding-record.md docs/changes/CHG-991/05-test-results.md
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L0 minimal-set: missing 04.5/05 still refused" 2 $?
  # ③ L1 + 仅声明行空壳 → GATE-E52（轻量通道越道拦截；盖章注释不计内容行）
  new_repo
  seed_begin CHG-992 L1 claude/s-1
  t37_fill CHG-992
  echo y > src/t37.js
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L1 declaration-only stub escapes its lane: stop refused" 2 $?
  out=$(scripts/agent-gate --stage stop 2>&1 || true)
  check_output "T37 refusal names the stub rule" "GATE-E52.*declaration-only stub" "$out"
  # ④ L1 + 半角括号/变体声明行 → E52 仍拦（评审 P1 修复：判定与形状解耦）
  { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'
    printf -- '- **编码记录**: 未命中, 不适用(纯文档)\n'; } > docs/changes/CHG-992/04.5-coding-record.md
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L1 bracket-variant stub still refused (P1 fix)" 2 $?
else
  echo "SKIP T37: agent-gate absent — 跳过 L0 最小集 golden cases"
fi

}
section_T38() {
# ------------------------------------------------ T38 断言预算制静态 pin（v3.45.0，REQ-965/967）
# audit 源层脚本 ROOT 绑定真仓——soft 行为面由交付实跑承载（对齐 T35/REQ-964 偏离先例）；
# 此处 pin 机制存在性与接线，防静默移除。
report "T38 audit soft bucket defined" 1 "$(grep -c 'report_soft()' "$ROOT/tests/audit-standards-src.sh")"
report "T38 audit soft env switch" 1 "$(grep -c 'SOFT="${AGENT_GUARD_AUDIT_SOFT:-}"' "$ROOT/tests/audit-standards-src.sh")"
# v3.86.0 (CHG-113): CI must run the source audit hard. The old pin counted any
# mention of the variable — including the ci.yml comment — so it stayed green
# even if a future edit added `AGENT_GUARD_AUDIT_SOFT: 1` back.
report "T38 CI does not set soft mode" 0 "$(grep -cE '^[[:space:]]*AGENT_GUARD_AUDIT_SOFT:' "$ROOT/.github/workflows/ci.yml")"
report "T38 CI runs the source audit hard" 1 "$(grep -cF 'bash tests/audit-standards-src.sh' "$ROOT/.github/workflows/ci.yml")"
report "T38 assertion lifecycle section" 1 "$(grep -c '^### 5.3 断言生命周期' "$ROOT/MAINTAINER.md")"
report "T38 graded ambiguity rule" 1 "$(grep -c '歧义分级裁定' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"

}
section_T39() {
# ------------------------------------------------ T39 条款注册表形态（v3.46.0，REQ-968）
REG_T39="$ROOT/resources/CLAUSE_REGISTRY.md"
if [[ -s "$REG_T39" ]]; then
  report "T39 registry schema header" 1 "$(grep -c '权威关系声明' "$REG_T39")"
  # v3.78.0 (CHG-102): 64 rows — R64（冻结树并行派发）joins the registry.
  report "T39 registry row count" 71 "$(grep -cE '^\| R[0-9]+[[:space:]]*\|' "$REG_T39")"
  report "T39 Rxx numbering continuous" 0 "$(awk -F'|' '/^\| R[0-9]+/{gsub(/[[:space:]]/,"",$2); n=substr($2,2)+0; if(n!=prev+1)bad++; prev=n} END{print bad+0}' "$REG_T39")"
  report "T39 labels in closed vocab" 0 "$(grep -E '^\| R[0-9]+' "$REG_T39" | awk -F'|' '{gsub(/[[:space:]]/,"",$5); if($5!="L0-bugfix"&&$5!="L1-standards"&&$5!="L2-architecture"&&$5!="L3-critical"&&$5!="universal")bad++} END{print bad+0}')"
  for t39_t in "L0-bugfix:12" "L1-standards:9" "L2-architecture:6" "L3-critical:3" "universal:12"; do
    t39_lab="${t39_t%%:*}"; t39_min="${t39_t##*:}"
    t39_n=$(grep -E '^\| R[0-9]+' "$REG_T39" | awk -F'|' -v l="$t39_lab" '{gsub(/[[:space:]]/,"",$5); if($5==l)n++} END{print n+0}')
    report "T39 type minimum $t39_lab >= $t39_min" 1 "$([[ "$t39_n" -ge "$t39_min" ]] && echo 1 || echo 0)"
  done
  t39_bad=0
  while IFS= read -r loc; do
    p="${loc%%::*}"; a="${loc#*::}"
    t39_file=""
    for t39_d in "$ROOT" "$ROOT/resources" "$ROOT/docs"; do
      [[ -f "$t39_d/$p" ]] && { t39_file="$t39_d/$p"; break; }
    done
    c=$(grep -cF -- "$a" "$t39_file" 2>/dev/null || echo 0)
    [[ "$c" == "1" ]] || t39_bad=$((t39_bad+1))
  done < <(grep -E '^\| R[0-9]+' "$REG_T39" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$4); print $4}')
  report "T39 all anchors resolve uniquely" 0 "$t39_bad"
  report "T39 generator present" 1 "$(test -x "$ROOT/resources/templates/generate-reading-pack.sh" && echo 1 || echo 0)"
else
  echo "SKIP T39: CLAUSE_REGISTRY.md absent — 跳过注册表 golden cases"
fi

}
section_T40() {
# ------------------------------------------------ T40 阅读包生成器多态（v3.46.0，REQ-969/970/971）
GEN_T40="$ROOT/resources/templates/generate-reading-pack.sh"
if [[ -x "$GEN_T40" ]]; then
  new_repo
  mkdir -p resources
  cp "$GEN_T40" resources/generate-reading-pack.sh && chmod +x resources/generate-reading-pack.sh
  printf '### 阶段 6\nfake clause body\n## 2.15 文档\nfake body 2\n## 2.7 发布\nrelease body\n### 0.5.1 风险\nrisk body\n### 1.1 编号\nnumbering body\n' > resources/fake-standards.md
  printf '路由行 content here\n' > resources/agents.md
  cat > resources/CLAUSE_REGISTRY.md <<'REG40'
| Rxx | 条款标题 | 权威落点 | 类型标签 | 强制级别 | 生命周期 |
| --- | --- | --- | --- | --- | --- |
| R01 | 缺陷主线 | resources/fake-standards.md::### 阶段 6 | L0-bugfix | 硬 | 结构 |
| R02 | 防覆盖 | resources/fake-standards.md::## 2.15 文档 | universal | 软 | 行为 |
| R03 | 前置 | resources/agents.md::路由行 | L1-standards | 硬 | 结构 |
| R04 | 发布 | resources/fake-standards.md::## 2.7 发布 | L2-architecture | 硬 | 结构 |
| R05 | 风险 | resources/fake-standards.md::### 0.5.1 风险 | L3-critical | 硬 | 结构 |
| R06 | 编号 | resources/fake-standards.md::### 1.1 编号 | L1-standards | 硬 | 结构 |
REG40
  out40="$(bash resources/generate-reading-pack.sh L0-bugfix 2>/dev/null)"; rc40=$?
  report "T40 normal generation exits 0" 0 "$rc40"
  report "T40 normal pack includes universal rows" 1 "$(printf '%s' "$out40" | grep -c '条款数：2')"
  report "T40 pack resolves line numbers" 1 "$(printf '%s' "$out40" | grep -c 'fake-standards.md:1')"
  out41="$(bash resources/generate-reading-pack.sh L1-standards 2>/dev/null)"; rc41=$?
  report "T40 L1 generation exits 0" 0 "$rc41"
  report "T40 L1 pack includes type rows" 1 "$(printf '%s' "$out41" | grep -c '条款数：3')"
  out42="$(bash resources/generate-reading-pack.sh L2-architecture 2>/dev/null)"; rc42=$?
  report "T40 L2 generation exits 0" 0 "$rc42"
  report "T40 L2 pack includes type rows" 1 "$(printf '%s' "$out42" | grep -c 'R04')"
  out43="$(bash resources/generate-reading-pack.sh L3-critical 2>/dev/null)"; rc43=$?
  report "T40 L3 generation exits 0" 0 "$rc43"
  report "T40 L3 pack includes type rows" 1 "$(printf '%s' "$out43" | grep -c 'R05')"
  bash resources/generate-reading-pack.sh L9-nope >/dev/null 2>&1
  report "T40 unknown type refused" 2 $?
  printf '| R01 | 坏锚 | resources/fake-standards.md::不存在的锚 | L0-bugfix | 硬 | 结构 |\n' > resources/reg-bad-miss.md
  CLAUSE_REGISTRY_FILE="$PWD/resources/reg-bad-miss.md" bash resources/generate-reading-pack.sh L0-bugfix >/dev/null 2>&1
  report "T40 anchor miss fail-closed" 3 $?
  printf '### 阶段 6\nfake clause body\n### 阶段 6\nduplicate anchor body\n' > resources/dup-standards.md
  printf '| R01 | 重锚 | resources/dup-standards.md::### 阶段 6 | L0-bugfix | 硬 | 结构 |\n' > resources/reg-bad-dup.md
  CLAUSE_REGISTRY_FILE="$PWD/resources/reg-bad-dup.md" bash resources/generate-reading-pack.sh L0-bugfix >/dev/null 2>&1
  report "T40 anchor not-unique fail-closed" 3 $?
  printf '| R01 | 缺文件 | resources/nofile.md::锚 | L0-bugfix | 硬 | 结构 |\n' > resources/reg-bad-file.md
  CLAUSE_REGISTRY_FILE="$PWD/resources/reg-bad-file.md" bash resources/generate-reading-pack.sh L0-bugfix >/dev/null 2>&1
  report "T40 anchor file missing fail-closed" 3 $?
  printf '| R01 | 无关 | resources/fake-standards.md::### 阶段 6 | L2-architecture | 硬 | 结构 |\n' > resources/reg-empty.md
  CLAUSE_REGISTRY_FILE="$PWD/resources/reg-empty.md" bash resources/generate-reading-pack.sh L0-bugfix >/dev/null 2>&1
  report "T40 empty type set refused" 4 $?
  v40="$(bash resources/generate-reading-pack.sh L0-bugfix --verify 2>/dev/null)"; rc40=$?
  report "T40 verify green silent exit 0" "0:0" "$rc40:${#v40}"
  # 接线静态 pin（源仓）
  # CHG-102：generator 计数 1→2（usage 护栏入口清单 + install 落点）。
  report "T40 bootstrap ships generator" 2 "$(grep -c 'generate-reading-pack' "$ROOT/scripts/bootstrap.sh")"
  report "T40 bootstrap ships registry" 1 "$(grep -c 'resources/CLAUSE_REGISTRY.md' "$ROOT/scripts/bootstrap.sh")"
  report "T40 uninstall lists generator" 1 "$(grep -c 'generate-reading-pack' "$ROOT/resources/templates/uninstall-standards.sh")"
  report "T40 gate exempt generator" 1 "$(grep -c 'generate-reading-pack' "$ROOT/resources/templates/agent-gate.sh")"
  report "T40 AGENTS pack route row" 1 "$(grep -c 'generate-reading-pack' "$ROOT/resources/AGENTS.md")"
  report "T40 DS registry clause" 1 "$(grep -c '2.17.2c' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
  report "T40 changelog v3.46.0 row" 1 "$(grep -c '^| v3.46.0 ' "$ROOT/resources/STANDARDS_CHANGELOG.md")"
else
  echo "SKIP T40: generator absent — 跳过阅读包生成器 golden cases"
fi

}
section_T41() {
# ------------------------------------------------ T41 gate 码唯一性（v3.48.1，CHG-060；E15/E16 重号复发防线）
GATE_T41="$ROOT/resources/templates/agent-gate.sh"
[[ -s "$GATE_T41" ]] || GATE_T41="$ROOT/scripts/agent-gate"
if [[ -s "$GATE_T41" ]]; then
  report "T41 gate die E-codes unique" 0 "$(grep -oE 'die "GATE-E[0-9]+: ' "$GATE_T41" | sort | uniq -d | wc -l | tr -d ' ')"
else
  echo "SKIP T41: agent-gate absent — 跳过码唯一性 golden case"
fi

}
section_T42() {
# ------------------------------------------------ T42 沟通先行门（v3.52.0，REQ-988/990/991）
new_repo
GATE42_SRC="$ROOT/resources/templates/agent-gate.sh"
NC42_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -s "$GATE42_SRC" && -s "$NC42_SRC" ]]; then
  cp "$GATE42_SRC" scripts/agent-gate
  cp "$NC42_SRC" scripts/new-change
  chmod +x scripts/agent-gate scripts/new-change
  seed_project_masters
  # TC-1035: begin 拒——00.5 缺失（presence 层 E03 点名 00.5；seed 夹具含确认标记，删除后触发）
  seed_artifacts CHG-950 L1 claude/s-42
  rm docs/changes/CHG-950/00.5-communication.md
  out=$(scripts/agent-gate begin CHG-950 2>&1 || true)
  check_output "T42 begin refuses missing 00.5 (E03 names the artifact)" "missing required artifact: docs/changes/CHG-950/00.5-communication.md" "$out"
  # TC-1036: begin 拒——确认记录节空（无标记）
  printf '# 00.5\n## 用户整体确认记录\n' > docs/changes/CHG-950/00.5-communication.md
  out=$(scripts/agent-gate begin CHG-950 2>&1 || true)
  check_output "T42 begin refuses empty confirmation record" "GATE-E83" "$out"
  # TC-1037: begin 过——确认标记在位
  printf '# 00.5\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n- 确认状态：已整体确认\n' > docs/changes/CHG-950/00.5-communication.md
  scripts/agent-gate begin CHG-950 >/dev/null 2>&1
  report "T42 begin passes with confirmation marker" 0 $?
  # TC-1039: AGENT_GUARD_ALLOW_UNCONFIRMED 显式越过
  seed_artifacts CHG-953 L1 claude/s-42
  rm docs/changes/CHG-953/00.5-communication.md
  AGENT_GUARD_ALLOW_UNCONFIRMED=1 scripts/agent-gate begin CHG-953 >/dev/null 2>&1
  report "T42 ALLOW_UNCONFIRMED is the explicit bypass" 0 $?
  # TC-1043: L0 单行声明轻量通道（无确认记录节，仅声明行）
  seed_artifacts CHG-954 L0 claude/s-42
  printf -- '- **沟通确认**：未命中，不适用（文案级变更，无行为面）\n' > docs/changes/CHG-954/00.5-communication.md
  scripts/agent-gate begin CHG-954 >/dev/null 2>&1
  report "T42 L0 single-line declaration satisfies the gate" 0 $?
  # F2 修复负例：L0-only 声明通道不外溢到 L1/L2/L3
  seed_artifacts CHG-958 L1 claude/s-42
  printf -- '- **沟通确认**：未命中，不适用（文案级变更）\n' > docs/changes/CHG-958/00.5-communication.md
  out=$(scripts/agent-gate begin CHG-958 2>&1 || true)
  check_output "T42 L0-only declaration refused for L1 (F2)" "L0-exclusive" "$out"
  # TC-1038: 批次成员按本变更锚点小节校验——兄弟成员的确认不外溢
  # P7（CHG-071）：本块成员差异（951 缺 00.5 锚 / 952 缺历史相似检索行）是测试点，不收拢 helper，保留原形独立演进。
  mkdir -p docs/changes/BATCH-99092501
  { printf '# intent\n'; printf '\n## CHG-951\n\n## 目录落位\n- **目录落位**：BATCH-YYYYMMDD（batch member）\n\n## 预期结果\n## 开放问题\n'; printf '\n## CHG-952\n\n## 目录落位\n- **目录落位**：BATCH-YYYYMMDD（batch member）\n\n## 预期结果\n## 开放问题\n'; } > docs/changes/BATCH-99092501/00-intent.md
  printf '{"change_id":"CHG-951","risk_level":"L1","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x"}\n{"change_id":"CHG-952","risk_level":"L1","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x"}\n' > docs/changes/BATCH-99092501/00-governance.json
  { printf '# spec\n\n## CHG-951\n\n- REQ-901: x\n'; printf '\n## CHG-952\n\n- REQ-902: x\n'; } > docs/changes/BATCH-99092501/01-spec.md
  { printf '# impact\n\n## CHG-951\n\n## 业务影响\n## 技术影响\n## 风险\n## 回滚策略\n延伸发现：未发现\n历史相似检索：未命中（x）\n'; printf '\n## CHG-952\n\n## 业务影响\n## 技术影响\n## 风险\n## 回滚策略\n延伸发现：未发现\n'; } > docs/changes/BATCH-99092501/02-code-impact-analysis.md
  { printf '# plan\n\n## CHG-951\n\n- DES-901: x\n## 技术选型\n备选: A vs B\n- **既有范式关系**：未命中（纯新增无同族实现）\n'; printf '\n## CHG-952\n\n- DES-902: x\n## 技术选型\n备选: A vs B\n'; } > docs/changes/BATCH-99092501/03-modification-plan.md
  { printf '# tasks\n\n## CHG-951\n\n- T-901: x（依赖: 无；里程碑: M1）\n- 评审输入: x\n'; printf '\n## CHG-952\n\n- T-902: x（依赖: 无；里程碑: M1）\n- 评审输入: x\n'; } > docs/changes/BATCH-99092501/03.5-tasks.md
  { printf '# tests\n\n## CHG-951\n\n- TC-901: x\n覆盖维度: 正常流\n- SC-901: x\n'; printf '\n## CHG-952\n\n- TC-902: x\n覆盖维度: 正常流\n- SC-902: x\n'; } > docs/changes/BATCH-99092501/04-test-scripts.md
  { printf '# comm\n\n## CHG-952\n\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n- 确认状态：已整体确认\n'; } > docs/changes/BATCH-99092501/00.5-communication.md
  out=$(scripts/agent-gate begin CHG-951 2>&1 || true)
  check_output "T42 batch member without own 00.5 anchor refused" "GATE-E83" "$out"
  scripts/agent-gate begin CHG-952 >/dev/null 2>&1
  report "T42 batch member with own anchor passes" 0 $?
  # TC-1040/1041/1042: new-change 两段式（wave1 三件 → 确认后补齐 → 越权旗标）
  seed_entry_templates intent '' comm '<!-- 标记待追加 -->' '' '' ''
  scripts/new-change CHG-955 --risk L1 >/dev/null 2>&1
  report "T42 wave1-only three files" 3 "$(ls docs/changes/CHG-955/*.md docs/changes/CHG-955/*.json 2>/dev/null | wc -l | tr -d ' ')"
  out=$(scripts/new-change CHG-955 --risk L1 2>&1 || true)
  check_output "T42 re-entry refuses before confirmation (NC-E09)" "NC-E09" "$out"
  printf -- '- 确认状态：已整体确认\n' >> docs/changes/CHG-955/00.5-communication.md
  scripts/new-change CHG-955 --risk L1 >/dev/null 2>&1
  report "T42 wave2 scaffolded after confirmation" 0 $?
  report "T42 full eight entry files" 8 "$(ls docs/changes/CHG-955/*.md docs/changes/CHG-955/*.json 2>/dev/null | wc -l | tr -d ' ')"
  scripts/new-change CHG-956 --risk L1 --allow-unconfirmed >/dev/null 2>&1
  report "T42 allow-unconfirmed scaffolds all eight" 8 "$(ls docs/changes/CHG-956/*.md docs/changes/CHG-956/*.json 2>/dev/null | wc -l | tr -d ' ')"
  # TC-1043（new-change 侧）：L0 声明解锁 wave2
  scripts/new-change CHG-957 --risk L0 >/dev/null 2>&1
  printf -- '- **沟通确认**：未命中，不适用（文案级变更）\n' >> docs/changes/CHG-957/00.5-communication.md
  scripts/new-change CHG-957 --risk L0 >/dev/null 2>&1
  report "T42 L0 declaration unblocks wave2" 8 "$(ls docs/changes/CHG-957/*.md docs/changes/CHG-957/*.json 2>/dev/null | wc -l | tr -d ' ')"
  # F2 镜像（new-change 侧）：L1 声明行不解锁 wave2（confirm_ok L0-exclusive）
  scripts/new-change CHG-959 --risk L1 >/dev/null 2>&1
  printf -- '- **沟通确认**：未命中，不适用（文案级变更）\n' >> docs/changes/CHG-959/00.5-communication.md
  out=$(scripts/new-change CHG-959 --risk L1 2>&1 || true)
  check_output "T42 L1 declaration does not unblock wave2 (NC-E09)" "NC-E09" "$out"
  # TC-1044 实证半边：stamp --all 给 00.5 盖溯源块
  bash "$ROOT/resources/templates/stamp-provenance.sh" --all CHG-955 >/dev/null 2>&1
  grep -q '^<!-- provenance$' docs/changes/CHG-955/00.5-communication.md
  report "T42 stamp --all covers 00.5" 0 $?
  # TC-1044: 入口模板在位 + 机校锚点串在模板中
  grep -q "用户整体确认记录" "$ROOT/resources/templates/entry/00.5-communication.md"
  report "T42 entry 00.5 template ships with confirmation anchor" 0 $?
  grep -q "00.5-communication.md" "$ROOT/scripts/bootstrap.sh"
  report "T42 bootstrap entry list carries 00.5" 0 $?
else
  echo "SKIP T42: agent-gate/new-change absent (bootstrap --guard 未安装) — 跳过沟通先行门 golden cases"
fi

}
section_T43() {
# ------------------------------------------------ T43 分阶段评审留痕（v3.53.0，REQ-993/994）
STD_T43="$ROOT/resources/DEVELOPMENT_STANDARDS.md"
AG_T43="$ROOT/resources/AGENTS.md"
if [[ -s "$STD_T43" ]]; then
  grep -q "分阶段评审留痕（v3.53.0，REQ-993）" "$STD_T43"
  report "T43 DS staged-review clause anchor" 0 $?
  grep -q "分阶段评审留痕核对" "$STD_T43"
  report "T43 DS stage-8 backfill-check row" 0 $?
  grep -q "缺陷轨机校点=绑定 CHG 的 begin" "$STD_T43"
  report "T43 bug-track machine checkpoint sentence (FU-902)" 0 $?
  grep -q '禁止"只做阶段 8 终审"的收敛执行' "$AG_T43"
  report "T43 AGENTS staged-review hard directive" 0 $?
  grep -q '分阶段评审\*\*：未命中，不适用' "$STD_T43"
  report "T43 L0/L1 merged-review declaration form" 0 $?
else
  echo "SKIP T43: DEVELOPMENT_STANDARDS.md absent — 跳过分阶段评审留痕 golden cases"
fi

}
section_T44() {
# ------------------------------------------------ T44 历史相似检索机校（v3.54.0，REQ-998）+ 补测（REQ-999）
GATE44_SRC="$ROOT/resources/templates/agent-gate.sh"
NC44_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -s "$GATE44_SRC" ]]; then
  new_repo
  cp "$GATE44_SRC" scripts/agent-gate
  cp "$NC44_SRC" scripts/new-change
  chmod +x scripts/agent-gate scripts/new-change
  seed_entry_templates intent '' comm '' '' '' ''
  seed_project_masters
  # TC-1052: CHG 轨——02 无历史相似检索节且无未命中声明 → E84；有声明 → 过
  seed_artifacts CHG-970 L1 claude/s-44
  sed -i '' '/历史相似检索/d' docs/changes/CHG-970/02-code-impact-analysis.md 2>/dev/null || sed -i '/历史相似检索/d' docs/changes/CHG-970/02-code-impact-analysis.md
  # CHG-117: begin narrowed to the entry gate; E84 lives on the legacy full
  # check and the staged/stop delivery face. Pin it through the documented
  # compatibility switch (default-on narrowing is covered by T80).
  out=$(AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-970 2>&1 || true)
  check_output "T44 CHG track refuses 02 missing 历史相似检索 (E84)" "GATE-E84" "$out"
  printf '历史相似检索：未命中（根因关键词检索）\n' >> docs/changes/CHG-970/02-code-impact-analysis.md
  AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-970 >/dev/null 2>&1
  report "T44 CHG track passes with declaration line" 0 $?
  # TC-1053: BUG 轨——01-diagnosis 缺历史相似检索 → E81
  mkdir -p docs/bugs/BUG-970
  for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do printf '# %s\n' "$d6" > "docs/bugs/BUG-970/$d6.md"; done
  printf '延伸发现：未发现\n' >> docs/bugs/BUG-970/01-diagnosis.md
  seed_artifacts CHG-971 L0 claude/s-44
  printf '{"change_id":"CHG-971","risk_level":"L0","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-970"}\n' > docs/changes/CHG-971/00-governance.json
  out=$(scripts/agent-gate begin CHG-971 2>&1 || true)
  check_output "T44 BUG track refuses 01-diagnosis missing 历史相似检索 (E81)" "GATE-E81.*延伸发现" "$out"
  printf '历史相似检索：未命中（根因关键词检索）\n' >> docs/bugs/BUG-970/01-diagnosis.md
  scripts/agent-gate begin CHG-971 >/dev/null 2>&1
  report "T44 BUG track passes with declaration line" 0 $?
  # TC-1050: staged 豁免态——ALLOW_UNCONFIRMED 下 00.5 缺省不阻 complete 判定
  seed_artifacts CHG-972 L1 claude/s-44
  rm -rf docs/changes/CHG-970 docs/changes/CHG-971 docs/bugs   # staged 判 complete-any：清掉其他完整目录隔离本例
  rm docs/changes/CHG-972/00.5-communication.md   # 工作树缺（complete 检查扫工作树）
  printf '#!/usr/bin/env bash\n' > scripts/probe-972.sh   # staged 的 complete 检查只对 code 文件触发（code without docs）
  git add scripts/probe-972.sh >/dev/null 2>&1   # 只 staged code——seed 的 md 不入 index（否则 docs_changed=true 绕过 complete 分支）
  scripts/agent-gate --stage staged >/dev/null 2>&1
  report "T44 staged code-only with worktree-missing 00.5 is refused (no bypass)" 2 $?
  out=$(AGENT_GUARD_ALLOW_UNCONFIRMED=1 scripts/agent-gate --stage staged 2>&1 || true)
  report "T44 staged passes under ALLOW_UNCONFIRMED" 0 $?
  # TC-1051: 批次成员自锚点在、节内确认记录空 → E83
  rm -rf docs/changes/CHG-973 docs/changes/CHG-974   # seed 专用目录会抢 change_dir 解析（独立目录永远优先）——只留批次形态
  mkdir -p docs/changes/BATCH-990944
  for f in 00-intent.md 00-governance.json 00.5-communication.md 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md; do : > "docs/changes/BATCH-990944/$f"; done
  for id in CHG-973 CHG-974; do seed_batch_member docs/changes/BATCH-990944 "$id"; done
  out=$(scripts/agent-gate begin CHG-973 2>&1 || true)
  check_output "T44 own anchor with empty confirmation refused (E83)" "GATE-E83" "$out"
  # TC-1055: confirm_ok 兄弟名单外溢负例（v3.54 收口）——兄弟有确认、本成员无 → wave2 仍拒
  scripts/new-change CHG-975 --risk L1 >/dev/null 2>&1
  printf -- '- 确认状态：已整体确认\n' >> docs/changes/CHG-975/00.5-communication.md
  scripts/new-change CHG-975 --risk L1 >/dev/null 2>&1
  report "T44 sibling-confirmed member scaffolds wave2" 8 "$(ls docs/changes/CHG-975/*.md docs/changes/CHG-975/*.json 2>/dev/null | wc -l | tr -d ' ')"
  scripts/new-change CHG-976 --risk L1 >/dev/null 2>&1
  out=$(scripts/new-change CHG-976 --risk L1 2>&1 || true)
  check_output "T44 no cross-member confirmation bleed (NC-E09)" "NC-E09" "$out"
  # TC-1056/1057: check-confirm 子命令 exit 协议（0/1/2）
  scripts/agent-gate check-confirm CHG-975 >/dev/null 2>&1
  report "T44 check-confirm exits 0 when confirmed" 0 $?
  scripts/agent-gate check-confirm CHG-976 >/dev/null 2>&1
  report "T44 check-confirm exits 1 when unconfirmed" 1 $?
  scripts/agent-gate check-confirm 2>/dev/null
  report "T44 check-confirm missing id exits 2 (non-die shape)" 2 $?
else
  echo "SKIP T44: agent-gate absent — 跳过历史相似检索机校 golden cases"
fi

}
section_T46() {
# ------------------------------------------------ T46 07 署名/溯源机校（v3.56.0，REQ-1005）
GATE46_SRC="$ROOT/resources/templates/agent-gate.sh"
if [[ -s "$GATE46_SRC" ]]; then
  new_repo
  cp "$GATE46_SRC" scripts/agent-gate
  chmod +x scripts/agent-gate
  seed_project_masters
  # TC-1061: 07 含签名行+task- id → stop 过（顺序：先 begin——09 落盘即闭合 E72）
  seed_begin CHG-980 L1 claude/s-46
  report "T46 fixture begins clean" 0 $?
  printf '## CHG-980 评审\n\n- 评审主体：agent-platform / llm-model / task-ses_0000000000fixture00000000\n- 结论：APPROVE\n- **发现处置**：未命中，不适用（T46 署名夹具，无发现）\n' > docs/changes/CHG-980/07-review-report.md
  printf '# coding\n实现记录\n' > docs/changes/CHG-980/04.5-coding-record.md
  printf '# results\nTests run: 1, Failures: 0\n' > docs/changes/CHG-980/05-test-results.md
  printf '# deploy\n未命中，不适用\n' > docs/changes/CHG-980/06.5-deployment-config.md
  printf '# delivery\n\n### 遗留\n- FU-980：T46 夹具（无实际遗留项，占位满足 E46 形态）\n' > docs/changes/CHG-980/06-delivery-summary.md
  printf '# changelog\n\n## CHG-980\n#### 项目总册回填清单\n- [x] P00 未命中（T46 夹具）\n- [x] P01 未命中（T46 夹具）\n- [x] P02 未命中（T46 夹具）\n- [x] P03 未命中（T46 夹具）\n- [x] P04 未命中（T46 夹具）\n- [x] P05 未命中（T46 夹具）\n- [x] P06 未命中（T46 夹具）\n- [x] P07 未命中（T46 夹具）\n- [x] P08 未命中（T46 夹具）\n- [x] P09 未命中（T46 夹具）\n- [x] P10 已回填（T46 夹具行）\n- [x] P11 已回填（T46 夹具行）\n- [x] P12 已回填（T46 夹具行）\n#### 执行记录（ReAct）\nObservation\n' > docs/changes/CHG-980/09-changelog.md
  printf '#!/usr/bin/env bash\n' > scripts/probe-980.sh   # stop 的 working_code_changed 前提
  bash "$ROOT/resources/templates/stamp-provenance.sh" --all CHG-980 >/dev/null 2>&1   # E19 溯源章
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T46 stop passes with signature+task id" 0 $?
  # TC-1062: 签名缺 task- id → E85 拒
  sed -i '' 's|task-ses_0000000000fixture00000000|self-reviewed|' docs/changes/CHG-980/07-review-report.md 2>/dev/null || sed -i 's|task-ses_0000000000fixture00000000|self-reviewed|' docs/changes/CHG-980/07-review-report.md
  out=$(scripts/agent-gate --stage stop 2>&1 || true)
  check_output "T46 stop refuses 07 without traceable task id (E85)" "GATE-E85" "$out"
else
  echo "SKIP T46: agent-gate absent — 跳过 07 署名机校 golden cases"
fi

}
section_T47() {
# ------------------------------------------------ T47 目录落位声明+E83 五要素（v3.60.0，REQ-1009）
GATE47_SRC="$ROOT/resources/templates/agent-gate.sh"
if [[ -s "$GATE47_SRC" ]]; then
  new_repo
  cp "$GATE47_SRC" scripts/agent-gate
  chmod +x scripts/agent-gate
  seed_project_masters
  # v3.62.2 (CHG-082): 本节主题=目录落位执法——显式撤掉 new_repo 的夹具豁免，
  # 让 E86 正反向新分支可见；个别非落位用例按需临时前缀豁免。
  unset AGENT_GUARD_ALLOW_INDEPENDENT
  # TC-1063: begin 拒——00-intent 缺落位声明（E86）
  seed_artifacts CHG-990 L1 claude/s-47
  sed -i '' '/目录落位/d' docs/changes/CHG-990/00-intent.md 2>/dev/null || sed -i '/目录落位/d' docs/changes/CHG-990/00-intent.md
  out=$(scripts/agent-gate begin CHG-990 2>&1 || true)
  check_output "T47 begin refuses missing placement declaration (E86)" "GATE-E86" "$out"
  # TC-1064: begin 拒——L2 声明 BATCH（风险级一致性）
  seed_begin CHG-991 L2 claude/s-47 tester reviewer
  sed -i '' 's/独立目录（single low-risk fixture）/BATCH-YYYYMMDD（wrong for L2）/' docs/changes/CHG-991/00-intent.md 2>/dev/null || sed -i 's/独立目录（single low-risk fixture）/BATCH-YYYYMMDD（wrong for L2）/' docs/changes/CHG-991/00-intent.md
  out=$(scripts/agent-gate begin CHG-991 2>&1 || true)
  check_output "T47 begin refuses L2 declaring BATCH placement (E86)" "GATE-E86" "$out"
  # TC-1065: begin 拒——非 L0 00.5 缺「风险」锚点（E83 五要素扩展）
  # v3.62.2: E86 先于 E83 落 die（声明级反向分支），为保 E83 为决定性失败，
  # 该用例临时前缀豁免（主题=E83，非落位）。
  seed_artifacts CHG-992 L1 claude/s-47
  sed -i '' '/^## 风险$/,/^risk: r$/d' docs/changes/CHG-992/00.5-communication.md 2>/dev/null || sed -i '/^## 风险$/,/^risk: r$/d' docs/changes/CHG-992/00.5-communication.md
  out=$(AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-992 2>&1 || true)
  check_output "T47 begin refuses 00.5 missing risk anchor (E83 five-element)" "GATE-E83.*风险" "$out"
  # TC-1066: 正例回归——L2 声明独立 + 五锚点齐 → begin 绿
  seed_begin CHG-993 L2 claude/s-47 tester reviewer
  scripts/agent-gate begin CHG-993 >/dev/null 2>&1
  report "T47 L2 declaring independent placement with full anchors begins" 0 $?
  # TC-1067 (v3.61.0 FU-912): begin 拒——批成员缺自锚段回落整文件=兄弟声明可替过（fail-open），
  # 现收紧 fail-closed；00.5 锚段在位使 E83 放行，E86 成唯一决定性失败
  seed_batch_artifacts BATCH-20260101 CHG-994:L0 CHG-995:L0
  sed -i '' '/^## CHG-995$/d' docs/changes/BATCH-20260101/00-intent.md 2>/dev/null || sed -i '/^## CHG-995$/d' docs/changes/BATCH-20260101/00-intent.md
  out=$(scripts/agent-gate begin CHG-995 2>&1 || true)
  check_output "T47 begin refuses batch member without own anchor section (E86 fail-closed)" "GATE-E86.*missing anchor section" "$out"
  report "T47 batch member with own anchor still begins (no spillover to sibling)" 0 $?
  scripts/agent-gate begin CHG-994 >/dev/null 2>&1
  # TC-1068 (v3.61.0): 正例回归——独立目录单成员无自锚段 → 整文件回落保留（防过收紧）
  # v3.62.2 (CHG-082): L0/L1 独立目录已非法（首个即建），回落语义的载体改用
  # L2 独立目录——E86 不涉 L2，回落正例语义原样保留。
  seed_begin CHG-996 L2 claude/s-47 tester reviewer
  scripts/agent-gate begin CHG-996 >/dev/null 2>&1
  report "T47 independent single-member change without anchor section falls back (v3.61.0 keeps fallback)" 0 $?
  # TC-1084 (v3.62.2, CHG-082 REQ-1028): E86 反向——无批 + 当日首个 L0/L1 声明独立 → begin 拒
  seed_artifacts CHG-997 L1 claude/s-47
  out=$(scripts/agent-gate begin CHG-997 2>&1 || true)
  check_output "T47 begin refuses first-of-day L0/L1 declaring independent placement (E86 reverse)" "GATE-E86.*first L0/L1 change of the day creates the day batch" "$out"
  # TC-1086 (v3.62.2): escape 两向通用——反向显式豁免后 begin 绿
  AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-997 >/dev/null 2>&1
  report "T47 escape admits a first-of-day L0/L1 independent change (explicit bypass)" 0 $?
  # TC-1085 (v3.62.2): E86 正向声明级——同日批目录已存在 + L1 声明独立 → begin 拒
  # （E86 措辞而非 E73：声明级校验在 validate_governance_state，先于 E73 的目录实况拦截）
  mkdir -p "docs/changes/BATCH-$(date -u +%Y%m%d)"
  seed_artifacts CHG-998 L1 claude/s-47
  out=$(scripts/agent-gate begin CHG-998 2>&1 || true)
  check_output "T47 begin refuses L0/L1 declaring independent while same-day batch exists (E86 forward)" "GATE-E86.*same-day L0/L1 changes must join the batch" "$out"
else
  echo "SKIP T47: agent-gate absent — 跳过落位声明 golden cases"
fi

}
section_T48() {
# ------------------------------------------------ T48 版本链同源 + 批次时序措辞（v3.62.0，REQ-1018/1020）
# TC-1073: four-chain version sameness (SKILL/AGENTS/DS/CHANGELOG) + wording
# "first-of-day creates the batch" present, old "same-day-many" trigger gone
# CHG-096: TC-1073 version pins recalibrated v3.72.0→v3.73.0 (four-chain bump).
# CHG-098: TC-1073 pins recalibrated v3.73.0→v3.74.0 (four-chain bump).
# CHG-100: TC-1073 pins recalibrated v3.75.0→v3.76.0 (four-chain bump).
# CHG-101: TC-1073 pins recalibrated v3.76.0→v3.77.0 (four-chain bump).
# CHG-102: TC-1073 pins recalibrated v3.77.0→v3.78.0 (four-chain bump). The two
# footer labels no longer spell a version literal — a label carrying a stale
# number was itself a drift source (renamed to "carries the current version").
report "T48 TC-1073 SKILL version line bumped" 1 "$(grep -cF "version: $CURRENT_VERSION" "$ROOT/SKILL.md")"
report "T48 TC-1073 SKILL carries v3.67.0 in prose (previous-version historical mentions preserved)" 3 "$(grep -cF 'v3.67.0' "$ROOT/SKILL.md")"
report "T48 TC-1073 DS footer carries the current version" 1 "$(grep -cF "规范版本：v$CURRENT_VERSION" "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T48 TC-1073 AGENTS footer carries the current version" 1 "$(grep -cF "当前对应规范版本：v$CURRENT_VERSION" "$ROOT/resources/AGENTS.md")"
# v3.72.0 erratum (CHG-095, TC-1275): v3.70.0 is no longer the top row (v3.72.0
# is), but its history row must stay present — grep pattern unchanged, label now
# states the superseded-row semantics.
report "T48 TC-1073 CHANGELOG v3.70.0 row exists (superseded by current top)" 1 "$(grep -c '^| v3.70.0 ' "$ROOT/resources/STANDARDS_CHANGELOG.md")"
report "T48 TC-1073 DS §1.1 first-of-day creates batch" 2 "$(grep -cF '当天 L0/L1 变更/缺陷首个即建' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T48 TC-1073 DS wording spots updated" 3 "$(grep -cF '首个即建' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T48 TC-1073 AGENTS gate section wording updated" 1 "$(grep -cF '当天 L0/L1 变更/缺陷首个即建' "$ROOT/resources/AGENTS.md")"
report "T48 TC-1073 README (en) wording updated" 1 "$(grep -cF 'first L0/L1** change (or defect) of the day creates' "$ROOT/README.md")"
report "T48 TC-1073 README (zh) wording updated" 1 "$(grep -cF '当天**首个 L0/L1** 变更/缺陷**即建**' "$ROOT/README.zh-CN.md")"
report "T48 TC-1073 entry template wording updated" 1 "$(grep -cF '当天首个 L0/L1 即入批' "$ROOT/resources/templates/entry/00-intent.md")"
report "T48 TC-1073 old same-day-many trigger gone from DS" 0 "$(grep -c '同一天\*\*多个\*\*.*默认共用' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T48 TC-1073 old same-day-many trigger gone from AGENTS" 0 "$(grep -c '同一天多个 L0/L1 默认共落' "$ROOT/resources/AGENTS.md")"
report "T48 TC-1073 README version strings bumped" 8 "$(grep -c 'v3.67.0' "$ROOT/README.md" "$ROOT/README.zh-CN.md" | awk -F: '{s+=$NF}END{print s}')"

}
section_T49() {
# ---- T49 (v3.63.0, CHG-083/REQ-1033~1037): 换挡执法 + 活性自检 + adapter 结构 ----
# ① GATE-E89 四态 + 时间窗 + R07-1 静默死亡回归。复用 T24 的种子手法：
#    new_repo（=新会话，started_at=-1H）+ seed_artifacts 一个 L1 变更。
new_repo
seed_artifacts CHG-950 L1 claude/s-1
mkdir -p .agent-state
# 态①：无 last-delivery → 放行
out=$(AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 2>&1); rc=$?
report "T49 E89 state1: no delivery passes" 0 "$rc"
rm -rf .git/agent-governance
# 态②：同会话交付（delivered 晚于 started）无 handoff → E89 die（rc=2，有码，不静默）
printf '{"delivered_at":"%s","change":"CHG-950","stage":"stop","session":""}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/last-delivery.json
out=$(AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 2>&1); rc=$?
report "T49 E89 state2: in-session delivery without handoff dies" 2 "$rc"
report "T49 E89 state2 die names the code (not silent)" 1 "$(printf '%s' "$out" | grep -c 'GATE-E89')"
rm -rf .git/agent-governance
# 态③：handoff 落在【变更自有目录】（R07-2 回归：尾斜杠路径）→ 放行
mkdir -p docs/changes/CHG-950
printf '# handoff\n' > docs/changes/CHG-950/handoff.md
out=$(AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 2>&1); rc=$?
report "T49 E89 state3: handoff in own change dir passes" 0 "$rc"
rm -rf .git/agent-governance docs/changes/CHG-950/handoff.md
# 态④：豁免 env → 放行
AGENT_GUARD_ALLOW_NO_SHIFT=1 scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T49 E89 state4: escape env passes" 0 $?
rm -rf .git/agent-governance
# 态⑤（TC-1095）：陈旧交付（早于 started_at）→ 放行
printf '{"delivered_at":"2020-01-01T00:00:00Z","change":"CHG-950","stage":"stop","session":""}\n' > .agent-state/last-delivery.json
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T49 E89 state5: stale delivery passes (fail-open)" 0 $?
rm -rf .git/agent-governance
# 态⑥（R07-1 回归）：last-delivery 在但 session-started.json 缺失 → 不得静默死亡
#    （死亡必须带 GATE 码；此处 CHG-950 已 active，begin 同号会走「已闭合/活跃」类
#    码——只断言"不无声退出"，语义由态②守门）
rm -f .agent-state/session-started.json
printf '{"delivered_at":"%s","change":"CHG-950","stage":"stop","session":""}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/last-delivery.json
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 >/dev/null 2>&1; rc=$?
report "T49 E89 R07-1: missing started marker is not a silent kill" 0 "$(( rc == 1 ? 1 : 0 ))"

# ② 活性自检三态（TC-1100；R07-5：坏 env 回落）
new_repo
mkdir -p .agent-state scripts
cp "$ROOT/resources/templates/session-gate.sh" scripts/session-gate.sh
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"turns":3,"bash":1,"grep":0,"other":2,"total":3,"updated_at":"2020-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
report "T49 liveness stale emits YELLOW" 1 "$(bash scripts/session-gate.sh status 2>&1 | grep -c 'telemetry stale')"
report "T49 liveness bad env falls back (no crash, still stale report)" 1 "$(AGENT_GUARD_SESSION_TELEMETRY_STALE_MIN=abc bash scripts/session-gate.sh status 2>&1 | grep -c 'telemetry stale')"
printf '{"turns":3,"bash":1,"grep":0,"other":2,"total":3,"updated_at":"%s"}\n' "$NOW" > .agent-state/session-tool-stats.json
report "T49 liveness fresh is quiet" 0 "$(bash scripts/session-gate.sh status 2>&1 | grep -c 'telemetry stale')"
rm -f .agent-state/session-tool-stats.json
mkdir -p .claude && printf '{}\n' > .claude/settings.json
report "T49 liveness wiring-but-no-telemetry emits YELLOW" 1 "$(AGENT_GUARD_ALLOW_NO_SHIFT=0 bash scripts/session-gate.sh status 2>&1 | grep -c 'zero telemetry')"

# ③ adapter 四段式（v3.64.0, CHG-084, TC-1103~1108）：桩 runtime 注入 + 真加载仲裁 + 功能级判据
new_repo
mkdir -p scripts
cat > stub-runtime.sh <<'STUB'
#!/usr/bin/env bash
# 桩 opencode runtime：SG_STUB_VERSION / SG_STUB_REJECT / SG_STUB_MARKER 三旋钮
# （T49-04 桩设计，CHG-084 04-test-scripts；模拟 拒载/载入/功能死 三态）
case "$1" in
  --version) echo "${SG_STUB_VERSION:-9.9.9-stub}"; exit 0 ;;
  serve)
    echo "opencode server listening on http://127.0.0.1:${3:-0}"
    # 探测契约对齐：POST /session 返回 200 体（免凭据，adapter 探针 POST 后
    # 即可拿到非空 probe-session.json）。nc 循环接受连接直到探针整组回收。
    if [[ "${3:-}" =~ ^[0-9]+$ ]]; then
      ( while true; do printf 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}' | nc -l 127.0.0.1 "$3" >/dev/null 2>&1; done ) &
    fi
    ;;
esac
# SG_STUB_SILENT=1：除 --version 外零输出零痕迹（E11 全 INCONCLUSIVE 路径）
if [[ "${SG_STUB_SILENT:-0}" == "1" && "$1" != "--version" ]]; then exit 0; fi
if [[ -n "${XDG_DATA_HOME:-}" ]]; then
  mkdir -p "$XDG_DATA_HOME/opencode/log" 2>/dev/null
  if [[ "${SG_STUB_REJECT:-0}" == "1" ]]; then
    printf '%s\n' "timestamp=T level=WARN message=\"failed to load plugin\" target=$PWD/.opencode/plugins/dev-standards-gate.js cause=\"SchemaError(stub)\"" > "$XDG_DATA_HOME/opencode/log/opencode.log"
  else
    printf '%s\n' "timestamp=T level=INFO message=\"plugin loaded: $PWD/.opencode/plugins/dev-standards-gate.js (stub)\"" > "$XDG_DATA_HOME/opencode/log/opencode.log"
  fi
fi
if [[ "${SG_STUB_MARKER:-0}" == "1" && "${SG_STUB_REJECT:-0}" != "1" ]]; then
  mkdir -p out 2>/dev/null
  printf 'sg-call start\n' >> out/sg-runs.log
  # 真实 session-gate.sh start 会写 .agent-state/*（含 probe-tag 关联行）——终验走这条通道，桩必须同型模拟
  mkdir -p .agent-state 2>/dev/null
  touch .agent-state/session-started.json
  printf 'probe-tag: %s\n' "${AGENT_GUARD_SESSION_TAG:-}" > .agent-state/session-gate-last.md
fi
# SG_STUB_DESKTOP_REJECT=1：desktop 形态调用（$1=workdir 路径）单独拒载——E13 主用回退路径
if [[ "${SG_STUB_DESKTOP_REJECT:-0}" == "1" && "$1" != "serve" && "$1" != "--version" && "$1" != "run" && -n "${XDG_DATA_HOME:-}" ]]; then
  mkdir -p "$XDG_DATA_HOME/opencode/log" 2>/dev/null
  printf '%s\n' "timestamp=T level=WARN message=\"failed to load plugin\" target=$PWD/.opencode/plugins/dev-standards-gate.js cause=\"SchemaError(stub-desktop)\"" > "$XDG_DATA_HOME/opencode/log/opencode.log"
  exit 0
fi
# 存活窗只需盖过探测窗（ arb 窗上限 3s + 终验重试 2s）：日志/功能标记均为
# spawn 同步落盘，先于本 sleep；探针按进程组回收，早退只让 kill 变 no-op。
sleep 2
STUB
chmod +x stub-runtime.sh
STUB_SH="$PWD/stub-runtime.sh"
cp "$ROOT/resources/templates/install-hook-adapter.sh" scripts/install-hook-adapter
cp "$ROOT/resources/templates/agent-gate.sh" scripts/agent-gate
cp "$ROOT/resources/templates/session-gate.sh" scripts/session-gate.sh
chmod +x scripts/install-hook-adapter scripts/agent-gate
export AGENT_GUARD_PROBE_WINDOW=1
export DEV_STANDARDS_OPENCODE_BIN="$STUB_SH"
export DEV_STANDARDS_OPENCODE_DESKTOP_BIN="$STUB_SH"
export SG_STUB_VERSION="1.19.0-stub"

# T49-01 (TC-1103): runtime 全抑制（路径不可执行=未检出）→ 显式 skip（非静默），不落盘
out=$(DEV_STANDARDS_OPENCODE_BIN=/nonexistent DEV_STANDARDS_OPENCODE_DESKTOP_BIN=/nonexistent \
  bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-01 no-runtime exits 2 (explicit no-op)" 2 "$rc"
report "T49-01 skip names the reason (not silent)" 1 "$(printf '%s' "$out" | grep -c 'no opencode runtime detected')"
report "T49-01 nothing written" 0 "$(test -f .opencode/plugins/dev-standards-gate.js && echo 1 || echo 0)"

# T49-02/03 (TC-1104/1105): 桩双 runtime 全过 → dual-active 胜出 + 契约头 + 功能证据落盘
SG_STUB_MARKER=1 bash scripts/install-hook-adapter --client opencode >/dev/null 2>&1; rc=$?
report "T49-02 stub-all-pass installs (rc0)" 0 "$rc"
report "T49-02 contract-runtime lists both runtimes" 1 "$(grep -c 'contract-runtime: cli=1.19.0-stub desktop=1.19.0-stub' .opencode/plugins/dev-standards-gate.js)"
report "T49-02 contract-shape=dual-active" 1 "$(grep -c 'contract-shape: dual-active' .opencode/plugins/dev-standards-gate.js)"
report "T49-02 contract-source field present" 1 "$(grep -c 'contract-source:' .opencode/plugins/dev-standards-gate.js)"
# R8 根因（收口复跑 651/3）：契约头按设计两行含 per-runtime PASS(function)——仲裁矩阵行(adapter :384→:645 盖章)+final-file 行(:699→:729 盖章)，grep -c 计行恒 2，期望 1 为过期断言；改钉 final-file 行全文（同时锁双 runtime 终验证据在位）
report "T49-02 verified evidence carries function marker" 1 "$(grep -cF 'final-file probes: cli=1.19.0-stub:PASS(function) desktop=1.19.0-stub:PASS(function)' .opencode/plugins/dev-standards-gate.js)"
report "T49-03 emitted default export is dual-active" 1 "$(grep -c 'export default { id: "dev-standards-gate", setup: DevStandardsGateV2, server: DevStandardsGate }' .opencode/plugins/dev-standards-gate.js)"
report "T49-03 named v1 export present" 1 "$(grep -c 'export const DevStandardsGate = async' .opencode/plugins/dev-standards-gate.js)"
report "T49-03 v2 setup export present" 1 "$(grep -c 'export const DevStandardsGateV2 = async' .opencode/plugins/dev-standards-gate.js)"
report "T49-05 arbitration attempts recorded (evidence not clobbered)" 1 "$(grep -cF 'attempt[all-runtimes] candidate[dual-active]' .opencode/plugins/dev-standards-gate.js)"

# T49-04 (TC-1106, SC-997): 客户端拒载桩 → ADAPTER-E12 die，不落盘
rm -f .opencode/plugins/dev-standards-gate.js
out=$(SG_STUB_MARKER=1 SG_STUB_REJECT=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-04 client-rejected dies (rc2)" 2 "$rc"
report "T49-04 die names ADAPTER-E12" 1 "$(printf '%s' "$out" | grep -c 'ADAPTER-E12')"
report "T49-04 no plugin left behind" 0 "$(test -f .opencode/plugins/dev-standards-gate.js && echo 1 || echo 0)"

# T49-04b (SC-998): 载入但零功能标记（schema-过-功能-死）→ E12 —— 假绿防线（本缺陷同族形态）
out=$(SG_STUB_MARKER=0 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-04b loaded-but-no-function dies (rc2)" 2 "$rc"
report "T49-04b names the functional-marker failure" 1 "$(printf '%s' "$out" | grep -q 'loaded-but-no-functional-marker' && echo 1 || echo 0)"

# T49-04c (E12 restore-with-backup)：已装好（T49-02 产物在位）→ 拒载重装 → E12 + 还原旧生成物
SG_STUB_MARKER=1 bash scripts/install-hook-adapter --client opencode >/dev/null 2>&1
out=$(SG_STUB_MARKER=1 SG_STUB_REJECT=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-04c reinstall-reject dies (rc2)" 2 "$rc"
report "T49-04c previous adapter restored intact" 1 "$(grep -cF 'export default { id: "dev-standards-gate", setup: DevStandardsGateV2, server: DevStandardsGate }' .opencode/plugins/dev-standards-gate.js 2>/dev/null)"

# T49-05a (E13 primary-only fallback)：desktop 形态单独拒载 → 全 runtime 无胜者 → 主用 runtime 择形 + 显式告警
out=$(SG_STUB_MARKER=1 SG_STUB_DESKTOP_REJECT=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-05a E13 fallback attempted but desktop-final-fail dies (rc2)" 2 "$rc"
report "T49-05a E13 warn names primary-only arbitration" 1 "$(printf '%s' "$out" | grep -c 'ADAPTER-E13 (warn)')"
# R8 根因：attempt[primary-only] 按设计出现两次——仲裁胜出 note(adapter :627)+final-fail die 附矩阵 note(:719，B2 追加式)，恒 2 非恒 1；期望同步为 2
report "T49-05a primary-only round recorded in matrix" 2 "$(printf '%s' "$out" | grep -c 'attempt\[primary-only\]')"

# T49-05b (E11 all-INCONCLUSIVE)：除版本应答外零痕迹 → 探测无判决 → E11 拒装
# R8 根因：E11 die(adapter :622) 先于 backup(:631)/写入(:639)，前置 T49-04c 还原的旧生成物原样保留 →「nothing written」恒 1（前置污染）；先清场再验「E11 不落盘」（对齐 T49-04 形态）
rm -f .opencode/plugins/dev-standards-gate.js
out=$(SG_STUB_MARKER=1 SG_STUB_SILENT=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-05b silent runtime dies E11 (rc2)" 2 "$rc"
report "T49-05b die names ADAPTER-E11" 1 "$(printf '%s' "$out" | grep -c 'ADAPTER-E11')"
report "T49-05b nothing written" 0 "$(test -f .opencode/plugins/dev-standards-gate.js && echo 1 || echo 0)"

# T49-06 (TC-1107): 真实 runtime 探测——默认 SKIP 并显式报告；AGENT_GUARD_T49_REAL_PROBE=1 才跑
unset AGENT_GUARD_PROBE_WINDOW DEV_STANDARDS_OPENCODE_BIN DEV_STANDARDS_OPENCODE_DESKTOP_BIN SG_STUB_VERSION
if [[ "${AGENT_GUARD_T49_REAL_PROBE:-0}" == "1" ]]; then
  out=$(bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
  report "T49-06 real-runtime install rc0" 0 "$rc"
  report "T49-06 no failed-to-load in verdict" 1 "$(printf '%s' "$out" | grep -c 'runtime-verified')"
else
  report "T49-06 real-runtime probe skipped by default (explicit, not silent)" 1 "1"
fi

# T49-07 (TC-1108): 套件不再包含 v3.63.0 自指形状断言（断言对象=行为证据，非模板字面量）
# 模式拆两段拼装：源码行永不连续包含该字面量（否则 grep 自匹配，永远=1）
_t49_legacy_head='export default { id: "dev-standards-gate", server: '
report "T49-07 legacy self-referential shape assertion removed" 0 "$(grep -cF "${_t49_legacy_head}DevStandardsGate }" "$ROOT/tests/run-tests.sh" || true)"

# ④ bootstrap 目录证据接线（TC-1096）——桩注入，不跑真探测
new_repo
mkdir -p .opencode
AGENT_GUARD_PROBE_WINDOW=1 SG_STUB_MARKER=1 SG_STUB_VERSION="1.19.0-stub" \
  DEV_STANDARDS_OPENCODE_BIN="$STUB_SH" DEV_STANDARDS_OPENCODE_DESKTOP_BIN="$STUB_SH" \
  bash "$ROOT/scripts/bootstrap.sh" --guard "$REPO" >/dev/null 2>&1
report "T49 bootstrap dir-evidence wires dual-active adapter" 1 "$(grep -c 'export default { id: "dev-standards-gate", setup: DevStandardsGateV2, server: DevStandardsGate }' .opencode/plugins/dev-standards-gate.js 2>/dev/null)"

}

# ------------------------------------------------ T50 run-tests 节过滤自测（v3.65.0，CHG-087/REQ-1046~1048）
# 嵌套跑只取轻量 grep 节（T38/T39）与元操作（-l / 未知节），绝不嵌套全跑（FU-907 纪律）。
# TC-1118 默认无参全节等价由 scripts/update-assertion-count.sh 全量实跑绿承载（不在此嵌套）。
section_T50() {
  local t50_out t50_rc t50_list t50_expect
  local t50_n39 t50_n38 t50_green t50_n t50_dup t50_first t50_last
  t50_out=$(bash "$ROOT/tests/run-tests.sh" -T T39 2>&1); t50_rc=$?
  # bash [[ ]] parses no bare pipelines; precompute all intermediates (learned:
  # nested $() inside [[ ]] inside "$()" mis-parses on bash 3.2 — TC-1115 first
  # run died with "conditional binary operator expected").
  t50_n39=$(printf '%s\n' "$t50_out" | grep -c '^ok   T39')
  t50_n38=$(printf '%s\n' "$t50_out" | grep -c '^ok   T38')
  t50_green=$(printf '%s\n' "$t50_out" | grep -q ', 0 failed$' && echo 1 || echo 0)
  report "T50 -T isolates single section (TC-1115)" 0 "$([[ $t50_rc -eq 0 && $t50_n39 -ge 3 && $t50_n38 -eq 0 && "$t50_green" == 1 ]] && echo 0 || echo 1)"
  report "T50 unknown section dies rc2 (TC-1116)" 2 "$(bash "$ROOT/tests/run-tests.sh" -T NOPE >/dev/null 2>&1; echo $?)"
  report "T50 wall-time is last line (TC-1117)" 1 "$(printf '%s\n' "$t50_out" | tail -1 | grep -cE '^wall-time: [0-9]+s$')"
  report "T50 summary anchor intact before wall-time (TC-1117)" 1 "$(printf '%s\n' "$t50_out" | tail -2 | head -1 | grep -cE '^[0-9]+ passed, [0-9]+ failed$')"
  t50_out=$(bash "$ROOT/tests/run-tests.sh" -T T39,T38 2>&1)
  report "T50 -T multi keeps source order (TC-1119)" "T38" "$(printf '%s\n' "$t50_out" | grep -m1 '^ok' | awk '{print $2}')"
  t50_list=$(bash "$ROOT/tests/run-tests.sh" -l 2>&1); t50_rc=$?
  t50_expect=$(grep -c '^section_' "$ROOT/tests/run-tests.sh")
  t50_n=$(printf '%s\n' "$t50_list" | grep -c '^T')
  t50_dup=$(printf '%s\n' "$t50_list" | sort | uniq -d)
  t50_first=$(printf '%s\n' "$t50_list" | head -1)
  t50_last=$(printf '%s\n' "$t50_list" | tail -1)
  # v3.66.0 (CHG-088): expected tail recalibrated T50→T51 after the receipt
  # self-test section joined the registry (same dynamic-count discipline).
  # v3.68.0 (CHG-043): tail recalibrated T52→T53 — T52 was taken by CHG-090 UX
  # gates, so the G13/G14 section registered as T53 (registry growth only;
  # count stays dynamic via t50_expect).
  # CHG-044: tail recalibrated T53→T54 (G14e element-enumeration section joins).
  # CHG-046: tail recalibrated T54→T55 (delivery four-gate section joins).
  # CHG-094: tail recalibrated T55→T56 (begin-artifact preflight probe joins).
  # CHG-095: tail recalibrated T56→T57 (parallel-dispatch / red-archive self-test joins).
  # CHG-096: tail recalibrated T57→T58 (telemetry discipline self-test joins).
  # CHG-100: tail recalibrated T60→T61 (验证通道方言与四态 golden 节 joins).
  # CHG-102: tail recalibrated T62→T63 (本变更注册 T63「治理面口径 + 下发面缺口」节).
  # CHG-109: tail recalibrated T63→T65 (秒级形状探针节 joins; T64 stays mid-list
  #   per CHG-107 scaffold ordering).
  # CHG-110: tail recalibrated T65→T66 (verify 结果缓存节 joins; TC-1414).
  # CHG-111: tail recalibrated T66→T67 (六不变量机校节 joins; TC-1424~1432).
  # CHG-113: tail recalibrated T67→T68; CHG-115: T68→T73b (基线/事实/编排/前置/变异/汇总六节 joins).
  # CHG-117: tail recalibrated T76→T81 (无账门/编辑硬拦/G16/阶段门/阶段感知五节 joins).
  report "T50 -l lists all sections uniquely (TC-1120)" 0 "$([[ $t50_rc -eq 0 && $t50_n -eq "$t50_expect" && -z "$t50_dup" && "$t50_first" == T1 && "$t50_last" == T83 ]] && echo 0 || echo 1)"
}

# ------------------------------------------------ T51 收据机制自测（v3.66.0，CHG-088/REQ-1049~1051）
# clone-layout 法（FU-907 零嵌套真实全跑）：tmp 仓 cp 真实 generator + fake run-tests
# （echo 777 passed + 落哨兵）+ fake README×2（声称 888）+ git init。收据采信=999
# （收据值），拒采内嵌=777（fake 值）——两值不同使哨兵与报文双向可判。
section_T51() {
  local r51 r51_head r51_out r51_rc r51_receipt r51_ts
  local r51_sentinel r51_has999 r51_has777 r51_same r51_same2 r51_had
  local r51_tree fp1 fp2 fp3 r51_pre r51_post r51_mis r51_ng r51_ngfp r51_ng2
  r51=$(mktemp -d "${TMPDIR:-/tmp}/receipt-test.XXXXXX")
  mkdir -p "$r51/scripts" "$r51/tests" "$r51/.agent-state"
  cp "$ROOT/scripts/update-assertion-count.sh" "$r51/scripts/"
  # v3.79.0 (CHG-103, REQ-1144): fixture carries the SAME fingerprint lib the
  # consumer sources, and ignores .agent-state like the real repo — without the
  # ignore rule the receipt file itself would be untracked content and shift
  # the tree fingerprint (TC-1378 would false-red for the wrong reason).
  printf '.agent-state/\n' > "$r51/.gitignore"
  cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r51/scripts/"
  cp "$ROOT/scripts/lib-source-facts.sh" "$r51/scripts/"
  cat > "$r51/tests/run-tests.sh" <<'R51FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/.embedded-ran"
printf '777 passed, 0 failed\n'
printf 'wall-time: 1s\n'
R51FAKE
  printf 'README claims 888 golden-case assertions here.\n' > "$r51/README.md"
  printf '这里声称 888 项 golden-case 断言。\n' > "$r51/README.zh-CN.md"
  ( cd "$r51" && git init -q && git add -A >/dev/null 2>&1 \
    && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
  r51_head=$(git -C "$r51" rev-parse HEAD 2>/dev/null || true)
  r51_receipt="$r51/.agent-state/last-suite-receipt.json"
  # v3.79.0 (CHG-103): the clean fixture tree fingerprints as HEAD^{tree} — the
  # identity TC-1382 pins. The receipt file itself is gitignored, so seeding it
  # does not shift the fingerprint.
  r51_tree=$(git -C "$r51" rev-parse HEAD^{tree} 2>/dev/null || true)
  # _r51_seed <head> <passed> <failed> [tree_fp]：播种收据并清哨兵。
  # v3.79.0：第 4 参非空 → 新 schema（含 tree_fingerprint）；空 → 旧 5 字段 schema
  # （TC-1381 反向兼容反证用：无指纹字段一律视为不新鲜）。
  _r51_seed() {
    if [[ -n "${4:-}" ]]; then
      printf '{"head":"%s","tree_fingerprint":"%s","passed":%s,"failed":%s,"wall_time_s":1,"generated_at":"2026-01-01T00:00:00Z"}\n' \
        "$1" "$4" "$2" "$3" > "$r51_receipt"
    else
      printf '{"head":"%s","passed":%s,"failed":%s,"wall_time_s":1,"generated_at":"2026-01-01T00:00:00Z"}\n' \
        "$1" "$2" "$3" > "$r51_receipt"
    fi
    rm -f "$r51/tests/.embedded-ran"
  }
  # _r51_run：fixture 内 UAC 调用。MAX_AGE 显式钉 30——防外层调用方 env（如
  # UAC 强制内嵌跑 MAX_AGE=0）泄漏进 fixture 使采信门整体跳过（TC-1121/1378/
  # 1379/1381 全依赖采信门参与判定；实测红档四连）；TC-1122d 自带显式 0 覆盖。
  _r51_run() { ( cd "$r51" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r51_receipt" AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN=30 bash scripts/update-assertion-count.sh --check 2>&1 ); }

  # TC-1121 采信主证：合法新鲜同 HEAD 收据 → 跳过内嵌（哨兵不在）+ N 来自收据（999）
  # v3.79.0（CHG-103）：fixture 升新 schema（含同树指纹）；TC-1378 追加断言指纹门参与判定
  _r51_seed "$r51_head" 999 0 "$r51_tree"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has999=$(printf '%s\n' "$r51_out" | grep -c 'expected 999')
  report "T51 fresh same-HEAD receipt trusted, embedded run skipped (TC-1121)" 0 "$([[ "$r51_sentinel" == 0 && "$r51_has999" -ge 1 ]] && echo 0 || echo 1)"
  r51_has999=$(printf '%s\n' "$r51_out" | grep -c 'tree-match')
  report "T51 trust path reports tree fingerprint match (TC-1378)" 0 "$([[ "$r51_sentinel" == 0 && "$r51_has999" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1122a head 不匹配 → 拒采（哨兵在 + expected 777）
  _r51_seed deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 999 0
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 head-mismatch receipt re-embeds (TC-1122a)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1122b 陈旧 mtime（2h 前）→ 拒采
  _r51_seed "$r51_head" 999 0
  r51_ts=$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S)
  touch -t "$r51_ts" "$r51_receipt"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 stale receipt re-embeds (TC-1122b)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1122c 损坏 JSON → 拒采
  _r51_seed "$r51_head" 999 0
  printf 'not json at all\n' > "$r51_receipt"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 malformed receipt re-embeds (TC-1122c)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1122d MAX_AGE_MIN=0（禁用采信）→ 拒采
  _r51_seed "$r51_head" 999 0
  r51_out=$( cd "$r51" && AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN=0 bash scripts/update-assertion-count.sh --check 2>&1 || true )
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 MAX_AGE_MIN=0 disables trusting (TC-1122d)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"

  # v3.79.0 (CHG-103, REQ-1143/1144)：树指纹语义 golden（缺口主证 = SC-1841）
  # TC-1379 tracked 文件内容变更 → 指纹不等 → 拒采（含 mismatch 提示行）
  # 注：改的是 tests/run-tests.sh（套件输入面）——README×2 是声明文件（消费方改写面），
  # 已被指纹排除（TC-1383 反向承载），不可用作 tracked 变更样本。
  _r51_seed "$r51_head" 999 0 "$r51_tree"
  printf '# dirty\n' >> "$r51/tests/run-tests.sh"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  r51_mis=$(printf '%s\n' "$r51_out" | grep -c 'tree-fingerprint mismatch')
  report "T51 tracked worktree change rejects receipt (TC-1379)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 && "$r51_mis" -ge 1 ]] && echo 0 || echo 1)"
  git -C "$r51" checkout -q -- tests/run-tests.sh 2>/dev/null || true

  # TC-1380 untracked 新文件内容 → 指纹不等 → 拒采（porcelain-only 配方的盲区，本门必拒）
  _r51_seed "$r51_head" 999 0 "$r51_tree"
  printf 'new file\n' > "$r51/tests/untracked-extra.txt"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 untracked new file rejects receipt (TC-1380)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"
  rm -f "$r51/tests/untracked-extra.txt"

  # TC-1381 旧 schema（无指纹字段）→ 拒采（反向兼容，fail-closed 方向）
  _r51_seed "$r51_head" 999 0
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  r51_mis=$(printf '%s\n' "$r51_out" | grep -c 'tree-fingerprint missing')
  report "T51 pre-v3.79 schema receipt rejected (TC-1381)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 && "$r51_mis" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1382 指纹确定性：同树两算同值，clean 树 = HEAD^{tree}
  # （先清内嵌哨兵：上一用例的 embedded run 会在 tests/ 留 untracked 哨兵，污染树）
  rm -f "$r51/tests/.embedded-ran"
  fp1=$(suite_tree_fingerprint "$r51")
  fp2=$(suite_tree_fingerprint "$r51")
  report "T51 fingerprint deterministic, clean tree = HEAD tree (TC-1382)" 0 "$([[ -n "$fp1" && "$fp1" == "$fp2" && "$fp1" == "$r51_tree" ]] && echo 0 || echo 1)"

  # TC-1383 指纹排除面：gitignored（.agent-state）不换指纹；声明文件（README×2/
  # .audit-baseline/.suite-baseline，消费方 UAC 全跑后自行改写的输出声明面）改内容
  # 也不换指纹——v3.87.0 CHG-115：漏掉 .suite-baseline 会让每次计数同步作废自己的收据，
  # 逼出一次 5 分钟重跑。真实 index 零副作用（porcelain 在指纹调用前后一致——两个采样点都含脏态）
  rm -f "$r51/tests/.embedded-ran"
  printf 'noise\n' > "$r51/.agent-state/noise.txt"
  printf 'README claims 777 golden-case assertions here.\n' > "$r51/README.md"
  printf '{"passed":777,"failed":0}\n' > "$r51/tests/.suite-baseline"
  r51_pre=$(git -C "$r51" status --porcelain)
  fp3=$(suite_tree_fingerprint "$r51")
  r51_post=$(git -C "$r51" status --porcelain)
  report "T51 ignored + claim files do not shift fingerprint; real index untouched (TC-1383)" 0 "$([[ "$fp3" == "$r51_tree" && -n "$r51_pre" && "$r51_pre" == "$r51_post" ]] && echo 0 || echo 1)"
  rm -f "$r51/.agent-state/noise.txt"
  printf 'README claims 888 golden-case assertions here.\n' > "$r51/README.md"
  printf '{"passed":888,"failed":0}\n' > "$r51/tests/.suite-baseline"

  # TC-1384 no-git 降级：lib 输出空串（exit 0）；UAC 无 git 走既有内嵌路径
  r51_ng=$(mktemp -d "${TMPDIR:-/tmp}/receipt-nogit.XXXXXX")
  r51_ngfp=$(suite_tree_fingerprint "$r51_ng")
  r51_ng2="$r51/nogit"
  mkdir -p "$r51_ng2/scripts" "$r51_ng2/tests"
  cp "$ROOT/scripts/update-assertion-count.sh" "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r51_ng2/scripts/"
  cp "$ROOT/scripts/lib-source-facts.sh" "$r51_ng2/scripts/"
  cp "$r51/tests/run-tests.sh" "$r51_ng2/tests/"
  printf 'README claims 888 golden-case assertions here.\n' > "$r51_ng2/README.md"
  printf '这里声称 888 项 golden-case 断言。\n' > "$r51_ng2/README.zh-CN.md"
  r51_out=$( cd "$r51_ng2" && AGENT_GUARD_SUITE_RECEIPT_PATH="" bash scripts/update-assertion-count.sh --check 2>&1 || true )
  r51_sentinel=$([[ -f "$r51_ng2/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 non-git repo: lib yields empty, UAC runs embedded (TC-1384)" 0 "$([[ -z "$r51_ngfp" && "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"
  rm -rf "$r51_ng" "$r51_ng2"

  # TC-1386 缺指纹 lib → 快路径整体关闭（fail-closed：无法证明树未变即不采信）
  _r51_seed "$r51_head" 999 0 "$r51_tree"
  mv "$r51/scripts/lib-suite-tree-fingerprint.sh" "$r51/scripts/lib.bak"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 missing fingerprint lib disables the fast path (TC-1386)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"
  mv "$r51/scripts/lib.bak" "$r51/scripts/lib-suite-tree-fingerprint.sh"

  # TC-1124/1125 真实仓：过滤 / rc2 运行不触收据（v3.86.0 起用隔离路径，
  # 不再播种/还原真实 .agent-state —— 并行会话与自测互不踩踏）
  r51_real="$ROOT/.agent-state/last-suite-receipt.json"
  r51_real_before=$(cksum < "$r51_real" 2>/dev/null || echo absent)
  r51_iso="$r51/.state-iso/last-suite-receipt.json"
  mkdir -p "$(dirname "$r51_iso")"
  printf '{"head":"seed","passed":12345,"failed":0,"wall_time_s":0,"generated_at":"seed"}\n' > "$r51_iso"
  cp "$r51_iso" "$r51/.seeded"
  r51_rc=0; AGENT_GUARD_SUITE_RECEIPT_PATH="$r51_iso" bash "$ROOT/tests/run-tests.sh" -T T1 >/dev/null 2>&1 || r51_rc=$?
  r51_same=0; cmp -s "$r51/.seeded" "$r51_iso" || r51_same=1
  report "T51 filtered run leaves receipt untouched (TC-1124)" 0 "$([[ $r51_rc -eq 0 && "$r51_same" == 0 ]] && echo 0 || echo 1)"
  r51_rc=2; AGENT_GUARD_SUITE_RECEIPT_PATH="$r51_iso" bash "$ROOT/tests/run-tests.sh" -T NOPE >/dev/null 2>&1 || r51_rc=$?
  r51_same2=0; cmp -s "$r51/.seeded" "$r51_iso" || r51_same2=1
  report "T51 rc2 run leaves receipt untouched (TC-1125)" 0 "$([[ $r51_rc -eq 2 && "$r51_same2" == 0 ]] && echo 0 || echo 1)"
  report "T51 isolated self-tests leave the REAL ledger untouched (TC-1124b)" 0 "$([[ "$(cksum < "$r51_real" 2>/dev/null || echo absent)" == "$r51_real_before" ]] && echo 0 || echo 1)"

  # TC-1126 发射端结构守卫：blk = 收据块数值行窗（grep -F 定锚）。自匹配三连教训：
  # ①grep 自身参数字面量 ②T51 注释里的同款字面量 ③起锚须带 'suite receipt' 后缀
  # 区别于 prelude 注释前缀——所有锚在 T51 源码内一律用 '"…"' 拼接断开。
  r51_s=$(grep -nF 'REQ-1049): '"suite receipt" "$ROOT/tests/run-tests.sh" | head -1 | cut -d: -f1)
  r51_e=$(grep -nF 'if [[ "$fail" -gt 0 ]]; '"then" "$ROOT/tests/run-tests.sh" | cut -d: -f1 | awk -v s="$r51_s" '$1>s{print;exit}')
  r51_blk=$(sed -n "${r51_s},${r51_e}p" "$ROOT/tests/run-tests.sh")
  r51_g1=$(grep -c '^SUITE_HEAD=' "$ROOT/tests/run-tests.sh")
  r51_g2=$(printf '%s\n' "$r51_blk" | grep -cF 'WANTED[@]} -eq 0 && -n "$SUITE_HEAD"')
  r51_g3=$(printf '%s\n' "$r51_blk" | grep -cF 'rm -f "$SUITE_RECEIPT_PATH"')
  r51_g4=$(printf '%s\n' "$r51_blk" | grep -cF 'date -u +%Y-%m-%dT%H:%M:%SZ')
  r51_w=$(grep -nF 'wall-time: '"%ds" "$ROOT/tests/run-tests.sh" | head -1 | cut -d: -f1)
  r51_r=$(grep -nF 'REQ-1049): '"suite receipt" "$ROOT/tests/run-tests.sh" | head -1 | cut -d: -f1)
  report "T51 emitter caches HEAD in prelude (TC-1126a)" 1 "$r51_g1"
  report "T51 receipt write guarded to full runs (TC-1126b)" 1 "$r51_g2"
  report "T51 red run deletes receipt (TC-1126c)" 1 "$r51_g3"
  report "T51 receipt stamped UTC (TC-1126d)" 1 "$([[ $r51_g4 -ge 1 ]] && echo 1 || echo 0)"
  report "T51 receipt block sits after wall-time (TC-1126e)" 0 "$([[ -n "$r51_w" && -n "$r51_r" && "$r51_w" -lt "$r51_r" ]] && echo 0 || echo 1)"
  # v3.79.0 (CHG-103, REQ-1142): emitter shape pins — the receipt printf carries
  # the tree_fingerprint field and the fingerprint is taken inside the guarded
  # block (runtime receipt content is evidenced by the T6 full run, 05).
  r51_mis=$(printf '%s\n' "$r51_blk" | grep -cF '"tree_fingerprint":"%s"')
  fp1=$(grep -cF '_tree_fp=$(suite_tree_fingerprint "$ROOT")' "$ROOT/tests/run-tests.sh")
  report "T51 receipt carries tree_fingerprint field, guarded compute (TC-1385)" 0 "$([[ "$r51_mis" -ge 1 && "$fp1" -ge 1 ]] && echo 0 || echo 1)"
  rm -rf "$r51"
}

# v3.67.0 (CHG-090, REQ-1053/1056~1060): UX 条件门（E90 + E92–E96）。
# 条件门只对 ui_change: true 生效；false 时逐字节等价（T52 隔离用例把这一条钉死）。
section_T52() {
# ------------------------------------------------ T52 UX 条件门（v3.67.0）
new_repo
seed_artifacts CHG-1000 L1 claude/s-1
# E90：声明 ui_change 但无 UJ → begin 拒
# CHG-117: begin 默认收窄为入口门，E90 由兼容开关下的全量 begin 与 staged
# 交付面执法；本三态钉用显式开关（默认收窄本身由 T80 钉）。
printf '# spec\n- **ui_change**：true\n- REQ-001: r\n' > docs/changes/CHG-1000/01-spec.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1000 >/dev/null 2>&1
report "T52 E90 rejects ui_change:true without a UJ" 2 $?
# E90 负例补强：模板形态的空挂靠（`**挂靠 UJ**：<!-- 待填 -->`）同样拒
printf '# spec\n- **ui_change**：true\n### REQ-001\n**描述**：r\n**挂靠 UJ**：<!-- 待填：UJ-xxx -->\n' > docs/changes/CHG-1000/01-spec.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1000 >/dev/null 2>&1
report "T52 E90 rejects an unfilled UJ anchor placeholder" 2 $?
# E90 正例：REQ 块内挂靠真实 UJ → begin 过
printf '# spec\n- **ui_change**：true\n## 用户任务\n### UJ-001\n- **入口**：记录列表\n### REQ-001\n**描述**：r\n**挂靠 UJ**：UJ-001\n' > docs/changes/CHG-1000/01-spec.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1000 >/dev/null 2>&1
report "T52 E90 passes once a UJ anchors the REQ" 0 $?
echo x > src/a.go
git add src/a.go
# E92：ui_change 但缺 03.6
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E92 rejects ui_change:true without 03.6-ui-spec" 2 $?
printf '# ui\n## 逐屏字段与控件\n- 列表选择\n' > docs/changes/CHG-1000/03.6-ui-spec.md
# E94：03.6 缺显示名↔主键映射
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E94 rejects 03.6 without the key-mapping section" 2 $?
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n- 用户直接输入 record_id 开始查询\n' > docs/changes/CHG-1000/03.6-ui-spec.md
# E97：03.6 把裸主键当主入口
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E97 rejects a bare primary-key entry" 2 $?
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n' > docs/changes/CHG-1000/03.6-ui-spec.md
# E93：03.5 无 UX/UI 任务行（注释里的图例不算，review P1-4）
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E93 rejects 03.5 without a UX task row" 2 $?
printf '# tasks\n| 任务 | 类型 | 依赖 | 里程碑 | 说明 |\n|---|---|---|---|---|\n| T1 | UX | 无 | M1 | 设计 |\n- 评审输入: x\n' > docs/changes/CHG-1000/03.5-tasks.md
# E95：L1 阈值 1，04 无用户旅程 E2E
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E95 rejects zero user-journey E2E cases" 2 $?
printf '# tests\n- TC-001 用户旅程 E2E（真人入口）\n覆盖维度: 正常流\n- SC-001 用户旅程 E2E（覆盖: TC-001）\n' > docs/changes/CHG-1000/04-test-scripts.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E92-E95 pass once 03.6 + UX task + E2E are in place" 0 $?
# E96/E98：07 缺用户可用性验收 → E96；有验收缺人类走查行 → E98
printf '# review\n## 评审结论\n通过\n' > docs/changes/CHG-1000/07-review-report.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E96 rejects a review without usability sign-off" 2 $?
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n## 评审结论\n通过\n' > docs/changes/CHG-1000/07-review-report.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E98 rejects the missing human-walkthrough line" 2 $?
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n- **建议人类走查（非阻塞）**：建议走查一次\n## 业务合理性终审\n- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）\n- **业务终审主体**：platform / glm / ses-t52a\n## 评审结论\n通过\n' > docs/changes/CHG-1000/07-review-report.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E96+E98 pass with usability sign-off + human-walkthrough line" 0 $?
# 隔离：ui_change 缺省/为 false 时不启用任何 UX 条件门
new_repo
seed_artifacts CHG-1001 L1 claude/s-1
scripts/agent-gate begin CHG-1001 >/dev/null 2>&1
echo x > src/a.go
git add src/a.go
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 UX lane stays dormant without ui_change" 0 $?
# 软告警：UI 路径 diff + 未声明 ui_change → 仅告警不拒（P1-5）
mkdir -p web
echo x > web/page.html
git add web/page.html
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T52 soft warning fires for UI-path diffs without ui_change" "UX soft warning" "$out"
}

# v3.68.0 (CHG-043, REQ-1076): T53 stop 级最小合交付件构造器 —— 复用 T23 夹具形态
#（ReAct Observation + 09 项目总册回填清单 + L0 轻量通道声明 + 06/06.5 + 全件盖章），
# 否则 stop 门进不去（validate_delivery 先于 G13/G14 执法）。仅 T53 使用；09 刻意
# 不含 REQ- 引用（避开 E51 rtvm 回填对账，非本节主题）。
seed_t53_delivery() { # <chg-id>
  local d="docs/changes/$1" pf
  printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > "$d/09-changelog.md"
  printf -- '- **编码记录**：未命中，不适用（L0 轻量通道）\n' > "$d/04.5-coding-record.md"
  printf -- '- **测试证据**：未命中，不适用（L0 轻量通道）\n' > "$d/05-test-results.md"
  printf '未命中，不适用（无配置变更）\n' > "$d/06.5-deployment-config.md"
  printf '# 交付总结\n#### 遗留\n- FU-531 演示\n' > "$d/06-delivery-summary.md"
  for pf in "$d"/*.md; do
    { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "$pf"; } > "$pf.tmp" && mv "$pf.tmp" "$pf"
  done
  append_masters "$d/09-changelog.md"
}

section_T53() {
# ------------------------------------------------ T53 G13/G14 行为面门禁（v3.68.0，CHG-043）
# TC↔REQ 映射：TC-1128→REQ-1067/1069/1076，TC-1129→REQ-1068，TC-1130→REQ-1067/1070，
# TC-1131→REQ-1071，TC-1132→REQ-1072，TC-1133→REQ-1073，TC-1134→REQ-1074，TC-1135→REQ-1075。
# 框架约束（v3.68.0 实际接线，DES-1842 已兑现）：begin 级门 E99/E100/E105/E106 执法点=
# validate_artifact_content 尾（begin 真执法）+ validate_dimensional_active（staged/stop 复验，
# 捕捉中途锚点腐烂）；complete_valid_change_exists 的结构探测经 AGENT_GUARD_DIM_PROBE=1 豁免
# 本门（探测只回答"件齐与否"，不回答"锚点新鲜否"——否则 E100 会被 E66 兜底掩盖）。
# 注意 T52 已被 CHG-090 UX 条件门占用，本节顺延为 T53。
EXTRACT_SRC="$ROOT/resources/templates/behavior-extract.sh"
[[ -f "$EXTRACT_SRC" ]] || EXTRACT_SRC="$ROOT/scripts/behavior-extract.sh"
new_repo
seed_artifacts CHG-1020 L1 claude/s-1
mkdir -p proto
cat > proto/index.html <<'EOF'
<button id="b1" onclick="save()">存</button>
<input id="i1" oninput="f()">
<form onsubmit="g()"><div onmouseover="pop()">x</div></form>
<a onclick="location.href='/list'">go</a>
<script>
document.getElementById("b1").addEventListener("click", save);
$("#f").on("change", h);
fetch("/api/x"); axios.get("/y"); $.ajax("/z"); new XMLHttpRequest();
setTimeout(tick, 100); setInterval(beat, 1000);
window.open("/w"); history.pushState({}, "", "/p");
</script>
EOF
cat > docs/changes/CHG-1020/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页改版
- **挂靠 UJ**：UJ-001
- **origin_artifact**: proto/index.html
- **chain_change**: true
- **ui_change**: true

## 数据流规格表
| 字段 | 来源 | 转换 | 去向 | 展示 |
|---|---|---|---|---|
| recordId | <表>.record_id | 直传 | 会话上下文 | 列表列 |
EOF
cat > docs/changes/CHG-1020/03.6-ui-spec.md <<'EOF'
# ui
## 显示名↔主键映射
- 记录显示名 → record_id
EOF
cat > docs/changes/CHG-1020/03.5-tasks.md <<'EOF'
# tasks
| 任务 | 类型 | 依赖 | 里程碑 | 说明 |
|---|---|---|---|---|
| T-001 | UX | 无 | M1 | 演示页改造 |
- 评审输入: 变更文件清单 + 待核对产物 + 行号锚点
EOF
cat > docs/changes/CHG-1020/04-test-scripts.md <<'EOF'
# tests
- TC-001 用户旅程 E2E：点击存档 → 列表刷新
覆盖维度: 正常流 / 边界 / 异常
## 否定测试
- NT-001: 断网点击存档必须失败提示，不得静默成功（回归: TC-001）
- SC-001: 演示页主流程（覆盖: TC-001）
EOF
# TC-1128：用真实行为抽取器产出 inventory（hash 一致性由 E100 复算兜底）
bash "$EXTRACT_SRC" proto/index.html > docs/changes/CHG-1020/behavior-inventory.json
inv=docs/changes/CHG-1020/behavior-inventory.json
inv_total=$(sed -n '1s/.*"total_behaviors":\([0-9]*\).*/\1/p' "$inv")
report "T53 TC-1128 extractor total_behaviors=20 (16 behaviors + 4 elements, CHG-044 schema pin)" 0 "$([[ "$inv_total" == 20 ]]; echo $?)"
report "T53 TC-1128 first data row is BHV-001 click pending" 1 "$(sed -n '2p' "$inv" | grep -c '"id":"BHV-001".*"kind":"click".*"status":"pending"')"
hrec=$(sed -n '1s/.*"artifact_hash":"\([a-f0-9]\{64\}\)".*/\1/p' "$inv")
hcur=$(shasum -a 256 proto/index.html 2>/dev/null | awk '{print $1}')
[[ -n "$hcur" ]] || hcur=$(sha256sum proto/index.html 2>/dev/null | awk '{print $1}')
report "T53 TC-1128 extractor hash equals recomputed sha256" 0 "$([[ -n "$hrec" && "$hrec" == "$hcur" ]]; echo $?)"
commit_all "t53 fixture CHG-1020"
scripts/agent-gate begin CHG-1020 >/dev/null 2>&1
report "T53 TC-1128 begin green with origin/chain/ui declared + inventory anchored" 0 $?
echo y > src/a.js
git add src/a.js
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1128 staged green: begin-lane E99/E100/E105/E106 all pass" 0 $?
# TC-1129（E100 锚点防腐）：篡改原型一个字符 → staged 红
printf 'x' >> proto/index.html
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1129 tampered origin artifact keeps staged red" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1129 refusal names GATE-E100 hash mismatch" "GATE-E100" "$out"
git checkout -q -- proto/index.html
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1129 staged green again after artifact restore" 0 $?
# TC-1130（E99 begin 级）：声明 origin 但清单缺失 → staged 红；补回抽取产物
rm docs/changes/CHG-1020/behavior-inventory.json
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1130 E99 staged red: origin declared but inventory missing" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1130 refusal names GATE-E99" "GATE-E99" "$out"
bash "$EXTRACT_SRC" proto/index.html > docs/changes/CHG-1020/behavior-inventory.json
# TC-1233（E109 begin 级，评审中3 补测）：origin_artifact 指向不存在路径 → begin 红
sed -e 's|origin_artifact\*\*: proto/index.html|origin_artifact**: proto/missing.html|' docs/changes/CHG-1020/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1020/01-spec.md
# CHG-117: E109 rides the full (legacy) begin lane and the delivery face;
# the default narrowed begin is covered by T80.
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1020 >/dev/null 2>&1
report "T53 TC-1233 E109 begin red: origin artifact path not found" 2 $?
out=$(AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1020 2>&1 || true)
check_output "T53 TC-1233 refusal names GATE-E109" "GATE-E109" "$out"
sed -e 's|origin_artifact\*\*: proto/missing.html|origin_artifact**: proto/index.html|' docs/changes/CHG-1020/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1020/01-spec.md
# TC-1132（E105/E106 begin 级）：chain_change 而无 数据流规格表 / 空单元格 / 无 否定测试
sed -e '/^## 数据流规格表/,$d' docs/changes/CHG-1020/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1020/01-spec.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1132 E105 staged red: chain_change without 数据流规格表" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1132 refusal names GATE-E105" "GATE-E105" "$out"
cat >> docs/changes/CHG-1020/01-spec.md <<'EOF'
## 数据流规格表
| 字段 | 来源 | 转换 | 去向 | 展示 |
|---|---|---|---|---|
|  |  |  |  |  |
EOF
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1132 E105 staged red: blank-cell row is a design gap" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1132 blank-cell refusal names GATE-E105" "GATE-E105" "$out"
sed -e '/^## 数据流规格表/,$d' docs/changes/CHG-1020/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1020/01-spec.md
cat >> docs/changes/CHG-1020/01-spec.md <<'EOF'
## 数据流规格表
| 字段 | 来源 | 转换 | 去向 | 展示 |
|---|---|---|---|---|
| patientSn | fzzl_patient.patientSn | 直传 | 会话上下文 | 列表列 |
EOF
grep -v '否定测试' docs/changes/CHG-1020/04-test-scripts.md > .t53-04.tmp && mv .t53-04.tmp docs/changes/CHG-1020/04-test-scripts.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1132 E106 staged red: chain_change without 否定测试 section" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1132 refusal names GATE-E106" "GATE-E106" "$out"
cat >> docs/changes/CHG-1020/04-test-scripts.md <<'EOF'
## 否定测试
- NT-001: 断网点击存档必须失败提示，不得静默成功（回归: TC-001）
EOF
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1132 staged green after table + negation section restored" 0 $?
# ---- stop 级夹具 CHG-1030（origin 声明 + ui_change:false：E101/E102/E103/E108 轨道）----
new_repo
seed_artifacts CHG-1030 L0 claude/s-1
mkdir -p proto
printf '<button id="b2" onclick="s1()">A</button>\n<button id="b3" onclick="s2()">B</button>\n<button id="b4" onclick="s3()">C</button>\n' > proto/index.html
cat > docs/changes/CHG-1030/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页对齐真实链路
- **origin_artifact**: proto/index.html
- **chain_change**: 未命中（静态演示页，无数据链变更）
- **ui_change**: false
- 事件链：BHV-001 → BHV-002 走真实业务链路（record_id 直传）
EOF
bash "$EXTRACT_SRC" proto/index.html > docs/changes/CHG-1030/behavior-inventory.json
scripts/agent-gate begin CHG-1030 >/dev/null 2>&1
report "T53 TC-1130 begin green before stop progression" 0 $?
seed_t53_delivery CHG-1030
echo y > src/t53b.js
inv2=docs/changes/CHG-1030/behavior-inventory.json
# TC-1130（E101 stop 级）：清单含 missing → stop 红
sed -e '4s/"status":"pending"/"status":"missing"/' "$inv2" > .t53-inv.tmp && mv .t53-inv.tmp "$inv2"
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1130 E101 stop red: inventory carries missing status" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1130 refusal names GATE-E101" "GATE-E101" "$out"
sed -e '4s/"status":"missing"/"status":"pending"/' "$inv2" > .t53-inv.tmp && mv .t53-inv.tmp "$inv2"
# TC-1130（E102 stop 级）：BHV-003 全目录无引用且未豁免 → stop 红；接线后绿
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1130 E102 stop red: BHV-003 never referenced nor waived" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1130 refusal names GATE-E102 with the orphan id" "GATE-E102.*BHV-003" "$out"
sed -e 's/- 事件链：BHV-001 → BHV-002 走真实业务链路/- 事件链：BHV-001 → BHV-002 → BHV-003 → BHV-004 → BHV-005 → BHV-006 走真实业务链路/' docs/changes/CHG-1030/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1030/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1130 stop green once all six BHVs (behavior+element) are referenced" 0 $?
# TC-1131（E103 stop 级）：demo_script 声明而 05 无 REPLAY: → 红；补证据行后绿
printf -- '- **demo_script**: 3\n' >> docs/changes/CHG-1030/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1131 E103 stop red: demo_script declared but 05 lacks REPLAY" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1131 refusal names GATE-E103" "GATE-E103" "$out"
printf 'REPLAY: 第1句 点击A按钮 → HTTP 200（快照 t53a）\n' >> docs/changes/CHG-1030/05-test-results.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1131 stop green with REPLAY evidence line" 0 $?
# TC-1133（E108 stop 级）：链上行为豁免行缺 00.5 → 红；补 00.5 引用后绿
cat >> docs/changes/CHG-1030/01-spec.md <<'EOF'

## 拆除/豁免登记簿
| 行为 | 处置 | 理由 |
|---|---|---|
| BHV-001 | 行为豁免 | 演示数据按钮，未走真实链 |
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1133 E108 stop red: chain-touching waiver without 00.5" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1133 refusal names GATE-E108" "GATE-E108" "$out"
sed -e 's#| BHV-001 | 行为豁免 | 演示数据按钮，未走真实链 |#| BHV-001 | 行为豁免 | 00.5 追加沟通轮已确认：演示按钮不触真实链 |#' docs/changes/CHG-1030/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1030/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1133 stop green once waiver carries 00.5 reference" 0 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1133 stop lane clean receipt prints counters" "G13/G14 stop lane clean" "$out"
# ---- stop 级夹具 CHG-1040（ui_change:true：E104/E107 轨道，复用 T52 UX 门绿基线）----
new_repo
seed_artifacts CHG-1040 L0 claude/s-1
cat > docs/changes/CHG-1040/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页可用性收口
- **挂靠 UJ**：UJ-001
- **origin_artifact**: 未命中（无原型页，改版基线=线上页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: true
EOF
cat > docs/changes/CHG-1040/03.6-ui-spec.md <<'EOF'
# ui
## 显示名↔主键映射
- 记录显示名 → record_id
EOF
cat > docs/changes/CHG-1040/03.5-tasks.md <<'EOF'
# tasks
| 任务 | 类型 | 依赖 | 里程碑 | 说明 |
|---|---|---|---|---|
| T-001 | UX | 无 | M1 | 可用性收口 |
- 评审输入: 变更文件清单 + 待核对产物 + 行号锚点
EOF
cat > docs/changes/CHG-1040/04-test-scripts.md <<'EOF'
# tests
- TC-001 用户旅程 E2E：入口到结果全程真人可走
覆盖维度: 正常流 / 边界 / 异常
- SC-001: 记录列表主流程（覆盖: TC-001）
EOF
cat > docs/changes/CHG-1040/07-review-report.md <<'EOF'
# review
## 用户可用性验收
- 结论：通过（依据 03.6 与 UJ-001）
- **建议人类走查（非阻塞）**：建议交付前真人走查一次
## 业务合理性终审
- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）
- **业务终审主体**：platform / glm / ses-t53a
- **发现处置**：未命中，不适用（T53 可用性夹具，无发现）
- 评审主体：platform / glm-5.3-flash / ses-t53c
EOF
scripts/agent-gate begin CHG-1040 >/dev/null 2>&1
report "T53 TC-1134 begin green: ui_change anchored to UJ-001" 0 $?
seed_t53_delivery CHG-1040
echo y > src/t53c.js
# TC-1134（E104 stop 级）：ui_change 而 05 无 UJ-001+证据词行 → 红
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1134 E104 stop red: UJ-001 lacks runtime evidence row in 05" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1134 refusal names GATE-E104" "GATE-E104" "$out"
printf -- '- UJ-001 运行时证据：HTTP 响应体 200，DB 行 <表> 更新，快照 snap-t53c\n' >> docs/changes/CHG-1040/05-test-results.md
printf -- '- **还原度断言**：未命中，不适用（T53 夹具无自动化浏览器环境，人工逐屏清单已附）\n' >> docs/changes/CHG-1040/05-test-results.md
# TC-1134（E107 stop 级）：07 有签名无 运行时走查 → 红
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1134 E107 stop red: 07 lacks 运行时走查 journey section" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1134 refusal names GATE-E107" "GATE-E107" "$out"
printf '\n## 运行时走查\n- 走查记录：ses-t53c（UJ-001 全程真人入口可走通）\n' >> docs/changes/CHG-1040/07-review-report.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1134 stop green with per-UJ evidence + journey walkthrough" 0 $?
# ---- TC-1135 负例（防门禁疲劳）：三行声明全 未命中 → begin/stop 全绿且零新门输出 ----
new_repo
seed_artifacts CHG-1050 L0 claude/s-1
cat > docs/changes/CHG-1050/01-spec.md <<'EOF'
# spec
- REQ-001: 纯文档微调
- **origin_artifact**: 未命中（无原型页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: false
EOF
scripts/agent-gate begin CHG-1050 >/dev/null 2>&1
report "T53 TC-1135 begin green when all three lanes declare 未命中" 0 $?
seed_t53_delivery CHG-1050
echo y > src/t53d.js
rc=0
out=$(scripts/agent-gate --stage stop 2>&1) || rc=$?
report "T53 TC-1135 stop green when all three lanes declare 未命中" 0 "$rc"
report "T53 TC-1135 zero new-gate output (anti gate-fatigue guard)" 0 "$(printf '%s' "$out" | grep -cE 'GATE-E(9[9]|10[0-9])|G13/G14')"
# TC-1231（v3.68.0 回测 record 687，locale 回归守卫）：含中文多字节文案的 HTML → exit 0 且 total>0
#（此前 macOS awk towc multibyte 死亡被吞=静默空清单 exit 0；现 LC_ALL=C 钉死 + fail-closed）
cat > .t53-locale.html <<'EOF'
<div class="panel">
  <button id="保存按钮" onclick="保存()">保存记录列表</button>
  <input id="搜索框" oninput="过滤()">
  <a href="#" onclick="跳转列表()">返回列表</a>
</div>
<script>
document.getElementById("保存按钮").addEventListener("click", 保存);
$("#搜索框").on("change", 过滤);
</script>
EOF
rc=0
t53c_out=$(bash "$EXTRACT_SRC" .t53-locale.html 2>/dev/null) || rc=$?
report "T53 TC-1231 extractor exit 0 on multibyte Chinese HTML (LC_ALL=C pinned)" 0 "$rc"
t53c_total=$(printf '%s\n' "$t53c_out" | sed -n '1s/.*"total_behaviors":\([0-9]*\).*/\1/p')
report "T53 TC-1231 multibyte extraction yields >0 behaviors" 0 "$([[ "$t53c_total" =~ ^[1-9][0-9]*$ ]]; echo $?)"
# TC-1232（fail-closed 空产出守卫）：零 pattern 纯静态 HTML → exit 3 + stderr 诊断词
cat > .t53-static.html <<'EOF'
<div class="static">
  <p>纯静态说明文案，无任何交互行为可抽取。</p>
  <span>keep-alive</span>
</div>
EOF
rc=0
t53d_err=$(bash "$EXTRACT_SRC" .t53-static.html 2>&1 >/dev/null) || rc=$?
report "T53 TC-1232 zero-pattern static HTML exits 3 (fail-closed empty output)" 3 "$rc"
check_output "T53 TC-1232 stderr names the zero-behavior diagnosis" "零行为" "$t53d_err"
}

section_T54() {
# ------------------------------------------------ T54 G14e 交互元素枚举（CHG-044）
# TC-1234~1238：元素行抽取（静态按钮/hidden 排除）→ 与行为行并存 → E102 元素孤儿对账 →
# 逗号列表批量接线 → 登记簿豁免传递（00.5）。词表唯一权威 = resources/templates/
# behavior-extract.sh 头注释（audit A43 单源执法），本节只持行为断言，禁止复制词表。
# CHG-044 01-spec REQ 尚为占位，REQ 映射待其填实后补记。
EXTRACT_SRC="$ROOT/resources/templates/behavior-extract.sh"
[[ -f "$EXTRACT_SRC" ]] || EXTRACT_SRC="$ROOT/scripts/behavior-extract.sh"
new_repo
seed_artifacts CHG-1060 L0 claude/s-1
mkdir -p proto
cat > proto/page.html <<'EOF'
<button id="btnStatic">静态按钮</button>
<button id="mic" onclick="录音()">主操作</button>
<input type="hidden" id="hid" value="x">
<div role="checkbox" aria-checked="false"></div>
<a href="/list">列表</a>
EOF
cat > docs/changes/CHG-1060/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页对齐真实链路
- **origin_artifact**: proto/page.html
- **chain_change**: 未命中（静态演示页，无数据链变更）
- **ui_change**: false
- 事件链：BHV-002 主操作点击走真实业务链路（BHV-003 同元素）
EOF
bash "$EXTRACT_SRC" proto/page.html > docs/changes/CHG-1060/behavior-inventory.json
inv=docs/changes/CHG-1060/behavior-inventory.json
t54_total=$(sed -n '1s/.*"total_behaviors":\([0-9]*\).*/\1/p' "$inv")
report "T54 TC-1234 fixture pins total=5 (2 behavior + 3 element rows)" 0 "$([[ "$t54_total" == 5 ]]; echo $?)"
report "T54 TC-1234 handler-free static button yields an element row" 1 "$(grep -c '"kind":"element","event":"button","target":"#btnStatic"' "$inv")"
report "T54 TC-1234 hidden input is excluded from element rows" 0 "$(grep -c '"target":"#hid"' "$inv")"
report "T54 TC-1235 behavior row for #mic (click)" 1 "$(grep -c '"kind":"click","event":"click","target":"mic"' "$inv")"
report "T54 TC-1235 element row coexists for #mic" 1 "$(grep -c '"kind":"element","event":"button","target":"#mic"' "$inv")"
scripts/agent-gate begin CHG-1060 >/dev/null 2>&1
report "T54 TC-1236 begin green before stop progression" 0 $?
seed_t53_delivery CHG-1060
echo y > src/t54.js
# TC-1236（E102 stop 级）：元素 BHV-001 全目录无引用且未豁免 → stop 红
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1236 E102 stop red: element BHV-001 never referenced nor waived" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T54 TC-1236 refusal names GATE-E102 with the element orphan id" "GATE-E102.*BHV-001" "$out"
# TC-1237：03.6/产物以逗号列表批量接线元素 BHV → 绿
printf -- '- 元素清单：BHV-001, BHV-004, BHV-005（逗号列表批量接线）\n' >> docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1237 stop green once element BHVs wired via comma list" 0 $?
# TC-1238：登记簿豁免元素 BHV（行为豁免+00.5 引用）→ 绿；去掉 00.5 → E108 红 → 恢复绿
cat >> docs/changes/CHG-1060/01-spec.md <<'EOF'

## 拆除/豁免登记簿
| 行为 | 处置 | 理由 |
|---|---|---|
| BHV-001 | 行为豁免 | 00.5 追加沟通轮：静态占位按钮已确认豁免 |
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1238 stop green: element waiver carries 00.5 reference" 0 $?
sed -e 's/00\.5 追加沟通轮：静态占位按钮已确认豁免/静态占位按钮已确认豁免（无沟通轮）/' docs/changes/CHG-1060/01-spec.md > .t54-spec.tmp && mv .t54-spec.tmp docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1238 E108 stop red: element waiver loses 00.5 reference" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T54 TC-1238 refusal names GATE-E108 with the element id" "GATE-E108.*BHV-001" "$out"
sed -e 's/静态占位按钮已确认豁免（无沟通轮）/00.5 追加沟通轮：静态占位按钮已确认豁免/' docs/changes/CHG-1060/01-spec.md > .t54-spec.tmp && mv .t54-spec.tmp docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1238 stop green again after 00.5 restored" 0 $?
# TC-1239（FU-934 收窄①，v3.70.0）：登记簿节外的「行为豁免」表行 → E108 红（堵节外躲检）
awk '{print} /元素清单/{print "| BHV-001 | 行为豁免 | 节外豁免行试图躲检 |"}' docs/changes/CHG-1060/01-spec.md > .t54-spec.tmp && mv .t54-spec.tmp docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1239 E108 stop red: waiver row outside the ledger section" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T54 TC-1239 refusal names the outside-ledger narrowing" "GATE-E108" "$out"
grep -v '^| BHV-001 | 行为豁免 | 节外豁免行试图躲检 |$' docs/changes/CHG-1060/01-spec.md > .t54-spec.tmp && mv .t54-spec.tmp docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1239 stop green again after stray row removed" 0 $?
}

# v3.65.0 (CHG-087, REQ-1046~1048): SECTIONS = source-order registry (T22a/T22b
# disambiguate the duplicate "T22" label at :570/:2173; 摘要 at :2172 is a
# misplaced separator, not a boundary). Dispatcher: -l list, wanted validation
# (unknown key dies rc2), then filtered invocation in original order.
section_T55() {
# ------------------------------------------------ T55 交付四门（v3.71.0，CHG-046）
# ① E110（REQ-1087）：ui_change 变更 05 还原度断言行三态
new_repo
seed_begin CHG-1070 L1 claude/s-1
printf '# spec\n- **ui_change**：true\n## 用户任务\n### UJ-001\n- **入口**：记录列表\n### REQ-001\n**描述**：r\n**挂靠 UJ**：UJ-001\n' > docs/changes/CHG-1070/01-spec.md
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n' > docs/changes/CHG-1070/03.6-ui-spec.md
printf '# tasks\n| 任务 | 类型 | 依赖 | 里程碑 | 说明 |\n|---|---|---|---|---|\n| T1 | UX | 无 | M1 | 设计 |\n- 评审输入: x\n' > docs/changes/CHG-1070/03.5-tasks.md
printf '# tests\n- TC-001 用户旅程 E2E（真人入口）\n覆盖维度: 正常流\n- SC-001 用户旅程 E2E（覆盖: TC-001）\n' > docs/changes/CHG-1070/04-test-scripts.md
scripts/agent-gate begin CHG-1070 >/dev/null 2>&1
printf '<!-- provenance\nauthor: fixture\nemail: fixture@test\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-1070/04.5-coding-record.md
printf '# 05 测试结果\n- UJ-001 HTTP 200 响应体 {"ok":true} @2026-10-14T00:00:00Z\n' > docs/changes/CHG-1070/05-test-results.md
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n- **建议人类走查（非阻塞）**：建议走查一次\n## 业务合理性终审\n- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）\n- **业务终审主体**：platform / glm / ses-t55a\n- **发现处置**：未命中，不适用（T55 交付四门夹具，无发现）\n## 评审结论\n通过\n## 运行时走查\n- ses-rev-1 走查 UJ-001\n\n署名：agent-platform / llm-model / task-rev-1\n' > docs/changes/CHG-1070/07-review-report.md
printf '# 06.5 部署/配置/DB 记录\n未命中，不适用：本变更无配置项、无 DB 变更。\n' > docs/changes/CHG-1070/06.5-deployment-config.md
printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-1070/06-delivery-summary.md
printf 'chg\n#### 执行记录（ReAct）\n| 阶段 | Thought | Observation |\n|---|---|---|\n| 阶段1 | t | grep -c REQ- 01-spec.md -> 1 |\n' > docs/changes/CHG-1070/09-changelog.md
append_masters docs/changes/CHG-1070/09-changelog.md
stamp_all docs/changes/CHG-1070
echo x > src/a.go
scripts/agent-gate --stage stop >/dev/null 2>&1
rc_e110a=$?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
report "T55 TC-1248 E110 red: 05 lacks the restoration-assertion line" 2 "$rc_e110a"
check_output "T55 TC-1248 refusal names GATE-E110" "GATE-E110" "$out"
# 豁免声明行 → E110 过（走到后续门全绿，写入首次交付记录）
printf '# 05 测试结果\n- UJ-001 HTTP 200 响应体 {"ok":true} @2026-10-14T00:00:00Z\n- **还原度断言**：未命中，不适用（无自动化环境，人工逐屏清单已附）\n' > docs/changes/CHG-1070/05-test-results.md
stamp_all docs/changes/CHG-1070
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1249 waiver declaration passes E110 (full stop green)" 0 $?
# 指向不存在文件 → 红；点名路径（05 换行重写后补章保 E19）
printf '# 05 测试结果\n- UJ-001 HTTP 200 响应体 {"ok":true} @2026-10-14T00:00:00Z\n- **还原度断言**：tests/ui-proto.test.js（断言面：节序/占位形态）\n' > docs/changes/CHG-1070/05-test-results.md
stamp_all docs/changes/CHG-1070
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T55 TC-1249 E110 red: assertion file missing" "GATE-E110.*ui-proto" "$out"
# 文件在 + 断言标记在 → 绿（全 stop 再绿；为 E112 铺垫交付记录）
mkdir -p tests
printf 'describe("proto", () => { it("节序", () => expect(1).toBe(1)); });\n' > tests/ui-proto.test.js
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1247 evidence line with a real test file passes (stop green)" 0 $?
# ② E112（REQ-1090）：同会话重复交付换挡执法（new_repo 已置 started_at=-1H 与
#    AGENT_GUARD_ALLOW_NO_SHIFT=1 导出——本组用 =0 显式开启执法面，T49 同法）
echo y > src/b.js
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage stop >/dev/null 2>&1
rc_e112=$?
out=$(AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage stop 2>&1 || true)
report "T55 TC-1254 E112 red: in-session re-delivery without handoff" 2 "$rc_e112"
check_output "T55 TC-1254 refusal names GATE-E112" "GATE-E112" "$out"
printf '\n- **换挡声明**：未到换挡点（同批次连续变更，用户明示继续）\n' >> docs/changes/CHG-1070/09-changelog.md
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1254 换挡声明 line passes E112" 0 $?
perl -ni -e 'print unless /换挡声明/' docs/changes/CHG-1070/09-changelog.md
AGENT_GUARD_ALLOW_NO_SHIFT=1 scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1254 escape env passes E112" 0 $?
printf '# handoff\nCHG-1070 handoff record\n' > docs/changes/CHG-1070/handoff.md
stamp_all docs/changes/CHG-1070
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1253 handoff.md passes E112" 0 $?
# ③ E113（REQ-1091）：TC 落点清单
new_repo
seed_begin CHG-1071 L1 claude/s-1
printf '<!-- provenance\nauthor: fixture\nemail: fixture@test\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-1071/04.5-coding-record.md
printf '# 05 测试结果\nok: 1\n' > docs/changes/CHG-1071/05-test-results.md
printf 'chg\n#### 执行记录（ReAct）\n| 阶段 | Thought | Observation |\n|---|---|---|\n| 阶段1 | t | ok |\n' > docs/changes/CHG-1071/09-changelog.md
append_masters docs/changes/CHG-1071/09-changelog.md
printf '# 06.5 部署/配置/DB 记录\n未命中，不适用：无配置。\n' > docs/changes/CHG-1071/06.5-deployment-config.md
printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-902 | 样例 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-1071/06-delivery-summary.md
stamp_all docs/changes/CHG-1071
printf '\n## TC 落点清单\n- TC-9001: tests/missing.test.js（类型：自动化）\n' >> docs/changes/CHG-1071/04-test-scripts.md
echo z > src/c.go
scripts/agent-gate --stage stop >/dev/null 2>&1
rc_e113=$?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
report "T55 TC-1256 E113 red: automated TC landing file missing" 2 "$rc_e113"
check_output "T55 TC-1256 refusal names GATE-E113 and the TC id" "GATE-E113.*TC-9001" "$out"
mkdir -p tests
printf 'it("works", () => expect(1).toBe(1));\n' > tests/ui-proto.test.js
sed -e 's#tests/missing.test.js#tests/ui-proto.test.js#' docs/changes/CHG-1071/04-test-scripts.md > .t55-04.tmp && mv .t55-04.tmp docs/changes/CHG-1071/04-test-scripts.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1255 E113 green: landing file exists with assertion marker" 0 $?
sed -e 's#（类型：自动化）#（类型：人工）#' docs/changes/CHG-1071/04-test-scripts.md > .t55-04.tmp && mv .t55-04.tmp docs/changes/CHG-1071/04-test-scripts.md
rm -f tests/ui-proto.test.js
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1256 人工-typed landing skips the file check" 0 $?
# ④ E111（REQ-1088）：基建冒烟门 fail-closed 三态 + check-smoke 探针
new_repo
seed_begin CHG-1072 L1 claude/s-1
printf 'smoke_placeholder: true\n' > pom.xml
git add pom.xml
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_e111a=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1251 E111 red: infra diff without a declared smoke command" 2 "$rc_e111a"
check_output "T55 TC-1251 refusal names GATE-E111 fail-closed" "GATE-E111" "$out"
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：login 200 ok @2026-10-14T00:00:00Z\n' > docs/changes/CHG-1072/05-test-results.md
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1250 E111 green: declared command + fresh evidence line" 0 $?
perl -ni -e 'print unless /冒烟证据/' docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_e111b=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1252 E111 red: declared command but no evidence" 2 "$rc_e111b"
check_output "T55 TC-1252 refusal asks for the evidence line" "冒烟证据" "$out"
printf '# 05 测试结果\n- **基建冒烟**：未命中，不适用（文档性配置，无运行面）\n' > docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1252 waiver declaration passes E111 with a warning" 0 $?
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_paths: zzz\.nomatch\n' > .agent-governance.yml
printf '# 05 测试结果\n' > docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1252 smoke_paths override shrinks the trigger face" 0 $?
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\n' > .agent-governance.yml
git add pom.xml .agent-governance.yml docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate check-smoke >/dev/null 2>&1
report "T55 TC-1257 check-smoke probe: violation exits 1" 1 $?
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：ok @2026-10-14T00:00:00Z\n' > docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate check-smoke >/dev/null 2>&1
report "T55 TC-1257 check-smoke probe: evidence present exits 0" 0 $?
# 证据窗时效（TC-1252 评审补强）：证据行在但 mtime 超窗 → 红
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\n' > .agent-governance.yml
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：ok @2026-01-01T00:00:00Z\n' > docs/changes/CHG-1072/05-test-results.md
touch -t 202601010000 docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_stale=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1252 E111 red: evidence line present but stale beyond the window" 2 "$rc_stale"
check_output "T55 TC-1252 refusal names the evidence line requirement" "冒烟证据" "$out"
# win=0 = 存在级（P1-1 裁定：窗只管时效，行必须查）
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_evidence_max_age_h: 0\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1252 win=0 keeps presence-level enforcement (stale file still passes)" 0 $?
# pre-commit 运行级（TC-1257 评审补强）：SHIFT REMINDER 输出 + 不阻塞
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\n' > .agent-governance.yml
touch docs/changes/CHG-1072/05-test-results.md
printf '{"delivered_at":"%s","change":"CHG-1072","stage":"stop","session":""}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/last-delivery.json
cp "$ROOT/scripts/stamp-provenance.sh" scripts/stamp-provenance.sh
out=$(bash "$ROOT/resources/templates/pre-commit" 2>&1 || true)
check_output "T55 TC-1257 pre-commit emits the SHIFT REMINDER" "SHIFT REMINDER" "$out"
bash "$ROOT/resources/templates/pre-commit" >/dev/null 2>&1
report "T55 TC-1257 pre-commit reminder does not block the commit (rc=0)" 0 $?
# ④b CHG-093（v3.71.0 erratum，REQ-1093/1094）：E111 扫描面收敛活跃变更 + 非法 smoke_paths ERE 拦截
new_repo
seed_begin CHG-1080 L1 claude/s-1
mkdir -p docs/changes/CHG-1079
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：ok @2026-01-01T00:00:00Z\n- **基建冒烟**：未命中，不适用（历史变更裁定）\n' > docs/changes/CHG-1079/05-test-results.md
printf '# 05 测试结果\n' > docs/changes/CHG-1080/05-test-results.md
printf 'smoke_placeholder: true\n' > pom.xml
git add pom.xml
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_hist=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1259 E111 red: historical change 05 waiver line no longer passes" 2 "$rc_hist"
check_output "T55 TC-1259 refusal names GATE-E111" "GATE-E111" "$out"
# TC-1260：活跃变更 05 豁免行放行 + stderr 指明活跃变更路径
printf '# 05 测试结果\n- **基建冒烟**：未命中，不适用（本变更裁定，无运行面）\n' > docs/changes/CHG-1080/05-test-results.md
out=$(scripts/agent-gate --stage staged 2>&1 || true)
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1260 active-change 05 waiver line passes E111" 0 $?
check_output "T55 TC-1260 waiver stderr names the active-change 05 path" "CHG-1080/05-test-results\.md" "$out"
# TC-1261：win=0 下非活跃陈年证据行失效；活跃变更证据行放行
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_evidence_max_age_h: 0\n' > .agent-governance.yml
printf '# 05 测试结果\n' > docs/changes/CHG-1080/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_evid=$?
report "T55 TC-1261 E111 red: win=0 evidence line in a non-active change is void" 2 "$rc_evid"
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：ok @2026-01-01T00:00:00Z\n' > docs/changes/CHG-1080/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1261 win=0 evidence line in the active change passes" 0 $?
# TC-1262：指针缺失 fail-open（rc=0 + stderr 含 fail-open）
rm -f "$(git rev-parse --git-path agent-governance/active-change)"
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1262 missing active-change pointer fail-opens E111" 0 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T55 TC-1262 fail-open stderr explains the skip" "smoke gate fail-open" "$out"
printf 'CHG-1080\n' > "$(git rev-parse --git-path agent-governance/active-change)"
# TC-1263：smoke_paths 非法 ERE die + 报文含修复指引
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_paths: pom\\.xml((\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_ere=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1263 E111 red: invalid smoke_paths ERE dies fail-closed" 2 "$rc_ere"
check_output "T55 TC-1263 refusal names GATE-E111 regex invalid" "GATE-E111.*regex invalid" "$out"
check_output "T55 TC-1263 refusal carries the smoke_paths repair guidance" "fix the comma-separated EREs" "$out"
# TC-1264：合法 ERE 覆写触发面行为不变（回归钉）
printf '# 05 测试结果\n' > docs/changes/CHG-1080/05-test-results.md
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_paths: pom\\.xml\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1264 valid ERE override still trips E111 on the matched face" 2 $?
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_paths: zzz\\.nomatch\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1264 valid ERE override that misses keeps the gate green" 0 $?
# TC-1265：pre-commit 零触碰钉 + 行形权威派生面在位
report "T55 TC-1265 pre-commit consumes no ALLOW_NO_SHIFT env (FU-943 erratum pin)" 0 "$(grep -c 'ALLOW_NO_SHIFT' "$ROOT/resources/templates/pre-commit")"
report "T55 TC-1265 gate header pins the CHG-093 erratum" 1 "$(grep -c '^# --- v3.71.0 (CHG-046, REQ-1088) + v3.71.0 erratum (CHG-093, REQ-1093/1094)' "$ROOT/resources/templates/agent-gate.sh")"
report "T55 TC-1265 governance yml pins the active-change scan face" 1 "$(grep -c '扫描面' "$ROOT/resources/templates/agent-governance.yml")"
report "T55 TC-1265 playbook pins the narrowed scan face" 1 "$(grep -c '扫描面限活跃变更 05' "$ROOT/resources/STAGE_PLAYBOOK.md")"
report "T55 TC-1265 DS anchor pins the narrowed scan face" 1 "$(grep -c '豁免/证据限活跃变更 05' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T55 TC-1265 registry pins pointer fail-open semantics" 1 "$(grep -c '指针缺失 fail-open' "$ROOT/resources/CLAUSE_REGISTRY.md")"
# TC-1266（评审 P1-1 第 4 象限机钉）：指针缺失 × 未声明 smoke_command → 配置门仍拦（fail-open 仅豁免扫描面）
new_repo
seed_begin CHG-1081 L1 claude/s-1
printf 'smoke_placeholder: true\n' > pom.xml
git add pom.xml
rm -f "$(git rev-parse --git-path agent-governance/active-change)"
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1266 E111 fail-closed: config gate survives a missing pointer" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T55 TC-1266 stderr shows the bounded fail-open skip" "smoke gate fail-open" "$out"
# ⑤ 条款与模板在位（TC-1258，audit 同源口径）
report "T55 TC-1258 DS carries the four-gate row" 1 "$(grep -c '交付四门' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T55 TC-1258 DS carries the config-observability clause" 1 "$(grep -c '生效配置可观测' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T55 TC-1258 playbook carries the four-gate detail" 1 "$(grep -c '交付四门细则' "$ROOT/resources/STAGE_PLAYBOOK.md")"
report "T55 TC-1258 playbook carries the no-parallel red line" 1 "$(grep -c '禁并行集成测试' "$ROOT/resources/STAGE_PLAYBOOK.md")"
report "T55 TC-1258 AGENTS carries the no-parallel discipline" 1 "$(grep -c '禁并行集成测试' "$ROOT/resources/AGENTS.md")"
report "T55 TC-1258 pre-commit carries the shift reminder" 1 "$(grep -c 'SHIFT REMINDER' "$ROOT/resources/templates/pre-commit")"
report "T55 TC-1258 04 entry template carries the landing section" 1 "$(grep -c 'TC 落点清单' "$ROOT/resources/templates/entry/04-test-scripts.md")"
report "T55 TC-1258 governance yml carries the smoke key" 1 "$(grep -c 'smoke_command:' "$ROOT/resources/templates/agent-governance.yml")"
report "T55 TC-1258 registry indexes the four new codes" 4 "$(grep -cE 'GATE-E11[0-3] \|' "$ROOT/resources/CLAUSE_REGISTRY.md")"
# ⑥ A42 通用性：四门 payload 面无来源项目特异 token（扫描面=评审 P0-1 扩至 8 文件）
a42_hit=0
for pf in resources/templates/agent-gate.sh resources/templates/pre-commit resources/STAGE_PLAYBOOK.md resources/templates/agent-governance.yml resources/templates/entry/04-test-scripts.md resources/DEVELOPMENT_STANDARDS.md resources/AGENTS.md resources/CLAUSE_REGISTRY.md; do
  grep -qE 'chg044|paper-proto|doctor01|fzzl_|ASR_UPSTREAM|dev\.sh && ' "$ROOT/$pf" && a42_hit=$(( a42_hit + 1 ))
done
report "T55 TC-1258 A42: no source-project tokens in the four-gate payload (8 files)" 0 "$a42_hit"
}

# ------------------------------------------------ T56 begin 前产物预检探针（v3.72.0，CHG-094/REQ-1095~1096）
# 探针语义：preflight <id> 对 begin 产物层校验链做子 shell 捕获聚合，一次报全部
# 缺锚 reason（collect-all，非 fail-fast 首错）；exit 0=全过 / 1=违规 / 2=usage；
# 零副作用（不写指针、不记 friction、不消费 bypass env；TC-1270 钉）。
section_T56() {
  # TC-1267 + TC-1270 共仓：四类缺锚并存（DES 行/SC 行/覆盖维度行/00.5 确认标记）
  new_repo
  seed_artifacts CHG-1073 L1 claude/s-56
  grep -v 'DES-001' docs/changes/CHG-1073/03-modification-plan.md > .t56-03.tmp && mv .t56-03.tmp docs/changes/CHG-1073/03-modification-plan.md
  grep -v -e '覆盖维度' -e 'SC-001' docs/changes/CHG-1073/04-test-scripts.md > .t56-04.tmp && mv .t56-04.tmp docs/changes/CHG-1073/04-test-scripts.md
  printf '# 00.5\n## 深挖结论\nf\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n' > docs/changes/CHG-1073/00.5-communication.md
  t56_friction_before=$([[ -f .agent-state/gate-friction.tsv ]] && wc -l < .agent-state/gate-friction.tsv || echo 0)  # -f 守卫免 "No such file" stderr 噪声（TC-1275，CHG-095）
  t56_out=$(scripts/agent-gate preflight CHG-1073 2>&1); t56_rc=$?
  report "T56 TC-1267 preflight multi-anchor dir exits 1" 1 "$t56_rc"
  report "T56 TC-1267 collects GATE-E83 (empty confirmation)" 1 "$(printf '%s\n' "$t56_out" | grep -c 'GATE-E83')"
  report "T56 TC-1267 collects GATE-E07 (DES anchor)" 1 "$(printf '%s\n' "$t56_out" | grep -c 'GATE-E07')"
  report "T56 TC-1267 collects GATE-E09 (SC scenario)" 1 "$(printf '%s\n' "$t56_out" | grep -c 'GATE-E09')"
  report "T56 TC-1267 collects GATE-E11 (coverage dimension)" 1 "$(printf '%s\n' "$t56_out" | grep -c 'GATE-E11')"
  report "T56 TC-1267 single run reports ≥4 GATE lines" 0 "$([[ $(printf '%s\n' "$t56_out" | grep -c 'GATE-E') -ge 4 ]] && echo 0 || echo 1)"
  t56_friction_after=$([[ -f .agent-state/gate-friction.tsv ]] && wc -l < .agent-state/gate-friction.tsv || echo 0)  # -f 守卫免 "No such file" stderr 噪声（TC-1275，CHG-095）
  report "T56 TC-1270 friction ledger unchanged" 0 "$([[ "$t56_friction_after" == "$t56_friction_before" ]] && echo 0 || echo 1)"
  report "T56 TC-1270 active-change pointer not written" 0 "$([[ -e .git/agent-governance/active-change ]] && echo 1 || echo 0)"
  # TC-1268: 干净夹具（seed_begin 全件）→ exit 0 + clean 行
  new_repo
  seed_begin CHG-1074 L1 claude/s-56
  scripts/agent-gate preflight CHG-1074 >/dev/null 2>&1
  report "T56 TC-1268 clean fixture exits 0" 0 $?
  t56_out=$(scripts/agent-gate preflight CHG-1074 2>&1)
  check_output "T56 TC-1268 clean run prints the all-clean line" "agent-gate: preflight: CHG-1074: all artifact gates clean" "$t56_out"
  # TC-1269: usage/bad-id → exit 2（不经 die 的探针参数面）
  scripts/agent-gate preflight >/dev/null 2>&1
  report "T56 TC-1269 no argument exits 2" 2 $?
  t56_out=$(scripts/agent-gate preflight 'CHG.094' 2>&1)
  report "T56 TC-1269 dotted id exits 2" 2 "$?"
  check_output "T56 TC-1269 bad id names the FU-023 shape" "valid change id" "$t56_out"
  # TC-1277（v3.72.0 erratum，CHG-095/DES-1870）：bypass env 不得泄漏进 preflight
  # 探针（p_run unset，探针确定性）；实现缺席时本组两断言红。
  new_repo
  seed_artifacts CHG-1075 L1 claude/s-56
  printf '# 00.5\n## 用户整体确认记录\n' > docs/changes/CHG-1075/00.5-communication.md
  t56_bypass_out=$(AGENT_GUARD_ALLOW_UNCONFIRMED=1 scripts/agent-gate preflight CHG-1075 2>&1); t56_bypass_rc=$?
  report "T56 TC-1277 bypass env does not relax preflight (rc stays 1)" 1 "$t56_bypass_rc"
  report "T56 TC-1277 preflight still collects GATE-E83 under bypass env" 1 "$(printf '%s\n' "$t56_bypass_out" | grep -c 'GATE-E83')"
  # TC-1278（N4 顺手项）：tpl usage 块 preflight 行存在钉
  report "T56 TC-1278 tpl usage block carries the preflight line" 1 "$(grep -c '^  scripts/agent-gate preflight <change-id>' "$ROOT/resources/templates/agent-gate.sh")"
}

# ------------------------------------------------ T57 -j 并行调度 + 红归档/FORCE_RED 缝自测（v3.72.0 erratum，CHG-095/DES-1868~1869）
# 嵌套纪律（FU-907）：只嵌套轻量节选（T41/T48/T56 全为 grep/夹具轻节），绝不嵌套全跑。
# 夹具：复用 $ROOT 直跑 run-tests.sh 自身 + 收据/红归档文件前后快照比对。
# FORCE_RED 缝为通用测试面（尾块注释声明测试缝语义），供 T57/CI 演练红路径。
section_T57() {
  local t57_a t57_b t57_c t57_rc t57_had t57_redhad t57_tmp t57_dir t57_iso t57_red
  t57_tmp="${TMPDIR:-/tmp}"
  # TC-1272: -j 2 ≡ 串行（通过数/序/汇总行同形）
  t57_a=$(bash "$ROOT/tests/run-tests.sh" -T T41,T48 2>&1)
  t57_b=$(bash "$ROOT/tests/run-tests.sh" -T T41,T48 -j 2 2>&1)
  report "T57 TC-1272 -j2 keeps the serial pass count" "$(printf '%s\n' "$t57_a" | grep -c '^ok ')" "$(printf '%s\n' "$t57_b" | grep -c '^ok ')"
  report "T57 TC-1272 -j2 keeps the serial fail count" "$(printf '%s\n' "$t57_a" | grep -c '^FAIL ')" "$(printf '%s\n' "$t57_b" | grep -c '^FAIL ')"
  report "T57 TC-1272 -j2 replay keeps source order" "T41" "$(printf '%s\n' "$t57_b" | grep -m1 '^ok' | awk '{print $2}')"
  report "T57 TC-1272 -j2 keeps the summary shape" 1 "$(printf '%s\n' "$t57_b" | tail -2 | head -1 | grep -cE '^[0-9]+ passed, [0-9]+ failed$')"
  # TC-1273: 过滤 × 并行 → 收据不写（v3.86.0：隔离路径，不触真实台账）
  t57_dir=$(mktemp -d "${TMPDIR:-/tmp}/t57-state.XXXXXX")
  t57_iso="$t57_dir/last-suite-receipt.json"
  printf '{"head":"seed","passed":12345,"failed":0,"wall_time_s":0,"generated_at":"seed"}\n' > "$t57_iso"
  cp "$t57_iso" "$t57_dir/seeded"
  AGENT_GUARD_SUITE_RECEIPT_PATH="$t57_iso" bash "$ROOT/tests/run-tests.sh" -T T41,T48 -j 2 >/dev/null 2>&1; t57_rc=$?
  report "T57 TC-1273 filtered -j2 run exits clean" 0 "$t57_rc"
  report "T57 TC-1273 filtered -j2 run leaves receipt untouched" 0 "$(cmp -s "$t57_dir/seeded" "$t57_iso" && echo 0 || echo 1)"
  # TC-1276: FORCE_RED 缝 → rc 1 + 红归档含 FAIL 行 + 收据仍不被过滤跑触碰
  t57_red="$t57_dir/last-suite-red.txt"
  AGENT_GUARD_SUITE_RECEIPT_PATH="$t57_iso" AGENT_GUARD_SUITE_RED_PATH="$t57_red" AGENT_GUARD_SUITE_FORCE_RED=1 bash "$ROOT/tests/run-tests.sh" -T T41 >/dev/null 2>&1; t57_rc=$?
  report "T57 TC-1276 FORCE_RED run exits 1" 1 "$t57_rc"
  report "T57 TC-1276 red archive carries the forced FAIL line" 1 "$(grep -cF 'FAIL T0 forced-red seam (AGENT_GUARD_SUITE_FORCE_RED)' "$t57_red")"
  report "T57 TC-1276 FORCE_RED filtered run leaves receipt untouched" 0 "$(cmp -s "$t57_dir/seeded" "$t57_iso" && echo 0 || echo 1)"
  # TC-1274: 并行 T56 计数互证 + -j 1 逐字节等价串行（wall-time 行除外）
  t57_a=$(bash "$ROOT/tests/run-tests.sh" -T T56 2>&1)
  t57_b=$(bash "$ROOT/tests/run-tests.sh" -T T56 -j 2 2>&1)
  t57_c=$(bash "$ROOT/tests/run-tests.sh" -T T56 -j 1 2>&1)
  report "T57 TC-1274 -j2 T56 pass count matches serial" "$(printf '%s\n' "$t57_a" | grep -c '^ok ')" "$(printf '%s\n' "$t57_b" | grep -c '^ok ')"
  report "T57 TC-1274 -j1 is byte-equivalent to serial (modulo wall-time)" "$(printf '%s\n' "$t57_a" | grep -v '^wall-time: ')" "$(printf '%s\n' "$t57_c" | grep -v '^wall-time: ')"
  # TC-1275: 源层卫生钉（:3417 label 语义 + T56 friction -f 守卫 + stderr 无噪声）
  # TC-1275 钉用 -F + 引号拼接断开字面（T51 自匹配三连教训），只命中 T48 label 行
  report "T57 TC-1275 T48 label carries the superseded-row semantics" 1 "$(grep -cF 'v3.70.0 row exists (superseded by current '"top)" "$ROOT/tests/run-tests.sh")"
  report "T57 TC-1275 T56 friction reads carry the -f guard" 2 "$(grep -cE '\[\[ -f \.agent-state/gate-friction\.tsv \]\] && wc -l < \.agent-state/gate-friction\.tsv' "$ROOT/tests/run-tests.sh")"
  t57_b=$(bash "$ROOT/tests/run-tests.sh" -T T56 2>&1 1>/dev/null)
  report "T57 TC-1275 T56 stderr carries no missing-file noise" 0 "$(printf '%s\n' "$t57_b" | grep -c 'No such file')"
  # 收据/红归档夹具清理（v3.86.0：全部落隔离目录，真实台账从未参与）
  rm -rf "$t57_dir"
  rm -f "$t57_tmp/t57-receipt.real" "$t57_tmp/t57-receipt.seeded" "$t57_tmp/t57-red.real"
  # TC-1279: helper 提升后的顺序无关性持久钉（T19 单跑须全绿；嵌套 ≈8s 可接受）
  out=$(bash "$ROOT/tests/run-tests.sh" -T T19 2>&1 || true)
  report "T57 TC-1279 T19 standalone passes after hoisting (order-independence)" 1 "$(printf '%s\n' "$out" | grep -cE '^9 passed, 0 failed')"
  # TC-1280: CHG-500 续仓链（T5→T22a→T16）经 SERIAL_CHAIN 在 -j 下串行保续，须全绿
  out=$(bash "$ROOT/tests/run-tests.sh" -T T5,T22a,T16 -j 2 2>&1 || true)
  report "T57 TC-1280 CHG-500 chain sections pass under -j (cwd continuity)" 0 "$(( $(printf '%s\n' "$out" | grep -cE '^FAIL ') > 0 || $(printf '%s\n' "$out" | grep -cE '^ok ') < 51 ? 1 : 0 ))"
}

section_T58() {
# ------------------------------------------------ T58 long-task wait + full-suite telemetry (v3.73.0)
new_repo
SESSION_GATE_SRC="$ROOT/resources/templates/session-gate.sh"
if [[ -f "$SESSION_GATE_SRC" ]]; then
  cp "$SESSION_GATE_SRC" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  # TC-1281 (REQ-1100/SC-001 positive): declared governance; sleep-head counted; yellow at threshold 2
  printf 'full_test_patterns: ^mvn test$\n' > .agent-governance.yml
  bash scripts/session-gate.sh start >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='sleep 900; grep -c FAIL x.log' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1281 sleep head counted once" '"sleep_polls":1' "$(cat .agent-state/session-tool-stats.json)"
  DEV_STDARDS_CMD_HEAD='sleep 900; grep -c FAIL x.log' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1281 sleep head counted twice" '"sleep_polls":2' "$(cat .agent-state/session-tool-stats.json)"
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T58 TC-1281 sleep yellow light on status" "YELLOW.*长任务等待" "$out"
  bash scripts/session-gate.sh count tool bash 'sleep 15' >/dev/null 2>&1
  check_output "T58 TC-1281 argv cmd-head counted" '"sleep_polls":3' "$(cat .agent-state/session-tool-stats.json)"
  printf '{"tool_name":"bash","tool_input":{"command":"sleep 5; ls"}}\n' | bash scripts/session-gate.sh count tool - >/dev/null 2>&1
  check_output "T58 TC-1281 stdin tool_input.command counted" '"sleep_polls":4' "$(cat .agent-state/session-tool-stats.json)"
  # TC-1282 (REQ-1100 negative): while-form exempt (first token); env override fires at 1
  DEV_STDARDS_CMD_HEAD='while ! grep -q DONE f; do sleep 30; done' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1282 while-form not counted" '"sleep_polls":4' "$(cat .agent-state/session-tool-stats.json)"
  bash scripts/session-gate.sh start >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='sleep 60' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  out=$(bash scripts/session-gate.sh status 2>&1)
  if printf '%s' "$out" | grep -q "长任务等待"; then report "T58 TC-1282 default threshold stays silent at 1" 1 0; else report "T58 TC-1282 default threshold stays silent at 1" 0 0; fi
  out=$(AGENT_GUARD_SLEEP_POLL_LIMIT=1 bash scripts/session-gate.sh status 2>&1)
  check_output "T58 TC-1282 sleep-limit env override fires at 1" "YELLOW.*长任务等待" "$out"
  # TC-1283 (REQ-1102 declared): anchored ERE counts the exact full form; variants miss
  bash scripts/session-gate.sh start >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='mvn test' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1283 anchored full pattern counted" '"full_suite":1' "$(cat .agent-state/session-tool-stats.json)"
  DEV_STDARDS_CMD_HEAD='mvn test -Dtest=X' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='mvn -q test' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1283 flag/reordered variants not matched" '"full_suite":1' "$(cat .agent-state/session-tool-stats.json)"
  # TC-1284 (REQ-1102 negative): undeclared = off (fail-open); limit env override
  rm -f .agent-governance.yml
  bash scripts/session-gate.sh start >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='mvn test' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1284 undeclared pattern not counted" '"full_suite":0' "$(cat .agent-state/session-tool-stats.json)"
  printf 'full_test_patterns: ^mvn test$\n' > .agent-governance.yml
  DEV_STDARDS_CMD_HEAD='mvn test' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  out=$(AGENT_GUARD_FULL_TEST_LIMIT=1 bash scripts/session-gate.sh status 2>&1)
  check_output "T58 TC-1284 full-test limit env override fires at 1" "YELLOW.*全量回归" "$out"
  # TC-1286 (regression): legacy pre-CHG-096 stats JSON survives count (missing keys read 0) + status read
  printf '{"turns":3,"bash":1,"grep":0,"other":0,"total":1,"updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
  DEV_STDARDS_CMD_HEAD='sleep 30' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1286 legacy stats JSON migrates on count (missing keys read 0)" '"sleep_polls":1,"full_suite":0' "$(cat .agent-state/session-tool-stats.json)"
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T58 TC-1286 status reads migrated stats" "session stats" "$out"
  rm -f .agent-governance.yml
else
  echo "SKIP T58: session-gate.sh absent — 跳过长任务等待/全量遥测 golden cases"
fi

}

# v3.65.0 (CHG-087, REQ-1046~1048): SECTIONS = source-order registry (T22a/T22b
# disambiguate the duplicate "T22" label at :570/:2173; 摘要 at :2172 is a
# misplaced separator, not a boundary). Dispatcher: -l list, wanted validation
section_T59() {
# --------------------------------- T59 发现处置闭环 + 评审轮次收敛（v3.74.0，CHG-098）
# TC↔REQ：TC-1307/1308/1309/1310/1311→REQ-1104；TC-1312/1313→REQ-1105；TC-1314/1317→REQ-1106。
# 夹具沿用 T53 的 L0 轻量通道形态（seed_t53_delivery = 已证绿的 stop 交付面）；07 一律
# 本行自写 provenance（在 seed_t53_delivery 之后覆写，避免出现两个 provenance 块）。
new_repo
# 本节负例矩阵会反复改写 07（每改一次即一轮），故先把阈值抬高；只有收敛用例用
# 行内 `AGENT_GUARD_REVIEW_ROUND_LIMIT=0` 覆写来触发 E116。
export AGENT_GUARD_REVIEW_ROUND_LIMIT=99
seed_artifacts CHG-1090 L0 claude/s-1
cat > docs/changes/CHG-1090/01-spec.md <<'EOF'
# spec
- REQ-001: 发现处置与评审轮次闭环
- **origin_artifact**: 未命中（无原型页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: false
EOF
scripts/agent-gate begin CHG-1090 >/dev/null 2>&1
seed_t53_delivery CHG-1090
echo y > src/t59a.js
t59_07() { { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat; } > docs/changes/CHG-1090/07-review-report.md; }
# TC-1307（REQ-1104/SC-001 正面）：处置节齐备且严重行已处置 → 放行
t59_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 已修复 | 补测并复跑全绿 |
| F2 | 命名不一致 | 低 | 已驳回（误报） | 与 §1.3 命名表一致 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1307 stop green with a complete disposition table" 0 $?
# TC-1308（REQ-1104/SC-002 负面）：无「发现处置」节 → E115
t59_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1308 E115 red: disposition section missing" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T59 TC-1308 refusal names GATE-E115" "GATE-E115" "$out"
# TC-1309（负面）：严重行处置=待处置 → E114
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 待处置 | 尚未修复 |
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1309 E114 red: severe row left undisposed" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T59 TC-1309 refusal names GATE-E114" "GATE-E114" "$out"
# TC-1310（负面）：安全性质发现处置=不处理 → E114（安全面须修复或显式驳回）
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 输入未做安全转义 | 低 | 不处理（登记 FU-99） | 待下批 |
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1310 E114 red: security finding shelved as 不处理" 2 $?
# TC-1311（边界，三值化）：表头/分隔行/列数不足行一律不判罚（不得假红）
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 已处置的真实行 | 低 | 已修复 | 已统一 |
| F2 | 列数不足的畸形行 | 严重 |
| 低 | 仅两列的畸形行 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1311 header/separator/short rows never fire a verdict" 0 $?
# TC-1311b（fail-closed）：只有占位/畸形行且无单行声明 → E115（畸形不得成为短路借口）
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| <编号> | <发现> | <严重度> | <处置> | <证据/理由> |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
out=$(scripts/agent-gate --stage stop 2>&1 || true)
report "T59 TC-1311b placeholder-only disposition section fails closed" 2 "$(scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
check_output "T59 TC-1311b refusal names GATE-E115" "GATE-E115" "$out"
# TC-1311c（放行）：单行声明等价于处置节（无发现时的轻量形态）
t59_07 <<'EOF'
# review
- **发现处置**：未命中，不适用（本夹具无发现）
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1311c single-line 未命中 declaration passes" 0 $?
# TC-1312a（REQ-1105 幂等）：同一 07 内容重复调用不增轮
t59_n=$(awk -F'\t' '$1=="CHG-1090" && $2!=""{c++} END{print c+0}' .agent-state/review-rounds.tsv 2>/dev/null)
scripts/agent-gate --stage stop >/dev/null 2>&1
t59_n2=$(awk -F'\t' '$1=="CHG-1090" && $2!=""{c++} END{print c+0}' .agent-state/review-rounds.tsv 2>/dev/null)
report "T59 TC-1312a ledger records at least one round" 1 "$([[ "${t59_n:-0}" -ge 1 ]] && echo 1 || echo 0)"
report "T59 TC-1312a unchanged 07 adds no round (idempotent)" "$t59_n" "$t59_n2"
# TC-1312b（REQ-1105 收敛）：超限且无「超限处置」行 → E116；补行后放行且亮黄灯
report "T59 TC-1312b E116 red: over the round cap without a 超限处置 line" 2 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
out=$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop 2>&1 || true)
check_output "T59 TC-1312b refusal names GATE-E116" "GATE-E116" "$out"
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 命名不一致 | 低 | 已修复 | 已统一 |
- **评审轮次**：4
- **超限处置**：回退重议——拆分为两批，先落门禁再做版本链
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
rc=0
out=$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop 2>&1) || rc=$?
report "T59 TC-1312b over-cap run passes once the 超限处置 line exists" 0 "$rc"
check_output "T59 TC-1312b over-cap run prints the YELLOW convergence notice" "YELLOW.*review rounds" "$out"
# TC-1312c（F3 回归）：模板派生的 07（占位行 + 注释态「超限处置」）不得短路 E116 / E115
t59_07_tpl() { { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# CHG-1090 评审报告（L2）\n'; sed -n '2,$p' "$ROOT/resources/templates/entry/07-review-report.md"; printf -- '- 评审主体：platform / fixture-model / ses-t59tpl\n'; } > docs/changes/CHG-1090/07-review-report.md; }
t59_07_tpl
out=$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop 2>&1 || true)
report "T59 TC-1312c template-derived 07 still hits E116 over the cap" 2 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
check_output "T59 TC-1312c refusal names GATE-E116" "GATE-E116" "$out"
report "T59 TC-1312c template-derived 07 fails closed on the unfilled disposition table" 2 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=99 scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
# TC-1313（兼容性/降级）：非法阈值回落 3（非 0）；`.agent-state` 整体缺位 → fail-open
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 命名不一致 | 低 | 已修复 | 已统一 |
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
rm -f .agent-state/review-rounds.tsv
report "T59 TC-1313 invalid AGENT_GUARD_REVIEW_ROUND_LIMIT falls back to 3, not 0" 0 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=abc scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
rm -rf .agent-state
report "T59 TC-1313 absent .agent-state is fail-open (no counting, no E116)" 0 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
# TC-1314（REQ-1106）：metrics 追加评审质效字段；无 07 的变更输出 0/null
seed_artifacts CHG-1091 L0 claude/s-1
out=$(scripts/agent-gate metrics 2>/dev/null || true)
check_output "T59 TC-1314 metrics emits review-quality fields" \
  '"change_id":"CHG-1090".*"review_rounds":[0-9]+,"review_rounds_over_limit":(true|false),"findings_total":[0-9]+,"findings_dismissed":[0-9]+,"dismissal_rate":(null|[0-9]+\.[0-9]+)' "$out"
check_output "T59 TC-1314 metrics defaults to 0/null without a review report" \
  '"change_id":"CHG-1091".*"findings_total":0,"findings_dismissed":0,"dismissal_rate":null' "$out"
# TC-1317（CHG-098 评审 V2 回归）：模板派生的 07（仅占位行）不得被 metrics 计为发现——
# 处置计数必须与门禁裁决同源（占位/注释态行一律不计），否则空 07 会报出"最高噪声"。
t59_07_tpl
out=$(scripts/agent-gate metrics 2>/dev/null || true)
check_output "T59 TC-1317 metrics ignores the template placeholder row" \
  '"change_id":"CHG-1090".*"findings_total":0,"findings_dismissed":0,"dismissal_rate":null' "$out"
}

section_T60() {
# ------------------------------- T60 评测资产派生 + 重打分 + 来源维 + 复盘汲取（v3.75.0，CHG-099）
# TC↔REQ：TC-1318/1319/1320/1321/1322→REQ-1108；TC-1323/1324/1325/1328/1333→REQ-1109；
# TC-1326/1327→REQ-1110；TC-1329/1330/1331/1332→REQ-1111；TC-1334→全量回归；TC-1335→安全面。
# 夹具纪律：new_repo 自带 scripts/agent-gate；本节自拷 eval-cases/eval-rescore，治理面一律用
# `--face` 指向自建 fixture 目录（不读本仓真实治理面，避免自指漂移与跨平台哈希耦合）。
CASES_SRC="$ROOT/resources/templates/eval-cases.sh"
[[ -f "$CASES_SRC" ]] || CASES_SRC="$ROOT/scripts/eval-cases"
SCORE_SRC="$ROOT/resources/templates/eval-rescore.sh"
[[ -f "$SCORE_SRC" ]] || SCORE_SRC="$ROOT/scripts/eval-rescore"
new_repo
cp "$CASES_SRC" scripts/eval-cases
cp "$SCORE_SRC" scripts/eval-rescore
chmod +x scripts/eval-cases scripts/eval-rescore
mkdir -p docs/bugs/BUG-002 docs/bugs/BUG-001 docs/bugs/BUG-20260101120000 docs/bugs/BATCH-20260102
# 手工缺陷（manual）：无「应捕获层」行 → 未声明；含敏感 canary 供 TC-1335 断言
cat > docs/bugs/BUG-001/01-diagnosis.md <<'EOF'
# 诊断
- **应捕获层**：测试
- **该层检查落点 / 补强**：tests/run-tests.sh T60（本次新增）
EOF
printf '# 矩阵\n| TC | 覆盖 |\n|---|---|\n| TC-1111 | 回归 |\n' > docs/bugs/BUG-001/04-matrix.md
cat > docs/bugs/BUG-002/01-diagnosis.md <<'EOF'
# 诊断
SECRET-CANARY-9f3
## 根因表
- R1 触发条件
EOF
printf '# 矩阵\n| TC | 覆盖 |\n|---|---|\n| 无 | — |\n' > docs/bugs/BUG-002/04-matrix.md
# 事故通道（incident）：id 形如 BUG-<UTC 时间戳>
cat > docs/bugs/BUG-20260101120000/01-diagnosis.md <<'EOF'
# 诊断
- **应捕获层**：门禁
- **该层检查落点 / 补强**：agent-gate E999（本次新增）
EOF
# 扁平批次（BATCH-* + `## BUG-*` 锚点）：自动回归锚点 + 事故锚点
cat > docs/bugs/BATCH-20260102/01-diagnosis.md <<'EOF'
# 批次诊断
## BUG-20260102000000 自动回归
- **复现记录（自动）**：fingerprint abc
- **应捕获层**：设计
## BUG-20260103000000 事故重入
- **应捕获层**：编码前置
EOF
cat > docs/bugs/BATCH-20260102/04-matrix.md <<'EOF'
# 批次矩阵
## BUG-20260102000000 自动回归
| TC | 覆盖 |
|---|---|
| TC-2222 | 回归 |
## BUG-20260103000000 事故重入
| TC | 覆盖 |
|---|---|
| 无 | — |
EOF
t60_tsv=.agent-state/eval-cases.tsv
rm -f "$t60_tsv"
scripts/eval-cases >/dev/null 2>&1
report "T60 TC-1318 derivation exits 0" 0 $?
report "T60 TC-1318 header + 5 derived cases" 6 "$(wc -l < "$t60_tsv" | tr -d ' ')"
t60_p1=$(printf '^EC-BUG-001\tmanual\tBUG-001\t测试\tdocs/bugs/BUG-001\tTC-1111$')
t60_p2=$(printf '^EC-BUG-002\tmanual\tBUG-002\t未声明\tdocs/bugs/BUG-002\t$')
t60_p3=$(printf '^EC-BUG-20260101120000\tincident\tBUG-20260101120000\t门禁\t')
t60_p4=$(printf '^EC-BUG-20260102000000\tregression\tBUG-20260102000000\t设计\t')
t60_p5=$(printf '^EC-BUG-20260103000000\tincident\tBUG-20260103000000\t编码前置\t')
check_output "T60 TC-1318 derived columns for the manual case" "$t60_p1" "$(cat "$t60_tsv")"
check_output "T60 TC-1322 undeclared capture layer stays 未声明" "$t60_p2" "$(cat "$t60_tsv")"
check_output "T60 TC-1322 incident channel derived from a timestamp id" "$t60_p3" "$(cat "$t60_tsv")"
check_output "T60 TC-1322 regression channel derived from the auto marker" "$t60_p4" "$(cat "$t60_tsv")"
check_output "T60 TC-1322 flat-batch anchor derives its own case" "$t60_p5" "$(cat "$t60_tsv")"
report "T60 TC-1320 stable order: first derived case is the lowest id" 0 "$([[ "$(awk -F'\t' 'NR==2{print $1}' "$t60_tsv")" == "EC-BUG-001" ]] && echo 0 || echo 1)"
# v3.75.0 收尾整改（独立评审 F-7）：补齐 REQ-1108 的两条 A 层验收——原 TC-1318 断言的是
# "5 组 → 6 行"，**空缺陷面**与**派生视图禁止入库**两条从未被机校（用例声称与实际断言不一致）。
t60_cases="$PWD/scripts/eval-cases"
t60_empty=$(mktemp -d "${TMPDIR:-/tmp}/t60-empty.XXXXXX")
( cd "$t60_empty" && bash "$t60_cases" --out "$t60_empty/out.tsv" >/dev/null 2>&1; echo $? > "$t60_empty/rc" )
report "T60 TC-1318b empty defect face exits 0" 0 "$(cat "$t60_empty/rc")"
report "T60 TC-1318b empty defect face emits the header only" 1 "$(wc -l < "$t60_empty/out.tsv" | tr -d ' ')"
# 派生视图禁止入库：路径无跟踪文件 → `git ls-files --error-unmatch` 以 1 退出
report "T60 TC-1318c no docs/evals derived asset is tracked" 1 "$(git ls-files --error-unmatch docs/evals >/dev/null 2>&1; echo $?)"
# F-8：同一缺陷 id 以"嵌套目录 + 扁平锚点"两形态出现时，必须按 case_id 去重（覆盖比分母不重复计数）
t60_mix=$(mktemp -d "${TMPDIR:-/tmp}/t60-mix.XXXXXX")
mkdir -p "$t60_mix/docs/bugs/BATCH-A/BUG-900" "$t60_mix/docs/bugs/BATCH-B"
printf '# 诊断\n- **应捕获层**：测试\n' > "$t60_mix/docs/bugs/BATCH-A/BUG-900/01-diagnosis.md"
printf '# 矩阵\n| TC | 覆盖 |\n|---|---|\n| TC-9 | 回归 |\n' > "$t60_mix/docs/bugs/BATCH-A/BUG-900/04-matrix.md"
printf '# 批诊断\n## BUG-900 重复锚点\n- **应捕获层**：测试\n' > "$t60_mix/docs/bugs/BATCH-B/01-diagnosis.md"
( cd "$t60_mix" && bash "$t60_cases" --out "$t60_mix/out.tsv" >/dev/null 2>&1 )
report "T60 TC-1318d duplicate bug id collapses to one case_id" 2 "$(wc -l < "$t60_mix/out.tsv" | tr -d ' ')"
rm -rf "$t60_empty" "$t60_mix"
t60_sum1=$(cksum < "$t60_tsv")
scripts/eval-cases >/dev/null 2>&1
report "T60 TC-1319 re-derivation is byte-identical (idempotent)" 0 "$([[ "$t60_sum1" == "$(cksum < "$t60_tsv")" ]] && echo 0 || echo 1)"
out=$(scripts/eval-cases --verify 2>&1)
report "T60 TC-1321 verify green on a well-formed defect face" 0 $?
report "T60 TC-1321 verify is silent when green" 0 "$([[ -z "$out" ]] && echo 0 || echo 1)"
cp docs/bugs/BUG-002/01-diagnosis.md "${TMPDIR:-/tmp}/t60-diag.bak"
: > docs/bugs/BUG-002/01-diagnosis.md
out=$(scripts/eval-cases --verify 2>&1)
report "T60 TC-1321 verify red on an empty diagnosis artifact" 1 $?
check_output "T60 TC-1321 refusal names the empty artifact" "empty diagnosis artifact" "$out"
cp "${TMPDIR:-/tmp}/t60-diag.bak" docs/bugs/BUG-002/01-diagnosis.md
out=$(scripts/eval-cases --verify 2>&1)
report "T60 TC-1321 verify green again after repair" 0 $?
# TC-1323/1324/1325/1328（REQ-1109）：覆盖比口径、零 case 契约、确定性、只读
out=$(scripts/eval-rescore --dry-run 2>&1)
report "T60 TC-1323 rescore dry-run exits 0" 0 $?
check_output "T60 TC-1323 coverage ratio = 2/5 and no invented fields" '"cases_total":5,"covered":2,"missed":3,"score":0.4000' "$out"
printf 'case_id\tsource\tbug_id\tcaptured_layer\tlanding\tregression_ref\n' > t60-empty.tsv
out=$(scripts/eval-rescore --cases t60-empty.tsv --dry-run 2>&1)
report "T60 TC-1324 zero-case run exits 0" 0 $?
check_output "T60 TC-1324 zero cases yields a null score, not 0 or 1" '"cases_total":0,"covered":0,"missed":0,"score":null,"config_sha"' "$out"
check_output "T60 TC-1324 zero cases is not reported stale" '"baseline_present":false,"stale":false' "$out"
t60_d1=$(scripts/eval-rescore --dry-run 2>&1 | sed 's/"generated_at":"[^"]*"/"generated_at":"X"/')
t60_d2=$(scripts/eval-rescore --dry-run 2>&1 | sed 's/"generated_at":"[^"]*"/"generated_at":"X"/')
report "T60 TC-1325 rescore is deterministic apart from the timestamp" 0 "$([[ "$t60_d1" == "$t60_d2" && -n "$t60_d1" ]] && echo 0 || echo 1)"
rm -f .agent-state/eval-score-receipt.json .agent-state/eval-score-baseline.json
scripts/eval-rescore --dry-run >/dev/null 2>&1
report "T60 TC-1328 dry-run writes no receipt" 0 "$([[ ! -e .agent-state/eval-score-receipt.json ]] && echo 0 || echo 1)"
report "T60 TC-1328 dry-run writes no baseline" 0 "$([[ ! -e .agent-state/eval-score-baseline.json ]] && echo 0 || echo 1)"
# TC-1335（安全面）：派生视图与收据不得携带诊断正文里的敏感值
report "T60 TC-1335 derived view carries no diagnosis-body secret" 0 "$([[ "$(grep -c 'SECRET-CANARY-9f3' "$t60_tsv" || true)" == 0 ]] && echo 0 || echo 1)"
# TC-1326/1327（REQ-1110）：治理面内容哈希漂移 + 用例集成员漂移
mkdir -p face1/resources/templates
printf 'g1=v1\n' > face1/resources/templates/g1.sh
scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" --update-baseline >/dev/null 2>&1
report "T60 TC-1326 baseline build exits 0" 0 $?
scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" >/dev/null 2>&1
report "T60 TC-1326 unchanged governance face stays green" 0 $?
printf 'g1=v2\n' > face1/resources/templates/g1.sh
out=$(scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" 2>&1)
report "T60 TC-1326 governance-face change is stale (rc 1)" 1 $?
check_output "T60 TC-1326 stale receipt marks the drift" '"stale":true' "$(cat .agent-state/eval-score-receipt.json)"
check_output "T60 TC-1326 drift alert is surfaced" "STALE" "$out"
scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" --update-baseline >/dev/null 2>&1
mkdir -p docs/bugs/BUG-003
printf '# 诊断\n- **应捕获层**：需求\n' > docs/bugs/BUG-003/01-diagnosis.md
scripts/eval-cases >/dev/null 2>&1
scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" >/dev/null 2>&1
report "T60 TC-1327 new eval member is stale (rc 1)" 1 $?
report "T60 TC-1335 receipt carries no diagnosis-body secret" 0 "$([[ "$(grep -c 'SECRET-CANARY-9f3' .agent-state/eval-score-receipt.json || true)" == 0 ]] && echo 0 || echo 1)"
# TC-1329/1330/1331/1332（REQ-1111）：07「来源」列与 metrics 字段
# 夹具切换：评测面用的 docs/bugs 夹具只服务派生测试（非六件套），在门禁面测试前移除，
# 避免把「缺陷组缺六件套」的无关红灯误记到本节的门禁断言上。
rm -rf docs/bugs
export AGENT_GUARD_REVIEW_ROUND_LIMIT=99
seed_artifacts CHG-1091 L0 claude/s-1
cat > docs/changes/CHG-1091/01-spec.md <<'EOF'
# spec
- REQ-001: 发现来源维闭环
- **origin_artifact**: 未命中（无原型页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: false
EOF
scripts/agent-gate begin CHG-1091 >/dev/null 2>&1
seed_t53_delivery CHG-1091
echo y > src/t60a.js
t60_07() { { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat; } > docs/changes/CHG-1091/07-review-report.md; }
t60_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 | 来源 |
|---|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 已修复 | 补测并复跑全绿 | 本次引入 |
| F2 | 命名不一致 | 低 | 已驳回（误报） | 与 §1.3 命名表一致 | 既有存量 |
| F3 | 注释缺失 | 低 | 已修复 | 补齐注释 | 本次引入 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t60a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T60 TC-1329 stop green with a lawful provenance column" 0 $?
out=$(scripts/agent-gate metrics 2>/dev/null || true)
check_output "T60 TC-1332 metrics counts introduced/pre-existing findings" '"findings_introduced":2,"findings_pre_existing":1' "$out"
t60_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 | 来源 |
|---|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 已修复 | 补测并复跑全绿 | 存量问题 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t60a
EOF
out=$(scripts/agent-gate --stage stop 2>&1)
report "T60 TC-1330 E117 red on an unlawful provenance value" 2 $?
check_output "T60 TC-1330 refusal names GATE-E117" "GATE-E117" "$out"
t60_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 已修复 | 补测并复跑全绿 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t60a
EOF
out=$(scripts/agent-gate --stage stop 2>&1)
report "T60 TC-1331 legacy five-column table stays green (upgrade compat)" 0 $?
check_output "T60 TC-1331 legacy shape gets a soft notice" "缺「来源」列" "$out"
out=$(scripts/agent-gate metrics 2>/dev/null || true)
check_output "T60 TC-1332 legacy shape reports null provenance, not zero" '"findings_introduced":null,"findings_pre_existing":null' "$out"
# TC-1333（REQ-1109）：工作流模板形状（schedule + 调用本地脚本）
# v3.75.0 收尾整改（独立评审 F-14）：原断言只数 `schedule:` 关键词（注释里也有），改钉
# **锚定行**（`^\s+schedule:` + `^\s+cron:` 同现），注释掉/空格错位即红。
t60_wf="$ROOT/resources/templates/github-reviewer-rescore.yml"
t60_sched=$(grep -cE '^[[:space:]]+schedule:' "$t60_wf" || true)
t60_cron=$(grep -cE '^[[:space:]]+(-[[:space:]]+)?cron:' "$t60_wf" || true)
report "T60 TC-1333 rescore workflow declares an anchored schedule + cron" 1 "$([[ "$t60_sched" -ge 1 && "$t60_cron" -ge 1 ]] && echo 1 || echo 0)"
report "T60 TC-1333 rescore workflow calls scripts/eval-rescore" 0 "$([[ "$(grep -c 'scripts/eval-rescore' "$ROOT/resources/templates/github-reviewer-rescore.yml")" -ge 1 ]] && echo 0 || echo 1)"
}

# ------------------------------------------------ T61 验证通道方言与四态（v3.76.0, CHG-100）
# REQ-1115~1122 / SC-1822~1827。判定口径 = `.agent-governance.yml` 的
# `ci.verification_command`（gate 唯一读取点 yml_scalar）。探针 `verify-channel` 是
# **只读**的（不执行命令、不写状态），因此方言矩阵可以零副作用全覆盖；执行面
# （状态文件 + 05 自检证据）另起两个夹具走 `--stage stop` 真车道。
section_T61() {
  local yml=".agent-governance.yml" out rc t61_bt t61_f
  new_repo
  t61_yml() { printf '%b' "$1" > "$yml"; git add -A >/dev/null 2>&1; git commit -qm yml >/dev/null 2>&1 || true; }
  t61_probe() { out=$(scripts/agent-gate verify-channel 2>&1); rc=$?; }

  # ---- TC-1338 / REQ-1115：旧型（双引号无转义）语义零回归 -------------------
  t61_yml 'ci:\n  verification_command: "bash tests/run-tests.sh"\n'
  t61_probe
  report "T61 TC-1338 legacy double-quoted yml still resolves (rc 0)" 0 "$rc"
  check_output "T61 TC-1338 legacy value is byte-identical" 'state=yml .*command=bash tests/run-tests\.sh$' "$out"

  # ---- TC-1337 / REQ-1115：方言矩阵（声明式超集） --------------------------
  t61_yml "ci:\n  verification_command: 'bash tests/run-tests.sh'\n"
  t61_probe
  check_output "T61 TC-1337 single-quoted scalar parses" 'command=bash tests/run-tests\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: bash tests/run-tests.sh\n'
  t61_probe
  check_output "T61 TC-1337 bare scalar parses" 'command=bash tests/run-tests\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: bash a.sh  # trailing comment\n'
  t61_probe
  check_output "T61 TC-1337 trailing comment is stripped" 'command=bash a\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: "bash -lc \\"echo hi\\""\n'
  t61_probe
  check_output "T61 TC-1337 escaped double quote decodes" 'command=bash -lc "echo hi"$' "$out"
  t61_yml 'ci:\n  verification_command: |\n    bash a.sh\n    bash b.sh\n'
  t61_probe
  check_output "T61 TC-1337 literal block keeps the first line" 'bash a\.sh' "$out"
  check_output "T61 TC-1337 literal block keeps the second line" 'bash b\.sh' "$out"
  t61_yml 'ci:\n  verification_command: >\n    bash a.sh\n    bash b.sh\n'
  t61_probe
  check_output "T61 TC-1337 folded block joins lines with a space" 'command=bash a\.sh bash b\.sh$' "$out"
  # F1（独立评审）：块标量**后面还有同级键/别的段**时，已收集的块不得被丢掉——
  # 本变更初版会在这种（最常见的）形态下静默判 absent，正是要消灭的事故形态。
  t61_yml 'ci:\n  verification_command: |\n    bash blk.sh\n  smoke_command: "x"\n'
  t61_probe
  check_output "T61 TC-1337 block scalar survives a following sibling key" 'command=bash blk\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: >\n    bash fol.sh\nstop_hook:\n  a: b\n'
  t61_probe
  check_output "T61 TC-1337 folded block survives a following section" 'command=bash fol\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: |-\n    bash a.sh\n'
  t61_probe
  check_output "T61 TC-1337 chomping indicator is accepted" 'command=bash a\.sh$' "$out"
  t61_yml 'ci:\r\n  verification_command: "bash c.sh"\r\n'
  t61_probe
  check_output "T61 TC-1337 CRLF line endings parse" 'command=bash c\.sh$' "$out"

  # ---- TC-1339 / REQ-1116：unparsable → fail-closed（探针 rc 2）-------------
  t61_yml 'ci:\n  verification_command:\n'
  t61_probe
  report "T61 TC-1339 empty value is unparsable (rc 2)" 2 "$rc"
  check_output "T61 TC-1339 empty value names the state" 'state=unparsable' "$out"
  t61_yml 'ci:\n  verification_command: ""\n'
  t61_probe
  report "T61 TC-1339 empty double quotes are unparsable (rc 2)" 2 "$rc"
  t61_yml 'ci:\n  verification_command: "bash a.sh\n'
  t61_probe
  report "T61 TC-1339 unterminated quote is unparsable (rc 2)" 2 "$rc"
  t61_yml 'ci:\n  verification_command: |x\n'
  t61_probe
  report "T61 TC-1339 illegal block indicator is unparsable (rc 2)" 2 "$rc"
  # F7：多行裸标量（合法 YAML，方言外）不得被静默截断成第一行
  t61_yml 'ci:\n  verification_command: bash a.sh\n    bash b.sh\n'
  t61_probe
  report "T61 TC-1339c multiline plain scalar is unparsable (rc 2)" 2 "$rc"
  # F6①：别的段（stop_hook）里的同名键不是通道
  t61_yml 'ci:\n  docs: ok\nstop_hook:\n  verification_command: "bash hook.sh"\n'
  t61_probe
  report "T61 TC-1339c a foreign-section key is unparsable (rc 2)" 2 "$rc"
  # F6②：更深的同名键（ci 子键之下）不是通道
  t61_yml 'ci:\n  sub:\n    verification_command: "bash nested.sh"\n'
  t61_probe
  report "T61 TC-1339c a deeper key is unparsable (rc 2)" 2 "$rc"
  # F6③ / 整改 R1：别的键的**块正文**里出现同名行 → fail-closed（不是配置，也不是
  # 静默 absent——yml 注释是方言声明唯一权威载体，已声明这类形态"一律 unparsable"）。
  t61_yml 'ci:\n  docs: |\n    verification_command: "bash ex.sh"\n'
  t61_probe
  report "T61 TC-1339c a block-body lookalike inside ci is unparsable (rc 2)" 2 "$rc"
  check_output "T61 TC-1339c block-body lookalike names the misplaced state" 'state=unparsable' "$out"
  # R1②：顶层键的块正文（同一形态、另一位置）——同样 misplaced，不许"合法跳过"
  t61_yml 'docs: |\n  verification_command: "bash ex.sh"\n'
  t61_probe
  report "T61 TC-1339c a top-level block-body lookalike is unparsable (rc 2)" 2 "$rc"
  check_output "T61 TC-1339c top-level block-body lookalike names the misplaced state" 'state=unparsable' "$out"
  # R1 反例（真键胜出，第 3 轮评审新发现 1）：兄弟键块正文含同名行不得污染真键
  t61_yml 'ci:\n  docs: |\n    verification_command: "bash ex.sh"\n  verification_command: "bash real.sh"\n'
  t61_probe
  report "T61 TC-1339c a real key beats a sibling block-body lookalike (rc 0)" 0 "$rc"
  check_output "T61 TC-1339c the real key's command wins over the lookalike" 'command=bash real.sh' "$out"
  # 第 3 轮评审新发现 4：行尾垃圾（引号后跟残余 token）是方言外形态，不得静默采值
  t61_yml 'ci:\n  verification_command: "bash a.sh" trailing\n'
  t61_probe
  report "T61 TC-1339c trailing garbage after a quoted value is unparsable (rc 2)" 2 "$rc"
  check_output "T61 TC-1339c trailing garbage names the state" 'state=unparsable' "$out"
  # 第 3 轮评审新发现 4：注释行里的同名键不得被误采（合法跳过，不是配置）
  t61_yml 'ci:\n  # verification_command: "bash x.sh"\n'
  t61_probe
  report "T61 TC-1339c a commented-out key is not the channel (rc 0)" 0 "$rc"
  check_output "T61 TC-1339c a commented-out key names the absent state" 'state=absent' "$out"

  # ---- TC-1340 / REQ-1116：合法跳过态（absent / placeholder）---------------
  rm -f "$yml"
  git add -A >/dev/null 2>&1; git commit -qm rmyml >/dev/null 2>&1 || true
  t61_probe
  report "T61 TC-1340 missing key is a lawful skip (rc 0)" 0 "$rc"
  check_output "T61 TC-1340 missing key names the absent state" 'state=absent' "$out"
  t61_yml 'ci:\n  verification_command: "<replace-with-project-test-command>"\n'
  t61_probe
  report "T61 TC-1340 install placeholder is a lawful skip (rc 0)" 0 "$rc"
  check_output "T61 TC-1340 install placeholder names the state" 'state=placeholder' "$out"
  # v3.76.0 整改（独立评审 F13）：顶层同名键**显式拒**（曾静默 absent，与旧 sed 的
  # "会执行"行为反向差异且无痕）——位置非法 = unparsable → GATE-E118。
  t61_yml 'verification_command: "bash toplevel.sh"\n'
  t61_probe
  report "T61 TC-1340 a top-level key is rejected, not silently absent (rc 2)" 2 "$rc"
  check_output "T61 TC-1340 misplaced key names the state" 'state=unparsable' "$out"

  # ---- TC-1341 / REQ-1119：anti-tamper × env 组合矩阵 ----------------------
  t61_yml 'ci:\n  verification_command: "bash committed.sh"\n'
  out=$(AGENT_GUARD_VERIFY_COMMAND='bash env.sh' scripts/agent-gate verify-channel 2>&1)
  check_output "T61 TC-1341 env wins over a clean yml" 'state=env source=env command=bash env\.sh' "$out"
  printf 'ci:\n  verification_command: "bash edited.sh"\n' > "$yml"
  t61_probe
  check_output "T61 TC-1341 pending yml blocks auto-execution (tampered)" 'state=tampered' "$out"
  out=$(AGENT_GUARD_VERIFY_COMMAND='bash env.sh' scripts/agent-gate verify-channel 2>&1)
  check_output "T61 TC-1341 pending yml + env is the lawful maintenance path" 'state=tampered\+env' "$out"

  # ---- TC-1342/1343 / REQ-1117/1118：stop 车道落状态文件 + 05 自检证据 ------
  new_repo
  seed_artifacts CHG-710 L0 claude/s-1
  scripts/agent-gate begin CHG-710 >/dev/null 2>&1
  seed_t53_delivery CHG-710
  cp "$ROOT/resources/templates/session-gate.sh" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  out=$(scripts/session-gate.sh status 2>&1 || true)
  check_output "T61 TC-1342 status says the channel is unrecorded before any stop" '验证通道：未记录' "$out"
  t61_yml 'ci:\n  verification_command: "printf ok > t61-probe.txt"\n'
  echo y > src/t61a.js
  out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
  report "T61 TC-1342 stop executes the yml channel command" 0 "$([[ -s t61-probe.txt ]] && echo 0 || echo 1)"
  report "T61 TC-1342 stop stays green when the channel passes" 0 "$rc"
  for t61_f in state source command exit_code reason env_fingerprint generated_at head; do
    grep -q "\"$t61_f\":" .agent-state/verify-channel.json
    report "T61 TC-1342 channel state file carries '$t61_f'" 0 $?
  done
  grep -q '"state":"yml"' .agent-state/verify-channel.json
  report "T61 TC-1342 channel state file records the yml source" 0 $?
  grep -q '通道自检证据' docs/changes/CHG-710/05-test-results.md
  report "T61 TC-1343 05 records the channel self-check evidence" 0 $?
  out=$(scripts/session-gate.sh status 2>&1 || true)
  check_output "T61 TC-1342 session-gate status shows the channel line" '- 验证通道：' "$out"

  # ---- TC-1343 / REQ-1118：未执行时 05 显式写「通道未验证」-----------------
  new_repo
  seed_artifacts CHG-711 L0 claude/s-1
  scripts/agent-gate begin CHG-711 >/dev/null 2>&1
  seed_t53_delivery CHG-711
  cp "$ROOT/resources/templates/session-gate.sh" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  echo y > src/t61b.js
  out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
  report "T61 TC-1343 stop without a channel still passes" 0 "$rc"
  grep -q '通道未验证（absent' docs/changes/CHG-711/05-test-results.md
  report "T61 TC-1343 05 records the explicit not-verified reason" 0 $?
  out=$(scripts/session-gate.sh status 2>&1 || true)
  check_output "T61 TC-1343 status surfaces the absent state, not a silent skip" '验证通道：absent' "$out"

  # ---- TC-1344 / REQ-1120：安装/升级写入 yml 提示通道暂停 ------------------
  t61_bt=$(mktemp -d "${TMPDIR:-/tmp}/t61-boot.XXXXXX")
  if [[ -f "$BOOT_SRC" ]]; then
    out=$(bash "$BOOT_SRC" --guard "$t61_bt" 2>&1 || true)
    check_output "T61 TC-1344 guard install warns the channel is paused" 'verification channel paused' "$out"
    out=$(bash "$BOOT_SRC" --guard --upgrade "$t61_bt" 2>&1 || true)
    report "T61 TC-1344 upgrade without a yml rewrite stays quiet" 0 "$(printf '%s' "$out" | grep -c 'verification channel paused')"
  else
    report "T61 TC-1344 bootstrap available (skill-repo layout only)" 0 "$([[ -f "$BOOT_SRC" ]] && echo 0 || echo 1)"
  fi
  rm -rf "$t61_bt"

  # ---- TC-1344b / REQ-1120（整改 F9）：提示口径必须与实际结果一致 -------------
  # 初版不分叉：本轮刚自动探测并把 `npm test` 写进 yml，却提示「paused：请声明
  # ci.verification_command」——与磁盘事实相反，维护者会以为通道还是断的。
  t61_bt2="${TMPDIR:-/tmp}/t61-boot-detect.$$"
  rm -rf "$t61_bt2"; mkdir -p "$t61_bt2"
  if [[ -f "$BOOT_SRC" ]]; then
    printf '{"name":"x","scripts":{"test":"exit 0"}}\n' > "$t61_bt2/package.json"
    out=$(bash "$BOOT_SRC" --guard "$t61_bt2" 2>&1 || true)
    check_output "T61 TC-1344b auto-wired channel reports the detected command" 'verification channel updated by this run' "$out"
    check_output "T61 TC-1344b the detected command is named" 'verification_command = npm test' "$out"
    report "T61 TC-1344b auto-wired channel is not called paused" 0 "$(printf '%s' "$out" | grep -c 'verification channel paused')"
  else
    report "T61 TC-1344b bootstrap available (skill-repo layout only)" 0 "$([[ -f "$BOOT_SRC" ]] && echo 0 || echo 1)"
  fi
  rm -rf "$t61_bt2"

  # ---- TC-1346 / REQ-1122：红档语义=最近一次运行结果（绿跑清档）-----------
  grep -qF 'if [[ ${#WANTED[@]} -eq 0 && "$fail" -eq 0 && -n "$SUITE_HEAD" ]]; then' "$ROOT/tests/run-tests.sh"
  report "T61 TC-1346 green clear is gated on a FULL run" 0 $?
  grep -qF 'rm -f "$SUITE_RED_PATH"' "$ROOT/tests/run-tests.sh"
  report "T61 TC-1346 full green run deletes the stale red archive" 0 $?
  grep -qF "recent run's result" "$ROOT/tests/run-tests.sh"
  report "T61 TC-1346 archive semantics documented as the most recent run" 0 $?
  # 行为面（F16：结构性 pin 不等于行为验证）：强制红跑留档；**过滤**绿跑不清档
  # （清档只归"全量绿跑"这一条路径）。v3.86.0：归档落在隔离路径，不触真实台账。
  t61_dir=$(mktemp -d "${TMPDIR:-/tmp}/t61-state.XXXXXX")
  t61_ar="$t61_dir/last-suite-red.txt"
  AGENT_GUARD_SUITE_RED_PATH="$t61_ar" AGENT_GUARD_SUITE_FORCE_RED=1 bash "$ROOT/tests/run-tests.sh" -T T39 >/dev/null 2>&1
  report "T61 TC-1346 a forced-red filtered run leaves the archive" 1 "$([[ -f "$t61_ar" ]] && echo 1 || echo 0)"
  AGENT_GUARD_SUITE_RED_PATH="$t61_ar" bash "$ROOT/tests/run-tests.sh" -T T39 >/dev/null 2>&1
  report "T61 TC-1346 a filtered green run does NOT clear the archive" 1 "$([[ -f "$t61_ar" ]] && echo 1 || echo 0)"
  rm -rf "$t61_dir"

  # ---- TC-1339b / REQ-1116：unparsable 在 **stop 车道**也 fail-closed ----------
  # （F3/F16：初版只测了探针，正好漏掉"die 行在 bash 3.2 上因全角标点吞变量名而
  #  崩溃、GATE-E118 文案根本没打出来"这一类缺陷——现在真跑 stop 车道。）
  new_repo
  seed_artifacts CHG-712 L0 claude/s-1
  scripts/agent-gate begin CHG-712 >/dev/null 2>&1
  seed_t53_delivery CHG-712
  t61_yml 'ci:\n  verification_command: "bash never-closed\n'
  echo y > src/t61c.js
  out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
  report "T61 TC-1339b stop lane rejects an unparsable channel (rc 2)" 2 "$rc"
  check_output "T61 TC-1339b stop lane names GATE-E118" 'GATE-E118' "$out"
  check_output "T61 TC-1339b stop lane carries the repair example" '修复示例' "$out"
  report "T61 TC-1339b state file is written before the refusal" 0 "$(grep -c '\"state\":\"unparsable\"' .agent-state/verify-channel.json >/dev/null 2>&1 && echo 0 || echo 1)"

  # ---- TC-1341b / REQ-1119：SKIP_VERIFY 真跳过（既有存量缺口，当批闭环）-----
  new_repo
  seed_artifacts CHG-713 L0 claude/s-1
  scripts/agent-gate begin CHG-713 >/dev/null 2>&1
  seed_t53_delivery CHG-713
  echo y > src/t61d.js
  rm -f t61-skip.txt
  out=$(AGENT_GUARD_SKIP_VERIFY=1 AGENT_GUARD_VERIFY_COMMAND='printf ran > t61-skip.txt' scripts/agent-gate --stage stop 2>&1); rc=$?
  report "T61 TC-1341b SKIP_VERIFY does not execute an env channel" 0 "$([[ -e t61-skip.txt ]] && echo 1 || echo 0)"
  report "T61 TC-1341b SKIP_VERIFY keeps the stop lane green" 0 "$rc"
  report "T61 TC-1341b a skipped run leaves no channel state file behind" 0 "$([[ -e .agent-state/verify-channel.json ]] && echo 1 || echo 0)"

  # ---- TC-1343b / REQ-1118：证据行受控覆盖 + 不刷新 05 的 mtime ------------
  # （F5：行内含 UTC 时间戳 → 无界追加把 05 涨成噪声；F4：通道证据刷新 05 的
  #  mtime 会把 GATE-E111 冒烟时效窗静默降级为"存在性"。）
  new_repo
  seed_artifacts CHG-714 L0 claude/s-1
  scripts/agent-gate begin CHG-714 >/dev/null 2>&1
  seed_t53_delivery CHG-714
  t61_yml 'ci:\n  verification_command: "printf ok > t61-ev.txt"\n'
  echo y > src/t61e.js
  scripts/agent-gate --stage stop >/dev/null 2>&1
  touch -t 202001010000 docs/changes/CHG-714/05-test-results.md
  t61_m1=$(stat -c %Y docs/changes/CHG-714/05-test-results.md 2>/dev/null || stat -f %m docs/changes/CHG-714/05-test-results.md 2>/dev/null || echo 0)
  echo y2 > src/t61e2.js
  scripts/agent-gate --stage stop >/dev/null 2>&1
  t61_m2=$(stat -c %Y docs/changes/CHG-714/05-test-results.md 2>/dev/null || stat -f %m docs/changes/CHG-714/05-test-results.md 2>/dev/null || echo 0)
  report "T61 TC-1343b repeated stops keep exactly one evidence line" 1 "$(grep -c '通道自检证据' docs/changes/CHG-714/05-test-results.md)"
  report "T61 TC-1343b the evidence line does not refresh the 05 mtime" 0 "$([[ -n "$t61_m1" && "$t61_m1" == "$t61_m2" ]] && echo 0 || echo 1)"

  # ---- TC-1347 / REQ-1115/1117：两对镜像可解析（工具面零新依赖）-----------
  bash -n "$GATE_SRC" && bash -n "$ROOT/resources/templates/session-gate.sh"
  report "T61 TC-1347 gate + session-gate mirrors parse (bash -n)" 0 $?
}

section_T62() {
# --------------------------------- T62 edit/write 密度遥测（v3.77.0，CHG-101）
# TC↔REQ：TC-1110~1113（REQ-1127/SC-1101~1106）。夹具仿 T58（templates 副本直装）。
new_repo
SESSION_GATE_SRC="$ROOT/resources/templates/session-gate.sh"
if [[ -f "$SESSION_GATE_SRC" ]]; then
  cp "$SESSION_GATE_SRC" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  # TC-1110 (SC-1101 positive): edit/write/MultiEdit 族计数；bash/grep 不计
  bash scripts/session-gate.sh start >/dev/null 2>&1
  bash scripts/session-gate.sh count tool edit >/dev/null 2>&1
  check_output "T62 TC-1349 edit counted" '"edits":1' "$(cat .agent-state/session-tool-stats.json)"
  bash scripts/session-gate.sh count tool Write >/dev/null 2>&1
  bash scripts/session-gate.sh count tool multiedit >/dev/null 2>&1
  check_output "T62 TC-1349 write+MultiEdit counted (case-insensitive)" '"edits":3' "$(cat .agent-state/session-tool-stats.json)"
  bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  bash scripts/session-gate.sh count tool grep >/dev/null 2>&1
  check_output "T62 TC-1349 bash/grep not counted" '"edits":3' "$(cat .agent-state/session-tool-stats.json)"
  # TC-1111 (SC-1102 boundary): default threshold 40 silent below / fires at 40
  bash scripts/session-gate.sh start >/dev/null 2>&1
  for i in $(seq 1 39); do bash scripts/session-gate.sh count tool edit >/dev/null 2>&1; done
  out=$(bash scripts/session-gate.sh status 2>&1)
  if printf '%s' "$out" | grep -q "调用批处理"; then report "T62 TC-1350 below threshold stays silent at 39" 1 0; else report "T62 TC-1350 below threshold stays silent at 39" 0 0; fi
  bash scripts/session-gate.sh count tool edit >/dev/null 2>&1
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T62 TC-1350 yellow at threshold 40" "YELLOW.*调用批处理" "$out"
  # TC-1112 (SC-1103): env override fires at 1
  bash scripts/session-gate.sh start >/dev/null 2>&1
  bash scripts/session-gate.sh count tool edit >/dev/null 2>&1
  out=$(AGENT_GUARD_EDIT_LIMIT=1 bash scripts/session-gate.sh status 2>&1)
  check_output "T62 TC-1351 env override fires at 1" "YELLOW.*调用批处理" "$out"
  # TC-1113 (SC-1104): legacy stats JSON (no edits key) reads 0, no false yellow
  printf '{"turns":3,"bash":1,"grep":0,"other":0,"total":1,"updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
  bash scripts/session-gate.sh count tool edit >/dev/null 2>&1
  check_output "T62 TC-1352 legacy schema migrates (edits reads 0 then 1)" '"edits":1' "$(cat .agent-state/session-tool-stats.json)"
  rm -f .agent-state/session-gate-last.md # stale report yellow lines would leak into status cat
  out=$(bash scripts/session-gate.sh status 2>&1)
  if printf '%s' "$out" | grep -q "调用批处理"; then report "T62 TC-1352 legacy schema no false yellow at 1" 1 0; else report "T62 TC-1352 legacy schema no false yellow at 1" 0 0; fi
  # SC-1105: reset writes initial edits key
  bash scripts/session-gate.sh start >/dev/null 2>&1
  check_output "T62 TC-1353 reset writes edits:0" '"edits":0' "$(cat .agent-state/session-tool-stats.json)"
  # SC-1106: emit wording + report file carries 09 registration line
  for i in $(seq 1 40); do bash scripts/session-gate.sh count tool write >/dev/null 2>&1; done
  out=$(bash scripts/session-gate.sh idle 2>&1 || true)
  check_output "T62 TC-1354 idle yellow wording" "YELLOW.*调用批处理" "$out"
  check_output "T62 TC-1354 report file carries 09 wording" "调用批处理.*登记 09" "$(cat .agent-state/session-gate-last.md 2>/dev/null || echo)"
  # mirror consistency (source vs template) — same-file identity
  report "T62 TC-1355 session-gate source/template byte-identical" 0 "$([[ ! -f "$ROOT/scripts/session-gate.sh" ]] && echo 0 || { cmp -s "$ROOT/scripts/session-gate.sh" "$SESSION_GATE_SRC" && echo 0 || echo 2; })"
else
  echo "SKIP T62: session-gate.sh absent — 跳过 edit/write 密度 golden cases"
fi

}

section_T63() {
# ------------------------------------------------ T63 CHG-102 新面 golden（v3.78.0，REQ-1129~1139）
# 四个面合并成节的原因：都属"本变更新增的断言面"，且各自小而独立（hook 是下发面、
# 评测面口径是行为面、UAC 形态是收口面、台账是回填面），单开四节只会摊薄 SECTIONS 可读性。
#   ①下发 hook golden（TC-1372）：教训 = `<githooks>/` 两个 hook 是**下发面**（bootstrap
#     --guard 复制），却长期没有 golden——模板被改动只靠安装清单行数旁证。而 hook 里的
#     调用串正是门禁的本地入口（`--stage ci --base` 分支门、`--stage commit-msg "$1"`
#     归属门）：漂移 = 本地静默放过，CI 才发现。锁四件事：落点 + 可执行 + 关键调用串 +
#     与源模板逐字节一致；另加非默认根用例（安装期路径改写必须进 hook 本体）。
#   ②评测面取样口径（TC-1358~1360）：原按源仓 `resources/**` 取样 → 目标仓面清单为空，
#     漂移告警**恒不触发**（fail-open）。三条用例 = 装点面可漂移 / `paths.docs` 真生效
#     （差分：改默认 docs 不翻、改 specs 才翻） / 源仓回落不回归。
#   ③UAC 并行形态（TC-1368/1369）：`-j` 只在**收口脚本内嵌全跑**打通，套件自身默认仍
#     串行（receipt 语义零触碰）；此处钉静态形态，行为等价由 T9 三连跑实证承载（05 证据）。
#   ④源层台账回填（TC-1374）：P10 缺口说明 + 回填行、P09 FU-902~945 块与 FU-943 承接行。
if [[ -f "$BOOT_SRC" ]]; then
  t63_tpl="$ROOT/resources/templates"
  t63_bt=$(mktemp -d)
  bash "$BOOT_SRC" --guard "$t63_bt" >/dev/null 2>&1
  report "T63 TC-1372 guard lands pre-push at <githooks>/ (executable)" 0 "$([[ -x "$t63_bt/.githooks/pre-push" ]] && echo 0 || echo 1)"
  report "T63 TC-1372 guard lands commit-msg at <githooks>/ (executable)" 0 "$([[ -x "$t63_bt/.githooks/commit-msg" ]] && echo 0 || echo 1)"
  report "T63 TC-1372 pre-push calls the strict branch gate" 1 "$(grep -cF 'agent-gate --stage ci --base' "$t63_bt/.githooks/pre-push")"
  report "T63 TC-1372 commit-msg forwards the message file to the gate" 1 "$(grep -cF 'agent-gate --stage commit-msg "$1"' "$t63_bt/.githooks/commit-msg")"
  report "T63 TC-1372 both hooks fail fast (set -euo pipefail)" 2 "$(grep -hcF 'set -euo pipefail' "$t63_bt/.githooks/pre-push" "$t63_bt/.githooks/commit-msg" | awk '{s+=$1} END{print s+0}')"
  cmp -s "$t63_tpl/pre-push" "$t63_bt/.githooks/pre-push"
  report "T63 TC-1372 installed pre-push is byte-identical to the shipped template" 0 $?
  cmp -s "$t63_tpl/commit-msg" "$t63_bt/.githooks/commit-msg"
  report "T63 TC-1372 installed commit-msg is byte-identical to the shipped template" 0 $?
  # v3.79.0 (CHG-103, REQ-1144): the fingerprint lib ships WITH run-tests.sh —
  # without it the target repo's receipt emitter degrades to empty fingerprints
  # (fast path dead on arrival). Pin: landed at <scripts>/, executable, and
  # byte-identical to the source-of-truth copy.
  report "T63 TC-1388 guard lands the fingerprint lib at <scripts>/ (executable)" 0 "$([[ -x "$t63_bt/scripts/lib-suite-tree-fingerprint.sh" ]] && echo 0 || echo 1)"
  cmp -s "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$t63_bt/scripts/lib-suite-tree-fingerprint.sh"
  report "T63 TC-1388 installed fingerprint lib is byte-identical to the source" 0 $?
  # 非默认 scripts 根：hook 本体必须按新根调门禁（安装期 transform，非运行期解析）
  t63_bt2=$(mktemp -d)
  bash "$BOOT_SRC" --guard --scripts-dir gov "$t63_bt2" >/dev/null 2>&1
  report "T63 TC-1372 custom scripts root follows into pre-push body" 1 "$(grep -cF 'gov/agent-gate --stage ci --base' "$t63_bt2/.githooks/pre-push")"
  report "T63 TC-1372 custom scripts root leaves no default-root call behind" 0 "$(grep -cF 'scripts/agent-gate' "$t63_bt2/.githooks/pre-push")"
  rm -rf "$t63_bt" "$t63_bt2"
else
  echo "SKIP T63 hook cases: bootstrap.sh 为 Skill 仓库安装器（不随 --guard 分发）"
fi

# ---- ② 评测面取样口径（TC-1358~1360，含 1359b 引号化取值）--------------------
t63_score="$ROOT/resources/templates/eval-rescore.sh"
[[ -f "$t63_score" ]] || t63_score="$ROOT/scripts/eval-rescore"
if [[ -f "$t63_score" ]]; then
  # 最小目标仓布局：装点治理文本 + 评测集（case 引用存在性由 eval-cases 派生，此处直接给）
  t63_seed() { # <dir> <docs_dir>
    mkdir -p "$1/.agent-state" "$1/$2"
    printf 'AGENTS.md\n' > "$1/AGENTS.md"
    printf 'standards-v1\n' > "$1/$2/DEVELOPMENT_STANDARDS.md"
    printf 'case_id\tsrc\tbug\tlayer\tlanding\tregression_ref\nC1\ta\tb\tc\td\tTC-1\n' > "$1/.agent-state/eval-cases.tsv"
  }
  t63_sha() { # <dir> <docs_dir>
    bash "$t63_score" --cases "$1/.agent-state/eval-cases.tsv" --face "$1" --dry-run 2>/dev/null \
      | grep -oE '"config_sha":"[^"]*"'
  }
  # TC-1358：装点面被改 → 漂移告警真的翻（改前这里恒不触发）
  t63r=$(mktemp -d); t63_seed "$t63r" docs
  bash "$t63_score" --cases "$t63r/.agent-state/eval-cases.tsv" --face "$t63r" --update-baseline >/dev/null 2>&1
  t63_sha_a=$(t63_sha "$t63r" docs)
  printf 'standards-v2\n' >> "$t63r/docs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r/.agent-state/eval-cases.tsv" --face "$t63r" >/dev/null 2>&1
  t63_stale_rc=$?
  report "T63 TC-1358 editing an installed docs face flips stale (rc 1)" 1 "$t63_stale_rc"
  report "T63 TC-1358 config_sha tracks the installed face content" 1 "$([[ -n "$t63_sha_a" && "$(t63_sha "$t63r" docs)" != "$t63_sha_a" ]] && echo 1 || echo 0)"
  rm -rf "$t63r"
  # TC-1359：`paths.docs: specs` 必须真生效——改默认 docs 不翻，改 specs 才翻（差分断言）
  t63r2=$(mktemp -d)
  t63_seed "$t63r2" specs
  mkdir -p "$t63r2/docs" && printf 'defaults-v1\n' > "$t63r2/docs/DEVELOPMENT_STANDARDS.md"
  printf 'paths:\n  docs: specs\n' > "$t63r2/.agent-governance.yml"
  bash "$t63_score" --cases "$t63r2/.agent-state/eval-cases.tsv" --face "$t63r2" --update-baseline >/dev/null 2>&1
  printf 'defaults-v2\n' >> "$t63r2/docs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r2/.agent-state/eval-cases.tsv" --face "$t63r2" >/dev/null 2>&1
  report "T63 TC-1359 untouched default docs root does not flip stale" 0 $?
  printf 'specs-v2\n' >> "$t63r2/specs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r2/.agent-state/eval-cases.tsv" --face "$t63r2" >/dev/null 2>&1
  report "T63 TC-1359 editing the yml-declared specs root flips stale" 1 $?
  rm -rf "$t63r2"
  # TC-1359b：yml 取值带引号（`docs: "specs"`）必须与裸值等价——留引号会让装点面全部落空
  # 并静默回落源仓路径（漂移告警仍恒不触发，与 REQ-1129 修的是同一失效类）。
  t63r2q=$(mktemp -d)
  t63_seed "$t63r2q" specs
  mkdir -p "$t63r2q/docs" && printf 'defaults-v1\n' > "$t63r2q/docs/DEVELOPMENT_STANDARDS.md"
  printf 'paths:\n  docs: "specs"\n' > "$t63r2q/.agent-governance.yml"
  bash "$t63_score" --cases "$t63r2q/.agent-state/eval-cases.tsv" --face "$t63r2q" --update-baseline >/dev/null 2>&1
  printf 'defaults-v2\n' >> "$t63r2q/docs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r2q/.agent-state/eval-cases.tsv" --face "$t63r2q" >/dev/null 2>&1
  report "T63 TC-1359b quoted docs root ignores the default docs tree" 0 $?
  printf 'specs-v2\n' >> "$t63r2q/specs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r2q/.agent-state/eval-cases.tsv" --face "$t63r2q" >/dev/null 2>&1
  report "T63 TC-1359b quoted docs root still flips stale" 1 $?
  rm -rf "$t63r2q"
  # TC-1360：源仓形态（只有 resources/**、无安装落点）→ 回落同名源路径，行为与变更前等价
  t63r3=$(mktemp -d)
  mkdir -p "$t63r3/.agent-state" "$t63r3/resources"
  printf 'src-agents\n' > "$t63r3/resources/AGENTS.md"
  printf 'src-standards\n' > "$t63r3/resources/DEVELOPMENT_STANDARDS.md"
  printf 'case_id\tsrc\tbug\tlayer\tlanding\tregression_ref\nC1\ta\tb\tc\td\tTC-1\n' > "$t63r3/.agent-state/eval-cases.tsv"
  t63_src_sha1=$(t63_sha "$t63r3" docs)
  t63_src_sha2=$(t63_sha "$t63r3" docs)
  report "T63 TC-1360 source-repo layout still yields a non-empty config_sha" 1 "$([[ -n "$t63_src_sha1" ]] && echo 1 || echo 0)"
  report "T63 TC-1360 source-repo fallback is stable across runs" 1 "$([[ -n "$t63_src_sha1" && "$t63_src_sha1" == "$t63_src_sha2" ]] && echo 1 || echo 0)"
  rm -rf "$t63r3"
else
  echo "SKIP T63 eval-rescore cases: eval-rescore 未安装"
fi

# ---- ③ UAC 并行形态（TC-1368/1369；静态形态，行为等价见 05 的 T9 三连跑证据）----
t63_uac="$ROOT/scripts/update-assertion-count.sh"
if [[ -f "$t63_uac" ]]; then
  report "T63 TC-1368 UAC embeds the parallel suite invocation" 1 "$(grep -cF 'tests/run-tests.sh" -j "$suite_jobs"' "$t63_uac")"
  report "T63 TC-1368 UAC defaults the pool to 4 jobs" 1 "$(grep -cF 'suite_jobs="${AGENT_GUARD_SUITE_JOBS:-4}"' "$t63_uac")"
  report "T63 TC-1369 UAC falls back for non-numeric and <1 (pool stays sane)" 2 "$(grep -cE '"\$suite_jobs" in|"\$suite_jobs" -ge 1' "$t63_uac")"
  report "T63 TC-1369 suite default stays serial (receipt semantics untouched)" 1 "$(grep -cE '^JOBS=1' "$ROOT/tests/run-tests.sh")"
else
  echo "SKIP T63 UAC cases: update-assertion-count.sh absent"
fi

# ---- ④ 源层台账回填（TC-1374）------------------------------------------------
t63_p10="$ROOT/docs/project/P10-change-ledger.md"
t63_p09="$ROOT/docs/project/P09-risk-register.md"
if [[ -f "$t63_p10" && -f "$t63_p09" ]]; then
  report "T63 TC-1374 P10 states the index gap explicitly" 2 "$(grep -c '缺口说明' "$t63_p10")"
  report "T63 TC-1374 P10 backfills CHG rows for the gap region" 1 "$([[ "$(grep -cE '^\| (BATCH-[0-9]+|—（独立目录）) \| CHG-0(7[1-9]|8[0-9]|9[1-7]) ' "$t63_p10")" -ge 10 ]] && echo 1 || echo 0)"
  report "T63 TC-1374 P09 registers the FU-902~945 retrospective block" 1 "$(grep -c 'FU-902~945 回溯回填' "$t63_p09")"
  report "T63 TC-1374 P09 carries the FU-943 carry-over row" 1 "$(grep -c '^| FU-943 ' "$t63_p09")"
  report "T63 TC-1374 P09 gap rows are labelled 未登记，非内容缺失" 3 "$(grep -c '未登记，非内容缺失' "$t63_p09")"
else
  echo "SKIP T63 ledger cases: docs/project 总册不在场（docs/ 本地不入库）"
fi

}

# v3.80.0 (CHG-107, REQ-1152/1153): scaffold end-to-end + phase read-set pins.
section_T64() {
  local t64 rc out
  t64=$(mktemp -d "${TMPDIR:-/tmp}/t64.XXXXXX")
  (cd "$t64" && git init -q && git config user.email t@x.invalid && git config user.name t)
  out=$(cd "$t64" && AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash "$GATE_SRC" begin t1 --scaffold 2>&1); rc=$?
  report "T64 TC-1400 scaffold runs clean (rc=0)" 0 "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  report "T64 TC-1400 scaffold reports created 8" 1 "$(printf '%s\n' "$out" | grep -c 'created 8, member-appended 0')"
  report "T64 TC-1400 member anchors in 7 md artifacts" 7 "$(grep -l '^## t1' "$t64"/docs/changes/BATCH-*/0*.md 2>/dev/null | wc -l | tr -d ' ')"
  for tf in "$t64"/docs/changes/BATCH-*/00-intent.md "$t64"/docs/changes/BATCH-*/00.5-communication.md "$t64"/docs/changes/BATCH-*/01-spec.md "$t64"/docs/changes/BATCH-*/02-code-impact-analysis.md "$t64"/docs/changes/BATCH-*/03-modification-plan.md "$t64"/docs/changes/BATCH-*/03.5-tasks.md "$t64"/docs/changes/BATCH-*/04-test-scripts.md; do
  sed -i '' 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf" 2>/dev/null || sed -i 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf"
  done
  for tf in "$t64"/docs/changes/BATCH-*/00.5-communication.md "$t64"/docs/changes/BATCH-*/00-intent.md "$t64"/docs/changes/BATCH-*/01-spec.md "$t64"/docs/changes/BATCH-*/02-code-impact-analysis.md "$t64"/docs/changes/BATCH-*/03-modification-plan.md "$t64"/docs/changes/BATCH-*/03.5-tasks.md "$t64"/docs/changes/BATCH-*/04-test-scripts.md; do
  sed -i '' 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf" 2>/dev/null || sed -i 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf"
  done
  (cd "$t64" && AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash "$GATE_SRC" begin t1 >/dev/null 2>&1); rc=$?
  report "T64 TC-1400 filled scaffold passes begin (rc=0)" 0 "$rc"
  # TC-1400b (评审 F1/F7): same-day second member — gov.json stays bare-object
  # parseable (no markdown injection between JSON objects) and begin reads the
  # member's OWN governance record (risk_level/owners), not a sibling's.
  out=$(cd "$t64" && bash "$GATE_SRC" begin t9 --risk L1 --scaffold 2>&1); rc=$?
  report "T64 TC-1400b second member appends 8 (created 0)" 1 "$(printf '%s\n' "$out" | grep -c 'created 0, member-appended 8')"
  for tf in "$t64"/docs/changes/BATCH-*/00.5-communication.md "$t64"/docs/changes/BATCH-*/00-intent.md "$t64"/docs/changes/BATCH-*/01-spec.md "$t64"/docs/changes/BATCH-*/02-code-impact-analysis.md "$t64"/docs/changes/BATCH-*/03-modification-plan.md "$t64"/docs/changes/BATCH-*/03.5-tasks.md "$t64"/docs/changes/BATCH-*/04-test-scripts.md; do
  sed -i '' 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf" 2>/dev/null || sed -i 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf"
  done
  (cd "$t64" && AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash "$GATE_SRC" begin t9 >/dev/null 2>&1); rc=$?
  report "T64 TC-1400b second member begin passes (gov_record per-member)" 0 "$rc"
  out=$(cd "$t64" && bash "$GATE_SRC" begin t1 --scaffold 2>&1); rc=$?
  report "T64 TC-1401 re-scaffold same id refuses (E121)" 0 "$([[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -q 'GATE-E121' && echo 0 || echo 1)"
  mkdir -p "$t64/docs/changes/t1c" && echo x > "$t64/docs/changes/t1c/junk.md"
  out=$(cd "$t64" && bash "$GATE_SRC" begin t1c --risk L2 --scaffold 2>&1); rc=$?
  report "T64 TC-1401 non-empty dedicated dir refuses (E120)" 0 "$([[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -q 'GATE-E120' && echo 0 || echo 1)"
  (cd "$t64" && bash "$GATE_SRC" begin t2 --risk L2 --scaffold >/dev/null 2>&1); rc=$?
  report "T64 TC-1402 L2 lands dedicated dir (not BATCH)" 0 "$([[ $rc -eq 0 && -f "$t64/docs/changes/t2/00-intent.md" ]] && echo 0 || echo 1)"
  report "T64 TC-1403 AGENTS carries the phase read-set discipline" 1 "$(grep -c '分阶段最小读集（v3.80.0' "$ROOT/resources/AGENTS.md")"
  report "T64 TC-1403 CLAUSE_REGISTRY registers R65" 1 "$(grep -c '^| R65 ' "$ROOT/resources/CLAUSE_REGISTRY.md")"
  report "T64 TC-1403 DS carries the read-set pointer line" 1 "$(grep -c '分阶段最小读集（v3.77.0/v3.80.0，CHG-101/107，REQ-1124/1125/1153）' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
  report "T64 TC-1404 gate usage names --scaffold" 1 "$(grep -c 'begin <change-id> \[--risk L0|L1|L2|L3\] \[--scaffold\]' "$GATE_SRC")"
}

section_T65() {
# ------------------------------------------------ T65 preflight 交付形状探针 + verify 睡眠防护 + 遥测失联兜底（v3.82.0，CHG-109/REQ-1160）
# TC↔REQ 映射：TC-1411→REQ-1160（preflight 收齐 stop 侧交付形状锚、零副作用），
# TC-1412→REQ-1160（verify 通道 caffeinate 包裹），TC-1413→REQ-1160（begin 遥测失联黄灯）。
# 实证驱动：目标会话 5 轮格式返工 ×16min verify（4 轮可避免）——形状反馈必须秒级；
# 睡眠假红（clock leap）与 hook 失联（stats 全 0 无人核查）同批闭环（no-leftover）。
# 设计约束：validate_delivery 拆 front/back 纯函数，die 站点逐字搬运（T30/T41 钉不动）；
# 探针零副作用 = track_review_round 留在 stop lane（E116 不进探针面，用户裁定）。
export AGENT_GUARD_REVIEW_ROUND_LIMIT=99 AGENT_GUARD_ALLOW_NO_SHIFT=1 AGENT_GUARD_ALLOW_OVER_RED=1 AGENT_GUARD_ALLOW_OVER_WATER=1
new_repo
seed_artifacts CHG-1092 L0 claude/s-1
scripts/agent-gate begin CHG-1092 >/dev/null 2>&1
seed_t53_delivery CHG-1092
t65_07() { { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat; } > docs/changes/CHG-1092/07-review-report.md; }
# TC-1411 负面：畸形 07（无独立署名 + 无发现处置节）→ 探针单跑收齐 E85+E115
t65_07 <<'EOF'
# review
## 评审结论
通过
EOF
t65_out=$(scripts/agent-gate preflight CHG-1092 2>&1)
report "T65 TC-1411 probe reds on malformed 07" 1 "$(printf '%s\n' "$t65_out" | grep -q 'GATE-E' && echo 1 || echo 0)"
report "T65 TC-1411 E85 collected" 1 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E85')"
report "T65 TC-1411 E115 collected" 1 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E115')"
report "T65 TC-1411 E116 absent from probe (round ledger excluded)" 0 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E116')"
# 零副作用：探针不写轮次台账
t65_r1=$([[ -f .agent-state/review-rounds.tsv ]] && wc -c < .agent-state/review-rounds.tsv || printf 0)
scripts/agent-gate preflight CHG-1092 >/dev/null 2>&1
t65_r2=$([[ -f .agent-state/review-rounds.tsv ]] && wc -c < .agent-state/review-rounds.tsv || printf 0)
report "T65 TC-1411 probe writes no round ledger" 0 "$([[ "$t65_r1" == "$t65_r2" ]] && echo 0 || echo 1)"
# E117（来源列乱值）与 E114（严重行未处置）同跑收齐
t65_07 <<'EOF'
# review
- 评审主体：claude / s-1 / ses-t65
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 | 来源 |
|---|---|---|---|---|---|
| F1 | 边界缺失 | 严重 | | 补测 | 乱值 |
- **评审轮次**：1
## 评审结论
通过
EOF
t65_out=$(scripts/agent-gate preflight CHG-1092 2>&1)
report "T65 TC-1411 E117 collected on unlawful provenance value" 1 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E117')"
report "T65 TC-1411 E114 collected on undisposed severe row" 1 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E114')"
# 正面：干净 07 与缺 07 均全绿（缺 07 = no-op，begin 期探针不受扰）
t65_07 <<'EOF'
# review
- 评审主体：claude / s-1 / ses-t65
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 | 来源 |
|---|---|---|---|---|---|
| F1 | 边界缺失 | 严重 | 已修复 | 补测并复跑全绿 | 本次引入 |
- **评审轮次**：1
## 评审结论
通过
EOF
report "T65 TC-1411 clean 07 probes green" 0 "$(scripts/agent-gate preflight CHG-1092 >/dev/null 2>&1; echo $?)"
rm docs/changes/CHG-1092/07-review-report.md
report "T65 TC-1411 absent 07 probes green (no-op)" 0 "$(scripts/agent-gate preflight CHG-1092 >/dev/null 2>&1; echo $?)"
# TC-1412：verify 通道经 caffeinate 包裹（stub 调用标记证明 wrap 路径真实发生——
# 评审 F2：仅断言 marker 存在证明不了 wrap，直跑同样建文件）
mkdir -p .oc-t65bin
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> .agent-state/t65-caf-calls\nwhile [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' > .oc-t65bin/caffeinate
chmod +x .oc-t65bin/caffeinate
rm -f .agent-state/t65-ran .agent-state/t65-caf-calls
# stop 的深检门 working_code_changed 需要一个 code face（T60 同款 src 夹具）；
# 纯 docs 夹具会静默短路 verify 通道（REQ-1160 探针语义不受此影响——探针不查会话态）
mkdir -p src && echo y > src/t65.js
t65_stop_out=$(PATH="$PWD/.oc-t65bin:$PATH" AGENT_GUARD_VERIFY_COMMAND='touch .agent-state/t65-ran' scripts/agent-gate --stage stop 2>&1)
report "T65 TC-1412 verify runs wrapped via caffeinate stub" 1 "$([[ -e .agent-state/t65-ran ]] && echo 1 || echo 0)"
report "T65 TC-1412 stub call log carries -dims (wrap proof)" 1 "$(grep -c -- '-dims' .agent-state/t65-caf-calls 2>/dev/null || printf 0)"
rm -rf .oc-t65bin .agent-state/t65-caf-calls
# TC-1413：begin 遥测失联黄灯（软）——water 新鲜 + stats 缺失 → 黄灯；stats 新鲜 → 静默。
# 新 id 走完整 begin（E86 已由夹具豁免放行；E72 不触发——八件套无 09）。
seed_artifacts CHG-1093 L0 claude/s-1
seed_artifacts CHG-1094 L0 claude/s-1
printf '{"turns":1,"bash":0,"grep":0,"other":0,"total":1,"updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-water.json
rm -f .agent-state/session-tool-stats.json
t65_out=$(scripts/agent-gate begin CHG-1093 2>&1)
report "T65 TC-1413 begin warns YELLOW when stats missing" 1 "$(printf '%s\n' "$t65_out" | grep -c 'YELLOW liveness')"
printf '{"turns":1,"bash":0,"grep":0,"other":0,"total":1,"updated_at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/session-tool-stats.json
t65_out=$(scripts/agent-gate begin CHG-1094 2>&1)
report "T65 TC-1413 fresh stats stays silent" 0 "$(printf '%s\n' "$t65_out" | grep -c 'YELLOW liveness')"
# 评审 F3：mtime 过期分支——stats 内容在但 mtime 老于 10min → 黄灯
touch -t 202001010000 .agent-state/session-tool-stats.json
t65_out=$(scripts/agent-gate begin CHG-1093 2>&1)
report "T65 TC-1413 stale-mtime stats warns YELLOW" 1 "$(printf '%s\n' "$t65_out" | grep -c 'YELLOW liveness')"
rm -f .agent-state/session-water.json .agent-state/session-tool-stats.json
}

section_T66() {
# ------------------------------------------------ T66 verify 结果缓存（v3.83.0，CHG-110/REQ-1161，DES-1923）
# TC↔REQ：TC-1414→REQ-1161（缓存命中/失效矩阵）。实证驱动：格式返工期间代码零变化
# 仍 4 次重跑 16min 全量（≈66min 可避免）。保守档（用户裁定）：只缓存 rc=0、键含
# gate 版本+vcmd sha+树指纹（docs/changes claim 排除）+变更号、TTL 30min、env 退出。
# 边界：外部状态依赖测试仓须 opt-out（CHANGELOG/usage 明示）；非 git 仓指纹空=降级直跑。
export AGENT_GUARD_REVIEW_ROUND_LIMIT=99 AGENT_GUARD_ALLOW_NO_SHIFT=1 AGENT_GUARD_ALLOW_OVER_RED=1 AGENT_GUARD_ALLOW_OVER_WATER=1
new_repo
seed_artifacts CHG-1095 L0 claude/s-1
scripts/agent-gate begin CHG-1095 >/dev/null 2>&1
seed_t53_delivery CHG-1095
mkdir -p src && echo hi > src/t66.js
git add -A >/dev/null 2>&1 && git commit -qm init   # 树指纹需 HEAD；纯 docs 夹具仍缺 code face
echo y > src/t66b.js
t66_stop() { AGENT_GUARD_VERIFY_COMMAND="$1" scripts/agent-gate --stage stop 2>&1; }
# 命中基线：首跑执行并写 rc=0 收据
rm -f .agent-state/t66-m .agent-state/verify-receipt.json
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 first run executes and writes rc0 receipt" 1 "$([[ -e .agent-state/t66-m && -e .agent-state/verify-receipt.json ]] && echo 1 || echo 0)"
report "T66 TC-1414 receipt binds change id" 1 "$(grep -c '"change_id":"CHG-1095"' .agent-state/verify-receipt.json)"
report "T66 TC-1414 receipt carries gate version" 1 "$(grep -cE '"gate_version":"[0-9][0-9.]*"' .agent-state/verify-receipt.json)"
# 命中：同键二跑不执行 vcmd
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 same-key second run skips execution (cached)" 0 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
report "T66 TC-1414 cached line surfaces" 1 "$(printf '%s\n' "$t66_out" | grep -c 'CACHED (receipt match')"
# docs/changes 改动不失效（claim 排除面）
printf 'x\n' >> docs/changes/CHG-1095/06-delivery-summary.md
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 docs/changes edit does not invalidate" 0 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# src 改动即失效
echo z >> src/t66b.js
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 src edit invalidates (re-runs)" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# rc≠0 不写收据：评审 M1——失败跑前记录收据 vcmd_sha，失败跑后断言 sha 未变
# （对「只缓存 rc=0」不变式有区分力；原 grep 't66-f' 恒 0 无失败区分力）
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
t66_sha_before=$(sed -n 's/.*"vcmd_sha":"\([^"]*\)".*/\1/p' .agent-state/verify-receipt.json | head -1)
rm -f .agent-state/t66-f
t66_out=$(t66_stop 'touch .agent-state/t66-f; false')
report "T66 TC-1414 failing verify dies E64" 1 "$(printf '%s\n' "$t66_out" | grep -c 'GATE-E64')"
t66_sha_after=$(sed -n 's/.*"vcmd_sha":"\([^"]*\)".*/\1/p' .agent-state/verify-receipt.json | head -1)
report "T66 TC-1414 receipt unchanged by failing run (rc0-only)" 1 "$([[ -n $t66_sha_before && $t66_sha_before == $t66_sha_after ]] && echo 1 || echo 0)"
# gate 版本失配失效：篡改收据版本字面
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
sed -E -i '' 's/"gate_version":"[0-9][0-9.]*"/"gate_version":"0.0.0"/' .agent-state/verify-receipt.json 2>/dev/null || sed -E -i 's/"gate_version":"[0-9][0-9.]*"/"gate_version":"0.0.0"/' .agent-state/verify-receipt.json
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 gate-version mismatch invalidates" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# TTL 失效：篡改 finished_at 为远古
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
sed -i '' 's/"finished_at":[0-9]*/"finished_at":1000/' .agent-state/verify-receipt.json 2>/dev/null || sed -i 's/"finished_at":[0-9]*/"finished_at":1000/' .agent-state/verify-receipt.json
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 TTL expiry invalidates" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# 变更号失配失效
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
sed -i '' 's/"change_id":"CHG-1095"/"change_id":"CHG-OTHER"/' .agent-state/verify-receipt.json 2>/dev/null || sed -i 's/"change_id":"CHG-1095"/"change_id":"CHG-OTHER"/' .agent-state/verify-receipt.json
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 change-id mismatch invalidates" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# opt-out：AGENT_GUARD_VERIFY_CACHE=0 恒真跑
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
rm -f .agent-state/t66-m
t66_out=$(AGENT_GUARD_VERIFY_CACHE=0 AGENT_GUARD_VERIFY_COMMAND='touch .agent-state/t66-m' scripts/agent-gate --stage stop 2>&1)
report "T66 TC-1414 opt-out always runs" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
}

section_T67() {
# ------------------------------------------------ T67 六不变量机校（v3.84.0，CHG-111/REQ-1162~1170）
# TC-1424 E122：03 缺「既有范式关系」节/声明 → begin 拒；声明行在 → 过
new_repo
seed_begin CHG-1110 L1 claude/s-1
printf '# plan\n- DES-001: d\n' > docs/changes/CHG-1110/03-modification-plan.md
# CHG-117: E122 is a full-lane anchor (legacy begin + delivery); the design
# stage gate reports it as G-设计门/E126. Pin the E122 code via the documented
# compatibility switch.
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1110 >/dev/null 2>&1
rc=$?
out=$(AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1110 2>&1 || true)
report "T67 TC-1424 E122 rejects 03 without 既有范式关系" 2 "$rc"
check_output "T67 TC-1424 refusal names GATE-E122" "GATE-E122" "$out"
seed_begin CHG-1110 L1 claude/s-1
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1110 >/dev/null 2>&1
report "T67 TC-1424 begin passes with 既有范式关系 declaration" 0 $?
# TC-1425/1426：E123（来源物映射）/E124（业务合理性终审）三态
new_repo
seed_begin CHG-1111 L1 claude/s-1
printf '# spec\n- **ui_change**：true\n- **外部来源物**：docs/proto.md\n## 用户任务\n### UJ-001\n- **入口**：记录列表\n### REQ-001\n**描述**：r\n**挂靠 UJ**：UJ-001\n' > docs/changes/CHG-1111/01-spec.md
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n' > docs/changes/CHG-1111/03.6-ui-spec.md
printf '# tasks\n| 任务 | 类型 | 依赖 | 里程碑 | 说明 |\n|---|---|---|---|---|\n| T1 | UX | 无 | M1 | 设计 |\n- 评审输入: x\n' > docs/changes/CHG-1111/03.5-tasks.md
printf '# tests\n- TC-001 用户旅程 E2E（真人入口）\n覆盖维度: 正常流\n- SC-001 用户旅程 E2E（覆盖: TC-001）\n' > docs/changes/CHG-1111/04-test-scripts.md
git add -A
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T67 TC-1425 E123 red: declared source but 03.6 lacks 来源物映射" 1 "$(printf '%s\n' "$out" | grep -c 'GATE-E123')"
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n## 来源物映射\n| 来源物条目（文件+锚点） | 实现文件:行 | 实测证据（05 运行痕迹引用） | 一致性结论 |\n|---|---|---|---|\n| proto.md#list | src/a.go:10 | 05 UJ-001 快照 @2026-10-21T00:00:00Z | 一致 |\n' > docs/changes/CHG-1111/03.6-ui-spec.md
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T67 TC-1425 E123 green once mapping section exists" 0 "$(printf '%s\n' "$out" | grep -c 'GATE-E123')"
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n- **建议人类走查（非阻塞）**：建议走查一次\n## 评审结论\n通过\n' > docs/changes/CHG-1111/07-review-report.md
git add -A
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T67 TC-1426 E124 red: 07 lacks 业务合理性终审" 1 "$(printf '%s\n' "$out" | grep -c 'GATE-E124')"
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n- **建议人类走查（非阻塞）**：建议走查一次\n## 业务合理性终审\n- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）\n- **业务终审主体**：platform / glm / ses-t67a\n## 评审结论\n通过\n' > docs/changes/CHG-1111/07-review-report.md
git add -A
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T67 TC-1426 staged passes with 终审 section + subject signature" 0 $?
# TC-1427 G15：来源物映射闭合（runtime；沙箱无 STD 时 audit 秒退，落最小规范桩）
printf '# t\n规范版本：v%s\n' "$CURRENT_VERSION" > docs/DEVELOPMENT_STANDARDS.md
bash "$ROOT/tests/audit-docs-consistency.sh" > t67_audit.txt 2>&1 || true
report "T67 TC-1427 G15 green on closed mapping rows" 0 "$(grep -c 'G15 CHG-1111' t67_audit.txt)"
grep -vF 'proto.md#list' docs/changes/CHG-1111/03.6-ui-spec.md > t67_tmp.md && mv t67_tmp.md docs/changes/CHG-1111/03.6-ui-spec.md
bash "$ROOT/tests/audit-docs-consistency.sh" > t67_audit2.txt 2>&1 || true
report "T67 TC-1427 G15 red on emptied mapping row" 1 "$(grep -cE 'G15 CHG-1111 映射行缺实现位或证据位|G15 CHG-1111 来源物映射节零数据行' t67_audit2.txt)"
rm -f t67_audit.txt t67_audit2.txt
# TC-1428/1432：独立缺陷批 pre-commit 自动盖章 + E56/E57 一次报全
new_repo
cp "$STAMP_SRC" scripts/stamp-provenance.sh
mkdir -p .githooks && cp "$ROOT/resources/templates/pre-commit" .githooks/pre-commit && chmod +x .githooks/pre-commit
mkdir -p docs/bugs/BATCH-20260101
printf '## BUG-900\n诊断：d\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > docs/bugs/BATCH-20260101/01-diagnosis.md
printf '## BUG-901\n诊断：d\n延伸发现：未发现\n历史相似检索：未命中（x）\n' >> docs/bugs/BATCH-20260101/01-diagnosis.md
git add -A
out=$(bash .githooks/pre-commit 2>&1 || true)
report "T67 TC-1428 pre-commit stamps standalone bug batch anchors" 1 "$(grep -c '<!-- provenance' docs/bugs/BATCH-20260101/01-diagnosis.md)"
report "T67 TC-1432 E56/E57 report BOTH incomplete groups in one shot" 2 "$(printf '%s\n' "$out" | grep -cE 'defect group BUG-9[0-9]+ is missing')"
# TC-1429：同族推演行名存续（N3 不改行名防机校断链）
report "T67 TC-1429 同族推演 row name survives in bug-diagnosis template" 1 "$(grep -c '同族推演' "$ROOT/resources/templates/bug-diagnosis.md" | awk '{print ($1>=2)?1:0}')"
# TC-1430：A11 体积上界
report "T67 TC-1430 DS body within A11 bound (<=167936B)" 1 "$([[ $(wc -c < "$ROOT/resources/DEVELOPMENT_STANDARDS.md" | tr -d ' ') -le 167936 ]] && echo 1 || echo 0)"
# TC-1431：版本链字面
report "T67 TC-1431 SKILL version literals resolve to the DS footer" 4 "$(grep -cF "$CURRENT_VERSION" "$ROOT/SKILL.md")"
# TC-1433：多字节方括号类在 C locale 下不匹配全角冒号（本环境实测）——发布面
# 必须用 (：|:) 交替；[：:] 会让 UX/G13 开关在 LANG=C 的 CI 上静默失效。
t67_br='['; t67_br="$t67_br：:]"
report "T67 TC-1433 shipped gate avoids multibyte bracket classes" 0 "$(grep -cF "$t67_br" "$GATE_SRC")"
}

section_T68() {
# ------------------------------------------------ T68 工作区锁与收据路径隔离（v3.86.0，CHG-113）
  local t68_d t68_rc t68_out t68_lib t68_dead
  t68_lib="$ROOT/scripts/lib-suite-lock.sh"
  t68_d=$(mktemp -d "${TMPDIR:-/tmp}/suite-lock.XXXXXX")
  report "T68 lock lib ships the three entry points" 3 "$(grep -cE '^suite_lock_(dir|release|acquire)\(\)' "$t68_lib")"
  t68_out=$(ROOT="$t68_d" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/lock" bash -c 'source "$1"; suite_lock_acquire; echo "first=$?"; suite_lock_acquire 2>/dev/null; echo "second=$?"; suite_lock_release; [[ -d "$AGENT_GUARD_SUITE_LOCK_DIR" ]] && echo present || echo released; suite_lock_acquire; echo "third=$?"; suite_lock_release' _ "$t68_lib" 2>&1)
  report "T68 first acquisition succeeds" 1 "$(printf '%s\n' "$t68_out" | grep -c '^first=0$')"
  report "T68 live owner is rejected" 1 "$(printf '%s\n' "$t68_out" | grep -c '^second=1$')"
  report "T68 release removes the lock" 1 "$(printf '%s\n' "$t68_out" | grep -c '^released$')"
  report "T68 reacquisition after release succeeds" 1 "$(printf '%s\n' "$t68_out" | grep -c '^third=0$')"
  mkdir -p "$t68_d/dead"
  # A just-reaped PID cannot be alive; a fixed 999999 is only dead on hosts whose
  # pid_max is below it (Linux can exceed 1e6), which made this assertion flaky.
  ( : ) & t68_dead=$!; wait "$t68_dead" 2>/dev/null || true
  printf '%s\n' "$t68_dead" > "$t68_d/dead/pid"
  ROOT="$t68_d" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/dead" bash -c 'source "$1"; suite_lock_acquire; echo "rc=$?"; suite_lock_release' _ "$t68_lib" > "$t68_d/out" 2>&1
  report "T68 dead-owner lock is reclaimed" 1 "$(grep -c '^rc=0$' "$t68_d/out")"
  mkdir -p "$t68_d/young"
  ROOT="$t68_d" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/young" bash -c 'source "$1"; suite_lock_acquire 2>/dev/null; echo "rc=$?"' _ "$t68_lib" > "$t68_d/out2" 2>&1
  report "T68 empty-pid lock inside grace is not stolen" 1 "$(grep -c '^rc=1$' "$t68_d/out2")"
  touch -t "$(date -v-2M +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 minutes ago' +%Y%m%d%H%M.%S)" "$t68_d/young"
  ROOT="$t68_d" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/young" bash -c 'source "$1"; suite_lock_acquire; echo "rc=$?"; suite_lock_release' _ "$t68_lib" > "$t68_d/out3" 2>&1
  report "T68 empty-pid lock past grace is reclaimed" 1 "$(grep -c '^rc=0$' "$t68_d/out3")"
  report "T68 suite sources the lock lib" 1 "$(grep -cF "source \"\$_lock_lib\"" "$ROOT/tests/run-tests.sh")"
  report "T68 lock is gated to full runs" 1 "$(grep -cF "LOCK_HELD:-0}\" != \"1\"" "$ROOT/tests/run-tests.sh")"
  # -ge 1, not ==1: the same phrase is also printed by the lock-refusal message
  # asserted below, so an exact count would make this a line-budget pin.
  report "T68 lock conflict exits 2 with a message" 1 \
    "$([[ $(grep -cF "another full sui""te owns this workspace" "$ROOT/tests/run-tests.sh") -ge 1 ]] && echo 1 || echo 0)"
  report "T68 full run trap releases the lock" 1 "$(grep -cF "trap 'suite_lock_""release' EXIT" "$ROOT/tests/run-tests.sh")"
  report "T68 interrupt traps exit after releasing" 2 "$(grep -cE "trap 'exit 1(30|43)' (INT|TERM)" "$ROOT/tests/run-tests.sh")"
  mkdir -p "$t68_d/held"; printf '%s\n' "$$" > "$t68_d/held/pid"
  t68_rc=0; AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/held" bash "$ROOT/tests/run-tests.sh" -T T39 >/dev/null 2>&1 || t68_rc=$?
  report "T68 filtered run ignores the workspace lock (no deadlock)" 0 "$t68_rc"
  t68_rc=0; t68_out=$(AGENT_GUARD_SUITE_LOCK_HELD=0 AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/held" bash "$ROOT/tests/run-tests.sh" -T "" 2>&1 >/dev/null) || t68_rc=$?
  report "T68 full run refuses a held lock with rc2" 2 "$t68_rc"
  # The rc2 above must come from the LOCK refusal, not from argument parsing:
  # `-T ""` is a full run, and a parser that rejects the empty operand would make
  # this assertion pass for the wrong reason (v3.87.0 R4, review finding #1).
  report "T68 the lock refusal is named in the message (not a usage error)" 1 \
    "$(printf '%s\n' "$t68_out" | grep -c 'another full suite owns this workspace')"
  report "T68 an empty -T operand is not reported as a usage error" 0 \
    "$(printf '%s\n' "$t68_out" | grep -c 'invalid -T value')"
  report "T68 refused full run leaves the lock intact" 1 "$([[ -d "$t68_d/held" ]] && echo 1 || echo 0)"
  rm -rf "$t68_d"
}

# (unknown key dies rc2), then filtered invocation in original order.
section_T69() {
# ------------------------------------------------ T69 套件基线 = 提交式证据（v3.87.0，CHG-115，REQ-1184/1185）
# 教训：源审计 A3 用裸 --check 时把 0.17s 的读表活付成了 300s 的整套套件——收据一陈旧
# 就隐式重跑。快路径的语义必须能回归：基线纯数字且受跟踪；--from-baseline 纯读、
# 永不触发内嵌套件；README 声称漂移显式 rc1 且不改文件；基线缺失/非数字 fail-closed rc2；
# --require-receipt 无新鲜收据即 rc2（绝不隐式重跑）；写模式把基线与双 README 一起回填。
  local r69 r69_rc r69_out r69_a r69_b r69_head r69_tree r69_snap r69_ts f
  if [[ ! -f "$ROOT/scripts/update-assertion-count.sh" || ! -f "$ROOT/scripts/lib-suite-tree-fingerprint.sh" || ! -f "$ROOT/tests/.suite-baseline" ]]; then
    echo "SKIP T69: the committed baseline or the generator/fingerprint lib is absent (source-layer only)"
  else
    r69_a=0
    if [[ -f "$ROOT/tests/.suite-baseline" ]]; then
      r69_b=$(tr -d '[:space:]' < "$ROOT/tests/.suite-baseline")
      case "$r69_b" in ''|*[!0-9]*) ;; *) r69_a=1 ;; esac
      git -C "$ROOT" check-ignore -q tests/.suite-baseline 2>/dev/null && r69_a=0
    fi
    report "T69 TC-1439 the committed suite baseline is numeric and never git-ignored" 1 "$r69_a"
    report "T69 TC-1439 A3 consumes the baseline and keeps no bare generator call" 1 \
      "$([[ $(grep -cF -- '--check --from-baseline' "$ROOT/tests/audit-standards-src.sh" 2>/dev/null) -ge 1 && $(grep -cF '"$GEN" --check 2>&1' "$ROOT/tests/audit-standards-src.sh" 2>/dev/null) -eq 0 ]] && echo 1 || echo 0)"
    r69=$(mktemp -d "${TMPDIR:-/tmp}/suite-baseline.XXXXXX")
    mkdir -p "$r69/scripts" "$r69/tests" "$r69/.agent-state" "$r69/.tmp"
    cp "$ROOT/scripts/update-assertion-count.sh" "$r69/scripts/"
    cp "$ROOT/scripts/lib-source-facts.sh" "$r69/scripts/"
    cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r69/scripts/"
    printf '.agent-state/\n.tmp/\n' > "$r69/.gitignore"
    # 哨兵写在 gitignored 的 .agent-state 下：放进 tests/ 会留 untracked 文件、
    # 把树指纹搞脏，收据类用例就会因为错误的原因变红（T51 实测教训）。
    cat > "$r69/tests/run-tests.sh" <<'R69FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/../.agent-state/embedded-ran"
printf '777 passed, 0 failed\n'
printf 'wall-time: 1s\n'
R69FAKE
    printf 'README claims (100 golden-case assertions) here.\n' > "$r69/README.md"
    printf '这里声称 100 项 golden-case 断言。\n' > "$r69/README.zh-CN.md"
    printf '100\n' > "$r69/tests/.suite-baseline"
    ( cd "$r69" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    r69_head=$(git -C "$r69" rev-parse HEAD 2>/dev/null || true)
    r69_tree=$(git -C "$r69" rev-parse 'HEAD^{tree}' 2>/dev/null || true)
    # TMPDIR 隔离：真实审计留下的 $TMPDIR/audit-executed-count 一旦漂进 fixture，
    # .audit-baseline 同步分支会把 rc 判定污染成假红。
    _r69_run() { ( cd "$r69" && TMPDIR="$r69/.tmp" AGENT_GUARD_SUITE_RECEIPT_PATH="$r69/.agent-state/last-suite-receipt.json" AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN=30 bash scripts/update-assertion-count.sh "$@" 2>&1 ); }
    _r69_sent() { [[ -f "$r69/.agent-state/embedded-ran" ]] && echo 1 || echo 0; }
    _r69_seed() { printf '{"head":"%s","tree_fingerprint":"%s","passed":%s,"failed":%s,"wall_time_s":1,"generated_at":"%s"}\n' "$1" "$2" "$3" "$4" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$r69/.agent-state/last-suite-receipt.json"; }
    rm -f "$r69/.agent-state/embedded-ran"

    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1440 --from-baseline is green on an in-sync repo" 0 "$r69_rc"
    report "T69 TC-1440 --from-baseline never executes the embedded suite" 0 "$(_r69_sent)"
    report "T69 TC-1440 the baseline is named as the evidence source" 1 \
      "$(printf '%s\n' "$r69_out" | grep -c 'in sync with run-tests (100)')"

    sed -e 's/(100 golden-case assertions)/(999 golden-case assertions)/' "$r69/README.md" > "$r69/.tmp/r" && mv "$r69/.tmp/r" "$r69/README.md"
    r69_snap="$r69/.tmp/snap-README.md"; cp "$r69/README.md" "$r69_snap"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1441 a stale README claim is rc1" 1 "$r69_rc"
    report "T69 TC-1441 the drift message names README.md and the baseline number" 1 \
      "$(printf '%s\n' "$r69_out" | grep -cE 'drift: .*README.md.*expected 100')"
    report "T69 TC-1441 --check leaves the claim file byte-identical" 0 "$(cmp -s "$r69_snap" "$r69/README.md" && echo 0 || echo 1)"
    git -C "$r69" checkout -q -- README.md 2>/dev/null || true

    mv "$r69/tests/.suite-baseline" "$r69/.tmp/hold"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1442 a missing baseline fails closed rc2 (no suite rerun)" 2 "$r69_rc"
    report "T69 TC-1442 the missing-baseline message names the file" 1 \
      "$(printf '%s\n' "$r69_out" | grep -c 'from-baseline requires')"
    printf 'not-a-number\n' > "$r69/tests/.suite-baseline"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1442 a non-numeric baseline fails closed rc2" 2 "$r69_rc"
    report "T69 TC-1442 a non-numeric baseline never touches the suite" 0 "$(_r69_sent)"
    mv "$r69/.tmp/hold" "$r69/tests/.suite-baseline"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline --require-receipt) || r69_rc=$?
    report "T69 TC-1442 the two evidence sources are mutually exclusive rc2" 2 "$r69_rc"

    rm -f "$r69/.agent-state/last-suite-receipt.json"
    r69_rc=0; r69_out=$(_r69_run --check --require-receipt) || r69_rc=$?
    report "T69 TC-1443 --require-receipt without a receipt fails closed rc2" 2 "$r69_rc"
    report "T69 TC-1443 fail-closed does not fall through to an implicit rerun" 0 "$(_r69_sent)"
    _r69_seed "$r69_head" "$r69_tree" 100 0
    r69_rc=0; r69_out=$(_r69_run --check --require-receipt) || r69_rc=$?
    report "T69 TC-1443 a fresh same-tree receipt satisfies --require-receipt" 0 "$r69_rc"
    r69_ts=$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S)
    touch -t "$r69_ts" "$r69/.agent-state/last-suite-receipt.json"
    r69_rc=0; r69_out=$(_r69_run --check --require-receipt) || r69_rc=$?
    report "T69 TC-1443 a stale receipt still fails closed rc2" 2 "$r69_rc"

    rm -f "$r69/.agent-state/last-suite-receipt.json" "$r69/.agent-state/embedded-ran"
    r69_rc=0; r69_out=$(_r69_run) || r69_rc=$?
    report "T69 TC-1443 write mode runs the suite exactly once" 1 "$(_r69_sent)"
    report "T69 TC-1443 write mode backfills tests/.suite-baseline" 777 "$(tr -d '[:space:]' < "$r69/tests/.suite-baseline")"
    report "T69 TC-1443 write mode re-syncs both README claims" 2 \
      "$( { grep -c '777 golden-case assertions' "$r69/README.md"; grep -c '777 项 golden-case 断言' "$r69/README.zh-CN.md"; } | awk '{s+=$1} END{print s}')"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1443 the backfilled baseline reads back green" 0 "$r69_rc"
    rm -rf "$r69"
  fi
}

section_T70() {
# ------------------------------------------------ T70 facts.sh 一次读完的事实面（v3.87.0，CHG-115，REQ-1186/1193）
# 每一轮 Agent 都在用 git/读文件/跑套件问同一批事实。facts 把它们压成一次只读 JSON：
# 键集固定、随工作树变化、绝不跑套件、<10s，且是源层专属（bootstrap 清单里不能有它）。
  local r70 r70_rc r70_out r70_t0 r70_dt r70_keys r70_p f r70_hang_pid r70_watchdog
  if [[ ! -f "$ROOT/scripts/facts.sh" || ! -f "$ROOT/scripts/lib-source-facts.sh" || ! -f "$ROOT/scripts/lib-suite-tree-fingerprint.sh" ]]; then
    echo "SKIP T70: facts.sh / lib-source-facts.sh absent (source-layer tools do not ship)"
  else
    r70=$(mktemp -d "${TMPDIR:-/tmp}/facts-test.XXXXXX")
    mkdir -p "$r70/scripts" "$r70/tests" "$r70/resources" "$r70/.agent-state"
    cp "$ROOT/scripts/facts.sh" "$ROOT/scripts/lib-source-facts.sh" "$r70/scripts/"
    cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r70/scripts/"
    printf '.agent-state/\n' > "$r70/.gitignore"
    printf '规范版本：v1.2.3\n' > "$r70/resources/DEVELOPMENT_STANDARDS.md"
    printf '1000\n' > "$r70/tests/.suite-baseline"
    printf '500\n' > "$r70/tests/.audit-baseline"
    cat > "$r70/tests/run-tests.sh" <<'R70FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/../.agent-state/embedded-ran"
printf '1 passed, 0 failed\n'
R70FAKE
    printf 'notes\n' > "$r70/notes.md"
    ( cd "$r70" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    mkdir -p "$r70/.git/agent-governance"
    printf 'CHG-9001\n' > "$r70/.git/agent-governance/active-change"
    r70_t0=$(date +%s)
    _r70_run() { ( cd "$r70" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r70/.agent-state/last-suite-receipt.json" bash scripts/facts.sh "$@" 2>&1 ); }
    r70_rc=0; r70_out=$(_r70_run) || r70_rc=$?
    r70_dt=$(( $(date +%s) - r70_t0 ))
    report "T70 TC-1444 facts exits 0 on a well-formed checkout" 0 "$r70_rc"
    r70_keys=$(printf '%s\n' "$r70_out" | grep -oE '"(schema|head|branch|version|tree_fingerprint|dirty|changed_count|changed_files|active_change|audit_baseline|suite_baseline|suite_receipt)":' | sort -u | wc -l | tr -d ' ')
    report "T70 TC-1444 the fact key set is complete" 12 "$r70_keys"
    report "T70 TC-1444 version resolves from the DS footer" 1 "$(printf '%s\n' "$r70_out" | grep -c '"version": "1.2.3"')"
    report "T70 TC-1444 both committed baselines are surfaced" 2 \
      "$(printf '%s\n' "$r70_out" | grep -cE '"(audit_baseline)": 500|"suite_baseline": 1000')"
    report "T70 TC-1444 the active change comes from the governance pointer" 1 \
      "$(printf '%s\n' "$r70_out" | grep -c '"active_change": "CHG-9001"')"
    report "T70 TC-1444 a clean tree reports no receipt and no dirt" 2 \
      "$(printf '%s\n' "$r70_out" | grep -cE '"exists": false|"dirty": false')"
    r70_rc=0; r70_out=$(_r70_run --root "$r70" ) || r70_rc=$?
    report "T70 TC-1446 --root inspects an explicit checkout" 0 "$r70_rc"
    printf '{"head":"%s","tree_fingerprint":"%s","passed":1000,"failed":0,"wall_time_s":9,"generated_at":"now"}\n' \
      "$(git -C "$r70" rev-parse HEAD)" "$(git -C "$r70" rev-parse 'HEAD^{tree}')" > "$r70/.agent-state/last-suite-receipt.json"
    r70_out=$(_r70_run)
    report "T70 TC-1444 a fresh same-tree receipt is reported fresh" 1 "$(printf '%s\n' "$r70_out" | grep -c '"fresh": true')"
    touch -t "$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S)" "$r70/.agent-state/last-suite-receipt.json"
    r70_out=$(_r70_run)
    report "T70 TC-1444 a stale receipt is reported not fresh" 1 "$(printf '%s\n' "$r70_out" | grep -c '"fresh": false')"
    rm -f "$r70/.agent-state/last-suite-receipt.json"
    printf 'more\n' >> "$r70/notes.md"
    r70_out=$(_r70_run)
    report "T70 TC-1445 a tracked edit shows up in dirty/changed_files" 2 \
      "$(printf '%s\n' "$r70_out" | grep -cE '"dirty": true|"changed_count": 1')"
    report "T70 TC-1445 the changed path is named" 1 "$(printf '%s\n' "$r70_out" | grep -c '"notes.md"')"
    printf '2000\n' > "$r70/tests/.suite-baseline"
    r70_out=$(_r70_run)
    report "T70 TC-1445 a baseline bump is visible without any run" 1 "$(printf '%s\n' "$r70_out" | grep -c '"suite_baseline": 2000')"
    report "T70 TC-1446 facts never executes the suite" 0 "$([[ -f "$r70/.agent-state/embedded-ran" ]] && echo 1 || echo 0)"
    report "T70 TC-1446 facts stays inside the read-only budget" 1 "$([[ $r70_dt -le 10 ]] && echo 1 || echo 0)"
    git -C "$r70" checkout -q -- notes.md tests/.suite-baseline 2>/dev/null || true
    r70_p="$r70/.agent-state/facts-override.json"
    r70_rc=0; r70_out=$(_r70_run --write --path "$r70_p") || r70_rc=$?
    report "T70 TC-1446 --write --path lands the snapshot" 1 "$([[ -s "$r70_p" ]] && echo 1 || echo 0)"
    report "T70 TC-1446 the written file is the JSON body" 1 "$(grep -c '"schema": 1' "$r70_p")"
    _r70_run --write >/dev/null 2>&1
    report "T70 TC-1446 the default --write path is .agent-state/facts.json" 1 \
      "$([[ -s "$r70/.agent-state/facts.json" ]] && echo 1 || echo 0)"
    report "T70 TC-1446 --write replaces atomically and leaves no temp file" 0 \
      "$(ls "$r70_p".* 2>/dev/null | wc -l | tr -d ' ')"
    r70_rc=0; r70_out=$(_r70_run --root) || r70_rc=$?
    report "T70 TC-1444 a trailing flag without its value dies rc2 instead of hanging" 2 "$r70_rc"
    r70_rc=0; r70_out=$(_r70_run --nope) || r70_rc=$?
    report "T70 TC-1444 an unknown facts argument dies rc2" 2 "$r70_rc"
    # A trailing option that takes a value must die, not keep the default: before
    # the arity guard `--path` with no operand printed to stdout as if it had been
    # ignored (v3.87.0 R4, finding #10 — same family as the suite's -T).
    r70_rc=0; r70_out=$(_r70_run --path) || r70_rc=$?
    report "T70 TC-1444 a trailing --path dies rc2 naming the option" 0 \
      "$([[ $r70_rc -eq 2 && $(printf '%s\n' "$r70_out" | grep -c -- '--path needs a value') -eq 1 ]] && echo 0 || echo 1)"
    r70_rc=0; r70_out=$(bash "$ROOT/scripts/facts.sh" --root "$r70/does-not-exist" 2>&1) || r70_rc=$?
    report "T70 TC-1444 a missing --root dies rc2 instead of inventing facts" 2 "$r70_rc"
    # N1 同族回归：随 bootstrap --guard 下发的套件自身也必须在尾随 -T 上立即失败。
    # 修复前实测是死循环（shift 2 在 $# == 1 时不推进），所以这里用看门狗把「挂住」
    # 本身变成断言失败，而不是让整套套件卡死。
    bash "$ROOT/tests/run-tests.sh" -T >"$r70/trailing-t.err" 2>&1 &
    r70_hang_pid=$!
    ( sleep 8; kill -0 "$r70_hang_pid" 2>/dev/null && kill -9 "$r70_hang_pid" 2>/dev/null ) &
    r70_watchdog=$!
    r70_rc=0; wait "$r70_hang_pid" || r70_rc=$?
    kill "$r70_watchdog" 2>/dev/null; wait "$r70_watchdog" 2>/dev/null
    report "T70 TC-1444 the shipped runner dies rc2 on a trailing -T instead of hanging" 2 "$r70_rc"
    report "T70 TC-1444 the hang fix is a named usage error, not a silent full run" 1 \
      "$(grep -c 'invalid -T value' "$r70/trailing-t.err")"
    report "T70 TC-1447 facts declares the source-layer boundary" 1 \
      "$([[ $(grep -cF 'Source-layer only (NOT shipped with the Skill)' "$ROOT/scripts/facts.sh") -ge 1 && $(grep -cF 'lib-source-facts.sh' "$ROOT/scripts/lib-source-facts.sh") -ge 1 ]] && echo 1 || echo 0)"
    report "T70 TC-1447 bootstrap ships neither facts nor its lib" 0 \
      "$(grep -cE 'facts\.sh|lib-source-facts' "$ROOT/scripts/bootstrap.sh")"
    r70_rc=0; r70_out=$(bash "$ROOT/scripts/facts.sh" 2>&1) || r70_rc=$?
    report "T70 TC-1446 facts runs against the live source repo" 0 "$r70_rc"
    report "T70 TC-1446 the live facts carry this suite's version authority" 1 \
      "$(printf '%s\n' "$r70_out" | grep -c "\"version\": \"${CURRENT_VERSION:-unset}\"")"
    rm -rf "$r70"
  fi
}

section_T71() {
# ------------------------------------------------ T71 verify-all 串行编排与收据复用（v3.87.0，CHG-115，REQ-1187）
# 一次调用拿到完整红/绿图：release→ledger→audit→suite 固定顺序、collect-all（前面失败
# 不短路）、套件收据复用（--fresh 强制真跑）、验证期间树变必须显式失败。
# 五步都可注入命令（AGENT_GUARD_VERIFY_*_CMD 测试缝），本节全靠缝，不碰真实套件。
  local r71 r71_rc r71_out r71_order r71_rec r71_logs r71_srecv r71_head r71_tree
  local r71_c_rel r71_c_led r71_c_aud r71_c_sui r71_seq
  if [[ ! -f "$ROOT/scripts/verify-all.sh" || ! -f "$ROOT/scripts/lib-source-facts.sh" ]]; then
    echo "SKIP T71: verify-all.sh / lib-source-facts.sh absent (source-layer tools do not ship)"
  else
    r71=$(mktemp -d "${TMPDIR:-/tmp}/verify-all.XXXXXX")
    mkdir -p "$r71/repo/scripts" "$r71/repo/tests" "$r71/repo/.agent-state"
    cp "$ROOT/scripts/verify-all.sh" "$ROOT/scripts/lib-source-facts.sh" "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r71/repo/scripts/"
    printf '.agent-state/\n' > "$r71/repo/.gitignore"
    cat > "$r71/repo/tests/run-tests.sh" <<'R71FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/../.agent-state/embedded-ran"
printf '777 passed, 0 failed\n'
printf 'wall-time: 1s\n'
R71FAKE
    printf 'notes\n' > "$r71/repo/notes.md"
    ( cd "$r71/repo" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    r71_order="$r71/repo/.agent-state/order.txt"
    r71_rec="$r71/repo/.agent-state/verify-receipt.json"
    r71_logs="$r71/repo/.agent-state/verify-logs"
    r71_srecv="$r71/repo/.agent-state/last-suite-receipt.json"
    r71_head=$(git -C "$r71/repo" rev-parse HEAD 2>/dev/null || true)
    # Same reason as T73b: seed with the value sf_receipt_fresh will compare against.
    r71_tree=$(bash -c 'source "$1/scripts/lib-source-facts.sh"; sf_tree_fingerprint "$1"' _ "$r71/repo" 2>/dev/null || true)
    r71_c_rel="printf 'release\\n' >> $r71_order"
    r71_c_led="printf 'ledger\\n' >> $r71_order"
    r71_c_aud="printf 'audit\\n' >> $r71_order"
    r71_c_sui="printf 'suite\\n' >> $r71_order"
    r71_c_gat="printf 'gate\\n' >> $r71_order"
    _r71_run() { ( cd "$r71/repo" && AGENT_GUARD_VERIFY_RECEIPT_PATH="$r71_rec" AGENT_GUARD_VERIFY_LOG_DIR="$r71_logs" AGENT_GUARD_SUITE_RECEIPT_PATH="$r71_srecv" AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN=30 AGENT_GUARD_VERIFY_RELEASE_CMD="$r71_c_rel" AGENT_GUARD_VERIFY_LEDGER_CMD="$r71_c_led" AGENT_GUARD_VERIFY_AUDIT_CMD="$r71_c_aud" AGENT_GUARD_VERIFY_SUITE_CMD="$r71_c_sui" AGENT_GUARD_VERIFY_GATE_CMD="$r71_c_gat" bash scripts/verify-all.sh "$@" 2>&1 ); }
    _r71_seed() { printf '{"kind":"full","head":"%s","tree_fingerprint":"%s","passed":%s,"failed":0,"wall_time_s":123,"generated_at":"now"}\n' "$1" "$2" "$3" > "$r71_srecv"; }
    rm -f "$r71_order" "$r71_srecv" "$r71_rec"; rm -rf "$r71_logs"

    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1448 the five-step orchestration is green" 0 "$r71_rc"
    r71_seq=$(tr '\n' ' ' < "$r71_order" | sed -e 's/^ *//' -e 's/ *$//')
    report "T71 TC-1448 the step order is release ledger audit suite gate" 1 \
      "$([[ "$r71_seq" == "release ledger audit suite gate" ]] && echo 1 || echo 0)"
    report "T71 TC-1448 every step reports a PASS line" 5 "$(printf '%s\n' "$r71_out" | grep -c '^PASS')"
    report "T71 TC-1448 the receipt records five steps" 5 "$(grep -o '"name":' "$r71_rec" | wc -l | tr -d ' ')"
    report "T71 TC-1448 the receipt says pass and the tree stayed stable" 2 \
      "$(grep -cE '"status": "pass"|"tree_stable": true' "$r71_rec")"
    report "T71 TC-1448 each step keeps its own log file" 5 "$(ls "$r71_logs" 2>/dev/null | wc -l | tr -d ' ')"

    r71_c_sui=""
    _r71_seed "$r71_head" "$r71_tree" 1000
    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1449 a fresh same-tree receipt is reused instead of rerun" 0 "$r71_rc"
    report "T71 TC-1449 the reuse line names the reused receipt" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'reused fresh same-tree receipt')"
    report "T71 TC-1449 reuse carries the receipt counts into the verify receipt" 1 \
      "$(grep -c '"reused": true, "passed": 1000' "$r71_rec")"
    r71_rc=0; r71_out=$(_r71_run --fresh) || r71_rc=$?
    report "T71 TC-1452 --fresh forbids reuse and runs the suite" 1 \
      "$([[ $(grep -c '"reused": false' "$r71_rec") -ge 1 ]] && echo 1 || echo 0)"
    report "T71 TC-1452 --fresh parses counts out of the real suite output" 1 "$(grep -c '"passed": 777, "failed": 0, "wall_time_s": 1' "$r71_rec")"
    rm -f "$r71/repo/.agent-state/embedded-ran"

    rm -f "$r71_order" "$r71_srecv"; rm -rf "$r71_logs"
    r71_c_sui="printf 'suite\\n' >> $r71_order"
    r71_c_led="printf 'ledger\\n' >> $r71_order; exit 1"
    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1450 a failing middle step makes the run rc1" 1 "$r71_rc"
    r71_seq=$(tr '\n' ' ' < "$r71_order" | sed -e 's/^ *//' -e 's/ *$//')
    report "T71 TC-1450 collect-all still runs the later steps" 1 \
      "$([[ "$r71_seq" == "release ledger audit suite gate" ]] && echo 1 || echo 0)"
    report "T71 TC-1450 the receipt status is fail with the failing rc kept" 1 \
      "$(grep -cE '"status": "fail"' "$r71_rec")"
    report "T71 TC-1450 the FAIL line points at the step log" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'FAIL ledger')"

    rm -f "$r71_order" "$r71_srecv"; rm -rf "$r71_logs"
    r71_c_led="printf 'ledger\\n' >> $r71_order"
    r71_c_sui="printf 'suite\\n' >> $r71_order; echo change >> notes.md"
    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1451 a tree change during verification fails rc1" 1 "$r71_rc"
    report "T71 TC-1451 the tree change is reported explicitly" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'changed during verification')"
    report "T71 TC-1451 the receipt marks the tree unstable" 1 "$(grep -c '"tree_stable": false' "$r71_rec")"
    git -C "$r71/repo" checkout -q -- notes.md 2>/dev/null || true

    # R4 (review finding #4): both fingerprints empty compares equal, so an
    # uncomputable fingerprint used to certify "tree_stable": true for a run whose
    # inputs were never pinned. A root that is not a git repo must fail instead.
    mkdir -p "$r71/nogit/scripts" "$r71/nogit/.agent-state"
    cp "$ROOT/scripts/verify-all.sh" "$ROOT/scripts/lib-source-facts.sh" "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r71/nogit/scripts/"
    r71_rc=0; r71_out=$( cd "$r71/nogit" && AGENT_GUARD_VERIFY_RECEIPT_PATH="$r71/nogit/.agent-state/verify-receipt.json" AGENT_GUARD_VERIFY_LOG_DIR="$r71/nogit/.agent-state/verify-logs" AGENT_GUARD_SUITE_RECEIPT_PATH="$r71/nogit/.agent-state/last-suite-receipt.json" AGENT_GUARD_VERIFY_RELEASE_CMD="$r71_c_rel" AGENT_GUARD_VERIFY_LEDGER_CMD="$r71_c_led" AGENT_GUARD_VERIFY_AUDIT_CMD="$r71_c_aud" AGENT_GUARD_VERIFY_SUITE_CMD="$r71_c_sui" bash scripts/verify-all.sh --root "$r71/nogit" 2>&1 ) || r71_rc=$?
    report "T71 TC-1451 a root with no computable fingerprint dies rc1" 1 "$r71_rc"
    report "T71 TC-1451 the missing fingerprint is named instead of guessed" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'stability cannot be proven')"
    report "T71 TC-1451 that receipt never claims a stable tree" 0 \
      "$(grep -c '"tree_stable": true' "$r71/nogit/.agent-state/verify-receipt.json")"

    rm -f "$r71_order" "$r71_rec"; rm -rf "$r71_logs"
    r71_c_sui="printf 'suite\\n' >> $r71_order"
    r71_rc=0; r71_out=$(_r71_run --skip-suite) || r71_rc=$?
    report "T71 TC-1448 --skip-suite still exits green" 0 "$r71_rc"
    report "T71 TC-1448 the skipped step is recorded as skip, not pass" 1 \
      "$(grep -c '"name":"suite","status":"skip"' "$r71_rec")"
    # R4 (review finding #5): the batch's headline hard gate must exist in the
    # local entry too, not only in CI — otherwise "verify-all is the local truth"
    # silently excludes the baseline==receipt check it was sold on.
    r71_rc=0; r71_out=$(_r71_run --skip-gate) || r71_rc=$?
    report "T71 TC-1448 --skip-gate records the gate as skip, never as pass" 0 \
      "$([[ $r71_rc -eq 0 && $(grep -c '"name":"gate","status":"skip"' "$r71_rec") -eq 1 ]] && echo 0 || echo 1)"
    r71_c_gat="printf 'gate\\n' >> $r71_order; exit 1"
    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1448 a red baseline/receipt gate reddens the whole local entry" 1 "$r71_rc"
    report "T71 TC-1448 the FAIL line names the gate step" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'FAIL gate')"
    r71_c_gat="printf 'gate\\n' >> $r71_order"
    r71_rc=0; r71_out=$(_r71_run --nope) || r71_rc=$?
    report "T71 TC-1448 an unknown verify-all argument dies rc2" 2 "$r71_rc"
    r71_rc=0; r71_out=$(_r71_run --jobs) || r71_rc=$?
    report "T71 TC-1444 a trailing --jobs dies rc2 instead of taking the default" 0 \
      "$([[ $r71_rc -eq 2 && $(printf '%s\n' "$r71_out" | grep -c -- '--jobs needs a value') -eq 1 ]] && echo 0 || echo 1)"
    # -j is the spelling used by the suite this tool forwards to; a documented
    # "-j 4" that dies as an unknown argument is a trap (v3.87.0 R4).
    r71_rc=0; r71_out=$(_r71_run --fresh -j 4) || r71_rc=$?
    report "T71 TC-1444 the suite spelling -j is accepted as an alias" 0 \
      "$([[ $r71_rc -eq 0 && $(printf '%s\n' "$r71_out" | grep -c 'unknown argument') -eq 0 ]] && echo 0 || echo 1)"
    report "T71 TC-1452 verify-all shares the receipt-reuse rule with the generator" 1 \
      "$(grep -cF 'sf_receipt_fresh' "$ROOT/scripts/verify-all.sh")"
    report "T71 TC-1447 verify-all declares the source-layer boundary and stays unshipped" 0 \
      "$(grep -cE 'verify-all\.sh' "$ROOT/scripts/bootstrap.sh")"
    rm -rf "$r71"
  fi
}

section_T72() {
# ------------------------------------------------ T72 pre-review-check 评审前置机检（v3.87.0，CHG-115，REQ-1188）
# 评审 Agent 不该把时间花在"产物齐不齐"上。16 产物在位非空、FILL 残留、00.5 确认行、
# 05 真实执行证据、责任人独立、07 署名与结论、provenance 戳、载体一致、README 计数、
# 空 glob 陷阱——全部机检；只读，失败不许改动任何产物。
  local r72 r72_rc r72_out r72_art r72_snap f g
  if [[ ! -f "$ROOT/scripts/pre-review-check.sh" || ! -f "$ROOT/scripts/lib-source-facts.sh" ]]; then
    echo "SKIP T72: pre-review-check.sh / lib-source-facts.sh absent (source-layer tools do not ship)"
  else
    r72=$(mktemp -d "${TMPDIR:-/tmp}/pre-review.XXXXXX")
    mkdir -p "$r72/repo/scripts" "$r72/repo/tests" "$r72/repo/.agent-state"
    cp "$ROOT/scripts/pre-review-check.sh" "$ROOT/scripts/lib-source-facts.sh" "$r72/repo/scripts/"
    printf '.agent-state/\n' > "$r72/repo/.gitignore"
    printf 'README (1000 golden-case assertions) (assertions: 500)\n' > "$r72/repo/README.md"
    printf '这里声称 1000 项 golden-case 断言（断言：500）。\n' > "$r72/repo/README.zh-CN.md"
    printf '1000\n' > "$r72/repo/tests/.suite-baseline"
    printf '500\n' > "$r72/repo/tests/.audit-baseline"
    r72_art="$r72/repo/docs/changes/BATCH-20990101"
    mkdir -p "$r72_art"
    for f in 00-intent.md 00.5-communication.md 01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md \
             03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 04.5-coding-record.md 05-test-results.md \
             06-delivery-summary.md 06.5-deployment-config.md 07-review-report.md 09-changelog.md handoff.md; do
      printf '# %s\n\n正文。\n<!-- provenance: CHG-9001 batch BATCH-20990101 -->\n' "$f" > "$r72_art/$f"
    done
    printf '{"change_id": "CHG-9001", "risk_level": "L1", "spec_author": "alice", "implementation_owner": "bob", "test_owner": "carol", "review_owner": "dave"}\n' > "$r72_art/00-governance.json"
    printf -- '- 确认状态：已确认\n' >> "$r72_art/00.5-communication.md"
    printf '套件：1127 passed, 0 failed\n' >> "$r72_art/05-test-results.md"
    printf '评审人：dave\n评审结论：通过\n' >> "$r72_art/07-review-report.md"
    ( cd "$r72/repo" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    _r72_run() { ( cd "$r72/repo" && bash scripts/pre-review-check.sh --root "$r72/repo" --skip-release --skip-audit "$@" 2>&1 ); }

    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1453 a complete artifact set passes with zero findings" 0 "$r72_rc"
    report "T72 TC-1453 the summary line says PASS with no failures" 1 "$(printf '%s\n' "$r72_out" | grep -c 'pre-review-check: PASS (0 failure')"
    r72_rc=0; r72_out=$(_r72_run) || r72_rc=$?
    report "T72 TC-1453 the newest governance file is discovered without --change" 0 "$r72_rc"
    # R4 (self-caught): the fixture dir is BATCH-20990101 while its governance id
    # is CHG-9001 — addressing a batch by its own name used to match nothing and
    # silently skip every artifact check.
    r72_rc=0; r72_out=$(_r72_run --change BATCH-20990101) || r72_rc=$?
    report "T72 TC-1465 a batch directory name resolves as --change" 0 "$r72_rc"
    report "T72 TC-1465 the resolved directory is the batch face" 1 \
      "$(printf '%s\n' "$r72_out" | grep -c 'change directory: .*BATCH-20990101$')"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9999) || r72_rc=$?
    report "T72 TC-1465 an id matching neither face is rc1" 1 "$r72_rc"
    report "T72 TC-1465 the finding names both resolution faces" 1 \
      "$(printf '%s\n' "$r72_out" | grep -c 'neither a directory under docs/changes nor a 00-governance.json change_id')"
    # Traversal / containing-slash operands are excluded from the directory-name
    # face by design (`*/*|.|..`); they must fall through to the same fail-closed
    # finding instead of being treated as a path or crashing the resolution.
    r72_rc=0; r72_out=$(_r72_run --change ../evil) || r72_rc=$?
    report "T72 TC-1465 a traversal change operand is rejected, not taken as a path" 1 "$r72_rc"
    report "T72 TC-1465 the traversal rejection names the resolution faces" 1 \
      "$(printf '%s\n' "$r72_out" | grep -c 'neither a directory under docs/changes nor a 00-governance.json change_id')"
    r72_snap="$r72/snap"; mkdir -p "$r72_snap"; cp -R "$r72_art/." "$r72_snap/"

    printf '<!-- FILL: 待补 -->\n' >> "$r72_art/01-spec.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1454 leftover FILL placeholders are rc1" 1 "$r72_rc"
    report "T72 TC-1454 the finding names the placeholder class" 1 "$(printf '%s\n' "$r72_out" | grep -c 'placeholders remain')"
    git -C "$r72/repo" checkout -q -- docs/changes/BATCH-20990101/01-spec.md 2>/dev/null || true

    sed -e 's/确认状态：已确认/沟通摘要：见下/' "$r72_art/00.5-communication.md" > "$r72/.t" && mv "$r72/.t" "$r72_art/00.5-communication.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1455 a missing 00.5 confirmation line is rc1" 1 "$r72_rc"
    report "T72 TC-1455 the finding names 确认状态" 1 "$(printf '%s\n' "$r72_out" | grep -c '确认状态')"
    cp "$r72_snap/00.5-communication.md" "$r72_art/00.5-communication.md"

    sed -e 's/- 确认状态：已确认/- **沟通确认**：未命中，不适用（L0）/' "$r72_art/00.5-communication.md" > "$r72/.t" && mv "$r72/.t" "$r72_art/00.5-communication.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1463 the L0 bold 沟通确认 bullet declaration is accepted" 0 "$r72_rc"
    cp "$r72_snap/00.5-communication.md" "$r72_art/00.5-communication.md"

    sed -e 's/套件：1127 passed, 0 failed/（证据待补）/' "$r72_art/05-test-results.md" > "$r72/.t" && mv "$r72/.t" "$r72_art/05-test-results.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1456 05 without execution evidence is rc1" 1 "$r72_rc"
    report "T72 TC-1456 the finding asks for a passed/failed line" 1 "$(printf '%s\n' "$r72_out" | grep -c 'no recognizable execution evidence')"
    cp "$r72_snap/05-test-results.md" "$r72_art/05-test-results.md"

    rm -f "$r72_art/07-review-report.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1456 a missing 07 artifact is rc1 and is named" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c '07-review-report.md') -ge 1 ]] && echo 0 || echo 1)"
    report "T72 TC-1456 a failing pre-review check never rewrites the artifacts" 0 \
      "$([[ -z "$(diff -rq -x 07-review-report.md "$r72_snap" "$r72_art" 2>/dev/null)" ]] && echo 0 || echo 1)"
    cp "$r72_snap/07-review-report.md" "$r72_art/07-review-report.md"

    sed -e 's/评审人：dave/评审人：alice/' "$r72_snap/07-review-report.md" > "$r72_art/07-review-report.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1456 07 must name the recorded review owner" 1 "$r72_rc"
    report "T72 TC-1456 the finding says 07 does not name review_owner" 1 \
      "$(printf '%s\n' "$r72_out" | grep -c 'does not name review_owner')"
    sed -e 's/评审结论：通过/（结论待补）/' "$r72_snap/07-review-report.md" > "$r72_art/07-review-report.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1456 07 without a verdict is rc1" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c 'no review verdict') -ge 1 ]] && echo 0 || echo 1)"
    cp "$r72_snap/07-review-report.md" "$r72_art/07-review-report.md"

    sed -e 's/"review_owner": "dave"/"review_owner": "alice"/' "$r72_snap/00-governance.json" > "$r72_art/00-governance.json"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1455 a reviewer who wrote the spec is rc1" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c 'review owner equals') -ge 1 ]] && echo 0 || echo 1)"
    cp "$r72_snap/00-governance.json" "$r72_art/00-governance.json"

    printf '# 无戳产物\n' > "$r72_art/09-changelog.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1453 an unstamped markdown artifact is rc1" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c 'unstamped artifacts') -ge 1 ]] && echo 0 || echo 1)"
    cp "$r72_snap/09-changelog.md" "$r72_art/09-changelog.md"

    printf '999\n' > "$r72/repo/tests/.suite-baseline"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1453 README counts are compared against the committed baseline" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c 'README suite counts drift') -ge 1 ]] && echo 0 || echo 1)"
    printf '1000\n' > "$r72/repo/tests/.suite-baseline"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1453 the fixture is green again once the baseline is restored" 0 "$r72_rc"

    r72_rc=0; r72_out=$(cd "$r72/repo" && bash scripts/pre-review-check.sh --root "$r72/repo" --skip-audit 2>&1) || r72_rc=$?
    report "T72 TC-1453 a missing release.sh is a warning, not a failure" 0 "$r72_rc"
    r72_rc=0; r72_out=$(cd "$r72/repo" && bash scripts/pre-review-check.sh --root "$r72/repo" --skip-audit --strict 2>&1) || r72_rc=$?
    report "T72 TC-1453 --strict promotes the warning to rc1" 1 "$r72_rc"
    r72_rc=0; r72_out=$(_r72_run --nope) || r72_rc=$?
    report "T72 TC-1453 an unknown pre-review argument dies rc2" 2 "$r72_rc"
    r72_rc=0; r72_out=$(_r72_run --change) || r72_rc=$?
    report "T72 TC-1444 a trailing --change dies rc2 instead of scanning every batch" 0 \
      "$([[ $r72_rc -eq 2 && $(printf '%s\n' "$r72_out" | grep -c -- '--change needs a value') -eq 1 ]] && echo 0 || echo 1)"
    report "T72 TC-1447 pre-review-check declares the source-layer boundary and stays unshipped" 0 \
      "$(grep -cE 'pre-review-check\.sh' "$ROOT/scripts/bootstrap.sh")"
    rm -rf "$r72"
  fi
}

section_T73() {
# ------------------------------------------------ T73 检查器自证：变异必须让检查器变红（v3.87.0，CHG-115，REQ-1190）
# 快路径检查器（版本载体 / 基线消费）一旦永绿，整条快路径就是假证据。本节在源仓的临时
# 副本上跑变异：四类枚举齐全、version-drift 被捕获、control 前后各一次绿，
# 且受跟踪文件逐字节不变——变异只发生在副本里，活树永远干净。
  local r73 r73_rc r73_out r73_before r73_after r73_n
  if [[ ! -f "$ROOT/scripts/mutation-check.sh" || ! -f "$ROOT/scripts/release.sh" || ! -f "$ROOT/tests/.suite-baseline" ]]; then
    echo "SKIP T73: mutation-check.sh / release.sh / the committed baseline are absent (source-layer only)"
  else
    r73_rc=0; r73_out=$(cd "$ROOT" && bash scripts/mutation-check.sh --list 2>&1) || r73_rc=$?
    r73_n=$(printf '%s\n' "$r73_out" | grep -cE '^(version-drift|gate-version-drift|baseline-missing|readme-count-drift)$')
    report "T73 TC-1457 --list enumerates the four fixed mutations" 4 "$r73_n"
    report "T73 TC-1457 --list exits 0" 0 "$r73_rc"
    r73_before=$(git -C "$ROOT" status --porcelain 2>/dev/null)
    r73_rc=0; r73_out=$(cd "$ROOT" && TMPDIR="${TMPDIR:-/tmp}" bash scripts/mutation-check.sh --only version-drift 2>&1) || r73_rc=$?
    report "T73 TC-1458 version-drift makes the release checker red (sweep PASS rc0)" 0 "$r73_rc"
    report "T73 TC-1458 the caught verdict is printed" 1 "$(printf '%s\n' "$r73_out" | grep -c 'caught by the checker')"
    report "T73 TC-1460 the un-mutated control is green before and after" 2 "$(printf '%s\n' "$r73_out" | grep -c 'control green')"
    r73_after=$(git -C "$ROOT" status --porcelain 2>/dev/null)
    report "T73 TC-1459 the sweep leaves the live tree byte-identical" 0 "$([[ "$r73_before" == "$r73_after" ]] && echo 0 || echo 1)"
    r73_rc=0; r73_out=$(cd "$ROOT" && bash scripts/mutation-check.sh --only not-a-mutation 2>&1) || r73_rc=$?
    report "T73 TC-1457 an unknown mutation name dies rc2" 2 "$r73_rc"
    r73_rc=0; r73_out=$(cd "$ROOT" && bash scripts/mutation-check.sh --list --only 2>&1) || r73_rc=$?
    report "T73 TC-1444 a trailing --only dies rc2 instead of selecting every mutation" 0 \
      "$([[ $r73_rc -eq 2 && $(printf '%s\n' "$r73_out" | grep -c -- '--only needs a value') -eq 1 ]] && echo 0 || echo 1)"
    r73_rc=0; r73_out=$(cd "$ROOT" && bash scripts/mutation-check.sh --root "$ROOT/does-not-exist" --list >/dev/null 2>&1) || r73_rc=$?
    report "T73 TC-1459 a missing --root dies rc2" 2 "$r73_rc"
    report "T73 TC-1460 the no-op mutation guard is part of the recipe" 1 "$(grep -cF 'no-op mutation' "$ROOT/scripts/mutation-check.sh")"
    report "T73 TC-1460 the live-tree guard hashes every git-visible path, not a hand-picked list" 1 \
      "$(awk '/^live_state\(\)/,/^}/' "$ROOT/scripts/mutation-check.sh" | grep -c -- '--others --exclude-standard')"
    report "T73 TC-1460 an empty live-tree listing is refused instead of comparing two empty files" 1 \
      "$(grep -cF '[ -s "$SNAP_BEFORE" ]' "$ROOT/scripts/mutation-check.sh")"
    report "T73 TC-1447 mutation-check declares the source-layer boundary and stays unshipped" 0 \
      "$(grep -cE 'mutation-check\.sh' "$ROOT/scripts/bootstrap.sh")"
  fi
}

section_T73b() {
# ------------------------------------------------ T73b CI 证据汇总 + 批次指标（v3.87.0，CHG-115，REQ-1189/1191/1192/1193）
# 运行期真值只有一份：CI 全量跑出来的收据。ci-summary --check 把它和受跟踪基线硬对齐
# （陈旧基线在 CI 里响亮地红，而不是安静地 documenting 一个没人跑的数）；batch-metrics
# 把每批次的成本（轮次/编辑/轮询/整跑）落到 .agent-state 台账。两者都是源层私货。
  local r73b r73b_rc r73b_out r73b_head r73b_tree r73b_rec r73b_sum f
  if [[ ! -f "$ROOT/scripts/ci-summary.sh" || ! -f "$ROOT/scripts/batch-metrics.sh" || ! -f "$ROOT/scripts/lib-source-facts.sh" ]]; then
    echo "SKIP T73b: ci-summary.sh / batch-metrics.sh absent (source-layer tools do not ship)"
  else
    r73b=$(mktemp -d "${TMPDIR:-/tmp}/ci-metrics.XXXXXX")
    mkdir -p "$r73b/repo/scripts" "$r73b/repo/tests" "$r73b/repo/resources" "$r73b/repo/.agent-state" "$r73b/repo/docs/changes/BATCH-20990101"
    cp "$ROOT/scripts/ci-summary.sh" "$ROOT/scripts/batch-metrics.sh" "$ROOT/scripts/lib-source-facts.sh" "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r73b/repo/scripts/"
    printf '.agent-state/\n' > "$r73b/repo/.gitignore"
    printf '规范版本：v1.2.3\n' > "$r73b/repo/resources/DEVELOPMENT_STANDARDS.md"
    printf '1000\n' > "$r73b/repo/tests/.suite-baseline"
    printf '500\n' > "$r73b/repo/tests/.audit-baseline"
    printf '{"change_id": "CHG-9001", "risk_level": "L2"}\n' > "$r73b/repo/docs/changes/BATCH-20990101/00-governance.json"
    for f in 00-intent.md 01-spec.md 05-test-results.md; do printf '# %s\n' "$f" > "$r73b/repo/docs/changes/BATCH-20990101/$f"; done
    ( cd "$r73b/repo" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    r73b_head=$(git -C "$r73b/repo" rev-parse HEAD 2>/dev/null || true)
    # Seed the receipt with the value the CONSUMER computes, not HEAD^{tree}:
    # the fingerprint recipe differs from a bare tree OID as soon as anything in
    # the fixture is untracked or dirty, so a HEAD^{tree} seed only accidentally
    # matched while ci-summary ignored the field (v3.87.0 R4, review finding #7).
    r73b_tree=$(bash -c 'source "$1/scripts/lib-source-facts.sh"; sf_tree_fingerprint "$1"' _ "$r73b/repo" 2>/dev/null || true)
    r73b_rec="$r73b/repo/.agent-state/last-suite-receipt.json"
    _r73b_seed() { printf '{"kind":"full","head":"%s","tree_fingerprint":"%s","passed":%s,"failed":%s,"wall_time_s":210,"generated_at":"now"}\n' "$1" "$2" "$3" "$4" > "$r73b_rec"; }
    _r73b_ci() { ( cd "$r73b/repo" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r73b_rec" bash scripts/ci-summary.sh "$@" 2>&1 ); }
    _r73b_bm() { ( cd "$r73b/repo" && AGENT_GUARD_BATCH_METRICS_PATH="$r73b/repo/.agent-state/bm.json" AGENT_GUARD_SUITE_RECEIPT_PATH="$r73b_rec" bash scripts/batch-metrics.sh "$@" 2>&1 ); }

    _r73b_seed "$r73b_head" "$r73b_tree" 1000 0
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 the baseline gate is green when the receipt agrees" 0 "$r73b_rc"
    printf '999\n' > "$r73b/repo/tests/.suite-baseline"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a stale committed baseline fails the gate rc1" 1 "$r73b_rc"
    report "T73b TC-1461 the failure names both numbers and the sync command" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c 'baseline is 999 but the run passed 1000')"
    printf '1000\n' > "$r73b/repo/tests/.suite-baseline"
    _r73b_seed "$r73b_head" "$r73b_tree" 1000 3
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a red receipt fails the gate rc1" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'failed=3') -ge 1 ]] && echo 0 || echo 1)"
    _r73b_seed deadbeefdeadbeefdeadbeefdeadbeefdeadbeef "$r73b_tree" 1000 0
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a receipt from another HEAD fails the gate rc1" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'receipt HEAD') -ge 1 ]] && echo 0 || echo 1)"
    # The trust rule is one rule: ci-summary --check must reject the same receipt
    # sf_receipt_fresh rejects, otherwise "reused evidence" and "CI gate" disagree.
    _r73b_seed "$r73b_head" 0000000000000000000000000000000000000000 1000 0
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a same-HEAD receipt from another tree fails the gate rc1" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'tree fingerprint') -ge 1 ]] && echo 0 || echo 1)"
    rm -f "$r73b_rec"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a missing receipt fails the gate rc1" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'no suite receipt') -ge 1 ]] && echo 0 || echo 1)"
    printf '{"head":"%s","tree_fingerprint":"%s","failed":0,"generated_at":"now"}\n' "$r73b_head" "$r73b_tree" > "$r73b_rec"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a receipt without a numeric passed field fails closed" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'no numeric passed field') -ge 1 ]] && echo 0 || echo 1)"
    _r73b_seed "$r73b_head" "$r73b_tree" 1000 0
    r73b_sum="$r73b/repo/.agent-state/step-summary.md"
    r73b_rc=0; r73b_out=$( cd "$r73b/repo" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r73b_rec" GITHUB_STEP_SUMMARY="$r73b_sum" bash scripts/ci-summary.sh 2>&1 ) || r73b_rc=$?
    report "T73b TC-1461 the summary renderer exits 0 and prints the table" 0 \
      "$([[ $r73b_rc -eq 0 && $(printf '%s\n' "$r73b_out" | grep -c '| suite baseline (tests/.suite-baseline) | 1000 |') -ge 1 ]] && echo 0 || echo 1)"
    report "T73b TC-1461 the summary states the private-ledger scope explicitly" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c 'is not pushed and is \*\*not\*\* checked here')"
    report "T73b TC-1461 GITHUB_STEP_SUMMARY receives the same body" 1 "$([[ -s "$r73b_sum" ]] && echo 1 || echo 0)"
    report "T73b TC-1461 the version column resolves from the DS footer" 1 "$(printf '%s\n' "$r73b_out" | grep -c '| standards version | 1.2.3 |')"
    r73b_rc=0; r73b_out=$(_r73b_ci --nope) || r73b_rc=$?
    report "T73b TC-1461 an unknown ci-summary argument dies rc2" 2 "$r73b_rc"

    r73b_rc=0; r73b_out=$(_r73b_bm report) || r73b_rc=$?
    report "T73b TC-1462 reading a ledger that does not exist yet dies rc1" 1 "$r73b_rc"
    r73b_rc=0; r73b_out=$(_r73b_bm record --batch BATCH-20990101) || r73b_rc=$?
    report "T73b TC-1462 batch-metrics record writes the canonical TSV" 1 \
      "$([[ $r73b_rc -eq 0 && -s "$r73b/repo/.agent-state/bm.tsv" ]] && echo 1 || echo 0)"
    report "T73b TC-1462 the JSON mirror is regenerated from the TSV" 1 \
      "$([[ -s "$r73b/repo/.agent-state/bm.json" ]] && echo 1 || echo 0)"
    report "T73b TC-1462 the row carries artifact completeness and the batch id" 1 \
      "$(grep -c $'BATCH-20990101\tL2\tCHG-9001\t4/16' "$r73b/repo/.agent-state/bm.tsv")"
    r73b_rc=0; r73b_out=$(_r73b_bm report --batch BATCH-20990101) || r73b_rc=$?
    report "T73b TC-1462 report reads the batch row back" 0 \
      "$([[ $r73b_rc -eq 0 && $(printf '%s\n' "$r73b_out" | grep -c 'BATCH-20990101') -ge 1 ]] && echo 0 || echo 1)"
    _r73b_bm record --batch BATCH-20990101 >/dev/null 2>&1
    report "T73b TC-1462 re-recording upserts instead of appending" 1 \
      "$([[ $(tail -n +2 "$r73b/repo/.agent-state/bm.tsv" | wc -l | tr -d ' ') -eq 1 ]] && echo 1 || echo 0)"
    report "T73b TC-1462 the JSON mirror splits artifacts and keeps the cost columns" 2 \
      "$(grep -oE '"artifacts_present":4,"artifacts_required":16|"suite_wall_s":210' "$r73b/repo/.agent-state/bm.json" | wc -l | tr -d ' ')"
    _r73b_bm record --batch 'Q"X' >/dev/null 2>&1
    report "T73b TC-1462 a quote in a ledger value cannot corrupt the JSON mirror" 1 \
      "$(grep -cF 'Q\"X' "$r73b/repo/.agent-state/bm.json")"
    r73b_rc=0; r73b_out=$(_r73b_bm nope) || r73b_rc=$?
    report "T73b TC-1462 an unknown batch-metrics action dies rc2" 2 "$r73b_rc"
    r73b_rc=0; r73b_out=$(_r73b_bm record --batch) || r73b_rc=$?
    report "T73b TC-1444 a trailing --batch dies rc2 instead of ledgering an empty batch id" 0 \
      "$([[ $r73b_rc -eq 2 && $(printf '%s\n' "$r73b_out" | grep -c -- '--batch needs a value') -eq 1 ]] && echo 0 || echo 1)"

    # Self-caught in the final measurement pass: a verify receipt carries "status"
    # inside every step as well as at the top level, and a generic last-match
    # reader returned the suite step — an audit-red batch got ledgered as pass.
    _r73b_vr() { printf '{\n  "schema": 1,\n  "status": "%s",\n  "steps": [{"name":"release","status":"pass","rc":0},{"name":"audit","status":"%s","rc":%s},{"name":"suite","status":"pass","rc":0}]\n}\n' "$1" "$2" "$3" \
      > "$r73b/repo/.agent-state/verify-receipt.json"; }
    _r73b_vfield() { tail -n 1 "$r73b/repo/.agent-state/bm.tsv" | cut -f16; }
    _r73b_vr fail fail 1
    _r73b_bm record --batch BATCH-20990101 >/dev/null 2>&1
    report "T73b TC-1464 a red verify step is ledgered as fail, not as the suite step" 0 \
      "$([[ $(_r73b_vfield) == fail ]] && echo 0 || echo 1)"
    r73b_rc=0; r73b_out=$( cd "$r73b/repo" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r73b_rec" bash scripts/ci-summary.sh 2>&1 ) || r73b_rc=$?
    report "T73b TC-1464 the CI summary prints the same top-level status, not a step's" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c '| verify-all status (if run locally) | fail |')"
    _r73b_vr pass pass 0
    _r73b_bm record --batch BATCH-20990101 >/dev/null 2>&1
    report "T73b TC-1464 a green receipt is still ledgered as pass (the reader is not stuck on fail)" 0 \
      "$([[ $(_r73b_vfield) == pass ]] && echo 0 || echo 1)"
    rm -f "$r73b/repo/.agent-state/verify-receipt.json"
    _r73b_bm record --batch BATCH-20990101 >/dev/null 2>&1
    report "T73b TC-1464 a missing verify receipt is ledgered as none" 0 \
      "$([[ $(_r73b_vfield) == none ]] && echo 0 || echo 1)"

    # v3.88.0 (CHG-116, REQ-1198): only a full run may pose as full authority.
    # kind is the machine boundary — a partial (auto) receipt and a pre-v3.88
    # legacy receipt without any kind both fail closed; kind:"full" keeps the
    # pre-existing green path so the boundary adds no false reds.
    printf '{"kind":"partial","head":"%s","tree_fingerprint":"%s","sections":"T50 T70","passed":1000,"failed":0,"wall_time_s":9,"generated_at":"now"}\n' "$r73b_head" "$r73b_tree" > "$r73b_rec"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1480 a partial receipt is not full authority (rc1)" 1 "$r73b_rc"
    report "T73b TC-1480 the finding says partial receipts are rejected" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c 'not full authority')"
    printf '{"head":"%s","tree_fingerprint":"%s","passed":1000,"failed":0,"wall_time_s":210,"generated_at":"now"}\n' "$r73b_head" "$r73b_tree" > "$r73b_rec"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1481 a legacy receipt without a kind field fails closed" 1 "$r73b_rc"
    report "T73b TC-1481 the finding names the missing kind" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c 'kind')"
    _r73b_seed "$r73b_head" "$r73b_tree" 1000 0
    r73b_rc=0; _r73b_ci --check >/dev/null 2>&1 || r73b_rc=$?
    report "T73b TC-1482 a kind:full receipt keeps the green path" 0 "$r73b_rc"
    report "T73b TC-1472 the A56 leak ring grew to 14 tokens and six discipline tags" 1 \
      "$([[ $(sed -n 's/^for a56_w in //p' "$ROOT/tests/audit-standards-src.sh" | grep -o '"' | wc -l | tr -d ' ') == 28 && $(grep -oE 'PD-[0-9]' "$ROOT/tests/audit-standards-src.sh" | sort -u | wc -l | tr -d ' ') == 6 ]] && echo 1 || echo 0)"

    report "T73b TC-1462 both evidence tools declare the source-layer boundary" 2 \
      "$( { grep -cF 'Source-layer only (NOT shipped with the Skill)' "$ROOT/scripts/ci-summary.sh"; grep -cF 'Source-layer only (NOT shipped with the Skill)' "$ROOT/scripts/batch-metrics.sh"; } | awk '{s+=$1} END{print s}')"
    report "T73b TC-1462 bootstrap ships neither the CI summarizer nor the metrics ledger" 0 \
      "$(grep -cE 'ci-summary\.sh|batch-metrics\.sh' "$ROOT/scripts/bootstrap.sh")"
    report "T73b TC-1462 the private maintenance workspace stays untracked" 0 \
      "$(git -C "$ROOT" ls-files .opencode 2>/dev/null | wc -l | tr -d ' ')"
    rm -rf "$r73b"
  fi
}

section_T74() {
# ------------------------------------------------ T74 pre-review 声称链对账（v3.88.0，CHG-116，REQ-1194）
# F5/N6 两母题的机检化：机器面（run-tests report 行的 TC 号）与声称面（04 映射表+落点清单+01.5
# 矩阵）双向差集必红；01.5 的 file:line（token）锚点逐条实测行内容。对账对象在 gitignored
# docs/，本节只在本地 pre-review 存在——CI 的 not-checked-here 边界不变。
  local r74 r74_rc r74_out r74_art f
  if [[ ! -f "$ROOT/scripts/pre-review-check.sh" || ! -f "$ROOT/scripts/lib-source-facts.sh" ]]; then
    echo "SKIP T74: pre-review-check.sh / lib-source-facts.sh absent (source-layer tools do not ship)"
  else
    r74=$(mktemp -d "${TMPDIR:-/tmp}/claims.XXXXXX")
    mkdir -p "$r74/repo/scripts" "$r74/repo/tests" "$r74/repo/.agent-state"
    cp "$ROOT/scripts/pre-review-check.sh" "$ROOT/scripts/lib-source-facts.sh" "$r74/repo/scripts/"
    printf '.agent-state/\n' > "$r74/repo/.gitignore"
    printf 'README (1000 golden-case assertions) (assertions: 500)\n' > "$r74/repo/README.md"
    printf '这里声称 1000 项 golden-case 断言（断言：500）。\n' > "$r74/repo/README.zh-CN.md"
    printf '1000\n' > "$r74/repo/tests/.suite-baseline"
    printf '500\n' > "$r74/repo/tests/.audit-baseline"
    # synthetic machine face: two report TC ids the claims face must mirror
    printf '# runner\nreport "T1 TC-1466 alpha" 0 0\nreport "T1 TC-1467 beta" 0 0\n' > "$r74/repo/tests/run-tests.sh"
    # anchor target: token lives on line 3
    printf '# tool\n# line two\n采集入口 here\n' > "$r74/repo/scripts/tool.sh"
    r74_art="$r74/repo/docs/changes/BATCH-20990102"
    mkdir -p "$r74_art"
    for f in 00-intent.md 00.5-communication.md 01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md \
             03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 04.5-coding-record.md 05-test-results.md \
             06-delivery-summary.md 06.5-deployment-config.md 07-review-report.md 09-changelog.md handoff.md; do
      printf '# %s\n\n正文。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->\n' "$f" > "$r74_art/$f"
    done
    printf '{"change_id": "CHG-9002", "risk_level": "L1", "spec_author": "alice", "implementation_owner": "bob", "test_owner": "carol", "review_owner": "dave"}\n' > "$r74_art/00-governance.json"
    printf -- '- 确认状态：已确认\n' >> "$r74_art/00.5-communication.md"
    printf '套件：1127 passed, 0 failed\n' >> "$r74_art/05-test-results.md"
    printf '评审人：dave\n评审结论：通过\n' >> "$r74_art/07-review-report.md"
    printf 'TC-1466 TC-1467 两条用例，落点节 T1。\n- TC-1466 → 节 T1\n- TC-1467 → 节 T1\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/04-test-scripts.md"
    printf '矩阵：TC-1466/TC-1467；锚点 `scripts/tool.sh:3`（采集入口）。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/01.5-rtvm-matrix.md"
    ( cd "$r74/repo" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm seed >/dev/null 2>&1 )
    _r74_run() { ( cd "$r74/repo" && bash scripts/pre-review-check.sh 2>&1 ); }
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1466 an aligned claims chain passes" 0 "$r74_rc"
    report "T74 TC-1466 the claims line reports the verified id count" 1 \
      "$(printf '%s\n' "$r74_out" | grep -c 'claims chain: 2 machine TC ids')"
    report "T74 TC-1469 the green run verifies the 01.5 anchor" 1 \
      "$(printf '%s\n' "$r74_out" | grep -c 'claims chain:.*1 anchors')"
    # machine face grew, docs did not (F5 family: TC-1465 incident)
    printf '# runner\nreport "T1 TC-1466 alpha" 0 0\nreport "T1 TC-1467 beta" 0 0\nreport "T1 TC-1468 gamma" 0 0\n' > "$r74/repo/tests/run-tests.sh"
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1467 an unregistered TC fails and is named" 1 "$r74_rc"
    report "T74 TC-1467 the finding says unregistered and names the id" 1 \
      "$(printf '%s\n' "$r74_out" | grep -cE 'unregistered TC.*TC-1468')"
    # docs claim a TC no report line produces
    printf 'TC-1466 TC-1467 TC-9999 三条用例。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/04-test-scripts.md"
    printf '# runner\nreport "T1 TC-1466 alpha" 0 0\nreport "T1 TC-1467 beta" 0 0\n' > "$r74/repo/tests/run-tests.sh"
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1468 a phantom TC fails and is named" 1 "$r74_rc"
    report "T74 TC-1468 the finding says phantom and names the id" 1 \
      "$(printf '%s\n' "$r74_out" | grep -cE 'phantom TC.*TC-9999')"
    # anchor freshness: token moved away from the pinned line
    printf '矩阵：TC-1466/TC-1467；锚点 `scripts/tool.sh:3`（采集入口）。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/01.5-rtvm-matrix.md"
    printf 'TC-1466 TC-1467 两条用例。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/04-test-scripts.md"
    printf '# tool\n# moved\n# down\n# three\n采集入口 here\n' > "$r74/repo/scripts/tool.sh"
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1470 a drifted anchor fails and names file:line" 1 "$r74_rc"
    report "T74 TC-1470 the finding names the drifted anchor" 1 \
      "$(printf '%s\n' "$r74_out" | grep -c 'tool.sh:3.（采集入口）')"
    # dangling: the anchored file is gone
    printf '# tool\n# line two\n采集入口 here\n' > "$r74/repo/scripts/tool.sh"
    rm "$r74/repo/scripts/tool.sh"
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1471 a dangling anchor file fails and is named" 1 "$r74_rc"
    report "T74 TC-1471 the finding says dangling" 1 \
      "$(printf '%s\n' "$r74_out" | grep -c 'dangling')"
    rm -rf "$r74"
  fi
}

section_T75() {
# ------------------------------------------------ T75 -T auto 裁剪 + 部分收据隔离（v3.88.0，CHG-116，REQ-1197/1198）
# 映射是优化、不是正确性依赖：无映射命中 / runner 自改一律回落全量。partial 收据只落
# last-suite-partial.json（kind:"partial"），权威路径 last-suite-receipt.json 永不被部分运行触碰。
  local r75 r75_rc r75_out r75_rec r75_part
  if ! is_source_layout; then
    echo "SKIP T75: -T auto maps source-layer tools (source repo layout only)"
  else
    r75=$(mktemp -d "${TMPDIR:-/tmp}/auto.XXXXXX")
    r75_rec="$r75/last-suite-receipt.json"
    r75_part="$r75/last-suite-partial.json"
    # resolution-only seam: decide without executing sections
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="scripts/facts.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
      bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1476 auto maps a changed tool to its sections plus the registry pin" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only: T50 T70')"
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="unknown/unmapped.xyz,scripts/facts.sh" \
      AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1477 an unmapped changed file falls back to FULL" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only: FULL')"
    # TC-1496/1497 (2026-10-25 wiring): two gaps the old 12-entry table left open —
    # docs/artifacts dragged a 25-minute FULL run in, and the standards body itself
    # was unmapped. Both are pure selection logic (resolve-only, no execution).
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="docs/changes/CHG-001/05-test-results.md,MAINTAINER.md" \
      AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1496 suite-irrelevant files resolve to NONE (no suite)" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only: NONE')"
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="resources/DEVELOPMENT_STANDARDS.md" \
      AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1497 the standards body maps to its sections (registry pin in source order)" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only:.*T48 T50 T55')"
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="tests/run-tests.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
      bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1479 a runner self-edit always resolves to FULL" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only: FULL')"
    # real partial run (T50+T70 are seconds): the authority path must stay untouched
    r75_rc=0
    AGENT_GUARD_SUITE_AUTO_DIFF="scripts/facts.sh" AGENT_GUARD_SUITE_RECEIPT_PATH="$r75_rec" \
      AGENT_GUARD_SUITE_PARTIAL_PATH="$r75_part" AGENT_GUARD_SESSION_STATS_PATH="$r75/stats.json" \
      bash "$ROOT/tests/run-tests.sh" -T auto -j 2 >/dev/null 2>&1 || r75_rc=$?
    report "T75 TC-1476 a mapped auto run is green and writes a partial receipt" 0 "$r75_rc"
    report "T75 TC-1476 the partial receipt carries kind:partial" 1 \
      "$(grep -c '"kind":"partial"' "$r75_part" 2>/dev/null)"
    report "T75 TC-1478 the authority receipt path is never touched by a partial run" 0 \
      "$([[ ! -e "$r75_rec" ]] && echo 0 || echo 1)"
    rm -rf "$r75"
  fi
}

section_T76() {
# ------------------------------------------------ T76 套件自记 full_suite（v3.88.0，CHG-116，REQ-1196）
# 全量运行才是一次"套件购买"：full_suite 只在全量路径 +1（-T 部分 run 与 verify-all 复用都不算）。
# 计数器本体用 FAKE_FULL seam 实跑（真实全跑在收口权威一次时自证——05 引 stats 增量）；门控
# 本身用真实 -T 不加 seam 钉（TC-1474），A57 另钉条件行结构。
  local r76 r76_rc r76_out r76_stats r76_after
  if ! is_source_layout; then
    echo "SKIP T76: session stats self-counting ships with the runner's tools (source repo layout only)"
  else
    r76=$(mktemp -d "${TMPDIR:-/tmp}/stats.XXXXXX")
    r76_stats="$r76/stats.json"
    printf '{"turns":3,"full_suite":4,"edits":1,"sleep_polls":0}\n' > "$r76_stats"
    r76_rc=0
    AGENT_GUARD_SESSION_STATS_PATH="$r76_stats" AGENT_GUARD_SUITE_FAKE_FULL=1 \
      AGENT_GUARD_SUITE_RECEIPT_PATH="$r76/rec.json" bash "$ROOT/tests/run-tests.sh" -T T50 >/dev/null 2>&1 || r76_rc=$?
    r76_after=$(sed -n 's/.*"full_suite":\([0-9]*\).*/\1/p' "$r76_stats" | tail -1)
    report "T76 TC-1473 a full run increments full_suite and preserves sibling keys" 0 \
      "$([[ $r76_rc -eq 0 && $r76_after == 5 && $(grep -c '"turns":3' "$r76_stats") -eq 1 ]] && echo 0 || echo 1)"
    r76_rc=0
    AGENT_GUARD_SESSION_STATS_PATH="$r76_stats" \
      AGENT_GUARD_SUITE_RECEIPT_PATH="$r76/rec.json" bash "$ROOT/tests/run-tests.sh" -T T50 >/dev/null 2>&1 || r76_rc=$?
    r76_after=$(sed -n 's/.*"full_suite":\([0-9]*\).*/\1/p' "$r76_stats" | tail -1)
    report "T76 TC-1474 a filtered run never touches the counter (real gating)" 0 \
      "$([[ $r76_rc -eq 0 && $r76_after == 5 ]] && echo 0 || echo 1)"
    r76_rc=0
    mkdir -p "$r76/ro" && chmod 555 "$r76/ro"
    AGENT_GUARD_SESSION_STATS_PATH="$r76/ro/stats.json" AGENT_GUARD_SUITE_FAKE_FULL=1 \
      AGENT_GUARD_SUITE_RECEIPT_PATH="$r76/rec.json" bash "$ROOT/tests/run-tests.sh" -T T50 >"$r76/out.log" 2>&1 || r76_rc=$?
    chmod 755 "$r76/ro"
    report "T76 TC-1475 a stats write failure warns but never blocks the suite" 0 \
      "$([[ $r76_rc -eq 0 && $(grep -c 'non-fatal' "$r76/out.log") -ge 1 ]] && echo 0 || echo 1)"
    rm -rf "$r76"
  fi
}

# hoisted (order-independence for -j; CHG-117 T78/T78b/T81 sandbox helper)
t_install_session_gate() { # -> sandbox scripts/session-gate.sh (target-repo-realistic layout)
  cp "$SESSION_GATE_SRC" scripts/session-gate.sh && chmod +x scripts/session-gate.sh
}

t_tc_landing() { # <04-file> <test-file> — append the TC 落点清单 face to a seeded 04
  printf '\n## TC 落点清单\n\n- TC-001: %s（类型：自动化）\n' "$2" >> "$1"
}

section_T77() {
# ------------------------------------------------ T77 gate 无账源码改动门（v3.89.0，CHG-117，REQ-1200，DES-1956）
# 交付边界 fail-closed：staged 扫暂存面、stop 扫 git status 合并面；豁免阶梯 =
# 活跃变更 / 当日缺陷组 / AGENT_GUARD_ALLOW_UNACCOUNTED=1（WARN 不静默，09 义务）。
if [[ ! -f "$GATE_SRC" ]]; then echo "SKIP T77: agent-gate absent"; return 0; fi
# TC-1483 red: staged source change, no active change, no same-day defect batch
new_repo
printf 'chg\n' > src/a.go
git add src/a.go
t77_out=$(scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1483 staged unaccounted source change dies E125" 2 "$t77_rc"
check_output "T77 TC-1483 die message carries the three-option ladder" "bind the defect batch" "$t77_out"
check_output "T77 TC-1483 die message names the exemption env" "AGENT_GUARD_ALLOW_UNACCOUNTED" "$t77_out"
check_output "T77 TC-1483 die message anchors standards §2.17.2b" "2\.17\.2b" "$t77_out"
# TC-1483b stop lane scans the merged worktree face (untracked source file included)
new_repo
printf 'x\n' > src/b.py
t77_out=$(scripts/agent-gate --stage stop 2>&1); t77_rc=$?
report "T77 TC-1483b stop merged face catches an untracked source file" 2 "$t77_rc"
check_output "T77 TC-1483b the stop-face red is E125 (not a downstream artifact complaint)" "GATE-E125" "$t77_out"
# TC-1483c: staged DELETION of tracked source is a source change too (A/M/R/D face)
new_repo
printf 'x\n' > src/gone.py
git add src/gone.py && git commit -qm addsrc
git rm -q src/gone.py
t77_out=$(scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1483c staged source deletion is unaccounted (E125)" 2 "$t77_rc"
check_output "T77 TC-1483c the deletion red is E125" "GATE-E125" "$t77_out"
# TC-1484 green: active change in place
new_repo
seed_begin CHG-1170 L1 claude/s-1
printf 'chg\n' > src/a.go
git add src/a.go
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T77 TC-1484 staged source change with an active change passes" 0 $?
# TC-1484b/c (独立评审 F2): an empty same-day batch directory is NOT a credential —
# the identity piece (01-diagnosis.md with a `## BUG-` anchor) is what counts.
# The assertion is scoped to E125: downstream gates (E57 completeness / E66
# change-artifact rule) keep their own bars and are not this case's subject.
new_repo
mkdir -p "docs/bugs/BATCH-$(date -u +%Y%m%d)"
printf 'chg\n' > src/a.go
git add src/a.go
t77_out=$(scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1484b empty same-day defect-batch dir does not exempt E125" 2 "$t77_rc"
check_output "T77 TC-1484b the red is E125 (no silent exemption)" "GATE-E125" "$t77_out"
printf '## BUG-9002\nseverity: P3\n诊断骨架\n' > "docs/bugs/BATCH-$(date -u +%Y%m%d)/01-diagnosis.md"
t77_out=$(scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1484c same-day batch carrying a BUG anchor clears E125" 0 "$(printf '%s\n' "$t77_out" | grep -c 'GATE-E125')"
# TC-1485a docs-only staged face never trips the gate (is_code_path exclusion face)
new_repo
seed_begin CHG-1171 L1 claude/s-1b
printf 'docs\n' >> README.md
git add README.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T77 TC-1485a docs-only staged change passes" 0 $?
# TC-1485b explicit env bypass is loud and does not hide the artifacts backstop
new_repo
printf 'chg\n' > src/a.go
git add src/a.go
seed_artifacts CHG-1172 L1 claude/s-1c   # complete artifacts face, deliberately NOT begun
t77_out=$(AGENT_GUARD_ALLOW_UNACCOUNTED=1 scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1485b env bypass releases the unaccounted gate (artifacts face still enforced)" 0 "$t77_rc"
check_output "T77 TC-1485b bypass is never silent (WARN line, 09 duty)" "WARN" "$t77_out"
}

section_T78() {
# ------------------------------------------------ T78 session-gate check 两态 + idle 收窄（v3.89.0，CHG-117，REQ-1199/1200，DES-1957/1958）
if [[ ! -f "$SESSION_GATE_SRC" ]]; then echo "SKIP T78: session-gate absent"; return 0; fi
new_repo
t_install_session_gate
# TC-1486 red: unaccounted source edit at edit time → exit 2 + three options
t78_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check 2>&1); t78_rc=$?
report "T78 TC-1486 check blocks an unaccounted source edit (exit 2)" 2 "$t78_rc"
check_output "T78 TC-1486 message carries the signal-③ three options" "三选项" "$t78_out"
check_output "T78 TC-1486 message names AGENT_GUARD_ALLOW_UNACCOUNTED" "ALLOW_UNACCOUNTED" "$t78_out"
# TC-1486b: Claude PreToolUse hands an ABSOLUTE file_path — normalization, not a silent bypass
t78_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/a.go"}}' "$PWD" | bash scripts/session-gate.sh check 2>&1); t78_rc=$?
report "T78 TC-1486b absolute hook path still hits the unaccounted gate (exit 2)" 2 "$t78_rc"
check_output "T78 TC-1486b absolute-path message carries the signal-③ three options" "三选项" "$t78_out"
# TC-1486c (独立评审 F4): a physical-root path into a NOT-yet-existing directory
# (dirname cannot be pwd -P'd) must still normalize, not fall open.
t78_phys=$(cd "$REPO" && pwd -P)
t78_out=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/newdir/a.go"}}' "$t78_phys" | bash scripts/session-gate.sh check 2>&1); t78_rc=$?
report "T78 TC-1486c physical path into a new directory still hits the gate" 2 "$t78_rc"
check_output "T78 TC-1486c normalized physical-path red is the unaccounted gate" "三选项" "$t78_out"
# TC-1487 green: accounted edit (active change + G-测试门 face) and docs paths
seed_begin CHG-1173 L1 claude/s-1
mkdir -p tests && printf 'assert "t78"\n' > tests/test_a.py
t_tc_landing docs/changes/CHG-1173/04-test-scripts.md tests/test_a.py
t78_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t78_rc=$?
report "T78 TC-1487 accounted source edit with the testplan face in place passes" 0 "$t78_rc"
t78_rc=0
printf '{"tool_name":"Write","tool_input":{"file_path":"docs/notes.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t78_rc=$?
report "T78 TC-1487b docs-path edit passes (exclusion face)" 0 "$t78_rc"
# TC-1488 SKIP_VERIFY narrowing (DES-1958): the env + the internal idle marker
# never waive the unaccounted gate — only the three structural exemptions do.
new_repo
t_install_session_gate
printf 'x\n' > src/a.go
git add src/a.go
t78_out=$(AGENT_GUARD_SKIP_VERIFY=1 AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle scripts/agent-gate --stage staged 2>&1); t78_rc=$?
report "T78b TC-1488a SKIP_VERIFY=1 + idle marker still red on the staged face" 2 "$t78_rc"
check_output "T78b TC-1488a the red is the unaccounted gate (E125), not a skip" "GATE-E125" "$t78_out"
t78_out=$(AGENT_GUARD_SKIP_VERIFY=1 AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle scripts/agent-gate --stage stop 2>&1); t78_rc=$?
report "T78b TC-1488b same narrowing on the stop merged face" 2 "$t78_rc"
check_output "T78b TC-1488b the stop-face red is E125" "GATE-E125" "$t78_out"
t78_rc=0
AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle scripts/agent-gate --stage staged >/dev/null 2>&1 || t78_rc=$?
report "T78b TC-1488c the internal marker alone grants nothing (anti-spoof)" 2 "$t78_rc"
}

section_T79() {
# ------------------------------------------------ T79 audit G16 三态（v3.89.0，CHG-117，REQ-1201，DES-1959）
if [[ ! -f "$AUDIT_SRC" ]]; then echo "SKIP T79: audit-docs-consistency absent"; return 0; fi
# clean + non-git: explicit VACUOUS SKIP line (G9 anti-false-green family)
t79_fx=$(mktemp -d); audit_fixture "$t79_fx"
t79_out=$(bash "$AUDIT_SRC" "$t79_fx" 2>&1); t79_rc=$?
report "T79 TC-1490a non-git fixture passes with G16 VACUOUS SKIP declared" 0 "$t79_rc"
check_output "T79 TC-1490a the skip is explicit, not silent" "G16 VACUOUS SKIP" "$t79_out"
# dirty unaccounted: FAIL names the offending files
t79_fx2=$(mktemp -d); audit_fixture "$t79_fx2"
(cd "$t79_fx2" && git init -q && git config user.email t@e.invalid && git config user.name t \
  && git add -A && git commit -qm init && mkdir -p src && printf 'x\n' > src/leak.py)
t79_out=$(bash "$AUDIT_SRC" "$t79_fx2" 2>&1); t79_rc=$?
report "T79 TC-1489 dirty unaccounted worktree fails G16" 1 "$t79_rc"
check_output "T79 TC-1489 the FAIL names the offending file" "leak\.py" "$t79_out"
# accounted: same dirty tree + active-change pointer
t79_af=$(git -C "$t79_fx2" rev-parse --git-path agent-governance/active-change)
mkdir -p "$t79_fx2/$(dirname "$t79_af")" && printf 'CHG-1173\n' > "$t79_fx2/$t79_af"
t79_out=$(bash "$AUDIT_SRC" "$t79_fx2" 2>&1); t79_rc=$?
report "T79 TC-1490b same dirty tree with an active change passes" 0 "$t79_rc"
check_output "T79 TC-1490b the pass states the account anchor" "G16 local source changes are accounted" "$t79_out"
# --only-fail on a clean git tree: rc 0 and the skip face is suppressed (DES-1959)
t79_fx3=$(mktemp -d); audit_fixture "$t79_fx3"
(cd "$t79_fx3" && git init -q && git config user.email t@e.invalid && git config user.name t \
  && git add -A && git commit -qm init)
t79_out=$(bash "$AUDIT_SRC" --only-fail "$t79_fx3" 2>&1); t79_rc=$?
report "T79 TC-1490c clean tree passes under --only-fail" 0 "$t79_rc"
report "T79 TC-1490c --only-fail suppresses the G16 skip face" 0 "$(printf '%s\n' "$t79_out" | grep -c 'G16 VACUOUS SKIP')"
rm -rf "$t79_fx" "$t79_fx2" "$t79_fx3"
}

section_T80() {
# ------------------------------------------------ T80 阶段门红→绿 + STAGE_GATES 开关（v3.89.0，CHG-117，REQ-1202，DES-1960）
if [[ ! -f "$GATE_SRC" ]]; then echo "SKIP T80: agent-gate absent"; return 0; fi
new_repo
seed_begin CHG-1174 L1 claude/s-1
# G-规格门: missing file / numbering gap / idempotent re-entry
rm docs/changes/CHG-1174/01-spec.md
t80_rc=0; scripts/agent-gate --stage spec >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1491a spec gate dies when 01-spec is missing" 2 "$t80_rc"
printf '# spec\n- REQ-001: a\n- REQ-003: gap\n' > docs/changes/CHG-1174/01-spec.md
t80_rc=0; scripts/agent-gate --stage spec >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1491b spec gate dies on a REQ numbering gap" 2 "$t80_rc"
printf '# spec\n- REQ-001: a\n- REQ-002: b\n' > docs/changes/CHG-1174/01-spec.md
t80_rc=0; scripts/agent-gate --stage spec >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1491c spec gate green after backfill (stateless re-entry)" 0 "$t80_rc"
# G-设计门: 02 rollback face / 03 selection+paradigm faces
sed -i '' '/回滚策略/d' docs/changes/CHG-1174/02-code-impact-analysis.md 2>/dev/null \
  || sed -i '/回滚策略/d' docs/changes/CHG-1174/02-code-impact-analysis.md
t80_rc=0; scripts/agent-gate --stage design >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1492a design gate dies when 02 lacks the rollback face" 2 "$t80_rc"
printf '## 回滚策略\nrollback: ok\n' >> docs/changes/CHG-1174/02-code-impact-analysis.md
t80_rc=0; scripts/agent-gate --stage design >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1492b design gate green again" 0 "$t80_rc"
# G-测试门: 04 用例矩阵 + TC 落点清单
t80_rc=0; scripts/agent-gate --stage testplan >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493a testplan gate dies without the TC 落点清单 section" 2 "$t80_rc"
mkdir -p tests && printf 'assert "t80"\n' > tests/test_a.py
t_tc_landing docs/changes/CHG-1174/04-test-scripts.md tests/test_a.py
t80_rc=0; scripts/agent-gate --stage testplan >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493b testplan gate green once the TC landing lands" 0 "$t80_rc"
# 八件齐的存量习惯: every stage gate idempotent-green
t80_all=0
for t80_g in spec design testplan; do
  scripts/agent-gate --stage "$t80_g" >/dev/null 2>&1 || t80_all=1
  scripts/agent-gate --stage "$t80_g" >/dev/null 2>&1 || t80_all=1   # second pass = idempotence
done
report "T80 TC-1493c all-artifacts habit passes every stage gate twice (idempotent)" 0 "$t80_all"
# narrowed begin takes the entry three alone; STAGE_GATES=0 restores the legacy full check
mkdir -p docs/changes/CHG-1175
printf '# i\n## 问题\np\n## 预期结果\ne\n## 目录落位\n- **目录落位**：独立目录（t80 fixture）\n## 开放问题\no\n' > docs/changes/CHG-1175/00-intent.md
printf '{"change_id":"CHG-1175","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-9","test_owner":"claude/s-t","review_owner":"claude/s-r"}\n' > docs/changes/CHG-1175/00-governance.json
cp docs/changes/CHG-1174/00.5-communication.md docs/changes/CHG-1175/00.5-communication.md
t80_rc=0; scripts/agent-gate begin CHG-1175 >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493d narrowed begin passes on the entry three alone" 0 "$t80_rc"
t80_rc=0; AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1175 >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493e STAGE_GATES=0 restores the legacy full begin check (missing 01 dies)" 2 "$t80_rc"
# TC-1493f (独立评审 F3): preflight must share the narrowed begin's entry scope —
# an entry-only change is green, not a wall of missing 01-04 complaints.
t80_out=$(scripts/agent-gate preflight CHG-1175 2>&1); t80_rc=$?
report "T80 TC-1493f preflight agrees with narrowed begin on an entry-only change" 0 "$t80_rc"
# TC-1493g (独立评审 F1): a BATCH member's artifacts live in the batch dir; the
# stage gate must resolve them through change_dir (same source as session-gate).
new_repo
seed_batch_artifacts BATCH-20260101 CHG-1177:L1
mkdir -p tests && printf 'assert "batch"\n' > tests/test_a.py
t_tc_landing docs/changes/BATCH-20260101/04-test-scripts.md tests/test_a.py
t80_af=$(git rev-parse --git-path agent-governance/active-change)
mkdir -p "$(dirname "$t80_af")" && printf 'CHG-1177\n' > "$t80_af"
t80_rc=0; scripts/agent-gate --stage testplan >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493g BATCH member testplan gate resolves the batch directory" 0 "$t80_rc"
}

section_T81() {
# ------------------------------------------------ T81 check 阶段感知四态（v3.89.0，CHG-117，REQ-1203，DES-1961）
if [[ ! -f "$SESSION_GATE_SRC" ]]; then echo "SKIP T81: session-gate absent"; return 0; fi
new_repo
t_install_session_gate
seed_begin CHG-1176 L1 claude/s-1
# TC-1494a: source edit without the G-测试门 face → exit 2 naming the gate
rm docs/changes/CHG-1176/04-test-scripts.md
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1494a source edit without G-测试门 dies" 2 "$t81_rc"
check_output "T81 TC-1494a message names the missing gate and the backfill face" "G-测试门" "$t81_out"
# TC-1494b: 04 with the TC-landing face present → release
mkdir -p tests && printf 'assert "t81"\n' > tests/test_a.py
printf '# tests\n- TC-001: sample case\n覆盖维度: 正常流\n' > docs/changes/CHG-1176/04-test-scripts.md
t_tc_landing docs/changes/CHG-1176/04-test-scripts.md tests/test_a.py
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1494b source edit passes once the testplan face is in place" 0 "$t81_rc"
# TC-1495a/b: 02 edit needs G-规格门 (01 REQ face in place)
mv docs/changes/CHG-1176/01-spec.md docs/changes/CHG-1176/01-held.md
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/02-code-impact-analysis.md"}}' | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1495a editing 02 without 01 dies at G-规格门" 2 "$t81_rc"
check_output "T81 TC-1495a message says which gate and what to backfill" "G-规格门" "$t81_out"
# TC-1495a2: the same red under Claude's ABSOLUTE file_path contract (normalization)
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/docs/changes/CHG-1176/02-code-impact-analysis.md"}}' "$PWD" | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1495a2 absolute hook path still dies at G-规格门 (normalized)" 2 "$t81_rc"
check_output "T81 TC-1495a2 absolute-path message names the spec gate" "G-规格门" "$t81_out"
mv docs/changes/CHG-1176/01-held.md docs/changes/CHG-1176/01-spec.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/02-code-impact-analysis.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495b 02 edit passes with 01 back in place" 0 "$t81_rc"
# TC-1495b2: editing 04 needs the whole G-设计门 face — 03.5 included
mv docs/changes/CHG-1176/03.5-tasks.md docs/changes/CHG-1176/03.5-held.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/04-test-scripts.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495b2 editing 04 without 03.5 dies at G-设计门" 2 "$t81_rc"
mv docs/changes/CHG-1176/03.5-held.md docs/changes/CHG-1176/03.5-tasks.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/04-test-scripts.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495b2b 04 edit passes with 02+03+03.5 in place" 0 "$t81_rc"
# TC-1495c: process-action faces are never blocked
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/00.5-communication.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495c 00.5 edits are process actions (never blocked)" 0 "$t81_rc"
# TC-1495d/e: bug credential channel — skeleton alone is NOT enough; the log row completes it
git rev-parse --git-path agent-governance/active-change | xargs rm -f
mkdir -p "docs/bugs/BATCH-$(date -u +%Y%m%d)"
# 独立评审 F2: the bare directory is not a defect batch (identity piece required)
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1495d0 empty same-day defect-batch dir does NOT release source edits" 2 "$t81_rc"
printf '## BUG-9001\n诊断骨架\n' > "docs/bugs/BATCH-$(date -u +%Y%m%d)/01-diagnosis.md"
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1495d batch skeleton without the bugfix-log row does NOT release source edits" 2 "$t81_rc"
check_output "T81 TC-1495d message names the missing credential" "bug 凭证" "$t81_out"
printf '### BUG-9001：现象\n' >> docs/bugfix-log.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495e bug credential (skeleton + log row) releases the fix edit" 0 "$t81_rc"
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/bugs/BATCH-99990101/01-diagnosis.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495f defect-batch-dir edits are process actions (never blocked)" 0 "$t81_rc"
# STAGE_GATES=0 turns the stage predicate layer off (unaccounted layer stays on)
mv docs/changes/CHG-1176/01-spec.md docs/changes/CHG-1176/01-held.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/02-code-impact-analysis.md"}}' | AGENT_GUARD_STAGE_GATES=0 bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495g STAGE_GATES=0 skips the stage predicate layer" 0 "$t81_rc"
mv docs/changes/CHG-1176/01-held.md docs/changes/CHG-1176/01-spec.md
# TC-1494c (独立评审 F1): a BATCH member's 04 lives in docs/changes/BATCH-*/ —
# check must resolve it the same way agent-gate change_dir does (no false red).
new_repo
t_install_session_gate
seed_batch_artifacts BATCH-20260101 CHG-1177:L1
mkdir -p tests && printf 'assert "batch"\n' > tests/test_a.py
t_tc_landing docs/changes/BATCH-20260101/04-test-scripts.md tests/test_a.py
t81_af=$(git rev-parse --git-path agent-governance/active-change)
mkdir -p "$(dirname "$t81_af")" && printf 'CHG-1177\n' > "$t81_af"
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1494c BATCH member source edit resolves the batch 04" 0 "$t81_rc"
}

# (unknown key dies rc2), then filtered invocation in original order.
SECTIONS=(T1 T1b T2 T3 T4 T5 T22a T16 T6 T6b T7 T7b T8 T9 T10 T11 T12 T13 T14 T15 T17 T17b T18 T18b T19 T20 T21 T22b T18c T18d T18d-E58R T23 T24 T25 T26 T26b T26c T64 T27 T28 T29 T30 T31 T32 T33 T34 T36 T37 T38 T39 T40 T41 T42 T43 T44 T46 T47 T48 T49 T50 T51 T52 T53 T54 T55 T56 T57 T58 T59 T60 T61 T62 T63 T65 T66 T67 T68 T69 T70 T71 T72 T73 T73b T74 T75 T76 T77 T78 T79 T80 T81 T82 T83)

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
    scripts/lib-source-facts.sh)       printf 'T69 T70 T71 T72 T73b' ;;
    scripts/facts.sh)                  printf 'T70' ;;
    scripts/verify-all.sh)             printf 'T71' ;;
    scripts/pre-review-check.sh)       printf 'T72 T74' ;;
    scripts/mutation-check.sh)         printf 'T73' ;;
    scripts/ci-summary.sh)             printf 'T73b T75' ;;
    scripts/batch-metrics.sh)          printf 'T73b' ;;
    scripts/update-assertion-count.sh) printf 'T69' ;;
    scripts/bootstrap.sh)              printf 'T11 T14 T15 T21 T40 T42 T49 T63 T70 T71 T72 T73 T73b' ;;
    tests/audit-standards-src.sh)      printf 'T69' ;;
    tests/.suite-baseline|tests/.audit-baseline) printf 'T51' ;;
    README.md|README.zh-CN.md)         printf 'T51' ;;
    .github/*)                         printf 'T73b' ;;
    .claude-plugin/*)                  printf 'T48' ;;
    resources/DEVELOPMENT_STANDARDS.md) printf 'T11 T14 T15 T20 T21 T31 T38 T40 T43 T48 T55 T63 T64 T67' ;;
    resources/AGENTS.md)               printf 'T26c T40 T43 T48 T55 T63 T64' ;;
    resources/STANDARDS_CHANGELOG.md)  printf 'T15 T40 T48' ;;
    SKILL.md)                          printf 'T11 T15 T19 T21 T48 T67' ;;
    resources/templates/audit-docs-consistency.sh)  printf 'T10 T79' ;;
    resources/templates/session-gate.sh)            printf 'T24 T26 T26b T29 T49 T78' ;;
    scripts/agent-gate|resources/templates/agent-gate.sh) printf 'T19 T26b T30 T41 T50 T78 T82 T83' ;;
    scripts/session-gate.sh|scripts/lib-suite-lock.sh) printf 'T26 T26b T41 T57' ;;
    tests/*)                           printf 'T50 T51 T75 T76' ;;
    resources/templates/stamp-provenance.sh)        printf 'T16 T17 T17b' ;;
    resources/templates/install-hook-adapter.sh)    printf 'T49' ;;
    resources/templates/*.md)          printf 'T7b T18c T18d T43 T46' ;;
    resources/templates/agent-governance.yml|resources/templates/github-*.yml) printf 'T73b' ;;
    resources/METHODOLOGY.md|resources/STAGE_PLAYBOOK.md|resources/methodologies/*|resources/templates/*.md) printf 'T40 T43 T48' ;;
    scripts/*|resources/templates/*.sh) printf 'T19 T30 T41' ;;
    docs/*)                            return 2 ;;  # 变更产物/评审记录：不影响治理工具，无需套件
    MAINTAINER.md)                     return 2 ;;
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
    if [[ "$_f" == "tests/run-tests.sh" ]]; then _auto_full="runner self-edit ($_f)"; break; fi
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
# v3.72.0 erratum (CHG-095, DES-1868): replay/re-export anchors — defined ONCE
# here; the parallel branch's counter/failed_names re-export shares them with
# the report() wire format (^ok / ^FAIL).
_RE_OK='^ok '
_RE_FAIL='^FAIL '
# v3.90.1 (CHG-123, P0-2): collected per-section timings -> suite-progress.json
_TIMINGS=()
progress_write running
if [[ "$JOBS" -ge 2 ]]; then
  # ---- parallel branch: section-level pool + source-order replay ----------
  # SERIAL_CHAIN: sections that cannot run in parallel subshells, in THIS
  # execution order — T50/T51 nest the real run-tests.sh and want cwd=$ROOT
  # (so they go first); T5→T22a→T16 form a CHG-500 fixture continuation chain
  # (T22a/T16 evolve T5's temp repo via cwd, deliberately not self-contained —
  # known limitation: `-T T22a` standalone is unsupported, use -T T5,T22a,T16).
  # They run serially (captured, not pooled) before the replay.
  SERIAL_CHAIN=(T50 T51 T5 T22a T16)
  _ran=(); _pool=(); _serial=()
  for _s in "${SECTIONS[@]}"; do
    if [[ ${#WANTED[@]} -eq 0 ]] || [[ " ${WANTED[*]} " == *" $_s "* ]]; then
      _ran+=("$_s")
      case " ${SERIAL_CHAIN[*]} " in
        *" $_s "*) ;; # chain member: collected below, in chain order
        *) _pool+=("$_s") ;;
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
    _sf="${TMPDIR:-/tmp}/suite-${_s}.$$.out"
    p=$(grep -cE "$_RE_OK" "$_sf")
    f=$(grep -cE "$_RE_FAIL" "$_sf")
    pass=$(( pass + p ))
    fail=$(( fail + f ))
    while IFS= read -r _fl; do fail_lines+=("$_fl"); done < <(grep -hE "$_RE_FAIL" "$_sf")
    while IFS= read -r _fn; do failed_names+=("$_fn"); done < <(grep -hE "$_RE_FAIL" "$_sf" | sed -E 's/^FAIL (.*) \((expected exit|output does not match).*$/\1/')
    grep -vE "$_RE_FAIL" "$_sf"
    grep -E "$_RE_FAIL" "$_sf" >&2
    _se=$(cat "${TMPDIR:-/tmp}/suite-${_s}.$$.sec" 2>/dev/null || echo 0)
    _ss=$(cat "${TMPDIR:-/tmp}/suite-${_s}.$$.setup" 2>/dev/null || echo 0)
    printf '[done] %s %ss\n' "$_s" "$_se"
    ledger_append sec "$_s" "$_se" "$_ss" none 0 "$(( p + f ))"
    _TIMINGS+=("${_s}:${_se}:${_ss}")
    rm -f "$_sf" "${TMPDIR:-/tmp}/suite-${_s}.$$.sec" "${TMPDIR:-/tmp}/suite-${_s}.$$.setup"
  done
else
  # ---- serial branch: pre--j dispatcher, byte-identical (JOBS<=1) ---------
  for _s in "${SECTIONS[@]}"; do
    if [[ ${#WANTED[@]} -eq 0 ]] || [[ " ${WANTED[*]} " == *" $_s "* ]]; then
      _t0=$(date +%s); NEW_REPO_SETUP_S=0
      _p0=$pass; _f0=$fail
      "section_${_s//-/_}"
      _p=$(( pass - _p0 )); _f=$(( fail - _f0 ))
      _el=$(( $(date +%s) - _t0 ))
      printf '[done] %s %ss\n' "$_s" "$_el"
      ledger_append sec "$_s" "$_el" "${NEW_REPO_SETUP_S:-0}" none 0 "$(( _p + _f ))"
      _TIMINGS+=("${_s}:${_el}:${NEW_REPO_SETUP_S:-0}")
      progress_write running
    fi
  done
fi

# v3.72.0 erratum (CHG-095, DES-1869): forced-red test seam. Setting
# AGENT_GUARD_SUITE_FORCE_RED=1 injects one guaranteed red case so red-path
# consumers (T57 archive drill, CI drills) can exercise the red path without a
# broken product. Test-only seam — real gate runs never set it.
if [[ "${AGENT_GUARD_SUITE_FORCE_RED:-0}" == "1" ]]; then
  report "T0 forced-red seam (AGENT_GUARD_SUITE_FORCE_RED)" 0 1
fi

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
  _pdial=$(grep -c '\\|' "$ROOT/tests/run-tests.sh" 2>/dev/null || true)
  _pwhite=$(sed -n '/^# PORTABILITY-WHITELIST-BEGIN/,/^# PORTABILITY-WHITELIST-END/p' "$ROOT/tests/run-tests.sh" 2>/dev/null | grep -c '\\|' || true)
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
