> 交付触发点：发起 PR 时；下游输入：评审、CI 门禁与 P10 变更总日志

## 变更编号
CHG-xxx（关联 `docs/<feature>/09-changelog.md`）

## 风险等级（§0.5）
- [ ] L0 极低  - [ ] L1 低  - [ ] L2 中  - [ ] L3 高
判定依据：

## 门禁自查（DEVELOPMENT_STANDARDS.md §2.16.3，逐项勾选，缺一不可合并）
- [ ] 门禁1：`01-spec.md` 含对应 REQ（来源/评审/DoD），`03-modification-plan.md` 含对应 DES，`03.5-tasks.md` 含对应 TASK（或 CHG 豁免标注，§2.16.3）
- [ ] 门禁2：`04-test-scripts.md` 含对应 TC，覆盖正常/边界/异常（最低下限），十一类覆盖维度逐维设计或显式标注不适用，业务场景清单 SC-xxx 全景枚举、场景覆盖率 ≥80%（L3 ≥90%）；打点断言完整、全量回归计划就绪（§2.5 阶段 4）
- [ ] 门禁3：`05-test-results.md` 有本批次真实控制台输出（非口头声明）、绑定 CHG 与四要素，历史批次未被覆盖
- [ ] 门禁4：`09-changelog.md` §4 必填字段完整且 `docs/<feature>/01.5-rtvm-matrix.md` 已回填、`03-modification-plan.md` 正文已回写、编号连续不重排、**项目总册回填清单逐册勾选（P00–P12，§1.3）**（§2.16.3）
- [ ] 门禁5：测试与 Review 由与开发不同的执行主体完成（角色签署表已附），L3 变更已获 Release Owner 授权
- [ ] UX 条件门（命中 `01-spec` `ui_change: true` 时）：项目上下文包 10 域与 UJ 已填、`03.6-ui-spec.md` 已产出（含来源物映射，E123/G15）、`03.5-tasks.md` 含 `UX`/`UI` 任务行、`04-test-scripts.md` 含真人入口 E2E、`07-review-report.md` 用户可用性验收已签署（E90/E92–E98）且「业务合理性终审」已签署（E124）
- [ ] 全部变更：`03-modification-plan.md` 含「既有范式关系」节或未命中声明（E122，begin 机校）
- [ ] ReAct 记录：`09-changelog.md` 含「执行记录（ReAct）」（每个已执行阶段 Observation 附命令与实际输出，§2.16.2）

## 独立性证据（命中 L2/L3 时必填）
| 环节 | 执行主体/Agent 标识 | 结论 |
|---|---|---|
| 测试验证 | | |
| 代码审查 | | |

## 未动项
（本次有意未改动的关联内容及理由）
