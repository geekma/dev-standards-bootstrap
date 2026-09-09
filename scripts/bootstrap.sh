#!/usr/bin/env bash
# bootstrap.sh — dev-standards-bootstrap 清单驱动安装器
#
# 把本 Skill 的治理文件按分层清单复制到目标仓库固定落点，替代 SKILL.md 中
# 的手工逐条复制（防接入遗漏）。清单即单一权威源：SKILL.md 只引用本脚本，
# 不再逐条枚举复制步骤。
#
# 设计：
#   - 幂等：目标文件与源一致时跳过并提示 "up to date"。
#   - 防覆盖：目标已有不同内容时展示 diff 并以退出码 2 拒绝；--force 覆盖。
#   - 零依赖：bash 3.2+ + cp + diff（macOS/Linux）。
#   - 分层 flags 与 SKILL.md 步骤 4 的可选增强一一对应。
#
# Usage:
#   bash scripts/bootstrap.sh [target_root]
#   bash scripts/bootstrap.sh --core|--claude|--ci|--guard|--pipeline|--all [--force] [target_root]
#
# target_root 缺省为当前目录；--core 为默认层（核心文档层）。
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [flags] [target_root]

Flags (layers; default --core when none given):
  --core       核心文档层: AGENTS.md, DEVELOPMENT_STANDARDS.md, METHODOLOGY.md,
               methodologies/, bugfix-log.md, docs/bugs/_templates/ (6),
               tests/audit-docs-consistency.sh (通用层审计)
  --claude     CLAUDE.md 一行导入
  --ci         工程化兜底: PULL_REQUEST_TEMPLATE.md, scripts/check-standards-compliance.sh
  --guard      强制执行包: scripts/agent-gate, .githooks/ (pre-commit/pre-push/commit-msg),
               .github/workflows/agent-governance.yml, scripts/install-hook-adapter,
               .agent-governance.yml, tests/run-tests.sh (治理自测试随强制包, §2.17.4)
  --pipeline   管线自动化: artifact-pipeline.yml, incident-to-intent.yml
  --all        以上全部
  --force      覆盖目标仓库中内容不同的既有文件（默认冲突时展示 diff 并拒绝）
  -h, --help   本帮助

任何层遇到冲突文件时退出 2（fail-closed），已复制的文件保留，重跑 --force 覆盖。
变更起编时使用的 per-change 模板（00-intent / 00-governance / coding-record）不在
本清单：它们随变更号动态落 docs/changes/<变更号>/，由 SKILL.md 指导生成。
EOF
}

force=false
layers=""
target=""
for arg in "$@"; do
  case "$arg" in
    --core)     layers="$layers core" ;;
    --claude)   layers="$layers claude" ;;
    --ci)       layers="$layers ci" ;;
    --guard)    layers="$layers guard" ;;
    --pipeline) layers="$layers pipeline" ;;
    --all)      layers="core claude ci guard pipeline" ;;
    --force)    force=true ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "bootstrap: unknown flag '$arg'" >&2; usage >&2; exit 2 ;;
    *)          target="$arg" ;;
  esac
done
[[ -n "$layers" ]] || layers="core"
[[ -n "$target" ]] || target="$PWD"
[[ -d "$target" ]] || { echo "bootstrap: target is not a directory: $target" >&2; exit 2; }

# install_file <dest_rel> <src_rel> [chmod_mode]
install_file() {
  local dest_rel="$1" src_rel="$2" chmod_mode="${3:-}"
  local dest="$target/$dest_rel" src="$SKILL_ROOT/$src_rel"
  [[ -f "$src" ]] || { echo "bootstrap: MISSING SOURCE $src_rel (skill repo broken)" >&2; exit 2; }
  if [[ -e "$dest" ]]; then
    if cmp -s "$dest" "$src"; then
      echo "up to date   $dest_rel"
      skipped=$(( skipped + 1 ))
      return 0
    fi
    if [[ "$force" != true ]]; then
      echo "CONFLICT     $dest_rel (different content; re-run with --force to overwrite)" >&2
      diff -u --label "$dest_rel (existing)" --label "$src_rel (template)" "$dest" "$src" >&2 || true
      exit 2
    fi
    echo "overwrite    $dest_rel"
    overwritten=$(( overwritten + 1 ))
  else
    echo "installed    $dest_rel"
    installed=$(( installed + 1 ))
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  [[ -n "$chmod_mode" ]] && chmod "$chmod_mode" "$dest"
}

installed=0
overwritten=0
skipped=0

run_layer() {
  local layer="$1"
  case "$layer" in
    core)
      install_file AGENTS.md resources/AGENTS.md
      install_file docs/DEVELOPMENT_STANDARDS.md resources/DEVELOPMENT_STANDARDS.md
      install_file docs/METHODOLOGY.md resources/METHODOLOGY.md
      for m in development.md data-structures.md state-trigger-audit.md; do
        install_file "docs/methodologies/$m" "resources/methodologies/$m"
      done
      install_file docs/bugfix-log.md resources/templates/bugfix-log.md
      for b in bug-diagnosis.md bug-impact.md bug-test-plan.md bug-matrix.md bug-config.md bug-tasks.md; do
        install_file "docs/bugs/_templates/$b" "resources/templates/$b"
      done
      install_file tests/audit-docs-consistency.sh resources/templates/audit-docs-consistency.sh 755
      ;;
    claude)
      install_file CLAUDE.md resources/templates/CLAUDE.md
      ;;
    ci)
      install_file .github/PULL_REQUEST_TEMPLATE.md resources/templates/PULL_REQUEST_TEMPLATE.md
      install_file scripts/check-standards-compliance.sh resources/templates/check-standards-compliance.sh 755
      ;;
    guard)
      install_file scripts/agent-gate resources/templates/agent-gate.sh 755
      install_file .githooks/pre-commit resources/templates/pre-commit 755
      install_file .githooks/pre-push resources/templates/pre-push 755
      install_file .githooks/commit-msg resources/templates/commit-msg 755
      install_file .github/workflows/agent-governance.yml resources/templates/github-agent-governance.yml
      install_file scripts/install-hook-adapter resources/templates/install-hook-adapter.sh 755
      install_file .agent-governance.yml resources/templates/agent-governance.yml
      # 治理自测试随强制包（打包错位修复）：改 agent-gate/hooks 前必须能跑 golden cases
      install_file tests/run-tests.sh tests/run-tests.sh 755
      ;;
    pipeline)
      install_file .github/workflows/artifact-pipeline.yml resources/templates/github-artifact-pipeline.yml
      install_file .github/workflows/incident-to-intent.yml resources/templates/github-incident-to-intent.yml
      ;;
  esac
}

echo "bootstrap: applying layers [$(echo $layers | tr ' ' ',')] -> $target"
for l in $layers; do
  run_layer "$l"
done

cat <<EOF

bootstrap: done. Summary for $target:
  installed: $installed   overwritten: $overwritten   up-to-date: $skipped   conflicts: 0
Next (per SKILL.md):
  - 变更起编时从模板生成 00-intent.md / 00-governance.json / 04.5-coding-record.md
  - 若启用了 --guard，运行 scripts/install-hook-adapter 生成当前客户端 Hook，
    并执行 git config core.hooksPath .githooks
  - 在托管平台将 agent-governance 与项目测试设为 Required Check
EOF
exit 0
