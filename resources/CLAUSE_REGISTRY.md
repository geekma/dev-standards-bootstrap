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
| R19 | 会话与上下文纪律（§2.9.6 水位/换挡） | DEVELOPMENT_STANDARDS.md::### 2.9.6 会话与上下文纪律 | universal | 软 | 行为 |
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
