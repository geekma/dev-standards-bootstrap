# MAINTAINER.md — 维护者须知

> **本文件面向"修改 `dev-standards-bootstrap` 本身"的人，不面向"用它给项目装规范"的人。**
> 它**不随 Skill 分发**（不在 `scripts/bootstrap.sh` 的复制清单内），也**不进任何目标仓库**。
> 装规范请读 [`SKILL.md`](SKILL.md)；规范正文请读 [`resources/DEVELOPMENT_STANDARDS.md`](resources/DEVELOPMENT_STANDARDS.md)。

放在仓库根而非 `resources/` 是刻意的：`resources/` 是随 Skill 分发的载荷目录，把"不随分发"的文档混进去，会让下一个维护者反复困惑"为什么这个文件没被复制"。

---

## 1. 文件角色

| 路径 | 角色 | 随 Skill 分发 |
|---|---|---|
| `SKILL.md` | 执行者入口：装什么、怎么装、红线 | ✅（Skill 本体） |
| `resources/DEVELOPMENT_STANDARDS.md` | **规范正文，版本号唯一权威源**（页脚） | ✅ → `<docs>/` |
| `resources/STANDARDS_CHANGELOG.md` | 规范升级日志唯一落点（v3.8.0 起） | ✅ → `<docs>/` |
| `resources/AGENTS.md` / `METHODOLOGY.md` / `methodologies/` | 上下文层与方法论层 | ✅ → `<docs>/` |
| `resources/templates/project/`（13 册 + 评审模板，v3.67.0） | 项目级总册骨架（§1.3） | ✅ → `<docs>/templates/project/`（目标仓首次变更复制为 `<docs>/project/` 并回填） |
| `resources/templates/**` | 落到目标仓库的模板与脚本 | ✅（按清单逐项） |
| `resources/templates/uninstall-standards.sh`（v3.41.0） | 一键卸载器：三层分类（运行时直删 / 标记核验删 / 共享资产备份移动永不 rm）；随 `--guard` 安装为 `<scripts>/uninstall-standards`；清单与安装器同源，改动须同步 bootstrap usage 与双 README FAQ | ✅ → `<scripts>/` |
| `scripts/bootstrap.sh` | 清单驱动安装器（**清单即单一权威源**） | ✅ |
| `scripts/install.sh` | 一键安装/升级器（v3.22.0，源层工具）：克隆 checkout + 薄委托 bootstrap，**不复制任何安装逻辑**；`--as-skill` 把 Skill 本体以 symlink 注册进 AI 客户端技能目录（不动目标仓，与安装/升级模式互斥） | ❌（不随 Skill 分发，同 bootstrap.sh 自身） |
| `CHANGELOG.md` | **已删除（CHG-050，用户裁定"不要两套"）**：版本历史唯一落点 = `resources/STANDARDS_CHANGELOG.md`（项目叙事并入对应版本行） | — |
| `tests/run-tests.sh` | 治理自测试（golden cases），随 `--guard` 分发 | ✅ → `<tests>/` |
| `tests/audit-standards-src.sh` | **规范源层**审计，仅本仓库使用 | ❌ |
| `scripts/update-assertion-count.sh` | 断言数生成器，仅本仓库使用 | ❌ |
| `tests/.audit-baseline` | 审计执行数基线（由生成器维护，A10 校验漂移），仅本仓库使用 | ❌ |
| `.github/workflows/ci.yml` | **本仓库自身的 CI**（PR / push main 跑两套自测试）。注意它不是 `resources/templates/github-*.yml` 那几个**下发给目标仓库**的 workflow 模板 | ❌ |
| `.claude-plugin/plugin.json` / `marketplace.json` | Claude Code 插件与市场清单：`source: "./"` 仓库即插件，根级 SKILL.md 被发现为 Skills(1)（实测）；改 name/version 必须两文件与 SKILL.md 版本三载体同步 | ❌ |
| `docs/`（`bugfix-log.md`、`06-delivery-summary.md`、`06.5-deployment-config.md`、`changes/**`、`bugs/**`、`review/**`） | **本仓治理活文档**：FU 台账、CFG/DB 声明、变更产物账本、历史评审；只追加/勘误，不随分发 | ❌ |
| `LICENSE` / `.gitignore` | MIT 许可；忽略清单（含 docs 忽略裁定块，属治理配置面） | ❌ |
| `screenshots/` / `cover-image/` | README 配图（双 README 引用，增删须同步双树）；cover-image 为未跟踪本地素材 | ❌ |
| `MAINTAINER.md`（本文件） | 维护者须知 | ❌ |
| `README.md` / `README.zh-CN.md` | 项目门面 | ❌ |

**两层不可互替**：`audit-standards-src.sh` 审的是**本仓库的规范源**；`run-tests.sh` / `agent-gate.sh` / `check-standards-compliance.sh` / `audit-docs-consistency.sh` 审的是**目标仓库的变更产物**。

---

## 2. 改哪里必须同时改哪里

| 改动 | 必须同步 |
|---|---|
| 规范正文条款 | 页脚版本号 + 上下文/方法论层页脚同步（`resources/AGENTS.md`、`resources/METHODOLOGY.md`、`resources/methodologies/*.md`）+ `STANDARDS_CHANGELOG.md` 顶部新行 + `SKILL.md` 三载体版本 + 双 README 版本 |
| `resources/templates/agent-gate.sh` | 先跑通 `tests/run-tests.sh`（§2.17.4），再发布；`tests/audit-standards-src.sh` 的 A 层断言 |
| `resources/templates/agent-governance.yml` 的 `paths:` | `agent-gate.sh` / `check-standards-compliance.sh` / `audit-docs-consistency.sh` **三者一起**——只升其一即"门禁按默认根找、文件在自定义根"的静默错位 |
| `scripts/bootstrap.sh` 复制清单 | `SKILL.md` 步骤 3–4 + `--help` 文本 |
| `scripts/install.sh` 的行为/参数 | 双 README「安装与升级/Installation & Upgrades」+ `SKILL.md` 步骤 3 的一句话路径 + golden T21；**改安装语义先改 bootstrap，install.sh 保持薄委托** |
| `CHANGELOG.md` | 每次发布（版本链变更）追加一个版本段；规范条款细节只链接 `STANDARDS_CHANGELOG.md`，不复制 |
| 断言增删 | `scripts/update-assertion-count.sh` → 再跑审计（A3 声称数 / A10 执行数基线）。**`tests/.audit-baseline` 与 `tests/.suite-baseline` 只由生成器写，禁手工改**；顺序坑见 §4。**收口取证顺序（v3.65.0/CHG-087 → 改于 v3.87.0/CHG-115）**：写模式的生成器才是唯一会（必要时）内嵌整跑套件的角色（FU-907 红拒校验）；**源审计 A3 不再整跑**，改 `--check --from-baseline` 纯读入库基线。**运行期真值只有一处**：CI（或本地 `verify-all.sh --fresh`）那一次全量跑，跑完由 `scripts/ci-summary.sh --check` 把基线与收据 `passed` 硬对齐；红套件即删收据，回落内嵌跑。同 HEAD 二次收口仍免重跑：新鲜同树收据（`sf_receipt_fresh`：同 HEAD + 同树指纹 + `failed=0` + mtime ≤ `AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN`，默认 30min）被生成器与 `--require-receipt` 共享采信 |
| 新增 / 删除测试套件 | `.github/workflows/ci.yml` 的 job 清单（仓库自己的 CI 必须覆盖全部套件）+ `MAINTAINER.md` §3 的命令清单 + 双 README 树（套件若属源层工具须标明不下发） |
| 双 README 目录树 | 磁盘实际文件（审计有树↔磁盘断言） |
| 新增 `resources/templates/**` 文件 | 双 README 树（树↔磁盘断言）+ `scripts/bootstrap.sh` 复制清单 + 若脚本被模板引用则补 `transform_src` 路径替换规则 |
| 改 `install-hook-adapter.sh` 的客户端接线 | `resources/templates/session-gate.sh` 同步（安装器 fail-closed 依赖其存在并 `bash -n` 验证）；opencode 插件生成物 `.opencode/plugins/` 的路径字面量（transform_src 需要能覆盖其内部 `scripts/` 引用） |
| 改 `session-gate.sh` 的 stop 等价检查强度 | `AGENT_GUARD_SKIP_VERIFY` 语义（idle 软执法跳过 verification_command，真实交付线不设）；active-change 路径必须与 gate 同源（`git rev-parse --git-path agent-governance/active-change`），不得自造第二路径 |
| 改 `resources/templates/agent-gate.sh` 的校验强度 | 所有写 `04.5-coding-record.md` 的 golden 夹具（校验一紧，夹具集体失效） |
| 改变更目录布局（`change_dir` / `resolve_dir` / 锚点形状） | `agent-gate.sh` + `stamp-provenance.sh` + `audit-docs-consistency.sh` 的 G7 **三者一起**，且锚点必须用**同一条** sed 表达式（门禁 `anchor_re` / `anchors_in_file` ↔ 审计 G7）——定义分叉即"审计绿而门禁红"，最难查 |
| 改批次风险上限（`is_batch_dir` 的 L0/L1） | 规范 §1.1 + `resources/AGENTS.md` 门禁步骤 + 审计 G7 的 L0/L1 断言 + golden T18 的拒绝用例 |
| 改"批次的变更集合从哪读"（`gov_ids` / `change_ids_in_dir` / `validate_diff` 批次分支） | 审计 G7 **一起**改，且**判定方向必须一致**：两边都只能**正向读** `00-governance.json` 的 `change_id`，**禁止从 `## <标题>` 反向推断**（§2.16.2 强制的 `## Observation` 会被当成变更号 → `metrics` 造幽灵行、`--stage staged` 拒掉整批；v3.19.0 实测）+ golden T18 的 ④b 断言 |
| 改"治理记录怎么读"（`gov_record` / `json_field`） | **格式无关是硬约束**：`gov_record` 必须先 `tr -d '\n\r'` 压平、再按顶层对象边界切分，**不得退回行式**（`grep` 取首行）——行式读不到多行记录的任何字段，而多行正是随包模板 `governance-state.json` 的形状、也是 SKILL.md 指示照抄的形状（v3.18.0 引入此回归、v3.20.0 修复；本仓 **16/16** 条记录曾被自己的门禁拒绝，`metrics` 一律报 `null`）。**反向也钉住**：不得用"把模板压成单行"来迁就读取器——数据迁就解析器是错的方向（审计 A21 有反向断言）。golden T19 三形状（多行 / 单行 / 多行批次）**一起**改，且批次断言必须保留"逐成员读自己的风险、不串兄弟" |
| 新增治理脚本 / 改 `is_code_path()` 白名单 | 见 §2.17 死锁说明：新增的 `.sh` 治理脚本漏加白名单 = 新仓库**第一次 commit 被自己的门禁拦下**（v3.17.0 实测踩过，症状伪装成"文案不匹配"） |
| 改"审计单元怎么取"（`looks_like_audit_dir` / `audit_dirs` / `g36_dirs`） | **分轨是硬约束，两个方向都不许动**（v3.21.0）：`audit_dirs`（G2 编号）必须是**功能目录 ∪ 变更目录**——收窄成只取功能目录会让管线态仓库（产物落 `docs/changes/<变更号>/`）**一条断言都不跑却显示通过**（本版实测：带 REQ 跳号的仓库通过了审计）；`g36_dirs`（G3/G5/G6）必须**只取活文档**——扩到冻结的变更目录是**时代错置**（§2.15 硬性规则 4 / §2.16.5「已闭合 CHG 禁止改写」明令历史不可回填），只会产出**永久无法清除的红**（本仓实测 CHG-002/005/007 共 4 条）。**空转声明必须保留且必须分开两组**（G2 与 G3/G5/G6 覆盖面不同；合并成一句会让操作者误判"哪几组没跑"）。golden T20 的七组用例 + 审计 A22 的 12 条锚点（含 1 条反向断言）**一起**改 |
| 改 `check_seq` 的"什么算一个编号" | 只数**定义式**（编号在**行首**：标题 / 表格首列 / 列表项 / 裸行首），**不得退回"grep 全出现"**——正文引用会污染编号集合（CHG-006 定义 `REQ-033`~`041`，因正文引用 `REQ-024`~`032` 被撑成 24..41）；区间基线必须是**文件自身 min**，**不得退回 `seq 1 max`**——编号空间是**全仓全局**的（§1.2），任何不始于 1 的文件都会被判"全是缺号"（本仓 16 个 `01-spec.md` 共误报 **695** 处）。两处修正**缺一不可**；实测基线见 §7 v3.21.0 行（61 个产物文件 0 误报） |

> ⚠️ **bash 3.2 陷阱（v3.18.0 实测踩过）**：`local a="$1" b="$prefix/$a"` 里 `$a` **尚未赋值**——`local` 先展开全部词、再逐个赋值，`set -u` 下直接报 `unbound variable`。要引用前一个局部变量，**声明必须拆成两行**。
> 更阴的是它的**表现形态**：若外层作用域里恰好有一个同名**全局**变量，命令替换（`$( )`）会读到全局值而"看起来正常"——同一函数在一条调用路径上正确、在另一条上崩溃。本版实测：`begin` 路径因 `id` 是全局而侥幸通过，`--stage staged` / CI 路径（`id` 是局部变量，不进入子壳）才是真崩点。**修 bug 时别只测报错的那条路径。**

---

## 3. 两道自测试（零依赖：bash 3.2+ / grep / awk / diff / git）

```bash
bash scripts/selfcheck.sh          # v3.87.0：单一入口 = 委托 verify-all（载体 → 私有台账 → 源层审计 → 套件）+ 评测派生校验；参数透传（--fresh / --skip-suite …）
bash tests/run-tests.sh            # 通用层全量：golden cases，断言 agent-gate 的退出码与输出（≈25 min / 1377 断言）
bash tests/run-tests.sh -T auto    # 按 git diff 选节（未映射文件回落全量）——改文档/模板/单脚本用这个（秒~分钟）
bash tests/run-tests.sh -l         # 列全部节名（T1 … T81）
bash tests/audit-standards-src.sh  # 源层：版本链 / 关键词落点 / §3↔§4 同源 / 树↔磁盘 …
```

- **改脚本 → 必须先跑通 `run-tests.sh`**（§2.17.4 硬性要求）。**但跑法分层，不要一律全量**：
  - 改**被测核心**（`resources/templates/agent-gate.sh`、`tests/run-tests.sh`、`agent-governance.yml`）→ 全量，且**收口跑一次**；
  - 改**其他脚本 / 文档 / 模板** → `-T auto`（按 `git diff` 选节）或 `-T <节[,节]>`。
  - 实证代价：同一会话裸跑 11 次 ≈ **4.6 小时**；`-T auto` 在同等覆盖面下为秒级到分钟级。
  - `_auto_map()`（`tests/run-tests.sh` 内）是选节映射表；**未映射的文件一律回落全量**（映射是优化，不是正确性依赖）。新增可映射文件时同步扩表，改完用 `-T T75` 自测映射，并先 `AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash tests/run-tests.sh -T auto` 看解析结果。
- **改规范正文 / 模板 / README → 必须先跑通 `audit-standards-src.sh`**。
- **CHG-115 起源层审计不再内嵌整跑**：A3 消费 `tests/.suite-baseline`（上一次真实绿跑计数的入库件），纯读/比，A3 改造当时实测 9.0s；本批 A56 边界段一度付到 ≈20s（受跟踪面措辞扫描 + 夹具实跑），R4 删去载荷专用措辞环后收口实跑 15s——这个数的机器真值是 verify 收据 `audit` 步的 duration_s，不要把任何复述当常量。旧写法（`update-assertion-count.sh --check`）会在同树收据过期（30min TTL）时隐式跑整套——620 条断言的审计曾因此付 300.984s（占墙钟 97.2%）。**运行期真值只有一个落点**：CI 的那一次全量跑，跑完由 `scripts/ci-summary.sh --check` 把基线与收据 `passed` 硬对齐；本地基线过期就会在 CI 响亮地红。本地同理：`bash scripts/verify-all.sh --fresh` 是唯一会跑整套的入口。
- **两道自测试并行是安全的**（v3.87.0）：audit 侧不再有隐式整跑，工作区锁（`lib-suite-lock.sh`）只约束"同一工作区同时只有一次全量套件"；`-T` 过滤跑不取锁（子用例靠它）。收据/红档/verify 产物路径全部可 `AGENT_GUARD_*` 覆盖，自测不污染真实台账。**CI 侧同样并行**：`source-audit` 已去掉 `needs: golden-case`（它只读入库基线，对套件运行无依赖），串行那一头曾是白等的 4 分钟，而且套件一红就完全不报审计发现。
- `run-tests.sh` 是**双布局自适应**的：在 Skill 仓库内跑全量；被 `--guard` 复制到目标仓库后，源路径自动回退、Skill 仓库专属用例（T11 安装器、T14b 安装器路径用例、依赖未装层的 T10/T12）自动 SKIP。

### 3.0 源层验证工具链（v3.87.0，CHG-115；全部**不下发**）

这六个工具 + 一个共享库是 B 面（源仓公开、不随 Skill 分发）。判据：**目标仓装完 Skill 看不见它们**，所以它们不进 `scripts/bootstrap.sh` 清单、不进 payload 模板字段，且 `run-tests.sh` 的 T69~T73b 在缺失时自动 SKIP（A56 钉这四件事同时成立）。

| 工具 | 一句话职责 | 常用调用 |
|---|---|---|
| `scripts/facts.sh` | 一次只读 JSON 快照：HEAD/分支/DS 版本/树指纹/脏文件/两个基线/套件收据新鲜度。**绝不跑套件**，实测 <1s | `bash scripts/facts.sh`；`--write` 落 `.agent-state/facts.json`（覆写：`AGENT_GUARD_FACTS_PATH`）；`--root DIR` 看别的检出 |
| `scripts/verify-all.sh` | 单串验证入口：release → ledger → audit → suite → **gate**（`ci-summary.sh --check`，把「入库基线 == 本次收据」这道 CI 头号硬门也在本地跑上），**失败全收集**（前面红不短路后面）；新鲜同树收据直接复用，`--fresh` 强制真跑；产 `.agent-state/verify-receipt.json` + 每步日志 | `bash scripts/verify-all.sh`；逐步跳过 `--skip-release` / `--skip-ledger` / `--skip-audit` / `--skip-suite` / `--skip-gate`（记为 `skip`，绝不算 pass）；`--jobs N`（别名 `-j N`，与它转发的套件同拼写）；落点覆写 `AGENT_GUARD_VERIFY_RECEIPT_PATH` / `AGENT_GUARD_VERIFY_LOG_DIR`；测试缝 `AGENT_GUARD_VERIFY_{RELEASE,LEDGER,AUDIT,SUITE,GATE}_CMD` |
| `scripts/pre-review-check.sh` | 把"可评审"里能机检的一半检查完：16 产物在位非空、FILL 残留、00.5 确认行、05 执行证据、责任人独立、07 署名与结论、溯源戳、载体一致、README 计数 vs 基线、`ls -d` 空 glob 陷阱。**只读** | `bash scripts/pre-review-check.sh [--change CHG-N] [--strict]`；`--strict` 把 warning 升成失败 |
| `scripts/mutation-check.sh` | 检查器自证：四类固定变异（DS 版本 / gate 版本 / 基线缺失 / README 计数）必须让对应快检查器变红；只在一次性副本里动手，前后对**全部 git 可见路径**（受跟踪 ∪ 未跟踪未忽略）做内容哈希比对，证明活树没变（含新增/删除），control 前后必须绿 | `bash scripts/mutation-check.sh`；`--list` / `--only NAME` |
| `scripts/ci-summary.sh` | CI 唯一真值面的两件事：`--check` 硬门（收据在位、failed=0、HEAD 对齐、**收据树指纹 == 当前树指纹**、`passed == tests/.suite-baseline`）+ 把运行渲染成 job 汇总（含"私有台账不推送也不在此校验"的口径声明与收据树指纹）。指纹判定与 `sf_receipt_fresh` 同一条规则，避免出现"复用面拒绝、CI 门接受"的两种信任。退出码：`--check` 是门（0/1/2=用法），默认渲染只报告恒 0——问题以 `Baseline/provenance problems: N` 出现在汇总里，而不是在写汇总之前把渲染步骤判红 | `bash scripts/ci-summary.sh --check` |
| `scripts/batch-metrics.sh` | 每批次成本台账：产物完整度（含 `handoff.md`，16 件）、两个基线、收据计数/墙钟、轮次/编辑/**轮询**/整跑次数、verify 总状态。TSV 为权威，JSON 每次由 TSV 重生成（两者不可能不一致）；值里的引号/反斜杠转义后再写，台账引用不会撑坏镜像。**verify 状态只读顶层 `status`（`sf_verify_status`）**——verify 收据的每个 step 也带同名字段，通用读取器取最后一个匹配会把「audit 红」的批次记成 `pass` | `bash scripts/batch-metrics.sh record [--batch ID]`；`report [--limit N]`；覆写 `AGENT_GUARD_BATCH_METRICS_PATH`（JSON，TSV 随之 `%json→%tsv`）或 `AGENT_GUARD_BATCH_METRICS_TSV_PATH`（只改 TSV） |
| `scripts/lib-source-facts.sh` | 上述工具的共享只读助手（JSON 读写、收据新鲜度 `sf_receipt_fresh`、基线解析）。**函数库，无顶层副作用** | 由工具 `source`，不直接调用 |

- **收据复用规则只有一份实现**：`sf_receipt_fresh`（同 HEAD + 同树指纹 + `failed=0` + mtime 新鲜度窗口）。`verify-all.sh` 与 `update-assertion-count.sh --check --require-receipt` 共享它（A56 末钉「verify-all shares the generator receipt-reuse rule」）——两处各写一份就会漂移，而漂移的表现是"某入口偷偷多跑 5 分钟"。
- `--require-receipt` 是**手动 fail-closed 开关**：无新鲜收据即 rc2，绝不退化成隐式整跑。给任何新入口选证据源时，优先级恒为：入库基线 → 新鲜收据 → 显式要求调用方自己跑。
- 版本载体、门面对称、基线数字这三类一致性由 `release.sh check` + A 组断言 + CI 硬门分担，**不要在新工具里再造第四份判定**。

### 3.1 第三道：把门禁指向**本仓自己的真实产物**（dogfooding，改门禁后必做）

前两道都在**夹具世界**里验证。夹具是维护者手写的，会不自觉地比真实产物**更规整**——而缺陷恰好住在规整与真实之间的缝里。本仓同时具备"真实产物"（`docs/changes/CHG-001..028`、`docs/bugs/` 缺陷组）和"自己的门禁"（`resources/templates/agent-gate.sh`），是最便宜的自测素材：

```bash
# 只读沙箱（不要在本仓直接跑）：复制真实 docs/ + 门禁，在临时仓库里跑
T=$(mktemp -d); cp -R docs "$T/docs"; mkdir -p "$T/scripts"
cp resources/templates/agent-gate.sh "$T/scripts/agent-gate"
cp resources/templates/agent-governance.yml "$T/.agent-governance.yml"
cd "$T" && git init -q . && git add -A >/dev/null && git -c user.email=a@b -c user.name=a commit -qm x
bash scripts/agent-gate metrics     # 每条记录的风险等级都该读出来，不该是 null
```

**两条实测教训**——都是"夹具比真实产物规整"造成的盲区，各跨了两个版本才被发现：

| 版本 | 夹具写的形状 | 真实/文档要求的形状 | 后果 |
|---|---|---|---|
| v3.19.0 | `#### 执行记录（ReAct）` | §2.16.2 **强制**的 `## Observation` | 批次被自己强制的内容卡死（§7.5-9） |
| v3.20.0 | `printf '{"change_id":...}\n'` **单行** | 随包模板 `governance-state.json` 的**多行** | 照文档生成的记录被自己的门禁拒绝（§7.6-15） |

> **更一般的规则**：校验器的自测必须**同时覆盖"最规整的输入"与"文档教用户写的那种输入"**。两者不一致时，缺陷就在中间。

---

## 4. 断言数生成器

```bash
bash scripts/update-assertion-count.sh                    # 写模式：必要时实跑套件取运行期实出数，同步双 README + tests/.suite-baseline
bash scripts/update-assertion-count.sh --check             # 只检查，漂移即 exit 1（绝不写文件）
bash scripts/update-assertion-count.sh --check --from-baseline
                                                          # 读入库基线判定（源审计 A3 用这条）；绝不跑套件
bash scripts/update-assertion-count.sh --check --require-receipt
                                                          # 只允许新鲜同树收据作证据；无收据即 exit 2，绝不退化成隐式整跑
```

它管**三件事**，且顺序有讲究：

1. **README 声称数** ← `run-tests.sh` **实际运行的通过数**（`N passed`；CHG-019 复核后改为运行期口径——静态调用点计数漏计同链双调用 `grep … && report … || report …` 与循环站点，曾致 281↔284、288↔291 两代 3 格漂移）。红套件拒同步（exit 2）。
2. **`tests/.suite-baseline`（v3.87.0/CHG-115）** ← 同一份运行期实出数；写模式与 README 一起同步，所以"入库基线"永远是最近一次真实绿跑的声明。**`--from-baseline` / `--require-receipt` 两种快模式绝不写文件**：基线缺失/非数字、两模式同时给出、`--require-receipt` 无新鲜收据，一律 exit 2（fail-closed，宁可拒绝也不隐式跑 5 分钟）。注意 `--from-baseline` 只声明"声称面与入库基线一致"，**不证明基线新鲜**——新鲜度由 CI 那一次真跑 + `ci-summary.sh --check` 兜（本地同理：`verify-all.sh`）。
3. **`tests/.audit-baseline` 执行数基线** ← 由**上一次审计运行**写出的 `${TMPDIR:-/tmp}/audit-executed-count`（闭 FU-022）。
4. **gate（`verify-all` 第五步，v3.87.0/CHG-115 R4）** ← 第 1~2 项同步完才有意义：改动断言数后第一次 `--fresh` 跑，本步**必然转红**（"收据条数 ≠ 入库基线条数"就是它要喊的内容），随后跑生成器同步、再跑 `verify-all`（收据复用，不重跑整套）转绿。红在这里不是故障，是"去同步"的指令。

> ⚠️ **顺序坑**：第 3 项读的是审计的**运行产物**。所以正确顺序是
> **先跑 `audit-standards-src.sh`，再跑 `update-assertion-count.sh`**。
> 反了的话基线会同步到上一轮的旧值，审计继续报 A10 不匹配——这不是脚本坏了，是顺序反了。

---

## 5. 审计脚本的 PART A / PART B

`tests/audit-standards-src.sh` 的断言分两区，**防脚本腐烂**：

- **PART A（永久结构不变量）**：无论规范升到哪一版都必须成立——版本链同源、§3↔§4 清单同源、编号体系收录、占位符 vs A 层断言防恒真、骨架 vs A 层关键词、树↔磁盘、日志排序。
- **PART B（版本快照）**：锚定某一版的落点。规范升级时**必须随 §2.14 日志一起更新**，否则脚本会因"快照过期"而红。

新增断言时想清楚它属于哪一区：**写成 PART A 却依赖某一版的具体措辞 = 下一版必红**。

### 5.1 规范体量上界（A11）与它的重校准

`A11` 断言 `resources/DEVELOPMENT_STANDARDS.md` 不超过一个硬上界（当前 **168 KB / 172,032 字节**，v3.89.0 自 164KB 按 +4KiB 步进重校准——CHG-117）。它不是"防内容变多"，而是**防无序回弹**——上界一旦失效，规范就会无声地膨胀下去。

**重校准是设计内的动作，不是破例**，但必须满足两个条件：

v3.43.0 重校准记录（CHG-053）：156KB 上界被 §2.17.2b 缺陷发现入口（三信号双通道 + 频控 + 自主权，160,160 字节）吃到负值 → 按 KiB 步进（+8KB，跨 4KB 档取整）重设 **164KB**（余量约 7.5KB），有 CHANGELOG v3.43.0 行对应。
v3.68.0 重校准记录（CHG-043 同版本收尾，2026-10-12 用户裁定"校准"）：164KB 上界的余量先被 v3.67.0 UX 体系压到 455B，再被 v3.68.0 三维对照门禁族（G13/G14，5 条款）吃到 **170,735 字节**（破线 2,799B）→ 按 KiB 步进（+8KB）重设 **172KB**，有 CHANGELOG v3.68.0 行勘误注对应。**配对减法纪律**：下次触软警线（171,008B）必须走结构性减法，禁止连续重校准；减法低垂果实 v3.61.0（FU-911）已摘尽，再减须动硬结构（权威锚点全量重验），另立 CHG。
v3.70.0 回转记录（CHG-045，2026-10-13 用户"体积要控制"+配对纪律兑现）：172KB 上界被存量法下沉（FU-936，形状迁 entry 模板×4+工具头注释+playbook 瘦身）减至 **167,610 字节** → 上界**回转 164KB**（软警 163,840B 即时常亮=下次结构增长的减法触发器）。**注**：盘点估值 13KB 偏高，无语义损失可移出的形状实为 ~3.2KB——剩余内容均为机校语义/权威定义（L 类），进一步减法须动硬结构。
v3.89.0 重校准记录（CHG-117，2026-10-24）：164KB 上界（167,936B）被 §2.17.2b 信号③专句 + §2.16.2 阶段门执法点 + §2.17 阶段门/无账门专段（REQ-1199~1203，含设计门补齐 03.5）吃到 **165,937 字节**（软警 163,840B 之上、硬上界之下，A11s 先亮）→ 按 **+4KiB 步进**重设 **168 KB（172,032 字节）**（余量 6,095B；独立评审指出 +8KiB 放宽过多，已按 +4KiB 收敛），有 CHANGELOG v3.89.0 行对应；软警线随上界 −4KiB = 167,936B。**配对减法纪律**：下次触软警线必须走结构性减法，禁止连续重校准。

1. **有 CHANGELOG 条目对应**（新条款必须登记）；
2. **先压缩再抬高**：把重复条款合并、把机制细节下沉到脚本头部注释（渐进披露），能省多少先省多少。

> **历史重校准记录**（v3.31.0 / v3.29.0 / v3.25.0 / v3.21.2 / v3.17.0）见 `resources/STANDARDS_CHANGELOG.md` 对应版本行。**五次的教训完全一致**：每次都是上一版把余量吃到几字节（最低 3 字节），所以必须按 KiB 步进重设，**不得贴合当前体量**。

**顺序坑**：抬高上界后必须重跑审计，确认 A11 通过且没有掩盖别的失败。

**软预警档（v3.58.0，REQ-1008）**：audit 新增 `A11s`——DS ≥163,840B（硬上界 −4KiB）即 soft warn（`report_soft` 桶，A3/A6/A10 同构）。进预警区的动作=**先减法再新增**（巨行指针化/枚举收敛/死文件清理），禁止无对应重校准的硬挤。**持续减法条款（v3.58.0）**：每个 minor 版本交付前跑一次三线审计（语义/去重/机械，只读子代理），候选即发现即登记不积压（R3→CHG-071 清账、CHG-072 收口为先例）。

**大文件体量台账（v3.58.0 实测口径）**：DS（A11 有界）；STANDARDS_CHANGELOG（FU-903 政策冻结，追加式）；run-tests（明示无界——测试可读性优先，helper 收敛尾量由 FU-906 跟踪）；audit-standards-src（明示无界——A10 基线+PART A/B 结构承载）；agent-gate / bootstrap / install-hook-adapter（明示无界——单文件零依赖部署契约）；MAINTAINER / README×2（明示无界——维护者文档）。上界类文件仅 DS 一件；新增 >40KB 文件须在本台账登记治理状态。

### 5.2 加一删一预算（减法机制，v3.40.0 CHG-048 / FU-106⑥）

规范只加不减 = 无限膨胀。A11 上界是**体量**准绳（防无序回弹），本节是**条款数**准绳（防只进不出）：

1. **每新增一条规范条款**（REQ/门禁/机器断言/模板必填件），同一版本内**对等淘汰**一条既有条款，或在 09「重要上下文」登记**预算豁免理由**（为何本条不可裁剪既有条款）。
2. **淘汰必须有痕**：规范内「废止」字样同行必须携带被替代版本指向（`v3.x`）——通用层审计 **G10** 机校此形态（缺指向 = 只废未清，FAIL）；被替代条款的机器断言与模板引用**同版本清扫**，禁止留死断言。
3. **优先减法序**：合并重复条款 > 机制细节下沉脚本注释（渐进披露）> 删除未命中条款 > 抬上界。前三条走不通才允许上界重校准（§5.1 两条件仍适用）。
4. 预算执行情况为 **B 层**核对项（评审角色逐版本核对 CHANGELOG 条目的加/减平衡），不做条款计数机校（M2 未命中即启用 = 过度设计）。

> **v3.89.0 预算豁免登记（CHG-117，2026-10-24）**：新增 5 条 REQ（REQ-1199~1203——无账源码改动信号③双层执法、SKIP_VERIFY 收窄、G16 披露面、无状态阶段门、check 阶段感知），均为新执法能力面，同版本内无可对等裁剪的既有条款——预算豁免登记于此（先例 v3.43.0「4 REQ + 2 模板件」同形态）；体量侧处置见 §5.1 v3.89.0 重校准记录。

> v3.45.0 注：断言层的预算与退役流程见 **§5.3 断言生命周期**（soft 桶 + 近两版捕获评审阶梯）；本节保持条款级，不与断言级混算。

### 5.3 断言生命周期（v3.45.0 CHG-055，Top3 装牙）

audit（源层）与 golden（通用层）断言只进不出 = 维护税复利。本节给断言装退役通道：

1. **四类标注**：新断言入册时在调用点注释标类型——〔结构〕存在性/机校逻辑、〔措辞〕关键词落点、〔行为〕运行时计算、〔计数〕表格/清单行数。
2. **近两版捕获评审**：每版本交付评审时核对——某措辞/计数类断言**近两版未捕获过真问题**（拦到漂移/缺陷）→ 列候选。
3. **阶梯处置**：候选断言先降 soft（audit 走 `report_soft`，CI warn 不阻断）观察一版；仍无捕获 → 退役（删除 + SLOG 行 + 09 登记，G10 式有痕）。结构/行为类不适用本阶梯（存在性防线不可降）。
4. **soft 桶滥用防线**：每次 `report_soft` 新调用必须在变更 09 登记（名称 + 理由），评审核对；禁止把硬断言静默改 soft。当前 soft 面：A3 数字闭环 / A3c 同步 / A10 基线（仅 `AGENT_GUARD_AUDIT_SOFT=1` CI 模式，本地恒硬）。
5. 自指断言（grep 断言所在脚本自身的字符串）无值守价值，入册即列退役候选。

---

## 6. 版本号三载体（平台事实）

平台的 Skill frontmatter **没有** `version` 字段，`/skills` 面板也只展示 name + description。所以版本号必须落在**三处**，缺一用户就看不出自己是不是最新版：

1. frontmatter `version:` —— 机器可读；
2. `description` 尾注 —— 技能列表 / 模型上下文可见；
3. 正文顶部版本横幅 —— SKILL.md 被加载即可见。

三处与**规范页脚**同源（页脚是唯一权威源，其余均为其派生），由 `audit-standards-src.sh` 的 A1 断言守护。**升级规范时页脚 + 这三处一起改，漏改即审计红。**

---

## 7. 逐版本升级推送清单

已经接入过的项目**不会自动更新**——需要用户再次调用本 Skill，走"检测已有文件 → 展示版本差异 → 询问是否升级"流程，或直接 `bash scripts/bootstrap.sh --upgrade <目标仓库>`。各版本新增/变更的补复制动作如下（保留**原有最近 5 行**，即 v3.83.0~v3.79.0；更早版本见下节手工表与 CHANGELOG）（**新条目置顶**；**口径（v3.58.0 统一）：每行必含 CHG 号 + REQ 号（REQ 引用多个逗号列出）**；**TC 注册口径（v3.58.0）**：T 块号即注册单位，TC-xxxx 为用例名——v3.56.0 的 TC-1061/1062=T46（E85 三断言），此后新 TC 在 SLOG 行内点名）：

| 版本 | 升级后需要补什么 |
|---|---|
| **v3.83.0** | **verify 结果按输入指纹缓存（保守档）（CHG-110，REQ-1161）**：`suite_tree_fingerprint` 追加式 reset-claim 变参（既有调用不变）；agent-gate verify 通道 receipt 缓存——键=gate 版本+vcmd sha256+树指纹（docs/changes claim 排除）+变更号，TTL 默认 30min，只缓存 rc=0，AGENT_GUARD_VERIFY_CACHE=0 退出，非 git 仓降级直跑；外部状态依赖测试仓须 opt-out（边界入 usage/CHANGELOG）。golden T66（TC-1414 九态矩阵）+ audit A53（SC-1860）；UAC 补中文「N 条」声称形态。**`--upgrade` 带走 agent-gate/lib-suite-tree-fingerprint/SKILL/README×2/DS/METHODOLOGY×6 版本行/CHANGELOG 版本行**。**回填义务：无**。 |
| **v3.82.0** | **秒级形状探针 + verify 睡眠防护 + 遥测失联兜底（CHG-109，REQ-1160）**：目标仓复盘反馈三条同批闭环（no-leftover）。`agent-gate` preflight 探针扩面：`validate_delivery` 拆 `validate_delivery_shape_front/back` 纯函数（die 站点/执行序字节不变）纳入 p_run collect-all，交付形状锚（E85/E114/E115/E117/E46）秒级反馈，E116 写台账面排除；verify 通道 `caffeinate -dims` 包裹（darwin 缺失警示）；`install-hook-adapter` 装后逐 harness 自证 PASS/FAIL + status 指引；`begin` 遥测失联 `YELLOW liveness` 软黄灯（water 新鲜而 stats 缺失/过期 >10min）。golden T65（TC-1411~1413）+ audit A52（SC-1859）。**`--upgrade` 带走 agent-gate/install-hook-adapter/AGENTS/SKILL/README×2/DS/METHODOLOGY×6 版本行/CHANGELOG 版本行**。**回填义务：无（探针/黄灯/自证升级即生效，无需重跑 install-hook-adapter）**。 |
| **v3.80.0** | **批次产物 scaffold + 分阶段最小读集（CHG-107，REQ-1152~1154，DES-1917~1918，TC-1400~1405）**：`agent-gate begin <id> --scaffold` 一条命令生成 8 件批次产物骨架——形状契约单源化到生成器（目录落位/五要素/确认状态 fail-closed/预期结果/开放问题/业务影响/风险/回滚/延伸/检索/编号自动续接台账），幂等 fail-closed，端到端钉锁死（scaffold→填充→begin 一次过）；分阶段最小读集（纪律 15 + R65 + DS §2.9.6 指针：begin §1.1/§2.5、编码 R 行锚点、测试 §2.13/§2.17.4、stop §2.13/§1.3，规范文档永不整读）。**升级后无手工动作**；批次文档成本 ~14 轮→1-2 轮。 |
| **v3.79.1** | **全项目 review 措辞修复（CHG-105，REQ-1148~1150，DES-1914~1915，TC-1389~1396）**：DS 术语单名化（§2.13 证据行「同树快照」→「同树指纹」）+ UAC 空指纹拒采子标签双因表述（源层私有件）。零行为变更——收据 schema/采信语义/下发清单不变，**目标仓升级无动作**；DS 等长替换 167,928 B 不变，A48 棘轮不重校准，断言 1052/审计基线 543 不变。 |
| **v3.79.0** | **suite receipt 树指纹（CHG-103，REQ-1142~1147，DES-1909~1913，TC-1378~1388）**：收口快路径采信由「同 HEAD + TTL」收紧为「同 HEAD + **同树指纹** + TTL」——收据增 `tree_fingerprint`（临时索引全树快照，单源 `scripts/lib-suite-tree-fingerprint.sh`，emitter/consumer 同源；声明文件 README×2/`tests/.audit-baseline` 排除——UAC 自身改写面，计入则同步后恒失配），旧 schema 收据/指纹为空/不等一律回落内嵌整跑（反向兼容 fail-closed，永不 fail-open 到错数）；DS 采信句与 05 `reused` 标注规则入文。**`--upgrade` 补复制**：`tests/run-tests.sh` + **`<scripts>/lib-suite-tree-fingerprint.sh`（新增下发件，随 --guard 同包）**、`<docs>/DEVELOPMENT_STANDARDS.md`；**agent-gate 治理工具白名单已同步 lib**（首装 commit 不死锁）。**动作**：目标仓升级后 emitter 即生效（绿全跑收据含真指纹）；UAC 收口工具不下发，收据消费按 DS 语义自接线；无配置项。 |

**历史版本（v3.78.0 及更早）的逐版动作不再在此罗列**——那是会过时的信息，且与 `resources/STANDARDS_CHANGELOG.md` 重复（该文件才是权威）。下面这张表只收**`--upgrade` 不会自动处理、必须人动手**的项；其余由 `--upgrade` 覆盖，逐版细节查 CHANGELOG 对应行：

| 版本 | 必须手工做 |
|---|---|
| v3.78.0 | 分支保护必检项**保持 job 名 `agent-governance`**（该版起为聚合 job，改名 = 静默失效） |
| v3.76.0 | `LIVE_SKIP` 方言自检：升级后确认 `bugfix-log`/`delivery-summary`/`06.5` 未被覆盖 |
| v3.67.0 | 总册 P12 产品上下文册需**人工回填**（模板可生成，内容不可代填） |
| v3.37.0 | 总册册号 `P` 前缀改名：旧仓需按 CHANGELOG 行重命名 `docs/project/` 下文件 |
| v3.15.0 | `agent-gate` / `check-standards-compliance.sh` / `audit-docs-consistency.sh` **三者必须一起升**（只升其一即静默错位） |
| v3.7.0 修订 | 补齐 `06.5-deployment-config.md` 与 `06-delivery-summary.md`（未命中也要显式声明） |
| v3.7.0 | 补缺陷六件套模板 + `coding-record.md` |
| v3.6.0 | 补缺陷三件模板（`bug-diagnosis`/`bug-impact`/`bug-test-plan`） |
| v3.5.0 | 补 `commit-msg` 模板 |
| v3.3.0 / v3.4.0 | 补 `METHODOLOGY.md` + `methodologies/` + `bugfix-log.md` |

> 更细的"本版改了什么、对既有文档有什么回填义务"，以 `resources/STANDARDS_CHANGELOG.md` 为准——**本表只是升级动作的速查，不复制变更条款**。

---

## 8. 自进化与派生资产

本 Skill **允许 Agent 自进化**：基于它派生出的、面向特定项目/特定 Agent 优化的 Skill（例如 `gated-defect-fix`、`verify-dev-standards-install`）**独立存在**，不回收到本仓库。

代价是升级时可能覆盖派生资产。防护契约见 `SKILL.md` 的「Agent 自进化契约」节：派生方在 frontmatter 声明 `agent_created: true` + `derived_from`，安装器的**每一条**升级路径跳过带 `derived_from` 的目录（`--force` 也不越过），并提供只读的 `--derived-report`。

**维护本 Skill 时的注意**：源仓**不应**出现派生 Skill 的**资产副本**（`skills/<name>/SKILL.md`、其脚本与模板），也不应出现**指向它们的可执行路径引用**（命令、脚本调用、安装清单条目）。

判定口径是"有没有可执行/可安装的副本或路径"，**不是字面零命中**——本文件本节、以及解释这条契约的说明性文字里出现派生 Skill 的名字（举例）不算引用。实测：

```bash
# ① 名字只应出现在解释性文字里：本文件本节 + docs/review/ 的历史评审（不进版本控制、不下发）
grep -rn 'gated-defect-fix' --include='*.md' --include='*.sh' .
# ② 分发载荷必须零命中 —— 这条是硬断言（resources/** 会复制到每个目标仓库）
grep -rnE 'gated-defect-fix|verify-dev-standards-install' resources/ && echo "DEFECT" || echo "ok: payload free of derived names"
# ③ 不得存在可安装/可执行的引用面（副本、脚本调用、安装清单条目）
grep -rnE 'gated-defect-fix|verify-dev-standards-install' scripts/ tests/ SKILL.md && echo "DEFECT" || echo "ok"
```

> 判定口径（2026-09-16 全项目 review，**两轮收敛**）：本节初版写"全仓 grep 零命中是正确状态"——被**本文件自身的举例**证伪；第二版改成"只应命中解释性文字，**且仅在 MAINTAINER.md**"——**仍不成立**：随分发的 `resources/DEVELOPMENT_STANDARDS.md`「Agent 自进化与派生资产」节当时也举例了两个派生名（该举例已于 v3.21.2 删除，概念保留、名字不留）。**结论：口径必须按"面"分**——解释性文字可以有（本文件 + `docs/review/` 的历史评审；实测命中集合还包括 `.workbuddy*/memory` 的会话笔记，它们被 `.gitignore` 忽略、不进仓库，同属解释性面），**分发载荷（`resources/**`）与可执行面（`scripts/`、`tests/`、`SKILL.md`、安装清单）必须零命中**。
> 注：脚本内用 `grep -E` 而非 `\|` 交替——BSD grep 的 BRE 不支持 `\|`，本机实测恒空。

## 8.5 研究依据（v2.18.0 实证；v3.70.0 CHG-045 自 DS §2.17 形状移入，唯一权威落点）

「状态外置、只信磁盘」的实证——CIKM '26《The Compaction Cliff》（[arXiv:2608.22752](https://arxiv.org/abs/2608.22752)）：/compact 一轮后安全规则仅存 53%、五轮后 10%，去验证器的系统「报告 100% 保留、实际静默丢失 57% 约束」；流程侧（意图漂移、决策不可复盘、事故不回流）见 Anthropic《[The AI-Native SDLC Playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)》。故铁律：治理状态外置磁盘产物；写盘后以 shell 级验证（`grep -c`/`wc -l`/`git diff`）确认落盘，不采信工具返回值或 Read 缓存；门禁只读磁盘与 git。DS §2.17 原位保留一行指针与本不变量句。

## 9. 源仓/目标仓边界（source vs target separation，CHG-070 立规）

**铁律：源仓自身的开发变更不得混入、更不得改变下发给目标仓的通用能力语义。** 评估任何源仓变更前先回答一个问题：**"这次改的是源仓自身，还是 skill 通用能力？"** 两类变更的评估准绳、影响面、CI 语义完全不同：

| 维度 | 源仓自身（source-only） | 通用能力（shipped payload） |
|---|---|---|
| 治理产物 | `docs/changes`、`docs/bugs`、`bugfix-log.md` **本地存在、不入库**（`docs/*` 忽略，CHG-017 裁定 2026-09-16 维持） | 目标仓的 `docs/` 是 skill 规定的能力面：**必须入库**，由 shipped 执法面（gate begin/stop + `audit-docs-consistency.sh` + CI）保证 |
| 审计 | `tests/audit-standards-src.sh` 只跑源仓（不下发）；其断言可依赖/豁免源仓本地态（如 A6 族 soft 化，CHG-070） | 目标仓执法 = gate + `audit-docs-consistency.sh` G1–G10 + `.github/workflows/agent-governance.yml`，**不受源仓 audit 断言调整波及** |
| 变更判据 | 改 CI/忽略/源层审计=源仓自身事务（如 A6 soft 化只因此成立） | 改 `resources/**`、gate 模板、规范正文=通用能力变更，必须以目标仓视角独立评估（所有目标仓可重现的行为） |

**反面教材（本仓实证）**：CI source-audit 恒红五日（2026-09-22 起）——根因即把"源仓 docs/ 不入库"（源仓自身事务）与"A6 断言"（源层审计断言）耦合后未按本节区分处置；修复时若误将 soft 桶推广到 shipped 面即违反本铁律。**自查命令**：改动涉及 `resources/**` 或规范正文时，任何"仅源仓如此"的理由都不可用。
