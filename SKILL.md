---
name: dev-standards-bootstrap
version: 3.51.0
description: 在任意代码仓库中一键初始化"全局软件开发与变更规范"体系（AGENTS.md 唯一入口 + 五道门禁 + 风险分级 + Agent 独立性矩阵 + PR/CI 兜底）。当用户说"给这个项目接入开发规范"、"初始化 dev standards"、"这个仓库还没有 AGENTS.md，帮我加上"、或新建项目/新仓库首次配置时使用。当前携带规范版本 v3.51.0，低于此版本即需升级。
---

# dev-standards-bootstrap

> **当前携带版本：v3.51.0**（与 `resources/DEVELOPMENT_STANDARDS.md` 页脚、`resources/STANDARDS_CHANGELOG.md` 顶部条目同源）
>
> **自查是不是最新版**：在本 Skill 目录执行 `git fetch --quiet && git log -1 --date=short --format='%h %ad %s'` 看本地副本是否落后；或比对仓库 README 的 `Standards Version` 徽章。低于上方版本号就该升级——对已接入的目标仓库说"更新 dev-standards-bootstrap"（步骤 4.5）。也可直接 `bash scripts/bootstrap.sh --check <目标仓库>` 看三处版本比对。

## 这个 Skill 做什么

把一套团队开发治理规范（文档先行、测试先行、五道门禁、四维追踪矩阵、Agent 角色独立性、分阶段专家评审（§2.2 九专家）、风险分级、防遗漏防跳过）**一次性**接入任意代码仓库。

`AGENTS.md` 是向 Agent 提供统一上下文的**上下文层**；可选的 `agent-gate` 在支持 Hook 的客户端写入前阻断，并由 Git / CI 对所有客户端兜底。装一次，以后每个新项目只需说一句"用 dev-standards-bootstrap 初始化这个仓库"。

## 何时触发

- 用户明确要求初始化/接入开发规范、AGENTS.md、变更管理流程
- 新建仓库、新项目第一次做工程化配置
- 用户提到"这个仓库还没有门禁 / 追踪矩阵 / Agent 分工机制"

## 执行步骤

1. **确认目标仓库根目录**（询问用户，或使用当前工作目录）。
2. **检测已有文件，避免覆盖**：目标已存在 `AGENTS.md` 或 `<docs>/DEVELOPMENT_STANDARDS.md` 时，先展示版本 / diff 差异，再询问是合并、追加新增章节，还是保留原文件仅追加一行引用。
3. **写入核心文件**——用安装器，不要手工逐条复制：

   ```bash
   bash scripts/bootstrap.sh --all <目标仓库>
   ```

   - **人类一句话路径**（v3.22.0）：不想先克隆本 Skill 时，可直接
     `curl -fsSL https://raw.githubusercontent.com/geekma/dev-standards-bootstrap/main/scripts/install.sh | bash -s -- <目标仓库>`——一条命令完成克隆 + 全量安装，目标仓已接入时自动转为升级（详见 README「Installation & Upgrades」）。Agent 走本 Skill 时仍按上面的 bootstrap 路径，两者落点与语义一致。要把 **Skill 本体**装进 AI 客户端（而非装进目标仓）：`scripts/install.sh --as-skill claude|opencode|all|<落点路径>`——以 symlink 注册进客户端技能目录（fail-closed；与安装/升级模式互斥），装完 `/reload-skills` 或重开会话生效；也可不跑命令，直接对 Agent 说"从 geekma/dev-standards-bootstrap 把本 Skill 装进你的技能目录"；或走通用 store `npx skills add geekma/dev-standards-bootstrap -g`、Claude Code 插件（`claude plugin marketplace add geekma/dev-standards-bootstrap` + `claude plugin install dev-standards-bootstrap@geekma-dev-standards`）——路由清单以 README 快速开始为唯一权威。
   - `--all` 是"用户说初始化"的**一条完成路径**（默认全量自动注入）。分层 flag（`--core` / `--claude` / `--ci` / `--guard` / `--pipeline`）**只在用户明确要求最小化安装或排障时**使用。
   - **各层的精确文件清单以 `bash scripts/bootstrap.sh --help` 为唯一权威源**，本文件不复制——同一份清单维护两处必然腐烂。
   - 安装器**幂等**、**失败即拒绝（fail-closed）**、目标已有不同内容时展示 diff 并要求 `--force` 才覆盖——这是"检测已有文件、绝不静默覆盖"红线的机器化兜底。`--all` 还会**自动接线**（`core.hooksPath` / 客户端适配器 / 验证命令探测），零手工。
   - 核心层含跨文档一致性机器审计 `<tests>/audit-docs-consistency.sh`（十组不变量 G1–G10 + A 组盖章互证，逐组定义以脚本头部注释与 `resources/AGENTS.md` 锚点表为唯一权威；支持 `--only-fail` 只打 FAIL 行与空转声明，存量红仓复跑免全量重放）；文档变更后或接入 CI 时运行，失败项即 §2.14 存量回填清单。核心层还含 `METHODOLOGY.md` 与 `methodologies/`（`development.md` / `data-structures.md` / `state-trigger-audit.md` / `expert-capabilities.md` / `project-masters.md`，v3.35.0 起含项目总册细节层）与项目总册骨架 `<docs>/templates/project/`（12 册+评审模板，v3.35.0）与一页文档地图 `<docs>/README.md`（五层职责+更新时机，v3.37.0）与条款注册表 `<docs>/CLAUSE_REGISTRY.md`（条款机器索引层，DS 仍是条款正文唯一叙事权威，v3.46.0）。
   - 强制包层含 Git Hook 归因闸门（`pre-commit` / `pre-push` / `commit-msg`）、`<scripts>/agent-gate`、**会话内执法 `<scripts>/session-gate.sh` + `<scripts>/install-hook-adapter`（按当前客户端自适应接线，v3.34.0）**、`.agent-governance.yml`、`.github/workflows/agent-governance.yml`（required-check 名 `agent-governance`）、阅读包生成器 `<scripts>/generate-reading-pack.sh`（按变更类型从条款注册表生成阅读切片，锚点 fail-closed，v3.46.0）与治理自测试 `<tests>/run-tests.sh`。
   - **缺陷文档组**模板为**六件套**（`bug-diagnosis.md` / `bug-impact.md` / `bug-test-plan.md` / `bug-matrix.md` / `bug-config.md` / `bug-tasks.md`），落 `<docs>/bugs/_templates/`；编码记录模板 `coding-record.md` 在变更起编时落 `<docs>/changes/<变更号>/04.5-coding-record.md`。
   - **变更起编时**（非安装期）再从模板生成 per-change 产物：`00-intent.md` → `<docs>/changes/<变更号>/00-intent.md`、`governance-state.json` → `00-governance.json`（须由用户/编排者填真实风险等级与执行主体）。同一天的多个 L0/L1 变更可改落 `<docs>/changes/BATCH-YYYYMMDD/`（见「变更批次」节）。
4. **仍需用户在托管平台完成的事**（安装器会打印指引，但改不了平台设置）：把 `agent-governance` 与项目测试设为 Required Check、禁止直推受保护分支、为 L3 配置 CODEOWNERS / 人工审批。本地 Hook 可被绕过——**受保护分支的 CI 才是跨客户端的最终信任边界**。

4.5 **Skill 版本更新**（用户说"更新 / 升级 dev-standards-bootstrap"，或检测到目标仓规范页脚版本低于本 Skill 携带版本）：

   - 先确认目标仓库工作区干净：**有未提交改动时 `--upgrade` 直接拒绝**（`--force` 可强制；git history 即升级备份）。
   - 执行 `bash scripts/bootstrap.sh --upgrade <目标仓库>`：治理自有文件（规范 / 方法论 / 模板 / 脚本 / hooks / workflows / tests）更新到携带版本并打印版本迁移；**live / 用户文件不动**（`bugfix-log.md`、`06-delivery-summary.md`、`06.5-deployment-config.md` 的累积记录与 `.agent-governance.yml` 的用户配置原样保留）；随后自动接线重跑。
   - 回执：版本迁移 + 实际更新文件清单 + live 未动清单 + 新版本 CHANGELOG 要点（`<docs>/STANDARDS_CHANGELOG.md` 顶部条目）。
   - **"这一版升级后要补什么"以 `MAINTAINER.md` §7 为准**；本文件**不列举**历史版本的补复制动作——那是会过时的信息，列举即违反官方"正文不得含时效性信息"。

5. **初始化第一个功能目录骨架**（可选，询问用户是否现在就开始第一个变更）：若用户已有具体功能，按规范 §1.1 在 `<docs>/<feature>/` 下创建空的 `01-spec.md` 骨架（仅标题与章节占位，**不臆造需求内容**）；变更管线入口 `00-intent.md`（§2.17）同样只创建骨架。

6. **完成后回执**：列出本次实际写入 / 跳过的文件清单、启用的客户端适配器、以及仍需用户在托管平台配置的 Required Checks。**不得声称"所有工具均在改前强制受控"**——应说明 `AGENTS.md` 是上下文层，受保护分支的 CI 才是最终信任边界。若装了管线自动化，提示 `scripts/agent-gate metrics` 可输出管线度量（§2.17.5，仅作观察，不替代 DoD）。

## 路径根可配置

安装时可用 `--docs-dir <path>`（另有 `--scripts-dir` / `--tests-dir` / `--githooks-dir`）把目录根改到仓库习惯的位置，例如 `bash scripts/bootstrap.sh --all --docs-dir doc <目标仓库>`。

- **不传即用默认**（`docs` / `scripts` / `tests` / `.githooks`），行为与引入本特性前逐字节一致——这是零回归保证。
- 解析优先级：CLI flag > 环境变量 `AGENT_GUARD_<KEY>_DIR` > 目标仓 `.agent-governance.yml` 的 `paths:` > 内置默认。
- 非默认根会**同步写入**目标仓 `.agent-governance.yml` 的 `paths.*`（并把 `change_root` / `bugs_root` 一并改为派生值——**仅当现值仍是内置默认** `docs/changes` / `docs/bugs`；你显式 pin 的值不会被静默覆盖，脚本会打印 NOTE），同时**改写模板内部的路径引用**（Git hooks 与客户端适配器按路径调门禁，workflows 与规范模板按路径引用文档）。这两步都不可省：门禁按配置找文件，落点与配置不一致就是静默错位。
- **只有目录根可配置**：`AGENTS.md` 文件名、`scripts/agent-gate` 落点名、变更 14 件产物名、缺陷六件套名、required-check 名 `agent-governance` 是**跨仓契约**，刻意不可配置；`.github/` 位置由平台强制、同样不可配。

## Agent 自进化契约

本 Skill **允许 Agent 自进化**：基于它派生的、面向特定项目或特定 Agent 优化的 Skill **独立存在**，**不回收到本仓库**。（源仓出现派生 Skill 的副本或引用即为缺陷——那会制造第二份权威源。）

**派生方义务**——在派生 Skill 的 `SKILL.md` frontmatter 声明三行：

```yaml
agent_created: true
derived_from: dev-standards-bootstrap
derived_from_version: <你派生时本 Skill 携带的版本，如 3.22.0>
```

**本 Skill 的义务**——升级时**不得覆盖派生资产**：

- `--upgrade` 的**每一条**写入路径都跳过携带 `derived_from` 的目录，并打印 `derived (skip) <路径>`；
- `--force` **不越过**该保护——`--force` 的语义是"覆盖内容不同的既有文件"，不是"覆盖别人派生出来的资产"；
- `bash scripts/bootstrap.sh --derived-report` 只读输出：哪些目录是派生的、基于哪个版本、当前携带版本是多少，用于判断派生资产是否需要跟上。

## 文件溯源

**强制范围（v3.34.0）＝变更目录全部 `*.md` ＋ 缺陷六件套**。交付前必跑两条命令：

- `scripts/stamp-provenance.sh --all <变更号>`——变更目录全部 `*.md` 产物盖章（`00-governance.json` 刻意不盖：HTML 注释破坏扁平 JSON 读取）；
- `scripts/stamp-provenance.sh --bug <BUG-id>`——本变更 `bug_ref` 绑定的缺陷六件套盖章（块以 `bug:` 标注、`risk: n/a`；v3.36.0 起命中扁平批次时块为 `bug: <BATCH-id>` + `batch_changes:` 成员清单）；gate stop 逐一校验，缺一件不可交付。

（v3.20~v3.25 的"默认只盖 04.5、`--all` 可选加强"措辞自 v3.26.0 起作废；v3.34.0 把六件套纳入同一条强制线。）

- 溯源块把**作者 / 邮箱 / 提交者 / 提交短哈希 / 主机名 / 平台 / UTC 时间 / 规范版本**从**运行环境**读出（`git config`、`git log -1`、`hostname`、`uname`、`date -u`）——`00-governance.json` 的 `implementation_owner` 是手写字符串，写什么就是什么；溯源块手写改不出这些真值。
- 门禁校验**形状与非占位**：块存在、四字段非空、`generated_at` 是 ISO 日期、`generated_by` 必须指向本脚本。**手写块能编 `author`，但过不了 `generated_by`**；作者值本身是否属实**不可机器验证**，别把它当成已解决的保证。
- **变更目录不追溯既往**：只校验当前活跃变更，**历史产物不得回填**（回填会把 `generated_at` 伪造成今天）；审计 A20 只抓"同目录半途盖章"（如 9 件只盖 2 件）与"v3.26.0 起新变更整目录未盖"，不抓时代差。**六件套例外（v3.34.0）**：对既有缺陷组跑 `--bug` 补盖写入的是当下真值、组内本无 `generated_at` 时序语义，属用户裁定的存量补齐，不算伪造。
- 写入**幂等**（整块替换）；`provenance.include_email: false` 使邮箱写为 `<redacted>`；工具缺失时字段降级为 `unknown`，不猜不编。

## 会话内执法（v3.34.0）

执法点不再只锚在 commit：pre-commit/CI 校验的是仓库，但 Agent 产物长期停在工作区不提交时它们**永不点火**——CHG-071（9 件只盖 2 件）与 BUG-040~055（16 组只写 01-diagnosis 即自勾"完成"）正是这么漏过来的。`scripts/session-gate.sh` 由客户端**会话事件**调用：

- **会话开始**（`start`）：跑一次 `tests/audit-docs-consistency.sh --only-fail`，存量红灯写 `.agent-state/session-gate-last.md`——Claude SessionStart 会把 stdout 注入会话上下文，opencode 插件写结构化日志并可用 `/gate-check` 命令随时复查。
- **会话空闲/收尾**（`idle`）：有活跃变更 → 跑 `agent-gate --stage stop` 等价检查（**软执法**：设 `AGENT_GUARD_SKIP_VERIFY=1` 跳过 `verification_command` 全量回归——session.idle 可能每轮触发，`mvn test` 级命令跑不起；结构/证据校验照跑，全量回归仍由 Claude Stop hook / pre-commit / CI 承担）；无活跃变更但有源码改动 → 红灯（"修完不留痕"）。硬阻断仍由 Claude Stop hook 与 Git hooks 承担，本脚本负责"让红灯被看见"。
- **接线由 `scripts/install-hook-adapter.sh` 自适应生成，不写死客户端**：探测（env 标记 / CLI on PATH / 仓库配置目录，三路证据）→ 按客户端 schema 生成（claude=JSON 合并、opencode=插件+命令、cursor/gemini=静态 schema、codex=如实声明由 Git hooks+CI 兜底）→ **生成后强制验证**（JSON 可解析 / 插件 bun|node 可加载 / hook 脚本 `bash -n`），验证不过即安装失败。`--detect` 只打印矩阵，`--client <name>` 显式指定。报告文件 `.agent-state/` 建议目标仓 `.gitignore` 追加忽略（运行态，不是治理产物）。

## 变更批次（同日合并）

**同一天**的多个 **L0/L1** 变更**默认共用** `<docs>/changes/BATCH-YYYYMMDD/` 一个目录，而不是各建一个变更目录（v3.24.0 默认化）。

- **只有目录被放宽，产物文件名一字不改**——仍是 `00-intent.md` … `09-changelog.md` 那 14 件同名文件；同批变更用 `## <变更号>` 小节锚点分开，`00-governance.json` 写成**一行一个 JSON 对象**（变更号 / 风险 / 责任人各自成行；**推荐写法，但不再是解析器的硬要求**——见下条）。所有按文件名找东西的既有习惯（门禁、审计、人工检索）继续有效——**这是复用既有体系，不是新起一套**。
- **L2/L3 不得入批**：批次让多个变更共享一套产物，会削弱逐变更证据边界与角色独立性。门禁按治理记录逐条校验并直接拒绝批次内的 L2/L3。
- **解析顺序**：独立 `<docs>/changes/<变更号>/`（历史布局，**永远优先**，存量仓库零影响）→ `AGENT_GUARD_CHANGE_DIR` → 含该锚点的 `BATCH-*/`。
- **闭环判定细一档**：`09-changelog.md` 被同批共享，"文件存在"不再等于"本变更已关闭"，改判**本变更自己的 `## <变更号>` 小节**是否存在。`metrics` 按**每个变更**输出一行。
- **变更集合从权威名单读**（v3.19.0）：门禁与审计都只认 `00-governance.json` 里的 `change_id`，**不从 `## <标题>` 反推**——标题分不清"变更小节"与"结构小节"，而规范强制 `09-changelog.md` 含 Observation 记录（§2.16.2），反推会让 `metrics` 造出幽灵变更、让 `--stage staged` 拒掉整批。**批次小节标题一律写 `## <变更号>`**（不带 `§N：` 前缀；那是 `05-test-results.md` 的批次小节格式）。
- 审计 G7 逐批次核对：每条记录在 `00-intent.md` 有自己的分节、记录 ⊆ 锚点、风险 ∈ {L0,L1}、变更号跨批次唯一。
- **治理记录的格式无关**（v3.20.0）：`00-governance.json` 是 JSON，JSON 的换行没有语义——**格式化的单对象**与**一行一变更的批次**是同一份数据，门禁与 `metrics` 必须读得一样。此前读取器是行式的（`grep … | head -1`），于是**照着随包模板 `governance-state.json`（多行）生成的记录会被 `begin` 拒绝**（报 `must declare risk_level L0, L1, L2, or L3`，而字段就在 `change_id` 下面两行），`metrics` 则对每条记录报 `"risk_level":null`。现在读取器先压平再按顶层对象切分：**任意合法 JSON 写法等价**，单行与多行都可用。记录仍须**扁平**（不嵌套对象）——`json_field` 是单行 sed，L3 的 `release_authorized_*` 三个字段刻意是扁平字符串，正是为此。
- **审计的覆盖面与"空转"必须如实**（v3.21.0）：`tests/audit-docs-consistency.sh` 按**不变量是否时间不变**分两轨——**G2 编号连续性**（时间不变：`REQ-001` 与 `REQ-003` 同现而缺 `002`，写下就错、今天仍错）覆盖**功能目录 ∪ 变更目录**；**G3/G5/G6**（拿**当前** §3/§4 比对）**只覆盖活文档（功能目录）**，因为冻结的变更目录按 §2.15 硬性规则 4 / §2.16.5「已闭合 CHG 禁止改写」**不可回填**，事后判它们只会产出永久无法清除的红。任一组没有目录可审时，脚本**打印一行 `VACUOUS SKIP`** 点名说明——**读到它不是"通过"，是"那一组没覆盖本仓库"**；变更轨的 §3/§4 一致性请在门禁侧确认（`agent-gate --stage stop`）。编号连续性只数**行首的定义式**（正文引用不算），区间基线取**文件自身 min**（编号空间是全仓全局的，§1.2）。

## 红线

- **不覆盖**用户已有的、内容不同的 `AGENTS.md` 或 `DEVELOPMENT_STANDARDS.md`，一律先展示差异再询问。（`--upgrade` 模式例外：目标仓已确认干净树后，治理自有文件更新到携带版本；live 文件清单永远跳过。）
- **不臆造项目特定内容**（技术栈、构建命令等）——`resources/AGENTS.md` 是通用治理规范，不含具体项目的构建 / 测试命令。如需补充，写入后提示用户自行在 `AGENTS.md` 末尾补"项目速览"小节（Dev environment / Build & Test 命令；可选补"方法论偏好"与"专家扩展"行，供 §2.2 专家能力卡自适应，本 Skill 不代为编造）。
- **不在多个工具专属文件里复制规范正文**；工具专属文件只允许引用同一个 `scripts/agent-gate`，不得分叉校验逻辑。
- 写入本仓库或目标仓库的任何文件后，**必须用 shell 级磁盘验证**（`grep -c` / `wc -l` / `git diff --stat`）确认落盘——禁信编辑工具的"成功"返回、禁用 Read 工具验证落盘（缓存）；上下文被压缩后以磁盘与 git 状态为唯一权威。细则与依据同 `resources/AGENTS.md` 红线。

## 版本同步

- **当前携带版本 v3.51.0**（见规范页脚，页脚是唯一权威源）。
- **版本号三载体**：frontmatter `version:`、`description` 尾注、正文顶部横幅——升级规范时**页脚 + 三处一起改**，漏改即审计红；平台事实论证（frontmatter 无 `version` 字段等）以 [`MAINTAINER.md`](MAINTAINER.md) §6 为权威，本文件不复述。
- **改本 Skill 本身的人**（改脚本 / 改规范 / 改模板 / 动断言）请读 **[`MAINTAINER.md`](MAINTAINER.md)**：文件角色表、改哪里必须同时改哪里的联动表、两道自测试的用法与顺序、断言数生成器、审计的 PART A/B 分区、逐版本升级推送清单。**装规范的人不需要读它。**
