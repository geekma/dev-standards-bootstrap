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
3. **写入核心文件**（推荐用安装器，无冲突时直接写入）：
   - 从本 Skill 目录执行 `bash scripts/bootstrap.sh --all <目标仓库>`（**默认全量自动注入**——用户说"初始化"即一条完成；用户明确要最小化时才按层选择）：自动复制 `AGENTS.md`、`DEVELOPMENT_STANDARDS.md`、`STANDARDS_CHANGELOG.md`（v3.8.0 起规范升级日志唯一落点，随规范分发至 `docs/`）、`METHODOLOGY.md`、`methodologies/`（`development.md` + `data-structures.md` + `state-trigger-audit.md`）、`bugfix-log.md`、`docs/bugs/_templates/` 缺陷六件套、`docs/06.5-deployment-config.md` 与 `docs/06-delivery-summary.md`（**八类最低文档集里原先既无模板也无门禁的两类**，v3.7.0 补入：未命中时也必须落文件并显式声明"未命中，不适用"）、`tests/audit-docs-consistency.sh`（**通用层跨文档一致性机器审计**：G1 版本链 / G2 编号连续无跳号 / G3 归档清单与 §3 同源 / G4 bugfix 双登记互证+陈旧占位检测 / G5 RTVM 短引用↔01.5 矩阵回填一致 / G6 最新 CHG §4 必填节完整；文档变更后或接入 CI 运行，失败项即 §2.14 存量回填清单）。安装器幂等、失败即拒绝（fail-closed），目标已有不同内容时展示 diff 并要求 `--force` 才覆盖——这是"检测已有文件、绝不静默覆盖"红线的机器化兜底。
   - 若目标仓库已存在 `AGENTS.md` / `DEVELOPMENT_STANDARDS.md`，仍先展示版本差异，询问用户是合并、追加新增章节，还是保留原文件仅追加引用行。
   - **变更起编时**（非安装期）再从模板生成 per-change 产物：`resources/templates/intent.md` → `docs/changes/<变更号>/00-intent.md`、`governance-state.json` → `00-governance.json`（须由用户/编排者填真实风险等级与执行主体）、`coding-record.md` → `04.5-coding-record.md`（v3.7.0 编码记录）。
4. **自动注入说明**（`--all` 已包含全部层并自动接线——hooksPath/客户端适配器/验证命令探测，零手工；以下分层 flag 语义仅供用户要求最小化安装或排障时使用）：
   - `--claude`：复制 `CLAUDE.md`（仅一行 `@AGENTS.md`，不重复内容）到仓库根目录，让 Claude Code 拿到其 hooks/subagent 富能力。
   - `--ci`（工程化兜底，不完全依赖 AI 自觉）：复制 `PULL_REQUEST_TEMPLATE.md` → `.github/`，`check-standards-compliance.sh` → `scripts/` 并 `chmod +x`（`--guard` 层已含完整 workflow；本层为不装 --guard 时的最小 CI 兜底）。
   - `--guard`（**强制执行包**）：先展示将写入的文件再确认，复制 `agent-gate.sh` → `scripts/agent-gate`、`.githooks/`（`pre-commit`/`pre-push`/`commit-msg` 归因闸门，v3.5.0）、`github-agent-governance.yml` → `.github/workflows/agent-governance.yml`、`install-hook-adapter.sh` → `scripts/install-hook-adapter`、`agent-governance.yml` → `.agent-governance.yml`；并复制 `tests/run-tests.sh`（**治理自测试随强制包**，§2.17.4：改 `agent-gate`/hooks/workflow 前必须先跑通，零依赖 bash+git；**副本为双布局自适应**——目标仓库运行自动回退源路径、Skill 仓库专属用例自动跳过，已装层全部回归）。bootstrap 已自动运行 `scripts/install-hook-adapter`（自动检测 `CLAUDECODE`/`CURSOR_AGENT`/`GEMINI_CLI` 或 `claude|cursor|gemini` 参数；未列出的客户端不臆造配置，由 Git Hook + CI 兜底——二者校验仓库而非编辑器）并自动配置 `git config core.hooksPath .githooks`；仍需说明：本地 Hook 可被绕过、必须在托管平台把 `agent-governance` 与项目测试设为 Required Check、禁止直推受保护分支、为 L3 配置 CODEOWNERS/人工审批。
   - `--pipeline`（**管线自动化**，规范 §2.17，托管平台层）：复制 `github-artifact-pipeline.yml`（传动 §2.17.1：`01-spec.md` 合入自动派发 02/03/03.5/04 骨架 PR、`09-changelog.md` 合入自动开发布检查单 issue，骨架只含待填注释，自主权上限 A2）与 `github-incident-to-intent.yml`（事故重入 §2.17.2：告警经 `repository_dispatch` 自动生成 `BUG-<时间戳>` 的 `00-intent.md` 骨架 PR，含 curl 接入示例）到 `.github/workflows/`；GitLab 等平台按两个 workflow 头部注释中的等价实现思路（CI 触发规则 + 平台 API）落地，语义以规范 §2.17 为准。
4.5 **Skill 版本更新场景**（用户说"更新/升级 dev-standards-bootstrap"，或检测到目标仓 `docs/DEVELOPMENT_STANDARDS.md` 页脚版本低于本 Skill 携带版本）：
   - 先确认目标仓库工作区干净：**有未提交改动时 `--upgrade` 直接拒绝**（--force 可强制；git history 即升级备份）。
   - 执行 `bash scripts/bootstrap.sh --upgrade <目标仓库>`：治理自有文件（规范/方法论/模板/脚本/hooks/workflows/tests）更新到携带版本并打印版本迁移；**live/用户文件不动**（`docs/bugfix-log.md`、`docs/06-delivery-summary.md`、`docs/06.5-deployment-config.md` 累积记录与 `.agent-governance.yml` 用户配置原样保留）；自动接线重跑（hooksPath/适配器/验证命令占位符探测）。
   - 回执：版本迁移 + 实际更新文件清单 + live 未动清单 + 新版本 CHANGELOG 要点（`docs/STANDARDS_CHANGELOG.md` 顶部条目）。
5. **初始化第一个功能目录骨架**（可选，询问用户是否现在就要开始第一个变更）：
   - 若用户已有具体功能要开发，按 `DEVELOPMENT_STANDARDS.md` §1.1 在 `docs/<feature>/` 下创建空的 `01-spec.md` 骨架（仅标题与章节占位，不臆造需求内容）；变更管线入口 `00-intent.md`（§2.17）同样只创建骨架。
6. **完成后回执**：列出本次实际写入/跳过的文件清单、启用的客户端适配器和仍需用户在托管平台配置的 Required Checks。不得声称“所有工具均在改前强制受控”；应说明 `AGENTS.md` 是上下文层，受保护分支的 CI 才是跨客户端的最终信任边界。若安装了管线自动化，提示 `scripts/agent-gate metrics` 可输出管线度量（§2.17.5），仅作观察不替代 DoD。

## 红线

- 不覆盖用户已有的、内容不同的 `AGENTS.md` 或 `DEVELOPMENT_STANDARDS.md`，一律先展示差异再询问（`--upgrade` 模式例外：目标仓已确认干净树后，治理自有文件更新到携带版本；live 文件清单永远跳过）。
- 不臆造项目特定内容（技术栈、构建命令等）--`resources/AGENTS.md` 是通用治理规范，不含具体项目的构建/测试命令；如需补充这类项目专属信息，在写入后追加提示，请用户自行在 `AGENTS.md` 末尾补充"项目速览"小节（Dev environment / Build & Test 命令），本 Skill 不代为编造。
- 不在多个工具专属文件里复制规范正文；工具专属文件只允许引用同一 `scripts/agent-gate`，不得分叉校验逻辑。
- 写入本仓库或目标仓库的任何文件后，必须用 shell 级磁盘验证（`grep -c` / `wc -l` / `git diff --stat`）确认落盘；不得信任编辑工具的“成功”返回值，不得用 Read 工具验证落盘（其可能返回缓存内容）。上下文被压缩后，以磁盘与 git 状态为唯一权威，重读后再继续。

## 版本同步

- **同步范围**：`resources/DEVELOPMENT_STANDARDS.md`、`resources/AGENTS.md` 与方法论层（`resources/METHODOLOGY.md` + `resources/methodologies/`）应随规范正文迭代更新（当前携带版本 v3.14.0，见规范页脚）；`resources/templates/agent-gate.sh` 与 `tests/run-tests.sh` 必须同步演进——改脚本必须先跑通 `tests/run-tests.sh` 再发布（§2.17.4）；`scripts/bootstrap.sh` 的清单与 SKILL.md 步骤 3-4 同步维护；断言数生成器 `scripts/update-assertion-count.sh` 管理 README 声称数与审计执行数基线（改断言后必须运行再发布）。
- **文档一致性**：改规范正文 / 模板 / README 后必须另跑通 `tests/audit-standards-src.sh`（规范源层审计：版本链、关键词落点矩阵、§3↔§4 清单同源、编号体系收录、占位符 vs A 层断言防恒真、骨架 vs A 层关键词、00 管线件落点、bugfix 双登记 9+1 项对齐、锚点章节存在性、README 树↔磁盘、升级日志排序）——文档完整性由方法与机器保证，不由轮数保证。
- **适用范围分层**：`audit-standards-src.sh` 属规范源层自检（仅本仓库使用，**不入** bootstrap 复制清单）；通用层（`agent-gate.sh`/`run-tests.sh`/`check-standards-compliance.sh`/`audit-docs-consistency.sh`）审计目标仓库的变更产物，两层不可互替。脚本断言分 PART A（永久结构不变量）与 PART B（版本快照落点，规范升级时随 §2.14 日志更新），防脚本腐烂。
- **升级推送**：每次升级本 Skill 内的规范版本后，已经接入过的项目**不会自动更新**，需要用户再次调用本 Skill 走"检测已有文件 -> 展示版本差异 -> 询问是否升级"的流程，并按版本补复制：v3.3.0+ 补 `METHODOLOGY.md`、`methodologies/`（v3.4.0 含 `state-trigger-audit.md`）与 `bugfix-log.md` 到 `docs/`；v3.5.0+ 补 `commit-msg` 模板到 `.githooks/` 并更新 `pre-push` 与 `scripts/agent-gate`；v3.6.0+ 补缺陷文档组模板（`bug-diagnosis.md`/`bug-impact.md`/`bug-test-plan.md`）到 `docs/bugs/_templates/`；v3.7.0+ 缺陷模板扩为六件套（补 `bug-matrix.md`/`bug-config.md`/`bug-tasks.md`）、补编码记录模板 `coding-record.md`（变更起编时落 `docs/changes/<变更号>/04.5-coding-record.md`）并同步更新 `scripts/agent-gate` 与 `tests/run-tests.sh`；v3.7.0 修订（CHG-004）补 `06.5-deployment-config.md` 与 `06-delivery-summary.md` 两个模板到 `docs/`，并同步更新 `scripts/agent-gate`——**这是一次交付门禁收紧**：此前 `--stage stop` 只校验 `04.5`/`05`/`09`，现在 `06.5` 与 `06-delivery-summary` 同样必检，老项目升级后需补齐这两份文档（未命中也要显式声明）才能通过。规范正文 §1.1 早已声明"八类缺一即未完成"，本修订只是让实现与已声明的语义对齐，故不升规范版本号。
