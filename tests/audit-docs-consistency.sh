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

for f in "$AGENTS" "$METH" "$DEV" "$DS"; do
  report "version footer synced: $(basename "$f")" 1 "$(grep_count "$f" "当前对应规范版本：v${V}_")"
done

report "version badge zh"            1 "$(grep_count "$RM_ZH" "规范版本-v${V}-")"
report "version badge en"            1 "$(grep_count "$RM_EN" "Standards-v${V}-")"
report "version footer zh"           1 "$(grep_count "$RM_ZH" "规范版本：\*\* v${V}")"
report "version footer en"           1 "$(grep_count "$RM_EN" "Standards Version:\*\* v${V}")"
report "version tree zh"             1 "$(grep_count "$RM_ZH" "完整规范文档 v${V}")"
report "version tree en"             1 "$(grep_count "$RM_EN" "Full standards document v${V}")"
report "skill carried version"       1 "$(grep_count "$SKILL" "当前携带版本 v${V}")"

# 升级日志首行（新条目置顶）== 页脚版本
log_head=$(awk '/^## 标准升级日志/,0' "$STD" | grep -m1 -oE '^\| v[0-9.]+' | grep -oE '[0-9.]+')
report "upgrade log newest row == footer version" "$V" "$log_head"

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

# ---------- §3 ↔ §4 执行清单同源（R-A 轮） ----------
# 注意：标准全文有 4 个 ```markdown fence（§1.2/§2.6.3/§3/§4），必须按章节标题锚定，
# 禁止按 fence 序号取（序号法取到 §1.2/§2.6.3 两个空清单 → 恒真 IDENTICAL，R-D 轮修正）。
awk '/^## 3\. 变更执行全流程检查清单/{w=1} w && /^```markdown$/{f=1; w=0; next} f==1{ if(/^```$/){exit} print }' "$STD" | grep -oE '【[^】]+】' | sort > /tmp/audit_s3.$$
awk '/^## 4\. Changelog/{w=1} w && /^```markdown$/{f=1; w=0; next} f==1{ if(/^```$/){exit} print }' "$STD" | grep -oE '【[^】]+】' | sort > /tmp/audit_s4.$$
if diff -q /tmp/audit_s3.$$ /tmp/audit_s4.$$ >/dev/null 2>&1; then r=1; else r=0; fi
report "section3 vs section4 checklist labels identical" 1 "$r"
n3=$(wc -l < /tmp/audit_s3.$$ | tr -d ' ')
report "section3 checklist extraction non-empty (防恒真空转)" 1 "$([[ "$n3" -gt 0 ]] && echo 1 || echo 0)"
rm -f /tmp/audit_s3.$$ /tmp/audit_s4.$$

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
claims=$(grep -ohE '[0-9]+ (assertions|项断言|golden-case 断言|Golden-Case 断言)' "$RM_EN" "$RM_ZH" | grep -oE '[0-9]+' | sort -u | tr '\n' ',')
actual=$(grep -cE '^[[:space:]]*(report|check_output) ' "$ROOT/tests/run-tests.sh")
report "A3 README assertion-count claims are a single consistent number" 1 "$(printf '%s' "$claims" | grep -c '^[0-9]*,$')"
report "A3 claimed assertion count == run-tests static call count" "$actual" "${claims%,}"

echo
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
