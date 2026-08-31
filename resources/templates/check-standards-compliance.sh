#!/usr/bin/env bash
# check-standards-compliance.sh
# 工程化兜底检查：不完全依赖 AI 自觉遵守 DEVELOPMENT_STANDARDS.md，
# 在 CI 中做最基础的"产物是否存在"校验（不校验内容质量，内容质量由门禁5独立 Review 负责）。
#
# 用法：在 PR/CI 流水线中，对比目标分支与当前分支的改动文件，
# 若命中 src/ 或 main 代码目录变更，则要求 docs/<feature>/ 下必须有对应更新。

set -euo pipefail

BASE_REF="${1:-origin/main}"
CHANGED_FILES=$(git diff --name-only "$BASE_REF"...HEAD)

CODE_CHANGED=$(echo "$CHANGED_FILES" | grep -E '\.(java|py|ts|tsx|js|go)$' || true)
DOCS_CHANGED=$(echo "$CHANGED_FILES" | grep -E '^docs/.*/(01-spec|03-modification-plan|04-test-scripts|05-test-results|09-changelog)\.md$' || true)

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
  done
fi

echo "✅ 基础合规检查通过（存在性 + A 层内容标记；内容质量仍需门禁5人工/独立 Agent Review）。"
