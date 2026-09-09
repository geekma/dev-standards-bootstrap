#!/usr/bin/env bash
# Golden-case test suite for resources/templates/agent-gate.sh
#
# 对治理配置自身做回归测试（规范 §2.17.4）：在一个临时 Git 仓库里构造
# 合规/违规的暂存区与工作区状态，断言 agent-gate 的退出码与输出。
# 零依赖：bash 3.2+（macOS/Linux 均可）、git。
#
# Usage: tests/run-tests.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GATE_SRC="$ROOT/resources/templates/agent-gate.sh"

pass=0
fail=0
failed_names=()

report() { # name expected actual
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$(( pass + 1 ))
    printf 'ok   %s\n' "$name"
  else
    fail=$(( fail + 1 ))
    failed_names+=("$name")
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
    printf 'FAIL %s (output does not match: %s)\n' "$name" "$pattern" >&2
  fi
}

new_repo() {
  REPO=$(mktemp -d "${TMPDIR:-/tmp}/agent-gate-test.XXXXXX")
  cd "$REPO"
  git init -q
  git config user.email test@example.invalid
  git config user.name test
  mkdir -p scripts docs/changes src
  cp "$GATE_SRC" scripts/agent-gate
  chmod +x scripts/agent-gate
  echo init > README.md
  git add README.md scripts
  git commit -qm init
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
## 开放问题
open: none
EOF
  if [[ -n "$test" && -n "$review" ]]; then
    printf '{"change_id":"%s","risk_level":"%s","implementation_owner":"%s","test_owner":"%s","review_owner":"%s"}\n' \
      "$id" "$risk" "$impl" "$test" "$review" > "$d/00-governance.json"
  else
    printf '{"change_id":"%s","risk_level":"%s","implementation_owner":"%s"}\n' \
      "$id" "$risk" "$impl" > "$d/00-governance.json"
  fi
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
EOF
  cat > "$d/03-modification-plan.md" <<'EOF'
# plan
- DES-001: sample design
## 技术选型
备选方案对比: A vs B
EOF
  cat > "$d/03.5-tasks.md" <<'EOF'
# tasks
- T-001: do something（依赖: 无；里程碑: M1）
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

# ---------------------------------------------------------------- T1 begin 门禁
new_repo
seed_artifacts CHG-100 L1 claude/s-1
rm docs/changes/CHG-100/00-intent.md   # 缺 intent：begin 必须拒绝
scripts/agent-gate begin CHG-100 >/dev/null 2>&1
report "begin rejects missing 00-intent.md" 2 $?

printf '## 问题\nx\n## 预期结果\ny\n## 开放问题\nz\n' > docs/changes/CHG-100/00-intent.md
scripts/agent-gate begin CHG-100 >/dev/null 2>&1
report "begin accepts seven complete artifacts (L1)" 0 $?

# ------------------------------------------------- T1b A 层内容校验（§2.5）
new_repo
seed_artifacts CHG-110 L1 claude/s-1
echo "no numbering here" > docs/changes/CHG-110/01-spec.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects spec without REQ- numbering" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
echo "no numbering" > docs/changes/CHG-110/03-modification-plan.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects plan without DES- numbering" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
echo "no numbering" > docs/changes/CHG-110/04-test-scripts.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects tests without TC- numbering" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '## 问题\nx\n## 开放问题\nz\n' > docs/changes/CHG-110/00-intent.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects intent missing expected-outcome section" 2 $?

# v2.20.0 专业角色标记负例：选型对比 / 覆盖维度 / 02 三维 / 03.5 依赖里程碑
seed_artifacts CHG-110 L1 claude/s-1
printf '# plan\n- DES-001: sample design\n' > docs/changes/CHG-110/03-modification-plan.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects plan without option-comparison markers" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '# tests\n- TC-001: sample case\n' > docs/changes/CHG-110/04-test-scripts.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects tests without coverage-dimension column" 2 $?

# v3.3.0：04 必含业务场景清单（SC- 编号），缺 SC 拒绝
seed_artifacts CHG-110 L1 claude/s-1
printf '# tests\n- TC-001: sample case\n## 用例矩阵\n覆盖维度: 正常流\n' > docs/changes/CHG-110/04-test-scripts.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects tests without SC- scenario numbering" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '# impact\n## 技术影响\ncall chain only\n' > docs/changes/CHG-110/02-code-impact-analysis.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects impact doc without business-impact section" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '# impact\n## 业务影响\nx\n## 风险\ny\n' > docs/changes/CHG-110/02-code-impact-analysis.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects impact doc without rollback strategy" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
printf '# tasks\n- T-001: do something\n' > docs/changes/CHG-110/03.5-tasks.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects tasks doc without dependency/milestone markers" 2 $?

# v2.22.0：豁免路径 / 缺 02 / 缺 03.5
seed_artifacts CHG-110 L1 claude/s-1
printf '# tasks\nCHG 直接实施（未拆任务，理由: trivial）\n' > docs/changes/CHG-110/03.5-tasks.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin accepts tasks doc with explicit exemption" 0 $?

seed_artifacts CHG-110 L1 claude/s-1
rm docs/changes/CHG-110/02-code-impact-analysis.md   # 缺影响分析：先分析后方案必须拒绝
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects missing impact analysis doc" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
rm docs/changes/CHG-110/03.5-tasks.md   # 缺任务拆解：必须拒绝
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin rejects missing tasks doc" 2 $?

seed_artifacts CHG-110 L1 claude/s-1
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
report "begin accepts compliant A-layer content markers" 0 $?

# ---------------------------------------------------------------- T2 治理状态校验
new_repo
seed_artifacts CHG-200 L2 gemini/m-1 gemini/m-1 gemini/m-2   # test 与 impl 相同
scripts/agent-gate begin CHG-200 >/dev/null 2>&1
report "begin rejects identical implementation/test owners at L2" 2 $?

seed_artifacts CHG-201 L2 gemini/m-1 claude/c-9 codex/x-7
scripts/agent-gate begin CHG-201 >/dev/null 2>&1
report "begin accepts distinct owners at L2" 0 $?

new_repo
seed_artifacts CHG-202 L1 claude/s-1
printf '{"change_id":"OTHER","risk_level":"L1","implementation_owner":"a"}\n' \
  > docs/changes/CHG-202/00-governance.json
scripts/agent-gate begin CHG-202 >/dev/null 2>&1
report "begin rejects mismatched change_id" 2 $?

new_repo
seed_artifacts CHG-203 L9 claude/s-1
scripts/agent-gate begin CHG-203 >/dev/null 2>&1
report "begin rejects invalid risk_level" 2 $?

# v3.5.0：占位 owner 与 L3 授权三字段
new_repo
seed_artifacts CHG-204 L1 PENDING
scripts/agent-gate begin CHG-204 >/dev/null 2>&1
report "begin rejects PENDING implementation owner" 2 $?

seed_artifacts CHG-205 L2 gemini/m-1 TODO codex/x-7
scripts/agent-gate begin CHG-205 >/dev/null 2>&1
report "begin rejects TODO test owner at L2" 2 $?

seed_artifacts CHG-206 L3 gemini/m-1 claude/c-9 codex/x-7
printf '{"change_id":"CHG-206","risk_level":"L3","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7"}\n' \
  > docs/changes/CHG-206/00-governance.json
scripts/agent-gate begin CHG-206 >/dev/null 2>&1
report "begin rejects L3 without release authorization fields" 2 $?

seed_artifacts CHG-207 L3 gemini/m-1 claude/c-9 codex/x-7
printf '{"change_id":"CHG-207","risk_level":"L3","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7","release_authorized_by":"tech-lead/h-1","release_authorized_at":"2026-09-09T00:00:00Z","release_authorization_evidence":"APPROVAL-001"}\n' \
  > docs/changes/CHG-207/00-governance.json
scripts/agent-gate begin CHG-207 >/dev/null 2>&1
report "begin accepts L3 with complete release authorization" 0 $?

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

seed_artifacts CHG-300 L1 claude/s-1
scripts/agent-gate begin CHG-300 >/dev/null 2>&1
printf '%s' '{"tool_name":"Write","tool_input":{"path":"src/new.py"}}' \
  | scripts/agent-gate --stage pre-write >/dev/null 2>&1
report "pre-write allows code edit with active change" 0 $?

scripts/agent-gate --stage pre-write --file src/other.ts >/dev/null 2>&1
report "pre-write accepts --file argument" 0 $?

scripts/agent-gate end >/dev/null 2>&1
scripts/agent-gate --stage pre-write --file src/other.ts >/dev/null 2>&1
report "pre-write blocks after end" 2 $?

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

# ---------------------------------------------------------------- T5 stop
new_repo
seed_artifacts CHG-500 L1 claude/s-1
commit_all "docs: CHG-500 artifacts"
scripts/agent-gate begin CHG-500 >/dev/null 2>&1
echo y > src/b.js   # 未跟踪文件计入工作区代码变更
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks finish without test evidence" 2 $?

echo results > docs/changes/CHG-500/05-test-results.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks finish without changelog" 2 $?

echo chg > docs/changes/CHG-500/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop blocks finish without ReAct Observation records" 2 $?

printf 'chg\n#### 执行记录（ReAct）\n| 阶段 | Thought | Observation |\n|---|---|---|\n| 阶段1 | t | grep -c REQ- 01-spec.md -> 1 |\n' > docs/changes/CHG-500/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop passes with evidence and changelog" 0 $?

AGENT_GUARD_VERIFY_COMMAND='false' scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop runs AGENT_GUARD_VERIFY_COMMAND and fails on it" 2 $?

AGENT_GUARD_VERIFY_COMMAND='true' scripts/agent-gate --stage stop >/dev/null 2>&1
report "stop passes when AGENT_GUARD_VERIFY_COMMAND succeeds" 0 $?

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
echo z > src/c.ts
git add -A
commit_all "feat: CHG-601 implement"
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci accepts code diff committed with artifacts and delivery evidence" 0 $?

# v3.5.0：branch 模式对 diff 触及的变更目录追加 delivery 证据校验（与 stop 同口径）
new_repo
base=$(git rev-parse HEAD)
seed_artifacts CHG-620 L1 claude/s-1
commit_all "docs: CHG-620 artifacts"
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci rejects docs-only diff whose change lacks delivery evidence" 2 $?
printf 'results\n' > docs/changes/CHG-620/05-test-results.md
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/CHG-620/09-changelog.md
commit_all "docs: CHG-620 delivery evidence"
scripts/agent-gate --stage ci --base "$base" >/dev/null 2>&1
report "ci accepts docs-only diff after delivery evidence lands" 0 $?

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
commit_all "docs: CHG-700 evidence"
out=$(scripts/agent-gate metrics)
check_output "metrics flips delivery_ready after evidence" '"delivery_ready":true' "$out"

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

# ---------------------------------------------------------------- T8 change_root 覆盖
new_repo
mkdir -p changes/CUSTOM-1
export AGENT_GUARD_CHANGE_ROOT=changes
cat > changes/CUSTOM-1/00-intent.md <<'EOF'
## 问题
i
## 预期结果
e
## 开放问题
o
EOF
printf '{"change_id":"CUSTOM-1","risk_level":"L0","implementation_owner":"a"}\n' > changes/CUSTOM-1/00-governance.json
echo "REQ-001 s" > changes/CUSTOM-1/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n' > changes/CUSTOM-1/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n' > changes/CUSTOM-1/03-modification-plan.md
printf '# tasks\n- T-001: x（依赖: 无；里程碑: M1）\n' > changes/CUSTOM-1/03.5-tasks.md
printf 'TC-001 t\n## 用例矩阵\n覆盖维度: 正常流\n## 业务场景清单\nSC-001 s（覆盖: TC-001）\n' > changes/CUSTOM-1/04-test-scripts.md
scripts/agent-gate begin CUSTOM-1 >/dev/null 2>&1
report "begin honors AGENT_GUARD_CHANGE_ROOT" 0 $?
unset AGENT_GUARD_CHANGE_ROOT

# ---------------------------------------------------------------- T9 help
new_repo
scripts/agent-gate help >/dev/null 2>&1
report "help exits 0" 0 $?
scripts/agent-gate bogus >/dev/null 2>&1
report "unknown command exits 2" 2 $?

# ------------------------------------------------ T10 audit-docs-consistency golden cases
# §2.17.4：治理配置模板自身必须可回归。对通用层 audit-docs-consistency.sh 构造
# 目标仓库 fixture：合规态全绿 / 跳号 / 归档清单漂移 / BUG 未登记 三类负例 / 未接入仓库 SKIP。
AUDIT_SRC="$ROOT/resources/templates/audit-docs-consistency.sh"
[[ -f "$AUDIT_SRC" ]] || AUDIT_SRC="$ROOT/tests/audit-docs-consistency.sh"
STD_SRC="$ROOT/resources/DEVELOPMENT_STANDARDS.md"
[[ -f "$STD_SRC" ]] || STD_SRC="$ROOT/docs/DEVELOPMENT_STANDARDS.md"
AG_SRC="$ROOT/resources/AGENTS.md"
[[ -f "$AG_SRC" ]] || AG_SRC="$ROOT/AGENTS.md"

audit_fixture() { # dest -> 构造合规目标仓库 fixture
  local dest="$1"
  rm -rf "$dest"; mkdir -p "$dest/docs/feata"
  cp "$STD_SRC" "$dest/docs/DEVELOPMENT_STANDARDS.md"
  cp "$AG_SRC" "$dest/AGENTS.md"
  printf -- '- REQ-001 用户故事A（DoD: x）\n- REQ-002 用户故事B（DoD: y）\n' > "$dest/docs/feata/01-spec.md"
  printf '# plan\n\nDES-001 设计\n' > "$dest/docs/feata/03-modification-plan.md"
  printf '# tests\n\n| TC | 场景 | 覆盖维度 | 覆盖的 REQ-DES |\n|---|---|---|---|\n| TC-001 | a | 正常流 | REQ-001 |\n| TC-002 | b | 边界 | REQ-002 |\n\n## 业务场景清单\n\nSC-001 场景（覆盖: TC-001）\n' > "$dest/docs/feata/04-test-scripts.md"
  printf '| REQ-001 | x | DES-001 | y | T1 | CHG-001 | TC-001 | test | PASS |\n| REQ-002 | x | DES-001 | y | T1 | CHG-001 | TC-001 | test | PASS |\n' > "$dest/docs/feata/01.5-rtvm-matrix.md"
  { echo "### BUG-001：现象（严重度 P1）"; echo; echo "| 字段 | 内容 |"; echo "|---|---|"; echo "| 关联变更 | CHG-001 |"; } > "$dest/docs/bugfix-log.md"
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
  rm -f "$dest/s3block.md"
}

FX=$(mktemp -d)
audit_fixture "$FX"
bash "$AUDIT_SRC" "$FX" >/dev/null 2>&1
report "audit fixture compliant repo passes" 0 $?

FX2=$(mktemp -d)
audit_fixture "$FX2"
printf -- '- REQ-004 用户故事D（DoD: z）\n' >> "$FX2/docs/feata/01-spec.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit rejects numbering gap (REQ-003 missing)" 1 $?

audit_fixture "$FX2"
sed -i '' '/【角色分派与独立性】/d' "$FX2/docs/feata/09-changelog.md" 2>/dev/null \
  || sed -i '/【角色分派与独立性】/d' "$FX2/docs/feata/09-changelog.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit rejects archived checklist drift vs §3" 1 $?

audit_fixture "$FX2"
sed -i '' 's/`BUG-001`（索引见 docs\/bugfix-log.md）/`BUG-001`、`BUG-009`（索引见 docs\/bugfix-log.md）/' "$FX2/docs/feata/09-changelog.md" 2>/dev/null \
  || sed -i 's/`BUG-001`（索引见 docs\/bugfix-log.md）/`BUG-001`、`BUG-009`（索引见 docs\/bugfix-log.md）/' "$FX2/docs/feata/09-changelog.md"
bash "$AUDIT_SRC" "$FX2" >/dev/null 2>&1
report "audit rejects unregistered BUG in CHG" 1 $?

SKIPD=$(mktemp -d)
bash "$AUDIT_SRC" "$SKIPD" >/dev/null 2>&1
report "audit skips repo without standards" 0 $?
rm -rf "$FX" "$FX2" "$SKIPD"

# ---------------------------------------------------------------- 摘要
printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
  printf 'failed cases: %s\n' "${failed_names[*]}" >&2
  exit 1
fi
exit 0
