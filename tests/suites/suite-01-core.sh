#!/usr/bin/env bash
# suite-01-core.sh — domain suite module (v4.13.0, CHG-158)

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

# TC-1645a~c (CHG-164, REQ-1645): assert G4 bugfix-log structure, reverse-chronological order, and same-class countermeasure
FX3=$(mktemp -d)
_t10_fx3_prep() {
  audit_fixture "$FX3"
  sed -i '' 's/`BUG-001`（索引见 docs\/bugfix-log.md）/`BUG-001`、`BUG-002`（索引见 docs\/bugfix-log.md）/' "$FX3/docs/feata/09-changelog.md" 2>/dev/null \
    || sed -i 's/`BUG-001`（索引见 docs\/bugfix-log.md）/`BUG-001`、`BUG-002`（索引见 docs\/bugfix-log.md）/' "$FX3/docs/feata/09-changelog.md"
}
_t10_fx3_prep
cat > "$FX3/docs/bugfix-log.md" <<'EOF'
# Bug Fix Log
### BUG-002：第二条（严重度 P2）

| 字段 | 内容 |
|---|---|
### BUG-001：第一条（严重度 P1）

| 字段 | 内容 |
|---|---|
| 日期 / 发现来源 | 2026-09-14 / 人工 |
| 关联变更 | CHG-001 |
| 历史相似 | 未命中（x） |
EOF
bash "$AUDIT_SRC" "$FX3" >/dev/null 2>&1
report "T10 TC-1645a audit rejects bugfix-log entry with truncated table (G4)" 1 $?

_t10_fx3_prep
cat > "$FX3/docs/bugfix-log.md" <<'EOF'
# Bug Fix Log
### BUG-001：旧条目排前面（严重度 P1）

| 字段 | 内容 |
|---|---|
| 日期 / 发现来源 | 2026-09-14 / 人工 |
| 关联变更 | CHG-001 |
| 历史相似 | 未命中（x） |

### BUG-002：新条目排后面（严重度 P1）

| 字段 | 内容 |
|---|---|
| 日期 / 发现来源 | 2026-09-20 / 人工 |
| 关联变更 | CHG-001 |
| 历史相似 | 未命中（x） |
EOF
bash "$AUDIT_SRC" "$FX3" >/dev/null 2>&1
report "T10 TC-1645b audit rejects bugfix-log entries not in reverse-chronological order (G4)" 1 $?

_t10_fx3_prep
cat > "$FX3/docs/bugfix-log.md" <<'EOF'
# Bug Fix Log
### BUG-002：同类再犯缺对策（严重度 P1）

| 字段 | 内容 |
|---|---|
| 日期 / 发现来源 | 2026-09-20 / 人工 |
| class | false-green |
| 类级对策 | |
| 关联变更 | CHG-001 |
| 历史相似 | 未命中（x） |

### BUG-001：首例（严重度 P1）

| 字段 | 内容 |
|---|---|
| 日期 / 发现来源 | 2026-09-18 / 人工 |
| class | false-green |
| 类级对策 | 首次出现，不适用 |
| 关联变更 | CHG-001 |
| 历史相似 | 未命中（x） |
EOF
bash "$AUDIT_SRC" "$FX3" >/dev/null 2>&1
report "T10 TC-1645c audit rejects repeat class within 30d without countermeasure (G4)" 1 $?

sed -i '' 's/| 类级对策 | |/| 类级对策 | 首次出现，不适用 |/' "$FX3/docs/bugfix-log.md" 2>/dev/null \
  || sed -i 's/| 类级对策 | |/| 类级对策 | 首次出现，不适用 |/' "$FX3/docs/bugfix-log.md"
bash "$AUDIT_SRC" "$FX3" >/dev/null 2>&1
report "T10 TC-1645c audit rejects repeat class copying default 首次出现 (G4)" 1 $?

sed -i '' 's/| 类级对策 | 首次出现，不适用 |/| 类级对策 | 收紧正则并补负例 |/' "$FX3/docs/bugfix-log.md" 2>/dev/null \
  || sed -i 's/| 类级对策 | 首次出现，不适用 |/| 类级对策 | 收紧正则并补负例 |/' "$FX3/docs/bugfix-log.md"
bash "$AUDIT_SRC" "$FX3" >/dev/null 2>&1
report "T10 TC-1645c audit passes once same-class countermeasure is filled (G4)" 0 $?

rm -rf "$FX" "$FX2" "$FX3" "$SKIPD"

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
grep -q "user: project anchor row" "$BT/AGENTS.md" && grep -q "所有 AI Agent" "$BT/AGENTS.md"
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
grep -q 'templates/entry' "$BT3/.github/workflows/artifact-pipeline.yml" && ! grep -q '## 业务影响' "$BT3/.github/workflows/artifact-pipeline.yml"
report "T11 TC-10028 artifact-pipeline copies templates/entry (no stale 业务影响)" 0 $?
grep -q 'PUSH_BEFORE_SHA' "$BT3/.github/workflows/artifact-pipeline.yml"
report "T11 TC-10029 artifact-pipeline isolates event.before via env" 0 $?
grep -q 'origin/${PR_BASE_REF}:.agent-governance.yml' "$BT2/.github/workflows/agent-governance.yml"
report "T11 TC-10030 agent-governance falls back to base branch .agent-governance.yml" 0 $?

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

