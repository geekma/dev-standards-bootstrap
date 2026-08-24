---
name: dev-standards-bootstrap
description: 在任意代码仓库中一键初始化"全局软件开发与变更规范"体系（AGENTS.md 唯一入口 + 五道门禁 + 风险分级 + Agent 独立性矩阵 + PR/CI 兜底）。当用户说"给这个项目接入开发规范"、"初始化 dev standards"、"这个仓库还没有 AGENTS.md，帮我加上"、或新建项目/新仓库首次配置时使用。
---

# dev-standards-bootstrap

## 这个 Skill 做什么

把一套完整的、已经打磨过的团队开发治理规范（文档先行、测试先行、五道门禁、四维追踪矩阵、Agent 角色独立性、风险分级、防遗漏防跳过执行规则）**一次性**接入任意代码仓库，且只在仓库里落一个内容文件（`AGENTS.md`），不需要为 Cursor / Codex / Windsurf / Gemini CLI / Qoder / Trae / OpenCode 等每个工具分别写一份——这些工具在 2026 年已经普遍原生支持读取 `AGENTS.md`（Linux 基金会 Agentic AI Foundation 治理的开放标准）。

本 Skill 本身是可复用的：装一次（放在你的个人/组织 Skill 目录），以后每个新项目只需要跟 Claude 说一句"用 dev-standards-bootstrap 初始化这个仓库"，不必再手写或复制粘贴任何文件。

## 何时触发

- 用户明确要求初始化/接入开发规范、AGENTS.md、变更管理流程
- 新建仓库、新项目第一次做工程化配置时
- 用户提到"这个仓库还没有门禁/追踪矩阵/Agent 分工机制"

## 执行步骤

1. **确认目标仓库根目录**（询问用户，或使用当前工作目录）。
2. **检测已有文件**，避免覆盖：
   - 若目标仓库已存在 `AGENTS.md`，不要直接覆盖——展示 diff，询问用户是合并、追加新增章节，还是保留原文件仅在末尾追加一行"另参见 docs/DEVELOPMENT_STANDARDS.md"。
   - 若已存在 `docs/DEVELOPMENT_STANDARDS.md`，同样先展示版本号差异（本 Skill 携带的版本见文件页脚），询问是否要升级覆盖。
3. **写入核心文件**（无冲突时直接写入）：
   - 复制 `resources/AGENTS.md` → 目标仓库根目录 `AGENTS.md`
   - 复制 `resources/DEVELOPMENT_STANDARDS.md` → 目标仓库 `docs/DEVELOPMENT_STANDARDS.md`
4. **询问是否需要可选增强**（不要求默认全装，分别询问）：
   - 是否要为 Claude Code 加一个一行导入文件？→ 复制 `resources/templates/CLAUDE.md`（内容仅一行 `@AGENTS.md`，不重复内容，只是让 Claude Code 也能拿到其专属的 hooks/subagent 富能力）到仓库根目录。
   - 是否要工程化兜底（不完全依赖 AI 自觉遵守）？→
     - 复制 `resources/templates/PULL_REQUEST_TEMPLATE.md` 到 `.github/PULL_REQUEST_TEMPLATE.md`
     - 复制 `resources/templates/check-standards-compliance.sh` 到 `scripts/check-standards-compliance.sh` 并 `chmod +x`，提示用户接入 CI（给出一个最小 GitHub Actions 示例：在 PR 触发时执行该脚本）。
5. **初始化第一个功能目录骨架**（可选，询问用户是否现在就要开始第一个变更）：
   - 若用户已有具体功能要开发，按 `DEVELOPMENT_STANDARDS.md` §1.1 在 `docs/<feature>/` 下创建空的 `01-spec.md` 骨架（仅标题与章节占位，不臆造需求内容）。
6. **完成后回执**：列出本次实际写入/跳过的文件清单，并提醒用户："以后任何工具打开这个仓库，都会自动读取 AGENTS.md；不需要再为新工具单独配置。"

## 红线

- 不覆盖用户已有的、内容不同的 `AGENTS.md` 或 `DEVELOPMENT_STANDARDS.md`，一律先展示差异再询问。
- 不臆造项目特定内容（技术栈、构建命令等）——`resources/AGENTS.md` 是通用治理规范，不含具体项目的构建/测试命令；如需补充这类项目专属信息，在写入后追加提示，请用户自行在 `AGENTS.md` 末尾补充"项目速览"小节（Dev environment / Build & Test 命令），本 Skill 不代为编造。
- 不在多个工具专属文件里复制正文内容；除 §步骤4 明确列出的一行导入文件外，不再新增任何其他工具的指针文件。

## 版本同步

`resources/DEVELOPMENT_STANDARDS.md` 与 `resources/AGENTS.md` 应随规范正文迭代更新；每次升级本 Skill 内的规范版本后，已经接入过的项目**不会自动更新**，需要用户再次调用本 Skill 走"检测已有文件 → 展示版本差异 → 询问是否升级"的流程。
