# 更新日志（Changelog）

> 本文件是 **dev-standards-bootstrap 项目本身**的版本历史（用户可感知的变更：安装/升级动线、文档、工具脚本）。
> **分工**：规范条款级的升级记录在 [`resources/STANDARDS_CHANGELOG.md`](resources/STANDARDS_CHANGELOG.md)（随 `--core` 下发到目标仓库）；本文件只做项目叙事，不复制其条款细节。
> 格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；语义化版本（`主.次.修订`：次版本号递增 = 携带的规范有新能力/新模板）。

## [Unreleased]

### 新增

- **Claude Code 插件分发面**：新增 `.claude-plugin/{plugin,marketplace}.json`（`source: "./"`——仓库即插件）。端到端实测：`claude plugin validate` 通过、`marketplace add` → `plugin install` → `plugin details` 显示 **Skills (1)**（根级 SKILL.md 被发现，常驻 ~197 tok）；`claude plugin marketplace add geekma/dev-standards-bootstrap` 即装。
- **README 接入动线重排（两步式，修复鸡生蛋）**：第 1 步「注册 Skill」四条实测路由任选——① `npx skills add geekma/dev-standards-bootstrap -g`（通用 store，今天即可用）② Claude Code 插件 ③ 对话粘贴话术 ④ `install.sh --as-skill`；第 2 步「一句话初始化」。旧「路径 A/路径 B」叙事移除；新增 CI 徽章与 TL;DR（定义句/关键词前置，SEO/GEO）。
- **审计 A24 承诺面入库守护**：README 宣传的安装命令所读取的文件（install.sh / CHANGELOG / MAINTAINER / stamp-provenance / .claude-plugin/*）必须 git-tracked——防「文档宣传未提交文件 → 线上 raw 404」类缺陷复发（实测缺陷：已提交 README 宣传 curl 命令，install.sh 却只在暂存区）。
- **README 安装命令去重（CHG-021）**：一条命令的全文 URL 从每份 README 5 处收敛为 1 处唯一权威落点（Installation & Upgrades），其余四处改 flag 变体 + 锚点链接；双语结构对称不变。
- **Skill 本体注册进 AI 客户端（对话式安装，CHG-019）**：`scripts/install.sh --as-skill <claude|opencode|all|落点路径>` 把 Skill 本体以 **symlink** 注册进客户端技能目录（`claude` → `~/.claude/skills`、`opencode` → `~/.config/opencode/skills`、`all` → 两者、值含 `/` 视为落点本身）。checkout 即 Skill 布局（根级 `SKILL.md` + `resources/` + `scripts/`），零复制、自更新即时生效；fail-closed（已有非 symlink 落点绝不触碰，`--force` 仅 retarget symlink 或替换空目录）；与 `--install`/`--upgrade`/`--check`/`--layer` 互斥，不触碰任何目标仓库。补齐 README 此前的鸡生蛋缺口：此前"对 Agent 说一句话"预设 Skill 已装，但没有任何装 Skill 本体的路径。双 README 新增对称小节 + 可直接粘贴给 Agent 的对话话术；`SKILL.md` 步骤 3 同步。golden T21 新增 TC-145..148（链接/幂等/冲突/自定义路径，全走 `--skills-root` 重定向，零真实 HOME 写入）。

### 修复

- **双 README golden 断言声称数漂移**：`scripts/update-assertion-count.sh` 原按**静态调用点**计数，漏计同链双调用（`grep … && report … || report …`）与循环站点，声称数与运行实出长期差 3（281↔284、288↔291 两代同型）。改为**运行期实出口径**（解析 `N passed`；红套件拒同步 exit 2），本版同步为 292。MAINTAINER §4 口径同步。

（历史版本见下方归档段）

## [3.22.0] — 2026-09-16

### 新增

- **一句话克隆并安装/升级**：新增 `scripts/install.sh`（源层工具）。一条命令完成"克隆本 Skill + 对目标仓全量安装"，目标仓已接入时自动转为升级：
  ```bash
  curl -fsSL https://raw.githubusercontent.com/geekma/dev-standards-bootstrap/main/scripts/install.sh | bash -s -- .
  ```
  支持 `--from <本地路径>`（离线/内网/测试）、`--skill-dir`、`--repo`、`--ref`、`--install`/`--upgrade` 显式模式，以及层与目录根参数透传；冲突与脏树守卫 100% 复用 `bootstrap.sh`（fail-closed，绝不静默覆盖）。
- **溯源全量盖章**：`scripts/stamp-provenance.sh --all <变更号>` 一条命令给活跃变更目录**全部 `*.md` 产物**盖溯源块（作者/邮箱/提交者/提交哈希/主机/平台/UTC 时间，全部从运行环境读出）。`00-governance.json` 刻意不盖（JSON 中注入注释会破坏机器读取）；默认行为（只盖 `04.5-coding-record.md`）逐字节不变。

### 修复

- **源仓溯源自锁**：源层审计 A19 反向断言由"历史变更目录一律不得盖章"修正为"溯源块只允许出现在活跃变更或已闭合变更"——原语义与"交付前必须盖章"的强制要求自相矛盾（盖章即审计红）。仍拦截对无关开放目录的随手盖章。
- **载荷缺文件**：`resources/templates/stamp-provenance.sh` 此前未纳入版本控制，全新 `git clone` 后 `--guard` 层安装会因缺源文件而失败；已入库。

### 文档

- **README 双语重写**：按最佳实践章节化（项目背景 / 功能 / 支持工具 / 快速开始 / 安装与升级 / 自动化说明 / 五道门禁 / 风险分级 / 治理细节 / 仓库结构 / FAQ / 贡献 / 许可证）；**全部截图保留**；叙事改为"命令由 Agent 与 Hook 自动调用，本文是参考手册，手动执行永远可选"。
- **版本说明外置**：原先堆在 Quick Start 里的 v3.15.0~v3.21.0 逐版本段落全部迁出至本文件。
- **FAQ 落裁定**：同一天多个 L0/L1 变更可并入 `BATCH-YYYYMMDD/`（v3.18.0 已实现）；缺陷六件套**刻意不入批**（逐缺陷证据边界，`docs/bugfix-log.md` 索引即天级检索）。

## [3.21.2] — 2026-09-16

独立复核对齐续修（10 条，无行为变更、无回填义务）。要点：规范正文删去派生 Skill 名举例；`SKILL.md` 版本自查条件补全；`agent-governance.yml` 的 `required_before_merge` 与门禁对齐（3→5 件）；`bootstrap.sh` 自定义根安装的假 NOTE 消除；规范体量上界按规程重校准至 128 KiB。登记 FU-030/031/032/033。逐条见 [STANDARDS_CHANGELOG](resources/STANDARDS_CHANGELOG.md)。

## [3.21.1] — 2026-09-16

全项目 review 对齐修正（15 条，无行为变更）。要点：`AGENTS.md` 门禁入口与 `begin` 硬校验对齐（补「开放问题」节）；场景覆盖率门槛补 L3 ≥90%；PR 模板门禁自检补齐 DoD 条目；`check-standards-compliance.sh` 自定义 `change_root` 假红修复；`--docs-dir` 不再静默覆盖用户显式 pin 的 `change_root`/`bugs_root`。

## [3.21.0] — 2026-09-15

**审计覆盖面修复**：通用层审计曾对"产物落在变更目录"的仓库**完全空转**（一条断言都不跑却显示通过，带跳号的仓库也能通过审计）。现在审计单元按正信号识别、空转必须显式打印 `VACUOUS SKIP`、编号连续性只数定义式且基线取文件自身 min（此前本仓 16 个 spec 误报 695 处"缺号"）、G3/G5/G6 刻意只覆盖活文档（冻结历史不可回填，判历史只会产出永远清不掉的红）。

## [3.20.0] — 2026-09-15

**治理记录格式无关**：照随包模板（多行 JSON）生成的 `00-governance.json` 曾被自己的门禁拒绝（`begin` 报 risk_level 缺失、`metrics` 全报 null）。读取器现在先压平再按顶层对象切分——任意合法 JSON 写法等价；"一行一个变更"降级为风格建议。

## [3.19.0] — 2026-09-15

**批次权威名单**：批次内的变更集合改为正向读 `00-governance.json` 的 `change_id`，不再从 `## <标题>` 反推（规范强制的 `## Observation` 结构标题曾让 `--stage staged` 拒掉整批、给 `metrics` 造出幽灵变更）。

## [3.18.0] — 2026-09-15

**变更批次（同日合并）**：同一天的多个 L0/L1 变更可共用 `<docs>/changes/BATCH-YYYYMMDD/` 一个目录——**只有目录放宽，12 件产物文件名一字不改**，同批变更用 `## <变更号>` 小节锚点区分；L2/L3 不得入批（门禁按治理记录逐条拒绝）；闭环判定细到"本变更自己的小节"；溯源块批感知（`change:` 记批次、`batch_changes:` 列成员、风险取批次最高值）。

## [3.17.0] — 2026-09-15

**文件溯源**：新增 `scripts/stamp-provenance.sh`——把作者/邮箱/提交者/提交哈希/主机名/平台/UTC 时间从运行环境读出写进 `04.5-coding-record.md`（禁手写；门禁校验块存在、四字段非空、`generated_by` 必须指向脚本）；`--stage stop` 与 CI 强检；不追溯既往；隐私开关 `provenance.include_email`。

## [3.16.0] — 2026-09-15

**Skill 自维护三改造**：`--check`（三处版本比对、漂移即 exit 1）、`--self-update`（只更新 Skill 自身）、`--derived-report`（派生 Skill 清单）；`--upgrade` 不再覆盖显式层选择（`--core --upgrade` 只升 core）；**Agent 自进化契约**（派生 Skill 声明 `derived_from` 后，安装/升级每条写入路径跳过它，`--force` 也不越过）；`SKILL.md` 瘦身 30%；新增 `MAINTAINER.md`（不随分发）。

## [3.15.0] — 2026-09-15

**路径根可配置**：`--docs-dir`/`--scripts-dir`/`--tests-dir`/`--githooks-dir`（或 `.agent-governance.yml` 的 `paths:`），不配置即逐字节等于默认行为；非默认根会同步写进目标仓配置并改写模板内部路径引用（防"门禁按默认根找、文件在自定义根"的静默错位）；`.github/` 与全部契约名刻意不可配置。

## [3.14.0] — 2026-09-14

**失败模式硬化**：门禁反篡改守卫（`.agent-governance.yml` 在待定变更中时其验证命令不自动执行，防恶意 PR 注入命令）；`--upgrade` 遇目标仓未提交改动拒绝（`--force` 逃生）；CONFLICT/MISSING 退出前打印部分安装计数。

## [3.13.0] — 2026-09-14

**全面升级自更新**：`--upgrade` 起步先自更新 Skill 源（干净树 `pull --ff-only`，实际更新则用新安装器重入），"一次命令全局生效"。

## [3.12.0] — 2026-09-14

**零命令初始化与升级模式**：初始化默认 `--all` 全量自动注入；新增 `bootstrap --upgrade`（治理自有文件升级到携带版本，live/用户文件硬清单跳过——累积记录零丢失）。

## [3.11.0] — 2026-09-14

**初始化自动接线**：`--guard` 自动配置 `core.hooksPath`（三态：未设→设/已对→跳/自定义→不覆盖并提示）、自动生成客户端 Hook 适配器（检测到 Claude Code/Cursor/Gemini 时）、自动探测构建命令预填验证命令。装完即无手工。

## 更早

3.1.0 ~ 3.10.0 的演进（风险分级矩阵、缺陷六件套、八类最低文档集、场景覆盖率、根因分类、检查器设计规约等）见 [STANDARDS_CHANGELOG](resources/STANDARDS_CHANGELOG.md)。

[Unreleased]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.22.0...HEAD
[3.22.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.21.2...v3.22.0
[3.21.2]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.21.1...v3.21.2
[3.21.1]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.21.0...v3.21.1
[3.21.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.20.0...v3.21.0
[3.20.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.19.0...v3.20.0
[3.19.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.18.0...v3.19.0
[3.18.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.17.0...v3.18.0
[3.17.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.16.0...v3.17.0
[3.16.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.15.0...v3.16.0
[3.15.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.14.0...v3.15.0
[3.14.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.13.0...v3.14.0
[3.13.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.12.0...v3.13.0
[3.12.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.11.0...v3.12.0
[3.11.0]: https://github.com/geekma/dev-standards-bootstrap/compare/v3.10.0...v3.11.0
