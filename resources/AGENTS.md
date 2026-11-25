<!-- dev-standards:managed begin — 本区块由 dev-standards-bootstrap 安装器整体维护（§1.1 契约名件）；用户内容请写在 end 标记之后，升级/重装时原样保留 -->
# AGENTS.md — 本项目 AI 协作强制入口

> 所有 AI Agent 在**开始任何开发任务前必须读取的第一个文件**。本文件只是精简入口（严格控制在 ≤14 KB 以防客户端 24 KB 规则截断），权威全文只有一处：`docs/DEVELOPMENT_STANDARDS.md`。

---

## 专业判断力内核（六机制，DS §0.6）

- **盘点**：全集枚举了吗？缺的格子裁决了吗？UI 交付页全部出站出口（卡片/链接/导航）入 UJ 或显式豁免了吗？——反模式：凭样本定规则、只按 diff 面划验收。
- **参照**：仓内同类实现/界面指认了吗？——反模式：不看现状自造、按图转录不质疑图。
- **自视**：成品打开看过吗？——反模式：端点绿=做完、build 绿=界面可用。
- **分层断言**：断言层=感知层吗？HTTP 巡检带耗时与有效体/DOM/点击截图了吗？——反模式：裸 HTTP 200 冒充可用、端点 POST 冒充 UI 链路。
- **见证**：评审依据是自产证据吗？走工具面缺失补偿时附覆盖对账表且差集为零了吗？——反模式：核对他人证据即放行、「证据链完整」式背书。
- **收口**：每个缺口裁决落盘了吗（实现｜不做=理由+确认｜挂账）？暴露的入口直连下游不可用时已降级或标阻塞了吗？——反模式：交付半扇门仍标「已交付」。

---

## 执行顺序（不可跳过）

1. **分阶段最小读集**读取 `docs/DEVELOPMENT_STANDARDS.md`（纪律 15）：begin 只读 §1.1 与 §2.5；编码前按 `CLAUSE_REGISTRY.md` 定位定点读；测试/收口读 §2.13 与 §2.17.4；stop 前加 §1.3。**禁止整读全文**。
2. **执行前置（§2.16.1）**：核对标准版本、读 `docs/<feature>/` 既有文档、确认编号基线、完成项目背景与业务上下文调研。
3. **风险分级（§0.5）**：判定 L0–L3，确定四主体独立性与评审/平台要求（§0.5.2）。
4. **逐阶段推进（§2.16.2）**：每步声明完成前，逐项引用 §2.5「验收标准」条目号勾选 `[x]`/`[ ]`（A 层附命令与关键输出，B 层交独立角色），禁以“已按规范完成”替代。
5. **最终交付**：必须包含风险等级、DoD 逐条勾选（§2.16.3）与 AI 防漏自检（§2.16.4）。

## 硬性红线

- 严禁无文档改代码、未跑测试宣称完工、同一执行主体自测/自审/自批。
- 严禁未经 `00.5-communication.md` 用户整体确认生成后续产物正文或改源码（§2.17.2d 沟通先行门）。
- 严禁未经 Thought（引用 02 三维影响）直接改码/文档；必须 Thought → Action → Observation 推进并归档 09「执行记录（ReAct）」。
- 严禁阶段产物缺「交付触发点 / 背景输入」两行即开动下一阶段（`GATE-E126`）。
- 严禁入口暴露给用户但直连下游挂起/不可用时标「已交付」（只允许降级隐藏入口或标阻塞/部分完成，`GATE-E162`）。
- 高风险变更（§0 门禁 5）须人类 Release Owner 明确授权；高成本/`deep` 模型评审须用户确认（`agent-gate review-plan`）。
- 评审须先在目标仓根探测当前运行客户端能力（`install-hook-adapter --detect`；动态接线见 `--print-contract`），并装载项目背景与专业能力（`resources/methodologies/review-intelligence.md`）。
- 写入文件后必须用 shell 命令（`grep -c` / `wc -l` / `git diff --stat`）验证落盘，禁信编辑工具返回或 Read 缓存；上下文压缩后以磁盘产物与 git 状态为唯一权威。

## Agent 执行资源纪律（十五条，细则见 DS §2.9.6 / STAGE_PLAYBOOK）

1. **管道过滤与落盘复用**：长输出接过滤管道（终端 ≤10 行），全文归档后 grep 复用不重跑；单会话编码类 `bash` ≤20 次；交付收尾写 `handoff.md` + 换挡声明（未换挡开新单被 `GATE-E89`/`E112` 拦）；`session-gate status` 亮 YELLOW 须核查钩子接线。
2. **一次拉全**：同文件检索一次 `grep -E` 合并全部 pattern。
3. **先定位后小窗**：读大文件先 `grep -n` 定位再小窗读（±80 行）。
4. **勘探下放**：预计读 >2 文件或 >100 行定位时合并调用或派只读子代理，只回结论与行号。
5. **无匹配 ≠ 通过**：以退出码与 FAIL 汇总行为准，禁吞掉 FAIL 行。
6. **并行批量**：相互独立的读写/编辑单轮并行调用。
7. **定向验证与证据轮**：单测/定向先行，改文档/模板/单脚本用 `tests/run-tests.sh -T auto` 或 `-T <节>`，禁随手裸跑全量；改被测核心（`agent-gate`/`run-tests.sh`/`.agent-governance.yml`）由 AI 给判定卡请用户三选一确认；**版本链先行（v3.95.0，CHG-132）**（`update-assertion-count.sh` 同步基线）、**证据轮 SOP（v3.96.0，CHG-133）**走 `scripts/evidence-round.sh`（默认 5 快照 + 1 非快照；起轮前 `scripts/pre-round-check.sh`，纯文档可 `--carry-check`）、**返工分治（v3.97.0，CHG-134）**（纯补钉记 05「延后补钉登记」）、**冻结规则（v3.97.1，CHG-135）**（轮内改树 `GATE-E156`）与 **fresh clone / 无 CI 仓必须全绿**（`fresh-clone-check.sh` 收口前跑一次，`E153` 支持代码面指纹复用；未验证 REQ 入 09 清单 `E154`）。
8. **有状态 mock 隔离**：跨调用有状态依赖每用例重建。
9. **禁并行集成测试**：共享远程 DB 期间禁并行跑集成测试。
10. **长任务等待纪律**：禁独立 LLM 轮 `sleep` 轮询与 `TaskOutput block:true timeout>60s` 阻塞等（用前台 timeout / 单 shell `while` / 后台通知三式，或读 `.agent-state/suite-progress.json`）。
11. **环境归因续跑**：环境类故障恢复后按已落盘产物续跑，任务类（方案错/理解错）才推倒重来，归因登记 09。
12. **调用批处理（v3.77.0）**：独立命令合并执行，同文件多处改动合并 edit（`session-gate` 对 edit ≥40 亮黄灯）。
13. **尾部增量读（v3.77.0）**：追加类更新用定点 edit/`cat >>`，换挡只读 `handoff.md` 与增量区段。
14. **冻结树并行派发（v3.78.0）**：树冻结后可并行派发只读评审/测试子代理，前提：输入契约互斥、不共写 `.agent-state/`、各子代理产出不同类型发现。
15. **分阶段最小读集（v3.80.0）**：DS 等大规范永不整读，按阶段定位定点读。

## 可执行门禁（仓库启用 `scripts/agent-gate` 时不可跳过）

1. **建单与确认**：运行 `scripts/new-change <变更号> --risk Lx` 两段式生成骨架（当天 L0/L1 变更/缺陷首个即建 `docs/changes/BATCH-YYYYMMDD/`，L2/L3 独立目录；00-intent 须写目录落位声明 `E86`）。在 `00.5-communication.md` 记录用户整体确认（`E83`）后再展开 01–04 产物。`ui_change: true` 触发 `03.6-ui-spec.md`、UJ/出站出口（`E104`/`E161`）、入口即承责（`E162`）、三查锚点（`E157–E159`）与 UAT/业务终审（`E96`/`E98`/`E107`/`E124`）。
2. **门禁推进**：改源码前执行 `scripts/agent-gate begin <变更号>`（可先 `preflight <变更号>` 一次列全缺口，v3.82.0 起并收 stop 侧交付形状面），按阶段过 `--stage spec|design|testplan`（`E126`）；项目总册 13 册须在位（§1.3）。
3. **提交与交付**：提交前 `scripts/agent-gate --stage staged`；pre-commit 自动执行 `scripts/stamp-provenance.sh --all <变更号>`（及 `--bug <BUG-id>`）；交付前补全 05、07、09（含 ReAct 记录与 P00–P12 总册回填清单）与 01.5 RTVM 回填。
4. **无账改动与度量**：无活跃变更直接改源码在编辑/提交时拦截（`GATE-E125`）；`scripts/agent-gate metrics` 只读输出度量。严禁删除/绕过 Hook、CI 或 `agent-gate`。

## 常用锚点（按需跳转）

| 我要做什么 | 读哪一节 / 命令 |
|---|---|
| 六机制词表 / 防生长元规则 | DS §0.6 + §2.14 |
| 风险分级 / 四主体互异 / 歧义裁定 | DS §0.5 + §2.1 规则 8/10/11 |
| 分阶段专家评审 / 派发契约 / 评审智能 | DS §2.2 + `resources/methodologies/review-intelligence.md` + `agent-gate review-plan <CHG>` |
| UI/UX 变更（UJ/03.6/出站出口/E2E/UAT） | DS §2.5 阶段 1/3/4/7/8 + `resources/methodologies/expert-capabilities.md` §13 |
| 方法论 / 工程决策 / 数据结构 / 状态触发 | `METHODOLOGY.md` / `methodologies/{development,data-structures,state-trigger-audit}.md`（隐式链路三向遍历与同族推演） |
| 缺陷修复（六件套 / `docs/bugfix-log.md` 双登记） | DS §2.5 阶段 6 + §1.1（`docs/bugs/BATCH-YYYYMMDD/`） |
| 按变更类型与栈取阅读包 | `bash scripts/generate-reading-pack.sh <type> [--profile <栈>]` |
| 交付前跨文档审计（G1–G16，含 G10 废弃条款 / A20–A21） | `bash tests/audit-docs-consistency.sh [--only-fail] [--incremental]` |
| 动态适配（Hook/CI/画像/评审模型，v4.7.0） | `scripts/install-hook-adapter`、`scripts/install-ci-adapter`、`bootstrap --print-profile-contract`、`agent-gate review-models` |
| 过程真实性与原子流（v4.8.0） | `agent-gate start/advance/next/fix/record-red`、`GATE-E163` DAG 因果序、L0/L1 单文件变更卡 |
| 架构收敛与热冷分层（v4.9.0） | `lib-json.sh` 共享库、`lib-gate-cold.sh` 冷路径懒加载、`tests/governance-smoke.sh` 目标仓轻冒烟 |
| 渐进执法与诊断收官（v4.10.0） | `enforcement.mode`（`strict\|ratchet\|advisory`）、`agent-gate doctor`、`metrics --summary` |
| 项目级总册（P00–P12） / 配置与发布 / 终检 | DS §1.3 / §2.6–§2.9 / §2.16.2–§2.16.6 / §4 |

## 本仓评审要点（按仓定制承载面）

> 各仓在**本区块内**填写本仓评审要点。**禁止**另建按仓评审文件、也禁止重定义风险分级（唯一权威=§0.5）。未填写写「未命中（理由）」。

- **失效形态**：<本仓什么算坏——例：配置仓=「静默错路由」；服务仓=「超时/数据丢失」>
- **要点上限**：<默认 5>
- **跳过路径**：<低价值 diff 面，如生成物 / 快照 / 锁文件>
- **证据要求**：<须给 文件:行 或可复跑命令；禁「凭名字猜」>

## 关于你（AI）的角色与派发契约

任务开始时编排者指派角色（§2.1），**同一变更内不得兼任多角色**（L0/L1 最低线=评审独立且作者≠评审）。阶段 1–5 的 B 层评审须逐阶段派发独立子代理并在 `07` 留痕（L0/L1 可单行声明合并评）——**禁止"只做阶段 8 终审"的收敛执行**。

**派发契约（v3.94.0，§2.2）**：派发任何子代理须带五标签（项目背景、变更上下文、证据包、专业与历史、独立与成本）+ 预算行（默认 ≤60 轮 / cache_read ≤250K），完成判据与 P8 红线置于 prompt 末尾；骨架用 `scripts/agent-gate dispatch <stage> <CHG>` 生成，全文见 `resources/methodologies/review-intelligence.md`。

---

_本文件随 `docs/DEVELOPMENT_STANDARDS.md` 版本同步维护，当前对应规范版本：v4.11.0_
<!-- dev-standards:managed end — 上方为规范托管区；下方用户内容升级/重装时保留 -->
