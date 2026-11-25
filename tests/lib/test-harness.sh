#!/usr/bin/env bash
# Shared golden-case test harness & seed helpers for tests/run-tests.sh (v4.13.0, CHG-158)
if [[ "${_TEST_HARNESS_LOADED:-0}" != "1" ]]; then
_TEST_HARNESS_LOADED=1

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
  # v3.91.9 (CHG-127): herestring, not a pipe. `printf '%s' "$out" | grep -Eq`
  # made grep exit early on a match; printf then took SIGPIPE and `pipefail`
  # turned a SUCCESSFUL match into a failure — CI saw it as random red on
  # large bodies (T26c/T82/T83), while small outputs stayed green.
  if grep -Eq -- "$pattern" <<< "$out"; then
    pass=$(( pass + 1 ))
    printf 'ok   %s\n' "$name"
  else
    fail=$(( fail + 1 ))
    failed_names+=("$name")
    fail_lines+=("$(printf 'FAIL %s (output does not match: %s)' "$name" "$pattern")")
    printf 'FAIL %s (output does not match: %s)\n' "$name" "$pattern" >&2
  fi
}

# v3.99.1 (CHG-141): BSD/GNU portable in-place sed for fixture mutations.
# macOS needs `-i ''`; GNU treats the empty string as the script. Source-layer
# fixtures run in CI (ubuntu-latest) too, so every new mutation must fall back.
sedi() { # <script> <files...>
  local s="$1"; shift
  sed -i '' "$s" "$@" 2>/dev/null || sed -i "$s" "$@"
}


copy_gate_to() { # <dest_dir> [bin_name]
  local dest="$1" bin="${2:-agent-gate}" d
  mkdir -p "$dest"
  cp "$GATE_SRC" "$dest/$bin"
  chmod +x "$dest/$bin"
  for d in lib-json.sh lib-gate-staged.sh lib-gate-cold.sh; do
    if [[ -f "$ROOT/resources/templates/$d" ]]; then
      cp "$ROOT/resources/templates/$d" "$dest/$d"
    elif [[ -f "$ROOT/scripts/$d" ]]; then
      cp "$ROOT/scripts/$d" "$dest/$d"
    fi
  done
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
## 专业质询三件
- 专业质询三件：未命中（fixture 通用夹具，无沟通期新增面）
## 用户整体确认记录
### 第 1 轮
- 结论：确认（按 §2.17.2d 呈现 Round-1 沟通稿后整体确认）
- 确认状态：已整体确认
EOF
  cat > "$d/01-spec.md" <<'EOF'
# spec
> 交付触发点：spec 阶段交付；下游输入：02/03 与 04
> 背景输入：P01 需求册 + P12 业务背景（fixture）
- REQ-001: sample requirement
EOF
  # v3.91.5: the RTVM row is a STAGE deliverable, so every fixture change carries
  # the full chain (REQ→DES→T→TC) from the moment it is seeded.
  cat > "$d/01.5-rtvm-matrix.md" <<EOF
# RTVM
> 交付触发点：随阶段交付回填；下游输入：阶段门与审计
> 背景输入：01-spec 的 REQ-001 + P01 需求册
| REQ | 需求简述 | DES | 核心设计方案 | TASK | CHG/位置 | TC | 测试方法 | 验证状态 |
|---|---|---|---|---|---|---|---|---|
| REQ-001 | r | DES-001 | d | T-001 | $id / f:1 | TC-001 | cmd | ✅ PASS |
EOF
  cat > "$d/02-code-impact-analysis.md" <<'EOF'
# impact
> 交付触发点：design 阶段交付；下游输入：03 与 04
> 背景输入：01-spec 的 REQ-001 + P12 业务背景
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
> 交付触发点：design 阶段交付；下游输入：03.5 与 04
> 背景输入：01-spec 的 REQ-001 + 02 业务影响
- DES-001: sample design
## 技术选型
备选方案对比: A vs B
## 既有范式关系
- **既有范式关系**：未命中（纯新增无同族实现）
EOF
  cat > "$d/03.5-tasks.md" <<'EOF'
# tasks
> 交付触发点：design 阶段交付；下游输入：开发与 04
> 背景输入：01-spec + 02 + 03 的 DES-001
- T-001: do something（依赖: 无；里程碑: M1）
- 评审输入: 变更文件清单 + 待核对产物 + 行号锚点（§2.2 输入契约）
EOF
  cat > "$d/04-test-scripts.md" <<'EOF'
# tests
> 交付触发点：testplan 阶段交付；下游输入：开发与 05/07
> 背景输入：02 业务影响 + 03 的 DES-001 + 01.5 的 DES/T 行
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
  printf '> 交付触发点：spec 阶段交付（批次成员逐节）；下游输入：02/03 与 04\n> 背景输入：P01 需求册 + P12 业务背景（batch fixture）\n' > "$d/01-spec.md"
  # v3.91.5: the shared batch RTVM carries one row per member (REQ→DES→T→TC).
  printf '# RTVM\n> 交付触发点：随阶段交付回填；下游输入：阶段门与审计\n> 背景输入：01-spec 的 REQ-901 + P01 需求册\n| REQ | 需求简述 | DES | 核心设计方案 | TASK | CHG/位置 | TC | 测试方法 | 验证状态 |\n|---|---|---|---|---|---|---|---|---|\n' > "$d/01.5-rtvm-matrix.md"
  printf '> 交付触发点：design 阶段交付（批次成员逐节）；下游输入：03 与 04\n> 背景输入：01-spec 的 REQ-901 + P12 业务背景\n' > "$d/02-code-impact-analysis.md"
  printf '> 交付触发点：design 阶段交付（批次成员逐节）；下游输入：03.5 与 04\n> 背景输入：01-spec 的 REQ-901 + 02 业务影响\n' > "$d/03-modification-plan.md"
  printf '> 交付触发点：design 阶段交付（批次成员逐节）；下游输入：开发与 04\n> 背景输入：01-spec + 02 + 03 的 DES-901\n' > "$d/03.5-tasks.md"
  printf '> 交付触发点：testplan 阶段交付（批次成员逐节）；下游输入：开发与 05/07\n> 背景输入：02 业务影响 + 03 的 DES-901 + 01.5 的 DES/T 行\n' > "$d/04-test-scripts.md"
  for pair in "$@"; do
    id="${pair%%:*}"; risk="${pair##*:}"
    printf '{"change_id":"%s","risk_level":"%s","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"claude/s-t","review_owner":"claude/s-r"}\n' "$id" "$risk" >> "$d/00-governance.json"
    printf '## %s\n## 问题\nproblem: x\n## 预期结果\nexpected: y\n## 目录落位\n- **目录落位**：BATCH-YYYYMMDD（batch member）\n## 开放问题\nopen: none\n' "$id" >> "$d/00-intent.md"
    printf '## %s\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n- 确认状态：已整体确认\n' "$id" >> "$d/00.5-communication.md"
    printf '## %s\nREQ-901: r\n' "$id" >> "$d/01-spec.md"
    printf '## %s\n### 业务影响\n### 风险\n### 回滚策略\n延伸发现：未发现\n历史相似检索：未命中（x）\n' "$id" >> "$d/02-code-impact-analysis.md"
    printf '## %s\nDES-901 备选方案对比\n- **既有范式关系**：未命中（纯新增无同族实现）\n' "$id" >> "$d/03-modification-plan.md"
    printf '## %s\n直接实施 T-901\n' "$id" >> "$d/03.5-tasks.md"
    printf '## %s\nTC-901 SC-901 覆盖维度\n' "$id" >> "$d/04-test-scripts.md"
    printf '| REQ-901 | r | DES-901 | d | T-901 | %s / f:1 | TC-901 | cmd | ✅ PASS |\n' "$id" >> "$d/01.5-rtvm-matrix.md"
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


t_install_session_gate() { # -> sandbox scripts/session-gate.sh (target-repo-realistic layout)
  cp "$SESSION_GATE_SRC" scripts/session-gate.sh && chmod +x scripts/session-gate.sh
}

t_tc_landing() { # <04-file> <test-file> — append the TC 落点清单 face to a seeded 04
  printf '\n## TC 落点清单\n\n- TC-001: %s（类型：自动化）\n' "$2" >> "$1"
}


fi
