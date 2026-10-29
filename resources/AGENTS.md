<!-- dev-standards:managed begin — 本区块由 dev-standards-bootstrap 安装器整体维护（§1.1 契约名件）；用户内容请写在 end 标记之后，升级/重装时原样保留 -->
# AGENTS.md — 本项目 AI 协作强制入口

> 本文件是所有 AI Agent（不论通过 Claude Code、Cursor、Codex、Windsurf、Gemini、Antigravity、Qoder、Trae、OpenCode 等何种工具接入本仓库）在__开始任何开发任务前必须读取的第一个文件__。
> 本文件只是入口摘要，不是规范全文；权威全文只有一处：`docs/DEVELOPMENT_STANDARDS.md`。二者内容如有出入，以 `docs/DEVELOPMENT_STANDARDS.md` 为准。

---

## 你现在必须做什么（不可跳过，按顺序）

1. __按分阶段最小读集读取__ `docs/DEVELOPMENT_STANDARDS.md`（纪律 15）：begin 阶段只读 §1.1（目录落位/批规则）与 §2.5（产物 A 层验收）；编码前按变更所涉 R 行定位锚点后定点读；测试/收口前只读 §2.13 与 §2.17.4；stop 前加 §1.3。**禁止整读全文**（v3.80.0 起，v3.86.0 消歧）。
2. 执行该文档 **§2.16.1 执行前置**：核对标准当前版本、读取 `docs/<feature>/` 目标功能目录下全部既有文档、确认编号基线，并**完成项目背景与业务上下文调研**（业务场景、历史决策/教训、行业与合规约束，§2.16.1 第 4 步）——未完成调研不得直接出方案或改代码。
3. 依据该文档 **§0.5** 判定本次变更的风险等级（L0-L3），并据此确定角色独立性与平台要求（§0.5.2）。
4. 依据该文档 **§2.16.2 执行主线** 按顺序执行全部适用阶段，不得跳步、不得用摘要代替逐项核对（§2.16.6）。**每步声明完成前，必须把该阶段 §2.5「验收标准」逐项引用条目号并勾选 `[x]`/`[ ]`（不要求抄录原文）**：A 层（机器可验项）先自跑校验命令（如 `grep -c 'REQ-' docs/<feature>/01-spec.md`）并把命令与过滤后关键输出记入清单，B 层（判定项）交独立角色核对——只写"已验收/已按规范完成"而不逐项列出，该阶段判定为未完成。
5. 在最终交付消息中，必须包含：风险等级判定、DoD 全部条目逐条勾选结果（§2.16.3）、AI 防漏自检逐条结果（§2.16.4）。

## 硬性红线（违反任一条，任务判定为未完成）

- 严禁无文档改代码、严禁未跑测试宣称完工、严禁同一执行主体自测/自审/自批。
- 严禁未经 `00.5-communication.md` 用户整体确认生成批量变更文档正文或修改源码（§2.17.2d 沟通先行门；豁免仅限自动化入口显式越过+09 登记）。
- 严禁用"已按规范完成"这类总结句代替逐条清单勾选。
- 严禁未经 Thought（全局影响分析：当前状态/目标/波及的调用方、流程与业务，引用 02 三维影响分析）直接修改代码或文档——必须 Thought → Action → Observation 三段式推进，Observation 须附验证命令与关键输出并归档 09「执行记录（ReAct）」（§2.16.2 铁律）。
- 严禁阶段产物缺「交付触发点 / 背景输入」两行即开动下一阶段：PMP 要求下阶段输入=上阶段产出，AI 必须先读业务/需求背景并写入产物；`agent-gate --stage spec|design|testplan` 缺即 GATE-E126（§2.16.2 阶段输入契约）。
- 严禁因为大部分完成就整体标记完成；任一清单项缺失即视为未完成，必须继续执行或明确报告阻塞原因。
- 高风险变更（命中 §0 门禁5 清单）必须获得人类 Release Owner 明确授权，AI 不得替代该授权。
- 严禁 AI 自行选择高成本/`deep` 档模型做评审：只能列候选、能力与成本档位，由用户确认后执行（§2.1 规则 11，`agent-gate review-plan`）；未确认即用=门禁违规。
- 严禁同一执行主体/同一会话既生产又评审，或编排 Agent 代签评审结论；评审必须先探测**目标仓被打开的 Agent 客户端**运行时再选执行方案（在目标仓根执行 `install-hook-adapter --detect`，不是编辑 Skill 的源仓客户端），且必须装载项目背景与专业能力（`resources/methodologies/review-intelligence.md`）。
- 写入文件后必须用 shell 命令（`grep -c` / `wc -l` / `git diff --stat`）在磁盘层验证落盘；不得以编辑工具的“成功”返回作为完成依据，不得用 Read 工具验证落盘（其可能返回缓存内容）。
- 上下文被压缩或总结后，对话记忆不可信：磁盘产物（`docs/changes/`、git 状态、文件内容）是唯一权威状态，必须重新从磁盘读取活跃变更与本红线后再继续，不得依据记忆中的“已完成”声明推进。
- 长输出命令（构建、测试、日志检索、JSON 解析等）必须接管道过滤，关键输出进对话与产物、完整输出归档到文件并给落点；禁止把原始输出整段贴入上下文（细则见下方「Agent 执行资源纪律」第 1 条）。

## Agent 执行资源纪律（十五条，违反按 §5 反模式登记）

1. **管道过滤**：长输出命令一律接过滤管道（通用形态：`<验证命令> 2>&1 | grep -E "<FAIL/ERROR 汇总词>" | tail -N`，按仓库替换命令与汇总词），终端只留关键输出（≤10 行级），全文归档由产物承载（`09-changelog.md` / `04.5-coding-record.md`）。**落盘复用（v3.85.0，CHG-112）**：验证/审计类长输出必须**落盘归档后 grep**，禁止重跑同一验证取不同过滤面——每轮重跑=全价重付（实证：同会话为换 grep 面重跑审计 3 次 ≈30min 纯重复）。**勘探预算（v3.39.0 量化；v3.60.0 分级，FU-909）**：单会话 `bash` 调用 ≤20 次（硬约束限于**编码/落点类**；baseline 校准、全量 suite、长复测类验证调用单列台账不占额）、单次检索必须合并全部 pattern（纪律 2）——idle/status 执法从 `.agent-state/session-tool-stats.json` 读数超限亮黄灯，超标原因须在 09「重要上下文」登记。**会话换挡硬拦（v3.58.0）**：install-hook-adapter 生成的 PreToolUse / tool.execute.before 接 `session-gate.sh check`，轮次超 `AGENT_GUARD_SESSION_TURN_LIMIT`（默认 50）即块工具调用（exit 2/throw，§2.9.6）——指令衰减免疫层；无 hook 能力的 Agent 以本纪律层 + begin 拒绝兜底。**事件型换挡触发（v3.63.0，治"轮次不可观测"）**：任一变更 commit/交付宣言后收尾必须写 handoff 文档（`docs/changes/<变更号>/handoff.md` 或活跃 BATCH 目录）+ 显式换挡声明；不换挡在同会话开新变更会被 `begin` 的 GATE-E89 硬拦（交付落在本会话存活期内且无 handoff 证据即拒；豁免 `AGENT_GUARD_ALLOW_NO_SHIFT=1` 须 09 登记；同批次连续变更/用户明示继续方可豁免，细则 §2.9.6）。**stop 侧镜像执法（v3.71.0，GATE-E112）**：同会话重复交付已交付变更且无 handoff/换挡声明即拦。**遥测活性自检（v3.63.0）**：`session-gate status/idle` 亮 YELLOW 失联 = adapter 未被客户端加载（插件 API 漂移实证过），须核查客户端日志，不得忽略。
2. **一次拉全**：同文件检索一次 grep 合并全部 pattern（`-e` / `-E`），禁止多 pattern 分次重扫。
3. **先定位后小窗**：read 大文件前先 `grep -n` 定位行号，再小窗读（±80 行）；同文件不重复大窗读。
4. **勘探下放（v3.39.0 起默认强制，非建议）**：预计读 >2 文件或 >100 行日志/代码定位、或 >2 pattern 的检索，**必须**合并单次调用或委派只读子代理执行，只回结论与行号，原始输出不进主上下文；子代理超出派发输入清单的读盘动作须在结论中声明原因（§2.2 输入契约）。
5. **无匹配 ≠ 通过**：过滤后无输出不等于校验通过——以命令退出码与 FAIL 汇总行为准，FAIL 汇总行不得被过滤吞掉。
6. **并行批量**：写产物、相互独立的编辑必须单消息并行批量调用；仅内容依赖前序输出时才拆轮。
7. **定向验证**：模块/单测级验证命令先行；全量回归仅由门禁（stop/staged/CI）统一触发，禁止随手裸跑全量。执法（v3.73.0，CHG-096/REQ-1102）：`.agent-governance.yml` 声明 `full_test_patterns`（锚定全量形态 ERE）后，session-gate 对 LLM bash 命中调用计数，≥阈值（默认 2，`AGENT_GUARD_FULL_TEST_LIMIT`）亮黄灯；不声明不执法；门禁/CI 触发的全量不经 LLM bash turn 天然豁免。**治理自测按变更选节（2026-10-25 接线补充，§2.17.4 执行细则）**：`tests/run-tests.sh` 具备 `-T auto`（按 `git diff` 自动选节，未映射文件回落全量）、`-T <节[,节]>`、`-j N`（节级并行，N≥2）、`-l`（列节）四种跑法；**改文档/模板/单个工具脚本一律 `-T auto` 或 `-T <节>`，禁止裸跑全量**——实证同一会话裸跑 11 次 ≈4.6 h，而 `-T auto` 同等覆盖面为秒级到分钟级。**全量范围 = AI 出议案 + 用户拍板（2026-10-27 二次裁定，取代"AI 单方面决定"）**：改动**被测核心**（`resources/templates/agent-gate.sh`、`tests/run-tests.sh`、`.agent-governance.yml`）时，AI 先给判定卡（建议节 / 预计秒数 source / 覆盖缺口 / 风险），再向用户提供三选一——①采纳建议 ②升档全量 ③降档并说明理由；用户选定后才执行，并把 `AGENT_GUARD_SCOPE_CONFIRM='<用户>@<ISO>'` 与 `AGENT_GUARD_SUITE_AI_SECTIONS/BASIS/REVIEWER` 一并传给 `plan`（写入 `decision.scope_confirmed`）。AI 不得替用户决定耗时动作；`judgment=ai` 无用户确认时 strict `E148` 拒。`T50` 恒跑，全量只在收口一次。**被 Kill 的处置**：先归因 `env_error`，最多一次自适应重试（分片或交 CI）；再次被 Kill 即停止，带"已耗时 / 覆盖缺口 / 风险"重新请用户决策——禁止无限重试与盲等。**测试范围 AI 判断（v3.90.4，FU-126-1）**：`tests/run-tests.sh` 自改默认回落 FULL **不是写死结论**——AI 可基于 diff 证据**提议**收窄，但必须先向用户展示三选一并取得确认（`AGENT_GUARD_SCOPE_CONFIRM`），同时给出 `AGENT_GUARD_SUITE_AI_SECTIONS`（节列表）+ `AGENT_GUARD_SUITE_AI_BASIS`（≥20 字符证据）+ `AGENT_GUARD_SUITE_AI_REVIEWER`（`platform / model / task- 或 ses-`）；缺证据、缺确认、评审签名不合规或未知节一律回落 FULL，`T50` 恒跑；判断来源与依据写入 `plan.decision` 的 `judgment/judgment_reviewer/judgment_basis/scope_confirmed`，门禁只验证据，不写死结论。**final-plan 收口（v3.90.5，CHG-126）**：`agent-gate baseline <CHG> [--write]`（P0-0 五数基线）与 `tc-index <CHG> [--write]`（P1-2 三源 TC 索引）按需调用；`stop`/`preflight` 消费 `decision`——硬项缺失 `E143`、strict 缺 decision `E142`、覆盖差集 `E144`（默认 WARN）；`--stage close <N>` 管 `filled-at stage=N change=<CHG> [at=<ISO>]` 时序（E145/E146）；`AGENT_GUARD_ADAPT=0` / `PLAN_STRICT=0` / `STAGE_CLOSE=0` 分别退出判定、严格消费、阶段时序门。收口前若不确定选节是否正确，用 `-T auto` 的 `AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1` 先看解析结果再执行。**本机全量已证实不可行（2026-10-27，CHG-127）**：本机全量被系统 `Killed: 9`（`-j2/-j4/-j6`、sandbox/非 sandbox、nohup 分离均复现）；`.agent-state/full-suite-kill.<host>` 标记存在时 `run-tests.sh` 对全量直接 `rc3` 拒绝，**只准 `--shard i/6` 分片（确定性划分全部 94 节）或交 CI，禁止第二次全量尝试**。**开工前 2 分钟既有红体检**：`tests/run-tests.sh -T T14,T26,T64,T67 -j 4`（高频失效钉），红先修再开工；收尾只跑改动相关节 + 分片，避免收尾时才暴露既有红并串行返工。**版本链先行（v3.95.0，CHG-132）**：任何套件证据轮（全量/分片/fresh-clone 收据）启动前，版本链必须先对齐——`STANDARDS_CHANGELOG.md` 顶行版本 = 版本载体版本，且 `tests/.suite-baseline`/`tests/.audit-baseline` 与 README 计数一致；不一致先补 CHANGELOG 行并经 `scripts/update-assertion-count.sh` 同步基线，再跑轮次（顺序颠倒是 T73 假红的流程根因，实证 CHG-131 首轮分片 6 三红）。**证据轮 SOP（v3.96.0，CHG-133）**：分片证据轮默认走 `scripts/evidence-round.sh --chg <CHG>`——每轮一个 `.agent-state/evidence/<CHG>/round-<N>/` 目录，失败分片日志与 rc 永不覆盖，ledger 追加 HEAD / tracked 树指纹 / 参数；默认跑法为 **5 快照 + 1 非快照**（live 片自动选含 T87 的片——快照内 T87 早退 1 条），全快照合计不得当作全量真值（快照内 T87 早退，合计必然少于全量；`shard-sum.sh` 会告警）。**fresh clone / 无 CI 仓必须全绿（v3.92.2，CHG-127）**：断言不得依赖未跟踪件（`docs/` 私有面、`scripts/agent-gate`、`scripts/stamp-provenance.sh`、`.agent-state/`）——缺则按**具体夹具路径**显式 SKIP，禁止用 `-d docs` 一类代理判定（套件自身会创建 `docs/`，代理会翻转为"docs 在场"的假象）；大输出断言用 herestring（`grep -Eq <<< "$out"`）而非 `printf | grep -q`——`pipefail` 下 grep 提前退出会让 printf 收到 SIGPIPE，把**命中**判成失败。**T82 墙钟 ≤1s** 只在串行档断言，`-j N` 档显式记"not asserted"（并行争用下的墙钟不是产品时延）。**交付质量门（v3.92.2，CHG-128）**：命中被测核心时，`staged/stop` 依次消费 `E153`（fresh-clone receipt：`tests/fresh-clone-check.sh`，tracked-only 快照的 audit+目标节绿）、`E150`（05 的 `red_repro:` / `green_after:` 两行，占位不算）、`E151`（`verification_owner` ≠ `implementation_owner`）、`E152`（`scope_overrun=over` 且无用户确认）；显式自查用 `--stage core` / `--stage scope`。三个降级开关（`AGENT_GUARD_FRESH_CLONE=0`、`AGENT_GUARD_ALLOW_SELF_VERIFY=1`、`AGENT_GUARD_SCOPE_OVERRUN=0`）均须在 09「重要上下文」登记理由；无 CI / 非 GitHub 仓以 G-ENV 为每批验收面。**G-ENV 收据只在收口前生成一次（v3.92.2）**：中间验证只跑受影响单节（`-T <节>`）；每次生成都会追加 `.agent-state/fresh-clone-history.tsv`，同一变更多次生成且 09 无 `- fresh-clone re-run: <理由>` 时脚本告警（`--ledger-check` 可查）——**重复付费必须可见**。**未验证 REQ 清单（v3.92.2）**：本变更 scope 内存在 RTVM 非 ✅ 的 REQ 时，09 必含该节并逐条列出（全部 ✅ 则无需）；缺/漏列即 `E154`；显式自查 `--stage rtvm`——静默降级从此是签名声明。
8. **有状态 mock 隔离**：跨两次调用的有状态依赖（会话/游标/水位类）每用例隔离重建；"第二次调用被跳过"类失败优先查共享 mock 内部状态。
9. **禁并行集成测试（v3.71.0，CHG-046/REQ-1092）**：共享远程 DB 期间禁止并行代理同时跑集成测试（实证：连接池抖动→伪红/资源争抢）；调度并行任务前核对目标库共享态，共享即串行或各自独立库；细则=STAGE_PLAYBOOK 阶段 7 节。
10. **长任务等待纪律（v3.73.0，CHG-096/REQ-1100）**：禁止把"等待长命令完成"做成独立 LLM 轮（`sleep N` 后再探测类调用算一次 bash 预算且无进展——每轮询烧一个 LLM turn）。合法三式：①前台单次执行+充足 timeout；②单 shell 内 `while ! 判据; do sleep 30; done` 一次等到；③后台启动+完成通知续接。执法：session-gate 对首 token 为 `sleep` 的 bash 调用计数，`idle/status` ≥阈值（默认 2，`AGENT_GUARD_SLEEP_POLL_LIMIT`）亮黄灯，要求 09「重要上下文」登记；判定口径与降级路径唯一权威=session-gate.sh 头注释。**进度文件（v3.90.3，CHG-123/P0-2）**：套件逐节输出 `[done] Tnn Ns` 并写 `.agent-state/suite-progress.json`；等待改「读进度文件 + 短轮询」，**禁止** `TaskOutput block:true timeout>60s`（一次阻塞超 1 分钟即盲等）。
11. **环境归因续跑（v3.73.0，CHG-096/REQ-1101，B 层）**：子代理/长任务失败先归因再处置——环境类（网络/凭证/超时/基建）恢复后按已落盘产物续跑或增量重启，不从零重启；任务类（方案错/理解错）才推倒重来；归因结论与续跑起点登记 09。
12. **调用批处理（v3.77.0，CHG-101/REQ-1124）**：独立 shell 命令合并为单次调用（`&&` 链或并行工具调用）；同文件多处改动合并为一次多段 edit，禁止小步高频读写同一文件——**每次工具调用重付整个上下文前缀，请求数 × 上下文水位才是 token 乘数**（单次 edit 在高水位会话约合十万级 token）；未用到的 MCP/扩展能力不挂载（静态基线按需）。执法（v3.77.0，CHG-101/REQ-1127）：session-gate 对 edit/write 族调用计数，`idle/status` ≥阈值（默认 40，`AGENT_GUARD_EDIT_LIMIT`）亮黄灯，要求 09「重要上下文」登记；判定口径与降级路径唯一权威=session-gate.sh 头注释。
13. **尾部增量读（v3.77.0，CHG-101/REQ-1125）**：追加类更新用 `cat >>` 或定点 Edit 落盘，禁止为追加而全量重读回灌上下文；read 大文件沿用纪律 3 小窗口径，换挡重建状态时只读 handoff 与增量区段（§2.9.6），禁止整文件重读。
14. **冻结树并行派发（v3.78.0，CHG-102/REQ-1140）**：树**冻结**后，同一轮内并行派发多个评审批/测试子代理属**许可**做法——它们只读不写，串行派发纯属浪费墙钟时间。三条前提缺一不可：①被审对象（树/产物）已冻结、本波不再落码；②各子代理输入契约互斥（变更文件清单 + 产物路径 + 行号锚点，§2.2 输入契约），互不依赖彼此结论；③**不共写** `.agent-state/`（收据/统计类运行时账本只由编排者写，子代理只回报结果）。违反任一条即退回串行；细则唯一权威 = 规范 §2.2「冻结树并行派发」。同一原则适用于**多目标仓 `bootstrap --upgrade`**：各目标仓独立目录、各自 `.agent-state/`，可同轮并行升版且互不共写；**同一仓内**禁并发升版。

15. **分阶段最小读集（v3.80.0，CHG-107/REQ-1153；v3.86.0 起取代第 1 条旧整读要求）**：规范文档（DS 等）**永不整读**——begin 阶段只读 §1.1（目录落位/批规则）与 §2.5（产物 A 层验收）；编码前按变更所涉 CLAUSE_REGISTRY R 行定位 DS 锚点后 `sed -n '<起>,<末>p'` 定点读；测试/收口前只读 §2.13 与 §2.17.4；stop 前加 §1.3；其余条款一律按需定点。追加式更新走纪律 13 尾部增量。细则唯一权威=本条，DS §2.9.6 只留指针。

## 可执行门禁（仓库启用时同样不可跳过）

若仓库存在 `scripts/agent-gate`，在首次改动源码前必须：

1. 在 `docs/changes/<变更号>/` 创建入口件与后续产物（**九件模板**）：`00-intent.md`、`00-governance.json`、`00.5-communication.md`、`01-spec.md`、`01.5-rtvm-matrix.md`、`02-code-impact-analysis.md`、`03-modification-plan.md`、`03.5-tasks.md`、`04-test-scripts.md`（**骨架可由 `scripts/new-change <变更号> --risk Lx` 两段式生成（v3.52.0）：确认记录在位后才补齐 01-spec 起五件，`--allow-unconfirmed` 供自动化入口显式越过；骨架不豁免填写，PENDING 执行主体被 begin 拒绝**）。各件必含节与机校语义——00-intent 为管线入口且 begin 硬校「预期结果/开放问题」（§2.17）、00.5 沟通先行门 GATE-E83 硬校确认记录非空 + L0 单行声明豁免、确认落盘前禁止生成后续产物正文与源码编辑（§2.17.2d）、02 先分析后方案三维 + 回滚（§2.5 阶段 2）、JSON 风险等级与四主体互异（L2/L3 强制互异；全等级最低线=作者≠评审）含 `spec_author`（§2.1 规则 10）、RTVM 回填门禁 4——**唯一权威见 DS 对应节，本入口不复制其细则**。**当天 L0/L1 变更/缺陷首个即建 `docs/changes/BATCH-YYYYMMDD/`（`## <变更号>` 锚点分节，后续同日变更/缺陷并入；L2/L3 独立目录；细则 §1.1）**；00-intent 必填**目录落位声明**（`- **目录落位**：BATCH-YYYYMMDD | 独立目录（<理由>）`，GATE-E86 硬校，v3.60.0），非 L0 的 00.5 沟通稿须含五要素锚点（§2.17.2d 第 4 条）。**命中 `ui_change: true` 的界面/体验变更**：`03.6-ui-spec.md`（条件件）与 E2E/UAT 条件门生效（GATE-E92–E98，v3.67.0）、07 增「业务合理性终审」节（GATE-E124）与来源物映射（GATE-E123/G15）（v3.84.0）；**全部变更 03 必含「既有范式关系」节（GATE-E122；设计门与交付全查，未命中声明放行，v3.84.0）**；未命中触发面时上下文包/UJ 一行「未命中（理由）」即合规，不强加（CHG-091）。
2. 执行 `scripts/agent-gate begin <变更号>`（begin 前可先 `agent-gate preflight <变更号>` 一次预检全部产物缺锚，v3.72.0；v3.82.0 起并收 stop 侧交付形状面——E85/E114/E115/E117/E46 秒级格式反馈，写台账的 E116 不在探针面）；未通过不得开始源码编辑。**v3.89.0 起 begin 为入口门 + 阶段门序列**：begin 只校验入口件（00-intent 预期结果/开放问题 + 00-governance.json + 00.5 确认记录），随后按序过**无状态阶段门**——阶段 3 开动前 `agent-gate --stage spec`、阶段 4 前 `--stage design`、阶段 5 前 `--stage testplan`（幂等可重入，不写阶段状态文件；九件齐的存量习惯全门自然绿）；未过对应阶段门不得进入该阶段（staged/stop/ci 交付全查不变，收窄≠弱化；`AGENT_GUARD_STAGE_GATES=0` 平滑关闭，默认开）。**阶段门 = 交付完整性门（v3.91.5，用户硬指令）**：`--stage design` 前 `01-spec` 必须已有 REQ 编号且 `01.5` 已有 REQ 行（**需求未写不得开始设计**）；`--stage testplan` 前 `02/03/03.5` 必须已交付且 `01.5` 已有 DES 与 TASK 行；`--stage close <N>` 校验本阶段维度（2=REQ、3=DES+TASK、4=TC）。缺任一即 `E126`，禁止"先做后补文档/RTVM 最后统一填"。**begin 同时机校项目总册 13 册在位（§1.3）**：`docs/project/` 缺失或不全时，先复制 `<docs>/templates/project/` 骨架、回填现状并完成逐册初评，再 begin（豁免 `AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1` 须在 09「重要上下文」登记理由）。begin 同时执法**会话红灯门（v3.41.0）**：`.agent-state/session-gate-last.md` 含 `GATE RED` 且新于最后交付 changelog 时拒绝（带病开工拦截；豁免 `AGENT_GUARD_ALLOW_OVER_RED=1` 并登记 09「重要上下文」）。
3. 提交前执行 `scripts/agent-gate --stage staged`；交付前补全测试证据与 Changelog（含「执行记录（ReAct）」Observation 记录，§2.16.2）与**「项目总册回填清单」节**（P00–P12 逐册勾选/未命中，§1.3）。**交付前变更目录全部 `*.md` 产物盖章（pre-commit 自动，v3.41.0）**：hook 自动执行 `scripts/stamp-provenance.sh --all <活跃变更>`（幂等、真值读 git/主机/UTC、**禁手写**；§4 追踪矩阵由 `--all` 从 01.5 矩阵派生 fail-open；`bug_ref` 六件套由 hook 逐一 `--bug`；无 pre-commit 环境手动执行同命令；gate stop 逐一校验缺一不可交付；只校验当前活跃变更，**历史产物不得回填**，§1.1/§4）。**`bug_ref` 绑定的缺陷六件套同样盖章**：`scripts/stamp-provenance.sh --bug <BUG-id>`（六件不齐 staged/stop/CI 与审计 G8 拦截；豁免须 `<docs>/bugs/.gate-allowlist` 登记理由；**v3.35.0 起六件套按天入批、v3.36.0 扁平化：`docs/bugs/BATCH-YYYYMMDD/` 同名文件 + `## BUG-xxx` 锚点分节**，嵌套子目录为历史合法形态，§1.1）。启用 Stop Hook / 会话内执法（v3.34.0）时自动检查上述产物与门禁 4 RTVM 回填（细则 §2.17.1）。
4. 传动与事故重入（§2.17.1/§2.17.2）：`01-spec.md` 合入会自动派发 02/03/03.5/04 骨架 PR，`09-changelog.md` 合入会自动开发布检查单 issue；生产事故经 incident 事件自动生成 `BUG-<时间戳>` 的 `00-intent.md` 骨架，接手者须走完整变更流程，禁止"修完不留痕"。**缺陷发现入口（§2.17.2b v3.43.0；v3.89.0 起三类信号）**：①主干回归红经 `bug-autointent` 自动建完整六件套骨架（频控窗口内同指纹只追加复现行）；②会话内 audit 红灯/gate 摩擦须**交互三选项**（建骨架/登记 FU/忽略须 09 理由），不得静默跳过；③**会话内无账源码改动**在编辑时刻被 session-gate `check` 硬拦（exit 2）、交付边界被 `agent-gate --stage staged/stop` fail-closed（`GATE-E125`）——豁免 `AGENT_GUARD_ALLOW_UNACCOUNTED=1` 须 09「重要上下文」登记理由（v3.89.0，CHG-117）。启用会话内执法时，会话开始自动注入规则 10 四主体自查表（§2.1 规则 10，冲突点名）。
5. `scripts/agent-gate metrics` 只读输出管线度量（§2.17.5），不得用度量数值替代 DoD 判定。

不得删除、禁用或修改 Hook、CI workflow、Required Check、`scripts/agent-gate` 以绕过本规范。无法通过门禁时，必须报告阻塞原因并等待授权；不得以“仅是小改动”为由绕过。

## 常用锚点（无需通读全文时，任务型 Agent 可按需跳转）

| 我要做什么 | 读哪一节 |
|---|---|
| 判断这次改动风险等级、要不要跨平台交叉验证 | §0.5 |
| 分阶段专家评审、九专家职责映射与上下文贴近契约（防泛泛而谈）；评审/测试子代理派发必须附**输入契约**（变更文件清单+diff 摘要+待核对产物路径+行号锚点，§2.2 v3.39.0）；专家能力卡见 `resources/methodologies/expert-capabilities.md` | §2.2 |
| 做各环节评审 / 派发评审子代理 / 选评审模型：项目背景装载、专业能力匹配、批判性质询、目标仓运行时探测、成本确认 | §2.1 规则 11 + §2.2 + `resources/methodologies/review-intelligence.md`（候选命令 `scripts/agent-gate review-plan <变更号>`） |
| 确认本次变更作者/实现/测试/评审四主体互异（能否兼任） | §2.1 规则 10 |
| 执行中遇到歧义怎么裁定（何时必须问用户、何时可自裁） | §2.1 规则 8「歧义分级裁定」 |
| 只加载本次任务需要的规范层（宪法/流程/操作/历史） | §头部「分层阅读路由」 |
| 新建功能，第一次接触本仓库 | §2.5 阶段 1-10 全部 |
| 做用户可见界面/体验变更（项目上下文包·UJ·03.6·UX 任务·E2E·UAT） | §2.5 阶段 1/3/4/8 + resources/methodologies/expert-capabilities.md §13 |
| 做影响分析 / 出方案 / 拆任务 | §2.5 阶段 2-3（三维影响 + ≥2 候选选型 + PM 拆分；命中状态/触发链路时隐式链路三向遍历见 `resources/methodologies/state-trigger-audit.md`） |
| 做技术/方法论选型（允许用哪些、禁止用哪些） | `resources/METHODOLOGY.md`（M0–M3 分级唯一权威表）+ §2.5 阶段 3 |
| 写代码前的工程决策（SOLID/DRY/KISS、复杂度、错误处理、日志、并发） | `resources/methodologies/development.md` |
| 定义数据结构 / 接口字段 / LLM 输入输出契约 | `resources/methodologies/data-structures.md`（六类模型 + 弱类型禁令） |
| 写测试用例 | §2.5 阶段 4 + §0 门禁 2（十一类覆盖维度 + SC-xxx 业务场景清单，场景覆盖率 ≥80%（L3 ≥90%）） |
| 执行中如何留痕（Thought/Observation） | §2.16.2 ReAct 执行铁律 |
| L0/L1 变更怎么按轻量通道执行（省表达成本，不省证据边界） | §0.5 指引 + §1.1「L0/L1 轻量通道」 |
| 怎么压会话/输出 token 成本 | 本文件「Agent 执行资源纪律」节 + §2.9.6 会话与上下文纪律 + §2.5 表达成本条款 |
| 只是改 bug | §2.5 阶段 6（`docs/bugfix-log.md` 双登记 + 根因表「同族推演」行 + 「Bug 修复回填清单」；三条款——诊断前必读总册 / TC 覆盖强制新增防回归 / 六件套按天入批 `docs/bugs/BATCH-YYYYMMDD/` 扁平化——与 **P3 缺陷轻量通道**（文案类：`01-diagnosis.md` 行首 `severity: P3` 免 02/05/06 三件，未声明=全六件）细则唯一权威见 §2.5 阶段 6 与 §1.1）+ `resources/methodologies/state-trigger-audit.md`（同族推演与反模式细则）+ §0 门禁 |
| 按变更类型取阅读包（阅读税路由，v3.46.0） | `bash scripts/generate-reading-pack.sh <type>`（type∈`L0-bugfix|L1-standards|L2-architecture|L3-critical|universal`）——从 `CLAUSE_REGISTRY.md`（机器索引层）按需生成内容切片，锚点 fail-closed 防漂移；本表为路由入口、阅读包为切片、DS 为正文唯一权威（§2.17.2c） |
| 交付前文档互证（CI/本地均可跑） | `bash tests/audit-docs-consistency.sh`（**G1–G16** + A 组盖章互证；逐组定义以脚本头注释为唯一权威、本文件锚点表为人类索引；`--only-fail` 只打 FAIL 与空转声明）。**组标签**：G1 版本链 / G2 编号连续+UID / G3 归档同源 / G4 缺陷双登记 / G5 RTVM / G6 必填节 / G7 批次自洽 / G8 六件套 / G9 总册+表外 reviews / G10 废弃条款 / G11–G12 UI 条件组 / G13–G14 三维+源对照 / G15 来源物 / G16 无账改动；A20/A21 盖章。失败项即 §2.14 回填清单，§2.13.4 |
| 项目级总册（总体需求/架构/接口/数据/任务/测试/部署/风险/决策） | §1.3 + `resources/methodologies/project-masters.md`（十三册清单与必含章节唯一权威；首次变更初始化，每次变更逐册回填+变更注记） |
| 涉及配置文件/数据库变更 | §2.6 |
| 要发布上线 | §2.7、§2.8 |
| 涉及模型/Prompt/AI 链路 | §2.9 + `resources/methodologies/data-structures.md` §4（LLM 结构专项） |
| 生产环境紧急热修复 | §2.11 |
| 完成前最后自检 | §2.16.2、§2.16.3、§2.16.4、§2.16.6 |
| 填写 Changelog | §4 |

## 本仓评审要点（v3.75.0，CHG-099，REQ-1113，按仓定制承载面）

> 各仓在**本区块内**填写本仓评审要点（评审器读这里的「失效形态」）。**禁止**另建按仓评审文件、也禁止在此重定义风险分级或「是否需要人」判定——唯一权威仍是 §0.5 与 §0.5.1（第二权威源即漂移源）。未填写即写「未命中（理由）」。

- **失效形态**：<本仓什么算坏——例：配置仓=「静默错路由」；文档仓=「说了假话」；服务仓=「超时/数据丢失」>
- **要点上限**：<本仓评审意见最多列 N 条，防噪声刷召回；默认 5>
- **跳过路径**：<低价值 diff 面，如生成物 / 快照 / 锁文件>
- **证据要求**：<须给 文件:行 或可复跑命令；禁「凭名字猜」的结论>

## 关于你（AI）的角色

任务开始时，编排者会告知你在本次任务中扮演的角色（需求 Agent / 架构-计划 Agent / 开发 Agent / 测试 Agent / Review Agent，见规范 §2.1）。**你只能完成本角色允许的工作，不得越权完成其他角色的验证与签署**——即使你有能力做到。这是本规范最核心的约束，不因效率考虑而放松。**同一变更内不得兼任多个角色**（规格/文档作者、实现、测试、评审四主体互异，L0/L1 最低线=评审独立且作者≠评审，§2.1 规则 10）。若被细分指派为 §2.2 某专家，还须满足该专家的评审动作、上下文贴近契约与署名要求（签署权映射回 §0.5.2 既有角色列）。**分阶段评审留痕（v3.53.0 硬指令）**：阶段 1-5 的 B 层评审**必须逐阶段派发独立子代理**（输入契约 §2.2）并在 `07-review-report.md`「分阶段评审」节留痕；L0/L1 可单行声明合并评——**禁止"只做阶段 8 终审"的收敛执行**。

**派发契约（v3.94.0，§2.2）**：编排者向任何 AI 子代理派发任务时，prompt 必须带五标签——项目背景、变更上下文、证据包、专业与历史、独立与成本；只给角色加一句"只读、不改文件"的 prompt 不合格（子代理只能泛评或自采）。骨架用 `scripts/agent-gate dispatch <stage> <CHG>` 生成，契约全文=`resources/methodologies/review-intelligence.md` §2/§2.1。子代理收到缺项 prompt 时按 P8 声明缺口并只做最小必要读盘，不得默认全量重勘探；未带项目背景的评审结论无效。

---

_本文件随 `docs/DEVELOPMENT_STANDARDS.md` 版本同步维护，当前对应规范版本：v3.96.0_
<!-- dev-standards:managed end — 上方为规范托管区；下方用户内容升级/重装时保留 -->
