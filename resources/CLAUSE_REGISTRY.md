# 条款注册表（CLAUSE_REGISTRY，v3.46.0，REQ-968）

<!-- 权威关系声明（防双权威源漂移）：本文件是条款的**机器索引层**，只登记"有哪些条款、
     在权威文件的哪个锚点、适用什么变更类型"；DEVELOPMENT_STANDARDS.md 仍是条款正文的
     **唯一叙事权威**。阅读包（generate-reading-pack.sh 按需生成，产物不入库）从本表筛选
     条款并逐条解析锚点存在性——锚点失配即 fail-closed 报错，生成永不产出与权威漂移的
     副本。禁止在本文件内复述条款正文；禁止预生成阅读包入库。 -->

## Schema

- 列定义：`| Rxx | 条款标题 | 权威落点(path::唯一锚点串) | 类型标签 | 强制级别 | 生命周期类别 |`
- 行 ID：`Rxx` 十进制连续无跳号（无连字符形态，不进入 REQ/DES/TC/SC/BUG/CHG/FU 编号面，A6c/G2 不误扫）。
- 权威落点：`path::anchor`——path 为仓根相对路径（须为随治理包分发的文件），anchor 为该文件中
  **唯一存在**的字符串（写行前必须 grep 验真 =1）；生成器按 `grep -F` 定位并解析行号，失配即 fail-closed。
- 类型标签（封闭词表）：`L0-bugfix` `L1-standards` `L2-architecture` `L3-critical` `universal`（universal=所有类型必读）。
- 强制级别：`硬`=违反即退回；`软`=黄灯登记可申诉。
- 生命周期类别（MAINTAINER §5.3 四类）：`结构` `措辞` `行为` `计数`。
- 维护规则：变更新加/改标题条款时**必须同步**本表加行/改锚点（新锚点先 grep 验真），
  并跑 `generate-reading-pack.sh --verify` 绿态后方可交付；删除条款同步删行。

## 注册表

| Rxx | 条款标题 | 权威落点 | 类型标签 | 强制级别 | 生命周期 |
| --- | --- | --- | --- | --- | --- |
| R01 | 缺陷处置主线（阶段 6） | DEVELOPMENT_STANDARDS.md::### 阶段 6：缺陷诊断与根因推导（Bug 专用） | L0-bugfix | 硬 | 结构 |
| R02 | 缺陷双登记（log 索引 + CHG 条目） | DEVELOPMENT_STANDARDS.md::**Bug 修复必须双登记** | L0-bugfix | 硬 | 行为 |
| R03 | 缺陷六件套必含清单 | DEVELOPMENT_STANDARDS.md::复现步骤、完整调用链 | L0-bugfix | 硬 | 结构 |
| R04 | 根因表与同族推演 | DEVELOPMENT_STANDARDS.md::**根因·同族推演（v3.4.0）** | L0-bugfix | 硬 | 结构 |
| R05 | Bug 修复记录七要素 | DEVELOPMENT_STANDARDS.md::Bug 修复记录七要素 | L0-bugfix | 硬 | 结构 |
| R06 | 缺陷发现入口（bug-autointent/交互三选项） | DEVELOPMENT_STANDARDS.md::#### 2.17.2b 缺陷发现入口扩展 | L0-bugfix | 硬 | 结构 |
| R07 | 诊断前必读总册 | DEVELOPMENT_STANDARDS.md::诊断前必读总册 | L0-bugfix | 硬 | 行为 |
| R08 | TC 覆盖强制（修复必被 TC 覆盖） | DEVELOPMENT_STANDARDS.md::TC 覆盖强制 | L0-bugfix | 硬 | 行为 |
| R09 | Bug 修复回填清单 | DEVELOPMENT_STANDARDS.md::#### Bug 修复回填清单 | L0-bugfix | 硬 | 结构 |
| R10 | 缺陷修复类 CHG 专项评审核对 | DEVELOPMENT_STANDARDS.md::缺陷修复类 CHG 专项 | L0-bugfix | 硬 | 结构 |
| R11 | 已闭合变更禁止改写（勘误新开组） | DEVELOPMENT_STANDARDS.md::已闭合 CHG 禁止改写 | universal | 硬 | 结构 |
| R12 | 防覆盖与变更逻辑（§2.15） | DEVELOPMENT_STANDARDS.md::## 2.15 文档更新与变更逻辑 | universal | 硬 | 结构 |
| R13 | 变更完成判定（DoD，§2.16.3） | DEVELOPMENT_STANDARDS.md::### 2.16.3 变更完成判定 | universal | 硬 | 结构 |
| R14 | AI 防漏自检（§2.16.4） | DEVELOPMENT_STANDARDS.md::### 2.16.4 AI 防漏自检 | universal | 硬 | 结构 |
| R15 | 防跳过红线（§2.16.6） | DEVELOPMENT_STANDARDS.md::### 2.16.6 防遗漏 | universal | 硬 | 结构 |
| R16 | 歧义分级裁定（§2.1 规则 8） | DEVELOPMENT_STANDARDS.md::歧义分级裁定 | universal | 硬 | 行为 |
| R17 | 四主体自查表（§2.1 规则 10） | DEVELOPMENT_STANDARDS.md::四主体自查表 | universal | 硬 | 行为 |
| R18 | 评审/测试子代理输入契约（§2.2） | DEVELOPMENT_STANDARDS.md::输入契约 | universal | 硬 | 行为 |
| R19 | 会话与上下文纪律（§2.9.6 水位/换挡/事件型触发） | DEVELOPMENT_STANDARDS.md::### 2.9.6 会话与上下文纪律 | universal | 半硬（check/水位/GATE-E89 begin 硬校+豁免；活性自检软） | 行为 |
| R20 | 遗留项闭环管理（FU，§2.12） | DEVELOPMENT_STANDARDS.md::## 2.12 遗留项闭环管理 | universal | 硬 | 结构 |
| R21 | 项目总册回填清单（§1.3） | DEVELOPMENT_STANDARDS.md::#### 项目总册回填清单 | L1-standards | 硬 | 结构 |
| R22 | 执行前置（§2.16.1） | DEVELOPMENT_STANDARDS.md::### 2.16.1 执行前置 | L1-standards | 硬 | 结构 |
| R23 | 执行主线（§2.16.2） | DEVELOPMENT_STANDARDS.md::### 2.16.2 执行主线 | L1-standards | 硬 | 结构 |
| R24 | 配置/DB 变更规范（§2.6） | DEVELOPMENT_STANDARDS.md::## 2.6 部署、配置与数据库变更规范 | L2-architecture | 硬 | 结构 |
| R25 | 热修复快速通道（§2.11） | DEVELOPMENT_STANDARDS.md::## 2.11 热修复快速通道 | L3-critical | 硬 | 结构 |
| R26 | AGENTS 路由入口（锚点表速览） | resources/AGENTS.md::交付前文档互证 | universal | 硬 | 结构 |
| R27 | 缺陷入口速查（AGENTS 门禁 4） | resources/AGENTS.md::bug-autointent | L0-bugfix | 硬 | 结构 |
| R28 | bugfix 场景路由（"只是改 bug"行） | resources/AGENTS.md::只是改 bug | L0-bugfix | 硬 | 结构 |
| R29 | 统一编号规范（§1.1） | DEVELOPMENT_STANDARDS.md::### 1.1 统一编号规范 | L1-standards | 硬 | 结构 |
| R30 | RTVM 矩阵文件与编号顺序（§1.2） | DEVELOPMENT_STANDARDS.md::### 1.2 独立 RTVM 矩阵文件与编号顺序规范 | L1-standards | 硬 | 结构 |
| R31 | 分阶段产物与规格（§2.5） | DEVELOPMENT_STANDARDS.md::## 2.5 分阶段产物与规格 | L1-standards | 硬 | 结构 |
| R32 | 标准升级与存量回填（§2.14） | DEVELOPMENT_STANDARDS.md::## 2.14 标准升级与存量文档回填 | L1-standards | 硬 | 结构 |
| R33 | 产物落点总表（§2.16.5） | DEVELOPMENT_STANDARDS.md::### 2.16.5 变更执行产物落点总表 | L1-standards | 硬 | 结构 |
| R34 | Changelog 格式规范（§4） | DEVELOPMENT_STANDARDS.md::## 4. Changelog 格式规范 | L1-standards | 硬 | 结构 |
| R35 | 发布与上线流程（§2.7） | DEVELOPMENT_STANDARDS.md::## 2.7 发布与上线流程规范 | L2-architecture | 硬 | 结构 |
| R36 | 监控告警门禁（§2.8） | DEVELOPMENT_STANDARDS.md::## 2.8 监控、告警与可观测门禁 | L2-architecture | 硬 | 结构 |
| R37 | AI/LLM 专项规范（§2.9） | DEVELOPMENT_STANDARDS.md::## 2.9 AI/LLM 专项规范 | L2-architecture | 硬 | 结构 |
| R38 | 测试数据与环境隔离（§2.10） | DEVELOPMENT_STANDARDS.md::## 2.10 测试数据与环境隔离 | L2-architecture | 硬 | 结构 |
| R39 | 协作/供应链/接口生命周期（§2.13） | DEVELOPMENT_STANDARDS.md::## 2.13 协作、依赖供应链与接口生命周期 | L2-architecture | 硬 | 结构 |
| R40 | 回滚标准与决策（§2.7.3） | DEVELOPMENT_STANDARDS.md::### 2.7.3 回滚标准与决策 | L3-critical | 硬 | 结构 |
| R41 | 风险等级判定表（§0.5.1） | DEVELOPMENT_STANDARDS.md::### 0.5.1 风险等级判定表 | L3-critical | 硬 | 结构 |
| R42 | 版本载体全链清单（§2.14） | DEVELOPMENT_STANDARDS.md::版本载体全链清单 | universal | 硬 | 结构 |
| R43 | 沟通先行门（§2.17.2d） | DEVELOPMENT_STANDARDS.md::#### 2.17.2d 沟通先行门 | universal | 硬 | 结构 |
| R44 | 项目上下文包 10 域（§2.5 阶段 1 条 7） | DEVELOPMENT_STANDARDS.md::**项目上下文包（v3.67.0，强制先于 REQ）** | universal | 硬 | 结构 |
| R45 | 用户任务 UJ 与 ui_change 声明（§2.5 阶段 1 条 8） | DEVELOPMENT_STANDARDS.md::**用户任务（`UJ-xxx`，v3.67.0）** | universal | 硬 | 结构 |
| R46 | 禁裸主键作用户入口（§2.5 阶段 3 条 9） | DEVELOPMENT_STANDARDS.md::禁止 DB 主键 | L2-architecture | 硬 | 行为 |
| R47 | 用户旅程 E2E 阈值（§2.5 阶段 4） | DEVELOPMENT_STANDARDS.md::**用户旅程 E2E（v3.67.0）** | L2-architecture | 硬 | 行为 |
| R48 | 产品可用性专家 UAT 与五方证据（§2.5 阶段 8） | DEVELOPMENT_STANDARDS.md::**「用户可用性验收」节（v3.67.0）** | L2-architecture | 硬 | 结构 |
| R49 | 业务度量埋点强制（§2.8） | DEVELOPMENT_STANDARDS.md::**业务度量埋点强制（v3.67.0）** | L2-architecture | 硬 | 行为 |
| R50 | 用户体验 DoD（§2.16.3） | DEVELOPMENT_STANDARDS.md::**用户体验（v3.67.0，命中 | universal | 硬 | 结构 |
| R51 | 原始锚点与机械抽取（§2.5 阶段 1） | DEVELOPMENT_STANDARDS.md::**原始锚点与机械抽取（v3.68.0，CHG-043）** | universal | 硬 | 结构 |
| R52 | 事件流切分与数据流规格（§2.5 阶段 2） | DEVELOPMENT_STANDARDS.md::**事件流切分与数据流规格（v3.68.0，CHG-043）** | universal | 硬 | 结构 |
| R53 | 否定测试抽查（§2.5 阶段 4） | DEVELOPMENT_STANDARDS.md::**否定测试抽查（v3.68.0，CHG-043）** | universal | 硬 | 行为 |
| R54 | 运行时证据硬门（§2.5 阶段 7） | DEVELOPMENT_STANDARDS.md::**运行时证据硬门（v3.68.0，CHG-043）** | universal | 硬 | 行为 |
| R55 | 评审跑旅程与上游错误计数（§2.5 阶段 8） | DEVELOPMENT_STANDARDS.md::**评审跑旅程与上游错误计数（v3.68.0，CHG-043）** | universal | 硬 | 行为 |
| R56 | 发现处置闭环与来源维（§2.5 阶段 8） | DEVELOPMENT_STANDARDS.md::**发现处置（v3.74.0；逐条处置，严重或安全发现未处置即拒 E114/E115，无发现可单行声明；v3.75.0 增「来源」列——本次引入/既有存量，E117）** | universal | 硬 | 行为 |
| R57 | 评审轮次收敛与超限处置（§2.1.8） | DEVELOPMENT_STANDARDS.md::**评审收敛（v3.74.0）** | universal | 硬 | 行为 |
| R58 | 评审质效度量的七项字段（§2.17.5；缺「来源」列时后两项输出 `null`，不臆造 0） | templates/agent-gate.sh::metrics prints one JSON object per change | universal | 软 | 计数 |
| R59 | 事故/回归复盘「应捕获层」与补强（§2.17.2） | DEVELOPMENT_STANDARDS.md::**复盘义务（v3.75.0，CHG-099，REQ-1112）** | universal | 硬 | 行为 |
| R60 | 评测资产派生与重打分（§2.17.4） | DEVELOPMENT_STANDARDS.md::**评测资产与重打分（v3.75.0，CHG-099，REQ-1108~1110）** | universal | 软 | 行为 |
| R61 | 按仓评审要点承载面（AGENTS 区块） | resources/AGENTS.md::本仓评审要点（v3.75.0，CHG-099，REQ-1113，按仓定制承载面） | universal | 软 | 措辞 |
| R62 | 验证通道方言与四态（含在途 yml 合法维护路径） | resources/templates/agent-governance.yml::方言与四态（v3.76.0，CHG-100，REQ-1115~1120） | universal | 硬（unparsable 即 GATE-E118） | 行为 |
| R63 | 工具调用批处理与尾部增量读（§2.9.6；细则唯一权威=resources/AGENTS.md 纪律 12/13） | DEVELOPMENT_STANDARDS.md::**调用批处理与增量读（v3.77.0，CHG-101，REQ-1124/1125）** | universal | 软（session-gate edits 黄灯，`AGENT_GUARD_EDIT_LIMIT`） | 行为 |

## GATE-E 码映射索引（v3.62.0，REQ-1021）

- 来源唯一权威：`resources/templates/agent-gate.sh` 的 `die "GATE-Exx:` 字符串（dev 份 `scripts/agent-gate` 与模板份单源同文）；语义逐码从 die 字符串提炼，不臆造。
- 每码一行：码 / 一句话语义 / 落点（模板份函数或节名——**不写行号**，行号漂移，计数断言才稳）。
- 计数互锁：本节 GATE-E 行数 == 模板 `die "GATE-E[0-9]+` 去重计数，由源层审计断言执法（`tests/audit-standards-src.sh`「CLAUSE_REGISTRY GATE-E rows == template die codes」）；agent-gate 新增 E 码必须同步加行，废止 E 码必须同步删行。本节只做索引，不复述门禁正文。

| 码 | 语义 | 落点 |
| --- | --- | --- |
| GATE-E01 | 未在 Git 仓库内运行 | agent-gate.sh::顶层（repo_root 解析） |
| GATE-E02 | 变更 id 形状非法（[A-Za-z0-9] 开头，仅字母数字/_/-，禁点号） | agent-gate.sh::required_docs_present() |
| GATE-E03 | begin 必备入口产物缺失 | agent-gate.sh::required_docs_present() |
| GATE-E04 | 00-intent 缺「预期结果」节 | agent-gate.sh::validate_artifact_content() |
| GATE-E05 | 00-intent 缺「开放问题」节 | agent-gate.sh::validate_artifact_content() |
| GATE-E06 | 01-spec 无 REQ- 编号 | agent-gate.sh::validate_artifact_content() |
| GATE-E07 | 03-modification-plan 无 DES- 编号 | agent-gate.sh::validate_artifact_content() |
| GATE-E08 | 04-test-scripts 无 TC- 编号 | agent-gate.sh::validate_artifact_content() |
| GATE-E09 | 04-test-scripts 无 SC- 场景编号 | agent-gate.sh::validate_artifact_content() |
| GATE-E10 | 03-modification-plan 缺备选/选型对比内容 | agent-gate.sh::validate_artifact_content() |
| GATE-E11 | 04-test-scripts 缺覆盖维度列 | agent-gate.sh::validate_artifact_content() |
| GATE-E12 | 02-code-impact-analysis 缺业务影响节 | agent-gate.sh::validate_artifact_content() |
| GATE-E13 | 02-code-impact-analysis 缺风险内容 | agent-gate.sh::validate_artifact_content() |
| GATE-E14 | 02-code-impact-analysis 缺回滚策略 | agent-gate.sh::validate_artifact_content() |
| GATE-E15 | 03.5-tasks 缺依赖信息 | agent-gate.sh::validate_artifact_content() |
| GATE-E16 | 03.5-tasks 缺里程碑信息 | agent-gate.sh::validate_artifact_content() |
| GATE-E17 | 03.5-tasks 缺评审输入字段（§2.2 输入契约） | agent-gate.sh::validate_artifact_content() |
| GATE-E18 | 治理记录字段 owner 是占位符（PENDING 类被拒） | agent-gate.sh::reject_placeholder_owner() |
| GATE-E19 | 交付产物无溯源块 | agent-gate.sh::validate_provenance() |
| GATE-E20 | 溯源块仍含占位符 | agent-gate.sh::validate_provenance() |
| GATE-E21 | 溯源块缺必填字段 | agent-gate.sh::validate_provenance() |
| GATE-E22 | 溯源块 generated_at 非 ISO-8601 日期 | agent-gate.sh::validate_provenance() |
| GATE-E23 | 溯源块非 stamp-provenance.sh 产出（手写块拒） | agent-gate.sh::validate_provenance() |
| GATE-E24 | 00-governance.json 缺失 | agent-gate.sh::validate_governance_state() |
| GATE-E25 | 治理记录无该变更的 JSON 行 | agent-gate.sh::validate_governance_state() |
| GATE-E26 | 治理记录 change_id 与变更号不符 | agent-gate.sh::validate_governance_state() |
| GATE-E27 | 治理记录 risk_level 非 L0~L3 | agent-gate.sh::validate_governance_state() |
| GATE-E28 | 批次成员风险超 L1（批次仅收 L0/L1） | agent-gate.sh::validate_governance_state() |
| GATE-E29 | 治理记录缺 implementation_owner | agent-gate.sh::validate_governance_state() |
| GATE-E30 | 治理记录缺 spec_author（四主体互异） | agent-gate.sh::validate_governance_state() |
| GATE-E31 | L2/L3 缺 test_owner 或 review_owner | agent-gate.sh::validate_governance_state() |
| GATE-E32 | 实现/测试/评审 owner 须互异（L2/L3） | agent-gate.sh::validate_governance_state() |
| GATE-E33 | spec_author 须异于实现/测试/评审 owner（L2/L3） | agent-gate.sh::validate_governance_state() |
| GATE-E34 | spec_author 不得等于 review_owner（最低线） | agent-gate.sh::validate_governance_state() |
| GATE-E35 | review_owner 不得等于 implementation_owner（最低线） | agent-gate.sh::validate_governance_state() |
| GATE-E36 | L3 缺 release_authorized_by | agent-gate.sh::validate_governance_state() |
| GATE-E37 | L3 缺 release_authorized_at | agent-gate.sh::validate_governance_state() |
| GATE-E38 | L3 缺 release_authorization_evidence | agent-gate.sh::validate_governance_state() |
| GATE-E39 | bug_ref 字段不可解析（须扁平串或扁平字符串数组） | agent-gate.sh::validate_governance_state() |
| GATE-E40 | bug_ref 缺陷 id 形状非法 | agent-gate.sh::validate_governance_state() |
| GATE-E41 | bug_ref 缺陷组在 bugs_root 下不存在 | agent-gate.sh::validate_governance_state() |
| GATE-E42 | bug_ref 缺陷组缺缺陷文档 | agent-gate.sh::validate_governance_state() |
| GATE-E43 | 无活跃变更（先建产物再 begin） | agent-gate.sh::active_change() |
| GATE-E44 | 交付缺必备类别文档（八类最低集） | agent-gate.sh::check_delivery_doc() |
| GATE-E45 | 产物仍是未填模板（TEMPLATE-MARKER 未删） | agent-gate.sh::check_delivery_doc() |
| GATE-E46 | 清单行既非 [x] 也无「未命中，不适用」证据 | agent-gate.sh::check_delivery_doc() |
| GATE-E47 | 缺 04.5-coding-record | agent-gate.sh::validate_delivery() |
| GATE-E48 | 缺 05-test-results | agent-gate.sh::validate_delivery() |
| GATE-E49 | 缺 09-changelog | agent-gate.sh::validate_delivery() |
| GATE-E50 | changelog 缺 ReAct Observation 记录 | agent-gate.sh::validate_delivery() |
| GATE-E51 | changelog 引用的 REQ 未回填 01.5-rtvm-matrix | agent-gate.sh::validate_delivery() |
| GATE-E52 | L0 声明式空壳不适用最小集豁免（通道越级） | agent-gate.sh::stub_guard() |
| GATE-E53 | 缺陷组存在于多个日批次（保留一个） | agent-gate.sh::bug_group_dir() |
| GATE-E54 | 缺陷组锚定在多个日批次（保留一个） | agent-gate.sh::bug_group_dir() |
| GATE-E55 | 缺陷组命中多个合法布局（standalone/嵌套/扁平批） | agent-gate.sh::bug_group_dir() |
| GATE-E56 | 独立/嵌套缺陷组六件缺件 | agent-gate.sh::validate_bug_groups() |
| GATE-E57 | 批次缺陷组六件锚段缺件 | agent-gate.sh::validate_bug_groups() |
| GATE-E58 | 独立缺陷组当日执法：批已存在须并入 / 无批当日首个须建批（provenance 判日，未章跳过） | agent-gate.sh::validate_bug_groups() |
| GATE-E59 | 09-changelog 缺「项目总册回填清单」节 | agent-gate.sh::validate_master_backfill() |
| GATE-E60 | 回填清单缺 Pxx 总册行 | agent-gate.sh::validate_master_backfill() |
| GATE-E61 | 回填清单行非 [x] 也非「未命中（理由）」 | agent-gate.sh::validate_master_backfill() |
| GATE-E62 | docs/project/ 未初始化（先复制总册骨架） | agent-gate.sh::validate_project_masters() |
| GATE-E63 | 十三总册不齐 | agent-gate.sh::validate_project_masters() |
| GATE-E64 | stop 阶段验证命令执行失败 | agent-gate.sh::validate_stop() |
| GATE-E65 | diff 模式未知（staged/branch 之外） | agent-gate.sh::changed_files() |
| GATE-E66 | 源码改动无对应变更产物（spec/plan/test/evidence） | agent-gate.sh::validate_diff() |
| GATE-E67 | commit message 文件为空 | agent-gate.sh::validate_commit_msg() |
| GATE-E68 | 代码提交未引用变更号 | agent-gate.sh::validate_commit_msg() |
| GATE-E69 | begin 缺变更 id 参数 | agent-gate.sh::命令分发（case "$command"） |
| GATE-E70 | 变更 id 为 ./..（非法） | agent-gate.sh::命令分发（case "$command"） |
| GATE-E71 | 批次成员已闭合（own ## 小节已在 changelog）仍 begin | agent-gate.sh::命令分发（case "$command"） |
| GATE-E72 | 独立变更 09-changelog 已存在（已闭合）仍 begin | agent-gate.sh::命令分发（case "$command"） |
| GATE-E73 | 同日批次已存在仍开独立目录（L0/L1 须入批） | agent-gate.sh::命令分发（case "$command"） |
| GATE-E74 | 会话水位超限（默认 50 轮须 handoff；v3.63.0 起 `-ge` 口径） | agent-gate.sh::命令分发（case "$command"） |
| GATE-E89 | 同会话交付后未换挡（last-delivery 在本会话存活期内且无 handoff 证据；豁免 AGENT_GUARD_ALLOW_NO_SHIFT=1+09 登记） | agent-gate.sh::begin（v3.63.0，REQ-1033） |
| GATE-E90 | ui_change:true 但 01-spec 的 REQ 块未挂 UJ-xxx（空占位同拒） | agent-gate.sh::validate_artifact_content()（v3.67.0，CHG-090） |
| GATE-E92 | ui_change:true 但缺条件产物 03.6-ui-spec.md | agent-gate.sh::validate_ux_conditions()（v3.67.0） |
| GATE-E93 | ui_change:true 但 03.5 无 UX/UI 任务行（注释图例不算） | agent-gate.sh::validate_ux_conditions()（v3.67.0） |
| GATE-E94 | 03.6 缺显示名↔主键映射节 | agent-gate.sh::validate_ux_conditions()（v3.67.0） |
| GATE-E95 | ui_change:true 但 04 用户旅程 E2E 计数低于阈值（L0/L1=1，L2/L3=3） | agent-gate.sh::validate_ux_conditions()（v3.67.0） |
| GATE-E96 | 07 缺「用户可用性验收」签名节 | agent-gate.sh::validate_ux_conditions()（v3.67.0） |
| GATE-E97 | 03.6 把 DB 裸主键写成用户主入口 | agent-gate.sh::validate_ux_conditions()（v3.67.0） |
| GATE-E98 | 07 缺「建议人类走查（非阻塞）」行 | agent-gate.sh::validate_ux_conditions()（v3.67.0） |
| GATE-E99 | origin_artifact 声明但 behavior-inventory.json 缺失 | agent-gate.sh::validate_dimensional_begin/stop()（v3.68.0） |
| GATE-E100 | 原始工件 hash 失配（锚点腐烂）或无法验证 | agent-gate.sh::validate_dimensional_begin()（v3.68.0） |
| GATE-E101 | 行为清单含 遗漏(missing) 项 | agent-gate.sh::validate_dimensional_stop()（v3.68.0） |
| GATE-E102 | 三方对账孤儿（行为未被任何产物引用且未豁免） | agent-gate.sh::validate_dimensional_stop()（v3.68.0） |
| GATE-E103 | demo_script 声明但 05 缺 REPLAY: 回放证据 | agent-gate.sh::validate_dimensional_stop()（v3.68.0） |
| GATE-E104 | ui_change 但 05 缺逐 UJ 运行痕迹（事故硬门化） | agent-gate.sh::validate_dimensional_stop()（v3.68.0） |
| GATE-E105 | chain_change 但缺数据流规格表或表含空单元格 | agent-gate.sh::validate_dimensional_begin()（v3.68.0） |
| GATE-E106 | chain_change 但 04 缺否定测试抽查节 | agent-gate.sh::validate_dimensional_begin()（v3.68.0） |
| GATE-E107 | 07 缺运行时走查节或 ses-/task- 证据 id | agent-gate.sh::validate_dimensional_stop()（v3.68.0） |
| GATE-E108 | 行为豁免触真实链但无 00.5 追加沟通轮引用 | agent-gate.sh::validate_dimensional_stop()（v3.68.0） |
| GATE-E109 | origin_artifact 路径不存在 | agent-gate.sh::validate_dimensional_begin()（v3.68.0） |
| GATE-E110 | ui_change 但 05 无还原度断言证据/豁免行，或指向文件不存在/无断言标记 | agent-gate.sh::validate_delivery()（v3.71.0） |
| GATE-E111 | 基建面 diff 无 smoke_command 声明、缺窗内冒烟证据或 smoke_paths 正则非法（fail-closed）；豁免/证据限活跃变更 05，指针缺失 fail-open | agent-gate.sh::check_smoke_gate()（v3.71.0） |
| GATE-E112 | 同会话重复交付已交付变更且无 handoff.md/换挡声明/豁免 env | agent-gate.sh::validate_delivery()（v3.71.0） |
| GATE-E113 | TC 落点清单自动化条目指向文件不存在或无断言标记 | agent-gate.sh::validate_delivery()（v3.71.0） |
| GATE-E114 | 07「发现处置」表存在未处置行（处置空/待处置）或严重·安全发现记「不处理」 | agent-gate.sh::assert_finding_disposition()（v3.74.0） |
| GATE-E115 | 07 既无「发现处置」节（或节内无真实发现行）也无「未命中，不适用」单行声明 | agent-gate.sh::assert_finding_disposition()（v3.74.0） |
| GATE-E116 | 评审轮次超 AGENT_GUARD_REVIEW_ROUND_LIMIT 且 07 无「已填写的超限处置行」 | agent-gate.sh::track_review_round()（v3.74.0） |
| GATE-E117 | 07「发现处置」表「来源」列取值非法（非 本次引入/既有存量）；缺列软提示放行 | agent-gate.sh::assert_finding_source()（v3.75.0） |
| GATE-E118 | 验证通道 `ci.verification_command` 有值但形态非法（空值/未闭合引号/非法块指示符/多行裸标量/不在 `ci:` 段内）——fail-closed，不静默跳过 | agent-gate.sh::yml_scalar()/validate_stop()（v3.76.0） |
| GATE-E75 | 会话审计红灯未清（红报告新于最后交付 changelog） | agent-gate.sh::命令分发（case "$command"） |
| GATE-E76 | hook 输入无法确定目标文件 | agent-gate.sh::命令分发（case "$command"） |
| GATE-E77 | --stage commit-msg 用法错误（缺 message 文件） | agent-gate.sh::命令分发（case "$command"） |
| GATE-E78 | 未知 stage | agent-gate.sh::命令分发（case "$command"） |
| GATE-E79 | 未知命令 | agent-gate.sh::命令分发（case "$command"） |
| GATE-E80 | 02-code-impact-analysis 缺「延伸发现」节 | agent-gate.sh::validate_artifact_content() |
| GATE-E81 | 01-diagnosis 缺「延伸发现/历史相似检索」节 | agent-gate.sh::validate_governance_state() |
| GATE-E82 | 专家评审记录缺 agent 签名（platform / model / task） | agent-gate.sh::validate_delivery() |
| GATE-E83 | 沟通先行门：用户整体确认未记录即生成后续产物 | agent-gate.sh::validate_artifact_content() |
| GATE-E84 | 02-code-impact-analysis 缺「历史相似检索」节（或未命中声明） | agent-gate.sh::validate_artifact_content() |
| GATE-E85 | 07-review-report 缺可溯源独立评审签名（task-/ses- id） | agent-gate.sh::validate_delivery() |
| GATE-E86 | 目录落位声明↔目录/风险一致性 + L0/L1 声明独立目录一律拒（正向并入/反向首个即建）+ 批成员缺自身锚点 fail-closed | agent-gate.sh::validate_governance_state() |
| GATE-E87 | 缺陷组锚点散落兄弟文档但 01-diagnosis 缺失 | agent-gate.sh::validate_bug_groups() |
| GATE-E88 | 缺 review_owner（评审主体强制，最低线 L0/L1 亦必填） | agent-gate.sh::validate_governance_state() |
