#!/usr/bin/env bash
# audit-docs-consistency.sh（通用层模板 —— 复制到目标仓库 tests/ 后使用）
#
# 【能力定位】跨文档一致性机器审计：规范要求"同一事实多处落点必须同步"
# （§3↔§4 同源声明、§1.2 编号顺序规则、门禁 4 双落点、§2.5 阶段 6 双登记），
# 此前只有 B 层人工核对。本脚本把这些一致性不变量固化为确定性断言，
# 与 agent-gate（单产物 A 层标记）互补——gate 管"单件合格"，本脚本管"多件互证"。
#
# 【审计范围】docs/DEVELOPMENT_STANDARDS.md + AGENTS.md + docs/<feature>/*/ + docs/bugfix-log.md：
#   G1 版本链：AGENTS.md 页脚版本 == 规范页脚版本（§2.16.4 第 6 条的机器化）
#   G2 编号体系：REQ/DES/TC/SC/CHG/CFG/DB/FU 连续递增、无跳号、无重号（§1.2 / 自检第 3 条）
#   G3 §3↔§4 同源：每个 09-changelog 最新 CHG 归档清单标签与规范 §3 完全一致（§3 同源声明）
#   G4 bugfix 双登记互证：log 每条 BUG 有对应 CHG；每个 CHG 的 BUG 行已登记 log（§2.5 阶段 6）
#   G5 RTVM 双落点：最新 CHG 追踪矩阵短引用中的 REQ 均已回填 01.5-rtvm-matrix（门禁 4）
#   G6 §4 必填节完整：最新 CHG 含 现象/分析/根因/方案/测试结论/角色签署/ReAct/检查清单/未动项
#
# 【更新语义】文档修订（活文档类）与批次保留冲突时以规范 §2.15 为准；存量仓库首跑
# 可能大量失败——失败项即 §2.14 存量回填清单，逐项处置或在 §2.13.4 走例外留痕。
#
# 零依赖：bash 3.2+、grep、awk、sort、comm。macOS/Linux 均可。
#
# Usage: tests/audit-docs-consistency.sh [repo_root]   # 默认当前仓库根
set -uo pipefail

ROOT="${1:-$(pwd)}"
STD="$ROOT/docs/DEVELOPMENT_STANDARDS.md"
AGENTS="$ROOT/AGENTS.md"
BFLOG="$ROOT/docs/bugfix-log.md"

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

# ---------- G2 编号体系：连续、唯一 ----------
# ---------- G2 编号体系：连续、无跳号 ----------
# 说明：重号（同一编号重复定义）无法在纯文本层面与"引用"可靠区分（TC/REQ 被下游
# 文档合法多次引用），故本脚本只做机器可验的连续性核查；重号核查留 §1.2 编号顺序
# 核对表（B 层/人工）。
check_seq() { # feature_dir prefix file_path label
  local dir="$1" prefix="$2" glob="$3" label="$4"
  local nums max i missing
  nums=$(grep -ohE "${prefix}-[0-9]+" "$glob" 2>/dev/null | grep -oE '[0-9]+' | awk '{printf "%d\n", $1}' | sort -n | uniq || true)
  [[ -z "$nums" ]] && { report "$label (no numbers, skip)" ok ok; return; }
  max=$(printf '%s\n' "$nums" | tail -1)
  if [[ "$max" -le 9999 ]]; then
    missing=0
    for i in $(seq 1 "$max"); do
      printf '%s\n' "$nums" | grep -qx "$i" || missing=$(( missing + 1 ))
    done
    report "$label continuous 1..${max} (no gaps)" 0 "$missing"
  else
    report "$label continuity (max=${max} skip)" ok ok
  fi
}

feature_dirs=$(find "$ROOT/docs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
if [[ -z "$feature_dirs" ]]; then
  report "G2 no feature dirs (vacuous skip)" ok ok
else
  # while-read 逐行迭代：兼容含空格的目录名（for in $var 会按空格拆词）
  while IFS= read -r d; do
    fname=$(basename "$d")
    [[ -f "$d/01-spec.md" ]] && check_seq "$d" "REQ" "$d/01-spec.md" "G2 REQ numbering in $fname"
    [[ -f "$d/03-modification-plan.md" ]] && check_seq "$d" "DES" "$d/03-modification-plan.md" "G2 DES numbering in $fname"
    [[ -f "$d/04-test-scripts.md" ]] && check_seq "$d" "TC" "$d/04-test-scripts.md" "G2 TC numbering in $fname"
    [[ -f "$d/04-test-scripts.md" ]] && check_seq "$d" "SC" "$d/04-test-scripts.md" "G2 SC numbering in $fname"
    [[ -f "$d/09-changelog.md" ]] && check_seq "$d" "CHG" "$d/09-changelog.md" "G2 CHG numbering in $fname"
    [[ -f "$d/06.5-deployment-config.md" ]] && check_seq "$d" "CFG" "$d/06.5-deployment-config.md" "G2 CFG numbering in $fname"
    [[ -f "$d/06.5-deployment-config.md" ]] && check_seq "$d" "DB" "$d/06.5-deployment-config.md" "G2 DB numbering in $fname"
    [[ -f "$d/06-delivery-summary.md" ]] && check_seq "$d" "FU" "$d/06-delivery-summary.md" "G2 FU numbering in $fname"
  done <<< "$feature_dirs"
fi

# ---------- G3 §3↔§4 同源 + G5 RTVM + G6 必填节（逐 09-changelog 最新 CHG） ----------
while IFS= read -r c; do
  chg="$c/09-changelog.md"
  [[ -f "$chg" ]] || continue
  fname=$(basename "$c")
  CHG_BLOCK=$(mktemp)
  awk 'BEGIN{f=0} f==1 && /^## /{exit} /^## /{f=1} f==1{print}' "$chg" > "$CHG_BLOCK"
  # G6 §4 必填节
  for sec in "#### 现象" "#### 分析" "#### 根因" "#### 方案" "#### 测试脚本与结论" "#### 角色签署与独立性" "#### 执行记录（ReAct" "#### 变更执行检查清单" "#### 未动项"; do
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
  # G5 RTVM 短引用 ⊆ 01.5 矩阵
  if [[ -f "$c/01.5-rtvm-matrix.md" ]]; then
    unreached=0
    for r in $(grep -oE 'REQ-[0-9]+' "$CHG_BLOCK" | sort -u); do
      grep -qE "^\| \`?${r}\`?" "$c/01.5-rtvm-matrix.md" || unreached=$(( unreached + 1 ))
    done
    report "G5 $fname CHG REQ rows all backfilled in 01.5 matrix" 0 "$unreached"
  else
    report "G5 $fname 01.5-rtvm-matrix.md missing" ok missing
  fi
  rm -f "$CHG_BLOCK"
done <<< "$feature_dirs"

# ---------- G4 bugfix 双登记互证 ----------
if [[ -f "$BFLOG" ]]; then
  # 陈旧模板占位自检：旧版模板占位标题含数字（### BUG-001：<一句话现象标题>），
  # 会被规范阶段 6 A 层 ^### BUG-[0-9] 计入 → 恒真统计。存在即判未替换。
  report "G4 stale numeric placeholder absent" 0 "$(grep -cE '^### BUG-0+1：<一句话现象标题>' "$BFLOG" 2>/dev/null || true)"
  orphans=0
  for b in $(grep -oE '^### BUG-[0-9]+' "$BFLOG" | grep -oE '[0-9]+' | awk '{printf "%d\n", $1}' | sort -n | uniq); do
    hit=0
    while IFS= read -r c; do
      [[ -f "$c/09-changelog.md" ]] && grep -qE "BUG-0*${b}([^0-9]|$)" "$c/09-changelog.md" && hit=1
    done <<< "$feature_dirs"
    [[ "$hit" -eq 0 ]] && orphans=$(( orphans + 1 ))
  done
  report "G4 every logged BUG referenced by some CHG" 0 "$orphans"
  unlogged=0
  while IFS= read -r c; do
    chg="$c/09-changelog.md"
    [[ -f "$chg" ]] || continue
    # 取「对应缺陷」行整行，行内可能引用多个 BUG（同批修复）
    bug_line=$(grep '对应缺陷' "$chg" | head -1)
    [[ -z "$bug_line" ]] && continue
    for b in $(printf '%s' "$bug_line" | grep -oE 'BUG-[0-9]+' | grep -oE '[0-9]+' | awk '{printf "%d\n", $1}' | sort -n | uniq); do
      grep -qE "^### BUG-0*${b}([^0-9]|$)" "$BFLOG" || unlogged=$(( unlogged + 1 ))
    done
  done <<< "$feature_dirs"
  report "G4 every CHG BUG line registered in log" 0 "$unlogged"
else
  report "G4 no docs/bugfix-log.md (skip; Bug 修复须先按 §2.5 阶段 6 建立)" ok ok
fi

rm -f "$S3TMP"
echo
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
