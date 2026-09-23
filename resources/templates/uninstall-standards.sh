#!/usr/bin/env bash
# uninstall-standards — 一键卸载 dev-standards-bootstrap 落地物（v3.41.0，CHG-049）
#
# 用法: scripts/uninstall-standards [--dry-run] [--force]
#
# 三层分类（防误删是第一设计目标）：
#   Tier1 安装器运行时件 —— 直接删。重跑 bootstrap --core/--guard 即完整还原。
#   Tier2 安装器模板件 —— 头标记核验通过才删（agent-gate / 门禁 / __CHANGE_ID__ /
#        独立完整声明 / dev-standards-gate）；被用户改动或无标记 → 保留并报告。
#   Tier3 共享知识资产 —— AGENTS.md、CLAUDE.md、规范/方法论/总册/变更与缺陷历史、
#        合并型接线（.claude/.cursor/.gemini 配置）等可能承载他人内容的文件：
#        默认保留并清单报告；--force 也只是移动到 .uninstall-backup-<UTCts>/
#        （可整目录搬回），永不 rm。
#
# 零依赖：bash 3.2+、git。路径根遵循 .agent-governance.yml（与安装器同源）。
set -u

usage() { echo "usage: scripts/uninstall-standards [--dry-run] [--force]"; exit 2; }
DRY=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
    *) usage ;;
  esac
done

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "uninstall-standards: run inside a Git repository" >&2; exit 2; }
cd "$repo_root"

cfg_path() { # key default
  local k="$1" d="$2" v=""
  if [[ -f ".agent-governance.yml" ]]; then
    v=$(sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" .agent-governance.yml 2>/dev/null | head -1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$v" ]] || v="$d"
  printf '%s' "$v"
}
DOCS_DIR="${AGENT_GUARD_DOCS_DIR:-$(cfg_path docs docs)}"
SCRIPTS_DIR="${AGENT_GUARD_SCRIPTS_DIR:-$(cfg_path scripts scripts)}"
TESTS_DIR="${AGENT_GUARD_TESTS_DIR:-$(cfg_path tests tests)}"
GITHOOKS_DIR="${AGENT_GUARD_GITHOOKS_DIR:-$(cfg_path githooks .githooks)}"

REMOVED=0; KEPT=0; MOVED=0
BACKUP_DIR=".uninstall-backup-$(date -u +%Y%m%dT%H%M%SZ)"

note()  { printf '  %s\n' "$1"; }
act_rm() { # <path>
  [[ -e "$1" || -L "$1" ]] || return 0
  if [[ "$DRY" == 1 ]]; then note "would remove  $1"; else rm -rf "$1" 2>/dev/null || { note "WARN failed   $1 (remove manually)"; return 0; }; fi
  REMOVED=$((REMOVED+1))
}
act_mv() { # <path>  (Tier3 --force: backup-move, never rm)
  [[ -e "$1" || -L "$1" ]] || return 0
  local dest="$BACKUP_DIR/$(printf '%s' "$1" | sed 's#^\./##')"
  if [[ "$DRY" == 1 ]]; then note "would backup  $1 -> $dest"; else mkdir -p "$(dirname "$dest")" && mv "$1" "$dest" 2>/dev/null || { note "WARN failed   $1 (move manually)"; return 0; }; fi
  MOVED=$((MOVED+1))
}
has_marker() { # <file> <ERE>
  [[ -f "$1" ]] && grep -qE "$2" "$1" 2>/dev/null
}

echo "uninstall-standards: repo=$repo_root docs=$DOCS_DIR$([[ "$DRY" == 1 ]] && echo ' (DRY-RUN — nothing written)')"
if [[ "$FORCE" == 1 ]]; then echo "uninstall-standards: --force ON — Tier3 assets are BACKUP-MOVED to $BACKUP_DIR (never deleted)"; fi

# ---- Tier1: installer runtime (safe to delete; reinstall restores) ----------
# NOTE: tests/run-tests.sh and tests/audit-docs-consistency.sh are deliberately
# NOT here — run-tests is a MERGED extension point (user projects append their
# own T-sections), so both live in Tier3 (keep & report; --force backup-moves).
for f in "$SCRIPTS_DIR/agent-gate" "$SCRIPTS_DIR/stamp-provenance.sh" "$SCRIPTS_DIR/new-change" \
         "$SCRIPTS_DIR/session-gate.sh" "$SCRIPTS_DIR/install-hook-adapter" \
         "$SCRIPTS_DIR/check-standards-compliance.sh"; do
  act_rm "$f"
done
act_rm ".agent-state"
act_rm ".git/agent-governance"
act_rm "$SCRIPTS_DIR/uninstall-standards"   # self — removed last below
hp=$(git config core.hooksPath 2>/dev/null || true)
if [[ "$hp" == "$GITHOOKS_DIR" || "$hp" == "$repo_root/$GITHOOKS_DIR" ]]; then
  if [[ "$DRY" == 1 ]]; then note "would unset    core.hooksPath ($hp)"; else git config --unset core.hooksPath; fi
  REMOVED=$((REMOVED+1))
elif [[ -n "$hp" ]]; then
  note "keep          core.hooksPath=$hp (not $GITHOOKS_DIR — not ours to touch)"; KEPT=$((KEPT+1))
fi
# adapter full-file output (generated, owned)
[[ -f ".opencode/plugins/dev-standards-gate.js" ]] && { act_rm ".opencode/plugins/dev-standards-gate.js"; }

# ---- Tier2: installer templates — delete ONLY on marker match ---------------
tier2() { # <path> <marker-ERE> <label>
  if [[ ! -e "$1" ]]; then return 0; fi
  if has_marker "$1" "$2"; then
    act_rm "$1"
  else
    note "keep          $1 (marker '${3}' not found — modified or foreign; remove manually if certain)"
    KEPT=$((KEPT+1))
  fi
}
tier2 "$GITHOOKS_DIR/pre-commit" "agent-gate" "pre-commit hook"
tier2 "$GITHOOKS_DIR/pre-push"   "agent-gate" "pre-push hook"
tier2 "$GITHOOKS_DIR/commit-msg" "agent-gate" "commit-msg hook"
tier2 ".github/PULL_REQUEST_TEMPLATE.md" "门禁[1-5]|agent-gate" "PR template"
tier2 ".github/workflows/agent-governance.yml"  "agent-gate|audit-docs-consistency" "workflow"
tier2 ".github/workflows/artifact-pipeline.yml" "agent-gate|audit-docs-consistency" "workflow"
tier2 ".github/workflows/incident-to-intent.yml" "agent-gate|incident" "workflow"
# scaffold trees: each file must carry its installer marker; foreign files stay
if [[ -d "$DOCS_DIR/templates" ]]; then
  while IFS= read -r f; do
    case "$f" in
      */entry/*)   tier2 "$f" "__CHANGE_ID__" "entry scaffold" ;;
      */project/*) tier2 "$f" "独立完整声明|总册编号" "project scaffold" ;;
      *)           tier2 "$f" "agent-gate|stamp-provenance|audit-docs-consistency|__CHANGE_ID__|独立完整声明|总册编号|dev-standards-bootstrap" "template" ;;
    esac
  done < <(find "$DOCS_DIR/templates" -type f 2>/dev/null)
  [[ "$DRY" != 1 ]] && find "$DOCS_DIR/templates" -depth -type d -empty -delete 2>/dev/null
fi
if [[ -d "$DOCS_DIR/bugs/_templates" ]]; then
  while IFS= read -r f; do
    tier2 "$f" "缺陷文档组六件套|BUG-xxx" "bug scaffold"
  done < <(find "$DOCS_DIR/bugs/_templates" -type f 2>/dev/null)
  [[ "$DRY" != 1 ]] && find "$DOCS_DIR/bugs/_templates" -depth -type d -empty -delete 2>/dev/null
fi
[[ -d "$GITHOOKS_DIR" && "$DRY" != 1 ]] && find "$GITHOOKS_DIR" -depth -type d -empty -delete 2>/dev/null

# ---- Tier3: shared knowledge assets — keep (report); --force = backup-move ---
# These may carry user/project content that did not come from the installer.
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if [[ "$FORCE" == 1 ]]; then act_mv "$p"; else
    if [[ -e "$p" ]]; then note "keep          $p (shared asset — remove manually if truly unwanted)"; KEPT=$((KEPT+1)); fi
  fi
done <<EOF
AGENTS.md
CLAUDE.md
$DOCS_DIR/DEVELOPMENT_STANDARDS.md
$DOCS_DIR/STANDARDS_CHANGELOG.md
$DOCS_DIR/METHODOLOGY.md
$DOCS_DIR/README.md
$DOCS_DIR/bugfix-log.md
$DOCS_DIR/06.5-deployment-config.md
$DOCS_DIR/06-delivery-summary.md
$TESTS_DIR/audit-docs-consistency.sh
$TESTS_DIR/run-tests.sh
$DOCS_DIR/methodologies
$DOCS_DIR/project
$DOCS_DIR/changes
$DOCS_DIR/bugs
.agent-governance.yml
.claude/settings.json
.cursor/hooks.json
.gemini/settings.json
EOF

# ---- summary ----------------------------------------------------------------
echo
echo "uninstall-standards: removed=$REMOVED backup_moved=$MOVED kept=$KEPT"
if [[ "$MOVED" -gt 0 ]]; then echo "  backup location: $BACKUP_DIR (move files back to restore)"; fi
echo "  manual follow-ups (merged/derived, not file-level):"
echo "    - .claude/.cursor/.gemini settings keep our hook entries — strip the dev-standards blocks or rerun install-hook-adapter after reinstall"
echo "    - README badges/sections mentioning dev-standards were not edited"
echo "  reinstall anytime: re-run bootstrap --core/--guard"
echo "  note: this uninstaller self-removes on a real (non-dry) run — rerun needs a reinstall first"
exit 0
