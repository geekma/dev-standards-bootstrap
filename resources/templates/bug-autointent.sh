#!/usr/bin/env bash
# bug-autointent — 缺陷发现入口：信号 → 自动六件套骨架（v3.43.0，REQ-958 / FU-106④）
#
# 解决的问题："发现靠用户反馈"是最大缺口。主干合入后测试回归红（无人值守）、
# 会话内 audit 红灯 / gate 摩擦（有人值守）三类信号不再依赖人工登记：
#   1. 计算失败指纹（规范化失败项集合的校验和）
#   2. 频控闸门：同指纹在 AGENT_GUARD_AUTOBUG_WINDOW（默认 86400 秒）内已登记
#      → 不新建，仅向原 01-diagnosis「复现记录（自动）」节追加一行复现
#   3. 窗口外/首次 → 在 docs/bugs/BATCH-<UTCday>/ 扁平建**完整六件套**骨架
#      （六模板锚点化 + 失败元数据预填，severity 不声明 = 六件全查 fail-closed）
#      + bugfix-log.md 双登记行（新条目置顶）
#
# 用法：
#   scripts/bug-autointent --source <label> --failing "<name[,name2...]>"
#                          [--run-url <url>] [--title <一句话现象>] [--window <sec>]
#                          [--bugs-root <dir>] [--repo-root <dir>]
#
# 通道分工（§2.17.2，v3.43.0）：无人值守（CI workflow_run 回调）自动建；
# 会话内信号由 Agent 交互三选项（建骨架 / 登记 FU / 忽略须 09 理由）后调用本脚本。
# 事故通道（github-incident-to-intent.yml，00-intent 骨架）语义不变，两通道并存。
#
# 零依赖：bash 3.2+、sed/awk/grep/cksum；无 git 时须显式 --repo-root（exit 2）。
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/bug-autointent --source <label> --failing "<name[,name2...]>"
                              [--run-url <url>] [--title <text>] [--window <sec>]
                              [--bugs-root <dir>] [--repo-root <dir>]

Derives a failure fingerprint and either appends a reproduction line to the
existing defect group (rate-limit window) or scaffolds a FULL six-piece defect
group under docs/bugs/BATCH-<UTCday>/ (flat `## BUG-<UTCts>` anchors) with the
failure metadata pre-filled, plus a bugfix-log.md index row (newest on top).

--source:  signal label (ci-regression / audit-red / gate-friction / interactive)
--failing: comma/newline separated failing test or job names (fingerprint basis)
--window:  rate-limit seconds (default $AGENT_GUARD_AUTOBUG_WINDOW or 86400)
EOF
}

source_label=""
failing=""
run_url=""
title=""
window="${AGENT_GUARD_AUTOBUG_WINDOW:-86400}"
bugs_root=""
repo_root=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --source)    source_label="${2:-}"; shift 2 ;;
    --failing)   failing="${2:-}"; shift 2 ;;
    --run-url)   run_url="${2:-}"; shift 2 ;;
    --title)     title="${2:-}"; shift 2 ;;
    --window)    window="${2:-}"; shift 2 ;;
    --bugs-root) bugs_root="${2:-}"; shift 2 ;;
    --repo-root) repo_root="${2:-}"; shift 2 ;;
    *) echo "bug-autointent: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$source_label" ]] || { echo "bug-autointent: --source is required" >&2; exit 2; }
[[ -n "$failing" ]]      || { echo "bug-autointent: --failing is required" >&2; exit 2; }

# 仓库根：--repo-root 优先；无 git 环境且未显式给出 → 显式降级（exit 2，不猜）
if [[ -z "$repo_root" ]]; then
  if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel)
  else
    echo "bug-autointent: no git repository and no --repo-root given — refuse to guess (exit 2)" >&2
    exit 2
  fi
fi
[[ -d "$repo_root" ]] || { echo "bug-autointent: repo root not found: $repo_root" >&2; exit 2; }

if [[ -z "$bugs_root" ]]; then
  br="${AGENT_GUARD_BUGS_ROOT:-docs/bugs}"
  case "$br" in
    /*) bugs_root="$br" ;;
    *)  bugs_root="$repo_root/$br" ;;
  esac
fi

now=$(date -u +%s)
now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- 失败指纹：规范化失败项集合 → cksum（POSIX 可移植） ----------------------
names=$(printf '%s\n' "$failing" | tr ',\n' '\n\n' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | sort -u)
[[ -n "$names" ]] || { echo "bug-autointent: no usable failing names" >&2; exit 2; }
fingerprint=$(printf '%s' "$names" | cksum | cut -d' ' -f1)
failing_one=$(printf '%s' "$names" | tr '\n' ',' | sed 's/,$//')

# --- 频控闸门：指纹台账（.tsv，隐藏非 md，不进 G8 扫描面） --------------------
tsv="$bugs_root/.autofingerprint.tsv"
mkdir -p "$bugs_root"
if [[ -f "$tsv" ]]; then
  dup_bug=$(awk -F'\t' -v fp="$fingerprint" -v now="$now" -v win="$window" \
    '$2==fp && (now-$1)<win {print $3; exit}' "$tsv" || true)
  if [[ -n "$dup_bug" ]]; then
    dup_diag=$(grep -lE "^##[[:space:]]+${dup_bug}([[:space:]]|\$)" \
      "$bugs_root"/BATCH-*/01-diagnosis.md 2>/dev/null | head -1 || true)
    if [[ -n "$dup_diag" ]]; then
      tmp=$(mktemp)
      awk -v id="$dup_bug" -v line="- 再次复现 ${now_iso} source=${source_label} run=${run_url:-n/a}（频控窗口内不新建骨架）" '
        { print }
        $0 ~ ("^##[[:space:]]+" id "([[:space:]]|$)") { on=1 }
        on && /^## 复现记录（自动）/ && !done { print line; done=1 }
      ' "$dup_diag" > "$tmp" && mv "$tmp" "$dup_diag"
    else
      echo "bug-autointent: WARN — ledger has ${dup_bug} but no 01-diagnosis anchor found; reproduction line skipped (ledger row still recorded)" >&2
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$fingerprint" "$dup_bug" "${run_url:-n/a}" "$source_label" >> "$tsv"
    echo "bug-autointent: dedup — reproduction appended to ${dup_bug}（频控窗口内不新建）"
    exit 0
  fi
fi

# --- 新建：完整六件套（扁平批次 + 锚点） --------------------------------------
day=$(date -u +%Y%m%d)
bug_id="BUG-$(date -u +%Y%m%d%H%M%S)"
batch_dir="$bugs_root/BATCH-$day"
mkdir -p "$batch_dir"

# 模板解析：已装仓 <docs>/bugs/_templates/；源仓 resources/templates/
tpl_dir="$bugs_root/_templates"
[[ -d "$tpl_dir" ]] || tpl_dir="$repo_root/resources/templates"
[[ -d "$tpl_dir" ]] || { echo "bug-autointent: no bug templates found ($bugs_root/_templates or resources/templates)" >&2; exit 2; }

declare-piece() { # 1=件名 2=模板名
  case "$1" in
    01-diagnosis) echo "bug-diagnosis.md" ;;
    02-impact)    echo "bug-impact.md" ;;
    03-test-plan) echo "bug-test-plan.md" ;;
    04-matrix)    echo "bug-matrix.md" ;;
    05-config)    echo "bug-config.md" ;;
    06-tasks)     echo "bug-tasks.md" ;;
  esac
}

for piece in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  f="$batch_dir/$piece.md"
  tpl="$tpl_dir/$(declare-piece "$piece")"
  {
    [[ -f "$f" ]] && printf '\n'
    printf '## %s · %s（%s 自动登记）\n\n' "$bug_id" "$piece" "$source_label"
    printf '> 本节由 bug-autointent 自动创建（%s，§2.17.2 回归/信号重入通道，v3.43.0）。\n> 元数据确定性注入勿删；正文由接手者按 §2.5 阶段 6 补全。severity 未声明 = 六件全查。\n\n' "$now_iso"
    if [[ -f "$tpl" ]]; then
      sed '1d' "$tpl"   # 去模板首行 H1，正文作接手指引
    else
      printf '[模板缺失：%s]\n' "$tpl"
    fi
    if [[ "$piece" == "01-diagnosis" ]]; then
      printf '\n## 复现记录（自动）\n\n'
    fi
  } >> "$f"
done

# 01-diagnosis 元数据预填 + 复现记录节
diag="$batch_dir/01-diagnosis.md"
tmp=$(mktemp)
awk -v id="$bug_id" -v line="- 首次登记 ${now_iso} source=${source_label} run=${run_url:-n/a}" '
  { print }
  $0 ~ ("^##[[:space:]]+" id "([[:space:]]|$)") { on=1 }
  on && /^## 复现记录（自动）/ && !done { print line; done=1 }
' "$diag" > "$tmp" && mv "$tmp" "$diag"

# --- 台账 + bugfix-log 双登记 -------------------------------------------------
printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$fingerprint" "$bug_id" "${run_url:-n/a}" "$source_label" >> "$tsv"

buglog="$repo_root/docs/bugfix-log.md"
if [[ -f "$buglog" ]]; then
  tmp=$(mktemp)
  entry="### ${bug_id}：${title:-自动登记：${source_label} 失败（严重度 P2/自动）}

| 字段 | 内容 |
|---|---|
| 日期 / 发现来源 | $(date -u +%Y-%m-%d) / ${source_label}（自动，run=${run_url:-n/a}） |
| 关联变更 | 待接手者填写（修复所在 CHG） |
| 关联需求 / 设计 | 无（缺陷类） |
| 关联缺陷 | 无 |
| 现象摘要 | 失败项：${failing_one}（指纹 ${fingerprint}） |
| 文档组落点 | docs/bugs/BATCH-${day}/（扁平，自动六件套骨架） |"
  first_bug=$(grep -nE '^### BUG-[0-9]' "$buglog" | head -1 | cut -d: -f1 || true)
  if [[ -n "$first_bug" ]]; then
    { head -n $(( first_bug - 1 )) "$buglog"; printf '%s\n' "$entry"; echo; tail -n +$first_bug "$buglog"; } > "$tmp"
  else
    { cat "$buglog"; printf '\n%s\n' "$entry"; } > "$tmp"
  fi
  mv "$tmp" "$buglog"
fi

echo "bug-autointent: created ${bug_id}（六件套骨架 docs/bugs/BATCH-${day}/，指纹 ${fingerprint}，频控 ${window}s）"
