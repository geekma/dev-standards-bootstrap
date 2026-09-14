#!/usr/bin/env bash
# check-standards-compliance.sh
# 工程化兜底检查：不完全依赖 AI 自觉遵守 DEVELOPMENT_STANDARDS.md，
# 在 CI 中做最基础的"产物是否存在"校验（不校验内容质量，内容质量由门禁5独立 Review 负责）。
#
# 用法：在 PR/CI 流水线中，对比目标分支与当前分支的改动文件，
# 若命中 src/ 或 main 代码目录变更，则要求 docs/<feature>/ 下必须有对应更新。
# 可选传入基线：scripts/check-standards-compliance.sh <base-ref>
#
# ── 基线（BASE_REF）为什么必须给，以及为什么不许写死 ──────────────────────────
# 1. 必须给：下方用三点号 diff（BASE...HEAD），即 merge-base 语义，只算"本分支相对
#    分叉点引入的改动"。去掉基线只剩 HEAD~1（多 commit 分支漏检）或工作区 diff
#    （CI 无工作区），都会漏检。基线要指向"合入目标"，不是"当前所在分支"。
# 2. 不许写死：写死 origin/main 在主线为 master 的仓库直接 fatal 退出（不可自愈）；
#    更危险的是为绕过报错顺手补 `|| true` —— CHANGED_FILES 变空后脚本会打印
#    "✅ 基础合规检查通过"：**检查没跑被伪装成检查通过**，比报错危险一个数量级。
# 3. 因此：解析顺序为"权威来源在前、猜测在后"（见 resolve_base_ref），
#    解析不出即 exit 2 拒绝放行（fail-closed），绝不退化为"空 diff 视为通过"。
#
# 环境变量：
#   CI_BASE_REF  CI 平台注入的 PR 目标分支（最权威的自动化来源；未设置即跳过本级）

set -euo pipefail

# 五级解析：1 显式参数 > 2 CI 注入 > 3 远端默认分支 > 4 常见远端候选 > 5 本地同名分支。
# 返回 0 且 stdout 非空 = 命中；返回 1 = 五级全落空；返回 2 = 调用方显式声明了 CI 基线
# 但该 ref 在本仓库不可解析（配置错误，须由调用方 fail-closed，不得静默降级到猜测——
# 否则会选出一个"可解析但错误"的基线，使 diff 悄悄变窄而漏检）。
resolve_base_ref() {
  local c
  if [[ -n "${1:-}" ]]; then
    printf '%s' "$1"
    return 0
  fi
  if [[ -n "${CI_BASE_REF:-}" ]]; then
    if git rev-parse -q --verify "${CI_BASE_REF}^{commit}" >/dev/null 2>&1; then
      printf '%s' "$CI_BASE_REF"
      return 0
    fi
    return 2
  fi
  c=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [[ -n "$c" ]]; then
    printf '%s' "$c"
    return 0
  fi
  for c in origin/main origin/master origin/trunk origin/develop; do
    if git rev-parse -q --verify "${c}^{commit}" >/dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  for c in main master trunk develop; do
    if git rev-parse -q --verify "${c}^{commit}" >/dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

BASE_REF=""
resolve_rc=0
BASE_REF=$(resolve_base_ref "${1:-}") || resolve_rc=$?
if [[ "$resolve_rc" -eq 2 ]]; then
  echo "❌ CI_BASE_REF='${CI_BASE_REF}' 在本仓库不可解析，拒绝放行（fail-closed）。" >&2
  echo "   CI 显式声明了基线即视为权威来源，不得静默降级到猜测（会选出错误基线而漏检）。" >&2
  echo "   请检查变量取值是否正确、或 CI 是否因浅克隆未取全该分支的历史。" >&2
  exit 2
fi
if [[ -z "$BASE_REF" ]]; then
  echo "❌ 门禁无法确定基线分支，拒绝放行（fail-closed）。" >&2
  echo "   显式传入：$0 <base-ref>（如 origin/master）" >&2
  echo "   或在 CI 中把 CI_BASE_REF 设为本次 PR 的目标分支。" >&2
  echo "   原因：基线未知时 diff 会退化为空，而空 diff 会被误读为「无变更」而放行。" >&2
  exit 2
fi
if ! git rev-parse -q --verify "${BASE_REF}^{commit}" >/dev/null 2>&1; then
  echo "❌ 门禁基线 '$BASE_REF' 在本仓库不可解析，拒绝放行（fail-closed）。" >&2
  echo "   常见原因：本仓库主线是 master 而基线写成了 origin/main；或 CI 浅克隆未取全历史。" >&2
  exit 2
fi
echo "基线（base ref）：$BASE_REF"

CHANGED_FILES=$(git diff --name-only "$BASE_REF"...HEAD)

# 代码路径定义必须与 agent-gate.sh is_code_path() 保持一致（同层守卫，单一口径）：
# 之前只列 6 种后缀，漏 .sh/.sql/.kt/.rb/.php/.cs/.cpp 等 → 代码变更逃过文档检查。
# 【同步义务】下方扩展名清单须与 resources/templates/agent-gate.sh 的 is_code_path()
# 一致——机器双守护：源层 audit A2 + tests/run-tests.sh T12；改其一必须同步改另一。
CODE_CHANGED=$(echo "$CHANGED_FILES" | grep -E '\.(c|cc|cpp|cs|go|java|js|jsx|kt|kts|php|py|rb|rs|scala|sh|sql|swift|ts|tsx|vue)$' || true)
DOCS_CHANGED=$(echo "$CHANGED_FILES" | grep -E '^docs/.*/(01-spec|02-code-impact-analysis|03-modification-plan|03\.5-tasks|04-test-scripts|05-test-results|09-changelog)\.md$' || true)

if [[ -n "$CODE_CHANGED" && -z "$DOCS_CHANGED" ]]; then
  echo "❌ 门禁拦截：检测到源码变更，但未发现 docs/<feature>/ 下对应的规范文档更新。"
  echo "命中门禁 1（需求/设计先行）与门禁 4（追踪矩阵闭环），本次变更判定为不合规。"
  echo "变更的源码文件："
  echo "$CODE_CHANGED"
  exit 1
fi

if [[ -n "$DOCS_CHANGED" ]]; then
  # 抽查 09-changelog.md 是否含有必填字段关键词，防止只建空文件
  for f in $(echo "$DOCS_CHANGED" | grep '09-changelog.md' || true); do
    for section in "追踪矩阵映射" "测试脚本与结论" "角色签署与独立性"; do
      if ! grep -q "$section" "$f"; then
        echo "❌ 门禁拦截：$f 缺少必填节「$section」（DEVELOPMENT_STANDARDS.md §4）"
        exit 1
      fi
    done
    grep -q 'Observation' "$f" || { echo "❌ ReAct 拦截：$f 缺「执行记录（ReAct）」Observation 记录（§2.16.2 铁律）"; exit 1; }
  done

  # A 层验收（§2.5 验收标准总则）：更新过的产物必须含编号体系，防空洞骨架冒充成品
  for f in $(echo "$DOCS_CHANGED" | grep '01-spec.md' || true); do
    grep -q 'REQ-' "$f" || { echo "❌ A 层验收拦截：$f 不含 REQ- 编号体系（§2.5 阶段1 验收标准 A 层）"; exit 1; }
  done
  for f in $(echo "$DOCS_CHANGED" | grep '03-modification-plan.md' || true); do
    grep -q 'DES-' "$f" || { echo "❌ A 层验收拦截：$f 不含 DES- 编号体系（§2.5 阶段3 验收标准 A 层）"; exit 1; }
  done
  for f in $(echo "$DOCS_CHANGED" | grep '04-test-scripts.md' || true); do
    grep -q 'TC-' "$f" || { echo "❌ A 层验收拦截：$f 不含 TC- 编号体系（§2.5 阶段4 验收标准 A 层）"; exit 1; }
    grep -q 'SC-' "$f" || { echo "❌ A 层验收拦截：$f 不含 SC- 业务场景清单（§2.5 阶段4，v3.3.0）"; exit 1; }
  done
fi

echo "✅ 基础合规检查通过（存在性 + A 层内容标记；内容质量仍需门禁5人工/独立 Agent Review）。"
