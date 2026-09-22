#!/usr/bin/env bash
# audit-docs-consistency.sh（通用层模板 —— 复制到目标仓库 tests/ 后使用）
#
# 【能力定位】跨文档一致性机器审计：规范要求"同一事实多处落点必须同步"
# （§3↔§4 同源声明、§1.2 编号顺序规则、门禁 4 双落点、§2.5 阶段 6 双登记），
# 此前只有 B 层人工核对。本脚本把这些一致性不变量固化为确定性断言，
# 与 agent-gate（单产物 A 层标记）互补——gate 管"单件合格"，本脚本管"多件互证"。
#
# 【审计范围】<docs>/DEVELOPMENT_STANDARDS.md + AGENTS.md + <docs>/bugfix-log.md + 产物目录。
# **产物目录按"不变量是否时间不变"分两类**（详见下方"审计单元"节，这是本文件的核心划分）：
#   G1 版本链：AGENTS.md 页脚版本 == 规范页脚版本（§2.16.4 第 6 条的机器化）
#   G2 编号体系：REQ/DES/TC/SC/CHG/CFG/DB/FU 连续递增、无跳号（§1.2 / 自检第 3 条）
#      —— 时间不变，故作用于 **功能目录 ∪ 变更目录**（`<change_root>/<变更号>/`）
#   G3 §3↔§4 同源：09-changelog 最新 CHG 归档清单标签与规范 §3 完全一致（§3 同源声明）
#   G4 bugfix 双登记互证：log 每条 BUG 有对应 CHG；每个 CHG 的 BUG 行已登记 log（§2.5 阶段 6）
#      —— **两个方向都遍历全树 09-changelog**（含 `<change_root>/<变更号>/` 深度 2，v3.21.0）
#   G5 RTVM 双落点：最新 CHG 追踪矩阵短引用中的 REQ 均已回填 01.5-rtvm-matrix（门禁 4；最新 CHG 无 REQ 引用时豁免建矩阵）
#   G6 §4 必填节完整：最新 CHG 含 追踪矩阵映射/现象/分析/根因/方案/测试结论/角色签署/ReAct/检查清单/未动项
#      —— G3/G5/G6 比对的是**当前规范版本**，故只作用于**活文档（功能目录）**：
#         冻结的变更目录按 §2.15 硬性规则 4 / §2.16.5「已闭合 CHG 禁止改写」不可回填，
#         事后按当前 §3/§4 判它们只会产出**永久无法清除的红**。变更轨由门禁在创建时兜住。
#   G7 变更批次自洽（v3.18.0；v3.19.0 修正判定方向）：<change_root>/BATCH-YYYYMMDD/ 的治理记录、
#      入口分节、风险等级、跨批次唯一性互相自证（§1.1 同天 L0/L1 合并）——批次把"一个变更
#      一套产物"放宽为"一套产物承载多个变更"，放宽的代价必须由机器盯住，否则批次会变成
#      绕过 A 层门禁的暗道。**判定一律从权威名单（00-governance.json 的 change_id）正向出发**，
#      不从 `## <标题>` 反向推断——后者分不清变更小节与结构小节（§2.16.2 的 `## Observation`）。
#   G8 缺陷六件套存在性（v3.28.0，CHG-071/BUG-040~055 复盘）：`<bugs_root>/BUG-*/` 凡起组
#      必须六件齐——此前六件套"刻意排除"出审计面、委托给门禁，而门禁只在变更轨 bug_ref
#      声明时校验，纯 bug 轨处置 16 组只写 01-diagnosis 亦无红灯。**委托必须落在会跑的
#      执法点上，否则就是循环踢皮球**：审计直接接管（存在性是时间不变量）。豁免 = 登记
#      `<bugs_root>/.gate-allowlist`（一行一 id，行尾注释写理由），登记组仍逐行点名可见。
#   G9 项目级总册存在与自证（v3.35.0，§1.3）+ 功能目录表外 reviews/ 拦截（v3.37.1，§1.3 第 6 条）：
#      12 册在位/自证/评审成对/最新变更回填清单；功能目录（01-spec 或 01.5 信号）内出现
#      reviews/ 即红（FU-105：评审唯一落点=变更轨 07 + 总册 reviews/，表外默认禁止）
#   A20 变更目录溯源盖章互证（v3.28.0）：①同目录 ≥1 件已盖而其余未盖 = 盖章半途而废
#      （时间不变的不一致，CHG-071 实测 2/9）；②`standard_version >= v3.26.0` 的变更目录
#      必须全 `*.md` 盖章（其规范版本自身要求）。**不触发历史回填禁令**：不要求 v3.26 前
#      老目录补章——A20 只抓"半途"与"新版未执行"，不抓"时代如此"。
#   A21 缺陷六件套溯源盖章（v3.28.0）：六件套同用环境真值证据头（`stamp-provenance.sh
#      --bug` 写入，禁手写）；缺失组即回填清单——`--bug` 写入的是当下真值，不是伪造历史。
#
# 【"空转"必须显式声明】（v3.21.0）产物目录用**正信号**识别（见"审计单元"节），不用
#   "是 <docs>/ 的子目录"取全集。任一组的目录集合为空时，本脚本**打印一行 `VACUOUS SKIP`
#   明确告知那一组没有覆盖本仓库**，而不是静默跳过。**静默空转 = 假绿**，是本文件最该防的
#   失效模式：旧实现在 <docs>/ 存在任意非功能子目录（如 docs/changes、docs/review）时让
#   G2/G3/G5/G6 一条断言都不执行、也不打印任何行，操作者读到 "N passed" 会以为它们都过了。
#   实测：一个 01-spec.md 带 REQ 跳号的仓库**通过**了审计。**读到 "VACUOUS SKIP" 就必须
#   知道：那一组没有覆盖本仓库，不能当"通过"理解。**
#
# 【更新语义】文档修订（活文档类）与批次保留冲突时以规范 §2.15 为准；存量仓库首跑
# 可能大量失败——失败项即 §2.14 存量回填清单，逐项处置或在 §2.13.4 走例外留痕。
#
# 零依赖：bash 3.2+、grep、awk、sort、comm。macOS/Linux 均可。
#
# Usage: tests/audit-docs-consistency.sh [--only-fail] [repo_root]   # 默认当前仓库根
#   --only-fail（v3.23.0）：只打印 FAIL 行、skip/空转声明行与最终汇总，ok 行抑制——
#   存量历史缺口永久 FAIL 的仓库反复复跑时，不必每次全量重放所有 ok 行。
#   **skip / VACUOUS SKIP 行豁免抑制**（v3.21.0"空转必须显式声明"硬约束不被本 flag 绕过）。
#   FAIL 行、最终汇总行与 exit code 语义与默认模式完全一致；默认（无 flag）逐字节不变。
# 路径根（docs 等）由 <repo_root>/.agent-governance.yml 的 paths.* 决定；
# 未配置即用内置默认 docs/，行为与 v3.14.0 一致（v3.15.0）。
set -uo pipefail

ROOT=""
only_fail=0
for _a in "$@"; do
  if [[ "$_a" == "--only-fail" ]]; then
    only_fail=1
  else
    ROOT="$_a"
  fi
done
ROOT="${ROOT:-$(pwd)}"

# 路径根可配置（v3.15.0）：默认值 = 历史写死值，未配置即行为不变。
# 解析优先级：环境变量 > .agent-governance.yml 的 paths.* > 内置默认。
cfg_path() { # key default
  local k="$1" d="$2" v=""
  if [[ -f "$ROOT/.agent-governance.yml" ]]; then
    v=$(sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" "$ROOT/.agent-governance.yml" 2>/dev/null \
        | head -n 1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$v" ]] || v="$d"
  printf '%s' "$v"
}
DOCS_DIR="${AGENT_GUARD_DOCS_DIR:-$(cfg_path docs docs)}"
DOCS="$ROOT/$DOCS_DIR"
STD="$DOCS/DEVELOPMENT_STANDARDS.md"
AGENTS="$ROOT/AGENTS.md"
BFLOG="$DOCS/bugfix-log.md"
# 变更根（v3.18.0 批次审计用）：默认 = <docs>/changes，与门禁同一套解析规则。
CHANGE_DIR="${AGENT_GUARD_CHANGE_ROOT:-$(cfg_path change_root "$DOCS_DIR/changes")}"
CHANGES="$ROOT/$CHANGE_DIR"

pass=0
fail=0
failed_names=()

report() { # name expected actual
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$(( pass + 1 ))
    # --only-fail（v3.23.0）：ok 行抑制，但 skip / VACUOUS SKIP 类行豁免——
    # 空转声明（v3.21.0）属于"读到它不能当通过"的正信号，吞掉它就是假绿复活。
    if [[ "$only_fail" -eq 1 ]] && [[ "$name" != *SKIP* && "$name" != *skip* ]]; then
      return 0
    fi
    printf 'ok   %s\n' "$name"
  else
    fail=$(( fail + 1 ))
    failed_names+=("$name")
    printf 'FAIL %s (expected %s, got %s)\n' "$name" "$expected" "$actual" >&2
  fi
}

at_least() { # name min actual_count
  if [[ "$3" -ge "$2" ]]; then report "$1" ok ok; else report "$1" ">=$2" "$3"; fi
}

[[ -f "$STD" ]] || { echo "SKIP: $STD 不存在（本仓库未接入 dev-standards-bootstrap）"; exit 0; }

# ---------- G1 版本链 ----------
SV=$(grep -oE '规范版本：v[0-9.]+' "$STD" | head -1 | grep -oE '[0-9.]+')
AV=$(grep -oE '规范版本：v[0-9.]+' "$AGENTS" 2>/dev/null | head -1 | grep -oE '[0-9.]+' || echo "")
report "G1 AGENTS.md footer version == standards footer version" "$SV" "$AV"

# ---------- 规范 §3 清单标签（按章节标题锚定 fence，防序号法空转） ----------
S3TMP=$(mktemp)
awk '/^## 3\. 变更执行全流程检查清单/{w=1} w && /^```markdown$/{f=1; w=0; next} f==1{ if(/^```$/){exit} print }' "$STD" \
  | grep -oE '【[^】]+】' | sort > "$S3TMP"

# ---------- G2 编号体系：连续、无跳号 ----------
# 说明：重号（同一编号重复定义）无法在纯文本层面与"引用"可靠区分（TC/REQ 被下游
# 文档合法多次引用），故本脚本只做机器可验的连续性核查；重号核查留 §1.2 编号顺序
# 核对表（B 层/人工）。
#
# 【v3.21.0 两处修正——旧实现对本仓真实产物误报 695 处"缺号"】
#
# ① **只数"定义式"出现，不数"引用"**。旧实现 grep 全文件的 `PREFIX-N`，把正文里的
#    引用也算成编号。实测（本仓 16 个变更目录的 01-spec.md）：
#      · CHG-006 定义 `REQ-033`~`REQ-041`（连续 9 个），但正文引用"`REQ-024`~`REQ-032`"
#        （依赖项/需求变更说明）→ 编号集合被撑到 24..41 → 区间内凭空多出 8 个"缺号"；
#      · CHG-002 定义 `REQ-008`~`REQ-013`，但首行写"REQ 从 `REQ-008` 起（CHG-001 已用
#        `REQ-001`~`REQ-007`）"→ 集合变成 {1,7,8..13} → 报 6 个"缺号"。
#    定义式形状 = 行首是标题（`#`~`######`）/ 表格首列（`| `）/ 列表项（`- `），紧跟
#    `PREFIX-N`；引用（出现在句中、第二列起）不再计入。**实测：全仓 61 个产物文件
#    （16 REQ + 15 DES + 16 TC + 14 SC）用定义式规则误报 0 处。**
#
# ② **区间基线是文件自身的 min，不是 1**。旧实现 `seq 1 "$max"` 假定被审文件独占
#    从 1 开始的整个编号空间，而 §1.2 的编号空间是**全仓全局**的：任何不始于 1 的
#    文件都被判"1..max 全是缺号"。本仓 CHG-016 的 01-spec.md 定义 080~083 连续，
#    却报 79 个缺号。改为 `seq "$min" "$max"`——只要求"文件自己定义的号段无空洞"，
#    这才是"跳号"的正确语义（REQ-001 与 REQ-003 同现而缺 002 = 真跳号，仍被抓）。
#
# 两处修正缺一不可：只改 ② 仍有引用污染（CHG-006 报 8），只改 ① 仍被 1..max 判死
# （CHG-003 定义 14..18 报 13 个缺号）。
DEF_RE() { # <prefix> -> 定义式编号行的正则
  printf '^#{1,6}[[:space:]]*%s-[0-9]+|^\\|[[:space:]]*`?%s-[0-9]+`?[[:space:]]*\\||^-[[:space:]]*`?%s-[0-9]+|^%s-[0-9]+' "$1" "$1" "$1" "$1"
}

check_seq() { # feature_dir prefix file_path label
  local dir="$1" prefix="$2" glob="$3" label="$4"
  local nums min max missing
  nums=$(grep -ohE "$(DEF_RE "$prefix")" "$glob" 2>/dev/null \
    | grep -oE '[0-9]+' | awk '{printf "%d\n", $1}' | sort -n | uniq || true)
  [[ -z "$nums" ]] && { report "$label (no numbers, skip)" ok ok; return; }
  min=$(printf '%s\n' "$nums" | head -1)
  max=$(printf '%s\n' "$nums" | tail -1)
  if [[ "$max" -le 9999 ]]; then
    missing=$(printf '%s\n' "$nums" \
      | awk -v mn="$min" -v mx="$max" '{a[$1+0]=1} END{n=0; for(i=mn;i<=mx;i++) if(!(i in a)) n++; print n}')
    report "$label continuous ${min}..${max} (no gaps)" 0 "$missing"
  else
    report "$label continuity (max=${max} skip)" ok ok
  fi
}

# ---------- 审计目录识别（v3.21.0） ----------
# 用**正信号**识别，不按"是 docs/ 的子目录"取全集：`docs/changes`、`docs/bugs`、
# `docs/review` 都是子目录，但 `docs/changes` 自己不是产物目录（它的**子目录**才是）。
# 旧实现取全集，于是只要 docs/ 下存在任意一个子目录，"没有产物目录"的空转分支就不
# 触发，G2/G3/G5/G6 **一条断言都不执行、也不打印任何行**——操作者读到 "4 passed" 会
# 以为它们都过了。实测（v3.21.0）：一个 `01-spec.md` 里带 REQ 跳号的仓库**通过**了
# 审计（假绿），同时 G4 因为找不到 `docs/changes/09-changelog.md` 误报**假红**。
# 正信号与门禁 `check_delivery_doc` 的"看起来像功能目录"判据同源（CHG-004 为修同族
# 假绿而引入：裸 `<docs>/*/` glob 会让任意占位文件永久放行）。
#
# 规范 §2.17「产物目录双轨约定」：`docs/<feature>/` 是功能级长期文档（05/06/07/09、
# 01.5 矩阵、06.5 等）的权威落点；`docs/changes/<变更号>/` 是变更管线产物（管线入口件
# 与门禁必检 7 件）的落点。
#
# 【审计单元按"不变量对冻结历史的适用性"分两类，这是本文件最核心的划分】
#
#   · **G2 编号连续性 → 功能目录 ∪ 变更目录**。这条不变量是**时间不变**的：`REQ-001`
#     与 `REQ-003` 同现而缺 `002`，在写下那天就是错的，今天仍是错的，与"当时规范怎么写"
#     无关。所以对两轨都成立、都该查。**这是本次修复的靶心**：旧实现只取功能目录，于是
#     `docs/changes/<CHG>/` 布局的仓库里 G2 一条断言都不执行、也不打印任何行，一个
#     01-spec.md 带 REQ 跳号的仓库**通过**了审计（假绿）。
#
#   · **G3/G5/G6 → 只取功能目录（活文档）**。这三组是拿**当前规范版本**去比对：G3 比
#     §3 归档清单标签、G6 比 §4 必填节、G5 比 01.5 矩阵回填。而 §2.15 硬性规则 4 与
#     §2.16.5「已闭合 CHG 禁止改写，勘误/补充一律新开一组变更文档」**明令历史变更目录
#     不可回填**——拿今天的 §3 去判 CHG-002 的归档清单，是**时代错置**：它只会产出
#     **永久无法清除的红**（本仓实测：CHG-002/CHG-005/CHG-007 共 4 条，且按规范不许改）。
#     永久红比漏报更坏：它训练操作者忽略审计。变更轨的这三类一致性由**门禁在创建时**
#     （`begin`/`staged`/`ci`/`stop`，那时产物还可修）承担，不由事后审计承担。
#     功能目录的 09-changelog 是**活文档**（累积 CHG，最新一条即当前变更）→ 可行动。
#
# 「变更目录」按**结构**判定（直接位于 `<change_root>/` 下一层），不按目录名猜——
# 变更号允许自定义形状（含 `BUG-<UTC 时间戳>` 等事故重入号），名字判据不可靠。
looks_like_audit_dir() { # <dir> -> 0 当且仅当它承载变更/功能产物
  [[ -f "$1/01-spec.md" || -f "$1/01.5-rtvm-matrix.md" || -f "$1/09-changelog.md" ]]
}

# 正信号 = 承载 01-spec / 01.5 矩阵 / 09-changelog 之一；`docs/bugs/<BUG-xxx>/` 的六件套
# 不命中本信号——v3.28.0 起其**存在性与盖章**由 G8 / A21 直接审计（不再"刻意排除"后
# 委托给可能不跑的门禁），其编号/§3/§4 同源类一致性仍归门禁与 B 层 Review。
# sort -u 去重：change_root 配成 docs 根时两路枚举会重叠。
audit_dirs=""   # G2：功能目录 ∪ 变更目录
g36_dirs=""     # G3/G5/G6：仅活文档（不在 <change_root>/ 下的产物目录）
for base in "$DOCS" "$CHANGES"; do
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    looks_like_audit_dir "$d" || continue
    audit_dirs="$audit_dirs$d"$'\n'
    # 变更根下的目录 = 冻结历史 → 不进 G3/G5/G6。
    case "$d" in "$CHANGES"/*) ;; *) g36_dirs="$g36_dirs$d"$'\n' ;; esac
  done <<< "$(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)"
done
audit_dirs=$(printf '%s' "$audit_dirs" | sort -u)
g36_dirs=$(printf '%s' "$g36_dirs" | sort -u)

if [[ -z "$audit_dirs" ]]; then
  # **显式声明"这些组没跑"**。静默空转 = 假绿，是本文件最该防的失效模式：旧实现只在
  # `<docs>/` 连一个子目录都没有时才打这一行，而 `docs/changes`、`docs/bugs`、
  # `docs/review` 都算"子目录"——它们一存在，G2/G3/G5/G6 就**一条断言都不执行、也不打
  # 任何行**，操作者读到 "4 passed" 会以为这几组都过了。实测：一个 01-spec.md 带 REQ
  # 跳号的仓库**通过**了审计。此行故意写得啰嗦：它不是"通过"，是"未覆盖"。
  report "G2 VACUOUS SKIP — no artifact dir under $DOCS_DIR/ or $CHANGE_DIR/, so G2 did NOT run (do NOT read this as a pass)" ok ok
else
  # while-read 逐行迭代：兼容含空格的目录名（for in $var 会按空格拆词）
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    fname=$(basename "$d")
    [[ -f "$d/01-spec.md" ]] && check_seq "$d" "REQ" "$d/01-spec.md" "G2 REQ numbering in $fname"
    [[ -f "$d/03-modification-plan.md" ]] && check_seq "$d" "DES" "$d/03-modification-plan.md" "G2 DES numbering in $fname"
    [[ -f "$d/04-test-scripts.md" ]] && check_seq "$d" "TC" "$d/04-test-scripts.md" "G2 TC numbering in $fname"
    [[ -f "$d/04-test-scripts.md" ]] && check_seq "$d" "SC" "$d/04-test-scripts.md" "G2 SC numbering in $fname"
    [[ -f "$d/09-changelog.md" ]] && check_seq "$d" "CHG" "$d/09-changelog.md" "G2 CHG numbering in $fname"
    [[ -f "$d/06.5-deployment-config.md" ]] && check_seq "$d" "CFG" "$d/06.5-deployment-config.md" "G2 CFG numbering in $fname"
    [[ -f "$d/06.5-deployment-config.md" ]] && check_seq "$d" "DB" "$d/06.5-deployment-config.md" "G2 DB numbering in $fname"
    [[ -f "$d/06-delivery-summary.md" ]] && check_seq "$d" "FU" "$d/06-delivery-summary.md" "G2 FU numbering in $fname"
  done <<< "$audit_dirs"
fi

# G3/G5/G6 的空转声明（与 G2 分开声明：两组的覆盖面不同，合并成一句会让操作者
# 误判"哪几组没跑"）。只落变更目录的仓库会命中这一行——那是**设计如此**（见上方划分），
# 不是缺陷，但必须让操作者知道这三组没覆盖本仓库。
if [[ -z "$g36_dirs" ]]; then
  report "G3/G5/G6 VACUOUS SKIP — no living-doc dir (feature dir) outside $CHANGE_DIR/; these groups did NOT run (by design: frozen change dirs are the gate's job, see header)" ok ok
fi

# ---------- G3 §3↔§4 同源 + G5 RTVM + G6 必填节（逐活文档目录的 09-changelog 最新 CHG） ----------
# 迭代 **$g36_dirs**（活文档），不是 $audit_dirs：见上方"审计单元分两类"——拿当前 §3/§4
# 判冻结的变更目录是时代错置。
while IFS= read -r c; do
  chg="$c/09-changelog.md"
  [[ -f "$chg" ]] || continue
  fname=$(basename "$c")
  CHG_BLOCK=$(mktemp)
  awk 'BEGIN{f=0} f==1 && /^## /{exit} /^## /{f=1} f==1{print}' "$chg" > "$CHG_BLOCK"
  # G6 §4 必填节
  for sec in "#### 追踪矩阵映射" "#### 现象" "#### 分析" "#### 根因" "#### 方案" "#### 测试脚本与结论" "#### 角色签署与独立性" "#### 执行记录（ReAct" "#### 变更执行检查清单" "#### 未动项"; do
    grep -q "$sec" "$CHG_BLOCK" && report "G6 $fname latest CHG has '$sec'" ok ok \
      || report "G6 $fname latest CHG has '$sec'" ok missing
  done
  # G3 归档清单标签同源
  L4TMP=$(mktemp)
  awk '/^#### 变更执行检查清单/{f=1; next} f==1 && /^#### /{exit} f==1{print}' "$CHG_BLOCK" \
    | grep -oE '【[^】]+】' | sort > "$L4TMP"
  if diff -q "$S3TMP" "$L4TMP" >/dev/null 2>&1; then
    report "G3 $fname archived checklist labels == standards §3" ok ok
  else
    report "G3 $fname archived checklist labels == standards §3" ok diff
  fi
  n3=$(wc -l < "$L4TMP" | tr -d ' ')
  report "G3 $fname archived checklist non-empty (防恒真空转)" 1 "$([[ "$n3" -gt 0 ]] && echo 1 || echo 0)"
  rm -f "$L4TMP"
  # G5 RTVM 短引用 ⊆ 01.5 矩阵（门禁 4：只改 changelog 不回填矩阵视为未闭环）。
  # §2.17：该矩阵**单落点于功能目录**（不双落变更目录），而本循环的审计单元正是功能
  # 目录（活文档）→ 就地取即正确，不需要全树兜底。**若这里改成"全树任意矩阵"兜底，
  # 会掩盖"矩阵被放错落点"这一真实问题**——那正是 G5 想抓的分叉。
  if [[ -f "$c/01.5-rtvm-matrix.md" ]]; then
    unreached=0
    for r in $(grep -oE 'REQ-[0-9]+' "$CHG_BLOCK" | sort -u); do
      grep -qE "^\| \`?${r}\`?" "$c/01.5-rtvm-matrix.md" || unreached=$(( unreached + 1 ))
    done
    report "G5 $fname CHG REQ rows all backfilled in 01.5 matrix" 0 "$unreached"
  elif grep -qE 'REQ-[0-9]+' "$CHG_BLOCK"; then
    report "G5 $fname CHG references REQ but 01.5-rtvm-matrix.md missing (gate 4 backfill)" 0 1
  else
    report "G5 $fname no REQ refs in latest CHG (matrix exempt)" ok ok
  fi
  rm -f "$CHG_BLOCK"
done <<< "$g36_dirs"

# ---------- G7 变更批次自洽（v3.18.0） ----------
# 批次目录 = <change_root>/BATCH-YYYYMMDD/（§1.1 同天 L0/L1 合并）。它把"一个变更
# 一套产物"放宽为"一套产物承载多个变更"，放宽的代价必须由机器盯住，否则批次会变成
# 绕过 A 层门禁的暗道。四条不变量，全部纯文本可验（无需 JSON 解析器）：
#   a) 记录 ⊆ 入口锚点：每条 change_id 必须在批次 00-intent.md 有自己的 `## <id>`
#      小节（§2.17 管线入口按变更分节；缺了就是"登记了却没说要做啥"）
#   b) 记录 ⊆ 锚点：每条 change_id 必须能在批次内某 *.md 找到锚点（否则是孤儿记录）
#   c) 风险等级 ∈ {L0,L1}：批次是低风险专用通道，L2/L3 必须在独立目录
#   d) 变更号跨批次唯一：同一 id 出现在两个批次 → 检索与归属二义
# 锚点形状与门禁 anchors_in_file 用同一条 sed 表达式，防止"审计认得的锚点"和
# "门禁认得的锚点"悄悄分叉（分叉会让审计通过而门禁拒绝，或反之）。
#
# 【v3.19.0 修正】原 a) 是"批次内任一 *.md 的 `## <id>` 必须有治理记录"，即把
# **每一个** `## <ascii 单词>` 标题都当作变更号。这条方向在批次里站不住：规范
# §2.16.2 强制 `09-changelog.md` 含 Observation 记录，作者写成 `## Observation`
# 时它就是一条合法标题——审计会把它当成"未登记的变更"报红（实测假红），门禁
# 也会拿 "Observation" 去查治理记录并拒绝整批（同一根因）。`## <标题>` 在文本
# 层面无法区分"变更小节"与"结构小节"，所以这条反向不变量被**替换**为 a)：
# 只从权威名单（00-governance.json 的 change_id）出发，不再反向推断。
# 代价如实记录："写了一个没登记的 `## CHG-903` 小节"不再由审计发现——但它本来
# 也由门禁兜住：任何变更号被 begin/staged/ci 用到时，validate_governance_state
# 都会因"没有治理记录"而 fail-closed（比按标题形状猜更准）。
batch_dirs=$(find "$CHANGES" -mindepth 1 -maxdepth 1 -type d \
  -name 'BATCH-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 2>/dev/null | sort || true)
if [[ -z "$batch_dirs" ]]; then
  report "G7 no change batches (vacuous skip)" ok ok
else
  b_noentry=0; b_unanchored=0; b_badrisk=0; b_dup=0
  seen_ids=$(mktemp)
  while IFS= read -r bd; do
    [[ -d "$bd" ]] || continue
    bname=$(basename "$bd")
    gov="$bd/00-governance.json"
    if [[ ! -s "$gov" ]]; then
      report "G7 $bname carries 00-governance.json" ok missing
      continue
    fi
    report "G7 $bname carries 00-governance.json" ok ok
    # 权威名单：只从治理记录取变更号（见文件头 v3.19.0 修正说明）。
    ids=$(grep -oE '"change_id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9._-]+"' "$gov" 2>/dev/null \
      | sed -E 's/.*"([A-Za-z0-9._-]+)"$/\1/' | sort -u || true)
    anchors=$(sed -nE 's/^##[[:space:]]+([A-Za-z0-9][A-Za-z0-9_-]*)([[:space:]].*)?$/\1/p' \
      "$bd"/*.md 2>/dev/null | sort -u || true)
    # a) 管线入口按变更分节（只查 00-intent.md，不查全部 *.md —— 后者会把
    #    `## Observation` 这类结构标题算成变更小节）。
    entry_anchors=$(sed -nE 's/^##[[:space:]]+([A-Za-z0-9][A-Za-z0-9_-]*)([[:space:]].*)?$/\1/p' \
      "$bd/00-intent.md" 2>/dev/null | sort -u || true)
    for i in $ids; do
      printf '%s\n' "$entry_anchors" | grep -qx "$i" || b_noentry=$(( b_noentry + 1 ))
    done
    for i in $ids; do
      printf '%s\n' "$anchors" | grep -qx "$i" || b_unanchored=$(( b_unanchored + 1 ))
    done
    for r in $(grep -oE '"risk_level"[[:space:]]*:[[:space:]]*"[^"]*"' "$gov" 2>/dev/null \
      | sed -E 's/.*"([^"]*)"$/\1/' || true); do
      case "$r" in L0|L1) ;; *) b_badrisk=$(( b_badrisk + 1 )) ;; esac
    done
    for i in $ids; do
      if grep -qx "$i" "$seen_ids" 2>/dev/null; then
        b_dup=$(( b_dup + 1 ))
      else
        printf '%s\n' "$i" >> "$seen_ids"
      fi
    done
  done <<< "$batch_dirs"
  report "G7 every batch change has a section in the batch 00-intent.md" 0 "$b_noentry"
  report "G7 every batch governance record has an anchor" 0 "$b_unanchored"
  report "G7 batch risk levels are L0/L1 only" 0 "$b_badrisk"
  report "G7 change ids unique across batches" 0 "$b_dup"
  rm -f "$seen_ids"
fi

# ---------- G4 bugfix 双登记互证 ----------
if [[ -f "$BFLOG" ]]; then
  # 陈旧模板占位自检：旧版模板占位标题含数字（### BUG-001：<一句话现象标题>），
  # 会被规范阶段 6 A 层 ^### BUG-[0-9] 计入 → 恒真统计。存在即判未替换。
  report "G4 stale numeric placeholder absent" 0 "$(grep -cE '^### BUG-0+1：<一句话现象标题>' "$BFLOG" 2>/dev/null || true)"
  # 两个方向都必须遍历**全树** changelog，而不只是功能目录：变更轨的 09-changelog
  # 落在 <change_root>/<变更号>/（深度 2），而旧实现只看 <docs>/ 下一层的
  # `$c/09-changelog.md`。**同一根因**造成一对不对称的假判定：
  #   · "每条已登记 BUG 都被某 CHG 引用" → **假红**（CHG 明明引用了，却找不到 changelog）；
  #   · "每条 CHG 的 BUG 行都已登记 log" → **空转假绿**（一个 changelog 都没读到，unlogged 恒为 0）。
  # v3.21.0 修正。
  all_changelogs=$(find "$DOCS" -name '09-changelog.md' -type f 2>/dev/null || true)
  orphans=0
  for b in $(grep -oE '^### BUG-[0-9]+' "$BFLOG" | grep -oE '[0-9]+' | awk '{printf "%d\n", $1}' | sort -n | uniq); do
    hit=0
    while IFS= read -r chg; do
      [[ -n "$chg" ]] || continue
      grep -qE "BUG-0*${b}([^0-9]|$)" "$chg" && hit=1
    done <<< "$all_changelogs"
    [[ "$hit" -eq 0 ]] && orphans=$(( orphans + 1 ))
  done
  report "G4 every logged BUG referenced by some CHG" 0 "$orphans"
  unlogged=0
  while IFS= read -r chg; do
    [[ -n "$chg" ]] || continue
    # 取「对应缺陷」行整行，行内可能引用多个 BUG（同批修复）
    bug_line=$(grep '对应缺陷' "$chg" | head -1)
    [[ -z "$bug_line" ]] && continue
    for b in $(printf '%s' "$bug_line" | grep -oE 'BUG-[0-9]+' | grep -oE '[0-9]+' | awk '{printf "%d\n", $1}' | sort -n | uniq); do
      grep -qE "^### BUG-0*${b}([^0-9]|$)" "$BFLOG" || unlogged=$(( unlogged + 1 ))
    done
  done <<< "$all_changelogs"
  report "G4 every CHG BUG line registered in log" 0 "$unlogged"
else
  report "G4 no $DOCS_DIR/bugfix-log.md (skip; Bug 修复须先按 §2.5 阶段 6 建立)" ok ok
fi

# ---------- G8 缺陷六件套存在性 + A20/A21 溯源盖章互证（v3.28.0） ----------
BUGS_DIR="${AGENT_GUARD_BUGS_ROOT:-$(cfg_path bugs_root "$DOCS_DIR/bugs")}"
BUGS="$ROOT/$BUGS_DIR"
ALLOW="$BUGS/.gate-allowlist"
SIX="01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md"

if [[ -d "$BUGS" ]]; then
  incomplete=0; allow_n=0
  # v3.35.0 (BUG-005): sweep BOTH layouts — standalone and day-batched groups.
  for g in "$BUGS"/BUG-*/ "$BUGS"/BATCH-*/BUG-*/; do
    [[ -d "$g" ]] || continue
    any=0
    for doc in $SIX; do [[ -e "$g/$doc" ]] && any=1; done
    [[ "$any" == 1 ]] || continue
    gid=$(basename "$g"); miss=""
    for doc in $SIX; do [[ -s "$g/$doc" ]] || miss="$miss $doc"; done
    [[ -z "$miss" ]] && continue
    listed=""
    [[ -f "$ALLOW" ]] && listed=$(grep -vE '^[[:space:]]*(#|$)' "$ALLOW" 2>/dev/null | awk '{print $1}' | grep -Fx "$gid" || true)
    if [[ -n "$listed" ]]; then
      allow_n=$((allow_n+1)); echo "     G8 allowlisted legacy: $gid — missing:$miss"
    else
      incomplete=$((incomplete+1)); echo "     G8 incomplete: $gid — missing:$miss (补六件，或登记理由进 $ALLOW)"
    fi
  done
  # v3.36.0 (BUG-006): FLAT day-batches — six pieces directly in BATCH-*/,
  # members separated by `## <BUG-id>` anchors; anchor-based completeness.
  for g in "$BUGS"/BATCH-*/; do
    [[ -s "${g}01-diagnosis.md" ]] || continue
    for gid in $(sed -nE 's/^##[[:space:]]+(BUG-[A-Za-z0-9._-]+)([[:space:]].*)?$/\1/p' "${g}01-diagnosis.md" | sort -u); do
      miss=""
      for doc in $SIX; do
        grep -qE "^##[[:space:]]+${gid}([[:space:]]|\$)" "$g/$doc" 2>/dev/null || miss="$miss $doc"
      done
      [[ -z "$miss" ]] && continue
      listed=""
      [[ -f "$ALLOW" ]] && listed=$(grep -vE '^[[:space:]]*(#|$)' "$ALLOW" 2>/dev/null | awk '{print $1}' | grep -Fx "$gid" || true)
      if [[ -n "$listed" ]]; then
        allow_n=$((allow_n+1)); echo "     G8 allowlisted legacy: $gid — missing:$miss"
      else
        incomplete=$((incomplete+1)); echo "     G8 incomplete: $gid — missing:$miss (扁平批次锚点缺件；补齐 $g 六件锚点，或登记理由进 $ALLOW)"
      fi
    done
  done
  report "G8 bug doc groups complete (six-piece)" 0 "$incomplete"
  report "G8 allowlisted legacy groups (counted, not hidden)" "$allow_n" "$allow_n"
else
  report "G8 VACUOUS SKIP — no $BUGS_DIR/ directory, so G8 did NOT run (do NOT read this as a pass)" ok ok
fi

vge() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,x,".");split(b,y,".");for(i=1;i<=3;i++){x[i]+=0;y[i]+=0;if(x[i]>y[i])exit 0;if(x[i]<y[i])exit 1}exit 0}'; }

if [[ -d "$CHANGES" ]]; then
  partial=0; era=0
  for cd_ in "$CHANGES"/*/; do
    [[ -d "$cd_" ]] || continue
    total=0; have=0
    for pf_ in "$cd_"*.md; do
      [[ -f "$pf_" ]] || continue
      total=$((total+1))
      grep -q '^<!-- provenance$' "$pf_" 2>/dev/null && have=$((have+1))
    done
    [[ "$total" -eq 0 ]] && continue
    if [[ "$have" -gt 0 && "$have" -lt "$total" ]]; then
      partial=$((partial+1)); echo "     A20 partial stamping: $(basename "$cd_") — $have/$total stamped"
    fi
    std_v=$(tr -d '\n' < "$cd_/00-governance.json" 2>/dev/null | sed -nE 's/.*"standard_version"[[:space:]]*:[[:space:]]*"v?([0-9.]+)".*/\1/p' | head -1)
    if [[ -n "$std_v" ]] && vge "$std_v" "3.26.0" && [[ "$have" -lt "$total" ]]; then
      era=$((era+1)); echo "     A20 v3.26+ change not fully stamped: $(basename "$cd_") (std $std_v) — $have/$total"
    fi
  done
  report "A20 change-dir stamping complete once started (no half-stamped dirs)" 0 "$partial"
  report "A20 v3.26.0+ change dirs fully stamped" 0 "$era"
else
  report "A20 VACUOUS SKIP — no change root, so A20 did NOT run (do NOT read this as a pass)" ok ok
fi

if [[ -d "$BUGS" ]]; then
  unprov=0
  # v3.35.0 (BUG-005): both layouts — standalone and day-batched groups.
  for g in "$BUGS"/BUG-*/ "$BUGS"/BATCH-*/BUG-*/; do
    [[ -d "$g" ]] || continue
    for pf_ in "$g"*.md; do
      [[ -f "$pf_" ]] || continue
      grep -q '^<!-- provenance$' "$pf_" 2>/dev/null || { unprov=$((unprov+1)); echo "     A21 unstamped: $pf_"; }
    done
  done
  # v3.36.0 (BUG-006): flat batches — the six pieces live directly in BATCH-*/
  # (nested subgroups are covered by the loop above, not by their parent).
  for g in "$BUGS"/BATCH-*/; do
    [[ -s "${g}01-diagnosis.md" ]] || continue
    for pf_ in "$g"*.md; do
      [[ -f "$pf_" ]] || continue
      grep -q '^<!-- provenance$' "$pf_" 2>/dev/null || { unprov=$((unprov+1)); echo "     A21 unstamped: $pf_"; }
    done
  done
  report "A21 bug doc groups carry provenance (stamp --bug)" 0 "$unprov"
else
  report "A21 VACUOUS SKIP — no $BUGS_DIR/ directory" ok ok
fi

# ---------- G9 项目级总册存在与自证（v3.35.0，§1.3） ----------
# 12 册在位、逐册自证（总册编号 + 独立完整声明）、评审记录成对；最新变更 09 含
# 回填清单节（存量回填清单语义，§2.14——失败项即回填清单，不产生"永久红"的
# 历史改写义务：总册是活文档，缺什么补什么即可）。
PROJECT_DIR="$ROOT/$DOCS_DIR/project"
if [[ -d "$PROJECT_DIR" ]]; then
  gm_missing=0; gself=0; grev=0
  for f in P00-project-charter.md P01-requirements-master.md P02-architecture-master.md P03-interface-registry.md P04-data-dictionary.md P05-task-plan.md P06-test-master.md P07-test-verdicts.md P08-deployment-master.md P09-risk-register.md P10-change-ledger.md P11-decision-log.md; do
    pm="$PROJECT_DIR/$f"
    if [[ ! -s "$pm" ]]; then
      gm_missing=$((gm_missing+1)); echo "     G9 missing master: project/$f"
      continue
    fi
    px="${f%%-*}"
    grep -q "总册编号：${px}" "$pm" || { gself=$((gself+1)); echo "     G9 no master id: project/$f (expect 总册编号：$px)"; }
    grep -q "独立完整声明" "$pm" || { gself=$((gself+1)); echo "     G9 no self-containment claim: project/$f (expect 独立完整声明)"; }
    rev="$PROJECT_DIR/reviews/$f.review.md"
    [[ -s "$rev" ]] || { grev=$((grev+1)); echo "     G9 missing review record: reviews/$f.review.md"; }
  done
  report "G9 project masters complete (twelve files)" 0 "$gm_missing"
  report "G9 project masters self-attesting (id + 独立完整声明)" 0 "$gself"
  report "G9 project masters review records paired" 0 "$grev"
  # 最新变更 09 含回填清单节（仅在仓库已有变更目录时核；按 mtime 取最新）。
  g9_ledger=0
  latest_chg=$(ls -1dt "$CHANGES"/*/ 2>/dev/null | while read -r cd2; do [[ -s "$cd2/09-changelog.md" ]] && printf '%s\n' "$cd2"; done | grep -E '/(CHG|BUG|BATCH)-[0-9]+$' | head -1)
  if [[ -n "$latest_chg" ]]; then
    grep -q "项目总册回填清单" "$latest_chg/09-changelog.md" || g9_ledger=1
    report "G9 latest change carries 项目总册回填清单 ($(basename "$latest_chg"))" 0 "$g9_ledger"
  else
    report "G9 latest-change ledger check VACUOUS SKIP — no change dirs with 09 yet" ok ok
  fi
else
  report "G9 VACUOUS SKIP — no $DOCS_DIR/project/ directory (masters not initialized; init on next change, standards §1.3)" ok ok
fi

# ---------- G9 功能目录表外子目录 sweep（v3.37.1 CHG-037/FU-105，§1.3 第 6 条执法面） ----------
# 评审留痕唯一落点 = 变更轨 07-review-report.md + 总册 reviews/（§1.3 第 6 条）；功能目录
# （含 01-spec.md 或 01.5-rtvm-matrix.md，与 gate "看起来像功能目录"判据同源）内出现
# reviews/ 等表外子目录即红。表外文件默认禁止——本断言只拦 FU-105 裁定的 reviews/ 形态。
# 结构目录与隐藏目录豁免；功能目录集合为空时显式空转（防静默假绿，§1.1）。
ooot=0; ofeat=0
for d2 in "$ROOT/$DOCS_DIR"/*/; do
  b2=$(basename "$d2")
  case "$b2" in changes|bugs|project|templates|methodologies|review) continue ;; esac
  [[ -f "$d2/01-spec.md" || -f "$d2/01.5-rtvm-matrix.md" ]] || continue
  ofeat=$((ofeat+1))
  if [[ -d "$d2/reviews" ]]; then
    ooot=$((ooot+1))
    echo "     G9 out-of-table reviews/ in feature dir $b2 (spec §1.3 rule 6: unique locations = change-track 07 + project reviews/)"
  fi
done
if [[ "$ofeat" -gt 0 ]]; then
  report "G9 feature dirs carry no out-of-table reviews/ (spec §1.3 rule 6)" 0 "$ooot"
else
  report "G9 out-of-table feature-dir sweep VACUOUS SKIP — no feature dirs under $DOCS_DIR/ (did NOT run; do not read this as a pass)" ok ok
fi

# ---------- G10 废弃条款 sweep（v3.40.0 CHG-048 / FU-106⑥，减法机制执法面） ----------
# 规范只加不减 = 无限膨胀（A11 上界多次重校准为证）。本门只做可确定性判定的
# 形态校验：DEVELOPMENT_STANDARDS.md / AGENTS.md 内每一行含「废止」字样的文字，
# 必须同行携带被替代版本指向（v3. 数字），使被替代条款可追溯、可清扫；缺指向
# 的废止标记 = 只废未清，FAIL 并列行。「加一删一」预算本身是政策层
# （MAINTAINER §5.2，B 层），不在此机校（防过度设计，METHODOLOGY M2）。
g10_bad=0; g10_hits=0
for f10 in "$STD" "$ROOT/$DOCS_DIR/AGENTS.md"; do
  [[ -f "$f10" ]] || continue
  while IFS= read -r l10; do
    g10_hits=$((g10_hits+1))
    printf '%s' "$l10" | grep -qE 'v3\.[0-9]' \
      || { g10_bad=$((g10_bad+1)); echo "     G10 废止标记缺版本指向: $(basename "$f10"): $(printf '%s' "$l10" | cut -c1-72)"; }
  done < <(grep -Fn "废止" "$f10" 2>/dev/null | sed 's/^[0-9]*://')
done
if [[ "$g10_hits" -gt 0 ]]; then
  report "G10 every 废止 marker carries a superseding v3.x pointer" 0 "$g10_bad"
else
  report "G10 废止-marker sweep VACUOUS SKIP — no markers in STD/AGENTS (did NOT run; do not read this as a pass)" ok ok
fi

rm -f "$S3TMP"
echo
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
