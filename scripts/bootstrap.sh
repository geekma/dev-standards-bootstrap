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
  --core       核心文档层: AGENTS.md, DEVELOPMENT_STANDARDS.md, STANDARDS_CHANGELOG.md, METHODOLOGY.md,
               methodologies/, bugfix-log.md, docs/bugs/_templates/ (6),
               docs/06.5-deployment-config.md, docs/06-delivery-summary.md
               (八类最低文档集里原先无模板的两类，CHG-004),
               tests/audit-docs-consistency.sh (通用层审计)
  --claude     CLAUDE.md 一行导入
  --ci         工程化兜底: PULL_REQUEST_TEMPLATE.md, scripts/check-standards-compliance.sh
  --guard      强制执行包: scripts/agent-gate, .githooks/ (pre-commit/pre-push/commit-msg),
               .github/workflows/agent-governance.yml, scripts/install-hook-adapter,
               .agent-governance.yml, tests/run-tests.sh (治理自测试随强制包, §2.17.4)
  --pipeline   管线自动化: artifact-pipeline.yml, incident-to-intent.yml
  --all        以上全部
  --upgrade    升级已接入仓库：治理自有文件（规范/方法论/模板/脚本/hooks/workflows/tests）
               更新到本 Skill 携带版本；跳过 live/用户文件（bugfix-log、06-delivery-summary、
               06.5、.agent-governance.yml、docs/changes/**、docs/bugs/BUG-*/）；随后重跑自动接线。
               升级前请先提交目标仓库（git history 即备份）。打印版本迁移。
  --force      覆盖目标仓库中内容不同的既有文件（默认冲突时展示 diff 并拒绝）
  -h, --help   本帮助

任何层遇到冲突文件时退出 2（fail-closed），已复制的文件保留，重跑 --force 覆盖。
变更起编时使用的 per-change 模板（00-intent / 00-governance / coding-record）不在
本清单：它们随变更号动态落 docs/changes/<变更号>/，由 SKILL.md 指导生成。
EOF
}

force=false
upgrade=false
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
    --upgrade)  layers="core claude ci guard pipeline"; upgrade=true ;;
    --force)    force=true ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "bootstrap: unknown flag '$arg'" >&2; usage >&2; exit 2 ;;
    *)          target="$arg" ;;
  esac
done
[[ -n "$layers" ]] || layers="core"
[[ -n "$target" ]] || target="$PWD"

# CHG-014 / REQ-073: --upgrade first self-updates the skill source (when it is
# a git clone with a clean tree), so "全面升级" = source latest + target sync.
# If the pull actually changed files, re-exec so the NEW installer code runs
# (bash must never execute a script file that changed underneath it).
if [[ "$upgrade" == true ]]; then
  if [[ -d "$SKILL_ROOT/.git" ]] && command -v git >/dev/null 2>&1; then
    if [[ -n "$(git -C "$SKILL_ROOT" status --porcelain 2>/dev/null)" ]]; then
      echo "NOTE       skill repo has uncommitted changes — skipping self-update; run with a clean skill repo for a full upgrade" >&2
    else
      before=$(git -C "$SKILL_ROOT" rev-parse HEAD 2>/dev/null || true)
      if GIT_TERMINAL_PROMPT=0 git -C "$SKILL_ROOT" pull --ff-only -q 2>/dev/null; then
        after=$(git -C "$SKILL_ROOT" rev-parse HEAD 2>/dev/null || true)
        if [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
          echo "self-update skill repo: ${before:0:9} -> ${after:0:9} (re-executing with updated installer)"
          exec bash "$SCRIPT_DIR/bootstrap.sh" "$@"
        fi
      else
        echo "NOTE       skill repo self-update (git pull) failed — continuing with the local version; update the skill repo manually for a full upgrade" >&2
      fi
    fi
  fi
fi

[[ -d "$target" ]] || { echo "bootstrap: target is not a directory: $target" >&2; exit 2; }

# install_file <dest_rel> <src_rel> [chmod_mode]
# CHG-013: live/user-owned files are NEVER touched by --upgrade (they hold
# accumulated data: FU ledger, bug index, CFG records, user's verify command).
LIVE_SKIP=(
  "docs/bugfix-log.md"
  "docs/06-delivery-summary.md"
  "docs/06.5-deployment-config.md"
  ".agent-governance.yml"
)

install_file() {
  local dest_rel="$1" src_rel="$2" chmod_mode="${3:-}"
  local dest="$target/$dest_rel" src="$SKILL_ROOT/$src_rel"
  [[ -f "$src" ]] || { echo "bootstrap: MISSING SOURCE $src_rel (skill repo broken) — partial install: installed=$installed" >&2; exit 2; }
  if [[ "$upgrade" == true ]]; then
    for skip in "${LIVE_SKIP[@]}"; do
      if [[ "$dest_rel" == "$skip" ]]; then
        echo "live (skip)  $dest_rel"
        skipped=$(( skipped + 1 ))
        return 0
      fi
    done
  fi
  if [[ -e "$dest" ]]; then
    if cmp -s "$dest" "$src"; then
      echo "up to date   $dest_rel"
      skipped=$(( skipped + 1 ))
      return 0
    fi
    if [[ "$upgrade" == true ]]; then
      echo "updated      $dest_rel (upgrade)"
      upgraded=$(( upgraded + 1 ))
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      [[ -n "$chmod_mode" ]] && chmod "$chmod_mode" "$dest"
      return 0
    fi
    if [[ "$force" != true ]]; then
      echo "CONFLICT     $dest_rel (different content; re-run with --force to overwrite)" >&2
      diff -u --label "$dest_rel (existing)" --label "$src_rel (template)" "$dest" "$src" >&2 || true
      echo "bootstrap: aborting — partial install: installed=$installed up-to-date=$skipped; re-run with --force to complete" >&2
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
upgraded=0

run_layer() {
  local layer="$1"
  case "$layer" in
    core)
      install_file AGENTS.md resources/AGENTS.md
      install_file docs/DEVELOPMENT_STANDARDS.md resources/DEVELOPMENT_STANDARDS.md
      install_file docs/STANDARDS_CHANGELOG.md resources/STANDARDS_CHANGELOG.md
      install_file docs/METHODOLOGY.md resources/METHODOLOGY.md
      for m in development.md data-structures.md state-trigger-audit.md; do
        install_file "docs/methodologies/$m" "resources/methodologies/$m"
      done
      install_file docs/bugfix-log.md resources/templates/bugfix-log.md
      for b in bug-diagnosis.md bug-impact.md bug-test-plan.md bug-matrix.md bug-config.md bug-tasks.md; do
        install_file "docs/bugs/_templates/$b" "resources/templates/$b"
      done
      # 八类最低文档集（规范 §1.1）中此前既无模板、也无门禁的两类（CHG-004 / BUG-002）：
      # 未命中时也必须存在并显式声明"未命中，不适用"——不能靠"不建文件"来表达不适用。
      for t in 06.5-deployment-config.md 06-delivery-summary.md; do
        install_file "docs/$t" "resources/templates/$t"
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
if [[ "$upgrade" == true ]]; then
  carried=$(grep -oE '规范版本：v[0-9.]+' "$SKILL_ROOT/resources/DEVELOPMENT_STANDARDS.md" 2>/dev/null | head -1 | grep -oE '[0-9.]+')
  installed_ver=$(grep -oE '规范版本：v[0-9.]+' "$target/docs/DEVELOPMENT_STANDARDS.md" 2>/dev/null | head -1 | grep -oE '[0-9.]+' || true)
  echo "upgrade: v${installed_ver:-not-installed} -> v${carried:-unknown}"
  # CHG-015: uncommitted changes + upgrade = overwrite data-loss risk → block
  # unless explicitly forced. Non-git targets get a prominent warning instead
  # (nothing to roll back, but --upgrade is an explicit user action there).
  if [[ -d "$target/.git" ]] && command -v git >/dev/null 2>&1; then
    if [[ -n "$(git -C "$target" status --porcelain 2>/dev/null)" ]]; then
      if [[ "$force" != true ]]; then
        echo "bootstrap: target has uncommitted changes — commit first, or pass --force to upgrade anyway (git history preserves customization)" >&2
        exit 2
      fi
      echo "WARNING     --force on a dirty target tree — uncommitted customizations may be overwritten" >&2
    fi
  elif [[ ! -d "$target/.git" ]]; then
    echo "WARNING     target is not a git repository — upgraded files cannot be rolled back" >&2
  fi
fi
for l in $layers; do
  run_layer "$l"
done

# CHG-012: guard auto-wiring — after install, wire everything that can be
# wired without asking. Respect existing user config; never overwrite.
auto_wire_guard() {
  # 1) hooksPath: three states — unset -> set; already .githooks -> skip;
  #    something else -> DO NOT touch, print manual hint (OQ-1).
  if [[ -d "$target/.git" ]] && command -v git >/dev/null 2>&1; then
    cur=$(git -C "$target" config --get core.hooksPath || true)
    if [[ -z "$cur" ]]; then
      git -C "$target" config core.hooksPath .githooks
      echo "auto-wired   git config core.hooksPath .githooks"
    elif [[ "$cur" == ".githooks" ]]; then
      echo "auto-wired   core.hooksPath already .githooks (skipped)"
    else
      echo "NOTE         core.hooksPath is '$cur' (custom) — left untouched; wire .githooks manually if intended" >&2
    fi
  fi
  # 2) client hook adapter: only run when a supported client is detected in
  #    THIS shell's env (the adapter itself exits 0 even without a client, so
  #    its exit code alone would false-positive — check the env here first).
  if [[ -f "$target/scripts/install-hook-adapter" ]]; then
    client=""
    if [[ "${CLAUDECODE:-}" == 1 ]]; then client=claude
    elif [[ -n "${CURSOR_AGENT:-}" || -n "${CURSOR_TRACE_ID:-}" ]]; then client=cursor
    elif [[ "${GEMINI_CLI:-}" == 1 ]]; then client=gemini
    fi
    if [[ -n "$client" ]]; then
      ok=0
      if (cd "$target" && bash scripts/install-hook-adapter "$client"); then
        for f in .claude/settings.json .cursor/hooks.json .gemini/settings.json; do
          [[ -f "$target/$f" ]] && ok=1
        done
      fi
      if [[ "$ok" == 1 ]]; then
        echo "auto-wired   client hook adapter generated ($client)"
      else
        echo "NOTE         adapter generation did not produce a config for $client — run scripts/install-hook-adapter manually" >&2
      fi
    else
      echo "NOTE         no supported coding client detected in this shell — run scripts/install-hook-adapter inside your client; Git hooks + CI still enforce" >&2
    fi
  fi
  # 3) verification command autodetect: replace the placeholder only; user
  #    customizations are never touched. Env var keeps highest priority at runtime.
  local yml="$target/.agent-governance.yml" detected=""
  if [[ -f "$yml" ]] && grep -q '<replace-with-project-test-command>' "$yml"; then
    if [[ -f "$target/package.json" ]] && grep -q '"test"[[:space:]]*:' "$target/package.json"; then detected="npm test"
    elif [[ -f "$target/Makefile" ]] && grep -qE '^test[[:space:]]*:' "$target/Makefile"; then detected="make test"
    elif [[ -f "$target/pom.xml" ]]; then detected="mvn test"
    elif [[ -f "$target/go.mod" ]]; then detected="go test ./..."
    elif [[ -f "$target/pyproject.toml" || -f "$target/pytest.ini" ]]; then detected="pytest -q"
    elif [[ -f "$target/Cargo.toml" ]]; then detected="cargo test"
    fi
    if [[ -n "$detected" ]]; then
      tmpf=$(mktemp 2>/dev/null) || tmpf=""
      if [[ -n "$tmpf" ]]; then
        # single-quoted sed program; the detected command is appended as a
        # separate argv piece to avoid any quote-escaping in the pattern
        sed 's|verification_command: "<replace-with-project-test-command>"|verification_command: "__DETECTED__"|' "$yml" > "$tmpf" \
          && sed "s|__DETECTED__|$detected|" "$tmpf" > "$tmpf.2" \
          && mv "$tmpf.2" "$yml" \
          && echo "auto-wired   verification command detected -> $detected (edit .agent-governance.yml to change; AGENT_GUARD_VERIFY_COMMAND env overrides)"
        rm -f "$tmpf" "$tmpf.2"
        grep -q '<replace-with-project-test-command>' "$yml" && echo "NOTE         placeholder replacement FAILED — set ci.verification_command manually" >&2
      fi
    else
      echo "NOTE         could not detect a test command — set ci.verification_command in .agent-governance.yml (or AGENT_GUARD_VERIFY_COMMAND)" >&2
    fi
  fi
  # 4) platform-side step cannot be automated via files — print exact hint.
  echo "manual       GitHub: mark 'agent-governance' workflow as a required check (repo Settings -> Branches -> Branch protection, or via gh api)"
}
case " $layers " in
  *" guard "*) auto_wire_guard ;;
esac
[[ "$upgrade" == true ]] && echo "upgrade: governance files synced to carried version; live/user files untouched"

cat <<EOF

bootstrap: done. Summary for $target:
  installed: $installed   overwritten: $overwritten   upgraded: $upgraded   up-to-date: $skipped   conflicts: 0
Next (per SKILL.md):
  - 变更起编时从模板生成 00-intent.md / 00-governance.json / 04.5-coding-record.md
  - --guard 已自动接线 hooksPath / 客户端适配器 / 验证命令探测（见上方 auto-wired 行）
  - 剩余手工仅平台侧：在托管平台将 agent-governance 与项目测试设为 Required Check
EOF
exit 0
