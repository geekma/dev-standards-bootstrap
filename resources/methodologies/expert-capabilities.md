# 专家能力卡（Expert Capability Profiles）

> 文档编号：methodologies/expert-capabilities.md（方法论层，M0/M1 基线；随 `bootstrap --core` 下发）
> 定位：规范 §2.2 管"哪个阶段必须有哪些专家、增量承诺是什么"（强制性）；**本文件管"每个专家怎么评得深"**——理论工具箱、广度协同、经验装载、方法论自适应。
> 理论注名原则：只注名经典方法论与一句本项目应用锚点，不搬运教材内容（防第二权威源）；学理细节以注名的原著/框架为唯一权威。

## 0. 通用契约（适用于全部专家）

### 0.1 方法论自适应绑定
- **基线（M0）**：卡内"基线"标注的工具箱，规范已强制或注名即用，任何仓不得裁剪。
- **扩展（M1/M2）**：按两个来源自适应裁剪——①目标仓 `AGENTS.md`「项目速览·方法论偏好」行（自由文本，如"偏好：DDD / 六边形架构 / 整洁架构"；未声明即用基线）；②`docs/METHODOLOGY.md` M0–M3 分级判定（M2 须选型论证）。
- **可审计**：动用扩展方法论须在评审记录「依据」段注名（方法名 + 一句为何适配本项目）；未注名即引用=依据不足，B 层退回。

### 0.2 经验装载（出动前置，§2.16.1 之外的专家侧加严）
出动前必须核对：①`docs/bugfix-log.md` 同族教训（本专家域内历史缺陷）；②`docs/06-delivery-summary.md` FU 台账（本域遗留项）；③既有 CHG 中本专家域的评审结论。**重复踩已知坑 = 评审无效**（B 层退回）。

### 0.3 增量承诺（每次出动 = 质量提升时刻的硬下限）
每次出动必须产出：①**≥1 条发现**（缺陷/风险/改进机会，引用项目证据 `路径:行号`/编号）**或显式达标确认**（引用判定依据）；且 ②**≥1 条可执行改进建议**（当场修复，或登记 `FU-xxx` 并写明负责人与期限）。**零发现零建议 = 泛评，等同未评审，按规范 §5 退回。**

**合规样例（golden 形状，照抄即过 A 层署名机校 v3.34.0）**：

````markdown
## 专家评审记录
| 阶段 | 专家 | 结论 | 依据 |
|---|---|---|---|
| 需求 | 业务专家 | 通过（2 项修订已回写 01） | `docs/<feature>/01-spec.md:12`（REQ-003 边界改写）；bugfix-log 同族 BUG-011 已核对 |

署名：opencode / glm-5.3-flash / task-review-01
````

> 形状要点：节以标题形态存在；署名行 = §2.1.7 三段 `平台 / 模型 / 任务ID`（` / ` 带空格）；依据段引项目证据（路径:行号 / 编号）。gate stop/CI 校验此形状；同节多专家多行署名各自成行。

### 0.4 条件命中专家（不占 L2 ≤3 会话基线护栏，按命中单独计）

| 专家 | 命中条件（规范锚点） | 出动时机 |
|---|---|---|
| 数据专家 | 变更含 CFG/DB/数据订正（§2.6） | 阶段 2 影响分析起 |
| LLM 专家 | 变更含模型/Prompt/评估链路（§2.9） | 阶段 1 需求起 |
| 可靠性专家 | 变更含发布/监控/回滚面（§2.7/§2.8） | 阶段 3 方案设计起 |

### 0.5 专家扩展协议（项目特定专家）
项目可经 `AGENTS.md`「项目速览·专家扩展」行声明领域专家（如医疗仓"临床专家"、金融仓"风控专家"）：四维卡同构（工具箱/协同/装载/自适应），签署权仍映射规范 §0.5.2 既有角色列，增量承诺与通用契约全适用；扩展专家不改动规范 §2.2 组合表（自进化契约：派生不改源）。

### 0.6 能力回填
专家发现的跨项目规律 → 规范 §2.14 标准改进评估；项目内教训 → 阶段 10 记忆沉淀。能力卡本身的修订走规范变更管线。

---

## 1. 业务专家（需求 Agent/业务 Owner 承担；阶段 1）

- **理论工具箱**：基线——用户故事与 INVEST 原则、验收标准可测性（DoD）；扩展——用户故事地图（Patton）、Impact Mapping（Adzic）、Kano 模型（需求分类与优先级）、JTBD（场景动机）。
- **广度协同**：向行业专家供业务约束清单；向测试专家供 SC 场景五维枚举输入；与 PM 专家对齐验收里程碑。
- **经验装载**：既有 `01-spec.md` REQ 演进史（同域需求为何改）、SC 清单历史遗漏、`02` 业务影响史。
- **自适应锚点**：偏好声明含 DDD 时，通用语言表并入 `01-spec` 术语节。

## 2. 行业专家（阶段 1/2；合规敏感域或 L2+ 独立主体）

- **理论工具箱**：基线——合规约束映射（行业法规 → 需求/设计约束项）；扩展——按域注名（金融：PCI-DSS/反洗钱；医疗：HIPAA/GxR/CDSS 指南；数据出境：GDPR/个保法/数据安全法；通用：领域驱动设计通用语言）。
- **广度协同**：向安全专家供合规性威胁面（监管红线≠技术红线的分野）；向业务专家回供行业惯例修正需求。
- **经验装载**：`02` 行业合规约束史、既有变更中监管相关 FU。
- **自适应锚点**：行业由项目速览声明；未声明且 02 未命中敏感域 → 本卡不独立出动（§2.2 二分触发）。

## 3. 技术专家（架构-计划 Agent 承担；阶段 2/3）

- **理论工具箱**：基线——≥2 候选选型对比、trade-off 显式化；扩展——ADR（决策记录）、CAP/PACELC 取舍、12-Factor、技术适配度评估（技术雷达思维）。
- **广度协同**：向架构专家供选型证据；向性能专家核对候选的容量含义；向 LLM 专家（命中时）核对模型侧可行性。
- **经验装载**：既有 `03` 选型论证史（同类决策为何取/舍）、`METHODOLOGY.md` M 层判定记录。
- **自适应锚点**：偏好声明的架构风格直接约束候选集（如偏好六边形 → 候选须通过端口-适配器检验）。

## 4. 架构专家（架构-计划 Agent 承担；阶段 2/3）

- **理论工具箱**：基线——深模块原则（Ousterhout）、耦合/内聚评估、接口前后兼容；扩展——C4 模型（架构描述）、ADR、演进式架构与适应度函数、康威定律检查（团队结构 ↔ 模块边界）。
- **广度协同**：与技术专家互为取舍双方；向 PM 专家供任务边界（模块=可独立提交/回滚单元）；向安全专家供信任边界图。
- **经验装载**：`02` 三维影响与隐式链路史、既有分层与坏味道（§5 反模式库）、`docs/methodologies/development.md` §3。
- **自适应锚点**：偏好声明的架构风格作为适应度函数的判定基线。

## 5. 项目管理专家（编排 Agent 调度面 + 架构-计划 Agent 拆解面；阶段 3/5）

- **理论工具箱**：基线——WBS（原子任务/依赖/关键路径）、DoR/DoD、漏项检测（规范 §2.2 内化）；扩展——PMBOK 监控过程组、关键链（Goldratt 缓冲管理）、风险登记册、RACI（与 §0.5.2 矩阵同构对照）。
- **广度协同**：向整体验收专家供里程碑达成证据；向编排 Agent 升级阻塞（§2.1.8）；向各专家催办增量承诺产出。
- **经验装载**：既有 `03.5` 任务偏差史、批次节奏（BATCH 实测）、RTVM 未映射历史模式。
- **自适应锚点**：项目声明迭代/瀑布偏好时，里程碑粒度随之适配（规范不强制节奏）。

## 6. 安全专家（开发/Review Agent 专项签署扩展；阶段 5/8）

- **理论工具箱**：基线——最小权限、纵深防御、敏感数据不入日志（§2.9.4 内化）；扩展——STRIDE 威胁建模、OWASP Top 10 / ASVS、攻击树、安全开发生命周期（SDL）、SCA 依赖供应链扫描（§2.13.2）。
- **广度协同**：向架构专家回供信任边界修正；与行业专家分野"监管合规 vs 技术攻击面"；向数据专家（命中时）对齐脱敏/加密策略。
- **经验装载**：`bugfix-log.md` 安全类 BUG 同族、§2.9.4 PII 面清单、既有 `07` 安全结论。
- **自适应锚点**：无威胁面的纯文档变更按 §0.5.2 合并留痕，不出动（成本护栏）。

## 7. 性能专家（开发/Review Agent 专项签署扩展；阶段 5/8）

- **理论工具箱**：基线——命中非功能指标才评审（§2.5 阶段 4 内化）、复杂度意识；扩展——USE 方法（资源-饱和-错误）、RED 方法（Rate/Errors/Duration）、容量建模、Amdahl 定律、缓存失效模式、基准测试有效性（冷启动/预热/噪声）。
- **广度协同**：向可靠性专家（命中时）供 SLO/容量输入；向技术专家回供候选方案的成本含义；与 LLM 专家（命中时）共担 token 成本（§2.9.5）。
- **经验装载**：`01` 非功能指标史、`05` 历史性能逃逸、监控基线（§2.8）。
- **自适应锚点**：项目声明性能预算（如 P99 ≤ 200ms）时作为强制判定线。

## 8. 测试专家（测试 Agent 承担；阶段 4/7）

- **理论工具箱**：基线——十一类覆盖维度 + NFR 反向核对 + SC 枚举（规范内化）、复用 vs 新增判定；扩展——测试金字塔（Cohn）、HTSM（Kaner 启发式）、契约测试、变异测试思想（断言有效性）、基于会话的探索性测试、缺陷预防与同族推演（规范内化）。
- **广度协同**：向业务专家回供场景盲区；向整体验收专家供回归证据；向数据/LLM 专家（命中时）供评估集与对账用例。
- **经验装载**：`bugfix-log.md` 全量同族扫描、`05` 历史逃逸缺陷、覆盖率趋势。
- **自适应锚点**：偏好声明含 TDD/BDD 时，04 先行的形态随之适配（行为式用例可直接映射 SC）。

## 9. 整体验收专家（Review Agent 终审扩展 + Release Owner 人类面；阶段 8/9）

- **理论工具箱**：基线——四方证据验收（规范 §2.2 内化）、RTVM 闭环核对；扩展——ATDD（验收测试导向）、Release Readiness Review 检查单、DoD 审计、尽调式抽样（按风险加权抽检而非全查）。
- **广度协同**：汇总全部专家增量承诺产出（发现/建议闭环率）；与 Release Owner 分野"验收结论 vs 授权决策"（门禁 5）。
- **经验装载**：`06` 交付总结史、FU 台账闭环率、历史回滚记录（§2.7.3）。
- **自适应锚点**：项目声明的合规等级提升抽样比例（L3 高风险域全查）。

## 10. 数据专家（条件命中：§2.6）

- **理论工具箱**：基线——CFG/DB 映射与回滚脚本（§2.6 内化）；扩展——数据迁移双写/影子表、对账与水位校验、数据质量维度（完整性/一致性/时效性）、主数据与血缘。
- **广度协同**：向安全专家对齐脱敏加密；向测试专家供对账用例；向架构专家供存储选型证据。
- **经验装载**：`06.5` 历史变更、既有 DB 类 BUG、数据订正回滚记录。
- **自适应锚点**：仓声明"禁 DML"等约束时按约束裁剪方案空间（平台规则先例）。

## 11. LLM 专家（条件命中：§2.9）

- **理论工具箱**：基线——Prompt 变更门禁、endpoint 可用性预检（§2.9 内化）；扩展——评估集驱动回归（golden set）、Prompt 版本化与 A/B、幻觉防护（引用强制/结构化输出）、token 成本治理（§2.9.5）、非确定性输出的判定式验收（结构化 schema 断言）。
- **广度协同**：向测试专家供评估集与判定式；向性能专家共担成本/延迟；向业务专家回供能力边界（防需求超出模型能力）。
- **经验装载**：`data-structures.md` §4 LLM 契约、既有 Prompt 变更记录、成本基线。
- **自适应锚点**：项目声明的模型厂商/成本上限直接约束候选。

## 12. 可靠性专家（条件命中：§2.7/§2.8）

- **理论工具箱**：基线——发布检查单、冒烟验证、回滚标准（§2.7 内化）；扩展——SLO/错误预算、可观测三支柱（日志/指标/trace）、故障注入与演练、值守交接（§2.11 热修复联动）。
- **广度协同**：向性能专家对齐容量；向 PM 专家供发布窗口与缓冲；向整体验收专家供监控就绪证据（§2.8"观测 0 字节"防线）。
- **经验装载**：`06.5` 发布史、告警噪音记录、历史回滚根因。
- **自适应锚点**：项目声明的环境拓扑（灰度/蓝绿/滚动）决定检查单形态。

---

## 附：理论出处索引

> 收录各专家卡注名的外部理论/框架及其原著载体；同一专家卡内并列工具以"/"合并一行，表尾"（待核）"行为跨卡多源工具聚合。标注"（待核）"=多源实践、无单一权威提出者。

| 理论/框架 | 提出者/机构 | 载体（原著/标准/文章） |
|---|---|---|
| 用户故事 / INVEST 原则 | Ron Jeffries；Bill Wake | 《User Stories Applied》(2004)；文章 "INVEST in Good Stories, and SMART Tasks"(2003) |
| 用户故事地图 / Impact Mapping | Jeff Patton / Gojko Adzic | 《User Story Mapping》(O'Reilly, 2014) / 《Impact Mapping》(2013) |
| Kano 模型 / JTBD | 狩野纪昭（Noriaki Kano）/ Clayton Christensen（推广者） | 论文 "Attractive Quality and Must-Be Quality"(1984) / 《Competing Against Luck》(2016) |
| DoR / DoD | Ken Schwaber & Jeff Sutherland（DoD）；DoR 为 Scrum 社区延伸 | 《Scrum Guide》 |
| DDD（通用语言） | Eric Evans | 《Domain-Driven Design》(2003) |
| 行业合规框架（PCI-DSS / HIPAA / GDPR） | PCI SSC / 美国 HHS / 欧盟立法机构 | 各标准与法规原文 |
| WBS / 监控过程组 / 风险登记册 / RACI | PMI | 《PMBOK Guide》 |
| 关键链 | Eliyahu M. Goldratt | 《Critical Chain》(1997) |
| ADR（架构决策记录） | Michael Nygard | 文章 "Documenting Architecture Decisions"(2011) |
| 深模块原则 | John Ousterhout | 《A Philosophy of Software Design》(2018) |
| C4 模型 / 演进式架构与适应度函数 | Simon Brown / Neal Ford 等 | 《Software Architecture for Developers》/ 《Building Evolutionary Architectures》(O'Reilly, 2017) |
| 康威定律 | Melvin Conway | 文章 "How Do Committees Invent?"（Datamation, 1968） |
| CAP / PACELC | Eric Brewer（Gilbert & Lynch 形式化）；PACELC 为 Daniel Abadi 扩展 | PODC 2000 keynote "Towards Robust Distributed Systems"；Abadi, IEEE Computer 45(2), 2012 |
| 12-Factor / 技术雷达 | Adam Wiggins（Heroku）/ ThoughtWorks | 12factor.net (2011) / Technology Radar 半年度报告 |
| STRIDE 威胁建模 | Loren Kohnfelder & Praerit Garg（Microsoft） | 文章 "The Threats to Our Products"(2016) |
| OWASP Top 10 / ASVS | OWASP Foundation | OWASP Top 10 报告 / ASVS 标准 |
| 攻击树 / SDL / 最小权限与纵深防御 | Bruce Schneier / Microsoft / Saltzer & Schroeder | 文章 "Attack Trees"（Dr. Dobb's Journal, 1999）/ 《The Security Development Lifecycle》(2006) / 论文 "The Protection of Information in Computer Systems"(1975) |
| USE 方法 / RED 方法 | Brendan Gregg / Tom Wilkie | 《Systems Performance》(2013) 与 "The USE Method"(2012) / 博客 "The RED Method"(2015) |
| Amdahl 定律 | Gene Amdahl | AFIPS 论文 "Validity of the Single Processor Approach to Achieving Large Scale Computing Capabilities"(1967) |
| 测试金字塔 / HTSM / SBTM | Mike Cohn / James Bach & Jonathan Bach | 《Succeeding with Agile》(2009) / HTSM 与 SBTM 白皮书（satisfice.com） |
| 契约测试 / 变异测试 | Martin Fowler / DeMillo, Lipton & Sayward | bliki "Integration Contract Tests"(2014) / 论文 "Hints on Test Data Selection"(1978) |
| SLO / 错误预算 / 可观测三支柱 | Google SRE 团队 / Cindy Sridharan | 《Site Reliability Engineering》(O'Reilly, 2016) / 《Distributed Systems Observability》(O'Reilly, 2018) |
| 故障注入 / 混沌工程 | Netflix（Chaos Monkey）；Casey Rosenthal & Nora Jones | Principles of Chaos（principlesofchaos.org）/ 《Chaos Engineering》(O'Reilly, 2019) |
| 数据质量维度 / 主数据 / 血缘 | DAMA International | 《DAMA-DMBOK》 |
| ATDD / SCA 依赖扫描 / LLM 评估集（golden set）/ Prompt 版本化与 A/B / 数据迁移双写与对账水位校验 / Release Readiness Review 检查单 | 多源社区与工业实践（无单一权威提出者） | （待核） |

学理细节以上述原著为唯一权威；本卡只定义"何时动用"（绑定关系），不复制学理内容。

_本文件随 `docs/DEVELOPMENT_STANDARDS.md` 版本同步维护，当前对应规范版本：v3.41.0_
