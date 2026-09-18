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
| `resources/templates/**` | 落到目标仓库的模板与脚本 | ✅（按清单逐项） |
| `scripts/bootstrap.sh` | 清单驱动安装器（**清单即单一权威源**） | ✅ |
| `scripts/install.sh` | 一键安装/升级器（v3.22.0，源层工具）：克隆 checkout + 薄委托 bootstrap，**不复制任何安装逻辑**；`--as-skill` 把 Skill 本体以 symlink 注册进 AI 客户端技能目录（不动目标仓，与安装/升级模式互斥） | ❌（不随 Skill 分发，同 bootstrap.sh 自身） |
| `CHANGELOG.md` | 项目级版本历史（用户可感知变更）；规范条款级历史在 `resources/STANDARDS_CHANGELOG.md` | ❌ |
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
| 断言增删 | `scripts/update-assertion-count.sh` → 再跑审计（A3 声称数 / A10 执行数基线）。**`tests/.audit-baseline` 只由生成器写，禁手工改**；顺序坑见 §4 |
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
bash tests/run-tests.sh            # 通用层：golden cases，断言 agent-gate 的退出码与输出
bash tests/audit-standards-src.sh  # 源层：版本链 / 关键词落点 / §3↔§4 同源 / 树↔磁盘 …
```

- **改脚本 → 必须先跑通 `run-tests.sh`**（§2.17.4 硬性要求）。
- **改规范正文 / 模板 / README → 必须先跑通 `audit-standards-src.sh`**。
- `run-tests.sh` 是**双布局自适应**的：在 Skill 仓库内跑全量；被 `--guard` 复制到目标仓库后，源路径自动回退、Skill 仓库专属用例（T11 安装器、T14b 安装器路径用例、依赖未装层的 T10/T12）自动 SKIP。

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
bash scripts/update-assertion-count.sh          # 实跑 run-tests.sh 取运行期实出数并改写双 README
bash scripts/update-assertion-count.sh --check  # 只检查，漂移即 exit 1（CI/审计模式）
```

它管**两件事**，且顺序有讲究：

1. **README 声称数** ← `run-tests.sh` **实际运行的通过数**（`N passed`；CHG-019 复核后改为运行期口径——静态调用点计数漏计同链双调用 `grep … && report … || report …` 与循环站点，曾致 281↔284、288↔291 两代 3 格漂移）。红套件拒同步（exit 2）。
2. **`tests/.audit-baseline` 执行数基线** ← 由**上一次审计运行**写出的 `${TMPDIR:-/tmp}/audit-executed-count`（闭 FU-022）。

> ⚠️ **顺序坑**：第 2 项读的是审计的**运行产物**。所以正确顺序是
> **先跑 `audit-standards-src.sh`，再跑 `update-assertion-count.sh`**。
> 反了的话基线会同步到上一轮的旧值，审计继续报 A10 不匹配——这不是脚本坏了，是顺序反了。

---

## 5. 审计脚本的 PART A / PART B

`tests/audit-standards-src.sh` 的断言分两区，**防脚本腐烂**：

- **PART A（永久结构不变量）**：无论规范升到哪一版都必须成立——版本链同源、§3↔§4 清单同源、编号体系收录、占位符 vs A 层断言防恒真、骨架 vs A 层关键词、树↔磁盘、日志排序。
- **PART B（版本快照）**：锚定某一版的落点。规范升级时**必须随 §2.14 日志一起更新**，否则脚本会因"快照过期"而红。

新增断言时想清楚它属于哪一区：**写成 PART A 却依赖某一版的具体措辞 = 下一版必红**。

### 5.1 规范体量上界（A11）与它的重校准

`A11` 断言 `resources/DEVELOPMENT_STANDARDS.md` 不超过一个硬上界（当前 **144 KB / 147,456 字节**）。它不是"防内容变多"，而是**防无序回弹**——上界一旦失效，规范就会无声地膨胀下去。

**重校准是设计内的动作，不是破例**，但必须满足两个条件：

1. **有 CHANGELOG 条目对应**（新条款必须登记）；
2. **先压缩再抬高**：把重复条款合并、把机制细节下沉到脚本头部注释（渐进披露），能省多少先省多少。

v3.31.0 的重校准记录（最近一次，供下次参照）：§2.1 规则 10（角色单一职责）+ §5 反模式行把 140 KB 上界的余量吃到 **-220 字节**（先压缩两处措辞仍压线），按 **KiB 步进（+4 KB）**重设到 144 KB。

v3.29.0 的重校准记录：§2.1 九专家行 + §2.2 评审矩阵把 132 KB 上界的余量吃到 **3 字节**（v3.25 同型——上界事实上再次失效）；先做两轮措辞压缩（仍超 136 KB 约 1.6 KB），再按 **KiB 步进（+4 KB）**重设到 140 KB。

v3.25.0 的重校准记录：v3.24.0 的表达成本条款把 128 KB 上界的余量吃到 **3 字节**，按同协议重设到 132 KB。

v3.21.2 的重校准记录：v3.21.1 + v3.21.2 两轮对齐修正把 124 KB 上界的余量吃到 **193 字节**；先做压缩（删除规范正文里的变更日志式括注、把派生资产判定口径收成一句），再按 **KiB 步进（+4 KB）**重设到 128 KB，余量 **4,289 字节**——同样不按当前体量贴合。

v3.17.0 的重校准记录：v3.16.0 的改动已把 120 KiB 上界的余量吃到 **53 字节**，上界事实上已失效；本版先做压缩（合并三条重复条款 + 机制下沉）把净增压到 **1,035 字节**，再按 **KiB 步进（+4 KiB）**重设——**不按当前体量贴合**，否则下一次任何实质新增又会立刻撞墙。

**顺序坑**：抬高上界后必须重跑审计，确认 A11 通过且没有掩盖别的失败。

---

## 6. 版本号三载体（平台事实）

平台的 Skill frontmatter **没有** `version` 字段，`/skills` 面板也只展示 name + description。所以版本号必须落在**三处**，缺一用户就看不出自己是不是最新版：

1. frontmatter `version:` —— 机器可读；
2. `description` 尾注 —— 技能列表 / 模型上下文可见；
3. 正文顶部版本横幅 —— SKILL.md 被加载即可见。

三处与**规范页脚**同源（页脚是唯一权威源，其余均为其派生），由 `audit-standards-src.sh` 的 A1 断言守护。**升级规范时页脚 + 这三处一起改，漏改即审计红。**

---

## 7. 逐版本升级推送清单

已经接入过的项目**不会自动更新**——需要用户再次调用本 Skill，走"检测已有文件 → 展示版本差异 → 询问是否升级"流程，或直接 `bash scripts/bootstrap.sh --upgrade <目标仓库>`。各版本新增/变更的补复制动作如下（**新条目置顶**）：

| 版本 | 升级后需要补什么 |
|---|---|
| **v3.34.0** | **四项打包**：gate L0/L1 评审独立机校（FU-042 闭环）+ metrics `expert_sessions` 观测字段 + session-gate 规则 10 自查表注入 + 能力卡合规样例——`--upgrade` 带走 agent-gate/session-gate/expert-capabilities 三件。**无回填义务**。golden 310。 |
| **v3.33.0** | **gate 执法收紧（FU-039/041 闭环）**：`scripts/agent-gate` 升级即得——治理记录必填 `spec_author`（全等级）、L2/L3 四主体互异、01/03 的「专家评审记录」节强制 §2.1.7 署名（stop/CI）。golden 308。**存量仓唯一动作**：升级后首个新变更的 00-governance.json 按模板声明 `spec_author`（模板已含）。 |
| **v3.32.0** | **对齐+两批制条款**：规范 §2.2 两批制/规则 10 补锚/DoD 补项、`agent-governance.yml`+`stamp-provenance.sh` 注释计数修正（v3.29.1 未落盘缺陷）、`resources/AGENTS.md` 门禁 1 与锚点表、bootstrap --help、能力卡索引补行——`--upgrade` 一次带走。**无回填义务**。FU-041 登记（gate 硬校验，与 FU-039 合并承载）。 |
| **v3.31.0** | **新规范性条款**：§2.1 规则 10（角色单一职责，作者/实现/测试/评审四主体互异）+ `governance-state.json` 模板增 `spec_author` 字段 + §5 "一人多角色"反模式行 + `expert-capabilities.md` 理论出处索引节——`--upgrade` 一次带走。**回填义务：无**（`spec_author` 只约束新变更）。源层：A11 重校准 140→144 KB（协议步进）。 |
| **v3.30.0** | **新方法论层文件**：`resources/methodologies/expert-capabilities.md`（专家能力卡）——`--upgrade` 自动带走（复制清单已扩）；规范 §2.2 新增能力卡条款（组合表不变）。**无回填义务**。源层：audit methodologies 动态遍历自动纳入新文件页脚断言（断言 279→282，生成器重写 .audit-baseline）。 |
| **v3.29.1** | **对齐续修（无新规范条款、无行为变更、无回填义务）**：规范正文（计数 15 件、§2.2 措辞与钩子、§3/§5 补行）、`resources/AGENTS.md`（角色段 §2.2 衔接）、`resources/METHODOLOGY.md`（双视角行）随 `--core`/`--upgrade` 下发；双 README 能力表补 2 行；CHANGELOG 补 3.28/3.29 节。门禁/golden 零改动。 |
| **v3.29.0** | **新规范条款（§2.2 分阶段专家评审矩阵）**：`resources/DEVELOPMENT_STANDARDS.md`（§2.1 +9 专家行 + §2.2 新节 + §0.5.2 联动注 + §2.5 阶段 1/2/3/4/5/8 验收行补句）、`resources/AGENTS.md`（锚点表 §2.2 行）随 `--core`/`--upgrade` 下发即可，**无回填义务**（新条款只约束新变更；存量产物不含「专家评审记录」节属合法空转）。门禁/golden 零改动。源仓侧：源层审计 **A11 上界 132KB→140KB 重校准**（v3.29.0 依据：§2.1/§2.2 专家条款演进，两轮措辞压缩后仍超 136KB 约 1.6KB，按 KiB 步进）——`tests/audit-standards-src.sh` 为源层工具不下发，目标仓零影响。§5.1 的"当前上界"句一并更新。 |
| **v3.22.0** | **唯一载荷变更**：`resources/templates/stamp-provenance.sh`（新增 `--all` 全量盖章，默认行为逐字节不变）。已接入项目 `--upgrade` 带过去即可，**无回填义务**——`--all` 是可选加强，不跑它行为与升级前一致。源仓侧同步：`scripts/install.sh`（新增，源层不下发）、双 README 重写 + 新增 `CHANGELOG.md`、`SKILL.md`（一句话安装路径 + `--all` 溯源行 + 版本载体）、源层审计 A19 语义修正（溯源块 ⊆ 活跃∪已闭合）+ A23 锚点组、golden T17b/T21。另修复 `resources/templates/stamp-provenance.sh` 未入库缺陷（此前全新 clone 后 `--guard` 安装必失败）。 |
| **v3.21.2** | **同上——纯对齐续修，无新规范条款、无行为变更、无回填义务**（10 条，逐条见 `resources/STANDARDS_CHANGELOG.md` 顶部行）。承接 v3.21.1 的独立复核发现：规范正文删去派生 Skill 名举例、校正 01.5 边界句措辞；`SKILL.md` 补上"仅当现值仍是内置默认"的条件；`agent-governance.yml` 的 `required_before_merge` 与门禁对齐（3 → 5 件）；`scripts/bootstrap.sh` 的派生改三态判定（消掉自定义根安装时的假 NOTE）；`MAINTAINER.md` §8 口径按"面"收敛。**建议同步**：`resources/DEVELOPMENT_STANDARDS.md`、`resources/templates/agent-governance.yml`、`SKILL.md`、`scripts/bootstrap.sh`（`--upgrade` 一次带过去即可）。**无回填义务**——历史产物与目录布局逐条不变。 |
| **v3.21.1** | **纯对齐修正——无新规范条款、无行为变更、无回填义务**（15 条，逐条见 `resources/STANDARDS_CHANGELOG.md` 顶部行）。门禁判定强度、产物文件名、目录布局逐条不变，已闭合的历史产物保持原样即合规。**建议同步的副本**（拿对齐后的版本即可）：`scripts/check-standards-compliance.sh`（自定义 `<change_root>` 不在 `<docs>/` 下时不再假红）、`.agent-governance.yml`（读取方清单补 `stamp-provenance.sh`）、`resources/templates/` 下的 `06-delivery-summary.md` / `06.5-deployment-config.md` / `PULL_REQUEST_TEMPLATE.md` / `github-artifact-pipeline.yml`（骨架任务号统一为 `TASK-`）。**曾用自定义根部署过的仓库**另需重跑 `bash scripts/bootstrap.sh --all --upgrade <目标仓库>`：本版修掉了 `--docs-dir` 会把显式 pin 的 `change_root` / `bugs_root` 静默改写成派生值的问题（升级不会改动你已 pin 的值）。 |
| **v3.21.0** | 同步 `tests/audit-docs-consistency.sh` **即可**（本版只改通用层审计；`scripts/agent-gate` 与 `scripts/stamp-provenance.sh` 本版未改）。**产物落功能目录 `docs/<feature>/` 的仓库零影响**——G2/G3/G5/G6 的覆盖与判定逐条不变。**受影响的仓库**：产物落**变更目录** `docs/changes/<变更号>/`（即启用了变更管线的仓库）→ 升级前审计对这四组**完全空转**：`docs/changes` 被当成"子目录"，于是"没有产物目录"的空转分支不触发，G2/G3/G5/G6 **一条断言都不执行、也不打印任何行**，而操作者读到的是 "4 passed"。升级后 G2 真正覆盖变更轨（管线态跳号会被判红），未覆盖的组会被点名声明。**升级后会看到一行 `G3/G5/G6 VACUOUS SKIP`**——那是**如实告知未覆盖**，不是失败（变更轨的 §3/§4 一致性由门禁 `--stage stop` 在创建时兜住）。**不要用"把 G3/G5/G6 扩到变更目录"来消灭这行提示**：冻结的历史变更目录按 §2.15 硬性规则 4 / §2.16.5 不可回填，那样只会得到永久无法清除的红。 |
| **v3.20.0** | 同步 `scripts/agent-gate` **即可**（本版只改门禁的"治理记录怎么读"；`stamp-provenance.sh` 与 `tests/audit-docs-consistency.sh` 本版未改）。**一直写单行记录的仓库零影响**——行为逐字节不变。**受影响的仓库**：`00-governance.json` 写成**多行格式化**的（即照 `resources/templates/governance-state.json` 模板生成的默认形状）→ 升级前 `begin` 报 `must declare risk_level L0, L1, L2, or L3`（字段其实就在 `change_id` 下面两行）、`metrics` 对每条记录报 `"risk_level":null`；升级后立即恢复通过。**这是 v3.18.0 引入的静默回归**（为支持批次把读取器从整文件改成行式），凡升过 v3.18.0 / v3.19.0 **且记录是多行**的仓库都中招——本仓自己的账本 16/16 条全中。**不要用"把记录压成单行"来绕过**：升级门禁才是正解。 |
| **v3.19.0** | 同步 `scripts/agent-gate` 与 `tests/audit-docs-consistency.sh` **两者**（`stamp-provenance.sh` 本版未改）。**不用批次的仓库零影响**——独立 `<变更号>/` 目录永远优先，新增的 `gov_ids()` 只在 `BATCH-*/` 分支被调用。**采用批次的仓库**：本版修掉"批次被它自己强制的内容卡住"——门禁与审计曾把**每一个** `## <标题>` 都当变更号，于是 §2.16.2 强制的 `## Observation` 会让 `--stage staged` / CI **拒掉一个完全合法的批次**，并给 `metrics` 加一行幽灵变更。升级后原先被误拒的批次交付立即恢复通过。 |
| **v3.18.0** | **无需补复制动作、无需回填**——批次是**可选**布局，不建 `BATCH-*/` 的仓库行为与升级前逐字节等价（独立 `<变更号>/` 目录永远优先）。同步 `scripts/agent-gate`（批次解析 + 行式治理记录 + 批次闭环判定 + 每变更一行 metrics）、`scripts/stamp-provenance.sh`（批次感知 + `batch_changes:`）、`tests/audit-docs-consistency.sh`（新增 G7 批次自洽组）**三者**。**只有想用批次的仓库需要动作**：把同一天的 L0/L1 变更放进 `<docs>/changes/BATCH-YYYYMMDD/`，产物**沿用原名**（不要改名），同批变更用 `## <变更号>` 小节分开，`00-governance.json` 改为**一行一个 JSON 对象**。**注意 L2/L3 不得入批**（门禁会按记录拒绝）。另本版修掉一个 bash 3.2 潜伏缺陷（`local a="$1" b="...$a"` 在 `set -u` 下报 unbound variable，只在 `--stage staged` / CI 路径现形）——同步 `agent-gate` 即修复。 |
| **v3.17.0** | 补 `scripts/stamp-provenance.sh` 到 `<scripts>/`（随 `--guard` 层落地）；`.agent-governance.yml` 新增 `provenance:` 段（默认 `include_email: true`）；`04.5-coding-record.md` 模板新增占位溯源块与验收勾选项；同步 `scripts/agent-gate`（新增溯源校验）。**这是一次交付门禁收紧**：`--stage stop` 与 branch 模式 CI 现在要求 `04.5-coding-record.md` 携带**由脚本生成**的溯源块。**老项目升级后下一次变更收尾前须跑一次 `scripts/stamp-provenance.sh <变更号>`，不跑即被拦下**。**不要回填历史变更**——门禁只校验活跃变更，回填会把 `generated_at` 伪造成今天（审计 A19 有反向断言）。仅装了 core 层未装 guard 层的项目不受影响。 |
| v3.16.0 | 补 `MAINTAINER.md`（仅本仓库，**不随分发**）；`.agent-governance.yml` 无变化。**无需补复制动作**——本版改的是 Skill 自身的分发与升级行为（`--check` / `--self-update` / `--derived-report` 三个新 flag、`--upgrade` 不再覆盖显式层选择、派生资产跳过保护、`docs/STANDARDS_CHANGELOG.md` 归属声明）。升级**仅当**目标仓曾在本仓 `docs/STANDARDS_CHANGELOG.md` 追加过本地行时会拒绝，需显式 `--force` 或先移出本地行。 |
| **v3.15.0** | `.agent-governance.yml` 新增 `paths:` 段（`docs`/`scripts`/`tests`/`githooks`）与 `bugs_root`；`scripts/agent-gate`、`scripts/check-standards-compliance.sh`、`tests/audit-docs-consistency.sh` **三者必须一起升级**（只升其一即静默错位）。**默认值即历史写死值，老项目不配置 `paths:` 时行为与升级前完全一致 → 升级本身不要求任何回填**；想换根的项目再跑一次 `bash scripts/bootstrap.sh --all --docs-dir <新根> <目标仓库>`。 |
| v3.7.0 修订（CHG-004） | 补 `06.5-deployment-config.md` 与 `06-delivery-summary.md` 到 `<docs>/`，并同步 `scripts/agent-gate`。**这是一次交付门禁收紧**：此前 `--stage stop` 只校验 `04.5`/`05`/`09`，现在 `06.5` 与 `06-delivery-summary` 同样必检，老项目升级后需补齐这两份文档（未命中也要显式声明"未命中，不适用"）才能通过。规范正文 §1.1 早已声明"八类缺一即未完成"，本修订只是让实现与已声明的语义对齐，故**不升规范版本号**。 |
| v3.7.0 | 缺陷模板扩为**六件套**（补 `bug-matrix.md`/`bug-config.md`/`bug-tasks.md`）；补编码记录模板 `coding-record.md`（变更起编时落 `<docs>/changes/<变更号>/04.5-coding-record.md`）；同步更新 `scripts/agent-gate` 与 `tests/run-tests.sh`。 |
| v3.6.0 | 补缺陷文档组模板 `bug-diagnosis.md`/`bug-impact.md`/`bug-test-plan.md` 到 `<docs>/bugs/_templates/`。 |
| v3.5.0 | 补 `commit-msg` 模板到 `<githooks>/`，并更新 `pre-push` 与 `scripts/agent-gate`。 |
| v3.3.0 / v3.4.0 | 补 `METHODOLOGY.md`、`methodologies/`（v3.4.0 含 `state-trigger-audit.md`）与 `bugfix-log.md` 到 `<docs>/`。 |

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
