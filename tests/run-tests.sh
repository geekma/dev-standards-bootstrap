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
# Usage: tests/run-tests.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# 源位置回退：Skill 仓库内为 resources/templates/（原样），bootstrap --core/--guard 落地的
# 目标仓库为 tests/audit-docs-consistency.sh 与 scripts/agent-gate——同一份 run-tests.sh
# 必须在两种布局都可用。
GATE_SRC="$ROOT/resources/templates/agent-gate.sh"
[[ -f "$GATE_SRC" ]] || GATE_SRC="$ROOT/scripts/agent-gate"
BOOT_SRC="$ROOT/scripts/bootstrap.sh"
AUDIT_SRC="$ROOT/resources/templates/audit-docs-consistency.sh"
[[ -f "$AUDIT_SRC" ]] || AUDIT_SRC="$ROOT/tests/audit-docs-consistency.sh"
STD_SRC="$ROOT/resources/DEVELOPMENT_STANDARDS.md"
[[ -f "$STD_SRC" ]] || STD_SRC="$ROOT/docs/DEVELOPMENT_STANDARDS.md"
AG_SRC="$ROOT/resources/AGENTS.md"
[[ -f "$AG_SRC" ]] || AG_SRC="$ROOT/AGENTS.md"

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
  seed_project_masters
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
    printf '{"change_id":"%s","risk_level":"%s","spec_author":"author/a-1","implementation_owner":"%s","test_owner":"%s","review_owner":"%s"}\n' \
      "$id" "$risk" "$impl" "$test" "$review" > "$d/00-governance.json"
  else
    printf '{"change_id":"%s","risk_level":"%s","spec_author":"author/a-1","implementation_owner":"%s"}\n' \
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

# v3.35.0（§1.3）：begin 强制项目总册在位——所有夹具仓库开箱即含 12 册最小骨架
#（含「总册编号」与「独立完整声明」自证行 + 逐册评审存根）；T23 负例删除后再验拒绝路径。
seed_project_masters() {
  mkdir -p docs/project/reviews
  local p
  for p in P00-project-charter P01-requirements-master P02-architecture-master P03-interface-registry P04-data-dictionary P05-task-plan P06-test-master P07-test-verdicts P08-deployment-master P09-risk-register P10-change-ledger P11-decision-log; do
    printf '# master\n总册编号：%s\n独立完整声明：fixture\n' "${p%%-*}" > "docs/project/$p.md"
    printf '# review R-%s\n' "${p%%-*}" > "docs/project/reviews/$p.md.review.md"
  done
}

# v3.35.0（§1.3）：交付侧 09 追加「项目总册回填清单」节（幂等；已存在则跳过）。
append_masters() { # <09-file>
  local f="$1" p
  [[ -f "$f" ]] || return 0
  grep -q '项目总册回填清单' "$f" && return 0
  {
    printf '\n#### 项目总册回填清单\n'
    for p in P00 P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11; do
      printf -- '- [x] %s 已回填（章节：fixture；变更注记 CHG-999）\n' "$p"
    done
  } >> "$f"
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

# CHG-007 / FU-008：编号必须带数字——散文提及 "REQ-"（无编号）不再放行
seed_artifacts CHG-110 L1 claude/s-1
printf '# spec\n需求编号参见 REQ- 约定（无具体编号）。\n' > docs/changes/CHG-110/01-spec.md
scripts/agent-gate begin CHG-110 >/dev/null 2>&1
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
printf '{"change_id":"OTHER","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"a"}\n' \
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
printf '{"change_id":"CHG-206","risk_level":"L3","spec_author":"author/a-1","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7"}\n' \
  > docs/changes/CHG-206/00-governance.json
scripts/agent-gate begin CHG-206 >/dev/null 2>&1
report "begin rejects L3 without release authorization fields" 2 $?

seed_artifacts CHG-207 L3 gemini/m-1 claude/c-9 codex/x-7
printf '{"change_id":"CHG-207","risk_level":"L3","spec_author":"author/a-1","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7","release_authorized_by":"tech-lead/h-1","release_authorized_at":"2026-09-09T00:00:00Z","release_authorization_evidence":"APPROVAL-001"}\n' \
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

printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop still accepts a structured FU table row (FU-020 positive)" 0 $?

printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-500/06-delivery-summary.md
scripts/agent-gate --stage stop >/dev/null 2>&1
stamp_fixture_all
report "stop passes with evidence and changelog" 0 $?

# ------------------------------------------------ T22 规则 10 A 层执法（v3.33.0）
# 生产-评审分离（§2.2 两批制）与 spec_author 的机器执法：记录级（begin）+
# 交付级（stop 署名节）。标题形态才触发；正文行内提及不触发（FU-014 同族教训）。
printf '\n## 专家评审记录\n| 主体 | 结论 |\n|---|---|\n| 业务专家 | 通过 |\n' >> docs/changes/CHG-500/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "stop rejects a signature-less 专家评审记录 section (FU-039)" "lacks an agent signature" "$out"
printf '\n署名：opencode / glm-5.3-flash / task-review-01\n' >> docs/changes/CHG-500/01-spec.md
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
printf '\n署名：opencode / glm-5.3-flash / task-review-02\n' >> docs/changes/CHG-500/03-modification-plan.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
stamp_fixture_all
report "stop accepts both sections once each carries a canonical signature" 0 "$rc"

# T22 的记录级用例（CHG-610/611）在套件尾部独立仓执行——不能内插在 CHG-500
# 流中部：new_repo 会重置夹具仓库，后续 CHG-500 用例将整体失联（本轮实测）。

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
append_masters docs/changes/CHG-700/09-changelog.md
commit_all "docs: CHG-700 evidence"
out=$(scripts/agent-gate metrics)
check_output "metrics flips delivery_ready after evidence" '"delivery_ready":true' "$out"
# v3.34.0（CHG-034）：专家会话数观测字段（只观测不拦截）
check_output "metrics emits expert_sessions field" '"expert_sessions":[0-9]+,"expert_sessions_over_guardrail":(true|false)' "$out"
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

# ------------------------------------------------ T7b bug_ref 缺陷文档组（v3.6.0）
new_repo
seed_artifacts CHG-800 L1 claude/s-1
mkdir -p docs/bugs/BUG-042
printf '# diagnosis\n' > docs/bugs/BUG-042/01-diagnosis.md
printf '# impact\n' > docs/bugs/BUG-042/02-impact.md
printf '# test plan\n' > docs/bugs/BUG-042/03-test-plan.md
printf '# matrix\n' > docs/bugs/BUG-042/04-matrix.md
printf '# config\n' > docs/bugs/BUG-042/05-config.md
printf '# tasks\n' > docs/bugs/BUG-042/06-tasks.md
printf '{"change_id":"CHG-800","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","bug_ref":"BUG-042"}\n' > docs/changes/CHG-800/00-governance.json
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

printf '# diagnosis restored\n' > docs/bugs/BUG-042/01-diagnosis.md
rm docs/bugs/BUG-042/04-matrix.md   # v3.7.0：六件套缺一件同样拦截
out=$(scripts/agent-gate begin CHG-800 2>&1 || true)
check_output "begin names a v3.7.0 defect doc when missing" "missing defect document: docs/bugs/BUG-042/04-matrix.md" "$out"
printf '# matrix recreated\n' > docs/bugs/BUG-042/04-matrix.md
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin accepts bug_ref after all six defect docs land" 0 $?
printf '{"change_id":"CHG-800","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","bug_ref":""}\n' > docs/changes/CHG-800/00-governance.json
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin skips bug_ref validation when empty" 0 $?

printf '{"change_id":"CHG-800","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","bug_ref":"../evil"}\n' > docs/changes/CHG-800/00-governance.json
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "begin rejects bug_ref with path-unsafe defect id" 2 $?

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
printf '{"change_id":"CUSTOM-1","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"a"}\n' > changes/CUSTOM-1/00-governance.json
echo "REQ-001 s" > changes/CUSTOM-1/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n' > changes/CUSTOM-1/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n' > changes/CUSTOM-1/03-modification-plan.md
printf '# tasks\n- T-001: x（依赖: 无；里程碑: M1）\n- 评审输入: 变更文件清单 + 产物路径 + 行号锚点\n' > changes/CUSTOM-1/03.5-tasks.md
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
# 源位置回退：Skill 仓库为 resources/templates/，bootstrap --core 落地目标仓库为
# tests/audit-docs-consistency.sh（v3.7 规范位置）；未安装 --core 时整节跳过。
if [[ -f "$AUDIT_SRC" ]]; then

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
  append_masters "$dest/docs/feata/09-changelog.md"
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

printf '# different content\n' > "$BT/AGENTS.md"
bash "$BOOT_SRC" --core "$BT" >/dev/null 2>&1
report "bootstrap rejects conflicting existing file" 2 $?
out=$(bash "$BOOT_SRC" --core "$BT" 2>&1 || true)
check_output "bootstrap names the conflicting file" "CONFLICT.*AGENTS.md" "$out"

bash "$BOOT_SRC" --core --force "$BT" >/dev/null 2>&1
report "bootstrap --force overwrites conflict" 0 $?
grep -q "本文件是所有 AI Agent" "$BT/AGENTS.md"
report "bootstrap --force restores template content" 0 $?

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

# ------------------------------------------------ T12 双校验器扩展名清单一致
# compliance.sh 与 agent-gate is_code_path 共享"代码后缀"策略（工程兜底层须可独立
# 安装，故不合并为单校验器）；漂移由源层 audit A2 + 本 T12 运行时双守护。
# 任一处新增/删除代码后缀而不同步，本用例即红——从"发布前 audit 发现"提前到"改完即发现"。
gate_ext=$(grep -E '\\\.\(c\|' "$GATE_SRC" | head -1 | sed -E 's/.*\\\.\(([^)]+)\)\$.*/\1/')
ci_src="$ROOT/resources/templates/check-standards-compliance.sh"
[[ -f "$ci_src" ]] || ci_src="$ROOT/scripts/check-standards-compliance.sh"
if [[ -f "$ci_src" ]]; then
ci_ext=$(grep -E '\\\.\(c\|' "$ci_src" | head -1 | sed -E 's/.*\\\.\(([^)]+)\)\$.*/\1/')
report "T12 code-extension list identical in gate and compliance.sh" "$gate_ext" "$ci_ext"
else
  echo "SKIP T12: check-standards-compliance.sh 未安装（bootstrap --ci 未运行）——跳过双校验器一致用例"
fi

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
## 开放问题
o
EOF
printf '{"change_id":"CFG-1","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"a"}\n' > doc/changes/CFG-1/00-governance.json
echo "REQ-001 s" > doc/changes/CFG-1/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n' > doc/changes/CFG-1/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n' > doc/changes/CFG-1/03-modification-plan.md
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
## 开放问题
o
EOF
printf '{"change_id":"CFG-2","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"a"}\n' > doc/changes/CFG-2/00-governance.json
echo "REQ-001 s" > doc/changes/CFG-2/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n' > doc/changes/CFG-2/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n' > doc/changes/CFG-2/03-modification-plan.md
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

# ------------------------------------------------ T17 溯源脚本本体（v3.17.0）
# T16 验的是**门禁的校验逻辑**（内联块，与布局无关）；T17 验的是**脚本本体的产出**——
# 真值取自环境、写入幂等、隐私开关、--check、以及"真脚本产出能过真门禁"的端到端闭环。
# 脚本是 --guard 层文件：目标仓未装 guard 层时不存在 → SKIP（同 T15 的布局自适应）。
STAMP_SRC="$ROOT/resources/templates/stamp-provenance.sh"
[[ -f "$STAMP_SRC" ]] || STAMP_SRC="$ROOT/scripts/stamp-provenance.sh"
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
  scripts/stamp-provenance.sh --all CHG-700 >/dev/null 2>&1
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T17 gate accepts a real script-stamped record (end-to-end)" 0 $?
else
  echo "SKIP T17: stamp-provenance.sh 为 --guard 层文件（未装 guard 层时不存在）"
fi

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

# ------------------------------------------------ T18 变更批次 / 同日合并（v3.18.0）
# 批次把"一个变更一套产物"放宽为"一套产物承载多个变更"。本组端到端验证放宽的**边界**：
# 目录放宽但文件名不变、治理记录必须逐变更成行（否则读到兄弟的风险）、风险上限不放宽、
# 闭环判定细一档（看自己的锚点而非共享文件），以及被 T17 掩盖的 `--stage staged` 路径
# （批次解析发生在 `$( )` 子壳里，与 begin 的全局变量路径不同——bash 3.2 的
# `local a="$1" b="...$a"` 缺陷正是在这里才会暴露）。
# v3.19.0 补 ④b：**权威名单**方向。批次共享产物必然含结构标题（§2.16.2 的
# `## Observation`），"把 `## <ascii 单词>` 当变更号"会让 metrics 造出幽灵变更、
# 让 `--stage staged` 拒掉整批。夹具必须用真实形状，不能用更规整的形状绕开。
# 批次夹具：一个 BATCH-YYYYMMDD/ 目录承载多个变更，文件名与独立目录**完全同名**，
# 靠 `## <id>` 锚点区分，治理记录一行一变更。
seed_batch_artifacts() { # <batch-id> <id:risk> [<id:risk> ...]
  local batch="$1"; shift
  local d="docs/changes/$batch" pair id risk
  mkdir -p "$d"
  : > "$d/00-intent.md"
  : > "$d/00-governance.json"
  : > "$d/01-spec.md"
  : > "$d/02-code-impact-analysis.md"
  : > "$d/03-modification-plan.md"
  : > "$d/03.5-tasks.md"
  : > "$d/04-test-scripts.md"
  for pair in "$@"; do
    id="${pair%%:*}"; risk="${pair##*:}"
    printf '{"change_id":"%s","risk_level":"%s","spec_author":"author/a-1","implementation_owner":"claude/s-1"}\n' "$id" "$risk" >> "$d/00-governance.json"
    printf '## %s\n## 问题\nproblem: x\n## 预期结果\nexpected: y\n## 开放问题\nopen: none\n' "$id" >> "$d/00-intent.md"
    printf '## %s\nREQ-901: r\n' "$id" >> "$d/01-spec.md"
    printf '## %s\n### 业务影响\n### 风险\n### 回滚策略\n' "$id" >> "$d/02-code-impact-analysis.md"
    printf '## %s\nDES-901 备选方案对比\n' "$id" >> "$d/03-modification-plan.md"
    printf '## %s\n直接实施\n' "$id" >> "$d/03.5-tasks.md"
    printf '## %s\nTC-901 SC-901 覆盖维度\n' "$id" >> "$d/04-test-scripts.md"
  done
}

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
report "T18 metrics still emits one row per declared change" 2 "$(wc -l < "$t18m2" | tr -d ' ')"
rm -f "$t18m2"

# ⑤ 风险上限不放宽：批次共享产物会削弱逐变更证据边界与角色独立性，
#    L2/L3 必须独立目录——门禁按**记录**拒绝，不能靠目录布局绕过
printf '{"change_id":"CHG-802","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"a","test_owner":"b","review_owner":"c"}\n' >> "$t18gov"
printf '## CHG-802\n## 问题\nx\n## 预期结果\ny\n## 开放问题\nn\n' >> docs/changes/BATCH-20260101/00-intent.md
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
seed_artifacts CHG-810 L1 claude/s-1
scripts/agent-gate begin CHG-810 >/dev/null 2>&1
report "T18 dedicated directory still resolves to itself (no regression)" 0 $?
seed_artifacts CHG-811 L2 claude/s-1 tester reviewer
scripts/agent-gate begin CHG-811 >/dev/null 2>&1
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

# ------------------------------------------------ T18b 同日批次默认强制（v3.27.0，CHG-027）
# §1.1 v3.24.0 把"同日多个 L0/L1 默认共用批次"写成默认，但 begin 不拦就是纯建议
# （下游实测：同日 5 组 L0/L1 全部各开独立目录）。本组验证：当日批次已存在时，
# 独立 L0/L1 begin 必须被拦；豁免必须显式；入批与 L2 独立照常。
new_repo
seed_batch_artifacts "BATCH-$(date +%Y%m%d)" CHG-820:L0
commit_all "docs: today's batch exists"
seed_artifacts CHG-821 L1 claude/s-1
scripts/agent-gate begin CHG-821 >/dev/null 2>&1
report "T18b begin rejects an independent L0/L1 when a same-day batch exists" 2 $?
out=$(scripts/agent-gate begin CHG-821 2>&1 || true)
check_output "T18b refusal names the batch and the escape hatch" "same-day batch exists.*AGENT_GUARD_ALLOW_INDEPENDENT" "$out"
AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-821 >/dev/null 2>&1
report "T18b explicit override allows an independent L0/L1" 0 $?
seed_batch_artifacts "BATCH-$(date +%Y%m%d)" CHG-822:L1
scripts/agent-gate begin CHG-822 >/dev/null 2>&1
report "T18b joining the same-day batch begins" 0 $?
seed_artifacts CHG-823 L2 claude/s-1 tester reviewer
scripts/agent-gate begin CHG-823 >/dev/null 2>&1
report "T18b L2 keeps its independent-directory right (no batch compulsion)" 0 $?

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
  "spec_author":"author/a-1","implementation_owner": "claude/s-1"
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
  "spec_author":"author/a-1","implementation_owner": "claude/s-1"
},
{
  "change_id": "CHG-831",
  "risk_level": "L1",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1"
}
EOF
t19b=$(scripts/agent-gate metrics 2>&1)
check_output "T19 a multi-line batch member reads its OWN risk" '"change_id":"CHG-830","risk_level":"L0"' "$t19b"
check_output "T19 the sibling reads its own risk, not the first record's" '"change_id":"CHG-831","risk_level":"L1"' "$t19b"
scripts/agent-gate begin CHG-831 >/dev/null 2>&1
report "T19 a member of a multi-line batch begins" 0 $?

# ⑤ 零回归：单行记录（历史与批次推荐写法）继续可用
new_repo
seed_artifacts CHG-842 L1 claude/s-1
scripts/agent-gate begin CHG-842 >/dev/null 2>&1
report "T19 one-line records still begin (no regression)" 0 $?

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

audit_change_fixture() { # dest -> 管线态布局：产物落 docs/changes/CHG-001/
  local dest="$1"
  rm -rf "$dest"; mkdir -p "$dest/docs/changes/CHG-001"
  cp "$STD_SRC" "$dest/docs/DEVELOPMENT_STANDARDS.md"
  cp "$AG_SRC" "$dest/AGENTS.md"
  printf '# spec\n\n## REQ-001 第一个需求\n## REQ-002 第二个需求\n' > "$dest/docs/changes/CHG-001/01-spec.md"
  printf '# CHG-001 Changelog\n\n## 2026-09-15\n' > "$dest/docs/changes/CHG-001/09-changelog.md"
}

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
{ echo '### BUG-001：现象（严重度 P1）'; echo; echo '| 字段 | 内容 |'; echo '|---|---|'; echo '| 关联变更 | CHG-001 |'; } > "$AC4/docs/bugfix-log.md"
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

# ------------------------------------------------ T21 一键安装器 install.sh（v3.22.0）
# install.sh 与 bootstrap.sh 同属源层工具（不随 --guard 分发）——目标仓布局自动 SKIP。
# 夹具用**最小 fake 源仓**（scripts/bootstrap.sh + tests/run-tests.sh + resources/，
# 无 .git）走 --from 离线路径：既覆盖"克隆之外"的全部逻辑，又保证测试零网络依赖。
if [[ -f "$ROOT/scripts/install.sh" && -f "$BOOT_SRC" ]]; then
  FAKE_SRC=$(mktemp -d "${TMPDIR:-/tmp}/install-src.XXXXXX")
  mkdir -p "$FAKE_SRC/scripts" "$FAKE_SRC/tests"
  cp "$ROOT/scripts/bootstrap.sh" "$FAKE_SRC/scripts/bootstrap.sh"
  cp "$ROOT/tests/run-tests.sh" "$FAKE_SRC/tests/run-tests.sh"
  cp "$ROOT/SKILL.md" "$FAKE_SRC/SKILL.md"
  cp -R "$ROOT/resources" "$FAKE_SRC/resources"

  TGT=$(mktemp -d "${TMPDIR:-/tmp}/install-tgt.XXXXXX")
  (cd "$TGT" && git init -q && git config user.email t@x.invalid && git config user.name t \
    && echo hi > README.md && git add README.md && git commit -qm init)

  # TC-141 离线全量安装
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT" 2>&1); rc=$?
  report "T21 install.sh --from performs a full offline install" 0 "$rc"
  for f in AGENTS.md docs/DEVELOPMENT_STANDARDS.md scripts/agent-gate .githooks/pre-commit \
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

  # TC-144 冲突 fail-closed：目标已有不同 AGENTS.md → CONFLICT 拒绝，不静默覆盖
  TGT2=$(mktemp -d "${TMPDIR:-/tmp}/install-tgt2.XXXXXX")
  printf '# my own agents file\n' > "$TGT2/AGENTS.md"
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT2" 2>&1); rc=$?
  report "T21 conflicting AGENTS.md fails closed" 2 "$rc"
  check_output "T21 conflict path prints CONFLICT and a --force hint" "CONFLICT.*--force" "$out"
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

# ------------------------------------------------ T18c 缺陷六件套按天入批（v3.35.0，BUG-005）
# §1.1 v3.35.0 废止 v3.22.0"缺陷组不入批"：当日缺陷批次已存在时，同日新建的独立
# 缺陷组必须入批（provenance generated_at 判日）；豁免显式；批次嵌套组照常扫描。
new_repo
seed_artifacts CHG-900 L1 claude/s-1
scripts/agent-gate begin CHG-900 >/dev/null 2>&1
today=$(date -u +%Y%m%d)
mkdir -p "docs/bugs/BATCH-$today/BUG-901"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# %s\n' "$d6" > "docs/bugs/BATCH-$today/BUG-901/$d6.md"
done
seed_artifacts CHG-902 L0 claude/s-1
printf '{"change_id":"CHG-902","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","bug_ref":"BUG-901"}\n' > docs/changes/CHG-902/00-governance.json
scripts/agent-gate begin CHG-902 >/dev/null 2>&1
report "T18c begin resolves a bug_ref bound to a batched defect group" 0 $?
mkdir -p docs/bugs/BUG-902
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# %s\n' "$d6" > "docs/bugs/BUG-902/$d6.md"
done
{ printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: %sT00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n' "$(date -u +%Y-%m-%d)"; cat docs/bugs/BUG-902/01-diagnosis.md; } > docs/bugs/BUG-902/01-diagnosis.md.tmp && mv docs/bugs/BUG-902/01-diagnosis.md.tmp docs/bugs/BUG-902/01-diagnosis.md
echo y > src/z.js   # staged/stop 只在存在代码路径改动时执法（对齐 T4/T5 夹具）
git add -A          # staged 以暂存区为准，空暂存即空转放行
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c defect groups join the same-day batch (standalone today is rejected)" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
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

# ------------------------------------------------ T18d 缺陷批次扁平化（v3.36.0，BUG-006）
# §1.1 v3.36.0：同日多缺陷共落 BATCH-YYYYMMDD/ 扁平目录——六件套同名文件 + `## <BUG-id>`
# 锚点分节，当天追加落在同一套文件里（与变更批次同构）；嵌套形态历史合法；
# bug_group_dir 三形态统一解析（独立 → 嵌套 → 扁平锚点，多处命中 fail-closed）。
new_repo
seed_artifacts CHG-930 L1 claude/s-1
scripts/agent-gate begin CHG-930 >/dev/null 2>&1
today=$(date -u +%Y%m%d)
mkdir -p "docs/bugs/BATCH-$today"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# flat batch\n\n## BUG-903 flat member\n' > "docs/bugs/BATCH-$today/$d6.md"
done
# 负例铺垫：BUG-904 只在诊断件锚定（其余五件缺同 id 小节 → 六件锚点不齐）
printf '\n## BUG-904 member\n' >> "docs/bugs/BATCH-$today/01-diagnosis.md"
seed_artifacts CHG-931 L0 claude/s-1
printf '{"change_id":"CHG-931","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","bug_ref":"BUG-903"}\n' > docs/changes/CHG-931/00-governance.json
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
cp "$ROOT/resources/templates/stamp-provenance.sh" scripts/stamp-provenance.sh
scripts/stamp-provenance.sh --bug BUG-903 >/dev/null 2>&1
report "T18d --bug resolves and stamps a flat batch member" 0 $?
check_output "T18d flat stamp attests the batch id" "^bug: BATCH-" "$(cat "docs/bugs/BATCH-$today/01-diagnosis.md")"
check_output "T18d flat stamp lists the members" "^batch_changes: BUG-90[34]" "$(cat "docs/bugs/BATCH-$today/01-diagnosis.md")"
mkdir -p "docs/bugs/BATCH-$today/BUG-905"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# nested\n' > "docs/bugs/BATCH-$today/BUG-905/$d6.md"
done
seed_artifacts CHG-932 L0 claude/s-1
printf '{"change_id":"CHG-932","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","bug_ref":"BUG-905"}\n' > docs/changes/CHG-932/00-governance.json
scripts/agent-gate begin CHG-932 >/dev/null 2>&1
report "T18d nested legacy group still resolves under the three-form resolver" 0 $?

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
report "T23 begin passes once the twelve masters exist" 0 $?
rm docs/project/P11-decision-log.md
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

# ------------------------------------------------ T24 session water level (v3.38.0)
new_repo
seed_artifacts CHG-920 L1 claude/s-1
mkdir -p .agent-state
printf '{"turns":80,"session":"s-1","updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-water.json
out=$(scripts/agent-gate begin CHG-920 2>&1); rc=$?
check_output "T24 begin names the water level and both escapes" "session water level 80 turns exceeds the 50-turn limit" "$out"
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

# ------------------------------------------------ T25 new-change scaffolder (v3.38.0)
new_repo
NEWCHANGE_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -f "$NEWCHANGE_SRC" ]]; then
  cp "$NEWCHANGE_SRC" scripts/new-change
  chmod +x scripts/new-change
  # 夹具内联最小入口模板（内容契约由 audit-standards-src pin 覆盖；此处测脚手架逻辑）
  mkdir -p docs/templates/entry
  cat > docs/templates/entry/00-intent.md <<'EOF'
# <__CHANGE_ID__> 意图
## 预期结果
__RISK__
## 开放问题
open
EOF
  printf '{"change_id": "__CHANGE_ID__", "risk_level": "__RISK__", "spec_author": "PENDING", "implementation_owner": "PENDING"}\n' > docs/templates/entry/00-governance.json
  printf '# <__CHANGE_ID__> spec (__RISK__)\n- REQ-001: tbd\n' > docs/templates/entry/01-spec.md
  printf '# <__CHANGE_ID__>\n## 业务影响\n## 技术影响\n## 风险\n## 回滚策略\n' > docs/templates/entry/02-code-impact-analysis.md
  printf '# <__CHANGE_ID__>\n- DES-001: tbd\n## 选型比较（备选）\n' > docs/templates/entry/03-modification-plan.md
  printf '# <__CHANGE_ID__>\n- T1: tbd（依赖: 无；里程碑: M1）\n- 评审输入: 待填（§2.2 输入契约）\n' > docs/templates/entry/03.5-tasks.md
  printf '# <__CHANGE_ID__>\n- TC-001: tbd\n覆盖维度: 正常流\n- SC-001: tbd\n' > docs/templates/entry/04-test-scripts.md

  scripts/new-change CHG-930 --risk L1 >/dev/null 2>&1
  report "T25 dedicated scaffold exits 0" 0 $?
  report "T25 scaffold creates seven entry files" 7 "$(ls docs/changes/CHG-930/*.md docs/changes/CHG-930/*.json 2>/dev/null | wc -l | tr -d ' ')"
  check_output "T25 id substituted in governance" '"change_id": "CHG-930"' "$(cat docs/changes/CHG-930/00-governance.json)"
  check_output "T25 risk substituted in spec" "L1" "$(cat docs/changes/CHG-930/01-spec.md)"
  out=$(scripts/agent-gate begin CHG-930 2>&1 || true)
  check_output "T25 PENDING owners rejected by begin" "must name a concrete owner" "$out"
  sed -i '' 's/PENDING/op\/s-930/g' docs/changes/CHG-930/00-governance.json 2>/dev/null \
    || sed -i 's/PENDING/op\/s-930/g' docs/changes/CHG-930/00-governance.json
  scripts/agent-gate begin CHG-930 >/dev/null 2>&1
  report "T25 filled scaffold passes begin (A-layer satisfied by skeleton)" 0 $?

  mkdir -p "docs/changes/BATCH-$(date +%Y%m%d)"
  printf '# intent\n## CHG-931\n## 预期结果\n## 开放问题\n' > "docs/changes/BATCH-$(date +%Y%m%d)/00-intent.md"
  printf '{"change_id": "CHG-931", "risk_level": "L0", "spec_author": "op/s-x", "implementation_owner": "op/s-x"}\n' > "docs/changes/BATCH-$(date +%Y%m%d)/00-governance.json"
  scripts/new-change CHG-932 --risk L0 >/dev/null 2>&1
  report "T25 batch-join exits 0" 0 $?
  report "T25 no dedicated dir for batch member" 0 "$(test ! -e docs/changes/CHG-932; echo $?)"
  grep -q '^## CHG-932' "docs/changes/BATCH-$(date +%Y%m%d)/01-spec.md"
  report "T25 batch shared file carries ## CHG-932 anchor" 0 $?
  report "T25 governance.json gains one line per member" 2 "$(wc -l < "docs/changes/BATCH-$(date +%Y%m%d)/00-governance.json" | tr -d ' ')"
  out=$(scripts/new-change CHG-932 --risk L0 2>&1 || true)
  check_output "T25 duplicate id in batch refused" "already has a section" "$out"
  out=$(scripts/new-change CHG-933 --risk L2 2>&1 || true)
  report "T25 L2 on a batch day goes dedicated (exit 0)" 0 $?
  report "T25 L2 dir is dedicated" 0 "$(test -d docs/changes/CHG-933; echo $?)"
  AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/new-change CHG-934 --risk L0 >/dev/null 2>&1
  report "T25 ALLOW_INDEPENDENT escapes to dedicated dir" 0 "$(test -d docs/changes/CHG-934; echo $?)"
  out=$(scripts/new-change CHG-935 2>&1 || true)
  check_output "T25 missing --risk refused" "--risk L0|L1|L2|L3 required" "$out"
  out=$(scripts/new-change CHG-936 --risk L9 2>&1 || true)
  check_output "T25 invalid risk refused" "--risk L0|L1|L2|L3 required" "$out"
else
  echo "SKIP T25: new-change.sh absent (bootstrap --guard 未安装) — 跳过脚手架 golden cases"
fi

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
else
  echo "SKIP T26: session-gate.sh absent — 跳过会话遥测 golden cases"
fi

# ------------------------------------------------ T27 pre-commit auto-stamp (v3.40.0)
new_repo
STAMP_SRC="$ROOT/resources/templates/stamp-provenance.sh"
HOOK_SRC="$ROOT/resources/templates/pre-commit"
if [[ -f "$STAMP_SRC" && -f "$HOOK_SRC" ]]; then
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  mkdir -p .githooks && cp "$HOOK_SRC" .githooks/pre-commit
  chmod +x .githooks/pre-commit scripts/stamp-provenance.sh scripts/agent-gate
  seed_artifacts CHG-940 L1 claude/s-27
  scripts/agent-gate begin CHG-940 >/dev/null 2>&1
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
  sed -i '' 's/}$/,"bug_ref":"BUG-940"}/' docs/changes/CHG-940/00-governance.json 2>/dev/null \
    || sed -i 's/}$/,"bug_ref":"BUG-940"}/' docs/changes/CHG-940/00-governance.json
  scripts/agent-gate begin CHG-940 >/dev/null 2>&1
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 hook exits 0 with bug_ref bound" 0 $?
  check_output "T27 bound defect group stamped" "generated_by: stamp-provenance.sh" "$(cat docs/bugs/BUG-940/01-diagnosis.md)"
  # comma-joined batch governance (the §1.1 recommended shape): each member's
  # bug_ref must be extracted in isolation — no cross-member bleed
  mkdir -p docs/bugs/BUG-943 docs/bugs/BUG-944
  for b in 943 944; do for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do printf '# %s\n' "$doc" > "docs/bugs/BUG-$b/$doc"; done; done
  mkdir -p docs/changes/BATCH-990922
  printf '{"change_id":"CHG-943","risk_level":"L0","spec_author":"a/x","implementation_owner":"i/x","bug_ref":"BUG-943"}{"change_id":"CHG-944","risk_level":"L0","spec_author":"a/x","implementation_owner":"i/x","bug_ref":"BUG-944"}\n' > docs/changes/BATCH-990922/00-governance.json
  seed_artifacts CHG-944 L0 claude/s-27
  scripts/agent-gate begin CHG-944 >/dev/null 2>&1
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 hook exits 0 on comma-joined batch member" 0 $?
  check_output "T27 member bug_ref stamped in isolation" "generated_by: stamp-provenance.sh" "$(cat docs/bugs/BUG-944/01-diagnosis.md)"
  if grep -q '^<!-- provenance$' docs/bugs/BUG-943/01-diagnosis.md; then report "T27 no cross-member bleed" 1 0; else report "T27 no cross-member bleed" 0 0; fi
else
  echo "SKIP T27: stamp-provenance.sh/pre-commit absent (bootstrap --guard 未安装) — 跳过自动章 golden cases"
fi

# ------------------------------------------------ T28 P3 defect lightweight channel (v3.40.0)
new_repo
seed_artifacts CHG-950 L1 claude/s-28
mkdir -p docs/bugs/BUG-950
printf '# 诊断\nseverity: P3\n现象：文案错别字\n' > docs/bugs/BUG-950/01-diagnosis.md
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
printf '# 批次诊断\n## BUG-951\nseverity: P3\n文案\n## BUG-952\n无 severity 行\n' > "$B9/01-diagnosis.md"
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

# ------------------------------------------------ T30 die error codes (v3.40.0)
total_die=$(grep -c 'die "' "$GATE_SRC" || true)
coded_die=$(grep -cE 'die "(GATE|NC|ADAPTER)-E[0-9]{2}: ' "$GATE_SRC" || true)
report "T30 every gate die carries an Exx code" 0 "$(( total_die - coded_die ))"
out=$(scripts/agent-gate begin CHG-404 2>&1 || true)
check_output "T30 refusal output carries GATE-E" "GATE-E" "$out"
NEWCHANGE_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -f "$NEWCHANGE_SRC" ]]; then
  report "T30 new-change die count equals coded" 0 "$(( $(grep -c 'die "' "$NEWCHANGE_SRC") - $(grep -cE 'die "NC-E[0-9]{2}: ' "$NEWCHANGE_SRC") ))"
fi
ADAPTER_SRC="$ROOT/resources/templates/install-hook-adapter.sh"
if [[ -f "$ADAPTER_SRC" ]]; then
  report "T30 adapter die count equals coded" 0 "$(( $(grep -c 'die "' "$ADAPTER_SRC") - $(grep -cE 'die "ADAPTER-E[0-9]{2}: ' "$ADAPTER_SRC") ))"
fi

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
  mkdir -p .github
  cp "$ROOT/resources/templates/PULL_REQUEST_TEMPLATE.md" .github/PULL_REQUEST_TEMPLATE.md
  git config core.hooksPath .githooks
  bash scripts/uninstall-standards --dry-run >/dev/null 2>&1
  report "T32 dry-run exits 0" 0 $?
  report "T32 dry-run removes nothing" 0 "$(test -f scripts/agent-gate && test -f .githooks/pre-commit && test -f AGENTS.md; echo $?)"
  bash scripts/uninstall-standards >/dev/null 2>&1
  report "T32 uninstall exits 0" 0 $?
  report "T32 runtime tier removed" 0 "$(test ! -e scripts/agent-gate && test ! -e scripts/uninstall-standards && test ! -d .agent-state; echo $?)"
  report "T32 marked hook removed" 0 "$(test ! -e .githooks/pre-commit; echo $?)"
  report "T32 PR template removed by marker" 0 "$(test ! -e .github/PULL_REQUEST_TEMPLATE.md; echo $?)"
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
else
  echo "SKIP T36: agent-gate absent — 跳过摩擦 metrics golden cases"
fi

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
  seed_artifacts CHG-991 L0 claude/s-1
  scripts/agent-gate begin CHG-991 >/dev/null 2>&1
  t37_fill CHG-991
  echo y > src/t37.js   # stop 只在存在代码路径改动时执法（对齐 T5/T23 夹具）
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L0 minimal-set: declaration satisfies 04.5/05" 0 $?
  # ② L0 + 04.5/05 缺失 → 拒绝（E47 先于 E48）
  rm docs/changes/CHG-991/04.5-coding-record.md docs/changes/CHG-991/05-test-results.md
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L0 minimal-set: missing 04.5/05 still refused" 2 $?
  # ③ L1 + 仅声明行空壳 → GATE-E52（轻量通道越道拦截；盖章注释不计内容行）
  new_repo
  seed_artifacts CHG-992 L1 claude/s-1
  scripts/agent-gate begin CHG-992 >/dev/null 2>&1
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
  printf 'failed cases: %s\n' "${failed_names[*]}" >&2
  exit 1
fi
exit 0
