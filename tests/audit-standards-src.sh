#!/usr/bin/env bash
# Standards 文档一致性机器审计（audit-docs-consistency）
#
# 背景：v3.4.0 收敛审计（三轮全维度遍历）发现的不变量，全部固化为机器断言。
# 目的：文档完整性由方法 + 机器保证，不由"再问一轮"保证（教训 6：反应式返工成本指数级）。
#
# 【适用范围分层——防误用】
#   通用层（随 Skill 复制到目标仓库）：resources/templates/agent-gate.sh、tests/run-tests.sh、
#                                     check-standards-compliance.sh——审计"被治理仓库的变更产物"。
#   规范源层（仅本仓库，禁止写入 SKILL 复制清单）：本脚本——审计"规范文本自身"的一致性。
#   目标仓库不需要本脚本：其文档一致性由门禁（gate/compliance）与规范落点保证，不复制规范正文。
#
# 【断言分区——防脚本腐烂】
#   PART A 永久结构不变量：版本链、清单同源、编号体系、防恒真、7+1 对齐、锚点存在性、
#          树↔磁盘、日志排序——跨规范版本有效，仅随结构变化维护。
#   PART B 版本快照不变量（当前锚定 v<页脚版本> 的特性落点）：关键词矩阵、措辞锚点——
#          规范每次升级（§2.14）时随升级日志更新本区；旧版本快照可归档或删除，不影响 A 区。
#
# 零依赖：bash 3.2+、grep、awk、diff。修改规范正文 / 模板 / README 后必须先跑通本脚本（SKILL.md 版本同步红线）。
#
# Usage: tests/audit-docs-consistency.sh
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STD="$ROOT/resources/DEVELOPMENT_STANDARDS.md"
AGENTS="$ROOT/resources/AGENTS.md"
METH="$ROOT/resources/METHODOLOGY.md"
DEV="$ROOT/resources/methodologies/development.md"
DS="$ROOT/resources/methodologies/data-structures.md"
STA="$ROOT/resources/methodologies/state-trigger-audit.md"
BFLOG="$ROOT/resources/templates/bugfix-log.md"
PIPE="$ROOT/resources/templates/github-artifact-pipeline.yml"
SKILL="$ROOT/SKILL.md"
RM_EN="$ROOT/README.md"
RM_ZH="$ROOT/README.zh-CN.md"

pass=0
fail=0
failed_names=()

report() { # name expected actual
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$(( pass + 1 ))
    printf 'ok   %s\n' "$name"
  else
    fail=$(( fail + 1 ))
    failed_names+=("$name")
    printf 'FAIL %s (expected %s, got %s)\n' "$name" "$expected" "$actual" >&2
  fi
}

grep_count() { # file pattern -> count（basic grep）
  grep -c -- "$2" "$1" 2>/dev/null || true
}

# 至少出现一次（关键词落点矩阵用；出现多处于语义无害）
at_least() { # name min file pattern
  local name="$1" min="$2" file="$3" pattern="$4"
  local c
  c=$(grep_count "$file" "$pattern")
  if [[ "$c" -ge "$min" ]]; then
    report "$name" ok ok
  else
    report "$name" ">=${min}" "$c"
  fi
}

# ===================== PART A：永久结构不变量（跨版本有效） =====================

# ---------- 版本链（单一权威：规范页脚） ----------
V=$(grep -oE '规范版本：v[0-9.]+' "$STD" | head -1 | grep -oE '[0-9.]+')
[[ -n "$V" ]] || V="UNKNOWN"

for f in "$AGENTS" "$METH"; do
  report "version footer synced: $(basename "$f")" 1 "$(grep_count "$f" "当前对应规范版本：v${V}_")"
done

# 方法论层页脚：动态遍历 resources/methodologies/*.md，禁止写静态清单。
#   CHG-004 / BUG-002：原实现为静态清单 "$AGENTS" "$METH" "$DEV" "$DS"——**漏了
#   state-trigger-audit.md**（该文件也确实没有页脚，双缺）。根因与 BUG-001 同族：
#   "方法论层版本页脚已同步"的语义覆盖面是"该目录下全部 .md"，而静态清单窄于语义
#   → 新增方法论文件不会自动纳入校验，规范升级时该文件静默滞后。
#   改为动态遍历后新增文件自动纳入；再加一条聚合断言防"遍历集本身漏文件"复发。
for m in $(ls "$ROOT/resources/methodologies" | grep '\.md$' | sort); do
  report "version footer synced: methodologies/$m" 1 \
    "$(grep_count "$ROOT/resources/methodologies/$m" "当前对应规范版本：v${V}_")"
done
# fail-closed：目录为空/文件数异常少时不得静默通过
m_all=$(ls "$ROOT"/resources/methodologies/*.md 2>/dev/null | wc -l | tr -d ' ')
m_ok=$(grep -l "当前对应规范版本：v${V}_" "$ROOT"/resources/methodologies/*.md 2>/dev/null | wc -l | tr -d ' ')
m_min=0; [[ "$m_all" -ge 3 ]] && m_min=1
report "methodology layer file count >= 3 (fail-closed)" 1 "$m_min"
report "methodology layer footer coverage == file count" "$m_all" "$m_ok"

report "version badge zh"            1 "$(grep_count "$RM_ZH" "规范版本-v${V}-")"
report "version badge en"            1 "$(grep_count "$RM_EN" "Standards-v${V}-")"
report "version footer zh"           1 "$(grep_count "$RM_ZH" "规范版本：\*\* v${V}")"
report "version footer en"           1 "$(grep_count "$RM_EN" "Standards Version:\*\* v${V}")"
report "version tree zh"             1 "$(grep_count "$RM_ZH" "完整规范文档 v${V}")"
report "version tree en"             1 "$(grep_count "$RM_EN" "Full standards document v${V}")"
report "skill carried version"       1 "$(grep_count "$SKILL" "当前携带版本 v${V}")"

# SKILL.md 版本可见性三载体（用户需求："在 skill 里就能看到是不是最新版"）。
# 平台事实：SKILL.md frontmatter 无 version 字段、/skills 面板只展示 name + description
# → 只写 frontmatter 用户看不见；只写正文则技能列表里看不见。故版本必须同时落在
# ①frontmatter version ②description 尾注 ③正文顶部横幅。三处任一漂移（升级规范时漏改）
# 即红——与"版本页脚已同步"同族：声称的覆盖面必须等于校验的覆盖面。
report "skill frontmatter version == footer version" "$V" \
  "$(grep -m1 -oE '^version: [0-9.]+' "$SKILL" | grep -oE '[0-9.]+')"
report "skill description carries carried version" 1 "$(grep_count "$SKILL" "携带规范版本 v${V}")"
report "skill body version banner present" 1 "$(grep_count "$SKILL" "当前携带版本：v${V}")"

# 升级日志（v3.8.0 起外置 STANDARDS_CHANGELOG.md，CHG-005）：新文件存在、
# 新条目置顶且首行版本 == 页脚版本、规范正文不再内嵌历史日志行
SLOG="$ROOT/resources/STANDARDS_CHANGELOG.md"
report "standards changelog file exists and non-empty" 1 "$([[ -s "$SLOG" ]] && echo 1 || echo 0)"
log_head=$(grep -m1 -oE '^\| v[0-9.]+' "$SLOG" 2>/dev/null | grep -oE '[0-9.]+')
report "standards changelog newest row == footer version" "$V" "$log_head"
at_least "standards §2.14 rule points to STANDARDS_CHANGELOG" 1 "$STD" 'STANDARDS_CHANGELOG.md'
std_log_rows=$(grep -cE '^\| v[0-9]+\.[0-9]+\.[0-9]+ \| 20[0-9]{2}-' "$STD")
report "standards body carries no historical upgrade-log rows" 0 "$std_log_rows"

# ===================== PART B：版本快照不变量（v<页脚版本> 特性落点，升级时随 §2.14 日志更新本区） =====================

# ---------- 关键词落点矩阵（v3.4.0：状态/触发链路审计 + 同族推演） ----------
for f in "$STD" "$METH" "$STA" "$BFLOG" "$AGENTS" "$RM_ZH"; do
  at_least "keyword 同族推演 in $(basename "$f")" 1 "$f" "同族推演"
done
at_least "keyword same-family scan in README en" 1 "$RM_EN" "same-family"
for f in "$STD" "$METH" "$STA" "$AGENTS"; do
  at_least "keyword 隐式链路三向遍历 in $(basename "$f")" 1 "$f" "隐式链路三向遍历"
done
for f in "$SKILL" "$RM_ZH" "$RM_EN" "$AGENTS" "$PIPE" "$STD" "$METH"; do
  at_least "route state-trigger-audit in $(basename "$f")" 1 "$f" "state-trigger-audit"
done

# ---------- v3.5.0 快照：占位符拒绝 + L3 释放授权 + commit-msg 归因闸门 ----------
for f in "$STD" "$RM_EN" "$RM_ZH"; do
  at_least "keyword release_authorized_by in $(basename "$f")" 1 "$f" "release_authorized_by"
done
for f in "$SKILL" "$RM_EN" "$RM_ZH"; do
  at_least "keyword commit-msg attribution gate in $(basename "$f")" 1 "$f" "commit-msg"
done

# ---------- v3.6.0 快照：一次变更一组文档 + 缺陷文档组三件套 ----------
for f in "$STD" "$RM_EN" "$RM_ZH"; do
  at_least "keyword 一次变更一组文档 in $(basename "$f")" 1 "$f" "一次变更一组文档"
done
for f in "$STD" "$BFLOG" "$SKILL"; do
  at_least "keyword 缺陷文档组 in $(basename "$f")" 1 "$f" "缺陷文档组"
done
TPL="$ROOT/resources/templates"
report "governance-state template declares empty bug_ref" 1 "$(grep_count "$TPL/governance-state.json" '"bug_ref": ""')"
report "agent-gate names missing defect document" 1 "$(grep_count "$TPL/agent-gate.sh" "missing defect document")"
tpl6=0
for t in bug-diagnosis.md bug-impact.md bug-test-plan.md bug-matrix.md bug-config.md bug-tasks.md; do
  [[ -s "$TPL/$t" ]] && tpl6=$(( tpl6 + 1 ))
done
report "bug doc-set templates present (6 files)" 6 "$tpl6"

# ---------- v3.7.0 快照：最低文档集八类映射 + 编码记录 04.5 + 缺陷六件套 ----------
at_least "keyword 最低文档集八类映射 in DEVELOPMENT_STANDARDS" 1 "$STD" "最低文档集八类映射"
at_least "keyword eight-category in README en" 1 "$RM_EN" "eight-category"
at_least "keyword 六件套 in DEVELOPMENT_STANDARDS" 1 "$STD" "六件套"
at_least "keyword 六件套 in SKILL" 1 "$SKILL" "六件套"
at_least "keyword 04.5-coding-record in DEVELOPMENT_STANDARDS" 1 "$STD" "04.5-coding-record"
at_least "keyword 04.5-coding-record in README zh" 1 "$RM_ZH" "04.5-coding-record"
at_least "keyword 04.5-coding-record in README en" 1 "$RM_EN" "04.5-coding-record"
at_least "keyword 04.5-coding-record in SKILL" 1 "$SKILL" "04.5-coding-record"
at_least "keyword 04.5-coding-record in agent-gate" 1 "$TPL/agent-gate.sh" "04.5-coding-record"
at_least "keyword 04.5-coding-record in run-tests" 1 "$ROOT/tests/run-tests.sh" "04.5-coding-record"
at_least "keyword bug-matrix.md in SKILL" 1 "$SKILL" "bug-matrix.md"
at_least "keyword coding-record template in SKILL" 1 "$SKILL" "coding-record.md"
at_least "keyword 06-tasks in agent-gate" 1 "$TPL/agent-gate.sh" "06-tasks"

# ===================== PART A（续） =====================

# ---------- §3 清单唯一性（CHG-005：v3.8.0 起 §3 为唯一权威，§4 只作归档引用） ----------
# 注意：标准全文的 ```markdown fence 数量随结构变化，必须按章节标题锚定，
# 禁止按 fence 序号取（序号法曾取到 §1.2/§2.6.3 两个空清单 → 恒真 IDENTICAL，R-D 轮修正；
# v3.8.0 起 §4 归档节改为"逐字复制 §3"引用式，旧"§3↔§4 标签完全一致"断言会被双清单复活绕过，
# 故反转为三条：§3 提取非空（防恒真）、§3 与 §4 标签集不相等（防重复清单复活）、§4 含引用锚点）。
awk '/^## 3\. 变更执行全流程检查清单/{w=1} w && /^```markdown$/{f=1; w=0; next} f==1{ if(/^```$/){exit} print }' "$STD" | grep -oE '【[^】]+】' | sort > /tmp/audit_s3.$$
awk '/^## 4\. Changelog/{w=1} /^## 5\. /{exit} w{print}' "$STD" | grep -oE '【[^】]+】' | sort > /tmp/audit_s4.$$
n3=$(wc -l < /tmp/audit_s3.$$ | tr -d ' ')
report "section3 checklist extraction non-empty (防恒真空转)" 1 "$([[ "$n3" -gt 0 ]] && echo 1 || echo 0)"
if diff -q /tmp/audit_s3.$$ /tmp/audit_s4.$$ >/dev/null 2>&1; then r=0; else r=1; fi
report "section3 is the sole authority (section4 carries no duplicate checklist)" 1 "$r"
report "section4 archive section references §3 verbatim-copy rule" 1 \
  "$(awk '/^## 4\. Changelog/{w=1} /^## 5\. /{exit} w{print}' "$STD" | grep -cE '逐字复制 §3')"
rm -f /tmp/audit_s3.$$ /tmp/audit_s4.$$

# ---------- 双 README 结构一致性（CHG-005 / P2-6：正文靠手工同步，至少结构须机器互证） ----------
#   ① 二级标题序列一致（EN/ZH 逐条对应）；② "仓库结构"树块逐行一致（文件名与树线同构，
#   语言差异只在注释列）——树块锚定：从 'dev-standards-bootstrap/' 根行到收尾 fence
#   （不能按 fence 序号取：README 还有 bash fence，序号法曾取空 → 防恒真断言拦截）。
tree_block_lines() { # $1 = readme → 树块规范化行数（去注释、去尾空白）
  awk 'f==1{ if(/^```$/){exit} print; next } /^dev-standards-bootstrap\/$/{f=1; print}' "$1" \
    | sed -e 's/#.*$//' -e 's/[[:space:]]*$//' | grep -c .
}
h2_en=$(grep -c '^## ' "$RM_EN")
h2_zh=$(grep -c '^## ' "$RM_ZH")
report "README h2 heading count identical (en vs zh)" "$h2_en" "$h2_zh"
tree_en=$(tree_block_lines "$RM_EN")
tree_zh=$(tree_block_lines "$RM_ZH")
report "README structure-tree line count identical (en vs zh)" "$tree_en" "$tree_zh"
report "README structure-tree extraction non-empty (防恒真空转)" 1 "$([[ "$tree_en" -gt 10 ]] && echo 1 || echo 0)"

# ---------- A7d 阶段验收 A 层命令速查表（CHG-006：命令唯一落点须机器守护） ----------
at_least "stage A-layer command quickref table present" 1 "$STD" '阶段验收 A 层命令速查表'
at_least "quickref carries stage-1 command anchor" 1 "$STD" "grep -c 'REQ-' docs/<feature>/01-spec.md"
at_least "quickref carries stage-6 command anchor" 1 "$STD" 'BUG-\[0-9\]'

# ---------- 编号体系收录（R-C 轮） ----------
declared=$(grep -oE '以下 [0-9]+ 种前缀' "$STD" | grep -oE '[0-9]+')
rows=$(awk '/^### 1.1/,/^### 1.2/' "$STD" | grep -cE '^\| \*\*')
report "1.1 declared prefix count == table rows" "$rows" "$declared"

all10="REQ/DES/TASK/CHG/TC/SC/BUG/CFG/DB/FU"
report "1.2 numbering rule lists all prefixes"      1 "$(grep_count "$STD" "各类编号（${all10}）")"
report "1.2 order checklist row includes SC"        1 "$(grep -cE '^\| SC/BUG/CFG/DB/FU' "$STD")"
report "2.16.4 self-check includes SC"              1 "$(grep_count "$STD" "是否所有编号（${all10}）")"

# ---------- 占位符 vs A 层断言（防恒真统计，R-A 轮） ----------
report "bugfix-log placeholder not matched by ^### BUG-[0-9]" 0 "$(grep -cE '^### BUG-[0-9]' "$BFLOG" 2>/dev/null || true)"

# ---------- 骨架 vs A 层关键词（防空骨架绕过；关键词属 v3.4.0 快照） ----------
report "pipeline 02 skeleton free of A-layer keyword" 0 "$(grep_count "$PIPE" "隐式链路三向遍历")"

# ---------- 00 管线件落点（R-A 轮） ----------
report "2.15 table has 00-intent row"        1 "$(grep_count "$STD" '\`00-intent.md\`（变更管线入口，§2.17）')"
report "2.15 table has 00-governance row"    1 "$(grep_count "$STD" '\`00-governance.json\`（§2.17）')"
report "2.16.5 table has pipeline-entry row" 1 "$(grep_count "$STD" '管线入口（§2.17）')"
report "2.17 governance definition present"  1 "$(grep_count "$STD" '管线治理声明')"
at_least "2.17 dual-root convention present" 1 "$STD" '产物目录双轨约定'
report "mainline starts with 00 files+begin" 1 "$(grep_count "$STD" '先落 00-intent.md / 00-governance.json（§2.17，变更目录）')"

# ---------- bugfix 双登记 9+1 项对齐（R-A 轮；v3.6.0 缺陷文档组 + v3.7.0 矩阵/配置/任务拆分项） ----------
chg_backfill=$(awk '/^#### Bug 修复回填清单/,/^#### [^B]/' "$STD" | grep -cE '^- \[ \]')
report "CHG backfill checklist == 10 items (log 9 + log itself)" 10 "$chg_backfill"
log_line=$(grep -E '^- \[ \] 01-spec' "$BFLOG" | head -1)
log_items=$(printf '%s' "$log_line" | grep -oE '\[ \]' | wc -l | tr -d ' ')
report "log-side backfill checklist == 9 items" 9 "$log_items"

# ---------- 锚点章节存在性（子代理轮） ----------
for h in '^## 0.5 ' '^## 2.6 ' '^## 2.7 ' '^## 2.8 ' '^## 2.9 ' '^## 2.11 ' '^#### 2.17.1' '^## 4. Changelog'; do
  report "standards heading exists: $h" 1 "$(grep -cE "$h" "$STD")"
done

# ---------- README 树 ↔ 磁盘（子代理轮） ----------
for m in $(ls "$ROOT/resources/methodologies" | grep '\.md$'); do
  at_least "README en mentions methodologies/$m" 1 "$RM_EN" "$m"
  at_least "README zh mentions methodologies/$m" 1 "$RM_ZH" "$m"
done

# ---------- README 树 ↔ 磁盘：resources/templates/（CHG-004 / BUG-002） ----------
#   本脚本头部注释早已声称 PART A 含"树↔磁盘"，但原实现**只校验 methodologies/ 的
#   README 提及、未校验 templates/** → 双 README 的"仓库结构"树对称漏列 7 个模板
#   （bug-diagnosis/impact/test-plan/matrix/config/tasks.md + coding-record.md）而长期
#   无人发现。语义：README 树必须列出该目录下全部文件——检查只覆盖一半 = 又一处
#   "检查的覆盖面窄于它声称的语义"（与 BUG-001 同族）。
#   解析要点：ZH README 用中文顿号「、」并列、EN 用「, 」——两种分隔符都要覆盖
#   （首版脚本只切逗号，误判 ZH 漏 3 个 Git Hook 文件；本轮实测踩过，故此处显式处理）。
tree_names() { # $1 = readme → 输出树中 templates/ 段的文件名（去重排序）
  awk '/└── templates\//{f=1;next} f && /^```/{exit} f{
    line=$0
    sub(/#.*$/,"",line)               # 去注释
    gsub(/[、,]/," ",line)            # 归一化分隔符（逐字节替换，对 ASCII 文件名无害）
    sub(/^[^A-Za-z0-9_.]*/,"",line)   # 去缩进与树线前缀
    n=split(line,a," ")
    for(i=1;i<=n;i++) if(a[i] ~ /^[A-Za-z0-9_.-]+$/) print a[i]
  }' "$1" | sort -u
}
tmpl_disk=$(ls "$ROOT/resources/templates" | sort)
for rmf in "$RM_EN" "$RM_ZH"; do
  t_miss=$(comm -23 <(printf '%s\n' "$tmpl_disk") <(tree_names "$rmf") | tr '\n' ' ')
  t_extra=$(comm -13 <(printf '%s\n' "$tmpl_disk") <(tree_names "$rmf") | tr '\n' ' ')
  [[ -z "$t_miss" ]] || echo "audit: $(basename "$rmf") tree missing templates: $t_miss" >&2
  [[ -z "$t_extra" ]] || echo "audit: $(basename "$rmf") tree lists non-existent templates: $t_extra" >&2
  report "README $(basename "$rmf") tree covers all resources/templates" 0 "$(printf '%s' "$t_miss" | grep -c . || true)"
  report "README $(basename "$rmf") tree has no phantom template" 0 "$(printf '%s' "$t_extra" | grep -c . || true)"
done

# ---------- 06.5 / 06-delivery-summary 模板存在性（CHG-004 / BUG-002） ----------
#   §1.1「最低文档集八类」含 06.5-deployment-config.md；06-delivery-summary.md 是
#   §2.5 阶段 9.5 的必含产物（**不在八类内**，落 §1.1 编号主表「遗留项 (Follow-up)」行）。
#   两者此前都无模板、门禁也不校验 → 目标仓库无处可复制、漏项无人拦。
#   本断言保证"有模板可复制"；"门禁必检"由 agent-gate.sh 的 stop 分支承担。
for t in 06.5-deployment-config.md 06-delivery-summary.md; do
  report "template exists and non-empty: $t" 1 "$([[ -s "$ROOT/resources/templates/$t" ]] && echo 1 || echo 0)"
done

# ---------- 阶段 6/8 专项与 §5 拦截（v3.4.0 快照） ----------
report "stage-8 defect-fix special check" 1 "$(grep_count "$STD" '缺陷修复类 CHG 专项')"
at_least "section5 same-family interceptor" 1 "$STD" '同族推演」行 / 同族行空口'

# ---------- METHODOLOGY 分级行（v3.4.0 快照） ----------
report "methodology 3.2 implicit-link row" 1 "$(grep_count "$METH" '隐式链路三向遍历（正向调用点')"
report "methodology 3.6 same-family row"   1 "$(grep_count "$METH" '同族推演（同根因旁路扫描）')"
report "methodology 4 conditional note"    1 "$(grep_count "$METH" '条件命中：涉及状态/触发/事件链路时必须')"

# ---------- 审计脚本自身接线（本轮） ----------
at_least "SKILL.md wires audit script"  1 "$SKILL" "audit-docs-consistency"
at_least "README en tree lists audit"   1 "$RM_EN" "audit-docs-consistency"
at_least "README zh tree lists audit"   1 "$RM_ZH" "audit-docs-consistency"

# ---------- 通用层防复发断言（源自本项目八轮漏检类别，防同类问题在目标仓库复现） ----------

# A1 管线派发骨架集必须覆盖 gate begin 必检集差集（01/00-* 为管线入口件除外）——
#    防"spec 合入后 begin 因缺骨架必失败"复发（v3.4.0 ⑬：03.5 曾缺失）
GATE_REQ_LINE=$(grep -m1 'required_docs=(' "$ROOT/resources/templates/agent-gate.sh")
pipe_missing=0
for f in 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md; do
  printf '%s' "$GATE_REQ_LINE" | grep -q "$f" || { echo "audit: gate required_docs changed, update A1 list" >&2; pipe_missing=$(( pipe_missing + 1 )); continue; }
  grep -q "docs/changes/\$id/$f" "$PIPE" || pipe_missing=$(( pipe_missing + 1 ))
done
report "A1 pipeline scaffolds every gate-required artifact (minus entry files)" 0 "$pipe_missing"

# A2 compliance.sh 与 agent-gate 的"代码扩展名"口径必须一致——
#    防 6-vs-20 种后缀分叉复发（v3.4.0 ⑫：14 种后缀逃过文档检查）
gate_ext=$(grep -E '\\\.\(c\|' "$ROOT/resources/templates/agent-gate.sh" | head -1 | sed -E 's/.*\\\.\(([^)]+)\)\$.*/\1/')
ci_ext=$(grep -E '\\\.\(c\|' "$ROOT/resources/templates/check-standards-compliance.sh" | head -1 | sed -E 's/.*\\\.\(([^)]+)\)\$.*/\1/')
report "A2 code-extension list identical in gate and compliance.sh" "$gate_ext" "$ci_ext"

# A3 README 声称的 golden-case 断言数必须与生成器**同源**（CHG-019：静态调用点计数
# 与运行期实出结构性死锁——同链双调用与循环站点使两口径恒差 3，README 取任一值都有
# 一侧红）。口径唯一权威 = 生成器（运行期实出 `N passed`，红套件拒同步）；本断言只
# 做"声称集合单一一致"与"== 生成器口径"两件事，重算逻辑不在此复制（防第三口径）。
#    防"47→52→55 多处数字漂移"复发（本项目实际发生过）
#
#    CHG-003 收紧取值正则，同时治两个方向的缺陷：
#    ① 漏匹配（危险方向）：旧正则 '[0-9]+ (assertions|项断言|golden-case 断言|Golden-Case 断言)'
#       要求数字后紧跟空格 + 关键词，于是 '107 golden-case assertions'（数字后跟 golden-case）
#       不匹配 → claims 只剩 {118} → A3 误判"单一一致数字"通过。该盲区曾让双 README 同时残留
#       107 与 118、而真值为 125，且这条 FAIL 在 main 上长期无人察觉。
#    ② 假阳性（阻断方向）：若仅放宽为 '[0-9]+[^0-9]{0,20}'，版本号尾数会被卷进来——实测
#       '见 §2.17.4 防恒真断言' 会命中 '4 防恒真断言'。
#    故最终形态：(^|[^0-9A-Za-z.])[0-9]+[^0-9]{0,20}(assertions?|项断言|項斷言|断言)
#       · 前导 '(^|[^0-9A-Za-z.])' 排除"前一个字符是数字、字母或小数点"，避免版本号尾数
#         与**标识符尾数**被当成计数；字母这一档是 v3.21.0 补的——实测
#         'G6 **executed no assertion' 会命中 '6 … assertion'，于是 claims 变成 {268,6}，
#         两个方向同时红（"单一一致数字"与"== 静态调用数"）。`G6`/`T20`/`A22`/`CHG-016`
#         这类标识符在本文档里到处都是，漏掉这一档等于给每个标识符都埋一颗地雷。
#       · 上限 20 覆盖全部已知中英表述（最长 '项 golden-case ' 为 14 字符）并避免跨句误匹配；
#       · 'assertions?' 兼顾单复数。
#    须命中：'107 golden-case assertions' / '118 assertions' / '107 项 golden-case 断言'
#    须不命中：'见 §2.17.4 防恒真断言'（版本号尾数）/ 'G6 executed no assertion'（标识符尾数）
#    已知残余缺口（不阻断，登记 FU-009）：'assertions: 125'（数字在关键词之后）不命中。
claims=$(grep -ohE '(^|[^0-9A-Za-z.])[0-9]+[^0-9]{0,20}(assertions?|项断言|項斷言|断言)' "$RM_EN" "$RM_ZH" | grep -oE '[0-9]+' | sort -u | tr '\n' ',')
GEN="$ROOT/scripts/update-assertion-count.sh"
gen_rc=0
gen_out=$(bash "$GEN" --check 2>&1) || gen_rc=$?
gen_n=$(printf '%s\n' "$gen_out" | sed -nE 's/^assertion claims in sync with run-tests \(([0-9]+)\)$/\1/p')
report "A3 README assertion-count claims are a single consistent number" 1 "$(printf '%s' "$claims" | grep -c '^[0-9]*,$')"
report "A3 claimed assertion count == generator runtime count (CHG-019)" "$gen_n" "${claims%,}"

# A3c 生成器同步校验（CHG-007 / FU-005+009）：README 声称数必须与生成器 --check 一致——
#    手工改数、漏改、或 run-tests 增删用例后未同步，都在这里红。
if [[ -f "$GEN" ]]; then
  report "A3c README assertion claims match generated count (FU-005/009)" 0 "$gen_rc"
else
  report "A3c assertion generator script exists" 1 0
fi

# A4 基线来源不得硬编码（CHG-002）——主线为 master 的仓库曾因写死 origin/main 直接
#    fatal（不可自愈）；更危险的是为绕过报错补 `|| true`，空 diff 被读成"通过"。
#    故：模板不得回退到字面分支名，且必须保留 fail-closed 拒绝路径。
#    运行时行为由 run-tests T13 守护，本段是源层发布前拦截。
CI_SCRIPT="$ROOT/resources/templates/check-standards-compliance.sh"
GOV_WF="$ROOT/resources/templates/github-agent-governance.yml"
report "A4 compliance.sh has no hardcoded origin/* default baseline" 0 "$(grep -c -- ':-origin/' "$CI_SCRIPT" || true)"
report "A4 compliance.sh resolves its baseline dynamically" 1 "$(grep -c '^resolve_base_ref() {' "$CI_SCRIPT" || true)"
report "A4 compliance.sh fails closed on an unknown baseline" 1 "$(grep -c '无法确定基线分支' "$CI_SCRIPT" || true)"
report "A4 governance workflow has no literal branch fallback" 0 "$(grep -cF "|| 'main'" "$GOV_WF" || true)"

# A5 门禁"交付必检文档"必须随 bootstrap --core 下发模板（CHG-004 / FU-012 防复发）——
#    根因：门禁要求某文档存在、而安装清单不提供模板 → 目标仓库无从落笔，只能靠人记；
#    `06.5` 与 `06-delivery-summary` 长期处于此状态（前者属八类、后者属阶段 9.5 必含，
#    两类交付必检文档都无模板），是 CHG-003 差点漏交 06.5 的制度性原因。
#    取值方式刻意用**动态派生**而非静态清单：从 agent-gate.sh 的 check_delivery_doc
#    调用点提取文件名，再**真跑一次 --core 到临时目录**核对落点。
#    为什么不 grep bootstrap.sh 的文本：首版就是这么写的，结果 install_file 写成
#    `for t in ...; do install_file ...; done` 循环即漏判（假 FAIL），而等价改写又会
#    假 PASS——**用文本形态代替行为，本身就是本族根因**。故此处验证产物，不验证写法。
deliver_docs=$(grep -oE 'check_delivery_doc "\$d" [^ ]+' "$ROOT/resources/templates/agent-gate.sh" | awk '{print $3}' | sort -u)
n_deliver=$(printf '%s\n' $deliver_docs | grep -c . || true)
report "A5 gate delivery-doc extraction non-empty (防恒真空转)" 1 "$([[ "$n_deliver" -ge 2 ]] && echo 1 || echo 0)"
A5_TMP=$(mktemp -d 2>/dev/null) || A5_TMP=""
bs_missing=0
if [[ -n "$A5_TMP" ]]; then
  bash "$ROOT/scripts/bootstrap.sh" --core "$A5_TMP" >/dev/null 2>&1 || true
  for t in $deliver_docs; do
    [[ -s "$A5_TMP/docs/$t" ]] \
      || { echo "audit: bootstrap --core does not ship a template for gate-required doc: $t" >&2; bs_missing=$(( bs_missing + 1 )); }
  done
  rm -rf "$A5_TMP"
else
  bs_missing=1
  echo "audit: mktemp failed, cannot verify bootstrap --core delivery templates" >&2
fi
report "A5 bootstrap --core ships a template for every gate delivery doc" 0 "$bs_missing"

# A5b 交付模板必须自带 TEMPLATE-MARKER 哨兵——门禁靠它区分"已填写的交付物"与
#     "直接复制过来的空模板"。若模板不带哨兵，门禁就只剩"文件非空"这一条弱校验，
#     等于"复制模板即算完成"重新可行。与 run-tests 的分工：模板侧由本断言守护，
#     门禁的哨兵识别行为由 run-tests T5 守护（内联哨兵，与仓库布局无关）。
for t in $deliver_docs; do
  at_least "A5b delivery template carries TEMPLATE-MARKER sentinel: $t" 1 \
    "$ROOT/resources/templates/$t" 'TEMPLATE-MARKER'
done

# ── PART A6: 本仓库自身治理产物审计（FU-013 闭环）──────────────────────────
# 本仓库 dogfood 的治理产物此前无任何机器审计（FU-013）。以下断言校验本仓库
# 自身的 docs/bugfix-log.md 双登记、docs/changes/CHG-*/ 编号连续性、
# docs/bugs/BUG-*/ 六件套齐备——"规范仓库自己也要受规范审计"。
REPO_BFLOG="$ROOT/docs/bugfix-log.md"
REPO_CHANGES="$ROOT/docs/changes"
REPO_BUGS="$ROOT/docs/bugs"

# A6a bugfix-log.md 存在且含真实 BUG 条目（非占位模板）
if [[ -f "$REPO_BFLOG" ]]; then
  bug_count=$(grep -cE '^### BUG-[0-9]' "$REPO_BFLOG" || true)
  report "A6a repo bugfix-log has real BUG entries (not placeholder)" 1 \
    "$([[ "$bug_count" -ge 2 ]] && echo 1 || echo 0)"
else
  report "A6a repo bugfix-log exists" 1 0
fi

# A6b docs/changes/ 下每个 CHG 目录至少含 00-intent.md（门禁 1 最低要求）
chg_dirs=$(ls -d "$REPO_CHANGES"/CHG-* 2>/dev/null || true)
chg_missing_intent=0
if [[ -n "$chg_dirs" ]]; then
  for d in $chg_dirs; do
    [[ -f "$d/00-intent.md" ]] || { echo "audit: $d missing 00-intent.md" >&2; chg_missing_intent=$(( chg_missing_intent + 1 )); }
  done
else
  chg_missing_intent=1
fi
report "A6b every CHG dir has 00-intent.md (gate 1 minimum)" 0 "$chg_missing_intent"

# A6c docs/changes/ 下 CHG 编号连续递增（CHG-001, CHG-002, ... 无跳号）
# BUG-004 修复：编号去前缀后保留前导零（008），bash 算术按**八进制**解析 →
# "value too great for base"；实测（bash 3.2）该错误会**中断整个 if 复合块**，
# 而不只是让条件为假 → 下面的 report 从未执行，断言既不会红也不会绿，连断言
# 总数都不计它（A10 基线按缺失它的口径固化，缺陷完全不可见）。
# 修法：复用本仓 shipped 模板 audit-docs-consistency.sh check_seq() 的既有范式——
# 在取值阶段用 awk '%d' 做十进制归一（非数字归一为 0，产生 gap 报错而非静默跳过）。
chg_nums=$(basename -s '' $(ls -d "$REPO_CHANGES"/CHG-* 2>/dev/null) 2>/dev/null \
  | sed 's/CHG-//' | awk '{printf "%d\n", $1}' | sort -n)
a6c_ran=0
if [[ -n "$chg_nums" ]]; then
  chg_prev=0
  chg_gap=0
  for n in $chg_nums; do
    if [[ "$n" -ne $(( chg_prev + 1 )) ]]; then
      echo "audit: CHG numbering gap: expected $(( chg_prev + 1 )), got $n" >&2
      chg_gap=1
    fi
    chg_prev=$n
  done
  report "A6c CHG numbering continuous (no gaps)" 0 "$chg_gap"
  a6c_ran=1
else
  report "A6c CHG numbering continuous (no gaps)" 1 0
  a6c_ran=1
fi
# BUG-004 放大器守卫：A10 基线只记**断言总数**、不记**断言名** → 任一断言被"整块
# 跳过"时总数与基线依然一致（基线本就是按缺失它的口径固化的），缺陷完全不可见。
# 本断言专防"复合块被算术错误中断导致 report 未执行"这一失效模式复发。
report "A6c actually executed (BUG-004 guard)" 1 "$a6c_ran"

# A6d docs/bugs/ 下每个 BUG 目录含六件套（01~06）
bug_dirs=$(ls -d "$REPO_BUGS"/BUG-* 2>/dev/null || true)
bug_missing_files=0
if [[ -n "$bug_dirs" ]]; then
  for d in $bug_dirs; do
    for f in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
      [[ -f "$d/$f" ]] || { echo "audit: $d missing $f" >&2; bug_missing_files=$(( bug_missing_files + 1 )); }
    done
  done
else
  # No bug dirs is valid (repo may not have bugs yet)
  bug_missing_files=0
fi
report "A6d every BUG dir has six-file set (v3.7.0)" 0 "$bug_missing_files"

# A6e 已闭合变更目录完整性（BUG-003 防复发）：目录含 09-changelog.md（闭合标志）则
# 必须同时含其余编号产物——防"闭合变更被部分覆盖/破坏"再次静默发生（BUG-003 实际
# 摧毁了 9 件产物而仅凭 A6b 检查 00-intent 无法发现）。
closed_missing=0
for d in $chg_dirs; do
  [[ -f "$d/09-changelog.md" ]] || continue
  for f in 00-intent.md 00-governance.json 01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 04.5-coding-record.md 05-test-results.md 07-review-report.md; do
    [[ -f "$d/$f" ]] || { echo "audit: closed change $d missing $f" >&2; closed_missing=$(( closed_missing + 1 )); }
  done
done
report "A6e closed change dirs are complete (BUG-003 guard)" 0 "$closed_missing"

# A24 quick-start 承诺面必须已入库（CHG-020）：README 宣传的安装命令读取的是**提交里**
# 的文件——文件只在暂存区/工作树时，远端 raw 404（实测缺陷：install.sh 未提交而已提交的
# README 已在宣传 curl 一条命令）。`git ls-files` 匹配=tracked（CI 干净 checkout 下即
# committed）；与"树↔磁盘"断言互补：那条管"README 树=磁盘实际"，本条管"README 命令=提交内容"。
a24_missing=0
for a24f in scripts/install.sh CHANGELOG.md MAINTAINER.md resources/templates/stamp-provenance.sh .claude-plugin/marketplace.json .claude-plugin/plugin.json; do
  git -C "$ROOT" ls-files --error-unmatch "$a24f" >/dev/null 2>&1 \
    || { echo "audit: quick-start surface not committed (untracked): $a24f" >&2; a24_missing=$(( a24_missing + 1 )); }
done
report "A24 quick-start surface is git-tracked (CHG-020)" 0 "$a24_missing"

# ── PART A8: 门禁硬化形态锚点（CHG-007：FU-008/014/015/019 防复发）──────────────────
#   门禁行为已由 run-tests golden case 守护；此处锁"实现形态"，防行为被静默回退成弱检查
#   （BUG-001 同族：检查模式弱于其声称语义）。取值用 grep -F 固定串，防正则元字符歧义。
GATE_TPL="$ROOT/resources/templates/agent-gate.sh"
# v3.18.0：FU-015 的闭环判定从"changelog 文件存在"细化为两种形态——独立目录仍看文件，
# 批次目录看**本变更自己的 `## <id>` 小节**（同批共享 changelog，"文件存在"会把后加入的
# 变更一起判为已关闭）。故此处由"恰好 1 处"改为"两种形态各至少 1 处"：恒等断言会把
# 正确的细化判成回退，下界断言才是这条不变量真正想守的东西。
at_least "A8 begin rejects closed change re-entry (FU-015)" 2 "$GATE_TPL" 'already closed'
report "A8 RTVM glob covers nested change-dir matrices (FU-019)" 1 "$(grep -cF '"$change_root"/*/01.5-rtvm-matrix.md' "$GATE_TPL")"
# 说明：固定串在 gate 中天然多处命中（检查点 + 报文），故下两条用 ≥1 下界语义而非恒等
ga_n=$(grep -cF 'REQ-[0-9]+' "$GATE_TPL")
report "A8 numbering checks are digit-anchored (FU-008)" 1 "$([[ "$ga_n" -ge 1 ]] && echo 1 || echo 0)"
ga_s=$(grep -cF '业务影响)' "$GATE_TPL")
report "A8 stage-2 impact checks are structure-anchored (FU-008)" 1 "$([[ "$ga_s" -ge 1 ]] && echo 1 || echo 0)"
report "A8 delivery declarations are line-anchored (FU-014)" 1 "$(grep -cF '[#>-][[:space:]]*)*未命中' "$GATE_TPL")"

# A9 规范条款存在性锚点（CHG-008 / FU-016）：防条款被静默移除
at_least "A9 change-id occupancy-verification clause present (FU-016)" 1 "$STD" '取号前必须核实占用'

# A11 规范体量上界（CHG-010 引入 / CHG-011、v3.21.2、v3.25.0 重校准）：治理内容演进时上界随之重校准
# （新条款须有 CHANGELOG 条目对应），硬上界只防"无序回弹"。当前上界 144KB。
# v3.29.0（CHG-028）重校准 132KB → 140KB 的依据：§2.1 九专家行 + §2.2 分阶段专家评审矩阵为
# 新增规范性内容（两轮措辞压缩后仍超 136KB 约 1.6KB），按 KiB 步进 +4KB；STANDARDS_CHANGELOG v3.29.0 行即依据。
# v3.25.0（CHG-025）重校准 128KB → 132KB 的依据（按既有三个条件）：
#   ① **先压缩**：v3.24.0 + v3.25.0 两轮新增条款均经措辞压缩（§2.9.6/§2.5 三轮收字），
#      v3.24.0 收口时余量仅剩 3 字节——上界事实上已失效（同 v3.17.0 的 53 字节、
#      v3.21.2 的 193 字节同型）；v3.25.0 新增为执行侧纪律（写侧并行批量/定向验证/
#      产物最小表达形态），非文字膨胀；
#   ② **有 CHANGELOG 条目对应**：见 `resources/STANDARDS_CHANGELOG.md` 的 v3.25.0 行；
#   ③ 上界按 KiB 步进（+4KB）重设，余量约 3.3KB——**不是**按当前体量贴合。
# v3.21.2（CHG-017 / REQ-089）重校准 124KB → 128KB 的依据（按 §5.1 的两个条件）：
#   ① **先压缩**：本轮新增文字先做了一轮浓缩（删除规范正文里的变更日志式括注、
#      把派生资产的判定口径收成一句），但 v3.21.1 + v3.21.2 两轮的对齐修正
#      （AGENTS 门禁节清单、L3 覆盖率门槛、矩阵落点句澄清等）已把 124KB 上界的
#      余量吃到 **193 字节**——上界事实上再次失效，与 v3.16.0 的 53 字节同型；
#   ② **有 CHANGELOG 条目对应**：见 `resources/STANDARDS_CHANGELOG.md` 的 v3.21.2 行；
#   ③ 上界按 KiB 步进（+4KB）重设，余量 **4,289 字节**——**不是**按当前体量贴合，
#      否则下一次任何实质新增又会立刻撞墙。
# v3.17.0 重校准 120KB → 124KB 的依据（不只是"装不下了"）：
#   ① v3.16.0 的未提交改动已把 120KB 上界的余量吃到 **53 字节**——上界事实上已失效，
#      留着它只会让下一位维护者以为还有空间；
#   ② 本版新增的是**治理要求**（文件溯源 + 不追溯既往），不是文字膨胀；且已先做压缩：
#      合并三条重复条款为一条、并把机制细节下沉到 stamp-provenance.sh 头部注释，
#      净增 1,035 字节（122,827 → 123,862）；
#   ③ 上界按 KiB 步进（+4KB）重设，余量 3,114 字节——**不是**按当前体量贴合。
# v3.35.0 重校准 144KB → 156KB 的依据（不只是"装不下了"）：
#   ① v3.31.0 的 144KB 上界余量已被 §1.3 项目级总册（CHG-035，12 册定义 + 门禁/DoD/
#      主线/落点/回填清单 + 缺陷按天入批 + bug 两条款）吃到负值（153,499 字节）；
#   ② 有 CHANGELOG 条目对应：resources/STANDARDS_CHANGELOG.md 的 v3.35.0 行；
#   ③ 上界按 KiB 步进（+12KB，跨 4KB 档取整）重设为 156KB，余量约 6.2KB——
#      不是按当前体量贴合。
std_bytes=$(wc -c < "$STD" | tr -d ' ')
report "A11 standards body size <= 156KB (FU-017, recalibrated v3.35.0)" 1 "$([[ "$std_bytes" -le 159744 ]] && echo 1 || echo 0)"
at_least "A11 layered reading map present (FU-018)" 1 "$STD" '分层阅读路由'

# A12 Bug 诊断增强锚点（CHG-011 / REQ-057~058，依据 arXiv:2602.02475）
at_least "A12 root-cause classification present (REQ-057)" 1 "$STD" '根因分类'
at_least "A12 change dynamic constraints present (REQ-058)" 1 "$STD" '变更动态约束'

# A13 安装器自动接线锚点（CHG-012）
at_least "A13 bootstrap auto-wires hooksPath (CHG-012)" 1 "$ROOT/scripts/bootstrap.sh" 'auto-wired   git config core.hooksPath'
at_least "A13 gate reads yml verification fallback (CHG-012)" 1 "$GATE_TPL" 'agent-governance.yml'

# A14 升级模式锚点（CHG-013）
at_least "A14 bootstrap upgrade mode present (CHG-013)" 1 "$ROOT/scripts/bootstrap.sh" '--upgrade'

# A15 全面升级自更新锚点（CHG-014）
at_least "A15 bootstrap self-update present (CHG-014)" 1 "$ROOT/scripts/bootstrap.sh" 'self-update skill repo'

# A16 失败模式与反篡改锚点（CHG-015）
at_least "A16 gate anti-tamper guard present (CHG-015)" 1 "$GATE_TPL" 'anti-tamper'
at_least "A16 upgrade blocks on dirty target (CHG-015)" 1 "$ROOT/scripts/bootstrap.sh" 'uncommitted changes — commit first, or pass --force'     

# A17 路径根可配置锚点（v3.15.0）——防两个反向回退：
#   ① 参数化回退：又变回硬编码（目标仓库换根后门禁按默认根找文件 → 静默错位）；
#   ② 过度参数化：把 AGENTS.md / 12 件产物名 / 六件套名也做成可配 →
#      跨仓逐文件比对与"装一次迁移任意仓库"解体。
#   形态锚点（grep -c）而非行为断言：行为由 run-tests T14 在真仓库里端到端验证。
GOV_YML_TPL="$ROOT/resources/templates/agent-governance.yml"
AUDIT_TPL="$ROOT/resources/templates/audit-docs-consistency.sh"
CI_TPL="$ROOT/resources/templates/check-standards-compliance.sh"
# 计数型断言统一归一到 0/1（本脚本的 at_least 是 4 参形态：name min file pattern，
# 计数型必须走 report + 归一，不能直接喂计数）
a17_at_least_1() { [[ "${1:-0}" -ge 1 ]] && echo 1 || echo 0; }
report "A17 gate resolves path roots from config" 1 "$(a17_at_least_1 "$(grep -c 'cfg_path() {' "$GATE_TPL" || true)")"
report "A17 gate path defaults are the historical values" 1 "$(a17_at_least_1 "$(grep -c 'cfg_path docs docs' "$GATE_TPL" || true)")"
report "A17 audit script resolves the docs root from config" 1 "$(a17_at_least_1 "$(grep -c 'cfg_path docs docs' "$AUDIT_TPL" || true)")"
report "A17 compliance script resolves the docs root from config" 1 "$(a17_at_least_1 "$(grep -c 'cfg_path docs docs' "$CI_TPL" || true)")"
report "A17 installer exposes --docs-dir" 1 "$(a17_at_least_1 "$(grep -c -- '--docs-dir' "$ROOT/scripts/bootstrap.sh" || true)")"
report "A17 installer persists non-default roots into the config" 1 "$(a17_at_least_1 "$(grep -c 'rewrite_yml_key' "$ROOT/scripts/bootstrap.sh" || true)")"
report "A17 live-skip keys are logical, not literal paths (D6)" 1 "$(a17_at_least_1 "$(grep -c 'install_file bugfix-log ' "$ROOT/scripts/bootstrap.sh" || true)")"
report "A17 shipped config declares the four configurable roots" 4 "$(grep -cE '^  (docs|scripts|tests|githooks):' "$GOV_YML_TPL" || true)"
report "A17 .github is NOT configurable (platform-fixed location)" 0 "$(grep -cE '^  github:' "$GOV_YML_TPL" || true)"
report "A17 contract names stay out of the configurable block" 0 "$(grep -cE '^  (AGENTS|CLAUDE|agent-gate|00-intent|01-diagnosis)' "$GOV_YML_TPL" || true)"
report "A17 installer substitutes in-template path references" 1 "$(a17_at_least_1 "$(grep -c 'transform_src' "$ROOT/scripts/bootstrap.sh" || true)")"
at_least "A17 standards documents the configurable roots" 1 "$STD" '路径根可配置'
at_least "A17 standards documents the non-configurable set" 1 "$STD" '不可配置项'

# A18 Agent 自进化契约 + 自更新/版本自查锚点（v3.16.0）——防三类反向回退：
#   ① 自更新又变回"静默跳过"（D1 回归：非 git 克隆时用户以为已升级）；
#   ② 升级又去覆盖显式层选择（D4 回归）或派生资产（自进化契约失效）；
#   ③ 派生标记解析退回整文件 grep（SKILL.md 正文的示例代码块会被误判为真实
#      声明——本轮实测踩过：源仓把自己报成了派生 Skill，且写入守卫会误拒
#      向本仓自身的合法安装）。
BOOT="$ROOT/scripts/bootstrap.sh"
report "A18 installer exposes a read-only --check mode" 1 "$(a17_at_least_1 "$(grep -c 'check_mode=true' "$BOOT" || true)")"
report "A18 installer exposes --self-update" 1 "$(a17_at_least_1 "$(grep -c 'self_update=true' "$BOOT" || true)")"
report "A18 installer exposes --derived-report" 1 "$(a17_at_least_1 "$(grep -c 'derived_report=true' "$BOOT" || true)")"
report "A18 upgrade preserves an explicit layer selection (D4)" 1 "$(a17_at_least_1 "$(grep -c 'layers_explicit' "$BOOT" || true)")"
report "A18 derived markers are parsed from frontmatter only" 1 "$(a17_at_least_1 "$(grep -c 'frontmatter() {' "$BOOT" || true)")"
report "A18 installer refuses to install into a derived skill" 1 "$(a17_at_least_1 "$(grep -c 'refusing to install into a derived skill directory' "$BOOT" || true)")"
report "A18 every write path skips derived dirs" 1 "$(a17_at_least_1 "$(grep -c 'derived (skip)' "$BOOT" || true)")"
report "A18 upgrade refuses to clobber local changelog rows (D5)" 1 "$(a17_at_least_1 "$(grep -c 'divergence_guard' "$BOOT" || true)")"
report "A18 installer pins path roots into the shipped config (idempotency)" 1 "$(a17_at_least_1 "$(grep -c 'DOCS_DIR}/changes' "$BOOT" || true)")"
at_least "A18 standards documents the changelog ownership" 1 "$STD" '规范升级日志的归属'
at_least "A18 standards documents the self-evolution contract" 1 "$STD" 'Agent 自进化与派生资产'
at_least "A18 SKILL.md declares the derived_from contract" 1 "$SKILL" 'derived_from'
report "A18 changelog template declares skill ownership" 1 "$(a17_at_least_1 "$(grep -c '归 Skill 所有' "$ROOT/resources/STANDARDS_CHANGELOG.md" || true)")"
report "A18 MAINTAINER.md exists (maintainer notes live outside the payload)" 1 "$([[ -s "$ROOT/MAINTAINER.md" ]] && echo 1 || echo 0)"
report "A18 MAINTAINER.md is NOT in the installer copy list" 0 "$(grep -c 'MAINTAINER.md' "$BOOT" || true)"

# A19 文件溯源锚点（v3.17.0）——防五类反向回退：
#   ① 溯源脚本从 payload 消失或未进 guard 层 → 门禁要求它，目标仓库却装不到，
#      每个变更都会卡在"run stamp-provenance.sh"却无脚本可跑（死锁）；
#   ② 门禁不再校验溯源 → 要求形同虚设，手写块畅通；
#   ③ 校验退回"只看块存在" → 占位块与手写块放行（本轮实测的反例形态）；
#   ④ 隐私开关失效 → email 恒明文，`include_email: false` 无声无效；
#   ⑤ 幂等性回退 → 重复运行叠加多个块（门禁按首块校验，叠加即误导）。
# 形态锚点而非行为断言：行为由 run-tests T16 在真仓库里端到端验证（26 断言）。
STAMP_TPL="$ROOT/resources/templates/stamp-provenance.sh"
CR_TPL="$ROOT/resources/templates/coding-record.md"
report "A19 provenance stamper ships in the payload" 1 "$([[ -s "$STAMP_TPL" ]] && echo 1 || echo 0)"
report "A19 installer lands the stamper in the guard layer" 1 "$(a17_at_least_1 "$(grep -c 'install_file - "\$SCRIPTS_DIR/stamp-provenance.sh"' "$BOOT" || true)")"
report "A19 installer substitutes the stamper path in templates" 1 "$(a17_at_least_1 "$(grep -c 'scripts/stamp-provenance' "$BOOT" || true)")"
# §2 联动表：改复制清单必须同步 --help 文本（--help 是文件清单的唯一权威源）
report "A19 installer --help lists the stamper in the guard layer" 1 "$(a17_at_least_1 "$(grep -c 'stamp-provenance.sh (文件溯源盖章' "$BOOT" || true)")"
report "A19 gate extracts the provenance block" 1 "$(a17_at_least_1 "$(grep -c 'provenance_block() {' "$GATE_TPL" || true)")"
# v3.26.0 (CHG-026): provenance scope widened — the gate loops over every *.md
# artifact (skipping 00-governance.json) instead of pinning 04.5 only. Anchor on
# the loop shape: skip-guard + loop call must both be present (防单点回潮).
report "A19 gate validates every artifact's provenance (CHG-026)" 1 "$([[ $(grep -c 'validate_provenance "\$pf"' "$GATE_TPL" || true) -ge 1 && $(grep -c '"00-governance.json"' "$GATE_TPL" || true) -ge 1 ]] && echo 1 || echo 0)"
report "A19 gate rejects a missing block" 1 "$(a17_at_least_1 "$(grep -c 'carries no provenance block' "$GATE_TPL" || true)")"
report "A19 gate rejects a placeholder block" 1 "$(a17_at_least_1 "$(grep -c 'provenance block still holds a placeholder' "$GATE_TPL" || true)")"
report "A19 gate requires the script as producer" 1 "$(a17_at_least_1 "$(grep -c 'was not produced by scripts/stamp-provenance.sh' "$GATE_TPL" || true)")"
report "A19 gate checks the ISO shape of generated_at" 1 "$(a17_at_least_1 "$(grep -c 'is not an ISO-8601 date' "$GATE_TPL" || true)")"
report "A19 gate requires the four mandatory fields" 1 "$(a17_at_least_1 "$(grep -c 'for k in author email generated_at generated_by' "$GATE_TPL" || true)")"
report "A19 stamper honours the privacy switch" 1 "$(a17_at_least_1 "$(grep -c 'include_email' "$STAMP_TPL" || true)")"
report "A19 stamper redacts the email when asked" 1 "$(a17_at_least_1 "$(grep -c '<redacted>' "$STAMP_TPL" || true)")"
report "A19 privacy switch is env-overridable (CLI > env > yml)" 1 "$(a17_at_least_1 "$(grep -c 'AGENT_GUARD_PROVENANCE_EMAIL' "$STAMP_TPL" || true)")"
report "A19 stamper replaces the block wholesale (idempotent)" 1 "$(a17_at_least_1 "$(grep -c '去掉已有块' "$STAMP_TPL" || true)")"
report "A19 stamper never fabricates: unknown fallbacks" 1 "$(a17_at_least_1 "$(grep -c 'unknown' "$STAMP_TPL" || true)")"
# 门禁的报错文案是"run scripts/stamp-provenance.sh <CHG-id>"——那么该命令在
# 编码记录尚未落盘时**必须**给出可执行的下一步，而不是 cryptic 的 "nothing stamped"；
# 且**不得**自动建空骨架（门禁对 04.5 只查"存在且非空"，自动建壳即放行空交付）。
report "A19 stamper gives an actionable next step when the record is absent" 1 "$(a17_at_least_1 "$(grep -c 'write the coding record first' "$STAMP_TPL" || true)")"
# v3.17.0 实测踩过：新增的治理脚本若不在 is_code_path() 的治理工具白名单里，
# 它以 .sh 结尾 → 被判为产品代码 → 新仓库装完治理包**第一次 commit 即死锁**。
# 故"新增治理脚本"必须同步进白名单；本断言把这条约束钉在源层。
report "A19 gate treats the stamper as a governance tool (no install deadlock)" 1 "$(a17_at_least_1 "$(grep -c 'scripts_re}/stamp-provenance' "$GATE_TPL" || true)")"
report "A19 shipped config declares the provenance section" 1 "$(a17_at_least_1 "$(grep -c '^provenance:' "$GOV_YML_TPL" || true)")"
report "A19 shipped config defaults include_email to true" 1 "$(a17_at_least_1 "$(grep -c '^  include_email: true' "$GOV_YML_TPL" || true)")"
report "A19 coding-record template carries the placeholder block" 1 "$(a17_at_least_1 "$(grep -c '^<!-- provenance' "$CR_TPL" || true)")"
report "A19 coding-record template placeholder is stamped PENDING" 1 "$(a17_at_least_1 "$(grep -c '^author: PENDING' "$CR_TPL" || true)")"
at_least "A19 standards documents the provenance requirement" 1 "$STD" '文件溯源'
at_least "A19 SKILL.md tells the agent to stamp provenance" 1 "$SKILL" 'stamp-provenance'
# 反向断言（v3.22.0 语义修正）：溯源块只允许出现在**活跃变更**或**已闭合变更**
# （含 09-changelog.md）——交付时盖章是 §1.1 的**强制动作**，原断言"历史目录一律
# 不得盖章"与它直接矛盾（自锁：本仓 17 个变更目录 0 盖章，一盖即红，溯源条款在
# 源仓从未走通过）。修正后仍拦住真正的伪造形态：对**无关的开放目录**随手盖章
# （那才是"把 generated_at 伪造成今天"的入口）；已闭合目录的块是交付时的合法
# 产物（幂等重盖本就无法与首次区分——门禁本就只校验活跃变更，此处不假装更强）。
# 活跃变更从 .git/agent-governance/active-change 读（gate begin 维护；无 gate 环境
# 退化为"已闭合即可"）。
active_id=""
if [[ -s "$ROOT/.git/agent-governance/active-change" ]]; then
  active_id=$(tr -d '[:space:]' < "$ROOT/.git/agent-governance/active-change")
fi
retro_stamped=0
for d in "$ROOT/docs/changes"/*/; do
  [[ -d "$d" ]] || continue
  dname=$(basename "$d")
  # 已闭合的目录级代理：存在 09-changelog.md。批次的"半闭合"（部分成员已写小节）
  # 由门禁的逐成员锚点语义兜底（A20），此处采用目录级代理并如实声明——共享产物的
  # 盖章属于整批交付动作，按成员拆分反而会把合法盖章误判为回填。
  [[ -f "$d/09-changelog.md" ]] && continue
  [[ "$dname" == "$active_id" ]] && continue
  for f in "$d"*.md; do
    [[ -f "$f" ]] || continue
    grep -q '^<!-- provenance$' "$f" 2>/dev/null || continue
    echo "audit: provenance block on a non-active, non-closed change artifact: ${f#$ROOT/}" >&2
    retro_stamped=$(( retro_stamped + 1 ))
  done
done
report "A19 stamps appear only on the active or closed changes (v3.22.0 semantics)" 0 "$retro_stamped"

# A20 变更批次锚点（v3.18.0）——防五类反向回退：
#   ① 批次解析从门禁消失 → 批次目录里的变更被判"缺产物"，同天合并直接不可用；
#   ② 治理记录退回"取文件里第一个 risk_level" → 批次里读到**兄弟变更的风险与
#      责任人**（最危险的一种：错的风险等级会放行 L2/L3）；
#   ③ 批次失去 L0/L1 上限 → 批次变成绕过角色独立性的暗道；
#   ④ 闭环判定退回"changelog 文件存在" → 同批兄弟的 changelog 把后加入的变更
#      一起判为已关闭（假阳性），或反之永不关闭；
#   ⑤ 审计与门禁对"锚点"的定义分叉 → 审计绿而门禁红（或反过来），最难查。
# 行为由 run-tests T18 在真仓库里端到端验证；此处钉形态，防静默删除。
report "A20 gate resolves batch directories" 1 "$(a17_at_least_1 "$(grep -c 'change_dir() {' "$GATE_TPL" || true)")"
report "A20 gate scans BATCH-* directories" 1 "$(a17_at_least_1 "$(grep -c '\$change_root\"/BATCH-\*/' "$GATE_TPL" || true)")"
report "A20 gate honours AGENT_GUARD_CHANGE_DIR" 1 "$(a17_at_least_1 "$(grep -c 'AGENT_GUARD_CHANGE_DIR' "$GATE_TPL" || true)")"
report "A20 gate recognises a batch directory by name" 1 "$(a17_at_least_1 "$(grep -c 'is_batch_dir() {' "$GATE_TPL" || true)")"
report "A20 gate has ONE definition of a section anchor" 1 "$(a17_at_least_1 "$(grep -c 'anchor_re() {' "$GATE_TPL" || true)")"
report "A20 gate extracts anchors with a single sed shape" 1 "$(a17_at_least_1 "$(grep -c 'anchors_in_file() {' "$GATE_TPL" || true)")"
report "A20 gate maps a directory to every change it carries" 1 "$(a17_at_least_1 "$(grep -c 'change_ids_in_dir() {' "$GATE_TPL" || true)")"
report "A20 governance records are scoped per change (one record per change id)" 1 "$(a17_at_least_1 "$(grep -c 'gov_record() {' "$GATE_TPL" || true)")"
report "A20 governance state is scoped to this change's own record" 1 "$(a17_at_least_1 "$(grep -c 'rec=\$(gov_record "\$file" "\$id")' "$GATE_TPL" || true)")"
report "A20 batches are L0/L1 only (refused on the record, not on the path)" 1 "$(a17_at_least_1 "$(grep -c 'batches are L0/L1 only' "$GATE_TPL" || true)")"
report "A20 batch closure is this change's own anchor, not the shared file" 1 "$(a17_at_least_1 "$(grep -c "carries a '## \$id' section" "$GATE_TPL" || true)")"
report "A20 metrics emits one row per change, not per directory" 1 "$(a17_at_least_1 "$(grep -c 'change_ids_in_dir "\${dir%/}"' "$GATE_TPL" || true)")"
report "A20 diff attribution reads a batch file's governance roster" 1 "$(a17_at_least_1 "$(grep -c 'id_list=\$(gov_ids "\$(dirname "\$f")/00-governance.json")' "$GATE_TPL" || true)")"
report "A20 stamper resolves the batch directory too" 1 "$(a17_at_least_1 "$(grep -c 'resolve_dir() {' "$STAMP_TPL" || true)")"
report "A20 stamper attests the batch and lists its members" 1 "$(a17_at_least_1 "$(grep -c 'batch_changes:' "$STAMP_TPL" || true)")"
# 批次共享一个编码记录 → 溯源块的 risk 行不该因"这次是哪个成员盖的"而变，
# 否则兄弟重盖会静默改掉风险行。取批次最高值：稳定且保守。
report "A20 batch provenance risk is member-independent (max of the batch)" 1 "$(a17_at_least_1 "$(grep -c 'batch_changes" && -f' "$STAMP_TPL" || true)")"
report "A20 template audit grew a G7 batch group" 1 "$(a17_at_least_1 "$(grep -c 'G7 变更批次自洽' "$AUDIT_TPL" || true)")"
# v3.23.0（CHG-023/REQ-114）：--only-fail 模式锚点——防静默回退（flag 消失 = 空转声明豁免与瘦身能力同失）
report "A20 template audit offers --only-fail with skip-line exemption" 1 "$(a17_at_least_1 "$(grep -c 'only-fail' "$AUDIT_TPL" || true)")"
report "A20 G7 checks every declared change has an entry section" 1 "$(a17_at_least_1 "$(grep -c 'every batch change has a section in the batch 00-intent.md' "$AUDIT_TPL" || true)")"
report "A20 G7 checks records are a subset of the anchors" 1 "$(a17_at_least_1 "$(grep -c 'every batch governance record has an anchor' "$AUDIT_TPL" || true)")"
report "A20 G7 re-checks the L0/L1 ceiling" 1 "$(a17_at_least_1 "$(grep -c 'batch risk levels are L0/L1 only' "$AUDIT_TPL" || true)")"
report "A20 G7 checks change ids are unique across batches" 1 "$(a17_at_least_1 "$(grep -c 'change ids unique across batches' "$AUDIT_TPL" || true)")"
# v3.19.0：批次变更集合必须**正向读权威名单**（00-governance.json 的 change_id），
# 不得反向从 `## <标题>` 推断——`## <标题>` 分不清变更小节与结构小节，而规范
# §2.16.2 强制 09-changelog.md 含 `## Observation`，反向推断会让 metrics 造出幽灵
# 变更、让 `--stage staged` 拒掉整批（实测）。下面三锚点钉住修法，末条是反向断言。
report "A20 gate has ONE place that reads the batch roster" 1 "$(a17_at_least_1 "$(grep -c 'gov_ids() {' "$GATE_TPL" || true)")"
report "A20 batch change set comes from the roster, not from headings" 1 "$(a17_at_least_1 "$(grep -c 'roster=\$(gov_ids "\$d/00-governance.json")' "$GATE_TPL" || true)")"
report "A20 audit reads the roster as the batch's authoritative id set" 1 "$(a17_at_least_1 "$(grep -c '权威名单：只从治理记录取变更号' "$AUDIT_TPL" || true)")"
report "A20 audit documents WHY the reverse direction was dropped" 1 "$(a17_at_least_1 "$(grep -c '无法区分\"变更小节\"与\"结构小节\"' "$AUDIT_TPL" || true)")"
# 反向断言：`## <标题>` 反向推断不得回潮（`id_list=$(anchors_in_file "$f")` 只能是
# 无名单时的兜底，不能是批次归属的主路径——主路径必须是 gov_ids）。
report "A20 batch attribution does not fall back to heading scanning first" 0 "$(grep -cE '^ *id_list=\$\(anchors_in_file "\$f"\)$' "$GATE_TPL" || true)"
# 审计与门禁必须用**同一条** sed 表达式提取锚点：定义分叉时审计会绿而门禁红。
# 锚点形状的规范表述见门禁 anchor_re()：^##[[:space:]]+<id>([[:space:]]|$)
report "A20 audit and gate share one anchor shape" 1 "$(a17_at_least_1 "$(grep -c '同一条 sed 表达式' "$AUDIT_TPL" || true)")"
at_least "A20 standards documents the change batch" 1 "$STD" '变更批次'
at_least "A20 SKILL.md documents the batch layout" 1 "$SKILL" '变更批次'
at_least "A20 AGENTS.md states the batch rule in the gate steps" 1 "$ROOT/resources/AGENTS.md" 'BATCH-YYYYMMDD'
at_least "A20 changelog carries the v3.18.0 entry" 1 "$ROOT/resources/STANDARDS_CHANGELOG.md" 'v3.18.0'
# 反向断言：bash 3.2 缺陷不得回潮。`local a="$1" b="$x/$a"` 里 `$a` 尚未赋值
# （local 先展开全部词再赋值），set -u 下报 unbound variable；在 begin 路径因 id
# 恰为全局而侥幸通过，在 --stage staged / CI 路径（id 是局部变量，不进入 $( ) 子壳）
# 上是潜伏的。本版修正，此处钉住"声明必须拆开"。
report "A20 gate splits the resolver's local declaration (bash 3.2)" 0 "$(grep -c 'local id="\$1" d=' "$GATE_TPL" || true)"
report "A20 stamper splits the resolver's local declaration (bash 3.2)" 0 "$(grep -c 'local id="\$1" d=' "$STAMP_TPL" || true)"

# A21 治理记录的格式无关性锚点（v3.20.0）——防三类反向回退：
#   ① 记录读取退回**行式**（`grep ... | head -1`）→ 多行格式化记录读不到任何字段。
#      这不是假想：v3.18.0 为支持批次正是这么改的（行式对批次是必需的：要按
#      change_id 隔离兄弟记录），它**静默打破了多行记录**，而多行恰是**随包下发的
#      模板** `resources/templates/governance-state.json` 的形状、也是 SKILL.md
#      指示生成 `00-governance.json` 时照抄的形状。实测后果：`begin` 报
#      `must declare risk_level L0, L1, L2, or L3`（字段就在 change_id 下面两行），
#      `metrics` 对每条记录报 `"risk_level":null`；本仓账本 16/16 条全中。
#   ② 有人"反向修"——把模板压成单行来迁就读取器。数据迁就解析器是错的方向：
#      模板是给人看的，读取器必须接受任意合法 JSON。故有下面的反向断言。
#   ③ 批次成员之间串读（本修复最容易引入的回归）——由 run-tests T19 ④ 端到端钉住。
# 形态锚点；行为由 run-tests T19 在真仓库里端到端验证（多行 / 单行 / 多行批次三种形状）。
report "A21 gate flattens a governance record before matching" 1 "$(a17_at_least_1 "$(grep -c 'flat=\$(tr -d' "$GATE_TPL" || true)")"
report "A21 gate splits sibling records on top-level object boundaries" 1 "$(a17_at_least_1 "$(grep -c 'top-level object boundaries' "$GATE_TPL" || true)")"
report "A21 the record reader is documented as no longer line-oriented" 1 "$(a17_at_least_1 "$(grep -c 'no longer a PARSER' "$GATE_TPL" || true)")"
report "A21 the batch one-line convention survives as a style rule" 1 "$(a17_at_least_1 "$(grep -c 'style rule, not a load-bearing one' "$GATE_TPL" || true)")"
# 正向：随包模板仍是多行（这是本缺陷的触发形状，也是文档指示照抄的形状）
report "A21 shipped governance template is the multi-line shape" 1 "$(grep -cE '^  \"change_id\":' "$ROOT/resources/templates/governance-state.json" || true)"
# 反向：模板**不得**被压成单行来迁就解析器（数据迁就解析器是错的方向）
report "A21 the template was NOT collapsed to one line (fix the reader, not the data)" 0 "$(grep -cE '^\{.*\"change_id\".*\}$' "$ROOT/resources/templates/governance-state.json" || true)"
report "A21 golden suite covers a pretty-printed record end-to-end" 1 "$(a17_at_least_1 "$(grep -c 'T19 begin accepts a pretty-printed governance record' "$ROOT/tests/run-tests.sh" || true)")"
report "A21 golden suite pins that a sibling's risk cannot leak" 1 "$(a17_at_least_1 "$(grep -c 'T19 the sibling reads its own risk, not the first record' "$ROOT/tests/run-tests.sh" || true)")"
report "A21 changelog carries the v3.20.0 entry" 1 "$(a17_at_least_1 "$(grep -c 'v3.20.0' "$ROOT/resources/STANDARDS_CHANGELOG.md" || true)")"
at_least "A21 SKILL.md documents the format-agnostic record reader" 1 "$SKILL" '格式无关'
at_least "A21 MAINTAINER documents the record-reader coupling" 1 "$ROOT/MAINTAINER.md" 'gov_record'

# A22 审计单元识别 / 空转显式声明 / 编号定义式（v3.21.0）——防四类反向回退：
#   ① 审计单元退回"<docs>/ 下一层子目录全集" → `docs/changes`、`docs/bugs`、`docs/review`
#      只要存在一个，G2/G3/G5/G6 就**一条断言都不执行、也不打印任何行**（静默空转 =
#      假绿）。实测：一个 `docs/changes/CHG-001/01-spec.md` 带 REQ 跳号的仓库**通过**了
#      审计；同一根因还让 G4 去找不存在的 `docs/changes/09-changelog.md` 而误报假红。
#   ② 空转声明被删掉、或合并成一句 → 操作者再次分不清"覆盖了"与"没覆盖"（两组覆盖面
#      不同，必须分开声明）。
#   ③ `check_seq` 退回"grep 全出现 + 基线从 1 开始" → 本仓 16 个 01-spec.md 误报 **695**
#      处"缺号"（CHG-006 定义 `REQ-033~041`，却因正文引用 `REQ-024~032` 被撑成 24..41）。
#   ④ G3/G5/G6 被"顺手"扩到冻结的变更目录 → 拿**当前** §3/§4 判历史，产出**永久无法清除
#      的红**（§2.15 硬性规则 4 / §2.16.5「已闭合 CHG 禁止改写」）。
# 形态锚点；行为由 run-tests T20 在真仓库里端到端验证（管线态跳号 / 非 1 起点 / 正文引用）。
report "A22 audit detects units by positive signal" 1 "$(a17_at_least_1 "$(grep -c 'looks_like_audit_dir()' "$AUDIT_TPL" || true)")"
report "A22 audit declares a G2 vacuous skip instead of skipping silently" 1 "$(a17_at_least_1 "$(grep -c 'G2 VACUOUS SKIP' "$AUDIT_TPL" || true)")"
report "A22 audit declares the G3/G5/G6 vacuous skip separately from G2" 1 "$(a17_at_least_1 "$(grep -c 'G3/G5/G6 VACUOUS SKIP' "$AUDIT_TPL" || true)")"
report "A22 numbering counts definition-shaped occurrences only" 1 "$(a17_at_least_1 "$(grep -c 'DEF_RE()' "$AUDIT_TPL" || true)")"
report "A22 numbering baseline is the file's own min, not 1" 0 "$(grep -c '\$(seq 1 "\$max")' "$AUDIT_TPL" || true)"
report "A22 G2 covers the change track as well as the feature track" 1 "$(a17_at_least_1 "$(grep -c 'for base in "\$DOCS" "\$CHANGES"' "$AUDIT_TPL" || true)")"
report "A22 G3/G5/G6 are scoped to living docs only" 1 "$(a17_at_least_1 "$(grep -c 'g36_dirs' "$AUDIT_TPL" || true)")"
at_least "A22 the audit header documents the frozen-history scoping" 1 "$AUDIT_TPL" '不变量对冻结历史的适用性'
report "A22 golden suite pins the change-dir REQ gap end-to-end" 1 "$(a17_at_least_1 "$(grep -c 'T20 audit reds on a REQ gap inside a change dir' "$ROOT/tests/run-tests.sh" || true)")"
report "A22 golden suite pins that in-prose refs do not widen the span" 1 "$(a17_at_least_1 "$(grep -c 'T20 in-prose REQ references do not widen the definition span' "$ROOT/tests/run-tests.sh" || true)")"
report "A22 changelog carries the v3.21.0 entry" 1 "$(a17_at_least_1 "$(grep -c 'v3.21.0' "$ROOT/resources/STANDARDS_CHANGELOG.md" || true)")"
at_least "A22 MAINTAINER documents the audit-unit scoping" 1 "$ROOT/MAINTAINER.md" 'g36_dirs'

# A23 一键安装器 + 溯源全量盖章形态锚点（v3.22.0）——防三类反向回退：
#   ① install.sh 退化成自含安装逻辑（复制 bootstrap 清单）→ 双权威源必然漂移
#      （SKILL.md 步骤 3 的既有教训）；必须保持"薄委托"形态；
#   ② install.sh 丢失离线路径（--from）→ golden T21 无法零网络运行，CI 脆化；
#   ③ stamper 的 --all 把 00-governance.json 也盖了 → JSON 注入 HTML 注释破坏
#      门禁/审计的扁平 JSON 读取（假绿/假红的不可诊断来源）。
INSTALL_SH="$ROOT/scripts/install.sh"
report "A23 install.sh exists in the source layer" 1 "$([[ -s "$INSTALL_SH" ]] && echo 1 || echo 0)"
report "A23 install.sh stays a thin delegate to bootstrap" 1 "$(a17_at_least_1 "$(grep -c 'scripts/bootstrap.sh' "$INSTALL_SH" || true)")"
report "A23 install.sh auto-detects install vs upgrade" 1 "$(a17_at_least_1 "$(grep -c 'mode="auto"' "$INSTALL_SH" || true)")"
report "A23 install.sh keeps the offline path (--from)" 1 "$(a17_at_least_1 "$(grep -c -- '--from' "$INSTALL_SH" || true)")"
report "A23 install.sh never overwrites a dirty skill checkout" 1 "$(a17_at_least_1 "$(grep -c 'never overwrites your checkout' "$INSTALL_SH" || true)")"
report "A23 install.sh documents the one-liner" 1 "$(a17_at_least_1 "$(grep -c 'curl -fsSL' "$INSTALL_SH" || true)")"
report "A23 stamper exposes the --all mode" 1 "$(a17_at_least_1 "$(grep -c 'stamp_all=true' "$STAMP_TPL" || true)")"
report "A23 stamper --all targets every md artifact" 1 "$(a17_at_least_1 "$(grep -cF '"$CHG_DIR"/*.md' "$STAMP_TPL" || true)")"
report "A23 stamper documents why the governance JSON is excluded" 1 "$(a17_at_least_1 "$(grep -c 'deliberately NOT stamped' "$STAMP_TPL" || true)")"
report "A23 golden suite covers --all end-to-end" 1 "$(a17_at_least_1 "$(grep -c 'T17b --all stamps the whole change directory' "$ROOT/tests/run-tests.sh" || true)")"
report "A23 golden suite covers the one-command installer" 1 "$(a17_at_least_1 "$(grep -c 'T21 install.sh --from performs a full offline install' "$ROOT/tests/run-tests.sh" || true)")"
report "A23 project CHANGELOG.md exists (version narrative lives outside the READMEs)" 1 "$([[ -s "$ROOT/CHANGELOG.md" ]] && echo 1 || echo 0)"
at_least "A23 README en points at install.sh" 1 "$RM_EN" 'install.sh'
at_least "A23 README zh points at install.sh" 1 "$RM_ZH" 'install.sh'
at_least "A23 MAINTAINER documents the install.sh role" 1 "$ROOT/MAINTAINER.md" 'install.sh'

# ── PART A25: 项目级总册 + 缺陷按天入批形态锚点（v3.35.0，CHG-035/BUG-005）────
# 防五类反向回退：①总册体系被删（规范/方法论/模板三层任一缺失）；②begin/stop
# 的总册机校被静默移除；③缺陷批次化回退为"刻意不入批"；④stamper/审计丢失批次
# 嵌套形态；⑤golden 负例被删导致机校裸奔。
MASTERS_MD="$ROOT/resources/methodologies/project-masters.md"
report "A25 project-masters methodology file exists" 1 "$([[ -s "$MASTERS_MD" ]] && echo 1 || echo 0)"
at_least "A25 methodology defines the twelve masters" 1 "$MASTERS_MD" '十二册清单'
at_least "A25 methodology defines review-record shape" 1 "$MASTERS_MD" '评审记录必含章节'
at_least "A25 standards §1.3 defines the master set" 1 "$STD" '项目级总册与评审记录（Project Master Set'
at_least "A25 standards pins every-change backfill" 1 "$STD" '项目总册回填清单'
at_least "A25 standards pins first-change initialization" 1 "$STD" 'AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS'
at_least "A25 standards pins the bug diagnosis master-reading clause" 1 "$STD" '诊断前必读总册'
at_least "A25 standards pins the TC-coverage clause for bug fixes" 1 "$STD" '不可覆盖必须新增防回归 TC'
at_least "A25 standards reverses the v3.22.0 no-batch decision" 1 "$STD" '缺陷六件套自 v3.35.0 起同样按天入批'
at_least "A25 standards flattens the bug batch (v3.36.0)" 1 "$STD" '扁平化'
at_least "A25 standards pins the flat anchor form" 1 "$STD" '## <BUG-xxx>'
report "A25 gate resolves defect groups across both layouts" 1 "$(a17_at_least_1 "$(grep -c 'bug_group_dir' "$GATE_TPL" || true)")"
report "A25 gate sweeps batched bug groups" 1 "$(a17_at_least_1 "$(grep -c 'BATCH-\*/BUG-\*/' "$GATE_TPL" || true)")"
report "A25 gate sweeps flat anchor batches" 1 "$(a17_at_least_1 "$(grep -c 'anchored in more than one day batch' "$GATE_TPL" || true)")"
report "A25 gate enforces the bug day-batch default" 1 "$(a17_at_least_1 "$(grep -c 'must join it into the day batch\|move it into the day batch' "$GATE_TPL" || true)")"
report "A25 gate begin checks the twelve masters" 1 "$(a17_at_least_1 "$(grep -c 'validate_project_masters' "$GATE_TPL" || true)")"
report "A25 gate stop checks the master backfill rows" 1 "$(a17_at_least_1 "$(grep -c 'validate_master_backfill' "$GATE_TPL" || true)")"
report "A25 stamper resolves batched bug groups" 1 "$(a17_at_least_1 "$(grep -c 'defect group not found' "$STAMP_TPL" || true)")"
report "A25 audit carries G9 masters checks" 1 "$(a17_at_least_1 "$(grep -c 'G9 project masters' "$AUDIT_TPL" || true)")"
report "A25 audit sweeps batched bug groups" 1 "$(a17_at_least_1 "$(grep -c 'BATCH-\*/BUG-\*/' "$AUDIT_TPL" || true)")"
report "A25 audit sweeps flat anchor batches" 1 "$(a17_at_least_1 "$(grep -c '扁平批次锚点缺件' "$AUDIT_TPL" || true)")"
masters_n=0
for mf in 00-project-charter 01-requirements-master 02-architecture-master 03-interface-registry 04-data-dictionary 05-task-plan 06-test-master 07-test-verdicts 08-deployment-master 09-risk-register 10-change-ledger 11-decision-log; do
  [[ -s "$ROOT/resources/templates/project/$mf.md" ]] && masters_n=$((masters_n+1))
done
report "A25 twelve master templates exist" 12 "$masters_n"
report "A25 review-record template exists" 1 "$([[ -s "$ROOT/resources/templates/project/reviews/_template.review.md" ]] && echo 1 || echo 0)"
report "A25 golden suite pins the master backfill gate" 1 "$(a17_at_least_1 "$(grep -c 'T23 project-master backfill checklist is enforced at stop' "$ROOT/tests/run-tests.sh" || true)")"
report "A25 golden suite pins begin masters check" 1 "$(a17_at_least_1 "$(grep -c 'T23 begin refuses to start without project masters' "$ROOT/tests/run-tests.sh" || true)")"
report "A25 golden suite pins the bug day-batch default" 1 "$(a17_at_least_1 "$(grep -c 'T18c defect groups join the same-day batch' "$ROOT/tests/run-tests.sh" || true)")"
report "A25 golden suite pins the flat bug batch form" 1 "$(a17_at_least_1 "$(grep -c 'T18d flat bug batch' "$ROOT/tests/run-tests.sh" || true)")"
at_least "A25 changelog carries the v3.35.0 entry" 1 "$ROOT/resources/STANDARDS_CHANGELOG.md" 'v3.35.0'
at_least "A25 changelog carries the v3.36.0 entry" 1 "$ROOT/resources/STANDARDS_CHANGELOG.md" 'v3.36.0'

# ── PART A10: 审计执行数基线自校验（CHG-009 / FU-022）──────────────────────────
# 语义：audit 的实际执行断言数（pass+fail）必须与基线文件一致。断言增删（含不可达
# 死调用）而未同步基线 → 红；红即提示跑 scripts/update-assertion-count.sh 同步。
# 不采用"静态调用数==执行数"口径：if/else 双分支站点使静态数天然≠执行数。
# 基线文件随本变更入库；/tmp 计数文件为本轮运行现场（供生成器 --check 比对）。
AUDIT_BASELINE="$ROOT/tests/.audit-baseline"
AUDIT_LAST="${TMPDIR:-/tmp}/audit-executed-count"
printf '%s\n' "$(( pass + fail ))" > "$AUDIT_LAST"
if [[ -f "$AUDIT_BASELINE" ]]; then
  expected_total=$(cat "$AUDIT_BASELINE" | tr -d '[:space:]')
  report "A10 audit executed-count matches baseline (FU-022)" "$expected_total" "$(( pass + fail ))"
else
  report "A10 audit baseline exists (FU-022; run scripts/update-assertion-count.sh)" 1 0
fi

echo
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
