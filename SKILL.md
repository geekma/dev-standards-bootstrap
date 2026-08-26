---
name: dev-standards-bootstrap
description: 在任意代码仓库中一键初始化"全局软件开发与变更规范"体系（AGENTS.md 唯一入口 + 五道门禁 + 风险分级 + Agent 独立性矩阵 + PR/CI 兜底）。当用户说"给这个项目接入开发规范"、"初始化 dev standards"、"这个仓库还没有 AGENTS.md，帮我加上"、或新建项目/新仓库首次配置时使用。
---

# dev-standards-bootstrap

## 这个 Skill 做什么

把一套完整的团队开发治理规范（文档先行、测试先行、五道门禁、四维追踪矩阵、Agent 角色独立性、风险分级、防遗漏防跳过执行规则）**一次性**接入任意代码仓库。`AGENTS.md` 负责向 Agent 提供统一上下文；可选的 `agent-gate` 负责在支持 Hook 的客户端写入前阻断，并由 Git/CI 对所有客户端兜底。

本 Skill 本身是可复用的：装一次（放在你的个人/组织 Skill 目录），以后每个新项目只需要跟 Claude 说一句"用 dev-standards-bootstrap 初始化这个仓库"，不必再手写或复制粘贴任何文件。

## 何时触发

- 用户明确要求初始化/接入开发规范、AGENTS.md、变更管理流程
- 新建仓库、新项目第一次做工程化配置时
- 用户提到"这个仓库还没有门禁/追踪矩阵/Agent 分工机制"

## 执行步骤

1. **确认目标仓库根目录**（询问用户，或使用当前工作目录）。
2. **检测已有文件**，避免覆盖：
   - 若目标仓库已存在 `AGENTS.md`，不要直接覆盖--展示 diff，询问用户是合并、追加新增章节，还是保留原文件仅在末尾追加一行"另参见 docs/DEVELOPMENT_STANDARDS.md"。
   - 若已存在 `docs/DEVELOPMENT_STANDARDS.md`，同样先展示版本号差异（本 Skill 携带的版本见文件页脚），询问是否要升级覆盖。
3. **写入核心文件**（无冲突时直接写入）：
   - 复制 `resources/AGENTS.md` -> 目标仓库根目录 `AGENTS.md`
   - 复制 `resources/DEVELOPMENT_STANDARDS.md` -> 目标仓库 `docs/DEVELOPMENT_STANDARDS.md`
4. **询问是否需要可选增强**（不要求默认全装，分别询问）：
   - 是否要为 Claude Code 加一个一行导入文件？-> 复制 `resources/templates/CLAUDE.md`（内容仅一行 `@AGENTS.md`，不重复内容，只是让 Claude Code 也能拿到其专属的 hooks/subagent 富能力）到仓库根目录。
   - 是否要工程化兜底（不完全依赖 AI 自觉遵守）？->
     - 复制 `resources/templates/PULL_REQUEST_TEMPLATE.md` 到 `.github/PULL_REQUEST_TEMPLATE.md`
     - 复制 `resources/templates/check-standards-compliance.sh` 到 `scripts/check-standards-compliance.sh` 并 `chmod +x`，提示用户接入 CI（给出一个最小 GitHub Actions 示例：在 PR 触发时执行该脚本）。
   - 是否要安装**强制执行包**？-> 先展示将写入的文件并确认，再复制下列文件：
     - `resources/templates/agent-gate.sh` -> `scripts/agent-gate`，并 `chmod +x`
     - `resources/templates/governance-state.json` -> `docs/changes/<变更号>/00-governance.json`；必须由用户/编排者填写真实风险等级与不同执行主体，不能保留模板占位符。
     - `resources/templates/intent.md` -> `docs/changes/<变更号>/00-intent.md`（变更管线入口：问题/预期结果/约束，规范 §2.17；同样只给骨架，不代填内容）。
     - `resources/templates/pre-commit`、`pre-push` -> `.githooks/`，并 `chmod +x`；指导执行 `git config core.hooksPath .githooks`
     - `resources/templates/github-agent-governance.yml` -> `.github/workflows/agent-governance.yml`
     - 复制 `resources/templates/install-hook-adapter.sh` -> `scripts/install-hook-adapter` 并 `chmod +x`，然后执行它：自动检测当前客户端（`CLAUDECODE` / `CURSOR_AGENT` / `GEMINI_CLI` 环境变量）或接受 `claude|cursor|gemini` 参数，生成对应 Hook 配置（Claude Code -> `.claude/settings.json`，Cursor -> `.cursor/hooks.json`，Gemini CLI -> `.gemini/settings.json`）。目标文件已存在且内容不同时，脚本会展示 diff 并拒绝覆盖（除非 `--force`）。未列出的客户端（Codex、Windsurf、Qoder、Trae、OpenCode 等）没有可生成的 Hook schema，不臆造配置；它们的强制执行由 Git Hook 与 CI workflow 兜底--二者校验仓库而非编辑器。
     - `resources/templates/agent-governance.yml` -> `.agent-governance.yml`，作为团队可审阅的配置记录；不臆造项目测试命令，要求用户在 GitHub Actions repository variable 中设置真实的 `AGENT_GUARD_VERIFY_COMMAND`。
     - 明确说明：本地 Hook 可被直接编辑器、shell 或禁用 hooks 绕过；必须在 Git 托管平台将 `agent-governance` 与项目测试设为 Required Status Check、禁止直接推送受保护分支，并为 L3 配置 CODEOWNERS/人工审批。
   - 是否要启用**管线自动化**（规范 §2.17，托管平台层，与客户端无关）？->
     - `resources/templates/github-artifact-pipeline.yml` -> `.github/workflows/artifact-pipeline.yml`（传动机制 §2.17.1：`01-spec.md` 合入自动派发 03/04 骨架 PR、`09-changelog.md` 合入自动开发布检查单 issue；骨架只含待填注释，workflow 自主权上限 A2）。
     - `resources/templates/github-incident-to-intent.yml` -> `.github/workflows/incident-to-intent.yml`（事故重入 §2.17.2：监控告警经 `repository_dispatch` 事件自动生成 `BUG-<时间戳>` 的 `00-intent.md` 骨架 PR；给出监控系统 curl 接入示例）。
     - 复制本仓库 `tests/run-tests.sh` -> 目标仓库 `tests/run-tests.sh`（治理配置 golden-case 自测试 §2.17.4：修改 `agent-gate`/hooks/workflow 前必须先跑通，零依赖 bash+git）。
     - GitLab 等平台：按两个 workflow 文件头部注释中的等价实现思路（CI 触发规则 + 平台 API）落地，语义以规范 §2.17 为准。
5. **初始化第一个功能目录骨架**（可选，询问用户是否现在就要开始第一个变更）：
   - 若用户已有具体功能要开发，按 `DEVELOPMENT_STANDARDS.md` §1.1 在 `docs/<feature>/` 下创建空的 `01-spec.md` 骨架（仅标题与章节占位，不臆造需求内容）；变更管线入口 `00-intent.md`（§2.17）同样只创建骨架。
6. **完成后回执**：列出本次实际写入/跳过的文件清单、启用的客户端适配器和仍需用户在托管平台配置的 Required Checks。不得声称“所有工具均在改前强制受控”；应说明 `AGENTS.md` 是上下文层，受保护分支的 CI 才是跨客户端的最终信任边界。若安装了管线自动化，提示 `scripts/agent-gate metrics` 可输出管线度量（§2.17.5），仅作观察不替代 DoD。

## 红线

- 不覆盖用户已有的、内容不同的 `AGENTS.md` 或 `DEVELOPMENT_STANDARDS.md`，一律先展示差异再询问。
- 不臆造项目特定内容（技术栈、构建命令等）--`resources/AGENTS.md` 是通用治理规范，不含具体项目的构建/测试命令；如需补充这类项目专属信息，在写入后追加提示，请用户自行在 `AGENTS.md` 末尾补充"项目速览"小节（Dev environment / Build & Test 命令），本 Skill 不代为编造。
- 不在多个工具专属文件里复制规范正文；工具专属文件只允许引用同一 `scripts/agent-gate`，不得分叉校验逻辑。

## 版本同步

`resources/DEVELOPMENT_STANDARDS.md` 与 `resources/AGENTS.md` 应随规范正文迭代更新（当前携带版本 v2.18.0，见规范页脚）；`resources/templates/agent-gate.sh` 与 `tests/run-tests.sh` 必须同步演进--改脚本必须先跑通 `tests/run-tests.sh` 再发布（§2.17.4）。每次升级本 Skill 内的规范版本后，已经接入过的项目**不会自动更新**，需要用户再次调用本 Skill 走"检测已有文件 -> 展示版本差异 -> 询问是否升级"的流程。
