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
#     例外（v3.50.0）：AGENTS.md 永不覆盖用户内容——有托管标记=只更新标记块
#     （用户区块保留）；无标记差异=保留原文（kept），--force 不越，删除重装可刷新。
#     安装清单（v3.51.0）：<target>/.dev-standards-manifest 记录每文件自安装基线
#     （cksum）——--upgrade 时用户改过的文件一律 kept（--force 显式越），legacy 仓
#     差异文件保守 kept（--force 一次同步并采纳清单）。
#   - 零依赖：bash 3.2+ + cp + diff（macOS/Linux）。
#   - 分层 flags 与 SKILL.md 步骤 4 的可选增强一一对应。
#   - 路径根可配置（v3.15.0）：默认值即历史写死值，不传参 = 行为不变。
#
# Usage:
#   bash scripts/bootstrap.sh [target_root]
#   bash scripts/bootstrap.sh --core|--claude|--ci|--guard|--pipeline|--all [--force] [target_root]
#   bash scripts/bootstrap.sh --docs-dir <path> [--scripts-dir <p>] [--tests-dir <p>] \
#                            [--githooks-dir <p>] [flags] [target_root]
#
# target_root 缺省为当前目录；--core 为默认层（核心文档层）。
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [flags] [target_root]

Flags (layers; default --core when none given):
  --core       核心文档层: AGENTS.md, DEVELOPMENT_STANDARDS.md, CLAUSE_REGISTRY.md, STANDARDS_CHANGELOG.md, METHODOLOGY.md,
               methodologies/ (5, 含 project-masters.md v3.35.0), bugfix-log.md, <docs>/bugs/_templates/ (6),
               <docs>/templates/project/ (总册 12 册 + 评审模板, v3.35.0),
               <docs>/templates/entry/ (变更入口骨架 8 件, v3.38.0; v3.52.0 起 8 件含 00.5),
               <docs>/README.md (一页文档地图, v3.37.0),
               <docs>/06.5-deployment-config.md, <docs>/06-delivery-summary.md
               (八类最低文档集里原先无模板的两类，CHG-004),
               <tests>/audit-docs-consistency.sh (通用层审计)
  --claude     CLAUDE.md 一行导入
  --ci         工程化兜底: PULL_REQUEST_TEMPLATE.md, <scripts>/check-standards-compliance.sh
  --guard      强制执行包: <scripts>/agent-gate, <scripts>/stamp-provenance.sh (文件溯源盖章, v3.17.0),
               <scripts>/new-change (变更入口骨架脚手架, v3.38.0),
               <scripts>/session-gate.sh + <scripts>/install-hook-adapter (会话内执法, v3.28.0),
               <githooks>/ (pre-commit/pre-push/commit-msg),
               <scripts>/uninstall-standards (一键卸载: 三层分类+标记核验+共享资产备份移动, v3.41.0),
               <github>/workflows/agent-governance.yml,
               .agent-governance.yml, <tests>/run-tests.sh (治理自测试随强制包, §2.17.4)
  --pipeline   管线自动化: artifact-pipeline.yml, incident-to-intent.yml
  --all        以上全部
  --upgrade    升级已接入仓库：治理自有文件（规范/方法论/模板/脚本/hooks/workflows/tests）
               更新到本 Skill 携带版本；跳过 live/用户文件（bugfix-log、06-delivery-summary、
               06.5、.agent-governance.yml、<docs>/changes/**、<docs>/bugs/BUG-*/）；随后重跑自动接线。
               AGENTS.md 托管块合并（用户区块保留，v3.50.0）。**安装清单归因（v3.51.0）**：
               安装后未改→updated；用户改过→kept 保留（--force 显式越）；legacy 无清单→
               差异文件保守 kept+提示（--force 一次同步并采纳清单）。
               升级前请先提交目标仓库（git history 即备份）。打印版本迁移。
               **只升级用户未显式指定的层**：`--core --upgrade` 就只升 core；一个层 flag 都不给
               才按全量 5 层升级（v3.16.0 修正：此前会静默扩为全量）。
  --check      只读三处版本比对并退出：Skill 携带版本 / Skill 源 vs 远端 / 目标仓已装版本。
               有漂移即 exit 1（可入 CI），无漂移 exit 0。不写任何文件。
  --self-update 只更新 Skill 自身的 git 克隆（pull --ff-only）并退出，不动任何目标仓库。
               用于回答"我的 Skill 副本是不是落后了"——这是与"目标仓要不要升级"不同的问题。
  --derived-report 只读列出从本 Skill 派生出去的 Skill（同目录下声明了 derived_from 的）：
               路径 / derived_from / derived_at / derived_from_version + 本 Skill 携带版本。
               用于判断派生资产是否需要跟上。不写任何文件。
  --force      覆盖目标仓库中内容不同的既有文件（默认冲突时展示 diff 并拒绝）。
               **不越过派生保护**——--force 的语义是"覆盖内容不同的既有文件"，
               不是"覆盖别人派生出来的资产"。
               **对 AGENTS.md 不越（v3.50.0）**——托管块合并/用户版保留语义见 --core。
               **对用户改过的文件（v3.51.0 清单核对）**：--force 是唯一显式覆盖通道，
               覆盖后刷新清单基线；无 --force 一律 kept。
  -h, --help   本帮助

自进化契约（v3.16.0）：派生 Skill 在自己的 SKILL.md frontmatter 声明
  derived_from: dev-standards-bootstrap
后，安装器与升级的**每一条**写入路径都跳过该目录并打印 `derived (skip)`。
源仓不写入该标记，也绝不回收到派生资产。

Path roots (v3.15.0) — 只配置**目录根**：
  --docs-dir <p>       文档根            默认 docs
  --scripts-dir <p>    治理脚本根        默认 scripts
  --tests-dir <p>      测试/审计脚本根   默认 tests
  --githooks-dir <p>   Git Hook 根       默认 .githooks
  解析优先级：CLI flag > 环境变量 AGENT_GUARD_<KEY>_DIR > 目标仓 .agent-governance.yml
              > 内置默认（= 历史写死值）。**不传即用默认，行为与升级前逐字节一致。**
  非默认根会同步写入目标仓 .agent-governance.yml 的 paths.*，并改写模板**内部**的
  路径引用（hooks/adapter 按路径调门禁、workflows 与规范模板按路径引用文档），
  否则门禁会按默认根去找文件而与安装落点不一致（该文件不存在时会一并落一份）。
  刻意不可配置：`.github/`（平台强制位置，换名即流水线失效）与全部契约名
  （AGENTS.md 名、agent-gate 落点名、变更 15 件产物名、缺陷六件套名、
  required-check 名）——可配即失去跨仓比对与迁移能力。

任何层遇到冲突文件时退出 2（fail-closed），已复制的文件保留，重跑 --force 覆盖。
变更起编使用的入口骨架落 <docs>/templates/entry/（8 件）、沟通稿正式模板落
<docs>/templates/communication.md（v3.52.0）；它们由 scripts/new-change 与 SKILL.md
指导使用，不随变更号动态落盘。
EOF
}

force=false
upgrade=false
check_mode=false
self_update=false
derived_report=false
layers=""
layers_explicit=false
target=""
opt_docs=""
opt_scripts=""
opt_tests=""
opt_githooks=""
pending=""
for arg in "$@"; do
  # 取值型 flag：消费紧随其后的一个参数（保持 "$@" 原样，供 --upgrade 重入使用）
  if [[ -n "$pending" ]]; then
    case "$pending" in
      docs)     opt_docs="$arg" ;;
      scripts)  opt_scripts="$arg" ;;
      tests)    opt_tests="$arg" ;;
      githooks) opt_githooks="$arg" ;;
    esac
    pending=""
    continue
  fi
  case "$arg" in
    --core)     layers="$layers core";     layers_explicit=true ;;
    --claude)   layers="$layers claude";   layers_explicit=true ;;
    --ci)       layers="$layers ci";       layers_explicit=true ;;
    --guard)    layers="$layers guard";    layers_explicit=true ;;
    --pipeline) layers="$layers pipeline"; layers_explicit=true ;;
    --all)      layers="core claude ci guard pipeline"; layers_explicit=true ;;
    # D4 (v3.16.0): --upgrade must NOT clobber an explicit layer selection.
    # It used to rewrite `layers` unconditionally, so `--core --upgrade` silently
    # became a full 5-layer install. The full set is now applied after parsing,
    # and only when the user named no layer at all.
    --upgrade)  upgrade=true ;;
    --check)          check_mode=true ;;
    --self-update)    self_update=true ;;
    --derived-report) derived_report=true ;;
    --force)    force=true ;;
    --docs-dir)     pending=docs ;;
    --scripts-dir)  pending=scripts ;;
    --tests-dir)    pending=tests ;;
    --githooks-dir) pending=githooks ;;
    --docs-dir=*)     opt_docs="${arg#*=}" ;;
    --scripts-dir=*)  opt_scripts="${arg#*=}" ;;
    --tests-dir=*)    opt_tests="${arg#*=}" ;;
    --githooks-dir=*) opt_githooks="${arg#*=}" ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "bootstrap: unknown flag '$arg'" >&2; usage >&2; exit 2 ;;
    *)          target="$arg" ;;
  esac
done
if [[ -n "$pending" ]]; then
  echo "bootstrap: --${pending}-dir requires a path argument" >&2
  exit 2
fi
if [[ "$upgrade" == true && "$layers_explicit" != true ]]; then
  layers="core claude ci guard pipeline"
fi
[[ -n "$layers" ]] || layers="core"
[[ -n "$target" ]] || target="$PWD"

# --- shared readers (v3.16.0) -----------------------------------------------
# Three version sources, read the same way everywhere:
#   carried   — the version THIS skill copy ships (standards footer, sole authority)
#   installed — what the target repo currently has
#   source    — whether the skill checkout itself is behind its git upstream
carried_version() {
  grep -oE '规范版本：v[0-9.]+' "$SKILL_ROOT/resources/DEVELOPMENT_STANDARDS.md" 2>/dev/null \
    | head -1 | grep -oE '[0-9.]+' || true
}
installed_version() { # <target-root> <docs-dir>
  grep -oE '规范版本：v[0-9.]+' "$1/$2/DEVELOPMENT_STANDARDS.md" 2>/dev/null \
    | head -1 | grep -oE '[0-9.]+' || true
}
# Numeric dotted compare, up to 3 fields, BSD/GNU-portable (no `sort -V`).
# ver_ge a b -> success when a >= b.
ver_ge() {
  local a="$1" b="$2" i x y
  local -a A B
  IFS='.' read -r -a A <<< "$a" 2>/dev/null || A=()
  IFS='.' read -r -a B <<< "$b" 2>/dev/null || B=()
  for i in 0 1 2; do
    x="${A[$i]:-0}"; y="${B[$i]:-0}"
    [[ "$x" =~ ^[0-9]+$ ]] || x=0
    [[ "$y" =~ ^[0-9]+$ ]] || y=0
    (( 10#$x > 10#$y )) && return 0
    (( 10#$x < 10#$y )) && return 1
  done
  return 0
}
# skill_source_state -> up-to-date | behind:<n> | diverged | unknown:<why>
# Never mutates the checkout: fetch is read-only, and a dirty tree short-circuits
# (we must not compare, let alone pull, on top of uncommitted local evolution).
skill_source_state() {
  if [[ ! -d "$SKILL_ROOT/.git" ]]; then printf 'unknown:not-a-git-checkout'; return 0; fi
  if ! command -v git >/dev/null 2>&1; then printf 'unknown:git-not-found'; return 0; fi
  if [[ -n "$(git -C "$SKILL_ROOT" status --porcelain 2>/dev/null)" ]]; then
    printf 'unknown:working-tree-dirty'; return 0
  fi
  GIT_TERMINAL_PROMPT=0 git -C "$SKILL_ROOT" fetch --quiet 2>/dev/null \
    || { printf 'unknown:fetch-failed'; return 0; }
  git -C "$SKILL_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 \
    || { printf 'unknown:no-upstream'; return 0; }
  local behind ahead
  behind=$(git -C "$SKILL_ROOT" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
  ahead=$(git -C "$SKILL_ROOT" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  if [[ "$behind" -gt 0 && "$ahead" -gt 0 ]]; then printf 'diverged'
  elif [[ "$behind" -gt 0 ]]; then printf 'behind:%s' "$behind"
  else printf 'up-to-date'; fi
}
# --- Agent self-evolution contract (v3.16.0) --------------------------------
# A skill derived from this one declares `derived_from:` in its SKILL.md
# frontmatter. That voluntary marker is the ONLY protection it has: the source
# repo never writes it, and the installer never writes INTO such a directory.
# Rationale: derived skills are optimised for one project/agent and evolve
# independently — overwriting them destroys work this repo cannot reconstruct.
#
# Parse the FRONTMATTER ONLY. A whole-file grep would also match the worked
# example inside SKILL.md's own "Agent 自进化契约" section — which made this
# report the source repo as a derived skill of itself (and would have made the
# write guard refuse a legitimate install into this very repo).
frontmatter() { # <skill-md> -> frontmatter block only
  local f="$1"
  [[ -f "$f" ]] || return 0
  awk 'NR==1 && /^---[[:space:]]*$/ { infm=1; next }
       infm && /^---[[:space:]]*$/ { exit }
       infm { print }' "$f" 2>/dev/null
}
fm_get() { # <skill-md> <key> -> frontmatter value, or empty
  local f="$1" k="$2"
  frontmatter "$f" | sed -nE "s/^${k}:[[:space:]]*//p" 2>/dev/null \
    | head -n 1 | tr -d "[:space:]\"'" || true
}
derived_of() { # <dir> -> declared derived_from value, or empty
  fm_get "$1/SKILL.md" derived_from
}
derived_skills_in() { # <parent-dir> -> "path|derived_from|derived_at|derived_from_version"
  local d="$1" sub f df da dv
  [[ -d "$d" ]] || return 0
  for sub in "$d"/*/; do
    [[ -d "$sub" ]] || continue
    f="$sub/SKILL.md"
    [[ -f "$f" ]] || continue
    df=$(derived_of "${sub%/}")
    [[ -n "$df" ]] || continue
    da=$(fm_get "$f" derived_at)
    dv=$(fm_get "$f" derived_from_version)
    printf '%s|%s|%s|%s\n' "${sub%/}" "$df" "${da:-未声明}" "${dv:-未声明}"
  done
  return 0
}

# --- --self-update (v3.16.0, D3) --------------------------------------------
# Pull the skill checkout itself and nothing else. Exists because --upgrade
# conflates two different questions ("is my skill copy current?" vs "is this
# target repo current?"); --check answers both, --self-update acts on the first.
if [[ "$self_update" == true ]]; then
  st=$(skill_source_state)
  echo "self-update: skill dir   $SKILL_ROOT"
  echo "self-update: carried     v$(carried_version)"
  case "$st" in
    up-to-date)
      echo "self-update: source      already up to date"
      exit 0 ;;
    behind:*)
      echo "self-update: source      behind upstream by ${st#behind:} commit(s) — pulling"
      if GIT_TERMINAL_PROMPT=0 git -C "$SKILL_ROOT" pull --ff-only -q 2>/dev/null; then
        echo "self-update: pulled      now carrying v$(carried_version)"
        exit 0
      fi
      echo "self-update: pull failed — resolve manually: git -C \"$SKILL_ROOT\" pull" >&2
      exit 1 ;;
    diverged)
      echo "self-update: source      diverged from upstream (local commits + remote commits) — resolve manually: git -C \"$SKILL_ROOT\" pull --rebase" >&2
      exit 1 ;;
    *)
      echo "self-update: source      cannot compare (${st#unknown:}) — reinstall via git clone to enable self-update" >&2
      exit 1 ;;
  esac
fi

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
  else
    # D1 (v3.15.0): a non-git install (the common case for a copied Skill dir)
    # used to skip self-update in total silence while still reporting success —
    # the user believed the upgrade ran. Say it out loud instead.
    if [[ ! -d "$SKILL_ROOT/.git" ]]; then
      echo "NOTE       self-update unavailable: skill dir is not a git checkout ($SKILL_ROOT) — using the local copy as-is. Reinstall via git clone, or run with --from-remote <url>, for a full upgrade." >&2
    else
      echo "NOTE       self-update unavailable: git not found on PATH — using the local copy as-is." >&2
    fi
  fi
fi

[[ -d "$target" ]] || { echo "bootstrap: target is not a directory: $target" >&2; exit 2; }

# --- path roots (v3.15.0) ---------------------------------------------------
# Directory ROOTS are configurable. Each built-in default IS the historical
# hardcoded value, so "flag not passed" == "byte-identical behaviour to before".
# Precedence: CLI flag > AGENT_GUARD_<KEY>_DIR env > target .agent-governance.yml
#             > built-in default.
cfg_path() { # key default yml-file
  local k="$1" d="$2" f="${3:-}" v=""
  if [[ -n "$f" && -f "$f" ]]; then
    v=$(sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" "$f" 2>/dev/null \
        | head -n 1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$v" ]] || v="$d"
  printf '%s' "$v"
}
GOV_YML="$target/.agent-governance.yml"
DOCS_DIR="${opt_docs:-${AGENT_GUARD_DOCS_DIR:-$(cfg_path docs docs "$GOV_YML")}}"
SCRIPTS_DIR="${opt_scripts:-${AGENT_GUARD_SCRIPTS_DIR:-$(cfg_path scripts scripts "$GOV_YML")}}"
TESTS_DIR="${opt_tests:-${AGENT_GUARD_TESTS_DIR:-$(cfg_path tests tests "$GOV_YML")}}"
GITHOOKS_DIR="${opt_githooks:-${AGENT_GUARD_GITHOOKS_DIR:-$(cfg_path githooks .githooks "$GOV_YML")}}"

# --- --derived-report (v3.16.0) ---------------------------------------------
# Read-only inventory of the skills derived from this one. Purpose: make the
# self-evolution contract visible — "which of my assets are derived, on what
# basis, and has the source moved on?" — without ever writing to them.
if [[ "$derived_report" == true ]]; then
  skills_root=$(dirname "$SKILL_ROOT")
  echo "derived-report: skills root $skills_root"
  echo "derived-report: carried     v$(carried_version)"
  rep=$(derived_skills_in "$skills_root")
  if [[ -z "$rep" ]]; then
    echo "derived        (none declares derived_from under $skills_root)"
  else
    while IFS='|' read -r p df da dv; do
      [[ -n "$p" ]] || continue
      printf 'derived        %s\n' "$p"
      printf '               derived_from=%s  derived_at=%s  derived_from_version=%s\n' "$df" "$da" "$dv"
    done <<< "$rep"
  fi
  exit 0
fi

# --- --check (v3.16.0, D3) --------------------------------------------------
# Read-only three-way version report. --upgrade only ever compared the TARGET
# repo against the carried version; it never asked whether the skill copy itself
# was stale. Answer both, exit non-zero on drift so this can gate CI.
if [[ "$check_mode" == true ]]; then
  carried=$(carried_version)
  installed=$(installed_version "$target" "$DOCS_DIR")
  st=$(skill_source_state)
  drift=0
  printf 'check: carried    v%s   (skill: %s)\n' "${carried:-unknown}" "$SKILL_ROOT"
  case "$st" in
    up-to-date)
      printf 'check: skill      up to date with upstream\n' ;;
    behind:*)
      printf 'check: skill      BEHIND upstream by %s commit(s) — run --self-update\n' "${st#behind:}"; drift=1 ;;
    diverged)
      printf 'check: skill      DIVERGED from upstream — resolve manually\n'; drift=1 ;;
    *)
      printf 'check: skill      cannot compare (%s)\n' "${st#unknown:}" ;;
  esac
  if [[ -z "$installed" ]]; then
    printf 'check: target     not installed (%s/%s/DEVELOPMENT_STANDARDS.md missing)\n' "$target" "$DOCS_DIR"
    drift=1
  elif [[ "$installed" == "$carried" ]]; then
    printf 'check: target     v%s   up to date\n' "$installed"
  elif ver_ge "$installed" "$carried"; then
    printf 'check: target     v%s   AHEAD of this skill (v%s) — skill copy is stale\n' "$installed" "$carried"
    drift=1
  else
    printf 'check: target     v%s -> v%s   UPGRADE AVAILABLE (run --upgrade)\n' "$installed" "$carried"
    drift=1
  fi
  if [[ "$drift" -eq 0 ]]; then
    echo "check: in sync"
    exit 0
  fi
  echo "check: drift detected" >&2
  exit 1
fi

# --- derived-asset write guard (v3.16.0) ------------------------------------
# The contract says the installer never writes INTO a derived skill: its own
# evolution would be overwritten and this repo cannot reconstruct it. Hard
# refusal — `--force` deliberately does NOT override it (--force means
# "overwrite files with different content", not "overwrite someone's asset").
TARGET_DERIVED=$(derived_of "$target")
if [[ -n "$TARGET_DERIVED" ]]; then
  echo "bootstrap: refusing to install into a derived skill directory" >&2
  echo "bootstrap:   target       $target" >&2
  echo "bootstrap:   derived_from $TARGET_DERIVED" >&2
  echo "bootstrap: derived skills evolve on their own and are never overwritten by their source (standards §1.1, v3.16.0). --force does not override this." >&2
  exit 2
fi

# --- in-template path substitution (v3.15.0) --------------------------------
# A non-default root changes paths *inside* the templates too: Git hooks and the
# client adapter invoke the gate by path, and the workflows / standards templates
# reference the docs tree. Substituting at install time keeps the runtime free of
# config parsing — and the comparison below runs against the SUBSTITUTED source,
# so idempotency still holds (comparing against the raw template would report
# "updated" on every single --upgrade).
PATHS_CUSTOM=0
if [[ "$DOCS_DIR" != "docs" || "$SCRIPTS_DIR" != "scripts" || "$TESTS_DIR" != "tests" || "$GITHOOKS_DIR" != ".githooks" ]]; then
  PATHS_CUSTOM=1
fi
transform_src() { # src -> stdout
  # `.agent-governance.yml` carries the roots *themselves* (the `paths:` block,
  # plus the derived change_root / bugs_root). The generic rules below all
  # require a trailing "/", so none of them can match `  docs: docs` — without
  # this branch the installed file would differ from transform_src(template),
  # and the NEXT run's same_as_src() would see "template vs pinned" and abort
  # with CONFLICT (bootstrap is contractually idempotent, so that is a bug, not
  # a warning). Pin the six keys here instead of patching the file afterwards.
  if [[ "${1##*/}" == "agent-governance.yml" ]]; then
    sed -E \
      -e "s|^([[:space:]]*docs:[[:space:]]*)[^#]*|\1${DOCS_DIR} |" \
      -e "s|^([[:space:]]*scripts:[[:space:]]*)[^#]*|\1${SCRIPTS_DIR} |" \
      -e "s|^([[:space:]]*tests:[[:space:]]*)[^#]*|\1${TESTS_DIR} |" \
      -e "s|^([[:space:]]*githooks:[[:space:]]*)[^#]*|\1${GITHOOKS_DIR} |" \
      -e "s|^([[:space:]]*change_root:[[:space:]]*)[^#]*|\1${DOCS_DIR}/changes |" \
      -e "s|^([[:space:]]*bugs_root:[[:space:]]*)[^#]*|\1${DOCS_DIR}/bugs |" \
      "$1"
    return 0
  fi
  sed -e "s|scripts/install-hook-adapter|$SCRIPTS_DIR/install-hook-adapter|g" \
      -e "s|scripts/session-gate\.sh|$SCRIPTS_DIR/session-gate.sh|g" \
      -e "s|scripts/check-standards-compliance\.sh|$SCRIPTS_DIR/check-standards-compliance.sh|g" \
      -e "s|scripts/stamp-provenance\.sh|$SCRIPTS_DIR/stamp-provenance.sh|g" \
      -e "s|scripts/agent-gate|$SCRIPTS_DIR/agent-gate|g" \
      -e "s|tests/run-tests\.sh|$TESTS_DIR/run-tests.sh|g" \
      -e "s|tests/audit-docs-consistency\.sh|$TESTS_DIR/audit-docs-consistency.sh|g" \
      -e "s|\.githooks/|$GITHOOKS_DIR/|g" \
      -e "s|docs/|$DOCS_DIR/|g" \
      "$1"
}
same_as_src() { # src dest
  if [[ "$PATHS_CUSTOM" == 1 ]]; then cmp -s <(transform_src "$1") "$2"; else cmp -s "$1" "$2"; fi
}
copy_src() { # src dest
  if [[ "$PATHS_CUSTOM" == 1 ]]; then transform_src "$1" > "$2"; else cp "$1" "$2"; fi
}

# install_file <logical-key> <dest_rel> <src_rel> [chmod_mode]
# CHG-013 / D6 (v3.15.0): live/user-owned files are NEVER touched by --upgrade
# (they hold accumulated data: FU ledger, bug index, CFG records, user config).
# The skip list matches on the LOGICAL KEY, not on a literal path — otherwise
# configuring a non-default docs root would silently defeat every skip.
LIVE_SKIP=(
  "bugfix-log"
  "delivery-summary"
  "deployment-config"
  "agent-governance-yml"
)

# CHG-062 (v3.50.0): AGENTS.md 托管块合并——用户在 end 标记后追加的内容升级/重装时
# 原样保留（用户指令 2026-09-24："安装文件含用户信息不要替换，保留原有内容"）。
# 无标记的差异文件视为用户改动版：一律保留原文，--force 不越（删除文件重装=唯一
# 强制刷新通道）。通用文件的 CONFLICT/--force 语义不受影响（仅 agents-md 键）。
M_BEGIN='<!-- dev-standards:managed begin'
M_END='<!-- dev-standards:managed end'
merge_managed() { # src dest -> stdout merged; rc 2 = dest lacks markers
  # 行首锚定（index==1）：用户区中「含」标记子串的行不受影响，仅整行标记触发分段（评审 P3-1/P3-2）
  local src="$1" dest="$2"
  grep -qF "$M_BEGIN" "$dest" && grep -qF "$M_END" "$dest" || return 2
  { awk -v B="$M_BEGIN" 'index($0,B)==1{exit} {print}' "$dest"
    awk -v B="$M_BEGIN" -v E="$M_END" 'index($0,B)==1{f=1} f{print} f&&index($0,E)==1{exit}' "$src"
    awk -v E="$M_END" 'seen{print;next} index($0,E)==1{seen=1}' "$dest"
  }
}

# CHG-063 (v3.51.0): 安装清单（dpkg conffile 同构）——被安装文件自安装基线。
# 任意文件升级时核对：hash 匹配=纯版本漂移（正常升级）；不匹配=用户改过（保留，
# --force 显式越）；无条目（legacy 仓）=保守保留+提示 --force 一次同步采纳清单。
# 用户指令 2026-09-24：安装/升级含用户信息的文件一律不替换、保留原有内容。
manifest_path() { printf '%s/.dev-standards-manifest' "$target"; }
file_cksum() { cksum "$1" | awk '{print $1}'; }
manifest_get() { awk -v k="$1" '$2==k{print $1; exit}' "$(manifest_path)" 2>/dev/null; }
manifest_record() { # dest_rel dest — upsert（载荷写入成功后调用；manifest 自身不入账）
  local c; c=$(file_cksum "$2")
  [[ -f $(manifest_path) ]] || : > "$(manifest_path)"
  if ! awk -v k="$1" -v c="$c" 'BEGIN{d=0} $2==k{print c" "k; d=1; next} {print} END{if(!d)print c" "k}' \
    "$(manifest_path)" > "$(manifest_path).tmp" || ! mv "$(manifest_path).tmp" "$(manifest_path)"; then
    rm -f "$(manifest_path).tmp"
    echo "WARNING     manifest record failed for $1 (baseline entry may be stale — next upgrade will treat as user-modified)" >&2
    return 1
  fi
}
manifest_user_modified() { # dest_rel dest -> 0 = entry 存在且 hash 异（用户改过）
  local e f
  e=$(manifest_get "$1")
  [[ -n "$e" ]] || return 1
  f=$(file_cksum "$2")
  [[ "$e" != "$f" ]]
}

# D5 (v3.16.0): the standards upgrade log belongs to the SKILL, not the target.
# It ships with the spec and is replaced wholesale on --upgrade — so a target
# repo that appended its own rows would lose them silently. Detect that specific
# case and refuse (fail-closed) instead of overwriting or trying to merge:
# a merge would destroy the only answer to "who maintains this line?".
divergence_guard() { # src dest -> 0 when dest has version rows src lacks
  local src="$1" dest="$2" extra
  [[ -f "$dest" ]] || return 1
  extra=$(comm -23 \
    <(grep -oE '^\| v[0-9]+\.[0-9]+\.[0-9]+' "$dest" 2>/dev/null | sort -u) \
    <(grep -oE '^\| v[0-9]+\.[0-9]+\.[0-9]+' "$src"  2>/dev/null | sort -u) 2>/dev/null \
    | tr -d ' |' | tr '\n' ' ')
  [[ -n "$extra" ]] || return 1
  printf '%s' "$extra"
  return 0
}

install_file() {
  local key="$1" dest_rel="$2" src_rel="$3" chmod_mode="${4:-}"
  local dest="$target/$dest_rel" src="$SKILL_ROOT/$src_rel"
  [[ -f "$src" ]] || { echo "bootstrap: MISSING SOURCE $src_rel (skill repo broken) — partial install: installed=$installed" >&2; exit 2; }
  if [[ "$upgrade" == true && "$key" != "-" ]]; then
    for skip in "${LIVE_SKIP[@]}"; do
      if [[ "$key" == "$skip" ]]; then
        echo "live (skip)  $dest_rel"
        skipped=$(( skipped + 1 ))
        return 0
      fi
    done
  fi
  # CHG-062 (v3.50.0): agents-md = merge-or-keep，永不覆盖用户内容。
  # 有标记 → 只换托管区（区外保留）；无标记差异 → kept（--force 不越）。
  if [[ "$key" == "agents-md" && -f "$dest" ]] && ! same_as_src "$src" "$dest"; then
    local msrc="$dest.merged.tmp"
    if [[ "$PATHS_CUSTOM" == 1 ]]; then transform_src "$src" > "$msrc"; else cp "$src" "$msrc"; fi
    if merge_managed "$msrc" "$dest" > "$msrc.out" && [[ -s "$msrc.out" ]]; then
      mv "$msrc.out" "$dest" || { rm -f "$msrc" "$msrc.out"; echo "bootstrap: AGENTS.md merge write failed — kept original" >&2; skipped=$(( skipped + 1 )); return 0; }
      rm -f "$msrc"
      echo "merged       $dest_rel (managed block updated; user sections outside markers preserved)"
      upgraded=$(( upgraded + 1 ))
      manifest_record "$dest_rel" "$dest"
      return 0
    fi
    rm -f "$msrc" "$msrc.out"
    echo "kept (user-modified AGENTS.md without managed markers — content preserved; delete it and re-run to adopt markers)  $dest_rel"
    skipped=$(( skipped + 1 ))
    return 0
  fi
  # Self-evolution contract: never write into a directory that declares
  # derived_from. Walk the ancestors strictly BETWEEN the destination and the
  # target (the target itself is checked once, up front) so a derived skill
  # nested anywhere under the target is protected — and stop at the target,
  # because walking past it would stat every ancestor up to "/".
  local anc="$dest"
  while :; do
    anc=$(dirname "$anc")
    [[ -z "$anc" || "$anc" == "$target" || "$anc" == "/" || "$anc" == "." ]] && break
    if [[ -n "$(derived_of "$anc")" ]]; then
      echo "derived (skip)  $dest_rel (inside derived skill $anc)"
      skipped=$(( skipped + 1 ))
      return 0
    fi
  done
  # D5: refuse to clobber local rows appended to the skill-owned upgrade log.
  if [[ "$upgrade" == true && "$key" == "standards-changelog" ]]; then
    local extra
    if extra=$(divergence_guard "$src" "$dest"); then
      if [[ "$force" != true ]]; then
        echo "bootstrap: $dest_rel has local rows this skill does not carry: $extra" >&2
        echo "bootstrap: that file belongs to the skill (it ships with the spec) — move your rows to <docs>/changes/<CHG>/09-changelog.md, or pass --force to overwrite anyway" >&2
        echo "bootstrap: aborting — partial install: installed=$installed up-to-date=$skipped" >&2
        exit 2
      fi
      echo "WARNING     $dest_rel has local rows ($extra) — overwriting them because --force was given" >&2
    fi
  fi
  if [[ -e "$dest" ]]; then
    if same_as_src "$src" "$dest"; then
      echo "up to date   $dest_rel"
      skipped=$(( skipped + 1 ))
      manifest_record "$dest_rel" "$dest"
      return 0
    fi
    if [[ "$upgrade" == true ]]; then
      local eck
      eck=$(manifest_get "$dest_rel")
      if [[ -n "$eck" && "$eck" == "$(file_cksum "$dest")" ]]; then
        echo "updated      $dest_rel (upgrade; unchanged since install)"
        upgraded=$(( upgraded + 1 ))
        mkdir -p "$(dirname "$dest")"
        copy_src "$src" "$dest"
        [[ -n "$chmod_mode" ]] && chmod "$chmod_mode" "$dest"
        manifest_record "$dest_rel" "$dest"
        return 0
      fi
      if [[ "$force" == true ]]; then
        echo "overwrite    $dest_rel (user-modified since install — --force given; previous content in git history)"
        overwritten=$(( overwritten + 1 ))
        mkdir -p "$(dirname "$dest")"
        copy_src "$src" "$dest"
        [[ -n "$chmod_mode" ]] && chmod "$chmod_mode" "$dest"
        manifest_record "$dest_rel" "$dest"
        return 0
      fi
      if [[ -n "$eck" ]]; then
        echo "kept (user-modified since install — preserved; --force overwrites, or merge manually)  $dest_rel"
      else
        echo "kept (no install manifest entry — legacy target preserved; run --force once to sync and adopt manifest)  $dest_rel"
      fi
      skipped=$(( skipped + 1 ))
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
  copy_src "$src" "$dest"
  [[ -n "$chmod_mode" ]] && chmod "$chmod_mode" "$dest"
  manifest_record "$dest_rel" "$dest"
}

installed=0
overwritten=0
skipped=0
upgraded=0

run_layer() {
  local layer="$1"
  case "$layer" in
    core)
      install_file agents-md AGENTS.md resources/AGENTS.md
      install_file - "$DOCS_DIR/DEVELOPMENT_STANDARDS.md" resources/DEVELOPMENT_STANDARDS.md
      # v3.46.0（REQ-968/969）：条款注册表 → 阅读包生成的结构化索引层（机器面权威，
      # DS 仍是叙事唯一权威；生成 fail-closed 防双权威源漂移）。
      install_file - "$DOCS_DIR/CLAUSE_REGISTRY.md" resources/CLAUSE_REGISTRY.md
      # v3.37.0（REQ-937）：一页文档地图 → <docs>/README.md（与 AGENTS.md 互补的人面地图；
      # 已存在同名文件且内容不同时 CONFLICT 拒绝，fail-closed 不静默覆盖）。
      install_file - "$DOCS_DIR/README.md" resources/templates/docs-readme.md
      install_file standards-changelog "$DOCS_DIR/STANDARDS_CHANGELOG.md" resources/STANDARDS_CHANGELOG.md
      install_file - "$DOCS_DIR/METHODOLOGY.md" resources/METHODOLOGY.md
      for m in development.md data-structures.md state-trigger-audit.md expert-capabilities.md project-masters.md; do
        install_file - "$DOCS_DIR/methodologies/$m" "resources/methodologies/$m"
      done
      # v3.35.0（§1.3）：项目级总册 12 册 + 评审记录模板骨架 → <docs>/templates/project/，
      # 首次变更时由用户复制到 <docs>/project/ 并回填现状（begin 机校 12 册在位）。
      mkdir -p "$DOCS_DIR/templates/project/reviews"
      for p in P00-project-charter.md P01-requirements-master.md P02-architecture-master.md P03-interface-registry.md P04-data-dictionary.md P05-task-plan.md P06-test-master.md P07-test-verdicts.md P08-deployment-master.md P09-risk-register.md P10-change-ledger.md P11-decision-log.md reviews/_template.review.md; do
        install_file - "$DOCS_DIR/templates/project/$p" "resources/templates/project/$p"
      done
      install_file bugfix-log "$DOCS_DIR/bugfix-log.md" resources/templates/bugfix-log.md
      for b in bug-diagnosis.md bug-impact.md bug-test-plan.md bug-matrix.md bug-config.md bug-tasks.md; do
        install_file - "$DOCS_DIR/bugs/_templates/$b" "resources/templates/$b"
      done
      # v3.38.0（CHG-038）：变更管线入口骨架（begin 必检模板）+ 脚手架脚本。
      # v3.52.0（CHG-064）：八件——00.5-communication.md 为沟通先行门产物（§2.17.2d）；
      # 正式沟通稿模板随 --core 下发（uninstall Tier2 按 __CHANGE_ID__ 标记识别）。
      mkdir -p "$DOCS_DIR/templates/entry"
      for e in 00-intent.md 00-governance.json 00.5-communication.md 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md; do
        install_file - "$DOCS_DIR/templates/entry/$e" "resources/templates/entry/$e"
      done
      install_file - "$DOCS_DIR/templates/communication.md" resources/templates/communication.md
      # 八类最低文档集（规范 §1.1）中此前既无模板、也无门禁的两类（CHG-004 / BUG-002）：
      # 未命中时也必须存在并显式声明"未命中，不适用"——不能靠"不建文件"来表达不适用。
      install_file deployment-config "$DOCS_DIR/06.5-deployment-config.md" resources/templates/06.5-deployment-config.md
      install_file delivery-summary  "$DOCS_DIR/06-delivery-summary.md"     resources/templates/06-delivery-summary.md
      install_file - "$TESTS_DIR/audit-docs-consistency.sh" resources/templates/audit-docs-consistency.sh 755
      ;;
    claude)
      install_file - CLAUDE.md resources/templates/CLAUDE.md
      ;;
    ci)
      install_file - ".github/PULL_REQUEST_TEMPLATE.md" resources/templates/PULL_REQUEST_TEMPLATE.md
      install_file - "$SCRIPTS_DIR/check-standards-compliance.sh" resources/templates/check-standards-compliance.sh 755
      ;;
    guard)
      install_file - "$SCRIPTS_DIR/agent-gate" resources/templates/agent-gate.sh 755
      install_file - "$SCRIPTS_DIR/stamp-provenance.sh" resources/templates/stamp-provenance.sh 755
      install_file - "$SCRIPTS_DIR/new-change" resources/templates/new-change.sh 755
      install_file - "$GITHOOKS_DIR/pre-commit" resources/templates/pre-commit 755
      install_file - "$GITHOOKS_DIR/pre-push" resources/templates/pre-push 755
      install_file - "$GITHOOKS_DIR/commit-msg" resources/templates/commit-msg 755
      install_file - ".github/workflows/agent-governance.yml" resources/templates/github-agent-governance.yml
      install_file - "$SCRIPTS_DIR/install-hook-adapter" resources/templates/install-hook-adapter.sh 755
      install_file - "$SCRIPTS_DIR/session-gate.sh" resources/templates/session-gate.sh 755
      install_file - "$SCRIPTS_DIR/bug-autointent" resources/templates/bug-autointent.sh 755
      install_file - "$SCRIPTS_DIR/generate-reading-pack.sh" resources/templates/generate-reading-pack.sh 755
      install_file - "$SCRIPTS_DIR/uninstall-standards" resources/templates/uninstall-standards.sh 755
      install_file agent-governance-yml .agent-governance.yml resources/templates/agent-governance.yml
      # 治理自测试随强制包（打包错位修复）：改 agent-gate/hooks 前必须能跑 golden cases
      install_file - "$TESTS_DIR/run-tests.sh" tests/run-tests.sh 755
      ;;
    pipeline)
      install_file - ".github/workflows/artifact-pipeline.yml" resources/templates/github-artifact-pipeline.yml
      install_file - ".github/workflows/incident-to-intent.yml" resources/templates/github-incident-to-intent.yml
      install_file - ".github/workflows/regression-to-bug.yml" resources/templates/github-regression-to-bug.yml
      ;;
  esac
}

echo "bootstrap: applying layers [$(echo $layers | tr ' ' ',')] -> $target"
echo "bootstrap: roots docs=$DOCS_DIR scripts=$SCRIPTS_DIR tests=$TESTS_DIR githooks=$GITHOOKS_DIR" 
if [[ "$upgrade" == true ]]; then
  carried=$(grep -oE '规范版本：v[0-9.]+' "$SKILL_ROOT/resources/DEVELOPMENT_STANDARDS.md" 2>/dev/null | head -1 | grep -oE '[0-9.]+')
  installed_ver=$(grep -oE '规范版本：v[0-9.]+' "$target/$DOCS_DIR/DEVELOPMENT_STANDARDS.md" 2>/dev/null | head -1 | grep -oE '[0-9.]+' || true)
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

# --- persist non-default roots into the installed config (v3.15.0) ----------
# The gates read .agent-governance.yml. If the installer wrote to non-default
# roots and left the config at its defaults, the gates would look in docs/ while
# the files sit in doc/ — a silent split. So: rewrite only the keys whose value
# actually differs, and materialise the config if a non-default root was asked
# for but no layer shipped it.
rewrite_yml_key() { # file key value
  local f="$1" k="$2" v="$3" cur tmpf
  [[ -f "$f" ]] || return 0
  cur=$(yml_key_value "$f" "$k")
  [[ -n "$cur" && "$cur" != "$v" ]] || return 0
  tmpf=$(mktemp 2>/dev/null) || return 0
  # cat (not mv) keeps the target inode's permissions/ownership
  if sed -E "s|^([[:space:]]*${k}:[[:space:]]*)[^#]*|\1${v} |" "$f" > "$tmpf" 2>/dev/null; then
    cat "$tmpf" > "$f"
    echo "auto-wired   $k = $v (in .agent-governance.yml)"
  fi
  rm -f "$tmpf"
  return 0
}

# Read one flat key's current value out of the installed config (same parse as
# rewrite_yml_key — kept in ONE place so the guard below cannot drift from the
# writer it guards).
yml_key_value() { # file key
  local f="$1" k="$2"
  [[ -f "$f" ]] || return 0
  sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" "$f" 2>/dev/null \
    | head -n 1 | tr -d "[:space:]\"'" || true
  return 0
}

apply_path_overrides() {
  if [[ "$PATHS_CUSTOM" != 1 ]]; then
    return 0
  fi
  if [[ ! -f "$GOV_YML" ]]; then
    mkdir -p "$(dirname "$GOV_YML")"
    cp "$SKILL_ROOT/resources/templates/agent-governance.yml" "$GOV_YML"
    echo "installed    .agent-governance.yml (required to pin non-default path roots)"
  fi
  rewrite_yml_key "$GOV_YML" docs     "$DOCS_DIR"
  rewrite_yml_key "$GOV_YML" scripts  "$SCRIPTS_DIR"
  rewrite_yml_key "$GOV_YML" tests    "$TESTS_DIR"
  rewrite_yml_key "$GOV_YML" githooks "$GITHOOKS_DIR"
  # change_root / bugs_root derive from the docs root, in three states
  # (CHG-017: v3.21.1 ⑫ — first guard; v3.21.2 ⑤ — three-state form):
  #   ① still the built-in default (`docs/changes` / `docs/bugs`) → derive;
  #   ② ALREADY the value this docs root derives (`<docs>/changes` / `<docs>/bugs`)
  #      → nothing to do and NOT a pin: the template copy already carries the
  #      derived value because `transform_src` rewrote it at install time, so
  #      saying "an explicit pin wins" here would be a false statement (v3.21.2 —
  #      a fresh `--all --docs-dir doc` install used to print that NOTE);
  #   ③ anything else → a deliberate pin (`specs/changes`): leave it and say so.
  if [[ "$DOCS_DIR" != "docs" ]]; then
    for pair in "change_root:changes" "bugs_root:bugs"; do
      key="${pair%%:*}"; sub="${pair#*:}"
      cur=$(yml_key_value "$GOV_YML" "$key")
      derived="$DOCS_DIR/$sub"
      if [[ "$cur" == "$derived" ]]; then
        continue
      elif [[ "$cur" == "docs/$sub" ]]; then
        rewrite_yml_key "$GOV_YML" "$key" "$derived"
      else
        echo "NOTE         $key is not the built-in default — left untouched (an explicit pin wins over --docs-dir derivation)" >&2
      fi
    done
  fi
  return 0
}
apply_path_overrides

# CHG-012: guard auto-wiring — after install, wire everything that can be
# wired without asking. Respect existing user config; never overwrite.
auto_wire_guard() {
  # 1) hooksPath: three states — unset -> set; already <githooks> -> skip;
  #    something else -> DO NOT touch, print manual hint (OQ-1).
  if [[ -d "$target/.git" ]] && command -v git >/dev/null 2>&1; then
    cur=$(git -C "$target" config --get core.hooksPath || true)
    if [[ -z "$cur" ]]; then
      git -C "$target" config core.hooksPath "$GITHOOKS_DIR"
      echo "auto-wired   git config core.hooksPath $GITHOOKS_DIR"
    elif [[ "$cur" == "$GITHOOKS_DIR" ]]; then
      echo "auto-wired   core.hooksPath already $GITHOOKS_DIR (skipped)"
    else
      echo "NOTE         core.hooksPath is '$cur' (custom) — left untouched; wire $GITHOOKS_DIR manually if intended" >&2
    fi
  fi
  # 2) client hook adapter: only run when a supported client is detected in
  #    THIS shell's env (the adapter itself exits 0 even without a client, so
  #    its exit code alone would false-positive — check the env here first).
  if [[ -f "$target/$SCRIPTS_DIR/install-hook-adapter" ]]; then
    ok=0
    if (cd "$target" && bash "$SCRIPTS_DIR/install-hook-adapter" >/dev/null 2>&1); then
      for f in .claude/settings.json .cursor/hooks.json .gemini/settings.json \
               .opencode/plugins/dev-standards-gate.js; do
        [[ -f "$target/$f" ]] && ok=1
      done
    fi
    if [[ "$ok" == 1 ]]; then
      echo "auto-wired   client session-enforcement wired (install-hook-adapter detected the local clients)"
    else
      echo "NOTE         no supported coding client detected — Git hooks + CI still enforce; run $SCRIPTS_DIR/install-hook-adapter inside your client later" >&2
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
          && cat "$tmpf.2" > "$yml" \
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
  roots: docs=$DOCS_DIR scripts=$SCRIPTS_DIR tests=$TESTS_DIR githooks=$GITHOOKS_DIR
Next (per SKILL.md):
  - 变更起编时从模板生成 00-intent.md / 00-governance.json / 04.5-coding-record.md
  - --guard 已自动接线 hooksPath / 客户端适配器 / 验证命令探测（见上方 auto-wired 行）
  - 剩余手工仅平台侧：在托管平台将 agent-governance 与项目测试设为 Required Check
EOF
exit 0
