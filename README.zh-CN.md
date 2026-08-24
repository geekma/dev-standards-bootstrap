<!-- markdownlint-disable MD033 MD041 MD013 -->

<div align="center">

# dev-standards-bootstrap

### 一键为任意代码仓库注入 AI Agent 开发治理与质量门禁体系

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![规范版本](https://img.shields.io/badge/规范版本-v2.16.0-green.svg)](resources/DEVELOPMENT_STANDARDS.md)
[![AGENTS.md](https://img.shields.io/badge/入口文件-AGENTS.md-orange.svg)](resources/AGENTS.md)
[![欢迎 PR](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](../../pulls)

[English](README.md) | [中文](README.zh-CN.md)

</div>

---

## 项目简介

**dev-standards-bootstrap** 是一个可复用的 AI Agent Skill，能够用一条指令将一套完整的、经过实战打磨的**软件开发与变更治理规范体系**注入到任意代码仓库中。

它只在目标仓库中写入**一个内容文件**（`AGENTS.md`）——所有主流 AI 编程工具（Claude Code、Cursor、Codex、Windsurf、Gemini CLI、Qoder、Trae、OpenCode）在 2026 年已普遍原生支持读取 `AGENTS.md`（Linux 基金会 Agentic AI Foundation 治理的开放标准）。无需为每个工具单独配置，无需复制多份文件，无需额外维护成本。

### 为什么需要它

当多个 AI Agent 同时在同一个代码仓库中工作时，如果没有治理机制，混乱不可避免：

- Agent 跳过文档直接改代码
- 测试是事后补的——或者根本没有
- 需求、设计、代码、测试之间没有可追溯性
- 同一个 Agent 自己写代码、自己测试、自己审批
- 用"总结"代替逐项核对，悄悄跳过步骤

本 Skill 通过安装**五道强制门禁**、**风险分级矩阵**、**Agent 角色独立性框架**和**防遗漏防跳过执行规则**，彻底解决上述问题——一次安装，永久生效。

---

## 核心特性

| 特性 | 说明 |
|---|---|
| **五道质量门禁** | 文档先行、测试先行、完工证据、全链路追踪矩阵、独立验证——不可绕过 |
| **风险分级（L0–L3）** | 决定 Agent 独立性要求和跨平台/跨模型厂商验证规则 |
| **Agent 角色独立性** | 编排者、需求、架构/计划、开发、测试、Review 角色必须是不同的执行主体 |
| **四维追踪矩阵（RTVM）** | 需求（REQ）-> 设计（DES）-> 任务（TASK）-> 测试用例（TC）全链路追溯 |
| **10 阶段开发生命周期** | 从需求定义到记忆沉淀与持续改进 |
| **AI 防漏防跳过规则** | 专门约束 AI Agent 静默跳步、用摘要代替逐项清单、提前标记完成等行为 |
| **CI/PR 工程化兜底** | GitHub PR 模板和 Bash 合规检查脚本，CI 流水线自动拦截 |
| **专项规范** | 覆盖部署、配置/数据库变更、AI/LLM 链路、测试数据隔离、紧急热修复、发布上线、监控告警、供应链依赖管理 |

---

## 支持的 AI 编程工具

本 Skill 基于各工具原生支持的 `AGENTS.md` 开放标准，无需额外配置：

| 工具 | 状态 |
|---|---|
| Claude Code | 原生读取 `AGENTS.md` |
| Cursor | 原生读取 `AGENTS.md` |
| Codex (OpenAI) | 原生读取 `AGENTS.md` |
| Windsurf | 原生读取 `AGENTS.md` |
| Gemini CLI | 原生读取 `AGENTS.md` |
| Qoder | 原生读取 `AGENTS.md` |
| Trae | 原生读取 `AGENTS.md` |
| OpenCode | 原生读取 `AGENTS.md` |

> 无需为每个工具单独写配置文件。一个 `AGENTS.md` 入口文件即可治理所有工具。

---

## 快速开始

### 安装 Skill

将仓库克隆到你的个人或组织 Skill 目录中：

```bash
git clone https://github.com/geekma/dev-standards-bootstrap.git
```

或者作为子模块添加到你的 Skill 集合中：

```bash
git submodule add https://github.com/geekma/dev-standards-bootstrap.git
```

### 初始化仓库

在任意目标仓库中打开你的 AI 编程工具（如 Claude Code），输入：

> "用 dev-standards-bootstrap 初始化这个仓库。"

Skill 将自动执行：

1. 检测已有文件，避免覆盖（先展示差异再询问）
2. 将 `AGENTS.md` 写入仓库根目录
3. 将 `DEVELOPMENT_STANDARDS.md` 写入 `docs/` 目录
4. 可选：为 Claude Code 添加一行导入文件（`CLAUDE.md`）
5. 可选：添加 PR 模板和 CI 合规检查脚本
6. 可选：在 `docs/<feature>/` 下创建第一个功能目录骨架

---

## 仓库结构

```ini
dev-standards-bootstrap/
├── SKILL.md                                # Skill 清单（触发条件、执行步骤、红线）
├── README.md                               # 英文文档
├── README.zh-CN.md                         # 中文文档（本文件）
├── LICENSE                                 # MIT 开源协议
└── resources/
    ├── AGENTS.md                           # AI Agent 入口文件（复制到目标仓库根目录）
    ├── DEVELOPMENT_STANDARDS.md             # 完整规范文档 v2.16.0（复制到 docs/）
    └── templates/
        ├── CLAUDE.md                       # Claude Code 一行导入文件
        ├── PULL_REQUEST_TEMPLATE.md        # GitHub PR 模板（含门禁自查）
        └── check-standards-compliance.sh   # CI 合规检查脚本
```

---

## 五道质量门禁

```ini
[ 门禁 1：文档先行 ]      需求/设计必须先于代码变更存在
        │
        ▼
[ 门禁 2：测试先行 ]      测试用例（TDD 红绿循环）必须先于实现代码
        │
        ▼
[ 门禁 3：完工证据 ]      必须有真实测试输出——禁止口头声明"已完成"
        │
        ▼
[ 门禁 4：追踪矩阵 ]      RTVM 必须闭环：REQ ↔ DES ↔ CODE ↔ TC
        │
        ▼
[ 门禁 5：独立验证 ]      测试与审查由不同角色完成；高风险需人类授权
```

任何未通过门禁的变更，**一律禁止合入主分支**。

---

## 风险分级矩阵

| 等级 | 判定依据 | 角色独立性 | 跨平台要求 | 人类审批 |
|---|---|---|---|---|
| **L0** 极低 | 无逻辑变更（文档、注释、格式化） | 角色可合并 | 不要求 | 不需要 |
| **L1** 低 | 非核心模块，不涉及对外接口 | 独立子任务 | 不要求 | 不需要 |
| **L2** 中（默认） | 核心业务逻辑，P0/P1 优先级 | 独立执行主体 | 建议 | 不需要 |
| **L3** 高 | 患者 PII、认证授权、生产 DB、模型/Prompt、对外接口破坏性变更、P0 热修复 | 强制跨平台/跨模型 | **强制**（≥2 个模型厂商） | **强制** |

---

## 贡献指南

欢迎贡献代码！提交变更时请遵守本仓库定义的规范：

1. 确保文档先于代码变更更新（门禁 1）
2. 测试先行（门禁 2）
3. 提供真实测试输出（门禁 3）
4. 闭环追踪矩阵 RTVM（门禁 4）
5. 确保独立审查（门禁 5）

Pull Request 请使用 [PR 模板](resources/templates/PULL_REQUEST_TEMPLATE.md) 并完成全部门禁自查。

---

## 开源协议

本项目基于 [MIT 协议](LICENSE) 开源。

---

<div align="center">

**规范版本：** v2.16.0 | **更新时间：** 2026-08-24 | **维护者：** [geekma](https://x.com/geekma) | **邮箱：** geekma@gmail.com

[报告 Bug](../../issues) | [功能需求](../../issues) | [阅读规范全文](resources/DEVELOPMENT_STANDARDS.md)

</div>
