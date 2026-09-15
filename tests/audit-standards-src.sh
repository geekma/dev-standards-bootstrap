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
#   §1.1「最低文档集八类」含 06.5-deployment-config.md 与 06-delivery-summary.md，
#   但原模板目录**无对应模板**、门禁也不校验 → 目标仓库无处可复制、漏项无人拦。
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

# A3 README 声称的 golden-case 断言数必须 == run-tests 静态调用数——
#    防"47→52→55 多处数字漂移"复发（本项目实际发生过）
#
#    CHG-003 收紧取值正则，同时治两个方向的缺陷：
#    ① 漏匹配（危险方向）：旧正则 '[0-9]+ (assertions|项断言|golden-case 断言|Golden-Case 断言)'
#       要求数字后紧跟空格 + 关键词，于是 '107 golden-case assertions'（数字后跟 golden-case）
#       不匹配 → claims 只剩 {118} → A3 误判"单一一致数字"通过。该盲区曾让双 README 同时残留
#       107 与 118、而真值为 125，且这条 FAIL 在 main 上长期无人察觉。
#    ② 假阳性（阻断方向）：若仅放宽为 '[0-9]+[^0-9]{0,20}'，版本号尾数会被卷进来——实测
#       '见 §2.17.4 防恒真断言' 会命中 '4 防恒真断言'。
#    故最终形态：(^|[^0-9.])[0-9]+[^0-9]{0,20}(assertions?|项断言|項斷言|断言)
#       · 前导 '(^|[^0-9.])' 排除"前一个字符是数字或小数点"，避免版本号尾数被当成计数；
#       · 上限 20 覆盖全部已知中英表述（最长 '项 golden-case ' 为 14 字符）并避免跨句误匹配；
#       · 'assertions?' 兼顾单复数。
#    须命中：'107 golden-case assertions' / '118 assertions' / '107 项 golden-case 断言'
#    须不命中：'见 §2.17.4 防恒真断言'（版本号尾数）
#    已知残余缺口（不阻断，登记 FU-009）：'assertions: 125'（数字在关键词之后）不命中。
claims=$(grep -ohE '(^|[^0-9.])[0-9]+[^0-9]{0,20}(assertions?|项断言|項斷言|断言)' "$RM_EN" "$RM_ZH" | grep -oE '[0-9]+' | sort -u | tr '\n' ',')
actual=$(grep -cE '^[[:space:]]*(report|check_output) ' "$ROOT/tests/run-tests.sh")
report "A3 README assertion-count claims are a single consistent number" 1 "$(printf '%s' "$claims" | grep -c '^[0-9]*,$')"
report "A3 claimed assertion count == run-tests static call count" "$actual" "${claims%,}"

# A3c 生成器同步校验（CHG-007 / FU-005+009）：README 声称数必须与生成器 --check 一致——
#    手工改数、漏改、或 run-tests 增删用例后未同步，都在这里红。
GEN="$ROOT/scripts/update-assertion-count.sh"
if [[ -f "$GEN" ]]; then
  bash "$GEN" --check >/dev/null 2>&1
  report "A3c README assertion claims match generated count (FU-005/009)" 0 "$?"
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
#    `06.5` 与 `06-delivery-summary` 长期处于此状态（八类中两类无守护），是 CHG-003
#    差点漏交 06.5 的制度性原因。
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
chg_nums=$(basename -s '' $(ls -d "$REPO_CHANGES"/CHG-* 2>/dev/null) 2>/dev/null | sed 's/CHG-//' | sort -n)
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
else
  report "A6c CHG numbering continuous (no gaps)" 1 0
fi

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

# ── PART A8: 门禁硬化形态锚点（CHG-007：FU-008/014/015/019 防复发）──────────────────
#   门禁行为已由 run-tests golden case 守护；此处锁"实现形态"，防行为被静默回退成弱检查
#   （BUG-001 同族：检查模式弱于其声称语义）。取值用 grep -F 固定串，防正则元字符歧义。
GATE_TPL="$ROOT/resources/templates/agent-gate.sh"
report "A8 begin rejects closed change re-entry (FU-015)" 1 "$(grep -cF 'already closed' "$GATE_TPL")"
report "A8 RTVM glob covers nested change-dir matrices (FU-019)" 1 "$(grep -cF 'docs/changes/*/01.5-rtvm-matrix.md' "$GATE_TPL")"
# 说明：固定串在 gate 中天然多处命中（检查点 + 报文），故下两条用 ≥1 下界语义而非恒等
ga_n=$(grep -cF 'REQ-[0-9]+' "$GATE_TPL")
report "A8 numbering checks are digit-anchored (FU-008)" 1 "$([[ "$ga_n" -ge 1 ]] && echo 1 || echo 0)"
ga_s=$(grep -cF '业务影响)' "$GATE_TPL")
report "A8 stage-2 impact checks are structure-anchored (FU-008)" 1 "$([[ "$ga_s" -ge 1 ]] && echo 1 || echo 0)"
report "A8 delivery declarations are line-anchored (FU-014)" 1 "$(grep -cF '[#>-][[:space:]]*)*未命中' "$GATE_TPL")"

# A9 规范条款存在性锚点（CHG-008 / FU-016）：防条款被静默移除
at_least "A9 change-id occupancy-verification clause present (FU-016)" 1 "$STD" '取号前必须核实占用'

# A11 规范体量上界（CHG-010 / FU-017）：≤115KB（117,760 字节）——防正文回弹
std_bytes=$(wc -c < "$STD" | tr -d ' ')
report "A11 standards body size <= 115KB (FU-017)" 1 "$([[ "$std_bytes" -le 117760 ]] && echo 1 || echo 0)"
at_least "A11 layered reading map present (FU-018)" 1 "$STD" '分层阅读路由'

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
