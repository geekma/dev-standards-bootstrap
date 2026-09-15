<!-- markdownlint-disable MD033 MD041 MD013 -->
<div align="center">

# dev-standards-bootstrap

### 一条命令，为任意仓库注入完整的 AI Agent 开发治理与质量门禁体系

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Standards Version](https://img.shields.io/badge/规范版本-v3.14.0-green.svg)](resources/DEVELOPMENT_STANDARDS.md)
[![AGENTS.md](https://img.shields.io/badge/入口文件-AGENTS.md-orange.svg)](resources/AGENTS.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](../../pulls)

[English](README.md) | [中文](README.zh-CN.md)

</div>

---

## 概览

**dev-standards-bootstrap** 是一个可复用的 AI Agent Skill：一条命令，即可为任意代码仓库注入一套久经实战的**软件开发与变更治理体系**——**五道强制质量门禁**、**风险分级矩阵**、**Agent 角色独立性框架**与**防跳步执行规则**，一次安装、永久生效。

这套设计有实证支撑，不是假设。CIKM '26 对生产级 Agent 记忆的研究（[arXiv:2608.22752](https://arxiv.org/abs/2608.22752)）实测 `/compact` 压缩后**一轮仅保留 53% 的安全规则、五轮后只剩 10%**；[AI-Native SDLC Playbook](https://claude.com/blog/the-ai-native-sdlc-playbook) 记录了意图漂移与"事故不回流"的流程侧失效。本项目的答案是架构级的：**不信任 Agent 记忆与自我报告**——治理状态外置为磁盘上的版本化产物，零依赖门禁在每次写入时读取文件系统（而非对话上下文），CI 做最终裁决，且治理配置用 158 项 golden-case 断言自测试。完整设计依据见 [DEVELOPMENT_STANDARDS.md §2.17](resources/DEVELOPMENT_STANDARDS.md)。

失败诊断侧同样有方法论文支撑。AgentRx（[arXiv:2602.02475](https://arxiv.org/abs/2602.02475)）证明：根因归因要保持可靠（标注一致性 κ=0.89），必须把根因逼进**互斥分类、用消歧问题裁决并强制引用证据**，且检查器必须**两段式——先结构 guard 后断言**（证据含糊不得判罚）。本项目已将其吸收进 Bug 流程：根因表携带互斥分类与逐类消歧问题、根因锚定"**最早未恢复失败点**"（晚期显著症状不是根因）、每个新增门禁/审计检查遵循同一 guard→断言设计规约（§2.5 阶段 6、§2.13.4）。

---

## 核心特性

| 特性 | 说明 |
|---|---|
| **五道门禁 + 两层验收** | Doc-First / Test-First / Evidence / Traceability / Independent Verification，不可绕过；每阶段过机器可验的 A 层标记 + 独立角色 B 层判定（开发 Agent 不得自评，§2.5） |
| **风险分级 × 角色独立性** | L0–L3 矩阵决定独立性要求：执行主体分离，L2/L3 要求跨平台/跨模型厂商，L3 须人类 Release Owner 授权（§0.5） |
| **RTVM 全链路追踪 + 一次变更一组文档** | REQ→DES→TASK→TC 四维矩阵；每次变更新建 `docs/changes/<新变更号>/` 文档组，满足**最低文档集八类**（含 stop/ci 强检的 `04.5-coding-record.md`），每个缺陷新建缺陷六件套（一次变更一组文档，§2.15） |
| **10 阶段生命周期 + AI 防漏规则** | 每步 ReAct（Thought→Action→Observation）；防漏规则禁止摘要式"已完成"、静默降级与提前标记完成（§2.16） |
| **测试覆盖标准（十一类维度）** | 逐维设计或显式标注"不适用，理由"；新增代码分支覆盖 ≥60%（L2+）；LLM 评估集回归；**业务场景覆盖率 ≥80%**（SC-xxx，L3 ≥90%） |
| **方法论选型层（M0–M3）** | `METHODOLOGY.md` 回答"允许/禁止用哪些方法论"；`methodologies/` 提供逐条工程依据（弱类型穿层禁令、LLM 输入输出 schema 分离、state-trigger-audit） |
| **Bug 修复日志 + 同族推演 + 根因分类** | 仓库级追加式 `bugfix-log.md` 索引；根因表必含**同族推演**行与**互斥根因分类**（逐类消歧问题，锚定最早未恢复失败点，源自 AgentRx；§2.5 阶段 6）——不做同族扫描的修复一律退回 |
| **确定性门禁 + 管线自动化** | 一个零依赖校验脚本，被写入时 Hook、Git Hook、CI 共用；spec 合入自动派发骨架、changelog 合入自动开发布检查单、事故自动生成 `BUG-<ts>` 意图 PR；自主权上限 A2（§2.17） |
| **Golden-Case 自测试** | `tests/run-tests.sh` 在临时 git 仓库中回归测试门禁与安装器（158 项断言）——仅依赖 bash + git（§2.17.4） |

`agent-gate metrics` 从 git 历史输出只读 JSON Lines 管线度量——仅作观察，不得替代 DoD 判定（§2.17.5）。专项规范覆盖部署/配置/DB 变更、AI/LLM 链路、测试数据隔离、紧急热修复、发布、监控与供应链（§2.6–§2.13）。

---

## 支持的 AI 编码工具

`AGENTS.md` 是上下文机制而非强制机制，各客户端支持程度不同。原生读取 `AGENTS.md`：**Claude Code、Cursor、Codex、Windsurf、Gemini CLI、Qoder、Trae、OpenCode**。无已知 Hook schema 的客户端不会被臆造配置——其强制路径是 Git Hook 与 CI（校验的是仓库而非编辑器）。最终跨客户端控制是分支保护 + Required CI Check。

---

## 快速开始

把仓库克隆进你的 Skill 目录（`git clone https://github.com/geekma/dev-standards-bootstrap.git`，或作为 submodule 添加），在任意目标仓库打开你的 AI 编码工具，说：

> "用 dev-standards-bootstrap 初始化这个仓库。"

Skill 会执行 `bash scripts/bootstrap.sh --all <目标仓库>`（分层 flag `--core/--claude/--ci/--guard/--pipeline` 可选装）：检测已有文件、绝不静默覆盖（先展示 diff，`--force` 才覆盖），然后**自动注入全部内容**——`AGENTS.md`、规范/方法论层、模板、门禁、Git Hook + `core.hooksPath` 接线、客户端 Hook 适配器、CI workflow、自动探测的验证命令、golden-case 自测试套件。初始化后没有需要手工接线的东西（仅剩一步平台侧操作，见下）。

**版本升级**：Skill 版本更新后，把同一句话再说一遍——Skill 检测版本差异并执行 `bootstrap --upgrade`：治理自有文件（规范/模板/脚本/hooks/workflows）更新到携带版本，**live 记录不动**（`bugfix-log.md`、交付总结、06.5 记录、你的 `.agent-governance.yml`），随后重跑自动接线。升级前先提交目标仓库，让 git history 保留任何自定义。

---

## 仓库结构

```
dev-standards-bootstrap/
├── SKILL.md                                # Skill 清单（触发器、执行步骤、红线）
├── README.md                               # 英文文档
├── README.zh-CN.md                         # 中文文档（本文件）
├── LICENSE                                 # MIT 许可证
├── scripts/
│   ├── bootstrap.sh                        # 清单驱动安装器（不随 Skill 下发）：按层复制 resources/ 到目标仓库，幂等、冲突安全
│   └── update-assertion-count.sh           # 仅规范源层（不下发）：再生成 README 断言声称数 + 审计执行数基线
├── screenshots/                            # README 截图（门禁拦截、变更产物）
├── tests/
│   ├── run-tests.sh                        # 治理模板 golden-case 回归套件，含门禁与 bootstrap（158 项断言；复制到目标 tests/——目标仓自适应：未下发/跳过用例自动 SKIP）
│   └── audit-standards-src.sh              # 仅规范源层（不下发）：审计规范文本自身——版本链 / 关键词矩阵 / 清单唯一性 / 编号体系 / 防恒真 grep
└── resources/
    ├── AGENTS.md                           # AI Agent 入口文件（复制到目标仓库根目录）
    ├── DEVELOPMENT_STANDARDS.md             # 完整规范文档 v3.14.0（复制到 docs/）
    ├── STANDARDS_CHANGELOG.md              # 规范升级日志（§2.14 日志唯一落点，v3.8.0 起；复制到 docs/）
    ├── METHODOLOGY.md                       # 方法论选型指南：M0–M3 分级 + 阶段×方法论×适用/不适用主表（复制到 docs/）
    ├── methodologies/
    │   ├── development.md                   # 代码规范：SOLID/DRY/KISS/YAGNI 适用与豁免 + 7 个工程维度
    │   ├── data-structures.md               # 数据结构规范：6 类模型 + 弱类型禁令 + LLM 输入输出专项
    │   └── state-trigger-audit.md           # 状态/触发链路审计：6 条教训 + 6 步清单 + 3 个反模式（v3.4.0）
    └── templates/
        ├── CLAUDE.md                       # Claude Code 一行导入
        ├── PULL_REQUEST_TEMPLATE.md        # 带门禁自检的 GitHub PR 模板
        ├── check-standards-compliance.sh   # CI 合规检查脚本
        ├── agent-gate.sh                   # pre-write / commit-msg / Git / CI 共用校验器（含 metrics）
        ├── intent.md                       # 每次变更 00-intent.md 的管线入口模板
        ├── coding-record.md                # 变更编码记录模板（→ docs/changes/<CHG>/04.5-coding-record.md）
        ├── bugfix-log.md                   # 仓库级缺陷索引模板（复制到 docs/bugfix-log.md）
        ├── bug-diagnosis.md、bug-impact.md、bug-test-plan.md、bug-matrix.md、bug-config.md、bug-tasks.md  # 缺陷文档组六件套（→ docs/bugs/_templates/）
        ├── 06.5-deployment-config.md       # 部署/配置/DB 记录模板（→ docs/；未命中须显式声明"未命中，不适用"）
        ├── 06-delivery-summary.md          # 交付总结 + FU 台账模板（→ docs/；§2.5 阶段 9.5 四项必含）
        ├── audit-docs-consistency.sh       # 跨文档一致性审计：版本链 / 编号连续 / 清单同源 / bugfix 双登记互证 / RTVM 回填（复制到 tests/）
        ├── governance-state.json           # 每次变更 00-governance.json 模板（风险等级 + 执行主体）
        ├── agent-governance.yml            # 团队可评审的治理配置记录（复制为 .agent-governance.yml）
        ├── pre-commit、pre-push、commit-msg  # Git Hook 模板（commit-msg：归因闸门）
        ├── install-hook-adapter.sh         # 为检测到的工具生成 Hook 适配器（claude/cursor/gemini）
        ├── github-agent-governance.yml     # Required Check workflow 模板
        ├── github-artifact-pipeline.yml    # 产物管线：spec 合入 -> 02/03/03.5/04 骨架 PR；changelog 合入 -> 发布检查单 issue
        └── github-incident-to-intent.yml   # 事故环：告警派发 -> BUG-<ts> 意图骨架 PR
```

---

## 确定性门禁（agent-gate）

`bootstrap --guard`（`--all` 含）**自动注入完整强制执行包**：`scripts/agent-gate`、`.githooks/` Git Hook（pre-commit/pre-push/commit-msg）与 `core.hooksPath` 接线、`.agent-governance.yml`（团队可评审记录）、检测到受支持编码客户端时自动生成 Hook 适配器、golden-case 套件。无 Hook schema 的客户端由 Git Hook + CI 强制执行——不臆造配置。

发起变更：在 `docs/changes/CHG-123/` 落 `00-intent.md`（意图登记）+ `00-governance.json`（风险等级 + 互异执行主体；L3 另须 `release_authorized_by` 系列三个授权字段）及非空的规格/影响/方案/任务/测试产物，然后执行：

```bash
scripts/agent-gate begin CHG-123
```

| 命令 | 用途 |
|---|---|
| `begin <change-id>` / `end` | 激活或清除活跃变更；`begin` 要求七件变更产物齐备且非空（含 `00-intent.md`、`02` 影响分析、`03.5` 任务拆解），并校验治理状态与 A 层内容标记 |
| `--stage pre-write` | Agent 写源码前校验活跃变更产物与治理状态；目标路径解析失败即拒绝放行（fail-closed） |
| `--stage staged` | 暂存的源码改动必须携带对应变更产物与有效治理状态，否则提交被拒 |
| `--stage commit-msg <msgfile>` | 归因闸门：暂存代码文件的提交消息必须引用有效变更号（合并 / Revert / 纯文档提交豁免） |
| `--stage stop` | 源码改动后结束回合前，必须存在 `04.5-coding-record.md`（最先校验）、`05-test-results.md`、`09-changelog.md`（含 ReAct Observation 记录），配置了 `AGENT_GUARD_VERIFY_COMMAND` 时还须真实执行通过；changelog 引用的 REQ 必须已回填 `docs/<feature>/01.5-rtvm-matrix.md` 行（门禁 4 RTVM 闭环） |
| `--stage ci [--base <ref>]` | 复核分支/PR diff（产物 + 治理状态 + 触及变更的交付证据）并执行真实验证命令 |
| `metrics` | 只读管线度量 JSON Lines——仅观察，不得替代 DoD |

![新变更必检产物集：00-governance.json、01-spec.md、03-modification-plan.md、04-test-scripts.md 以新文件暂存](screenshots/change-artifacts-required-set.png)

![agent-gate 在 IDE 内拦截不合规的源码提交](screenshots/agent-gate-blocked-in-trae.png)

**验证命令**（`stop` 与 `ci` 运行的真实构建/测试命令）在 bootstrap 时从项目布局**自动探测**（package.json / Makefile / pom.xml / go.mod / pyproject / Cargo）并预填 `.agent-governance.yml`——可直接编辑，或用 `AGENT_GUARD_VERIFY_COMMAND` 环境变量覆盖（最高优先级）。用户既有配置绝不被覆盖（自定义 `core.hooksPath` 或已改的 yml 原样保留）。安全说明：**yml 文件本身处于待定变更中时，其验证命令不会被执行**（反篡改——PR 无法向审查者的钩子注入命令）；先提交，或用环境变量。

唯一剩余的平台侧步骤：将 `agent-governance` workflow 标记为**必需的分支保护检查**（Settings → Branches，或经 `gh api`）。状态文件与勾选框只是声明而非证据：CI 会重跑真实命令，且是强制要求。

### 可选管线自动化（§2.17）

由 `bootstrap --pipeline`（`--all` 含）自动注入——workflow 直接落 `.github/workflows/`，零接线：

- **产物管线**（`github-artifact-pipeline.yml`）：`01-spec.md` 合入自动创建 scaffold 分支并派发 `02`/`03`/`03.5`/`04` 骨架 PR；`09-changelog.md` 合入自动开发布检查单 issue。骨架只含标题与待填注释。
- **事故环**（`github-incident-to-intent.yml`）：监控系统触发 `repository_dispatch` 类型 `incident`，workflow 自动创建 `BUG-<UTC 时间戳>` 意图骨架 PR——每次事故都以登记意图的形式重入管线。
- **自主权上限**：托管 workflow 限于 A2 动作（分支、骨架、PR、issue）；内容（A3）与执行（A4）留在本地；合入门禁不因自动化而豁免。语义以规范 §2.17 为准，与平台无关。
- **自测试**：改动 `agent-gate.sh`、Hook 或 workflow 前，先跑 `bash tests/run-tests.sh`——158 项 golden-case 断言，仅依赖 bash + git。

---

## 五道质量门禁

变更通过门禁的过程会积累完整产物链，从 `01-spec.md` 一直到 `08-supplement.md`：

![变更完整产物生命周期：01-spec 至 08-supplement](screenshots/change-artifacts-full-lifecycle.png)

```
[ 门禁 1: 需求/设计先行 ]   任何代码改动前必须先有需求与设计
        │
        ▼
[ 门禁 2: 测试脚本先行 ]   实现前必须先有测试用例（TDD 红绿循环）
        │
        ▼
[ 门禁 3: 运行测试与证据 ] 必须有真实测试输出——严禁口头宣称"已完成"
        │
        ▼
[ 门禁 4: 全链路追踪 ]     RTVM 必须闭环：REQ ↔ DES ↔ CODE ↔ TC
        │
        ▼
[ 门禁 5: 独立验证 ]       测试与审查由不同主体完成；高风险须人类授权
```

任何一道门禁未通过，变更即被**拦截在合入主分支之外**。

---

## 风险分级矩阵

| 等级 | 判定依据 | 独立性 | 跨平台 | 人类授权 |
|---|---|---|---|---|
| **L0** 极低 | 无逻辑变更（文档、注释、格式化） | 角色可合并 | 不要求 | 无 |
| **L1** 低 | 非核心模块、无对外接口 | 独立子任务 | 不要求 | 无 |
| **L2** 中（默认） | 核心业务逻辑、P0/P1 优先级 | 独立执行主体 | 建议 | 无 |
| **L3** 高 | 敏感个人数据（PII）、认证授权、生产 DB、AI/Prompt、对外接口破坏性变更、P0 热修复 | 强制跨平台/跨模型 | **强制**（≥2 模型厂商） | **强制** |

---

## 参与贡献

欢迎贡献！提交变更请遵循本仓库规范：文档先行（门禁 1）、测试先行（门禁 2）、真实测试输出（门禁 3）、RTVM 闭环（门禁 4）、独立审查（门禁 5）。PR 请使用 [PR 模板](resources/templates/PULL_REQUEST_TEMPLATE.md)并完成全部门禁自检。

---

## 许可证

本项目基于 [MIT 许可证](LICENSE)开源。

---

<div align="center">

**规范版本：** v3.14.0 | **最后更新：** 2026-09-14 | **维护者：** [geekma](https://x.com/geekma) | **邮箱：** geekma@gmail.com

[报告问题](../../issues) | [请求功能](../../issues) | [阅读规范全文](resources/DEVELOPMENT_STANDARDS.md)

</div>
