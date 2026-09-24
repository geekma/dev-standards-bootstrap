<!-- markdownlint-disable MD033 MD041 MD013 -->
<div align="center">

# dev-standards-bootstrap

### 一条命令，为任意仓库接入 AI Agent 开发治理与质量门禁体系

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/geekma/dev-standards-bootstrap/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/geekma/dev-standards-bootstrap/actions/workflows/ci.yml)
[![Standards Version](https://img.shields.io/badge/规范版本-v3.49.0-green.svg)](resources/DEVELOPMENT_STANDARDS.md)
[![AGENTS.md](https://img.shields.io/badge/Entry_Point-AGENTS.md-orange.svg)](resources/AGENTS.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](../../pulls)

[English](README.md) | [中文](README.zh-CN.md) | [更新日志](resources/STANDARDS_CHANGELOG.md)

</div>

`dev-standards-bootstrap` 是一个 **Agent 技能**（也是普通 git 仓库，可装入任意编码 Agent），把**开发治理**注入任意代码仓库：所有编码 Agent 首先读取的 `AGENTS.md` 唯一入口、五道强制**质量门禁**（文档先行/测试先行/证据/追踪/独立验证）、风险分级的**变更管理**、Git/CI 兜底执行——装一次，随升级链保持最新。

| | |
|---|---|
| **注册 Skill（一次性）** | `npx skills add geekma/dev-standards-bootstrap -g` —— 或在[第 1 步](#第-1-步--把-skill-注册进你的-ai-客户端一次性)选任意路由 |
| **初始化任意仓库** | 说一句：*"用 dev-standards-bootstrap 初始化这个仓库。"* |

---

## 项目简介

**dev-standards-bootstrap** 是一个可复用的 AI Agent Skill：一句话把一套久经实战的开发治理体系接入任意代码仓库。它提炼自一个 Agent 日产出数亿 token 的生产仓库——封装的正是让这些产出可交付的闭环：先文档后代码、先测试后功能、先证据后"完成"、先独立评审后合并。

`AGENTS.md` 是所有编码 Agent 第一个读取的上下文层；可选的确定性门禁（`agent-gate`）通过客户端 Hook 与 Git Hook 在写入前阻断不合规变更，CI 是跨客户端的最终裁决者。装一次，之后每次变更只需告诉 Agent 你要做什么——流程自己会跑。

> **本 README 是参考手册。** 文中所有命令都在正确的时机由 Skill、Git Hook 或 CI **自动调用**；手动执行永远只是可选。

## 为什么需要它

设计有实测依据，不是假想。CIKM '26 对生产环境 Agent 记忆的研究（[arXiv:2608.22752](https://arxiv.org/abs/2608.22752)）表明：`/compact` 一轮后安全规则仅存 **53%**，五轮后 **10%**；[AI-Native SDLC Playbook](https://claude.com/blog/the-ai-native-sdlc-playbook) 记录了意图漂移与"事故不回流"。答案是架构性的：**永不信任 Agent 的记忆与自我汇报**——治理状态以版本化产物落盘，零依赖门禁在每次写入时读文件系统（而非对话），CI 最终裁决，治理包自带自测试（见[核心功能](#核心功能)）。

故障诊断侧同样有依据：AgentRx（[arXiv:2602.02475](https://arxiv.org/abs/2602.02475)）证明根因归因只有在**互斥分类 + 消歧清单 + 证据引用**下才可靠。本项目把两者都折进缺陷流程：根因锚定**最早未恢复失败点**，每个门禁/审计检查器遵循 guard→断言两段式设计。

两条来自本规范所出处生产仓库的实战记录：

<p align="center">
  <img src="screenshots/token-counter-93m-per-day.png" alt="Token 计数器：单日 93.9M tokens，七天 192.6M" width="360">
  <br>
  <sub><b>实战记录 1 —— 代码不再是瓶颈。</b>真实 token 计数器截图：单日 93.9M tokens（$2.36），七天 192.6M。产出以亿计，崩的是裹在产出外面的流程。</sub>
</p>

<p align="center">
  <img src="screenshots/standards-bloated-879-lines.png" alt="Agent 接到任务后先 wc -l docs/DEVELOPMENT_STANDARDS.md 并 ls docs/" width="760">
  <br>
  <sub><b>实战记录 2 —— 标准活在磁盘上，不在上下文里。</b>Agent 接到任务的第一个动作是 <code>wc -l docs/DEVELOPMENT_STANDARDS.md</code> 与 <code>ls docs/</code>：它把规范当作"必须去读的文件"，而不是"恰好记得的规则"——对话可能早已被压缩。</sub>
</p>

## 实测收益

不是理论——基于 11 个真实工作会话的三方能力贡献分析（会话 DB 实测 + git 历史 + 治理产物交叉验证；[完整分析](能力对比分析.md)）：

| 维度 | 模型（LLM） | Agent Harness | **dev-standards-bootstrap** |
|---|---|---|---|
| 20 个 SDLC 环节贡献平均 | 36% | 17% | **44%** |
| 最强环节 | 编码实现 70% | 测试执行 70% | **经验沉淀 70%** |
| 去掉它还剩什么 | — | — | 编码/测试仍保留 85~95%；**沉淀、跨会话交接、合规审计、立项留痕只剩 25~40%** |
| 配对配置达成度（有 vs 无） | — | — | **约 59% → 100%（高约 41 个百分点）** |

**这能给你带来什么：**

- **方差压缩，不是更聪明。** 治理不提高模型智力，而是把"聪明但失忆、局部强但全局弱、单次准但复现差"的结构性缺陷用机校 + 记忆 + 独立性钉死。没有它，交付质量是抽签：实测样本包括同一函数六连修、测试断言示例值伪造家族。
- **价值集中在组织记忆。** 会话一压缩/结束，无治理的 Agent 从失忆重启；这里状态活在 12 册项目总册与磁盘产物里。
- **税是可测量且正在被砍的。** 治理机制成本约 25% 工具调用 + 常驻底座，而 token 账单的 97.5%+ 是不换挡会话的 cache-read prefill——v3.38/v3.39 把会话纪律升级为机器执法（水位门、勘探预算黄灯、评审输入契约）正是冲着它去的：**约 90% 达成度 + 30~50% 成本下降**——规范的质量，接近裸奔的成本。

## 核心功能

| 功能 | 说明 |
|---|---|
| **五道门禁 + 两层验收** | 文档先行 / 测试先行 / 证据闭环 / 追踪矩阵 / 独立验证——不可绕过；每阶段过机器可验的 A 层标记 + 独立角色 B 层判定（§2.5） |
| **风险分级 × 角色独立性** | L0–L3 矩阵驱动独立性：独立执行主体，L2/L3 要求不同平台/模型厂商，L3 强制人类 Release Owner 授权（§0.5） |
| **分阶段专家评审（9 专家，§2.2）** | 业务/行业/技术/架构/项目管理/安全/性能/测试/整体验收专家，作为既有角色的细分执行主体；PMP 对齐的分阶段评审矩阵 + 上下文贴近契约（无项目证据的模板泛评一律退回）+ 会话成本护栏 |
| **RTVM 追踪矩阵 + 一次变更一组文档** | REQ→DES→TASK→TC 全链路矩阵；每次变更新开 `docs/changes/<新变更号>/` 文档组（满足**八类最低文档集**，§1.1）；每个缺陷新开六件套 |
| **10 阶段生命周期 + AI 防跳过规则** | 每步 ReAct（Thought→Action→Observation）；禁止总结式"已完成"、静默降级、提前标完成（§2.16） |
| **测试覆盖标准（11 维度）** | 逐维设计或显式"不适用"；分支覆盖率 ≥60%（L2+）；LLM 评估集回归；**业务场景覆盖率 ≥80%**（SC-xxx，L3 ≥90%） |
| **方法论选型层（M0–M3）** | `METHODOLOGY.md` 回答"哪些方法论允许/禁止"；`methodologies/` 提供逐条工程依据（弱类型禁令、LLM I/O 契约分离、状态触发链路审计） |
| **缺陷日志 + 同族推演 + 根因分类** | 仓库级追加式 `bugfix-log.md` 索引；根因表必含**同族推演**行与互斥根因分类，锚定最早未恢复失败点（AgentRx 依据；§2.5 阶段 6）——不做同族扫描的修复被拒 |
| **确定性门禁 + 管线自动化** | 一个零依赖校验器被写入时 Hook、Git Hook 与 CI 共享；spec 合入自动派发骨架 PR、changelog 合入自动开发布检查单、事故自动生成 `BUG-<时间戳>` 意图 PR；自主权上限 A2（§2.17） |
| **golden case 自测试** | `tests/run-tests.sh` 在临时 Git 仓库里回归测试门禁与安装器（480 项 golden-case 断言）——只需 bash + git（§2.17.4） |

`agent-gate metrics` 从 git 历史输出只读 JSON Lines 管线度量——仅作观察，永不替代 DoD 判定（§2.17.5）。专项规范覆盖部署/配置/DB、AI/LLM 管线、测试数据隔离、紧急热修复、发布、监控与供应链（§2.6–§2.13）。唯一版本历史是 [`resources/STANDARDS_CHANGELOG.md`](resources/STANDARDS_CHANGELOG.md)（随 --core 下发，audit G1 机校）。

## 支持的 AI 编码工具

`AGENTS.md` 是上下文机制而非强制机制，支持度因客户端而异。原生读取 `AGENTS.md`：**Claude Code、Cursor、Codex、Windsurf、Gemini CLI、Antigravity、Qoder、Trae、OpenCode**。没有已知 Hook schema 的客户端不会被伪造配置——它们的强制路径是 Git Hook + CI（校验的是仓库而非编辑器）。跨客户端的最终控制是受保护分支 + 必需 CI 检查。

## 快速开始

### 第 1 步 —— 把 Skill 注册进你的 AI 客户端（一次性）

第 2 步那句话生效的前提：Agent 先认识这个 Skill。**四选一**（A/B/D 端到端实测；C 是给 Agent 的自然语言指令，无可执行物）：

**A. 通用 skill store** —— 今天即可用，任意仓库、任意支持的客户端：

```bash
npx skills add geekma/dev-standards-bootstrap -g
```

**B. Claude Code 插件** —— 市场化安装与更新：

```bash
claude plugin marketplace add geekma/dev-standards-bootstrap
claude plugin install dev-standards-bootstrap@geekma-dev-standards
```

**C. 直接对 Agent 说**（不动命令行）：

> "从 https://github.com/geekma/dev-standards-bootstrap 安装 dev-standards-bootstrap 这个 Skill 到你的技能目录（克隆仓库后把它的 `SKILL.md` + `resources/` + `scripts/` 链接进去），然后重载技能。"

**D. 仓库自带安装器** —— 取[那条唯一命令](#安装与升级)并在末尾追加 `--as-skill claude`：symlink 进 `~/.claude/skills`（语义与其他客户端见 [`--as-skill` 详解](#--as-skill-详解快速开始路由-d)）。

装完重载客户端（Claude Code 里 `/reload-skills`，或重开会话）。

### 第 2 步 —— 初始化仓库（一句话）

在目标仓库打开你的 AI 编码工具，说：

> "用 dev-standards-bootstrap 初始化这个仓库。"

就这样。Agent 会检测已有文件（绝不静默覆盖——先展示 diff 再询问）、运行安装器、接好 Hook，并汇报剩余事项（仅一步平台侧配置，见[下文](#自动化与手动边界)）。以后升级还是同一句话——Skill 检测版本差后自动升级。

**完全不想注册 Skill？** 照[那条唯一命令](#安装与升级)原样执行（不加任何 flag）——治理体系直接装进仓库，与 Agent 无关（`AGENTS.md` 上下文层被所有支持的客户端原生读取）；目标仓已接入时自动转为升级。

无论哪条路径，装完之后没有任何需要手工接线的东西：

<p align="center">
  <img src="screenshots/agent-writing-change-artifacts.png" alt="Agent 在写 CHG-044 全套产物与 BUG-016/BUG-017 缺陷文档组" width="620">
  <br>
  <sub>提报变更是 Agent 的工作，不是你的：Agent 写出 CHG-044 的全套产物（意图 → 治理声明 → 规格 → 影响分析 → 方案 → 任务 → 测试脚本）以及 BUG-016/BUG-017 的缺陷文档组——全部落在第一行源码之前。</sub>
</p>

## 安装与升级

**一条命令（安装或升级，自动探测）：**

```bash
curl -fsSL https://raw.githubusercontent.com/geekma/dev-standards-bootstrap/main/scripts/install.sh | bash -s -- .
```

- 默认目标仓是当前目录；把路径作为第一个参数传入即可指定。
- Skill checkout 保存在 `~/.dev-standards-bootstrap/dev-standards-bootstrap`（`--skill-dir <路径>` 可覆盖）；已存在的 checkout 会被复用并 fast-forward 拉取——**其中的本地改动绝不会被覆盖**（命令会拒绝并指路）。
- 目标仓已接入 → 自动转 `--upgrade`：治理自有文件（规范/模板/脚本/hooks/workflows/tests）升到携带版本，**live 记录不动**（`bugfix-log.md`、交付总结、06.5 记录、你的 `.agent-governance.yml`）。升级前先提交目标仓——git 历史即备份。
- 离线/锁定版本安装：`--from <本地checkout>`、`--repo <url>`、`--ref <分支或tag>`。
- 分层安装（`--layer core|claude|ci|guard|pipeline`）与自定义目录根（`--docs-dir`、`--scripts-dir`、`--tests-dir`、`--githooks-dir`）透传给安装器；不传即全量 `--all` + 默认根。
- 目标仓应是 git 仓库：Hook 接线（`core.hooksPath`）依赖 `.git/`——裸目录能装文件但 Git Hook 层不生效（接入 CI 后仍有 CI 兜底）。
- 只查版本不落盘：`--check` 三处版本比对，有漂移 exit 1（可入 CI）。

### `--as-skill` 详解（快速开始路由 D）

路由 D 把 checkout symlink 进客户端技能目录——同[那条唯一命令](#安装与升级)，换不同参数：

- `--as-skill opencode` → symlink 进 `~/.config/opencode/skills/`
- `--as-skill all` → 两个客户端都装
- `--as-skill ~/.agents/skills/dev-standards-bootstrap` → 其他任意客户端，直接给落点目录

注册是**符号链接**指向 checkout（零复制——自更新即时生效）、fail-closed（已有非 symlink 落点绝不触碰；`--force` 仅 retarget symlink 或替换**空**目录）、与 `--install`/`--upgrade`/`--check`/`--layer` 互斥（同调即 usage error，exit 2），与"治理体系进仓库"两条路径独立、可组合。装完重载（Claude Code 里 `/reload-skills`，或重开会话）。

**手动等价（两条命令，如果你更喜欢）：**

```bash
git clone https://github.com/geekma/dev-standards-bootstrap.git
bash dev-standards-bootstrap/scripts/bootstrap.sh --all <目标仓库>
```

**自查版本**：携带的规范版本写在 `SKILL.md` 三处——frontmatter `version:`、`description` 尾注、正文顶部横幅——技能列表里与每次加载时都能看到。与 README 顶部的 `规范版本` 徽章比对，或执行 `bash <skill目录>/scripts/bootstrap.sh --check <目标仓库>`。

**自定义目录根**：默认根是 `docs/`、`scripts/`、`tests/`、`.githooks/`（另有 `.github/`——平台强制位置，因此不可移动）。**只有目录根可配置**：`AGENTS.md` 文件名、门禁落点名、变更 14 件产物名、缺陷六件套名、required-check 名是跨仓契约——做成可配置就失去了跨仓比对与迁移能力。

## 自动化与手动边界

装好之后，强制是事件驱动的——**你永远不需要自己跑门禁**：

| 事件 | 自动发生什么 |
|---|---|
| Agent 将要写源码 | 客户端 pre-write Hook 校验活跃变更的产物与治理状态 |
| 你（或 Agent）提交 | `pre-commit`/`commit-msg` Hook 校验暂存产物与变更归因；代码提交不带变更号即被拒 |
| 源码改动后一轮结束 | stop Hook 要求编码记录（带脚本盖章溯源）、测试证据、含 ReAct Observation 的 changelog |
| 会话开始 / 收尾 | 会话门禁开始时跑一致性审计、空闲时跑 stop 等价检查——存量红灯在会话内即可见（v3.28.0）；红灯同时输出缺陷信号交互三选项提示（建骨架/登记 FU/忽略须 09 理由，v3.43.0） |
| PR 打开 | CI 重跑产物校验**和项目真实验证命令**，并要求 `agent-governance` 检查 |
| `01-spec.md` 合入主干 | 自动创建骨架分支并派发 `02`/`03`/`03.5`/`04` 骨架 PR（产物管线） |
| `09-changelog.md` 合入主干 | 自动开发布检查单 issue |
| 生产事故触发 | `repository_dispatch type=incident` 自动创建 `BUG-<UTC时间戳>` 意图骨架 PR——每个事故都以记录过的意图重入管线 |
| 主干测试运行失败 | `regression-to-bug` workflow 调用 `scripts/bug-autointent`：自动建**完整缺陷六件套**骨架（按天扁平批、元数据预填），带**指纹频控**——窗口内（默认 24h，env 可覆）同一失败集合只追加复现行，不重复建组（v3.43.0） |

命令参考（由上述事件自动调用；手动执行用于排障）：

| 命令 | 用途 |
|---|---|
| `begin <变更号>` / `end` | 激活或清除活跃变更；要求七件变更产物并校验治理状态（风险等级、互异的执行主体；L3 另须三个 `release_authorized_by` 系列授权字段）与 A 层内容标记 |
| `--stage pre-write` | Agent 写源码前校验活跃变更；无法从 Hook 输入解析目标路径即 fail-closed |
| `--stage staged` | 暂存的源码变更必须随带匹配的变更产物，否则提交被拒 |
| `--stage commit-msg <msgfile>` | 归因闸门：含代码的提交必须引用有效变更号（合并/回退/纯文档豁免） |
| `--stage stop` | 源码改动后收尾要求 `04.5-coding-record.md`、`05-test-results.md`、`09-changelog.md`（含 ReAct Observation）及验证命令通过（L0：04.5/05 可按 §1.1 单行声明，v3.44.0）；changelog 引用的 REQ 须回填 `01.5-rtvm-matrix.md`（门禁 4 闭环） |
| `--stage ci [--base <ref>]` | 复查分支/PR diff 并运行真实验证命令 |
| `metrics` | 只读管线度量（JSON Lines）——仅观察；聚合 gate 摩擦事件账（die 错误码→计数，v3.43.0） |

**文件溯源**：编码记录必须携带由 `scripts/stamp-provenance.sh <变更号>` 生成的 `<!-- provenance -->` 块——作者、提交者、提交哈希、主机、平台、UTC 时间全部从运行环境读出，手写编不出来。`--all` 可给变更目录全部 `*.md` 产物盖章（治理 JSON 刻意排除）；v3.41.0 起 pre-commit Hook 自动执行，v3.42.0 增 `--trace`——changelog §4 的追踪矩阵编号从 `01.5-rtvm-matrix.md` 确定性派生，不再手抄。门禁校验块形状与生产者；`author` 值本身是否属实**不可机器验证**——设计如实说明而非假装已解决。不追溯既往：历史永不回填，因为回填会把 `generated_at` 伪造成"今天"——那正是溯源块要防的事。

**验证命令自动探测**：安装时从项目布局（package.json / Makefile / pom.xml / go.mod / pyproject / Cargo）探测真实构建/测试命令并预填 `.agent-governance.yml`——可在该文件修改，或用 `AGENT_GUARD_VERIFY_COMMAND` 环境变量覆盖（最高优先级）。yml 里的验证命令**在该文件本身处于待定变更中时不会执行**（防篡改——PR 无法把命令注入审查者的 Hook）；先提交它，或改用环境变量。

**唯一的手动步骤（平台侧，文件做不到）**：把 `agent-governance` workflow 标记为**必需的分支保护检查**（Settings → Branches，或 `gh api`）。状态文件与勾选框只是声明不是证明：CI 重跑真实命令且强制执行。

截图——门禁在零手动步骤下工作：

<p align="center">
  <img src="screenshots/change-artifacts-required-set.png" alt="00-governance.json、01-spec.md、03-modification-plan.md 与 04-test-scripts.md 作为新文件暂存" width="620">
  <br>
  <sub>新变更的最低产物集作为新文件暂存——没有它们，<code>begin</code> 拒绝激活门禁。</sub>
</p>

<p align="center">
  <img src="screenshots/agent-gate-blocked-in-trae.png" alt="agent-gate 在 IDE 内拒绝无变更产物的源码提交" width="420">
  <br>
  <sub>agent-gate 在 IDE 内拦截不合规源码提交：<code>docs/changes/&lt;变更号&gt;/</code> 下没有产物，就没有提交——且强制不绑定任何单一编辑器。</sub>
</p>

<p align="center">
  <img src="screenshots/agent-gate-blocks-defect-doc-set.png" alt="agent-gate 拒绝缺少 docs/changes/BUG-021/00-intent.md 的缺陷提交" width="420">
  <br>
  <sub>缺陷路径上的同一道门：缺少 <code>docs/changes/BUG-021/00-intent.md</code> 的提交在到达分支之前就被拒绝。</sub>
</p>

## 五道质量门禁

穿过五道门禁的变更会积累完整产物链，从 `01-spec.md` 一直到 `09-changelog.md`：

```
[ 门禁 1: 需求/设计先行 ]   任何代码改动前必须先有需求与设计
        │
        ▼
[ 门禁 2: 测试脚本先行 ]   实现之前必须先有测试用例（TDD 红绿循环）
        │
        ▼
[ 门禁 3: 完工证据闭环 ]   必须有真实测试输出——严禁口头宣称"完成"
        │
        ▼
[ 门禁 4: 全链路追踪 ]     RTVM 必须闭环：REQ ↔ DES ↔ CODE ↔ TC
        │
        ▼
[ 门禁 5: 独立验证 ]       测试与审查由不同主体完成；高风险需人类授权
```

任一门禁未过的变更**一律禁止合入主分支**。

<p align="center">
  <img src="screenshots/change-artifacts-full-lifecycle.png" alt="一次变更的产物链：01-spec.md 到 09-changelog.md" width="520">
  <br>
  <sub>一次变更的完整产物链，<code>01-spec.md</code> → <code>09-changelog.md</code>。每阶段以提交一个受版本控制的产物收尾；下一阶段以读它开始——提交链本身就是审计链。</sub>
</p>

<p align="center">
  <img src="screenshots/ai-client-todo-with-traceability.png" alt="AI 客户端待办列表：先文档、后失败测试、再代码，每项带 REQ/DES/TC 编号" width="720">
  <br>
  <sub>同一链条在 AI 客户端内的样子：一张顺序被规范钉死的待办列表——先文档、再失败测试（红）、再代码——每一项都带 REQ/DES/TASK/TC/CHG 追踪编号。</sub>
</p>

### 证据与追踪实战

<p align="center">
  <img src="screenshots/rtvm-matrix-full-chain.png" alt="RTVM 矩阵：REQ、DES、TASK、TC 与验证列" width="620">
  <br>
  <sub>门禁 4 的 RTVM 矩阵：每个 REQ 行都必须落到 DES / TASK / TC 与验证证据——未闭环的行阻断合入。</sub>
</p>

<p align="center">
  <img src="screenshots/dod-item-by-item-checklist.png" alt="DoD 清单逐项勾选并内联引用各门禁证据" width="360">
  <br>
  <sub>门禁 3 / §2.16.3 实战：DoD 逐项闭环并内联引用各门禁证据。一句"已按规范完成"会被拒——清单才是交付物。</sub>
</p>

### 门禁 5 实战：独立性是派生出来的，不是声明出来的

<p align="center">
  <img src="screenshots/gate5-green-evidence-and-review-dispatch.png" alt="复跑全绿 PASS 24 / FAIL 0，EXIT=0，随后派发两个只读子任务" width="760">
  <br>
  <sub>门禁 5 从真实证据出发而非声明：复跑全绿（PASS 24 / FAIL 0，EXIT=0）加冻结基线哈希，然后派发两个<b>只读</b>子任务——一个测试复核、一个代码评审。</sub>
</p>

<p align="center">
  <img src="screenshots/independent-review-rejection.png" alt="独立测试复核与代码评审作为独立子任务派发，评审返回阻断项" width="480">
  <br>
  <sub>独立性是派生出来的，不是声明出来的：测试复核与代码评审各自独立子任务——且评审<b>退回</b>并带阻断发现，这正是系统在正常工作。</sub>
</p>

<p align="center">
  <img src="screenshots/gate5-independent-recheck.png" alt="新的独立评审者复核修复后的返工" width="760">
  <br>
  <sub>返工由<b>新的</b>独立评审者验证：作者不能自证，所以"修好了"必须由修复之后产生的证据支撑。</sub>
</p>

## 风险分级矩阵

| 等级 | 判定依据 | 独立性要求 | 跨平台要求 | 人类授权 |
|---|---|---|---|---|
| **L0** 极低 | 无逻辑变更（文档、注释、格式化） | 角色可合并 | 不要求 | 无 |
| **L1** 低 | 非核心模块、无对外接口 | 独立子任务 | 不要求 | 无 |
| **L2** 中（默认档） | 核心业务逻辑、P0/P1 优先级 | 独立执行主体 | 建议 | 无 |
| **L3** 高 | 敏感个人数据（PII）、认证授权、生产 DB、模型/Prompt、对外接口破坏性变更、P0 热修复 | 强制跨平台/跨模型 | **强制**（≥2 模型厂商） | **强制** |

## 治理细节

- **执行侧 token 纪律（v3.24.0/v3.25.0）**：下发的 `AGENTS.md` 内置「Agent 执行资源纪律」**八条**（管道过滤/一次 grep 合并/先定位后小窗/勘探下放只读子代理/无匹配≠通过/并行批量写/定向验证/有状态 mock 隔离）；规范 §2.9.6 会话与上下文纪律（单会话单主题，>50 轮或主题切换即 handoff）；§2.5 产物最小表达形态 + 单产物 ≤40 行软上限——目标：压 cache_read（= 上下文水位 × 轮数）。
- **同日变更批次（v3.18.0；v3.24.0 默认化）**：同一天的多个 **L0/L1** 变更**默认共用** `<docs>/changes/BATCH-YYYYMMDD/` 一个目录，而不是各建一个。放宽的只有目录——产物文件名一字不改，同批变更用 `## <变更号>` 小节锚点区分，批次变更集合从 `00-governance.json` 的权威名单读取（绝不从标题反推）。风险上限不放宽：**L2/L3 必须独立目录**，门禁按治理记录拒绝批次内的 L2/L3（以 `00-governance.json` 名单为准）。
- **缺陷六件套默认按天入批（v3.35.0；v3.36.0 扁平化）**：同日多个缺陷共落扁平 `docs/bugs/BATCH-YYYYMMDD/`——六件套文件名一字不改，用 `## BUG-xxx` 小节锚点区分，当天的追加/回填落在同一套文件里（逐缺陷子目录为历史合法形态，存量不回改）；追加式 `docs/bugfix-log.md` 索引（每缺陷一行、带日期）保持天级检索层；缺陷的**变更轨入口**（`BUG-*`）仍可像普通变更一样入批。
- **方法论选型（M0–M3）**：`docs/METHODOLOGY.md` 是哪一级允许哪些方法论的唯一权威；`docs/methodologies/development.md`、`docs/methodologies/data-structures.md`、`docs/methodologies/state-trigger-audit.md`、`docs/methodologies/expert-capabilities.md` 与 `docs/methodologies/project-masters.md` 提供逐条工程依据（SOLID/DRY 适用性、弱类型禁令、隐式状态/触发链路三向遍历、专家理论工具箱）。
- **自进化**：从本 Skill 派生（声明 `derived_from: dev-standards-bootstrap`）的 Skill 独立演进，安装/升级的每条写入路径都会跳过它们；`--force` 也不越过。`bash scripts/bootstrap.sh --derived-report` 可列出派生清单。
- **跨文档一致性审计**：`bash tests/audit-docs-consistency.sh`（G1 版本链 / G2 编号连续 / G3 归档同源 / G4 缺陷双登记互证 / G5 RTVM 回填 / G6 必填节 / G7 批次自洽 / G8 缺陷六件套存在性 / G9 项目总册存在+自证+回填清单+功能目录表外 reviews/ 拦截 / G10 废弃条款 sweep——废止标记须带被替代版本指向（v3.41.0） / A 组盖章互证）可在 CI 或本地运行；失败项即回填清单。

## 仓库结构

```
dev-standards-bootstrap/
├── SKILL.md                                # Skill 清单（触发、执行步骤、红线）
├── README.md                               # 英文文档
├── README.zh-CN.md                         # 中文文档（本文件）
├── LICENSE                                 # MIT 许可证
├── MAINTAINER.md                           # 维护者须知（不随 Skill 分发）：文件角色 / 变更联动表 / 两道自测试与顺序 / 版本载体 / 逐版本升级动作
├── .github/
│   └── workflows/ci.yml                    # 本仓自身的 CI（非模板下发）：每次 PR 与 push main 跑两套自测试
├── .claude-plugin/
│   ├── plugin.json                         # Claude Code 插件清单——本仓库即插件（根级 SKILL.md 被发现）
│   └── marketplace.json                    # 市场条目：claude plugin marketplace add geekma/dev-standards-bootstrap
├── scripts/
│   ├── bootstrap.sh                        # 清单驱动安装器（不下发）：按层复制 resources/ 到目标仓，幂等、防覆盖
│   ├── install.sh                          # 一键安装器（不下发）：克隆 + 安装/升级一步完成
│   └── update-assertion-count.sh           # 源层专用（不下发）：再生成 README 断言计数声称 + 审计执行数基线
├── screenshots/                            # README 截图（动机、门禁拦截、产物、门禁5评审）
├── tests/
│   ├── run-tests.sh                        # 治理模板 golden case 回归套件（含门禁与安装器；复制到目标 tests/ ——目标仓自适应：不下发/未装层的用例自动跳过）
│   ├── audit-standards-src.sh              # 源层专用（不下发）：审计规范文本自身——版本链 / 关键词矩阵 / 清单唯一性 / 编号 / 防恒真 grep
│   └── .audit-baseline                     # 源层专用（不下发）：审计执行断言数的入库基线（断言 A10 对漂移判红）
└── resources/
    ├── AGENTS.md                           # AI Agent 入口（复制到目标仓根）
    ├── CLAUSE_REGISTRY.md                  # 条款注册表：规范条款机器索引（Rxx 行号 ID + 文件名::锚点 + 类型封闭词表）；DS 仍是正文唯一权威；供阅读包生成器消费（v3.46.0）
    ├── DEVELOPMENT_STANDARDS.md             # 完整规范文档 v3.49.0（复制到 docs/）
    ├── STANDARDS_CHANGELOG.md              # 规范升级历史（§2.14 升级日志唯一落点，v3.8.0 起；复制到 docs/）
    ├── METHODOLOGY.md                       # 方法论选型指南：M0-M3 分级 + 阶段×方法论×适用/不适用表（复制到 docs/）
    ├── methodologies/
    │   ├── development.md                   # 代码规范：SOLID/DRY/KISS/YAGNI 适用与豁免 + 7 个工程维度
    │   ├── data-structures.md               # 数据结构规范：六类模型 + 弱类型禁令 + LLM 输入输出专项
    │   ├── state-trigger-audit.md           # 状态/触发链路审计：6 条教训 + 6 步清单 + 3 个反模式（v3.4.0）
    │   ├── expert-capabilities.md           # 专家能力卡：9 核心 + 3 条件命中专家（理论工具箱/广度/经验/自适应）（v3.34.0）
    │   └── project-masters.md               # 项目级总册细节层：12 册清单/必含章节/回填注记语义（v3.35.0）
    └── templates/
        ├── docs-readme.md                  # 一页文档地图（v3.37.0）：五层职责+更新时机（→ <docs>/README.md）
        ├── project                           # 项目级总册（v3.35.0）：SDLC 12 册 P00–P11 + 评审记录模板（→ docs/templates/project/）
        ├── entry                             # 变更入口骨架（v3.43.0）：begin 必检七件模板（→ docs/templates/entry/）
        ├── new-change.sh                   # 变更入口脚手架（v3.43.0）：专用目录/当日批次自动判定（→ scripts/new-change）
        ├── CLAUDE.md                       # Claude Code 一行导入
        ├── PULL_REQUEST_TEMPLATE.md        # 带门禁自检的 GitHub PR 模板
        ├── check-standards-compliance.sh   # CI 合规检查脚本
        ├── agent-gate.sh                   # pre-write / commit-msg / Git / CI 共享校验器（+ metrics、+ 变更批次解析）
        ├── uninstall-standards.sh          # 一键卸载：三层分类 + 标记核验删除 + 共享资产备份移动（v3.43.0）
        ├── intent.md                       # 每次变更 00-intent.md 的管线入口模板（不下发——由 Agent 按变更生成）
        ├── coding-record.md                # docs/changes/<CHG>/04.5-coding-record.md 的编码记录模板（不下发——由 Agent 按变更生成）
        ├── stamp-provenance.sh             # 溯源盖章脚本：从运行环境读作者/主机/时间（v3.17.0；批感知 v3.18.0；--all v3.22.0）
        ├── bugfix-log.md                   # 仓库级缺陷修复索引模板（复制到 docs/bugfix-log.md）
        ├── bug-diagnosis.md、bug-impact.md、bug-test-plan.md、bug-matrix.md、bug-config.md、bug-tasks.md  # 缺陷文档组六件套（→ docs/bugs/_templates/）
        ├── 06.5-deployment-config.md       # 部署/配置/DB 记录模板（→ docs/；未命中须显式声明"未命中，不适用"）
        ├── 06-delivery-summary.md          # 交付总结 + FU 台账模板（→ docs/；§2.5 阶段 9.5 四个必含节）
        ├── audit-docs-consistency.sh       # 跨文档一致性审计：版本链 / 编号连续 / 清单同步 / 缺陷双登记 / RTVM 回填 / 变更批次自洽（复制到 tests/）
        ├── governance-state.json           # 每次变更 00-governance.json 的模板（不下发——由 Agent 按变更生成）
        ├── agent-governance.yml            # 团队可复核的治理配置记录（复制到 .agent-governance.yml）
        ├── pre-commit、pre-push、commit-msg  # Git Hook 模板（commit-msg：归因闸门）
        ├── install-hook-adapter.sh         # 探测本地 AI 客户端并自适应接线会话内执法（v3.34.0）
        ├── session-gate.sh                  # 会话内执法：start=审计亮红灯+缺陷信号交互三选项，idle=stop 等价检查
        ├── bug-autointent.sh               # 缺陷发现入口：信号 -> 完整六件套骨架 + 指纹频控（v3.43.0）
        ├── generate-reading-pack.sh        # 阅读包生成器：条款注册表 -> 按类型切片，锚点 fail-closed 防漂移（v3.46.0）
        ├── github-agent-governance.yml     # 必需检查 workflow 模板
        ├── github-artifact-pipeline.yml    # 产物管线：spec 合入 -> 02/03/03.5/04 骨架 PR；changelog 合入 -> 发布检查单 issue
        ├── github-incident-to-intent.yml   # 事故回路：告警派发 -> BUG-<ts> 意图骨架 PR
        └── github-regression-to-bug.yml    # 回归回路：主干测试红 -> 六件套缺陷骨架 PR（频控，v3.43.0）
```

## FAQ

**会改我的代码吗？** 不会。整套包是围绕你工作流的文档、模板、Hook 与校验器。门禁只会**拒绝**提交，从不编辑文件。

**如何卸载？** 跑随 `--guard` 附带的一键卸载器：`scripts/uninstall-standards`（`--dry-run` 预览、`--force` 连共享资产一起处理）。它**直接删除**安装器运行时件（gate 脚本、hooksPath、`.agent-state`）；模板件只在安装器标记完好时删除（被改动的保留并报告）；**共享知识资产默认保留**——`AGENTS.md`、`CLAUDE.md`、`docs/` 下的治理历史（`changes/`、`bugs/`、项目总册）与合并型客户端接线（`.claude/` 等），`--force` 也只是**备份移动**到 `.uninstall-backup-<时间戳>/`，永不 `rm`。`core.hooksPath` 指向托管钩子目录时自动解除。随时可用 `bootstrap --core/--guard` 重装。

**会把数据发到服务器吗？** 不会。门禁、溯源盖章与审计都是零依赖 shell 脚本，只读你的文件系统与 git 元数据。`install.sh` 仅克隆本公开仓库。

**同一天的多个低风险变更能共用一套文档吗？** 能——见[治理细节](#治理细节)：同日 L0/L1 变更可并入 `BATCH-YYYYMMDD/`（文件名不变、`## <变更号>` 锚点区分）。缺陷六件套默认并入当日扁平批次（v3.35.0/3.36.0）；逐缺陷子目录为历史合法形态。

**这些文件是谁生成的——能回溯吗？** 每次变更的编码记录（用 `stamp-provenance.sh --all` 则是活跃变更的全部产物）都带溯源块：作者、提交者、提交哈希、主机、平台、UTC 时间，全部从运行环境读出。

**GitHub 之外能用吗？** 强制语义平台无关（Git Hook + 任意 CI）。四个随包 workflow 是 GitHub Actions 参考实现；§2.17.1 定义的是语义而非平台。

## 参与贡献

欢迎贡献！请遵循本仓库定义的规范：文档先行（门禁 1）、测试先行（门禁 2）、真实测试输出（门禁 3）、RTVM 闭环（门禁 4）、独立评审（门禁 5）。PR 请使用 [PR 模板](resources/templates/PULL_REQUEST_TEMPLATE.md)并完成全部门禁自检。维护者请先读 [MAINTAINER.md](MAINTAINER.md)；版本条目写入 [`resources/STANDARDS_CHANGELOG.md`](resources/STANDARDS_CHANGELOG.md)（一版本一行）。

## 许可证

本项目基于 [MIT License](LICENSE) 开源。

---

<div align="center">

**规范版本：** v3.49.0 | **最后更新：** 2026-09-24 | **维护者：** [geekma](https://x.com/geekma) | **邮箱：** geekma@gmail.com

[报告缺陷](../../issues) | [功能建议](../../issues) | [阅读规范](resources/DEVELOPMENT_STANDARDS.md) | [更新日志](resources/STANDARDS_CHANGELOG.md)

</div>
