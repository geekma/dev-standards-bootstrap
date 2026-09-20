# 更新日志（Changelog）

> 本文件是 **dev-standards-bootstrap 项目本身**的版本历史（用户可感知的变更：安装/升级动线、文档、工具脚本）。
> **分工**：规范条款级的升级记录在 [`resources/STANDARDS_CHANGELOG.md`](resources/STANDARDS_CHANGELOG.md)（随 `--core` 下发到目标仓库）；本文件只做项目叙事，不复制其条款细节。
> 格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；语义化版本（`主.次.修订`：次版本号递增 = 携带的规范有新能力/新模板）。

## [Unreleased]

### 新增

- **项目级总册体系（规范 v3.35.0，CHG-035）**：`docs/project/` 12 册（章程/总需求/总架构/接口索引/数据字典/任务计划/测试总册/测试结论/部署/风险遗留/变更总日志/决策总册）+ 逐册评审记录；每次变更强制回填（09「项目总册回填清单」机校）；每册独立完整 + 变更注记可追溯；首次变更 begin 强制初始化。`--core` 扩发 `templates/project/`（13 件）与 `methodologies/project-masters.md`。
- **缺陷环节三条款（规范 v3.35.0，BUG-005）**：诊断前必读总册相关册；修复落点不被既有 TC 覆盖必须新增防回归 TC；缺陷六件套按天入批 `docs/bugs/BATCH-YYYYMMDD/BUG-xxx/`（gate/stamper/audit 双形态兼容，存量独立目录合法保留）。
- **四项打包（规范 v3.34.0）**：gate L0/L1"评审≠实现"机校（FU-042 闭环）；metrics `expert_sessions` 专家会话数观测（L2 ≤3 护栏可见化，只观测不拦截）；session-gate 会话开始注入规则 10 四主体自查表（冲突点名）；能力卡附合规「专家评审记录」golden 样例。golden 310。
- **规则 10 机器执法（规范 v3.33.0）**：agent-gate 强制 `spec_author` 声明（全等级）、L2/L3 四主体互异、「专家评审记录」节强制 §2.1.7 署名（stop/CI）——作者/实现/测试/评审分离从 B 层升 A 层。golden 299→308（含评审收口 +2）。

### 变更

- audit 新增 G9（总册存在/自证/评审配对/回填清单）；源层审计新增 A25，A11 上界重校准 144KB→156KB；golden 310→324，源层断言 282→309。

- **专家两批制（规范 v3.32.0）**：每阶段专家分生产批与评审批，专家不得评审自己参与生产的产物（需求分析者≠需求评审者、方案设计者≠方案评审者）；规则 10 补 spec_author 锚点与 DoD 核对项；第三轮 review 修复（含 v3.29.1 一处"声称已改未落盘"的模板计数补正）。条款细节见 `resources/STANDARDS_CHANGELOG.md` v3.32.0 行。
- **角色单一职责（规范 v3.31.0）**：同一变更内规格/文档作者、实现、测试、评审四主体互异（L0/L1 最低线=评审独立且作者≠评审）；`00-governance.json` 模板增 `spec_author` 字段；§5 "一人多角色"=严重违规。另：专家能力卡补理论出处索引（25 行，含提出者与原著载体）。
- **专家能力卡（规范 v3.30.0）**：`methodologies/expert-capabilities.md`——9 核心 + 3 条件命中专家（数据/LLM/可靠性）的能力定义层（理论工具箱注名经典方法论、广度协同、项目经验装载、方法论自适应绑定）；§2.2 新增增量承诺（零发现零建议=泛评退回）与"项目速览·方法论偏好/专家扩展"自适应。条款细节见 `resources/STANDARDS_CHANGELOG.md` v3.30.0 行。

### 变更

- **对齐与压缩续修（v3.29.1，CHG-029）**：全项目三路评审 22 项必修——计数修正（"12 件产物"实为 15 件，7 处）、§2.2 与 §0.5.2 豁免措辞冲突消解、§3/§5/§2.16.2 补专家评审执行钩子、MAINTAINER §5.1 上界句过时更新、双 README 漂移修复、CHANGELOG 版本链断档补齐；SKILL/MAINTAINER 冗余压缩。零规范性条款变更，门禁/golden 零改动。废止"双 README ≤200 行"目标（v3.22.0 重写后失效，正式登记）。

## [3.29.0] — 2026-09-18

### 新增

- **分阶段专家评审（规范 §2.2）**：九专家（业务/行业/技术/架构/项目管理/安全/性能/测试/整体验收）映射既有角色；需求四步循环、开发漏项检测、测试 NFR 反向核对、交付四方整体验收；上下文贴近契约（无项目证据的模板泛评一律退回）。条款细节见 `resources/STANDARDS_CHANGELOG.md` v3.29.0 行。

## [3.28.0] — 2026-09-17

### 新增

- **会话内执法**：`session-gate.sh` + `install-hook-adapter.sh`——会话开始自动跑一致性审计亮存量红灯，会话空闲跑 stop 等价检查；按客户端自适应接线（claude/opencode/cursor/gemini/codex），生成后强制验证。
- **缺陷六件套执法闭环**：gate 逐组校验六件齐（豁免走 `.gate-allowlist` 登记理由）；`stamp-provenance.sh --bug` 给缺陷组盖章；审计新增 G8/A20/A21 接管。
- **Claude Code 插件分发面**：新增 `.claude-plugin/{plugin,marketplace}.json`（仓库即插件，`claude plugin marketplace add geekma/dev-standards-bootstrap` 即装，根级 SKILL.md 常驻 ~197 tok）。
- **README 接入动线重排（两步式，修复鸡生蛋）**：第 1 步「注册 Skill」四条实测路由任选（`npx skills add` 通用 store / Claude Code 插件 / 对话话术 / `install.sh --as-skill`）；第 2 步「一句话初始化」；新增 CI 徽章与 TL;DR。
- **Skill 本体注册进 AI 客户端（CHG-019）**：`install.sh --as-skill <claude|opencode|all|路径>` 以 symlink 注册进客户端技能目录，checkout 即 Skill 布局，零复制、自更新即时生效、fail-closed；golden T21 新增 4 用例。
- **审计 A24 承诺面入库守护**：README 宣传命令所读取的文件必须 git-tracked，防「文档宣传未提交文件 → raw 404」复发。

### 变更

- **README 安装命令去重（CHG-021）**：一条命令全文 URL 从每份 README 5 处收敛为 1 处唯一权威落点，其余改 flag 变体 + 锚点链接；双语对称。

### 修复

- **双 README golden 断言声称数漂移**：`update-assertion-count.sh` 改运行期实出口径（解析 `N passed`；红套件拒同步），声称数与运行实出长期差 3 的问题修复。MAINTAINER §4 口径同步。

（历史版本见下方归档段）

## [3.27.0] — 2026-09-17

### 新增

- **同日批次默认强制**（CHG-027）：当日 `BATCH-YYYYMMDD` 已存在时，L0/L1 变更 begin 必须入批（独立目录被拒；显式 `AGENT_GUARD_ALLOW_INDEPENDENT=1` 豁免并登记理由）；§5 反模式新增"同日多个 L0/L1 各开独立目录"= 中度违规。下游实测动机：同日 5 组 L0/L1 全部未合批。

## [3.26.0] — 2026-09-17

### 新增

- **溯源全产物强制**（CHG-026）：变更目录全部 `*.md` 交付时必须携带溯源块（`stamp-provenance.sh --all` 必跑，gate stop/CI 逐一校验）；`00-governance.json` 豁免、历史不回填规则不变。动机：下游仓实证每目录 9 件 md 仅 04.5 有块。
- **BUG/CHG 不双建条款**（§2.5 阶段 6）：缺陷默认只落六件套 + bugfix-log；升级变更轨需满足三条件之一，`bug_ref` 指向六件套，诊断正文只引用不复制。§1.1 补句：变更轨 `BUG-xxx`（L0/L1）同适用按天合并。

### 变更

- golden 断言 292 → 294（夹具全量盖章 + unstamped 负例）。

## [3.25.0] — 2026-09-17

### 新增

- **执行侧纪律二批**（CHG-025，条款细节见 [STANDARDS_CHANGELOG](resources/STANDARDS_CHANGELOG.md) v3.25.0 行）：AGENTS.md 执行资源纪律五条→八条（+并行批量写、+定向验证优先、+有状态 mock 隔离，+过滤模板通用形态）；规范 §2.5 新增「产物最小表达形态」、§2.9.6 新增定向验证与 cache_read 量纲注。

### 变更

- **A11 规范体量上界重校准 128KB→132KB**（v3.21.2 先例：先压缩、有 CHANGELOG 条目、KiB 步进；v3.24.0 收口余量仅 3 字节）。源层脚本 `tests/audit-standards-src.sh`，目标仓零影响。

## [3.24.0] — 2026-09-17

### 新增

- **执行侧 token 纪律入规范**（CHG-024，条款细节见 [STANDARDS_CHANGELOG](resources/STANDARDS_CHANGELOG.md) v3.24.0 行）：AGENTS.md 下发面新增「Agent 执行资源纪律」五条（管道过滤 / 一次 grep 合并 / 先定位后小窗 / 勘探下放只读子代理 / 无匹配≠通过）；规范新增 §2.9.6 会话与上下文纪律（单会话单主题、>50 轮或主题切换即 handoff）；§1.1 同日 L0/L1 批次由"可共用"升"默认共用"；§2.5 总则新增跨产物引用制 + 单产物 ≤40 行软上限。

### 修复

- **golden T21 夹具版本耦合**：夹具 sed 钉死 `规范版本：v3.23.0` 字面量，源版本 bump 后必红；改为版本无关形态 `v[0-9.][0-9.]*`（同文件 T14 先例），断言数/语义不变。

## [3.23.0] — 2026-09-16

### 新增

- **审计 `--only-fail`**：`audit-docs-consistency.sh` 支持 `--only-fail`——只打 FAIL 行、skip/VACUOUS SKIP 行与汇总；存量红仓复跑不再全量重放 ok 行。默认行为逐字节不变（规范条款见 STANDARDS_CHANGELOG v3.23.0 ②）。
- **L0/L1 轻量通道**：L0/L1 变更的 02/03/03.5/04 允许单行"未命中，不适用（理由）"显式声明满足存在性；L2/L3 不变，文件名与门禁零改动（③）。

### 变更

- **验收勾选改条目号引用制**：不再要求把验收标准原文逐条抄进清单——条目号 + 勾选 + A 层关键输出一行即可；"只写已验收"仍判未完成（①）。
- **Observation 输出瘦身**：归档过滤后关键输出（≤10 行）+ 完整日志落点，禁止整段原文贴入对话或产物；全规范 9 处"实际输出"措辞同步统一为"关键输出"（④）。
- **09 双节引用制**：追踪矩阵映射一行索引 01.5（禁复制行）；ReAct 表行引用 05 批次（⑤）。

## [3.22.0] — 2026-09-16

### 新增

- **一句话克隆并安装/升级**：新增 `scripts/install.sh`（源层工具）。一条命令完成"克隆本 Skill + 对目标仓全量安装"，目标仓已接入时自动转为升级：
  ```bash
  curl -fsSL https://raw.githubusercontent.com/geekma/dev-standards-bootstrap/main/scripts/install.sh | bash -s -- .
  ```
  支持 `--from <本地路径>`（离线/内网/测试）、`--skill-dir`、`--repo`、`--ref`、`--install`/`--upgrade` 显式模式，以及层与目录根参数透传；冲突与脏树守卫 100% 复用 `bootstrap.sh`（fail-closed，绝不静默覆盖）。
- **溯源全量盖章**：`scripts/stamp-provenance.sh --all <变更号>` 一条命令给活跃变更目录**全部 `*.md` 产物**盖溯源块（作者/邮箱/提交者/提交哈希/主机/平台/UTC 时间，全部从运行环境读出）。`00-governance.json` 刻意不盖（JSON 中注入注释会破坏机器读取）；默认行为（只盖 `04.5-coding-record.md`）逐字节不变。

### 修复

- **源仓溯源自锁**：源层审计 A19 反向断言由"历史变更目录一律不得盖章"修正为"溯源块只允许出现在活跃变更或已闭合变更"——原语义与"交付前必须盖章"的强制要求自相矛盾（盖章即审计红）。仍拦截对无关开放目录的随手盖章。
- **载荷缺文件**：`resources/templates/stamp-provenance.sh` 此前未纳入版本控制，全新 `git clone` 后 `--guard` 层安装会因缺源文件而失败；已入库。

### 文档

- **README 双语重写**：按最佳实践章节化（项目背景 / 功能 / 支持工具 / 快速开始 / 安装与升级 / 自动化说明 / 五道门禁 / 风险分级 / 治理细节 / 仓库结构 / FAQ / 贡献 / 许可证）；**全部截图保留**；叙事改为"命令由 Agent 与 Hook 自动调用，本文是参考手册，手动执行永远可选"。
- **版本说明外置**：原先堆在 Quick Start 里的 v3.15.0~v3.21.0 逐版本段落全部迁出至本文件。
- **FAQ 落裁定**：同一天多个 L0/L1 变更可并入 `BATCH-YYYYMMDD/`（v3.18.0 已实现）；缺陷六件套**刻意不入批**（逐缺陷证据边界，`docs/bugfix-log.md` 索引即天级检索）。

## [3.21.2] — 2026-09-16

独立复核对齐续修（10 条，无行为变更、无回填义务）。要点：规范正文删去派生 Skill 名举例；`SKILL.md` 版本自查条件补全；`agent-governance.yml` 的 `required_before_merge` 与门禁对齐（3→5 件）；`bootstrap.sh` 自定义根安装的假 NOTE 消除；规范体量上界按规程重校准至 128 KiB。登记 FU-030/031/032/033。逐条见 [STANDARDS_CHANGELOG](resources/STANDARDS_CHANGELOG.md)。

## [3.21.1] — 2026-09-16

全项目 review 对齐修正（15 条，无行为变更）。要点：`AGENTS.md` 门禁入口与 `begin` 硬校验对齐（补「开放问题」节）；场景覆盖率门槛补 L3 ≥90%；PR 模板门禁自检补齐 DoD 条目；`check-standards-compliance.sh` 自定义 `change_root` 假红修复；`--docs-dir` 不再静默覆盖用户显式 pin 的 `change_root`/`bugs_root`。

## [3.21.0] — 2026-09-15

**审计覆盖面修复**：通用层审计曾对"产物落在变更目录"的仓库**完全空转**（一条断言都不跑却显示通过，带跳号的仓库也能通过审计）。现在审计单元按正信号识别、空转必须显式打印 `VACUOUS SKIP`、编号连续性只数定义式且基线取文件自身 min（此前本仓 16 个 spec 误报 695 处"缺号"）、G3/G5/G6 刻意只覆盖活文档（冻结历史不可回填，判历史只会产出永远清不掉的红）。

## [3.20.0] — 2026-09-15

**治理记录格式无关**：照随包模板（多行 JSON）生成的 `00-governance.json` 曾被自己的门禁拒绝（`begin` 报 risk_level 缺失、`metrics` 全报 null）。读取器现在先压平再按顶层对象切分——任意合法 JSON 写法等价；"一行一个变更"降级为风格建议。

## [3.19.0] — 2026-09-15

**批次权威名单**：批次内的变更集合改为正向读 `00-governance.json` 的 `change_id`，不再从 `## <标题>` 反推（规范强制的 `## Observation` 结构标题曾让 `--stage staged` 拒掉整批、给 `metrics` 造出幽灵变更）。

## [3.18.0] — 2026-09-15

**变更批次（同日合并）**：同一天的多个 L0/L1 变更可共用 `<docs>/changes/BATCH-YYYYMMDD/` 一个目录——**只有目录放宽，12 件产物文件名一字不改**，同批变更用 `## <变更号>` 小节锚点区分；L2/L3 不得入批（门禁按治理记录逐条拒绝）；闭环判定细到"本变更自己的小节"；溯源块批感知（`change:` 记批次、`batch_changes:` 列成员、风险取批次最高值）。

## [3.17.0] — 2026-09-15

**文件溯源**：新增 `scripts/stamp-provenance.sh`——把作者/邮箱/提交者/提交哈希/主机名/平台/UTC 时间从运行环境读出写进 `04.5-coding-record.md`（禁手写；门禁校验块存在、四字段非空、`generated_by` 必须指向脚本）；`--stage stop` 与 CI 强检；不追溯既往；隐私开关 `provenance.include_email`。

## [3.16.0] — 2026-09-15

**Skill 自维护三改造**：`--check`（三处版本比对、漂移即 exit 1）、`--self-update`（只更新 Skill 自身）、`--derived-report`（派生 Skill 清单）；`--upgrade` 不再覆盖显式层选择（`--core --upgrade` 只升 core）；**Agent 自进化契约**（派生 Skill 声明 `derived_from` 后，安装/升级每条写入路径跳过它，`--force` 也不越过）；`SKILL.md` 瘦身 30%；新增 `MAINTAINER.md`（不随分发）。

## [3.15.0] — 2026-09-15

**路径根可配置**：`--docs-dir`/`--scripts-dir`/`--tests-dir`/`--githooks-dir`（或 `.agent-governance.yml` 的 `paths:`），不配置即逐字节等于默认行为；非默认根会同步写进目标仓配置并改写模板内部路径引用（防"门禁按默认根找、文件在自定义根"的静默错位）；`.github/` 与全部契约名刻意不可配置。

## [3.14.0] — 2026-09-14

**失败模式硬化**：门禁反篡改守卫（`.agent-governance.yml` 在待定变更中时其验证命令不自动执行，防恶意 PR 注入命令）；`--upgrade` 遇目标仓未提交改动拒绝（`--force` 逃生）；CONFLICT/MISSING 退出前打印部分安装计数。

## [3.13.0] — 2026-09-14

**全面升级自更新**：`--upgrade` 起步先自更新 Skill 源（干净树 `pull --ff-only`，实际更新则用新安装器重入），"一次命令全局生效"。

## [3.12.0] — 2026-09-14

**零命令初始化与升级模式**：初始化默认 `--all` 全量自动注入；新增 `bootstrap --upgrade`（治理自有文件升级到携带版本，live/用户文件硬清单跳过——累积记录零丢失）。

## [3.11.0] — 2026-09-14

**初始化自动接线**：`--guard` 自动配置 `core.hooksPath`（三态：未设→设/已对→跳/自定义→不覆盖并提示）、自动生成客户端 Hook 适配器（检测到 Claude Code/Cursor/Gemini 时）、自动探测构建命令预填验证命令。装完即无手工。

## 更早

3.1.0 ~ 3.10.0 的演进（风险分级矩阵、缺陷六件套、八类最低文档集、场景覆盖率、根因分类、检查器设计规约等）见 [STANDARDS_CHANGELOG](resources/STANDARDS_CHANGELOG.md)。

[Unreleased]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.29.0...HEAD
[3.29.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.28.0...v3.29.0
[3.28.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.27.0...v3.28.0
[3.27.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.26.0...v3.27.0
[3.26.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.25.0...v3.26.0
[3.25.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.24.0...v3.25.0
[3.24.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.23.0...v3.24.0
[3.23.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.22.0...v3.23.0
[3.22.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.21.2...v3.22.0
[3.21.2]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.21.1...v3.21.2
[3.21.1]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.21.0...v3.21.1
[3.21.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.20.0...v3.21.0
[3.20.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.19.0...v3.20.0
[3.19.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.18.0...v3.19.0
[3.18.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.17.0...v3.18.0
[3.17.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.16.0...v3.17.0
[3.16.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.15.0...v3.16.0
[3.15.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.14.0...v3.15.0
[3.14.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.13.0...v3.14.0
[3.13.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.12.0...v3.13.0
[3.12.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.11.0...v3.12.0
[3.11.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.10.0...v3.11.0
